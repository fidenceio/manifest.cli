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

@test "status: fleet root prints repo table with version, timestamp, and latest commit" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi

    mkdir -p "$SCRATCH/svc-a" "$SCRATCH/svc-b"
    git -C "$SCRATCH/svc-a" init -q
    git -C "$SCRATCH/svc-a" config user.email t@e.com
    git -C "$SCRATCH/svc-a" config user.name t
    echo "1.2.3" > "$SCRATCH/svc-a/VERSION"
    git -C "$SCRATCH/svc-a" add VERSION
    GIT_AUTHOR_DATE="2026-05-01T12:00:00Z" GIT_COMMITTER_DATE="2026-05-01T12:00:00Z" \
        git -C "$SCRATCH/svc-a" commit -qm "Initial A"

    git -C "$SCRATCH/svc-b" init -q
    git -C "$SCRATCH/svc-b" config user.email t@e.com
    git -C "$SCRATCH/svc-b" config user.name t
    echo "2.0.0" > "$SCRATCH/svc-b/VERSION"
    git -C "$SCRATCH/svc-b" add VERSION
    GIT_AUTHOR_DATE="2026-05-02T12:00:00Z" GIT_COMMITTER_DATE="2026-05-02T12:00:00Z" \
        git -C "$SCRATCH/svc-b" commit -qm "Initial B"
    echo "dirty" > "$SCRATCH/svc-b/dirty.txt"

    cat > "$SCRATCH/manifest.fleet.yaml" <<'YAML'
fleet:
  name: test-fleet
services:
  svc-a:
    path: ./svc-a
    branch: master
  svc-b:
    path: ./svc-b
    branch: master
YAML

    cd "$SCRATCH"
    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Fleet:.*test-fleet"
    echo "$output" | grep -q "Repo.*Branch.*State.*Version.*Timestamp.*Latest commit"
    echo "$output" | grep -q "svc-a.*master.*clean.*1.2.3.*2026-05-01 12:00:00 UTC.*Initial A"
    echo "$output" | grep -q "svc-b.*master.*dirty.*2.0.0.*2026-05-02 12:00:00 UTC.*Initial B"
}
