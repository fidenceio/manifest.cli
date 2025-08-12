#!/bin/bash

# Manifest Local CLI Installer
# Installs the Manifest CLI for local development

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.manifest-local"
BIN_DIR="$HOME/.local/bin"

echo "=========================================="
echo "   Manifest Local CLI Installer"
echo "=========================================="
echo ""

# Check prerequisites
log "Checking prerequisites..."

# Check Node.js
if command -v node >/dev/null 2>&1; then
    success "Node.js is available"
else
    error "Node.js is required but not installed"
    echo "Please install Node.js from https://nodejs.org/"
    exit 1
fi

# Check Git
if command -v git >/dev/null 2>&1; then
    success "Git is available"
else
    error "Git is required but not installed"
    echo "Please install Git from https://git-scm.com/"
    exit 1
fi

# Create installation directory
log "Creating installation directory..."
if [ ! -d "$INSTALL_DIR" ]; then
mkdir -p "$INSTALL_DIR"
success "Installation directory created: $INSTALL_DIR"
else
    success "Installation directory already exists: $INSTALL_DIR"
fi

# Copy project files
log "Copying project files..."
cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/examples" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/package.json" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/Dockerfile" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/Dockerfile.test" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/install-client.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/push.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/ENHANCED_FEATURES.md" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/DEPLOYMENT.md" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/.manifestrc.example" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/env.example" "$INSTALL_DIR/"
success "Project files copied"

# Install Node.js dependencies
log "Installing Node.js dependencies..."
cd "$INSTALL_DIR"
npm install --production
success "Node.js dependencies installed"

# Create default configuration
log "Creating default configuration..."
if [ ! -f ".env" ]; then
    cp env.example .env 2>/dev/null || echo "# Manifest Local Configuration" > .env
success "Default configuration created"
else
    success "Configuration already exists"
fi

# Create bin directory if it doesn't exist
if [ ! -d "$BIN_DIR" ]; then
    mkdir -p "$BIN_DIR"
fi

# Create Manifest Local CLI
log "Creating Manifest Local CLI..."
cp "$INSTALL_DIR/src/cli/manifest-cli.sh" "$BIN_DIR/manifest"
chmod +x "$BIN_DIR/manifest"
success "Manifest Local CLI created: $BIN_DIR/manifest"

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
if [ -f "$BIN_DIR/manifest" ]; then
    success "Manifest Local CLI is accessible"
else
    error "Manifest Local CLI installation failed"
    exit 1
fi

if [ -f "$INSTALL_DIR/package.json" ]; then
    success "Project files are ready"
else
    error "Project files are missing"
    exit 1
fi

echo ""
echo "=========================================="
echo "   Installation Summary"
echo "=========================================="
echo "Installation Directory: $INSTALL_DIR"
echo "CLI Location: $BIN_DIR/manifest"
echo "Configuration: $INSTALL_DIR/.env"
echo ""

echo "Next steps:"
echo "1. Configure your cloud service URL in $INSTALL_DIR/.env"
echo "2. Use manifest CLI for Git operations: manifest help"
echo "3. Integrate with Manifest Cloud service for LLM features"
echo ""

echo -e "${GREEN}Installation completed! 🎉${NC}"
echo ""
echo "For help, run: manifest help"
echo ""
echo "Note: This CLI is for local development and Git operations."
echo "It integrates with the Manifest Cloud service for LLM capabilities."
