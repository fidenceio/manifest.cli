#!/bin/bash

# =============================================================================
# Manifest Ship Module (v42 redesign)
# =============================================================================
#
# Implements: manifest ship repo|fleet <patch|minor|major|revision> [--local]
#
# PURPOSE:
#   Publish a release — version bump, docs, commit, tag, push, Homebrew.
#   Highest consequence command in the CLI.
#
# KEY CHANGES from pre-v42:
#   - "manifest ship <type>" (old) -> "manifest ship repo <type>"
#   - "manifest prep <type>" (old local preview) -> "manifest ship repo <type> --local"
#   - Fleet release syntax is "manifest ship fleet <type>"
#
# COMMANDS:
#   manifest ship repo <type>           Full release (tag + push + Homebrew)
#   manifest ship repo <type> --local   Local-only (no tag, no push)
#   manifest ship repo resume           Resume post-release steps after failure
#   manifest ship fleet <type>          Coordinated fleet release
#   manifest ship fleet <type> --local  Coordinated fleet local-only
#
# DEPENDENCIES:
#   - manifest-pr.sh (manifest_ship — the existing ship function)
#   - manifest-orchestrator.sh (manifest_ship_workflow)
#   - manifest-fleet.sh (fleet_ship, fleet_prep)
# =============================================================================

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_SHIP_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_SHIP_LOADED=1

# -----------------------------------------------------------------------------
# Function: manifest_ship_repo
# -----------------------------------------------------------------------------
# Ship a single repo: version bump + docs + commit + tag + push + Homebrew.
# With --local: everything except tag/push/Homebrew.
#
# ARGUMENTS:
#   $1             Increment type: patch|minor|major|revision
#   --local        Local-only mode (no remote operations)
#   -i|--interactive  Enable interactive safety prompts
# -----------------------------------------------------------------------------
manifest_ship_repo() {
    local increment_type=""
    local local_only=false
    local interactive=false
    local explain=false
    local execution_mode="preview"
    local remaining_args=()

    if ! manifest_execution_parse execution_mode local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major|revision)
                increment_type="$1"; shift ;;
            resume)
                manifest_ship_repo_resume "$@"
                return $?
                ;;
            -p) increment_type="patch"; shift ;;
            -m) increment_type="minor"; shift ;;
            -M) increment_type="major"; shift ;;
            -r) increment_type="revision"; shift ;;
            -i|--interactive) interactive=true; shift ;;
            --explain) explain=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest ship repo <patch|minor|major|revision>|resume [-y|--yes] [--dry-run] [--local] [-i]" \
                    "Preview or publish a release: version bump, docs, commit, tag, push." \
                    "Options" "  patch | -p          Increment patch version (e.g. 1.2.3 -> 1.2.4)
  minor | -m          Increment minor version (e.g. 1.2.3 -> 1.3.0)
  major | -M          Increment major version (e.g. 1.2.3 -> 2.0.0)
  revision | -r       Increment revision (e.g. 1.2.3 -> 1.2.3.1)
  --dry-run           Explicit preview; no writes, commits, tags, or pushes
  -y, --yes           Apply the release plan
  --local             With -y, local only — no tag, push, or Homebrew update
  -i, --interactive   Enable interactive safety prompts
  --explain           Show the built-in recipe definition without running it
  resume              Continue safe post-release steps for current VERSION/tag" \
                    "Examples" "  manifest ship repo patch
  manifest ship repo patch -y
  manifest ship repo minor --local -y
  manifest ship repo -M -i -y
  manifest ship repo resume"
                return 0
                ;;
            *)
                _render_help_error \
                    "Unknown option: $1" \
                    "manifest ship repo <patch|minor|major|revision> [--local] [-i]"
                return 1
                ;;
        esac
    done

    if [[ -z "$increment_type" ]]; then
        _render_help_error \
            "ship repo requires a release type" \
            "manifest ship repo <patch|minor|major|revision> [--local] [-i]"
        return 1
    fi

    if [[ "$explain" == "true" ]]; then
        manifest_recipe_explain_command "ship" "repo" "$increment_type"
        return $?
    fi

    if [[ "$execution_mode" == "preview" ]]; then
        if [[ "$local_only" == "true" ]]; then
            echo "Ship repo preview (local): $increment_type — no changes written"
        else
            echo "Ship repo preview: $increment_type — no changes written"
        fi
        echo ""
        if declare -F manifest_repo_identity_block >/dev/null 2>&1; then
            manifest_repo_identity_block "$PWD"
            echo ""
        fi
        echo "Would perform:"
        echo "  - Validate repository identity and release readiness"
        echo "  - Increment VERSION using release type: $increment_type"
        echo "  - Regenerate release documentation and changelog"
        echo "  - Commit release files"
        if [[ "$local_only" == "true" ]]; then
            echo "  - Skip tag, push, and Homebrew publishing (--local)"
        else
            echo "  - Create release tag"
            echo "  - Push branch and tag"
            echo "  - Run downstream publish hooks when configured"
        fi
        local replay_command="manifest ship repo $increment_type"
        [[ "$local_only" == "true" ]] && replay_command="$replay_command --local"
        manifest_execution_footer "$replay_command -y"
        return 0
    fi

    manifest_execution_apply_header

    local publish_release="true"
    if [[ "$local_only" == "true" ]]; then
        publish_release="false"
        echo "Ship (local): $increment_type — no remote operations"
    else
        echo "Ship: $increment_type"
    fi

    if declare -F manifest_repo_identity_block >/dev/null 2>&1; then
        manifest_repo_identity_block "$PWD"
        echo ""
    fi

    manifest_ship_workflow "$increment_type" "$interactive" "$publish_release"
}

