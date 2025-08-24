package api

import (
	"net/http"
	"strconv"

	"server/internal/auth"
	"server/internal/casbinx"
	"server/internal/domain/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// AdminSettingsHandler exposes org settings & audit config APIs
type AdminSettingsHandler struct {
	settings *services.SettingService
	enforcer *casbinx.Enforcer
	logger   *zap.Logger
}

func NewAdminSettingsHandler(settings *services.SettingService, enforcer *casbinx.Enforcer, logger *zap.Logger) *AdminSettingsHandler {
	return &AdminSettingsHandler{settings: settings, enforcer: enforcer, logger: logger.With(zap.String("component", "admin_settings_handler"))}
}

// GET /api/v1/admin/orgs/:id/settings
func (h *AdminSettingsHandler) GetOrgSettings(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}
	orgID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid org id"})
		return
	}

	// Require admin/manage on org
	domain := "org:" + orgID.String()
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "settings", "read")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}
	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
		return
	}

	out, _ := h.settings.GetOrgSettings(c, orgID)
	c.JSON(http.StatusOK, out)
}

// PUT /api/v1/admin/orgs/:id/settings
func (h *AdminSettingsHandler) UpdateOrgSettings(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}
	orgID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid org id"})
		return
	}

	domain := "org:" + orgID.String()
	allowed, err := h.enforcer.Enforce(user.UserID, domain, "settings", "write")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
		return
	}
	if !allowed && !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
		return
	}

	var req services.OrgSettings
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.settings.SetOrgSettings(c, orgID, req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update settings"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "updated"})
}

// GET /api/v1/admin/audit/retention-days
func (h *AdminSettingsHandler) GetAuditRetention(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}
	// require super or global admin; keep simple: super only for now
	if !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
		return
	}
	days, _ := h.settings.GetAuditRetentionDays(c)
	c.JSON(http.StatusOK, gin.H{"retention_days": days})
}

// PUT /api/v1/admin/audit/retention-days
func (h *AdminSettingsHandler) SetAuditRetention(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}
	if !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
		return
	}
	var payload struct {
		RetentionDays int `json:"retention_days"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if payload.RetentionDays < 1 {
		payload.RetentionDays = 1
	}
	if err := h.settings.SetAuditRetentionDays(c, payload.RetentionDays); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update retention"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "updated"})
}

// POST /api/v1/admin/audit/purge?days=30
func (h *AdminSettingsHandler) PurgeAudit(c *gin.Context) {
	user := auth.GetUserContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}
	if !user.IsSuperUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
		return
	}
	days, _ := strconv.Atoi(c.DefaultQuery("days", "0"))
	n, err := h.settings.PurgeAudit(c, days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to purge"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"purged": n})
}
