#!/bin/bash

# =============================================================================
# Manifest CLI Installation Script
# =============================================================================
#
# This script installs the Manifest CLI tool locally with comprehensive
# configuration and validation. The Manifest CLI is a powerful tool for:
#
# 🚀 **Core Features:**
#   • Automated version management (patch, minor, major, revision)
#   • AI-powered documentation generation
#   • Trusted NTP timestamp verification
#   • Git workflow automation (sync, commit, tag, push)
#   • Homebrew formula integration
#   • Historical documentation management
#
# 🎯 **Use Cases:**
#   • Software development teams
#   • DevOps & CI/CD pipelines
#   • Open source projects
#   • Compliance and audit requirements
#
# 📚 **Documentation:**
#   • Comprehensive user guides
#   • Command reference
#   • Installation instructions
#   • Contributing guidelines
#   • Examples and best practices
#
# 🔧 **Architecture:**
#   • Modular design with extensible modules
#   • Cross-platform compatibility
#   • Environment-based configuration
#   • Automated testing framework
#
# =============================================================================

set -e

# =============================================================================
# Configuration & Constants
# =============================================================================

# Colors for rich output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Installation paths
LOCAL_BIN="$HOME/.local/bin"
PROJECT_DIR="$HOME/.manifest-cli"
CLI_NAME="manifest"

# Function to determine the best installation directory
get_install_dir() {
    # Check if user has a preference
    if [ -n "$MANIFEST_INSTALL_DIR" ]; then
        echo "$MANIFEST_INSTALL_DIR"
        return 0
    fi
    
    # Try different locations based on system capabilities
    if [ -w "/usr/local/share" ]; then
        echo "/usr/local/share/manifest-cli"
    elif [ -w "/opt" ]; then
        echo "/opt/manifest-cli"
    elif [ -w "$HOME/.local/share" ]; then
        echo "$HOME/.local/share/manifest-cli"
    else
        echo "$HOME/.manifest-cli"
    fi
}

# Set the actual installation directory
INSTALL_DIR="$(get_install_dir)"

# Version information
MIN_BASH_VERSION="4.0"

# =============================================================================
# Utility Functions
# =============================================================================

# Print colored status messages
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

print_header() {
    echo -e "${BOLD}${CYAN}$1${NC}"
}

print_subheader() {
    echo -e "${BOLD}${PURPLE}$1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system information
get_system_info() {
    print_subheader "🔍 System Information"
    
    # OS Detection
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_NAME="macOS"
        OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
        PACKAGE_MANAGER="Homebrew"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command_exists lsb_release; then
            OS_NAME=$(lsb_release -si)
            OS_VERSION=$(lsb_release -sr)
        else
            OS_NAME="Linux"
            OS_VERSION="Unknown"
        fi
        
        if command_exists apt; then
            PACKAGE_MANAGER="APT"
        elif command_exists yum; then
            PACKAGE_MANAGER="YUM"
        elif command_exists dnf; then
            PACKAGE_MANAGER="DNF"
        else
            PACKAGE_MANAGER="Unknown"
        fi
    else
        OS_NAME="Unknown"
        OS_VERSION="Unknown"
        PACKAGE_MANAGER="Unknown"
    fi
    
    # Shell detection
    SHELL_NAME=$(basename "$SHELL")
    SHELL_VERSION="$($SHELL --version 2>/dev/null | head -n1 || echo 'Unknown')"
    
    # Bash version check
    if command_exists bash; then
        BASH_VERSION=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2 || echo "Unknown")
    else
        BASH_VERSION="Not installed"
    fi
    
    echo "   🖥️  OS: $OS_NAME $OS_VERSION"
    echo "   📦 Package Manager: $PACKAGE_MANAGER"
    echo "   🐚 Shell: $SHELL_NAME"
    echo "   🐍 Bash Version: $BASH_VERSION"
    echo ""
}

