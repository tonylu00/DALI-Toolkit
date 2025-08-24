package store

import (
	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"gorm.io/gorm"
)

// DeviceRepository handles device data operations
type DeviceRepository struct {
	db *gorm.DB
}

// NewDeviceRepository creates a new device repository
func NewDeviceRepository(db *gorm.DB) *DeviceRepository {
	return &DeviceRepository{db: db}
}

// Create creates a new device
func (r *DeviceRepository) Create(device *models.Device) error {
	return r.db.Create(device).Error
}

// GetByID gets a device by ID
func (r *DeviceRepository) GetByID(id uuid.UUID) (*models.Device, error) {
	var device models.Device
	err := r.db.Preload("Project").Preload("Partition").First(&device, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &device, nil
}

// GetByMAC gets a device by MAC address
func (r *DeviceRepository) GetByMAC(mac string) (*models.Device, error) {
	var device models.Device
	err := r.db.Preload("Project").Preload("Partition").First(&device, "mac = ?", mac).Error
	if err != nil {
		return nil, err
	}
	return &device, nil
}

// GetByIMEI gets a device by IMEI
func (r *DeviceRepository) GetByIMEI(imei string) (*models.Device, error) {
	var device models.Device
	err := r.db.Preload("Project").Preload("Partition").First(&device, "imei = ?", imei).Error
	if err != nil {
		return nil, err
	}
	return &device, nil
}

// ListByProject lists devices by project ID with optional filtering
func (r *DeviceRepository) ListByProject(projectID uuid.UUID, filters map[string]interface{}) ([]models.Device, error) {
	var devices []models.Device
	query := r.db.Preload("Project").Preload("Partition").Where("project_id = ?", projectID)
	
	for key, value := range filters {
		query = query.Where(key+" = ?", value)
	}
	
	err := query.Find(&devices).Error
	return devices, err
}

// ListByOrg lists devices by organization ID (through project relationship)
func (r *DeviceRepository) ListByOrg(orgID uuid.UUID, filters map[string]interface{}) ([]models.Device, error) {
	var devices []models.Device
	query := r.db.Preload("Project").Preload("Partition").
		Joins("JOIN projects ON devices.project_id = projects.id").
		Where("projects.org_id = ?", orgID)
	
	for key, value := range filters {
		if key == "status" || key == "device_type" {
			query = query.Where("devices."+key+" = ?", value)
		}
	}
	
	err := query.Find(&devices).Error
	return devices, err
}

// Update updates a device
func (r *DeviceRepository) Update(device *models.Device) error {
	return r.db.Save(device).Error
}

// Delete deletes a device
func (r *DeviceRepository) Delete(id uuid.UUID) error {
	return r.db.Delete(&models.Device{}, "id = ?", id).Error
}

// UpdateLastSeen updates the last seen timestamp for a device
func (r *DeviceRepository) UpdateLastSeen(deviceID uuid.UUID) error {
	return r.db.Model(&models.Device{}).Where("id = ?", deviceID).Update("last_seen_at", gorm.Expr("NOW()")).Error
}