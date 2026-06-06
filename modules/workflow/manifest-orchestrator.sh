#!/bin/bash

# Manifest Orchestrator Module
# Coordinates the complete manifest workflow using atomized modules

# Orchestrator module - uses PROJECT_ROOT from core module

# Orchestrator module - modules are already sourced by manifest-core.sh

_emit_ship_status_file() {
    # Writes key=value lines to $MANIFEST_CLI_SHIP_STATUS_FILE when set.
    # Used by fleet ship to classify per-member outcomes without parsing stdout.
    [[ -n "${MANIFEST_CLI_SHIP_STATUS_FILE:-}" ]] || return 0
    : > "$MANIFEST_CLI_SHIP_STATUS_FILE" 2>/dev/null || return 0
    while [[ $# -ge 2 ]]; do
        # Defense in depth: redact in case a value ever carries a credential.
        printf '%s=%s\n' "$1" "$(manifest_redact "$2")" >> "$MANIFEST_CLI_SHIP_STATUS_FILE"
        shift 2
    done
}

# Run one ship step, recording its boundary in the per-run diagnostic log
# (§5.6). Captures the step's stderr to a scratch file so it can be appended to
# the log (redacted by manifest_ship_log_step) for forensic replay, then
# replays that stderr to the terminal so the operator still sees it. Tracks the
# step label in _MANIFEST_CLI_SHIP_LAST_STEP so a failing run's log footer and
# the failure report agree on where the ship stopped. Returns the step's own
# exit status, so callers keep their existing `if ! _ship_step ...; then` flow.
#
# Stderr is redirected to a file (not tee'd through a process substitution) so
# the capture is exact and race-free: an async tee can outlive the step and
# interleave with the next one, which would corrupt a forensic record. The
# tradeoff is that a step's stderr surfaces after the step finishes rather than
# streaming live — acceptable for these discrete, short-lived boundaries.
# Usage: _manifest_ship_step STEP cmd [args...]
_manifest_ship_step() {
    local step="$1"; shift
    _MANIFEST_CLI_SHIP_LAST_STEP="$step"

    # No log this run (logging disabled or dir uncreatable) → run plainly.
    if [ -z "${MANIFEST_CLI_SHIP_LOG_FILE:-}" ]; then
        "$@"
        return $?
    fi

    local err_file rc
    err_file="$(mktemp "$(manifest_make_scratch_path ship-log)/stderr.XXXXXXXX" 2>/dev/null || true)"
    if [ -z "$err_file" ]; then
        "$@"
        rc=$?
        manifest_ship_log_step "$step" "$rc"
        return $rc
    fi

    # Capture stderr synchronously, then replay it to the terminal.
    "$@" 2>"$err_file"
    rc=$?
    cat "$err_file" >&2 2>/dev/null || true
    manifest_ship_log_step "$step" "$rc" "$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$err_file" 2>/dev/null || true
    return $rc
}

emit_ship_failure_report() {
    local failure_step="$1"
    local start_sha="$2"
    local version="$3"
    local tag_name="$4"
    local push_status="$5"
    local homebrew_status="$6"

    local branch upstream ahead behind commits_created
    branch="$(git branch --show-current 2>/dev/null || echo "unknown")"
    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "none")"
    ahead="unknown"
    behind="unknown"
    if [ "$upstream" != "none" ]; then
        local lr_counts=""
        lr_counts="$(git rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "")"
        if [ -n "$lr_counts" ]; then
            behind="$(echo "$lr_counts" | awk '{print $1}')"
            ahead="$(echo "$lr_counts" | awk '{print $2}')"
        fi
    fi

    commits_created="unknown"
    if [ -n "$start_sha" ] && git cat-file -e "$start_sha^{commit}" 2>/dev/null; then
        commits_created="$(git rev-list --count "${start_sha}..HEAD" 2>/dev/null || echo "unknown")"
    fi

    echo ""
    echo "🚨 Ship Failure Report"
    echo "======================"
    echo "   failed step:        ${failure_step}"
    echo "   target version:     ${version:-unknown}"
    echo "   commits created:    ${commits_created}"
    echo "   tag:                ${tag_name:-none}"
    echo "   push status:        ${push_status}"
    echo "   homebrew status:    ${homebrew_status}"
    echo "   branch:             ${branch}"
    echo "   upstream:           ${upstream}"
    echo "   ahead/behind:       ${ahead}/${behind}"
    echo "   start commit:       ${start_sha:-unknown}"
    echo ""
    echo "📋 Git status snapshot:"
    git status --short --branch 2>/dev/null || echo "   (unavailable)"
    echo ""
    echo "🛠️  Recovery commands:"
    if [[ "$push_status" == "success" && "$failure_step" =~ ^(homebrew_|github_release) ]]; then
        echo "   Release artifacts are already pushed. Do not delete the tag or hard-reset unless you are intentionally rolling back a public release."
        echo "   Resume:      manifest ship repo resume"
        echo "   Retry branch push if needed: git push origin ${branch}"
        if [ -n "$tag_name" ] && [ "$tag_name" != "none" ]; then
            echo "   Verify tag:  git ls-remote --tags origin ${tag_name}"
        fi
    elif [ -n "$tag_name" ] && [ "$tag_name" != "none" ]; then
        echo "   Retry push:  git push origin ${branch} ${tag_name}"
        echo "   Resume:      manifest ship repo resume"
        echo "   Remove tag:  git tag -d ${tag_name}"
    else
        echo "   Retry push:  git push origin ${branch}"
    fi
    if [ -n "$start_sha" ] && ! [[ "$push_status" == "success" && "$failure_step" =~ ^(homebrew_|github_release) ]]; then
        echo "   Roll back:   git reset --hard ${start_sha}"
    fi
    echo ""

    _emit_ship_status_file \
        result failed \
        failure_step "$failure_step" \
        version "${version:-}" \
        tag "${tag_name:-}" \
        push_status "$push_status" \
        homebrew_status "$homebrew_status"

    # Close the per-run diagnostic log (§5.6) on the failure path, recording
    # the step the ship stopped at so resume can report "picking up from step X".
    manifest_ship_log_end "failed" "$failure_step"
}

manifest_should_wait_for_github_actions() {
    ! is_falsy "${MANIFEST_CLI_GITHUB_ACTIONS_WAIT:-false}"
}

manifest_check_github_actions_for_head() {
    local head_sha="${1:-}"
    local wait_seconds="${MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS:-600}"
    local poll_seconds="${MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS:-5}"
    local elapsed=0
    local run_id=""

    if ! manifest_should_wait_for_github_actions; then
        echo "GitHub Actions: skipped (disabled by MANIFEST_CLI_GITHUB_ACTIONS_WAIT)"
        return 2
    fi
    if [[ -z "$head_sha" ]]; then
        echo "GitHub Actions: skipped (no HEAD SHA available)"
        return 2
    fi
    if ! command -v gh >/dev/null 2>&1; then
        echo "GitHub Actions: skipped (gh not installed)"
        return 2
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "GitHub Actions: skipped (gh not authenticated)"
        return 2
    fi

    echo "🧪 Checking GitHub Actions for ${head_sha:0:7}..."
    while (( elapsed <= wait_seconds )); do
        run_id="$(gh run list --commit "$head_sha" --limit 1 --json databaseId --jq '.[0].databaseId // ""' 2>/dev/null || true)"
        if [[ -n "$run_id" ]]; then
            break
        fi
        sleep "$poll_seconds"
        elapsed=$((elapsed + poll_seconds))
    done

    if [[ -z "$run_id" ]]; then
        echo "GitHub Actions: unavailable (no workflow run found within ${wait_seconds}s)"
        return 2
    fi

    echo "   Run: $run_id"
    if gh run watch "$run_id" --exit-status --interval "$poll_seconds"; then
        echo "GitHub Actions: passed"
        return 0
    fi

    echo "GitHub Actions: failed"
    echo "   Inspect: gh run view $run_id --log-failed"
    return 1
}

# -----------------------------------------------------------------------------
# Release gate — block a release until verification passes.
# -----------------------------------------------------------------------------
# One self-describing policy, MANIFEST_CLI_RELEASE_GATE (YAML: release.gate):
#   none        no verification (loud + audited bypass)
#   local-tests run the project's test command before any mutation (default)
#   remote-ci   require the pushed commit's GitHub checks to be green before
#               the GitHub Release / Homebrew publish
#   all         local-tests AND remote-ci
#
# The gate runs per repository, so a fleet ship verifies each member against its
# own config and its own commit — preserving fleet version independence.
#
# Phases:
#   pre-bump   local-tests (fail-fast, before any version mutation); also emits
#              the bypass notice for `none`.
#   post-push  remote-ci (after the commit+tag are pushed, before publishing).

# Echo the normalized policy. Defaults to local-tests; rejects unknown values
# (return 2) so a typo can never silently disable the gate.
manifest_release_gate_policy() {
    local norm
    norm="$(normalize_enum_value "${MANIFEST_CLI_RELEASE_GATE:-local-tests}")"
    case "$norm" in
        none|local-tests|remote-ci|all) printf '%s' "$norm" ;;
        *)
            log_error "Invalid release_gate '${MANIFEST_CLI_RELEASE_GATE}'. Expected: none, local-tests, remote-ci, all."
            return 2
            ;;
    esac
}

