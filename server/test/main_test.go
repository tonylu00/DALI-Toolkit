package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestHealthEndpoint(t *testing.T) {
	// Set Gin to test mode
	gin.SetMode(gin.TestMode)

	// Create a new router
	router := gin.New()

	// Add health check endpoint
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status": "ok",
		})
	})

	// Create a test request
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/health", nil)
	router.ServeHTTP(w, req)

	// Assert the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "ok")
}

func TestInfoEndpoint(t *testing.T) {
	// Set Gin to test mode
	gin.SetMode(gin.TestMode)

	// Create a new router
	router := gin.New()

	// Add info endpoint
	router.GET("/api/v1/info", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"name":    "DALI-Toolkit Server",
			"version": "v0.1.0",
		})
	})

	// Create a test request
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/info", nil)
	router.ServeHTTP(w, req)

	// Assert the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "DALI-Toolkit Server")
	assert.Contains(t, w.Body.String(), "v0.1.0")
}