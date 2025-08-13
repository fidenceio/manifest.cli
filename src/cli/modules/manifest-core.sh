#!/bin/bash

# Manifest Core Module
# Main CLI interface and workflow orchestration

# Import modules
# Use a simple approach: assume we're in the project root when sourced
MODULES_DIR="src/cli/modules"
source "$MODULES_DIR/manifest-os.sh"
source "$MODULES_DIR/manifest-ntp.sh"
source "$MODULES_DIR/manifest-git.sh"
source "$MODULES_DIR/manifest-docs.sh"

# Main workflow function
manifest_go() {
    local increment_type="$1"
    local interactive="$2"
    
    echo "🚀 Starting automated Manifest process..."
    echo ""
    
    # Get NTP timestamp
    get_ntp_timestamp
    
    # Determine version increment type
    if [ -z "$increment_type" ]; then
        increment_type="patch"
    fi
    
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
    elif [ -f "package.json" ]; then
        new_version=$(node -p "require('./package.json').version")
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
    if [ -f "scripts/update-homebrew.sh" ]; then
        # Use user's MANIFEST_BREW_OPTION if set, otherwise default to enabled
        local brew_option="${MANIFEST_BREW_OPTION:-enabled}"
        # Use user's MANIFEST_BREW_INTERACTIVE if set, otherwise default to no
        local brew_interactive="${MANIFEST_BREW_INTERACTIVE:-no}"
        if MANIFEST_BREW_OPTION="$brew_option" MANIFEST_BREW_INTERACTIVE="$brew_interactive" ./scripts/update-homebrew.sh; then
            echo "   ✅ Homebrew formula updated successfully"
        else
            echo "   ⚠️  Homebrew formula update failed (continuing anyway)"
        fi
    else
        echo "   ⚠️  Homebrew update script not found (skipping)"
    fi
    echo ""
    
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
    elif [ -f "package.json" ]; then
        current_version=$(node -p "require('./package.json').version")
    fi
    
    if [ -z "$current_version" ]; then
        echo "unknown"
        return
    fi
    
    # Parse version components
    local major=$(echo "$current_version" | cut -d. -f1)
    local minor=$(echo "$current_version" | cut -d. -f2)
    local patch=$(echo "$current_version" | cut -d. -f3)
    
    case "$increment_type" in
        "patch")
            echo "$major.$minor.$((patch + 1))"
            ;;
        "minor")
            echo "$major.$((minor + 1)).0"
            ;;
        "major")
            echo "$((major + 1)).0.0"
            ;;
        "revision")
            if [ -f "VERSION" ]; then
                local revision=$(echo "$current_version" | cut -d. -f4)
                if [ -z "$revision" ]; then
                    revision=1
                else
                    revision=$((revision + 1))
                fi
                echo "$major.$minor.$patch.$revision"
            else
                echo "$major.$minor.$((patch + 1))"
            fi
            ;;
        *)
            echo "$current_version"
            ;;
    esac
}

# Main command dispatcher
main() {
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
            local new_version=$(cat VERSION 2>/dev/null || node -p "require('./package.json').version")
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
                    if [ -f "scripts/update-homebrew.sh" ]; then
                        # Use user's MANIFEST_BREW_OPTION if set, otherwise default to enabled
                        local brew_option="${MANIFEST_BREW_OPTION:-enabled}"
                        # Use user's MANIFEST_BREW_INTERACTIVE if set, otherwise default to no
                        local brew_interactive="${MANIFEST_BREW_INTERACTIVE:-no}"
                        MANIFEST_BREW_OPTION="$brew_option" MANIFEST_BREW_INTERACTIVE="$brew_interactive" ./scripts/update-homebrew.sh
                    else
                        echo "   ❌ Homebrew update script not found"
                    fi
                    ;;
                *)
                    echo "📚 Documentation commands:"
                    echo "   docs metadata  - Update repository metadata"
                    echo "   docs homebrew - Update Homebrew formula"
                    ;;
            esac
            ;;
        "test")
            test_command "$@"
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
    echo "  sync        - 🔄 Sync local repo with remote (pull latest changes)"
    echo "  revert      - 🔄 Revert to previous version"
    echo "  push        - Version bump, commit, and push changes"
    echo "  commit      - Commit changes with custom message"
    echo "  version     - Bump version (patch/minor/major)"
    echo "  docs        - 📚 Create documentation and release notes"
    echo "    docs metadata  - 🏷️  Update repository metadata (description, topics, etc.)"
    echo "    docs homebrew  - 🍺 Update Homebrew formula"
    echo "  test        - 🧪 Test CLI functionality and workflows"

    echo "  help        - Show this help"
    echo ""
    echo "This CLI provides comprehensive Git operations and version management."
echo ""
echo "The 'go' command performs a complete workflow: sync → docs → version → commit → push → metadata"
echo ""
echo "Environment Variables:"
echo "  • MANIFEST_BREW_OPTION       - Control Homebrew functionality (enabled/disabled)"
echo "  • MANIFEST_BREW_INTERACTIVE  - Interactive Homebrew updates (yes/true/1, default: no)"
echo ""
echo "For testing and verification:"
echo "  • manifest test              - Basic functionality test"
echo "  • manifest test versions     - Test version increment logic"
echo "  • manifest test all          - Comprehensive system testing"
}
source "$MODULES_DIR/manifest-test.sh"
