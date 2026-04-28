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

# PROJECT_ROOT = where the user is working (always PWD, never the install location).
# main() re-sets this after validating the command, but modules sourced at
# load time may read it, so give it a sane default now.
PROJECT_ROOT="$PWD"

# INSTALL_LOCATION = where the CLI files live (separate concern from PROJECT_ROOT)
INSTALL_LOCATION="${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest-cli}"

# Note: PROJECT_ROOT will be validated and corrected in the main() function
# to ensure we're always working from the repository root

# Export variables so they're available to sourced modules
export INSTALL_LOCATION
export MANIFEST_CLI_CORE_BINARY_LOCATION
export PROJECT_ROOT

# Source shared utilities first
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-utils.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-functions.sh"

# Source YAML module before config (config depends on YAML functions)
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-yaml.sh"

# Source plugin loader (must come after shared-utils for log_* functions)
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-plugin-loader.sh"

# Now source core modules after variables are set
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-config.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-os.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-time.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/git/manifest-git.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-security.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/docs/manifest-documentation.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-uninstall.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/workflow/manifest-orchestrator.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/docs/manifest-cleanup-docs.sh"

# Optional modules — loaded from Manifest Cloud plugins, or stubs if absent
manifest_load_plugin "testing/manifest-test.sh" \
    || source "$MANIFEST_CLI_CORE_MODULES_DIR/stubs/manifest-test-stub.sh"

# PR loading order: native (gh wrapper) → Cloud plugin (may override) → stub
# (fills any remaining gaps with "requires Cloud" message). Native + Cloud
# are non-exclusive; Cloud functions take precedence where both define one.
source "$MANIFEST_CLI_CORE_MODULES_DIR/pr/manifest-pr-native.sh"
manifest_load_plugin "pr/manifest-pr.sh" || true
source "$MANIFEST_CLI_CORE_MODULES_DIR/stubs/manifest-pr-stub.sh"

manifest_load_plugin "cloud/manifest-agent-containerized.sh" \
    || source "$MANIFEST_CLI_CORE_MODULES_DIR/stubs/manifest-agent-stub.sh"
if ! manifest_load_plugin "cloud/manifest-mcp-utils.sh"; then
    source "$MANIFEST_CLI_CORE_MODULES_DIR/stubs/manifest-cloud-stub.sh"
else
    manifest_load_plugin "cloud/manifest-mcp-connector.sh" || true
fi

# Source Fleet module for polyrepo management
source "$MANIFEST_CLI_CORE_MODULES_DIR/fleet/manifest-fleet.sh"

# Source v42 journey modules (init, prep, refresh, ship dispatchers)
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-init.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-prep.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-refresh.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-ship.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-status.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-doctor.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-config-crud.sh"

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

# Back-compat shim. The canonical implementations live in
# manifest-shared-functions.sh:
#   - manifest_origin_repo_slug (takes optional project_root)
#   - manifest_is_canonical_repo (uses MANIFEST_CLI_CANONICAL_REPO_SLUGS,
#     accepts MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS as a deprecated alias)
# Old call sites continue to work via this shim.
should_update_homebrew_for_repo() {
    manifest_is_canonical_repo "$@"
}

