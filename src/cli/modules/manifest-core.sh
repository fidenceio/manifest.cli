#!/bin/bash

# Manifest Core Module
# Main CLI interface and workflow orchestration

# Import modules
# Determine the absolute path to the modules directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR"

# Load configuration at startup
# Get the installation location (three levels up from modules)
INSTALL_LOCATION="$(dirname "$(dirname "$(dirname "$MODULES_DIR")")")"

# Determine the project root (where we're actually working)
# Use the current working directory from the environment, not the script's directory
if [ -n "$PWD" ] && git -C "$PWD" rev-parse --git-dir > /dev/null 2>&1; then
    # We're in a git repository, use current working directory
    PROJECT_ROOT="$PWD"
    # echo "DEBUG: Using PWD as PROJECT_ROOT: $PROJECT_ROOT" >&2
else
    # Not in a git repository, use installation location
    PROJECT_ROOT="$INSTALL_LOCATION"
    # echo "DEBUG: Using INSTALL_LOCATION as PROJECT_ROOT: $PROJECT_ROOT" >&2
fi

# Export variables so they're available to sourced modules
export INSTALL_LOCATION
export PROJECT_ROOT

# Source shared utilities first
source "$MODULES_DIR/manifest-shared-utils.sh"

# Now source modules after variables are set
source "$MODULES_DIR/manifest-config.sh"
source "$MODULES_DIR/manifest-os.sh"
source "$MODULES_DIR/manifest-ntp.sh"
source "$MODULES_DIR/manifest-git.sh"
source "$MODULES_DIR/manifest-security.sh"
source "$MODULES_DIR/manifest-documentation.sh"
source "$MODULES_DIR/manifest-orchestrator.sh"

# Debug output (can be removed in production)
# echo "DEBUG: INSTALL_LOCATION=$INSTALL_LOCATION" >&2
# echo "DEBUG: PROJECT_ROOT=$PROJECT_ROOT" >&2
# echo "DEBUG: Current directory=$(pwd)" >&2
# echo "DEBUG: PWD=$PWD" >&2
# echo "DEBUG: Git check result=$(git -C "$PWD" rev-parse --git-dir 2>&1)" >&2

# Function to get the CLI installation directory dynamically
get_cli_dir() {
    # If we're in a development environment, use the current project root
    if [ -f "$PROJECT_ROOT/VERSION" ] && [ -f "$PROJECT_ROOT/src/cli/manifest-cli-wrapper.sh" ]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    
    # Try to find installed CLI in common locations
    local possible_dirs=(
        "$HOME/.manifest-cli"
        "$HOME/.local/share/manifest-cli"
        "/usr/local/share/manifest-cli"
        "/opt/manifest-cli"
        "/usr/share/manifest-cli"
    )
    
    for dir in "${possible_dirs[@]}"; do
        if [ -d "$dir" ] && [ -f "$dir/VERSION" ] && [ -f "$dir/src/cli/manifest-cli-wrapper.sh" ]; then
            echo "$dir"
            return 0
        fi
    done
    
    # Fallback to project root if nothing else works
    echo "$PROJECT_ROOT"
}

# Set the CLI directory
CLI_DIR="$(get_cli_dir)"
load_configuration "$CLI_DIR"

# Archive old documentation files (delegated to manifest-cleanup-docs.sh)
archive_old_docs() {
    echo "📁 Archiving old documentation files..."
    main_cleanup --force
    echo "   ✅ Documentation archiving completed"
    echo ""
}

# Main workflow function is now handled by manifest-orchestrator.sh

# Update CLI function
update_cli() {
    # Source the auto-update module
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-auto-update.sh"
    
    # Call the update function from the auto-update module
    local args=("$@")
    update_cli_internal "${args[@]}"
}

