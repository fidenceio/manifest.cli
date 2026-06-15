#!/bin/bash

# =============================================================================
# Manifest Ship Module (v42 redesign)
# =============================================================================
#
# Implements: manifest ship repo|fleet <patch|minor|major|revision> [--local]
#
# PURPOSE:
#   Publish a release — version bump, docs, commit, tag, push, tap formula.
#   Highest consequence command in the CLI.
#
# KEY CHANGES from pre-v42:
#   - "manifest ship <type>" (old) -> "manifest ship repo <type>"
#   - "manifest prep <type>" (old local preview) -> "manifest ship repo <type> --local"
#   - Fleet release syntax is "manifest ship fleet <type>"
#
# COMMANDS:
#   manifest ship repo <type>           Full release (tag + push + tap formula)
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
# Single-flight per-repo lock
# -----------------------------------------------------------------------------
# Serialize concurrent `manifest ship repo ... -y` runs in the SAME repo so two
# invocations (e.g. a human + a CI runner) cannot race on the VERSION bump, tag
# creation, or push and leave a half-shipped repo. The fleet lock guards only
# the FLEET apply path; this protects the direct repo path. We deliberately
# REUSE the battle-tested fleet lock primitives (atomic mkdir mutex, PID +
# process-start-token + same-host liveness, race-safe stale reclaim, TOCTOU
# grace) rather than inventing a second locking scheme — they are defined in
# manifest-fleet.sh, which is sourced before this module in the same process.

# Lock dir for the current repo, keyed by the canonicalized git root so that
# `.`, an absolute path, and a symlinked path all resolve to one lock.
_manifest_repo_lock_dir_path() {
    local repo_root git_root hash
    repo_root="${PROJECT_ROOT:-$PWD}"
    git_root="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" || git_root="$repo_root"
    git_root="$(cd "$git_root" 2>/dev/null && pwd -P)" || git_root="$repo_root"
    hash="$(printf '%s' "$git_root" | _manifest_hash_short)"
    printf '%s/repo-%s.lock.d' "$(manifest_install_paths_locks_dir)" "${hash:0:16}"
}

# Canonicalized git root for the current repo (used both for the lock key and
# the MANIFEST_CLI_REPO_LOCK_HELD marker). Echoes the path.
_manifest_repo_lock_git_root() {
    local repo_root git_root
    repo_root="${PROJECT_ROOT:-$PWD}"
    git_root="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" || git_root="$repo_root"
    git_root="$(cd "$git_root" 2>/dev/null && pwd -P)" || git_root="$repo_root"
    printf '%s' "$git_root"
}

# Guard: should a `manifest ship repo` APPLY acquire the per-repo lock?
# Returns 0 (yes, lock) by default; returns 1 (no, SKIP) for the nested cases
# where the parent already holds a lock and re-acquiring would DEADLOCK:
#   1. Fleet child: `ship fleet` runs each member as `manifest ship repo ...`
#      with MANIFEST_CLI_AUDIT_SOURCE=cli-fleet, sequentially, while already
#      holding the fleet lock — members must NOT take a repo lock.
#   2. Follow-up patch: a ship re-invokes `ship repo patch -y` with
#      MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE set while the PARENT is still
#      inside manifest_ship_workflow holding THIS repo's lock — the child would
#      self-deadlock on the same lock dir.
# Defense-in-depth: MANIFEST_CLI_REPO_LOCK_HELD marks the git root whose lock is
# already held in this process tree, so any other nested manifest invocation in
# the same tree for the same root also skips. The two env-var checks above are
# the primary mechanism.
_manifest_ship_repo_should_lock() {
    [[ "${MANIFEST_CLI_AUDIT_SOURCE:-}" != "cli-fleet" ]] || return 1
    [[ -z "${MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE:-}" ]] || return 1
    if [[ -n "${MANIFEST_CLI_REPO_LOCK_HELD:-}" ]]; then
        [[ "${MANIFEST_CLI_REPO_LOCK_HELD}" != "$(_manifest_repo_lock_git_root)" ]] || return 1
    fi
    return 0
}