# Update Homebrew formula in both this repo and the tap repo
update_homebrew_formula() {
    if ! should_update_homebrew_for_repo; then
        local origin_slug=""
        origin_slug="$(manifest_origin_repo_slug || echo "unknown")"
        echo "🍺 Skipping Homebrew formula update for repository: ${origin_slug}"
        echo "   Homebrew updates run only for: ${MANIFEST_CLI_CANONICAL_REPO_SLUGS:-${MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS:-fidenceio/manifest.cli,fidenceio/fidenceio.manifest.cli}}"
        return 0
    fi

    local version
    version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null)
    if [ -z "$version" ]; then
        log_error "Could not read VERSION file"
        return 1
    fi

    local tag="v${version}"
    local tarball_url="https://github.com/fidenceio/manifest.cli/archive/refs/tags/${tag}.tar.gz"
    local formula_file="$PROJECT_ROOT/formula/manifest.rb"

    echo "🍺 Updating Homebrew formula to ${tag}..."

    # Get SHA256 of the release tarball
    echo "   Fetching SHA256 for ${tag}..."
    local sha256
    sha256=$(curl -fsSL "$tarball_url" | shasum -a 256 | cut -d' ' -f1)
    if [ -z "$sha256" ]; then
        log_error "Failed to fetch tarball SHA256 for ${tag}"
        return 1
    fi
    echo "   SHA256: ${sha256}"

    # Update formula in this repo
    if [ -f "$formula_file" ]; then
        # Cross-platform in-place sed (BSD on macOS requires -i '', GNU requires -i)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|url \"https://github.com/fidenceio/manifest.cli/archive/refs/tags/v.*\.tar\.gz\"|url \"${tarball_url}\"|" "$formula_file"
            sed -i '' "s|sha256 \"[a-f0-9]*\"|sha256 \"${sha256}\"|" "$formula_file"
        else
            sed -i "s|url \"https://github.com/fidenceio/manifest.cli/archive/refs/tags/v.*\.tar\.gz\"|url \"${tarball_url}\"|" "$formula_file"
            sed -i "s|sha256 \"[a-f0-9]*\"|sha256 \"${sha256}\"|" "$formula_file"
        fi
        echo "   ✅ Updated ${formula_file}"
    else
        log_error "Formula file not found: ${formula_file}"
        return 1
    fi

    # Sync to the Homebrew tap repo
    local tap_dir
    if command -v brew &>/dev/null; then
        tap_dir="$(brew --prefix)/Library/Taps/fidenceio/homebrew-tap"
    fi

    if [ -d "$tap_dir/Formula" ]; then
        if (
            set -e
            cd "$tap_dir"
            git pull --rebase origin main
        ); then
            :
        else
            echo "   ⚠️  Could not pull latest from homebrew-tap — continuing with local state"
        fi
        cp "$formula_file" "$tap_dir/Formula/manifest.rb"
        if (
            set -e
            cd "$tap_dir"
            git add Formula/manifest.rb
            if ! git diff --cached --quiet; then
                git commit -m "Update formula to ${tag}"
            fi
            git push origin main
        ); then
            echo "   ✅ Pushed to homebrew-tap repo"
        else
            log_error "Failed to push formula to homebrew-tap repo"
            return 1
        fi
    else
        echo "   ⚠️  Homebrew tap not found locally — formula updated in this repo only"
        echo "   Push formula/manifest.rb to the homebrew-tap repo manually"
    fi

    echo "🍺 Homebrew formula update complete"
}

# Upgrade CLI function
upgrade_cli() {
    # Source the auto-upgrade module
    source "$MANIFEST_CLI_CORE_MODULES_DIR/workflow/manifest-auto-upgrade.sh"
    
    # Call the upgrade function from the auto-upgrade module
    local args=("$@")
    upgrade_cli_internal "${args[@]}"
}

