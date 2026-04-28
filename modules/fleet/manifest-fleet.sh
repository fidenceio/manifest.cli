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
# COMMANDS (legacy, still routed via 'manifest fleet *'):
#   manifest fleet status    - Show fleet status
#   manifest fleet update    - Re-scan and add new repos (--dry-run to preview)
#   manifest fleet discover  - Alias for 'fleet update --dry-run'
#   manifest fleet add       - Add a service to fleet
#   manifest fleet quickstart - Auto-discover git repos (skips TSV selection)
#   manifest fleet prep      - Coordinated version bump (no commit/push)
#   manifest fleet docs      - Generate unified documentation
#   manifest fleet validate  - Validate configuration
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
MANIFEST_FLEET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prevent multiple sourcing
if [[ -n "${_MANIFEST_FLEET_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_FLEET_LOADED=1

# Module metadata
readonly MANIFEST_FLEET_MODULE_VERSION="1.0.0"
readonly MANIFEST_FLEET_MODULE_NAME="manifest-fleet"

# -----------------------------------------------------------------------------
# Source Dependencies
# -----------------------------------------------------------------------------
# Source fleet sub-modules
source "$MANIFEST_FLEET_SCRIPT_DIR/manifest-fleet-config.sh"
source "$MANIFEST_FLEET_SCRIPT_DIR/manifest-fleet-detect.sh"
source "$MANIFEST_FLEET_SCRIPT_DIR/manifest-fleet-docs.sh"

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
#   $1 - Root directory to search (defaults to MANIFEST_FLEET_ROOT or pwd)
#
# OUTPUT:
#   Echoes the resolved config file path
# -----------------------------------------------------------------------------
_fleet_resolve_config() {
    local root_dir="${1:-${MANIFEST_FLEET_ROOT:-.}}"
    local config_file="${MANIFEST_FLEET_CONFIG_FILE:-}"
    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        local config_filename="${MANIFEST_CLI_FLEET_CONFIG_FILENAME:-$MANIFEST_FLEET_DEFAULT_CONFIG_FILENAME}"
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
    if [[ "$MANIFEST_FLEET_ACTIVE" != "true" ]]; then
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
#   manifest fleet status
#   manifest fleet status --verbose
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
        echo "  manifest fleet discover"
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
    echo "Fleet: $MANIFEST_FLEET_NAME"
    [[ -n "$MANIFEST_FLEET_DESCRIPTION" ]] && echo "       $MANIFEST_FLEET_DESCRIPTION"
    echo "Root:  $MANIFEST_FLEET_ROOT"
    echo ""

    # Fleet version (if enabled)
    if [[ "$MANIFEST_FLEET_VERSIONING" != "none" ]] && [[ -n "$MANIFEST_FLEET_VERSION" ]]; then
        echo "Fleet Version: $MANIFEST_FLEET_VERSION ($MANIFEST_FLEET_VERSIONING)"
        echo ""
    fi

    # Service count
    local service_count
    # shellcheck disable=SC2086
    service_count=$(set -- $MANIFEST_FLEET_SERVICES; echo $#)
    echo "Services: $service_count"
    echo ""

    # Service table header
    printf "┌─────────────────────────┬──────────┬──────────┬──────────────┬─────────┐\n"
    printf "│ %-23s │ %-8s │ %-8s │ %-12s │ %-7s │\n" "SERVICE" "TYPE" "VERSION" "BRANCH" "STATUS"
    printf "├─────────────────────────┼──────────┼──────────┼──────────────┼─────────┤\n"

    # Service details
    for service in $MANIFEST_FLEET_SERVICES; do
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
    echo "    \"name\": \"$(_json_escape "$MANIFEST_FLEET_NAME")\","
    echo "    \"root\": \"$(_json_escape "$MANIFEST_FLEET_ROOT")\","
    if [[ -n "${MANIFEST_FLEET_VERSION:-}" ]]; then
        echo "    \"version\": \"$(_json_escape "$MANIFEST_FLEET_VERSION")\","
    else
        echo "    \"version\": null,"
    fi
    echo "    \"versioning\": \"$MANIFEST_FLEET_VERSIONING\""
    echo "  },"
    echo "  \"services\": ["

    local first=true
    for service in $MANIFEST_FLEET_SERVICES; do
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
# Equivalent to: manifest fleet init --_quickstart
# -----------------------------------------------------------------------------
fleet_quickstart() {
    _fleet_init --_quickstart "$@"
}

# =============================================================================
# INTERNAL: fleet start (Phase 1 of init fleet)
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _fleet_start (internal)
# -----------------------------------------------------------------------------
# Scans ALL subdirectories (git and non-git) and writes a TSV selection file.
# The user edits the file to choose which directories to include, then runs
# 'manifest init fleet' (Phase 2) to apply initialization standards.
#
# Called from manifest_init_fleet (Phase 1) in modules/core/manifest-init.sh.
#
# ARGUMENTS:
#   --depth N    Maximum search depth (default: 5)
#   --force      Overwrite existing manifest.fleet.tsv
# -----------------------------------------------------------------------------
_fleet_start() {
    local depth=5
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--depth requires a numeric value"
                    return 1
                fi
                depth="$2"; shift 2 ;;
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
    echo ""

    local discovered
    discovered=$(discover_all_directories "$root_dir" "$depth")

    if [[ -z "$discovered" ]]; then
        log_warning "No directories found in: $root_dir"
        return 0
    fi

    # Write TSV selection file
    generate_start_tsv "$discovered" "$root_dir" "$depth" > "$start_file"

    # Count stats for summary
    local total=0 git_count=0 plain_count=0
    while IFS=$'\t' read -r name path type branch version url submodule has_git has_remote; do
        [[ -z "$name" ]] && continue
        ((total++))
        if [[ "$has_git" == "true" ]]; then
            ((git_count++))
        else
            ((plain_count++))
        fi
    done <<< "$discovered"

    echo "Scan results:"
    echo "  Total directories:  $total"
    echo "  With git:           $git_count (selected by default)"
    echo "  Without git:        $plain_count (not selected by default)"
    echo ""
    echo "✓ Created: $start_file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit manifest.fleet.tsv — set SELECT to true/false"
    echo "  2. Run 'manifest init fleet' to initialize selected directories"
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
# -----------------------------------------------------------------------------
_fleet_init() {
    local fleet_name=""
    local minimal_template=false
    local force=false
    local skip_start=false
    local create_repo_visibility=""

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
        echo "  Quick start:  manifest fleet quickstart     (auto-discover git repos)"
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

        if [[ -n "$all_dirs" ]]; then
            # Generate TSV with git repos auto-selected
            generate_start_tsv "$all_dirs" "$target_dir" 5 > "$start_file"
            echo "✓ Created: $start_file"

            local service_count=0
            while IFS=$'\t' read -r name path type branch version url submodule has_git has_remote; do
                [[ -z "$name" ]] && continue
                [[ "$has_git" == "true" ]] && ((service_count++))
            done <<< "$all_dirs"
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
  require_expected_branch: true
EOF
}

# =============================================================================
# COMMAND: fleet discover (alias for fleet update --dry-run)
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_discover
# -----------------------------------------------------------------------------
# Alias for 'fleet update --dry-run'. Kept for backwards compatibility.
# All discovery logic now lives in fleet_update.
# -----------------------------------------------------------------------------
fleet_discover() {
    fleet_update --dry-run "$@"
}

# =============================================================================
# INTERNAL: fleet sync (called by 'manifest prep fleet')
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _fleet_validate_clone_path (internal)
# -----------------------------------------------------------------------------
# Validates that a fleet service path is safely under MANIFEST_FLEET_ROOT.
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

    local parallel=$(get_fleet_config_value "parallel" "$MANIFEST_FLEET_DEFAULT_PARALLEL")
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
        _fleet_sync_dry_run "$clone_only" "$pull_only"
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

    local total=0 would_clone=0 would_pull=0 would_skip=0 would_fail=0
    local service path url is_submodule

    for service in $MANIFEST_FLEET_SERVICES; do
        ((total++))
        path=$(get_fleet_service_property "$service" "path")
        url=$(get_fleet_service_property "$service" "url")
        is_submodule=$(get_fleet_service_property "$service" "submodule" "false")

        if [[ ! -d "$path" ]]; then
            if [[ "$pull_only" == "true" ]]; then
                echo "  $service: would skip (pull-only, path missing)"
                ((would_skip++))
            elif [[ "$is_submodule" == "true" ]]; then
                echo "  $service: would fail (submodule path missing — needs parent 'submodule update --init')"
                ((would_fail++))
            elif [[ -z "$url" ]]; then
                echo "  $service: would fail (no URL)"
                ((would_fail++))
            elif ! _fleet_validate_clone_path "$path"; then
                echo "  $service: would fail (invalid path: $path)"
                ((would_fail++))
            else
                echo "  $service: would clone from $url -> $path"
                ((would_clone++))
            fi
        else
            if [[ "$clone_only" == "true" ]]; then
                echo "  $service: would skip (clone-only, path exists)"
                ((would_skip++))
            elif [[ ! -d "$path/.git" ]] && [[ "$is_submodule" != "true" ]]; then
                echo "  $service: would skip (not a git repo)"
                ((would_skip++))
            else
                echo "  $service: would pull --rebase ($path)"
                ((would_pull++))
            fi
        fi
    done

    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    echo "Plan: $would_clone clone, $would_pull pull, $would_skip skip, $would_fail fail (of $total total)"
    echo ""
    echo "No changes written. Re-run without --dry-run to apply."
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
        mkdir -p "$MANIFEST_FLEET_ROOT/$(dirname "$path")"

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
    for service in $MANIFEST_FLEET_SERVICES; do
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
    result_dir=$(mktemp -d)

    local total=0
    for service in $MANIFEST_FLEET_SERVICES; do
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
    result_dir=$(mktemp -d)

    local pids=()
    for service in $MANIFEST_FLEET_SERVICES; do
        _fleet_sync_service "$service" "$clone_only" "$pull_only" "$result_dir" &
        pids+=($!)
    done

    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    local total=0
    for service in $MANIFEST_FLEET_SERVICES; do
        ((total++))
    done

    _fleet_sync_print_summary "$result_dir" "$total"
    rm -rf "$result_dir"
}

# =============================================================================
# COMMAND: fleet update
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_update
# -----------------------------------------------------------------------------
# Re-scans the workspace and adds newly discovered repos to manifest.fleet.config.yaml.
#
# Also serves as the single discovery entry point. Use --dry-run to preview
# changes without writing (this is what 'fleet discover' does).
#
# ARGUMENTS:
#   --depth N      Maximum search depth (default: 5)
#   --dry-run      Preview only — do not modify manifest.fleet.config.yaml
#   --json         Output JSON summary (implies --dry-run)
#   --quiet, -q    Only output new repo lines, for scripting (implies --dry-run)
#
# EXAMPLE:
#   manifest fleet update
#   manifest fleet update --depth 3
#   manifest fleet update --dry-run
# -----------------------------------------------------------------------------
fleet_update() {
    local depth=5
    local skip_init_check=false
    local dry_run=false
    local json_output=false
    local quiet=false

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
            --dry-run) dry_run=true; shift ;;
            --json) json_output=true; dry_run=true; shift ;;
            -q|--quiet) quiet=true; dry_run=true; shift ;;
            *) shift ;;
        esac
    done

    if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
        log_error "--depth must be a non-negative integer"
        return 1
    fi

    local root_dir="${MANIFEST_FLEET_ROOT:-$(pwd)}"

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
            echo "  manifest fleet update"
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

    if [[ -n "$all_dirs" ]]; then
        # merge_start_tsv writes TSV to stdout and "NEW:<count>" to stderr
        local merge_stderr
        merge_stderr=$(merge_start_tsv "$all_dirs" "$start_file" "$root_dir" "$depth" 2>&1 > "${start_file}.tmp")
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
# COMMAND: fleet prep
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
#   manifest fleet prep
#   manifest fleet prep minor
# -----------------------------------------------------------------------------
# Internal prep runner (no banner — called by fleet_ship and fleet_prep)
_fleet_prep_run() {
    local increment_type="${1:-patch}"

    local any_failures=0
    for service in $MANIFEST_FLEET_SERVICES; do
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

# -----------------------------------------------------------------------------
# Function: _fleet_filter_services
# -----------------------------------------------------------------------------
# Computes a filtered subset of $MANIFEST_FLEET_SERVICES based on --only and
# --except selectors. Selectors are comma- or space-separated service names.
# Exactly one of $1 / $2 may be set (validation is the caller's job).
#
# Echoes the filtered service list (newline-free, space-separated).
# Returns 1 if any named service is not present in the fleet.
# -----------------------------------------------------------------------------
_fleet_filter_services() {
    local only_csv="$1"
    local except_csv="$2"
    local result=""
    local name

    if [ -n "$only_csv" ]; then
        for name in $(echo "$only_csv" | tr ',' ' '); do
            if [ -z "$name" ]; then
                continue
            fi
            if [[ " $MANIFEST_FLEET_SERVICES " != *" $name "* ]]; then
                log_error "Service '$name' is not in the fleet."
                return 1
            fi
            result="${result:+$result }$name"
        done
    elif [ -n "$except_csv" ]; then
        local exclude=" "
        for name in $(echo "$except_csv" | tr ',' ' '); do
            if [ -z "$name" ]; then
                continue
            fi
            if [[ " $MANIFEST_FLEET_SERVICES " != *" $name "* ]]; then
                log_error "Service '$name' is not in the fleet."
                return 1
            fi
            exclude="$exclude$name "
        done
        local svc
        for svc in $MANIFEST_FLEET_SERVICES; do
            if [[ "$exclude" != *" $svc "* ]]; then
                result="${result:+$result }$svc"
            fi
        done
    else
        result="$MANIFEST_FLEET_SERVICES"
    fi

    echo "$result"
}

# -----------------------------------------------------------------------------
# Function: fleet_ship
# -----------------------------------------------------------------------------
# Highest-level coordinated fleet workflow:
#   (optional) prep -> fleet pr create -> (optional checks/ready) -> fleet pr queue
# -----------------------------------------------------------------------------
fleet_ship() {
    if ! _fleet_require_initialized "ship"; then
        return 1
    fi

    local increment_type="patch"
    local run_prep=true
    local safe=false
    local method="squash"
    local force=false
    local no_delete_branch=false
    local draft=false
    local any_failures=0
    local only_filter=""
    local except_filter=""

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
            --safe)
                safe=true
                shift
                ;;
            --method)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--method requires a value: merge|squash|rebase"
                    return 1
                fi
                method="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --no-delete-branch)
                no_delete_branch=true
                shift
                ;;
            --draft)
                draft=true
                shift
                ;;
            --only)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--only requires a service name (or comma-separated list)"
                    return 1
                fi
                only_filter="${only_filter:+$only_filter,}$2"
                shift 2
                ;;
            --except)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    log_error "--except requires a service name (or comma-separated list)"
                    return 1
                fi
                except_filter="${except_filter:+$except_filter,}$2"
                shift 2
                ;;
            -h|--help)
                cat << 'EOF'