# Echo the normalized gate test tier (smoke|full). Defaults to full so the
# invariant holds — nothing releases without a full run unless a repo explicitly
# opts its local gate down. Rejects unknown values (return 2) like the policy
# normalizer, so a typo can never silently shrink what the gate runs.
manifest_release_gate_tier() {
    local norm
    norm="$(normalize_enum_value "${MANIFEST_CLI_RELEASE_GATE_TIER:-full}")"
    case "$norm" in
        smoke|full) printf '%s' "$norm" ;;
        *)
            log_error "Invalid release_gate_tier '${MANIFEST_CLI_RELEASE_GATE_TIER}'. Expected: smoke, full."
            return 2
            ;;
    esac
}

# Resolve the command run for the local-tests phase. Configured command wins;
# otherwise auto-detect ./scripts/run-tests.sh and pass the gate tier through to
# it (arg 1, already normalized to smoke|full). Returns 1 if none resolvable.
# The command is executed directly as the gate action — never interpolated into
# another command (no eval). It carries the same trust as the repo's own test
# tooling, which a release already runs. A configured command owns its own
# tiering, so the tier is appended only on the auto-detect path.
#
# The gate runs --jobs 1 (serial): it executes on whatever host the user ships
# from, and GNU parallel (run-tests.sh's parallel dependency) is provisioned
# only in the environments we control — the test container and CI. Keeping the
# gate serial means shipping never requires parallel on a developer's machine.
# Local-ship speed comes from the tier (smoke), not parallelism.
_manifest_release_gate_test_command() {
    local tier="${1:-full}"
    local configured="${MANIFEST_CLI_RELEASE_GATE_COMMAND:-}"
    if [[ -n "${configured//[[:space:]]/}" ]]; then
        printf '%s' "$configured"
        return 0
    fi
    if [[ -x "${PROJECT_ROOT:-$PWD}/scripts/run-tests.sh" ]]; then
        # --no-cache: the release gate always executes the suite. The TTL'd
        # green-run cache (§5.10) accelerates dev/CI loops, but nothing releases
        # on a cached result — the gate must observe the tests passing here, now.
        printf '%s' "./scripts/run-tests.sh --tier ${tier} --jobs 1 --no-cache"
        return 0
    fi
    return 1
}

# Durable gate disposition, mirroring _MANIFEST_SHIP_LAST_HOMEBREW_STATUS. The
# final ship status-file emit (which truncates and rewrites) reads these so the
# audit record — including a `none` bypass or an `unverified` skip — survives a
# successful run, not just a failure.
_MANIFEST_CLI_SHIP_LAST_GATE_STATUS="not-run"
_MANIFEST_CLI_SHIP_LAST_GATE_POLICY=""

# Run a release-gate verification command in a clean room.
#
# By the time the gate fires, the ship process has sourced every module
# (exporting ~160 manifest_* shell functions) and loaded config (exporting
# ~130 MANIFEST_CLI_* vars, plus PROJECT_ROOT, GIT_*, MANIFEST_CLI_AUTO_CONFIRM,
# …). A child that inherits any of it sees the releaser's internal state, not a
# fresh shell, and hermetic tests fail spuriously: an exported manifest_*
# function resolved against a half-initialized child (status 127), AUTO_CONFIRM=1
# suppressing a confirmation under test, or a leaked PROJECT_ROOT redirecting a
# test's sandboxed git/status checks at the real repo.
#
# Prefix-scrubbing one variable family at a time is whack-a-mole, so run the
# command in a true clean room: env -i drops ALL inherited state (every var and
# every exported function) and we rebuild only the minimal environment a
# developer or CI shell provides — PATH (locate bats/bash/git), HOME (git config
# and test sandboxing), TMPDIR (bats scratch), locale, and a few standard vars.
# Verified to run the suite green even with the full ship environment present.
_manifest_release_gate_exec() {
    local gate_root="$1" cmd="$2"
    env -i \
        PATH="${PATH-}" \
        HOME="${HOME-}" \
        USER="${USER-}" \
        LOGNAME="${LOGNAME-}" \
        SHELL="${SHELL-}" \
        TERM="${TERM-}" \
        TMPDIR="${TMPDIR-}" \
        LANG="${LANG-}" \
        LC_ALL="${LC_ALL-}" \
        LC_CTYPE="${LC_CTYPE-}" \
        TZ="${TZ-}" \
        bash -c "cd \"\$1\" && $cmd" _ "$gate_root"
}

