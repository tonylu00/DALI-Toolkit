package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/tonylu00/DALI-Toolkit/server/internal/auth"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casbinx"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"go.uber.org/zap"
)

// PermissionHandler handles permission-related API endpoints
type PermissionHandler struct {
	organizationService *services.OrganizationService
	enforcer           *casbinx.Enforcer
	logger             *zap.Logger
}

// NewPermissionHandler creates a new permission handler
func NewPermissionHandler(organizationService *services.OrganizationService, enforcer *casbinx.Enforcer, logger *zap.Logger) *PermissionHandler {
	return &PermissionHandler{
		organizationService: organizationService,
		enforcer:           enforcer,
		logger:             logger.With(zap.String("component", "permission_handler")),
	}
}

// ListRoles returns available roles in the system
func (h *PermissionHandler) ListRoles(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	// Define standard roles
	roles := []gin.H{
		{
			"name":        "org_admin",
			"description": "Organization administrator with full access",
			"scope":       "organization",
		},
		{
			"name":        "org_viewer",
			"description": "Organization viewer with read-only access",
			"scope":       "organization",
		},
		{
			"name":        "project_owner",
			"description": "Project owner with full project access",
			"scope":       "project",
		},
		{
			"name":        "project_admin",
			"description": "Project administrator with management access",
			"scope":       "project",
		},
		{
			"name":        "project_viewer",
			"description": "Project viewer with read-only access",
			"scope":       "project",
		},
		{
			"name":        "partition_admin",
			"description": "Partition administrator with management access",
			"scope":       "partition",
		},
		{
			"name":        "partition_viewer",
			"description": "Partition viewer with read-only access",
			"scope":       "partition",
		},
		{
			"name":        "device_owner",
			"description": "Device owner with full device access",
			"scope":       "device",
		},
		{
			"name":        "device_editor",
			"description": "Device editor with modification access",
			"scope":       "device",
		},
		{
			"name":        "device_viewer",
			"description": "Device viewer with read-only access",
			"scope":       "device",
		},
	}

	c.JSON(http.StatusOK, gin.H{
		"roles": roles,
	})
}

// ListSubjects lists subjects (users/groups) with permissions in a domain
func (h *PermissionHandler) ListSubjects(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	projectID := c.Query("project_id")
	partitionID := c.Query("partition_id")
	deviceMAC := c.Query("device_mac")

	// Determine domain
	var domain string
	if deviceMAC != "" {
		domain = "device:" + deviceMAC
	} else if partitionID != "" {
		domain = "partition:" + partitionID
	} else if projectID != "" {
		domain = "project:" + projectID
	} else {
		domain = "org:" + user.OrgID.String()
	}

	// Check if user can view permissions for this domain
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "permissions", "read")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to view permissions"})
		return
	}

	// Get grouping policies (user -> role mappings) for this domain
	groupings := h.enforcer.GetFilteredGroupingPolicy(2, domain)

	subjects := make([]gin.H, 0)
	for _, grouping := range groupings {
		if len(grouping) >= 3 {
			subjects = append(subjects, gin.H{
				"subject": grouping[0],
				"role":    grouping[1],
				"domain":  grouping[2],
			})
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"domain":   domain,
		"subjects": subjects,
	})
}

// GrantPermission grants a role to a subject in a domain
func (h *PermissionHandler) GrantPermission(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	var req struct {
		Domain  string `json:"domain" binding:"required"`
		Subject string `json:"subject" binding:"required"`
		Role    string `json:"role" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user can manage permissions for this domain
	allowed, err := h.enforcer.Enforce(user.UserID, req.Domain, "permissions", "manage")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to manage permissions"})
		return
	}

	// Add grouping policy (subject -> role in domain)
	success, err := h.enforcer.AddGroupingPolicy(req.Subject, req.Role, req.Domain)
	if err != nil {
		h.logger.Error("Failed to add grouping policy", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to grant permission"})
		return
	}

	if !success {
		c.JSON(http.StatusConflict, gin.H{"error": "Permission already exists"})
		return
	}

	h.logger.Info("Permission granted",
		zap.String("domain", req.Domain),
		zap.String("subject", req.Subject),
		zap.String("role", req.Role),
		zap.String("granted_by", user.UserID))

	c.JSON(http.StatusOK, gin.H{
		"message": "Permission granted successfully",
		"domain":  req.Domain,
		"subject": req.Subject,
		"role":    req.Role,
	})
}

// RevokePermission revokes a role from a subject in a domain
func (h *PermissionHandler) RevokePermission(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	var req struct {
		Domain  string `json:"domain" binding:"required"`
		Subject string `json:"subject" binding:"required"`
		Role    string `json:"role" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user can manage permissions for this domain
	allowed, err := h.enforcer.Enforce(user.UserID, req.Domain, "permissions", "manage")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to manage permissions"})
		return
	}

	// Remove grouping policy
	success, err := h.enforcer.RemoveGroupingPolicy(req.Subject, req.Role, req.Domain)
	if err != nil {
		h.logger.Error("Failed to remove grouping policy", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to revoke permission"})
		return
	}

	if !success {
		c.JSON(http.StatusNotFound, gin.H{"error": "Permission not found"})
		return
	}

	h.logger.Info("Permission revoked",
		zap.String("domain", req.Domain),
		zap.String("subject", req.Subject),
		zap.String("role", req.Role),
		zap.String("revoked_by", user.UserID))

	c.JSON(http.StatusOK, gin.H{
		"message": "Permission revoked successfully",
		"domain":  req.Domain,
		"subject": req.Subject,
		"role":    req.Role,
	})
}

// CheckPermission checks if a subject has permission for a specific action
func (h *PermissionHandler) CheckPermission(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	subject := c.Query("subject")
	domain := c.Query("domain")
	object := c.Query("object")
	action := c.Query("action")

	if subject == "" || domain == "" || object == "" || action == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "subject, domain, object, and action parameters are required",
		})
		return
	}

	// Check if user can view permissions for this domain
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "permissions", "read")
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to check permissions"})
		return
	}

	// Check the actual permission
	hasPermission, err := h.enforcer.Enforce(subject, domain, object, action)
	if err != nil {
		h.logger.Error("Permission check failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"subject":       subject,
		"domain":        domain,
		"object":        object,
		"action":        action,
		"has_permission": hasPermission,
	})
}