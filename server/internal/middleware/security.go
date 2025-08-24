package middleware

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// RateLimitMiddleware provides rate limiting
func RateLimitMiddleware() gin.HandlerFunc {
	// Create a rate limiter that allows 100 requests per minute
	limiter := rate.NewLimiter(rate.Every(time.Minute/100), 100)

	return func(c *gin.Context) {
		if !limiter.Allow() {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": gin.H{
					"code":        "RATE_LIMIT_EXCEEDED",
					"message":     "Too many requests",
					"retry_after": "60s",
				},
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

// SecurityHeadersMiddleware adds security headers
func SecurityHeadersMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Basic security headers
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("X-XSS-Protection", "1; mode=block")
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")

		// Remove server information
		c.Header("Server", "")

		// Add security headers for API endpoints
		if c.Request.URL.Path != "/" && c.Request.URL.Path != "/health" {
			c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
			c.Header("Pragma", "no-cache")
			c.Header("Expires", "0")
		}

		c.Next()
	}
}

// RequestSizeMiddleware limits request body size
func RequestSizeMiddleware(maxSize int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.ContentLength > maxSize {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{
				"error": gin.H{
					"code":    "REQUEST_TOO_LARGE",
					"message": fmt.Sprintf("Request body too large. Maximum size: %d bytes", maxSize),
				},
			})
			c.Abort()
			return
		}

		// Limit request body size
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxSize)
		c.Next()
	}
}

// TimeoutMiddleware adds request timeout
func TimeoutMiddleware(timeout time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Create a context with timeout
		ctx, cancel := context.WithTimeout(c.Request.Context(), timeout)
		defer cancel()

		// Replace the request context
		c.Request = c.Request.WithContext(ctx)

		// Use a channel to wait for the request to complete or timeout
		done := make(chan struct{})
		go func() {
			defer close(done)
			c.Next()
		}()

		select {
		case <-done:
			// Request completed normally
		case <-ctx.Done():
			// Request timed out
			if ctx.Err() == context.DeadlineExceeded {
				c.JSON(http.StatusRequestTimeout, gin.H{
					"error": gin.H{
						"code":    "REQUEST_TIMEOUT",
						"message": "Request timed out",
					},
				})
				c.Abort()
			}
		}
	}
}

// CSRFMiddleware provides basic CSRF protection
func CSRFMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip CSRF for GET, HEAD, OPTIONS requests
		if c.Request.Method == "GET" || c.Request.Method == "HEAD" || c.Request.Method == "OPTIONS" {
			c.Next()
			return
		}

		// Check for CSRF token in header or form
		token := c.GetHeader("X-CSRF-Token")
		if token == "" {
			token = c.PostForm("_csrf_token")
		}

		// For now, just check that a token is present
		// In production, you'd validate against a secure token
		if token == "" {
			// Only enforce CSRF for non-API requests or when Origin header suggests browser
			origin := c.GetHeader("Origin")

			if origin != "" && !c.GetBool("skip_csrf") {
				c.JSON(http.StatusForbidden, gin.H{
					"error": gin.H{
						"code":    "CSRF_TOKEN_REQUIRED",
						"message": "CSRF token required for this request",
					},
				})
				c.Abort()
				return
			}
		}

		c.Next()
	}
}

// AuditLogMiddleware logs security-relevant events
func AuditLogMiddleware() gin.HandlerFunc {
	return gin.LoggerWithConfig(gin.LoggerConfig{
		Formatter: func(param gin.LogFormatterParams) string {
			// Only log certain paths for security audit
			if shouldAuditPath(param.Path) {
				return fmt.Sprintf("[AUDIT] %s %s %d %s %s %s\n",
					param.TimeStamp.Format("2006-01-02 15:04:05"),
					param.Method,
					param.StatusCode,
					param.Path,
					param.ClientIP,
					param.Request.UserAgent(),
				)
			}
			return ""
		},
	})
}

// shouldAuditPath determines if a path should be audited
func shouldAuditPath(path string) bool {
	auditPaths := []string{
		"/api/v1/auth/",
		"/api/v1/devices",
		"/api/v1/permissions",
		"/api/v1/admin/",
	}

	for _, auditPath := range auditPaths {
		if len(path) >= len(auditPath) && path[:len(auditPath)] == auditPath {
			return true
		}
	}

	return false
}