manifest_release_gate_run() {
    local phase="$1"
    local policy
    policy="$(manifest_release_gate_policy)" || return 1
    _MANIFEST_CLI_SHIP_LAST_GATE_POLICY="$policy"

    case "$phase" in
        pre-bump)
            case "$policy" in
                none)
                    log_warning "Release gate disabled (release_gate=none) — publishing without test verification."
                    _MANIFEST_CLI_SHIP_LAST_GATE_STATUS="bypassed"
                    ;;
                local-tests|all)
                    local tier
                    tier="$(manifest_release_gate_tier)" || return 1
                    local cmd
                    if ! cmd="$(_manifest_release_gate_test_command "$tier")"; then
                        # Nothing to run: a repo without a discoverable test
                        # command can't be gated by local-tests. Warn and
                        # proceed rather than block — teams that need hard
                        # enforcement set release_gate_command or use remote-ci.
                        log_warning "Release gate (local-tests): no test command found; proceeding without test verification."
                        log_warning "Set release_gate_command (MANIFEST_CLI_RELEASE_GATE_COMMAND) or add ./scripts/run-tests.sh to enforce."
                        _MANIFEST_CLI_SHIP_LAST_GATE_STATUS="unverified"
                        return 0
                    fi
                    local gate_root="${PROJECT_ROOT:-$PWD}"
                    if [[ ! -d "$gate_root" ]]; then
                        log_error "Release gate: PROJECT_ROOT '$gate_root' is not a directory."
                        return 1
                    fi
                    echo "🧪 Release gate: running tests before release (${cmd})..."
                    if ( _manifest_release_gate_exec "$gate_root" "$cmd" ); then
                        echo "✅ Release gate: tests passed."
                        _MANIFEST_CLI_SHIP_LAST_GATE_STATUS="verified-local"
                    else
                        log_error "Release gate failed: '${cmd}' returned non-zero. No version changes were made."
                        return 1
                    fi
                    ;;
                remote-ci) : ;;  # handled in post-push
            esac
            ;;
        post-push)
            case "$policy" in
                remote-ci|all)
                    local head_sha rc
                    head_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
                    # The gate's whole purpose is to wait for CI, so enable the
                    # waiter for this call regardless of the global default.
                    MANIFEST_CLI_GITHUB_ACTIONS_WAIT=true \
                        manifest_check_github_actions_for_head "$head_sha"
                    rc=$?
                    if [[ "$rc" -eq 0 ]]; then
                        echo "✅ Release gate: remote CI is green."
                        _MANIFEST_CLI_SHIP_LAST_GATE_STATUS="verified-remote"
                    elif [[ "$rc" -eq 1 ]]; then
                        log_error "Release gate failed: remote CI did not pass for HEAD. Publish withheld."
                        return 1
                    else
                        # rc=2: no run found / gh unavailable. Under a strict gate
                        # this is a hard stop, not a silent pass.
                        log_error "Release gate (remote-ci) could not confirm a green CI run for HEAD."
                        log_error "Ensure CI is configured and gh is authenticated, or set release_gate=none to bypass."
                        return 1
                    fi
                    ;;
                none|local-tests) : ;;
            esac
            ;;
    esac
    return 0
}

manifest_should_create_github_release() {
    ! is_falsy "${MANIFEST_CLI_GITHUB_RELEASE_ENABLED:-true}"
}

manifest_github_release_notes_for_version() {
    local version="$1"
    local changelog="${PROJECT_ROOT:-$PWD}/CHANGELOG.md"
    local notes=""

    if [[ -f "$changelog" ]]; then
        notes="$(awk -v version="$version" '
            $0 ~ "^## \\[" version "\\]" { found = 1; next }
            found && $0 ~ "^## \\[" { exit }
            found { print }
        ' "$changelog" 2>/dev/null || true)"
    fi

    if [[ -z "${notes//[[:space:]]/}" ]]; then
        notes="Release v${version}. See CHANGELOG.md for release history."
    fi

    printf '%s\n' "$notes"
}

