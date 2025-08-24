package casbinx

import (
	"github.com/casbin/casbin/v2"
	"github.com/casbin/casbin/v2/model"
	gormadapter "github.com/casbin/gorm-adapter/v3"
	"gorm.io/gorm"
)

// Enforcer wraps Casbin enforcer with additional functionality
type Enforcer struct {
	enforcer *casbin.Enforcer
	adapter  *gormadapter.Adapter
}

// New creates a new Casbin enforcer
func New(db *gorm.DB) (*Enforcer, error) {
	// Create GORM adapter
	adapter, err := gormadapter.NewAdapterByDBUseTableName(db, "", "casbin_rule")
	if err != nil {
		return nil, err
	}

	// Define RBAC with Domains model
	modelText := `
[request_definition]
r = sub, dom, obj, act

[policy_definition]
p = sub, dom, obj, act

[role_definition]
g = _, _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = g(r.sub, p.sub, r.dom) && r.dom == p.dom && r.obj == p.obj && r.act == p.act || g(r.sub, "super_admin", "*")
`

	// Create model from text
	m, err := model.NewModelFromString(modelText)
	if err != nil {
		return nil, err
	}

	// Create enforcer
	enforcer, err := casbin.NewEnforcer(m, adapter)
	if err != nil {
		return nil, err
	}

	// Load policies from database
	if err := enforcer.LoadPolicy(); err != nil {
		return nil, err
	}

	return &Enforcer{
		enforcer: enforcer,
		adapter:  adapter,
	}, nil
}

// Enforce checks if a request is allowed
func (e *Enforcer) Enforce(sub, dom, obj, act string) (bool, error) {
	return e.enforcer.Enforce(sub, dom, obj, act)
}

// AddPolicy adds a policy
func (e *Enforcer) AddPolicy(sub, dom, obj, act string) (bool, error) {
	return e.enforcer.AddPolicy(sub, dom, obj, act)
}

// RemovePolicy removes a policy
func (e *Enforcer) RemovePolicy(sub, dom, obj, act string) (bool, error) {
	return e.enforcer.RemovePolicy(sub, dom, obj, act)
}

// AddRoleForUser adds a role for user in domain
func (e *Enforcer) AddRoleForUser(user, role, domain string) (bool, error) {
	return e.enforcer.AddRoleForUser(user, role, domain)
}

// DeleteRoleForUser deletes a role for user in domain
func (e *Enforcer) DeleteRoleForUser(user, role, domain string) (bool, error) {
	return e.enforcer.DeleteRoleForUser(user, role, domain)
}

// GetRolesForUser gets roles for user in domain
func (e *Enforcer) GetRolesForUser(user, domain string) []string {
	return e.enforcer.GetRolesForUserInDomain(user, domain)
}

// GetUsersForRole gets users for role in domain
func (e *Enforcer) GetUsersForRole(role, domain string) []string {
	return e.enforcer.GetUsersForRoleInDomain(role, domain)
}

// GetPermissionsForUser gets permissions for user in domain
func (e *Enforcer) GetPermissionsForUser(user, domain string) [][]string {
	return e.enforcer.GetPermissionsForUserInDomain(user, domain)
}

// SavePolicy saves all policies to database
func (e *Enforcer) SavePolicy() error {
	return e.enforcer.SavePolicy()
}

// LoadPolicy loads all policies from database
func (e *Enforcer) LoadPolicy() error {
	return e.enforcer.LoadPolicy()
}

// InitDefaultPolicies initializes default policies and roles
func (e *Enforcer) InitDefaultPolicies() error {
	// Define default roles and their permissions
	defaultPolicies := [][]string{
		// Organization admin can manage everything in their org
		{"role:org_admin", "org:*", "*", "manage"},
		{"role:org_viewer", "org:*", "*", "read"},

		// Project roles
		{"role:project_owner", "project:*", "projects", "manage"},
		{"role:project_owner", "project:*", "devices", "manage"},
		{"role:project_owner", "project:*", "partitions", "manage"},
		{"role:project_admin", "project:*", "projects", "write"},
		{"role:project_admin", "project:*", "devices", "write"},
		{"role:project_admin", "project:*", "partitions", "write"},
		{"role:project_viewer", "project:*", "projects", "read"},
		{"role:project_viewer", "project:*", "devices", "read"},
		{"role:project_viewer", "project:*", "partitions", "read"},

		// Device roles
		{"role:device_owner", "device:*", "devices", "manage"},
		{"role:device_editor", "device:*", "devices", "write"},
		{"role:device_viewer", "device:*", "devices", "read"},
	}

	// Add default policies
	for _, policy := range defaultPolicies {
		if len(policy) == 4 {
			_, err := e.AddPolicy(policy[0], policy[1], policy[2], policy[3])
			if err != nil {
				return err
			}
		}
	}

	return e.SavePolicy()
}

// BuildDomain builds domain string from resource type and ID
func BuildDomain(resourceType, resourceID string) string {
	return resourceType + ":" + resourceID
}

// IsSuperUser checks if user has super admin role
func (e *Enforcer) IsSuperUser(userID string) bool {
	roles, _ := e.enforcer.GetRolesForUser(userID)
	for _, role := range roles {
		if role == "super_admin" {
			return true
		}
	}
	return false
}

// GrantSuperAdmin grants super admin role to user
func (e *Enforcer) GrantSuperAdmin(userID string) error {
	_, err := e.enforcer.AddRoleForUser(userID, "super_admin", "*")
	if err != nil {
		return err
	}
	return e.SavePolicy()
}

// AddGroupingPolicy adds a grouping policy (user -> role in domain)
func (e *Enforcer) AddGroupingPolicy(subject, role, domain string) (bool, error) {
	return e.enforcer.AddGroupingPolicy(subject, role, domain)
}

// RemoveGroupingPolicy removes a grouping policy
func (e *Enforcer) RemoveGroupingPolicy(subject, role, domain string) (bool, error) {
	return e.enforcer.RemoveGroupingPolicy(subject, role, domain)
}

// GetFilteredGroupingPolicy gets filtered grouping policies
func (e *Enforcer) GetFilteredGroupingPolicy(fieldIndex int, fieldValue string) [][]string {
	policies, err := e.enforcer.GetFilteredGroupingPolicy(fieldIndex, fieldValue)
	if err != nil {
		return [][]string{}
	}
	return policies
}