# Test mode function
manifest_test() {
    local test_type="$1"
    
    echo "🧪 Starting Manifest test mode..."
    echo ""
    
    # Get trusted timestamp
    get_time_timestamp

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
            
            # Test timestamp
            echo "🕐 Testing timestamp functionality..."
            get_time_timestamp
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
            
            # Get trusted timestamp
            get_time_timestamp

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

# Auto-upgrade check with cooldown
check_auto_upgrade() {
    # Load from Cloud plugins; silently skip if not installed
    if manifest_load_plugin "workflow/manifest-auto-upgrade.sh"; then
        check_auto_upgrade_internal
    fi
}

# Legacy prep entry point — kept for internal callers (manifest_ship in pr module)
manifest_prep() {
    local increment_type="${1:-}"
    local interactive="${2:-false}"
    local publish_release="${3:-false}"
    if [ -z "$increment_type" ]; then
        log_error "prep requires a release type subcommand"
        echo "Usage: manifest ship repo <patch|minor|major|revision> [--local] [-i]"
        return 1
    fi
    manifest_ship_workflow "$increment_type" "$interactive" "$publish_release"
}

main() {
    # Set INSTALL_LOCATION early for security checks
    INSTALL_LOCATION="${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest-cli}"
    export INSTALL_LOCATION

    # SECURITY: Early check to prevent running from installation directory
    if is_installation_directory "$(pwd)"; then
        log_error "SECURITY ERROR: Cannot run Manifest CLI from installation directory"
        log_error "   Installation directory: ${INSTALL_LOCATION:-$HOME/.manifest-cli}"
        log_error "   Current directory: $(pwd)"
        log_error ""
        log_error "Please run Manifest CLI from your project directory instead:"
        log_error "   cd /path/to/your/project"
        log_error "   manifest [command]"
        return 1
    fi

    local command="${1:-}"
    [[ $# -gt 0 ]] && shift

    # =========================================================================
    # Pre-dispatch: load config / validate git depending on command
    # =========================================================================
    case "$command" in
        # Commands that do NOT require a Git repository
        "help"|"-help"|"--help"|"-h"|"version"|"-version"|"--version"|"-v"|"-V"|"uninstall"|"reinstall"|"update"|"upgrade"|"config")
            case "$command" in
                "config")
                    PROJECT_ROOT="$(pwd)"
                    export PROJECT_ROOT
                    load_configuration "$PROJECT_ROOT" "false"
                    ;;
            esac
            ;;
        "")
            # No command — will fall through to display_help
            ;;
        # init may create a git repo, so don't require one
        "init")
            PROJECT_ROOT="$(pwd)"
            export PROJECT_ROOT
            load_configuration "$PROJECT_ROOT" "false"
            ;;
        # status is read-only; it handles non-git directories itself
        "status"|"doctor")
            PROJECT_ROOT="$(pwd)"
            export PROJECT_ROOT
            load_configuration "$PROJECT_ROOT" "false"
            ;;
        *)
            # All other commands require a Git repository
            if ! ensure_repository_root; then
                log_error "Repository root validation failed"
                return 1
            fi

            PROJECT_ROOT="$(pwd)"
            export PROJECT_ROOT
            load_configuration "$PROJECT_ROOT"
            check_auto_upgrade
            ;;
    esac

    # =========================================================================
    # Command dispatch — v42 core journey + supporting + legacy aliases
    # =========================================================================
    case "$command" in

        # =====================================================================
        # CORE JOURNEY: config → init → prep → refresh → ship
        # =====================================================================
        "config")
            case "${1:-}" in
                "show")
                    show_configuration
                    ;;
                "time")
                    display_time_config
                    ;;
                "doctor")
                    shift
                    config_doctor "$@"
                    ;;
                "list")
                    shift
                    manifest_config_list "$@"
                    ;;
                "get")
                    shift
                    manifest_config_get "$@"
                    ;;
                "set")
                    shift
                    manifest_config_set "$@"
                    ;;
                "unset")
                    shift
                    manifest_config_unset "$@"
                    ;;
                "describe")
                    shift
                    manifest_config_describe "$@"
                    ;;
                "")
                    if [ -t 0 ]; then
                        configure_interactive
                    else
                        show_configuration
                    fi
                    ;;
                "-h"|"--help")
                    cat <<'EOF'
Usage: manifest config [<subcommand>] [args]

  (no args)        Interactive wizard (TTY) or show config (non-TTY)
  show             Print full effective configuration
  time             Print time server configuration
  doctor [--fix]   Detect stale/deprecated config; --fix to apply
  setup            Force interactive configuration wizard

  list [--layer L]                  List all keys + effective layer
  get <key>                         Read effective value of a key
  set [--layer L] <key> <value>     Write a key (default layer: local)
  unset [--layer L] <key>           Remove a key from a layer
  describe <key>                    Show key value at every layer + env var

