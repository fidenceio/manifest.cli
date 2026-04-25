#!/bin/bash

# =============================================================================
# Manifest Status Module (Tier 4 #17)
# =============================================================================
#
# Implements: manifest status
#
# PURPOSE:
#   Read-only snapshot of "what would happen if I ship now?". Zero side
#   effects. Designed to be the first command a user runs after install.
#
# OUTPUT INCLUDES:
#   - Repo slug + canonical-repo gate result
#   - Branch / upstream sync state
#   - Working-tree pending changes
#   - Current VERSION + previews of patch/minor/major bumps
#   - Single-repo vs fleet mode + fleet member count
#   - Config layers detected
# =============================================================================

if [[ -n "${_MANIFEST_STATUS_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_STATUS_LOADED=1

# Compute next-version preview without writing anything.
# Args: $1 current_version, $2 increment_type
_status_preview_bump() {
    local current="$1"
    local kind="$2"
    local sep="${MANIFEST_CLI_VERSION_SEPARATOR:-.}"
    # Require strict X<sep>Y<sep>Z with numeric components (BSD cut otherwise
    # echoes the whole input back when the delimiter is absent).
    if [[ "$current" != *"$sep"*"$sep"* ]]; then echo "?"; return; fi
    local major minor patch
    major=$(echo "$current" | cut -d"$sep" -f1)
    minor=$(echo "$current" | cut -d"$sep" -f2)
    patch=$(echo "$current" | cut -d"$sep" -f3)
    if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]]; then
        echo "?"; return
    fi
    case "$kind" in
        patch) echo "${major}${sep}${minor}${sep}$((patch + 1))" ;;
        minor) echo "${major}${sep}$((minor + 1))${sep}0" ;;
        major) echo "$((major + 1))${sep}0${sep}0" ;;
    esac
}

# Render a single line aligned at column 14 for label, then value.
_status_line() {
    printf "  %-12s %s\n" "$1" "$2"
}

manifest_status() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: manifest status"
        echo ""
        echo "Read-only snapshot of repo, version, and what 'ship' would do."
        return 0
    fi

    local proj="${PROJECT_ROOT:-$(pwd)}"
    cd "$proj" 2>/dev/null || { echo "❌ Cannot enter $proj"; return 1; }

    echo ""
    echo "Manifest status"
    echo "==============="

    # -- Repository identity ------------------------------------------------
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _status_line "Repository:" "(not a git repository)"
        _status_line "Path:" "$proj"
        echo ""
        return 0
    fi

    local slug canonical_marker=""
    slug="$(manifest_origin_repo_slug "$proj" 2>/dev/null || echo "")"
    if [[ -z "$slug" ]]; then
        slug="(no origin remote)"
    elif manifest_is_canonical_repo "$proj" 2>/dev/null; then
        canonical_marker="  (canonical — Homebrew formula updates here)"
    fi
    _status_line "Repository:" "${slug}${canonical_marker}"

    # -- Branch + upstream sync --------------------------------------------
    local branch upstream sync_state
    branch="$(git -C "$proj" branch --show-current 2>/dev/null || echo "(detached)")"
    upstream="$(git -C "$proj" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "")"
    if [[ -z "$upstream" ]]; then
        sync_state="no upstream"
        _status_line "Branch:" "$branch  ($sync_state)"
    else
        local lr ahead behind
        lr="$(git -C "$proj" rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "0	0")"
        behind="$(echo "$lr" | awk '{print $1}')"
        ahead="$(echo "$lr" | awk '{print $2}')"
        if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
            sync_state="in sync"
        else
            sync_state="ahead ${ahead}, behind ${behind}"
        fi
        _status_line "Branch:" "$branch → $upstream  ($sync_state)"
    fi

    # -- Working tree -------------------------------------------------------
    local modified untracked
    modified="$(git -C "$proj" status --porcelain 2>/dev/null | grep -cv '^??' || echo 0)"
    untracked="$(git -C "$proj" status --porcelain 2>/dev/null | grep -c '^??' || echo 0)"
    if [[ "$modified" == "0" && "$untracked" == "0" ]]; then
        _status_line "Working:" "clean"
    else
        _status_line "Working:" "${modified} modified, ${untracked} untracked"
    fi

    # -- Version + bump previews -------------------------------------------
    if [[ -f "$proj/VERSION" ]]; then
        local current
        current="$(cat "$proj/VERSION" 2>/dev/null | tr -d '[:space:]')"
        _status_line "Version:" "$current"
        local p m M
        p="$(_status_preview_bump "$current" "patch")"
        m="$(_status_preview_bump "$current" "minor")"
        M="$(_status_preview_bump "$current" "major")"
        printf "  %-12s patch → %s\n" "" "$p"
        printf "  %-12s minor → %s\n" "" "$m"
        printf "  %-12s major → %s\n" "" "$M"
    else
        _status_line "Version:" "(no VERSION file — run 'manifest init repo')"
    fi

    # -- Single-repo vs fleet ----------------------------------------------
    local fleet_mode="single-repo"
    local fleet_count=""
    if [[ -f "$proj/manifest.fleet.config.yaml" ]]; then
        fleet_mode="fleet"
        if command -v yq >/dev/null 2>&1; then
            fleet_count="$(yq e '.services | length' "$proj/manifest.fleet.config.yaml" 2>/dev/null || echo "?")"
        fi
    elif [[ -f "$proj/manifest.fleet.tsv" ]]; then
        fleet_mode="fleet (init phase 1 — TSV pending review)"
    fi
    if [[ -n "$fleet_count" && "$fleet_count" != "0" && "$fleet_count" != "?" ]]; then
        _status_line "Mode:" "$fleet_mode  ($fleet_count members)"
    else
        _status_line "Mode:" "$fleet_mode"
    fi

    # -- Config layers ------------------------------------------------------
    local g="${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}"
    local ps="$proj/manifest.config.yaml"
    local pl="$proj/manifest.config.local.yaml"
    _status_line "Config:" "$([ -f "$g" ]  && echo "✓" || echo "·") global   $g"
    _status_line ""        "$([ -f "$ps" ] && echo "✓" || echo "·") project  $ps"
    _status_line ""        "$([ -f "$pl" ] && echo "✓" || echo "·") local    $pl"

    echo ""
    return 0
}

export -f manifest_status
