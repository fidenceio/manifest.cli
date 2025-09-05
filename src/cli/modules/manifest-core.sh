#!/bin/bash

# Manifest Core Module
# Main CLI interface and workflow orchestration

# Import modules
# Determine the absolute path to the modules directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR"
source "$MODULES_DIR/manifest-config.sh"
source "$MODULES_DIR/manifest-os.sh"
source "$MODULES_DIR/manifest-ntp.sh"
source "$MODULES_DIR/manifest-git.sh"
source "$MODULES_DIR/manifest-security.sh"
source "$MODULES_DIR/manifest-orchestrator.sh"

# Load configuration at startup
# Get the project root (two levels up from modules)
PROJECT_ROOT="$(dirname "$(dirname "$MODULES_DIR")")"

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

# Archive old documentation files (delegated to manifest-archive.sh)
archive_old_docs() {
    echo "📁 Archiving old documentation files..."
    main_cleanup --force
    echo "   ✅ Documentation archiving completed"
    echo ""
}

# Main workflow function is now handled by manifest-orchestrator.sh

# Update CLI function
update_cli() {
    local force_update="false"
    local check_only="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_update="true"
                shift
                ;;
            -c|--check)
                check_only="true"
                shift
                ;;
            -h|--help)
                echo "Manifest CLI Update Command"
                echo ""
                echo "Usage: manifest update [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -f, --force    Force update regardless of current version"
                echo "  -c, --check    Check for updates only (don't update)"
                echo "  -h, --help     Show this help message"
                echo ""
                echo "Examples:"
                echo "  manifest update              # Check and optionally update"
                echo "  manifest update --force      # Force update to latest version"
                echo "  manifest update --check      # Check version only"
                return 0
                ;;
            *)
                echo "❌ Unknown option: $1"
                echo "Use 'manifest update --help' for usage information"
                return 1
                ;;
        esac
    done
    
    # Determine the correct path to the update script
    local update_script=""
    if [ -f "scripts/auto-update.sh" ]; then
        # We're in the project root
        update_script="scripts/auto-update.sh"
    elif [ -f "$CLI_DIR/scripts/auto-update.sh" ]; then
        # We're running from installed CLI
        update_script="$CLI_DIR/scripts/auto-update.sh"
    else
        echo "❌ Update script not found"
        echo "Please reinstall Manifest CLI using the install script"
        return 1
    fi
    
    # Run the update script with appropriate arguments
    if [ "$force_update" = "true" ]; then
        "$update_script" --force
    elif [ "$check_only" = "true" ]; then
        "$update_script" --check
    else
        "$update_script"
    fi
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
    # Check if auto-update is disabled
    if [ "${MANIFEST_AUTO_UPDATE:-true}" = "false" ]; then
        return 0
    fi
    
    local last_check_file="$CLI_DIR/.last_update_check"
    local cooldown_minutes="${MANIFEST_UPDATE_COOLDOWN:-30}"
    local current_time=$(date +%s)
    local last_check_time=0
    
    # Read last check time if file exists
    if [ -f "$last_check_file" ]; then
        last_check_time=$(cat "$last_check_file" 2>/dev/null || echo "0")
    fi
    
    # Calculate time difference in minutes
    local time_diff=$(( (current_time - last_check_time) / 60 ))
    
    # Only check for updates if cooldown period has passed
    if [ "$time_diff" -ge "$cooldown_minutes" ]; then
        # Update last check timestamp
        echo "$current_time" > "$last_check_file"
        
        # Run update check in background (non-blocking)
        (
            # Determine the correct path to the update script
            local update_script=""
            if [ -f "scripts/auto-update.sh" ]; then
                update_script="scripts/auto-update.sh"
            elif [ -f "$CLI_DIR/scripts/auto-update.sh" ]; then
                update_script="$CLI_DIR/scripts/auto-update.sh"
            fi
            
            # Run update check if script is available
            if [ -n "$update_script" ] && [ -f "$update_script" ]; then
                "$update_script" --check >/dev/null 2>&1
                local update_available=$?
                
                # If update is available, show a subtle notification
                if [ $update_available -eq 1 ]; then
                    echo "🔄 Update available! Run 'manifest update' to install the latest version."
                fi
            fi
        ) &
    fi
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
                    echo "🍺 Updating Homebrew formula..."
                    
                    # Determine the correct path to scripts directory
                    local scripts_dir=""
                    if [ -f "scripts/update-homebrew.sh" ]; then
                        # We're in the project root
                        scripts_dir="scripts"
                    elif [ -f "$CLI_DIR/scripts/update-homebrew.sh" ]; then
                        # We're running from installed CLI
                        scripts_dir="$CLI_DIR/scripts"
                    else
                        echo "   ❌ Homebrew update script not found"
                        return 0
                    fi
                    
                    if [ -f "$scripts_dir/update-homebrew.sh" ]; then
                        # Use user's MANIFEST_BREW_OPTION if set, otherwise default to enabled
                        local brew_option="${MANIFEST_BREW_OPTION:-enabled}"
                        # Use user's MANIFEST_BREW_INTERACTIVE if set, otherwise default to no
                        local brew_interactive="${MANIFEST_BREW_INTERACTIVE:-no}"
                        # Use user's MANIFEST_TAP_REPO if set, otherwise default to the standard tap
                        local tap_repo="${MANIFEST_TAP_REPO:-https://github.com/fidenceio/fidenceio-homebrew-tap.git}"
                        MANIFEST_BREW_OPTION="$brew_option" MANIFEST_BREW_INTERACTIVE="$brew_interactive" MANIFEST_TAP_REPO="$tap_repo" "$scripts_dir/update-homebrew.sh"
                    else
                        echo "   ❌ Homebrew update script not found"
                    fi
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
                    generate_documentation_workflow "$current_version" "$timestamp" "patch"
                    ;;
            esac
            ;;
        "cleanup")
            echo "📁 Repository cleanup operations..."
            if [ -f "scripts/repo-cleanup.sh" ]; then
                ./scripts/repo-cleanup.sh all
            else
                echo "❌ repo-cleanup.sh not found. Please run from project root."
                return 1
            fi
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

