#!/bin/bash

# Flutter Web Build Script for DALI-Toolkit Integration
# This script builds the Flutter web app and integrates it with the Go server
# Enhanced for CI/CD pipeline compatibility

set -e

echo "DALI-Toolkit Flutter Web Build Script"
echo "======================================"

# Build configuration
BUILD_TYPE="${1:-development}"
SKIP_SERVER_BUILD="${2:-false}"

PROJECT_ROOT="$(pwd)"
FLUTTER_PROJECT_ROOT="$PROJECT_ROOT"
SERVER_ROOT="$PROJECT_ROOT/server"
WEB_EMBED_DIR="$SERVER_ROOT/internal/web/flutter_web"

# Check if this is run from the correct directory
if [[ ! -f "pubspec.yaml" ]]; then
    echo "Error: This script must be run from the Flutter project root (where pubspec.yaml is located)"
    exit 1
fi

echo "🔧 Configuration:"
echo "  Build Type: $BUILD_TYPE"
echo "  Skip Server Build: $SKIP_SERVER_BUILD"
echo "  Flutter Project: $FLUTTER_PROJECT_ROOT"
echo "  Server Project: $SERVER_ROOT"
echo "  Web Embed Directory: $WEB_EMBED_DIR"
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "Flutter is not installed or not in PATH."
    echo "Please install Flutter from https://flutter.dev/docs/get-started/install"
    echo ""
    echo "For now, creating a placeholder web build..."
    
    # Create a minimal web build placeholder
    mkdir -p build/web
    
    # Copy enhanced placeholder files
    cat > build/web/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="DALI-Toolkit Management Interface">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="DALI-Toolkit">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <title>DALI-Toolkit</title>
  <link rel="manifest" href="manifest.json">
  <style>
    body {
      margin: 0;
      padding: 0;
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .container {
      max-width: 800px;
      background: white;
      padding: 40px;
      border-radius: 12px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.1);
      text-align: center;
    }
    .logo {
      width: 80px;
      height: 80px;
      background: #007bff;
      border-radius: 50%;
      margin: 0 auto 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: white;
      font-size: 24px;
      font-weight: bold;
    }
    h1 {
      color: #333;
      margin-bottom: 10px;
    }
    .subtitle {
      color: #666;
      margin-bottom: 30px;
    }
    .status {
      padding: 20px;
      background: #f8f9fa;
      border-radius: 8px;
      margin: 20px 0;
    }
    .btn {
      background: #007bff;
      color: white;
      padding: 12px 24px;
      text-decoration: none;
      border-radius: 6px;
      display: inline-block;
      margin: 10px;
      border: none;
      cursor: pointer;
      transition: background-color 0.3s;
    }
    .btn:hover {
      background: #0056b3;
    }
    .btn-secondary {
      background: #6c757d;
    }
    .btn-secondary:hover {
      background: #545b62;
    }
    .feature-list {
      text-align: left;
      display: inline-block;
      margin: 20px 0;
    }
    .feature-item {
      padding: 8px 0;
      border-bottom: 1px solid #eee;
    }
    .feature-item:last-child {
      border-bottom: none;
    }
    .build-info {
      background: #e3f2fd;
      padding: 15px;
      border-radius: 6px;
      margin: 20px 0;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">DT</div>
    <h1>DALI-Toolkit</h1>
    <div class="subtitle">Device Management Platform</div>
    
    <div id="auth-status" class="status">
      <p>🔄 Checking authentication...</p>
    </div>
    
    <div class="build-info">
      <strong>Flutter Web Integration Ready</strong><br>
      This placeholder will be replaced when Flutter web build is available.
    </div>
    
    <div class="feature-list">
      <strong>Available Features:</strong>
      <div class="feature-item">✅ Device Management API</div>
      <div class="feature-item">✅ Project & Partition Organization</div>
      <div class="feature-item">✅ Permission Management</div>
      <div class="feature-item">✅ WebSocket Cloud Connectivity</div>
      <div class="feature-item">✅ MQTT Device Integration</div>
      <div class="feature-item">🚧 Flutter Web Interface (placeholder)</div>
    </div>
    
    <div>
      <a href="/api/v1/info" class="btn">API Info</a>
      <a href="/api/v1/auth/info" class="btn btn-secondary">Auth Info</a>
      <a href="/health" class="btn btn-secondary">Health Check</a>
    </div>
    
    <script>
      // Check authentication status
      fetch('/api/v1/auth/me', { 
        credentials: 'include',
        headers: { 'Accept': 'application/json' }
      })
      .then(response => {
        const statusEl = document.getElementById('auth-status');
        if (response.ok) {
          return response.json().then(user => {
            statusEl.innerHTML = `
              <p style="color: green;">✅ Authenticated as <strong>${user.username || 'User'}</strong></p>
              <small>Organization: ${user.organization || 'N/A'}</small>
            `;
          });
        } else if (response.status === 401) {
          statusEl.innerHTML = `
            <p style="color: orange;">🔐 Authentication required</p>
            <a href="/api/v1/auth/login" class="btn">Login with Casdoor</a>
          `;
        } else {
          throw new Error('Auth check failed');
        }
      })
      .catch(err => {
        document.getElementById('auth-status').innerHTML = `
          <p style="color: #666;">⚠️ Auth service unavailable</p>
          <small>Server may be starting up...</small>
        `;
      });
      
      // Auto-refresh every 30 seconds
      setTimeout(() => window.location.reload(), 30000);
    </script>
  </div>
</body>
</html>
EOF

    # Copy manifest and other assets
    cp server/internal/web/flutter_web/manifest.json build/web/ 2>/dev/null || true
    
    echo "✅ Placeholder web build created"
else
    echo "✅ Flutter found, building web app..."
    
    # Install dependencies
    echo "📦 Installing Flutter dependencies..."
    flutter pub get
    
    # Build web app
    echo "🔨 Building Flutter web app..."
    if [[ "$BUILD_TYPE" == "production" ]]; then
        flutter build web --release --no-tree-shake-icons --dart-define=FLUTTER_WEB_AUTO_DETECT=true
    else
        flutter build web --no-tree-shake-icons --dart-define=FLUTTER_WEB_AUTO_DETECT=true
    fi
    
    echo "✅ Flutter web build completed"
fi

# Copy build to server embed directory
echo "📂 Integrating with Go server..."
rm -rf "$WEB_EMBED_DIR"/*
mkdir -p "$WEB_EMBED_DIR"
cp -r build/web/* "$WEB_EMBED_DIR/"

echo "✅ Flutter web integrated into server"

# Rebuild server with embedded web app
if [[ "$SKIP_SERVER_BUILD" != "true" ]]; then
    echo "🔨 Rebuilding server with embedded web app..."
    cd "$SERVER_ROOT"
    
    # Check if make build target exists
    if make -n build &>/dev/null; then
        make build
    else
        # Fallback to direct go build
        mkdir -p bin
        go build -o bin/server ./cmd/server
    fi
else
    echo "⏭️ Skipping server build (SKIP_SERVER_BUILD=true)"
fi

echo ""
echo "🎉 Build completed successfully!"
echo ""
echo "📁 Build Output:"
echo "  Flutter Web: $WEB_EMBED_DIR/"
if [[ "$SKIP_SERVER_BUILD" != "true" ]]; then
    echo "  Server Binary: $SERVER_ROOT/bin/server"
fi
echo ""
echo "🚀 Next steps:"
if [[ "$SKIP_SERVER_BUILD" != "true" ]]; then
    echo "1. Start the server: cd server && ./bin/server"
    echo "2. Open web interface: http://localhost:8080/app/"
    echo "3. Check API status: http://localhost:8080/health"
else
    echo "1. Web files ready for embedding in server"
    echo "2. Build server with: cd server && make build"
    echo "3. Or use the comprehensive build script: ./build-all.sh"
fi
echo ""
if [[ "$BUILD_TYPE" == "development" ]]; then
    echo "💡 For production builds, use: ./build-web.sh production"
fi
echo "💡 For all platform builds, use: ./build-all.sh"