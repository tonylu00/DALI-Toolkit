#!/bin/bash

# DALI-Toolkit Multi-Platform Build Script
# Builds Flutter apps and Go server for all supported platforms

set -e

echo "DALI-Toolkit Multi-Platform Build Script"
echo "========================================"

PROJECT_ROOT="$(pwd)"
FLUTTER_PROJECT_ROOT="$PROJECT_ROOT"
SERVER_ROOT="$PROJECT_ROOT/server"
BUILD_DIR="$PROJECT_ROOT/dist"
WEB_EMBED_DIR="$SERVER_ROOT/internal/web/flutter_web"

# Build configuration
VERSION="${1:-dev}"
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check if this is run from the correct directory
if [[ ! -f "pubspec.yaml" ]]; then
    echo "Error: This script must be run from the Flutter project root (where pubspec.yaml is located)"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"/{flutter,server,docker}

echo "🔧 Build Configuration:"
echo "  Version: $VERSION"
echo "  Build Time: $BUILD_TIME"
echo "  Output Directory: $BUILD_DIR"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Flutter builds
echo "📱 Building Flutter Applications..."
echo "=================================="

if command_exists flutter; then
    echo "✅ Flutter found, building all platforms..."
    
    # Install dependencies
    echo "📦 Installing Flutter dependencies..."
    flutter pub get
    
    # Enable all platforms
    flutter config --enable-web
    flutter config --enable-android
    flutter config --enable-linux-desktop
    flutter config --enable-macos-desktop
    flutter config --enable-windows-desktop
    # iOS is enabled by default on macOS
    
    # Build web (priority for server integration)
    echo "🌐 Building Flutter Web..."
    flutter build web --release --no-tree-shake-icons
    cp -r build/web "$BUILD_DIR/flutter/web"
    
    # Build Android APK
    echo "🤖 Building Android APK..."
    if flutter build apk --release 2>/dev/null; then
        cp build/app/outputs/flutter-apk/app-release.apk "$BUILD_DIR/flutter/dali-toolkit-android.apk"
        echo "  ✅ Android APK: $BUILD_DIR/flutter/dali-toolkit-android.apk"
    else
        echo "  ⚠️ Android APK build failed (SDK may not be available)"
    fi
    
    # Build Android AAB
    echo "📦 Building Android AAB..."
    if flutter build appbundle --release 2>/dev/null; then
        cp build/app/outputs/bundle/release/app-release.aab "$BUILD_DIR/flutter/dali-toolkit-android.aab"
        echo "  ✅ Android AAB: $BUILD_DIR/flutter/dali-toolkit-android.aab"
    else
        echo "  ⚠️ Android AAB build failed (SDK may not be available)"
    fi
    
    # Build Linux desktop
    echo "🐧 Building Linux Desktop..."
    if flutter build linux --release 2>/dev/null; then
        cp -r build/linux/x64/release/bundle "$BUILD_DIR/flutter/linux"
        echo "  ✅ Linux Desktop: $BUILD_DIR/flutter/linux/"
    else
        echo "  ⚠️ Linux desktop build failed (dependencies may not be available)"
    fi
    
    # Build macOS desktop (only on macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "🍎 Building macOS Desktop..."
        if flutter build macos --release 2>/dev/null; then
            cp -r build/macos/Build/Products/Release "$BUILD_DIR/flutter/macos"
            echo "  ✅ macOS Desktop: $BUILD_DIR/flutter/macos/"
        else
            echo "  ⚠️ macOS desktop build failed"
        fi
        
        echo "📱 Building iOS..."
        if flutter build ios --release --no-codesign 2>/dev/null; then
            cp -r build/ios/iphoneos "$BUILD_DIR/flutter/ios"
            echo "  ✅ iOS: $BUILD_DIR/flutter/ios/ (unsigned)"
        else
            echo "  ⚠️ iOS build failed (Xcode may not be available)"
        fi
    fi
    
    # Build Windows desktop (only on Windows)
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "🪟 Building Windows Desktop..."
        if flutter build windows --release 2>/dev/null; then
            cp -r build/windows/x64/runner/Release "$BUILD_DIR/flutter/windows"
            echo "  ✅ Windows Desktop: $BUILD_DIR/flutter/windows/"
        else
            echo "  ⚠️ Windows desktop build failed"
        fi
    fi
    
