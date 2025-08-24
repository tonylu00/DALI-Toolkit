package store

import (
	"testing"

	"server/internal/domain/models"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// setupTestDB creates an in-memory SQLite database for testing
func setupTestDB(t *testing.T) *Store {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	require.NoError(t, err)

	store := &Store{db: db}

	// Run migrations
	err = store.AutoMigrate()
	require.NoError(t, err)

	return store
}

func TestOrganizationRepository_CRUD(t *testing.T) {
	store := setupTestDB(t)
	t.Cleanup(func() { _ = store.Close() })

	repo := NewOrganizationRepository(store.DB())

	// Create
	org := &models.Organization{
		BaseModel:  models.BaseModel{ID: uuid.New()},
		CasdoorOrg: "test-org",
		Name:       "Test Organization",
	}

	err := repo.Create(org)
	assert.NoError(t, err)
	assert.NotEqual(t, uuid.Nil, org.ID)

	// Read by ID
	retrieved, err := repo.GetByID(org.ID)
	assert.NoError(t, err)
	assert.Equal(t, org.CasdoorOrg, retrieved.CasdoorOrg)
	assert.Equal(t, org.Name, retrieved.Name)

	// Read by Casdoor org
	retrieved, err = repo.GetByCasdoorOrg("test-org")
	assert.NoError(t, err)
	assert.Equal(t, org.ID, retrieved.ID)

	// Update
	retrieved.Name = "Updated Test Organization"
	err = repo.Update(retrieved)
	assert.NoError(t, err)

	// Verify update
	updated, err := repo.GetByID(org.ID)
	assert.NoError(t, err)
	assert.Equal(t, "Updated Test Organization", updated.Name)

	// List
	orgs, err := repo.List()
	assert.NoError(t, err)
	assert.Len(t, orgs, 1)

	// Delete
	err = repo.Delete(org.ID)
	assert.NoError(t, err)

	// Verify deletion
	_, err = repo.GetByID(org.ID)
	assert.Error(t, err)
}

func TestDeviceRepository_CRUD(t *testing.T) {
	store := setupTestDB(t)
	t.Cleanup(func() { _ = store.Close() })

	orgRepo := NewOrganizationRepository(store.DB())
	deviceRepo := NewDeviceRepository(store.DB())

	// Setup organization and project
	org := &models.Organization{
		BaseModel:  models.BaseModel{ID: uuid.New()},
		CasdoorOrg: "test-org",
		Name:       "Test Organization",
	}
	err := orgRepo.Create(org)
	require.NoError(t, err)

	project := &models.Project{
		BaseModel: models.BaseModel{ID: uuid.New()},
		OrgID:     org.ID,
		Name:      "Test Project",
		CreatedBy: uuid.New(),
	}
	err = store.DB().Create(project).Error
	require.NoError(t, err)

	// Create device
	device := &models.Device{
		BaseModel:   models.BaseModel{ID: uuid.New()},
		MAC:         "A1B2C3D4E5F6",
		DeviceType:  models.DeviceTypeLTE,
		ProjectID:   project.ID,
		DisplayName: "Test Device",
		Status:      models.DeviceStatusUnbound,
	}

	err = deviceRepo.Create(device)
	assert.NoError(t, err)

	// Read by MAC
	retrieved, err := deviceRepo.GetByMAC("A1B2C3D4E5F6")
	assert.NoError(t, err)
	assert.Equal(t, device.MAC, retrieved.MAC)
	assert.Equal(t, device.DisplayName, retrieved.DisplayName)

	// Test with IMEI
	imei := "123456789012345"
	device.IMEI = &imei
	err = deviceRepo.Update(device)
	assert.NoError(t, err)

	retrieved, err = deviceRepo.GetByIMEI(imei)
	assert.NoError(t, err)
	assert.Equal(t, device.ID, retrieved.ID)

	// List by project
	devices, err := deviceRepo.ListByProject(project.ID, nil)
	assert.NoError(t, err)
	assert.Len(t, devices, 1)

	// List by organization
	devices, err = deviceRepo.ListByOrg(org.ID, map[string]interface{}{
		"status": models.DeviceStatusUnbound,
	})
	assert.NoError(t, err)
	assert.Len(t, devices, 1)

	// Update device status
	device.Status = models.DeviceStatusOnline
	err = deviceRepo.Update(device)
	assert.NoError(t, err)

	// Verify update
	updated, err := deviceRepo.GetByID(device.ID)
	assert.NoError(t, err)
	assert.Equal(t, models.DeviceStatusOnline, updated.Status)

	// Delete
	err = deviceRepo.Delete(device.ID)
	assert.NoError(t, err)

	// Verify deletion
	_, err = deviceRepo.GetByID(device.ID)
	assert.Error(t, err)
}
