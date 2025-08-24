package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// BaseModel provides common fields for all models
type BaseModel struct {
	ID        uuid.UUID      `gorm:"type:uuid;primary_key" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
}

// Organization represents a tenant/organization from Casdoor
type Organization struct {
	BaseModel
	CasdoorOrg string `gorm:"uniqueIndex;not null" json:"casdoor_org"`
	Name       string `gorm:"not null" json:"name"`
}

// User represents a user in the system
type User struct {
	BaseModel
	CasdoorUserID string    `gorm:"uniqueIndex;not null" json:"casdoor_user_id"`
	Username      string    `gorm:"not null" json:"username"`
	OrgID         uuid.UUID `gorm:"type:uuid;not null;index" json:"org_id"`
	Email         string    `json:"email"`

	// Relationships
	Organization *Organization `gorm:"foreignKey:OrgID" json:"organization,omitempty"`
}

// Group represents a user group
type Group struct {
	BaseModel
	CasdoorGroupID string    `gorm:"uniqueIndex;not null" json:"casdoor_group_id"`
	Name           string    `gorm:"not null" json:"name"`
	OrgID          uuid.UUID `gorm:"type:uuid;not null;index" json:"org_id"`

	// Relationships
	Organization *Organization `gorm:"foreignKey:OrgID" json:"organization,omitempty"`
}

// Project represents a project within an organization
type Project struct {
	BaseModel
	OrgID     uuid.UUID `gorm:"type:uuid;not null;index" json:"org_id"`
	Name      string    `gorm:"not null" json:"name"`
	Remark    string    `json:"remark"`
	CreatedBy uuid.UUID `gorm:"type:uuid;not null" json:"created_by"`

	// Relationships
	Organization *Organization `gorm:"foreignKey:OrgID" json:"organization,omitempty"`
	Creator      *User         `gorm:"foreignKey:CreatedBy" json:"creator,omitempty"`
	Partitions   []Partition   `gorm:"foreignKey:ProjectID" json:"partitions,omitempty"`
	Devices      []Device      `gorm:"foreignKey:ProjectID" json:"devices,omitempty"`
}

// Partition represents a hierarchical partition within a project
type Partition struct {
	BaseModel
	ProjectID uuid.UUID  `gorm:"type:uuid;not null;index" json:"project_id"`
	ParentID  *uuid.UUID `gorm:"type:uuid;index" json:"parent_id"`
	Name      string     `gorm:"not null" json:"name"`
	Path      string     `gorm:"type:text;index" json:"path"` // Use text for SQLite compatibility, ltree for PostgreSQL
	Depth     int        `gorm:"not null" json:"depth"`

	// Relationships
	Project  *Project    `gorm:"foreignKey:ProjectID" json:"project,omitempty"`
	Parent   *Partition  `gorm:"foreignKey:ParentID" json:"parent,omitempty"`
	Children []Partition `gorm:"foreignKey:ParentID" json:"children,omitempty"`
	Devices  []Device    `gorm:"foreignKey:PartitionID" json:"devices,omitempty"`
}

// DeviceType represents the type of device
type DeviceType string

const (
	DeviceTypeLTE   DeviceType = "lte_nr"
	DeviceTypeWiFi  DeviceType = "wifi_eth"
	DeviceTypeOther DeviceType = "other"
)

// DeviceStatus represents the status of a device
type DeviceStatus string

const (
	DeviceStatusOnline      DeviceStatus = "online"
	DeviceStatusOffline     DeviceStatus = "offline"
	DeviceStatusUnbound     DeviceStatus = "unbound"
	DeviceStatusMaintenance DeviceStatus = "maintenance"
)

// Device represents a physical device
type Device struct {
	BaseModel
	MAC         string       `gorm:"size:12;uniqueIndex;not null" json:"mac"` // 12 char uppercase hex
	IMEI        *string      `gorm:"size:16;uniqueIndex" json:"imei"`         // 14-16 digit string
	DeviceType  DeviceType   `gorm:"not null" json:"device_type"`
	ProjectID   uuid.UUID    `gorm:"type:uuid;not null;index" json:"project_id"`
	PartitionID *uuid.UUID   `gorm:"type:uuid;index" json:"partition_id"`
	DisplayName string       `json:"display_name"`
	Status      DeviceStatus `gorm:"default:'unbound'" json:"status"`
	LastSeenAt  *time.Time   `json:"last_seen_at"`
	Meta        string       `gorm:"type:jsonb" json:"meta"` // JSON metadata

	// Relationships
	Project   *Project         `gorm:"foreignKey:ProjectID" json:"project,omitempty"`
	Partition *Partition       `gorm:"foreignKey:PartitionID" json:"partition,omitempty"`
	Bindings  []DeviceBinding  `gorm:"foreignKey:DeviceID" json:"bindings,omitempty"`
	Shares    []DeviceShare    `gorm:"foreignKey:DeviceID" json:"shares,omitempty"`
	Transfers []DeviceTransfer `gorm:"foreignKey:DeviceID" json:"transfers,omitempty"`
}

// DeviceBinding represents a device bound to a user
type DeviceBinding struct {
	BaseModel
	DeviceID uuid.UUID `gorm:"type:uuid;not null;index" json:"device_id"`
	UserID   uuid.UUID `gorm:"type:uuid;not null;index" json:"user_id"`
	BoundAt  time.Time `gorm:"not null" json:"bound_at"`
	BoundBy  uuid.UUID `gorm:"type:uuid;not null" json:"bound_by"`

	// Relationships
	Device *Device `gorm:"foreignKey:DeviceID" json:"device,omitempty"`
	User   *User   `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Binder *User   `gorm:"foreignKey:BoundBy" json:"binder,omitempty"`
}

