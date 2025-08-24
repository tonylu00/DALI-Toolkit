package store

import (
	"fmt"

	"github.com/tonylu00/DALI-Toolkit/server/internal/config"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/models"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Store represents the data store
type Store struct {
	db *gorm.DB
}

// New creates a new store instance
func New(cfg *config.Config) (*Store, error) {
	db, err := gorm.Open(postgres.Open(cfg.PostgresDSN), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
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