Layer L is one of: global | project | local
Writing to 'global' triggers the safety-gate confirmation.
EOF
                    ;;
                "setup")
                    configure_interactive
                    ;;
                "--non-interactive")
                    show_configuration
                    ;;
                *)
                    log_error "Unknown config view: $1"
                    echo "Usage: manifest config [show|time|doctor|setup|list|get|set|unset|describe]"
                    return 1
                    ;;
            esac
            ;;

        "init")
            manifest_init_dispatch "$@"
            ;;

        "prep")
            manifest_prep_dispatch "$@"
            ;;

        "refresh")
            manifest_refresh_dispatch "$@"
            ;;

        "ship")
            manifest_ship_dispatch "$@"
            ;;

        "status")
            manifest_status "$@"
            ;;

        "doctor")
            manifest_doctor "$@"
            ;;

        # =====================================================================
        # SUPPORTING COMMANDS (used anytime, not part of core sequence)
        # =====================================================================
        "pr")
            local subcommand=""
            case "${1:-}" in
                "create"|"update"|"status"|"ready"|"checks"|"merge"|"queue"|"policy"|"help"|"-h"|"--help")
                    subcommand="${1:-help}"
                    shift || true
                    ;;
                "")
                    manifest_pr_interactive "$@"
                    return $?
                    ;;
                --*)
                    manifest_pr_interactive "$@"
                    return $?
                    ;;
                *)
                    log_error "Unknown pr subcommand: ${1:-}"
                    echo "Usage: manifest pr [interactive options]"
                    echo "       manifest pr <create|update|status|ready|checks|queue|policy|help> [options]"
                    echo "Run 'manifest pr help' for detailed usage."
                    return 1
                    ;;
            esac
            case "$subcommand" in
                "create")
                    manifest_pr_create "$@"
                    ;;
                "update")
                    manifest_pr_update "$@"
                    ;;
                "status")
                    manifest_pr_status "$@"
                    ;;
                "ready")
                    manifest_pr_ready "$@"
                    ;;
                "checks")
                    manifest_pr_checks "$@"
                    ;;
                "merge")
                    manifest_pr_merge "$@"
                    ;;
                "queue")
                    manifest_pr_queue "$@"
                    ;;
                "policy")
                    local policy_subcommand="${1:-show}"
                    shift || true
                    case "$policy_subcommand" in
                        "show")
                            manifest_pr_policy_show "$@"
                            ;;
                        "validate")
                            manifest_pr_policy_validate "$@"
                            ;;
                        *)
                            log_error "Unknown pr policy command: $policy_subcommand"
                            echo "Run 'manifest pr help' for usage."
                            return 1
                            ;;
                    esac
                    ;;
                "help"|"-h"|"--help")
                    manifest_pr_help
                    ;;
                *)
                    log_error "Unknown pr command: $subcommand"
                    echo "Run 'manifest pr help' for usage."
                    return 1
                    ;;
            esac
            ;;

        "revert")
            revert_version
            ;;

        # =====================================================================
        # DIAGNOSTIC / MAINTENANCE COMMANDS
        # =====================================================================
        "security")
            manifest_security
            ;;

        "test")
            run_manifest_test "$@"
            ;;

        "upgrade")
            if manifest_load_plugin "workflow/manifest-auto-upgrade.sh"; then
                upgrade_cli_internal "$@"
            else
                log_warning "Upgrade module requires Manifest Cloud."
                echo "  To upgrade via Homebrew: brew update && brew upgrade manifest"
            fi
            ;;

        "uninstall")
            local force_flag="false"
            if [ "$2" = "--force" ]; then
                force_flag="true"
            fi
            uninstall_manifest "$force_flag" "$force_flag"
            ;;

        "reinstall")
            echo "Reinstalling Manifest CLI..."
            echo ""
            if ! uninstall_manifest "true" "true"; then
                log_warning "Uninstall reported issues; continuing reinstall."
            fi
            echo ""
            if [[ "$OSTYPE" == "darwin"* ]] && ! command -v brew &>/dev/null; then
                echo "macOS detected but Homebrew is not installed"
                echo "   Homebrew is the recommended way to install, upgrade, manage, and cleanly remove Manifest CLI on macOS."
                read -p "   Would you like to install Homebrew? (Y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    echo "   Installing Homebrew..."
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                    if [ -f "/opt/homebrew/bin/brew" ]; then
                        eval "$(/opt/homebrew/bin/brew shellenv)"
                    elif [ -f "/usr/local/bin/brew" ]; then
                        eval "$(/usr/local/bin/brew shellenv)"
                    fi
                else
                    echo "   Skipping Homebrew — will use manual installation"
                fi
            fi
            if command -v brew &>/dev/null; then
                echo "Reinstalling via Homebrew..."
                brew tap fidenceio/tap 2>/dev/null
                if brew list fidenceio/tap/manifest &>/dev/null || brew list manifest &>/dev/null; then
                    brew reinstall fidenceio/tap/manifest || brew reinstall manifest
                else
                    brew install fidenceio/tap/manifest || brew install manifest
                fi
            else
                echo "Reinstalling via manual install..."
                if manifest_load_plugin "workflow/manifest-auto-upgrade.sh"; then
                    install_cli "true"
                    migrate_user_global_config_internal
                else
                    log_error "Manual reinstall requires Manifest Cloud. Use: brew reinstall manifest"
                    return 1
                fi
            fi
            ;;

        # =====================================================================
        # CLOUD / AGENT (optional add-ons)
        # =====================================================================
        "cloud")
            local subcommand="$1"
            case "$subcommand" in
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
                    echo "  cloud config                  - Configure API key and connection"
                    echo "  cloud status                  - Show connection status"
                    echo "  cloud generate <version> [opts] - Generate documentation via Manifest Cloud"
                    echo ""
                    echo "Run 'manifest test cloud' for MCP connectivity tests."
                    ;;
            esac
            ;;

        "agent")
            agent_main "${@}"
            ;;

        # =====================================================================
        # HIDDEN LEGACY ALIASES (still functional, not shown in help)
        # =====================================================================

        # Old "manifest fleet *" top-level — still works, routes to fleet_main
        "fleet")
            fleet_main "$@"
            ;;

        # Old "manifest sync" -> new "manifest prep repo"
        "sync")
            log_deprecated "manifest sync" "manifest prep repo"
            manifest_prep_repo
            ;;

        # Old "manifest time" -> accessible via "manifest config time"
        "time")
            display_time_info
            ;;

        # Old "manifest update" -> "manifest upgrade"
        "update")
            log_deprecated "manifest update" "manifest upgrade"
            if manifest_load_plugin "workflow/manifest-auto-upgrade.sh"; then
                upgrade_cli_internal "$@"
            else
                log_warning "Upgrade module requires Manifest Cloud."
                echo "  To upgrade via Homebrew: brew update && brew upgrade manifest"
            fi
            ;;

        # Old "manifest commit" — plumbing, called by ship
        "commit")
            local message="$1"
            get_time_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            commit_changes "$message" "$timestamp"
            ;;

        # Old "manifest version" — plumbing, called by ship internally
        "bump-version")
            local increment_type="${1:-patch}"
            bump_version "$increment_type"
            ;;

        # Old "manifest docs" — plumbing, replaced by "refresh"
        "docs")
            local subcommand="$1"
            case "$subcommand" in
                "metadata")
                    update_repository_metadata
                    ;;
                "homebrew")
                    echo "Homebrew formula is updated automatically by 'manifest ship'"
                    ;;
                "cleanup")
                    echo "Moving historical documentation to zArchive..."
                    move_existing_historical_docs
                    ;;
                *)
                    local current_version=""
                    if [ -f "$MANIFEST_CLI_VERSION_FILE" ]; then
                        current_version=$(cat "$MANIFEST_CLI_VERSION_FILE")
                    fi
                    if [ -z "$current_version" ]; then
                        log_error "Could not determine current version. Run 'manifest init repo' first."
                        return 1
                    fi
                    get_time_timestamp >/dev/null
                    local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
                    generate_documents "$current_version" "$timestamp" "patch"
                    ;;
            esac
            ;;

        # Old "manifest cleanup" — plumbing, absorbed into "refresh"
        "cleanup")
            echo "Repository cleanup operations..."
            local current_version=""
            if [ -f "$MANIFEST_CLI_VERSION_FILE" ]; then
                current_version=$(cat "$MANIFEST_CLI_VERSION_FILE")
            fi
            get_time_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            main_cleanup "$current_version" "$timestamp"
            ;;

        # =====================================================================
        # HELP / FALLBACK
        # =====================================================================
        "help"|"-help"|"--help"|"-h")
            display_help
            ;;

        "version"|"-version"|"--version"|"-v"|"-V")
            display_version
            ;;

        *)
            log_error "Unknown command: $command"
            echo ""
            display_help
            return 1
            ;;
    esac
}

