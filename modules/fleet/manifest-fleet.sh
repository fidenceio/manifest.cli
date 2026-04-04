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
# COMMANDS:
#   manifest fleet init      - Initialize a new fleet
#   manifest fleet status    - Show fleet status
#   manifest fleet discover  - Discover repos in workspace
#   manifest fleet add       - Add a service to fleet
#   manifest fleet remove    - Remove a service from fleet
#   manifest fleet sync      - Clone/pull all services
#   manifest fleet prep        - Coordinated version bump
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
        log_error "  1. Run from a directory containing manifest.fleet.yaml"
        log_error "  2. Run 'manifest fleet init' to create a new fleet"
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
        echo "  manifest fleet init"
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
    echo "  manifest fleet update       - Add newly discovered repos"
    echo "  manifest fleet sync         - Clone missing, pull existing"
    echo "  manifest fleet prep patch   - Bump all services"
    echo "  manifest fleet discover     - Preview new/missing repos"
}

# -----------------------------------------------------------------------------
# Function: _fleet_status_json (internal)
# -----------------------------------------------------------------------------
# Outputs fleet status in JSON format.
# -----------------------------------------------------------------------------
_fleet_status_json() {
    echo "{"
    echo "  \"fleet\": {"
    echo "    \"name\": \"$MANIFEST_FLEET_NAME\","
    echo "    \"root\": \"$MANIFEST_FLEET_ROOT\","
    echo "    \"version\": \"${MANIFEST_FLEET_VERSION:-null}\","
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

        echo -n "    {\"name\": \"$service\", \"type\": \"$type\", \"version\": \"$version\", \"branch\": \"$branch\", \"status\": \"$status\"}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# =============================================================================
# COMMAND: fleet init
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_init
# -----------------------------------------------------------------------------
# Initializes a new fleet in the current directory.
#
# BEHAVIOR:
#   1. If fleet already exists (no --force), routes to fleet_update
#   2. Creates skeleton manifest.fleet.yaml (fleet metadata, operations, etc.)
#   3. Creates .env.manifest.local with fleet settings
#   4. Calls fleet_update to discover and populate services
#   5. Validates the configuration
#
# ARGUMENTS:
#   --name, -n NAME     Fleet name (prompted if not provided)
#   --template, -t      Use minimal template (no comments)
#   --force, -f         Overwrite existing manifest.fleet.yaml
#
# EXAMPLE:
#   manifest fleet init
#   manifest fleet init --name "my-platform"
# -----------------------------------------------------------------------------
fleet_init() {
    local fleet_name=""
    local minimal_template=false
    local force=false

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
            *) shift ;;
        esac
    done

    local target_dir="$(pwd)"
    local config_file="$target_dir/manifest.fleet.yaml"

    # If fleet already exists, route to update routine (unless --force reinit)
    if [[ -f "$config_file" ]] && [[ "$force" != "true" ]]; then
        log_info "Fleet already initialized. Running update routine..."
        fleet_update --_from-init
        return $?
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                     MANIFEST FLEET INITIALIZATION                    ║"
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

    # Generate skeleton manifest.fleet.yaml (no services — update populates them)
    echo "Creating manifest.fleet.yaml..."

    if [[ "$minimal_template" == "true" ]]; then
        _generate_minimal_manifest "$config_file" "$fleet_name"
    else
        _generate_full_manifest "$config_file" "$fleet_name"
    fi

    echo "✓ Created: $config_file"

    # Create .env.manifest.local if it doesn't exist
    local env_file="$target_dir/.env.manifest.local"
    if [[ ! -f "$env_file" ]]; then
        echo ""
        echo "Creating .env.manifest.local..."
        cat > "$env_file" << 'EOF'
# Fleet-specific configuration (git-ignored)
# See manifest.fleet.yaml for fleet definition

MANIFEST_CLI_FLEET_MODE="auto"
# MANIFEST_CLI_FLEET_PARALLEL="true"
# MANIFEST_CLI_FLEET_PUSH_STRATEGY="batched"
EOF
        echo "✓ Created: $env_file"
    fi

    # Discover and populate services via fleet update
    if ! fleet_update --_from-init; then
        log_error "Fleet update failed during initialization"
        return 1
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
            echo "  1. Review manifest.fleet.yaml and adjust service configuration"
            echo "  2. Run 'manifest fleet status' to see fleet overview"
            echo "  3. Run 'manifest fleet sync' to clone/pull all services"
            echo "  4. Run 'manifest fleet prep patch' for first coordinated release"
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

services:
  # Services are populated by 'manifest fleet update'
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
# Generated by: manifest fleet init
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

# =============================================================================
# SERVICES
# =============================================================================
services:
  # Services are populated by 'manifest fleet update'
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
# COMMAND: fleet discover
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_discover
# -----------------------------------------------------------------------------
# Discovers repositories in the workspace and shows diff against manifest.
#
# ARGUMENTS:
#   --depth N      Maximum search depth (default: 5)
#   --json         Output in JSON format
#   --quiet, -q    Only show new repos
#
# EXAMPLE:
#   manifest fleet discover
#   manifest fleet discover --depth 3
# -----------------------------------------------------------------------------
fleet_discover() {
    local depth=5
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
            --json) json_output=true; shift ;;
            -q|--quiet) quiet=true; shift ;;
            *) shift ;;
        esac
    done

    local root_dir="${MANIFEST_FLEET_ROOT:-$(pwd)}"
    if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
        log_error "--depth must be a non-negative integer"
        return 1
    fi

    if [[ "$json_output" == "true" ]]; then
        quick_discover "$root_dir"
        return 0
    fi

    if [[ "$quiet" == "true" ]]; then
        # Just output new repos for scripting
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

    # Interactive discovery
    interactive_discover "$root_dir"
}

