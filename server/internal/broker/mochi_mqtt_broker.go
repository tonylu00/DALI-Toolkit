package broker

import (
	"context"
	"regexp"
	"strings"
	"sync"

	mqtt "github.com/mochi-mqtt/server/v2"
	"github.com/mochi-mqtt/server/v2/listeners"
	"github.com/mochi-mqtt/server/v2/packets"
	"go.uber.org/zap"

	"server/internal/config"
	"server/internal/domain/models"
	"server/internal/domain/services"
)

// MochiBroker implements MQTT using mochi-mqtt/server v2
type MochiBroker struct {
	cfg           *config.Config
	deviceService *services.DeviceService
	auditService  *services.AuditService
	logger        *zap.Logger

	srv     *mqtt.Server
	running bool
	mu      sync.RWMutex

	// clientID -> normalized device ID (from password)
	clientDevice sync.Map

	// deviceID -> WS handler
	handlers   map[string]func(topic string, payload []byte)
	handlersMu sync.RWMutex
}

// NewMQTTBroker returns a new Mochi MQTT broker
func NewMQTTBroker(cfg *config.Config, deviceService *services.DeviceService, audit *services.AuditService, logger *zap.Logger) *MochiBroker {
	return &MochiBroker{
		cfg:           cfg,
		deviceService: deviceService,
		auditService:  audit,
		logger:        logger.With(zap.String("component", "mqtt_broker")),
		handlers:      make(map[string]func(topic string, payload []byte)),
	}
}

// Start launches the broker; blocks until ctx done
func (b *MochiBroker) Start(ctx context.Context) error {
	b.mu.Lock()
	if b.running {
		b.mu.Unlock()
		return nil
	}
	b.running = true
	b.mu.Unlock()

	// Create server with inline client enabled for internal publish/subscribe
	srv := mqtt.New(&mqtt.Options{InlineClient: true})

	// Add TCP listener
	tcp := listeners.NewTCP(listeners.Config{ID: "tcp", Address: b.cfg.MQTTListenAddr})
	if err := srv.AddListener(tcp); err != nil {
		b.logger.Error("Failed to add TCP listener", zap.Error(err))
		return err
	}

	// Custom hook to implement connect auth and ACL precisely
	if err := srv.AddHook(&mochiHook{b: b}, nil); err != nil {
		b.logger.Error("Failed to add MQTT hook", zap.Error(err))
		return err
	}

	// Start serving
	go func() {
		if err := srv.Serve(); err != nil {
			b.logger.Error("Mochi MQTT serve error", zap.Error(err))
		}
	}()

	b.srv = srv
	b.logger.Info("mochi-mqtt broker running", zap.String("addr", b.cfg.MQTTListenAddr))

	<-ctx.Done()

	// Shutdown
	_ = srv.Close()

	b.mu.Lock()
	b.running = false
	b.mu.Unlock()
	b.logger.Info("mochi-mqtt broker stopped")
	return nil
}

// Stop stops the broker gracefully
func (b *MochiBroker) Stop() error {
	b.mu.RLock()
	srv := b.srv
	b.mu.RUnlock()
	if srv != nil {
		return srv.Close()
	}
	return nil
}

// PublishToDevice publishes data to devices/<id>/down
func (b *MochiBroker) PublishToDevice(deviceID, deviceBy string, payload []byte) error {
	b.mu.RLock()
	running := b.running
	srv := b.srv
	b.mu.RUnlock()
	if !running || srv == nil {
		return ErrBrokerNotRunning
	}
	topic := "devices/" + normalizeDeviceKey(deviceID) + "/down"
	return srv.Publish(topic, payload, false, 1)
}

