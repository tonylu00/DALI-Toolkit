package casdoor

import (
	"context"
	"time"

	"github.com/casdoor/casdoor-go-sdk/casdoorsdk"
	"github.com/tonylu00/DALI-Toolkit/server/internal/config"
	"github.com/tonylu00/DALI-Toolkit/server/pkg/errors"
	"golang.org/x/oauth2"
)

// Client wraps Casdoor SDK functionality
type Client struct {
	client *casdoorsdk.Client
	config *config.Config
}

// UserInfo represents user information from Casdoor
type UserInfo struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Username     string   `json:"username"`
	Email        string   `json:"email"`
	Organization string   `json:"organization"`
	Roles        []string `json:"roles"`
	Groups       []string `json:"groups"`
}

// New creates a new Casdoor client
func New(cfg *config.Config) (*Client, error) {
	client := casdoorsdk.NewClient(
		cfg.CasdoorServerURL,
		cfg.CasdoorClientID,
		cfg.CasdoorClientSecret,
		cfg.CasdoorCertificate, // Certificate (PEM public key) required for JWT verify
		cfg.CasdoorOrg,
		cfg.CasdoorApp,
	)

	casdoorClient := &Client{
		client: client,
		config: cfg,
	}

	return casdoorClient, nil
}

// No JWKS fetching here; casdoor-go-sdk expects the app certificate to verify JWT.

// VerifyToken verifies a JWT token and returns user information
func (c *Client) VerifyToken(tokenString string) (*UserInfo, error) {
	// Use casdoor-go-sdk to parse and verify JWT using configured certificate
	claims, err := c.client.ParseJwtToken(tokenString)
	if err != nil {
		return nil, errors.NewUnauthorizedError("Invalid token")
	}

	// Basic expiry check (sdk already validates via jwt library)
	if claims.ExpiresAt != nil && time.Until(claims.ExpiresAt.Time) <= 0 {
		return nil, errors.NewUnauthorizedError("Token has expired")
	}

	// Map to UserInfo
	userInfo := &UserInfo{
		ID:           claims.Id,
		Name:         claims.DisplayName,
		Username:     claims.Name,
		Email:        claims.Email,
		Organization: claims.Owner,
		Groups:       claims.Groups,
	}
	// Roles mapping if available via permissions/roles
	if claims.Roles != nil {
		names := make([]string, 0, len(claims.Roles))
		for _, r := range claims.Roles {
			if r != nil && r.Name != "" {
				names = append(names, r.Name)
			}
		}
		userInfo.Roles = names
	}

	return userInfo, nil
}

// GetSigninURL builds Casdoor sign-in URL with redirect
func (c *Client) GetSigninURL(redirectURI string) string {
	return c.client.GetSigninUrl(redirectURI)
}

// ExchangeOAuthToken exchanges code+state for an OAuth token from Casdoor
func (c *Client) ExchangeOAuthToken(code, state string) (*oauth2.Token, error) {
	return c.client.GetOAuthToken(code, state)
}

// ParseClaims parses and verifies JWT access token and returns Casdoor claims
func (c *Client) ParseClaims(accessToken string) (*casdoorsdk.Claims, error) {
	return c.client.ParseJwtToken(accessToken)
}

// GetUsers fetches users from Casdoor organization
func (c *Client) GetUsers(ctx context.Context, orgName string) ([]UserInfo, error) {
	// Use SDK to get users
	users, err := c.client.GetUsers()
	if err != nil {
		return nil, errors.NewInternalError("Failed to fetch users from Casdoor")
	}

	result := make([]UserInfo, len(users))
	for i, user := range users {
		result[i] = UserInfo{
			ID:           user.Id,
			Name:         user.Name,
			Username:     user.Name, // Casdoor uses Name as username
			Email:        user.Email,
			Organization: user.Owner,
		}
	}

	return result, nil
}

// GetGroups fetches groups from Casdoor organization
func (c *Client) GetGroups(ctx context.Context, orgName string) ([]*casdoorsdk.Group, error) {
	groups, err := c.client.GetGroups()
	if err != nil {
		return nil, errors.NewInternalError("Failed to fetch groups from Casdoor")
	}

	return groups, nil
}

// SyncPolicies synchronizes authorization policies from Casdoor
func (c *Client) SyncPolicies(ctx context.Context) error {
	// This would fetch and synchronize policies from Casdoor
	// For now, this is a placeholder
	return nil
}

// IsSuperOrganization checks if the organization is a super organization
func (c *Client) IsSuperOrganization(orgName string) bool {
	return orgName == c.config.CasdoorSuperOrg
}
