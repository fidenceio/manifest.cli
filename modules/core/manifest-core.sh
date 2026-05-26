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
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-requirements.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-utils.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-execution-policy.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-functions.sh"

# Source YAML module before config (config depends on YAML functions)
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-yaml.sh"

# Source plugin loader (must come after shared-utils for log_* functions)
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-plugin-loader.sh"

# Now source core modules after variables are set
source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-config.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-os.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-time.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-runtime-cleanup.sh"
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
source "$MANIFEST_CLI_CORE_MODULES_DIR/recipe/manifest-recipe.sh"
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
# Main workflow function is now handled by manifest-orchestrator.sh

# Back-compat shim. The canonical implementations live in
# manifest-shared-functions.sh:
#   - manifest_origin_repo_slug (takes optional project_root)
#   - manifest_is_canonical_repo (uses MANIFEST_CLI_CANONICAL_REPO_SLUGS)
# Old call sites continue to work via this shim.
should_update_homebrew_for_repo() {
    manifest_is_canonical_repo "$@"
}

manifest_homebrew_tap_checkout_candidates() {
    local primary_tap_dir="${1:-}"
    local workspace_parent=""
    workspace_parent="$(dirname "$PROJECT_ROOT" 2>/dev/null || echo "")"

    local candidates=""
    if [[ -n "${MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT:-}" ]]; then
        candidates="${candidates}${MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT}"$'\n'
    fi
    if [[ -n "$primary_tap_dir" ]]; then
        candidates="${candidates}${primary_tap_dir}"$'\n'
    fi
    if command -v brew &>/dev/null; then
        candidates="${candidates}$(brew --prefix 2>/dev/null)/Library/Taps/fidenceio/homebrew-tap"$'\n'
    fi
    if [[ -n "$workspace_parent" && "$workspace_parent" != "." ]]; then
        candidates="${candidates}${workspace_parent}/fidenceio.homebrew.tap"$'\n'
        candidates="${candidates}${workspace_parent}/homebrew-tap"$'\n'
    fi

    local seen="|"
    local candidate=""
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        case "$seen" in
            *"|$candidate|"*) continue ;;
        esac
        seen="${seen}${candidate}|"
        echo "$candidate"
    done <<< "$candidates"
}

manifest_refresh_homebrew_tap_checkouts() {
    local primary_tap_dir="${1:-}"
    local branch="${MANIFEST_CLI_HOMEBREW_TAP_BRANCH:-main}"
    local expected_slug="${MANIFEST_CLI_HOMEBREW_TAP_SLUG-fidenceio/homebrew-tap}"
    local refreshed=0
    local skipped=0
    local failed=0
    local candidate=""

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        [[ -d "$candidate" ]] || continue

        local result=""
        local status=0
        result="$(manifest_git_safe_fast_forward_checkout "$candidate" "$expected_slug" "$branch" "origin")"
        status=$?

        case "$status:$result" in
            0:updated)
                echo "   ✅ Refreshed local Homebrew tap checkout: $candidate"
                refreshed=$((refreshed + 1))
                ;;
            0:current)
                echo "   ✅ Local Homebrew tap checkout already current: $candidate"
                refreshed=$((refreshed + 1))
                ;;
            2:*)
                echo "   ⚠️  Skipped local Homebrew tap checkout: $candidate ($result)"
                skipped=$((skipped + 1))
                ;;
            *)
                echo "   ⚠️  Could not refresh local Homebrew tap checkout: $candidate ($result)"
                failed=$((failed + 1))
                ;;
        esac
    done < <(manifest_homebrew_tap_checkout_candidates "$primary_tap_dir")

    if [[ "$refreshed" -gt 0 || "$skipped" -gt 0 || "$failed" -gt 0 ]]; then
        echo "   Homebrew tap checkout refresh: ${refreshed} current/updated, ${skipped} skipped, ${failed} failed"
    fi

    return 0
}

