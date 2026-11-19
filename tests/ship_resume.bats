#!/usr/bin/env bats

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
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"

    update_repository_metadata() { :; }
    brew() { return 1; }
    manifest() { return 1; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "ship failure report prints exact tag push and the finish command" {
    git tag v1.2.3      # the report offers a finish only for a tag that exists
    run emit_ship_failure_report "push_changes" "$(git rev-parse HEAD)" "1.2.3" "v1.2.3" "failed" "skipped"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Retry push:  git push origin main v1.2.3"* ]]
    [[ "$output" == *"Finish:      manifest ship repo patch   (plans finishing v1.2.3; add -y to apply"* ]]
    [[ "$output" != *"ship repo resume"* ]]
    [[ "$output" != *"--follow-tags"* ]]
}

@test "ship failure report avoids rollback advice after published Homebrew failure" {
    run emit_ship_failure_report "homebrew_update" "$(git rev-parse HEAD)" "1.2.3" "v1.2.3" "success" "failed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Release artifacts are already pushed"* ]]
    [[ "$output" == *"Finish:      manifest ship repo patch   (plans finishing v1.2.3; add -y to apply"* ]]
    [[ "$output" != *"ship repo resume"* ]]
    [[ "$output" == *"Verify tag:  git ls-remote --tags origin v1.2.3"* ]]
    [[ "$output" != *"Remove tag:"* ]]
    [[ "$output" != *"Roll back:"* ]]
}

@test "ship failure report never advises reset --hard when no commits were created (§9.10)" {
    # The real incident: a pre-commit hook blocked version_commit, so zero
    # commits existed — running the advised `git reset --hard` would have
    # erased the uncommitted working tree unrecoverably.
    run emit_ship_failure_report "version_commit" "$(git rev-parse HEAD)" "1.2.4" "none" "not_attempted" "not_applicable"
    [ "$status" -eq 0 ]
    [[ "$output" == *"commits created:    0"* ]]
    [[ "$output" != *"reset --hard"* ]]
    [[ "$output" == *"do NOT hard-reset"* ]]
    [[ "$output" == *"git checkout HEAD -- VERSION CHANGELOG.md README.md docs/INDEX.md"* ]]
}

@test "ship failure report suppresses destructive advice when the commit count is unverifiable (§9.10)" {
    # start_sha is not a resolvable commit -> commits_created stays "unknown".
    # An unverifiable count must not authorize a destructive command.
    run emit_ship_failure_report "version_commit" "0000000000000000000000000000000000000000" "1.2.4" "none" "not_attempted" "not_applicable"
    [ "$status" -eq 0 ]
    [[ "$output" == *"commits created:    unknown"* ]]
    [[ "$output" != *"reset --hard"* ]]
    [[ "$output" != *"git checkout HEAD --"* ]]
    [[ "$output" == *"rollback advice suppressed"* ]]
}

@test "ship failure report still advises rollback for a verified positive commit count" {
    # Anti-regression pin: the pre-push failure path with real commits keeps its
    # existing `git reset --hard <start_sha>` advice byte-for-byte.
    local start_sha
    start_sha="$(git rev-parse HEAD)"
    git commit --allow-empty -qm "ship-created commit"
    run emit_ship_failure_report "push_changes" "$start_sha" "1.2.4" "v1.2.4" "failed" "skipped"
    [ "$status" -eq 0 ]
    [[ "$output" == *"commits created:    1"* ]]
    [[ "$output" == *"Roll back:   git reset --hard ${start_sha}"* ]]
    [[ "$output" != *"git checkout HEAD --"* ]]
}

@test "ship failure report offers no Finish line when the tag was never created" {
    # A ship that fails AT create_tag has made its release commit and no tag.
    # "Finish: manifest ship repo patch" there would send the operator to a
    # command that plans the next version, not this one.
    local start_sha
    start_sha="$(git rev-parse HEAD)"
    git commit --allow-empty -qm "Bump version to 1.2.4"
    run emit_ship_failure_report "create_tag" "$start_sha" "1.2.4" "v1.2.4" "not_attempted" "skipped"
    [ "$status" -eq 0 ]
    [[ "$output" == *"The tag v1.2.4 was not created, so nothing was pushed and there is nothing to finish."* ]]
    [[ "$output" != *"Finish:"* ]]
    [[ "$output" != *"Retry push:"* ]]
    [[ "$output" != *"Remove tag:"* ]]
    # The count rules still apply: one verified commit, nothing public.
    [[ "$output" == *"Roll back:   git reset --hard ${start_sha}"* ]]

    # CONTROL: the same call once the tag exists prints all three.
    git tag v1.2.4
    run emit_ship_failure_report "create_tag" "$start_sha" "1.2.4" "v1.2.4" "not_attempted" "skipped"
    [[ "$output" == *"Finish:      manifest ship repo patch"* ]]
    [[ "$output" == *"Remove tag:  git tag -d v1.2.4"* ]]
}

