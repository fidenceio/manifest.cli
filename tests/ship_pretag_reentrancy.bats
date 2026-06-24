#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for pre-tag re-entrancy (CLI tracker 5.5): if a ship is interrupted
# between the version bump and the commit, VERSION holds the next value but is
# uncommitted. manifest_ship_repo_pretag_state must detect that exact state so a
# re-run resumes in place (skips the re-bump) instead of double-bumping. A
# manual/divergent VERSION edit must NOT be mistaken for a resume.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    export MANIFEST_CLI_GIT_TAG_PREFIX="v"
    export MANIFEST_CLI_GIT_TAG_SUFFIX=""
    REPO="$SCRATCH/repo"
    mk_repo_at_version "$REPO" "1.2.3"
    cd "$REPO"
    export MANIFEST_CLI_PROJECT_ROOT="$REPO"
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# A git repo on main with a committed VERSION.
mk_repo_at_version() {
    local dir="$1" version="$2"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" checkout -q -b main 2>/dev/null || true
    git -C "$dir" config user.email t@e.co
    git -C "$dir" config user.name "Test"
    echo "$version" > "$dir/VERSION"
    echo "# readme" > "$dir/README.md"
    git -C "$dir" add VERSION README.md
    git -C "$dir" commit -q -m "Bump version to $version"
}

state_of() { manifest_ship_repo_pretag_state "$1"; }

@test "pretag: clean repo at committed version is fresh" {
    run state_of patch
    [ "$status" -eq 0 ]
    [[ "$output" == fresh\|* ]]
}

@test "pretag: VERSION bumped-but-uncommitted to the expected next is resume-in-place" {
    echo "1.2.4" > "$REPO/VERSION"   # what `ship patch` would have produced
    run state_of patch
    [ "$status" -eq 0 ]
    [[ "$output" == resume-in-place\|1.2.4\|* ]]
}

@test "pretag: resume-in-place tracks the increment type (minor)" {
    echo "1.3.0" > "$REPO/VERSION"   # next minor of 1.2.3
    run state_of minor
    [ "$status" -eq 0 ]
    [[ "$output" == resume-in-place\|1.3.0\|* ]]
}

@test "pretag: a dirty VERSION that is NOT this bump stays fresh (manual edit)" {
    echo "9.9.9" > "$REPO/VERSION"   # not patch(1.2.3)=1.2.4
    run state_of patch
    [ "$status" -eq 0 ]
    [[ "$output" == fresh\|* ]]
}

@test "pretag: bumped value that already has a tag is the post-tag resume domain" {
    echo "1.2.4" > "$REPO/VERSION"
    git -C "$REPO" tag "v1.2.4"
    run state_of patch
    [ "$status" -eq 0 ]
    [[ "$output" == tagged\|1.2.4\|* ]]
}

@test "pretag: re-running the same increment after a completed bump does not double-bump" {
    # Simulate a completed, committed bump to 1.2.4 (no tag, e.g. --local).
    echo "1.2.4" > "$REPO/VERSION"
    git -C "$REPO" commit -aqm "Bump version to 1.2.4"
    # VERSION now clean at 1.2.4. A re-run probes as fresh (legitimately the
    # next release), NOT resume-in-place — the resume path only triggers on an
    # UNCOMMITTED bump, so there is no double-bump-from-dirty hazard here.
    run state_of patch
    [ "$status" -eq 0 ]
    [[ "$output" == fresh\|1.2.4\|* ]]
}

# --- Wiring guard -----------------------------------------------------------

@test "pretag: probe runs before the auto-commit and gates the bump" {
    local f="$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    local probe_line autocommit_line bump_guard_line
    probe_line=$(grep -n 'pretag_state="\$(manifest_ship_repo_pretag_state' "$f" | head -1 | cut -d: -f1)
    autocommit_line=$(grep -n 'Uncommitted changes detected' "$f" | head -1 | cut -d: -f1)
    bump_guard_line=$(grep -n 'resume_in_place.*!=.*true' "$f" | tail -1 | cut -d: -f1)
    # Probe precedes the auto-commit (so the dirty VERSION signal survives) ...
    [ "$probe_line" -lt "$autocommit_line" ]
    # ... and the bump is guarded by the resume flag.
    [ -n "$bump_guard_line" ]
    grep -q 'if \[ "\$resume_in_place" != "true" \]; then' "$f"
}
