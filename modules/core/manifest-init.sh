#!/bin/bash

# =============================================================================
# Manifest Init Module
# =============================================================================
#
# Implements: manifest init repo|fleet
#
# PURPOSE:
#   Scaffold a single repo or fleet. First step after config in the user journey.
#   Creates local files only — no remote operations.
#
# COMMANDS:
#   manifest init repo          Scaffold single repo (VERSION, CHANGELOG, etc.)
#   manifest init fleet         Two-phase fleet setup via TSV discovery
#
# DEPENDENCIES:
#   - manifest-shared-functions.sh (ensure_required_files, create_default_*)
#   - manifest-fleet.sh (fleet_start, fleet_init)
#   - manifest-yaml.sh (set_yaml_value)
# =============================================================================

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_INIT_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_INIT_LOADED=1

# -----------------------------------------------------------------------------
# Function: manifest_init_repo
# -----------------------------------------------------------------------------
# Scaffolds a single repository with required files.
# Creates: VERSION (1.0.0), CHANGELOG.md, README.md, docs/, .gitignore entries,
# manifest.config.local.yaml.
#
# Idempotent — safe to re-run. Reports what was created/updated.
#
# ARGUMENTS:
#   --force    Re-create files even if they exist
# -----------------------------------------------------------------------------
manifest_init_repo() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            -h|--help)
                echo "Usage: manifest init repo [--force]"
                echo ""
                echo "Scaffold a single repository with required files."
                echo "Creates: VERSION, CHANGELOG.md, README.md, docs/, .gitignore"
                echo ""
                echo "Options:"
                echo "  --force    Re-create files even if they already exist"
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: manifest init repo [--force]"
                return 1
                ;;
        esac
    done

    local project_root="${PROJECT_ROOT:-$(pwd)}"

    echo ""
    echo "Initializing repository: $project_root"
    echo ""

    # Ensure we're in a git repo (or create one)
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "No git repository found. Initializing..."
        if git init "$project_root" >/dev/null 2>&1; then
            echo "  Created: .git/"
        else
            log_error "Failed to initialize git repository"
            return 1
        fi
    fi

    # Use the shared ensure_required_files function
    # This creates VERSION, README.md, CHANGELOG.md, docs/, .gitignore
    if ! ensure_required_files "$project_root"; then
        log_error "Failed to create required files"
        return 1
    fi

    # Create manifest.config.local.yaml if it doesn't exist
    local local_config="$project_root/manifest.config.local.yaml"
    if [[ ! -f "$local_config" ]] || [[ "$force" == "true" ]]; then
        cat > "$local_config" << 'EOF'
# Manifest CLI — Local Configuration (git-ignored)
# This file overrides manifest.config.yaml for your local environment.
# See: manifest config show

# project:
#   name: "my-project"
#   description: "My project description"

# git:
#   default_branch: "main"

# debug:
#   enabled: false
#   verbose: false
EOF
        echo "  Created: manifest.config.local.yaml"
    fi

    echo ""
    echo "Repository initialized successfully."
    echo ""
    echo "Next steps:"
    echo "  manifest prep repo       Connect remotes, pull latest"
    echo "  manifest config          Adjust settings"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: manifest_init_fleet
# -----------------------------------------------------------------------------
# Two-phase fleet initialization:
#   Phase 1 (no TSV exists): Scan directories, create manifest.fleet.tsv
#   Phase 2 (TSV exists):    Read selections, scaffold each repo, create config
#
# Delegates to fleet_start (phase 1) and fleet_init (phase 2) in
# manifest-fleet.sh.
#
# ARGUMENTS:
#   --depth N    Scan depth (default: 2)
#   --force      Overwrite existing files
#   --name NAME  Fleet name
# -----------------------------------------------------------------------------
manifest_init_fleet() {
    local depth=2
    local force=false
    local fleet_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--depth requires a numeric value"
                    return 1
                fi
                depth="$2"; shift 2 ;;
            -f|--force) force=true; shift ;;
            -n|--name) fleet_args+=("--name" "$2"); shift 2 ;;
            -h|--help)
                echo "Usage: manifest init fleet [--depth N] [--force] [--name NAME]"
                echo ""
                echo "Two-phase fleet initialization:"
                echo "  Phase 1: Scan directories, create manifest.fleet.tsv for review"
                echo "  Phase 2: Read TSV selections, scaffold repos, create fleet config"
                echo ""
                echo "Options:"
                echo "  --depth N    Scan depth (default: 2)"
                echo "  --force      Overwrite existing files"
                echo "  --name NAME  Fleet name (prompted if not provided)"
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: manifest init fleet [--depth N] [--force] [--name NAME]"
                return 1
                ;;
        esac
    done

    local root_dir="$(pwd)"
    local start_file="$root_dir/manifest.fleet.tsv"
    local config_file="$root_dir/manifest.fleet.config.yaml"

    # Phase 1: No TSV exists yet — run discovery
    if [[ ! -f "$start_file" ]] || [[ "$force" == "true" && ! -f "$config_file" ]]; then
        # Delegate to fleet_start with our depth
        local start_args=("--depth" "$depth")
        if [[ "$force" == "true" ]]; then
            start_args+=("--force")
        fi

        fleet_start "${start_args[@]}"
        return $?
    fi

    # Phase 2: TSV exists — run initialization
    if [[ "$force" == "true" ]]; then
        fleet_args+=("--force")
    fi

    fleet_init "${fleet_args[@]}"
}

# -----------------------------------------------------------------------------
# Function: manifest_init_dispatch
# -----------------------------------------------------------------------------
# Main entry point for 'manifest init' command routing.
#
# ARGUMENTS:
#   $1 - Scope: "repo" or "fleet"
#   $@ - Remaining arguments passed to the scope handler
# -----------------------------------------------------------------------------
manifest_init_dispatch() {
    local scope="${1:-}"
    shift || true

    case "$scope" in
        repo)
            manifest_init_repo "$@"
            ;;
        fleet)
            manifest_init_fleet "$@"
            ;;
        -h|--help|help)
            echo "Usage: manifest init <repo|fleet> [options]"
            echo ""
            echo "Scaffold a repository or fleet. No remote operations."
            echo ""
            echo "Scopes:"
            echo "  repo     Scaffold single repo (VERSION, CHANGELOG, docs, etc.)"
            echo "  fleet    Two-phase fleet setup via directory scanning"
            echo ""
            echo "Run 'manifest init repo --help' or 'manifest init fleet --help' for details."
            ;;
        "")
            echo "Usage: manifest init <repo|fleet>"
            echo ""
            echo "Run 'manifest init --help' for details."
            return 1
            ;;
        *)
            log_error "Unknown scope: $scope"
            echo "Usage: manifest init <repo|fleet>"
            return 1
            ;;
    esac
}

# Export public functions
export -f manifest_init_repo
export -f manifest_init_fleet
export -f manifest_init_dispatch
