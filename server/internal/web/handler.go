package web

import (
	"net/http"
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
)

// Config holds web app configuration
type Config struct {
	// AppEmbedEnabled controls whether to use embedded Flutter web app
	AppEmbedEnabled bool `mapstructure:"app_embed_enabled"`
	// AppStaticPath is the external path to Flutter web build (when not embedded)
	AppStaticPath string `mapstructure:"app_static_path"`
	// AppBasePath is the route prefix for the web app
	AppBasePath string `mapstructure:"app_base_path"`
}

// Handler provides web app serving functionality
type Handler struct {
	config *Config
}

// NewHandler creates a new web handler
func NewHandler(config *Config) *Handler {
	if config.AppBasePath == "" {
		config.AppBasePath = "/app"
	}
	if config.AppStaticPath == "" {
		config.AppStaticPath = "./app"
	}
	return &Handler{config: config}
}

// RegisterRoutes registers web app routes with Gin router
func (h *Handler) RegisterRoutes(r *gin.RouterGroup) error {
	// Try embedded first, then external directory

	if h.config.AppEmbedEnabled {
		webFS, err := GetFlutterWebFS()
		if err == nil {
			// Mount embedded Flutter web app
			r.StaticFS("/app", http.FS(webFS))
			return nil
		}
		// Fall back to external if embedded fails
	}

	// Check if external Flutter web build exists
	if _, err := os.Stat(h.config.AppStaticPath); err == nil {
		// Mount external Flutter web build
		r.Static("/app", h.config.AppStaticPath)
		return nil
	}

	// No web app available
	r.GET("/app/*filepath", func(c *gin.Context) {
		c.JSON(http.StatusNotFound, gin.H{
			"error": gin.H{
				"code":    "WEB_APP_NOT_AVAILABLE",
				"message": "Flutter web app not available. Build it first or enable embedding.",
				"details": gin.H{
					"embed_enabled": h.config.AppEmbedEnabled,
					"static_path":   h.config.AppStaticPath,
				},
			},
		})
	})

	return nil
}

// BuildFlutterWeb builds the Flutter web app (for development)
func (h *Handler) BuildFlutterWeb(projectRoot string) error {
	buildPath := filepath.Join(projectRoot, "build", "web")

	// Create symlink from build/web to configured static path
	if h.config.AppStaticPath != "./app" {
		if err := os.RemoveAll(h.config.AppStaticPath); err != nil {
			return err
		}
		return os.Symlink(buildPath, h.config.AppStaticPath)
	}

	return nil
}
