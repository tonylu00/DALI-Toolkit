package services

import (
	"fmt"
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

// Service errors
var (
	ErrDeviceNotFound = errors.NewNotFoundError("Device not found")
)

// NewDeviceService creates a new device service
func NewDeviceService(db *gorm.DB) *DeviceService {
	return &DeviceService{
		deviceRepo: store.NewDeviceRepository(db),
	}
}

// NormalizeMAC normalizes MAC address to uppercase 12-character hex string
func NormalizeMAC(mac string) (string, error) {
	// Remove common separators
	mac = strings.ReplaceAll(mac, ":", "")
	mac = strings.ReplaceAll(mac, "-", "")
	mac = strings.ReplaceAll(mac, ".", "")
	mac = strings.ReplaceAll(mac, " ", "")

	// Convert to uppercase
	mac = strings.ToUpper(mac)

	// Validate length
	if len(mac) != 12 {
		return "", fmt.Errorf("MAC address must be 12 characters, got %d", len(mac))
	}

	// Validate hex characters
	for _, char := range mac {
		if !((char >= '0' && char <= '9') || (char >= 'A' && char <= 'F')) {
			return "", fmt.Errorf("MAC address contains invalid character: %c", char)
		}
	}

	return mac, nil
}

// NormalizeIMEI normalizes IMEI (14-16 digits)
func NormalizeIMEI(imei string) (string, error) {
	// IMEI should only contain digits, validate first
	for _, char := range imei {
		if char < '0' || char > '9' {
			return "", fmt.Errorf("IMEI contains invalid character: %c", char)
		}
	}

	// Validate length
	if len(imei) < 14 || len(imei) > 16 {
		return "", fmt.Errorf("IMEI must be 14-16 digits, got %d", len(imei))
	}

	return imei, nil
}

// ValidateIMEI validates IMEI (14-16 digits)
func ValidateIMEI(imei string) bool {
	_, err := NormalizeIMEI(imei)
	return err == nil
}

// ValidateMAC validates MAC address (12 hex characters)
func ValidateMAC(mac string) bool {
	_, err := NormalizeMAC(mac)
	return err == nil
}

// CreateDevice creates a new device
func (s *DeviceService) CreateDevice(mac string, imei *string, deviceType models.DeviceType, projectID uuid.UUID, partitionID *uuid.UUID, displayName string) (*models.Device, error) {
	var normalizedMAC string
	var err error
	if mac != "" {
		normalizedMAC, err = NormalizeMAC(mac)
		if err != nil {
			return nil, errors.NewValidationError("Invalid MAC address", map[string]interface{}{
				"mac": err.Error(),
			})
		}
	}

	// Validate IMEI if provided
	var normalizedIMEI *string
	if imei != nil && *imei != "" {
		normalized, err := NormalizeIMEI(*imei)
		if err != nil {
			return nil, errors.NewValidationError("Invalid IMEI", map[string]interface{}{
				"imei": err.Error(),
			})
		}
		normalizedIMEI = &normalized
	}

	// Check if device already exists
	if normalizedMAC != "" {
		existing, err := s.deviceRepo.GetByMAC(normalizedMAC)
		if err == nil && existing != nil {
			return nil, errors.NewConflictError("Device with this MAC already exists")
		}
	}

	if normalizedIMEI != nil {
		if existingByIMEI, err := s.deviceRepo.GetByIMEI(*normalizedIMEI); err == nil && existingByIMEI != nil {
			return nil, errors.NewConflictError("Device with this IMEI already exists")
		}
	}

	device := &models.Device{
		BaseModel:   models.BaseModel{ID: uuid.New()},
		MAC:         normalizedMAC,
		IMEI:        normalizedIMEI,
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
		normalizedMAC, normErr := NormalizeMAC(identifier)
		if normErr != nil {
			return nil, errors.NewValidationError("Invalid MAC address", map[string]interface{}{
				"mac": normErr.Error(),
			})
		}
		device, err = s.deviceRepo.GetByMAC(normalizedMAC)
	case "imei":
		normalizedIMEI, normErr := NormalizeIMEI(identifier)
		if normErr != nil {
			return nil, errors.NewValidationError("Invalid IMEI", map[string]interface{}{
				"imei": normErr.Error(),
			})
		}
		device, err = s.deviceRepo.GetByIMEI(normalizedIMEI)
	default:
		return nil, errors.NewBadRequestError("Invalid identifier type. Must be 'mac' or 'imei'")
	}

	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, ErrDeviceNotFound
		}
		return nil, errors.NewInternalError("Failed to get device")
	}

	return device, nil
}

