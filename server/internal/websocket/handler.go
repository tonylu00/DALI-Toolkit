package websocket

import (
	"errors"
	"net/http"

	"server/internal/auth"
	"server/internal/casbinx"
	"server/internal/domain/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// WebSocket errors
var (
	ErrTooManyConnections = errors.New("too many connections for user")
	ErrConnectionClosed   = errors.New("connection closed")
	ErrDeviceNotFound     = errors.New("device not found")
	ErrAccessDenied       = errors.New("access denied to device")
	ErrInvalidDeviceID    = errors.New("invalid device ID")
	ErrMissingParameters  = errors.New("missing required parameters")
)

// Handler handles WebSocket connections
type Handler struct {
	hub           *Hub
	deviceService *services.DeviceService
	enforcer      *casbinx.Enforcer
	mqttBroker    MQTTBrokerInterface
	logger        *zap.Logger
}

// NewHandler creates a new WebSocket handler
func NewHandler(hub *Hub, deviceService *services.DeviceService, enforcer *casbinx.Enforcer, mqttBroker MQTTBrokerInterface, logger *zap.Logger) *Handler {
	return &Handler{
		hub:           hub,
		deviceService: deviceService,
		enforcer:      enforcer,
		mqttBroker:    mqttBroker,
		logger:        logger.With(zap.String("component", "websocket_handler")),
	}
}

// HandleWebSocket handles WebSocket upgrade requests
func (h *Handler) HandleWebSocket(c *gin.Context) {
	// Get user context from auth middleware
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	// Get device parameters
	deviceID := c.Query("deviceId")
	deviceBy := c.Query("by") // "imei" or "mac"

	if deviceID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "deviceId parameter required"})
		return
	}

	if deviceBy == "" {
		deviceBy = "mac" // Default to MAC
	}

	if deviceBy != "imei" && deviceBy != "mac" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "by parameter must be 'imei' or 'mac'"})
		return
	}

	// Normalize device ID
	normalizedDeviceID, err := h.normalizeDeviceID(deviceID, deviceBy)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid device ID format", "details": err.Error()})
		return
	}

	// Check if device exists and user has access
	device, err := h.deviceService.GetDeviceByID(normalizedDeviceID, deviceBy)
	if err != nil {
		if err == services.ErrDeviceNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to verify device", "details": err.Error()})
		}
		return
	}

	// Check permissions - user must have read access to the device
	domain := h.getDeviceDomain(&device.ProjectID, device.PartitionID)
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "devices", "read")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to device"})
		return
	}

	// Upgrade to WebSocket
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		h.logger.Error("WebSocket upgrade failed", zap.Error(err))
		return
	}

	// Create new connection
	wsConn := NewConnection(conn, user.UserID, normalizedDeviceID, deviceBy, h.hub, h.mqttBroker, h.logger)

	// Register connection with hub
	if err := h.hub.Register(wsConn); err != nil {
		h.logger.Error("Failed to register WebSocket connection", zap.Error(err))
		_ = wsConn.SendError("Connection registration failed", "REGISTRATION_FAILED", err.Error())
		wsConn.Close()
		return
	}

	// Subscribe to MQTT topics for this device
	if h.mqttBroker != nil {
		if err := h.mqttBroker.SubscribeToDevice(normalizedDeviceID, deviceBy, wsConn.HandleMQTTMessage); err != nil {
			h.logger.Error("Failed to subscribe to MQTT topics", zap.Error(err))
			// Don't fail the connection, just log the error
		}
	}

	// Send welcome message
	_ = wsConn.Send("connected", map[string]interface{}{
		"device_id":     normalizedDeviceID,
		"device_by":     deviceBy,
		"connection_id": wsConn.ID,
		"message":       "WebSocket connection established",
	})

	// Start connection pumps
	wsConn.Run()

	h.logger.Info("WebSocket connection established",
		zap.String("user_id", user.UserID),
		zap.String("device_id", normalizedDeviceID),
		zap.String("device_by", deviceBy),
		zap.String("connection_id", wsConn.ID))
}

// HandleStats returns WebSocket hub statistics
func (h *Handler) HandleStats(c *gin.Context) {
	stats := h.hub.GetStats()
	c.JSON(http.StatusOK, stats)
}

// normalizeDeviceID normalizes device ID based on type
func (h *Handler) normalizeDeviceID(deviceID, deviceBy string) (string, error) {
	switch deviceBy {
	case "mac":
		return services.NormalizeMAC(deviceID)
	case "imei":
		return services.NormalizeIMEI(deviceID)
	default:
		return "", ErrInvalidDeviceID
	}
}

// getDeviceDomain constructs the domain string for device permissions
func (h *Handler) getDeviceDomain(projectID, partitionID *uuid.UUID) string {
	if partitionID != nil {
		return "partition:" + partitionID.String()
	}
	if projectID != nil {
		return "project:" + projectID.String()
	}
	return "org" // Fallback to organization level
}
