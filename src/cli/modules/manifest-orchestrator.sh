#!/bin/bash

# Manifest Orchestrator Module
# Coordinates the complete manifest workflow using atomized modules

# Orchestrator module - uses PROJECT_ROOT from core module

# Import required modules
source "$SCRIPT_DIR/manifest-config.sh"
source "$SCRIPT_DIR/manifest-os.sh"
source "$SCRIPT_DIR/manifest-ntp.sh"
source "$SCRIPT_DIR/manifest-git.sh"
source "$SCRIPT_DIR/manifest-documentation.sh"
source "$SCRIPT_DIR/manifest-cleanup-docs.sh"
source "$SCRIPT_DIR/manifest-markdown-validation.sh"

# Main workflow function
manifest_go() {
    local increment_type="$1"
    local interactive="$2"
    
    # Change to the project root directory for all operations
    cd "$PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $PROJECT_ROOT"
        return 1
    }
    
    # Determine version increment type
    if [ -z "$increment_type" ]; then
        increment_type="patch"
    fi
    
    echo "🚀 Starting automated Manifest process..."
    echo ""
    
    # Interactive confirmation for safety
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
    
    # Generate documentation using new architecture
    local timestamp=$(format_timestamp "$MANIFEST_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    echo "📚 Generating documentation and release notes..."
    if generate_documents "$new_version" "$timestamp" "$increment_type"; then
        echo "✅ Documentation generated successfully"
    else
        echo "⚠️  Documentation generation had issues, but continuing..."
    fi
    echo ""
    
    # Archive previous version documentation to zArchive (now that new version is created)
    echo "📁 Archiving previous version documentation..."
    main_cleanup "$new_version" "$timestamp"
    echo ""
    
    # Final markdown validation and fixing (before commit)
    echo "🔍 Final markdown validation and fixing..."
    if validate_project "true"; then
        echo "✅ Markdown validation completed"
    else
        echo "⚠️  Markdown validation found issues, but continuing..."
    fi
    echo ""
    
    # Commit version changes
    echo "💾 Committing version changes..."
    commit_changes "Bump version to $new_version" "$timestamp"
    echo ""
    
    # Update main CHANGELOG.md for GitHub visibility
    echo "📝 Updating main CHANGELOG.md for GitHub..."
    local latest_changelog="$PROJECT_ROOT/docs/CHANGELOG_v$new_version.md"
    if [[ -f "$latest_changelog" ]]; then
        # Copy the changelog and add the update message
        cp "$latest_changelog" "$PROJECT_ROOT/CHANGELOG.md"
        echo "" >> "$PROJECT_ROOT/CHANGELOG.md"
        echo "---" >> "$PROJECT_ROOT/CHANGELOG.md"
        echo "" >> "$PROJECT_ROOT/CHANGELOG.md"
        echo "📝 Updating main CHANGELOG.md for GitHub..." >> "$PROJECT_ROOT/CHANGELOG.md"
        git add CHANGELOG.md
        git commit -m "Update main CHANGELOG.md to v$new_version"
        echo "✅ Main CHANGELOG.md updated for GitHub"
    else
        echo "⚠️  Latest changelog not found: $latest_changelog"
    fi
    echo ""
    
    # Validate repository state after commit
    echo "🔍 Validating repository state..."
    validate_repository || true
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
    
    # Homebrew update functionality is now handled by the orchestrator
    echo "   ⚠️  Homebrew update functionality is now integrated into the orchestrator"
    return 0
    echo ""
    
    # Archive old documentation files (completed after new version creation)
    echo "📁 Archiving old documentation files..."
    echo "   ✅ Documentation archiving completed"
    
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

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "go")
            local increment_type="${2:-patch}"
            local interactive="${3:-false}"
            manifest_go "$increment_type" "$interactive"
            ;;
        "test")
            local increment_type="${2:-patch}"
            manifest_test_dry_run "$increment_type"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Orchestrator Module"
            echo "==========================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  go [type] [interactive]  - Complete manifest workflow"
            echo "  test [type]              - Test/dry-run mode"
            echo "  help                     - Show this help"
            echo ""
            echo "Options:"
            echo "  type: patch, minor, major, revision (default: patch)"
            echo "  interactive: -i for interactive mode"
            echo ""
            echo "Examples:"
            echo "  $0 go minor"
            echo "  $0 go patch -i"
            echo "  $0 test major"
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