else
    echo "⚠️ Flutter not found, creating web placeholder..."
    
    # Create placeholder web build
    mkdir -p build/web
    cat > build/web/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="DALI-Toolkit Management Interface">
  <title>DALI-Toolkit</title>
  <style>
    body { 
      font-family: Arial, sans-serif; 
      text-align: center; 
      padding: 50px; 
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      min-height: 100vh;
      margin: 0;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .container {
      background: rgba(255,255,255,0.1);
      padding: 40px;
      border-radius: 10px;
      backdrop-filter: blur(10px);
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>DALI-Toolkit</h1>
    <p>Flutter SDK not available - using placeholder</p>
    <p>Install Flutter SDK and rebuild for full functionality</p>
  </div>
</body>
</html>
EOF
    cp -r build/web "$BUILD_DIR/flutter/web"
fi

echo ""

# Server builds
echo "🖥️ Building Server Binaries..."
echo "==============================="

if command_exists go; then
    cd "$SERVER_ROOT"
    
    # Install dependencies
    echo "📦 Installing Go dependencies..."
    go mod download
    
    # Build for multiple platforms
    platforms=(
        "linux/amd64"
        "linux/arm64" 
        "windows/amd64"
        "windows/arm64"
        "darwin/amd64"
        "darwin/arm64"
    )
    
    for platform in "${platforms[@]}"; do
        IFS='/' read -r GOOS GOARCH <<< "$platform"
        extension=""
        if [[ "$GOOS" == "windows" ]]; then
            extension=".exe"
        fi
        
        echo "🔨 Building server for $GOOS/$GOARCH..."
        
        # Build standalone server
        mkdir -p "../dist/server"
        GOOS=$GOOS GOARCH=$GOARCH CGO_ENABLED=0 go build \
            -ldflags="-w -s -X main.Version=$VERSION -X main.BuildTime=$BUILD_TIME" \
            -o "../dist/server/dali-toolkit-server-$GOOS-$GOARCH$extension" \
            ./cmd/server
        
        echo "  ✅ Standalone: dali-toolkit-server-$GOOS-$GOARCH$extension"
        
        # Build server with embedded web (only for main platforms)
        if [[ "$GOOS" == "linux" && "$GOARCH" == "amd64" ]] || \
           [[ "$GOOS" == "windows" && "$GOARCH" == "amd64" ]] || \
           [[ "$GOOS" == "darwin" ]]; then
            
            # Copy web build to embed directory
            rm -rf internal/web/flutter_web/*
            mkdir -p internal/web/flutter_web
            if [[ -d "../dist/flutter/web" ]]; then
                cp -r "../dist/flutter/web"/* internal/web/flutter_web/
            else
                echo "  ⚠️ Web build not found, creating placeholder..."
                cat > internal/web/flutter_web/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>DALI-Toolkit</title>
  <style>
    body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
    .container { max-width: 600px; margin: 0 auto; }
  </style>
</head>
<body>
  <div class="container">
    <h1>DALI-Toolkit</h1>
    <p>Web interface placeholder</p>
    <p>Install Flutter SDK and rebuild for full functionality</p>
  </div>
</body>
</html>
EOF
                # Create minimal manifest for embedding
                cat > internal/web/flutter_web/manifest.json << 'EOF'
{
  "name": "DALI-Toolkit",
  "short_name": "DALI-Toolkit",
  "start_url": "./",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#007bff"
}
EOF
            fi
            
            GOOS=$GOOS GOARCH=$GOARCH CGO_ENABLED=0 go build \
                -ldflags="-w -s -X main.Version=$VERSION -X main.BuildTime=$BUILD_TIME" \
                -tags="embed_web" \
                -o "../dist/server/dali-toolkit-server-web-$GOOS-$GOARCH$extension" \
                ./cmd/server
            
            echo "  ✅ With Web: dali-toolkit-server-web-$GOOS-$GOARCH$extension"
        fi
    done
    
    cd "$PROJECT_ROOT"
else
    echo "⚠️ Go not found, skipping server builds"
fi

echo ""

# Docker builds
echo "🐳 Building Docker Images..."
echo "============================"

if command_exists docker; then
    cd "$SERVER_ROOT"
    
    # Copy Linux server binary
    if [[ -f "../dist/server/dali-toolkit-server-linux-amd64" ]]; then
        mkdir -p bin
        cp "../dist/server/dali-toolkit-server-linux-amd64" bin/server
        chmod +x bin/server
        
        echo "🔨 Building standalone Docker image..."
        docker build -t dali-toolkit-server:standalone .
        docker save dali-toolkit-server:standalone | gzip > "../dist/docker/dali-toolkit-server-standalone.tar.gz"
        echo "  ✅ Standalone Docker: $BUILD_DIR/docker/dali-toolkit-server-standalone.tar.gz"
    fi
    
    # Copy Linux server with web binary
    if [[ -f "../dist/server/dali-toolkit-server-web-linux-amd64" ]]; then
        cp "../dist/server/dali-toolkit-server-web-linux-amd64" bin/server
        chmod +x bin/server
        
        echo "🔨 Building web-enabled Docker image..."
        docker build -t dali-toolkit-server:with-web .
        docker save dali-toolkit-server:with-web | gzip > "../dist/docker/dali-toolkit-server-with-web.tar.gz"
        echo "  ✅ Web-enabled Docker: $BUILD_DIR/docker/dali-toolkit-server-with-web.tar.gz"
    fi
    
    cd "$PROJECT_ROOT"
else
    echo "⚠️ Docker not found, skipping Docker builds"
fi

echo ""

# Generate checksums
echo "🔐 Generating checksums..."
cd "$BUILD_DIR"
find . -type f \( -name "*.apk" -o -name "*.aab" -o -name "*.exe" -o -name "dali-toolkit-server-*" -o -name "*.tar.gz" \) -exec sha256sum {} \; > checksums.txt
echo "  ✅ Checksums: $BUILD_DIR/checksums.txt"

cd "$PROJECT_ROOT"

echo ""
echo "🎉 Build completed successfully!"
echo ""
echo "📦 Generated Artifacts:"
echo "======================"
echo "Flutter Apps:"
if [[ -d "$BUILD_DIR/flutter/web" ]]; then
    echo "  🌐 Web: $BUILD_DIR/flutter/web/"
fi
if [[ -f "$BUILD_DIR/flutter/dali-toolkit-android.apk" ]]; then
    echo "  🤖 Android APK: $BUILD_DIR/flutter/dali-toolkit-android.apk"
fi
if [[ -f "$BUILD_DIR/flutter/dali-toolkit-android.aab" ]]; then
    echo "  📦 Android AAB: $BUILD_DIR/flutter/dali-toolkit-android.aab"
fi
if [[ -d "$BUILD_DIR/flutter/linux" ]]; then
    echo "  🐧 Linux: $BUILD_DIR/flutter/linux/"
fi
if [[ -d "$BUILD_DIR/flutter/macos" ]]; then
    echo "  🍎 macOS: $BUILD_DIR/flutter/macos/"
fi
if [[ -d "$BUILD_DIR/flutter/windows" ]]; then
    echo "  🪟 Windows: $BUILD_DIR/flutter/windows/"
fi
if [[ -d "$BUILD_DIR/flutter/ios" ]]; then
    echo "  📱 iOS: $BUILD_DIR/flutter/ios/"
fi

echo ""
echo "Server Binaries:"
for file in "$BUILD_DIR/server"/dali-toolkit-server-*; do
    if [[ -f "$file" ]]; then
        echo "  🖥️ $(basename "$file")"
    fi
done

echo ""
echo "Docker Images:"
for file in "$BUILD_DIR/docker"/*.tar.gz; do
    if [[ -f "$file" ]]; then
        echo "  🐳 $(basename "$file")"
    fi
done

echo ""
echo "Quick Start:"
echo "============"
echo "1. Server (standalone): ./dist/server/dali-toolkit-server-<platform>-<arch>"
echo "2. Server (with web): ./dist/server/dali-toolkit-server-web-<platform>-<arch>"
echo "3. Docker: docker load < dist/docker/dali-toolkit-server-*.tar.gz && docker run -p 8080:8080 dali-toolkit-server:<variant>"
echo "4. Web interface (if using web-enabled server): http://localhost:8080/app/"
echo "5. API documentation: http://localhost:8080/api/v1/info"