manifest_github_origin_repo_slug() {
    local repo_url=""
    repo_url="$(git -C "${PROJECT_ROOT:-$PWD}" remote get-url origin 2>/dev/null || echo "")"

    if [[ "$repo_url" =~ ^git@github\.com:([^/]+)/([^/]+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "$repo_url" =~ ^https?://github\.com/([^/]+)/([^/]+)$ ]]; then
        local org="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]%.git}"
        echo "${org}/${repo}"
        return 0
    fi

    echo ""
    return 1
}

manifest_create_github_release_for_tag() {
    local version="$1"
    local tag_name="$2"
    local repo_slug title notes

    if ! manifest_should_create_github_release; then
        echo "GitHub Release: skipped (disabled by MANIFEST_CLI_GITHUB_RELEASE_ENABLED)"
        return 2
    fi
    if [[ -z "$version" || -z "$tag_name" || "$tag_name" == "none" ]]; then
        echo "GitHub Release: skipped (no release tag available)"
        return 2
    fi
    if ! command -v gh >/dev/null 2>&1; then
        echo "GitHub Release: skipped (gh not installed)"
        return 2
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "GitHub Release: skipped (gh not authenticated)"
        return 2
    fi

    repo_slug="$(manifest_github_origin_repo_slug || echo "")"
    if [[ -z "$repo_slug" ]]; then
        echo "GitHub Release: skipped (origin is not a GitHub repository)"
        return 2
    fi

    if gh release view "$tag_name" --repo "$repo_slug" >/dev/null 2>&1; then
        echo "GitHub Release: exists ($tag_name)"
        return 0
    fi

    title="$(manifest_repo_display_name) ${tag_name}"
    notes="$(manifest_github_release_notes_for_version "$version")"

    local args=(release create "$tag_name" --repo "$repo_slug" --title "$title" --notes "$notes")
    if is_truthy "${MANIFEST_CLI_GITHUB_RELEASE_DRAFT:-false}"; then
        args+=(--draft)
    fi
    if is_truthy "${MANIFEST_CLI_GITHUB_RELEASE_PRERELEASE:-false}"; then
        args+=(--prerelease)
    fi

    echo "🐙 Creating GitHub Release..."
    echo "   Repo:  $repo_slug"
    echo "   Tag:   $tag_name"
    if gh "${args[@]}"; then
        echo "GitHub Release: created ($tag_name)"
        return 0
    fi

    echo "GitHub Release: failed"
    echo "   Retry: gh release create $tag_name --repo $repo_slug --title \"$title\" --notes-file CHANGELOG.md"
    if is_truthy "${MANIFEST_CLI_GITHUB_RELEASE_REQUIRED:-false}"; then
        return 1
    fi
    return 2
}

manifest_ship_post_push_steps() {
    local new_version="$1"
    local workflow_start_sha="$2"
    local workflow_tag_name="$3"
    local workflow_push_status="${4:-success}"
    local workflow_homebrew_status="skipped"
    local workflow_github_release_status="skipped"
    _MANIFEST_SHIP_LAST_LOCAL_UPGRADE_STATUS="not_attempted"

    # Update Homebrew formula only for the Manifest CLI canonical repository.
    if [ -f "$PROJECT_ROOT/formula/manifest.rb" ] && should_update_homebrew_for_repo; then
        workflow_homebrew_status="attempted"
        echo "🍺 Updating Homebrew formula..."
        if update_homebrew_formula; then
            # Commit the formula change to this repo
            if [ -n "$(git status --porcelain formula/manifest.rb 2>/dev/null)" ]; then
                git add formula/manifest.rb
                if ! git commit -m "Update Homebrew formula to v$new_version"; then
                    workflow_homebrew_status="failed"
                    log_error "Failed to commit Homebrew formula update."
                    emit_ship_failure_report "homebrew_commit" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
                    return 1
                fi
                if ! git push origin "${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"; then
                    workflow_homebrew_status="failed"
                    log_error "Failed to push Homebrew formula commit."
                    emit_ship_failure_report "homebrew_push" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
                    return 1
                fi
            fi
            workflow_homebrew_status="success"
            echo "✅ Homebrew formula updated"
        else
            workflow_homebrew_status="failed"
            log_error "Homebrew formula update failed; aborting ship workflow."
            emit_ship_failure_report "homebrew_update" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi
        echo ""
    elif [ -f "$PROJECT_ROOT/formula/manifest.rb" ]; then
        workflow_homebrew_status="skipped_non_canonical_repo"
        local origin_slug=""
        origin_slug="$(manifest_origin_repo_slug || echo "unknown")"
        echo "🍺 Skipping Homebrew formula update for non-canonical repo: ${origin_slug}"
        echo ""
    fi

    workflow_github_release_status="attempted"
    if manifest_create_github_release_for_tag "$new_version" "$workflow_tag_name" "$release_type" "$previous_version"; then
        workflow_github_release_status="success"
    else
        local github_release_rc=$?
        if [[ "$github_release_rc" -eq 1 ]]; then
            workflow_github_release_status="failed"
            emit_ship_failure_report "github_release" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi
        workflow_github_release_status="skipped"
    fi
    echo ""

    # Only run when this ship actually pushed a new formula to the tap; otherwise
    # brew upgrades against stale tap state and reports a misleading "upgraded to vN".
    if [[ "$workflow_homebrew_status" == "success" ]]; then
        echo "🔄 Upgrading local Manifest CLI installation..."
        if command -v brew &>/dev/null; then
            if ! manifest_install_paths_is_brew_managed; then
                echo "⚠️  Local manifest is not installed via Homebrew — skipping upgrade"
                echo "   Run: brew install fidenceio/tap/manifest"
                _MANIFEST_SHIP_LAST_LOCAL_UPGRADE_STATUS="skipped_not_homebrew"
            else
                # Trust the formula before upgrading. Once tap-trust is enforced
                # (HOMEBREW_REQUIRE_TAP_TRUST=1) Homebrew ignores an untrusted
                # formula and `brew upgrade` silently no-ops — the "upgraded to
                # vN" line below would then print against a stale install.
                # Non-fatal; older brew has no `trust`. (§7.6)
                manifest_install_paths_ensure_brew_trust
                case $? in
                    1) echo "   ⚠️  Could not auto-trust the Manifest formula; if Homebrew enforces tap-trust the upgrade may be ignored. Run: brew trust --formula $(manifest_install_paths_homebrew_formula)" ;;
                esac
                if brew update &>/dev/null && brew upgrade manifest 2>&1; then
                    echo "✅ Local installation upgraded to v$new_version via Homebrew"
                    _MANIFEST_SHIP_LAST_LOCAL_UPGRADE_STATUS="success"
                    manifest_ship_restore_tap_ssh_origin
                else
                    echo "⚠️  Homebrew upgrade did not complete — try 'brew update && brew upgrade manifest' manually"
                    _MANIFEST_SHIP_LAST_LOCAL_UPGRADE_STATUS="failed"
                fi
            fi
        else
            if manifest upgrade --force 2>&1; then
                echo "✅ Local installation upgraded to v$new_version"
                _MANIFEST_SHIP_LAST_LOCAL_UPGRADE_STATUS="success"
            else
                echo "⚠️  Local upgrade did not complete — try 'manifest upgrade --force' manually"
                _MANIFEST_SHIP_LAST_LOCAL_UPGRADE_STATUS="failed"
            fi
        fi
        echo ""
    fi

    _MANIFEST_SHIP_LAST_HOMEBREW_STATUS="$workflow_homebrew_status"
    _MANIFEST_SHIP_LAST_GITHUB_RELEASE_STATUS="$workflow_github_release_status"
    return 0
}

# `brew update` / `brew upgrade` resets the tap checkout's `origin` URL back to
# the canonical HTTPS form. Future `manifest ship` runs from this canonical repo
# push the formula via the explicit `MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL` (SSH
# by default), so the push itself is unaffected — but other tooling that reads
# the tap's origin (and the user's stated preference) expects SSH. Re-assert it.
#
# Path resolution goes through manifest_install_paths_homebrew_tap_dir so that
# this code, the formula sync code, and the uninstall code all agree on where
# the tap lives — no drift between call sites.
manifest_ship_restore_tap_ssh_origin() {
    local tap_dir
    tap_dir="$(manifest_install_paths_homebrew_tap_dir)"
    [ -n "$tap_dir" ] || return 0
    [ -d "$tap_dir/.git" ] || return 0
    local ssh_url="${MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL:-git@github.com:fidenceio/homebrew-tap.git}"
    git -C "$tap_dir" remote set-url origin "$ssh_url" 2>/dev/null || true
}

manifest_ship_followup_has_releasable_changes() {
    local tag_name="${1:-}"
    if [[ -z "$tag_name" || "$tag_name" == "none" ]]; then
        return 0
    fi

    if ! git rev-parse "${tag_name}^{commit}" >/dev/null 2>&1; then
        return 0
    fi

    local changed_files dirty_files
    changed_files="$(git diff --name-only "${tag_name}..HEAD" -- . ':(exclude)formula/manifest.rb' 2>/dev/null || true)"
    dirty_files="$(git status --porcelain 2>/dev/null | awk '$2 != "formula/manifest.rb" && $0 != "" { print; found=1 } END { exit found ? 0 : 1 }' || true)"

    [[ -n "$changed_files" || -n "$dirty_files" ]]
}

manifest_ship_should_run_followup_patch() {
    local increment_type="$1"
    local publish_release="${2:-false}"
    local tag_name="${3:-}"

    [[ "$publish_release" == "true" ]] || return 1
    [[ "$increment_type" != "patch" ]] || return 1
    [[ -z "${MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE:-}" ]] || return 1

    if is_falsy "${MANIFEST_CLI_SHIP_FOLLOWUP_PATCH:-true}"; then
        return 1
    fi

    if ! should_update_homebrew_for_repo; then
        return 1
    fi

    if ! manifest_ship_followup_has_releasable_changes "$tag_name"; then
        return 1
    fi

    return 0
}

manifest_ship_run_followup_patch() {
    echo ""
    echo "🔁 Running follow-up patch under the upgraded Manifest CLI..."
    echo "   Reason: canonical CLI ships may upgrade release behavior mid-run; the follow-up patch exercises the newly installed version once."
    MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE=1 manifest_exec_manifest ship repo patch -y
}

# Probes whether the current repo is in a resume-eligible state. Pure function:
# no log_error, no side effects, no PROJECT_ROOT mutation. Caller is responsible
# for cd'ing into the repo first; uses PROJECT_ROOT if set, else pwd.
#
# Echoes a single pipe-separated line: <code>|<version>|<tag>|<detail>
# Codes:
#   eligible          - VERSION present + local tag matches + ancestor of HEAD + clean modulo formula
#   no-version        - VERSION file missing or empty
#   no-branch         - detached HEAD
#   no-local-tag      - VERSION present, but expected local tag does not exist
#   tag-not-ancestor  - tag exists but does not point at an ancestor of HEAD
#   dirty-tree        - working tree has changes outside formula/manifest.rb
#
# Returns 0 for "eligible", 1 for any non-eligible code.
manifest_ship_repo_resume_eligible() {
    local project_root="${PROJECT_ROOT:-$(pwd)}"
    local version="" tag_name tag_commit branch dirty_files non_formula_count

    if [[ -r "$project_root/VERSION" ]]; then
        version="$(tr -d '[:space:]' < "$project_root/VERSION" 2>/dev/null || echo "")"
    fi
    if [[ -z "$version" ]]; then
        echo "no-version|||VERSION file missing or empty"
        return 1
    fi
    tag_name="$(manifest_release_tag_name "$version")"

    branch="$(git -C "$project_root" branch --show-current 2>/dev/null || echo "")"
    if [[ -z "$branch" ]]; then
        echo "no-branch|$version|$tag_name|detached HEAD"
        return 1
    fi

    if ! tag_commit="$(git -C "$project_root" rev-parse "${tag_name}^{commit}" 2>/dev/null)"; then
        echo "no-local-tag|$version|$tag_name|local tag missing"
        return 1
    fi
    if ! git -C "$project_root" merge-base --is-ancestor "$tag_commit" HEAD 2>/dev/null; then
        echo "tag-not-ancestor|$version|$tag_name|tag is not an ancestor of HEAD"
        return 1
    fi

    dirty_files="$(git -C "$project_root" status --porcelain 2>/dev/null || true)"
    non_formula_count=$(printf '%s\n' "$dirty_files" \
        | awk '$2 != "formula/manifest.rb" && $0 != ""' \
        | grep -c . 2>/dev/null || true)
    non_formula_count="${non_formula_count:-0}"
    if (( non_formula_count > 0 )); then
        echo "dirty-tree|$version|$tag_name|${non_formula_count} unrelated dirty path(s)"
        return 1
    fi

    echo "eligible|$version|$tag_name|"
    return 0
}

# Pre-tag re-entrancy probe (sibling to the post-tag resume probe above).
# Detects an interrupted ship — VERSION bumped but not yet committed — so a
# re-run resumes in place instead of bumping a second time. Output:
#   "<state>|<version>|<detail>"
#     fresh            normal run; proceed with the bump
#     resume-in-place  VERSION was bumped to <version>, is uncommitted, and no
#                      tag exists yet -> skip the re-bump, commit/tag <version>
#     tagged           <version> already has a release tag -> post-tag resume
#                      domain; caller should defer to 'manifest ship repo resume'
# Only the exact, unambiguous signal triggers resume-in-place: VERSION dirty vs
# HEAD AND equal to what THIS increment would produce from the committed
# version. A manual or divergent VERSION edit stays "fresh" so existing
# behavior (auto-commit + bump) is preserved.
manifest_ship_repo_pretag_state() {
    local increment_type="$1"
    local project_root="${PROJECT_ROOT:-$(pwd)}"
    local working committed expected tag_name tmp

    [[ -r "$project_root/VERSION" ]] || { echo "fresh||no VERSION"; return 0; }
    working="$(tr -d '[:space:]' < "$project_root/VERSION" 2>/dev/null || echo "")"
    [[ -n "$working" ]] || { echo "fresh||empty VERSION"; return 0; }

    # VERSION unchanged vs HEAD -> not a bump-in-progress.
    if git -C "$project_root" diff --quiet HEAD -- VERSION 2>/dev/null; then
        echo "fresh|$working|VERSION matches HEAD"
        return 0
    fi

    committed="$(git -C "$project_root" show HEAD:VERSION 2>/dev/null | tr -d '[:space:]' || echo "")"
    # What THIS increment would produce from the committed version.
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/manifest-pretag.XXXXXX" 2>/dev/null)" || { echo "fresh|$working|"; return 0; }
    printf '%s\n' "$committed" > "$tmp/VERSION"
    expected="$( (cd "$tmp" && get_next_version "$increment_type" 2>/dev/null) || echo "" )"
    rm -rf "$tmp" 2>/dev/null

    if [[ -n "$expected" && "$working" == "$expected" ]]; then
        tag_name="$(manifest_release_tag_name "$working" 2>/dev/null || echo "")"
        if [[ -n "$tag_name" ]] && git -C "$project_root" rev-parse "${tag_name}^{commit}" >/dev/null 2>&1; then
            echo "tagged|$working|release tag ${tag_name} already exists"
            return 0
        fi
        echo "resume-in-place|$working|VERSION bumped to ${working}, uncommitted, no tag"
        return 0
    fi

    echo "fresh|$working|VERSION dirty but not a ${increment_type} bump of ${committed:-?}"
    return 0
}

manifest_ship_repo_resume() {
    if ! ensure_repository_root; then
        log_error "Repository root validation failed"
        return 1
    fi
    PROJECT_ROOT="$(pwd)"
    export PROJECT_ROOT

    # Resume is a mutating apply (push, post-push steps, metadata) and reaches
    # the same shared per-repo state as a normal ship, so it must hold the
    # per-repo single-flight lock too. Reuses the ship module's lock helpers,
    # which honor the fleet-child / follow-up-patch exemptions and the
    # MANIFEST_CLI_REPO_LOCK_HELD marker. Released on any exit (mirrors the
    # main ship path's trap). The helper lives in manifest-ship.sh and the
    # release primitive in manifest-fleet.sh; the real loader sources both
    # before any of these run, but this module is also loaded in isolation
    # (unit tests, a sourced subset), so guard on the helper's presence —
    # matching the declare-F guards used elsewhere in this module — rather
    # than hard-failing under set -e when the lock stack isn't loaded.
    local repo_lock=""
    if declare -F _manifest_ship_repo_lock_acquire >/dev/null 2>&1; then
        if ! _manifest_ship_repo_lock_acquire; then
            return 1
        fi
        repo_lock="${_MANIFEST_CLI_SHIP_REPO_LOCK_DIR:-}"
    fi
    if [ -n "$repo_lock" ]; then
        trap '_fleet_lock_release "${repo_lock:-}"' RETURN
        trap '_fleet_lock_release "${repo_lock:-}"; trap - INT; kill -INT $$' INT
        trap '_fleet_lock_release "${repo_lock:-}"; trap - TERM; kill -TERM $$' TERM
    fi

    local probe code version tag_name detail
    probe="$(manifest_ship_repo_resume_eligible)"
    IFS='|' read -r code version tag_name detail <<<"$probe"
    case "$code" in
        no-version)
            log_error "Cannot resume ship: VERSION file is missing or empty."
            return 1
            ;;
        no-branch)
            log_error "Cannot resume ship: detached HEAD is not supported."
            return 1
            ;;
        no-local-tag)
            log_error "Cannot resume ship: local tag ${tag_name} does not exist."
            log_error "Run a normal ship workflow or create the release tag first."
            return 1
            ;;
        tag-not-ancestor)
            log_error "Cannot resume ship: ${tag_name} does not point at an ancestor of HEAD."
            return 1
            ;;
        dirty-tree)
            log_error "Cannot resume ship with unrelated working-tree changes:"
            git status --porcelain | awk '$2 != "formula/manifest.rb" && $0 != ""'
            return 1
            ;;
        eligible) ;;
        *)
            log_error "Cannot resume ship: unknown probe state ($code)."
            return 1
            ;;
    esac

    local tag_commit branch dirty_files remote_branch_status remote_tag_status
    tag_commit="$(git rev-parse "${tag_name}^{commit}" 2>/dev/null)"
    branch="$(git branch --show-current 2>/dev/null || echo "")"
    dirty_files="$(git status --porcelain 2>/dev/null || true)"

    remote_branch_status="unknown"
    remote_tag_status="unknown"
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        remote_branch_status="present"
    else
        remote_branch_status="missing or unreachable"
    fi
    if git ls-remote --exit-code --tags origin "$tag_name" >/dev/null 2>&1; then
        remote_tag_status="present"
    else
        remote_tag_status="missing or unreachable"
    fi

    echo ""
    echo "Ship resume"
    echo "==========="
    echo "   version:       $version"
    echo "   tag:           $tag_name ($tag_commit)"
    echo "   branch:        $branch"
    echo "   remote branch: $remote_branch_status"
    echo "   remote tag:    $remote_tag_status"
    if [[ -n "$dirty_files" ]]; then
        echo "   working tree:  formula/manifest.rb pending"
    else
        echo "   working tree:  clean"
    fi

    # Read the prior run's diagnostic log (§5.6) to report where it stopped, so
    # resume tells the operator which step it is picking up from rather than
    # leaving them to guess. Best-effort: silent if no prior log exists.
    local prior_log prior_step
    prior_log="$(manifest_ship_log_latest)"
    if [ -n "$prior_log" ]; then
        prior_step="$(manifest_ship_log_last_step "$prior_log")"
        echo "   prior run log: $prior_log"
        [ -n "$prior_step" ] && echo "   picking up from step: $prior_step"
    fi
    echo ""

    if ! push_changes "$version"; then
        log_error "Resume failed while pushing branch/tag."
        emit_ship_failure_report "resume_push" "$(git rev-parse HEAD 2>/dev/null || echo "")" "$version" "$tag_name" "failed" "skipped"
        return 1
    fi
    echo ""

    if ! manifest_ship_post_push_steps "$version" "$(git rev-parse HEAD 2>/dev/null || echo "")" "$tag_name" "success"; then
        return 1
    fi

    update_repository_metadata
    echo ""
    echo "✅ Ship resume completed for v${version}"
}

