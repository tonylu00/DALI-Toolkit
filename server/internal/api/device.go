package api

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/auth"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casbinx"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"github.com/tonylu00/DALI-Toolkit/server/pkg/errors"
	"go.uber.org/zap"
)

// DeviceHandler handles device-related API endpoints
type DeviceHandler struct {
	deviceService       *services.DeviceService
	organizationService *services.OrganizationService
	enforcer            *casbinx.Enforcer
	logger              *zap.Logger
}

// NewDeviceHandler creates a new device handler
func NewDeviceHandler(deviceService *services.DeviceService, organizationService *services.OrganizationService, enforcer *casbinx.Enforcer, logger *zap.Logger) *DeviceHandler {
	return &DeviceHandler{
		deviceService:       deviceService,
		organizationService: organizationService,
		enforcer:            enforcer,
		logger:              logger.With(zap.String("component", "device_handler")),
	}
}

// ListDevices lists devices with filtering
func (h *DeviceHandler) ListDevices(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	// Parse query parameters
	orgID := c.Query("org_id")
	projectID := c.Query("project_id")
	partitionID := c.Query("partition_id")
	status := c.Query("status")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	// Validate pagination
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	// Use user's organization if not specified
	if orgID == "" {
		orgID = user.OrgID.String()
	}

	// Check if user can access the specified organization
	if !user.IsSuperUser && orgID != user.OrgID.String() {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to organization"})
		return
	}

	orgUUID, err := uuid.Parse(orgID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid org_id"})
		return
	}

	// Build filters
	filters := make(map[string]interface{})
	if status != "" {
		filters["status"] = status
	}
	if projectID != "" {
		if projUUID, err := uuid.Parse(projectID); err == nil {
			filters["project_id"] = projUUID
		}
	}
	if partitionID != "" {
		if partUUID, err := uuid.Parse(partitionID); err == nil {
			filters["partition_id"] = partUUID
		}
	}

	// List devices
	devices, err := h.deviceService.ListDevicesByOrganization(orgUUID, filters)
	if err != nil {
		h.logger.Error("Failed to list devices", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list devices"})
		return
	}

	// Apply pagination
	start := (page - 1) * pageSize
	end := start + pageSize
	if start >= len(devices) {
		devices = []models.Device{}
	} else {
		if end > len(devices) {
			end = len(devices)
		}
		devices = devices[start:end]
	}

	c.JSON(http.StatusOK, gin.H{
		"devices": devices,
		"pagination": gin.H{
			"page":      page,
			"page_size": pageSize,
			"total":     len(devices),
		},
	})
}

// GetDevice gets a device by ID
func (h *DeviceHandler) GetDevice(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	deviceID := c.Param("id")
	deviceBy := c.DefaultQuery("by", "mac")

	if deviceBy != "mac" && deviceBy != "imei" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "by parameter must be 'mac' or 'imei'"})
		return
	}

	device, err := h.deviceService.GetDeviceByIdentifier(deviceID, deviceBy)
	if err != nil {
		if err == services.ErrDeviceNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		} else {
			h.logger.Error("Failed to get device", zap.Error(err))
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get device"})
		}
		return
	}

	// Check permissions
	domain := h.buildDeviceDomain(device)
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

	c.JSON(http.StatusOK, device)
}

// CreateDevice creates a new device (bind)
func (h *DeviceHandler) CreateDevice(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	var req struct {
		MAC         string            `json:"mac,omitempty"`
		IMEI        string            `json:"imei,omitempty"`
		DeviceType  models.DeviceType `json:"device_type" binding:"required"`
		ProjectID   uuid.UUID         `json:"project_id" binding:"required"`
		PartitionID *uuid.UUID        `json:"partition_id,omitempty"`
		DisplayName string            `json:"display_name" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate that at least one identifier is provided
	if req.MAC == "" && req.IMEI == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Either MAC or IMEI must be provided"})
		return
	}

	// Check permissions for the project
	domain := "project:" + req.ProjectID.String()
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "devices", "write")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to project"})
		return
	}

	// Use MAC as primary identifier, fallback to IMEI
	primaryID := req.MAC
	if primaryID == "" {
		primaryID = req.IMEI
	}

	var imeiPtr *string
	if req.IMEI != "" {
		imeiPtr = &req.IMEI
	}

	device, err := h.deviceService.CreateDevice(primaryID, imeiPtr, req.DeviceType, req.ProjectID, req.PartitionID, req.DisplayName)
	if err != nil {
		if appErr, ok := err.(*errors.AppError); ok {
			c.JSON(appErr.HTTPStatus, gin.H{"error": appErr.Message, "details": appErr.Details})
		} else {
			h.logger.Error("Failed to create device", zap.Error(err))
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create device"})
		}
		return
	}

	h.logger.Info("Device created",
		zap.String("device_id", device.ID.String()),
		zap.String("user_id", user.UserID),
		zap.String("mac", device.MAC))

	c.JSON(http.StatusCreated, device)
}

// UpdateDevice updates device information
func (h *DeviceHandler) UpdateDevice(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	deviceID := c.Param("id")
	deviceBy := c.DefaultQuery("by", "mac")

	if deviceBy != "mac" && deviceBy != "imei" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "by parameter must be 'mac' or 'imei'"})
		return
	}

	var req struct {
		DisplayName string                 `json:"display_name,omitempty"`
		Tags        []string               `json:"tags,omitempty"`
		Meta        map[string]interface{} `json:"meta,omitempty"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	device, err := h.deviceService.GetDeviceByIdentifier(deviceID, deviceBy)
	if err != nil {
		if err == services.ErrDeviceNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		} else {
			h.logger.Error("Failed to get device", zap.Error(err))
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get device"})
		}
		return
	}

	// Check permissions
	domain := h.buildDeviceDomain(device)
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "devices", "write")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to device"})
		return
	}

	// Update fields
	if req.DisplayName != "" {
		device.DisplayName = req.DisplayName
	}
	// TODO: Add support for tags and meta fields when they are added to the model

	if err := h.deviceService.UpdateDevice(device); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update device"})
		return
	}
	c.JSON(http.StatusOK, device)
}

// DeleteDevice deletes/unbinds a device
func (h *DeviceHandler) DeleteDevice(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	deviceID := c.Param("id")
	deviceBy := c.DefaultQuery("by", "mac")

	if deviceBy != "mac" && deviceBy != "imei" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "by parameter must be 'mac' or 'imei'"})
		return
	}

	device, err := h.deviceService.GetDeviceByIdentifier(deviceID, deviceBy)
	if err != nil {
		if err == services.ErrDeviceNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Device not found"})
		} else {
			h.logger.Error("Failed to get device", zap.Error(err))
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get device"})
		}
		return
	}

	// Check permissions
	domain := h.buildDeviceDomain(device)
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "devices", "manage")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to device"})
		return
	}

	// TODO: Implement device deletion in service
	// For now, just return success
	h.logger.Info("Device deletion requested",
		zap.String("device_id", device.ID.String()),
		zap.String("user_id", user.UserID))

	c.JSON(http.StatusOK, gin.H{"message": "Device deletion requested (to be implemented)"})
}

// buildDeviceDomain constructs the permission domain for a device
func (h *DeviceHandler) buildDeviceDomain(device *models.Device) string {
	if device.PartitionID != nil {
		return "partition:" + device.PartitionID.String()
	}
	return "project:" + device.ProjectID.String()
}
