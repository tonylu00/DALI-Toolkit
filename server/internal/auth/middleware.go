package auth

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casdoor"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casbinx"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"github.com/tonylu00/DALI-Toolkit/server/pkg/errors"
	"go.uber.org/zap"
)

// UserContext represents the current user context
type UserContext struct {
	UserID       string   `json:"user_id"`
	Username     string   `json:"username"`
	Email        string   `json:"email"`
	Organization string   `json:"organization"`
	OrgID        uuid.UUID `json:"org_id"`
	Roles        []string `json:"roles"`
	Groups       []string `json:"groups"`
	IsSuperUser  bool     `json:"is_super_user"`
}

// Middleware provides authentication and authorization middleware
type Middleware struct {
	casdoorClient *casdoor.Client
	enforcer      *casbinx.Enforcer
	orgService    *services.OrganizationService
	logger        *zap.Logger
}

// Service provides authentication services (alias for Middleware for compatibility)
type Service = Middleware

// New creates a new auth middleware
func New(
	casdoorClient *casdoor.Client,
	enforcer *casbinx.Enforcer,
	orgService *services.OrganizationService,
	logger *zap.Logger,
) *Middleware {
	return &Middleware{
		casdoorClient: casdoorClient,
		enforcer:      enforcer,
		orgService:    orgService,
		logger:        logger,
	}
}

// extractToken extracts Bearer token from Authorization header
func extractToken(c *gin.Context) string {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		return ""
	}

	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
		return ""
	}

	return parts[1]
}

// AuthRequired middleware that requires valid authentication
func (m *Middleware) AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := extractToken(c)
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Missing or invalid authorization header",
			})
			c.Abort()
			return
		}

		// Verify token with Casdoor
		userInfo, err := m.casdoorClient.VerifyToken(token)
		if err != nil {
			m.logger.Warn("Token verification failed", zap.Error(err))
			if appErr, ok := err.(*errors.AppError); ok {
				c.JSON(appErr.HTTPStatus, gin.H{"error": appErr.Message})
			} else {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
			}
			c.Abort()
			return
		}

		// Get organization info
		org, err := m.orgService.GetOrganizationByCasdoor(userInfo.Organization)
		if err != nil {
			m.logger.Warn("Organization not found", zap.String("org", userInfo.Organization))
			c.JSON(http.StatusForbidden, gin.H{
				"error": "Organization not found or not authorized",
			})
			c.Abort()
			return
		}

		// Check if user is super user
		isSuperUser := m.casdoorClient.IsSuperOrganization(userInfo.Organization) ||
			m.enforcer.IsSuperUser(userInfo.ID)

		// Build user context
		userCtx := &UserContext{
			UserID:       userInfo.ID,
			Username:     userInfo.Username,
			Email:        userInfo.Email,
			Organization: userInfo.Organization,
			OrgID:        org.ID,
			Roles:        userInfo.Roles,
			Groups:       userInfo.Groups,
			IsSuperUser:  isSuperUser,
		}

		// Store user context in gin context
		c.Set("user", userCtx)
		c.Next()
	}
}

// RequirePermission middleware that checks specific permissions
func (m *Middleware) RequirePermission(resource, action string) gin.HandlerFunc {
	return func(c *gin.Context) {
		userCtx := GetUserContext(c)
		if userCtx == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
			c.Abort()
			return
		}

		// Super users can do anything
		if userCtx.IsSuperUser {
			c.Next()
			return
		}

		// Build domain based on organization
		domain := casbinx.BuildDomain("org", userCtx.OrgID.String())

		// Check permission
		allowed, err := m.enforcer.Enforce(userCtx.UserID, domain, resource, action)
		if err != nil {
			m.logger.Error("Permission check failed", zap.Error(err))
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
			c.Abort()
			return
		}

		if !allowed {
			m.logger.Warn("Permission denied",
				zap.String("user", userCtx.UserID),
				zap.String("domain", domain),
				zap.String("resource", resource),
				zap.String("action", action),
			)
			c.JSON(http.StatusForbidden, gin.H{"error": "Permission denied"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// RequireResourcePermission checks permission for a specific resource
func (m *Middleware) RequireResourcePermission(resourceType, action string) gin.HandlerFunc {
	return func(c *gin.Context) {
		userCtx := GetUserContext(c)
		if userCtx == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
			c.Abort()
			return
		}

		// Super users can do anything
		if userCtx.IsSuperUser {
			c.Next()
			return
		}

		// Get resource ID from URL parameters or body
		resourceID := c.Param("id")
		if resourceID == "" {
			resourceID = c.Param("resource_id")
		}

		if resourceID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Resource ID required"})
			c.Abort()
			return
		}

		// Build domain for specific resource
		domain := casbinx.BuildDomain(resourceType, resourceID)

		// Check permission
		allowed, err := m.enforcer.Enforce(userCtx.UserID, domain, resourceType, action)
		if err != nil {
			m.logger.Error("Permission check failed", zap.Error(err))
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
			c.Abort()
			return
		}

		if !allowed {
			// Also try organization-level permission
			orgDomain := casbinx.BuildDomain("org", userCtx.OrgID.String())
			allowed, err = m.enforcer.Enforce(userCtx.UserID, orgDomain, resourceType, action)
			if err != nil {
				m.logger.Error("Permission check failed", zap.Error(err))
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Permission check failed"})
				c.Abort()
				return
			}
		}

		if !allowed {
			c.JSON(http.StatusForbidden, gin.H{"error": "Permission denied"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// GetUserContext retrieves user context from gin context
func GetUserContext(c *gin.Context) *UserContext {
	if user, exists := c.Get("user"); exists {
		if userCtx, ok := user.(*UserContext); ok {
			return userCtx
		}
	}
	return nil
}

// RequireOrganization ensures user belongs to specified organization
func (m *Middleware) RequireOrganization(orgID string) gin.HandlerFunc {
	return func(c *gin.Context) {
		userCtx := GetUserContext(c)
		if userCtx == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
			c.Abort()
			return
		}

		// Super users can access any organization
		if userCtx.IsSuperUser {
			c.Next()
			return
		}

		if userCtx.OrgID.String() != orgID {
			c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to organization"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// ValidateToken validates a token and returns user context
func (m *Middleware) ValidateToken(token string) (*UserContext, error) {
	// Verify token with Casdoor
	userInfo, err := m.casdoorClient.VerifyToken(token)
	if err != nil {
		return nil, err
	}

	// Get organization info
	org, err := m.orgService.GetOrganizationByCasdoor(userInfo.Organization)
	if err != nil {
		return nil, err
	}

	// Check if user is super user
	isSuperUser := m.casdoorClient.IsSuperOrganization(userInfo.Organization) ||
		m.enforcer.IsSuperUser(userInfo.ID)

	// Build user context
	userCtx := &UserContext{
		UserID:       userInfo.ID,
		Username:     userInfo.Username,
		Email:        userInfo.Email,
		Organization: userInfo.Organization,
		OrgID:        org.ID,
		Roles:        userInfo.Roles,
		Groups:       userInfo.Groups,
		IsSuperUser:  isSuperUser,
	}

	return userCtx, nil
}