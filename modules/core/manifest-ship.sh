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

manifest_ship_preview_next_version() {
    local increment_type="$1"
    local repo_root="${PROJECT_ROOT:-$PWD}"

    if [[ -f "$repo_root/VERSION" ]] && declare -F get_next_version >/dev/null 2>&1; then
        (cd "$repo_root" && get_next_version "$increment_type" 2>/dev/null) || echo "unknown"
    else
        echo "unknown"
    fi
}

manifest_ship_preview_dirty_files() {
    local repo_root="${1:-${PROJECT_ROOT:-$PWD}}"
    local porcelain total shown line
    porcelain="$(git -C "$repo_root" status --porcelain -uall 2>/dev/null || true)"

    if [[ -z "$porcelain" ]]; then
        echo "  - Working tree: clean; no pre-release auto-commit needed"
        return 0
    fi

    total="$(printf '%s\n' "$porcelain" | grep -c .)"
    echo "  - Working tree: $total pending file(s) would be auto-committed before release"
    shown=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        shown=$((shown + 1))
        if [[ "$shown" -le 12 ]]; then
            echo "      ${line}"
        fi
    done <<< "$porcelain"
    if [[ "$total" -gt 12 ]]; then
        echo "      ... $((total - 12)) more"
    fi
}

manifest_ship_preview_join_items() {
    local count="$#"
    local i=1
    local item

    for item in "$@"; do
        if [[ "$i" -gt 1 ]]; then
            if [[ "$count" -eq 2 ]]; then
                printf ' and '
            elif [[ "$i" -eq "$count" ]]; then
                printf ', and '
            else
                printf ', '
            fi
        fi
        printf '%s' "$item"
        i=$((i + 1))
    done
}

manifest_ship_preview_summary() {
    local repo_root="${1:-${PROJECT_ROOT:-$PWD}}"
    local files bullets
    files="$(git -C "$repo_root" status --porcelain -uall 2>/dev/null | sed 's/^...//' || true)"

    if [[ -z "$files" ]]; then
        echo "  No pending source changes are queued for this release."
        return 0
    fi

    if declare -F manifest_git_changes_bullets_for_files >/dev/null 2>&1; then
        bullets="$(manifest_git_changes_bullets_for_files "$files")"
        manifest_ship_preview_summary_from_bullets "$bullets"
        return 0
    fi

    local total
    total="$(printf '%s\n' "$files" | grep -c .)"
    echo "  Updated ${total:-multiple} pending file(s) for this release."
}

manifest_ship_preview_summary_from_bullets() {
    local bullets="$1"
    local added=()
    local updated=()
    local other=()
    local line change

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        change="${line#- }"
        case "$change" in
            Add\ *) added+=("${change#Add }") ;;
            Update\ *) updated+=("${change#Update }") ;;
            Document\ *) updated+=("${change#Document }") ;;
            Backfill\ *) updated+=("${change#Backfill }") ;;
            Wire\ *) updated+=("${change#Wire }") ;;
            *) other+=("$change") ;;
        esac
    done <<< "$bullets"

    if [[ "${#added[@]}" -eq 0 && "${#updated[@]}" -eq 0 ]]; then
        if [[ "${#other[@]}" -gt 0 ]]; then
            printf '  %s.\n' "$(manifest_ship_preview_join_items "${other[@]}")"
        else
            echo "  No categorized release-note summary is available yet."
        fi
        return 0
    fi

    if [[ "${#added[@]}" -gt 0 ]]; then
        printf '  Added %s.\n' "$(manifest_ship_preview_join_items "${added[@]}")"
    fi
    if [[ "${#updated[@]}" -gt 0 ]]; then
        printf '  Updated %s.\n' "$(manifest_ship_preview_join_items "${updated[@]}")"
    fi
}