# Main ship workflow: version bump, docs, commit, tag, push, Homebrew.
# With publish_release=false this stops short of tag/push (the --local path).
manifest_ship_workflow() {
    local increment_type="$1"
    local interactive="$2"
    local publish_release="${3:-false}"
    local workflow_start_sha=""
    local workflow_tag_name="none"
    local workflow_push_status="not_attempted"
    local workflow_homebrew_status="not_applicable"
    local workflow_github_release_status="not_applicable"
    local workflow_actions_status="not_applicable"
    local workflow_version_commit_sha=""

    if [ "$publish_release" = "true" ]; then
        workflow_homebrew_status="skipped"
    fi
    
    # Ensure we're running from repository root
    if ! ensure_repository_root; then
        log_error "Repository root validation failed"
        return 1
    fi
    
    # Update PROJECT_ROOT to the actual current directory (in case we changed)
    PROJECT_ROOT="$(pwd)"
    export PROJECT_ROOT
    workflow_start_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"

    # Earliest clean halt point: a publish pushes the default-branch ref, so
    # refuse before any mutation if HEAD is on a different branch (see
    # manifest_assert_release_branch). Local/prep mode never pushes, so it's exempt.
    if [ "$publish_release" = "true" ]; then
        if ! manifest_assert_release_branch "$PROJECT_ROOT"; then
            log_error "Aborting ship: HEAD is not on the release branch."
            return 1
        fi
    fi

    # Determine version increment type
    if [ -z "$increment_type" ]; then
        increment_type="patch"
    fi
    
    # Open the per-run diagnostic log (§5.6). Best-effort: never aborts a ship.
    local _ship_log_path _ship_log_mode
    [ "$publish_release" = "true" ] && _ship_log_mode="publish" || _ship_log_mode="local"
    _ship_log_path="$(manifest_ship_log_begin "manifest ship repo ${increment_type} (${_ship_log_mode})")"

    echo "🚀 Starting automated Manifest process..."
    echo ""
    [ -n "$_ship_log_path" ] && echo "   run log:           $_ship_log_path"
    echo "   git repo:          $(git remote get-url origin 2>/dev/null || echo 'none')"
    echo "   git branch (remote): $(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo 'none')"
    echo "   git branch (local):  $(git branch --show-current 2>/dev/null || echo 'unknown')"
    echo "   working folder:    $PROJECT_ROOT"
    echo "   docs folder:       $(get_docs_folder "$PROJECT_ROOT")"
    echo "   archive folder:    $(get_zarchive_dir)"
    echo "   previous version:  $(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo 'unknown')"
    echo ""

    # Ensure required files exist before proceeding
    echo "🔍 Checking for required files..."
    if ! ensure_required_files "$PROJECT_ROOT"; then
        log_error "Failed to ensure required files are present"
        return 1
    fi
    echo ""
    
    # Interactive confirmation for safety
    local interactive_mode=false
    
    # Enable interactive mode with explicit flag values.
    if [ "$interactive" = "-i" ] || [ "$interactive" = "--interactive" ] || [ "$interactive" = "true" ] || [ "$interactive" = "1" ]; then
        interactive_mode=true
    fi
    
    # Enable interactive mode if environment variable is set to true
    if is_truthy "${MANIFEST_CLI_INTERACTIVE_MODE:-false}"; then
        interactive_mode=true
    fi
    
    # Disable interactive mode if not in a terminal (CI/CD environments)
    if [ ! -t 0 ]; then
        interactive_mode=false
    fi
    
    if [ "$interactive_mode" = "true" ]; then
        echo "🔍 Safety Check - CI/CD & Collaborative Environment Protection"
        echo "=============================================================="
        echo ""
        echo "📋 Version increment type: $increment_type"
        echo "📍 Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
        echo "🏷️  Current version: $(cat VERSION 2>/dev/null || echo 'unknown')"
        echo ""
        echo "⚠️  This will perform a complete version bump workflow including:"
        echo "   • Sync with remote repository"
        echo "   • Bump version to next $increment_type"
        echo "   • Generate documentation and release notes"
        echo "   • Commit local changes"
        if [ "$publish_release" = "true" ]; then
            echo "   • Create Git tag and push to remote repository"
            echo "   • Update Homebrew formula"
        else
            echo "   • No remote pushes/tags (local-only prep mode)"
        fi
        echo ""
        echo "🤔 What would you like to do?"
        echo ""
        echo "   1) 🧪 Run test/dry-run first (recommended)"
        echo "   2) 🚀 Go ahead and execute $increment_type version bump now"
        echo "   3) ❌ Cancel and exit"
        echo ""
        
        while true; do
            read -r -p "   Enter your choice (1-3): " choice
            case $choice in
                1)
                    echo ""
                    echo "🧪 Running test/dry-run first..."
                    echo "================================"
                    manifest_test_dry_run "$increment_type"
                    echo ""
                    echo "🤔 Test completed. Would you like to proceed with the actual version bump?"
                    read -r -p "   Proceed with $increment_type version bump? (y/N): " proceed
                    case $proceed in
                        [Yy]|[Yy][Ee][Ss])
                            echo ""
                            echo "🚀 Proceeding with $increment_type version bump..."
                            break
                            ;;
                        *)
                            echo "❌ Version bump cancelled by user."
                            return 0
                            ;;
                    esac
                    ;;
                2)
                    echo ""
                    echo "🚀 Proceeding with $increment_type version bump..."
                    break
                    ;;
                3)
                    echo "❌ Version bump cancelled by user."
                    return 0
                    ;;
                *)
                    echo "   ❌ Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
        echo ""
    fi
    
    # Get trusted timestamp
    get_time_timestamp
    
    echo "📋 Version increment type: $increment_type"
    echo ""

    # Pre-tag re-entrancy: if a prior ship was interrupted between the version
    # bump and the commit, VERSION is already at the next value but uncommitted.
    # Resume in place (skip the re-bump) instead of double-bumping. Must run
    # BEFORE the auto-commit below, which would otherwise sweep the dirty
    # VERSION into a generic commit and destroy this signal.
    local resume_in_place=false
    local new_version=""
    local pretag_state
    pretag_state="$(manifest_ship_repo_pretag_state "$increment_type")"
    case "$pretag_state" in
        resume-in-place\|*)
            resume_in_place=true
            new_version="${pretag_state#resume-in-place|}"; new_version="${new_version%%|*}"
            log_warning "Interrupted ship detected: VERSION already bumped to ${new_version} but not committed."
            echo "↻ Resuming in place: skipping re-bump; will commit and tag ${new_version}."
            echo ""
            ;;
        tagged\|*)
            local _pt_ver="${pretag_state#tagged|}"; _pt_ver="${_pt_ver%%|*}"
            log_error "VERSION ${_pt_ver} already has a release tag; nothing to re-bump."
            log_error "Use 'manifest ship repo resume' to continue post-tag steps."
            return 1
            ;;
    esac

    # Release gate (pre-bump): run the project's tests BEFORE auto-committing,
    # syncing the remote, or any version mutation, so a failing gate leaves the
    # repo genuinely untouched. Also emits the bypass notice for `none`.
    if ! _manifest_ship_step "release_gate" manifest_release_gate_run "pre-bump"; then
        emit_ship_failure_report "release_gate" "$workflow_start_sha" "$(cat "${PROJECT_ROOT:-$PWD}/VERSION" 2>/dev/null || echo unknown)" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    echo ""

    # Check for uncommitted changes (skipped when resuming in place — the dirty
    # VERSION and any generated docs are captured by the release commit below).
    if [ "$resume_in_place" != "true" ] && [ -n "$(git status --porcelain)" ]; then
        echo "📝 Uncommitted changes detected. Committing first..."
        local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
        # Add a scope hint to the auto-commit subject so `git log --oneline`
        # alone tells you what got swept up. Hint covers tracked changes
        # AND untracked files, since `commit_changes` runs `git add .`.
        local _ac_files _ac_count _ac_first _ac_hint=""
        _ac_files="$(git status --porcelain | sed 's/^...//')"
        _ac_count=$(printf '%s\n' "$_ac_files" | grep -c .)
        _ac_first=$(printf '%s\n' "$_ac_files" | head -1)
        if [ "$_ac_count" -eq 1 ] && [ -n "$_ac_first" ]; then
            _ac_hint=" ($_ac_first)"
        elif [ "$_ac_count" -gt 1 ]; then
            _ac_hint=" ($_ac_count files: $_ac_first, ...)"
        fi
        echo "⚠️  Auto-committing $_ac_count pending file(s) into this release from $PROJECT_ROOT."
        commit_changes "Auto-commit before Manifest process$_ac_hint" "$timestamp"
        echo ""
    fi
    
    # Sync with remote. Skipped when resuming an interrupted ship: the
    # pre-interrupt run already synced before bumping, and pulling now would run
    # against the dirty uncommitted VERSION and could conflict on that very
    # file — disrupting the resume this path exists to complete.
    if [ "$resume_in_place" != "true" ]; then
        echo "🔄 Syncing with remote..."
        sync_repository
        echo ""
    else
        echo "↻ Skipping remote sync on resume (recovering local release state)."
        echo ""
    fi

    # Bump version (skipped when resuming an interrupted ship — VERSION already
    # holds the intended next value).
    if [ "$resume_in_place" != "true" ]; then
        echo "📦 Bumping version..."
        if ! _manifest_ship_step "version_bump" bump_version "$increment_type"; then
            log_error "Version bump failed"
            return 1
        fi
        new_version=""
        if [ -f "VERSION" ]; then
            new_version=$(cat VERSION)
        fi
    fi

    if [ -z "$new_version" ]; then
        log_error "Could not determine new version"
        return 1
    fi
    
    echo ""
    
    # Generate documentation using new architecture
    local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    echo "📚 Generating documentation and release notes..."
    if ! _manifest_ship_step "doc_generation" manifest_docs_generate "$new_version" "$timestamp" "$increment_type"; then
        log_error "Document generation aborted; aborting ship workflow."
        emit_ship_failure_report "doc_generation" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    echo "✅ Documentation generated successfully"
    echo ""
    
    # Archive previous version documentation to zArchive (now that new version is created)
    echo "📁 Archiving previous version documentation..."
    if ! _manifest_ship_step "archive_sweep" main_cleanup "$new_version" "$timestamp"; then
        log_error "Archive sweep aborted; aborting ship workflow."
        emit_ship_failure_report "archive_sweep" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    echo ""
    
    # Final markdown validation and fixing (before commit)
    echo "🔍 Final markdown validation and fixing..."
    if validate_project "true"; then
        echo "✅ Markdown validation completed"
    else
        echo "⚠️  Markdown validation found issues, but continuing..."
    fi
    echo ""
    
    # Commit version changes
    echo "💾 Committing version changes..."
    local pre_version_commit_sha
    pre_version_commit_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
    if ! _manifest_ship_step "version_commit" commit_changes "Bump version to $new_version" "$timestamp"; then
        log_error "Failed to commit version bump; aborting ship workflow."
        emit_ship_failure_report "version_commit" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    workflow_version_commit_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
    if [[ -z "$workflow_version_commit_sha" || "$workflow_version_commit_sha" == "$pre_version_commit_sha" ]]; then
        log_error "Version commit did not advance HEAD (pre=${pre_version_commit_sha:-unknown} post=${workflow_version_commit_sha:-unknown}); aborting ship workflow."
        emit_ship_failure_report "version_commit" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    echo ""

    # Validate repository state after commit
    echo "🔍 Validating repository state..."
    validate_repository || true
    echo ""
    
    if [ "$publish_release" = "true" ]; then
        workflow_tag_name="$(manifest_release_tag_name "$new_version")"

        # Resolve which commit the release tag should point at.
        # version_commit — the explicit "Bump version to X" commit, even when
        #                  a CHANGELOG commit follows it. Default.
        # release_head   — current HEAD at tagging time (post-CHANGELOG,
        #                  pre-Homebrew). Homebrew commits cannot be included
        #                  because update_homebrew_formula needs the GitHub
        #                  tarball SHA256 of an already-pushed tag.
        local tag_target_sha
        tag_target_sha="$(resolve_tag_target_sha "$workflow_version_commit_sha")"

        # Create git tag
        if ! _manifest_ship_step "create_tag" create_tag "$new_version" "$tag_target_sha"; then
            log_error "Tag creation failed; aborting ship workflow."
            emit_ship_failure_report "create_tag" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi
        echo ""

        # Push changes
        workflow_push_status="attempted"
        if ! _manifest_ship_step "push_changes" push_changes "$new_version"; then
            workflow_push_status="failed"
            log_error "Push failed; aborting ship workflow."
            emit_ship_failure_report "push_changes" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi
        workflow_push_status="success"
        echo ""

        # Release gate (post-push): for remote-ci/all, require the pushed
        # commit's CI to be green before publishing the GitHub Release and
        # Homebrew formula. The tag is already pushed; only the publish is gated.
        if ! _manifest_ship_step "release_gate_post_push" manifest_release_gate_run "post-push"; then
            emit_ship_failure_report "release_gate" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi

        if ! manifest_ship_post_push_steps "$new_version" "$workflow_start_sha" "$workflow_tag_name" "$workflow_push_status"; then
            return 1
        fi
        workflow_homebrew_status="${_MANIFEST_SHIP_LAST_HOMEBREW_STATUS:-skipped}"
        workflow_github_release_status="${_MANIFEST_SHIP_LAST_GITHUB_RELEASE_STATUS:-skipped}"

        workflow_actions_status="attempted"
        local workflow_final_head_sha
        workflow_final_head_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
        if manifest_check_github_actions_for_head "$workflow_final_head_sha"; then
            workflow_actions_status="passed"
        else
            local actions_rc=$?
            if [[ "$actions_rc" -eq 1 ]]; then
                workflow_actions_status="failed"
                echo "⚠️  GitHub Actions failed after publish. Release artifacts were already pushed."
            else
                workflow_actions_status="skipped"
            fi
        fi
        echo ""
    else
        echo "🧰 Prep mode complete: skipped tag/push/Homebrew publish steps."
        echo ""
    fi

    # Update repository metadata
    update_repository_metadata
    echo ""
    
    # Success message
    echo "🎉 Manifest process completed successfully!"
    echo ""
    
    # Summary
    echo "📋 Summary:"
    echo "   - Version: $new_version"
    if [ "$publish_release" = "true" ]; then
        echo "   - Tag: $workflow_tag_name"
        echo "   - Remotes: All pushed successfully"
        echo "   - GitHub Release: $workflow_github_release_status"
        echo "   - GitHub Actions: $workflow_actions_status"
    else
        echo "   - Tag: (not created in prep mode)"
        echo "   - Remotes: (no pushes in prep mode)"
    fi
    echo "   - Timestamp: $timestamp"
    echo "   - Source: $MANIFEST_CLI_TIME_SERVER ($MANIFEST_CLI_TIME_SERVER_IP)"
    echo "   - Offset: $MANIFEST_CLI_TIME_OFFSET seconds"
    echo "   - Uncertainty: ±$MANIFEST_CLI_TIME_UNCERTAINTY seconds"
    echo "   - Method: $MANIFEST_CLI_TIME_METHOD"

    _emit_ship_status_file \
        result success \
        version "$new_version" \
        tag "${workflow_tag_name:-}" \
        push_status "${workflow_push_status:-skipped}" \
        homebrew_status "${workflow_homebrew_status:-skipped}" \
        gate_status "${_MANIFEST_CLI_SHIP_LAST_GATE_STATUS:-not-run}" \
        gate_policy "${_MANIFEST_CLI_SHIP_LAST_GATE_POLICY:-}"

    # Close the per-run diagnostic log (§5.6) on the success path.
    manifest_ship_log_end "success" "${_MANIFEST_CLI_SHIP_LAST_STEP:-}"

    if manifest_ship_should_run_followup_patch "$increment_type" "$publish_release" "$workflow_tag_name"; then
        manifest_ship_run_followup_patch
    fi
}

