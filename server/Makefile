.PHONY: help build test clean run docker-build docker-up docker-down

# Default target
help:
	@echo "Available targets:"
	@echo "  build       - Build the server binary"
	@echo "  test        - Run tests"
	@echo "  clean       - Clean build artifacts"
	@echo "  run         - Run the server locally"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-up   - Start services with docker-compose"
	@echo "  docker-down - Stop services with docker-compose"

# Build the server binary
build:
	go build -o bin/server ./cmd/server

# Run tests
test:
	go test ./...

# Clean build artifacts
clean:
	rm -rf bin/

# Run the server locally
run:
	go run ./cmd/server

# Build Docker image
docker-build:
	docker build -t dali-toolkit-server .

# Start services with docker-compose
docker-up:
	docker-compose up -d

# Stop services with docker-compose
docker-down:
	docker-compose down