# -----------------------------------------------------------------------------
# Function: manifest_ship_fleet
# -----------------------------------------------------------------------------
# Coordinated fleet ship: version bump + docs + commit + tag + push across fleet.
# With --local: local-only (delegates to fleet_prep instead of fleet_ship).
#
# ARGUMENTS:
#   $1             Increment type: patch|minor|major|revision
#   --local        Local-only mode
#   Plus all fleet_ship options (--safe, --method, --draft, etc.)
# -----------------------------------------------------------------------------
manifest_ship_fleet() {
    local increment_type=""
    local local_only=false
    local explain=false
    local fleet_args=()
    local execution_mode="preview"
    local remaining_args=()

    if ! manifest_execution_parse execution_mode local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major|revision)
                increment_type="$1"; shift ;;
            --explain) explain=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest ship fleet <patch|minor|major|revision> [-y|--yes] [--dry-run] [--local] [fleet options]" \
                    "Preview or publish a coordinated fleet release across eligible services." \
                    "Options" "  patch | minor | major | revision   Release type
  --dry-run                Explicit preview; no writes, commits, tags, pushes, or PRs
  -y, --yes                Apply the fleet release plan
  --local                  With -y, local only — no push, no tags
  --explain                Show the built-in recipe definition without running it
  --noprep                 Skip per-service prep step (requires clean trees)
  --only <name[,name...]>  Ship only selected services
  --except <name[,name...]> Ship all services except selected services" \
                    "Flow" "  preview:  load fleet -> render per-service release plan
  apply:    load fleet -> ship release-enabled services directly
  PR work:  use manifest pr fleet ... explicitly" \
                    "Examples" "  manifest ship fleet patch
  manifest ship fleet patch -y
  manifest ship fleet minor --local -y
  manifest ship fleet patch --only fidenceiomanifestcli"
                return 0
                ;;
            *)
                fleet_args+=("$1"); shift ;;
        esac
    done

    if [[ -z "$increment_type" ]]; then
        _render_help_error \
            "ship fleet requires a release type" \
            "manifest ship fleet <patch|minor|major|revision> [--local]"
        return 1
    fi

    if [[ "$explain" == "true" ]]; then
        manifest_recipe_explain_command "ship" "fleet" "$increment_type"
        return $?
    fi

    if [[ "$local_only" == "true" ]]; then
        if [[ "$execution_mode" == "preview" ]]; then
            echo "Ship fleet preview (local): $increment_type — no changes written"
            fleet_ship "$increment_type" "--dry-run" "--local" "${fleet_args[@]}"
        else
            manifest_execution_apply_header
            echo "Ship fleet (local): $increment_type — no remote operations"
            fleet_ship "$increment_type" "--local" "-y" "${fleet_args[@]}"
        fi
    else
        if [[ "$execution_mode" == "preview" ]]; then
            echo "Ship fleet preview: $increment_type — no changes written"
            fleet_ship "$increment_type" "--dry-run" "${fleet_args[@]}"
        else
            manifest_execution_apply_header
            echo "Ship fleet: $increment_type"
            fleet_ship "$increment_type" "-y" "${fleet_args[@]}"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Function: manifest_ship_dispatch
# -----------------------------------------------------------------------------
# Main entry point for 'manifest ship' command routing (v42).
# -----------------------------------------------------------------------------
manifest_ship_dispatch() {
    local scope="${1:-}"
    shift || true

    case "$scope" in
        repo)
            manifest_ship_repo "$@"
            ;;
        fleet)
            manifest_ship_fleet "$@"
            ;;
        -h|--help|help)
            _render_help \
                "manifest ship <repo|fleet> <patch|minor|major|revision> [--local] [-i]" \
                "Publish a release. Highest consequence command." \
                "Scopes" "  repo    Single repo: version + docs + commit + tag + push
  fleet   Coordinated fleet release across all services" \
                "Options" "  --local             Local only — no tag, push, Homebrew, PRs
  -i, --interactive   Enable interactive safety prompts" \
                "More" "  manifest ship repo --help    Per-repo options + bump short flags
  manifest ship fleet --help   Fleet-specific flags (--noprep, --safe, --method, ...)"
            ;;
        # Legacy support: old "ship <patch|minor|major|revision>" routes to ship repo
        patch|minor|major|revision)
            manifest_ship_repo "$scope" "$@"
            ;;
        "")
            _render_help_error \
                "ship requires a scope" \
                "manifest ship <repo|fleet> <patch|minor|major|revision>"
            return 1
            ;;
        *)
            _render_help_error \
                "Unknown scope: $scope" \
                "manifest ship <repo|fleet> <patch|minor|major|revision>"
            return 1
            ;;
    esac
}

# Export public functions
export -f manifest_ship_repo
export -f manifest_ship_fleet
export -f manifest_ship_dispatch
