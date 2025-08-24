package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/tonylu00/DALI-Toolkit/server/internal/config"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"github.com/tonylu00/DALI-Toolkit/server/internal/logger"
	"github.com/tonylu00/DALI-Toolkit/server/internal/store"
	"go.uber.org/zap"
)

func main() {
	// Initialize configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize logger
	logger, err := logger.New(cfg.LogLevel)
	if err != nil {
		log.Fatalf("Failed to initialize logger: %v", err)
	}
	defer logger.Sync()

	logger.Info("Starting DALI-Toolkit server", zap.String("version", "v0.1.0"))

	// Initialize database
	store, err := store.New(cfg)
	if err != nil {
		logger.Fatal("Failed to initialize database", zap.Error(err))
	}
	defer store.Close()

	// Run database migrations
	if err := store.AutoMigrate(); err != nil {
		logger.Fatal("Failed to run database migrations", zap.Error(err))
	}

	// Test database connection
	if err := store.Health(); err != nil {
		logger.Fatal("Database health check failed", zap.Error(err))
	}
	logger.Info("Database connected successfully")

	// Initialize services
	orgService := services.NewOrganizationService(store.DB())
	deviceService := services.NewDeviceService(store.DB())

	// Set gin mode
	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Create router
	router := gin.New()
	router.Use(gin.Recovery())

	// Basic health check endpoint
	router.GET("/health", func(c *gin.Context) {
		// Check database health
		if err := store.Health(); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"status": "unhealthy",
				"error":  "database connection failed",
			})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"status": "ok",
			"time":   time.Now().UTC(),
		})
	})

	// API version endpoint
	router.GET("/api/v1/info", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"name":    "DALI-Toolkit Server",
			"version": "v0.1.0",
			"env":     cfg.Env,
		})
	})

	// Test endpoints for M1 verification
	v1 := router.Group("/api/v1")
	{
		// Organizations
		v1.GET("/organizations", func(c *gin.Context) {
			orgs, err := orgService.ListOrganizations()
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, orgs)
		})

		v1.POST("/organizations", func(c *gin.Context) {
			var req struct {
				CasdoorOrg string `json:"casdoor_org" binding:"required"`
				Name       string `json:"name" binding:"required"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			org, err := orgService.CreateOrganization(req.CasdoorOrg, req.Name)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusCreated, org)
		})

		// Devices
		v1.GET("/devices", func(c *gin.Context) {
			orgID := c.Query("org_id")
			if orgID == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "org_id is required"})
				return
			}

			orgUUID, err := uuid.Parse(orgID)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid org_id"})
				return
			}

			filters := make(map[string]interface{})
			if status := c.Query("status"); status != "" {
				filters["status"] = status
			}

			devices, err := deviceService.ListDevicesByOrganization(orgUUID, filters)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, devices)
		})
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:         cfg.ServerAddr,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in a goroutine
	go func() {
		logger.Info("Server starting", zap.String("addr", cfg.ServerAddr))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("Failed to start server", zap.Error(err))
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Server shutting down...")

	// The context is used to inform the server it has 5 seconds to finish
	// the request it is currently handling
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Fatal("Server forced to shutdown", zap.Error(err))
	}

	logger.Info("Server exited")
}