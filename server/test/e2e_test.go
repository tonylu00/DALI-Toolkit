package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"server/internal/domain/models"
	"server/internal/domain/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// setupTestApp creates a test app with in-memory database
func setupTestApp(t *testing.T) (*gin.Engine, *services.OrganizationService, *services.DeviceService) {
	gin.SetMode(gin.TestMode)

	// Create in-memory database
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	require.NoError(t, err)

	// Run migrations
	err = db.AutoMigrate(
		&models.Organization{},
		&models.User{},
		&models.Group{},
		&models.Project{},
		&models.Partition{},
		&models.Device{},
		&models.DeviceBinding{},
		&models.DeviceShare{},
		&models.DeviceTransfer{},
		&models.CasbinRule{},
		&models.AuditLog{},
	)
	require.NoError(t, err)

	// Create services
	orgService := services.NewOrganizationService(db)
	deviceService := services.NewDeviceService(db)

	// Create router
	router := gin.New()

	// Add test endpoints
	v1 := router.Group("/api/v1")
	{
		v1.GET("/organizations", func(c *gin.Context) {
			orgs, err := orgService.ListOrganizations()
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, orgs)
		})

		v1.POST("/organizations", func(c *gin.Context) {
			var req struct {
				CasdoorOrg string `json:"casdoor_org" binding:"required"`
				Name       string `json:"name" binding:"required"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			org, err := orgService.CreateOrganization(req.CasdoorOrg, req.Name)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusCreated, org)
		})

		v1.GET("/devices", func(c *gin.Context) {
			orgID := c.Query("org_id")
			if orgID == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "org_id is required"})
				return
			}

			orgUUID, err := uuid.Parse(orgID)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid org_id"})
				return
			}

			filters := make(map[string]interface{})
			if status := c.Query("status"); status != "" {
				filters["status"] = status
			}

			devices, err := deviceService.ListDevicesByOrganization(orgUUID, filters)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, devices)
		})
	}

	return router, orgService, deviceService
}

func TestE2E_OrganizationCRUD(t *testing.T) {
	router, _, _ := setupTestApp(t)

	// Test create organization
	createReq := map[string]string{
		"casdoor_org": "test-org",
		"name":        "Test Organization",
	}
	body, _ := json.Marshal(createReq)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/organizations", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusCreated, w.Code)

	var org models.Organization
	err := json.Unmarshal(w.Body.Bytes(), &org)
	assert.NoError(t, err)
	assert.Equal(t, "test-org", org.CasdoorOrg)
	assert.Equal(t, "Test Organization", org.Name)

	// Test list organizations
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/organizations", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var orgs []models.Organization
	err = json.Unmarshal(w.Body.Bytes(), &orgs)
	assert.NoError(t, err)
	assert.Len(t, orgs, 1)
	assert.Equal(t, "test-org", orgs[0].CasdoorOrg)
}

func TestE2E_DeviceFiltering(t *testing.T) {
	router, orgService, _ := setupTestApp(t)

	// Create organization and project
	org, err := orgService.CreateOrganization("test-org", "Test Organization")
	require.NoError(t, err)

	// Create project directly in database for testing
	// This would normally be done through a proper service
	// For now, testing the device filtering functionality

	// Test device listing with org filter
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices?org_id="+org.ID.String(), nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var devices []models.Device
	err = json.Unmarshal(w.Body.Bytes(), &devices)
	assert.NoError(t, err)
	assert.Len(t, devices, 0) // No devices yet

	// Test with invalid org_id
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/devices?org_id=invalid", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	// Test without org_id
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/devices", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}
