#!/bin/bash

# =============================================================================
# Manifest Init — Connect Phase
# =============================================================================
#
# Implements: the network half of `manifest init repo|fleet` (--connect), and
# the deprecated `manifest prep repo|fleet` spelling that used to own it.
#
# PURPOSE:
#   Connect a workspace to its remotes — add or create origin, clone missing
#   fleet members, pull latest. This is the ONLY phase of init that uses the
#   network; the scaffold phase in manifest-init.sh writes files and nothing
#   else.
#
# WHY THIS IS A PHASE OF `init` AND NOT ITS OWN VERB:
#   `init` and `prep` were split so that one wrote files and the other spoke to
#   the network. The split never held. Both offered --create-repo-private /
#   --create-repo-public, so BOTH called `gh repo create` (inline in
#   manifest_init_repo, and here) — and `manifest help` told users init
#   "never touches the network" while a flag on that very command published a
#   repository to GitHub. Both also scaffolded .env.example through the same
#   no-clobber `ensure_env_files`. Two verbs, two shared writers, one false
#   safety claim between them.
#
#   Folding prep into init makes the boundary real rather than asserted: one
#   verb owns setup, its scaffold phase writes files, and its connect phase
#   (this file) is where the REPO scope's remote calls live.
#
#   Scope of that claim, stated exactly because the looser version was wrong
#   when first written here: `_manifest_gh_repo_create` still has TWO call
#   sites. This file is the repo-scope one. The other is
#   manifest-fleet.sh (`_fleet_init_directory`), which creates a GitHub repo per
#   scaffolded fleet member during `init fleet` Phase 2 — inside the scaffold
#   phase, not the connect phase. So `init fleet --create-repo-*` still reaches
#   the network outside this file. Unifying that one means moving per-member
#   repo creation out of Phase 2, which is a larger change than this fold and
#   has not been made. Do not restate this as "one call site".
#
#   `.env.example` is still written in both phases and that is deliberate, not
#   leftover duplication: `ensure_env_files` is no-clobber and idempotent, and
#   the connect phase is the retrofit surface for repos that predate the
#   scaffold (ENV-001). With one verb there is no longer a boundary for it to
#   straddle. tests/prep_apply.bats guards that its preview text and its apply
#   still agree.
#
# COMMANDS:
#   manifest init repo --connect     Add/create origin, pull latest
#   manifest init fleet --connect    Clone missing members, pull existing ones
#   manifest prep repo|fleet         DEPRECATED alias for the above
#
# DEPENDENCIES:
#   - manifest-git.sh (sync_repository)
#   - manifest-fleet.sh (_fleet_sync)
# =============================================================================

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_PREP_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_PREP_LOADED=1

# -----------------------------------------------------------------------------
# Function: manifest_init_connect_repo
# -----------------------------------------------------------------------------
# Connect phase for a single repository: ensure origin exists (create it via
# `gh repo create` when asked, otherwise prompt), then pull latest from every
# remote.
#
# Absorbs the old sync_repository() behavior, and — since the fold — the
# --create-repo-* handling that manifest_init_repo used to duplicate inline.
#
# Nesting: when init's scaffold phase calls this as its second phase it exports
# _MANIFEST_CLI_INIT_CONNECT_NESTED=1, which suppresses the duplicate apply banner.
# The gates themselves still run; a network write earns its own check even when
# the scaffold that preceded it did not.
# -----------------------------------------------------------------------------
manifest_init_connect_repo() {
    local nested="${_MANIFEST_CLI_INIT_CONNECT_NESTED:-0}"
    local dry_run=true
    local create_repo_visibility=""
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
            --create-repo-private)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "private") || return 1
                shift ;;
            --create-repo-public)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "public") || return 1
                shift ;;
            -h|--help)
                _render_help \
                    "manifest init repo --connect [-y|--yes] [--dry-run] [--create-repo-private|--create-repo-public]" \
                    "Connect phase: add remote if missing, pull latest from all remotes.
