# DALI-Toolkit CI/CD Pipeline

This document describes the comprehensive CI/CD pipeline for DALI-Toolkit, supporting multi-platform builds for both Flutter applications and Go server components.

## Overview

The CI/CD pipeline provides automated building, testing, and deployment for:

- **Flutter Applications**: Android, iOS, Web, Windows, macOS, Linux
- **Go Server**: Multiple architectures (amd64, arm64) on Linux, Windows, macOS
- **Server Variants**: Standalone and web-integrated binaries
- **Docker Images**: Containerized deployment options

## Pipeline Jobs

### 1. Code Quality & Testing

- **`lint`**: Go code linting and formatting checks
- **`flutter-lint`**: Flutter code analysis and formatting
- **`test`**: Server unit tests with coverage reporting
- **`flutter-test`**: Flutter unit tests with coverage
- **`integration-test`**: End-to-end integration tests with PostgreSQL/Redis
- **`security`**: Security scanning with gosec

### 2. Multi-Platform Builds

#### Flutter Build Matrix (`flutter-build`)

Builds Flutter applications for all supported platforms:

| Platform | OS | Output | Notes |
|----------|----|---------|----|
| **Web** | Ubuntu | `build/web/` | Primary platform for server integration |
| **Android APK** | Ubuntu | `.apk` file | Ready for sideloading |
| **Android AAB** | Ubuntu | `.aab` file | Ready for Play Store |
| **iOS** | macOS | iOS build | Unsigned, requires code signing |
| **Windows** | Windows | `.exe` + assets | Desktop application |
| **macOS** | macOS | `.app` bundle | Desktop application |
| **Linux** | Ubuntu | Binary + assets | Desktop application |

#### Server Build Matrix (`server-build`)

Builds Go server binaries for multiple platforms:

| Platform | Architecture | Binary Name |
|----------|-------------|-------------|
| Linux | amd64, arm64 | `dali-toolkit-server-linux-<arch>` |
| Windows | amd64, arm64 | `dali-toolkit-server-windows-<arch>.exe` |
| macOS | amd64, arm64 | `dali-toolkit-server-darwin-<arch>` |

#### Server with Web Integration (`server-with-web`)

Creates server binaries with embedded Flutter web interface:

- Combines Flutter web build with Go server
- Uses `go:embed` for seamless integration
- Available for primary platforms (Linux amd64, Windows amd64, macOS)
- Binary naming: `dali-toolkit-server-web-<platform>-<arch>`

### 3. Containerization (`docker`)

Creates Docker images for both server variants:

- **`standalone`**: Server-only image
- **`with-web`**: Server with embedded web interface

### 4. Release Management (`release`)

Automatically creates releases when tags are pushed:

- Collects all build artifacts
- Creates platform-specific archives
- Generates checksums for verification
- Publishes GitHub release with all assets

### 5. Deployment (`deploy`)

Supports staging and production deployments:

- Health checks after deployment
- Environment-specific configuration
- Integration points for various deployment targets

## Triggers

The pipeline runs on:

- **Push** to `main` or `develop` branches
- **Pull requests** to `main` branch
- **Tag pushes** (triggers release workflow)
- **Manual dispatch** via GitHub UI

## Build Scripts

### Local Development

#### `build-web.sh`
Quick Flutter web build and server integration:

```bash
# Development build
./build-web.sh

# Production build
./build-web.sh production

# Skip server rebuild (CI mode)
./build-web.sh development true
```

#### `build-all.sh`
Comprehensive multi-platform build:

```bash
# Build all platforms
./build-all.sh

# Build with specific version
./build-all.sh v1.0.0
```

### Output Structure

```
dist/
├── flutter/
│   ├── web/                    # Flutter web build
│   ├── dali-toolkit-android.apk
│   ├── dali-toolkit-android.aab
│   ├── linux/                 # Linux desktop app
│   ├── macos/                 # macOS desktop app
│   ├── windows/               # Windows desktop app
│   └── ios/                   # iOS app (unsigned)
├── server/
│   ├── dali-toolkit-server-linux-amd64
│   ├── dali-toolkit-server-linux-arm64
│   ├── dali-toolkit-server-windows-amd64.exe
│   ├── dali-toolkit-server-web-linux-amd64
│   └── ...
├── docker/
│   ├── dali-toolkit-server-standalone.tar.gz
│   └── dali-toolkit-server-with-web.tar.gz
└── checksums.txt
```

