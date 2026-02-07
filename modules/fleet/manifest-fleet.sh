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
#   manifest fleet go        - Coordinated version bump
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

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

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
    local service_count=0
    for _ in $MANIFEST_FLEET_SERVICES; do
        service_count=$((service_count + 1))
    done
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
            if [[ -n "$(get_fleet_service_property "$service" "url")" ]]; then
                printf "│   URL:  %-63s │\n" "$(get_fleet_service_property "$service" "url")"
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
    echo "  manifest fleet sync       - Clone missing, pull existing"
    echo "  manifest fleet go patch   - Bump all services"
    echo "  manifest fleet discover   - Find new repos"
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
#   1. Creates manifest.fleet.yaml from template
#   2. Optionally runs discovery to populate services
#   3. Creates .env.manifest.local with fleet settings
#   4. Validates the configuration
#
# ARGUMENTS:
#   --name, -n NAME     Fleet name (prompted if not provided)
#   --discover, -d      Auto-discover repos and add to manifest
#   --template, -t      Use minimal template (no comments)
#   --force, -f         Overwrite existing manifest.fleet.yaml
#
# EXAMPLE:
#   manifest fleet init
#   manifest fleet init --name "my-platform" --discover
# -----------------------------------------------------------------------------
fleet_init() {
    local fleet_name=""
    local auto_discover=false
    local minimal_template=false
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name) fleet_name="$2"; shift 2 ;;
            -d|--discover) auto_discover=true; shift ;;
            -t|--template) minimal_template=true; shift ;;
            -f|--force) force=true; shift ;;
            *) shift ;;
        esac
    done

    local target_dir="$(pwd)"
    local config_file="$target_dir/manifest.fleet.yaml"

    # Check for existing manifest
    if [[ -f "$config_file" ]] && [[ "$force" != "true" ]]; then
        log_error "manifest.fleet.yaml already exists"
        log_error "Use --force to overwrite or edit the existing file"
        return 1
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

    # Run discovery if requested
    local discovered_services=""
    if [[ "$auto_discover" == "true" ]]; then
        echo "Discovering repositories..."
        discovered_services=$(discover_fleet_repos "$target_dir")
        local count=$(echo "$discovered_services" | grep -c "^" 2>/dev/null || echo "0")
        echo "Found $count potential service(s)"
        echo ""
    fi

    # Generate manifest.fleet.yaml
    echo "Creating manifest.fleet.yaml..."

    if [[ "$minimal_template" == "true" ]]; then
        _generate_minimal_manifest "$config_file" "$fleet_name" "$discovered_services"
    else
        _generate_full_manifest "$config_file" "$fleet_name" "$discovered_services"
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

    # Load and validate
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
            echo "  4. Run 'manifest fleet go patch' for first coordinated release"
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
    local discovered_services="$3"

    cat > "$config_file" << EOF
fleet:
  name: "$fleet_name"
  versioning: "date"

services:
EOF

    # Add discovered services
    if [[ -n "$discovered_services" ]]; then
        while IFS=$'\t' read -r name path type branch version url is_sub; do
            [[ -z "$name" ]] && continue
            echo "  $name:" >> "$config_file"
            echo "    path: \"./$path\"" >> "$config_file"
            echo "    type: \"$type\"" >> "$config_file"
        done <<< "$discovered_services"
    else
        # Add placeholder
        echo "  # Add services here or run 'manifest fleet discover'" >> "$config_file"
        echo "  # example-service:" >> "$config_file"
        echo "  #   path: \"./example-service\"" >> "$config_file"
        echo "  #   type: \"service\"" >> "$config_file"
    fi
}

