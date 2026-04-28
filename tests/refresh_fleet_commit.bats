#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-refresh.sh"

    SCRATCH="$(mk_scratch)"

    # Configure committer identity inside the sandbox so `git commit` works
    # without leaking into the developer's real ~/.gitconfig.
    export GIT_AUTHOR_NAME="bats" GIT_AUTHOR_EMAIL="bats@example"
    export GIT_COMMITTER_NAME="bats" GIT_COMMITTER_EMAIL="bats@example"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_FLEET_ROOT MANIFEST_FLEET_SERVICES
}

# Lightweight stub for get_fleet_service_property keyed off two associative
# helper arrays the test fills in. Avoids loading the full fleet stack.
_stub_fleet_helpers() {
    declare -gA _STUB_PATH _STUB_EXCLUDED
    get_fleet_service_property() {
        local svc="$1" key="$2" default="${3:-}"
        case "$key" in
            path)     echo "${_STUB_PATH[$svc]:-$default}" ;;
            excluded) echo "${_STUB_EXCLUDED[$svc]:-${default:-false}}" ;;
            *)        echo "$default" ;;
        esac
    }
    export -f get_fleet_service_property
}

mk_repo_with_change() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "bats@example"
    git -C "$dir" config user.name "bats"
    echo "first" > "$dir/seed.md"
    git -C "$dir" add seed.md
    git -C "$dir" commit -q -m "seed"
    # Now add a "refreshed" file so there is something to commit.
    echo "refreshed" > "$dir/RELEASE_NOTES.md"
}

mk_repo_clean() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "bats@example"
    git -C "$dir" config user.name "bats"
    echo "seed" > "$dir/seed.md"
    git -C "$dir" add seed.md
    git -C "$dir" commit -q -m "seed"
}

# -----------------------------------------------------------------------------
# Help text
# -----------------------------------------------------------------------------

@test "refresh fleet --help: lists --commit without 'not yet implemented'" {
    run manifest_refresh_fleet --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--commit"* ]]
    [[ "$output" == *"Stage and commit refreshed metadata"* ]]
    [[ "$output" != *"not yet implemented"* ]]
}

# -----------------------------------------------------------------------------
# _refresh_fleet_commit_changes: commits fleet root when there are changes
# -----------------------------------------------------------------------------

@test "_refresh_fleet_commit_changes: commits fleet root with pending changes" {
    _stub_fleet_helpers
    mk_repo_with_change "$SCRATCH/root"
    export MANIFEST_FLEET_ROOT="$SCRATCH/root"
    export MANIFEST_FLEET_SERVICES=""

    run _refresh_fleet_commit_changes "Refresh fleet metadata"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet root: committed"* ]]
    [[ "$output" == *"1 committed"* ]]

    # Verify a real commit landed.
    run git -C "$SCRATCH/root" log -1 --pretty=%s
    [ "$output" = "Refresh fleet metadata" ]
}

@test "_refresh_fleet_commit_changes: reports no-changes for clean fleet root" {
    _stub_fleet_helpers
    mk_repo_clean "$SCRATCH/root"
    export MANIFEST_FLEET_ROOT="$SCRATCH/root"
    export MANIFEST_FLEET_SERVICES=""

    run _refresh_fleet_commit_changes
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet root: no changes"* ]]
    [[ "$output" == *"0 committed"* ]]
    [[ "$output" == *"1 no-changes"* ]]
}

# -----------------------------------------------------------------------------
# Services iteration
# -----------------------------------------------------------------------------

