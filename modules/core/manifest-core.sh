#!/bin/bash

# Manifest Core Module
# Main CLI interface and workflow orchestration

# Enable strict error handling for critical operations
set -eo pipefail

# Import modules
# Determine the absolute path to the modules directory
MANIFEST_CLI_CORE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_CLI_CORE_MODULES_DIR="$(dirname "$MANIFEST_CLI_CORE_SCRIPT_DIR")"

# Load configuration at startup
# Get the binary location (where the CLI binary is installed)
MANIFEST_CLI_CORE_BINARY_LOCATION="${MANIFEST_CLI_BIN_DIR:-$HOME/.local/bin}"

# Determine the project root (where we're actually working)
# Use the current working directory from the environment, not the script's directory
if [ -n "$PWD" ] && git -C "$PWD" rev-parse --git-dir > /dev/null 2>&1; then
    # We're in a git repository, use current working directory
    PROJECT_ROOT="$PWD"
    # When in a git repo, INSTALL_LOCATION is where the CLI files are installed
    INSTALL_LOCATION="${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest-cli}"
else
    # Not in a git repository, use installation location for both
    INSTALL_LOCATION="${MANIFEST_CLI_CORE_MODULES_DIR%/*/*/*}"
    PROJECT_ROOT="$INSTALL_LOCATION"
fi

# Note: PROJECT_ROOT will be validated and corrected in the main() function
# to ensure we're always working from the repository root

# Export variables so they're available to sourced modules
export INSTALL_LOCATION
export MANIFEST_CLI_CORE_BINARY_LOCATION
export PROJECT_ROOT

# Source shared utilities first
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-utils.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-functions.sh"
# Function registry removed - not compatible with macOS default Bash 3.2

# Now source modules after variables are set
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-config.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-os.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-ntp.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/git/manifest-git.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-security.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/docs/manifest-documentation.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-uninstall.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/workflow/manifest-orchestrator.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/docs/manifest-cleanup-docs.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/testing/manifest-test.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/cloud/manifest-agent-containerized.sh"

# Source MCP utilities and connector for Manifest Cloud
source "$MANIFEST_CLI_CORE_MODULES_DIR/cloud/manifest-mcp-utils.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/cloud/manifest-mcp-connector.sh"

# Source Fleet module for polyrepo management
source "$MANIFEST_CLI_CORE_MODULES_DIR/fleet/manifest-fleet.sh"

# Function to get the CLI installation directory dynamically
get_cli_dir() {
    # If we're in a development environment, use the current project root
    if [ -f "$PROJECT_ROOT/$MANIFEST_CLI_VERSION_FILE" ] && [ -f "$PROJECT_ROOT/scripts/manifest-cli-wrapper.sh" ]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    
    # Try to find installed CLI (primary: ~/.manifest-cli)
    local possible_dirs=(
        "$HOME/.manifest-cli"
    )
    
    for dir in "${possible_dirs[@]}"; do
        if [ -d "$dir" ] && [ -f "$dir/$MANIFEST_CLI_VERSION_FILE" ] && [ -f "$dir/scripts/manifest-cli-wrapper.sh" ]; then
            echo "$dir"
            return 0
        fi
    done
    
    # Fallback to project root if nothing else works
    echo "$PROJECT_ROOT"
}

# Set the CLI directory
MANIFEST_CLI_CORE_DIR="$(get_cli_dir)"

# Archive old documentation files (delegated to manifest-cleanup-docs.sh)
archive_old_docs() {
    echo "📁 Archiving old documentation files..."
    main_cleanup
    echo "   ✅ Documentation archiving completed"
    echo ""
}

# Main workflow function is now handled by manifest-orchestrator.sh

