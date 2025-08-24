package websocket

import (
	"context"
	"sync"
	"time"

	"go.uber.org/zap"
)

// Hub manages all WebSocket connections and their lifecycle
type Hub struct {
	// Connections by user ID
	connections map[string]map[string]*Connection // userID -> connectionID -> connection
	mu          sync.RWMutex

	// Configuration
	maxConnPerUser int
	logger         *zap.Logger

	// Channels for hub operations
	register   chan *Connection
	unregister chan *Connection
	stop       chan struct{}
}

// NewHub creates a new WebSocket hub
func NewHub(maxConnPerUser int, logger *zap.Logger) *Hub {
	return &Hub{
		connections:    make(map[string]map[string]*Connection),
		maxConnPerUser: maxConnPerUser,
		logger:         logger,
		register:       make(chan *Connection, 256),
		unregister:     make(chan *Connection, 256),
		stop:           make(chan struct{}),
	}
}

// Run starts the hub's main loop
func (h *Hub) Run(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case conn := <-h.register:
			h.handleRegister(conn)

		case conn := <-h.unregister:
			h.handleUnregister(conn)

		case <-ticker.C:
			h.cleanup()

		case <-ctx.Done():
			h.shutdown()
			return

		case <-h.stop:
			h.shutdown()
			return
		}
	}
}

// Register registers a new connection
func (h *Hub) Register(conn *Connection) error {
	h.mu.Lock()
	defer h.mu.Unlock()

	userID := conn.UserID
	connID := conn.ID

	// Check connection limit per user
	if userConns, exists := h.connections[userID]; exists {
		if len(userConns) >= h.maxConnPerUser {
			h.logger.Warn("User connection limit exceeded",
				zap.String("user_id", userID),
				zap.Int("current_connections", len(userConns)),
				zap.Int("max_connections", h.maxConnPerUser))
			return ErrTooManyConnections
		}
	} else {
		h.connections[userID] = make(map[string]*Connection)
	}

	h.connections[userID][connID] = conn
	h.logger.Info("WebSocket connection registered",
		zap.String("user_id", userID),
		zap.String("connection_id", connID),
		zap.String("device_id", conn.DeviceID))

	// Send to register channel for async processing
	select {
	case h.register <- conn:
	default:
		h.logger.Warn("Register channel full, processing synchronously")
		h.handleRegister(conn)
	}

	return nil
}

// Unregister removes a connection
func (h *Hub) Unregister(conn *Connection) {
	h.mu.Lock()
	defer h.mu.Unlock()

	userID := conn.UserID
	connID := conn.ID

	if userConns, exists := h.connections[userID]; exists {
		if _, exists := userConns[connID]; exists {
			delete(userConns, connID)
			h.logger.Info("WebSocket connection unregistered",
				zap.String("user_id", userID),
				zap.String("connection_id", connID))

			// Clean up empty user connections map
			if len(userConns) == 0 {
				delete(h.connections, userID)
			}

			// Send to unregister channel for async processing
			select {
			case h.unregister <- conn:
			default:
				h.logger.Warn("Unregister channel full, processing synchronously")
				h.handleUnregister(conn)
			}
		}
	}
}

// GetConnection retrieves a connection by user and connection ID
func (h *Hub) GetConnection(userID, connID string) (*Connection, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if userConns, exists := h.connections[userID]; exists {
		if conn, exists := userConns[connID]; exists {
			return conn, true
		}
	}
	return nil, false
}

// GetUserConnections returns all connections for a user
func (h *Hub) GetUserConnections(userID string) []*Connection {
	h.mu.RLock()
	defer h.mu.RUnlock()

	userConns, exists := h.connections[userID]
	if !exists {
		return nil
	}

	connections := make([]*Connection, 0, len(userConns))
	for _, conn := range userConns {
		connections = append(connections, conn)
	}
	return connections
}

// GetStats returns current hub statistics
func (h *Hub) GetStats() map[string]interface{} {
	h.mu.RLock()
	defer h.mu.RUnlock()

	totalConnections := 0
	for _, userConns := range h.connections {
		totalConnections += len(userConns)
	}

	return map[string]interface{}{
		"total_users":       len(h.connections),
		"total_connections": totalConnections,
		"max_conn_per_user": h.maxConnPerUser,
	}
}

// Stop stops the hub
func (h *Hub) Stop() {
	close(h.stop)
}

// handleRegister processes connection registration
func (h *Hub) handleRegister(conn *Connection) {
	// Initialize MQTT subscription for this device if needed
	// This will be implemented when MQTT broker is added
	h.logger.Debug("Processing connection registration",
		zap.String("connection_id", conn.ID),
		zap.String("device_id", conn.DeviceID))
}

// handleUnregister processes connection unregistration
func (h *Hub) handleUnregister(conn *Connection) {
	// Cleanup MQTT subscriptions for this device if needed
	// This will be implemented when MQTT broker is added
	h.logger.Debug("Processing connection unregistration",
		zap.String("connection_id", conn.ID),
		zap.String("device_id", conn.DeviceID))
}

// cleanup performs periodic cleanup of stale connections
func (h *Hub) cleanup() {
	h.mu.Lock()
	defer h.mu.Unlock()

	now := time.Now()
	for userID, userConns := range h.connections {
		for connID, conn := range userConns {
			if conn.IsStale(now) {
				delete(userConns, connID)
				conn.Close()
				h.logger.Info("Cleaned up stale connection",
					zap.String("user_id", userID),
					zap.String("connection_id", connID))
			}
		}
		// Clean up empty user connections map
		if len(userConns) == 0 {
			delete(h.connections, userID)
		}
	}
}

// shutdown gracefully shuts down all connections
func (h *Hub) shutdown() {
	h.mu.Lock()
	defer h.mu.Unlock()

	for userID, userConns := range h.connections {
		for connID, conn := range userConns {
			conn.Close()
			h.logger.Info("Shut down connection",
				zap.String("user_id", userID),
				zap.String("connection_id", connID))
		}
	}

	h.connections = make(map[string]map[string]*Connection)
	h.logger.Info("WebSocket hub shutdown complete")
}