@test "_refresh_fleet_commit_changes: commits each service with pending changes" {
    _stub_fleet_helpers
    mk_repo_with_change "$SCRATCH/svc-a"
    mk_repo_with_change "$SCRATCH/svc-b"

    _STUB_PATH[svc-a]="$SCRATCH/svc-a"
    _STUB_PATH[svc-b]="$SCRATCH/svc-b"

    export MANIFEST_FLEET_ROOT="$SCRATCH"   # not a git repo, skipped
    export MANIFEST_FLEET_SERVICES="svc-a svc-b"

    run _refresh_fleet_commit_changes
    [ "$status" -eq 0 ]
    [[ "$output" == *"svc-a: committed"* ]]
    [[ "$output" == *"svc-b: committed"* ]]
    [[ "$output" == *"2 committed"* ]]

    [ "$(git -C "$SCRATCH/svc-a" log -1 --pretty=%s)" = "Refresh fleet metadata" ]
    [ "$(git -C "$SCRATCH/svc-b" log -1 --pretty=%s)" = "Refresh fleet metadata" ]
}

@test "_refresh_fleet_commit_changes: skips excluded services" {
    _stub_fleet_helpers
    mk_repo_with_change "$SCRATCH/svc-a"
    mk_repo_with_change "$SCRATCH/svc-skip"

    _STUB_PATH[svc-a]="$SCRATCH/svc-a"
    _STUB_PATH[svc-skip]="$SCRATCH/svc-skip"
    _STUB_EXCLUDED[svc-skip]="true"

    export MANIFEST_FLEET_ROOT="$SCRATCH"
    export MANIFEST_FLEET_SERVICES="svc-a svc-skip"

    run _refresh_fleet_commit_changes
    [ "$status" -eq 0 ]
    [[ "$output" == *"svc-a: committed"* ]]
    [[ "$output" != *"svc-skip"* ]]

    # The excluded repo's pending file must remain uncommitted.
    run git -C "$SCRATCH/svc-skip" status --porcelain
    [[ "$output" == *"RELEASE_NOTES.md"* ]]
}

@test "_refresh_fleet_commit_changes: skips non-git service paths" {
    _stub_fleet_helpers
    mkdir -p "$SCRATCH/not-a-repo"   # exists but no .git
    _STUB_PATH[ghost]="$SCRATCH/not-a-repo"

    export MANIFEST_FLEET_ROOT="$SCRATCH"
    export MANIFEST_FLEET_SERVICES="ghost"

    run _refresh_fleet_commit_changes
    [ "$status" -eq 0 ]
    [[ "$output" != *"ghost"* ]]
    [[ "$output" == *"0 committed"* ]]
}

@test "_refresh_fleet_commit_changes: does not double-commit when service path equals fleet root" {
    _stub_fleet_helpers
    mk_repo_with_change "$SCRATCH/root"
    _STUB_PATH[main]="$SCRATCH/root"

    export MANIFEST_FLEET_ROOT="$SCRATCH/root"
    export MANIFEST_FLEET_SERVICES="main"

    run _refresh_fleet_commit_changes
    [ "$status" -eq 0 ]
    # Exactly one commit should have happened (one "committed" line).
    [ "$(printf '%s\n' "$output" | grep -c 'committed' | head -n1)" -ge 1 ]
    [[ "$output" == *"1 committed"* ]]
    [[ "$output" != *"main: committed"* ]]
}

# -----------------------------------------------------------------------------
# Dry-run preview
# -----------------------------------------------------------------------------

@test "refresh fleet --dry-run --commit: prints would-commit preview, writes nothing" {
    # Stub fleet_update so we don't need a real fleet config to drive the
    # dispatcher; the function checks --dry-run very early.
    fleet_update() { echo "fleet_update called with: $*"; }
    export -f fleet_update

    mk_repo_with_change "$SCRATCH/root"
    export MANIFEST_FLEET_ROOT="$SCRATCH/root"
    export MANIFEST_FLEET_SERVICES=""

    run manifest_refresh_fleet --dry-run --commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would commit refreshed metadata"* ]]
    [[ "$output" == *"No changes written"* ]]

    # Hard guarantee: nothing actually committed.
    run git -C "$SCRATCH/root" log --oneline
    [[ "$output" != *"Refresh fleet metadata"* ]]
}