# Test mode function
manifest_test() {
    local test_type="$1"
    
    echo "🧪 Starting Manifest test mode..."
    echo ""
    
    # Get NTP timestamp
    get_ntp_timestamp
    
    case "$test_type" in
        "versions")
            echo "🔄 Testing version increments..."
            echo ""
            
            local versions=("patch" "minor" "major" "revision")
            for version in "${versions[@]}"; do
                echo "📋 Testing $version increment..."
                echo "   Would increment version to: $(get_next_version "$version")"
                echo ""
            done
            
            echo "✅ Version increment tests completed"
            ;;
        "all")
            echo "🔄 Running comprehensive tests..."
            echo ""
            
            # Test NTP
            echo "🕐 Testing NTP functionality..."
            get_ntp_timestamp
            echo ""
            
            # Test Git operations
            echo "📦 Testing Git operations..."
            echo "   Would sync repository"
            echo "   Would check version files"
            echo "   Would validate Git status"
            echo ""
            
            # Test documentation
            echo "📚 Testing documentation generation..."
            echo "   Would create docs directory"
            echo "   Would generate sample files"
            echo ""
            
            echo "✅ Comprehensive tests completed"
            ;;
        *)
            echo "🔄 Running basic test mode..."
            echo "   No changes will be made"
            echo "   All operations are simulated"
            echo ""
            
            # Get NTP timestamp
            get_ntp_timestamp
            
            # Check repository status
            echo "📋 Repository status:"
            echo "   - Branch: $(git branch --show-current)"
            echo "   - Status: $(git status --porcelain | wc -l) uncommitted changes"
            echo "   - Remotes: $(git remote | wc -l) configured"
            echo ""
            
            echo "✅ Basic test completed"
            ;;
    esac
}

# Helper function to get next version
get_next_version() {
    local increment_type="$1"
    local current_version=""
    
    # Read current version
    if [ -f "VERSION" ]; then
        current_version=$(cat VERSION)

    fi
    
    if [ -z "$current_version" ]; then
        echo "unknown"
        return
    fi
    
    # Parse version components using configuration
    local separator="${MANIFEST_VERSION_SEPARATOR:-.}"
    local major=$(echo "$current_version" | cut -d"$separator" -f1)
    local minor=$(echo "$current_version" | cut -d"$separator" -f2)
    local patch=$(echo "$current_version" | cut -d"$separator" -f3)
    
    case "$increment_type" in
        "patch")
            echo "$major${separator}$minor${separator}$((patch + 1))"
            ;;
        "minor")
            echo "$major${separator}$((minor + 1))${separator}0"
            ;;
        "major")
            echo "$((major + 1))${separator}0${separator}0"
            ;;
        "revision")
            if [ -f "VERSION" ]; then
                local revision=$(echo "$current_version" | cut -d"$separator" -f4)
                if [ -z "$revision" ]; then
                    revision=1
                else
                    revision=$((revision + 1))
                fi
                echo "$major${separator}$minor${separator}$patch${separator}$revision"
            else
                echo "$major${separator}$minor${separator}$((patch + 1))"
            fi
            ;;
        *)
            echo "$current_version"
            ;;
    esac
}

# Auto-update check with cooldown
check_auto_update() {
    # Source the auto-update module
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-auto-update.sh"
    
    # Call the check function from the auto-update module
    check_auto_update_internal
}

# Main command dispatcher
main() {
    # Check for updates in background (with cooldown)
    check_auto_update
    
    local command="$1"
    shift
    
    case "$command" in
        "ntp")
            display_ntp_info
            ;;
        "ntp-config")
            display_ntp_config
            ;;
        "go")
            local increment_type=""
            local interactive=false
            
            # Parse arguments
            while [[ $# -gt 0 ]]; do
                case $1 in
                    "patch"|"minor"|"major"|"revision")
                        increment_type="$1"
                        shift
                        ;;
                    "-i"|"--interactive")
                        interactive=true
                        shift
                        ;;
                    "-p")
                        increment_type="patch"
                        shift
                        ;;
                    "-m")
                        increment_type="minor"
                        shift
                        ;;
                    "-M")
                        increment_type="major"
                        shift
                        ;;
                    "-r")
                        increment_type="revision"
                        shift
                        ;;
                    *)
                        echo "❌ Unknown option: $1"
                        echo "Usage: manifest go [patch|minor|major|revision] [-i|--interactive]"
                        return 1
                        ;;
                esac
            done
            
            # Call the orchestrator's manifest_go function
            source "$MODULES_DIR/manifest-orchestrator.sh"
            manifest_go "$increment_type" "$interactive"
            ;;
        "sync")
            sync_repository
            ;;
        "revert")
            revert_version
            ;;
        "push")
            local increment_type="${1:-patch}"
            local timestamp=$(format_timestamp "$(date -u +%s)" '+%Y-%m-%d %H:%M:%S UTC')
            
            bump_version "$increment_type"
            local new_version=$(cat VERSION 2>/dev/null)
            commit_changes "Bump version to $new_version" "$timestamp"
            create_tag "$new_version"
            push_changes "$new_version"
            ;;
        "commit")
            local message="$1"
            local timestamp=$(format_timestamp "$(date -u +%s)" '+%Y-%m-%d %H:%M:%S UTC')
            commit_changes "$message" "$timestamp"
            ;;
        "version")
            local increment_type="${1:-patch}"
            bump_version "$increment_type"
            ;;
        "docs")
            local subcommand="$1"
            case "$subcommand" in
                "metadata")
                    update_repository_metadata
                    ;;
                "homebrew")
                    echo "🍺 Homebrew functionality is now handled by the orchestrator"
                    echo "   Use 'manifest go' for the complete workflow including Homebrew updates"
                    ;;
                "cleanup")
                    echo "📁 Moving historical documentation to zArchive..."
                    move_existing_historical_docs
                    ;;
                *)
                    # Generate all documentation for current version
                    local current_version=""
                    if [ -f "VERSION" ]; then
                        current_version=$(cat VERSION)
                    fi
                    
                    if [ -z "$current_version" ]; then
                        echo "❌ Could not determine current version. Please run 'manifest version' first."
                        return 1
                    fi
                    
                    local timestamp=$(format_timestamp "$(date -u +%s)" '+%Y-%m-%d %H:%M:%S UTC')
                    source "$MODULES_DIR/manifest-documentation.sh"
                    generate_documents "$current_version" "$timestamp" "patch"
                    ;;
            esac
            ;;
        "cleanup")
            echo "📁 Repository cleanup operations..."
            source "$MODULES_DIR/manifest-cleanup-docs.sh"
            main clean
            ;;
        "config")
            show_configuration
            ;;
        "security")
            manifest_security "$PROJECT_ROOT"
            ;;
        "test")
            test_command "$@"
            ;;
        "update")
            update_cli "$@"
            ;;
        "help"|*)
            display_help
            ;;
    esac
}

