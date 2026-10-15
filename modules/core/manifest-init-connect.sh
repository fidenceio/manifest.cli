#!/bin/bash

# =============================================================================
# Manifest Init — Connect Phase
# =============================================================================
#
# Implements: the network half of `manifest init repo|fleet` (--connect).
#
# PURPOSE:
#   Connect a workspace to its remotes — add or create origin, clone missing
#   fleet members, pull latest. Scaffold writers are local; applied release
#   checks can also use the network to build images or install container deps.
#
# Repository setup connects before scaffolding so an existing remote can supply
# its own project files. Empty origins need no pull. Populated origins must
# fast-forward; failures block setup. Fleet connection retains its clone/pull
# implementation. Only applied calls may contact a remote.
#
# The init.repo caller suppresses the duplicate apply banner via
# _MANIFEST_CLI_INIT_CONNECT_NESTED; the shared consent/audit gate still runs.
# =============================================================================
if [[ -n "${_MANIFEST_CLI_INIT_CONNECT_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_INIT_CONNECT_LOADED=1

manifest_init_connect_repo() {
    local nested="${_MANIFEST_CLI_INIT_CONNECT_NESTED:-0}"
    local dry_run=true
    local create_repo_visibility=""
    local remote_url=""
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    [[ "$execution_mode" == "apply" ]] && dry_run=false
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remote)
                [[ -n "${2:-}" && "$2" != -* ]] || { log_error "--remote requires a URL or path"; return 1; }
                remote_url="$2"; shift 2 ;;
            --create-repo-private)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "private") || return 1
                shift ;;
            --create-repo-public)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "public") || return 1
                shift ;;
            -h|--help)
                _render_help \
                    "manifest init repo --connect [-y|--yes] [--dry-run] [--create-repo-private|--create-repo-public]" \
                    "Connect phase: establish origin and fast-forward existing history.
