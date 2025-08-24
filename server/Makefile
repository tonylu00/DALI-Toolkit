.PHONY: help build test clean run docker-build docker-up docker-down lint security-scan integration-test flutter-web

# Default target
help:
	@echo "Available targets:"
	@echo "  build           - Build the server binary"
	@echo "  test            - Run unit tests"
	@echo "  integration-test - Run integration tests"
	@echo "  lint            - Run linters"
	@echo "  security-scan   - Run security analysis"
	@echo "  clean           - Clean build artifacts"
	@echo "  run             - Run the server locally"
	@echo "  flutter-web     - Build and integrate Flutter web app"
	@echo "  docker-build    - Build Docker image"
	@echo "  docker-up       - Start services with docker-compose"
	@echo "  docker-down     - Stop services with docker-compose"
	@echo "  ci              - Run complete CI pipeline"

# Build the server binary
build:
	@echo "Building server binary..."
	@mkdir -p bin
	go build -ldflags="-s -w" -o bin/server ./cmd/server

# Run unit tests
test:
	@echo "Running unit tests..."
	go test -v ./internal/...

# Run integration tests
integration-test:
	@echo "Running integration tests..."
	go test -v ./test/...

# Run all tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	go test -v -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

# Run linters
lint:
	@echo "Running linters..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo "golangci-lint not installed, running basic checks..."; \
		go vet ./...; \
		go fmt ./...; \
	fi

# Run security analysis
security-scan:
	@echo "Running security analysis..."
	@if command -v gosec >/dev/null 2>&1; then \
		gosec ./...; \
	else \
		echo "gosec not installed, skipping security scan"; \
		echo "Install with: go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest"; \
	fi

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf bin/ coverage.out coverage.html

# Run the server locally with development settings
run:
	@echo "Starting server in development mode..."
	@export ENV=development && go run ./cmd/server

# Build and integrate Flutter web app
flutter-web:
	@echo "Building Flutter web app..."
	@if [ -f "../pubspec.yaml" ]; then \
		cd .. && flutter build web; \
		echo "Copying Flutter web build to server..."; \
		rm -rf server/internal/web/flutter_web/*; \
		cp -r build/web/* server/internal/web/flutter_web/; \
		echo "Flutter web app integrated successfully"; \
	else \
		echo "Flutter project not found. Using placeholder web app."; \
	fi

# Build Docker image
docker-build:
	@echo "Building Docker image..."
	docker build -t dali-toolkit-server .

# Start services with docker-compose
docker-up:
	@echo "Starting services with docker-compose..."
	docker-compose up -d

# Stop services with docker-compose
docker-down:
	@echo "Stopping services with docker-compose..."
	docker-compose down

# Complete CI pipeline
ci: lint test integration-test security-scan build
	@echo "CI pipeline completed successfully"

# Development workflow
dev: clean lint test build
	@echo "Development build completed"