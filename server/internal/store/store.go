package store

import (
	"fmt"
	"strings"

	"server/internal/config"
	"server/internal/domain/models"

	"github.com/glebarez/sqlite"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Store represents the data store
type Store struct {
	db *gorm.DB
}

// New creates a new store instance
// New creates a new store instance based on DSN:
// - postgres://... -> use PostgreSQL driver
// - sqlite://path or sqlite::memory: -> use SQLite driver (pure Go, no CGO)
func New(cfg *config.Config) (*Store, error) {
	var (
		db  *gorm.DB
		err error
	)

	dsn := cfg.PostgresDSN
	// Allow sqlite for development if DSN starts with "sqlite://" or "sqlite:"
	lower := strings.ToLower(dsn)
	switch {
	case strings.HasPrefix(lower, "sqlite://") || strings.HasPrefix(lower, "sqlite:"):
		// normalize: trim leading "sqlite://" to get actual DSN path accepted by sqlite.Open
		normalized := strings.TrimPrefix(dsn, "sqlite://")
		normalized = strings.TrimPrefix(normalized, "sqlite:")
		if normalized == "" {
			normalized = ":memory:"
		}
		db, err = gorm.Open(sqlite.Open(normalized), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Info),
		})
	default:
		// default to postgres
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Info),
		})
	}

	if err != nil {
		return nil, fmt.Errorf("failed to connect to database (dsn=%s): %w", dsn, err)
	}

	return &Store{db: db}, nil
}

// DB returns the underlying database connection
func (s *Store) DB() *gorm.DB {
	return s.db
}

// AutoMigrate runs database migrations
func (s *Store) AutoMigrate() error {
	return s.db.AutoMigrate(
		&models.Organization{},
		&models.User{},
		&models.Group{},
		&models.Project{},
		&models.Partition{},
		&models.Device{},
		&models.DeviceBinding{},
		&models.DeviceShare{},
		&models.DeviceTransfer{},
		&models.CasbinRule{},
		&models.AuditLog{},
		&models.OrganizationSetting{},
		&models.SystemSetting{},
	)
}

// Close closes the database connection
func (s *Store) Close() error {
	sqlDB, err := s.db.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}

// Health checks the database connection
func (s *Store) Health() error {
	sqlDB, err := s.db.DB()
	if err != nil {
		return err
	}
	return sqlDB.Ping()
}