# =============================================================================
# COMMAND: fleet sync
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_sync
# -----------------------------------------------------------------------------
# Synchronizes all fleet services (clone missing, pull existing).
#
# ARGUMENTS:
#   --parallel, -p   Run in parallel (default based on config)
#   --clone-only     Only clone missing, don't pull existing
#   --pull-only      Only pull existing, don't clone missing
#
# EXAMPLE:
#   manifest fleet sync
#   manifest fleet sync --parallel
# -----------------------------------------------------------------------------
fleet_sync() {
    if ! _fleet_require_initialized "sync"; then
        return 1
    fi

    local parallel=$(get_fleet_config_value "parallel" "$MANIFEST_FLEET_DEFAULT_PARALLEL")
    local clone_only=false
    local pull_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--parallel) parallel=true; shift ;;
            --clone-only) clone_only=true; shift ;;
            --pull-only) pull_only=true; shift ;;
            *) shift ;;
        esac
    done

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                         MANIFEST FLEET SYNC                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""

    local total=0
    local cloned=0
    local pulled=0
    local failed=0

    for service in $MANIFEST_FLEET_SERVICES; do
        ((total++))
        local path=$(get_fleet_service_property "$service" "path")
        local url=$(get_fleet_service_property "$service" "url")
        local branch=$(get_fleet_service_property "$service" "branch" "main")
        local is_submodule=$(get_fleet_service_property "$service" "submodule" "false")

        echo "[$total] $service"

        if [[ ! -d "$path" ]]; then
            # Need to clone
            if [[ "$pull_only" == "true" ]]; then
                echo "    ⏭ Skipping (clone-only mode)"
                continue
            fi

            if [[ -z "$url" ]]; then
                echo "    ✗ Cannot clone: no URL specified"
                ((failed++))
                continue
            fi

            # Validate path is within fleet root (prevent path traversal)
            local abs_clone_path
            abs_clone_path=$(cd "$MANIFEST_FLEET_ROOT" 2>/dev/null && mkdir -p "$(dirname "$path")" 2>/dev/null && cd "$(dirname "$path")" && echo "$(pwd)/$(basename "$path")")
            if [[ -z "$abs_clone_path" ]] || [[ "$abs_clone_path" != "$MANIFEST_FLEET_ROOT"* ]]; then
                echo "    ✗ Invalid path (outside fleet root): $path"
                ((failed++))
                continue
            fi

            echo "    → Cloning from $url..."
            if git clone --branch "$branch" "$url" "$path" 2>&1 | tail -1; then
                echo "    ✓ Cloned successfully"
                ((cloned++))
            else
                echo "    ✗ Clone failed"
                ((failed++))
            fi
        else
            # Already exists - pull
            if [[ "$clone_only" == "true" ]]; then
                echo "    ⏭ Skipping (pull-only mode)"
                continue
            fi

            if [[ ! -d "$path/.git" ]] && [[ "$is_submodule" != "true" ]]; then
                echo "    ⚠ Not a git repository"
                continue
            fi

            echo "    → Pulling latest..."
            local pull_output
            if pull_output=$(git -C "$path" pull --rebase 2>&1); then
                echo "    ✓ Updated"
                ((pulled++))
            else
                echo "    ⚠ Pull failed: $(echo "$pull_output" | tail -1)"
                ((failed++))
            fi
        fi
    done

    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    echo "Summary: $cloned cloned, $pulled pulled, $failed failed (of $total total)"
    echo ""
}

# =============================================================================
# COMMAND: fleet update
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_update
# -----------------------------------------------------------------------------
# Re-scans the workspace and adds newly discovered repos to manifest.fleet.yaml.
#
# This is the routine counterpart to fleet init — run it whenever new repos
# appear in the workspace. Also invoked automatically by fleet init when a
# manifest already exists.
#
# ARGUMENTS:
#   --depth N      Maximum search depth (default: 5)
#
# EXAMPLE:
#   manifest fleet update
#   manifest fleet update --depth 3
# -----------------------------------------------------------------------------
fleet_update() {
    local depth=5
    local skip_init_check=false

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
            *) shift ;;
        esac
    done

    # When called standalone, require fleet to be initialized.
    # When called from fleet_init (--_from-init), skip — config was just created.
    if [[ "$skip_init_check" != "true" ]]; then
        if ! _fleet_require_initialized "update"; then
            return 1
        fi
    fi

    local root_dir="${MANIFEST_FLEET_ROOT:-$(pwd)}"

    # Resolve config file
    local config_file
    config_file=$(_fleet_resolve_config "$root_dir")

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                       MANIFEST FLEET UPDATE                          ║"
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
        echo "Adding new repositories:"
        echo ""
        echo "$diff_output" | grep "^+" | while IFS=$'\t' read -r status name path type branch version url is_sub; do
            printf "  + %-25s %-12s %s\n" "$name" "($type)" "$path"
        done
        echo ""

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
        echo "  Run 'manifest fleet sync' to clone missing repos,"
        echo "  or remove them from manifest.fleet.yaml manually."
    fi

    echo ""
}

