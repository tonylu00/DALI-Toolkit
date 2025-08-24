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
	// projectService      *services.ProjectService  // TODO: Implement ProjectService
	organizationService *services.OrganizationService
	enforcer           *casbinx.Enforcer
	logger             *zap.Logger
}

// NewProjectHandler creates a new project handler
func NewProjectHandler(organizationService *services.OrganizationService, enforcer *casbinx.Enforcer, logger *zap.Logger) *ProjectHandler {
	return &ProjectHandler{
		// projectService:      projectService,  // TODO: Add when implemented
		organizationService: organizationService,
		enforcer:           enforcer,
		logger:             logger.With(zap.String("component", "project_handler")),
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

	// For now, return placeholder data since ProjectService is not implemented
	c.JSON(http.StatusOK, gin.H{
		"projects": []gin.H{},
		"org_id":   orgUUID,
		"message":  "Project service to be implemented",
	})
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

	// For now, return placeholder data
	c.JSON(http.StatusOK, gin.H{
		"id":      projectUUID,
		"message": "Project service to be implemented",
	})
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

	// For now, return placeholder response
	projectID := uuid.New()
	h.logger.Info("Project creation requested",
		zap.String("project_id", projectID.String()),
		zap.String("name", req.Name),
		zap.String("user_id", user.UserID))

	c.JSON(http.StatusCreated, gin.H{
		"id":      projectID,
		"name":    req.Name,
		"remark":  req.Remark,
		"message": "Project service to be implemented",
	})
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

	h.logger.Info("Project update requested",
		zap.String("project_id", projectUUID.String()),
		zap.String("user_id", user.UserID))

	c.JSON(http.StatusOK, gin.H{
		"id":      projectUUID,
		"message": "Project service to be implemented",
	})
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

	h.logger.Info("Project deletion requested",
		zap.String("project_id", projectUUID.String()),
		zap.String("user_id", user.UserID))

	c.JSON(http.StatusOK, gin.H{
		"message": "Project service to be implemented",
	})
}