// SubjectType represents the type of subject (user or group)
type SubjectType string

const (
	SubjectTypeUser  SubjectType = "user"
	SubjectTypeGroup SubjectType = "group"
)

// DeviceRole represents the role assigned to a subject for a device
type DeviceRole string

const (
	DeviceRoleOwner  DeviceRole = "owner"
	DeviceRoleEditor DeviceRole = "editor"
	DeviceRoleViewer DeviceRole = "viewer"
)

// DeviceShare represents device sharing permissions
type DeviceShare struct {
	BaseModel
	DeviceID    uuid.UUID   `gorm:"type:uuid;not null;index" json:"device_id"`
	SubjectType SubjectType `gorm:"not null" json:"subject_type"`
	SubjectID   uuid.UUID   `gorm:"type:uuid;not null;index" json:"subject_id"`
	Role        DeviceRole  `gorm:"not null" json:"role"`
	GrantedBy   uuid.UUID   `gorm:"type:uuid;not null" json:"granted_by"`
	GrantedAt   time.Time   `gorm:"not null" json:"granted_at"`

	// Relationships
	Device  *Device `gorm:"foreignKey:DeviceID" json:"device,omitempty"`
	Granter *User   `gorm:"foreignKey:GrantedBy" json:"granter,omitempty"`
}

// TransferStatus represents the status of a device transfer
type TransferStatus string

const (
	TransferStatusPending   TransferStatus = "pending"
	TransferStatusApproved  TransferStatus = "approved"
	TransferStatusRejected  TransferStatus = "rejected"
	TransferStatusCancelled TransferStatus = "cancelled"
)

// DeviceTransfer represents a device transfer request
type DeviceTransfer struct {
	BaseModel
	DeviceID      uuid.UUID      `gorm:"type:uuid;not null;index" json:"device_id"`
	FromSubjectID uuid.UUID      `gorm:"type:uuid;not null" json:"from_subject_id"`
	ToSubjectID   uuid.UUID      `gorm:"type:uuid;not null" json:"to_subject_id"`
	Status        TransferStatus `gorm:"default:'pending'" json:"status"`
	ProcessedAt   *time.Time     `json:"processed_at"`

	// Relationships
	Device      *Device `gorm:"foreignKey:DeviceID" json:"device,omitempty"`
	FromSubject *User   `gorm:"foreignKey:FromSubjectID" json:"from_subject,omitempty"`
	ToSubject   *User   `gorm:"foreignKey:ToSubjectID" json:"to_subject,omitempty"`
}

// CasbinRule represents Casbin authorization rules
type CasbinRule struct {
	ID    uint   `gorm:"primaryKey;autoIncrement"`
	Ptype string `gorm:"size:512;uniqueIndex:unique_index"`
	V0    string `gorm:"size:512;uniqueIndex:unique_index"`
	V1    string `gorm:"size:512;uniqueIndex:unique_index"`
	V2    string `gorm:"size:512;uniqueIndex:unique_index"`
	V3    string `gorm:"size:512;uniqueIndex:unique_index"`
	V4    string `gorm:"size:512;uniqueIndex:unique_index"`
	V5    string `gorm:"size:512;uniqueIndex:unique_index"`
}

// TableName sets the table name for CasbinRule
func (CasbinRule) TableName() string {
	return "casbin_rule"
}

// AuditLog represents audit trail for actions
type AuditLog struct {
	BaseModel
	Actor      uuid.UUID  `gorm:"type:uuid;not null;index" json:"actor"`
	Action     string     `gorm:"not null;index" json:"action"`
	TargetType string     `gorm:"not null;index" json:"target_type"`
	TargetID   *uuid.UUID `gorm:"type:uuid;index" json:"target_id"`
	Detail     string     `gorm:"type:jsonb" json:"detail"`
	IP         string     `json:"ip"`
	UserAgent  string     `json:"user_agent"`

	// Relationships
	User *User `gorm:"foreignKey:Actor" json:"user,omitempty"`
}

// OrganizationSetting stores per-organization configuration
type OrganizationSetting struct {
	BaseModel
	OrgID                    uuid.UUID  `gorm:"type:uuid;uniqueIndex" json:"org_id"`
	FactoryAllowRegistration bool       `gorm:"not null;default:true" json:"factory_allow_registration"`
	FactoryDefaultProjectID  *uuid.UUID `gorm:"type:uuid" json:"factory_default_project_id"`
}

// SystemSetting provides simple key-value settings for the whole deployment
type SystemSetting struct {
	Key   string `gorm:"primaryKey;size:128" json:"key"`
	Value string `gorm:"type:text" json:"value"`
}
