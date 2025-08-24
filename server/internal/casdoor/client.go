package casdoor

import (
	"context"
	"time"

	"github.com/casdoor/casdoor-go-sdk/casdoorsdk"
	"github.com/golang-jwt/jwt/v4"
	"github.com/tonylu00/DALI-Toolkit/server/internal/config"
	"github.com/tonylu00/DALI-Toolkit/server/pkg/errors"
)

// Client wraps Casdoor SDK functionality
type Client struct {
	client    *casdoorsdk.Client
	config    *config.Config
	publicKey string
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
		"",    // Certificate (we'll use JWKS)
		cfg.CasdoorOrg,
		cfg.CasdoorApp,
	)

	casdoorClient := &Client{
		client: client,
		config: cfg,
	}

	// Get public key from JWKS endpoint
	if err := casdoorClient.refreshPublicKey(); err != nil {
		return nil, err
	}

	return casdoorClient, nil
}

// refreshPublicKey fetches the public key from Casdoor JWKS endpoint
func (c *Client) refreshPublicKey() error {
	// For now, we'll use a placeholder. In production, this should fetch from JWKS
	// endpoint: {casdoorServerURL}/.well-known/openid_configuration
	// Then fetch keys from jwks_uri
	c.publicKey = "" // Will be set from JWKS
	return nil
}

// VerifyToken verifies a JWT token and returns user information
func (c *Client) VerifyToken(tokenString string) (*UserInfo, error) {
	// Parse the token
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		// Validate the signing method
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, errors.NewUnauthorizedError("Unexpected signing method")
		}
		
		// For testing, we'll return a dummy key. In production, use JWKS
		// return jwt.ParseRSAPublicKeyFromPEM([]byte(c.publicKey))
		return []byte("test-secret"), nil // Temporary for development
	})

	if err != nil {
		return nil, errors.NewUnauthorizedError("Invalid token")
	}

	if !token.Valid {
		return nil, errors.NewUnauthorizedError("Token is not valid")
	}

	// Extract claims
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil, errors.NewUnauthorizedError("Invalid token claims")
	}

	// Validate required claims
	if !claims.VerifyExpiresAt(time.Now().Unix(), true) {
		return nil, errors.NewUnauthorizedError("Token has expired")
	}

	if !claims.VerifyIssuer(c.config.CasdoorServerURL, true) {
		return nil, errors.NewUnauthorizedError("Invalid token issuer")
	}

	// Extract user information
	userInfo := &UserInfo{}
	
	if sub, ok := claims["sub"].(string); ok {
		userInfo.ID = sub
	}
	
	if name, ok := claims["name"].(string); ok {
		userInfo.Name = name
	}
	
	if username, ok := claims["preferred_username"].(string); ok {
		userInfo.Username = username
	}
	
	if email, ok := claims["email"].(string); ok {
		userInfo.Email = email
	}
	
	if org, ok := claims["organization"].(string); ok {
		userInfo.Organization = org
	}
	
	// Extract roles and groups if present
	if roles, ok := claims["roles"].([]interface{}); ok {
		userInfo.Roles = make([]string, len(roles))
		for i, role := range roles {
			if roleStr, ok := role.(string); ok {
				userInfo.Roles[i] = roleStr
			}
		}
	}
	
	if groups, ok := claims["groups"].([]interface{}); ok {
		userInfo.Groups = make([]string, len(groups))
		for i, group := range groups {
			if groupStr, ok := group.(string); ok {
				userInfo.Groups[i] = groupStr
			}
		}
	}

	return userInfo, nil
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