package websocket

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

type fakeBroker struct{ published [][]byte }

func (f *fakeBroker) PublishToDevice(deviceID, deviceBy string, payload []byte) error {
	f.published = append(f.published, payload)
	return nil
}
func (f *fakeBroker) SubscribeToDevice(deviceID, deviceBy string, handler func(topic string, payload []byte)) error {
	return nil
}
func (f *fakeBroker) Kick(deviceID string) error { return nil }

func TestHandleDeviceCommand(t *testing.T) {
	// Use a WebSocket in-memory server
	srv := httptest.NewServer(httpHandler(func(w *websocket.Conn) {
		// no-op
	}))
	defer srv.Close()

	// Dialer to create a dummy connection; we won't use network IO in the test
	u := "ws://example/"
	d := websocket.Dialer{}
	_, _, _ = d.Dial(u, nil) // best-effort; this may fail in tests and is not required

	broker := &fakeBroker{}
	logger, _ := zap.NewDevelopment()
	conn := NewConnection(&websocket.Conn{}, "user1", "AABBCCDDEEFF", "mac", &Hub{}, broker, logger)

	// Send a device_command
	payload := map[string]interface{}{"cmd": "reboot"}
	msg := Message{Type: "device_command", DeviceID: conn.DeviceID, Data: payload, Timestamp: time.Now()}
	b, _ := json.Marshal(msg)
	conn.handleMessage(b)

	if len(broker.published) != 1 {
		t.Fatalf("expected 1 publish, got %d", len(broker.published))
	}
}

func TestHandleMQTTMessageClassification(t *testing.T) {
	logger, _ := zap.NewDevelopment()
	conn := NewConnection(&websocket.Conn{}, "user1", "AABBCCDDEEFF", "mac", &Hub{}, &fakeBroker{}, logger)
	// override send channel to avoid blocking
	conn.send = make(chan []byte, 10)

	// up
	conn.HandleMQTTMessage("devices/AABBCCDDEEFF/up", []byte(`{"x":1}`))
	// status
	conn.HandleMQTTMessage("devices/AABBCCDDEEFF/status", []byte("online"))
	// register
	conn.HandleMQTTMessage("devices/AABBCCDDEEFF/register", []byte("{}"))

	if len(conn.send) < 3 {
		t.Fatalf("expected at least 3 outbound messages, got %d", len(conn.send))
	}
}

// httpHandler adapts a function to httptest server that upgrades to WebSocket
func httpHandler(fn func(*websocket.Conn)) *testWSHandler { return &testWSHandler{fn: fn} }

type testWSHandler struct{ fn func(*websocket.Conn) }

func (h *testWSHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	conn, _ := upgrader.Upgrade(w, r, nil)
	if conn != nil {
		h.fn(conn)
	}
}