# Validate system requirements
validate_system() {
    print_subheader "🔍 System Requirements Validation"
    
    local errors=0
    
    # Check if we're in the right directory
    if [ ! -f "src/cli/manifest-cli.sh" ]; then
        print_error "❌ This script must be run from the manifest.cli project root directory"
        print_error "   Please navigate to the project root and try again"
        errors=$((errors + 1))
    fi
    
    # Check bash version
    if command_exists bash; then
        local bash_ver=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
        if [ -n "$bash_ver" ]; then
            local major_ver=$(echo "$bash_ver" | cut -d'.' -f1)
            local minor_ver=$(echo "$bash_ver" | cut -d'.' -f2)
            
            if [ "$major_ver" -lt 4 ] || ([ "$major_ver" -eq 4 ] && [ "$minor_ver" -lt 0 ]); then
                print_warning "⚠️  Bash version $bash_ver detected. Version 4.0+ recommended."
                print_warning "   Some features may not work correctly with older versions."
            else
                print_success "✅ Bash version $bash_ver meets requirements"
            fi
        fi
    else
        print_error "❌ Bash is not installed or not in PATH"
        errors=$((errors + 1))
    fi
    
    # Check for essential commands
    local required_commands=("git" "curl" "wget")
    for cmd in "${required_commands[@]}"; do
        if command_exists "$cmd"; then
            print_success "✅ $cmd is available"
        else
            print_warning "⚠️  $cmd is not available (some features may be limited)"
        fi
    done
    
    # Check for Node.js (optional but recommended)
    if command_exists node; then
        local node_version=$(node --version)
        print_success "✅ Node.js $node_version is available"
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "❌ System validation failed with $errors error(s)"
        exit 1
    fi
    
    print_success "✅ System validation passed"
    echo ""
}

# =============================================================================
# Installation Functions
# =============================================================================

# Clean up old installation directory
cleanup_old_installation() {
    print_subheader "🧹 Cleaning Up Old Installation"
    
    # Clean up the old .manifest-cli directory
    if [ -d "$PROJECT_DIR" ]; then
        print_status "Removing old installation directory: $PROJECT_DIR"
        rm -rf "$PROJECT_DIR"
        print_success "✅ Old installation directory removed"
    else
        print_success "✅ No old installation directory found"
    fi
    
    # Clean up any old CLI binary
    if [ -f "$LOCAL_BIN/$CLI_NAME" ]; then
        print_status "Removing old CLI binary: $LOCAL_BIN/$CLI_NAME"
        rm -f "$LOCAL_BIN/$CLI_NAME"
        print_success "✅ Old CLI binary removed"
    fi
    
    echo ""
}

# Create directory structure
create_directories() {
    print_subheader "📁 Creating Directory Structure"
    
    # Create local bin directory
    if [ ! -d "$LOCAL_BIN" ]; then
        mkdir -p "$LOCAL_BIN"
        print_success "✅ Created $LOCAL_BIN"
    else
        print_success "✅ $LOCAL_BIN already exists"
    fi
    
    # Create project directory
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
        print_success "✅ Created $INSTALL_DIR"
    else
        print_success "✅ $INSTALL_DIR already exists"
    fi
    
    # Create subdirectories
    mkdir -p "$INSTALL_DIR/src"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/docs"
    
    print_success "✅ Directory structure created"
    echo ""
}

# Copy CLI files
copy_cli_files() {
    print_subheader "📦 Copying CLI Files"
    
    # Copy main CLI script
    if [ -f "src/cli/manifest-cli-wrapper.sh" ]; then
        cp "src/cli/manifest-cli-wrapper.sh" "$LOCAL_BIN/$CLI_NAME"
        chmod +x "$LOCAL_BIN/$CLI_NAME"
        print_success "✅ Copied CLI script to $LOCAL_BIN/$CLI_NAME"
    else
        print_error "❌ CLI wrapper script not found"
        exit 1
    fi
    
    # Copy source modules
    if [ -d "src" ]; then
        cp -r "src" "$INSTALL_DIR/"
        print_success "✅ Copied source modules"
    fi
    
    # Copy essential project files
    local essential_files=("VERSION" ".gitignore")
    for file in "${essential_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$INSTALL_DIR/"
            print_success "✅ Copied $file"
        else
            print_warning "⚠️  $file not found (skipping)"
        fi
    done
    
    # Copy documentation
    if [ -d "docs" ]; then
        cp -r "docs" "$INSTALL_DIR/"
        print_success "✅ Copied documentation"
    fi
    
    # Copy scripts
    if [ -d "scripts" ]; then
        cp -r "scripts" "$INSTALL_DIR/"
        print_success "✅ Copied utility scripts"
    fi
    
    print_success "✅ All CLI files copied successfully"
    echo ""
}

