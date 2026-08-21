#!/usr/bin/env bats
#
# §8.1a: a multi-remote push that succeeds on some remotes and fails on another
# leaves public state behind — push_changes must record a per-remote ledger and
# report push_status "partial", and the failure report must suppress hard-reset
# advice and print a per-remote retry for every remote that lacks the release.
# Single-remote behavior must stay byte-compatible ("failed", no new lines).

load 'helpers/setup'

setup() {
    load_modules "system/manifest-os.sh" "git/manifest-git.sh" "workflow/manifest-orchestrator.sh"
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT"
    cd "$MANIFEST_CLI_PROJECT_ROOT"
    git init -q .
    git checkout -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "1.2.3" > VERSION
    git add VERSION
    git commit -qm "Bump version to 1.2.3"
    git tag v1.2.3
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
    # One attempt per remote: the broken remote fails fast with no retry sleeps.
    export MANIFEST_CLI_GIT_RETRIES=1
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# `git remote` lists alphabetically, so alpha (working bare repo) is pushed
# before beta (nonexistent path -> fails fast).
_add_two_remotes() {
    git init --bare -q "$SCRATCH/alpha.git"
    git remote add alpha "$SCRATCH/alpha.git"
    git remote add beta "$SCRATCH/nonexistent/beta.git"
}

@test "push_changes: two remotes, second fails -> partial status with per-remote ledger" {
    _add_two_remotes
    _probe() {
        push_changes "1.2.3" || true
        echo "ledger_status=${_MANIFEST_CLI_GIT_PUSH_STATUS}"
        local entry
        for entry in "${_MANIFEST_CLI_GIT_PUSH_REMOTE_RESULTS[@]}"; do
            echo "ledger_entry=$entry"
        done
    }
    run _probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"ledger_status=partial"* ]]
    [[ "$output" == *"ledger_entry=alpha|success"* ]]
    [[ "$output" == *"ledger_entry=beta|failed"* ]]
    # The release really is public on the remote the ledger marked success.
    git --git-dir="$SCRATCH/alpha.git" rev-parse "v1.2.3^{commit}" >/dev/null
}

@test "push_changes: remotes after the first failure are recorded not_attempted, not pushed" {
    _add_two_remotes
    # gamma sorts after beta; the beta failure must stop the push before gamma.
    git init --bare -q "$SCRATCH/gamma.git"
    git remote add gamma "$SCRATCH/gamma.git"
    _probe() {
        push_changes "1.2.3" || true
        echo "ledger_status=${_MANIFEST_CLI_GIT_PUSH_STATUS}"
        local entry
        for entry in "${_MANIFEST_CLI_GIT_PUSH_REMOTE_RESULTS[@]}"; do
            echo "ledger_entry=$entry"
        done
    }
    run _probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"ledger_status=partial"* ]]
    [[ "$output" == *"ledger_entry=gamma|not_attempted"* ]]
    # No push reached gamma after the detected failure.
    refute git --git-dir="$SCRATCH/gamma.git" rev-parse --verify -q "refs/heads/main"
}

@test "partial push failure report suppresses reset --hard and prints per-remote retries" {
    _add_two_remotes
    local start_sha
    start_sha="$(git rev-parse HEAD)"
    _probe() {
        push_changes "1.2.3" || true
        emit_ship_failure_report "push_changes" "$start_sha" "1.2.3" "v1.2.3" "${_MANIFEST_CLI_GIT_PUSH_STATUS:-failed}" "skipped"
    }
    run _probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"push status:        partial"* ]]
    [[ "$output" != *"reset --hard"* ]]
    [[ "$output" != *"Remove tag:"* ]]
    [[ "$output" == *"Remote alpha: success"* ]]
    [[ "$output" == *"Remote beta: failed"* ]]
    [[ "$output" == *"Retry:    git push beta main v1.2.3"* ]]
    [[ "$output" == *"status probe checks origin only"* ]]
    [[ "$output" == *"Resume:      manifest ship repo resume"* ]]
}

@test "push_changes: single remote failure stays 'failed' — no partial vocabulary" {
    git remote add origin "$SCRATCH/nonexistent/origin.git"
    _probe() {
        push_changes "1.2.3" || true
        echo "ledger_status=${_MANIFEST_CLI_GIT_PUSH_STATUS}"
    }
    run _probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"❌ Failed to push to origin"* ]]
    [[ "$output" == *"ledger_status=failed"* ]]
    [[ "$output" != *"ledger_status=partial"* ]]
}

@test "single remote failure report keeps its existing shape — no per-remote lines" {
    git remote add origin "$SCRATCH/nonexistent/origin.git"
    local start_sha
    start_sha="$(git rev-parse HEAD)"
    git commit --allow-empty -qm "ship-created commit"
    _probe() {
        push_changes "1.2.3" || true
        emit_ship_failure_report "push_changes" "$start_sha" "1.2.3" "v1.2.3" "${_MANIFEST_CLI_GIT_PUSH_STATUS:-failed}" "skipped"
    }
    run _probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"push status:        failed"* ]]
    [[ "$output" == *"Retry push:  git push origin main v1.2.3"* ]]
    [[ "$output" == *"Roll back:   git reset --hard ${start_sha}"* ]]
    [[ "$output" != *"Remote origin:"* ]]
}

@test "push_changes: all remotes succeeding still reports success" {
    git init --bare -q "$SCRATCH/alpha.git"
    git init --bare -q "$SCRATCH/beta.git"
    git remote add alpha "$SCRATCH/alpha.git"
    git remote add beta "$SCRATCH/beta.git"
    _probe() {
        push_changes "1.2.3"
        echo "ledger_status=${_MANIFEST_CLI_GIT_PUSH_STATUS}"
    }
    run _probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ All remotes updated successfully"* ]]
    [[ "$output" == *"ledger_status=success"* ]]
}