# Push an updated Formula/manifest.rb from a tap checkout to the canonical
# Homebrew tap remote. Defaults to the SSH URL so push works regardless of how
# the local checkout's `origin` was configured (modern `brew tap` defaults to
# HTTPS, which fails the push with `could not read Username for 'https://github.com'`
# on hosts without cached HTTPS credentials).
#
# Overrides:
#   MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL — push target (default: SSH URL)
#   MANIFEST_CLI_HOMEBREW_TAP_BRANCH     — target branch (default: main)
manifest_homebrew_tap_push_formula() {
    local tap_dir="$1"
    local formula_file="$2"
    local tag="$3"

    local push_remote_url="${MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL:-git@github.com:fidenceio/homebrew-tap.git}"
    local push_branch="${MANIFEST_CLI_HOMEBREW_TAP_BRANCH:-main}"

    cp "$formula_file" "$tap_dir/Formula/manifest.rb"

    local push_log
    push_log="$(mktemp "$(manifest_make_scratch_path core)/tmp.XXXXXXXX")"
    (
        set -e
        cd "$tap_dir"
        git add Formula/manifest.rb
        if ! git diff --cached --quiet; then
            git commit -m "Update formula to ${tag}"
        fi
        git push "$push_remote_url" "HEAD:${push_branch}"
    ) >"$push_log" 2>&1
    local push_status=$?

    if [ "$push_status" -eq 0 ]; then
        cat "$push_log"
        echo "   ✅ Pushed to homebrew-tap repo (${push_remote_url})"
        rm -f "$push_log"
        return 0
    fi

    cat "$push_log" >&2
    log_error "Failed to push formula to homebrew-tap repo (${push_remote_url})"
    if grep -q "could not read Username for 'https://github.com" "$push_log"; then
        cat >&2 <<'EOF'

   The push target appears to be HTTPS with no cached credentials.
   Fix once, workspace-wide (recommended):
     git config --global url."git@github.com:fidenceio/".insteadOf "https://github.com/fidenceio/"

   This rewrites any https://github.com/fidenceio/* URL to SSH at the git
   transport layer — no per-repo remote edits needed, and survives re-taps.
EOF
    fi
    rm -f "$push_log"
    return "$push_status"
}

# Update Homebrew formula in both this repo and the tap repo
update_homebrew_formula() {
    if ! should_update_homebrew_for_repo; then
        local origin_slug=""
        origin_slug="$(manifest_origin_repo_slug || echo "unknown")"
        echo "🍺 Skipping Homebrew formula update for repository: ${origin_slug}"
        echo "   Homebrew updates run only for: ${MANIFEST_CLI_CANONICAL_REPO_SLUGS:-fidenceio/manifest.cli,fidenceio/fidenceio.manifest.cli}"
        return 0
    fi

    local version
    version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null)
    if [ -z "$version" ]; then
        log_error "Could not read VERSION file"
        return 1
    fi

    local tag
    if declare -F manifest_release_tag_name >/dev/null 2>&1; then
        tag="$(manifest_release_tag_name "$version")"
    else
        tag="v${version}"
    fi
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
            git pull --ff-only origin main
        ); then
            :
        else
            echo "   ⚠️  Could not pull latest from homebrew-tap — continuing with local state"
        fi
        if ! manifest_homebrew_tap_push_formula "$tap_dir" "$formula_file" "$tag"; then
            return 1
        fi
    else
        log_error "Homebrew tap not found locally at ${tap_dir:-<unset>} — formula sync would silently skip and leave the tap stale."
        log_error "Run: brew tap fidenceio/tap && brew install manifest, then re-ship."
        return 1
    fi

    manifest_refresh_homebrew_tap_checkouts "$tap_dir"

    echo "🍺 Homebrew formula update complete"
}

# Upgrade CLI function
# Test mode function
# get_next_version() - Now available from manifest-shared-functions.sh

# Auto-upgrade check with cooldown
check_auto_upgrade() {
    # Load from Cloud plugins; silently skip if not installed
    if manifest_load_plugin "workflow/manifest-auto-upgrade.sh"; then
        check_auto_upgrade_internal
    fi
}

_manifest_cli_is_help_token() {
    case "${1:-}" in
        help|-help|-h|--help) return 0 ;;
        *) return 1 ;;
    esac
}

_manifest_cli_has_help_token() {
    local arg
    for arg in "$@"; do
        if _manifest_cli_is_help_token "$arg"; then
            return 0
        fi
    done
    return 1
}

_manifest_cli_has_help_flag() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -help|-h|--help) return 0 ;;
        esac
    done
    return 1
}