@test "ship failure report for a failed finish advises nothing destructive" {
    git tag v1.2.3
    # A finish that cannot reach the remote reads the tag as "missing or
    # unreachable". The report for the removed `resume` then offered
    # `git tag -d` and a checkout of VERSION for a release that was public.
    run emit_ship_failure_report "finish_push" "$(git rev-parse HEAD)" "1.2.3" "v1.2.3" "failed" "skipped"
    [ "$status" -eq 0 ]
    [[ "$output" == *"This run created nothing: the release commit and v1.2.3 already existed."* ]]
    [[ "$output" == *"Do NOT delete the tag or reset"* ]]
    [[ "$output" == *"Retry push:  git push origin main v1.2.3"* ]]
    [[ "$output" == *"Finish:      manifest ship repo patch"* ]]
    [[ "$output" != *"Remove tag:"* ]]
    [[ "$output" != *"git tag -d"* ]]
    [[ "$output" != *"git checkout HEAD --"* ]]
    [[ "$output" != *"reset --hard"* ]]

    # CONTROL: an ordinary push failure with a tag still offers the tag removal,
    # so the assertions above are not passing on a report that never prints it.
    run emit_ship_failure_report "push_changes" "$(git rev-parse HEAD)" "1.2.3" "v1.2.3" "failed" "skipped"
    [[ "$output" == *"Remove tag:  git tag -d v1.2.3"* ]]
}

# The finish routine, unit level. Its consent and its lock belong to the caller
# (manifest_ship_repo's apply path) — tests/ship_unfinished_release.bats drives
# that route through the real entrypoint, and tests/ship_repo_lock.bats pins
# that it is the only one.

@test "finish pushes the tag of a recorded unfinished release and clears the record" {
    local remote="$SCRATCH/remote.git"
    git init --bare -q "$remote"
    git remote add origin "$remote"
    run create_tag "1.2.3"
    [ "$status" -eq 0 ]
    manifest_ship_inflight_begin "1.2.3" "v1.2.3" "$(git rev-parse 'v1.2.3^{commit}')"
    [ -f .git/manifest-ship/in-flight ]

    run manifest_ship_repo_finish
    [ "$status" -eq 0 ]
    [[ "$output" == *"Finishing release"* ]]
    [[ "$output" == *"remote tag:"* ]]
    [[ "$output" == *"Release v1.2.3 finished. Nothing was bumped."* ]]
    git --git-dir="$remote" rev-parse "v1.2.3^{commit}" >/dev/null
    [ ! -e .git/manifest-ship/in-flight ]
}

@test "finish refuses when no unfinished release is recorded, even with a tag to push" {
    # The shape `ship repo resume` used to act on: a local tag, nothing else.
    # Without a record there is nothing this routine may finish.
    local remote="$SCRATCH/remote.git"
    git init --bare -q "$remote"
    git remote add origin "$remote"
    run create_tag "1.2.3"
    [ "$status" -eq 0 ]

    run manifest_ship_repo_finish
    [ "$status" -ne 0 ]
    [[ "$output" == *"Nothing to finish"* ]]
    refute git --git-dir="$remote" rev-parse -q --verify "refs/tags/v1.2.3^{commit}"
}