# Display help
display_help() {
    echo "Manifest CLI"
    echo ""
    echo "Usage: manifest <command>"
    echo ""
    echo "Commands:"
    echo "  ntp         - 🕐 Get trusted timestamp for manifest operations"
    echo "  ntp-config  - ⚙️  Show and configure timestamp settings"
    echo "  go          - 🚀 Complete automated Manifest workflow (recommended)"
    echo "    go [patch|minor|major|revision] [-i]       # Complete workflow: sync, docs, version, commit, push, metadata"
    echo "    go -p|-m|-M|-r [-i]                        # Short form options with interactive mode"
    echo "    Note: Use -i flag to enable interactive safety prompts (default: non-interactive)"
    echo "  sync        - 🔄 Sync local repo with remote (pull latest changes)"
    echo "  revert      - 🔄 Revert to previous version"
    echo "  push        - Version bump, commit, and push changes"
    echo "  commit      - Commit changes with custom message"
    echo "  version     - Bump version (patch/minor/major)"
      echo "  docs        - 📚 Create documentation and release notes"
  echo "    docs metadata  - 🏷️  Update repository metadata (description, topics, etc.)"
  echo "    docs homebrew  - 🍺 Update Homebrew formula"
  echo "  cleanup     - 📁 Clean repository files and archive old docs"
  echo "  config      - ⚙️  Show current configuration and environment variables"
  echo "  security    - 🔒 Security audit for vulnerabilities and privacy protection"
  echo "  test        - 🧪 Test CLI functionality and workflows"
  echo "  update      - 🔄 Check for and install CLI updates"
  echo "    update [--force] [--check]        # Update options: force update or check only"

    echo "  help        - Show this help"
    echo ""
    echo "This CLI provides comprehensive Git operations and version management."
echo ""
echo "The 'go' command performs a complete workflow: sync → docs → version → commit → push → metadata"
echo ""
echo "Environment Variables:"
echo "  • MANIFEST_INTERACTIVE_MODE  - Interactive safety prompts (true/false, default: false)"
echo "  • MANIFEST_BREW_OPTION       - Control Homebrew functionality (enabled/disabled)"
echo "  • MANIFEST_BREW_INTERACTIVE  - Interactive Homebrew updates (yes/true/1, default: no)"
echo "  • MANIFEST_TAP_REPO          - Homebrew tap repository URL (default: fidenceio/fidenceio-homebrew-tap)"
echo ""
echo "For testing and verification:"
echo "  • manifest test              - Basic functionality test"
echo "  • manifest test versions     - Test version increment logic"
echo "  • manifest test all          - Comprehensive system testing"
}

# Test/dry-run function (delegated to orchestrator)
manifest_test_dry_run() {
    source "$MODULES_DIR/manifest-orchestrator.sh"
    manifest_test_dry_run "$@"
}

source "$MODULES_DIR/manifest-test.sh"
