package logger

import "testing"

func TestNewLoggerLevels(t *testing.T) {
	levels := []string{"debug", "info", "warn", "error", "unknown"}
	for _, lvl := range levels {
		l, err := New(lvl)
		if err != nil {
			t.Fatalf("logger.New(%q) returned error: %v", lvl, err)
		}
		if l == nil {
			t.Fatalf("logger.New(%q) returned nil logger", lvl)
		}
		_ = l.Sync()
	}
}
