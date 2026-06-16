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
source "$MANIFEST_CLI_FLEET_SCRIPT_DIR/manifest-fleet-topics.sh"
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
            gitignore_failed=$((gitignore_failed+1))
            continue
        fi

        case "$result" in
            ".gitignore")
                echo "  ✓ $name: created .gitignore"
                gitignore_created=$((gitignore_created+1))
                ;;
            ".gitignore:empty-overwrite")
                echo "  ✓ $name: created .gitignore"
                gitignore_overwritten=$((gitignore_overwritten+1))
                overwritten_repos+=("$name")
                ;;
            ".gitignore.manifest")
                echo "  ~ $name: existing .gitignore preserved, created .gitignore.manifest"
                gitignore_ref=$((gitignore_ref+1))
                ;;
            *)
                gitignore_skipped=$((gitignore_skipped+1))
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
#   --depth N|auto  Scan depth; auto deepens to repos found, capped (default: auto)
#   --all-folders   Write every scanned folder to manifest.fleet.tsv
#   --force         Overwrite existing manifest.fleet.tsv
# -----------------------------------------------------------------------------
_fleet_start() {
    local depth="auto"
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

    local root_dir="$(pwd)"
    local start_file="$root_dir/manifest.fleet.tsv"
    # Resolve --depth (N|auto) to a concrete scan depth (§7.3).
    depth="$(manifest_fleet_resolve_depth "$depth" "$root_dir")" || return 1

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
    local line
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local name="${fields[0]:-}"
        [[ -z "$name" ]] && continue
        scanned_total=$((scanned_total+1))
    done <<< "$discovered"
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local name="${fields[0]:-}"
        local has_git="${fields[7]:-}"
        [[ -z "$name" ]] && continue
        listed_total=$((listed_total+1))
        if [[ "$has_git" == "true" ]]; then
            git_count=$((git_count+1))
        else
            plain_count=$((plain_count+1))
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

# -----------------------------------------------------------------------------
# Function: create_fleet_gitignore (internal)
# -----------------------------------------------------------------------------
# Writes an ALLOWLIST .gitignore for a fleet coordination root: ignore everything,
# then re-include ONLY Manifest's coordination files. This keeps the coordination
# repo from ever tracking member repos, service source, secrets, or workspace
# artifacts — the full fleet layout lives in manifest.fleet.tsv.
#
# No-clobber policy mirrors ensure_gitignore_smart(): an existing populated
# .gitignore is preserved and the allowlist is written to .gitignore.manifest
# as a reference instead.
#
# Output (stdout): ".gitignore" | ".gitignore:empty-overwrite" | ".gitignore.manifest" | ""
# Returns 0 on success, 1 on write failure.
# -----------------------------------------------------------------------------
_fleet_write_allowlist_gitignore() {
    local dest="$1"
    local tmp="${dest}.tmp.$$"
    # Write to a sibling temp then atomically rename, so an interrupted write
    # never leaves a truncated .gitignore (pattern: _manifest_config_atomic_write_timestamp).
    if ! cat > "$tmp" << 'EOF'
# =============================================================================
# Manifest fleet — coordination repo .gitignore (ALLOWLIST model)
# =============================================================================
# This local-only git repo exists to satisfy Manifest's fleet-root requirement:
# date-versioned fleets commit FLEET_VERSION here, and the fleet config is tracked
# for the team. It tracks ONLY Manifest's coordination files — never member repos,
# service source, secrets, or workspace artifacts. The full fleet layout lives in
# manifest.fleet.tsv (the structure-of-record).
#
# Model: ignore everything, then re-include only the coordination files.

# Ignore everything…
/*

# …then re-include only the coordination files (all at the fleet root).
!/.gitignore
!/manifest.fleet.config.yaml
!/manifest.fleet.tsv
!/FLEET_VERSION
!/CHANGELOG_FLEET.md
EOF
    then
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
    mv -f "$tmp" "$dest" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    return 0
}

# True when DIR is itself the root of a git work tree (has its own .git), as
# opposed to merely being nested inside a parent repo. Reuses the discovery
# helper when loaded; falls back to a direct .git check so it is correct in any
# sourcing order.
_fleet_dir_is_own_git_repo() {
    local dir="$1"
    if declare -F manifest_discovery_is_git_repository >/dev/null 2>&1; then
        manifest_discovery_is_git_repository "$dir"
    else
        [[ -d "$dir/.git" ]] || [[ -f "$dir/.git" ]]
    fi
}

create_fleet_gitignore() {
    local fleet_root="$1"
    local gitignore_file="$fleet_root/.gitignore"
    local manifest_ref="$fleet_root/.gitignore.manifest"

    if [[ ! -f "$gitignore_file" ]]; then
        _fleet_write_allowlist_gitignore "$gitignore_file" || return 1
        echo ".gitignore"; return 0
    fi

    # Idempotent: an existing allowlist is already correct — no-op, and do NOT
    # spawn a redundant .gitignore.manifest on repeat runs.
    if grep -q 'coordination repo .gitignore (ALLOWLIST model)' "$gitignore_file" 2>/dev/null \
       && grep -qxF '/*' "$gitignore_file" 2>/dev/null; then
        return 0
    fi

    local entry_count
    entry_count=$(grep -cvE '^\s*$|^\s*#' "$gitignore_file" 2>/dev/null || echo "0")
    if [[ "$entry_count" -eq 0 ]]; then
        _fleet_write_allowlist_gitignore "$gitignore_file" || return 1
        echo ".gitignore:empty-overwrite"; return 0
    fi

    if [[ ! -f "$manifest_ref" ]]; then
        _fleet_write_allowlist_gitignore "$manifest_ref" || return 1
        echo ".gitignore.manifest"; return 0
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
# Reads the reviewed selections from manifest.fleet.tsv (written by Phase 1 /
# _fleet_start, or by `manifest first` on a fleet) and initializes the selected
# directories. Phase 2 requires the TSV — there is no auto-discovery fallback
# (that path was retired with the internal `--_autodiscover` flag once
# `manifest first` moved onto the two-phase rails).
#
# BEHAVIOR:
#   1. Reads selected directories from manifest.fleet.tsv
#   2. Bootstraps each directory (git init, .gitignore, optional gh repo)
#   3. Scaffolds each member with the Manifest-required files (ensure_required_files)
#   4. Creates skeleton manifest.fleet.config.yaml + manifest.config.local.yaml
#   5. Validates the configuration
#
# ARGUMENTS:
#   --name, -n NAME              Fleet name (prompted if not provided)
#   --template, -t               Use minimal template (no comments)
#   --force, -f                  Overwrite existing manifest.fleet.config.yaml
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

    # Phase 2 requires the reviewed selection file. It is written by Phase 1
    # (`manifest init fleet` with no TSV) or by `manifest first` on a fleet;
    # there is no auto-discovery fallback here.
    if [[ ! -f "$start_file" ]]; then
        log_warning "No selection file found."
        echo ""
        echo "  Run first:  manifest init fleet   (scan and select directories)"
        echo "  Or:         manifest first        (discover and register git repos)"
        return 1
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                  MANIFEST INIT FLEET (PHASE 2/2)                    ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Get fleet name if not provided. Prompt only when interactive; a
    # non-interactive apply (-y in CI/automation, consent model C) must not
    # block on or abort at the prompt — it falls back to the directory-derived
    # default. (`read` on EOF returns non-zero, which would trip the CLI's
    # set -e — hence the TTY guard rather than a bare `read`.)
    if [[ -z "$fleet_name" ]]; then
        local default_name
        default_name=$(basename "$target_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        if [[ -t 0 ]]; then
            echo "Enter fleet name (default: $default_name):"
            read -r fleet_name || true
        fi
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

    # Ensure the fleet ROOT is itself a git repo with a coordination allowlist.
    # All fleet roots get this: date-versioned fleets must commit FLEET_VERSION
    # here, and every fleet benefits from a tracked, shareable config. The repo is
    # LOCAL-ONLY — no remote is added. The allowlist guarantees only coordination
    # files can ever be tracked (never member repos, service source, or secrets).
    echo ""
    if _fleet_dir_is_own_git_repo "$target_dir"; then
        echo "Fleet-root git repo: present"
    else
        if git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            log_warning "Fleet root is nested inside a parent git repo; creating a separate local-only coordination repo here."
        fi
        echo "Initializing fleet-root git repo (local-only, no remote)..."
        if git init -b main "$target_dir" >/dev/null 2>&1 || git init "$target_dir" >/dev/null 2>&1; then
            echo "✓ git init: $(basename "$target_dir")"
        else
            log_error "Could not git init fleet root: $target_dir (fleet ship needs a git root)"
            _fleet_init_status=1
        fi
    fi
    local _fleet_root_gi
    if _fleet_root_gi=$(create_fleet_gitignore "$target_dir"); then
        case "$_fleet_root_gi" in
            .gitignore) echo "✓ Created: $target_dir/.gitignore (coordination allowlist)" ;;
            .gitignore:empty-overwrite) echo "✓ Wrote coordination allowlist into empty $target_dir/.gitignore" ;;
            .gitignore.manifest) echo "✓ Created: $target_dir/.gitignore.manifest (existing .gitignore preserved — merge the allowlist as needed)" ;;
        esac
    else
        log_error "Could not write fleet-root .gitignore in $target_dir"
        _fleet_init_status=1
    fi

    # --- Bootstrap the reviewed selections (start_file guaranteed present) ---
    if [[ -f "$start_file" ]]; then
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

            local _init_rc
            _fleet_init_directory "$abs_path" "$has_git" "$create_repo_visibility"
            _init_rc=$?
            case $_init_rc in
                0)
                    init_count=$((init_count+1))
                    [[ -n "$create_repo_visibility" ]] && gh_ok_count=$((gh_ok_count+1))
                    ;;
                1)
                    init_failed_paths+=("$path")
                    ;;
                2)
                    init_count=$((init_count+1))
                    gh_failed_paths+=("$path")
                    ;;
                3)
                    missing_paths+=("$path")
                    ;;
            esac

            # Make the member Manifest-trackable: scaffold the same required
            # files `init repo` creates (VERSION/README/CHANGELOG/docs/.gitignore)
            # via the shared primitive — no second scaffolder. Run only when the
            # directory init succeeded (rc 0 = init ok, rc 2 = init ok but gh
            # failed); skip rc 1 (init failed) and rc 3 (path missing) so we
            # never cd into a broken/absent dir. No-clobber (existing member
            # files are preserved) and NO commit (files land uncommitted, parity
            # with `init repo`). Run in an isolated subshell with cwd+PROJECT_ROOT
            # set to the member so the README's git-derived fields resolve
            # against the member, not the fleet root (idiom: manifest-fleet-docs.sh).
            if [[ ( "$_init_rc" -eq 0 || "$_init_rc" -eq 2 ) ]] \
                && declare -F ensure_required_files >/dev/null 2>&1; then
                (
                    cd "$abs_path" || exit 0
                    export PROJECT_ROOT="$abs_path"
                    ensure_required_files "$abs_path" >/dev/null 2>&1
                ) || true
            fi
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
        local all_dirs _refresh_depth
        # Match Phase 1's adaptive depth so the refresh sees the same dirs (§7.3).
        _refresh_depth="$(manifest_fleet_resolve_depth auto "$target_dir")" || _refresh_depth=5
        all_dirs=$(discover_all_directories "$target_dir" "$_refresh_depth")
        if [[ -n "$all_dirs" ]]; then
            merge_start_tsv "$all_dirs" "$start_file" "$target_dir" "$_refresh_depth" > "${start_file}.tmp" 2>/dev/null
            mv "${start_file}.tmp" "$start_file"
            echo "✓ Updated: $start_file"
        fi

        local service_count=0
        while IFS=$'\t' read -r _n _p _t _h _u _b _v; do
            [[ -z "$_n" ]] && continue
            service_count=$((service_count+1))
        done <<< "$selected"
        echo ""
        echo "✓ Fleet inventory: $service_count service(s) in manifest.fleet.tsv"
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
# GITHUB TOPICS (opt-in; off while commented out)
# =============================================================================
# Derive GitHub topics from each member's dot-separated repo name and push
# the missing ones (additive-only) on `manifest update fleet -y`. Modes:
#   inner          fidence.service.accounting.avalara -> service, accounting
#   all-but-first  fidence.service.accounting.avalara -> service, accounting, avalara
#   all            every slug becomes a topic
# topics:
#   from_name: inner

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
# Fleet apply always requires a clean working tree: any service with
# uncommitted changes is refused at plan and apply time. This guarantee is
# unconditional and intentionally not configurable, so there is no
# validation: block here — config that advertised a toggle the CLI ignores
# was removed (see CLI TRACKER §2.8, following the require_expected_branch
# precedent).
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
            "manifest discover fleet [--depth N|auto] [--json] [--quiet]" \
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
            clone) cloned=$((cloned+1)) ;;
            pull)  pulled=$((pulled+1)) ;;
            fail)  failed=$((failed+1)) ;;
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
        total=$((total+1))
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
        total=$((total+1))
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
#   --depth N|auto Scan depth; auto deepens to repos found, capped (default: auto)
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
    local depth="auto"
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
                    "manifest update fleet [-y|--yes] [--dry-run] [--depth N|auto] [--json] [--quiet]" \
                    "Re-scan fleet membership and add newly discovered repositories." \
                    "Options" "  --dry-run    Explicit preview; do not modify manifest.fleet.config.yaml
  -y, --yes    Apply fleet membership updates
  --depth N|auto  Scan depth; auto deepens to the shallowest level with repos, capped (default: auto)
  --json       Output JSON summary
  --quiet, -q  Only output new repo lines"
                return 0
                ;;
            *) shift ;;
        esac
    done

    local root_dir="${MANIFEST_CLI_FLEET_ROOT:-$(pwd)}"
    # Resolve --depth (N|auto) to a concrete scan depth (§7.3). The JSON
    # fast-summary path below keeps its own intentionally shallow fixed probe.
    depth="$(manifest_fleet_resolve_depth "$depth" "$root_dir")" || return 1

    # --- JSON summary mode (fast, limited depth) ---
    if [[ "$json_output" == "true" ]]; then
        local discovered
        discovered=$(discover_fleet_repos "$root_dir" 3)  # Limited depth for speed

        local total=0 services=0 libraries=0 infra=0 tools=0
        while IFS=$'\t' read -r name path type rest; do
            [[ -z "$name" ]] && continue
            total=$((total+1))
            case "$type" in
                "service") services=$((services+1)) ;;
                "library") libraries=$((libraries+1)) ;;
                "infrastructure") infra=$((infra+1)) ;;
                "tool") tools=$((tools+1)) ;;
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

    # §9.1: an invalid topics.from_name fails loud BEFORE any mutation —
    # a typo must never silently disable topic projection.
    manifest_fleet_topics_mode "$config_file" >/dev/null || return 1

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

    # §9.1: project repo-name slugs onto GitHub topics (opt-in; silent no-op
    # when topics.from_name is unset).
    manifest_fleet_topics_run "$root_dir" "$config_file" "$dry_run" || return 1

    echo ""
}

# =============================================================================
# COMMAND: topics fleet
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_topics
# -----------------------------------------------------------------------------
# Direct entry to the §9.1 topics projection: preview the per-member topic
# delta by default, push it with -y. Runs the same single hook as `manifest
# update fleet` and the quiet post-ship pass — on demand, with full output.
# -----------------------------------------------------------------------------
fleet_topics() {
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                _render_help \
                    "manifest topics fleet [-y|--yes] [--dry-run]" \
                    "Project fleet repo-name slugs onto GitHub topics (additive-only)." \
                    "Options" "  --dry-run    Explicit preview; no GitHub writes
  -y, --yes    Push the missing topics"
                return 0
                ;;
            *)
                log_error "Unknown option for 'manifest topics fleet': $1"
                return 1
                ;;
        esac
    done

    if ! _fleet_require_initialized "topics"; then
        return 1
    fi

    local root_dir="${MANIFEST_CLI_FLEET_ROOT:-$(pwd)}"
    local config_file
    config_file=$(_fleet_resolve_config "$root_dir") || return 1

    local mode
    mode=$(manifest_fleet_topics_mode "$config_file") || return 1
    if [[ -z "$mode" ]]; then
        echo "Topics are off. Enable with topics.from_name in manifest.fleet.config.yaml"
        echo "(inner | all | all-but-first), or for this machine only:"
        echo "  manifest config set topics.from_name inner --layer global"
        return 0
    fi

    local dry_run=true
    [[ "$execution_mode" == "apply" ]] && dry_run=false

    manifest_fleet_topics_run "$root_dir" "$config_file" "$dry_run" "false" "manifest topics fleet -y" || return 1

    if [[ "$dry_run" == "true" ]]; then
        return "$(manifest_preview_exit_code)"
    fi
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

# A member whose release.strategy is "pr" must never be shipped directly by
# `manifest ship fleet`: its release has to land through a reviewed pull request
# (`manifest pr fleet ...`). This is the single self-describing config field
# `release.strategy` (values: none | direct | pr) — not a separate boolean knob.
# Returns 0 when the member is PR-gated, 1 otherwise.
_fleet_service_pr_gated() {
    local service="$1"
    local release_strategy
    release_strategy=$(get_fleet_service_property "$service" "release_strategy" "")
    [[ "$release_strategy" == "pr" ]]
}

_fleet_service_config_skip_reason() {
    local service="$1"
    local excluded release_enabled release_strategy

    excluded=$(get_fleet_service_property "$service" "excluded" "false")
    if [[ "$excluded" == "true" ]]; then
        echo "excluded"
        return 0
    fi

    # Direct fleet shipping must not inspect PR-gated members. They are
    # surfaced in the plan as a routing decision, then fail closed on apply.
    if _fleet_service_pr_gated "$service"; then
        echo "pr-gated"
        return 0
    fi

    release_enabled=$(get_fleet_service_property "$service" "release_enabled" "")
    if [[ -n "$release_enabled" ]] && is_falsy "$release_enabled"; then
        echo "release disabled"
        return 0
    fi

    release_strategy=$(get_fleet_service_property "$service" "release_strategy" "")
    case "$release_strategy" in
        none)
            echo "release strategy none"
            return 0
            ;;
        direct|"")
            return 1
            ;;
        *)
            echo "unsupported release strategy: $release_strategy"
            return 0
            ;;
    esac
}

_fleet_service_dirty_summary() {
    local path="$1"
    if declare -F manifest_git_changes_dirty_summary >/dev/null 2>&1; then
        manifest_git_changes_dirty_summary "$path"
        return 0
    fi

    [[ -n "$path" && -d "$path/.git" ]] || return 0
    local porcelain modified untracked
    porcelain=$(git -C "$path" status --porcelain 2>/dev/null \
        | awk '$2 != "formula/manifest.rb" && NF > 0 { print }' || true)
    [[ -n "$porcelain" ]] || return 0
    modified=$({ printf '%s\n' "$porcelain" | grep -cv '^??'; } 2>/dev/null || true)
    untracked=$({ printf '%s\n' "$porcelain" | grep -c '^??'; } 2>/dev/null || true)
    : "${modified:=0}" "${untracked:=0}"
    printf '%dm+%du' "$modified" "$untracked"
}

_fleet_service_has_release_changes() {
    local path="$1"
    [[ -n "$path" && -d "$path/.git" ]] || return 1

    if [[ -n "$(_fleet_service_dirty_summary "$path")" ]]; then
        return 0
    fi

    local current tag tag_commit head_commit
    current="$(_fleet_plan_current_version "$path")"
    [[ -n "$current" ]] || return 1

    if declare -F manifest_release_tag_name >/dev/null 2>&1; then
        tag="$(manifest_release_tag_name "$current")"
    else
        tag="v$current"
    fi

    if ! git -C "$path" rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null 2>&1; then
        return 0
    fi

    tag_commit="$(git -C "$path" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null || true)"
    head_commit="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    if [[ -z "$tag_commit" || -z "$head_commit" ]]; then
        return 0
    fi
    if [[ "$tag_commit" == "$head_commit" ]]; then
        return 1
    fi

    local changed_files
    changed_files="$(git -C "$path" diff --name-only "$tag_commit..$head_commit" 2>/dev/null \
        | awk '$0 != "formula/manifest.rb" && NF > 0 { print }' || true)"
    if [[ -n "$changed_files" ]]; then
        return 0
    fi

    return 1
}

_fleet_service_static_release_reason() {
    local service="$1"
    local path="$2"
    local config_skip

    if config_skip=$(_fleet_service_config_skip_reason "$service"); then
        echo "$config_skip"
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
    if [[ -n "$release_enabled" ]] && is_truthy "$release_enabled"; then
        echo "release enabled"
        return 0
    fi

    local release_strategy
    release_strategy=$(get_fleet_service_property "$service" "release_strategy" "")
    case "$release_strategy" in
        direct)
            echo "release strategy direct"
            return 0
            ;;
        "")
            ;;
        *)
            # Unsupported values are handled by _fleet_service_config_skip_reason
            # before any repo probes; this branch is kept as a defensive fallback.
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

_fleet_service_release_reason() {
    local service="$1"
    local path="$2"
    local force_bump="${3:-false}"
    local reason

    if ! reason=$(_fleet_service_static_release_reason "$service" "$path"); then
        echo "$reason"
        return 1
    fi
    # --force-bump bypasses ONLY the dynamic "no changes since tag" gate. The
    # static/policy gates above (excluded, pr-gated, release-disabled, no VERSION,
    # tap, fleet root) are always honored — force-bump never ships those.
    if [[ "$force_bump" != "true" ]] && ! _fleet_service_has_release_changes "$path"; then
        echo "no changes"
        return 1
    fi

    echo "$reason"
    return 0
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
    local force_bump="${1:-false}"
    local failed=()
    local service path reason
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path=$(get_fleet_service_property "$service" "path")
        if ! reason=$(_fleet_service_release_reason "$service" "$path" "$force_bump"); then
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
    local force_bump="${1:-false}"
    local failed=0
    local service path reason
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path=$(get_fleet_service_property "$service" "path")
        if ! reason=$(_fleet_service_release_reason "$service" "$path" "$force_bump"); then
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

# Fail-closed gate: `manifest ship fleet` must never directly ship a PR-gated
# member (release.strategy: pr) — its release has to land through a reviewed
# pull request. If any selected member is PR-gated, apply refuses before any
# mutation and emits a structured error plus the exact `manifest pr fleet ... -y`
# replay command. The preview (_fleet_ship_plan) already lists these members so
# the refusal is never a surprise. Skipping them silently would leave the fleet
# half-shipped, which §1.1 exists to prevent.
_fleet_preflight_no_pr_gated() {
    local gated=()
    local service path
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        if _fleet_service_pr_gated "$service"; then
            path=$(get_fleet_service_property "$service" "path")
            gated+=("$(_fleet_plan_service_display_name "$service" "$path") ($path)")
        fi
    done

    [[ ${#gated[@]} -eq 0 ]] && return 0

    log_error "Pre-flight: ${#gated[@]} fleet member(s) are PR-gated (release.strategy: pr) and cannot be shipped directly:"
    local entry
    for entry in "${gated[@]}"; do
        echo "  - $entry"
    done
    echo ""
    echo "Reason:      a PR-gated member's release must land through a reviewed pull request,"
    echo "             not a direct \`manifest ship fleet\` tag-and-push."
    echo "Replay:      manifest pr fleet -y"
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

# Branch cell for the ship plan: the member's ACTUAL current branch — matching
# the apply guard (manifest_assert_release_branch), the --json output, and
# `fleet status`, NOT the configured target branch (which is always the default
# and so could never reveal a checkout on the wrong branch). Releaseable members
# whose HEAD is off the release branch get a trailing "!" so the preview shows
# what apply will refuse. Non-git paths render as "—"; detached HEAD as
# "detached". Long names are truncated to keep the column aligned.
_fleet_plan_branch_cell() {
    local path="$1" releaseable="$2"
    local expected="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
        echo "—"
        return
    fi
    local cur
    cur="$(git -C "$path" branch --show-current 2>/dev/null)"
    [[ -z "$cur" ]] && cur="detached"
    if [[ "$releaseable" == "true" && "$cur" != "$expected" ]]; then
        echo "${cur:0:10}!"
    else
        echo "${cur:0:12}"
    fi
}

_fleet_plan_current_version() {
    local path="$1"
    [[ -n "$path" && -f "$path/VERSION" ]] || return 0
    tr -d '[:space:]' < "$path/VERSION" 2>/dev/null || true
}

_fleet_plan_version_surface_report() {
    local labels_name="$1"
    local paths_name="$2"
    local -n _surface_labels="$labels_name"
    local -n _surface_paths="$paths_name"

    [[ "${#_surface_paths[@]}" -gt 0 ]] || return 0
    declare -F manifest_version_surface_scan >/dev/null 2>&1 || return 0
    manifest_version_surfaces_enabled || return 0

    local mode
    mode="$(manifest_version_surface_notification_mode)"
    [[ "$mode" != "off" ]] || return 0

    local total_noncanonical=0 repos_with_surfaces=0
    local rows=()
    local i path label id role kind relationship rel_file version_value
    for i in "${!_surface_paths[@]}"; do
        path="${_surface_paths[$i]}"
        label="${_surface_labels[$i]}"
        [[ -d "$path" ]] || continue
        local repo_noncanonical=0 repo_rows=()
        while IFS=$'\t' read -r id role kind relationship rel_file version_value; do
            [[ -n "$rel_file" ]] || continue
            [[ "$relationship" != "canonical" ]] || continue
            repo_noncanonical=$((repo_noncanonical + 1))
            repo_rows+=("$(printf "    %-30s %-32s %-18s %-8s %s" "$label" "$rel_file" "$role" "$kind" "${version_value:-unknown}")")
        done < <(manifest_version_surface_scan "$path" 2>/dev/null || true)
        if [[ "$repo_noncanonical" -gt 0 ]]; then
            repos_with_surfaces=$((repos_with_surfaces + 1))
            total_noncanonical=$((total_noncanonical + repo_noncanonical))
            if [[ "$mode" == "list" ]]; then
                rows+=("${repo_rows[@]}")
            fi
        fi
    done

    [[ "$total_noncanonical" -gt 0 ]] || return 0
    echo ""
    echo "Version surfaces: ${total_noncanonical} noncanonical detected across ${repos_with_surfaces} releaseable repo(s)"
    echo "  Read-only in this preview; only explicit version.sync targets are rewritten during ship."
    if [[ "$mode" == "list" && "${#rows[@]}" -gt 0 ]]; then
        local row
        printf "    %-30s %-32s %-18s %-8s %s\n" "Service" "Path" "Role" "Kind" "Version"
        for row in "${rows[@]}"; do
            printf "%s\n" "$row"
        done
    fi
}

_fleet_ship_plan() {
    local increment_type="$1"
    local local_only="$2"
    local force_bump="${3:-false}"
    local releaseable_count=0
    local skipped_count=0

    echo ""
    echo "Fleet ship plan ($increment_type)"
    echo ""
    echo "Included repositories"
    printf '%-30s %-12s %-12s %-15s %-7s %-9s %-13s %s\n' "Service" "Type" "Branch" "Version" "Dirty" "Effect" "Decision" "Path / reason"
    printf '%-30s %-12s %-12s %-15s %-7s %-9s %-13s %s\n' "-------" "----" "------" "-------" "-----" "------" "--------" "-------------"

    local service path reason effect decision type branch display_name dirty version current next config_skip
    local offbranch_count=0
    local pr_gated_count=0
    # Salient inputs for the fleet plan fingerprint: the increment type, the
    # local/remote mode, and each releaseable member's name + version transition.
    # Same shape -> same digest, so a preview and its apply can be compared.
    local fp_parts=("ship-fleet" "$increment_type" "$local_only")
    local surface_labels=()
    local surface_paths=()
    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path=$(get_fleet_service_property "$service" "path")
        type=$(get_fleet_service_property "$service" "type" "service")
        display_name=$(_fleet_plan_service_display_name "$service" "$path")
        if config_skip=$(_fleet_service_config_skip_reason "$service"); then
            branch="—"
            version="—"
            dirty=""
            if [[ "$config_skip" == "pr-gated" ]]; then
                # PR-gated members are listed separately from plain skips: apply will
                # refuse them (fail-closed) and route their release through review.
                pr_gated_count=$((pr_gated_count + 1))
                printf '%-30s %-12s %-12s %-15s %-7s %-9s %-13s %s\n' "$display_name" "$type" "$branch" "$version" "$dirty" "pr-gate" "needs PR" "$path (release.strategy: pr)"
            else
                skipped_count=$((skipped_count + 1))
                printf '%-30s %-12s %-12s %-15s %-7s %-9s %-13s %s\n' "$display_name" "$type" "$branch" "$version" "$dirty" "read" "skip" "$path ($config_skip)"
            fi
            continue
        fi

        dirty=$(_fleet_service_dirty_summary "$path")
        current="$(_fleet_plan_current_version "$path")"
        if reason=$(_fleet_service_release_reason "$service" "$path" "$force_bump"); then
            releaseable_count=$((releaseable_count + 1))
            effect="release"
            if [[ "$force_bump" == "true" ]]; then
                decision="would force"
            elif [[ "$local_only" == "true" ]]; then
                decision="would local"
            else
                decision="would ship"
            fi
            # Actual current branch; a trailing "!" marks members apply will refuse.
            branch=$(_fleet_plan_branch_cell "$path" true)
            [[ "$branch" == *"!" ]] && offbranch_count=$((offbranch_count + 1))
            # Per-member next version, computed against the member's own VERSION.
            next="$( (cd "$path" 2>/dev/null && get_next_version "$increment_type" 2>/dev/null) || echo "")"
            if [[ -n "$current" && -n "$next" ]]; then
                version="${current}->${next}"
            elif [[ -n "$current" ]]; then
                version="${current}->?"
            else
                version="—"
            fi
            printf '%-30s %-12s %-12s %-15s %-7s %-9s %-13s %s\n' "$display_name" "$type" "$branch" "$version" "$dirty" "$effect" "$decision" "$path"
            fp_parts+=("${display_name}:${version}")
            surface_labels+=("$display_name")
            surface_paths+=("$path")
        else
            skipped_count=$((skipped_count + 1))
            # Skipped members never ship, so no off-branch marker is applied.
            branch=$(_fleet_plan_branch_cell "$path" false)
            version="${current:-—}"
            printf '%-30s %-12s %-12s %-15s %-7s %-9s %-13s %s\n' "$display_name" "$type" "$branch" "$version" "$dirty" "read" "skip" "$path ($reason)"
        fi
    done

    echo ""
    echo "Plan summary: $releaseable_count releaseable, $pr_gated_count pr-gated, $skipped_count skipped"
    if [[ "$force_bump" == "true" ]]; then
        echo "force-bump: members with no changes since their tag are included (forward-only — new commit + tag, no history rewrite). Policy-gated members (pr-gated, release-disabled) are still skipped."
    fi
    _fleet_plan_version_surface_report surface_labels surface_paths
    # Fleet plan fingerprint, rendered through the shared plan-table renderer so
    # it reads identically to the single-repo preview. Exported for the caller to
    # persist (preview) and re-compare (apply) — CLI tracker §2.2.
    MANIFEST_CLI_FLEET_PLAN_FINGERPRINT="$(manifest_plan_fingerprint "${fp_parts[@]}")"
    manifest_plan_render_fingerprint_line "$MANIFEST_CLI_FLEET_PLAN_FINGERPRINT"
    if [[ $pr_gated_count -gt 0 ]]; then
        echo ""
        echo "⚠️  ${pr_gated_count} member(s) shown 'needs PR' are PR-gated (release.strategy: pr)."
        echo "    Apply refuses these (fail-closed): a PR-gated release must land through a"
        echo "    reviewed pull request, not a direct ship. Release them with:"
        echo "        manifest pr fleet -y"
    fi
    if [[ $offbranch_count -gt 0 ]]; then
        local _rel_branch="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
        echo ""
        echo "⚠️  ${offbranch_count} releaseable member(s) marked '!' have HEAD off the release branch ('${_rel_branch}')."
        echo "    Apply refuses these (manifest_assert_release_branch): the version commit and tag"
        echo "    would land off '${_rel_branch}'. Move the work onto '${_rel_branch}' before re-running with -y."
    fi
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
# -----------------------------------------------------------------------------
# Single-flight fleet lock
# -----------------------------------------------------------------------------
# Serialize concurrent `manifest ship fleet ... -y` runs in the same workspace
# so two invocations cannot race on shared per-member state (VERSION bumps, tag
# creation, Homebrew tap formula publishes). Portable mkdir-based mutex — `flock` is
# absent on stock macOS. A lock left by a dead holder is reclaimed; a lock held
# by a live process — including one on another host when $HOME is on shared
# storage — is never broken.

# Lock dir for the current workspace, keyed by the canonicalized fleet root so
# that `.`, an absolute path, and a symlinked path all resolve to one lock.
_fleet_lock_dir_path() {
    local ws_root hash
    ws_root="$(cd "${MANIFEST_CLI_FLEET_ROOT:-$PWD}" 2>/dev/null && pwd -P)" \
        || ws_root="${MANIFEST_CLI_FLEET_ROOT:-$PWD}"
    hash="$(printf '%s' "$ws_root" | _manifest_hash_short)"
    printf '%s/fleet-%s.lock.d' "$(manifest_install_paths_locks_dir)" "${hash:0:16}"
}

# Process start-time token — distinguishes a live holder from a recycled PID.
# Linux: starttime (field 22 of /proc/<pid>/stat). The comm field (2) can
# contain spaces/parens, so parse the fields AFTER the final ')' — starttime is
# then the 20th. macOS/BSD: ps lstart. Empty if unknown.
_fleet_proc_start_token() {
    local pid="$1"
    if [ -r "/proc/$pid/stat" ]; then
        sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $20}'
    else
        ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' '
    fi
}

# Modification time of a path in epoch seconds.
# GNU-first: the wrapper forces coreutils' gnubin onto PATH on macOS, so
# `stat -c %Y` is the clean mtime there. GNU MUST come first — BSD `stat -f %m`
# run first on Linux mis-parses `%m` as a filename, dumps garbage and exits 1 —
# so the BSD form is only a fallback, for contexts that ran without the prepend
# (a module sourced in isolation) or native BSDs without GNU stat.
_fleet_dir_mtime_epoch() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# 0 if the recorded holder is a live process on THIS host (do not break it).
# 1 if reclaimable (abandoned). A holder on a different host is treated as alive
# (returns 0) so shared-$HOME / NFS setups are never broken cross-host.
_fleet_lock_holder_alive() {
    local lock_dir="$1"
    local holder="$lock_dir/holder"
    if [ ! -r "$holder" ]; then
        # No holder file. Either a winner that hasn't written its holder yet
        # (the mkdir-then-write window) or a crash before the write. Treat a
        # freshly-created lock dir as alive for a short grace period so a racer
        # can never break a lock that was just legitimately acquired; only a
        # holder-less dir older than the grace window is abandoned/reclaimable.
        local grace="${MANIFEST_CLI_FLEET_LOCK_GRACE_SECONDS:-15}"
        local mtime now
        mtime="$(_fleet_dir_mtime_epoch "$lock_dir")"
        now="$(date +%s 2>/dev/null)"
        if [ -n "$mtime" ] && [ -n "$now" ] && [ "$((now - mtime))" -lt "$grace" ]; then
            return 0   # fresh, holder write likely in flight -> treat as alive
        fi
        return 1       # old and holder-less -> abandoned, reclaimable
    fi
    local h_pid h_host h_token now_token
    h_pid="$(sed -n 's/^pid=//p' "$holder" 2>/dev/null)"
    h_host="$(sed -n 's/^host=//p' "$holder" 2>/dev/null)"
    h_token="$(sed -n 's/^start=//p' "$holder" 2>/dev/null)"
    [ "$h_host" = "$(hostname 2>/dev/null)" ] || return 0   # cross-host: never break
    [ -n "$h_pid" ] || return 1
    kill -0 "$h_pid" 2>/dev/null || return 1                # pid gone: dead
    now_token="$(_fleet_proc_start_token "$h_pid")"
    [ "$now_token" = "$h_token" ]                            # mismatch: pid reused
}

_fleet_lock_write_holder() {
    local lock_dir="$1"
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=%s\n' "$(_fleet_proc_start_token "$$")"
        printf 'since=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    } > "$lock_dir/holder" 2>/dev/null || true
}

_fleet_lock_acquire() {
    local lock_dir="$1"
    local attempts=0
    local max_attempts="${MANIFEST_CLI_FLEET_LOCK_ATTEMPTS:-50}"
    mkdir -p "$(dirname "$lock_dir")" 2>/dev/null || true
    while ! mkdir "$lock_dir" 2>/dev/null; do
        if ! _fleet_lock_holder_alive "$lock_dir"; then
            # Snapshot the holder we judged dead, then reclaim by renaming the
            # dir aside (atomic; only one racer's mv can succeed — the source
            # vanishes for the others). After the rename, re-verify: if the
            # holder changed under us (someone acquired in the gap), we grabbed
            # a LIVE lock — restore it and retry instead of deleting it.
            local stale="${lock_dir}.stale.$$"
            local before_holder after_holder
            before_holder="$(cat "$lock_dir/holder" 2>/dev/null || echo "")"
            if mv "$lock_dir" "$stale" 2>/dev/null; then
                after_holder="$(cat "$stale/holder" 2>/dev/null || echo "")"
                if [ "$after_holder" != "$before_holder" ] && _fleet_lock_holder_alive "$stale"; then
                    mv "$stale" "$lock_dir" 2>/dev/null || rm -rf "$stale" 2>/dev/null
                else
                    rm -rf "$stale" 2>/dev/null
                    log_warning "Reclaimed a stale fleet lock (previous holder is gone)."
                    continue
                fi
            fi
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$max_attempts" ]; then
            log_error "Another fleet ship is already running for this workspace."
            if [ -r "$lock_dir/holder" ]; then
                log_error "  Lock holder: $(tr '\n' ' ' < "$lock_dir/holder" 2>/dev/null)"
            fi
            log_error "  Lock: $lock_dir"
            log_error "  If no other run is active, remove that directory and retry."
            return 1
        fi
        sleep 0.1
    done
    _fleet_lock_write_holder "$lock_dir"
    return 0
}

_fleet_lock_release() {
    local lock_dir="$1"
    [ -n "$lock_dir" ] && [ -d "$lock_dir" ] && rm -rf "$lock_dir" 2>/dev/null || true
}

# PR orchestration belongs under `manifest pr fleet ...`, never here.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Function: _fleet_next_version (internal)
# -----------------------------------------------------------------------------
# Compute the next FLEET-level version for a versioning scheme.
#   $1 scheme         none | date | semver | increment
#   $2 current        current FLEET_VERSION value (may be empty)
#   $3 increment_type patch | minor | major | revision (used by semver)
# Echoes the next version; echoes nothing for scheme=none.
# -----------------------------------------------------------------------------
_fleet_next_version() {
    local scheme="$1" current="$2" increment_type="${3:-patch}"
    case "$scheme" in
        none|"")
            return 0
            ;;
        date)
            local today
            today="$(date -u +%Y.%m.%d)"
            if [[ "$current" == "$today" ]]; then
                echo "${today}.1"
            elif [[ "$current" == "$today".* ]]; then
                local counter="${current##*.}"
                if [[ "$counter" =~ ^[0-9]+$ ]]; then
                    echo "${today}.$((counter + 1))"
                else
                    echo "${today}.1"
                fi
            else
                echo "$today"
            fi
            ;;
        increment)
            if [[ "$current" =~ ^[0-9]+$ ]]; then
                echo "$((current + 1))"
            else
                echo "1"
            fi
            ;;
        semver|*)
            local major minor patch revision
            IFS='.' read -r major minor patch revision <<< "${current:-0.0.0}"
            major=${major:-0}; minor=${minor:-0}; patch=${patch:-0}; revision=${revision:-0}
            case "$increment_type" in
                minor) minor=$((minor + 1)); patch=0 ;;
                major) major=$((major + 1)); minor=0; patch=0 ;;
                revision) revision=$((revision + 1)) ;;
                *) patch=$((patch + 1)) ;;
            esac
            if [[ "$revision" -gt 0 ]]; then
                echo "$major.$minor.$patch.$revision"
            else
                echo "$major.$minor.$patch"
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Function: _fleet_root_release (internal)
# -----------------------------------------------------------------------------
# After a successful fleet ship, bump + commit the fleet-level version file at
# the coordination root. SECURITY: stages ONLY coordination files (by name) and
# verifies the staged set before committing — never `git add .`/-A — so a dirty
# root can never sweep member repos, source, or secrets into the commit.
#
#   $1 increment_type   $2 execution_mode (preview|apply)
#   $3 local_only (true|false)   $4 completed_count (members that shipped)
# Idempotent: no-op when scheme=none, no member shipped, or the version is
# unchanged. Returns non-zero on real failure (caller treats it as a warning —
# members have already shipped).
# -----------------------------------------------------------------------------
_fleet_root_release() {
    local increment_type="$1" execution_mode="$2" local_only="$3" completed_count="${4:-0}"
    local scheme="${MANIFEST_CLI_FLEET_VERSIONING:-none}"
    local root="${MANIFEST_CLI_FLEET_ROOT:-$PWD}"

    [[ "$scheme" != "none" ]] || return 0
    [[ "${completed_count:-0}" -gt 0 ]] || return 0

    local version_name version_file current next
    version_name="$(get_yaml_value "${MANIFEST_CLI_FLEET_CONFIG_FILE:-$root/manifest.fleet.config.yaml}" ".fleet.version_file" "${MANIFEST_CLI_FLEET_DEFAULT_VERSION_FILE:-FLEET_VERSION}")"
    version_file="$root/$version_name"
    current="${MANIFEST_CLI_FLEET_VERSION:-}"
    next="$(_fleet_next_version "$scheme" "$current" "$increment_type")"

    [[ -n "$next" && "$next" != "$current" ]] || return 0

    if [[ "$execution_mode" != "apply" ]]; then
        echo "  - fleet root: would bump fleet version ${current:-(unset)} → $next (commit $version_name)"
        return 0
    fi

    # Ensure the root is a coordination git repo with the allowlist in place.
    if ! _fleet_dir_is_own_git_repo "$root"; then
        git init -b main "$root" >/dev/null 2>&1 || git init "$root" >/dev/null 2>&1 || {
            log_error "Fleet-root release: could not git init $root"; return 1; }
    fi
    create_fleet_gitignore "$root" >/dev/null || {
        log_error "Fleet-root release: could not write allowlist .gitignore"; return 1; }

    # Write the version file atomically (temp + rename).
    local tmp="${version_file}.tmp.$$"
    if ! printf '%s\n' "$next" > "$tmp" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null
        log_error "Fleet-root release: could not write $version_name"; return 1
    fi
    mv -f "$tmp" "$version_file" 2>/dev/null || {
        rm -f "$tmp" 2>/dev/null; log_error "Fleet-root release: rename of $version_name failed"; return 1; }

    # SECURITY: stage ONLY coordination files, by name. The version file is
    # force-added (it is coordination by definition, even under a custom name);
    # everything else is left to the allowlist.
    local f
    for f in .gitignore manifest.fleet.config.yaml manifest.fleet.tsv CHANGELOG_FLEET.md; do
        [[ -f "$root/$f" ]] && git -C "$root" add -- "$f" 2>/dev/null
    done
    [[ -f "$version_file" ]] && git -C "$root" add -f -- "$version_name" 2>/dev/null

    # Defense-in-depth: refuse to commit if ANYTHING outside the allowlist is staged.
    local staged bad="" line
    staged="$(git -C "$root" diff --cached --name-only 2>/dev/null)"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        case "$line" in
            .gitignore|"$version_name"|manifest.fleet.config.yaml|manifest.fleet.tsv|CHANGELOG_FLEET.md) ;;
            *) bad="$bad $line" ;;
        esac
    done <<< "$staged"
    if [[ -n "$bad" ]]; then
        log_error "Fleet-root release ABORTED: non-coordination files staged at the root:$bad"
        log_error "Refusing to commit — this would leak workspace content into the coordination repo."
        git -C "$root" reset -q >/dev/null 2>&1 || true
        return 1
    fi

    # Nothing staged (version file unchanged on disk) -> idempotent skip.
    [[ -n "$staged" ]] || return 0

    if ! git -C "$root" commit -q -m "Bump fleet version to $next" >/dev/null 2>&1; then
        log_error "Fleet-root release: commit failed (is git user.name/user.email configured?)"
        return 1
    fi
    echo "  - fleet root: committed fleet version $next"

    # Push only on a non-local ship, and only when a remote is configured.
    if [[ "$local_only" != "true" ]] && git -C "$root" remote get-url origin >/dev/null 2>&1; then
        local branch
        branch="$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null || echo main)"
        if git -C "$root" push origin "$branch" >/dev/null 2>&1; then
            echo "  - fleet root: pushed $branch"
        else
            log_warning "Fleet-root release: push failed; the fleet version commit is local."
        fi
    fi
    return 0
}

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
    local force_bump=false
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
            --force-bump)
                force_bump=true
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
  --force-bump              Ship every release-eligible member even with no changes
                            since its tag (forward-only; honors pr-gated/disabled)

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
        _fleet_ship_plan "$increment_type" "$local_only" "$force_bump"
        _fleet_root_release "$increment_type" "preview" "$local_only" 1
        # Stash the fingerprint the user is reading so a later apply can warn if
        # the fleet plan drifted between this preview and that apply.
        manifest_plan_fingerprint_persist "ship-fleet" "${MANIFEST_CLI_FLEET_PLAN_FINGERPRINT:-}" "${MANIFEST_CLI_FLEET_ROOT:-$PWD}"
        local replay_command="manifest ship fleet $increment_type"
        [[ "$local_only" == "true" ]] && replay_command="$replay_command --local"
        manifest_execution_footer "$replay_command -y"
        # Preview-without-consent exit code: 0 by default, or the distinct code
        # when preview.exit_code=distinct (CLI tracker §2.2).
        return "$(manifest_preview_exit_code)"
    fi

    echo "Starting fleet ship workflow ($increment_type)"
    _fleet_scope_block
    _fleet_ship_plan "$increment_type" "$local_only" "$force_bump"
    # Warn (never block) if the fleet plan drifted since the preview.
    manifest_plan_fingerprint_warn_on_drift "ship-fleet" "${MANIFEST_CLI_FLEET_PLAN_FINGERPRINT:-}" "${MANIFEST_CLI_FLEET_ROOT:-$PWD}"
    echo ""

    if ! _fleet_preflight_no_pr_gated; then
        return 1
    fi

    if ! _fleet_preflight_git_writability "$force_bump"; then
        return 1
    fi

    if ! _fleet_preflight_on_default_branch "$force_bump"; then
        return 1
    fi

    # Single-flight: only one fleet ship may apply in this workspace at a time.
    # Acquired only on the apply path (preview returned above) and only after
    # the read-only pre-flights pass.
    local fleet_lock status_dir=""
    fleet_lock="$(_fleet_lock_dir_path)"
    if ! _fleet_lock_acquire "$fleet_lock"; then
        return 1
    fi
    # Release the lock and clean scratch on ANY exit from this function. RETURN
    # is function-scoped (functrace is off) so it never clobbers the CLI's
    # top-level traps. INT/TERM additionally re-raise so Ctrl-C still terminates
    # with the correct status. This also fixes a pre-existing status_dir leak on
    # signal.
    trap '_fleet_lock_release "${fleet_lock:-}"; [ -n "${status_dir:-}" ] && rm -rf "${status_dir}" 2>/dev/null' RETURN
    trap '_fleet_lock_release "${fleet_lock:-}"; [ -n "${status_dir:-}" ] && rm -rf "${status_dir}" 2>/dev/null; trap - INT; kill -INT $$' INT
    trap '_fleet_lock_release "${fleet_lock:-}"; [ -n "${status_dir:-}" ] && rm -rf "${status_dir}" 2>/dev/null; trap - TERM; kill -TERM $$' TERM
    # SIGHUP = the controlling terminal/tab was closed (the common IDE "interrupt").
    # Without this the lock would leak until the next ship's stale-reclaim; release
    # it promptly here too. See CLI tracker §8.x (interrupted-ship robustness).
    trap '_fleet_lock_release "${fleet_lock:-}"; [ -n "${status_dir:-}" ] && rm -rf "${status_dir}" 2>/dev/null; trap - HUP; kill -HUP $$' HUP

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
        if ! reason=$(_fleet_service_release_reason "$service" "$path" "$force_bump"); then
            echo "  - $service: skipped ($reason)"
            skipped+=("$service|$path|$reason")
            continue
        fi
        if [[ "$force_bump" == "true" ]]; then
            echo "  - $service: force-bumping $increment_type"
        else
            echo "  - $service: shipping $increment_type"
        fi
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
            # Tag this member's apply-event audit record (§5.8) as fleet-sourced
            # so per-member applies are distinguishable from a direct ship repo.
            MANIFEST_CLI_AUDIT_SOURCE="cli-fleet"
            export MANIFEST_CLI_AUDIT_SOURCE
            # Forced members must carry --force-bump into the per-member ship, or
            # the repo-level gate (Commit 1) would re-skip a clean, at-tag member.
            member_ship_args=("$increment_type" "-y")
            [[ "$local_only" == "true" ]] && member_ship_args+=("--local")
            [[ "$force_bump" == "true" ]] && member_ship_args+=("--force-bump")
            manifest_ship_repo "${member_ship_args[@]}"
        )
        rc=$?
        if [[ $rc -ne 0 ]]; then
            failed_service="$service"
            failed_path="$path"
            failed_status_file="$status_file"
            for ((rem_idx=idx; rem_idx<${#member_list[@]}; rem_idx++)); do
                rem="${member_list[$rem_idx]}"
                rem_path=$(get_fleet_service_property "$rem" "path")
                if rem_reason=$(_fleet_service_release_reason "$rem" "$rem_path" "$force_bump"); then
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

    # Fleet-level version bump + commit at the coordination root (members done).
    # A failure here is a warning, not fatal: member releases have already applied.
    if ! _fleet_root_release "$increment_type" "apply" "$local_only" "${#completed[@]}"; then
        log_warning "Fleet-root version bump did not complete; member releases already applied."
    fi

    _fleet_ship_topics_pass "$local_only"

    echo "✅ Fleet ship workflow complete."
}

# -----------------------------------------------------------------------------
# Function: _fleet_ship_topics_pass
# -----------------------------------------------------------------------------
# §9.1: with topics enabled (yaml key or env override), groom GitHub topics at
# the end of a completed fleet ship — quiet: one line when something changed
# or failed, nothing otherwise. Skipped for --local ships (no remote writes
# were consented to). Post-release metadata grooming never fails a completed
# ship; an invalid topics.from_name still logs loud via the mode probe.
#
# ARGUMENTS:
#   $1 - local_only flag from the ship ("true" = skip)
# -----------------------------------------------------------------------------
_fleet_ship_topics_pass() {
    local local_only="${1:-false}"
    [[ "$local_only" == "true" ]] && return 0

    local topics_root topics_config
    topics_root="${MANIFEST_CLI_FLEET_ROOT:-$PWD}"
    topics_config=$(_fleet_resolve_config "$topics_root" 2>/dev/null) || topics_config=""
    [[ -n "$topics_config" ]] || return 0

    manifest_fleet_topics_run "$topics_root" "$topics_config" "false" "true" || true
    return 0
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
        if ! reason=$(_fleet_service_static_release_reason "$service" "$path"); then
            # Includes static target exclusions such as "not a git repo",
            # "missing path", "release disabled", and "excluded". Resume then
            # runs its own per-repo probe, because stranded release state can be
            # clean except for formula-only files that ship intentionally skips.
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
        add|discover|docs|init|prep|pr|ship|start|status|sync|update|validate)
            local replacement
            case "$subcommand" in
                add)        replacement="manifest add fleet" ;;
                discover)   replacement="manifest discover fleet" ;;
                docs)       replacement="manifest docs fleet" ;;
                init|start) replacement="manifest init fleet" ;;
                prep|sync)  replacement="manifest prep fleet" ;;
                pr)         replacement="manifest pr fleet" ;;
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
  manifest discover fleet       Preview fleet membership discovery
  manifest update fleet         Re-scan and add new repos
  manifest refresh fleet        Re-scan + regenerate docs
  manifest validate fleet       Validate fleet configuration
  manifest add fleet <path>     Add a service to the fleet
  manifest docs fleet           Generate fleet documentation
  manifest topics fleet         Project repo-name slugs onto GitHub topics
  manifest pr fleet             Fleet-wide PR operations
  manifest ship fleet <bump>    Coordinated release

COMMAND DETAILS:

  manifest init fleet [options]
    Two-phase fleet setup. Scans with a depth guardrail, then asks how deep
    repos should be under each top-level folder before writing manifest.fleet.tsv.
    Options:
      --depth N|auto     Scan depth; auto deepens to repos found, capped (default: auto)
      --all-folders      Write every scanned folder to manifest.fleet.tsv
      --name, -n NAME    Fleet name
      --force, -f        Overwrite generated files
      --dry-run          Preview files and discovery without writing

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
      --depth N|auto     Scan depth; auto deepens to repos found, capped (default: auto)
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

  manifest ship fleet [patch|minor|major|revision]|resume [options]
    Highest-level coordinated fleet workflow.
    Options:
      --dry-run          Explicit preview; no writes, commits, tags, or pushes
      -y, --yes          Apply the fleet release plan
      --local            With -y, local release prep only
      --noprep           Skip per-service prep step (requires clean trees)
      --explain          Show the built-in recipe definition without running it
    PR flags (--safe, --method, --force, --no-delete-branch, --draft) belong
    under 'manifest pr fleet ...'.

  manifest topics fleet [-y|--yes] [--dry-run]
    Project fleet repo-name slugs onto GitHub topics (additive-only; §9.1).
    Preview by default; -y pushes the missing topics. Requires topics.from_name
    (inner | all | all-but-first) in manifest.fleet.config.yaml, or host-local:
      manifest config set topics.from_name inner --layer global
    With topics enabled, 'manifest ship fleet -y' also runs this quietly after
    a completed ship.

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
