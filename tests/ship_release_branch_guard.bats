#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the release-branch guard. push_changes() pushes the *literal*
# default-branch ref while the version commit/tag are made on whatever HEAD is
# checked out, so shipping off the default branch tags the wrong commit and
# pushes a stale default branch (the v4.0.0 mishap: tag public, main never
# advanced). manifest_assert_release_branch refuses before any mutation and
# hands the user the git steps to fix it.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# Repo on an explicit branch with one commit, so branch --show-current is stable
# regardless of the host's init.defaultBranch.
init_repo_on() {
    local dir="$1" branch="$2"
    mkdir -p "$dir"
    git -C "$dir" init -q -b "$branch"
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name "Test"
    echo "initial" > "$dir/README"
    git -C "$dir" add README
    git -C "$dir" commit -q -m "initial"
}

source_guard() {
    # shellcheck disable=SC1091
    load_modules "git/manifest-git.sh" >/dev/null 2>&1
}

# --- manifest_assert_release_branch unit tests ------------------------------

@test "guard: on default branch returns 0 silently" {
    init_repo_on "$SCRATCH/repo" main
    source_guard
    run manifest_assert_release_branch "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "guard: on a feature branch returns 1 with branch names and git remediation" {
    init_repo_on "$SCRATCH/repo" main
    git -C "$SCRATCH/repo" checkout -q -b feature
    source_guard
    run manifest_assert_release_branch "$SCRATCH/repo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"feature"* ]]
    [[ "$output" == *"not 'main'"* ]]
    [[ "$output" == *"git checkout main && git merge feature"* ]]
}

@test "guard: detached HEAD returns 1 and is named as detached" {
    init_repo_on "$SCRATCH/repo" main
    git -C "$SCRATCH/repo" checkout -q --detach
    source_guard
    run manifest_assert_release_branch "$SCRATCH/repo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"detached HEAD"* ]]
}

@test "guard: honors a configured non-main default branch" {
    init_repo_on "$SCRATCH/repo" master
    source_guard
    MANIFEST_CLI_GIT_DEFAULT_BRANCH=master run manifest_assert_release_branch "$SCRATCH/repo"
    [ "$status" -eq 0 ]
}

# --- Fleet apply integration ------------------------------------------------

write_two_member_fleet() {
    git -C "$SCRATCH/work" init -q -b main
    init_repo_on "$SCRATCH/work/svc-a" main
    init_repo_on "$SCRATCH/work/svc-b" main
    echo "1.0.0" > "$SCRATCH/work/svc-a/VERSION"
    echo "1.0.0" > "$SCRATCH/work/svc-b/VERSION"

    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svca:
    path: "./svc-a"
    type: "service"
    branch: "main"
  svcb:
    path: "./svc-b"
    type: "service"
    branch: "main"
YAML

    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svca	./svc-a	true
true	svcb	./svc-b	true
TSV
}

@test "ship fleet -y aborts when a member is off its release branch, ships nothing" {
    write_two_member_fleet
    git -C "$SCRATCH/work/svc-a" checkout -q -b feature

    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet patch -y

    [ "$status" -ne 0 ]
    [[ "$output" == *"feature"* ]]
    [[ "$output" == *"Cannot release"* ]]
    [[ "$output" == *"no fleet member was shipped"* ]]

    # Pre-flight refused before mutation: neither member tagged.
    [ -z "$(git -C "$SCRATCH/work/svc-a" tag 2>/dev/null)" ]
    [ -z "$(git -C "$SCRATCH/work/svc-b" tag 2>/dev/null)" ]
}

@test "ship fleet preview does not invoke the release-branch pre-flight" {
    write_two_member_fleet
    git -C "$SCRATCH/work/svc-a" checkout -q -b feature

    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" != *"Cannot release"* ]]
}

# --- Coupling guardrails ----------------------------------------------------

@test "push_changes still pushes the literal default-branch ref (guard's premise)" {
    # The guard exists because push_changes pushes $default_branch, not HEAD.
    # If a refactor makes the push branch-aware, this trips and the guard's
    # rationale must be re-evaluated.
    grep -E 'git push .*\$default_branch .*\$tag_name' \
        "$TEST_REPO_ROOT/modules/git/manifest-git.sh" >/dev/null
}

@test "single-repo publish path invokes the release-branch guard" {
    grep -F 'manifest_assert_release_branch' \
        "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh" >/dev/null
}