# Update CLI function
update_cli() {
    # Source the auto-update module
    source "$MANIFEST_CLI_CORE_MODULES_DIR/workflow/manifest-auto-update.sh"
    
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

# get_next_version() - Now available from manifest-shared-functions.sh

# Auto-update check with cooldown
check_auto_update() {
    # Source the auto-update module
    source "$MANIFEST_CLI_CORE_MODULES_DIR/workflow/manifest-auto-update.sh"
    
    # Call the check function from the auto-update module
    check_auto_update_internal
}

# Main command dispatcher
main() {
    # Set INSTALL_LOCATION early for security checks
    INSTALL_LOCATION="${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest}"
    export INSTALL_LOCATION

    # SECURITY: Early check to prevent running from installation directory
    if is_installation_directory "$(pwd)"; then
        log_error "❌ SECURITY ERROR: Cannot run Manifest CLI from installation directory"
        log_error "   Installation directory: ${INSTALL_LOCATION:-$HOME/.manifest-cli}"
        log_error "   Current directory: $(pwd)"
        log_error ""
        log_error "💡 Please run Manifest CLI from your project directory instead:"
        log_error "   cd /path/to/your/project"
        log_error "   manifest [command]"
        return 1
    fi
    
    # Ensure we're running from repository root for all commands
    if ! ensure_repository_root; then
        log_error "Repository root validation failed"
        return 1
    fi
    
    # Update PROJECT_ROOT to the actual current directory (in case we changed)
    PROJECT_ROOT="$(pwd)"
    export PROJECT_ROOT
    
    # Load configuration now that all variables are properly set
    load_configuration "$PROJECT_ROOT"
    
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
                        log_error "Unknown option: $1"
                        echo "Usage: manifest go [patch|minor|major|revision] [-i|--interactive]"
                        return 1
                        ;;
                esac
            done
            
            # Call the orchestrator's manifest_go function
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
            # Get NTP timestamp for accurate versioning
            get_ntp_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            
            bump_version "$increment_type"
            local new_version=$(cat "$MANIFEST_CLI_VERSION_FILE" 2>/dev/null)
            commit_changes "Bump version to $new_version" "$timestamp"
            create_tag "$new_version"
            push_changes "$new_version"
            ;;
        "commit")
            local message="$1"
            # Get NTP timestamp for accurate versioning
            get_ntp_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
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
                    if [ -f "$MANIFEST_CLI_VERSION_FILE" ]; then
                        current_version=$(cat "$MANIFEST_CLI_VERSION_FILE")
                    fi
                    
                    if [ -z "$current_version" ]; then
                        log_error "Could not determine current version. Please run 'manifest version' first."
                        return 1
                    fi
                    
                    # Get NTP timestamp for accurate documentation
                    get_ntp_timestamp >/dev/null
                    local timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
                    generate_documents "$current_version" "$timestamp" "patch"
                    ;;
            esac
            ;;
        "cleanup")
            echo "📁 Repository cleanup operations..."
            local current_version=""
            if [ -f "$MANIFEST_CLI_VERSION_FILE" ]; then
                current_version=$(cat "$MANIFEST_CLI_VERSION_FILE")
            fi
            # Get NTP timestamp for accurate cleanup
            get_ntp_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            main_cleanup "$current_version" "$timestamp"
            ;;
        "config")
            show_configuration
            ;;
        "security")
            manifest_security
            ;;
        "test")
            test_command "$@"
            ;;
        "update")
            update_cli "$@"
            ;;
        "uninstall")
            # Check for --force flag
            local force_flag="false"
            if [ "$2" = "--force" ]; then
                force_flag="true"
            fi
            # Parameters: skip_confirmations (from --force flag), non_interactive=true (non-interactive by default)
            uninstall_manifest "$force_flag" "true"
            ;;
        # Registry commands removed - not compatible with macOS default Bash 3.2
        "cloud")
            local subcommand="$1"
            case "$subcommand" in
                "test")
                    test_mcp_connectivity
                    ;;
                "config")
                    configure_mcp_connection
                    ;;
                "status")
                    show_mcp_status
                    ;;
                "generate")
                    local version="${2:-}"
                    local timestamp="${3:-$(date -u +"%Y-%m-%d %H:%M:%S UTC")}"
                    local release_type="${4:-patch}"

                    if [ -z "$version" ]; then
                        log_error "Version required"
                        echo "Usage: manifest cloud generate <version> [timestamp] [release_type]"
                        return 1
                    fi

                    # Create temporary changes file
                    local changes_file=$(mktemp)
                    get_git_changes "$version" > "$changes_file"

                    send_to_manifest_cloud "$version" "$changes_file" "$release_type"
                    local result=$?
                    rm -f "$changes_file"
                    return $result
                    ;;
                *)
                    echo "Manifest Cloud MCP Usage:"
                    echo "========================="
                    echo ""
                    echo "Commands:"
                    echo "  cloud test                    - Test MCP connectivity to Manifest Cloud"
                    echo "  cloud config                  - Configure API key and connection"
                    echo "  cloud status                  - Show connection status"
                    echo "  cloud generate <version> [opts] - Generate documentation via Manifest Cloud"
                    echo ""
                    echo "Configuration:"
                    echo "  MANIFEST_CLI_CLOUD_API_KEY       - Your Manifest Cloud API key"
                    echo "  MANIFEST_CLI_CLOUD_ENDPOINT      - Manifest Cloud endpoint (optional)"
                    echo ""
                    echo "Examples:"
                    echo "  manifest cloud test"
                    echo "  manifest cloud config"
                    echo "  manifest cloud generate 1.2.3 '2025-01-27 10:00:00 UTC' patch"
                    echo ""
                    echo "Get your API key from: https://manifest.cloud/dashboard"
                    ;;
            esac
            ;;
        "agent")
            agent_main "${@}"
            ;;
        "fleet")
            # Fleet commands for polyrepo management
            fleet_main "$@"
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
  echo "  uninstall   - 🗑️  Remove Manifest CLI completely"
  echo "    uninstall [--force]               # Uninstall options: force uninstall without confirmation"
  echo "  cloud       - ☁️  Manifest Cloud MCP connector"
  echo "    cloud test                        # Test connectivity to Manifest Cloud"
  echo "    cloud config                      # Configure API key and connection"
  echo "    cloud status                      # Show connection status"
  echo "    cloud generate <version> [opts]   # Generate documentation via Manifest Cloud"
  echo "  agent       - 🤖  Containerized agent for secure cloud integration"
  echo "    agent init <mode>                 # Initialize agent (docker|binary|script)"
  echo "    agent auth github                 # Set up GitHub OAuth authentication"
  echo "    agent auth manifest               # Set up Manifest Cloud subscription"
  echo "    agent status                      # Show agent status and configuration"
  echo "    agent logs                        # Show agent operation logs"
  echo "    agent test                        # Test agent functionality"
  echo "    agent uninstall                   # Remove agent completely"
  echo "  fleet       - 🚢 Coordinate versioning across multiple repos (run 'manifest fleet' for details)"
  # Registry commands removed - not compatible with macOS default Bash 3.2
  echo "  help        - Show this help"
    echo ""
    echo "This CLI provides comprehensive Git operations and version management."
