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
MANIFEST_CLI_LOCAL_BIN="$HOME/.local/bin"
MANIFEST_CLI_NAME="manifest"

# Function to determine the best installation directory
get_install_location() {
    # Check if user has a preference
    if [ -n "$MANIFEST_CLI_INSTALL_LOCATION" ]; then
        echo "$MANIFEST_CLI_INSTALL_LOCATION"
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
MANIFEST_CLI_INSTALL_LOCATION="$(get_install_location)"

# Version information
MANIFEST_CLI_MIN_BASH_VERSION="4.0"

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
    if [ ! -f "manifest-cli.sh" ]; then
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

# Source the uninstall module for cleanup
source_manifest_uninstall() {
    # Get the directory where this script is located
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local modules_dir="$script_dir/modules"
    
    # Source shared utilities first
    if [ -f "$modules_dir/core/manifest-shared-utils.sh" ]; then
        source "$modules_dir/core/manifest-shared-utils.sh"
    fi
    
    # Source the uninstall module
    if [ -f "$modules_dir/system/manifest-uninstall.sh" ]; then
        source "$modules_dir/system/manifest-uninstall.sh"
    else
        print_error "❌ Uninstall module not found: $modules_dir/system/manifest-uninstall.sh"
        return 1
    fi
}

# Source the environment management module
source_manifest_env_management() {
    # Get the directory where this script is located
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local modules_dir="$script_dir/modules"
    
    # Source shared utilities first
    if [ -f "$modules_dir/core/manifest-shared-utils.sh" ]; then
        source "$modules_dir/core/manifest-shared-utils.sh"
    fi
    
    # Source the environment management module
    if [ -f "$modules_dir/core/manifest-env-management.sh" ]; then
        source "$modules_dir/core/manifest-env-management.sh"
    else
        print_error "❌ Environment management module not found: $modules_dir/core/manifest-env-management.sh"
        return 1
    fi
}

# Clean up environment variables
cleanup_environment_variables() {
    print_subheader "🧹 Cleaning Up Manifest CLI Environment Variables"
    
    # Source the environment management module
    if ! source_manifest_env_management; then
        print_error "❌ Failed to load environment management module"
        print_error "❌ Cannot proceed with environment cleanup"
        return 1
    fi
    
    # Clean up all Manifest CLI-related environment variables
    cleanup_all_manifest_env_vars
    
    # Remove Manifest CLI variables from shell profile files
    remove_manifest_from_shell_profiles
    
    print_success "✅ Environment variable cleanup completed"
}

# Clean up old installation using the uninstall module
cleanup_old_installation() {
    print_subheader "🧹 Cleaning Up Old Installation"
    
    # Source the uninstall module
    if ! source_manifest_uninstall; then
        print_error "❌ Failed to load uninstall module"
        print_error "❌ Cannot proceed with installation without cleanup capability"
        return 1
    fi
    
    # Use the uninstall module for comprehensive cleanup
    # Parameters: skip_confirmations=true, non_interactive=true
    uninstall_manifest "true" "true"
}

# Create directory structure
create_directories() {
    print_subheader "📁 Creating Directory Structure"
    
    # Create local bin directory
    if [ ! -d "$MANIFEST_CLI_LOCAL_BIN" ]; then
        mkdir -p "$MANIFEST_CLI_LOCAL_BIN"
        print_success "✅ Created $MANIFEST_CLI_LOCAL_BIN"
    else
        print_success "✅ $MANIFEST_CLI_LOCAL_BIN already exists"
    fi
    
    # Create project directory
    if [ ! -d "$MANIFEST_CLI_INSTALL_LOCATION" ]; then
        mkdir -p "$MANIFEST_CLI_INSTALL_LOCATION"
        print_success "✅ Created $MANIFEST_CLI_INSTALL_LOCATION"
    else
        print_success "✅ $MANIFEST_CLI_INSTALL_LOCATION already exists"
    fi
    
    # Create subdirectories
    mkdir -p "$MANIFEST_CLI_INSTALL_LOCATION/src"
    mkdir -p "$MANIFEST_CLI_INSTALL_LOCATION/scripts"
    mkdir -p "$MANIFEST_CLI_INSTALL_LOCATION/docs"
    
    print_success "✅ Directory structure created"
    echo ""
}

# Copy CLI files
copy_cli_files() {
    print_subheader "📦 Copying CLI Files"
    
    # Copy main CLI script
    if [ -f "manifest-cli-wrapper.sh" ]; then
        cp "manifest-cli-wrapper.sh" "$MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
        chmod +x "$MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
        print_success "✅ Copied CLI script to $MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
    else
        print_error "❌ CLI wrapper script not found"
        exit 1
    fi
    
    # Copy source modules
    if [ -d "modules" ]; then
        cp -r "modules" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied source modules"
    fi
    
    # Copy essential project files
    local essential_files=("$MANIFEST_CLI_VERSION_FILE" "$MANIFEST_CLI_GITIGNORE_FILE")
    for file in "${essential_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$MANIFEST_CLI_INSTALL_LOCATION/"
            print_success "✅ Copied $file"
        else
            print_warning "⚠️  $file not found (skipping)"
        fi
    done
    
    # Copy documentation
    if [ -d "docs" ]; then
        cp -r "docs" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied documentation"
    fi
    
    # Copy scripts
    if [ -d "scripts" ]; then
        cp -r "scripts" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied utility scripts"
    fi
    
    print_success "✅ All CLI files copied successfully"
    echo ""
}

# Create configuration files
create_configuration() {
    print_subheader "⚙️  Creating Configuration Files"
    
    # Copy global configuration template
    if [ -f "env.manifest.global.example" ]; then
        cp "env.manifest.global.example" "$MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global"
        print_success "✅ Global configuration template copied: $MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global"
    else
        print_warning "⚠️  env.manifest.global.example not found, creating basic configuration"
        # Create minimal configuration if template not found
        cat > "$MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global" << 'EOF'
# =============================================================================
# Manifest CLI Configuration
# =============================================================================
# Copy env.manifest.global.example to customize this file
# =============================================================================

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1=time.apple.com
MANIFEST_CLI_NTP_SERVER2=time.google.com
MANIFEST_CLI_NTP_SERVER3=pool.ntp.org
MANIFEST_CLI_NTP_SERVER4=time.nist.gov
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=3
MANIFEST_CLI_NTP_VERIFY=true

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT=XX.XX.XX
MANIFEST_CLI_GIT_TAG_PREFIX=v
MANIFEST_CLI_GIT_DEFAULT_BRANCH=main

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER=docs
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER=docs/zArchive
MANIFEST_CLI_DOCS_AUTO_GENERATE=true

# Interactive Mode
MANIFEST_CLI_INTERACTIVE_MODE=false
EOF
    fi

    print_success "✅ Configuration file created: $MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global"
    echo ""
}

# Set up environment variables
setup_environment_variables() {
    print_subheader "🌍 Setting Up Environment Variables"
    
    # Source the environment management module
    if ! source_manifest_env_management; then
        print_error "❌ Failed to load environment management module"
        return 1
    fi
    
    # Export environment variables from the configuration file
    if [ -f "$MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global" ]; then
        export_env_from_config "$MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global"
        print_success "✅ Environment variables loaded from configuration"
    else
        print_warning "⚠️  Configuration file not found, using defaults"
    fi
    
    # Set essential installation variables
    export MANIFEST_CLI_INSTALL_DIR="$MANIFEST_CLI_INSTALL_LOCATION"
    export MANIFEST_CLI_BIN_DIR="$MANIFEST_CLI_LOCAL_BIN"
    export MANIFEST_CLI_VERSION_FILE="VERSION"
    export MANIFEST_CLI_GITIGNORE_FILE=".gitignore"
    
    print_success "✅ Environment variables configured"
    echo ""
}

# Configure PATH
configure_path() {
    print_subheader "🛤️  Configuring PATH"
    
    if [[ ":$PATH:" != *":$MANIFEST_CLI_LOCAL_BIN:"* ]]; then
        print_warning "⚠️  $MANIFEST_CLI_LOCAL_BIN is not in your PATH"
        
        # Add to current session
        print_status "Adding to PATH for current session..."
        export PATH="$MANIFEST_CLI_LOCAL_BIN:$PATH"
        
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
            echo "   export PATH=\"$MANIFEST_CLI_LOCAL_BIN:\$PATH\""
            
            # Offer to add it automatically
            read -p "   Would you like me to add this to $shell_profile? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "export PATH=\"$MANIFEST_CLI_LOCAL_BIN:\$PATH\"" >> "$shell_profile"
                print_success "✅ Added to $shell_profile"
                print_status "Please restart your terminal or run: source $shell_profile"
            fi
        fi
    else
        print_success "✅ $MANIFEST_CLI_LOCAL_BIN is already in your PATH"
    fi
    
    echo ""
}

# Verify installation
verify_installation() {
    print_subheader "🔍 Verifying Installation"
    
    if command_exists "$MANIFEST_CLI_NAME"; then
        print_success "✅ Manifest CLI installed successfully!"
        
        # Get version information
        local version_info
        if version_info=$("$MANIFEST_CLI_NAME" --version 2>/dev/null); then
            print_status "📋 CLI Version: $version_info"
        else
            print_status "📋 CLI Version: Version info not available"
        fi
        
        # Determine project root (current working directory if in git repo)
        if [ -n "$PWD" ] && git -C "$PWD" rev-parse --git-dir > /dev/null 2>&1; then
            PROJECT_ROOT="$PWD"
        else
            PROJECT_ROOT="$MANIFEST_CLI_INSTALL_LOCATION"
        fi
        
        print_status "📍 Location: $(which "$MANIFEST_CLI_NAME")"
        print_status "🏠 Project directory: $PROJECT_ROOT"
        
        # Test basic functionality
        print_status "🧪 Testing basic functionality..."
        if "$MANIFEST_CLI_NAME" --help >/dev/null 2>&1; then
            print_success "✅ Help command working"
        else
            print_warning "⚠️  Help command failed"
        fi
        
        return 0
    else
        print_error "❌ Installation failed - $MANIFEST_CLI_NAME command not found"
        print_error "Please check the installation and try again"
        return 1
    fi
}

# Display post-installation information
display_post_install_info() {
    print_subheader "🎉 Installation Complete!"
    
    echo
    print_success "🚀 You can now use the Manifest CLI:"
    echo "   $MANIFEST_CLI_NAME --help          # Show comprehensive help"
    echo "   $MANIFEST_CLI_NAME go              # Run complete workflow"
    echo "   $MANIFEST_CLI_NAME test            # Test functionality"
    echo "   $MANIFEST_CLI_NAME ntp             # Get NTP timestamp"
    echo "   $MANIFEST_CLI_NAME sync            # Sync with remote"
    echo "   $MANIFEST_CLI_NAME cleanup         # Manage historical docs"
    
    echo
    print_status "💡 Next Steps:"
    echo "   1. Configure your Git credentials if not already set"
    echo "   2. Run '$MANIFEST_CLI_NAME test' to verify everything works"
    echo "   3. Check the generated documentation in the docs/ folder"
    echo "   4. Review and customize $MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global"
    echo "   5. Copy env.manifest.global.example to your project root as .env.manifest.global"

    # Add git hooks info if they were installed
    if [ -f ".git/hooks/pre-commit" ] && grep -q "Manifest CLI Pre-Commit Hook" ".git/hooks/pre-commit" 2>/dev/null; then
        echo
        print_status "🔒 Git Hooks Installed:"
        echo "   • Pre-commit hook is active and protecting your commits"
        echo "   • To update hooks: Re-run ./install-cli.sh"
        echo "   • Documentation: docs/GIT_HOOKS.md"
    fi
    
    echo
    print_status "📚 Documentation:"
    echo "   • User Guide: $MANIFEST_CLI_INSTALL_LOCATION/docs/USER_GUIDE.md"
    echo "   • Command Reference: $MANIFEST_CLI_INSTALL_LOCATION/docs/COMMAND_REFERENCE.md"
    echo "   • Examples: $MANIFEST_CLI_INSTALL_LOCATION/docs/EXAMPLES.md"
    echo "   • Contributing: $MANIFEST_CLI_INSTALL_LOCATION/docs/CONTRIBUTING.md"
    
    echo
    print_status "🔧 Configuration:"
    echo "   • Environment: $MANIFEST_CLI_INSTALL_LOCATION/.env.manifest.global"
    echo "   • Global Template: env.manifest.global.example (copy to .env.manifest.global)"
    echo "   • Customize the .env.manifest.global file for your specific needs"
    
    echo
    print_status "🌐 Community & Support:"
    echo "   • GitHub: https://github.com/fidenceio/fidenceio.manifest.cli"
    echo "   • Issues: https://github.com/fidenceio/fidenceio.manifest.cli/issues"
    echo "   • Discussions: https://github.com/fidenceio/fidenceio.manifest.cli/discussions"
    
    echo
    print_success "🚀 Happy manifesting!"
}

# =============================================================================
# Git Hooks Installation
# =============================================================================

install_git_hooks() {
    print_subheader "🔒 Installing Git Hooks"

    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        print_warning "⚠️  Not in a Git repository, skipping git hooks installation"
        print_warning "   Run './install-git-hooks.sh' manually when in a git repository"
        return 0
    fi

    local GIT_HOOKS_SOURCE_DIR=".git-hooks"
    local GIT_HOOKS_TARGET_DIR=".git/hooks"
    local PRE_COMMIT_SOURCE="$GIT_HOOKS_SOURCE_DIR/pre-commit"
    local PRE_COMMIT_TARGET="$GIT_HOOKS_TARGET_DIR/pre-commit"

    # Check if git hooks source directory exists
    if [ ! -d "$GIT_HOOKS_SOURCE_DIR" ]; then
        print_warning "⚠️  Git hooks source directory not found: $GIT_HOOKS_SOURCE_DIR"
        print_warning "   Skipping git hooks installation"
        return 0
    fi

    # Create hooks directory if it doesn't exist
    if [ ! -d "$GIT_HOOKS_TARGET_DIR" ]; then
        mkdir -p "$GIT_HOOKS_TARGET_DIR"
        print_success "✅ Created git hooks directory"
    fi

    # Check if pre-commit hook source exists
    if [ ! -f "$PRE_COMMIT_SOURCE" ]; then
        print_warning "⚠️  Pre-commit hook source not found: $PRE_COMMIT_SOURCE"
        print_warning "   Skipping git hooks installation"
        return 0
    fi

    # Backup existing hook if it exists
    if [ -f "$PRE_COMMIT_TARGET" ]; then
        local BACKUP_FILE="$PRE_COMMIT_TARGET.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "⚠️  Existing pre-commit hook found"
        print_warning "   Creating backup: $BACKUP_FILE"
        cp "$PRE_COMMIT_TARGET" "$BACKUP_FILE"
    fi

    # Copy and install the hook
    cp "$PRE_COMMIT_SOURCE" "$PRE_COMMIT_TARGET"
    chmod +x "$PRE_COMMIT_TARGET"

    # Verify installation
    if [ -f "$PRE_COMMIT_TARGET" ] && [ -x "$PRE_COMMIT_TARGET" ]; then
        if grep -q "Manifest CLI Pre-Commit Hook" "$PRE_COMMIT_TARGET" 2>/dev/null; then
            print_success "✅ Git hooks installed successfully"
            echo
            print_success "🔒 Security features enabled:"
            print_success "   • Blocks commits with private environment files"
            print_success "   • Scans for sensitive data patterns (API keys, tokens, passwords)"
            print_success "   • Verifies .gitignore configuration"
            print_success "   • Detects large files (>10MB)"
            print_success "   • Integrates with Manifest CLI security module"
        else
            print_warning "⚠️  Git hooks installed but content verification failed"
        fi
    else
        print_warning "⚠️  Git hooks installation failed"
    fi

    echo
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
    cleanup_environment_variables
    cleanup_old_installation
    create_directories
    copy_cli_files
    create_configuration
    setup_environment_variables
    configure_path

    # Verification
    if verify_installation; then
        # Install git hooks if in a git repository
        install_git_hooks

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
