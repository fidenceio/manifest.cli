#!/bin/bash

# =============================================================================
# Manifest Refresh Module
# =============================================================================
#
# Implements: manifest refresh repo|fleet
#
# PURPOSE:
#   Regenerate docs, update metadata, maintain project state — without any
#   version change. Use this between releases to keep docs current.
#
# COMMANDS:
#   manifest refresh repo     Regenerate docs and metadata for single repo
#   manifest refresh fleet    Re-scan fleet membership, regenerate docs across fleet
#
# DEPENDENCIES:
#   - manifest-documentation.sh (generate_documents, update_repository_metadata)
#   - manifest-cleanup-docs.sh (main_cleanup)
#   - manifest-markdown-validation.sh (validate_project)
#   - manifest-fleet.sh (fleet_update, fleet_validate, fleet_docs_dispatch)
#   - manifest-time.sh (get_time_timestamp, format_timestamp)
# =============================================================================

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_REFRESH_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_REFRESH_LOADED=1

# -----------------------------------------------------------------------------
# Function: manifest_refresh_repo
# -----------------------------------------------------------------------------
# Regenerates documentation and metadata for a single repository.
# No version bump, no commit, no remote operations.
#
# Steps:
#   1. Get trusted timestamp
#   2. Regenerate documentation (release notes, etc.)
#   3. Archive old docs
#   4. Validate markdown
#   5. Update repository metadata
#
# ARGUMENTS:
#   --commit    Also commit the refreshed files (optional)
# -----------------------------------------------------------------------------
manifest_refresh_repo() {
    local do_commit=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --commit) do_commit=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest refresh repo [--commit]" \
                    "Regenerate docs and metadata without changing the version." \
                    "Options" "  --commit    Also commit refreshed files after regeneration" \
                    "Examples" "  manifest refresh repo
  manifest refresh repo --commit"
                return 0
                ;;
            *)
                _render_help_error "Unknown option: $1" "manifest refresh repo [--commit]"
                return 1
                ;;
        esac
    done

    local project_root="${PROJECT_ROOT:-$(pwd)}"

    echo ""
    echo "Refreshing repository: $project_root"
    echo ""

    # Read current version
    local current_version=""
    if [[ -f "$project_root/VERSION" ]]; then
        current_version=$(cat "$project_root/VERSION")
    fi

    if [[ -z "$current_version" ]]; then
        log_error "Could not determine current version. Run 'manifest init repo' first."
        return 1
    fi

    echo "  Version: $current_version (unchanged)"
    echo ""

    # Get trusted timestamp
    get_time_timestamp >/dev/null 2>&1
    local timestamp
    timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')

    # Regenerate documentation
    echo "Regenerating documentation..."
    if generate_documents "$current_version" "$timestamp" "patch"; then
        echo "  Documentation regenerated"
    else
        log_warning "Documentation generation had issues, continuing..."
    fi
    echo ""

    # Archive old docs
    echo "Archiving previous documentation..."
    main_cleanup "$current_version" "$timestamp"
    echo ""

    # Validate markdown
    echo "Validating markdown..."
    if validate_project "true" 2>/dev/null; then
        echo "  Markdown validation passed"
    else
        log_warning "Markdown validation found issues, continuing..."
    fi
    echo ""

    # Update repository metadata
    echo "Updating repository metadata..."
    update_repository_metadata
    echo ""

    # Optionally commit
    if [[ "$do_commit" == "true" ]]; then
        if [[ -n "$(git status --porcelain)" ]]; then
            echo "Committing refreshed files..."
            git add .
            git commit -m "Refresh docs and metadata for v$current_version"
            echo "  Committed"
        else
            echo "  No changes to commit"
        fi
        echo ""
    fi

    echo "Refresh complete."
    echo ""
}

# -----------------------------------------------------------------------------
# Function: manifest_refresh_fleet
# -----------------------------------------------------------------------------
# Re-scans fleet membership, regenerates docs, validates config.
# Absorbs logic from fleet update, fleet discover, fleet validate, fleet docs.
#
# ARGUMENTS:
#   --dry-run   Preview changes without applying them
#   --commit    Commit refreshed files across fleet
# -----------------------------------------------------------------------------
manifest_refresh_fleet() {
    local dry_run=false
    local do_commit=false
    local fleet_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; fleet_args+=("--dry-run"); shift ;;
            --commit) do_commit=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest refresh fleet [--dry-run] [--commit]" \
                    "Re-scan fleet membership, regenerate docs, validate config." \
                    "Options" "  --dry-run    Preview changes without applying
  --commit     Commit refreshed files across fleet (not yet implemented)" \
                    "Examples" "  manifest refresh fleet
  manifest refresh fleet --dry-run"
                return 0
                ;;
            *)
                _render_help_error \
                    "Unknown option: $1" \
                    "manifest refresh fleet [--dry-run] [--commit]"
                return 1
                ;;
        esac
    done

    echo ""
    echo "Refreshing fleet..."
    echo ""

    # Re-scan fleet membership (fleet_update handles discovery + merge)
    echo "Re-scanning fleet membership..."
    fleet_update "${fleet_args[@]}"
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run complete — no further changes."
        return 0
    fi

    # Validate fleet configuration
    echo "Validating fleet configuration..."
    fleet_validate
    echo ""

    # Regenerate fleet documentation
    echo "Regenerating fleet documentation..."
    fleet_docs_dispatch
    echo ""

    if [[ "$do_commit" == "true" ]]; then
        echo "Note: Fleet commit not yet implemented in refresh. Use 'manifest ship fleet --local' for coordinated commits."
    fi

    echo "Fleet refresh complete."
    echo ""
}

# -----------------------------------------------------------------------------
# Function: manifest_refresh_dispatch
# -----------------------------------------------------------------------------
# Main entry point for 'manifest refresh' command routing.
# -----------------------------------------------------------------------------
manifest_refresh_dispatch() {
    local scope="${1:-}"
    shift || true

    case "$scope" in
        repo)
            manifest_refresh_repo "$@"
            ;;
        fleet)
            manifest_refresh_fleet "$@"
            ;;
        -h|--help|help)
            _render_help \
                "manifest refresh <repo|fleet> [options]" \
                "Regenerate docs, metadata, and fleet membership.
No version change. No remote operations." \
                "Scopes" "  repo    Regenerate docs and metadata for single repo
  fleet   Re-scan fleet, regenerate docs, validate config" \
                "More" "  manifest refresh repo --help    Per-repo options
  manifest refresh fleet --help   Fleet-specific options"
            ;;
        "")
            _render_help_error "refresh requires a scope" "manifest refresh <repo|fleet>"
            return 1
            ;;
        *)
            _render_help_error "Unknown scope: $scope" "manifest refresh <repo|fleet>"
            return 1
            ;;
    esac
}

# Export public functions
export -f manifest_refresh_repo
export -f manifest_refresh_fleet
export -f manifest_refresh_dispatch
