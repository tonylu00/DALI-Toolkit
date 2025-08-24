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
	"github.com/tonylu00/DALI-Toolkit/server/internal/api"
	"github.com/tonylu00/DALI-Toolkit/server/internal/auth"
	"github.com/tonylu00/DALI-Toolkit/server/internal/broker"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casbinx"
	"github.com/tonylu00/DALI-Toolkit/server/internal/casdoor"
	"github.com/tonylu00/DALI-Toolkit/server/internal/config"
	"github.com/tonylu00/DALI-Toolkit/server/internal/domain/services"
	"github.com/tonylu00/DALI-Toolkit/server/internal/logger"
	"github.com/tonylu00/DALI-Toolkit/server/internal/store"
	"github.com/tonylu00/DALI-Toolkit/server/internal/websocket"
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

	// Initialize Casdoor client
	casdoorClient, err := casdoor.New(cfg)
	if err != nil {
		logger.Fatal("Failed to initialize Casdoor client", zap.Error(err))
	}
	logger.Info("Casdoor client initialized")

	// Initialize Casbin enforcer
	enforcer, err := casbinx.New(store.DB())
	if err != nil {
		logger.Fatal("Failed to initialize Casbin enforcer", zap.Error(err))
	}
	logger.Info("Casbin enforcer initialized")

	// Initialize auth middleware
	authMiddleware := auth.New(casdoorClient, enforcer, orgService, logger)

	// Initialize API handlers
	deviceHandler := api.NewDeviceHandler(deviceService, orgService, enforcer, logger)
	projectHandler := api.NewProjectHandler(orgService, enforcer, logger) // ProjectService not implemented yet
	permissionHandler := api.NewPermissionHandler(orgService, enforcer, logger)

	// Initialize MQTT broker (simplified implementation for M3)
	mqttBroker := broker.NewMQTTBroker(cfg, deviceService, logger)
	
	// Start MQTT broker in background
	mqttCtx, mqttCancel := context.WithCancel(context.Background())
	defer mqttCancel()
	go func() {
		if err := mqttBroker.Start(mqttCtx); err != nil {
			logger.Error("MQTT broker failed", zap.Error(err))
		}
	}()
	
	logger.Info("MQTT broker initialized", zap.String("addr", cfg.MQTTListenAddr))

	// Initialize WebSocket hub
	var wsHub *websocket.Hub
	var wsHandler *websocket.Handler
	if cfg.WSEnable {
		wsHub = websocket.NewHub(cfg.WSMaxConnPerUser, logger)
		wsHandler = websocket.NewHandler(wsHub, deviceService, enforcer, mqttBroker, logger)
		
		// Start WebSocket hub in background
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		go wsHub.Run(ctx)
		
		logger.Info("WebSocket hub initialized", 
			zap.String("path", cfg.WSPath),
			zap.Int("max_conn_per_user", cfg.WSMaxConnPerUser))
	}

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
		// Public endpoints
		v1.GET("/auth/info", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"casdoor_server": cfg.CasdoorServerURL,
				"organization":   cfg.CasdoorOrg,
				"app":           cfg.CasdoorApp,
			})
		})

		// Organizations (public for testing)
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

		// Protected endpoints requiring authentication
		protected := v1.Group("/protected")
		protected.Use(authMiddleware.AuthRequired())
		{
			protected.GET("/user", func(c *gin.Context) {
				user := auth.GetUserContext(c)
				c.JSON(http.StatusOK, user)
			})

			// Devices endpoint with organization filtering
			protected.GET("/devices", func(c *gin.Context) {
				user := auth.GetUserContext(c)
				orgID := c.Query("org_id")
				
				// If no org_id specified, use user's organization
				if orgID == "" {
					orgID = user.OrgID.String()
				}

				// Check if user can access the specified organization
				if !user.IsSuperUser && orgID != user.OrgID.String() {
					c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to organization"})
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

		// Admin endpoints requiring specific permissions
		admin := v1.Group("/admin")
		admin.Use(authMiddleware.AuthRequired())
		admin.Use(authMiddleware.RequirePermission("admin", "manage"))
		{
			admin.GET("/users", func(c *gin.Context) {
				c.JSON(http.StatusOK, gin.H{"message": "Admin users endpoint"})
			})
		}
		
		// WebSocket endpoint (if enabled)
		if cfg.WSEnable && wsHandler != nil {
			v1.GET("/ws", authMiddleware.AuthRequired(), wsHandler.HandleWebSocket)
			
			// WebSocket stats endpoint
			admin.GET("/ws/stats", wsHandler.HandleStats)
		}
		
		// MQTT endpoints
		v1.GET("/mqtt/status", func(c *gin.Context) {
			stats := mqttBroker.GetStats()
			c.JSON(http.StatusOK, stats)
		})
		
		admin.POST("/mqtt/kick", authMiddleware.AuthRequired(), func(c *gin.Context) {
			// TODO: Implement client kick functionality
			c.JSON(http.StatusOK, gin.H{"message": "MQTT kick endpoint - to be implemented"})
		})
		
		// Device API endpoints (M4)
		devices := v1.Group("/devices")
		devices.Use(authMiddleware.AuthRequired())
		{
			devices.GET("", deviceHandler.ListDevices)
			devices.POST("", deviceHandler.CreateDevice)
			devices.GET("/:id", deviceHandler.GetDevice)
			devices.PATCH("/:id", deviceHandler.UpdateDevice)
			devices.DELETE("/:id", deviceHandler.DeleteDevice)
		}
		
		// Project API endpoints (M4) 
		projects := v1.Group("/projects")
		projects.Use(authMiddleware.AuthRequired())
		{
			projects.GET("", projectHandler.ListProjects)
			projects.POST("", projectHandler.CreateProject)
			projects.GET("/:id", projectHandler.GetProject)
			projects.PATCH("/:id", projectHandler.UpdateProject)
			projects.DELETE("/:id", projectHandler.DeleteProject)
		}
		
		// Permission API endpoints (M5)
		permissions := v1.Group("/permissions")
		permissions.Use(authMiddleware.AuthRequired())
		{
			permissions.GET("/roles", permissionHandler.ListRoles)
			permissions.GET("/subjects", permissionHandler.ListSubjects)
			permissions.POST("/grant", permissionHandler.GrantPermission)
			permissions.POST("/revoke", permissionHandler.RevokePermission)
			permissions.GET("/check", permissionHandler.CheckPermission)
		}
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