#!/bin/bash

# =============================================================================
# MANIFEST FLEET - MAIN MODULE
# =============================================================================
#
# PURPOSE:
#   Main entry point for Manifest Fleet functionality. Provides the command
#   interface for managing polyrepo/microservices architectures with
#   coordinated versioning, documentation, and releases.
#
# OVERVIEW:
#   Manifest Fleet extends Manifest CLI to handle multiple related repositories
#   as a cohesive unit ("fleet"). It enables:
#
#   - Coordinated version bumps across all services
#   - Unified changelogs aggregating changes from all repos
#   - Dependency tracking between services
#   - Auto-discovery of new repos in workspace
#   - Parallel operations for faster releases
#
# ARCHITECTURE:
#   ┌─────────────────────────────────────────────────────────────────┐
#   │                     manifest-fleet.sh (this file)               │
#   │                     Main orchestration & CLI                    │
#   └─────────────────────────────────────────────────────────────────┘
#                                    │
#          ┌─────────────────────────┼─────────────────────────┐
#          ▼                         ▼                         ▼
#   ┌─────────────────┐   ┌──────────────────┐   ┌─────────────────────┐
#   │ fleet-config.sh │   │ fleet-detect.sh  │   │ fleet-changelog.sh  │
#   │ YAML parsing    │   │ Auto-discovery   │   │ Unified docs        │
#   │ Configuration   │   │ Repo detection   │   │ (future)            │
#   └─────────────────┘   └──────────────────┘   └─────────────────────┘
#
# COMMANDS (v42 entry points — preferred):
#   manifest init fleet      - Scaffold a new fleet (calls _fleet_start / _fleet_init)
#   manifest prep fleet      - Clone/pull all services (calls _fleet_sync)
#   manifest refresh fleet   - Re-scan, regenerate docs (calls fleet_update + fleet_docs)
#   manifest ship fleet      - Coordinated release across services
#
# ADDITIONAL ACTION-FIRST COMMANDS:
#   manifest status          - Show fleet status when in fleet mode
#   manifest update fleet    - Re-scan and add new repos (--dry-run to preview)
#   manifest discover fleet  - Alias for 'update fleet --dry-run'
#   manifest add fleet       - Add a service to fleet
#   manifest quickstart fleet - Auto-discover git repos (skips TSV selection)
#   manifest prep fleet      - Coordinated version bump (no commit/push)
#   manifest docs fleet      - Generate unified documentation
#   manifest validate fleet  - Validate configuration
#
# USAGE:
#   # From manifest-core.sh
#   source manifest-fleet.sh
#   fleet_main "status"
#
#   # Standalone (for testing)
#   ./manifest-fleet.sh status
#
# =============================================================================

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Get the directory where this script is located
MANIFEST_CLI_FLEET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prevent multiple sourcing
if [[ -n "${_MANIFEST_CLI_FLEET_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_FLEET_LOADED=1

# Module metadata
readonly MANIFEST_CLI_FLEET_MODULE_VERSION="1.0.0"
readonly MANIFEST_CLI_FLEET_MODULE_NAME="manifest-fleet"

# -----------------------------------------------------------------------------
# Source Dependencies
# -----------------------------------------------------------------------------
# Source fleet sub-modules
source "$MANIFEST_CLI_FLEET_SCRIPT_DIR/manifest-fleet-config.sh"
source "$MANIFEST_CLI_FLEET_SCRIPT_DIR/manifest-fleet-detect.sh"
source "$MANIFEST_CLI_FLEET_SCRIPT_DIR/manifest-fleet-docs.sh"
source "$MANIFEST_CLI_FLEET_SCRIPT_DIR/manifest-fleet-plan.sh"
source "$MANIFEST_CLI_FLEET_SCRIPT_DIR/manifest-fleet-apply.sh"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _fleet_ensure_gitignores (internal)
# -----------------------------------------------------------------------------
# Ensures .gitignore files exist in discovered repos.
#
# ARGUMENTS:
#   $1 - Fleet root directory
#   $2 - Tab-delimited repo list (from get_new_repos or discover_fleet_repos)
# -----------------------------------------------------------------------------
_fleet_ensure_gitignores() {
    local root_dir="$1"
    local repos="$2"

    [[ -z "$repos" ]] && return 0

    echo ""
    echo "Ensuring .gitignore in discovered repositories..."
    local gitignore_created=0
    local gitignore_overwritten=0
    local gitignore_ref=0
    local gitignore_skipped=0
    local gitignore_failed=0
    local overwritten_repos=()

    while IFS=$'\t' read -r name path _type _branch _version _url _submodule; do
        [[ -z "$path" ]] && continue
        local repo_path="$root_dir/$path"
        [[ ! -d "$repo_path" ]] && continue

        local result
        result=$(ensure_gitignore_smart "$repo_path")
        local rc=$?

        if [[ $rc -ne 0 ]]; then
            echo "  ✗ $name: failed to create .gitignore"
            ((gitignore_failed++))
            continue
        fi

        case "$result" in
            ".gitignore")
                echo "  ✓ $name: created .gitignore"
                ((gitignore_created++))
                ;;
            ".gitignore:empty-overwrite")
                echo "  ✓ $name: created .gitignore"
                ((gitignore_overwritten++))
                overwritten_repos+=("$name")
                ;;
            ".gitignore.manifest")
                echo "  ~ $name: existing .gitignore preserved, created .gitignore.manifest"
                ((gitignore_ref++))
                ;;
            *)
                ((gitignore_skipped++))
                ;;
        esac
    done <<< "$repos"

    echo ""
    local total_created=$((gitignore_created + gitignore_overwritten))
    echo "Gitignore summary: $total_created created, $gitignore_ref reference files, $gitignore_skipped already present${gitignore_failed:+, $gitignore_failed failed}"

    # Deferred warnings for empty-overwrite repos
    if [[ ${#overwritten_repos[@]} -gt 0 ]]; then
        echo ""
        log_warning "The following repos had an existing .gitignore with no entries, which was overwritten with Manifest defaults:"
        for repo_name in "${overwritten_repos[@]}"; do
            log_warning "  • $repo_name"
        done
        log_warning "If any empty .gitignore was intentional, review and adjust as needed."
    fi
}

# -----------------------------------------------------------------------------
# Function: _fleet_resolve_config (internal)
# -----------------------------------------------------------------------------
# Resolves the fleet config file path. Prefers the global variable if set,
# otherwise looks for the config file in the given root directory.
#
# ARGUMENTS:
#   $1 - Root directory to search (defaults to MANIFEST_CLI_FLEET_ROOT or pwd)
#
# OUTPUT:
#   Echoes the resolved config file path
# -----------------------------------------------------------------------------
_fleet_resolve_config() {
    local root_dir="${1:-${MANIFEST_CLI_FLEET_ROOT:-.}}"
    local config_file="${MANIFEST_CLI_FLEET_CONFIG_FILE:-}"
    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        local config_filename="${MANIFEST_CLI_FLEET_CONFIG_FILENAME:-$MANIFEST_CLI_FLEET_DEFAULT_CONFIG_FILENAME}"
        config_file="$root_dir/$config_filename"
    fi
    echo "$config_file"
}

# -----------------------------------------------------------------------------
# Function: _fleet_ensure_initialized
# -----------------------------------------------------------------------------
# Ensures fleet configuration is loaded before running commands.
#
# RETURNS:
#   0 if fleet is initialized and loaded
#   1 if not in fleet mode or configuration failed to load
# -----------------------------------------------------------------------------
_fleet_ensure_initialized() {
    if [[ "$MANIFEST_CLI_FLEET_ACTIVE" != "true" ]]; then
        if ! load_fleet_config; then
            return 1
        fi
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Function: _fleet_require_initialized
# -----------------------------------------------------------------------------
# Like _fleet_ensure_initialized but exits with error if not in fleet.
#
# ARGUMENTS:
#   $1 - Command name (for error message)
# -----------------------------------------------------------------------------
_fleet_require_initialized() {
    local command="$1"

    if ! _fleet_ensure_initialized; then
        log_error "Command '$command' requires fleet mode"
        log_error "Either:"
        log_error "  1. Run from a directory containing manifest.fleet.config.yaml"
        log_error "  2. Run 'manifest init fleet' to create a new fleet"
        log_error "  3. Set MANIFEST_CLI_FLEET_ROOT to point to fleet directory"
        return 1
    fi
    return 0
}

# =============================================================================
# COMMAND: fleet status
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_status
# -----------------------------------------------------------------------------
# Displays comprehensive fleet status including:
#   - Fleet metadata
#   - Service status (git state, version, branch)
#   - Dependency health
#   - Pending changes summary
#
# ARGUMENTS:
#   --verbose, -v    Show detailed information for each service
#   --json           Output in JSON format (for scripting)
#
# EXAMPLE:
#   manifest status
#   manifest status --verbose
# -----------------------------------------------------------------------------
fleet_status() {
    local verbose=false
    local json_output=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) verbose=true; shift ;;
            --json) json_output=true; shift ;;
            *) shift ;;
        esac
    done

    # Ensure fleet is initialized
    if ! _fleet_ensure_initialized; then
        # Not in fleet mode - show single repo status hint
        echo "Not in fleet mode. Use 'manifest status' for single-repo status."
        echo ""
        echo "To initialize a fleet in this directory:"
        echo "  manifest init fleet"
        echo ""
        echo "To discover existing repos:"
        echo "  manifest discover fleet"
        return 0
    fi

    # Output JSON if requested
    if [[ "$json_output" == "true" ]]; then
        _fleet_status_json
        return 0
    fi

    # Header
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                        MANIFEST FLEET STATUS                         ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Fleet metadata
    echo "Fleet: $MANIFEST_CLI_FLEET_NAME"
    [[ -n "$MANIFEST_CLI_FLEET_DESCRIPTION" ]] && echo "       $MANIFEST_CLI_FLEET_DESCRIPTION"
    echo "Root:  $MANIFEST_CLI_FLEET_ROOT"
    echo ""

    # Fleet version (if enabled)
    if [[ "$MANIFEST_CLI_FLEET_VERSIONING" != "none" ]] && [[ -n "$MANIFEST_CLI_FLEET_VERSION" ]]; then
        echo "Fleet Version: $MANIFEST_CLI_FLEET_VERSION ($MANIFEST_CLI_FLEET_VERSIONING)"
        echo ""
    fi

    # Service count
    local service_count
    # shellcheck disable=SC2086
    service_count=$(set -- $MANIFEST_CLI_FLEET_SERVICES; echo $#)
    echo "Services: $service_count"
    echo ""

    # Service table header
    printf "┌─────────────────────────┬──────────┬──────────┬──────────────┬─────────┐\n"
    printf "│ %-23s │ %-8s │ %-8s │ %-12s │ %-7s │\n" "SERVICE" "TYPE" "VERSION" "BRANCH" "STATUS"
    printf "├─────────────────────────┼──────────┼──────────┼──────────────┼─────────┤\n"

    # Service details
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        local path=$(get_fleet_service_property "$service" "path")
        local type=$(get_fleet_service_property "$service" "type" "service")
        local expected_branch=$(get_fleet_service_property "$service" "branch" "main")
        local excluded=$(get_fleet_service_property "$service" "excluded" "false")

        # Get actual status from repo
        local version="N/A"
        local branch="N/A"
        local status="missing"
        local status_icon=""

        if [[ -d "$path" ]]; then
            if _is_git_repository "$path"; then
                version=$(_get_repo_version "$path")
                branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "detached")

                # Determine status
                local dirty=$(git -C "$path" status --porcelain 2>/dev/null | head -1)
                if [[ -n "$dirty" ]]; then
                    status="dirty"
                    status_icon="*"
                elif [[ "$branch" != "$expected_branch" ]]; then
                    status="branch"
                    status_icon="~"
                else
                    status="ready"
                    status_icon="✓"
                fi
            else
                status="not-git"
            fi
        fi

        # Truncate long values for display
        local display_service="${service:0:23}"
        local display_type="${type:0:8}"
        local display_version="${version:0:8}"
        local display_branch="${branch:0:12}"

        printf "│ %-23s │ %-8s │ %-8s │ %-12s │ %-1s %-5s │\n" \
            "$display_service" "$display_type" "$display_version" "$display_branch" "$status_icon" "$status"

        # Verbose output
        if [[ "$verbose" == "true" ]]; then
            printf "│   Path: %-63s │\n" "$path"
            local service_url
            service_url=$(get_fleet_service_property "$service" "url")
            if [[ -n "$service_url" ]]; then
                printf "│   URL:  %-63s │\n" "$service_url"
            fi
        fi
    done

    printf "└─────────────────────────┴──────────┴──────────┴──────────────┴─────────┘\n"

    # Legend
    echo ""
    echo "Status: ✓ ready  * dirty  ~ wrong branch  missing/not-git"
    echo ""

    # Quick actions
    echo "Quick actions:"
    echo "  manifest refresh fleet            - Re-scan, regenerate docs"
    echo "  manifest refresh fleet --dry-run  - Preview new/missing repos"
    echo "  manifest prep fleet               - Clone missing, pull existing"
    echo "  manifest ship fleet patch         - Coordinated release"
}