Usage: manifest fleet ship [patch|minor|major|revision] [options]

Options:
  --noprep                  Skip per-service prep step
  --safe                    Run checks/ready gate before queueing
  --method <merge|squash|rebase>
  --force                   Bypass readiness gate during queue
  --no-delete-branch        Keep source branches after queue
  --draft                   Create draft PRs
  --only <name[,name...]>   Ship only the named service(s) (repeatable)
  --except <name[,name...]> Ship all services except the named one(s) (repeatable)

Flow:
  default: fleet prep -> fleet docs -> fleet pr create -> fleet pr queue
  --safe:  fleet prep -> fleet docs -> fleet pr create -> fleet pr checks -> fleet pr ready -> fleet pr queue

--only and --except are mutually exclusive.
EOF
                return 0
                ;;
            *)
                log_error "Unknown option for 'manifest fleet ship': $1"
                return 1
                ;;
        esac
    done

    if [ -n "$only_filter" ] && [ -n "$except_filter" ]; then
        log_error "--only and --except are mutually exclusive."
        return 1
    fi

    if [[ ! "$method" =~ ^(merge|squash|rebase)$ ]]; then
        log_error "Invalid --method value: '$method' (expected merge|squash|rebase)"
        return 1
    fi

    local _saved_services="$MANIFEST_FLEET_SERVICES"
    if [ -n "$only_filter" ] || [ -n "$except_filter" ]; then
        local filtered
        if ! filtered=$(_fleet_filter_services "$only_filter" "$except_filter"); then
            return 1
        fi
        if [ -z "$filtered" ]; then
            log_error "Filter selected zero services."
            return 1
        fi
        MANIFEST_FLEET_SERVICES="$filtered"
        echo "🎯 Filter applied: $filtered"
    fi

    # Filter args forwarded to manifest_fleet_pr_dispatch — Cloud plugin honors
    # them so its own service iteration matches the local filter.
    local pr_filter_args=()
    [ -n "$only_filter" ]   && pr_filter_args+=(--only   "$only_filter")
    [ -n "$except_filter" ] && pr_filter_args+=(--except "$except_filter")

    # Determine step count based on whether safe mode adds extra steps
    local total_steps=5
    if [ "$safe" = "true" ]; then
        total_steps=6
    fi

    echo "🚢 Starting fleet ship workflow ($increment_type)"

    # One-shot block so we always restore $MANIFEST_FLEET_SERVICES on exit.
    local _rc=0
    while :; do
        if [ "$run_prep" = "true" ]; then
            echo "🔧 Step 1/$total_steps: Running prep across fleet services..."
            if ! _fleet_prep_run "$increment_type"; then
                _rc=1; break
            fi
        else
            echo "⏭️  Skipping fleet prep (--noprep)."
            for service in $MANIFEST_FLEET_SERVICES; do
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
                _rc=1; break
            fi
        fi

        # --- Fleet docs generation ---
        echo "📄 Step 2/$total_steps: Generating fleet documentation..."
        local docs_strategy
        docs_strategy=$(get_fleet_docs_strategy)
        fleet_docs_generate "$increment_type" || {
            log_warning "Fleet docs generation had issues, continuing..."
        }

        echo "🔀 Step 3/$total_steps: Creating or reusing PRs across fleet..."
        local create_args=("${pr_filter_args[@]}")
        [ "$draft" = "true" ] && create_args+=("--draft")
        manifest_fleet_pr_dispatch create "${create_args[@]}" || { _rc=1; break; }

        if [ "$safe" = "true" ]; then
            echo "🧪 Step 4/$total_steps: Verifying checks and readiness across fleet..."
            manifest_fleet_pr_dispatch checks "${pr_filter_args[@]}" || { _rc=1; break; }
            manifest_fleet_pr_dispatch ready  "${pr_filter_args[@]}" || { _rc=1; break; }
        fi

        local queue_step=$((total_steps))
        echo "📥 Step ${queue_step}/${total_steps}: Queueing PRs across fleet..."
        local queue_args=("${pr_filter_args[@]}" --method "$method")
        [ "$force" = "true" ] && queue_args+=("--force")
        [ "$no_delete_branch" = "true" ] && queue_args+=("--no-delete-branch")
        manifest_fleet_pr_dispatch queue "${queue_args[@]}" || { _rc=1; break; }

        echo "✅ Fleet ship workflow complete."
        break
    done

    MANIFEST_FLEET_SERVICES="$_saved_services"
    return $_rc
}

