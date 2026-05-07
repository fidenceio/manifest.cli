#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "system/manifest-os.sh" "git/manifest-git.sh" "workflow/manifest-orchestrator.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$PROJECT_ROOT"
    cd "$PROJECT_ROOT"
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

@test "ship failure report prints exact tag push and resume command" {
    run emit_ship_failure_report "push_changes" "$(git rev-parse HEAD)" "1.2.3" "v1.2.3" "failed" "skipped"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Retry push:  git push origin main v1.2.3"* ]]
    [[ "$output" == *"Resume:      manifest ship repo resume"* ]]
    [[ "$output" != *"--follow-tags"* ]]
}

@test "ship repo resume pushes existing local release tag" {
    local remote="$SCRATCH/remote.git"
    git init --bare -q "$remote"
    git remote add origin "$remote"
    run create_tag "1.2.3"
    [ "$status" -eq 0 ]

    run manifest_ship_repo_resume
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship resume"* ]]
    [[ "$output" == *"remote tag:"* ]]
    git --git-dir="$remote" rev-parse "v1.2.3^{commit}" >/dev/null
}

@test "ship repo resume refuses when VERSION tag is missing" {
    run manifest_ship_repo_resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"local tag v1.2.3 does not exist"* ]]
}

@test "follow-up patch gate allows canonical non-patch full release" {
    should_update_homebrew_for_repo() { return 0; }
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE

    run manifest_ship_should_run_followup_patch "minor" "true"

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
