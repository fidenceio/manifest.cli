#!/bin/bash

# Manifest Cloud Client Installer
# Easy setup for containerized testing environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.manifest-cloud"
BIN_DIR="$HOME/.local/bin"

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

# Header
echo "=========================================="
echo "   Manifest Cloud Client Installer"
echo "=========================================="
echo ""

# Check prerequisites
log "Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
    exit 1
fi
success "Docker is available"

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi
success "Docker Compose is available"

# Check Node.js
if ! command -v node &> /dev/null; then
    error "Node.js is not installed. Please install Node.js first."
    exit 1
fi
success "Node.js is available"

# Check Git
if ! command -v git &> /dev/null; then
    error "Git is not installed. Please install Git first."
    exit 1
fi
success "Git is available"

echo ""

# Create installation directory
log "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
success "Installation directory created: $INSTALL_DIR"

# Copy project files
log "Copying project files..."
cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/tests" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/examples" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/package.json" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/Dockerfile" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/Dockerfile.test" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/"
success "Project files copied"

# Install Node.js dependencies
log "Installing Node.js dependencies..."
cd "$INSTALL_DIR"
npm ci --only=production
success "Node.js dependencies installed"

# Create default configuration
log "Creating default configuration..."
cat > "$INSTALL_DIR/.env" << EOF
# Manifest Cloud Configuration
MANIFEST_SECRET=your-secret-key-here
NODE_ENV=production
PORT=3001

# CORS Configuration
CORS_ORIGIN=*
CORS_METHODS=GET,POST,PUT,DELETE
CORS_CREDENTIALS=true

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# Feature Flags
ENABLE_REPOSITORY_API=true
ENABLE_SECURITY_HEADERS=true
ENABLE_RATE_LIMITING=true
EOF
success "Default configuration created"

# Create manifest-cloud CLI
log "Creating manifest-cloud CLI..."
cat > "$BIN_DIR/manifest-cloud" << 'EOF'
#!/bin/bash

# Manifest Cloud CLI
# Containerized testing and management tool

set -e

SCRIPT_DIR="$HOME/.manifest-cloud"
cd "$SCRIPT_DIR"

case "$1" in
    "test")
        echo "Running comprehensive test suite..."
        ./tests/test-runner.sh
        ;;
    "start")
        echo "Starting Manifest Cloud services..."
        docker-compose up -d --build
        echo "Services started. Access at http://localhost:3001"
        ;;
    "stop")
        echo "Stopping Manifest Cloud services..."
        docker-compose down
        ;;
    "status")
        echo "Service status:"
        docker-compose ps
        ;;
    "logs")
        echo "Service logs:"
        docker-compose logs -f
        ;;
    "install")
        echo "Installing dependencies..."
        docker-compose build --no-cache
        ;;
    "uninstall")
        echo "Removing Manifest Cloud services..."
        docker-compose down -v
        docker system prune -f
        echo "Services removed"
        ;;
    "help"|*)
        echo "Manifest Cloud CLI"
        echo ""
        echo "Usage: manifest-cloud <command>"
        echo ""
        echo "Commands:"
        echo "  test      - Run comprehensive test suite"
        echo "  start     - Start services"
        echo "  stop      - Stop services"
        echo "  status    - Show service status"
        echo "  logs      - Show service logs"
        echo "  install   - Install/rebuild services"
        echo "  uninstall - Remove all services"
        echo "  help      - Show this help"
        ;;
esac
EOF

chmod +x "$BIN_DIR/manifest-cloud"
success "CLI created: $BIN_DIR/manifest-cloud"

# Add to PATH if not already there
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    log "Adding $BIN_DIR to PATH..."
    echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.zshrc"
    echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.bashrc"
    warning "Please restart your terminal or run 'source ~/.zshrc' to use the CLI"
fi

echo ""
log "Installation completed successfully!"
echo ""

# Verification
log "Verifying installation..."
if [ -f "$BIN_DIR/manifest-cloud" ]; then
    success "CLI is accessible"
else
    error "CLI installation failed"
    exit 1
fi

if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    success "Docker Compose configuration is ready"
else
    error "Docker Compose configuration is missing"
    exit 1
fi

echo ""
echo "=========================================="
echo "   Installation Summary"
echo "=========================================="
echo "Installation Directory: $INSTALL_DIR"
echo "CLI Location: $BIN_DIR/manifest-cloud"
echo "Configuration: $INSTALL_DIR/.env"
echo ""

echo "Next steps:"
echo "1. Configure your environment in $INSTALL_DIR/.env"
echo "2. Start services: manifest-cloud start"
echo "3. Run tests: manifest-cloud test"
echo "4. Access service: http://localhost:3001"
echo ""

echo -e "${GREEN}Installation completed! 🎉${NC}"
echo ""
echo "For help, run: manifest-cloud help"
