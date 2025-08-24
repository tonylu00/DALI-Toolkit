package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/auth"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casbinx"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"go.uber.org/zap"
)

// ProjectHandler handles project-related API endpoints
type ProjectHandler struct {
	projectService      *services.ProjectService
	organizationService *services.OrganizationService
	enforcer            *casbinx.Enforcer
	logger              *zap.Logger
}

// NewProjectHandler creates a new project handler
func NewProjectHandler(projectService *services.ProjectService, organizationService *services.OrganizationService, enforcer *casbinx.Enforcer, logger *zap.Logger) *ProjectHandler {
	return &ProjectHandler{
		projectService:      projectService,
		organizationService: organizationService,
		enforcer:            enforcer,
		logger:              logger.With(zap.String("component", "project_handler")),
	}
}

// ListProjects lists projects for an organization
func (h *ProjectHandler) ListProjects(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	// Parse query parameters
	orgID := c.Query("org_id")

	// Use user's organization if not specified
	if orgID == "" {
		orgID = user.OrgID.String()
	}

	// Check if user can access the specified organization
	if !user.IsSuperUser && orgID != user.OrgID.String() {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to organization"})
		return
	}

	orgUUID, err := uuid.Parse(orgID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid org_id"})
		return
	}

	projects, err := h.projectService.ListProjectsByOrg(orgUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list projects"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"projects": projects})
}

// GetProject gets a project by ID
func (h *ProjectHandler) GetProject(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	projectID := c.Param("id")
	projectUUID, err := uuid.Parse(projectID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid project ID"})
		return
	}

	// Check permissions
	domain := "project:" + projectUUID.String()
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "projects", "read")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to project"})
		return
	}

	project, err := h.projectService.GetProject(projectUUID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Project not found"})
		return
	}
	c.JSON(http.StatusOK, project)
}

// CreateProject creates a new project
func (h *ProjectHandler) CreateProject(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	var req struct {
		Name   string `json:"name" binding:"required"`
		Remark string `json:"remark,omitempty"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check permissions for organization
	domain := "org:" + user.OrgID.String()
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "projects", "write")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to create projects"})
		return
	}

	project, err := h.projectService.CreateProject(user.OrgID, req.Name, req.Remark, uuid.MustParse(user.UserID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create project"})
		return
	}
	c.JSON(http.StatusCreated, project)
}

// UpdateProject updates a project
func (h *ProjectHandler) UpdateProject(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	projectID := c.Param("id")
	projectUUID, err := uuid.Parse(projectID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid project ID"})
		return
	}

	var req struct {
		Name   string `json:"name,omitempty"`
		Remark string `json:"remark,omitempty"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check permissions
	domain := "project:" + projectUUID.String()
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "projects", "write")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to project"})
		return
	}

	project, err := h.projectService.UpdateProject(projectUUID, req.Name, req.Remark)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update project"})
		return
	}
	c.JSON(http.StatusOK, project)
}

// DeleteProject deletes a project
func (h *ProjectHandler) DeleteProject(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	projectID := c.Param("id")
	projectUUID, err := uuid.Parse(projectID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid project ID"})
		return
	}

	// Check permissions
	domain := "project:" + projectUUID.String()
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "projects", "manage")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to project"})
		return
	}

	if err := h.projectService.DeleteProject(projectUUID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete project"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Project deleted"})
}
