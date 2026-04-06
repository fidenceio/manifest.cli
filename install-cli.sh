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
#   • Trusted HTTPS timestamp verification
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

    # Default to ~/.manifest-cli (user's home directory, no sudo required)
    echo "$HOME/.manifest-cli"
}

# Set the actual installation directory
MANIFEST_CLI_INSTALL_LOCATION="$(get_install_location)"

# Version information
MANIFEST_CLI_MIN_BASH_VERSION="5.0"

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

# Cross-platform in-place sed
# BSD sed (macOS, FreeBSD, OpenBSD, NetBSD) requires -i ''
# GNU sed (Linux, WSL2, Git Bash/MSYS2, Cygwin) requires -i without argument
sed_inplace() {
    case "$OSTYPE" in
        darwin*|freebsd*|openbsd*|netbsd*)
            sed -i '' "$@" ;;
        *)
            sed -i "$@" ;;
    esac
}

migrate_user_global_configuration() {
    local config_file="$HOME/.manifest-cli/manifest.config.global.yaml"
    [ -f "$config_file" ] || return 0

    # Source the YAML module for get_yaml_value / set_yaml_value
    local yaml_module
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    yaml_module="$script_dir/modules/core/manifest-yaml.sh"
    if [[ -f "$yaml_module" ]]; then
        source "$yaml_module"
    elif [[ -f "$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh" ]]; then
        source "$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh"
    else
        print_warning "⚠️  YAML module not found, skipping configuration migration"
        return 0
    fi

    print_subheader "🧭 Migrating User Configuration (Safe Merge)"

    local migrated=0

    local time1 time2 time3 time4 tap_repo
    time1=$(get_yaml_value "$config_file" "time.server1")
    time2=$(get_yaml_value "$config_file" "time.server2")
    time3=$(get_yaml_value "$config_file" "time.server3")
    time4=$(get_yaml_value "$config_file" "time.server4")
    tap_repo=$(get_yaml_value "$config_file" "brew.tap_repo")

    # Migrate only known legacy defaults; preserve user custom values.
    if [ "$time1" = "time.apple.com" ] || [ "$time1" = "216.239.35.0" ]; then
        set_yaml_value "$config_file" "time.server1" "https://www.cloudflare.com/cdn-cgi/trace"
        migrated=$((migrated + 1))
    fi
    if [ "$time2" = "time.google.com" ] || [ "$time2" = "216.239.35.4" ]; then
        set_yaml_value "$config_file" "time.server2" "https://www.google.com/generate_204"
        migrated=$((migrated + 1))
    fi
    if [ "$time3" = "pool.ntp.org" ]; then
        set_yaml_value "$config_file" "time.server3" "https://www.apple.com"
        migrated=$((migrated + 1))
    fi
    if [ "$time4" = "time.nist.gov" ]; then
        set_yaml_value "$config_file" "time.server4" ""
        migrated=$((migrated + 1))
    fi
    if [ "$tap_repo" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        set_yaml_value "$config_file" "brew.tap_repo" "https://github.com/fidenceio/homebrew-tap.git"
        migrated=$((migrated + 1))
    fi

    # Ensure new cache controls exist.
    local cache_ttl cache_cleanup cache_stale
    cache_ttl=$(get_yaml_value "$config_file" "time.cache_ttl")
    if [ -z "$cache_ttl" ]; then
        set_yaml_value "$config_file" "time.cache_ttl" "120"
        migrated=$((migrated + 1))
    fi
    cache_cleanup=$(get_yaml_value "$config_file" "time.cache_cleanup_period")
    if [ -z "$cache_cleanup" ]; then
        set_yaml_value "$config_file" "time.cache_cleanup_period" "3600"
        migrated=$((migrated + 1))
    fi
    cache_stale=$(get_yaml_value "$config_file" "time.cache_stale_max_age")
    if [ -z "$cache_stale" ]; then
        set_yaml_value "$config_file" "time.cache_stale_max_age" "21600"
        migrated=$((migrated + 1))
    fi

    if [ "$migrated" -gt 0 ]; then
        print_success "✅ Migrated $migrated configuration setting(s) in $config_file"
    else
        print_status "ℹ️  No user config migrations needed"
    fi
    echo ""
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
    if [ ! -f "scripts/manifest-cli-wrapper.sh" ]; then
        print_error "❌ This script must be run from the manifest.cli project root directory"
        print_error "   Please navigate to the project root and try again"
        errors=$((errors + 1))
    fi
    
    # Check bash version
    if command_exists bash; then
        local bash_ver=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
        if [ -n "$bash_ver" ]; then
            local major_ver=$(echo "$bash_ver" | cut -d'.' -f1)
            
            if [ "$major_ver" -lt 5 ]; then
                print_error "❌ Bash version $bash_ver detected. Manifest CLI requires Bash 5.0+."
                print_error "   Install Bash 5+ and retry:"
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    print_error "     brew install bash"
                elif command_exists apt-get; then
                    print_error "     sudo apt-get install bash"
                elif command_exists dnf; then
                    print_error "     sudo dnf install bash"
                elif command_exists yum; then
                    print_error "     sudo yum install bash"
                elif command_exists zypper; then
                    print_error "     sudo zypper install bash"
                elif command_exists apk; then
                    print_error "     sudo apk add bash"
                elif command_exists pacman; then
                    print_error "     sudo pacman -S bash"
                else
                    print_error "     Install Bash 5+ using your distro package manager"
                fi
                errors=$((errors + 1))
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

# Clean up legacy installation locations
cleanup_legacy_locations() {
    print_subheader "🧹 Cleaning Up Legacy Installation Locations"

    # Only check for the previous default location
    local legacy_location="/usr/local/share/manifest-cli"

    if [ -d "$legacy_location" ]; then
        print_status "Found legacy installation at: $legacy_location"
        # Try with sudo since it's a system location
        if sudo rm -rf "$legacy_location" 2>/dev/null; then
            print_success "✅ Removed legacy installation: $legacy_location"
        else
            print_warning "⚠️  Could not remove $legacy_location (may need manual cleanup)"
        fi
    else
        print_status "No legacy installations found"
    fi

    print_success "✅ Legacy location cleanup completed"
}

# Clean up old installation using the uninstall module
cleanup_old_installation() {
    print_subheader "🧹 Cleaning Up Old Installation"

    # First, clean up any legacy installation locations
    cleanup_legacy_locations

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
    mkdir -p "$MANIFEST_CLI_INSTALL_LOCATION/docs"
    
    print_success "✅ Directory structure created"
    echo ""
}

# Copy CLI files
copy_cli_files() {
    print_subheader "📦 Copying CLI Files"
    
    # Copy main CLI script
    if [ -f "scripts/manifest-cli-wrapper.sh" ]; then
        cp "scripts/manifest-cli-wrapper.sh" "$MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
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

    # Copy documentation
    if [ -d "docs" ]; then
        cp -r "docs" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied documentation"
    fi

    # Copy example configuration files
    if [ -d "examples" ]; then
        cp -r "examples" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied example configuration files"
    fi

    print_success "✅ All CLI files copied successfully"
    echo ""
}

# Create configuration files
create_configuration() {
    print_subheader "⚙️  Creating Configuration Files"

    local config_dir="$HOME/.manifest-cli"
    local config_file="$config_dir/manifest.config.global.yaml"

    # Ensure the config directory exists
    mkdir -p "$config_dir"

    # Create user's global configuration in home directory if it doesn't exist
    if [ ! -f "$config_file" ]; then
        if [ -f "examples/manifest.config.yaml.example" ]; then
            cp "examples/manifest.config.yaml.example" "$config_file"
            print_success "✅ Global configuration created: $config_file"
        else
            print_warning "⚠️  manifest.config.yaml.example not found, creating basic configuration"
            cat > "$config_file" << 'EOF'
# Manifest CLI Global Configuration
# See: examples/manifest.config.yaml.example for all options

time:
  timezone: "UTC"
  server1: "https://www.cloudflare.com/cdn-cgi/trace"
  server2: "https://www.google.com/generate_204"
  server3: "https://www.apple.com"
  server4: ""
  timeout: 5
  retries: 3
  verify: true
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600

version:
  format: "XX.XX.XX"

git:
  tag_prefix: "v"
  default_branch: "main"

docs:
  folder: "docs"
  archive_folder: "docs/zArchive"
  auto_generate: true

config:
  schema_version: 2
EOF
            print_success "✅ Global configuration created: $config_file"
        fi
    else
        print_status "ℹ️  Global configuration already exists: $config_file (preserved)"
    fi

    # Detect legacy .env config and suggest migration
    if [[ -f "$HOME/.env.manifest.global" ]]; then
        print_warning "⚠️  Legacy config found: $HOME/.env.manifest.global"
        print_warning "   Config has been migrated to YAML: $config_file"
        print_warning "   You can safely remove the old file: rm $HOME/.env.manifest.global"
    fi

    # Apply safe key-level migrations on every install/upgrade run.
    migrate_user_global_configuration

    echo ""
}

# Set up environment variables
setup_environment_variables() {
    print_subheader "🌍 Setting Up Environment Variables"

    local config_file="$HOME/.manifest-cli/manifest.config.global.yaml"

    # Source the YAML module for load_yaml_to_env
    local yaml_module="$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh"
    if [[ -f "$yaml_module" ]]; then
        source "$yaml_module"
    fi

    # Export environment variables from the user's global YAML configuration
    if [ -f "$config_file" ]; then
        if type load_yaml_to_env &>/dev/null; then
            load_yaml_to_env "$config_file"
            print_success "✅ Environment variables loaded from $config_file"
        else
            print_warning "⚠️  YAML module not available, cannot load $config_file"
        fi
    else
        print_warning "⚠️  Configuration file not found: $config_file, using defaults"
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
    echo "   $MANIFEST_CLI_NAME ship patch      # Publish release artifacts (no PR actions)"
    echo "   $MANIFEST_CLI_NAME prep patch      # Prepare changes only"
    echo "   $MANIFEST_CLI_NAME config setup    # Run interactive configuration wizard"
    echo "   $MANIFEST_CLI_NAME test            # Test functionality"
    echo "   $MANIFEST_CLI_NAME test cloud      # Test Manifest Cloud connectivity"
    echo "   $MANIFEST_CLI_NAME test agent      # Test Manifest Agent functionality"
    echo "   $MANIFEST_CLI_NAME time            # Get trusted timestamp"
    echo "   $MANIFEST_CLI_NAME sync            # Sync with remote"
    echo "   $MANIFEST_CLI_NAME cleanup         # Manage historical docs"
    
    echo
    print_status "💡 Next Steps:"
    echo "   1. Configure your Git credentials if not already set"
    echo "   2. Run '$MANIFEST_CLI_NAME test' to verify everything works"
    echo "   3. Customize your global settings in ~/.manifest-cli/manifest.config.global.yaml (e.g., timezone)"
    echo "   4. For project-specific overrides, copy examples/manifest.config.yaml.example to your project root"

    # Add git hooks info if they were installed
    if [ -f ".git/hooks/pre-commit" ] && grep -q "Manifest CLI Pre-Commit Hook" ".git/hooks/pre-commit" 2>/dev/null; then
        echo
        print_status "🔒 Git Hooks Installed:"
        echo "   • Pre-commit hook is active and protecting your commits"
        echo "   • To refresh hooks: Re-run ./install-cli.sh"
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
    echo "   • Global Config: ~/.manifest-cli/manifest.config.global.yaml"
    echo "   • Example Templates: $MANIFEST_CLI_INSTALL_LOCATION/examples/"
    echo "   • For project overrides, copy examples/manifest.config.yaml.example to your project root"
    
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
# Legacy Manual Install Cleanup
# =============================================================================

# Cleanup step used before Homebrew install
cleanup_homebrew_install() {
    local found_legacy=false

    # Check for manual install binary
    if [ -f "$HOME/.local/bin/manifest" ]; then
        found_legacy=true
    fi

    # Check for manual install directory
    if [ -d "$HOME/.manifest-cli" ]; then
        found_legacy=true
    fi

    # Check for legacy system location
    if [ -d "/usr/local/share/manifest-cli" ]; then
        found_legacy=true
    fi

    if [ "$found_legacy" = "false" ]; then
        return 0
    fi

    print_subheader "🧹 Cleaning up previous manual installation"

    # Remove manual install binary
    if [ -f "$HOME/.local/bin/manifest" ]; then
        rm -f "$HOME/.local/bin/manifest"
        print_success "✅ Removed $HOME/.local/bin/manifest"
    fi

    # Remove manual install directory
    if [ -d "$HOME/.manifest-cli" ]; then
        rm -rf "$HOME/.manifest-cli"
        print_success "✅ Removed $HOME/.manifest-cli"
    fi

    # Remove legacy system location
    if [ -d "/usr/local/share/manifest-cli" ]; then
        sudo rm -rf "/usr/local/share/manifest-cli" 2>/dev/null && \
            print_success "✅ Removed /usr/local/share/manifest-cli" || \
            print_warning "⚠️  Could not remove /usr/local/share/manifest-cli (may need manual cleanup)"
    fi

    # Remove PATH entries for ~/.local/bin added by previous installer
    local shell_profiles=("$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc")
    for profile in "${shell_profiles[@]}"; do
        if [ -f "$profile" ] && grep -q '\.local/bin' "$profile" 2>/dev/null; then
            # Remove the manifest-specific PATH export line
            sed_inplace '/export PATH=.*\.local\/bin.*PATH/d' "$profile" 2>/dev/null && \
                print_success "✅ Cleaned PATH entry from $(basename "$profile")"
        fi
    done

    # Clean up manifest environment variables from shell profiles
    if source_manifest_env_management 2>/dev/null; then
        cleanup_all_manifest_env_vars 2>/dev/null
        remove_manifest_from_shell_profiles 2>/dev/null
    fi

    echo ""
}

# =============================================================================
# Homebrew Installation
# =============================================================================

MANIFEST_CLI_TAP="fidenceio/tap"

install_via_homebrew() {
    print_subheader "🍺 Installing via Homebrew"

    # Tap the repository
    if ! brew tap "$MANIFEST_CLI_TAP" 2>/dev/null; then
        print_error "❌ Failed to tap $MANIFEST_CLI_TAP"
        return 1
    fi
    print_success "✅ Tapped $MANIFEST_CLI_TAP"

    # Install or upgrade
    if brew list "$MANIFEST_CLI_TAP/manifest" &>/dev/null; then
        print_status "Manifest CLI already installed via Homebrew, upgrading..."
        brew upgrade "$MANIFEST_CLI_TAP/manifest" 2>/dev/null || true
    else
        if ! brew install "$MANIFEST_CLI_TAP/manifest"; then
            print_error "❌ brew install failed"
            return 1
        fi
    fi

    print_success "✅ Manifest CLI installed via Homebrew"
    echo ""
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

    # On macOS, offer to install Homebrew if not present
    if [[ "$OSTYPE" == "darwin"* ]] && ! command_exists brew; then
        print_status "🍺 macOS detected but Homebrew is not installed"
        print_status "Homebrew is the recommended way to install, upgrade, manage, and cleanly remove Manifest CLI on macOS. Plus, it offers thousands of other packages."
        echo ""
        read -p "   Would you like to install Homebrew? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            print_status "Installing Homebrew..."
            echo ""
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Add Homebrew to PATH for this session (Apple Silicon vs Intel)
            if [ -f "/opt/homebrew/bin/brew" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -f "/usr/local/bin/brew" ]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            if command_exists brew; then
                print_success "✅ Homebrew installed successfully"
            else
                print_error "❌ Homebrew installation failed — falling back to manual install"
            fi
        else
            print_status "Skipping Homebrew — will use manual installation"
        fi
        echo ""
    fi

    # Route through Homebrew when available
    if command_exists brew; then
        print_status "🍺 Homebrew detected — installing via Homebrew"
        echo ""

        # Remove any previous manual installation before Homebrew install
        cleanup_homebrew_install

        if install_via_homebrew; then
            # Set up configuration (shared by both paths)
            create_configuration

            # Install git hooks if in a git repository
            install_git_hooks

            # Verify
            print_subheader "🔍 Verifying Installation"
            local brew_manifest
            brew_manifest="$(brew --prefix)/bin/manifest"
            if [ -x "$brew_manifest" ] && "$brew_manifest" --help >/dev/null 2>&1; then
                print_success "✅ Manifest CLI installed successfully!"
                print_status "📍 Location: $brew_manifest"
                echo ""
                print_subheader "🎉 Installation Complete!"
                echo ""
                print_success "🚀 You can now use the Manifest CLI:"
                echo "   manifest --help          # Show comprehensive help"
                echo "   manifest ship patch        # Publish release artifacts (no PR actions)"
                echo "   manifest prep patch        # Prepare changes only"
                echo "   manifest test            # Test functionality"
                echo "   manifest test cloud      # Test Manifest Cloud connectivity"
                echo "   manifest test agent      # Test Manifest Agent functionality"
                echo "   manifest time            # Get trusted timestamp"
                echo ""
                print_status "💡 To upgrade: brew update && brew upgrade manifest"
                echo ""
            else
                print_error "❌ Homebrew installation verification failed"
                exit 1
            fi
        else
            print_error "❌ Homebrew installation failed"
            exit 1
        fi
    else
        # Fallback: manual installation (Linux, CI, no Homebrew)
        print_status "Homebrew not found — using manual installation"
        echo ""

        validate_system

        cleanup_environment_variables
        cleanup_old_installation
        create_directories
        copy_cli_files
        create_configuration
        setup_environment_variables
        configure_path

        if verify_installation; then
            install_git_hooks
            display_post_install_info
        else
            print_error "❌ Installation verification failed"
            exit 1
        fi
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