// GetDeviceByID gets a device by MAC or IMEI with proper error handling
func (s *DeviceService) GetDeviceByID(identifier string, idType string) (*models.Device, error) {
	return s.GetDeviceByIdentifier(identifier, idType)
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

// UpdateDevice persists device changes
func (s *DeviceService) UpdateDevice(device *models.Device) error {
	if err := s.deviceRepo.Update(device); err != nil {
		return errors.NewInternalError("Failed to update device")
	}
	return nil
}

// FindOrCreateForRegistration finds an existing device by MAC/IMEI; if not found and factory mode allows, creates one.
// Inputs:
// - macRaw: string from MQTT password or topic; optional but recommended
// - imeiRaw: optional IMEI from payload
// - displayName: optional
// - defaultProjectID: UUID string of project to attach when creating
// - allowCreate: if false, do not create when not found
// Returns device and a boolean created flag
func (s *DeviceService) FindOrCreateForRegistration(macRaw string, imeiRaw *string, displayName string, deviceType models.DeviceType, defaultProjectID string, allowCreate bool) (*models.Device, bool, error) {
	var mac string
	var imei *string
	var err error

	if macRaw != "" {
		if mac, err = NormalizeMAC(macRaw); err != nil {
			return nil, false, errors.NewValidationError("Invalid MAC address", map[string]interface{}{"mac": err.Error()})
		}
	}
	if imeiRaw != nil && *imeiRaw != "" {
		normalized, e := NormalizeIMEI(*imeiRaw)
		if e != nil {
			return nil, false, errors.NewValidationError("Invalid IMEI", map[string]interface{}{"imei": e.Error()})
		}
		imei = &normalized
	}

	// Try by MAC first
	if mac != "" {
		if dev, err := s.deviceRepo.GetByMAC(mac); err == nil && dev != nil {
			// Update optional fields if empty
			changed := false
			if dev.IMEI == nil && imei != nil {
				dev.IMEI = imei
				changed = true
			}
			if dev.DisplayName == "" && displayName != "" {
				dev.DisplayName = displayName
				changed = true
			}
			if changed {
				if uerr := s.deviceRepo.Update(dev); uerr != nil {
					return nil, false, errors.NewInternalError("Failed to update device")
				}
			}
			return dev, false, nil
		}
	}

	// Try by IMEI
	if imei != nil {
		if dev, err := s.deviceRepo.GetByIMEI(*imei); err == nil && dev != nil {
			// Backfill MAC if missing
			if dev.MAC == "" && mac != "" {
				dev.MAC = mac
				if uerr := s.deviceRepo.Update(dev); uerr != nil {
					return nil, false, errors.NewInternalError("Failed to update device")
				}
			}
			return dev, false, nil
		}
	}

	// Not found
	if !allowCreate {
		return nil, false, ErrDeviceNotFound
	}
	// Require default project id
	if defaultProjectID == "" {
		return nil, false, errors.NewBadRequestError("Factory default project not configured")
	}
	projID, err := uuid.Parse(defaultProjectID)
	if err != nil {
		return nil, false, errors.NewValidationError("Invalid default project id", map[string]interface{}{"project_id": err.Error()})
	}

	// Create device with available identifiers
	var imeiForCreate *string
	if imei != nil {
		imeiForCreate = imei
	}
	device, cerr := s.CreateDevice(mac, imeiForCreate, deviceType, projID, nil, chooseDisplayName(displayName, mac, imeiForCreate))
	if cerr != nil {
		return nil, false, cerr
	}
	return device, true, nil
}

func chooseDisplayName(name, mac string, imei *string) string {
	if name != "" {
		return name
	}
	if mac != "" {
		return mac
	}
	if imei != nil {
		return *imei
	}
	return "device"
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