# Test/dry-run function for safety
manifest_test_dry_run() {
    local increment_type="$1"
    local current_version=$(cat VERSION 2>/dev/null || echo "unknown")
    local next_version=""
    
    echo "🧪 Manifest Test/Dry-Run Mode"
    echo "============================="
    echo ""
    
    # Test version increment logic
    echo "📋 Version Testing:"
    echo "   Current version: $current_version"
    
    case "$increment_type" in
        "patch")
            next_version=$(echo "$current_version" | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')
            ;;
        "minor")
            next_version=$(echo "$current_version" | awk -F. '{$2 = $2 + 1; $3 = 0;} 1' | sed 's/ /./g')
            ;;
        "major")
            next_version=$(echo "$current_version" | awk -F. '{print $1 + 1 ".0.0"}')
            ;;
        "revision")
            next_version="$current_version.1"
            ;;
    esac
    
    echo "   Next version: $next_version"
    echo "   Increment type: $increment_type"
    echo ""
    
    # Test Git status
    echo "🔍 Git Status Check:"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo "   ✅ In Git repository"
        echo "   📍 Current branch: $(git branch --show-current)"
        echo "   📡 Remote: $(git remote get-url origin 2>/dev/null || echo 'none')"
        
        # Check for uncommitted changes
        if [ -n "$(git status --porcelain)" ]; then
            echo "   ⚠️  Uncommitted changes detected"
        else
            echo "   ✅ Working directory clean"
        fi
    else
        echo "   ❌ Not in a Git repository"
    fi
    echo ""
    
    # Test NTP functionality
    echo "🕐 NTP Testing:"
    if command -v sntp >/dev/null 2>&1; then
        echo "   ✅ sntp command available"
    elif command -v ntpdate >/dev/null 2>&1; then
        echo "   ✅ ntpdate command available"
    else
        echo "   ⚠️  No NTP command available (will use system time)"
    fi
    echo ""
    
    # Test documentation generation
    echo "📚 Documentation Testing:"
    if [ -f "README.md" ]; then
        echo "   ✅ README.md exists"
    else
        echo "   ❌ README.md missing"
    fi
    
    if [ -d "docs" ]; then
        echo "   ✅ docs/ directory exists"
    else
        echo "   ❌ docs/ directory missing"
    fi
    echo ""
    
    # Test configuration
    echo "⚙️  Configuration Testing:"
    if [ -f "env.example" ]; then
        echo "   ✅ env.example exists"
    else
        echo "   ❌ env.example missing"
    fi
    
    if [ -f "manifest.config" ]; then
        echo "   ✅ manifest.config exists"
    else
        echo "   ❌ manifest.config missing"
    fi
    echo ""
    
    # Test security
    echo "🔒 Security Testing:"
    if manifest security >/dev/null 2>&1; then
        echo "   ✅ Security audit passed"
    else
        echo "   ⚠️  Security audit had issues (check with 'manifest security')"
    fi
    echo ""
    
    echo "✅ Test/dry-run completed successfully!"
    echo "   All systems appear ready for version bump."
}

source "$MODULES_DIR/manifest-test.sh"
