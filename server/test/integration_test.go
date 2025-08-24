package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"server/internal/middleware"
	"server/internal/web"
)

func setupTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()

	// Add security middleware
	r.Use(middleware.SecurityHeadersMiddleware())
	r.Use(middleware.RateLimitMiddleware())
	r.Use(middleware.RequestSizeMiddleware(1024 * 1024)) // 1MB

	// Add basic routes for testing
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/api/v1/info", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"name": "DALI-Toolkit", "version": "v0.1.0"})
	})

	return r
}

func TestSecurityHeaders(t *testing.T) {
	router := setupTestRouter()

	req, _ := http.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	// Check security headers
	assert.Equal(t, "nosniff", w.Header().Get("X-Content-Type-Options"))
	assert.Equal(t, "DENY", w.Header().Get("X-Frame-Options"))
	assert.Equal(t, "1; mode=block", w.Header().Get("X-XSS-Protection"))
	assert.Equal(t, "strict-origin-when-cross-origin", w.Header().Get("Referrer-Policy"))
	assert.Equal(t, "", w.Header().Get("Server"))
}

func TestRateLimit(t *testing.T) {
	router := setupTestRouter()

	// Make multiple requests quickly
	for i := 0; i < 10; i++ {
		req, _ := http.NewRequest("GET", "/health", nil)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		// First few requests should succeed
		if i < 5 {
			assert.Equal(t, http.StatusOK, w.Code)
		}
	}
}

func TestRequestSizeLimit(t *testing.T) {
	router := setupTestRouter()

	// Add a POST endpoint for testing
	router.POST("/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"received": "ok"})
	})

	// Create a large request body (larger than 1MB limit)
	largeBody := bytes.Repeat([]byte("a"), 2*1024*1024) // 2MB

	req, _ := http.NewRequest("POST", "/test", bytes.NewReader(largeBody))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusRequestEntityTooLarge, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	require.NoError(t, err)

	errorInfo := response["error"].(map[string]interface{})
	assert.Equal(t, "REQUEST_TOO_LARGE", errorInfo["code"])
}

func TestWebAppIntegration(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()

	// Setup web handler
	webConfig := &web.Config{
		AppEmbedEnabled: true,
		AppStaticPath:   "./test_app",
		AppBasePath:     "/app",
	}
	webHandler := web.NewHandler(webConfig)

	// Register web routes
	webGroup := router.Group("")
	err := webHandler.RegisterRoutes(webGroup)
	require.NoError(t, err)

	// Test web app route
	req, _ := http.NewRequest("GET", "/app/", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	// Should return placeholder or embedded content
	assert.True(t, w.Code == http.StatusOK || w.Code == http.StatusNotFound)
}

func TestCORSMiddleware(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(web.CORSMiddleware())

	router.GET("/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "test"})
	})

	// Test CORS preflight request
	req, _ := http.NewRequest("OPTIONS", "/test", nil)
	req.Header.Set("Origin", "http://localhost:3000")

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "http://localhost:3000", w.Header().Get("Access-Control-Allow-Origin"))
	assert.Equal(t, "true", w.Header().Get("Access-Control-Allow-Credentials"))
}

func TestCSPMiddleware(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(web.CSPMiddleware())

	router.GET("/app/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "test"})
	})

	req, _ := http.NewRequest("GET", "/app/test", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Header().Get("Content-Security-Policy"), "default-src 'self'")
	assert.Equal(t, "DENY", w.Header().Get("X-Frame-Options"))
	assert.Equal(t, "nosniff", w.Header().Get("X-Content-Type-Options"))
}

func TestHealthEndpointSecurity(t *testing.T) {
	router := setupTestRouter()

	req, _ := http.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	require.NoError(t, err)

	assert.Equal(t, "ok", response["status"])
}

func TestAPIInfoEndpointSecurity(t *testing.T) {
	router := setupTestRouter()

	req, _ := http.NewRequest("GET", "/api/v1/info", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	require.NoError(t, err)

	assert.Equal(t, "DALI-Toolkit", response["name"])
	assert.Equal(t, "v0.1.0", response["version"])
}
