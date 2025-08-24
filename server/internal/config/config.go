package config

import (
	"os"
	"strconv"
	"strings"
)

// Config holds application configuration
type Config struct {
	// Server
	ServerAddr string
	Env        string
	LogLevel   string

	// Database
	PostgresDSN string
	RedisAddr   string

	// Casdoor
	CasdoorServerURL    string
	CasdoorClientID     string
	CasdoorClientSecret string
	CasdoorOrg          string
	CasdoorApp          string
	CasdoorSuperOrg     string
	// Casdoor Application certificate (public key in PEM), used to verify JWT
	CasdoorCertificate string

	// MQTT
	MQTTListenAddr     string
	MQTTDeviceUsername string

	// App/Web
	AppEmbedEnabled bool
	AppStaticPath   string

	// WebSocket
	WSEnable         bool
	WSPath           string
	WSMaxConnPerUser int

	// Factory/Production
	// Whether to allow device self-registration via MQTT register topic when device not exists
	FactoryAllowRegistration bool
	// Default project to attach newly registered devices (UUID string). If empty, creation will be skipped.
	FactoryDefaultProjectID string
}

// Load loads configuration from environment variables
func Load() (*Config, error) {
	cfg := &Config{
		// Server defaults
		ServerAddr: getEnv("SERVER_ADDR", ":8080"),
		Env:        getEnv("ENV", "development"),
		LogLevel:   getEnv("LOG_LEVEL", "info"),

		// Database defaults
		PostgresDSN: getEnv("PG_DSN", "postgres://postgres:password@localhost:5432/dali_toolkit?sslmode=disable"),
		RedisAddr:   getEnv("REDIS_ADDR", "localhost:6379"),

		// Casdoor defaults
		CasdoorServerURL:    getEnv("CASDOOR_SERVER_URL", "https://door.casdoor.com"),
		CasdoorClientID:     getEnv("CASDOOR_CLIENT_ID", ""),
		CasdoorClientSecret: getEnv("CASDOOR_CLIENT_SECRET", ""),
		CasdoorOrg:          getEnv("CASDOOR_ORG", ""),
		CasdoorApp:          getEnv("CASDOOR_APP", ""),
		CasdoorSuperOrg:     getEnv("CASDOOR_SUPER_ORG", "built-in"),
		CasdoorCertificate:  getEnv("CASDOOR_CERTIFICATE", getEnv("CASDOOR_CERT", "")),

		// MQTT defaults
		MQTTListenAddr:     getEnv("MQTT_LISTEN_ADDR", ":1883"),
		MQTTDeviceUsername: getEnv("MQTT_DEVICE_USERNAME", "device"),

		// App/Web defaults
		AppEmbedEnabled: getEnvBool("APP_EMBED_ENABLED", true),
		AppStaticPath:   getEnv("APP_STATIC_PATH", "./app"),

		// WebSocket defaults
		WSEnable:         getEnvBool("WS_ENABLE", true),
		WSPath:           getEnv("WS_PATH", "/ws"),
		WSMaxConnPerUser: getEnvInt("WS_MAX_CONN_PER_USER", 4),

		// Factory defaults
		FactoryAllowRegistration: getEnvBool("FACTORY_ALLOW_REGISTRATION", true),
		FactoryDefaultProjectID:  getEnv("FACTORY_PROJECT_ID", ""),
	}

	return cfg, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		return strings.ToLower(value) == "true"
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if i, err := strconv.Atoi(value); err == nil {
			return i
		}
	}
	return defaultValue
}
