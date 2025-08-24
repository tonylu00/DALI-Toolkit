package websocket

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

const (
	// Time allowed to write a message to the peer
	writeWait = 10 * time.Second

	// Time allowed to read the next pong message from the peer
	pongWait = 60 * time.Second

	// Send pings to peer with this period. Must be less than pongWait
	pingPeriod = (pongWait * 9) / 10

	// Maximum message size allowed from peer
	maxMessageSize = 512 * 1024 // 512KB

	// Maximum time a connection can be idle before being considered stale
	maxIdleTime = 5 * time.Minute
)

// Connection represents a WebSocket connection
type Connection struct {
	// The websocket connection
	conn *websocket.Conn

	// Connection metadata
	ID       string
	UserID   string
	DeviceID string
	DeviceBy string // "imei" or "mac"

	// Buffered channel of outbound messages
	send chan []byte

	// Hub reference for unregistering
	hub *Hub

	// MQTT broker reference for publishing
	mqttBroker MQTTBrokerInterface

	// Context for cancellation
	ctx    context.Context
	cancel context.CancelFunc

	// Last activity time for stale connection detection
	lastActivity time.Time
	mu           sync.RWMutex

	// Logger
	logger *zap.Logger
}

// MQTTBrokerInterface interface for MQTT operations
type MQTTBrokerInterface interface {
	PublishToDevice(deviceID, deviceBy string, payload []byte) error
	SubscribeToDevice(deviceID, deviceBy string, handler func(topic string, payload []byte)) error
	Kick(deviceID string) error
}

// Message represents a WebSocket message
type Message struct {
	Type      string      `json:"type"`
	DeviceID  string      `json:"device_id,omitempty"`
	Data      interface{} `json:"data,omitempty"`
	Timestamp time.Time   `json:"timestamp"`
}

// ErrorMessage represents an error message
type ErrorMessage struct {
	Error   string `json:"error"`
	Code    string `json:"code,omitempty"`
	Details string `json:"details,omitempty"`
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		// Allow connections from any origin in development
		// In production, this should be more restrictive
		return true
	},
}

// NewConnection creates a new WebSocket connection
func NewConnection(conn *websocket.Conn, userID, deviceID, deviceBy string, hub *Hub, mqttBroker MQTTBrokerInterface, logger *zap.Logger) *Connection {
	ctx, cancel := context.WithCancel(context.Background())

	return &Connection{
		conn:         conn,
		ID:           uuid.New().String(),
		UserID:       userID,
		DeviceID:     deviceID,
		DeviceBy:     deviceBy,
		send:         make(chan []byte, 256),
		hub:          hub,
		mqttBroker:   mqttBroker,
		ctx:          ctx,
		cancel:       cancel,
		lastActivity: time.Now(),
		logger:       logger.With(zap.String("component", "websocket_connection")),
	}
}

// Run starts the connection's read and write pumps
func (c *Connection) Run() {
	go c.writePump()
	go c.readPump()
}

// Close closes the connection
func (c *Connection) Close() {
	c.cancel()
	close(c.send)
	c.conn.Close()
}

// Send sends a message to the connection
func (c *Connection) Send(messageType string, data interface{}) error {
	msg := Message{
		Type:      messageType,
		DeviceID:  c.DeviceID,
		Data:      data,
		Timestamp: time.Now(),
	}

	jsonData, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	select {
	case c.send <- jsonData:
		return nil
	default:
		c.logger.Warn("Connection send buffer full, dropping message",
			zap.String("connection_id", c.ID))
		return ErrConnectionClosed
	}
}

// SendError sends an error message to the connection
func (c *Connection) SendError(errorMsg, code, details string) error {
	errData := ErrorMessage{
		Error:   errorMsg,
		Code:    code,
		Details: details,
	}
	return c.Send("error", errData)
}

// IsStale checks if the connection is stale
func (c *Connection) IsStale(now time.Time) bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return now.Sub(c.lastActivity) > maxIdleTime
}

// updateActivity updates the last activity time
func (c *Connection) updateActivity() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.lastActivity = time.Now()
}

