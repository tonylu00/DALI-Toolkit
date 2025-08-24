package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casdoor"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casbinx"
	"github.com/tonylu00/DALI-Toolkit/server/internal/config"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupTestMiddleware(t *testing.T) (*Middleware, *gin.Engine) {
	gin.SetMode(gin.TestMode)

	// Setup database
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	require.NoError(t, err)

	err = db.AutoMigrate(&models.Organization{}, &models.CasbinRule{})
	require.NoError(t, err)

	// Create test organization
	org := &models.Organization{
		BaseModel:  models.BaseModel{ID: uuid.New()},
		CasdoorOrg: "test-org",
		Name:       "Test Organization",
	}
	err = db.Create(org).Error
	require.NoError(t, err)

	// Setup services
	orgService := services.NewOrganizationService(db)

	// Setup Casdoor client (mock for testing)
	cfg := &config.Config{
		CasdoorServerURL: "https://door.casdoor.com",
		CasdoorSuperOrg:  "built-in",
	}
	casdoorClient, err := casdoor.New(cfg)
	require.NoError(t, err)

	// Setup Casbin enforcer
	enforcer, err := casbinx.New(db)
	require.NoError(t, err)

	// Setup logger
	logger, err := zap.NewDevelopment()
	require.NoError(t, err)

	// Create middleware
	middleware := New(casdoorClient, enforcer, orgService, logger)

	// Setup router
	router := gin.New()
	
	// Test endpoints
	router.GET("/public", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "public"})
	})

	protected := router.Group("/protected")
	protected.Use(middleware.AuthRequired())
	{
		protected.GET("/test", func(c *gin.Context) {
			user := GetUserContext(c)
			c.JSON(http.StatusOK, gin.H{"user": user})
		})
	}

	permissioned := router.Group("/permissioned")
	permissioned.Use(middleware.AuthRequired())
	permissioned.Use(middleware.RequirePermission("devices", "read"))
	{
		permissioned.GET("/devices", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"message": "devices"})
		})
	}

	return middleware, router
}

func TestAuthMiddleware_PublicEndpoint(t *testing.T) {
	_, router := setupTestMiddleware(t)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/public", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	
	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(t, err)
	assert.Equal(t, "public", response["message"])
}

func TestAuthMiddleware_MissingToken(t *testing.T) {
	_, router := setupTestMiddleware(t)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/protected/test", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestAuthMiddleware_InvalidToken(t *testing.T) {
	_, router := setupTestMiddleware(t)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/protected/test", nil)
	req.Header.Set("Authorization", "Bearer invalid-token")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestGetUserContext(t *testing.T) {
	gin.SetMode(gin.TestMode)
	c, _ := gin.CreateTestContext(httptest.NewRecorder())

	// Test when no user context exists
	userCtx := GetUserContext(c)
	assert.Nil(t, userCtx)

	// Test when user context exists
	expectedCtx := &UserContext{
		UserID:   "test-user",
		Username: "testuser",
		Email:    "test@example.com",
	}
	c.Set("user", expectedCtx)

	userCtx = GetUserContext(c)
	assert.NotNil(t, userCtx)
	assert.Equal(t, expectedCtx.UserID, userCtx.UserID)
	assert.Equal(t, expectedCtx.Username, userCtx.Username)
	assert.Equal(t, expectedCtx.Email, userCtx.Email)
}

// Note: Testing with actual JWT tokens would require setting up proper test tokens
// For now, we test the middleware structure and error cases
// In production, you would mock the Casdoor client or use test tokens