# Acquire the per-repo single-flight lock for the current repo's APPLY path,
# unless an exemption applies. Must run in the CALLER's shell (not a command
# substitution) so the mkdir lock, the exported MANIFEST_CLI_REPO_LOCK_HELD
# marker, and the lock-dir handoff all persist for the caller.
#   - Exits 0 with _MANIFEST_CLI_SHIP_REPO_LOCK_DIR="" when exempt (no lock taken).
#   - Exits 0 with _MANIFEST_CLI_SHIP_REPO_LOCK_DIR=<dir> when the lock is held;
#     the caller wires a release trap on that dir and clears the global.
#   - Exits 1 on acquire failure (holder + path already printed).
_manifest_ship_repo_lock_acquire() {
    _MANIFEST_CLI_SHIP_REPO_LOCK_DIR=""
    if ! _manifest_ship_repo_should_lock; then
        return 0
    fi
    local lock_dir
    lock_dir="$(_manifest_repo_lock_dir_path)"
    # _fleet_lock_acquire surfaces the holder identity + lock path on failure,
    # but its banner names "fleet ship". Add a repo-scoped line so the operator
    # sees the correct context (another `ship repo` is in progress here).
    if ! _fleet_lock_acquire "$lock_dir"; then
        log_error "Another 'manifest ship repo' is already applying in this repository."
        if [ -r "$lock_dir/holder" ]; then
            log_error "  Lock holder: $(tr '\n' ' ' < "$lock_dir/holder" 2>/dev/null)"
        fi
        log_error "  Lock: $lock_dir"
        return 1
    fi
    MANIFEST_CLI_REPO_LOCK_HELD="$(_manifest_repo_lock_git_root)"
    export MANIFEST_CLI_REPO_LOCK_HELD
    _MANIFEST_CLI_SHIP_REPO_LOCK_DIR="$lock_dir"
    return 0
}

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