// readPump pumps messages from the websocket connection to the hub
func (c *Connection) readPump() {
	defer func() {
		c.hub.Unregister(c)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		c.updateActivity()
		return nil
	})

	for {
		select {
		case <-c.ctx.Done():
			return
		default:
		}

		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				c.logger.Error("WebSocket read error", zap.Error(err))
			}
			break
		}

		c.updateActivity()

		// Handle incoming message from client
		c.handleMessage(message)
	}
}

// writePump pumps messages from the hub to the websocket connection
func (c *Connection) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// The hub closed the channel
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				c.logger.Error("WebSocket write error", zap.Error(err))
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}

		case <-c.ctx.Done():
			return
		}
	}
}

// handleMessage processes incoming messages from the client
func (c *Connection) handleMessage(data []byte) {
	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil {
		c.logger.Warn("Invalid message format", zap.Error(err), zap.ByteString("data", data))
		c.SendError("Invalid message format", "INVALID_FORMAT", err.Error())
		return
	}

	c.logger.Debug("Received message",
		zap.String("type", msg.Type),
		zap.String("device_id", msg.DeviceID))

	switch msg.Type {
	case "device_command":
		c.handleDeviceCommand(msg)
	case "ping":
		c.handlePing()
	default:
		c.logger.Warn("Unknown message type", zap.String("type", msg.Type))
		c.SendError("Unknown message type", "UNKNOWN_TYPE", msg.Type)
	}
}

// handleDeviceCommand processes device command messages
func (c *Connection) handleDeviceCommand(msg Message) {
	// Validate device ID matches connection
	if msg.DeviceID != c.DeviceID {
		c.SendError("Device ID mismatch", "DEVICE_MISMATCH", "Message device ID does not match connection device ID")
		return
	}

	// Convert message data to bytes for MQTT
	var payload []byte
	var err error

	if data, ok := msg.Data.(string); ok {
		payload = []byte(data)
	} else {
		payload, err = json.Marshal(msg.Data)
		if err != nil {
			c.SendError("Invalid message data", "INVALID_DATA", err.Error())
			return
		}
	}

	// Forward command to MQTT broker
	if c.mqttBroker != nil {
		if err := c.mqttBroker.PublishToDevice(c.DeviceID, c.DeviceBy, payload); err != nil {
			c.logger.Error("Failed to publish to MQTT",
				zap.String("device_id", c.DeviceID),
				zap.Error(err))
			c.SendError("Failed to send command to device", "MQTT_ERROR", err.Error())
			return
		}
	}

	c.logger.Info("Device command forwarded to MQTT",
		zap.String("device_id", msg.DeviceID),
		zap.Int("payload_size", len(payload)))

	// Send acknowledgment
	c.Send("command_ack", map[string]interface{}{
		"status":    "forwarded",
		"timestamp": time.Now(),
	})
}

// HandleMQTTMessage handles incoming MQTT messages for this device
func (c *Connection) HandleMQTTMessage(topic string, payload []byte) {
	// Determine message type based on topic suffix
	var messageType string
	if strings.HasSuffix(topic, "/up") {
		messageType = "device_data"
	} else if strings.HasSuffix(topic, "/status") {
		messageType = "device_status"
	} else if strings.HasSuffix(topic, "/register") {
		messageType = "device_register"
	} else {
		messageType = "device_message"
	}

	// Try to parse payload as JSON, fallback to string
	var data interface{}
	if err := json.Unmarshal(payload, &data); err != nil {
		data = string(payload)
	}

	// Send to WebSocket client
	if err := c.Send(messageType, data); err != nil {
		c.logger.Error("Failed to send MQTT message to WebSocket client",
			zap.String("topic", topic),
			zap.Error(err))
	} else {
		c.logger.Debug("MQTT message forwarded to WebSocket",
			zap.String("topic", topic),
			zap.String("message_type", messageType),
			zap.Int("payload_size", len(payload)))
	}
}

// handlePing processes ping messages
func (c *Connection) handlePing() {
	c.Send("pong", map[string]interface{}{
		"timestamp": time.Now(),
	})
}
