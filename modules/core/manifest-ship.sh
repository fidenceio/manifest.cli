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
#   - "manifest fleet ship <type>" -> "manifest ship fleet <type>"
#   - "manifest fleet prep <type>" -> "manifest ship fleet <type> --local"
#
# COMMANDS:
#   manifest ship repo <type>           Full release (tag + push + Homebrew)
#   manifest ship repo <type> --local   Local-only (no tag, no push)
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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major|revision)
                increment_type="$1"; shift ;;
            -p) increment_type="patch"; shift ;;
            -m) increment_type="minor"; shift ;;
            -M) increment_type="major"; shift ;;
            -r) increment_type="revision"; shift ;;
            --local) local_only=true; shift ;;
            -i|--interactive) interactive=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest ship repo <patch|minor|major|revision> [--local] [-i]" \
                    "Publish a release: version bump, docs, commit, tag, push." \
                    "Options" "  patch | -p          Increment patch version (e.g. 1.2.3 -> 1.2.4)
  minor | -m          Increment minor version (e.g. 1.2.3 -> 1.3.0)
  major | -M          Increment major version (e.g. 1.2.3 -> 2.0.0)
  revision | -r       Increment revision (e.g. 1.2.3 -> 1.2.3.1)
  --local             Local only — no tag, push, or Homebrew update
  -i, --interactive   Enable interactive safety prompts" \
                    "Examples" "  manifest ship repo patch
  manifest ship repo minor --local
  manifest ship repo -M -i"
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

    local publish_release="true"
    if [[ "$local_only" == "true" ]]; then
        publish_release="false"
        echo "Ship (local): $increment_type — no remote operations"
    else
        echo "Ship: $increment_type"
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
    local fleet_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major|revision)
                increment_type="$1"; shift ;;
            --local) local_only=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest ship fleet <patch|minor|major|revision> [--local] [fleet options]" \
                    "Coordinated fleet release across all services." \
                    "Options" "  patch | minor | major | revision   Release type
  --local                  Local only — no push, no PRs
  --noprep                 Skip per-service prep step (requires clean trees)
  --safe                   Insert checks/ready gate before queueing
  --method <merge|squash|rebase>
                           PR merge strategy (default: squash)
  --force                  Bypass readiness gate during queue
  --no-delete-branch       Keep source branches after queue
  --draft                  Create draft PRs" \
                    "Flow" "  default:  fleet prep -> fleet docs -> fleet pr create -> fleet pr queue
  --safe:   fleet prep -> fleet docs -> fleet pr create -> fleet pr checks -> fleet pr ready -> fleet pr queue" \
                    "Examples" "  manifest ship fleet patch
  manifest ship fleet minor --local
  manifest ship fleet major --safe --method squash
  manifest ship fleet patch --noprep --draft"
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

    if [[ "$local_only" == "true" ]]; then
        echo "Ship fleet (local): $increment_type — no remote operations"
        fleet_prep "$increment_type" "${fleet_args[@]}"
    else
        echo "Ship fleet: $increment_type"
        fleet_ship "$increment_type" "${fleet_args[@]}"
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