# -----------------------------------------------------------------------------
# Function: _generate_full_manifest (internal)
# -----------------------------------------------------------------------------
_generate_full_manifest() {
    local config_file="$1"
    local fleet_name="$2"
    local discovered_services="$3"

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
EOF

    # Add discovered services
    if [[ -n "$discovered_services" ]]; then
        while IFS=$'\t' read -r name path type branch version url is_sub; do
            [[ -z "$name" ]] && continue
            echo "" >> "$config_file"
            echo "  $name:" >> "$config_file"
            echo "    path: \"./$path\"" >> "$config_file"
            [[ -n "$url" ]] && echo "    url: \"$url\"" >> "$config_file"
            echo "    type: \"$type\"" >> "$config_file"
            echo "    branch: \"$branch\"" >> "$config_file"
            [[ "$is_sub" == "true" ]] && echo "    submodule: true" >> "$config_file"
        done <<< "$discovered_services"
    else
        cat >> "$config_file" << 'EOF'
  # Add services here or run 'manifest fleet discover'
  #
  # example-service:
  #   path: "./services/example"
  #   type: "service"
  #   branch: "main"
  #
  # shared-lib:
  #   path: "./libs/shared"
  #   type: "library"
EOF
    fi

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
            --depth) depth="$2"; shift 2 ;;
            --json) json_output=true; shift ;;
            -q|--quiet) quiet=true; shift ;;
            *) shift ;;
        esac
    done

    local root_dir="${MANIFEST_FLEET_ROOT:-$(pwd)}"

    if [[ "$json_output" == "true" ]]; then
        quick_discover "$root_dir"
        return 0
    fi

    if [[ "$quiet" == "true" ]]; then
        # Just output new repos for scripting
        local discovered
        discovered=$(discover_fleet_repos "$root_dir" "$depth")

        if [[ -f "$MANIFEST_FLEET_CONFIG_FILE" ]]; then
            local diff_output
            diff_output=$(diff_discovered_repos "$discovered")
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

            echo "    → Cloning from $url..."
            if git clone --branch "$branch" "$url" "$path" 2>/dev/null; then
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
            if git -C "$path" pull --rebase 2>/dev/null; then
                echo "    ✓ Updated"
                ((pulled++))
            else
                echo "    ⚠ Pull failed (may have local changes)"
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
            --name) service_name="$2"; shift 2 ;;
            --type) service_type="$2"; shift 2 ;;
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

    # Generate YAML to add
    echo "Add the following to manifest.fleet.yaml under 'services:':"
    echo ""
    echo "  $service_name:"
    if [[ "$is_url" == "true" ]]; then
        echo "    url: \"$path_or_url\""
        echo "    path: \"./$service_name\""
    else
        local rel_path="${path_or_url#$MANIFEST_FLEET_ROOT/}"
        rel_path="${rel_path#./}"
        echo "    path: \"./$rel_path\""
    fi
    echo "    type: \"$service_type\""
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
        validate)
            fleet_validate "$@"
            ;;
        add)
            fleet_add "$@"
            ;;
        go)
            # TODO: Implement coordinated version bump
            log_warning "fleet go is not yet implemented"
            echo "For now, run 'manifest go' in each service directory"
            ;;
        docs)
            # TODO: Implement unified documentation
            log_warning "fleet docs is not yet implemented"
            echo "For now, run 'manifest docs' in each service directory"
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
    Options:
      --name, -n NAME    Fleet name
      --discover, -d     Auto-discover repos
      --force, -f        Overwrite existing manifest.fleet.yaml

  manifest fleet status [options]
    Show fleet status overview.
    Options:
      --verbose, -v      Show detailed information
      --json             Output as JSON

  manifest fleet discover [options]
    Discover repositories in workspace.
    Options:
      --depth N          Maximum search depth (default: 5)
      --quiet, -q        Only show new repos

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

  manifest fleet go [patch|minor|major]
    Coordinated version bump across all services.
    (Coming soon)

  manifest fleet docs
    Generate unified fleet documentation.
    (Coming soon)

CONFIGURATION:

  Fleet is configured via manifest.fleet.yaml in the fleet root directory.
  Service-specific overrides go in each service's .env.manifest.local.

  Run 'manifest fleet init' to create a new fleet configuration.

EXAMPLES:

  # Initialize a new fleet with auto-discovery
  manifest fleet init --discover

  # Check fleet status
  manifest fleet status

  # Clone all missing services
  manifest fleet sync

  # Discover new repos added to workspace
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
