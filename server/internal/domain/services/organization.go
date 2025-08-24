package services

import (
	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"github.com/tonylu00/DALI-Toolkit/server/internal/store"
	"github.com/tonylu00/DALI-Toolkit/server/pkg/errors"
	"gorm.io/gorm"
)

// OrganizationService handles organization business logic
type OrganizationService struct {
	orgRepo *store.OrganizationRepository
}

// NewOrganizationService creates a new organization service
func NewOrganizationService(db *gorm.DB) *OrganizationService {
	return &OrganizationService{
		orgRepo: store.NewOrganizationRepository(db),
	}
}

// ProjectService handles project business logic
type ProjectService struct {
	projRepo *store.ProjectRepository
}

// NewProjectService creates a new project service
func NewProjectService(db *gorm.DB) *ProjectService {
	return &ProjectService{
		projRepo: store.NewProjectRepository(db),
	}
}

// CreateProject creates a new project in org
func (s *ProjectService) CreateProject(orgID uuid.UUID, name, remark string, createdBy uuid.UUID) (*models.Project, error) {
	project := &models.Project{
		BaseModel: models.BaseModel{ID: uuid.New()},
		OrgID:     orgID,
		Name:      name,
		Remark:    remark,
		CreatedBy: createdBy,
	}
	if err := s.projRepo.Create(project); err != nil {
		return nil, errors.NewInternalError("Failed to create project")
	}
	return project, nil
}

// GetProject returns a project by ID
func (s *ProjectService) GetProject(id uuid.UUID) (*models.Project, error) {
	proj, err := s.projRepo.GetByID(id)
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, errors.NewNotFoundError("Project not found")
		}
		return nil, errors.NewInternalError("Failed to get project")
	}
	return proj, nil
}

// ListProjectsByOrg lists projects by organization
func (s *ProjectService) ListProjectsByOrg(orgID uuid.UUID) ([]models.Project, error) {
	projects, err := s.projRepo.ListByOrg(orgID)
	if err != nil {
		return nil, errors.NewInternalError("Failed to list projects")
	}
	return projects, nil
}

// UpdateProject updates name/remark
func (s *ProjectService) UpdateProject(id uuid.UUID, name, remark string) (*models.Project, error) {
	proj, err := s.GetProject(id)
	if err != nil {
		return nil, err
	}
	if name != "" {
		proj.Name = name
	}
	if remark != "" {
		proj.Remark = remark
	}
	if err := s.projRepo.Update(proj); err != nil {
		return nil, errors.NewInternalError("Failed to update project")
	}
	return proj, nil
}

// DeleteProject deletes a project
func (s *ProjectService) DeleteProject(id uuid.UUID) error {
	// Ensure exists
	if _, err := s.GetProject(id); err != nil {
		return err
	}
	if err := s.projRepo.Delete(id); err != nil {
		return errors.NewInternalError("Failed to delete project")
	}
	return nil
}

// CreateOrganization creates a new organization
func (s *OrganizationService) CreateOrganization(casdoorOrg, name string) (*models.Organization, error) {
	// Check if organization already exists
	existing, err := s.orgRepo.GetByCasdoorOrg(casdoorOrg)
	if err == nil && existing != nil {
		return nil, errors.NewConflictError("Organization already exists")
	}

	org := &models.Organization{
		BaseModel:  models.BaseModel{ID: uuid.New()},
		CasdoorOrg: casdoorOrg,
		Name:       name,
	}

	if err := s.orgRepo.Create(org); err != nil {
		return nil, errors.NewInternalError("Failed to create organization")
	}

	return org, nil
}

// GetOrganization gets an organization by ID
func (s *OrganizationService) GetOrganization(id uuid.UUID) (*models.Organization, error) {
	org, err := s.orgRepo.GetByID(id)
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, errors.NewNotFoundError("Organization not found")
		}
		return nil, errors.NewInternalError("Failed to get organization")
	}
	return org, nil
}

// GetOrganizationByCasdoor gets an organization by Casdoor org name
func (s *OrganizationService) GetOrganizationByCasdoor(casdoorOrg string) (*models.Organization, error) {
	org, err := s.orgRepo.GetByCasdoorOrg(casdoorOrg)
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, errors.NewNotFoundError("Organization not found")
		}
		return nil, errors.NewInternalError("Failed to get organization")
	}
	return org, nil
}

// ListOrganizations lists all organizations
func (s *OrganizationService) ListOrganizations() ([]models.Organization, error) {
	orgs, err := s.orgRepo.List()
	if err != nil {
		return nil, errors.NewInternalError("Failed to list organizations")
	}
	return orgs, nil
}

// UpdateOrganization updates an organization
func (s *OrganizationService) UpdateOrganization(id uuid.UUID, name string) (*models.Organization, error) {
	org, err := s.GetOrganization(id)
	if err != nil {
		return nil, err
	}

	org.Name = name
	if err := s.orgRepo.Update(org); err != nil {
		return nil, errors.NewInternalError("Failed to update organization")
	}

	return org, nil
}

// DeleteOrganization deletes an organization
func (s *OrganizationService) DeleteOrganization(id uuid.UUID) error {
	if _, err := s.GetOrganization(id); err != nil {
		return err
	}

	if err := s.orgRepo.Delete(id); err != nil {
		return errors.NewInternalError("Failed to delete organization")
	}

	return nil
}