# Create configuration files
create_configuration() {
    print_subheader "⚙️  Creating Configuration Files"
    
    # Create main .env configuration
    cat > "$INSTALL_DIR/.env" << 'EOF'
# =============================================================================
# Manifest CLI Configuration
# =============================================================================
# This file contains environment-specific settings for the Manifest CLI
# Copy this file to your project root and customize as needed
# =============================================================================

# NTP Configuration (Trusted Timestamps)
# Multiple servers for redundancy and accuracy
MANIFEST_NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org,time.nist.gov"
MANIFEST_NTP_TIMEOUT=5
MANIFEST_NTP_RETRIES=3
MANIFEST_NTP_VERIFY=true

# Repository Configuration (Auto-detected)
# These are automatically detected from your git remote
# MANIFEST_REPO_PROVIDER=github
# MANIFEST_REPO_OWNER=fidenceio
# MANIFEST_REPO_NAME=manifest.cli

# Git Configuration (Uses system defaults if not set)
# MANIFEST_GIT_USER_NAME="Your Name"
# MANIFEST_GIT_USER_EMAIL="your.email@example.com"
# MANIFEST_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# Homebrew Integration (macOS)
# MANIFEST_BREW_OPTION=enabled          # enabled/disabled
# MANIFEST_BREW_INTERACTIVE=no          # yes/no
# MANIFEST_TAP_REPO="https://github.com/fidenceio/fidenceio-homebrew-tap.git"

# Documentation Configuration
# MANIFEST_DOCS_TEMPLATE_DIR="./templates"
# MANIFEST_DOCS_AUTO_GENERATE=true
# MANIFEST_DOCS_HISTORICAL_LIMIT=20

# Development & Debugging
# MANIFEST_DEBUG=false
# MANIFEST_VERBOSE=false
# MANIFEST_LOG_LEVEL="INFO"
# MANIFEST_INTERACTIVE=true

# Cloud Services (Future Features)
# MANIFEST_CLOUD_URL=https://your-cloud-service.com
# MANIFEST_CLOUD_API_KEY=your-api-key
# MANIFEST_CLOUD_PROJECT_ID=your-project-id

# =============================================================================
# Quick Start Examples
# =============================================================================
# 1. Basic usage: manifest go patch
# 2. Interactive mode: manifest go minor -i
# 3. Test functionality: manifest test
# 4. Get timestamp: manifest ntp
# 5. Sync repository: manifest sync
# 6. Clean repository files: manifest cleanup
# =============================================================================
EOF

    print_success "✅ Configuration file created: $INSTALL_DIR/.env"
    echo ""
}

# Configure PATH
configure_path() {
    print_subheader "🛤️  Configuring PATH"
    
    if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
        print_warning "⚠️  $LOCAL_BIN is not in your PATH"
        
        # Add to current session
        print_status "Adding to PATH for current session..."
        export PATH="$LOCAL_BIN:$PATH"
        
        # Detect shell and suggest permanent configuration
        local shell_profile=""
        if [ -n "$ZSH_VERSION" ]; then
            shell_profile="$HOME/.zshrc"
            print_status "Detected zsh shell"
        elif [ -n "$BASH_VERSION" ]; then
            if [ -f "$HOME/.bash_profile" ]; then
                shell_profile="$HOME/.bash_profile"
            else
                shell_profile="$HOME/.bashrc"
            fi
            print_status "Detected bash shell"
        fi
        
        if [ -n "$shell_profile" ]; then
            print_warning "⚠️  To make this permanent, add this line to $shell_profile:"
            echo "   export PATH=\"$LOCAL_BIN:\$PATH\""
            
            # Offer to add it automatically
            read -p "   Would you like me to add this to $shell_profile? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$shell_profile"
                print_success "✅ Added to $shell_profile"
                print_status "Please restart your terminal or run: source $shell_profile"
            fi
        fi
    else
        print_success "✅ $LOCAL_BIN is already in your PATH"
    fi
    
    echo ""
}