# -----------------------------------------------------------------------------
# Function: _fleet_status_json (internal)
# -----------------------------------------------------------------------------
# Outputs fleet status in JSON format.
# -----------------------------------------------------------------------------
_fleet_status_json() {
    # Helper: escape a string for safe JSON embedding
    _json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\t'/\\t}"
        s="${s//$'\r'/\\r}"
        s="${s//$'\b'/\\b}"
        s="${s//$'\f'/\\f}"
        printf '%s' "$s"
    }

    echo "{"
    echo "  \"fleet\": {"
    echo "    \"name\": \"$(_json_escape "$MANIFEST_CLI_FLEET_NAME")\","
    echo "    \"root\": \"$(_json_escape "$MANIFEST_CLI_FLEET_ROOT")\","
    if [[ -n "${MANIFEST_CLI_FLEET_VERSION:-}" ]]; then
        echo "    \"version\": \"$(_json_escape "$MANIFEST_CLI_FLEET_VERSION")\","
    else
        echo "    \"version\": null,"
    fi
    echo "    \"versioning\": \"$MANIFEST_CLI_FLEET_VERSIONING\""
    echo "  },"
    echo "  \"services\": ["

    local first=true
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        [[ "$first" == "true" ]] || echo ","
        first=false

        local path=$(get_fleet_service_property "$service" "path")
        local type=$(get_fleet_service_property "$service" "type" "service")
        local version=$(_get_repo_version "$path" 2>/dev/null || echo "unknown")
        local branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "unknown")
        local status="missing"
        [[ -d "$path" ]] && status="present"
        [[ -d "$path/.git" ]] && status="ready"

        echo -n "    {\"name\": \"$(_json_escape "$service")\", \"type\": \"$(_json_escape "$type")\", \"version\": \"$(_json_escape "$version")\", \"branch\": \"$(_json_escape "$branch")\", \"status\": \"$status\"}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# =============================================================================
# COMMAND: fleet quickstart
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_quickstart
# -----------------------------------------------------------------------------
# Shortcut that skips the selection file and auto-discovers existing git repos.
# Equivalent to: manifest init fleet with the quickstart path.
# -----------------------------------------------------------------------------
fleet_quickstart() {
    local original_args=("$@")
    local dry_run=true
    local fleet_name=""
    local force=false
    local create_repo_visibility=""
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()

    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    [[ "$execution_mode" == "apply" ]] && dry_run=false
    original_args=("${remaining_args[@]}")
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--name requires a value"
                    return 1
                fi
                fleet_name="$2"; shift 2 ;;
            -f|--force) force=true; shift ;;
            --create-repo-private)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "private") || return 1
                shift ;;
            --create-repo-public)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "public") || return 1
                shift ;;
            *) shift ;;
        esac
    done

    if [[ "${original_args[0]:-}" == "help" || "${original_args[0]:-}" == "-h" || "${original_args[0]:-}" == "--help" ]]; then
        _render_help \
            "manifest quickstart fleet [-y|--yes] [--dry-run] [--name NAME] [--force]" \
            "Initialize a fleet by auto-discovering existing git repositories."
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        if [[ -n "$create_repo_visibility" ]]; then
            log_error "--create-repo-$create_repo_visibility is not supported with quickstart."
            log_error "Quickstart discovers existing repos; --create-repo-* is for fresh dirs."
            log_error "Use 'manifest init fleet --create-repo-$create_repo_visibility --dry-run' instead."
            return 1
        fi

        local target_dir="$(pwd)"
        local config_file="$target_dir/manifest.fleet.config.yaml"
        local start_file="$target_dir/manifest.fleet.tsv"
        local local_config="$target_dir/manifest.config.local.yaml"
        local discovered
        discovered=$(discover_all_directories "$target_dir" 5)

        local total=0 git_count=0
        while IFS=$'\t' read -r name _path _type _branch _version _url _submodule has_git _has_remote; do
            [[ -z "$name" ]] && continue
            ((total += 1))
            [[ "$has_git" == "true" ]] && ((git_count += 1))
        done <<< "$discovered"

        if [[ -z "$fleet_name" ]]; then
            fleet_name=$(basename "$target_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        fi

        echo ""
        echo "Dry run - manifest quickstart fleet: $target_dir"
        echo ""
        if [[ -f "$config_file" && "$force" == "true" ]]; then
            echo "Would overwrite: $config_file"
        elif [[ -f "$config_file" ]]; then
            echo "Exists:          $config_file"
        else
            echo "Would create:    $config_file"
        fi
        if [[ -f "$local_config" ]]; then
            echo "Exists:          $local_config"
        else
            echo "Would create:    $local_config"
        fi
        if [[ -f "$start_file" ]]; then
            echo "Would update:    $start_file"
        else
            echo "Would create:    $start_file"
        fi
        echo "Fleet name:      $fleet_name"
        echo "Would scan:      $total directories"
        echo "Would list:      $git_count existing git repos in manifest.fleet.tsv"
        echo ""
        manifest_execution_footer "manifest quickstart fleet -y"
        return 0
    fi

    manifest_execution_apply_header
    _fleet_init --_quickstart "${original_args[@]}"
}

# =============================================================================
# INTERNAL: fleet start (Phase 1 of init fleet)
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _fleet_start (internal)
# -----------------------------------------------------------------------------
# Scans subdirectories and writes a TSV selection file. By default, the scan is
# exhaustive internally but the TSV is compact: users choose the repo depth for
# each top-level folder. Pass --all-folders for the old exhaustive TSV.
#
# Called from manifest_init_fleet (Phase 1) in modules/core/manifest-init.sh.
#
# ARGUMENTS:
#   --depth N       Maximum search depth (default: 5)
#   --all-folders   Write every scanned folder to manifest.fleet.tsv
#   --force         Overwrite existing manifest.fleet.tsv
# -----------------------------------------------------------------------------
_fleet_start() {
    local depth=5
    local force=false
    local all_folders=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--depth requires a numeric value"
                    return 1
                fi
                depth="$2"; shift 2 ;;
            --all-folders) all_folders=true; shift ;;
            -f|--force) force=true; shift ;;
            *) shift ;;
        esac
    done

    if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
        log_error "--depth must be a non-negative integer"
        return 1
    fi

    local root_dir="$(pwd)"
    local start_file="$root_dir/manifest.fleet.tsv"

    # Guard against overwriting a hand-edited file
    if [[ -f "$start_file" ]] && [[ "$force" != "true" ]]; then
        log_warning "Selection file already exists: $start_file"
        echo ""
        echo "  To edit and continue:    open manifest.fleet.tsv"
        echo "  To regenerate:           manifest init fleet --force"
        echo "  To initialize from it:   manifest init fleet"
        return 0
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                  MANIFEST INIT FLEET (PHASE 1/2)                    ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Scanning: $root_dir (depth: $depth)"
    if [[ "$all_folders" == "true" ]]; then
        echo "Inventory mode: all scanned folders"
    else
        echo "Inventory mode: repo-depth prompts"
    fi
    echo ""

    local discovered
    discovered=$(discover_all_directories "$root_dir" "$depth")

    if [[ -z "$discovered" ]]; then
        log_warning "No directories found in: $root_dir"
        return 0
    fi

    local rules="" fingerprint_mode="fingerprint"
    if [[ "$all_folders" != "true" ]]; then
        if [[ -t 0 && -r /dev/tty ]]; then
            rules=$(_fleet_prompt_repo_depth_rules "$discovered")
            fingerprint_mode="trusted"
        else
            rules=$(_fleet_default_repo_depth_rules "$discovered")
        fi
    fi

    local inventory
    inventory=$(filter_start_inventory_by_repo_depth "$discovered" "$rules" "$all_folders")

    if [[ -z "$inventory" ]]; then
        log_warning "No directories matched the selected repo-depth rules."
        echo "Use --all-folders to write the exhaustive directory inventory."
        return 0
    fi

    # Write TSV selection file
    if [[ "$all_folders" == "true" ]]; then
        generate_start_tsv "$inventory" "$root_dir" "$depth" "git-only" "$fingerprint_mode" > "$start_file"
    else
        generate_start_tsv "$inventory" "$root_dir" "$depth" "listed" "$fingerprint_mode" > "$start_file"
    fi

    # Count stats for summary
    local scanned_total=0 listed_total=0 git_count=0 plain_count=0
    while IFS=$'\t' read -r name path type branch version url submodule has_git has_remote; do
        [[ -z "$name" ]] && continue
        ((scanned_total++))
    done <<< "$discovered"
    while IFS=$'\t' read -r name path type branch version url submodule has_git has_remote; do
        [[ -z "$name" ]] && continue
        ((listed_total++))
        if [[ "$has_git" == "true" ]]; then
            ((git_count++))
        else
            ((plain_count++))
        fi
    done <<< "$inventory"

    echo "Scan results:"
    echo "  Scanned directories: $scanned_total"
    echo "  Listed in TSV:       $listed_total"
    echo "  With git:            $git_count"
    if [[ "$all_folders" == "true" ]]; then
        echo "  Without git:         $plain_count (not selected by default)"
    else
        echo "  Without git:         $plain_count (selected by repo-depth rule)"
    fi
    echo ""
    echo "✓ Created: $start_file"
    echo ""
    echo "Next steps:"
    echo "  1. Review manifest.fleet.tsv — adjust SELECT if needed"
    echo "  2. Run 'manifest init fleet' to initialize selected directories"
    if [[ "$all_folders" != "true" ]]; then
        echo ""
        echo "Tip: use 'manifest init fleet --all-folders --force' for the exhaustive directory list."
    fi
    echo ""
}

# =============================================================================
# INTERNAL: directory initialization helper
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _fleet_init_directory (internal)
# -----------------------------------------------------------------------------
# Bootstraps a single directory with git and .gitignore as needed, and
# (optionally) creates the GitHub repo behind it via `gh repo create`.
#
# ARGUMENTS:
#   $1 - Absolute path to the directory
#   $2 - has_git flag ("true" or "false")
#   $3 - create_visibility ("" / "private" / "public") — when set, after init
#        invokes _manifest_gh_repo_create (already idempotent vs. existing
#        origin). Caller is responsible for the one-time gh pre-flight.
#
# EXIT CODES:
#   0 - init ok (and gh ok / skipped / not requested)
#   1 - git init failed (real failure — permissions, disk full, etc.)
#   2 - init ok but gh repo create failed
#   3 - path missing on disk (TSV row points at a non-existent directory)
# -----------------------------------------------------------------------------
_fleet_init_directory() {
    local dir_path="$1"
    local has_git="$2"
    local create_visibility="${3:-}"

    if [[ ! -d "$dir_path" ]]; then
        log_warning "Directory not found, skipping: $dir_path"
        return 3
    fi

    if [[ "$has_git" != "true" ]]; then
        if git init "$dir_path" >/dev/null; then
            echo "  ✓ git init: $(basename "$dir_path")"
        else
            log_error "git init failed: $dir_path"
            return 1
        fi
    fi

    # Ensure .gitignore exists
    if declare -F ensure_gitignore_smart >/dev/null 2>&1; then
        ensure_gitignore_smart "$dir_path" >/dev/null 2>&1
    fi

    if [[ -n "$create_visibility" ]]; then
        if ! _manifest_gh_repo_create "$dir_path" "$create_visibility"; then
            return 2
        fi
    fi

    return 0
}