## Platform Support

### Flutter Applications

| Platform | Status | Distribution |
|----------|--------|--------------|
| **Android** | ✅ Full | Play Store (AAB) or sideload (APK) |
| **iOS** | ✅ Build only | Requires code signing for App Store |
| **Web** | ✅ Full | Any web server, integrated with Go server |
| **Windows** | ✅ Full | Standalone executable |
| **macOS** | ✅ Full | Standalone application |
| **Linux** | ✅ Full | Standalone executable |

### Server Components

| Platform | Architecture | Status |
|----------|-------------|--------|
| **Linux** | amd64, arm64 | ✅ Full support |
| **Windows** | amd64, arm64 | ✅ Full support |
| **macOS** | amd64, arm64 | ✅ Full support |

### Container Support

- **Docker**: Linux amd64 images
- **Multi-stage builds**: Optimized image sizes
- **Health checks**: Built-in monitoring
- **Both variants**: Standalone and web-integrated

## Environment Variables

The pipeline uses these environment variables:

```yaml
GO_VERSION: '1.21'          # Go version for builds
FLUTTER_VERSION: '3.24.5'  # Flutter version
JAVA_VERSION: '17'          # Java for Android builds
NODE_VERSION: '18'          # Node.js for tooling
```

## Artifacts

### Build Artifacts

All builds generate artifacts with 7-day retention:

- `flutter-<platform>-build`: Platform-specific Flutter builds
- `server-<platform>-<arch>`: Server binaries
- `server-web-<platform>-<arch>`: Server binaries with embedded web
- `docker-image-<variant>`: Docker images

### Release Assets

Release builds include:

- All Flutter application packages
- All server binaries for supported platforms
- Docker images
- Checksums file for verification

## Security

### Build Security

- **Dependency scanning**: Automated security checks
- **Code scanning**: Static analysis with gosec
- **Signed commits**: Verification in CI
- **Isolated builds**: Clean environments for each job

### Deployment Security

- **Environment isolation**: Separate staging/production
- **Health checks**: Post-deployment verification
- **Rollback capability**: Previous version retention
- **Secret management**: Environment-specific configuration

## Usage Examples

### Local Development

```bash
# Quick web development cycle
./build-web.sh development true
cd server && ./bin/server

# Full local build
./build-all.sh
```

### CI/CD Integration

```bash
# In CI environment (automatically detected)
flutter build web --release
go build -o server ./cmd/server
```

### Production Deployment

```bash
# Download release assets
wget https://github.com/tonylu00/DALI-Toolkit/releases/latest/download/dali-toolkit-server-web-linux-amd64

# Or use Docker
docker load < dali-toolkit-server-with-web.tar.gz
docker run -p 8080:8080 dali-toolkit-server:with-web
```

## Monitoring

### Build Status

The pipeline provides comprehensive build status reporting:

- **Job summaries**: Overview of all build results
- **Artifact tracking**: Generated assets and sizes
- **Coverage reports**: Test coverage metrics
- **Security reports**: Vulnerability scanning results

### Health Checks

Automated health checks verify:

- **API endpoints**: Server responsiveness
- **Web interface**: Flutter app loading
- **Database connectivity**: Integration test results
- **Container health**: Docker image functionality

## Troubleshooting

### Common Issues

1. **Flutter build failures**
   - Check Flutter SDK version compatibility
   - Verify platform dependencies (Android SDK, Xcode)
   - Review pub.lock file for dependency conflicts

2. **Server build failures**
   - Verify Go version compatibility
   - Check cross-compilation setup
   - Review build flags and dependencies

3. **Docker build issues**
   - Ensure binary permissions are correct
   - Verify artifact download paths
   - Check Docker layer caching

### Debug Commands

```bash
# Check Flutter environment
flutter doctor -v

# Verify Go build environment
go env

# Test Docker image locally
docker run --rm -it dali-toolkit-server:with-web /bin/sh
```

## Contributing

When contributing to the CI/CD pipeline:

1. Test changes locally with build scripts
2. Verify compatibility across platforms
3. Update documentation for new features
4. Ensure security best practices
5. Test artifact generation and deployment