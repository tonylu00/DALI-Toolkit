package services

import (
	"testing"

	"server/internal/domain/models"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupTestDB(t *testing.T) *gorm.DB {
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

	return db
}

func TestOrganizationService_CRUD(t *testing.T) {
	db := setupTestDB(t)
	service := NewOrganizationService(db)

	// Create
	org, err := service.CreateOrganization("test-org", "Test Organization")
	assert.NoError(t, err)
	assert.Equal(t, "test-org", org.CasdoorOrg)
	assert.Equal(t, "Test Organization", org.Name)

	// Create duplicate should fail
	_, err = service.CreateOrganization("test-org", "Duplicate Org")
	assert.Error(t, err)

	// Get by ID
	retrieved, err := service.GetOrganization(org.ID)
	assert.NoError(t, err)
	assert.Equal(t, org.CasdoorOrg, retrieved.CasdoorOrg)

	// Get by Casdoor org
	retrieved, err = service.GetOrganizationByCasdoor("test-org")
	assert.NoError(t, err)
	assert.Equal(t, org.ID, retrieved.ID)

	// Update
	updated, err := service.UpdateOrganization(org.ID, "Updated Organization")
	assert.NoError(t, err)
	assert.Equal(t, "Updated Organization", updated.Name)

	// List
	orgs, err := service.ListOrganizations()
	assert.NoError(t, err)
	assert.Len(t, orgs, 1)

	// Delete
	err = service.DeleteOrganization(org.ID)
	assert.NoError(t, err)

	// Verify deletion
	_, err = service.GetOrganization(org.ID)
	assert.Error(t, err)
}

func TestDeviceService_Validation(t *testing.T) {
	// Test MAC validation
	assert.True(t, ValidateMAC("A1B2C3D4E5F6"))
	assert.True(t, ValidateMAC("a1:b2:c3:d4:e5:f6"))
	assert.True(t, ValidateMAC("a1-b2-c3-d4-e5-f6"))
	assert.False(t, ValidateMAC("invalid"))
	assert.False(t, ValidateMAC("A1B2C3D4E5"))

	// Test MAC normalization
	normalized1, _ := NormalizeMAC("a1:b2:c3:d4:e5:f6")
	assert.Equal(t, "A1B2C3D4E5F6", normalized1)
	normalized2, _ := NormalizeMAC("a1-b2-c3-d4-e5-f6")
	assert.Equal(t, "A1B2C3D4E5F6", normalized2)
	normalized3, _ := NormalizeMAC("a1b2c3d4e5f6")
	assert.Equal(t, "A1B2C3D4E5F6", normalized3)

	// Test IMEI validation
	assert.True(t, ValidateIMEI("123456789012345"))
	assert.True(t, ValidateIMEI("12345678901234"))
	assert.False(t, ValidateIMEI("1234567890123"))     // too short
	assert.False(t, ValidateIMEI("12345678901234567")) // too long
	assert.False(t, ValidateIMEI("1234567890123a5"))   // non-digit
}

func TestDeviceService_CRUD(t *testing.T) {
	db := setupTestDB(t)
	orgService := NewOrganizationService(db)
	deviceService := NewDeviceService(db)

	// Setup organization and project
	org, err := orgService.CreateOrganization("test-org", "Test Organization")
	require.NoError(t, err)

	project := &models.Project{
		BaseModel: models.BaseModel{ID: uuid.New()},
		OrgID:     org.ID,
		Name:      "Test Project",
		CreatedBy: uuid.New(),
	}
	err = db.Create(project).Error
	require.NoError(t, err)

	// Create device
	imei := "123456789012345"
	device, err := deviceService.CreateDevice(
		"a1:b2:c3:d4:e5:f6",
		&imei,
		models.DeviceTypeLTE,
		project.ID,
		nil,
		"Test Device",
	)
	assert.NoError(t, err)
	assert.Equal(t, "A1B2C3D4E5F6", device.MAC)
	assert.Equal(t, &imei, device.IMEI)
	assert.Equal(t, models.DeviceStatusUnbound, device.Status)

	// Create duplicate MAC should fail
	_, err = deviceService.CreateDevice(
		"A1B2C3D4E5F6",
		nil,
		models.DeviceTypeWiFi,
		project.ID,
		nil,
		"Duplicate Device",
	)
	assert.Error(t, err)

	// Get by ID
	retrieved, err := deviceService.GetDevice(device.ID)
	assert.NoError(t, err)
	assert.Equal(t, device.MAC, retrieved.MAC)

	// Get by MAC
	retrieved, err = deviceService.GetDeviceByIdentifier("a1:b2:c3:d4:e5:f6", "mac")
	assert.NoError(t, err)
	assert.Equal(t, device.ID, retrieved.ID)

	// Get by IMEI
	retrieved, err = deviceService.GetDeviceByIdentifier("123456789012345", "imei")
	assert.NoError(t, err)
	assert.Equal(t, device.ID, retrieved.ID)

	// Update status
	err = deviceService.UpdateDeviceStatus(device.ID, models.DeviceStatusOnline)
	assert.NoError(t, err)

	// Verify status update
	updated, err := deviceService.GetDevice(device.ID)
	assert.NoError(t, err)
	assert.Equal(t, models.DeviceStatusOnline, updated.Status)
	assert.NotNil(t, updated.LastSeenAt)

	// List by organization
	devices, err := deviceService.ListDevicesByOrganization(org.ID, map[string]interface{}{
		"status": models.DeviceStatusOnline,
	})
	assert.NoError(t, err)
	assert.Len(t, devices, 1)

	// List by project
	devices, err = deviceService.ListDevicesByProject(project.ID, nil)
	assert.NoError(t, err)
	assert.Len(t, devices, 1)
}
