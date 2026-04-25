#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "status preview bump: patch increments rightmost" {
    run _status_preview_bump "1.2.3" "patch"
    [ "$output" = "1.2.4" ]
}

@test "status preview bump: minor increments middle, zeros patch" {
    run _status_preview_bump "1.2.3" "minor"
    [ "$output" = "1.3.0" ]
}

@test "status preview bump: major increments leftmost, zeros minor+patch" {
    run _status_preview_bump "1.2.3" "major"
    [ "$output" = "2.0.0" ]
}

@test "status preview bump: malformed version yields '?' instead of crashing" {
    run _status_preview_bump "garbage" "patch"
    [ "$output" = "?" ]
}

@test "status: runs cleanly in a non-git directory (no crash, exit 0)" {
    cd "$SCRATCH"
    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "not a git repository"
}

@test "status: shows VERSION + bump previews when VERSION is present" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "3.7.1" > VERSION
    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Version:.*3.7.1"
    echo "$output" | grep -q "patch → 3.7.2"
    echo "$output" | grep -q "minor → 3.8.0"
    echo "$output" | grep -q "major → 4.0.0"
}