_manifest_cli_has_explain_flag() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --explain) return 0 ;;
        esac
    done
    return 1
}

_manifest_cli_is_existing_repo_scope_request() {
    local command="${1:-}"
    shift || true

    case "$command" in
        prep|refresh|ship|status)
            [[ "${1:-}" == "repo" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

_manifest_cli_replay_command() {
    local command="${1:-manifest}"
    shift || true
    local replay="manifest $command"
    local arg
    for arg in "$@"; do
        replay+=" $arg"
    done
    echo "$replay"
}

_manifest_cli_is_help_request() {
    local command="${1:-}"
    shift || true

    if _manifest_cli_is_help_token "$command"; then
        return 0
    fi

    if [[ "${1:-}" == "help" ]]; then
        return 0
    fi

    _manifest_cli_has_help_flag "$@"
}

_manifest_pr_fleet_dispatch() {
    local pr_subcommand=""
    local implicit_queue=false

    case "${1:-}" in
        create|status|checks|ready|queue|help|-h|--help)
            pr_subcommand="${1:-help}"
            shift || true
            ;;
        "")
            pr_subcommand="queue"
            implicit_queue=true
            ;;
        *)
            pr_subcommand="queue"
            implicit_queue=true
            ;;
    esac

    if [ "$implicit_queue" = "true" ]; then
        echo "ℹ️  Default fleet PR action: queue (use 'manifest pr fleet help' for all subcommands)."
    fi
    if [[ "$pr_subcommand" == "help" || "$pr_subcommand" == "-h" || "$pr_subcommand" == "--help" ]]; then
        _render_help \
            "manifest pr fleet [queue|create|status|checks|ready] [-y|--yes] [--dry-run] [options]" \
            "Preview or run fleet-wide PR operations." \
            "Examples" "  manifest pr fleet
  manifest pr fleet create
  manifest pr fleet create -y
  manifest pr fleet queue --method squash -y"
        return 0
    fi

    case "$pr_subcommand" in
        create|ready|queue)
            local execution_mode="preview"
            local _local_only=false
            local remaining_args=()
            if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
                return 1
            fi
            set -- "${remaining_args[@]}"
            if [[ "$execution_mode" == "preview" ]]; then
                local replay_command="manifest pr fleet $pr_subcommand"
                local operation_label="$pr_subcommand"
                if [[ $# -gt 0 ]]; then
                    replay_command+=" $*"
                    operation_label+=" $*"
                fi
                manifest_execution_preview_header "manifest pr fleet $pr_subcommand"
                echo "Would run fleet PR operation: $operation_label"
                manifest_execution_footer "$replay_command -y"
                return 0
            fi
            manifest_execution_apply_header
            export MANIFEST_CLI_EXECUTION_MODE="apply"
            ;;
    esac

    if declare -F manifest_fleet_pr_dispatch >/dev/null 2>&1; then
        manifest_fleet_pr_dispatch "$pr_subcommand" "$@"
    else
        log_error "Fleet PR module unavailable"
        return 1
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
        "help"|"-help"|"--help"|"-h"|"version"|"-version"|"--version"|"-v"|"-V"|"uninstall"|"reinstall"|"add"|"discover"|"fleet"|"quickstart"|"update"|"upgrade"|"validate"|"config")
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
        "recipe")
            if [[ "${1:-}" == "run" ]] && ! _manifest_cli_is_help_request "$command" "$@"; then
                if ! ensure_repository_root; then
                    log_error "Repository root validation failed"
                    return 1
                fi

                PROJECT_ROOT="$(pwd)"
                export PROJECT_ROOT
                load_configuration "$PROJECT_ROOT"
                check_auto_upgrade
            else
                PROJECT_ROOT="$(pwd)"
                export PROJECT_ROOT
                load_configuration "$PROJECT_ROOT" "false"
            fi
            ;;
        "docs"|"pr"|"quickstart"|"plan"|"reconcile"|"discover"|"add"|"update"|"validate")
            if [[ "${1:-}" == "fleet" ]] || _manifest_cli_is_help_request "$command" "$@"; then
                PROJECT_ROOT="$(pwd)"
                export PROJECT_ROOT
                load_configuration "$PROJECT_ROOT" "false"
            else
                if ! ensure_repository_root; then
                    log_error "Repository root validation failed"
                    return 1
                fi

                PROJECT_ROOT="$(pwd)"
                export PROJECT_ROOT
                load_configuration "$PROJECT_ROOT"
                check_auto_upgrade
            fi
            ;;
        *)
            if _manifest_cli_is_help_request "$command" "$@" || { [[ "$command" == "ship" ]] && _manifest_cli_has_explain_flag "$@"; }; then
                PROJECT_ROOT="$(pwd)"
                export PROJECT_ROOT
                load_configuration "$PROJECT_ROOT" "false"
            else
                # All other commands require a Git repository
                if _manifest_cli_is_existing_repo_scope_request "$command" "$@"; then
                    if ! manifest_repo_scope_require_git "$(_manifest_cli_replay_command "$command" "$@")"; then
                        return 1
                    fi
                fi
                if ! ensure_repository_root; then
                    log_error "Repository root validation failed"
                    return 1
                fi

                PROJECT_ROOT="$(pwd)"
                export PROJECT_ROOT
                load_configuration "$PROJECT_ROOT"
                check_auto_upgrade
            fi
            ;;
    esac

    # =========================================================================
    # Command dispatch — v42 core journey + supporting + legacy aliases
    # =========================================================================
    case "$command" in

        # =====================================================================
        # CORE JOURNEY: config → init → prep → refresh → ship
        # =====================================================================
        "quickstart")
            case "${1:-}" in
                fleet)
                    shift || true
                    if _manifest_cli_has_help_token "$@"; then
                        _render_help \
                            "manifest quickstart fleet [-y|--yes] [--dry-run] [--name NAME] [--force]" \
                            "Initialize a fleet by auto-discovering existing git repositories." \
                            "Options" "  --dry-run      Explicit preview; no writes
  -y, --yes      Apply the quickstart plan
  --name NAME    Fleet name
  --force        Overwrite existing generated files"
                        return 0
                    fi
                    fleet_quickstart "$@"
                    ;;
                help|-h|--help)
                    _render_help \
                        "manifest quickstart <fleet> [options]" \
                        "Run an opinionated quickstart workflow." \
                        "Scopes" "  fleet   Auto-discover existing git repos and initialize a fleet"
                    ;;
                "")
                    _render_help_error "quickstart requires a scope" "manifest quickstart <fleet>"
                    return 1
                    ;;
                *)
                    _render_help_error "Unknown quickstart scope: $1" "manifest quickstart <fleet>"
                    return 1
                    ;;
            esac
            ;;

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

        "plan")
            case "${1:-}" in
                fleet)
                    shift || true
                    fleet_plan "$@"
                    ;;
                help|-h|--help)
                    _render_help \
                        "manifest plan <fleet> [options]" \
                        "Generate adoption plans. Dry-run by default." \
                        "Scopes" "  fleet   Generate manifest.fleet.plan.yaml"
                    ;;
                "")
                    _render_help_error "plan requires a scope" "manifest plan <fleet>"
                    return 1
                    ;;
                *)
                    _render_help_error "Unknown plan scope: $1" "manifest plan <fleet>"
                    return 1
                    ;;
            esac
            ;;

        "reconcile")
            case "${1:-}" in
                fleet)
                    shift || true
                    fleet_reconcile "$@"
                    ;;
                help|-h|--help)
                    _render_help \
                        "manifest reconcile <fleet> [options]" \
                        "Validate and apply adoption plans. Dry-run by default." \
                        "Scopes" "  fleet   Reconcile manifest.fleet.plan.yaml"
                    ;;
                "")
                    _render_help_error "reconcile requires a scope" "manifest reconcile <fleet>"
                    return 1
                    ;;
                *)
                    _render_help_error "Unknown reconcile scope: $1" "manifest reconcile <fleet>"
                    return 1
                    ;;
            esac
            ;;

        "refresh")
            manifest_refresh_dispatch "$@"
            ;;

        "recipe")
            manifest_recipe_dispatch "$@"
            ;;

        "discover")
            case "${1:-}" in
                fleet)
                    shift || true
                    if _manifest_cli_has_help_token "$@"; then
                        _render_help \
                            "manifest discover fleet [--depth N] [--json] [--quiet]" \
                            "Discover repositories for fleet membership without writing changes." \
                            "Options" "  --depth N    Maximum search depth (default: 5)
  --json       Output JSON summary
  --quiet, -q  Only output new repo lines"
                        return 0
                    fi
                    fleet_discover "$@"
                    ;;
                help|-h|--help)
                    _render_help \
                        "manifest discover <fleet> [options]" \
                        "Discover resources without writing changes." \
                        "Scopes" "  fleet   Discover repositories for fleet membership"
                    ;;
                "")
                    _render_help_error "discover requires a scope" "manifest discover <fleet>"
                    return 1
                    ;;
                *)
                    _render_help_error "Unknown discover scope: $1" "manifest discover <fleet>"
                    return 1
                    ;;
            esac
            ;;

        "add")
            case "${1:-}" in
                fleet)
                    shift || true
                    if _manifest_cli_has_help_token "$@"; then
                        _render_help \
                            "manifest add fleet <path-or-url> [-y|--yes] [--dry-run] [--name NAME] [--type TYPE]" \
                            "Add a local path or remote URL to fleet membership." \
                            "Options" "  --dry-run      Explicit preview; do not modify manifest.fleet.config.yaml
  -y, --yes      Apply fleet membership updates
  --name NAME    Service name
  --type TYPE    Service type"
                        return 0
                    fi
                    fleet_add "$@"
                    ;;
                help|-h|--help)
                    _render_help \
                        "manifest add <fleet> [options]" \
                        "Add a resource to Manifest-managed configuration." \
                        "Scopes" "  fleet   Add a service to fleet membership"
                    ;;
                "")
                    _render_help_error "add requires a scope" "manifest add <fleet>"
                    return 1
                    ;;
                *)
                    _render_help_error "Unknown add scope: $1" "manifest add <fleet>"
                    return 1
                    ;;
            esac
            ;;

        "update")
            case "${1:-}" in
                fleet)
                    shift || true
                    if _manifest_cli_has_help_token "$@"; then
                        _render_help \
                            "manifest update fleet [-y|--yes] [--dry-run] [--depth N] [--json] [--quiet]" \
                            "Re-scan fleet membership and add newly discovered repositories." \
                            "Options" "  --dry-run    Explicit preview; do not modify manifest.fleet.config.yaml
  -y, --yes    Apply fleet membership updates
  --depth N    Maximum search depth (default: 5)
  --json       Output JSON summary
  --quiet, -q  Only output new repo lines"
                        return 0
                    fi
                    fleet_update "$@"
                    ;;
                help|-h|--help)
                    _render_help \
                        "manifest update <fleet>" \
                        "Update resources. For CLI upgrades, use manifest upgrade." \
                        "Scopes" "  fleet   Re-scan fleet membership"
                    ;;
                "")
                    _render_help_error "update requires a scope" "manifest update <fleet>"
                    echo "For CLI upgrades, use: manifest upgrade"
                    return 1
                    ;;
                *)
                    _render_help_error "Unknown update scope: $1" "manifest update <fleet>"
                    return 1
                    ;;
            esac
            ;;

        "validate")
            case "${1:-}" in
                fleet)
                    shift || true
                    if _manifest_cli_has_help_token "$@"; then
                        _render_help \
                            "manifest validate fleet" \
                            "Validate fleet configuration and service paths."
                        return 0
                    fi
                    fleet_validate "$@"
                    ;;
                help|-h|--help)
                    _render_help \
                        "manifest validate <fleet>" \
                        "Validate Manifest-managed resources." \
                        "Scopes" "  fleet   Validate fleet configuration"
                    ;;
                "")
                    _render_help_error "validate requires a scope" "manifest validate <fleet>"
                    return 1
                    ;;
                *)
                    _render_help_error "Unknown validate scope: $1" "manifest validate <fleet>"
                    return 1
                    ;;
            esac
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
            if [[ "${1:-}" == "fleet" ]]; then
                shift || true
                _manifest_pr_fleet_dispatch "$@"
                return $?
            fi

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
                    local execution_mode="preview"
                    local _local_only=false
                    local remaining_args=()
                    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
                        return 1
                    fi
                    if [[ "$execution_mode" == "preview" ]]; then
                        manifest_execution_preview_header "manifest pr queue"
                        echo "Would run PR queue operation: ${remaining_args[*]}"
                        manifest_execution_footer "manifest pr queue ${remaining_args[*]} -y"
                        return 0
                    fi
                    manifest_execution_apply_header
                    export MANIFEST_CLI_EXECUTION_MODE="apply"
                    manifest_pr_queue "${remaining_args[@]}"
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
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest revert" \
                    "Interactively check out a previous version tag."
                return 0
            fi
            revert_version
            ;;

        # =====================================================================
        # DIAGNOSTIC / MAINTENANCE COMMANDS
        # =====================================================================
        "security")
            manifest_security "$@"
            ;;

        "test")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest test [type]" \
                    "Run diagnostic tests when the Manifest Cloud test module is installed."
                return 0
            fi
            run_manifest_test "$@"
            ;;

        "upgrade")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest upgrade" \
                    "Update Manifest CLI through the installed upgrade provider."
                return 0
            fi
            if manifest_load_plugin "workflow/manifest-auto-upgrade.sh"; then
                upgrade_cli_internal "$@"
            else
                log_warning "Upgrade module requires Manifest Cloud."
                echo "  To upgrade via Homebrew: brew update && brew upgrade manifest"
            fi
            ;;

        "uninstall")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest uninstall [-y|--yes] [--dry-run] [--force]" \
                    "Preview or remove Manifest CLI installation files. --force bypasses extra prompts only after -y selects apply mode."
                return 0
            fi
            local execution_mode="preview"
            local _local_only=false
            local remaining_args=()
            if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
                return 1
            fi
            local force_flag="false"
            local uninstall_arg
            for uninstall_arg in "${remaining_args[@]}"; do
                case "$uninstall_arg" in
                    --force)
                        force_flag="true"
                        ;;
                    *)
                        _render_help_error "Unknown uninstall option: $uninstall_arg" "manifest uninstall [-y|--yes] [--dry-run] [--force]"
                        return 1
                        ;;
                esac
            done
            if [[ "$execution_mode" == "preview" ]]; then
                local replay_command="manifest uninstall"
                [[ "$force_flag" == "true" ]] && replay_command+=" --force"
                preview_uninstall_manifest "$replay_command -y"
                return 0
            fi
            manifest_execution_apply_header
            uninstall_manifest "$force_flag" "$force_flag"
            ;;

        "reinstall")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest reinstall [-y|--yes] [--dry-run]" \
                    "Preview or reinstall Manifest CLI through Homebrew or the installed provider."
                return 0
            fi
            local execution_mode="preview"
            local _local_only=false
            local remaining_args=()
            if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
                return 1
            fi
            if [[ ${#remaining_args[@]} -gt 0 ]]; then
                _render_help_error "Unknown reinstall option: ${remaining_args[0]}" "manifest reinstall [-y|--yes] [--dry-run]"
                return 1
            fi
            if [[ "$execution_mode" == "preview" ]]; then
                preview_reinstall_manifest "manifest reinstall -y"
                return 0
            fi
            manifest_execution_apply_header
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
                # Manual reinstall: delegate to the canonical install-cli.sh.
                # Requires the user to be in the Manifest CLI source repo (or
                # in a checkout that still has install-cli.sh + modules/).
                if [ -f "$PROJECT_ROOT/install-cli.sh" ] && [ -d "$PROJECT_ROOT/modules" ]; then
                    echo "Reinstalling via manual install (running install-cli.sh from $PROJECT_ROOT)..."
                    bash "$PROJECT_ROOT/install-cli.sh"
                else
                    log_error "Manual reinstall requires install-cli.sh from the Manifest CLI source repo."
                    log_error "  cd /path/to/manifest.cli && ./install-cli.sh"
                    log_error "  brew reinstall fidenceio/tap/manifest"
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
                    local changes_file=$(mktemp "$(manifest_make_scratch_path core)/tmp.XXXXXXXX")
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
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest agent <subcommand> [options]" \
                    "Manage the optional containerized Manifest Cloud agent."
                return 0
            fi
            agent_main "${@}"
            ;;

        # =====================================================================
        # HIDDEN LEGACY ALIASES (still functional, not shown in help)
        # =====================================================================

        # Old "manifest fleet *" top-level — help plus replacement hints only
        "fleet")
            fleet_main "$@"
            ;;

        # Old "manifest sync" -> new "manifest prep repo"
        "sync")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest sync" \
                    "Deprecated alias for manifest prep repo."
                return 0
            fi
            log_deprecated "manifest sync" "manifest prep repo"
            manifest_prep_repo
            ;;

        # Old "manifest time" -> accessible via "manifest config time"
        "time")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest time" \
                    "Deprecated alias for manifest config time."
                return 0
            fi
            display_time_info
            ;;

        # Old "manifest commit" — plumbing, called by ship
        "commit")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest commit <message>" \
                    "Internal plumbing command used by ship to commit generated changes."
                return 0
            fi
            local message="$1"
            get_time_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            commit_changes "$message" "$timestamp"
            ;;

        # Old "manifest version" — plumbing, called by ship internally
        "bump-version")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest bump-version <patch|minor|major|revision>" \
                    "Internal plumbing command used by ship to update VERSION."
                return 0
            fi
            local increment_type="${1:-patch}"
            bump_version "$increment_type"
            ;;

        # Old "manifest docs" — plumbing, replaced by "refresh"
        "docs")
            if [[ "${1:-}" == "fleet" ]]; then
                shift || true
                fleet_docs_dispatch "$@"
                return $?
            fi
            local execution_mode="preview"
            local _local_only=false
            local docs_args=()
            if ! manifest_execution_parse execution_mode _local_only docs_args "$@"; then
                return 1
            fi
            set -- "${docs_args[@]}"
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest docs [metadata|cleanup|fleet] [-y|--yes] [--dry-run]" \
                    "Generate or inspect documentation for a Manifest-managed resource." \
                    "Scopes" "  fleet   Generate fleet documentation" \
                    "Options" "  --dry-run   Explicit preview; no writes
  -y, --yes   Apply documentation writes"
                return 0
            fi
            local subcommand="$1"
            case "$subcommand" in
                "metadata")
                    if [[ "$execution_mode" == "preview" ]]; then
                        manifest_execution_preview_header "manifest docs metadata"
                        echo "Would update repository metadata."
                        manifest_execution_footer "manifest docs metadata -y"
                        return 0
                    fi
                    manifest_execution_apply_header
                    update_repository_metadata
                    ;;
                "homebrew")
                    echo "Homebrew formula is updated automatically by 'manifest ship'"
                    ;;
                "cleanup")
                    local cleanup_version=""
                    if [ -f "$MANIFEST_CLI_VERSION_FILE" ]; then
                        cleanup_version=$(cat "$MANIFEST_CLI_VERSION_FILE")
                    fi
                    if [ -z "$cleanup_version" ]; then
                        log_error "Could not determine current version. Run 'manifest init repo' first."
                        return 1
                    fi
                    get_time_timestamp >/dev/null
                    local cleanup_timestamp
                    cleanup_timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
                    if [[ "$execution_mode" == "preview" ]]; then
                        manifest_execution_preview_header "manifest docs cleanup"
                        echo "Would move historical documentation to zArchive for v$cleanup_version."
                        manifest_execution_footer "manifest docs cleanup -y"
                        return 0
                    fi
                    manifest_execution_apply_header
                    echo "Moving historical documentation to zArchive..."
                    main_cleanup "$cleanup_version" "$cleanup_timestamp"
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
                    if [[ "$execution_mode" == "preview" ]]; then
                        manifest_execution_preview_header "manifest docs"
                        echo "Would generate documentation for v$current_version."
                        manifest_execution_footer "manifest docs -y"
                        return 0
                    fi
                    manifest_execution_apply_header
                    manifest_docs_generate "$current_version" "$timestamp" "patch"
                    ;;
            esac
            ;;

        # Old "manifest cleanup" — plumbing, absorbed into "refresh"
        "cleanup")
            if _manifest_cli_has_help_token "$@"; then
                _render_help \
                    "manifest cleanup" \
                    "Deprecated documentation cleanup plumbing. Prefer manifest refresh repo."
                return 0
            fi
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
    recipe                              Inspect workflow recipe definitions
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
