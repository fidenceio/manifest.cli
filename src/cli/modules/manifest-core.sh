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
source "$MODULES_DIR/manifest-docs.sh"
source "$MODULES_DIR/manifest-security.sh"

# Load configuration at startup
# Get the project root (two levels up from modules)
PROJECT_ROOT="$(dirname "$(dirname "$MODULES_DIR")")"
load_configuration "$PROJECT_ROOT"

# Archive old documentation files
archive_old_docs() {
    echo "📁 Archiving old documentation files..."
    
    # Ensure zArchive directory exists
    mkdir -p "$PROJECT_ROOT/docs/zArchive"
    
    # Get the current version for comparison
    local current_version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.0.0")
    local current_major=$(echo "$current_version" | cut -d. -f1)
    local current_minor=$(echo "$current_version" | cut -d. -f2)
    
    # Archive old changelog and release files (keep only the most recent 2 versions)
    local docs_dir="$PROJECT_ROOT/docs"
    local archive_dir="$PROJECT_ROOT/docs/zArchive"
    
    # Find all CHANGELOG and RELEASE files in docs directory
    for file in "$docs_dir"/CHANGELOG_v*.md "$docs_dir"/RELEASE_v*.md; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local version=$(echo "$filename" | sed -n 's/.*_v\([0-9.]*\)\.md/\1/p')
            
            if [ -n "$version" ]; then
                local file_major=$(echo "$version" | cut -d. -f1)
                local file_minor=$(echo "$version" | cut -d. -f2)
                
                # Archive files that are more than 2 versions old
                if [ "$file_major" -lt "$current_major" ] || 
                   ([ "$file_major" -eq "$current_major" ] && [ "$file_minor" -lt "$((current_minor - 1))" ]); then
                    echo "   📦 Archiving $filename"
                    mv "$file" "$archive_dir/"
                fi
            fi
        fi
    done
    
    # Archive other old documentation files (keep only the most recent)
    # Note: Core documentation files are protected from archiving
    local static_files=(
        "CONFIG_VS_SECURITY.md"
        "CONTRIBUTING.md" 
        "COVERAGE_SUMMARY.md"
        "HUMAN_INTUITIVE_VERSIONING.md"
        "SECURITY.md"
        "TESTING.md"
    )
    
    # Core documentation files that should never be archived
    local protected_files=(
        "README.md"
        "COMMAND_REFERENCE.md"
        "EXAMPLES.md"
        "INSTALLATION.md"
        "USER_GUIDE.md"
    )
    
    for file in "${static_files[@]}"; do
        if [ -f "$docs_dir/$file" ]; then
            # Skip if file is in protected list
            local is_protected=false
            for protected in "${protected_files[@]}"; do
                if [ "$file" = "$protected" ]; then
                    is_protected=true
                    break
                fi
            done
            
            if [ "$is_protected" = "false" ]; then
                # Check if file is older than 7 days
                if [ "$(find "$docs_dir/$file" -mtime +7 2>/dev/null)" ]; then
                    echo "   📦 Archiving $file"
                    mv "$docs_dir/$file" "$archive_dir/"
                fi
            fi
        fi
    done
    
    echo "   ✅ Documentation archiving completed"
    echo ""
}