# Display help
display_help() {
    cat << 'EOF'
Manifest CLI

Usage: manifest <command> [scope] [options]

  Core workflow:
    config                              Setup wizard / show configuration
    init repo|fleet                     Scaffold repo or fleet
    status                              Read-only snapshot (next bump, sync state)
    prep repo|fleet                     Connect remotes, pull latest
    refresh repo|fleet                  Regenerate docs, metadata, membership
    ship repo|fleet <patch|minor|major> Publish release (version + tag + push)
         --local                        Preview locally without pushing

  Pull requests:                              (gh wrapper, no Cloud needed)
    pr                                  Show current PR or prompt to create
    pr create|status|ready              Create, view, mark-ready (gh)
    pr checks|merge|update              CI status, merge, update branch (gh)
    pr queue|policy                     Auto-merge, policy enforcement [Cloud]

  Config:
    config doctor                       Detect and fix config issues

  Maintenance:
    doctor                              Health check (deps, config, repo)
    upgrade                             Update Manifest CLI  [Cloud]
    uninstall                           Remove Manifest CLI
    security                            Run security audit
    test                                Run diagnostic tests [Cloud]

  Cloud:                                       [Cloud]
    cloud config|status|generate        Manifest Cloud connector
    agent init|auth|status              Containerized cloud agent

  Recovery:
    revert                              Roll back to a previous version

  Info:
    version                             Show CLI version
    help                                Show this help message

Run 'manifest <command> --help' for details on any command.
EOF
}

# Display version — reads the CLI's own VERSION, not the target project's
display_version() {
    local cli_root="${MANIFEST_CLI_CORE_MODULES_DIR%/modules}"
    local version=""
    if [ -f "$cli_root/VERSION" ]; then
        version=$(cat "$cli_root/VERSION" 2>/dev/null)
    fi
    if [ -n "$version" ]; then
        echo "Manifest CLI v${version}"
    else
        log_error "Could not read Manifest CLI VERSION file"
        return 1
    fi
}

# Test module is sourced at the top level