// SubscribeToDevice registers WS handler for device uplinks
func (b *MochiBroker) SubscribeToDevice(deviceID, deviceBy string, handler func(topic string, payload []byte)) error {
	b.mu.RLock()
	running := b.running
	srv := b.srv
	b.mu.RUnlock()
	if !running || srv == nil {
		return ErrBrokerNotRunning
	}
	id := normalizeDeviceKey(deviceID)
	// store handler
	b.handlersMu.Lock()
	b.handlers[id] = handler
	b.handlersMu.Unlock()

	// Inline subscribe to all uplink topics for this device
	cb := func(cl *mqtt.Client, sub packets.Subscription, pk packets.Packet) {
		// deliver to handler
		payload := make([]byte, len(pk.Payload))
		copy(payload, pk.Payload)
		handler(pk.TopicName, payload)
	}
	// Subscribe to up/status/register
	_ = srv.Subscribe("devices/"+id+"/up", 1, cb)
	_ = srv.Subscribe("devices/"+id+"/status", 1, cb)
	_ = srv.Subscribe("devices/"+id+"/register", 1, cb)
	return nil
}

// GetStats provides summary
func (b *MochiBroker) GetStats() map[string]interface{} {
	b.mu.RLock()
	status := "stopped"
	if b.running {
		status = "running"
	}
	b.mu.RUnlock()
	return map[string]interface{}{
		"status":          status,
		"listen_address":  b.cfg.MQTTListenAddr,
		"device_username": b.cfg.MQTTDeviceUsername,
		"implementation":  "mochi-mqtt",
	}
}

// Kick disconnects client by device id (MAC)
func (b *MochiBroker) Kick(deviceID string) error {
	b.mu.RLock()
	srv := b.srv
	b.mu.RUnlock()
	if srv == nil {
		return ErrBrokerNotRunning
	}
	target := normalizeDeviceKey(deviceID)
	// Iterate clients from server and disconnect matches
	for id, cl := range srv.Clients.GetAll() {
		if v, ok := b.clientDevice.Load(id); ok {
			if equalsDeviceID(toString(v), target) {
				_ = srv.DisconnectClient(cl, packets.CodeSuccess)
			}
		}
	}
	return nil
}

// mochiHook implements fine-grained auth and ACL via hooks
type mochiHook struct {
	mqtt.HookBase
	b *MochiBroker
}

func (h *mochiHook) ID() string { return "dalitoolkit-auth-acl" }

func (h *mochiHook) Provides(b byte) bool { return true }

// OnConnectAuthenticate validates username/password
func (h *mochiHook) OnConnectAuthenticate(cl *mqtt.Client, pk packets.Packet) bool {
	username := string(pk.Connect.Username)
	password := string(pk.Connect.Password)
	if username != h.b.cfg.MQTTDeviceUsername {
		h.b.logger.Warn("MQTT auth failed: username mismatch", zap.String("username", username))
		return false
	}
	mac, err := services.NormalizeMAC(password)
	if err != nil {
		h.b.logger.Warn("MQTT auth failed: invalid MAC password", zap.String("password", password))
		return false
	}
	h.b.clientDevice.Store(cl.ID, mac)

	// Mark device online if exists
	if dev, derr := h.b.deviceService.GetDeviceByIdentifier(mac, "mac"); derr == nil && dev != nil {
		_ = h.b.deviceService.UpdateDeviceStatus(dev.ID, models.DeviceStatusOnline)
	}
	h.b.logger.Info("MQTT client connected", zap.String("client_id", cl.ID), zap.String("device_mac", mac))
	return true
}

// OnDisconnect marks offline
func (h *mochiHook) OnDisconnect(cl *mqtt.Client, err error, expire bool) {
	if v, ok := h.b.clientDevice.LoadAndDelete(cl.ID); ok {
		if dev, derr := h.b.deviceService.GetDeviceByIdentifier(toString(v), "mac"); derr == nil && dev != nil {
			_ = h.b.deviceService.UpdateDeviceStatus(dev.ID, models.DeviceStatusOffline)
		}
		h.b.logger.Info("MQTT client disconnected", zap.String("client_id", cl.ID), zap.Error(err))
	}
}

