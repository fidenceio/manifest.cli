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
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest init repo [--force] [--dry-run]" \
                    "Scaffold a single repository: VERSION, CHANGELOG.md, README.md, docs/, .gitignore.
Idempotent — safe to re-run. No remote operations." \
                    "Options" "  -f, --force   Re-create files even if they already exist
  --dry-run     Print what would be created/updated; no writes" \
                    "Examples" "  manifest init repo
  manifest init repo --dry-run
  manifest init repo --force"
                return 0
                ;;
            *)
                _render_help_error "Unknown option: $1" "manifest init repo [--force] [--dry-run]"
                return 1
                ;;
        esac
    done

    local project_root="${PROJECT_ROOT:-$(pwd)}"

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "Dry run — manifest init repo: $project_root"
        echo ""
        if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
            echo "  would create: .git/   (git init)"
        else
            echo "  exists:       .git/"
        fi
        local f
        for f in VERSION README.md CHANGELOG.md .gitignore; do
            if [[ -f "$project_root/$f" ]]; then
                if [[ "$force" == "true" ]]; then
                    echo "  would overwrite: $f   (--force)"
                else
                    echo "  exists:          $f"
                fi
            else
                echo "  would create:    $f"
            fi
        done
        if [[ -d "$project_root/docs" ]]; then
            echo "  exists:          docs/"
        else
            echo "  would create:    docs/"
        fi
        if [[ -f "$project_root/manifest.config.local.yaml" && "$force" != "true" ]]; then
            echo "  exists:          manifest.config.local.yaml"
        else
            echo "  would create:    manifest.config.local.yaml"
        fi
        echo ""
        echo "No changes written. Re-run without --dry-run to apply."
        echo ""
        return 0
    fi

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
                _render_help \
                    "manifest init fleet [--depth N] [--force] [--name NAME]" \
                    "Two-phase fleet initialization." \
                    "Phases" "  Phase 1 (no TSV yet):  Scan directories, write manifest.fleet.tsv
                         for you to review and edit selections.
  Phase 2 (TSV exists):  Read selections, scaffold each repo, write
                         manifest.fleet.config.yaml." \
                    "Options" "  --depth N      Scan depth in Phase 1 (default: 2)
  -f, --force    Overwrite existing files (re-runs Phase 1 + skips guard)
  -n, --name     Fleet name (prompted if not provided)" \
                    "Examples" "  manifest init fleet                 # Phase 1: discover
  vim manifest.fleet.tsv             # edit SELECT column
  manifest init fleet                 # Phase 2: apply selections
  manifest init fleet --depth 4 --name acme"
                return 0
                ;;
            *)
                _render_help_error \
                    "Unknown option: $1" \
                    "manifest init fleet [--depth N] [--force] [--name NAME]"
                return 1
                ;;
        esac
    done

    local root_dir="$(pwd)"
    local start_file="$root_dir/manifest.fleet.tsv"
    local config_file="$root_dir/manifest.fleet.config.yaml"

    # Phase 1: No TSV exists yet — run discovery.
    # Also re-runs Phase 1 if --force is given AND no fleet config exists yet
    # (so users can regenerate the TSV before applying it).
    if [[ ! -f "$start_file" ]] || [[ "$force" == "true" && ! -f "$config_file" ]]; then
        echo ""
        echo "Phase 1/2: Discovering directories…"
        echo "After this completes, edit manifest.fleet.tsv to set SELECT=true/false,"
        echo "then re-run 'manifest init fleet' to apply your selections (Phase 2)."
        echo ""

        local start_args=("--depth" "$depth")
        if [[ "$force" == "true" ]]; then
            start_args+=("--force")
        fi

        fleet_start "${start_args[@]}"
        return $?
    fi

    # Phase 2: TSV exists — guard against accidental re-scan that would
    # discard the user's edits unless --force is explicit.
    if _fleet_init_tsv_is_stale "$start_file" "$config_file"; then
        log_warning "manifest.fleet.tsv has not been edited since it was generated."
        echo ""
        echo "  If you meant to apply Phase 1 results without changes, that's fine —"
        echo "  re-run with --force to acknowledge:"
        echo "    manifest init fleet --force"
        echo ""
        echo "  Otherwise, edit manifest.fleet.tsv first to set SELECT=true/false,"
        echo "  then re-run 'manifest init fleet'."
        return 1
    fi

    echo ""
    echo "Phase 2/2: Applying TSV selections…"
    echo ""

    if [[ "$force" == "true" ]]; then
        fleet_args+=("--force")
    fi

    fleet_init "${fleet_args[@]}"
}

# -----------------------------------------------------------------------------
# Function: _fleet_init_tsv_is_stale (internal)
# -----------------------------------------------------------------------------
# Returns 0 (stale = unedited) when the TSV's SELECT column matches the
# default-selection fingerprint that fleet_start wrote into the header,
# meaning the user ran Phase 2 without touching selections.
# Returns 1 (edited, or no fingerprint, or cannot tell) otherwise — in
# which case Phase 2 proceeds without prompting.
#
# We deliberately err on the side of *not* flagging as stale so we don't
# false-positive and block legitimate Phase 2 runs (e.g. on TSVs written
# by older versions of generate_start_tsv that lack the fingerprint).
# -----------------------------------------------------------------------------
_fleet_init_tsv_is_stale() {
    local tsv="$1"
    local config="$2"

    [[ -f "$tsv" ]] || return 1
    # If a fleet config already exists, we're past phase 2 — not stale.
    [[ -f "$config" ]] && return 1

    # Pull the embedded default-selection fingerprint. Old TSVs (pre-#15)
    # have no such header — treat as edited so we don't break them.
    local stored_hash
    stored_hash=$(awk '/^# DEFAULT-SELECT-HASH:/ {print $3; exit}' "$tsv")
    [[ -z "$stored_hash" ]] && return 1

    # Recompute the fingerprint from the current SELECT column. If the
    # user has edited even one row, the hashes diverge.
    local current_hash
    current_hash=$(awk -F'\t' '
        /^#/ {next}
        $1 == "" {next}
        {print $1}
    ' "$tsv" | _manifest_hash_short)

    [[ "$stored_hash" == "$current_hash" ]] && return 0
    return 1
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
            _render_help \
                "manifest init <repo|fleet> [options]" \
                "Scaffold a repository or fleet. No remote operations." \
                "Scopes" "  repo    Scaffold single repo (VERSION, CHANGELOG, docs, .gitignore)
  fleet   Two-phase fleet setup via directory scanning" \
                "More" "  manifest init repo --help    Per-repo options
  manifest init fleet --help   Phase 1 / Phase 2 details"
            ;;
        "")
            _render_help_error "init requires a scope" "manifest init <repo|fleet>"
            return 1
            ;;
        *)
            _render_help_error "Unknown scope: $scope" "manifest init <repo|fleet>"
            return 1
            ;;
    esac
}

# Export public functions
export -f manifest_init_repo
export -f manifest_init_fleet
export -f manifest_init_dispatch