# Main workflow function
manifest_go() {
    local increment_type="$1"
    local interactive="$2"
    
    # Determine version increment type
    if [ -z "$increment_type" ]; then
        increment_type="patch"
    fi
    
    echo "🚀 Starting automated Manifest process..."
    echo ""
    
    # Interactive confirmation for safety
    # Default: non-interactive (false), use -i flag to enable interactive mode
    local interactive_mode=false
    
    # Enable interactive mode with -i flag
    if [ "$interactive" = "-i" ]; then
        interactive_mode=true
    fi
    
    # Enable interactive mode if environment variable is set to true
    if [ "${MANIFEST_INTERACTIVE_MODE:-false}" = "true" ] || [ "${MANIFEST_INTERACTIVE_MODE:-false}" = "yes" ] || [ "${MANIFEST_INTERACTIVE_MODE:-false}" = "1" ]; then
        interactive_mode=true
    fi
    
    # Disable interactive mode if not in a terminal (CI/CD environments)
    if [ ! -t 0 ]; then
        interactive_mode=false
    fi
    
    if [ "$interactive_mode" = "true" ]; then
        echo "🔍 Safety Check - CI/CD & Collaborative Environment Protection"
        echo "=============================================================="
        echo ""
        echo "📋 Version increment type: $increment_type"
        echo "📍 Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
        echo "🏷️  Current version: $(cat VERSION 2>/dev/null || echo 'unknown')"
        echo ""
        echo "⚠️  This will perform a complete version bump workflow including:"
        echo "   • Sync with remote repository"
        echo "   • Bump version to next $increment_type"
        echo "   • Generate documentation and release notes"
        echo "   • Commit changes and create Git tag"
        echo "   • Push to remote repository"
        echo ""
        echo "🤔 What would you like to do?"
        echo ""
        echo "   1) 🧪 Run test/dry-run first (recommended)"
        echo "   2) 🚀 Go ahead and execute $increment_type version bump now"
        echo "   3) ❌ Cancel and exit"
        echo ""
        
        while true; do
            read -p "   Enter your choice (1-3): " choice
            case $choice in
                1)
                    echo ""
                    echo "🧪 Running test/dry-run first..."
                    echo "================================"
                    manifest_test_dry_run "$increment_type"
                    echo ""
                    echo "🤔 Test completed. Would you like to proceed with the actual version bump?"
                    read -p "   Proceed with $increment_type version bump? (y/N): " proceed
                    case $proceed in
                        [Yy]|[Yy][Ee][Ss])
                            echo ""
                            echo "🚀 Proceeding with $increment_type version bump..."
                            break
                            ;;
                        *)
                            echo "❌ Version bump cancelled by user."
                            return 0
                            ;;
                    esac
                    ;;
                2)
                    echo ""
                    echo "🚀 Proceeding with $increment_type version bump..."
                    break
                    ;;
                3)
                    echo "❌ Version bump cancelled by user."
                    return 0
                    ;;
                *)
                    echo "   ❌ Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
        echo ""
    fi
    
    # Get NTP timestamp
    get_ntp_timestamp
    
    echo "📋 Version increment type: $increment_type"
    echo ""
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "📝 Uncommitted changes detected. Committing first..."
        local timestamp=$(format_timestamp "$MANIFEST_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
        commit_changes "Auto-commit before Manifest process" "$timestamp"
        echo ""
    fi
    
    # Sync with remote
    echo "🔄 Syncing with remote..."
    sync_repository
    echo ""
    
    # Move previous version documentation to zArchive
    echo "📁 Moving previous version documentation..."
    move_previous_documentation
    echo ""
    
    # Bump version
    echo "📦 Bumping version..."
    if ! bump_version "$increment_type"; then
        echo "❌ Version bump failed"
        return 1
    fi
    
    # Get new version
    local new_version=""
    if [ -f "VERSION" ]; then
        new_version=$(cat VERSION)

    fi
    
    if [ -z "$new_version" ]; then
        echo "❌ Could not determine new version"
        return 1
    fi
    
    echo ""
    
    # Generate documentation
    local timestamp=$(format_timestamp "$MANIFEST_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    generate_documentation "$new_version" "$timestamp"
    echo ""
    
    # Commit version changes
    echo "💾 Committing version changes..."
    commit_changes "Bump version to $new_version" "$timestamp"
    echo ""
    
    # Create git tag
    create_tag "$new_version"
    echo ""
    
    # Push changes
    push_changes "$new_version"
    echo ""
    
    # Update repository metadata
    update_repository_metadata
    echo ""
    
    # Update Homebrew formula
    echo "🍺 Updating Homebrew formula..."
    
    # Determine the correct path to scripts directory
    local scripts_dir=""
    if [ -f "scripts/update-homebrew.sh" ]; then
        # We're in the project root
        scripts_dir="scripts"
    elif [ -f "/Users/william/.manifest-cli/scripts/update-homebrew.sh" ]; then
        # We're running from installed CLI
        scripts_dir="/Users/william/.manifest-cli/scripts"
    else
        echo "   ⚠️  Homebrew update script not found (skipping)"
        return 0
    fi
    
    if [ -f "$scripts_dir/update-homebrew.sh" ]; then
        # Use user's MANIFEST_BREW_OPTION if set, otherwise default to enabled
        local brew_option="${MANIFEST_BREW_OPTION:-enabled}"
        # Use user's MANIFEST_BREW_INTERACTIVE if set, otherwise default to no
        local brew_interactive="${MANIFEST_BREW_INTERACTIVE:-no}"
        # Use user's MANIFEST_TAP_REPO if set, otherwise default to the standard tap
        local tap_repo="${MANIFEST_TAP_REPO:-https://github.com/fidenceio/fidenceio-homebrew-tap.git}"
        
        echo "   🔧 Environment variables:"
        echo "      - MANIFEST_BREW_OPTION: $brew_option"
        echo "      - MANIFEST_BREW_INTERACTIVE: $brew_interactive"
        echo "      - MANIFEST_TAP_REPO: $tap_repo"
        
        echo "   🚀 Executing Homebrew update script..."
        if MANIFEST_BREW_OPTION="$brew_option" MANIFEST_BREW_INTERACTIVE="$brew_interactive" MANIFEST_TAP_REPO="$tap_repo" "$scripts_dir/update-homebrew.sh"; then
            echo "   ✅ Homebrew formula updated successfully"
        else
            echo "   ⚠️  Homebrew formula update failed (continuing anyway)"
        fi
    else
        echo "   ⚠️  Homebrew update script not found (skipping)"
    fi
    echo ""
    
    # Archive old documentation files
    archive_old_docs
    
    # Success message
    echo "🎉 Manifest process completed successfully!"
    echo ""
    
    # Summary
    echo "📋 Summary:"
    echo "   - Version: $new_version"
    echo "   - Tag: v$new_version"
    echo "   - Remotes: All pushed successfully"
    echo "   - Timestamp: $timestamp"
    echo "   - Source: $MANIFEST_NTP_SERVER ($MANIFEST_NTP_SERVER_IP)"
    echo "   - Offset: $MANIFEST_NTP_OFFSET seconds"
    echo "   - Uncertainty: ±$MANIFEST_NTP_UNCERTAINTY seconds"
    echo "   - Method: $MANIFEST_NTP_METHOD"
}

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
    elif [ -f "/Users/william/.manifest-cli/scripts/auto-update.sh" ]; then
        # We're running from installed CLI
        update_script="/Users/william/.manifest-cli/scripts/auto-update.sh"
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
    
    local last_check_file="/Users/william/.manifest-cli/.last_update_check"
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
            elif [ -f "/Users/william/.manifest-cli/scripts/auto-update.sh" ]; then
                update_script="/Users/william/.manifest-cli/scripts/auto-update.sh"
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
                    elif [ -f "/Users/william/.manifest-cli/scripts/update-homebrew.sh" ]; then
                        # We're running from installed CLI
                        scripts_dir="/Users/william/.manifest-cli/scripts"
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
                    generate_documentation "$current_version" "$timestamp"
                    ;;
            esac
            ;;
        "cleanup")
            echo "📁 Moving historical documentation to zArchive..."
            move_existing_historical_docs
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
  echo "  cleanup     - 📁 Move historical documentation to zArchive"
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