# Stable fingerprint of the single-repo ship plan. Computed identically in
# preview and apply so the two can be compared (and so the future apply-event
# audit log can record exactly which plan was applied).
manifest_ship_repo_plan_fingerprint() {
    local increment_type="$1"
    local local_only="$2"
    local repo_root="${PROJECT_ROOT:-$PWD}"
    local current next tag
    current="$(tr -d '[:space:]' < "$repo_root/VERSION" 2>/dev/null || echo "unknown")"
    next="$(manifest_ship_preview_next_version "$increment_type")"
    if [[ "$next" != "unknown" ]] && declare -F manifest_release_tag_name >/dev/null 2>&1; then
        tag="$(manifest_release_tag_name "$next")"
    else
        tag="v${next}"
    fi
    manifest_plan_fingerprint "ship-repo" "$increment_type" "$local_only" "$current" "$next" "$tag"
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
    local plan_fingerprint
    plan_fingerprint="$(manifest_ship_repo_plan_fingerprint "$increment_type" "$local_only")"
    manifest_plan_render_field "Release type" "$increment_type"
    manifest_plan_render_field "Current version" "$current_version"
    manifest_plan_render_field "Next version" "$next_version"
    manifest_plan_render_field "Release tag" "$tag_name"
    manifest_plan_render_fingerprint_line "$plan_fingerprint"
    manifest_plan_render_field "Writes" "none in preview mode"
    # Stash the fingerprint the user is reading so a later apply can warn if the
    # plan drifted between this preview and that apply (CLI tracker §2.2).
    manifest_plan_fingerprint_persist "ship-repo" "$plan_fingerprint" "$repo_root"
    echo ""

    echo "What's new"
    echo "----------"
    manifest_ship_preview_summary "$repo_root"
    echo ""
    manifest_ship_preview_dirty_files "$repo_root"
    echo "  - VERSION: update $current_version -> $next_version"
    if declare -F _manifest_version_sync_targets >/dev/null 2>&1; then
        local _sync_target
        while IFS= read -r _sync_target; do
            [ -n "$_sync_target" ] && echo "  - ${_sync_target}: sync version field -> $next_version (version.sync)"
        done < <(_manifest_version_sync_targets 2>/dev/null)
    fi
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
# Ship a single repo: version bump + docs + commit + tag + push + tap formula.
# With --local: everything except tag/push/tap publish.
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
    local force_bump=false
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
            --force-bump) force_bump=true; shift ;;
            --explain) explain=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest ship repo <patch|minor|major|revision>|resume [-y|--yes] [--dry-run] [--local] [--force-bump] [-i]" \
                    "Preview or publish a release: version bump, docs, commit, tag, push." \
                    "Options" "  patch | -p          Increment patch version (e.g. 1.2.3 -> 1.2.4)
  minor | -m          Increment minor version (e.g. 1.2.3 -> 1.3.0)
  major | -M          Increment major version (e.g. 1.2.3 -> 2.0.0)
  revision | -r       Increment revision (e.g. 1.2.3 -> 1.2.3.1)
  --dry-run           Explicit preview; no writes, commits, tags, or pushes
  -y, --yes           Apply the release plan
  --local             With -y, local only — no tag, push, or Homebrew update
  -i, --interactive   Enable interactive safety prompts
  --force-bump        Bump, commit, and push even with no changes since the last
                      tag (forward-only — new commit + tag; never rewrites history)
  --explain           Show the built-in recipe definition without running it
  resume              Continue safe post-release steps for current VERSION/tag" \
                    "Examples" "  manifest ship repo patch
  manifest ship repo patch -y
  manifest ship repo minor --local -y
  manifest ship repo patch --force-bump -y
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

    # Symmetric "nothing to release" gate (parity with ship fleet's per-member
    # skip): a clean working tree already at the current release tag has nothing
    # to ship. Reuses the repo-side predicate so repo and fleet decide
    # identically. --force-bump bypasses it to cut a deliberate forward-only
    # release (new commit + tag; the bump itself becomes the change).
    if [[ "$force_bump" == "true" ]]; then
        echo "force-bump: cutting a release regardless of changes since the last tag (forward-only — new commit + tag, no history rewrite)."
    else
        local _repo_root="${PROJECT_ROOT:-$PWD}"
        local _cur_version _cur_tag
        _cur_version="$(tr -d '[:space:]' < "$_repo_root/VERSION" 2>/dev/null || echo "unknown")"
        if [[ "$_cur_version" != "unknown" ]] && declare -F manifest_release_tag_name >/dev/null 2>&1; then
            _cur_tag="$(manifest_release_tag_name "$_cur_version")"
        else
            _cur_tag="v${_cur_version}"
        fi
        if declare -F manifest_ship_followup_has_releasable_changes >/dev/null 2>&1 \
            && ! ( cd "$_repo_root" 2>/dev/null && manifest_ship_followup_has_releasable_changes "$_cur_tag" ); then
            echo "Nothing to release: HEAD is at ${_cur_tag} and the working tree is clean."
            echo "  Re-run to cut a release anyway:"
            echo "    ${replay_command} --force-bump -y"
            return 0
        fi
    fi

    if [[ "$execution_mode" == "preview" ]]; then
        manifest_ship_repo_identity_notice "${PROJECT_ROOT:-$PWD}"
        manifest_ship_preview_plan "$increment_type" "$local_only"
        manifest_execution_footer "$(manifest_execution_replay_hint "$replay_command")"
        manifest_ship_repo_preview_preflight_notice
        # Preview-without-consent exit code: 0 by default (the historical
        # contract), or the distinct code when preview.exit_code=distinct so CI
        # wrappers can tell "previewed, awaiting consent" from a real apply.
        return "$(manifest_preview_exit_code)"
    fi

    local publish_release="true"
    if [[ "$local_only" == "true" ]]; then
        publish_release="false"
    fi

    if ! manifest_recipe_validate_command_effects \
        "ship" "repo" "$increment_type" "$execution_mode" "$local_only" "$publish_release"; then
        return 1
    fi

    local plan_fingerprint
    plan_fingerprint="$(manifest_ship_repo_plan_fingerprint "$increment_type" "$local_only")"

    # Warn (never block) if the plan drifted since the preview the user read.
    manifest_plan_fingerprint_warn_on_drift "ship-repo" "$plan_fingerprint" "${PROJECT_ROOT:-$PWD}"

    if ! manifest_execution_require_apply "$execution_mode" "${PROJECT_ROOT:-$PWD}" "$(manifest_execution_replay_hint "$replay_command")" "$plan_fingerprint"; then
        return 1
    fi

    manifest_execution_apply_header

    manifest_plan_render_fingerprint_line "$plan_fingerprint"
    if [[ "$local_only" == "true" ]]; then
        echo "Ship (local): $increment_type — no remote operations"
    else
        echo "Ship: $increment_type"
    fi

    # Single-flight: only one `ship repo` may APPLY in this repository at a time
    # (preview returned above and writes nothing, so it never locks). Exempt the
    # nested fleet-child and follow-up-patch paths (see the guard helper) to
    # avoid deadlocking under an already-locked parent.
    if ! _manifest_ship_repo_lock_acquire; then
        return 1
    fi
    local repo_lock="${_MANIFEST_CLI_SHIP_REPO_LOCK_DIR:-}"
    if [ -n "$repo_lock" ]; then
        # Release the lock on ANY exit from this function. RETURN is
        # function-scoped (functrace is off) so it never clobbers the CLI's
        # top-level traps. INT/TERM additionally re-raise so Ctrl-C still
        # terminates with the correct status. Mirrors fleet_ship's pattern.
        trap '_fleet_lock_release "${repo_lock:-}"' RETURN
        trap '_fleet_lock_release "${repo_lock:-}"; trap - INT; kill -INT $$' INT
        trap '_fleet_lock_release "${repo_lock:-}"; trap - TERM; kill -TERM $$' TERM
    fi

    local workflow_rc=0
    manifest_ship_workflow "$increment_type" "$interactive" "$publish_release" || workflow_rc=$?

    # Completion audit event (§8.3a): the authorization event emitted at the
    # apply guard recorded only whether the *confirmation* succeeded — a ship
    # that passed confirmation then failed at push/gate is logged authorized:0.
    # Emit a second event here carrying the REAL workflow rc so the durable log
    # shows OUTCOME, not just authorization. Reuse the same plan fingerprint the
    # authorization path recorded, and thread the release-gate disposition
    # (§8.3b) from _MANIFEST_CLI_SHIP_LAST_GATE_STATUS so a `none` bypass or an
    # `unverified` fail-open is observable after the fact. Source mirrors the
    # guard (cli, or cli-fleet for a fleet member's subshell). Best-effort: never
    # alters the returned rc. This runs for direct ship repo AND, because the
    # fleet child invokes this same function in a subshell, per fleet member.
    if declare -F manifest_audit_apply_event >/dev/null 2>&1; then
        local _ship_git_root
        _ship_git_root="$(git -C "${PROJECT_ROOT:-$PWD}" rev-parse --show-toplevel 2>/dev/null || echo "${PROJECT_ROOT:-$PWD}")"
        manifest_audit_apply_event \
            "${MANIFEST_CLI_AUDIT_SOURCE:-cli}" \
            "$(manifest_execution_replay_hint "$replay_command")" \
            "$_ship_git_root" \
            "$plan_fingerprint" \
            "$workflow_rc" \
            "completed" \
            "${_MANIFEST_CLI_SHIP_LAST_GATE_STATUS:-not-run}"
    fi

    return "$workflow_rc"
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
    local subcommand="ship"

    if ! manifest_execution_parse execution_mode local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major|revision)
                increment_type="$1"; shift ;;
            resume)
                subcommand="resume"; shift ;;
            --explain) explain=true; shift ;;
            -h|--help)
                if [[ "$subcommand" == "resume" ]]; then
                    fleet_resume "--help"
                    return $?
                fi
                _render_help \
                    "manifest ship fleet <patch|minor|major|revision>|resume [-y|--yes] [--dry-run] [--local] [fleet options]" \
                    "Preview or publish a coordinated fleet release across eligible services." \
                    "Options" "  patch | minor | major | revision   Release type
  resume                   Resume stranded fleet members (push tag + tap formula for each eligible repo)
  --dry-run                Explicit preview; no writes, commits, tags, pushes, or PRs
  -y, --yes                Apply the fleet release plan
  --local                  With -y, local only — no push, no tags (ship only; not valid for resume)
  --explain                Show the built-in recipe definition without running it
  --noprep                 Skip per-service prep step (requires clean trees)
  --force-bump             Ship every release-eligible member even with no changes since its tag
                           (forward-only — new commit + tag; honors pr-gated/release-disabled)" \
                    "Flow" "  preview:  load fleet -> render per-service release plan
  apply:    load fleet -> ship release-enabled services directly
  resume:   load fleet -> per-member eligibility probe -> delegate to repo resume
  PR work:  use manifest pr fleet ... explicitly" \
                    "Examples" "  manifest ship fleet patch
  manifest ship fleet patch -y
  manifest ship fleet minor --local -y
  manifest ship fleet resume
  manifest ship fleet resume -y"
                return 0
                ;;
            *)
                fleet_args+=("$1"); shift ;;
        esac
    done

    if [[ "$subcommand" == "resume" ]]; then
        if [[ "$local_only" == "true" ]]; then
            _render_help_error \
                "manifest ship fleet resume does not support --local" \
                "manifest ship fleet resume [-y|--yes] [--dry-run]"
            return 1
        fi
        if [[ "$explain" == "true" ]]; then
            log_error "manifest ship fleet resume has no recipe to explain."
            return 1
        fi
        if [[ "$execution_mode" == "preview" ]]; then
            echo "Ship fleet resume preview — no changes written"
            fleet_resume "--dry-run" "${fleet_args[@]}"
        else
            manifest_execution_apply_header
            echo "Ship fleet resume"
            fleet_resume "-y" "${fleet_args[@]}"
        fi
        return $?
    fi

    if [[ -z "$increment_type" ]]; then
        _render_help_error \
            "ship fleet requires a release type" \
            "manifest ship fleet <patch|minor|major|revision>|resume [--local]"
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