Empty remotes need no pull; connection failures stop setup." \
                    "Options" "  --dry-run                  Explicit preview; no remote calls
  -y, --yes                  Apply the connect plan
  --create-repo-private      When no remote exists, create a private GitHub repo (gh repo create) and add as origin
  --create-repo-public       When no remote exists, create a public GitHub repo (gh repo create) and add as origin" \
                    "Examples" "  manifest init repo --connect
  manifest init repo --connect --dry-run
  manifest init repo --connect -y
  manifest init repo --create-repo-private -y   # implies --connect"
                return 0
                ;;
            *)
                _render_help_error "Unknown option: $1" "manifest init repo --connect [--dry-run] [--create-repo-private|--create-repo-public]"
                return 1
                ;;
        esac
    done

    local project_root="${MANIFEST_CLI_PROJECT_ROOT:-$(pwd)}"
    if [[ -n "$create_repo_visibility" ]]; then
        _manifest_github_repo_target "$project_root" >/dev/null || return 1
    fi
    local replay_command="manifest init repo --connect"
    [[ -n "$create_repo_visibility" ]] && replay_command="$replay_command --create-repo-$create_repo_visibility"

    if ! manifest_repo_scope_require_git "$replay_command"; then
        return 1
    fi

    # origin_required: the apply gate's default is `true`, which is right for a
    # pull — an unambiguous target needs a named branch AND an origin. It is
    # exactly wrong for --create-repo-*, whose entire premise is that there is
    # no origin yet. With the default, the gate refuses at this line and
    # `gh repo create` (below) is unreachable: the flag has no state in which it
    # works, because the one state where the gate passes is the state where
    # `_manifest_gh_repo_create` skips as already-configured.
    #
    # This was live in `manifest prep repo --create-repo-*` before the fold, and
    # folding propagated it to `init repo --create-repo-*`, where the flag DID
    # work (init had no apply gate at all). Caught by the pre-commit steward and
    # reproduced A/B with a stubbed gh: pre-fold 2 invocations, post-fold 0.
    local origin_required="true"
    [[ -n "$create_repo_visibility" || -n "$remote_url" ]] && origin_required="false"
    if ! manifest_execution_require_apply "$execution_mode" "$project_root" \
            "$(manifest_execution_replay_hint "$replay_command")" "" "$origin_required"; then
        return 1
    fi
    if [[ "$dry_run" != "true" ]]; then
        manifest_assert_release_branch "$project_root" || return 1
    fi

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run — $replay_command: $project_root"
    else
        echo "Connecting repository: $project_root"
    fi
    echo ""

    if [[ -n "$remote_url" ]]; then
        local existing_origin
        existing_origin="$(git -C "$project_root" remote get-url origin 2>/dev/null || true)"
        if [[ -n "$existing_origin" && "$existing_origin" != "$remote_url" ]]; then
            log_error "origin already points elsewhere; preserving it: $existing_origin"
            return 1
        fi
        if [[ "$dry_run" == "true" ]]; then
            printf '  would connect origin: %s\n' "$(manifest_redact "$remote_url")"
            return 0
        elif [[ -z "$existing_origin" ]]; then
            git -C "$project_root" remote add origin "$remote_url" || return 1
        fi
    fi

    # Env schema template (.env.example) — ENV-001, STANDARD.md §2.7. The connect
    # phase is the retrofit surface: repos that predate the scaffold gain it here
    # (no-clobber). Since the fold this is the same verb as the scaffold phase,
    # so it duplicates nothing — see the header note.
    if [[ "$dry_run" == "true" ]]; then
        if [[ ! -f "$project_root/.env.example" ]]; then
            echo "  would create: .env.example   (your env var names; non-secrets carry their spec default, secrets are commented out)"
            echo ""
        fi
    fi

    # Check if remote exists; if not, prompt for one
    local remotes
    remotes=$(git -C "$project_root" remote 2>/dev/null)

    if ! git -C "$project_root" remote get-url origin >/dev/null 2>&1; then
        if [[ "$dry_run" == "true" ]]; then
            if [[ -n "$create_repo_visibility" ]]; then
                local repo_target
                repo_target="$(_manifest_github_repo_display_target "$project_root")" || return 1
                echo "  no remotes configured — would gh repo create: $repo_target ($create_repo_visibility) and add as origin"
            else
                echo "  no remotes configured — would prompt for an origin URL"
            fi
            echo ""
            manifest_execution_footer "$replay_command -y"
            echo ""
            return 0
        fi
        echo "No remote configured."
        if [[ -n "$create_repo_visibility" ]]; then
            echo ""
            if ! _manifest_gh_repo_create "$project_root" "$create_repo_visibility"; then
                return 1
            fi
            # Refresh the remotes list so the pull step below picks up origin.
            remotes=$(git -C "$project_root" remote 2>/dev/null)
        elif [[ -t 0 ]]; then
            echo ""
            read -r -p "Enter remote URL for 'origin' (or press Enter to skip): " remote_url
            if [[ -n "$remote_url" ]]; then
                if git -C "$project_root" remote add origin "$remote_url"; then
                    echo "  Added remote: origin -> $remote_url"
                else
                    log_error "Failed to add remote"
                    return 1
                fi

                # Probe the URL — non-fatal so offline workflows still succeed,
                # but surfaces typos and missing repos before the first ship/push.
                echo "  Probing remote..."
                if git -C "$project_root" ls-remote --exit-code "$remote_url" >/dev/null 2>&1; then
                    echo "  ✓ Remote is reachable"
                else
                    log_warning "Remote unreachable: $remote_url"
                    echo "  Common causes: typo, repo not yet created, no network, or auth required."
                    echo "  Remove with: git -C \"$project_root\" remote remove origin"
                    echo "  Or recreate via: manifest init repo --create-repo-private -y"
                fi
            else
                log_error "Setup incomplete: origin is required to ship."
                return 1
            fi
        else
            log_error "Setup incomplete: no origin. Use init repo --remote URL or --create-repo-private."
            return 1
        fi
    elif [[ -n "$create_repo_visibility" ]]; then
        log_warning "Remote(s) already configured — ignoring --create-repo-$create_repo_visibility."
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
        manifest_execution_footer "$replay_command -y"
        echo ""
        return 0
    fi

    # Nested under init's scaffold phase, the apply banner has already been
    # printed once; a second one reads as a second apply.
    [[ "$nested" == "1" ]] || manifest_execution_apply_header
    # Ship publishes origin, so setup verifies that remote only. A newly created
    # remote has nothing to pull; failures and diverged history must never be
    # swallowed as a successful initialization.
    _manifest_init_sync_origin "$project_root" || return 1
    ensure_env_files "$project_root"
}