// OnACLCheck allow per-topic rules
func (h *mochiHook) OnACLCheck(cl *mqtt.Client, topic string, write bool) bool {
	// lookup device id from connect
	v, _ := h.b.clientDevice.Load(cl.ID)
	did := toString(v)
	if did == "" {
		return false
	}
	if write {
		// publish allowed only to devices/<id>/(up|status|register)
		id, kind := parseDeviceTopic(topic)
		if id == "" {
			return false
		}
		if !equalsDeviceID(did, id) {
			return false
		}
		if kind == "up" || kind == "status" || kind == "register" {
			return true
		}
		return false
	}
	// subscribe: only to devices/<id>/down
	expected := "devices/" + normalizeDeviceKey(did) + "/down"
	return topic == expected
}

// OnPublished fanout to WS and device lifecycle handling
func (h *mochiHook) OnPublished(cl *mqtt.Client, pk packets.Packet) {
	// only handle publish from clients (not inline) on device topics
	id, kind := parseDeviceTopic(pk.TopicName)
	if id == "" {
		return
	}

	// Update lifecycle
	go h.b.handleDeviceLifecycleOnPublish(id, kind, pk.Payload)

	// deliver to handler if exists
	h.b.handlersMu.RLock()
	handler := h.b.handlers[id]
	h.b.handlersMu.RUnlock()
	if handler != nil {
		payload := make([]byte, len(pk.Payload))
		copy(payload, pk.Payload)
		go handler(pk.TopicName, payload)
	}
}

// helpers from old gmqtt implementation (adapted)
func toString(v interface{}) string {
	if v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

var macRegex = regexp.MustCompile(`^[0-9A-F]{12}$`)

func normalizeDeviceKey(id string) string {
	up := strings.ToUpper(strings.ReplaceAll(strings.ReplaceAll(strings.ReplaceAll(id, ":", ""), "-", ""), ".", ""))
	if macRegex.MatchString(up) {
		return up
	}
	return id
}

func equalsDeviceID(a, b string) bool { return normalizeDeviceKey(a) == normalizeDeviceKey(b) }

func parseDeviceTopic(topic string) (id string, kind string) {
	if !strings.HasPrefix(topic, "devices/") {
		return "", ""
	}
	parts := strings.Split(topic, "/")
	if len(parts) != 3 {
		return "", ""
	}
	return normalizeDeviceKey(parts[1]), parts[2]
}

// ErrBrokerNotRunning indicates broker not running
var ErrBrokerNotRunning = &BrokerError{"MQTT broker not running"}

type BrokerError struct{ msg string }

func (e *BrokerError) Error() string { return e.msg }

// device lifecycle
func (b *MochiBroker) handleDeviceLifecycleOnPublish(deviceID, kind string, payload []byte) {
	dev, err := b.deviceService.GetDeviceByIdentifier(deviceID, "mac")
	if err == nil && dev != nil {
		switch kind {
		case "status":
			text := strings.TrimSpace(strings.ToLower(string(payload)))
			status := models.DeviceStatusOnline
			if strings.Contains(text, "offline") {
				status = models.DeviceStatusOffline
			}
			_ = b.deviceService.UpdateDeviceStatus(dev.ID, status)
		default:
			_ = b.deviceService.UpdateDeviceStatus(dev.ID, models.DeviceStatusOnline)
		}
		return
	}

	// best-effort: for unknown devices and register topic, auto-register if enabled
	if kind == "register" && b.cfg.FactoryAllowRegistration {
		// minimal fields handled server-side already (full parsing in domain service)
		if dev2, created, e := b.deviceService.FindOrCreateForRegistration(deviceID, nil, "", models.DeviceTypeOther, b.cfg.FactoryDefaultProjectID, true); e == nil && dev2 != nil {
			_ = b.deviceService.UpdateDeviceStatus(dev2.ID, models.DeviceStatusOnline)
			if created {
				b.logger.Info("Device auto-registered via MQTT", zap.String("mac", deviceID), zap.String("device_id", dev2.ID.String()))
			}
		}
	}
}
