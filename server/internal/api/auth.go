package api

import (
	"net/http"
	"net/url"
	"time"

	"server/internal/auth"
	"server/internal/casdoor"

	"github.com/gin-gonic/gin"
)

// AuthHandler exposes minimal auth endpoints for web login flow
type AuthHandler struct {
	authMW  *auth.Middleware
	casdoor *casdoor.Client
}

func NewAuthHandler(authMW *auth.Middleware, cas *casdoor.Client) *AuthHandler {
	return &AuthHandler{authMW: authMW, casdoor: cas}
}

// RegisterRoutes registers /api/v1/auth/* routes
func (h *AuthHandler) RegisterRoutes(r *gin.RouterGroup) {
	grp := r.Group("/auth")
	{
		grp.GET("/login", h.Login)
		grp.GET("/callback", h.Callback)
		grp.GET("/me", h.authMW.AuthRequired(), h.Me)
		grp.POST("/logout", h.Logout)
	}
}

// Login redirects to Casdoor sign-in, preserving redirect URL
func (h *AuthHandler) Login(c *gin.Context) {
	redirect := c.Query("redirect")
	if redirect == "" {
		redirect = "/app/"
	}
	// State carries return URL; in production, sign and bind to session/CSRF
	state := redirect
	signinURL := h.casdoor.GetSigninURL(h.getCallbackURL(c)) + "&state=" + url.QueryEscape(state)
	c.Redirect(http.StatusFound, signinURL)
}

// Callback handles Casdoor OAuth callback
func (h *AuthHandler) Callback(c *gin.Context) {
	code := c.Query("code")
	state := c.Query("state")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing code"})
		return
	}
	token, err := h.casdoor.ExchangeOAuthToken(code, state)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "oauth exchange failed"})
		return
	}
	// Validate token and derive user
	claims, err := h.casdoor.ParseClaims(token.AccessToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "token invalid, parse failed: " + err.Error()})
		return
	}
	userCtx := &auth.UserContext{
		UserID:       claims.Id,
		Username:     claims.Name,
		Email:        claims.Email,
		Organization: claims.Owner,
		Groups:       claims.Groups,
	}
	// Set httpOnly cookie as a lightweight session for web
	cookieName := "dt_access_token"
	maxAge := int(time.Until(time.Now().Add(2 * time.Hour)).Seconds())
	if token.Expiry.After(time.Now()) {
		maxAge = int(time.Until(token.Expiry).Seconds())
	}
	c.SetCookie(cookieName, token.AccessToken, maxAge, "/", "", false, true)
	// Optionally set user hints headers
	_ = userCtx
	// Redirect back
	redirect := state
	if redirect == "" {
		redirect = "/app/"
	}
	c.Redirect(http.StatusFound, redirect)
}

// Me returns current user info
func (h *AuthHandler) Me(c *gin.Context) {
	user := auth.GetUserContext(c)
	c.JSON(http.StatusOK, user)
}

// Logout clears cookie
func (h *AuthHandler) Logout(c *gin.Context) {
	c.SetCookie("dt_access_token", "", -1, "/", "", false, true)
	c.JSON(http.StatusOK, gin.H{"message": "logged out"})
}

// getCallbackURL builds absolute callback URL based on request host
func (h *AuthHandler) getCallbackURL(c *gin.Context) string {
	scheme := "http"
	if c.Request.TLS != nil || c.Request.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	host := c.Request.Host
	return scheme + "://" + host + "/api/v1/auth/callback"
}

// no extra helpers
