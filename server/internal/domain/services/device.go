package services

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"github.com/tonylu00/DALI-Toolkit/server/internal/store"
	"github.com/tonylu00/DALI-Toolkit/server/pkg/errors"
	"gorm.io/gorm"
)

// DeviceService handles device business logic
type DeviceService struct {
	deviceRepo *store.DeviceRepository
}

// NewDeviceService creates a new device service
func NewDeviceService(db *gorm.DB) *DeviceService {
	return &DeviceService{
		deviceRepo: store.NewDeviceRepository(db),
	}
}

// NormalizeMAC normalizes MAC address to uppercase 12-character hex string
func NormalizeMAC(mac string) string {
	// Remove common separators
	mac = strings.ReplaceAll(mac, ":", "")
	mac = strings.ReplaceAll(mac, "-", "")
	mac = strings.ReplaceAll(mac, ".", "")
	mac = strings.ReplaceAll(mac, " ", "")
	
	// Convert to uppercase
	return strings.ToUpper(mac)
}

// ValidateIMEI validates IMEI (14-16 digits)
func ValidateIMEI(imei string) bool {
	if len(imei) < 14 || len(imei) > 16 {
		return false
	}
	
	for _, char := range imei {
		if char < '0' || char > '9' {
			return false
		}
	}
	
	return true
}

// ValidateMAC validates MAC address (12 hex characters)
func ValidateMAC(mac string) bool {
	normalized := NormalizeMAC(mac)
	if len(normalized) != 12 {
		return false
	}
	
	for _, char := range normalized {
		if !((char >= '0' && char <= '9') || (char >= 'A' && char <= 'F')) {
			return false
		}
	}
	
	return true
}

// CreateDevice creates a new device
func (s *DeviceService) CreateDevice(mac string, imei *string, deviceType models.DeviceType, projectID uuid.UUID, partitionID *uuid.UUID, displayName string) (*models.Device, error) {
	// Validate and normalize MAC
	if !ValidateMAC(mac) {
		return nil, errors.NewValidationError("Invalid MAC address", map[string]interface{}{
			"mac": "Must be 12 hexadecimal characters",
		})
	}
	normalizedMAC := NormalizeMAC(mac)
	
	// Validate IMEI if provided
	if imei != nil {
		if !ValidateIMEI(*imei) {
			return nil, errors.NewValidationError("Invalid IMEI", map[string]interface{}{
				"imei": "Must be 14-16 digits",
			})
		}
	}
	
	// Check if device already exists
	existing, err := s.deviceRepo.GetByMAC(normalizedMAC)
	if err == nil && existing != nil {
		return nil, errors.NewConflictError("Device with this MAC already exists")
	}
	
	if imei != nil {
		existing, err = s.deviceRepo.GetByIMEI(*imei)
		if err == nil && existing != nil {
			return nil, errors.NewConflictError("Device with this IMEI already exists")
		}
	}
	
	device := &models.Device{
		BaseModel:   models.BaseModel{ID: uuid.New()},
		MAC:         normalizedMAC,
		IMEI:        imei,
		DeviceType:  deviceType,
		ProjectID:   projectID,
		PartitionID: partitionID,
		DisplayName: displayName,
		Status:      models.DeviceStatusUnbound,
	}
	
	if err := s.deviceRepo.Create(device); err != nil {
		return nil, errors.NewInternalError("Failed to create device")
	}
	
	return device, nil
}

// GetDevice gets a device by ID
func (s *DeviceService) GetDevice(id uuid.UUID) (*models.Device, error) {
	device, err := s.deviceRepo.GetByID(id)
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, errors.NewNotFoundError("Device not found")
		}
		return nil, errors.NewInternalError("Failed to get device")
	}
	return device, nil
}

// GetDeviceByIdentifier gets a device by MAC or IMEI
func (s *DeviceService) GetDeviceByIdentifier(identifier string, idType string) (*models.Device, error) {
	var device *models.Device
	var err error
	
	switch idType {
	case "mac":
		if !ValidateMAC(identifier) {
			return nil, errors.NewValidationError("Invalid MAC address", nil)
		}
		device, err = s.deviceRepo.GetByMAC(NormalizeMAC(identifier))
	case "imei":
		if !ValidateIMEI(identifier) {
			return nil, errors.NewValidationError("Invalid IMEI", nil)
		}
		device, err = s.deviceRepo.GetByIMEI(identifier)
	default:
		return nil, errors.NewBadRequestError("Invalid identifier type. Must be 'mac' or 'imei'")
	}
	
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, errors.NewNotFoundError("Device not found")
		}
		return nil, errors.NewInternalError("Failed to get device")
	}
	
	return device, nil
}

// UpdateDeviceStatus updates device status and last seen time
func (s *DeviceService) UpdateDeviceStatus(deviceID uuid.UUID, status models.DeviceStatus) error {
	device, err := s.GetDevice(deviceID)
	if err != nil {
		return err
	}
	
	device.Status = status
	now := time.Now()
	device.LastSeenAt = &now
	
	if err := s.deviceRepo.Update(device); err != nil {
		return errors.NewInternalError("Failed to update device status")
	}
	
	return nil
}

// ListDevicesByOrganization lists devices by organization with filtering
func (s *DeviceService) ListDevicesByOrganization(orgID uuid.UUID, filters map[string]interface{}) ([]models.Device, error) {
	devices, err := s.deviceRepo.ListByOrg(orgID, filters)
	if err != nil {
		return nil, errors.NewInternalError("Failed to list devices")
	}
	return devices, nil
}

// ListDevicesByProject lists devices by project with filtering
func (s *DeviceService) ListDevicesByProject(projectID uuid.UUID, filters map[string]interface{}) ([]models.Device, error) {
	devices, err := s.deviceRepo.ListByProject(projectID, filters)
	if err != nil {
		return nil, errors.NewInternalError("Failed to list devices")
	}
	return devices, nil
}