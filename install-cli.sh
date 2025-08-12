#!/bin/bash

# Manifest CLI Installation Script
# This script installs the Manifest CLI tool locally

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "src/cli/manifest-cli.sh" ]; then
    print_error "This script must be run from the manifest.cli project root directory"
    print_error "Please navigate to the project root and try again"
    exit 1
fi

print_status "🚀 Installing Manifest CLI..."

# Create local bin directory if it doesn't exist
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# Copy CLI script
print_status "📁 Copying CLI script..."
cp "src/cli/manifest-cli-wrapper.sh" "$LOCAL_BIN/manifest"
chmod +x "$LOCAL_BIN/manifest"

# Copy essential project files
print_status "📦 Copying project files..."
PROJECT_DIR="$HOME/.manifest-cli"
mkdir -p "$PROJECT_DIR"

# Copy only the essential files for CLI operation
cp -r "src" "$PROJECT_DIR/"
cp "package.json" "$PROJECT_DIR/"
cp "README.md" "$PROJECT_DIR/"
cp "VERSION" "$PROJECT_DIR/"
cp ".gitignore" "$PROJECT_DIR/"

# Create default .env configuration
print_status "⚙️  Creating default configuration..."
cat > "$PROJECT_DIR/.env" << 'EOF'
# Manifest CLI Configuration
# This file contains environment-specific settings

# NTP Configuration (optional)
# MANIFEST_NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org,time.nist.gov"
# MANIFEST_NTP_TIMEOUT=5

# Repository Configuration (auto-detected)
# MANIFEST_REPO_PROVIDER=github
# MANIFEST_REPO_OWNER=fidenceio
# MANIFEST_REPO_NAME=manifest.cli

# Git Configuration (uses system defaults)
# MANIFEST_GIT_USER_NAME="Your Name"
# MANIFEST_GIT_USER_EMAIL="your.email@example.com"

# Optional: Manifest Cloud Service (if using)
# MANIFEST_CLOUD_URL=https://your-cloud-service.com
# MANIFEST_CLOUD_API_KEY=your-api-key
EOF

print_success "✅ Configuration file created: $PROJECT_DIR/.env"

# Check if PATH includes local bin
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    print_warning "⚠️  $LOCAL_BIN is not in your PATH"
    print_status "Adding to PATH for current session..."
    export PATH="$LOCAL_BIN:$PATH"
    
    print_warning "⚠️  To make this permanent, add this line to your shell profile:"
    echo "export PATH=\"$LOCAL_BIN:\$PATH\""
    
    # Try to detect shell and suggest the right file
    if [ -n "$ZSH_VERSION" ]; then
        print_status "For zsh, add to: ~/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        print_status "For bash, add to: ~/.bashrc or ~/.bash_profile"
    fi
else
    print_success "✅ $LOCAL_BIN is already in your PATH"
fi

# Verify installation
print_status "🔍 Verifying installation..."
if command -v manifest >/dev/null 2>&1; then
    print_success "✅ Manifest CLI installed successfully!"
    print_status "📋 CLI Version: $(manifest --version 2>/dev/null || echo 'Version info not available')"
    print_status "📍 Location: $(which manifest)"
    print_status "🏠 Project directory: $PROJECT_DIR"
    
    echo
    print_success "🎉 Installation complete! You can now use:"
    echo "  manifest --help          # Show help"
    echo "  manifest go              # Run complete workflow"
    echo "  manifest test            # Test functionality"
    echo "  manifest ntp             # Get NTP timestamp"
    echo "  manifest sync            # Sync with remote"
    
    echo
    print_status "💡 Next steps:"
    echo "  1. Configure your Git credentials if not already set"
    echo "  2. Run 'manifest test' to verify everything works"
    echo "  3. Check the generated documentation in the docs/ folder"
    
else
    print_error "❌ Installation failed - manifest command not found"
    print_error "Please check the installation and try again"
    exit 1
fi

print_status "🚀 Happy manifesting!"
