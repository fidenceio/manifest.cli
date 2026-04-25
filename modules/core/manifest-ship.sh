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
                echo "Usage: manifest ship repo <patch|minor|major|revision> [--local] [-i]"
                echo ""
                echo "Publish a release: version bump, docs, commit, tag, push."
                echo ""
                echo "Options:"
                echo "  --local        Do everything locally (no tag, push, or Homebrew)"
                echo "  -i|--interactive  Enable interactive safety prompts"
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: manifest ship repo <patch|minor|major|revision> [--local] [-i]"
                return 1
                ;;
        esac
    done

    if [[ -z "$increment_type" ]]; then
        log_error "ship repo requires a release type"
        echo "Usage: manifest ship repo <patch|minor|major|revision> [--local] [-i]"
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
                echo "Usage: manifest ship fleet <patch|minor|major|revision> [--local] [fleet options]"
                echo ""
                echo "Coordinated fleet release."
                echo ""
                echo "Options:"
                echo "  --local        Do everything locally (no push, no PRs)"
                echo "  --noprep       Skip per-service prep step"
                echo "  --safe         Run checks/ready gate before queueing"
                echo "  --method <merge|squash|rebase>"
                echo "  --draft        Create draft PRs"
                return 0
                ;;
            *)
                fleet_args+=("$1"); shift ;;
        esac
    done

    if [[ -z "$increment_type" ]]; then
        log_error "ship fleet requires a release type"
        echo "Usage: manifest ship fleet <patch|minor|major|revision> [--local]"
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
            echo "Usage: manifest ship <repo|fleet> <patch|minor|major|revision> [--local] [-i]"
            echo ""
            echo "Publish a release. Highest consequence command."
            echo ""
            echo "Scopes:"
            echo "  repo     Single repo: version + docs + commit + tag + push"
            echo "  fleet    Coordinated fleet release across all repos"
            echo ""
            echo "Options:"
            echo "  --local  Do everything locally (no tag, push, Homebrew)"
            echo "  -i       Enable interactive safety prompts"
            echo ""
            echo "Run 'manifest ship repo --help' or 'manifest ship fleet --help' for details."
            ;;
        # Legacy support: old "ship <patch|minor|major|revision>" routes to ship repo
        patch|minor|major|revision)
            manifest_ship_repo "$scope" "$@"
            ;;
        "")
            echo "Usage: manifest ship <repo|fleet> <patch|minor|major|revision>"
            echo ""
            echo "Run 'manifest ship --help' for details."
            return 1
            ;;
        *)
            log_error "Unknown scope: $scope"
            echo "Usage: manifest ship <repo|fleet> <patch|minor|major|revision>"
            return 1
            ;;
    esac
}

# Export public functions
export -f manifest_ship_repo
export -f manifest_ship_fleet
export -f manifest_ship_dispatch