# =============================================================================
# COMMAND: fleet validate
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_validate
# -----------------------------------------------------------------------------
# Validates fleet configuration and reports issues.
#
# EXAMPLE:
#   manifest fleet validate
# -----------------------------------------------------------------------------
fleet_validate() {
    if ! _fleet_require_initialized "validate"; then
        return 1
    fi

    echo ""
    echo "Validating fleet: $MANIFEST_FLEET_NAME"
    echo ""

    validate_fleet_config
}

# =============================================================================
# COMMAND: fleet add
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
#   manifest fleet add ./new-service
#   manifest fleet add git@github.com:org/repo.git --name my-service
# -----------------------------------------------------------------------------
fleet_add() {
    local path_or_url=""
    local service_name=""
    local service_type=""

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
            *)
                if [[ -z "$path_or_url" ]]; then
                    path_or_url="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$path_or_url" ]]; then
        log_error "Usage: manifest fleet add <path-or-url> [--name NAME] [--type TYPE]"
        return 1
    fi

    # Determine if it's a path or URL
    local is_url=false
    if [[ "$path_or_url" == git@* ]] || [[ "$path_or_url" == https://* ]] || [[ "$path_or_url" == http://* ]]; then
        is_url=true
    fi

    echo ""
    echo "Adding service to fleet: $MANIFEST_FLEET_NAME"
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
            service_name=$(_extract_service_name "$path_or_url" "$MANIFEST_FLEET_ROOT")
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
        local rel_path="${path_or_url#"$MANIFEST_FLEET_ROOT"/}"
        rel_path="${rel_path#./}"
        yaml_content+="    path: \"./${rel_path//\"/\\\"}\""$'\n'
    fi
    yaml_content+="    type: \"${service_type//\"/\\\"}\""

    local config_file
    config_file=$(_fleet_resolve_config)

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
        quickstart)
            fleet_quickstart "$@"
            ;;
        # 'start', 'init', and 'sync' are no longer dispatcher routes — the
        # underlying functions are private (_fleet_start/_fleet_init/_fleet_sync)
        # and are reached via the v42 entry points (manifest init/prep fleet).
        # The unknown-command fallback below detects these and prints migration
        # hints rather than a bare "Unknown fleet command" error.
        status)
            fleet_status "$@"
            ;;
        discover)
            fleet_discover "$@"
            ;;
        update)
            fleet_update "$@"
            ;;
        ship)
            fleet_ship "$@"
            ;;
        validate)
            fleet_validate "$@"
            ;;
        add)
            fleet_add "$@"
            ;;
        pr)
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
                    # Treat unknown first token as queue option payload.
                    pr_subcommand="queue"
                    implicit_queue=true
                    ;;
            esac
            if [ "$implicit_queue" = "true" ]; then
                echo "ℹ️  Default fleet PR action: queue (use 'manifest fleet pr help' for all subcommands)."
            fi
            if declare -F manifest_fleet_pr_dispatch >/dev/null 2>&1; then
                manifest_fleet_pr_dispatch "$pr_subcommand" "$@"
            else
                log_error "Fleet PR module unavailable"
                return 1
            fi
            ;;
        prep)
            fleet_prep "$@"
            ;;
        docs)
            fleet_docs_dispatch "$@"
            ;;
        help|--help|-h)
            fleet_help
            ;;
        start|init|sync)
            local replacement
            case "$subcommand" in
                start) replacement="manifest init fleet" ;;
                init)  replacement="manifest init fleet" ;;
                sync)  replacement="manifest prep fleet" ;;
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