This is the only part of 'init' that uses the network." \
                    "Options" "  --dry-run                  Explicit preview; no remote calls
  -y, --yes                  Apply the connect plan
  --create-repo-private      When no remote exists, create a private GitHub repo (gh repo create) and add as origin
  --create-repo-public       When no remote exists, create a public GitHub repo (gh repo create) and add as origin" \
                    "Examples" "  manifest init repo --connect
  manifest init repo --connect --dry-run
  manifest init repo --connect -y
  manifest init repo --create-repo-private -y   # implies --connect" \
                    "Deprecated spelling" "  manifest prep repo   still works; prints a deprecation notice"
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
    # The replay hint must name the spelling the user actually typed, or the
    # "run this to apply" line teaches a command they did not invoke. Under the
    # deprecated alias that is `manifest prep repo`; otherwise it is the fold's
    # spelling. _MANIFEST_CLI_INIT_CONNECT_ALIAS is set only by manifest_prep_repo.
    local replay_command="${_MANIFEST_CLI_INIT_CONNECT_ALIAS:-manifest init repo --connect}"
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
    [[ -n "$create_repo_visibility" ]] && origin_required="false"
    if ! manifest_execution_require_apply "$execution_mode" "$project_root" \
            "$(manifest_execution_replay_hint "$replay_command")" "" "$origin_required"; then
        return 1
    fi

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run — $replay_command: $project_root"
    else
        echo "Connecting repository: $project_root"
    fi
    echo ""

    # Env schema template (.env.example) — ENV-001, STANDARD.md §2.7. The connect
    # phase is the retrofit surface: repos that predate the scaffold gain it here
    # (no-clobber). Since the fold this is the same verb as the scaffold phase,
    # so it duplicates nothing — see the header note.
    if [[ "$dry_run" == "true" ]]; then
        if [[ ! -f "$project_root/.env.example" ]]; then
            echo "  would create: .env.example   (your env var names; non-secrets carry their spec default, secrets are commented out)"
            echo ""
        fi
    else
        ensure_env_files "$project_root" || true
    fi

    # Check if remote exists; if not, prompt for one
    local remotes
    remotes=$(git -C "$project_root" remote 2>/dev/null)

    if [[ -z "$remotes" ]]; then
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
                echo "  Skipped. Add a remote later: git remote add origin <url>"
                return 0
            fi
        else
            log_warning "No remotes configured and not in interactive mode. Skipping sync."
            return 0
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
    # Pull latest from all remotes (delegates to existing sync_repository)
    sync_repository
}

# -----------------------------------------------------------------------------
# Function: manifest_prep_repo  (DEPRECATED alias)
# -----------------------------------------------------------------------------
# The pre-fold spelling. Kept working — it is a published command and it is the
# entrypoint the built-in recipe manifest.builtin.prep.repo maps to — but it
# announces the replacement and hands straight over. _MANIFEST_CLI_INIT_CONNECT_ALIAS
# makes the preview's replay hint echo the spelling the user typed.
# -----------------------------------------------------------------------------
manifest_prep_repo() {
    log_deprecated "manifest prep repo" "manifest init repo --connect" "prep folded into init; one verb owns setup"
    _MANIFEST_CLI_INIT_CONNECT_ALIAS="manifest prep repo" manifest_init_connect_repo "$@"
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
  manifest init fleet --connect --clone-only" \
                    "Deprecated spelling" "  manifest prep fleet   still works; prints a deprecation notice"
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

# -----------------------------------------------------------------------------
# Function: manifest_prep_fleet  (DEPRECATED alias)
# -----------------------------------------------------------------------------
manifest_prep_fleet() {
    log_deprecated "manifest prep fleet" "manifest init fleet --connect" "prep folded into init; one verb owns setup"
    _MANIFEST_CLI_INIT_CONNECT_ALIAS="manifest prep fleet" manifest_init_connect_fleet "$@"
}

# -----------------------------------------------------------------------------
# Function: manifest_prep_dispatch  (DEPRECATED verb)
# -----------------------------------------------------------------------------
# `manifest prep` is the pre-fold spelling of `manifest init <scope> --connect`.
# It still works and is still tested; it announces the replacement and routes to
# the same phase. The verb stays listed in help with its DEPRECATED label rather
# than being hidden, because a user who types it should read why it moved rather
# than get an "unknown command".
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
                "manifest prep <repo|fleet> [options]   (DEPRECATED)" \
                "Connect remotes and pull latest.

This verb folded into 'init' — it is now the connect phase of one setup verb:
  manifest prep repo    ->  manifest init repo --connect
  manifest prep fleet   ->  manifest init fleet --connect
Both spellings work today; 'prep' prints a deprecation notice." \
                "Scopes" "  repo    Add remote if missing, pull latest from all remotes
  fleet   Clone missing repos, pull existing ones" \
                "More" "  manifest init repo --help    Scaffold + connect options
  manifest init fleet --help   Fleet-specific flags"
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
export -f manifest_init_connect_repo
export -f manifest_init_connect_fleet
# Deprecated aliases — exported because the built-in recipe and the `sync` alias
# still reach them by name.
export -f manifest_prep_repo
export -f manifest_prep_fleet
export -f manifest_prep_dispatch