@test "unfinished probe: none without a record, unfinished with one, none once the tag moves" {
    run create_tag "1.2.3"
    [ "$status" -eq 0 ]

    run manifest_ship_repo_unfinished
    [ "$status" -ne 0 ]
    [[ "$output" == none\|* ]]

    manifest_ship_inflight_begin "1.2.3" "v1.2.3" "$(git rev-parse 'v1.2.3^{commit}')"
    manifest_ship_inflight_note_stop "1.2.3" "homebrew_update"
    run manifest_ship_repo_unfinished
    [ "$status" -eq 0 ]
    [[ "$output" == unfinished\|1.2.3\|v1.2.3\|homebrew_update\|* ]]

    # A stop noted for another version is not this record's.
    manifest_ship_inflight_note_stop "9.9.9" "push_changes"
    run manifest_ship_repo_unfinished
    [[ "$output" == unfinished\|1.2.3\|v1.2.3\|homebrew_update\|* ]]

    # The tag now points somewhere else: the record no longer describes it.
    git commit --allow-empty -qm "later"
    git tag -f v1.2.3 >/dev/null
    run manifest_ship_repo_unfinished
    [ "$status" -ne 0 ]
    [[ "$output" == none\|* ]]
}

@test "follow-up patch gate allows canonical non-patch full release" {
    should_update_homebrew_for_repo() { return 0; }
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE

    run manifest_ship_should_run_followup_patch "minor" "true"

    [ "$status" -eq 0 ]
}

@test "follow-up patch gate skips formula-only post-tag changes" {
    should_update_homebrew_for_repo() { return 0; }
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE
    mkdir -p formula
    echo "old formula" > formula/manifest.rb
    git add formula/manifest.rb
    git commit -qm "Add formula"
    run create_tag "1.2.3"
    [ "$status" -eq 0 ]
    echo "new formula" > formula/manifest.rb
    git add formula/manifest.rb
    git commit -qm "Update Homebrew formula to v1.2.3"

    run manifest_ship_should_run_followup_patch "minor" "true" "v1.2.3"

    [ "$status" -ne 0 ]
}

@test "follow-up patch gate allows non-formula post-tag changes" {
    should_update_homebrew_for_repo() { return 0; }
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE
    run create_tag "1.2.3"
    [ "$status" -eq 0 ]
    echo "runtime change" > runtime.txt
    git add runtime.txt
    git commit -qm "Runtime change"

    run manifest_ship_should_run_followup_patch "minor" "true" "v1.2.3"

    [ "$status" -eq 0 ]
}

@test "follow-up patch gate refuses patch releases" {
    should_update_homebrew_for_repo() { return 0; }
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE

    run manifest_ship_should_run_followup_patch "patch" "true"

    [ "$status" -ne 0 ]
}

@test "follow-up patch gate refuses local-only releases" {
    should_update_homebrew_for_repo() { return 0; }
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE

    run manifest_ship_should_run_followup_patch "minor" "false"

    [ "$status" -ne 0 ]
}

@test "follow-up patch gate respects disable env var" {
    should_update_homebrew_for_repo() { return 0; }
    export MANIFEST_CLI_SHIP_FOLLOWUP_PATCH=false
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE

    run manifest_ship_should_run_followup_patch "minor" "true"

    [ "$status" -ne 0 ]
}

@test "follow-up patch gate refuses recursive runs" {
    should_update_homebrew_for_repo() { return 0; }
    export MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE=1
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH

    run manifest_ship_should_run_followup_patch "minor" "true"

    [ "$status" -ne 0 ]
}

@test "follow-up patch runner invokes manifest with recursion sentinel" {
    manifest_exec_manifest() {
        echo "sentinel=${MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE:-}"
        echo "args=$*"
    }

    run manifest_ship_run_followup_patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Running follow-up patch"* ]]
    [[ "$output" == *"sentinel=1"* ]]
    [[ "$output" == *"args=ship repo patch -y"* ]]
}

@test "child manifest helper clears inherited bash re-exec sentinel" {
    local bin_dir="$SCRATCH/bin"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/manifest" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'sentinel=%s\n' "${MANIFEST_CLI_BASH_REEXEC:-}"
printf 'active=%s\n' "${MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE:-}"
printf 'args=%s\n' "$*"
SCRIPT
    chmod +x "$bin_dir/manifest"
    export PATH="$bin_dir:$PATH"
    export MANIFEST_CLI_BASH_REEXEC=1

    MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE=1
    run manifest_exec_manifest ship repo patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"sentinel="* ]]
    [[ "$output" != *"sentinel=1"* ]]
    [[ "$output" == *"active=1"* ]]
    [[ "$output" == *"args=ship repo patch"* ]]
}