manifest_ship_preview_plan() {
    local increment_type="$1"
    local local_only="$2"
    local repo_root="${PROJECT_ROOT:-$PWD}"
    local current_version next_version tag_name

    current_version="$(tr -d '[:space:]' < "$repo_root/VERSION" 2>/dev/null || echo "unknown")"
    next_version="$(manifest_ship_preview_next_version "$increment_type")"
    if [[ "$next_version" != "unknown" ]] && declare -F manifest_release_tag_name >/dev/null 2>&1; then
        tag_name="$(manifest_release_tag_name "$next_version")"
    elif [[ "$next_version" != "unknown" ]]; then
        tag_name="v${next_version}"
    else
        tag_name="unknown"
    fi

    if [[ "$local_only" == "true" ]]; then
        echo "Ship repo preview (local)"
    else
        echo "Ship repo preview"
    fi
    echo "================="
    echo "  Release type:   $increment_type"
    echo "  Current version: $current_version"
    echo "  Next version:    $next_version"
    echo "  Release tag:     $tag_name"
    echo "  Writes:          none in preview mode"
    echo ""

    echo "What's new"
    echo "----------"
    manifest_ship_preview_summary "$repo_root"
    echo ""
    manifest_ship_preview_dirty_files "$repo_root"
    echo "  - VERSION: update $current_version -> $next_version"
    echo "  - CHANGELOG.md: prepend the $next_version release entry"
    echo "  - README.md and docs/INDEX.md: refresh displayed current-version metadata when needed"
    echo "  - docs/: regenerate release documentation and command/reference indexes"
    echo "  - docs/zArchive/: archive superseded release/changelog artifacts according to docs.retain"
    echo "  - Documentation review: inspect changed source/docs before release commits"
}

manifest_ship_repo_identity_notice() {
    local repo_root="${1:-${PROJECT_ROOT:-$PWD}}"

    if declare -F manifest_repo_identity_block >/dev/null 2>&1; then
        manifest_repo_identity_block "$repo_root"
    else
        echo "Repo identity"
        echo "-------------"
        echo "  Git root:     $(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null || echo "$repo_root")"
        echo "  Target:       this Git repository only"
    fi
    echo ""
}

manifest_ship_repo_preview_preflight_notice() {
    echo ""
    echo "DRY RUN COMPLETE: APPLY PREFLIGHT WAS NOT RUN"
    echo "  Preview mode did not touch .git or test Git metadata writes."
    echo "  When you rerun with -y, Manifest checks Git metadata write access before changing files."
    echo "  Depending upon your IDE or agent, you may see a brief failure before an elevated script completes the job."
}

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

    local replay_command="manifest ship repo $increment_type"
    [[ "$local_only" == "true" ]] && replay_command="$replay_command --local"

    if ! manifest_repo_scope_require_git "$replay_command"; then
        return 1
    fi

    if [[ "$execution_mode" == "preview" ]]; then
        manifest_ship_repo_identity_notice "${PROJECT_ROOT:-$PWD}"
        manifest_ship_preview_plan "$increment_type" "$local_only"
        manifest_execution_footer "$replay_command -y"
        manifest_ship_repo_preview_preflight_notice
        return 0
    fi

    local publish_release="true"
    if [[ "$local_only" == "true" ]]; then
        publish_release="false"
    fi

    if ! manifest_recipe_validate_command_effects \
        "ship" "repo" "$increment_type" "$execution_mode" "$local_only" "$publish_release"; then
        return 1
    fi

    if ! manifest_repo_scope_confirm_apply "${PROJECT_ROOT:-$PWD}" "$replay_command -y"; then
        return 1
    fi

    manifest_execution_apply_header

    if [[ "$local_only" == "true" ]]; then
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
  --noprep                 Skip per-service prep step (requires clean trees)" \
                    "Flow" "  preview:  load fleet -> render per-service release plan
  apply:    load fleet -> ship release-enabled services directly
  PR work:  use manifest pr fleet ... explicitly" \
                    "Examples" "  manifest ship fleet patch
  manifest ship fleet patch -y
  manifest ship fleet minor --local -y"
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

    local publish_release="true"
    [[ "$local_only" == "true" ]] && publish_release="false"

    if ! manifest_recipe_validate_command_effects \
        "ship" "fleet" "$increment_type" "$execution_mode" "$local_only" "$publish_release"; then
        return 1
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