# =============================================================================
# COMMAND: fleet ship
# =============================================================================

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

Flow:
  default: fleet prep -> fleet docs -> fleet pr create -> fleet pr queue
  --safe:  fleet prep -> fleet docs -> fleet pr create -> fleet pr checks -> fleet pr ready -> fleet pr queue
EOF
                return 0
                ;;
            *)
                log_error "Unknown option for 'manifest fleet ship': $1"
                return 1
                ;;
        esac
    done

    if [[ ! "$method" =~ ^(merge|squash|rebase)$ ]]; then
        log_error "Invalid --method value: '$method' (expected merge|squash|rebase)"
        return 1
    fi

    # Determine step count based on whether safe mode adds extra steps
    local total_steps=5
    if [ "$safe" = "true" ]; then
        total_steps=6
    fi

    echo "🚢 Starting fleet ship workflow ($increment_type)"

    if [ "$run_prep" = "true" ]; then
        echo "🔧 Step 1/$total_steps: Running prep across fleet services..."
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
            return 1
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
    local create_args=()
    [ "$draft" = "true" ] && create_args+=("--draft")
    manifest_fleet_pr_dispatch create "${create_args[@]}" || return 1

    if [ "$safe" = "true" ]; then
        echo "🧪 Step 4/$total_steps: Verifying checks and readiness across fleet..."
        manifest_fleet_pr_dispatch checks || return 1
        manifest_fleet_pr_dispatch ready || return 1
    fi

    local queue_step=$((total_steps))
    echo "📥 Step ${queue_step}/${total_steps}: Queueing PRs across fleet..."
    local queue_args=(--method "$method")
    [ "$force" = "true" ] && queue_args+=("--force")
    [ "$no_delete_branch" = "true" ] && queue_args+=("--no-delete-branch")
    manifest_fleet_pr_dispatch queue "${queue_args[@]}" || return 1

    echo "✅ Fleet ship workflow complete."
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
            echo "Add the following to manifest.fleet.yaml under 'services:' manually:"
            echo ""
            echo "$yaml_content"
            return 1
        fi
    else
        echo "No manifest.fleet.yaml found. Add the following under 'services:':"
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
        status)
            fleet_status "$@"
            ;;
        init)
            fleet_init "$@"
            ;;
        discover)
            fleet_discover "$@"
            ;;
        sync)
            fleet_sync "$@"
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
            # TODO: Implement coordinated version bump
            log_warning "fleet prep is not yet implemented"
            echo "For now, run 'manifest prep' in each service directory"
            ;;
        docs)
            shift
            fleet_docs_dispatch "$@"
            ;;
        help|--help|-h)
            fleet_help
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

COMMANDS:

  manifest fleet init [options]
    Initialize a new fleet in the current directory.
    Creates skeleton config, then runs 'fleet update' to discover repos.
    If fleet already exists, routes directly to 'fleet update'.
    Options:
      --name, -n NAME    Fleet name
      --force, -f        Overwrite existing manifest.fleet.yaml

  manifest fleet status [options]
    Show fleet status overview.
    Options:
      --verbose, -v      Show detailed information
      --json             Output as JSON

  manifest fleet discover [options]
    Discover repositories in workspace (read-only).
    Options:
      --depth N          Maximum search depth (default: 5)
      --quiet, -q        Only show new repos

  manifest fleet update [options]
    Re-scan workspace and add new repos to manifest.fleet.yaml.
    Also runs automatically when 'fleet init' is called on an existing fleet.
    Options:
      --depth N          Maximum search depth (default: 5)

  manifest fleet sync [options]
    Clone missing repos, pull existing ones.
    Options:
      --parallel, -p     Run operations in parallel
      --clone-only       Only clone missing repos
      --pull-only        Only pull existing repos

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

  Fleet is configured via manifest.fleet.yaml in the fleet root directory.
  Service-specific overrides go in each service's .env.manifest.local.

  Run 'manifest fleet init' to create a new fleet configuration.

EXAMPLES:

  # Initialize a new fleet (discovers repos automatically)
  manifest fleet init

  # Add newly discovered repos to existing fleet
  manifest fleet update

  # Check fleet status
  manifest fleet status

  # Clone all missing services
  manifest fleet sync

  # Preview new/missing repos (read-only)
  manifest fleet discover

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
