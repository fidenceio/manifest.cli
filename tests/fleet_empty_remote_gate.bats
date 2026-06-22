#!/usr/bin/env bats

# Coverage for the empty-REMOTE_URL ship-time gate (_fleet_preflight_no_empty_remote).
#
# A non-local `ship fleet` of a releaseable member with no pushable 'origin'
# would commit + tag locally then silently skip the push and GitHub Release,
# stranding the release on disk. The gate (apply-only, non-local) repairs the
# member from the fleet TSV's declared REMOTE_URL where it can, and refuses the
# whole apply before any release mutation when it cannot.
#
# Three layers:
#   1. End-to-end refuse — `ship fleet patch -y` through the entry script
#   2. Isolated repair    — real loader + direct gate call, file:// remote
#   3. Isolated refuse     — real loader + direct gate call, empty REMOTE_URL

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
}

teardown() {
    cd /tmp || true
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# A member repo with VERSION + an initial commit on main and NO origin remote.
mk_member_repo() {
    local repo="$1" version="${2:-1.0.0}"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b main
    git -C "$repo" config user.email t@e.com
    git -C "$repo" config user.name t
    echo "$version" > "$repo/VERSION"
    git -C "$repo" add -A
    git -C "$repo" commit -qm init
}

# Write a one-member fleet at $SCRATCH/work. $1 is the member's REMOTE_URL cell
# (may be empty). The fleet root itself is a git repo, as in production.
write_one_member_fleet() {
    local remote_url="$1"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work" checkout -q -b main
    mk_member_repo "$SCRATCH/work/svc-a"

    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svca:
    path: "./svc-a"
    branch: "main"
YAML

    printf 'true\tsvca\t./svc-a\ttrue\t%s\tmain\n' "$remote_url" \
        > "$SCRATCH/work/manifest.fleet.tsv"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# Load the real fleet config so get_fleet_service_property returns TSV values,
# then make the gate callable directly.
load_fleet_and_gate() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    load_fleet_config "$SCRATCH/work" >/dev/null 2>&1
    cd "$SCRATCH/work"
}

@test "ship fleet -y refuses when a releaseable member has no origin and no REMOTE_URL" {
    write_one_member_fleet ""

    run_manifest ship fleet patch -y

    [ "$status" -ne 0 ]
    [[ "$output" == *"no 'origin' remote and no usable REMOTE_URL"* ]]
    [[ "$output" == *"svc-a"* ]]
    [[ "$output" == *"no fleet member was shipped"* ]]
    # Refused before mutation: no release tag was created on the member.
    [ -z "$(git -C "$SCRATCH/work/svc-a" tag 2>/dev/null)" ]
}

@test "ship fleet --local does NOT invoke the empty-remote gate (never pushes)" {
    write_one_member_fleet ""

    run_manifest ship fleet patch -y --local

    # The gate is the only thing that emits this line; --local must skip it.
    [[ "$output" != *"no usable REMOTE_URL"* ]]
}

@test "gate repairs origin from the TSV REMOTE_URL when it is a valid git URL" {
    bare="$SCRATCH/remote-a.git"
    git init -q --bare "$bare"
    write_one_member_fleet "file://$bare"
    # Member starts with no origin.
    run git -C "$SCRATCH/work/svc-a" remote get-url origin
    [ "$status" -ne 0 ]

    load_fleet_and_gate
    run _fleet_preflight_no_empty_remote true

    [ "$status" -eq 0 ]
    [[ "$output" == *"Wired up 'origin'"* ]]
    run git -C "$SCRATCH/work/svc-a" remote get-url origin
    [ "$status" -eq 0 ]
    [ "$output" = "file://$bare" ]
}

@test "gate refuses (and adds no remote) when the TSV REMOTE_URL is empty" {
    write_one_member_fleet ""

    load_fleet_and_gate
    run _fleet_preflight_no_empty_remote true

    [ "$status" -ne 0 ]
    [[ "$output" == *"no 'origin' remote and no usable REMOTE_URL"* ]]
    run git -C "$SCRATCH/work/svc-a" remote get-url origin
    [ "$status" -ne 0 ]
}
