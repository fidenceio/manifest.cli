#!/bin/bash

# =============================================================================
# Manifest Prep Module (v42 redesign)
# =============================================================================
#
# Implements: manifest prep repo|fleet
#
# PURPOSE:
#   Prepare workspace for development — add remotes, pull latest.
#   This is the NEW meaning of "prep" in v42:
#     - Old "prep <type>" (local release preview) -> "manifest ship <type> --local"
#     - Old "sync" -> "manifest prep repo"
#
# COMMANDS:
#   manifest prep repo     Add remote if missing, pull latest from all remotes
#   manifest prep fleet    Clone missing repos, pull existing ones across fleet
#
# DEPENDENCIES:
#   - manifest-git.sh (sync_repository)
#   - manifest-fleet.sh (fleet_sync)
# =============================================================================

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_PREP_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_PREP_LOADED=1

# -----------------------------------------------------------------------------
# Function: manifest_prep_repo
# -----------------------------------------------------------------------------
# Prepares a single repository workspace: ensures remote is configured,
# pulls latest from all remotes.
#
# Absorbs the old sync_repository() behavior.
# -----------------------------------------------------------------------------
manifest_prep_repo() {
    local dry_run=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest prep repo [--dry-run]" \
                    "Prepare workspace: add remote if missing, pull latest from all remotes." \
                    "Options" "  --dry-run   Print what would happen; no remote calls" \
                    "Examples" "  manifest prep repo
  manifest prep repo --dry-run"
                return 0
                ;;
            *)
                _render_help_error "Unknown option: $1" "manifest prep repo [--dry-run]"
                return 1
                ;;
        esac
    done

    local project_root="${PROJECT_ROOT:-$(pwd)}"

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run — manifest prep repo: $project_root"
    else
        echo "Preparing repository: $project_root"
    fi
    echo ""

    # Check if remote exists; if not, prompt for one
    local remotes
    remotes=$(git -C "$project_root" remote 2>/dev/null)

    if [[ -z "$remotes" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            echo "  no remotes configured — would prompt for an origin URL"
            echo ""
            echo "No changes written. Re-run without --dry-run to apply."
            echo ""
            return 0
        fi
        echo "No remote configured."
        if [[ -t 0 ]]; then
            echo ""
            read -r -p "Enter remote URL for 'origin' (or press Enter to skip): " remote_url
            if [[ -n "$remote_url" ]]; then
                if git -C "$project_root" remote add origin "$remote_url"; then
                    echo "  Added remote: origin -> $remote_url"
                else
                    log_error "Failed to add remote"
                    return 1
                fi
            else
                echo "  Skipped. Add a remote later: git remote add origin <url>"
                return 0
            fi
        else
            log_warning "No remotes configured and not in interactive mode. Skipping sync."
            return 0
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo "Remotes that would be pulled:"
        local r
        while IFS= read -r r; do
            [[ -z "$r" ]] && continue
            local url
            url="$(git -C "$project_root" remote get-url "$r" 2>/dev/null || echo "?")"
            printf "  %-12s %s\n" "$r" "$url"
        done <<< "$remotes"
        echo ""
        echo "No changes written. Re-run without --dry-run to apply."
        echo ""
        return 0
    fi

    # Pull latest from all remotes (delegates to existing sync_repository)
    sync_repository
}

# -----------------------------------------------------------------------------
# Function: manifest_prep_fleet
# -----------------------------------------------------------------------------
# Prepares fleet workspace: clones missing repos, pulls existing ones.
#
# Absorbs the old fleet_sync() behavior.
#
# ARGUMENTS:
#   --parallel    Run operations in parallel
#   --clone-only  Only clone missing repos (skip pull)
#   --pull-only   Only pull existing repos (skip clone)
# -----------------------------------------------------------------------------
manifest_prep_fleet() {
    local fleet_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--parallel) fleet_args+=("--parallel"); shift ;;
            --clone-only) fleet_args+=("--clone-only"); shift ;;
            --pull-only) fleet_args+=("--pull-only"); shift ;;
            -h|--help)
                _render_help \
                    "manifest prep fleet [--parallel] [--clone-only] [--pull-only]" \
                    "Prepare fleet workspace: clone missing repos, pull existing ones." \
                    "Options" "  -p, --parallel     Run operations in parallel
  --clone-only       Only clone missing repos (skip pull)
  --pull-only        Only pull existing repos (skip clone)" \
                    "Examples" "  manifest prep fleet
  manifest prep fleet --parallel
  manifest prep fleet --clone-only"
                return 0
                ;;
            *)
                _render_help_error \
                    "Unknown option: $1" \
                    "manifest prep fleet [--parallel] [--clone-only] [--pull-only]"
                return 1
                ;;
        esac
    done

    # Delegate to existing fleet_sync
    fleet_sync "${fleet_args[@]}"
}

# -----------------------------------------------------------------------------
# Function: manifest_prep_dispatch
# -----------------------------------------------------------------------------
# Main entry point for 'manifest prep' command routing (v42).
# -----------------------------------------------------------------------------
manifest_prep_dispatch() {
    local scope="${1:-}"
    shift || true

    case "$scope" in
        repo)
            manifest_prep_repo "$@"
            ;;
        fleet)
            manifest_prep_fleet "$@"
            ;;
        -h|--help|help)
            _render_help \
                "manifest prep <repo|fleet> [options]" \
                "Prepare workspace: connect remotes, pull latest." \
                "Scopes" "  repo    Add remote if missing, pull latest from all remotes
  fleet   Clone missing repos, pull existing ones" \
                "More" "  manifest prep repo --help    Per-repo options
  manifest prep fleet --help   Fleet-specific flags"
            ;;
        # Legacy support: old "prep <patch|minor|major|revision>" routes to ship --local
        patch|minor|major|revision)
            log_deprecated "manifest prep $scope" "manifest ship repo $scope --local" "old prep-as-local-release syntax"
            manifest_ship_dispatch "repo" "$scope" "--local" "$@"
            ;;
        "")
            _render_help_error "prep requires a scope" "manifest prep <repo|fleet>"
            return 1
            ;;
        *)
            _render_help_error "Unknown scope: $scope" "manifest prep <repo|fleet>"
            return 1
            ;;
    esac
}

# Export public functions
export -f manifest_prep_repo
export -f manifest_prep_fleet
export -f manifest_prep_dispatch