# Verify installation
verify_installation() {
    print_subheader "🔍 Verifying Installation"
    
    if command_exists "$CLI_NAME"; then
        print_success "✅ Manifest CLI installed successfully!"
        
        # Get version information
        local version_info
        if version_info=$("$CLI_NAME" --version 2>/dev/null); then
            print_status "📋 CLI Version: $version_info"
        else
            print_status "📋 CLI Version: Version info not available"
        fi
        
        print_status "📍 Location: $(which "$CLI_NAME")"
        print_status "🏠 Project directory: $INSTALL_DIR"
        
        # Test basic functionality
        print_status "🧪 Testing basic functionality..."
        if "$CLI_NAME" --help >/dev/null 2>&1; then
            print_success "✅ Help command working"
        else
            print_warning "⚠️  Help command failed"
        fi
        
        return 0
    else
        print_error "❌ Installation failed - $CLI_NAME command not found"
        print_error "Please check the installation and try again"
        return 1
    fi
}

# Display post-installation information
display_post_install_info() {
    print_subheader "🎉 Installation Complete!"
    
    echo
    print_success "🚀 You can now use the Manifest CLI:"
    echo "   $CLI_NAME --help          # Show comprehensive help"
    echo "   $CLI_NAME go              # Run complete workflow"
    echo "   $CLI_NAME test            # Test functionality"
    echo "   $CLI_NAME ntp             # Get NTP timestamp"
    echo "   $CLI_NAME sync            # Sync with remote"
    echo "   $CLI_NAME cleanup         # Manage historical docs"
    
    echo
    print_status "💡 Next Steps:"
    echo "   1. Configure your Git credentials if not already set"
    echo "   2. Run '$CLI_NAME test' to verify everything works"
    echo "   3. Check the generated documentation in the docs/ folder"
    echo "   4. Review and customize $INSTALL_DIR/.env"
    echo "   5. Copy env.example to your project root as .env"
    
    echo
    print_status "📚 Documentation:"
    echo "   • User Guide: $INSTALL_DIR/docs/USER_GUIDE.md"
    echo "   • Command Reference: $INSTALL_DIR/docs/COMMAND_REFERENCE.md"
    echo "   • Examples: $INSTALL_DIR/docs/EXAMPLES.md"
    echo "   • Contributing: $INSTALL_DIR/docs/CONTRIBUTING.md"
    
    echo
    print_status "🔧 Configuration:"
    echo "   • Environment: $INSTALL_DIR/.env"
    echo "   • Project Template: env.example (copy to .env)"
    echo "   • Customize the .env file for your specific needs"
    
    echo
    print_status "🌐 Community & Support:"
    echo "   • GitHub: https://github.com/fidenceio/fidenceio.manifest.cli"
    echo "   • Issues: https://github.com/fidenceio/fidenceio.manifest.cli/issues"
    echo "   • Discussions: https://github.com/fidenceio/fidenceio.manifest.cli/discussions"
    
    echo
    print_success "🚀 Happy manifesting!"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Display banner
    echo
    print_header "============================================================================="
    print_header "🚀 Manifest CLI Installation Script"
    print_header "============================================================================="
    echo
    
    print_status "Welcome to the Manifest CLI installation!"
    print_status "This script will install a powerful CLI tool for versioning,"
    print_status "AI documenting, and repository operations."
    echo
    
    # System validation
    get_system_info
    validate_system
    
    # Installation process
    cleanup_old_installation
    create_directories
    copy_cli_files
    create_configuration
    configure_path
    
    # Verification
    if verify_installation; then
        display_post_install_info
    else
        print_error "❌ Installation verification failed"
        exit 1
    fi
}

# =============================================================================
# Script Execution
# =============================================================================

# Check if script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
else
    # Script is being sourced
    print_warning "⚠️  This script is designed to be executed, not sourced"
    print_warning "   Please run: ./install-cli.sh"
fi
