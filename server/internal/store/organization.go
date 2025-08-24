package store

import (
	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"gorm.io/gorm"
)

// OrganizationRepository handles organization data operations
type OrganizationRepository struct {
	db *gorm.DB
}

// NewOrganizationRepository creates a new organization repository
func NewOrganizationRepository(db *gorm.DB) *OrganizationRepository {
	return &OrganizationRepository{db: db}
}

// Create creates a new organization
func (r *OrganizationRepository) Create(org *models.Organization) error {
	return r.db.Create(org).Error
}

// GetByID gets an organization by ID
func (r *OrganizationRepository) GetByID(id uuid.UUID) (*models.Organization, error) {
	var org models.Organization
	err := r.db.First(&org, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &org, nil
}

// GetByCasdoorOrg gets an organization by Casdoor org name
func (r *OrganizationRepository) GetByCasdoorOrg(casdoorOrg string) (*models.Organization, error) {
	var org models.Organization
	err := r.db.First(&org, "casdoor_org = ?", casdoorOrg).Error
	if err != nil {
		return nil, err
	}
	return &org, nil
}

// List lists all organizations
func (r *OrganizationRepository) List() ([]models.Organization, error) {
	var orgs []models.Organization
	err := r.db.Find(&orgs).Error
	return orgs, err
}

// Update updates an organization
func (r *OrganizationRepository) Update(org *models.Organization) error {
	return r.db.Save(org).Error
}

// Delete deletes an organization
func (r *OrganizationRepository) Delete(id uuid.UUID) error {
	return r.db.Delete(&models.Organization{}, "id = ?", id).Error
}