# =============================================================================
# INTERNAL: fleet init (Phase 2 of init fleet)
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _fleet_init (internal)
# -----------------------------------------------------------------------------
# Initializes a new fleet in the current directory.
#
# Called from manifest_init_fleet (Phase 2) in modules/core/manifest-init.sh.
#
# If manifest.fleet.tsv exists (from Phase 1 / _fleet_start), reads the user's
# selections and initializes those directories. Otherwise, falls back to
# auto-discovery via fleet_update (--_quickstart forces this path).
#
# BEHAVIOR (with start file):
#   1. Reads selected directories from manifest.fleet.tsv
#   2. Bootstraps each directory (git init, .gitignore)
#   3. Creates skeleton manifest.fleet.config.yaml with selected services
#   4. Creates manifest.config.local.yaml
#   5. Validates the configuration
#
# BEHAVIOR (without start file / --_quickstart):
#   1. Creates skeleton manifest.fleet.config.yaml
#   2. Calls fleet_update --_from-init to auto-discover git repos
#   3. Validates the configuration
#
# ARGUMENTS:
#   --name, -n NAME              Fleet name (prompted if not provided)
#   --template, -t               Use minimal template (no comments)
#   --force, -f                  Overwrite existing manifest.fleet.config.yaml
#   --_quickstart                Skip start file, use auto-discovery (used by fleet_quickstart)
#   --create-repo-private        After init, gh-create a private GitHub repo per dir
#   --create-repo-public         After init, gh-create a public  GitHub repo per dir
#
# EXIT CODES:
#   0  All directories initialized (and gh ok if requested)
#   1  One or more directories failed to init or to create their gh repo
#   2  TSV references one or more directories that don't exist on disk
# -----------------------------------------------------------------------------
_fleet_init() {
    local fleet_name=""
    local minimal_template=false
    local force=false
    local skip_start=false
    local create_repo_visibility=""
    local _fleet_init_status=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--name requires a value"
                    return 1
                fi
                fleet_name="$2"; shift 2 ;;
            -t|--template) minimal_template=true; shift ;;
            -f|--force) force=true; shift ;;
            --_quickstart) skip_start=true; shift ;;
            --create-repo-private)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "private") || return 1
                shift ;;
            --create-repo-public)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "public") || return 1
                shift ;;
            *) shift ;;
        esac
    done

    # Quickstart discovers existing git repos and writes the TSV; it does
    # not loop through _fleet_init_directory, so --create-repo-* would
    # silently no-op. Hard-error instead of paying the gh pre-flight then
    # ignoring the flag.
    if [[ "$skip_start" == "true" && -n "$create_repo_visibility" ]]; then
        log_error "--create-repo-$create_repo_visibility is not supported with quickstart."
        log_error "Quickstart discovers existing repos; --create-repo-* is for fresh dirs."
        log_error "Use 'manifest init fleet --create-repo-$create_repo_visibility' instead."
        return 1
    fi

    # Pre-flight gh ONCE before the per-row loop. _manifest_require_gh
    # memoizes the success result so subsequent calls inside
    # _fleet_init_directory are no-ops (TTL bounds staleness).
    if [[ -n "$create_repo_visibility" ]]; then
        if ! _manifest_require_gh; then
            return 1
        fi
    fi

    local target_dir="$(pwd)"
    local config_file="$target_dir/manifest.fleet.config.yaml"
    local start_file="$target_dir/manifest.fleet.tsv"

    # If fleet already exists, tell the user clearly and suggest the right command
    if [[ -f "$config_file" ]] && [[ "$force" != "true" ]]; then
        log_warning "Fleet already initialized at: $config_file"
        echo ""
        echo "  To add newly discovered repos:  manifest refresh fleet"
        echo "  To preview without changes:     manifest refresh fleet --dry-run"
        echo "  To reinitialize from scratch:   manifest init fleet --force"
        return 0
    fi

    # Decide which path: start-file or auto-discovery
    local use_start_file=false
    if [[ "$skip_start" != "true" ]] && [[ -f "$start_file" ]]; then
        use_start_file=true
    elif [[ "$skip_start" != "true" ]] && [[ ! -f "$start_file" ]]; then
        log_warning "No selection file found."
        echo ""
        echo "  Recommended:  manifest init fleet           (scan and select directories)"
        echo "  Quick start:  manifest quickstart fleet     (auto-discover git repos)"
        return 1
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                  MANIFEST INIT FLEET (PHASE 2/2)                    ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Get fleet name if not provided
    if [[ -z "$fleet_name" ]]; then
        local default_name
        default_name=$(basename "$target_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        echo "Enter fleet name (default: $default_name):"
        read -r fleet_name
        fleet_name="${fleet_name:-$default_name}"
    fi

    echo "Initializing fleet: $fleet_name"
    echo "Location: $target_dir"
    echo ""

    # Generate skeleton manifest.fleet.config.yaml
    echo "Creating manifest.fleet.config.yaml..."

    if [[ "$minimal_template" == "true" ]]; then
        _generate_minimal_manifest "$config_file" "$fleet_name"
    else
        _generate_full_manifest "$config_file" "$fleet_name"
    fi

    echo "✓ Created: $config_file"

    # Create manifest.config.local.yaml if it doesn't exist
    local local_config="$target_dir/manifest.config.local.yaml"
    if [[ ! -f "$local_config" ]]; then
        echo ""
        echo "Creating manifest.config.local.yaml..."
        cat > "$local_config" << 'EOF'
# Fleet-specific configuration (git-ignored)
# See manifest.fleet.config.yaml for fleet definition

fleet:
  mode: "auto"
  # parallel: true
  # push_strategy: "batched"
EOF
        echo "✓ Created: $local_config"
    fi

    if [[ "$use_start_file" == "true" ]]; then
        # --- Start-file path: bootstrap selected directories ---
        echo ""
        echo "Reading selections from: $start_file"

        local selected
        selected=$(parse_start_tsv "$start_file")

        if [[ -z "$selected" ]]; then
            log_warning "No directories selected in $start_file"
            echo "Edit the file and set SELECT to 'true' for directories to include."
            return 0
        fi

        # Bootstrap each selected directory (git init, .gitignore, optional gh).
        # Per-row outcomes accumulate into arrays so the fix-it block can name
        # the offending paths instead of just counting them.
        local init_count=0 gh_ok_count=0
        local missing_paths=() init_failed_paths=() gh_failed_paths=()
        echo ""
        echo "Initializing selected directories..."

        while IFS=$'\t' read -r name path type has_git url branch version; do
            [[ -z "$name" ]] && continue
            local abs_path="$target_dir/${path#./}"

            _fleet_init_directory "$abs_path" "$has_git" "$create_repo_visibility"
            case $? in
                0)
                    ((init_count++))
                    [[ -n "$create_repo_visibility" ]] && ((gh_ok_count++))
                    ;;
                1)
                    init_failed_paths+=("$path")
                    ;;
                2)
                    ((init_count++))
                    gh_failed_paths+=("$path")
                    ;;
                3)
                    missing_paths+=("$path")
                    ;;
            esac
        done <<< "$selected"

        local missing_count=${#missing_paths[@]}
        local init_failed_count=${#init_failed_paths[@]}
        local gh_failed_count=${#gh_failed_paths[@]}

        echo ""
        if (( missing_count > 0 || init_failed_count > 0 )); then
            echo "Initialized: $init_count   Missing: $missing_count   Failed: $init_failed_count"
        else
            echo "Initialized: $init_count"
        fi
        if [[ -n "$create_repo_visibility" ]]; then
            echo "GitHub ($create_repo_visibility): $gh_ok_count ready, $gh_failed_count failed"
        fi

        # Strict exit-code rule: real failures (init / gh) outrank config
        # errors (missing). CI/automation parses status without grepping
        # English; ordering matches severity.
        if (( init_failed_count > 0 || gh_failed_count > 0 )); then
            _fleet_init_status=1
        elif (( missing_count > 0 )); then
            _fleet_init_status=2
        fi

        if (( missing_count + init_failed_count + gh_failed_count > 0 )); then
            local p
            echo ""
            echo "Issues to resolve:"
            if (( missing_count > 0 )); then
                echo ""
                echo "  Missing paths (TSV references directories that don't exist):"
                for p in "${missing_paths[@]}"; do
                    echo "    - $p"
                done
                echo "    Fix: edit manifest.fleet.tsv to correct these paths or remove their"
                echo "         rows, then re-run: manifest init fleet --force"
            fi
            if (( init_failed_count > 0 )); then
                echo ""
                echo "  git init failed:"
                for p in "${init_failed_paths[@]}"; do
                    echo "    - $p"
                done
                echo "    Fix: check directory permissions / disk space, then re-run."
            fi
            if (( gh_failed_count > 0 )); then
                echo ""
                echo "  GitHub repo creation failed:"
                for p in "${gh_failed_paths[@]}"; do
                    echo "    - $p"
                done
                echo "    Fix: verify 'gh auth status' and that the repo name is available;"
                echo "         re-run after resolving, or create manually with:"
                echo "           gh repo create <name> --$create_repo_visibility --source=<path> --remote=origin"
            fi
        fi

        # Refresh TSV with updated metadata (directories now have git)
        echo ""
        echo "Refreshing manifest.fleet.tsv..."
        local all_dirs
        all_dirs=$(discover_all_directories "$target_dir" 5)
        if [[ -n "$all_dirs" ]]; then
            merge_start_tsv "$all_dirs" "$start_file" "$target_dir" 5 > "${start_file}.tmp" 2>/dev/null
            mv "${start_file}.tmp" "$start_file"
            echo "✓ Updated: $start_file"
        fi

        local service_count=0
        while IFS=$'\t' read -r _n _p _t _h _u _b _v; do
            [[ -z "$_n" ]] && continue
            ((service_count++))
        done <<< "$selected"
        echo ""
        echo "✓ Fleet inventory: $service_count service(s) in manifest.fleet.tsv"
    else
        # --- Auto-discovery path (quickstart): scan, populate TSV, bootstrap ---
        echo ""
        echo "Auto-discovering repositories..."
        local all_dirs
        all_dirs=$(discover_all_directories "$target_dir" 5)
        local inventory
        inventory=$(filter_start_inventory_git_repos "$all_dirs")

        if [[ -n "$inventory" ]]; then
            # Generate TSV with only existing git repos auto-selected.
            generate_start_tsv "$inventory" "$target_dir" 5 > "$start_file"
            echo "✓ Created: $start_file"

            local service_count=0
            while IFS=$'\t' read -r name path type branch version url submodule has_git has_remote; do
                [[ -z "$name" ]] && continue
                [[ "$has_git" == "true" ]] && ((service_count++))
            done <<< "$inventory"
            echo "✓ Fleet inventory: $service_count service(s) in manifest.fleet.tsv"
        fi
    fi

    # Validate the final configuration
    echo ""
    echo "Validating configuration..."
    if load_fleet_config "$target_dir"; then
        if validate_fleet_config; then
            echo ""
            echo "╔══════════════════════════════════════════════════════════════════════╗"
            echo "║                     FLEET INITIALIZED SUCCESSFULLY                   ║"
            echo "╚══════════════════════════════════════════════════════════════════════╝"
            echo ""
            echo "Next steps:"
            echo "  1. Review manifest.fleet.config.yaml and adjust service configuration"
            echo "  2. Run 'manifest status' to see fleet overview"
            echo "  3. Run 'manifest prep fleet' to clone/pull all services"
            echo "  4. Run 'manifest ship fleet patch' for first coordinated release"
            echo ""
        fi
    fi

    return $_fleet_init_status
}

# -----------------------------------------------------------------------------
# Function: _generate_minimal_manifest (internal)
# -----------------------------------------------------------------------------
_generate_minimal_manifest() {
    local config_file="$1"
    local fleet_name="$2"

    cat > "$config_file" << EOF
fleet:
  name: "$fleet_name"
  versioning: "date"
EOF
}

# -----------------------------------------------------------------------------
# Function: _generate_full_manifest (internal)
# -----------------------------------------------------------------------------
_generate_full_manifest() {
    local config_file="$1"
    local fleet_name="$2"

    cat > "$config_file" << EOF
# =============================================================================
# MANIFEST FLEET CONFIGURATION
# =============================================================================
# Generated by: manifest init fleet
# Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
#
# This file defines a collection of related repositories ("fleet") that
# Manifest CLI manages together for coordinated versioning and releases.
# =============================================================================

fleet:
  name: "$fleet_name"
  description: "Fleet managed by Manifest CLI"
  versioning: "date"
  version_file: "FLEET_VERSION"

EOF

    # Add operations section
    cat >> "$config_file" << 'EOF'

# =============================================================================
# OPERATIONS
# =============================================================================
operations:
  default_bump: "patch"
  parallel: true
  max_parallel: 4

  commit:
    strategy: "per-service"

  push:
    strategy: "batched"

# =============================================================================
# CHANGELOG
# =============================================================================
changelog:
  unified:
    enabled: true
    file: "CHANGELOG_FLEET.md"
    include:
      summary_table: true
      breaking_changes: true
      per_service_sections: true
      compatibility_matrix: true

  per_service:
    enabled: true

# =============================================================================
# VALIDATION
# =============================================================================
validation:
  require_clean_status: true
  enforce_dependencies: true
EOF
}

# =============================================================================
# COMMAND: discover fleet (alias for update fleet --dry-run)
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_discover
# -----------------------------------------------------------------------------
# Alias for 'update fleet --dry-run'.
# All discovery logic now lives in fleet_update.
# -----------------------------------------------------------------------------
fleet_discover() {
    if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest discover fleet [--depth N] [--json] [--quiet]" \
            "Discover repositories for fleet membership without writing changes."
        return 0
    fi
    fleet_update --dry-run "$@"
}

# =============================================================================
# INTERNAL: fleet sync (called by 'manifest prep fleet')
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _fleet_validate_clone_path (internal)
# -----------------------------------------------------------------------------
# Validates that a fleet service path is safely under MANIFEST_CLI_FLEET_ROOT.
# Pure string check — no filesystem writes, so a malformed config can't
# create stray directories outside the fleet root before being rejected.
#
# Rejects: absolute paths, empty paths, any '..' segment.
# (Symlink-based escapes are not covered by this check.)
#
# Returns: 0 if safe, 1 otherwise.
# -----------------------------------------------------------------------------
_fleet_validate_clone_path() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ "$path" = /* ]] && return 1
    case "/$path/" in
        */../*) return 1 ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# Function: _fleet_sync (internal)
# -----------------------------------------------------------------------------
# Synchronizes all fleet services (clone missing, pull existing).
# Called from manifest_prep_fleet in modules/core/manifest-prep.sh.
#
# ARGUMENTS:
#   --parallel, -p   Run in parallel (default based on config)
#   --clone-only     Only clone missing, don't pull existing
#   --pull-only      Only pull existing, don't clone missing
# -----------------------------------------------------------------------------
_fleet_sync() {
    if ! _fleet_require_initialized "sync"; then
        return 1
    fi

    local parallel=$(get_fleet_config_value "parallel" "$MANIFEST_CLI_FLEET_DEFAULT_PARALLEL")
    local clone_only=false
    local pull_only=false
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--parallel) parallel=true; shift ;;
            --clone-only) clone_only=true; shift ;;
            --pull-only) pull_only=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    if [[ "$dry_run" == "true" ]]; then
        echo "║                  MANIFEST FLEET SYNC (DRY RUN)                       ║"
    else
        echo "║                         MANIFEST FLEET SYNC                          ║"
    fi
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        _fleet_sync_dry_run "$clone_only" "$pull_only" "$parallel"
        return 0
    fi

    if [[ "$parallel" == "true" ]]; then
        _fleet_sync_parallel "$clone_only" "$pull_only"
    else
        _fleet_sync_sequential "$clone_only" "$pull_only"
    fi
}

# -----------------------------------------------------------------------------
# Function: _fleet_sync_dry_run (internal)
# -----------------------------------------------------------------------------
# Reports what _fleet_sync would do, without touching disk or network.
# Mirrors the decision logic in _fleet_sync_service so the preview matches
# the live run.
# -----------------------------------------------------------------------------
_fleet_sync_dry_run() {
    local clone_only="$1"
    local pull_only="$2"
    local parallel="${3:-false}"

    local total=0 would_clone=0 would_pull=0 would_skip=0 would_fail=0
    local service path url is_submodule

    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        ((total += 1))
        path=$(get_fleet_service_property "$service" "path")
        url=$(get_fleet_service_property "$service" "url")
        is_submodule=$(get_fleet_service_property "$service" "submodule" "false")

        if [[ ! -d "$path" ]]; then
            if [[ "$pull_only" == "true" ]]; then
                echo "  $service: would skip (pull-only, path missing)"
                ((would_skip += 1))
            elif [[ "$is_submodule" == "true" ]]; then
                echo "  $service: would fail (submodule path missing — needs parent 'submodule update --init')"
                ((would_fail += 1))
            elif [[ -z "$url" ]]; then
                echo "  $service: would fail (no URL)"
                ((would_fail += 1))
            elif ! _fleet_validate_clone_path "$path"; then
                echo "  $service: would fail (invalid path: $path)"
                ((would_fail += 1))
            else
                echo "  $service: would clone from $url -> $path"
                ((would_clone += 1))
            fi
        else
            if [[ "$clone_only" == "true" ]]; then
                echo "  $service: would skip (clone-only, path exists)"
                ((would_skip += 1))
            elif [[ ! -d "$path/.git" ]] && [[ "$is_submodule" != "true" ]]; then
                echo "  $service: would skip (not a git repo)"
                ((would_skip += 1))
            else
                echo "  $service: would pull --rebase ($path)"
                ((would_pull += 1))
            fi
        fi
    done

    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    echo "Plan: $would_clone clone, $would_pull pull, $would_skip skip, $would_fail fail (of $total total)"
    echo ""
    local replay_command="manifest prep fleet"
    [[ "$parallel" == "true" ]] && replay_command="$replay_command --parallel"
    [[ "$clone_only" == "true" ]] && replay_command="$replay_command --clone-only"
    [[ "$pull_only" == "true" ]] && replay_command="$replay_command --pull-only"
    manifest_execution_footer "$replay_command -y"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: _fleet_sync_service (internal)
# -----------------------------------------------------------------------------
# Syncs a single fleet service (clone or pull). Writes result to a status file.
#
# ARGUMENTS:
#   $1 - service name
#   $2 - clone_only flag
#   $3 - pull_only flag
#   $4 - result directory (for parallel mode status tracking)
# -----------------------------------------------------------------------------
_fleet_sync_service() {
    local service="$1"
    local clone_only="$2"
    local pull_only="$3"
    local result_dir="$4"

    local path url branch is_submodule
    path=$(get_fleet_service_property "$service" "path")
    url=$(get_fleet_service_property "$service" "url")
    branch=$(get_fleet_service_property "$service" "branch" "main")
    is_submodule=$(get_fleet_service_property "$service" "submodule" "false")

    if [[ ! -d "$path" ]]; then
        # Need to clone
        if [[ "$pull_only" == "true" ]]; then
            echo "  $service: ⏭ Skipping (pull-only mode)"
            [[ -n "$result_dir" ]] && echo "skip" > "$result_dir/$service"
            return 0
        fi

        # Submodules must be hydrated from the parent repo (.gitmodules), not
        # cloned standalone — otherwise the parent's gitlink stays broken.
        if [[ "$is_submodule" == "true" ]]; then
            echo "  $service: ✗ Submodule path missing — run 'git submodule update --init' from the parent repo"
            [[ -n "$result_dir" ]] && echo "fail" > "$result_dir/$service"
            return 1
        fi

        if [[ -z "$url" ]]; then
            echo "  $service: ✗ Cannot clone: no URL specified"
            [[ -n "$result_dir" ]] && echo "fail" > "$result_dir/$service"
            return 1
        fi

        # Validate path is safely under fleet root (pure check, no side effects)
        if ! _fleet_validate_clone_path "$path"; then
            echo "  $service: ✗ Invalid path (outside fleet root or contains '..'): $path"
            [[ -n "$result_dir" ]] && echo "fail" > "$result_dir/$service"
            return 1
        fi

        # Safe to create parent directory now that path is validated.
        mkdir -p "$MANIFEST_CLI_FLEET_ROOT/$(dirname "$path")"

        echo "  $service: → Cloning from $url..."
        # Clone without --branch and checkout afterward — tolerates remotes
        # whose default branch differs from the configured branch.
        local clone_out
        if ! clone_out=$(git clone "$url" "$path" 2>&1); then
            local last_lines
            last_lines=$(printf '%s' "$clone_out" | tail -3 | tr '\n' ' ')
            echo "  $service: ✗ Clone failed: $last_lines"
            [[ -n "$result_dir" ]] && echo "fail" > "$result_dir/$service"
            return 1
        fi

        if [[ -n "$branch" ]]; then
            local current_branch
            current_branch=$(git -C "$path" symbolic-ref --short -q HEAD 2>/dev/null || echo "")
            if [[ -n "$current_branch" && "$current_branch" != "$branch" ]]; then
                if ! git -C "$path" checkout "$branch" >/dev/null 2>&1; then
                    echo "  $service: ⚠ Cloned, but couldn't checkout '$branch' (default: $current_branch)"
                fi
            fi
        fi

        echo "  $service: ✓ Cloned successfully"
        [[ -n "$result_dir" ]] && echo "clone" > "$result_dir/$service"
        return 0
    else
        # Already exists - pull
        if [[ "$clone_only" == "true" ]]; then
            echo "  $service: ⏭ Skipping (clone-only mode)"
            [[ -n "$result_dir" ]] && echo "skip" > "$result_dir/$service"
            return 0
        fi

        if [[ ! -d "$path/.git" ]] && [[ "$is_submodule" != "true" ]]; then
            echo "  $service: ⚠ Not a git repository"
            [[ -n "$result_dir" ]] && echo "skip" > "$result_dir/$service"
            return 0
        fi

        local pull_output
        if pull_output=$(git -C "$path" pull --rebase 2>&1); then
            echo "  $service: ✓ Updated"
            [[ -n "$result_dir" ]] && echo "pull" > "$result_dir/$service"
            return 0
        else
            echo "  $service: ⚠ Pull failed: $(echo "$pull_output" | tail -1)"
            [[ -n "$result_dir" ]] && echo "fail" > "$result_dir/$service"
            return 1
        fi
    fi
}

# -----------------------------------------------------------------------------
# Function: _fleet_sync_print_summary (internal)
# -----------------------------------------------------------------------------
# Tallies per-service status files written by _fleet_sync_service and prints
# the summary line. Shared between sequential and parallel paths so a single
# helper change updates both.
# -----------------------------------------------------------------------------
_fleet_sync_print_summary() {
    local result_dir="$1"
    local total="$2"

    local cloned=0 pulled=0 failed=0
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        local result_file="$result_dir/$service"
        [[ -f "$result_file" ]] || continue
        local result
        result=$(<"$result_file")
        case "$result" in
            clone) ((cloned++)) ;;
            pull)  ((pulled++)) ;;
            fail)  ((failed++)) ;;
        esac
    done

    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    echo "Summary: $cloned cloned, $pulled pulled, $failed failed (of $total total)"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: _fleet_sync_sequential (internal)
# -----------------------------------------------------------------------------
_fleet_sync_sequential() {
    local clone_only="$1"
    local pull_only="$2"

    local result_dir
    result_dir=$(mktemp -d "$(manifest_make_scratch_path fleet)/sync.XXXXXXXX")

    local total=0
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        ((total++))
        echo "[$total] $service"
        _fleet_sync_service "$service" "$clone_only" "$pull_only" "$result_dir" || true
    done

    _fleet_sync_print_summary "$result_dir" "$total"
    rm -rf "$result_dir"
}

# -----------------------------------------------------------------------------
# Function: _fleet_sync_parallel (internal)
# -----------------------------------------------------------------------------
_fleet_sync_parallel() {
    local clone_only="$1"
    local pull_only="$2"

    echo "Running in parallel mode..."
    echo ""

    local result_dir
    result_dir=$(mktemp -d "$(manifest_make_scratch_path fleet)/sync.XXXXXXXX")

    local pids=()
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        _fleet_sync_service "$service" "$clone_only" "$pull_only" "$result_dir" &
        pids+=($!)
    done

    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    local total=0
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        ((total++))
    done

    _fleet_sync_print_summary "$result_dir" "$total"
    rm -rf "$result_dir"
}

# =============================================================================
# COMMAND: update fleet
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_update
# -----------------------------------------------------------------------------
# Re-scans the workspace and adds newly discovered repos to manifest.fleet.config.yaml.
#
# Also serves as the single discovery entry point. Use --dry-run to preview
# changes without writing (this is what 'discover fleet' does).
#
# ARGUMENTS:
#   --depth N      Maximum search depth (default: 5)
#   --dry-run      Preview only — do not modify manifest.fleet.config.yaml
#   --json         Output JSON summary (implies --dry-run)
#   --quiet, -q    Only output new repo lines, for scripting (implies --dry-run)
#
# EXAMPLE:
#   manifest update fleet
#   manifest update fleet --depth 3
#   manifest update fleet --dry-run
# -----------------------------------------------------------------------------
fleet_update() {
    local depth=5
    local skip_init_check=false
    local dry_run=true
    local json_output=false
    local quiet=false
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()

    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    [[ "$execution_mode" == "apply" ]] && dry_run=false
    set -- "${remaining_args[@]}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--depth requires a numeric value"
                    return 1
                fi
                depth="$2"; shift 2 ;;
            --_from-init) skip_init_check=true; shift ;;
            --json) json_output=true; dry_run=true; shift ;;
            -q|--quiet) quiet=true; dry_run=true; shift ;;
            -h|--help|help)
                _render_help \
                    "manifest update fleet [-y|--yes] [--dry-run] [--depth N] [--json] [--quiet]" \
                    "Re-scan fleet membership and add newly discovered repositories." \
                    "Options" "  --dry-run    Explicit preview; do not modify manifest.fleet.config.yaml
  -y, --yes    Apply fleet membership updates
  --depth N    Maximum search depth (default: 5)
  --json       Output JSON summary
  --quiet, -q  Only output new repo lines"
                return 0
                ;;
            *) shift ;;
        esac
    done

    if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
        log_error "--depth must be a non-negative integer"
        return 1
    fi

    local root_dir="${MANIFEST_CLI_FLEET_ROOT:-$(pwd)}"

    # --- JSON summary mode (fast, limited depth) ---
    if [[ "$json_output" == "true" ]]; then
        local discovered
        discovered=$(discover_fleet_repos "$root_dir" 3)  # Limited depth for speed

        local total=0 services=0 libraries=0 infra=0 tools=0
        while IFS=$'\t' read -r name path type rest; do
            [[ -z "$name" ]] && continue
            ((total++))
            case "$type" in
                "service") ((services++)) ;;
                "library") ((libraries++)) ;;
                "infrastructure") ((infra++)) ;;
                "tool") ((tools++)) ;;
            esac
        done <<< "$discovered"

        cat << EOF
{
  "total": $total,
  "services": $services,
  "libraries": $libraries,
  "infrastructure": $infra,
  "tools": $tools,
  "root": "$root_dir"
}
EOF
        return 0
    fi

    # --- Quiet mode (new repos only, for scripting) ---
    if [[ "$quiet" == "true" ]]; then
        local discovered
        discovered=$(discover_fleet_repos "$root_dir" "$depth")

        local config_file
        config_file=$(_fleet_resolve_config "$root_dir")

        if [[ -f "$config_file" ]]; then
            local diff_output
            diff_output=$(diff_discovered_repos "$discovered" "$config_file")
            get_new_repos "$diff_output"
        else
            echo "$discovered"
        fi
        return 0
    fi

    # --- Standard / dry-run mode ---

    # When called standalone, require fleet to be initialized.
    # When called from _fleet_init (--_from-init), skip — config was just created.
    if [[ "$skip_init_check" != "true" ]]; then
        if ! _fleet_require_initialized "update"; then
            return 1
        fi
    fi

    # Resolve config file
    local config_file
    config_file=$(_fleet_resolve_config "$root_dir")

    local header_label="MANIFEST FLEET UPDATE"
    [[ "$dry_run" == "true" ]] && header_label="MANIFEST FLEET UPDATE (dry-run)"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    printf "║  %-68s  ║\n" "$header_label"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Scanning: $root_dir"
    echo ""

    local discovered
    discovered=$(discover_fleet_repos "$root_dir" "$depth")

    local diff_output
    diff_output=$(diff_discovered_repos "$discovered" "$config_file")

    # Count changes in a single pass
    local new_count=0 removed_count=0 changed_count=0 unchanged_count=0
    while IFS= read -r _line; do
        case "${_line:0:1}" in
            +) new_count=$((new_count + 1)) ;;
            -) removed_count=$((removed_count + 1)) ;;
            '~') changed_count=$((changed_count + 1)) ;;
            =) unchanged_count=$((unchanged_count + 1)) ;;
        esac
    done <<< "$diff_output"

    echo "Fleet scan results:"
    echo "  + New:       $new_count"
    echo "  - Missing:   $removed_count"
    echo "  ~ Changed:   $changed_count"
    echo "  = Unchanged: $unchanged_count"
    echo ""

    # Handle new repos
    if [[ "$new_count" -gt 0 ]]; then
        if [[ "$dry_run" == "true" ]]; then
            echo "New repositories (not in manifest):"
        else
            echo "Adding new repositories:"
        fi
        echo ""
        echo "$diff_output" | grep "^+" | while IFS=$'\t' read -r status name path type branch version url is_sub; do
            printf "  + %-25s %-12s %s\n" "$name" "($type)" "$path"
        done
        echo ""

        if [[ "$dry_run" == "true" ]]; then
            echo "To add these services, run:"
            echo "  manifest update fleet --depth $depth -y"
        else
            local new_repos
            new_repos=$(get_new_repos "$diff_output")

            local yaml_content
            yaml_content=$(generate_manifest_additions "$new_repos")

            if append_services_to_manifest "$config_file" "$yaml_content"; then
                echo "✓ Added $new_count service(s) to $config_file"
            else
                log_error "Failed to update $config_file"
                return 1
            fi

            # Ensure .gitignore in newly discovered repos
            _fleet_ensure_gitignores "$root_dir" "$new_repos"
        fi
    else
        echo "✓ No new repositories found."
    fi

    # Report missing repos (informational — don't auto-remove)
    if [[ "$removed_count" -gt 0 ]]; then
        echo ""
        log_warning "Missing repositories (in manifest but not on disk):"
        echo "$diff_output" | grep "^-" | while IFS=$'\t' read -r status name path type rest; do
            printf "  - %-25s %s\n" "$name" "$path"
        done
        echo ""
        echo "  Run 'manifest prep fleet' to clone missing repos,"
        echo "  or remove them from manifest.fleet.config.yaml manually."
    fi

    # Refresh manifest.fleet.tsv with current scan (preserves user selections)
    local start_file="$root_dir/manifest.fleet.tsv"
    local all_dirs
    all_dirs=$(discover_all_directories "$root_dir" "$depth")
    local refresh_inventory
    refresh_inventory=$(filter_start_inventory_git_repos "$all_dirs")

    if [[ -n "$refresh_inventory" && "$dry_run" == "true" ]]; then
        echo ""
        echo "Would refresh manifest.fleet.tsv from current scan"
    elif [[ -n "$refresh_inventory" ]]; then
        # merge_start_tsv writes TSV to stdout and "NEW:<count>" to stderr
        local merge_stderr
        merge_stderr=$(merge_start_tsv "$refresh_inventory" "$start_file" "$root_dir" "$depth" 2>&1 > "${start_file}.tmp")
        mv "${start_file}.tmp" "$start_file"

        local tsv_new_count=0
        if [[ "$merge_stderr" =~ NEW:([0-9]+) ]]; then
            tsv_new_count="${BASH_REMATCH[1]}"
        fi

        if [[ "$tsv_new_count" -gt 0 ]]; then
            echo ""
            echo "✓ Updated manifest.fleet.tsv ($tsv_new_count new directories added)"
        else
            echo ""
            echo "✓ Updated manifest.fleet.tsv"
        fi
    fi

    echo ""
}

# =============================================================================
# COMMAND: prep fleet
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_prep
# -----------------------------------------------------------------------------
# Runs manifest prep across all fleet services. This is the coordinated version
# bump step that can be invoked standalone or as part of fleet ship.
#
# ARGUMENTS:
#   $1 - Increment type: patch|minor|major|revision (default: patch)
#
# EXAMPLE:
#   manifest prep fleet
#   manifest prep fleet minor
# -----------------------------------------------------------------------------
# Internal prep runner (no banner — called by fleet_ship and fleet_prep)
_fleet_prep_run() {
    local increment_type="${1:-patch}"

    local any_failures=0
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        local path
        path=$(get_fleet_service_property "$service" "path")
        if [ ! -d "$path/.git" ]; then
            echo "  - $service: skipped (not a git repo)"
            continue
        fi
        (
            cd "$path" || exit 1
            manifest_prep "$increment_type" "false"
        ) || {
            echo "  - $service: ❌ prep failed"
            any_failures=1
        }
    done

    if [ "$any_failures" -eq 1 ]; then
        log_error "Fleet prep failed for one or more services."
        return 1
    fi
}

fleet_prep() {
    if ! _fleet_require_initialized "prep"; then
        return 1
    fi

    local increment_type="${1:-patch}"

    if [[ ! "$increment_type" =~ ^(patch|minor|major|revision)$ ]]; then
        log_error "Invalid increment type: '$increment_type' (expected patch|minor|major|revision)"
        return 1
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                         MANIFEST FLEET PREP                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Running prep ($increment_type) across fleet services..."

    if ! _fleet_prep_run "$increment_type"; then
        return 1
    fi

    echo ""
    echo "✓ Fleet prep complete ($increment_type)"
    echo ""
}

# =============================================================================
# COMMAND: fleet ship
# =============================================================================

_fleet_service_count() {
    local count=0
    local service
    for service in $1; do
        count=$((count + 1))
    done
    echo "$count"
}

_fleet_scope_block() {
    local count
    count="$(_fleet_service_count "$MANIFEST_CLI_FLEET_SERVICES")"

    echo ""
    echo "Fleet scope"
    echo "-----------"
    printf "  %-10s %s\n" "Fleet:" "${MANIFEST_CLI_FLEET_NAME:-unnamed-fleet}"
    printf "  %-10s %s\n" "Root:" "${MANIFEST_CLI_FLEET_ROOT:-$(pwd)}"
    printf "  %-10s %s\n" "Config:" "${MANIFEST_CLI_FLEET_CONFIG_FILE:-manifest.fleet.config.yaml}"
    printf "  %-10s %s\n" "Scope:" "fleet"
    printf "  %-10s %s\n" "Mutation:" "fleet repositories listed below"
    printf "  %-10s %s\n" "Services:" "$count"
}

_fleet_service_release_reason() {
    local service="$1"
    local path="$2"
    local excluded
    excluded=$(get_fleet_service_property "$service" "excluded" "false")

    if [[ "$excluded" == "true" ]]; then
        echo "excluded"
        return 1
    fi
    if [[ -z "$path" || ! -d "$path" ]]; then
        echo "missing path"
        return 1
    fi
    if [[ ! -d "$path/.git" ]]; then
        echo "not a git repo"
        return 1
    fi

    local release_enabled
    release_enabled=$(get_fleet_service_property "$service" "release_enabled" "")
    if [[ -n "$release_enabled" ]] && is_falsy "$release_enabled"; then
        echo "release disabled"
        return 1
    fi
    if [[ -n "$release_enabled" ]] && is_truthy "$release_enabled"; then
        echo "release enabled"
        return 0
    fi

    local release_strategy
    release_strategy=$(get_fleet_service_property "$service" "release_strategy" "")
    case "$release_strategy" in
        none)
            echo "release strategy none"
            return 1
            ;;
        direct)
            echo "release strategy direct"
            return 0
            ;;
        "")
            ;;
        *)
            echo "unsupported release strategy: $release_strategy"
            return 1
            ;;
    esac

    case "$service:$path" in
        *homebrew*tap*|*Homebrew*Tap*)
            echo "formula-only"
            return 1
            ;;
    esac

    local root_dir="${MANIFEST_CLI_FLEET_ROOT:-$(pwd)}"
    if [[ "$path" == "." || "$path" == "$root_dir" || "$(cd "$path" 2>/dev/null && pwd)" == "$root_dir" ]]; then
        echo "fleet root infrastructure"
        return 1
    fi

    if [[ -f "$path/VERSION" ]]; then
        echo "has VERSION"
        return 0
    fi

    echo "no VERSION"
    return 1
}

# Probes whether the caller can write under <path>/.git. Sandboxed
# environments (Claude Code, restricted CI runners) frequently allow reads
# but deny mutations under .git/, which surfaces as a partial-ship failure
# mid-iteration. Pre-flighting the probe per member lets fleet apply refuse
# before any state is written.
_fleet_preflight_git_writable() {
    local path="$1"
    [[ -d "$path/.git" ]] || return 1
    local probe="$path/.git/.manifest-preflight-$$"
    if : > "$probe" 2>/dev/null; then
        rm -f "$probe" 2>/dev/null
        return 0
    fi
    return 1
}

# Iterates fleet members and refuses fleet apply if any releaseable member's
# .git is not writable. Skipped members (excluded, missing path, not a git
# repo, release disabled, etc.) are not probed — fleet apply never writes
# into them.
_fleet_preflight_git_writability() {
    local failed=()
    local service path reason
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path=$(get_fleet_service_property "$service" "path")
        if ! reason=$(_fleet_service_release_reason "$service" "$path"); then
            continue
        fi
        if ! _fleet_preflight_git_writable "$path"; then
            failed+=("$service ($path)")
        fi
    done

    if [[ ${#failed[@]} -eq 0 ]]; then
        return 0
    fi

    log_error "Pre-flight: .git write denied for ${#failed[@]} fleet member(s):"
    local entry
    for entry in "${failed[@]}"; do
        echo "  - $entry"
    done
    echo ""
    echo "Likely cause: sandboxed environment denying writes under .git/."
    echo "Remediation:  rerun outside the sandbox or under elevated permissions."
    echo "Pre-flight refused before any mutation; no fleet member was modified."
    return 1
}

# Refuses fleet apply if any releaseable member has HEAD on a branch other than
# the one its release would push. Same correctness guard as the single-repo
# path (manifest_assert_release_branch) — releasing off the default branch tags
# the wrong commit and pushes a stale default branch. Reports every offender at
# once so the user can fix the whole fleet before retrying. Skipped members are
# not checked — fleet apply never ships them.
_fleet_preflight_on_default_branch() {
    local failed=0
    local service path reason
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path=$(get_fleet_service_property "$service" "path")
        if ! reason=$(_fleet_service_release_reason "$service" "$path"); then
            continue
        fi
        if ! manifest_assert_release_branch "$path" "  "; then
            failed=1
        fi
    done

    [[ $failed -eq 0 ]] && return 0

    echo ""
    echo "Pre-flight refused before any mutation; no fleet member was shipped."
    return 1
}

# Returns the user-facing service name for plan output. YAML keys are
# intentionally dot-free for variable-name compatibility (see
# manifest-fleet-config.sh `tr '[:lower:]-.' '[:upper:]__'`), so the
# basename of `path` is the source of truth for the dotted display
# form. Falls back to the slug for workspace-root entries where the
# basename would be uninformative.
_fleet_plan_service_display_name() {
    local service="$1"
    local path="$2"
    local root_dir="${MANIFEST_CLI_FLEET_ROOT:-$(pwd)}"
    local resolved="${path%/}"
    resolved="${resolved%/.}"

    if [[ -z "$resolved" || "$resolved" == "." || "$resolved" == "$root_dir" ]]; then
        echo "$service"
        return
    fi

    local candidate
    candidate=$(basename "$resolved")
    if [[ -z "$candidate" || "$candidate" == "." ]]; then
        echo "$service"
        return
    fi
    echo "$candidate"
}

_fleet_ship_plan() {
    local increment_type="$1"
    local local_only="$2"
    local releaseable_count=0
    local skipped_count=0

    echo ""
    echo "Fleet ship plan ($increment_type)"
    echo ""
    echo "Included repositories"
    printf '%-36s %-14s %-12s %-7s %-10s %-16s %s\n' "Service" "Type" "Branch" "Dirty" "Effect" "Decision" "Path / reason"
    printf '%-36s %-14s %-12s %-7s %-10s %-16s %s\n' "-------" "----" "------" "-----" "------" "--------" "-------------"

    local service path reason effect decision type branch display_name dirty
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path=$(get_fleet_service_property "$service" "path")
        type=$(get_fleet_service_property "$service" "type" "service")
        branch=$(get_fleet_service_property "$service" "branch" "${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}")
        display_name=$(_fleet_plan_service_display_name "$service" "$path")
        dirty=$(manifest_git_changes_dirty_summary "$path")
        if reason=$(_fleet_service_release_reason "$service" "$path"); then
            releaseable_count=$((releaseable_count + 1))
            effect="release"
            if [[ "$local_only" == "true" ]]; then
                decision="would local"
            else
                decision="would ship"
            fi
            printf '%-36s %-14s %-12s %-7s %-10s %-16s %s\n' "$display_name" "$type" "$branch" "$dirty" "$effect" "$decision" "$path"
        else
            skipped_count=$((skipped_count + 1))
            printf '%-36s %-14s %-12s %-7s %-10s %-16s %s\n' "$display_name" "$type" "$branch" "$dirty" "read" "skip" "$path ($reason)"
        fi
    done

    echo ""
    echo "Plan summary: $releaseable_count releaseable, $skipped_count skipped"
    return 0
}

# Reads a key=value status file written by the orchestrator and prints a
# structured fleet-level recovery report. Classifies the failed member into
# one of:
#   pushed-then-stranded - release is on origin; formula/release-notes stranded; DO NOT rollback
#   local-only           - failure before push; no public state on origin
#   unknown              - status file missing or unparsable (rare; child crashed before emit)
# Reads `completed`, `not_started`, `skipped` arrays from caller scope.
_fleet_emit_recovery_report() {
    local failed_service="$1"
    local failed_path="$2"
    local status_file="$3"
    local increment_type="$4"
    local local_only="$5"

    local result="unknown" failure_step="unknown" push_status="unknown"
    local homebrew_status="unknown" version="" tag=""
    if [[ -f "$status_file" ]]; then
        local k v
        while IFS='=' read -r k v; do
            case "$k" in
                result)          result="$v" ;;
                failure_step)    failure_step="$v" ;;
                push_status)     push_status="$v" ;;
                homebrew_status) homebrew_status="$v" ;;
                version)         version="$v" ;;
                tag)             tag="$v" ;;
            esac
        done < "$status_file"
    fi

    local category recovery_line resume_cmd retry_cmd
    if [[ "$push_status" == "success" && "$failure_step" =~ ^(homebrew_|github_release) ]]; then
        category="pushed-then-stranded"
        recovery_line="Release v${version:-?} is live (tag ${tag:-?} on origin). Formula/release stranded. DO NOT rollback."
        resume_cmd="cd $failed_path && manifest ship repo resume"
        retry_cmd=""
    elif [[ "$push_status" == "failed" || "$result" == "failed" ]]; then
        category="local-only"
        recovery_line="Failure before public push; no remote state for this member. Safe to retry or rollback locally."
        resume_cmd="cd $failed_path && manifest ship repo resume"
        retry_cmd="cd $failed_path && manifest ship repo $increment_type -y"
    else
        category="unknown"
        recovery_line="Per-member status file missing; see the failure report above for recovery commands."
        resume_cmd=""
        retry_cmd=""
    fi

    echo ""
    echo "Fleet ship: partial completion"
    echo "==============================="
    echo "  Fleet:     ${MANIFEST_CLI_FLEET_NAME:-unknown}"
    echo "  Increment: $increment_type"
    [[ "$local_only" == "true" ]] && echo "  Mode:      --local"
    echo ""

    echo "  Completed (${#completed[@]}):"
    if [[ ${#completed[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        local entry svc sfile sver rest
        for entry in "${completed[@]}"; do
            svc="${entry%%|*}"
            rest="${entry#*|}"
            sfile="${rest#*|}"
            sver=""
            if [[ -f "$sfile" ]]; then
                sver=$(grep '^version=' "$sfile" 2>/dev/null | cut -d= -f2-)
            fi
            echo "    ✅ $svc → v${sver:-?}"
        done
    fi
    echo ""

    echo "  Failed (1):"
    echo "    ❌ $failed_service ($failed_path)"
    echo "       step:     $failure_step"
    echo "       category: $category"
    echo "       $recovery_line"
    if [[ -n "$resume_cmd" ]]; then
        echo "       Resume:   $resume_cmd"
    fi
    if [[ -n "$retry_cmd" ]]; then
        echo "       Or retry: $retry_cmd"
    fi
    echo ""

    echo "  Not started (${#not_started[@]}):"
    if [[ ${#not_started[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        local entry ns_svc ns_path
        for entry in "${not_started[@]}"; do
            ns_svc="${entry%%|*}"
            ns_path="${entry#*|}"
            echo "    ⏸  $ns_svc ($ns_path)"
        done
    fi
    echo ""

    echo "  Skipped (${#skipped[@]}):"
    if [[ ${#skipped[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        local entry sk_svc sk_path sk_reason rest
        for entry in "${skipped[@]}"; do
            sk_svc="${entry%%|*}"
            rest="${entry#*|}"
            sk_path="${rest%%|*}"
            sk_reason="${rest#*|}"
            echo "    ⏭  $sk_svc ($sk_reason)"
        done
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Function: fleet_ship
# -----------------------------------------------------------------------------
# Highest-level coordinated fleet workflow:
#   preview by default -> direct ship of releaseable services with -y.
# PR orchestration belongs under `manifest pr fleet ...`, never here.
# -----------------------------------------------------------------------------
fleet_ship() {
    local execution_mode="preview"
    local local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    local increment_type="patch"
    local run_prep=true
    local any_failures=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major|revision)
                increment_type="$1"
                shift
                ;;
            --noprep)
                run_prep=false
                shift
                ;;
            --safe|--force|--no-delete-branch|--draft)
                log_error "$1 belongs under 'manifest pr fleet ...', not 'manifest ship fleet'."
                return 1
                ;;
            --method)
                log_error "--method belongs under 'manifest pr fleet queue', not 'manifest ship fleet'."
                return 1
                ;;
            -h|--help)
                cat << 'EOF'
Usage: manifest ship fleet [patch|minor|major|revision] [-y|--yes] [--dry-run] [--local] [options]

Options:
  --dry-run                 Explicit preview; no writes, commits, tags, pushes, or PRs
  -y, --yes                 Apply the fleet release plan
  --local                   With -y, apply local release prep only
  --noprep                  Skip per-service prep step during apply

Flow:
  default: preview release plan
  -y:      direct ship of releaseable services
  PR work: manifest pr fleet ...

Fleet membership and release-eligibility are determined by manifest.fleet.config.yaml.
EOF
                return 0
                ;;
            *)
                log_error "Unknown option for 'manifest ship fleet': $1"
                return 1
                ;;
        esac
    done

    if ! _fleet_require_initialized "ship"; then
        return 1
    fi

    if [[ "$execution_mode" == "preview" ]]; then
        _fleet_scope_block
        _fleet_ship_plan "$increment_type" "$local_only"
        local replay_command="manifest ship fleet $increment_type"
        [[ "$local_only" == "true" ]] && replay_command="$replay_command --local"
        manifest_execution_footer "$replay_command -y"
        return 0
    fi

    echo "Starting fleet ship workflow ($increment_type)"
    _fleet_scope_block
    _fleet_ship_plan "$increment_type" "$local_only"
    echo ""

    if ! _fleet_preflight_git_writability; then
        return 1
    fi

    if ! _fleet_preflight_on_default_branch; then
        return 1
    fi

    if [ "$run_prep" != "true" ]; then
        echo "⏭️  Skipping fleet prep (--noprep)."
        for service in $MANIFEST_CLI_FLEET_SERVICES; do
            local path
            path=$(get_fleet_service_property "$service" "path")
            if [ ! -d "$path/.git" ]; then
                continue
            fi
            if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
                echo "  - $service: ❌ has uncommitted changes; cannot use --noprep"
                any_failures=1
            fi
        done
        if [ "$any_failures" -eq 1 ]; then
            log_error "Cannot continue fleet ship --noprep with dirty repositories."
            return 1
        fi
    fi

    echo "Step 1/1: Shipping releaseable services directly..."

    local -a member_list=()
    # shellcheck disable=SC2206
    member_list=( $MANIFEST_CLI_FLEET_SERVICES )

    local status_dir
    status_dir=$(mktemp -d "${TMPDIR:-/tmp}/manifest-fleet-status.XXXXXX") || {
        log_error "Could not create fleet status scratch directory."
        return 1
    }

    local -a completed=() not_started=() skipped=()
    local failed_service="" failed_path="" failed_status_file=""
    local service path reason status_file idx=0 rc rem rem_path rem_reason rem_idx

    for service in "${member_list[@]}"; do
        idx=$((idx + 1))
        path=$(get_fleet_service_property "$service" "path")
        if ! reason=$(_fleet_service_release_reason "$service" "$path"); then
            echo "  - $service: skipped ($reason)"
            skipped+=("$service|$path|$reason")
            continue
        fi
        echo "  - $service: shipping $increment_type"
        status_file="$status_dir/${service}.status"

        # Fleet's -y is the apply consent; suppress the per-member confirmation
        # prompt that manifest_ship_repo would otherwise trigger. The status
        # file lets the fleet aggregator classify per-member outcomes without
        # parsing the child's stdout.
        (
            cd "$path" || exit 1
            PROJECT_ROOT="$PWD"
            export PROJECT_ROOT
            MANIFEST_CLI_AUTO_CONFIRM=1
            export MANIFEST_CLI_AUTO_CONFIRM
            MANIFEST_CLI_SHIP_STATUS_FILE="$status_file"
            export MANIFEST_CLI_SHIP_STATUS_FILE
            if [[ "$local_only" == "true" ]]; then
                manifest_ship_repo "$increment_type" "--local" "-y"
            else
                manifest_ship_repo "$increment_type" "-y"
            fi
        )
        rc=$?
        if [[ $rc -ne 0 ]]; then
            failed_service="$service"
            failed_path="$path"
            failed_status_file="$status_file"
            for ((rem_idx=idx; rem_idx<${#member_list[@]}; rem_idx++)); do
                rem="${member_list[$rem_idx]}"
                rem_path=$(get_fleet_service_property "$rem" "path")
                if rem_reason=$(_fleet_service_release_reason "$rem" "$rem_path"); then
                    not_started+=("$rem|$rem_path")
                else
                    skipped+=("$rem|$rem_path|$rem_reason")
                fi
            done
            break
        fi
        completed+=("$service|$path|$status_file")
    done

    if [[ -n "$failed_service" ]]; then
        _fleet_emit_recovery_report \
            "$failed_service" "$failed_path" "$failed_status_file" \
            "$increment_type" "$local_only"
        rm -rf "$status_dir" 2>/dev/null
        log_error "Fleet ship aborted at $failed_service. See classification above before retrying."
        return 1
    fi

    rm -rf "$status_dir" 2>/dev/null
    echo "✅ Fleet ship workflow complete."
}

# =============================================================================
# COMMAND: ship fleet resume
# =============================================================================

# Probes each releaseable fleet member, classifies it as eligible / nothing /
# release-disabled, and (when applied) delegates to per-repo resume for each
# eligible member. Pure read in preview mode; sequential fail-fast on apply.
#
# Fills caller-scope arrays `eligible`, `nothing`, `disabled` via dynamic
# scope. Each entry is pipe-delimited:
#   eligible: svc|path|version|tag
#   nothing:  svc|path|code|detail
#   disabled: svc|path|reason
_fleet_resume_classify() {
    eligible=()
    nothing=()
    disabled=()

    local service path reason probe code version tag_name detail
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path=$(get_fleet_service_property "$service" "path")
        if ! reason=$(_fleet_service_release_reason "$service" "$path"); then
            # Includes "not a git repo", "missing path", "release disabled",
            # "excluded", etc. — anything fleet ship would also skip.
            disabled+=("$service|$path|$reason")
            continue
        fi
        # `|| true` neutralizes set -eo pipefail propagation from the subshell
        # when the probe returns 1 (non-eligible); the probe's stdout is the
        # source of truth — rc just mirrors eligible-vs-not.
        probe=$(
            cd "$path" 2>/dev/null || exit 1
            PROJECT_ROOT="$PWD"
            export PROJECT_ROOT
            manifest_ship_repo_resume_eligible
        ) || true
        IFS='|' read -r code version tag_name detail <<<"$probe"
        case "$code" in
            eligible)
                eligible+=("$service|$path|$version|$tag_name")
                ;;
            *)
                nothing+=("$service|$path|${code:-unknown}|${detail:-no detail}")
                ;;
        esac
    done
}

# Prints the per-category recap used by both preview and apply summary.
# Reads caller-scope arrays `eligible`, `nothing`, `disabled`.
_fleet_resume_print_classification() {
    local header_label="${1:-Fleet resume preview}"
    echo ""
    echo "$header_label"
    echo "  Fleet:     ${MANIFEST_CLI_FLEET_NAME:-unknown}"
    echo ""

    echo "  Eligible (${#eligible[@]}):"
    if [[ ${#eligible[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        local entry svc spath sver stag
        for entry in "${eligible[@]}"; do
            IFS='|' read -r svc spath sver stag <<<"$entry"
            echo "    🔧 $svc → resume v${sver} (tag ${stag})"
        done
    fi
    echo ""

    echo "  Nothing to resume (${#nothing[@]}):"
    if [[ ${#nothing[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        local entry nsvc npath ncode ndetail
        for entry in "${nothing[@]}"; do
            IFS='|' read -r nsvc npath ncode ndetail <<<"$entry"
            echo "    ✓  $nsvc ($ncode)"
        done
    fi
    echo ""

    echo "  Release disabled (${#disabled[@]}):"
    if [[ ${#disabled[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        local entry dsvc dpath dreason
        for entry in "${disabled[@]}"; do
            IFS='|' read -r dsvc dpath dreason <<<"$entry"
            echo "    ⏭  $dsvc ($dreason)"
        done
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Function: fleet_resume
# -----------------------------------------------------------------------------
# Fleet-level counterpart to `manifest ship repo resume`. Walks each
# releaseable member, applies the per-repo resume eligibility probe, and
# delegates to per-repo resume for any member found in the stranded state.
# Preview by default; -y to apply. Refuses --local (resume's job is to push
# stranded artifacts).
# -----------------------------------------------------------------------------
fleet_resume() {
    local execution_mode="preview"
    local local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    if [[ "$local_only" == "true" ]]; then
        log_error "fleet resume does not support --local."
        return 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat << 'EOF'
Usage: manifest ship fleet resume [-y|--yes] [--dry-run]

Walks each releaseable fleet member, probes per-repo resume eligibility
(VERSION present, local tag matches, ancestor of HEAD, clean tree modulo
formula/manifest.rb), and (with -y) delegates to `manifest ship repo resume`
for each eligible member.

Options:
  --dry-run    Explicit preview; classify members but do not resume
  -y, --yes    Apply: resume each eligible member in sequence

Resume is sequential and fail-fast. A failure aborts remaining members so
the user can inspect state before re-running.
EOF
                return 0
                ;;
            *)
                log_error "Unknown option for 'manifest ship fleet resume': $1"
                return 1
                ;;
        esac
    done

    if ! _fleet_require_initialized "ship resume"; then
        return 1
    fi

    local -a eligible=() nothing=() disabled=()
    _fleet_resume_classify

    _fleet_scope_block
    _fleet_resume_print_classification "Fleet resume plan"

    if [[ "$execution_mode" == "preview" ]]; then
        manifest_execution_footer "manifest ship fleet resume -y"
        return 0
    fi

    if [[ ${#eligible[@]} -eq 0 ]]; then
        echo "Nothing to resume across fleet."
        return 0
    fi

    if ! _fleet_preflight_git_writability; then
        return 1
    fi

    if ! _fleet_preflight_on_default_branch; then
        return 1
    fi

    echo "Resuming ${#eligible[@]} member(s)..."
    local entry svc spath sver stag rc
    local -a resumed=() failed=()
    for entry in "${eligible[@]}"; do
        IFS='|' read -r svc spath sver stag <<<"$entry"
        echo "  - $svc: resuming v${sver}"
        (
            cd "$spath" || exit 1
            PROJECT_ROOT="$PWD"
            export PROJECT_ROOT
            MANIFEST_CLI_AUTO_CONFIRM=1
            export MANIFEST_CLI_AUTO_CONFIRM
            manifest_ship_repo_resume
        )
        rc=$?
        if [[ $rc -ne 0 ]]; then
            failed+=("$svc|$spath|$sver")
            break
        fi
        resumed+=("$svc|$spath|$sver")
    done

    echo ""
    echo "Fleet resume summary"
    echo "  Resumed (${#resumed[@]}):"
    if [[ ${#resumed[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        for entry in "${resumed[@]}"; do
            IFS='|' read -r svc spath sver <<<"$entry"
            echo "    ✅ $svc → v${sver}"
        done
    fi
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "  Failed (${#failed[@]}):"
        for entry in "${failed[@]}"; do
            IFS='|' read -r svc spath sver <<<"$entry"
            echo "    ❌ $svc → v${sver}"
        done
        log_error "Fleet resume aborted at ${failed[0]%%|*}. See per-member output above."
        return 1
    fi
    echo "✅ Fleet resume complete."
    return 0
}

# =============================================================================
# COMMAND: validate fleet
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_validate
# -----------------------------------------------------------------------------
# Validates fleet configuration and reports issues.
#
# EXAMPLE:
#   manifest validate fleet
# -----------------------------------------------------------------------------
fleet_validate() {
    if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest validate fleet" \
            "Validate fleet configuration and service paths."
        return 0
    fi

    if ! _fleet_require_initialized "validate"; then
        return 1
    fi

    echo ""
    echo "Validating fleet: $MANIFEST_CLI_FLEET_NAME"
    echo ""

    validate_fleet_config
}

# =============================================================================
# COMMAND: add fleet
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_add
# -----------------------------------------------------------------------------
# Adds a service to the fleet.
#
# ARGUMENTS:
#   $1 - Path or URL to add
#   --name NAME      Service name (auto-detected if not provided)
#   --type TYPE      Service type (auto-detected if not provided)
#
# EXAMPLE:
#   manifest add fleet ./new-service
#   manifest add fleet git@github.com:org/repo.git --name my-service
# -----------------------------------------------------------------------------
fleet_add() {
    local path_or_url=""
    local service_name=""
    local service_type=""
    local dry_run=true
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()

    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    [[ "$execution_mode" == "apply" ]] && dry_run=false
    set -- "${remaining_args[@]}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--name requires a value"
                    return 1
                fi
                service_name="$2"; shift 2 ;;
            --type)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--type requires a value"
                    return 1
                fi
                service_type="$2"; shift 2 ;;
            -h|--help|help)
                _render_help \
                    "manifest add fleet <path-or-url> [-y|--yes] [--dry-run] [--name NAME] [--type TYPE]" \
                    "Add a local path or remote URL to fleet membership."
                return 0
                ;;
            *)
                if [[ -z "$path_or_url" ]]; then
                    path_or_url="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$path_or_url" ]]; then
        log_error "Usage: manifest add fleet <path-or-url> [--name NAME] [--type TYPE]"
        return 1
    fi

    local existing_config
    existing_config=$(_fleet_resolve_config "$(pwd)")
    if [[ "$MANIFEST_CLI_FLEET_ACTIVE" != "true" && -f "$existing_config" ]]; then
        load_fleet_config "$(pwd)" || return 1
    fi
    MANIFEST_CLI_FLEET_ROOT="${MANIFEST_CLI_FLEET_ROOT:-$(pwd)}"
    MANIFEST_CLI_FLEET_NAME="${MANIFEST_CLI_FLEET_NAME:-$(basename "$MANIFEST_CLI_FLEET_ROOT")}"

    # Determine if it's a path or URL
    local is_url=false
    if [[ "$path_or_url" == git@* ]] || [[ "$path_or_url" == https://* ]] || [[ "$path_or_url" == http://* ]]; then
        is_url=true
    fi

    echo ""
    echo "Adding service to fleet: $MANIFEST_CLI_FLEET_NAME"
    echo ""

    if [[ "$is_url" == "true" ]]; then
        echo "Type: Remote URL"
        echo "URL:  $path_or_url"

        # Auto-detect name from URL
        if [[ -z "$service_name" ]]; then
            service_name=$(basename "$path_or_url" .git | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        fi
    else
        echo "Type: Local path"
        echo "Path: $path_or_url"

        # Auto-detect name and type
        if [[ -z "$service_name" ]]; then
            service_name=$(_extract_service_name "$path_or_url" "$MANIFEST_CLI_FLEET_ROOT")
        fi

        if [[ -z "$service_type" ]] && [[ -d "$path_or_url" ]]; then
            service_type=$(_classify_repository "$path_or_url")
        fi
    fi

    service_type="${service_type:-service}"

    echo ""
    echo "Service name: $service_name"
    echo "Service type: $service_type"
    echo ""

    # Sanitize service name for safe YAML key (alphanumeric + hyphens only)
    local safe_name
    safe_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--' | \
                sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
    if [[ -z "$safe_name" ]]; then
        log_error "Service name '$service_name' contains no valid characters"
        return 1
    fi

    # Build YAML snippet (escape embedded quotes in values)
    local yaml_content=""
    yaml_content+="  $safe_name:"$'\n'
    if [[ "$is_url" == "true" ]]; then
        yaml_content+="    url: \"${path_or_url//\"/\\\"}\""$'\n'
        yaml_content+="    path: \"./$safe_name\""$'\n'
    else
        local rel_path="${path_or_url#"$MANIFEST_CLI_FLEET_ROOT"/}"
        rel_path="${rel_path#./}"
        yaml_content+="    path: \"./${rel_path//\"/\\\"}\""$'\n'
    fi
    yaml_content+="    type: \"${service_type//\"/\\\"}\""

    local config_file
    config_file=$(_fleet_resolve_config)

    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run - manifest add fleet"
        if [[ -f "$config_file" ]]; then
            echo "Would update: $config_file"
        else
            echo "No manifest.fleet.config.yaml found."
            echo "Would print manual YAML only."
        fi
        echo ""
        echo "Would add under services:"
        echo ""
        echo "$yaml_content"
        echo ""
        manifest_execution_footer "manifest add fleet $path_or_url -y"
        return 0
    fi

    manifest_execution_apply_header
    if [[ -f "$config_file" ]]; then
        if append_services_to_manifest "$config_file" "$yaml_content"; then
            echo "✓ Added '$service_name' to $config_file"
        else
            log_error "Failed to update $config_file"
            echo ""
            echo "Add the following to manifest.fleet.config.yaml under 'services:' manually:"
            echo ""
            echo "$yaml_content"
            return 1
        fi
    else
        echo "No manifest.fleet.config.yaml found. Add the following under 'services:':"
        echo ""
        echo "$yaml_content"
    fi
    echo ""
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_main
# -----------------------------------------------------------------------------
# Main entry point for fleet commands.
#
# ARGUMENTS:
#   $1 - Subcommand (status, init, discover, sync, go, docs, validate, add, remove)
#   $@ - Additional arguments passed to subcommand
#
# EXAMPLE:
#   fleet_main "status" "--verbose"
#   fleet_main "init" "--name" "my-fleet" "--discover"
# -----------------------------------------------------------------------------
fleet_main() {
    local subcommand="${1:-help}"
    shift || true

    case "$subcommand" in
        help|--help|-h)
            fleet_help
            ;;
        add|discover|docs|init|prep|pr|quickstart|ship|start|status|sync|update|validate)
            local replacement
            case "$subcommand" in
                add)        replacement="manifest add fleet" ;;
                discover)   replacement="manifest discover fleet" ;;
                docs)       replacement="manifest docs fleet" ;;
                init|start) replacement="manifest init fleet" ;;
                prep|sync)  replacement="manifest prep fleet" ;;
                pr)         replacement="manifest pr fleet" ;;
                quickstart) replacement="manifest quickstart fleet" ;;
                ship)       replacement="manifest ship fleet" ;;
                status)     replacement="manifest status" ;;
                update)     replacement="manifest update fleet" ;;
                validate)   replacement="manifest validate fleet" ;;
            esac
            log_error "'manifest fleet $subcommand' is no longer a dispatcher route."
            echo "  Use: $replacement"
            echo ""
            echo "  See 'manifest help' for the v42 command surface."
            return 1
            ;;
        *)
            log_error "Unknown fleet command: $subcommand"
            fleet_help
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Function: fleet_help
# -----------------------------------------------------------------------------
# Displays help for fleet commands.
# -----------------------------------------------------------------------------
fleet_help() {
    cat << 'EOF'

MANIFEST FLEET - Polyrepo Management
=====================================

Manage multiple related repositories as a coordinated fleet.

Use action-first commands:

  manifest init fleet           Scaffold
  manifest plan fleet           Generate an adoption plan (dry-run by default)
  manifest reconcile fleet      Apply a validated adoption plan (--apply/--do)
  manifest prep fleet           Clone/pull
  manifest quickstart fleet     Auto-discover git repos, skip TSV selection
  manifest discover fleet       Preview fleet membership discovery
  manifest update fleet         Re-scan and add new repos
  manifest refresh fleet        Re-scan + regenerate docs
  manifest validate fleet       Validate fleet configuration
  manifest add fleet <path>     Add a service to the fleet
  manifest docs fleet           Generate fleet documentation
  manifest pr fleet             Fleet-wide PR operations
  manifest ship fleet <bump>    Coordinated release

COMMAND DETAILS:

  manifest init fleet [options]
    Two-phase fleet setup. Scans with a depth guardrail, then asks how deep
    repos should be under each top-level folder before writing manifest.fleet.tsv.
    Options:
      --depth N          Scan guardrail (default: 2 via manifest init)
      --all-folders      Write every scanned folder to manifest.fleet.tsv
      --name, -n NAME    Fleet name
      --force, -f        Overwrite generated files
      --dry-run          Preview files and discovery without writing

  manifest quickstart fleet [options]
    Quick fleet setup — auto-discovers existing git repos, skips selection.
    Equivalent to: manifest init fleet (without the TSV selection step).
    Options:
      -y, --yes         Apply the quickstart plan
      --dry-run          Preview files and discovery without writing
      --name, -n NAME    Fleet name
      --force, -f        Overwrite existing manifest.fleet.config.yaml

  manifest plan fleet [options]
    Generate manifest.fleet.plan.yaml for fleet adoption.
    Dry-run by default.
    Options:
      --apply, --do      Write the plan file
      --depth N|auto     Scan depth guardrail (default: auto)
      --plan FILE        Plan file path

  manifest reconcile fleet [options]
    Validate and apply manifest.fleet.plan.yaml.
    Dry-run by default.
    Options:
      --apply, --do      Apply local filesystem/config changes
      --commit           Commit local changes (requires --apply/--do)
      --push             Push commits (requires --commit)
      --force            Reserved for explicit overrides (requires --apply/--do)
      --adopt-submodules Allow adopt_submodule actions

  manifest status [options]
    Show fleet status overview.
    Options:
      --verbose, -v      Show detailed information
      --json             Output as JSON

  manifest update fleet [options]
    Re-scan workspace and add new repos to manifest.fleet.config.yaml.
    Options:
      -y, --yes          Apply fleet membership updates
      --dry-run          Preview only — do not modify manifest.fleet.config.yaml
      --depth N          Maximum search depth (default: 5)
      --json             Output JSON summary (implies --dry-run)
      --quiet, -q        Only output new repo lines (implies --dry-run)

  manifest discover fleet [options]
    Alias for 'manifest update fleet --dry-run'.

  manifest validate fleet
    Validate fleet configuration.

  manifest add fleet <path-or-url> [options]
    Add a service to the fleet.
    Options:
      -y, --yes          Apply fleet membership updates
      --dry-run          Preview YAML without modifying manifest.fleet.config.yaml
      --name NAME        Service name
      --type TYPE        Service type (service|library|infrastructure|tool)

  manifest pr fleet [options]
    Preferred shorthand for: manifest pr fleet queue [options]
    (queues policy-aware auto-merge across fleet PRs after gates pass)
    Queue options:
      --method <merge|squash|rebase>
      --force
      --no-delete-branch
    Explicit subcommands:
      create | status | checks | ready | queue
    Examples:
      manifest pr fleet
      manifest pr fleet create
      manifest pr fleet status
      manifest pr fleet checks
      manifest pr fleet ready
      manifest pr fleet --method squash         # Preferred team path
      manifest pr fleet queue --method merge    # Explicit equivalent

  manifest ship fleet [patch|minor|major|revision] [options]
    Highest-level coordinated fleet workflow.
    Options:
      --noprep
      --safe
      --method <merge|squash|rebase>
      --force
      --no-delete-branch
      --draft

  manifest docs fleet [subcommand] [-y|--yes] [--dry-run] [options]
    Generate fleet documentation per configured strategy.
    Subcommands:
      generate          Generate docs (default)
      status            Show current docs configuration
      help              Show docs help
    Options:
      --strategy <s>    Override strategy: fleet-root|per-service|both
      --fleet-only      Only generate fleet-root docs
      --services-only   Only generate per-service docs
      --dry-run         Preview planned docs writes without changing files
      -y, --yes         Apply planned docs writes

CONFIGURATION:

  Fleet is configured via manifest.fleet.config.yaml in the fleet root directory.
  Service-specific overrides go in each service's manifest.config.local.yaml.

  Run 'manifest init fleet' to set up a new fleet.

EXAMPLES:

  # Recommended workflow for new fleet (v42)
  manifest init fleet                   # choose repo depths, write manifest.fleet.tsv
  # ... review manifest.fleet.tsv ...
  manifest init fleet                   # apply selections (Phase 2)

  # Quick setup (auto-discover git repos, no selection step)
  manifest quickstart fleet --dry-run

  # Add newly discovered repos to an existing fleet
  manifest refresh fleet                # also regenerates docs

  # Preview only (read-only)
  manifest plan fleet
  manifest reconcile fleet
  manifest init fleet --dry-run
  manifest refresh fleet --dry-run
  manifest docs fleet --dry-run

  # Check fleet status
  manifest status

  # Clone all missing services
  manifest prep fleet

EOF
}

# =============================================================================
# STANDALONE EXECUTION
# =============================================================================
# Allows running this module directly for testing

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Source dependencies if running standalone
    MODULES_DIR="$(dirname "$MANIFEST_CLI_FLEET_SCRIPT_DIR")"

    if [[ -f "$MODULES_DIR/core/manifest-shared-utils.sh" ]]; then
        source "$MODULES_DIR/core/manifest-shared-utils.sh"
    else
        # Minimal logging fallback
        log_info() { echo "[INFO] $*"; }
        log_error() { echo "[ERROR] $*" >&2; }
        log_warning() { echo "[WARN] $*"; }
        log_success() { echo "[OK] $*"; }
        log_debug() { [[ "${MANIFEST_CLI_DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*"; }
    fi

    fleet_main "$@"
fi