echo ""
echo "The 'go' command performs a complete workflow: sync → docs → version → commit → push → metadata"
echo ""
echo "Environment Variables:"
echo "  • MANIFEST_CLI_INTERACTIVE_MODE  - Interactive safety prompts (true/false, default: false)"
echo "  • MANIFEST_CLI_BREW_OPTION       - Control Homebrew functionality (enabled/disabled)"
echo "  • MANIFEST_CLI_BREW_INTERACTIVE  - Interactive Homebrew updates (yes/true/1, default: no)"
echo "  • MANIFEST_CLI_TAP_REPO          - Homebrew tap repository URL (default: fidenceio/fidenceio-homebrew-tap)"
echo "  • MANIFEST_CLI_CLOUD_API_KEY     - Manifest Cloud API key (get from https://manifest.cloud/dashboard)"
echo "  • MANIFEST_CLI_CLOUD_ENDPOINT    - Manifest Cloud endpoint (default: https://api.manifest.cloud)"
echo "  • MANIFEST_CLI_CLOUD_SKIP        - Skip Manifest Cloud and use local docs (true/false)"
echo "  • MANIFEST_CLI_OFFLINE_MODE      - Force offline mode, no cloud connectivity (true/false)"
echo ""
echo "For testing and verification:"
echo "  • manifest test              - Basic functionality test"
echo "  • manifest test versions     - Test version increment logic"
echo "  • manifest test all          - Comprehensive system testing"
}

# Test module is sourced at the top level
