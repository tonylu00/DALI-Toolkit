package broker

import (
	"context"
	"fmt"
	"sync"

	"github.com/tonylu00/DALI-Toolkit/server/internal/config"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"go.uber.org/zap"
)

// SimpleMQTTBroker is a simplified MQTT broker implementation
// This will be replaced with full gmqtt implementation once dependencies are resolved
type SimpleMQTTBroker struct {
	config        *config.Config
	deviceService *services.DeviceService
	logger        *zap.Logger
	running       bool
	mu            sync.RWMutex
	
	// Message handlers for WebSocket connections
	handlers map[string]func(topic string, payload []byte)
	handlersMu sync.RWMutex
}

// NewMQTTBroker creates a new simplified MQTT broker
func NewMQTTBroker(cfg *config.Config, deviceService *services.DeviceService, logger *zap.Logger) *SimpleMQTTBroker {
	return &SimpleMQTTBroker{
		config:        cfg,
		deviceService: deviceService,
		logger:        logger.With(zap.String("component", "mqtt_broker")),
		handlers:      make(map[string]func(topic string, payload []byte)),
	}
}

// Start starts the simplified MQTT broker
func (b *SimpleMQTTBroker) Start(ctx context.Context) error {
	b.mu.Lock()
	b.running = true
	b.mu.Unlock()
	
	b.logger.Info("Simplified MQTT broker starting", zap.String("addr", b.config.MQTTListenAddr))
	
	// Wait for context cancellation
	<-ctx.Done()
	
	b.mu.Lock()
	b.running = false
	b.mu.Unlock()
	
	b.logger.Info("Simplified MQTT broker stopped")
	return nil
}

// Stop stops the broker
func (b *SimpleMQTTBroker) Stop() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	
	b.running = false
	b.logger.Info("MQTT broker stop requested")
	return nil
}

// PublishToDevice publishes a message to a specific device
func (b *SimpleMQTTBroker) PublishToDevice(deviceID, deviceBy string, payload []byte) error {
	b.mu.RLock()
	running := b.running
	b.mu.RUnlock()
	
	if !running {
		return fmt.Errorf("MQTT broker not running")
	}

	topic := fmt.Sprintf("devices/%s/down", deviceID)
	
	b.logger.Debug("Message published to device (simplified)",
		zap.String("device_id", deviceID),
		zap.String("topic", topic),
		zap.Int("payload_size", len(payload)))

	// In a real implementation, this would send to MQTT clients
	// For now, we just log the message
	return nil
}

// SubscribeToDevice subscribes to device uplink messages
func (b *SimpleMQTTBroker) SubscribeToDevice(deviceID, deviceBy string, handler func(topic string, payload []byte)) error {
	b.mu.RLock()
	running := b.running
	b.mu.RUnlock()
	
	if !running {
		return fmt.Errorf("MQTT broker not running")
	}

	// Store handler for this device
	b.handlersMu.Lock()
	b.handlers[deviceID] = handler
	b.handlersMu.Unlock()

	b.logger.Debug("Device subscription registered (simplified)",
		zap.String("device_id", deviceID))

	return nil
}

// GetStats returns broker statistics
func (b *SimpleMQTTBroker) GetStats() map[string]interface{} {
	b.mu.RLock()
	running := b.running
	b.mu.RUnlock()
	
	status := "stopped"
	if running {
		status = "running"
	}

	return map[string]interface{}{
		"status":           status,
		"listen_address":   b.config.MQTTListenAddr,
		"device_username":  b.config.MQTTDeviceUsername,
		"implementation":   "simplified",
		"note":            "This is a simplified implementation for M3 milestone",
	}
}

// SimulateDeviceMessage simulates an incoming device message (for testing)
func (b *SimpleMQTTBroker) SimulateDeviceMessage(deviceID, messageType string, payload []byte) {
	topic := fmt.Sprintf("devices/%s/%s", deviceID, messageType)
	
	b.handlersMu.RLock()
	handler, exists := b.handlers[deviceID]
	b.handlersMu.RUnlock()
	
	if exists && handler != nil {
		handler(topic, payload)
		b.logger.Debug("Simulated device message delivered",
			zap.String("device_id", deviceID),
			zap.String("topic", topic))
	} else {
		b.logger.Debug("No handler for simulated device message",
			zap.String("device_id", deviceID),
			zap.String("topic", topic))
	}
}