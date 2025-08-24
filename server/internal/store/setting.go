package store

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// OrganizationSettingRepository handles org-level settings
type OrganizationSettingRepository struct{ db *gorm.DB }

func NewOrganizationSettingRepository(db *gorm.DB) *OrganizationSettingRepository {
	return &OrganizationSettingRepository{db: db}
}

func (r *OrganizationSettingRepository) Get(ctx context.Context, orgID uuid.UUID) (*models.OrganizationSetting, error) {
	var s models.OrganizationSetting
	err := r.db.WithContext(ctx).First(&s, "org_id = ?", orgID).Error
	if err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *OrganizationSettingRepository) Upsert(ctx context.Context, s *models.OrganizationSetting) error {
	// Upsert by unique org_id
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "org_id"}},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"factory_allow_registration": s.FactoryAllowRegistration,
			"factory_default_project_id": s.FactoryDefaultProjectID,
			"updated_at":                 gorm.Expr("NOW()"),
		}),
	}).Create(s).Error
}

// SystemSettingRepository handles system-level key-values
type SystemSettingRepository struct{ db *gorm.DB }

func NewSystemSettingRepository(db *gorm.DB) *SystemSettingRepository {
	return &SystemSettingRepository{db: db}
}

func (r *SystemSettingRepository) Get(ctx context.Context, key string) (*models.SystemSetting, error) {
	var s models.SystemSetting
	if err := r.db.WithContext(ctx).First(&s, "key = ?", key).Error; err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *SystemSettingRepository) Set(ctx context.Context, key, value string) error {
	s := &models.SystemSetting{Key: key, Value: value}
	return r.db.WithContext(ctx).Save(s).Error
}

// AuditLogRepository helpers for purge
type AuditLogRepository struct{ db *gorm.DB }

func NewAuditLogRepository(db *gorm.DB) *AuditLogRepository { return &AuditLogRepository{db: db} }

func (r *AuditLogRepository) PurgeOlderThan(ctx context.Context, cutoff time.Time) (int64, error) {
	res := r.db.WithContext(ctx).Where("created_at < ?", cutoff).Delete(&models.AuditLog{})
	return res.RowsAffected, res.Error
}

func (r *AuditLogRepository) Insert(ctx context.Context, rec *models.AuditLog) error {
	return r.db.WithContext(ctx).Create(rec).Error
}