This is a legacy command surface — prefer the v42 entry points:

  manifest init fleet           Scaffold (was: manifest fleet start + init)
  manifest prep fleet           Clone/pull (was: manifest fleet sync)
  manifest refresh fleet        Re-scan + regenerate docs (was: manifest fleet update)
  manifest ship fleet <bump>    Coordinated release (was: manifest fleet ship)

LEGACY-ONLY COMMANDS:

  manifest fleet quickstart [options]
    Quick fleet setup — auto-discovers existing git repos, skips selection.
    Equivalent to: manifest init fleet (without the TSV selection step).
    Options:
      --name, -n NAME    Fleet name
      --force, -f        Overwrite existing manifest.fleet.config.yaml

  manifest fleet status [options]
    Show fleet status overview. (Prefer 'manifest status'.)
    Options:
      --verbose, -v      Show detailed information
      --json             Output as JSON

  manifest fleet update [options]
    Re-scan workspace and add new repos to manifest.fleet.config.yaml.
    (Prefer 'manifest refresh fleet' which also regenerates docs.)
    Options:
      --depth N          Maximum search depth (default: 5)
      --dry-run          Preview only — do not modify manifest.fleet.config.yaml
      --json             Output JSON summary (implies --dry-run)
      --quiet, -q        Only output new repo lines (implies --dry-run)

  manifest fleet discover [options]
    Alias for 'manifest fleet update --dry-run'.

  manifest fleet validate
    Validate fleet configuration.

  manifest fleet add <path-or-url> [options]
    Add a service to the fleet.
    Options:
      --name NAME        Service name
      --type TYPE        Service type (service|library|infrastructure|tool)

  manifest fleet pr [options]
    Preferred shorthand for: manifest fleet pr queue [options]
    (queues policy-aware auto-merge across fleet PRs after gates pass)
    Queue options:
      --method <merge|squash|rebase>
      --force
      --no-delete-branch
    Explicit subcommands:
      create | status | checks | ready | queue
    Examples:
      manifest fleet pr
      manifest fleet pr create
      manifest fleet pr status
      manifest fleet pr checks
      manifest fleet pr ready
      manifest fleet pr --method squash         # Preferred team path
      manifest fleet pr queue --method merge    # Explicit equivalent

  manifest fleet ship [patch|minor|major|revision] [options]
    Highest-level coordinated fleet workflow.
    Options:
      --noprep
      --safe
      --method <merge|squash|rebase>
      --force
      --no-delete-branch
      --draft

  manifest fleet prep [patch|minor|major]
    Coordinated version bump across all services.
    (Coming soon)

  manifest fleet docs [subcommand] [options]
    Generate fleet documentation per configured strategy.
    Subcommands:
      generate          Generate docs (default)
      status            Show current docs configuration
      help              Show docs help
    Options:
      --strategy <s>    Override strategy: fleet-root|per-service|both
      --fleet-only      Only generate fleet-root docs
      --services-only   Only generate per-service docs

CONFIGURATION:

  Fleet is configured via manifest.fleet.config.yaml in the fleet root directory.
  Service-specific overrides go in each service's manifest.config.local.yaml.

  Run 'manifest init fleet' to set up a new fleet.

EXAMPLES:

  # Recommended workflow for new fleet (v42)
  manifest init fleet                   # scan and write manifest.fleet.tsv
  # ... edit manifest.fleet.tsv ...
  manifest init fleet                   # apply selections (Phase 2)

  # Quick setup (auto-discover git repos, no selection step)
  manifest fleet quickstart

  # Add newly discovered repos to an existing fleet
  manifest refresh fleet                # also regenerates docs

  # Preview only (read-only)
  manifest refresh fleet --dry-run

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
    MODULES_DIR="$(dirname "$MANIFEST_FLEET_SCRIPT_DIR")"

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