# Test/dry-run function for safety
manifest_test_dry_run() {
    local increment_type="$1"
    local current_version=$(cat VERSION 2>/dev/null || echo "unknown")
    local next_version=""
    
    echo "🧪 Manifest Test/Dry-Run Mode"
    echo "============================="
    echo ""
    echo "   git repo:          $(git remote get-url origin 2>/dev/null || echo 'none')"
    echo "   git branch (remote): $(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo 'none')"
    echo "   git branch (local):  $(git branch --show-current 2>/dev/null || echo 'unknown')"
    echo "   working folder:    $PROJECT_ROOT"
    echo "   docs folder:       $(get_docs_folder "$PROJECT_ROOT")"
    echo "   archive folder:    $(get_zarchive_dir)"
    echo "   previous version:  $(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo 'unknown')"
    echo ""

    # Test file requirements
    echo "📁 File Requirements Testing:"
    if ensure_required_files "$PROJECT_ROOT"; then
        echo "   ✅ All required files are present or created"
    else
        echo "   ❌ Failed to ensure required files"
    fi
    echo ""
    
    # Test version increment logic
    echo "📋 Version Testing:"
    echo "   Current version: $current_version"
    
    case "$increment_type" in
        "patch")
            next_version=$(echo "$current_version" | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')
            ;;
        "minor")
            next_version=$(echo "$current_version" | awk -F. '{$2 = $2 + 1; $3 = 0;} 1' | sed 's/ /./g')
            ;;
        "major")
            next_version=$(echo "$current_version" | awk -F. '{print $1 + 1 ".0.0"}')
            ;;
        "revision")
            next_version="$current_version.1"
            ;;
    esac
    
    echo "   Next version: $next_version"
    echo "   Increment type: $increment_type"
    echo ""
    
    # Test Git status
    echo "🔍 Git Status Check:"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo "   ✅ In Git repository"
        echo "   📍 Current branch: $(git branch --show-current)"
        echo "   📡 Remote: $(git remote get-url origin 2>/dev/null || echo 'none')"
        
        # Check for uncommitted changes
        if [ -n "$(git status --porcelain)" ]; then
            echo "   ⚠️  Uncommitted changes detected"
        else
            echo "   ✅ Working directory clean"
        fi
    else
        echo "   ❌ Not in a Git repository"
    fi
    echo ""
    
    # Test timestamp functionality
    echo "🕐 Timestamp Testing:"
    if command -v curl >/dev/null 2>&1; then
        echo "   ✅ curl command available (HTTPS timestamps)"
    else
        echo "   ⚠️  curl not available (will use system time)"
    fi
    echo ""
    
    # Test documentation generation
    echo "📚 Documentation Testing:"
    if [ -f "README.md" ]; then
        echo "   ✅ README.md exists"
    else
        echo "   ❌ README.md missing"
    fi
    
    local docs_dir=$(get_docs_folder)
    if [ -d "$docs_dir" ]; then
        echo "   ✅ Documentation directory exists: $(basename "$docs_dir")/"
    else
        echo "   ❌ Documentation directory missing: $(basename "$docs_dir")/"
    fi
    echo ""
    
    # Test configuration
    echo "⚙️  Configuration Testing:"
    if [ -f "env.example" ]; then
        echo "   ✅ env.example exists"
    else
        echo "   ❌ env.example missing"
    fi
    
    if [ -f "manifest.config" ]; then
        echo "   ✅ manifest.config exists"
    else
        echo "   ❌ manifest.config missing"
    fi
    echo ""
    
    # Test security
    echo "🔒 Security Testing:"
    if manifest security --check >/dev/null 2>&1; then
        echo "   ✅ Security audit passed"
    else
        echo "   ⚠️  Security audit had issues (check with 'manifest security --check')"
    fi
    echo ""
    
    echo "✅ Test/dry-run completed successfully!"
    echo "   All systems appear ready for version bump."
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "ship"|"prep")
            local increment_type="${2:-patch}"
            local interactive="${3:-false}"
            manifest_ship_workflow "$increment_type" "$interactive" "false"
            ;;
        "test")
            local increment_type="${2:-patch}"
            manifest_test_dry_run "$increment_type"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Orchestrator Module"
            echo "==========================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  ship [type] [interactive]  - Complete ship workflow (local-only)"
            echo "  test [type]              - Test/dry-run mode"
            echo "  help                     - Show this help"
            echo ""
            echo "Options:"
            echo "  type: patch, minor, major, revision (default: patch)"
            echo "  interactive: -i for interactive mode"
            echo ""
            echo "Examples:"
            echo "  $0 ship minor"
            echo "  $0 ship patch -i"
            echo "  $0 test major"
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# Back-compat: old name forwards to the renamed function. Remove once external
# callers (if any) have migrated.
# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
