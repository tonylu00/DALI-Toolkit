package services

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"server/internal/domain/models"
	"server/internal/store"

	"github.com/google/uuid"
)

const systemAuditRetentionDaysKey = "audit.retention_days"

// SettingService manages org/system settings
type SettingService struct {
	orgRepo   *store.OrganizationSettingRepository
	sysRepo   *store.SystemSettingRepository
	auditRepo *store.AuditLogRepository
}

func NewSettingServiceWithRepos(org *store.OrganizationSettingRepository, sys *store.SystemSettingRepository, audit *store.AuditLogRepository) *SettingService {
	return &SettingService{orgRepo: org, sysRepo: sys, auditRepo: audit}
}

// OrgSettings view model
type OrgSettings struct {
	FactoryAllowRegistration bool       `json:"factory_allow_registration"`
	FactoryDefaultProjectID  *uuid.UUID `json:"factory_default_project_id"`
}

func (s *SettingService) GetOrgSettings(ctx context.Context, orgID uuid.UUID) (*OrgSettings, error) {
	rec, err := s.orgRepo.Get(ctx, orgID)
	if err != nil {
		return &OrgSettings{FactoryAllowRegistration: true, FactoryDefaultProjectID: nil}, nil
	}
	return &OrgSettings{FactoryAllowRegistration: rec.FactoryAllowRegistration, FactoryDefaultProjectID: rec.FactoryDefaultProjectID}, nil
}

func (s *SettingService) SetOrgSettings(ctx context.Context, orgID uuid.UUID, in OrgSettings) error {
	rec := &models.OrganizationSetting{
		BaseModel:                models.BaseModel{ID: uuid.New()},
		OrgID:                    orgID,
		FactoryAllowRegistration: in.FactoryAllowRegistration,
		FactoryDefaultProjectID:  in.FactoryDefaultProjectID,
	}
	return s.orgRepo.Upsert(ctx, rec)
}

func (s *SettingService) GetAuditRetentionDays(ctx context.Context) (int, error) {
	rec, err := s.sysRepo.Get(ctx, systemAuditRetentionDaysKey)
	if err != nil || rec.Value == "" {
		return 30, nil
	}
	v, err := strconv.Atoi(rec.Value)
	if err != nil {
		return 30, nil
	}
	if v < 1 {
		v = 1
	}
	return v, nil
}

func (s *SettingService) SetAuditRetentionDays(ctx context.Context, days int) error {
	if days < 1 {
		days = 1
	}
	return s.sysRepo.Set(ctx, systemAuditRetentionDaysKey, strconv.Itoa(days))
}

func (s *SettingService) PurgeAudit(ctx context.Context, days int) (int64, error) {
	if days <= 0 {
		var err error
		days, err = s.GetAuditRetentionDays(ctx)
		if err != nil {
			days = 30
		}
	}
	cutoff := time.Now().AddDate(0, 0, -days)
	return s.auditRepo.PurgeOlderThan(ctx, cutoff)
}

// Audit logging
type AuditService struct{ repo *store.AuditLogRepository }

func NewAuditService(repo *store.AuditLogRepository) *AuditService { return &AuditService{repo: repo} }

func (a *AuditService) Log(ctx context.Context, actor uuid.UUID, action, targetType string, targetID *uuid.UUID, detail interface{}, ip, ua string) error {
	var detailStr string
	if detail != nil {
		b, _ := json.Marshal(detail)
		detailStr = string(b)
	}
	rec := &models.AuditLog{
		BaseModel:  models.BaseModel{ID: uuid.New()},
		Actor:      actor,
		Action:     action,
		TargetType: targetType,
		TargetID:   targetID,
		Detail:     detailStr,
		IP:         ip,
		UserAgent:  ua,
	}
	return a.repo.Insert(ctx, rec)
}
