package config

import (
	"os"
	"testing"
)

func TestLoad(t *testing.T) {
	// Test with default values
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}

	if cfg.ServerAddr != ":8080" {
		t.Errorf("Expected ServerAddr to be :8080, got %s", cfg.ServerAddr)
	}

	if cfg.LogLevel != "info" {
		t.Errorf("Expected LogLevel to be info, got %s", cfg.LogLevel)
	}
}

func TestLoadWithEnvVars(t *testing.T) {
	// Set environment variables
	if err := os.Setenv("SERVER_ADDR", ":9090"); err != nil {
		t.Fatalf("failed to set env: %v", err)
	}
	if err := os.Setenv("LOG_LEVEL", "debug"); err != nil {
		t.Fatalf("failed to set env: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Unsetenv("SERVER_ADDR")
		_ = os.Unsetenv("LOG_LEVEL")
	})

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}

	if cfg.ServerAddr != ":9090" {
		t.Errorf("Expected ServerAddr to be :9090, got %s", cfg.ServerAddr)
	}

	if cfg.LogLevel != "debug" {
		t.Errorf("Expected LogLevel to be debug, got %s", cfg.LogLevel)
	}
}
