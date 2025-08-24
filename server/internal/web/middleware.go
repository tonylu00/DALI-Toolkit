package web

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	
	"github.com/tonylu00/DALI-Toolkit/server/internal/auth"
)

// WebAuthMiddleware provides authentication for web app routes
func WebAuthMiddleware(authService *auth.Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip authentication for static assets
		if isStaticAsset(c.Request.URL.Path) {
			c.Next()
			return
		}

		// Try session-based authentication first (for browser)
		if user := getSessionUser(c); user != nil {
			c.Set("user", user)
			c.Next()
			return
		}

		// Try Bearer token authentication (for API)
		authHeader := c.GetHeader("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token := strings.TrimPrefix(authHeader, "Bearer ")
			if user, err := authService.ValidateToken(token); err == nil {
				c.Set("user", user)
				c.Next()
				return
			}
		}

		// No valid authentication found
		handleUnauthenticated(c)
	}
}

// isStaticAsset checks if the request is for a static asset
func isStaticAsset(path string) bool {
	staticExtensions := []string{
		".js", ".css", ".html", ".png", ".jpg", ".jpeg", ".gif", ".svg", 
		".ico", ".woff", ".woff2", ".ttf", ".eot", ".json", ".txt",
	}
	
	path = strings.ToLower(path)
	for _, ext := range staticExtensions {
		if strings.HasSuffix(path, ext) {
			return true
		}
	}
	
	// Also consider paths with these patterns as static
	staticPaths := []string{
		"/assets/", "/canvaskit/", "/favicon.png", "/manifest.json",
	}
	
	for _, staticPath := range staticPaths {
		if strings.Contains(path, staticPath) {
			return true
		}
	}
	
	return false
}

// getSessionUser retrieves user from session (placeholder implementation)
func getSessionUser(c *gin.Context) interface{} {
	// TODO: Implement session-based authentication
	// This would typically check secure HTTP-only cookies
	// and validate session tokens stored in Redis/database
	
	// For now, return nil to fall back to Bearer token auth
	return nil
}

// handleUnauthenticated handles unauthenticated requests
func handleUnauthenticated(c *gin.Context) {
	// For API requests, return JSON error
	if strings.HasPrefix(c.Request.Header.Get("Accept"), "application/json") || 
	   strings.Contains(c.Request.Header.Get("Content-Type"), "application/json") {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error": gin.H{
				"code":    "AUTHENTICATION_REQUIRED",
				"message": "Authentication required to access this resource",
			},
		})
		c.Abort()
		return
	}

	// For browser requests, redirect to login or return login page
	if isWebAppRequest(c.Request.URL.Path) {
		// Return a simple login redirect page
		c.Header("Content-Type", "text/html")
		c.String(http.StatusUnauthorized, `
<!DOCTYPE html>
<html>
<head>
    <title>Authentication Required</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .container { max-width: 400px; margin: 0 auto; }
        .btn { background: #007bff; color: white; padding: 10px 20px; 
               text-decoration: none; border-radius: 5px; display: inline-block; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Authentication Required</h1>
        <p>You need to authenticate to access the DALI-Toolkit web application.</p>
        <a href="/api/v1/auth/login" class="btn">Login with Casdoor</a>
    </div>
    <script>
        // Auto-redirect if this is embedded in the Flutter app
        if (window.location.pathname.startsWith('/app')) {
            setTimeout(() => {
                window.location.href = '/api/v1/auth/login?redirect=' + encodeURIComponent(window.location.href);
            }, 2000);
        }
    </script>
</body>
</html>`)
		c.Abort()
		return
	}

	// Default JSON response
	c.JSON(http.StatusUnauthorized, gin.H{
		"error": gin.H{
			"code":    "AUTHENTICATION_REQUIRED", 
			"message": "Authentication required",
		},
	})
	c.Abort()
}

// isWebAppRequest checks if this is a request for the web app
func isWebAppRequest(path string) bool {
	return strings.HasPrefix(path, "/app")
}

// AutoLoginMiddleware provides automatic login for Flutter web integration
func AutoLoginMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip for non-app routes
		if !strings.HasPrefix(c.Request.URL.Path, "/app") {
			c.Next()
			return
		}

		user, exists := c.Get("user")
		if !exists || user == nil {
			c.Next()
			return
		}

		// Inject user info into HTML for Flutter web app
		if strings.HasSuffix(c.Request.URL.Path, "/") || 
		   strings.HasSuffix(c.Request.URL.Path, "/index.html") ||
		   c.Request.URL.Path == "/app" {
			
			// This will be handled by the static file server, but we can
			// add headers for the Flutter app to detect authentication status
			c.Header("X-User-Authenticated", "true")
			c.Header("X-User-Info", "available") // Flutter can call /api/v1/auth/me
		}

		c.Next()
	}
}

// CORSMiddleware provides CORS support for web app
func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")
		
		// Allow requests from same origin and local development
		if origin == "" || 
		   strings.HasPrefix(origin, "http://localhost") ||
		   strings.HasPrefix(origin, "http://127.0.0.1") ||
		   strings.HasSuffix(origin, c.Request.Host) {
			
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Credentials", "true")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Accept, Authorization, Content-Type, X-CSRF-Token")
			c.Header("Access-Control-Max-Age", "86400")
		}

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusOK)
			return
		}

		c.Next()
	}
}

// CSPMiddleware adds Content Security Policy headers
func CSPMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// For web app routes, add CSP headers
		if strings.HasPrefix(c.Request.URL.Path, "/app") {
			csp := "default-src 'self'; " +
				"script-src 'self' 'unsafe-inline' 'unsafe-eval'; " +
				"style-src 'self' 'unsafe-inline'; " +
				"img-src 'self' data: https:; " +
				"font-src 'self' data:; " +
				"connect-src 'self' ws: wss:; " +
				"frame-ancestors 'none'"
			
			c.Header("Content-Security-Policy", csp)
			c.Header("X-Frame-Options", "DENY")
			c.Header("X-Content-Type-Options", "nosniff")
			c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		}
		
		c.Next()
	}
}

// RequestLoggingMiddleware logs web app requests
func RequestLoggingMiddleware() gin.HandlerFunc {
	return gin.LoggerWithConfig(gin.LoggerConfig{
		Formatter: func(param gin.LogFormatterParams) string {
			if strings.HasPrefix(param.Path, "/app") {
				// Use gin's built-in logging for now
				// TODO: integrate with structured logger
			}
			return ""
		},
	})
}