_manifest_init_sync_origin() {
    local root="$1" branch="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}" refs
    manifest_git_assert_safe_ref_name "$branch" "git.default_branch" || return 1
    if ! refs="$(git -C "$root" ls-remote origin)"; then
        log_error "Cannot read origin. Check its URL and authentication, then re-run init."
        return 1
    fi
    if [[ -z "$refs" ]]; then
        echo "origin is empty — no pull needed; the first ship will publish the branch."
        return 0
    fi
    if ! printf '%s\n' "$refs" | awk -v ref="refs/heads/$branch" '$2 == ref {found=1} END {exit !found}'; then
        log_error "origin has history but no '$branch' branch. Set git.default_branch to the intended release branch, then re-run init."
        return 1
    fi
    echo "Syncing with origin/$branch (fast-forward only)..."
    if ! git -C "$root" fetch origin "refs/heads/$branch:refs/remotes/origin/$branch" \
        || ! git -C "$root" merge --ff-only "refs/remotes/origin/$branch"; then
        log_error "Cannot fast-forward from origin/$branch. Resolve local changes or diverged history with Git, then re-run init."
        return 1
    fi
    git -C "$root" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null || return 1
    echo "Successfully synced with origin. Repository synced successfully."
}

# -----------------------------------------------------------------------------
# Function: manifest_init_connect_fleet
# -----------------------------------------------------------------------------
# Connect phase for a fleet: clones missing members, pulls existing ones.
#
# Absorbs the old fleet_sync() behavior (now _fleet_sync).
#
# ARGUMENTS:
#   --parallel    Run operations in parallel
#   --clone-only  Only clone missing repos (skip pull)
#   --pull-only   Only pull existing repos (skip clone)
# -----------------------------------------------------------------------------
manifest_init_connect_fleet() {
    local nested="${_MANIFEST_CLI_INIT_CONNECT_NESTED:-0}"
    local fleet_args=()
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    if [[ "$execution_mode" == "preview" ]]; then
        fleet_args+=("--dry-run")
    else
        # See the repo phase: nested under init, the banner is already printed.
        [[ "$nested" == "1" ]] || manifest_execution_apply_header
    fi
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--parallel) fleet_args+=("--parallel"); shift ;;
            --clone-only) fleet_args+=("--clone-only"); shift ;;
            --pull-only) fleet_args+=("--pull-only"); shift ;;
            -h|--help)
                _render_help \
                    "manifest init fleet --connect [-y|--yes] [--dry-run] [--parallel] [--clone-only] [--pull-only]" \
                    "Connect phase: clone missing members, pull existing ones.
This is the only part of 'init' that uses the network." \
                    "Options" "  --dry-run          Explicit preview; no clones, no pulls
  -y, --yes          Apply the connect plan
  -p, --parallel     Run operations in parallel
  --clone-only       Only clone missing repos (skip pull)
  --pull-only        Only pull existing repos (skip clone)" \
                    "Examples" "  manifest init fleet --connect
  manifest init fleet --connect -y
  manifest init fleet --connect --parallel
  manifest init fleet --connect --clone-only"
                return 0
                ;;
            *)
                _render_help_error \
                    "Unknown option: $1" \
                    "manifest init fleet --connect [--parallel] [--clone-only] [--pull-only] [--dry-run]"
                return 1
                ;;
        esac
    done

    # Delegate to internal fleet sync (private after #9)
    _fleet_sync "${fleet_args[@]}"
}

# Export connect phases used by init.
export -f manifest_init_connect_repo
export -f manifest_init_connect_fleet
