#!/usr/bin/env bats

# APPLY coverage for `manifest prep fleet -y` (manifest_prep_fleet → _fleet_sync).
#
# fleet_dry_run.bats proves the preview plans without touching disk. This file
# proves the apply: a member that is BEHIND its origin really gets
# `git pull --rebase`d (HEAD advances to the remote tip), on both the
# sequential (operations.parallel=false) and --parallel runners. All remotes
# are local bare repos (file://), so every git transfer stays offline.
#
# NOT covered here (needs a source change, out of scope for test-only work):
# the clone-missing-member path of _fleet_sync_service. The TSV loader
# absolutizes member paths (_load_all_service_configs), while
# _fleet_validate_clone_path rejects absolute paths, so a missing member's
# clone always fails validation ("Invalid path (outside fleet root ...)")
# regardless of its REMOTE_URL — and the parallel runner still exits 0.

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
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# TSV-based fleet: the roster of record is manifest.fleet.tsv. The fleet
# root itself is a git repo, as in production (the CLI validates this).
# operations.parallel defaults to true; pin it false so the default tests
# exercise the sequential runner, and --parallel exercises the parallel one.
write_fleet_config() {
    git -C "$SCRATCH/work" init -q -b main
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
operations:
  parallel: false
YAML
}

# Builds a member named $1:
#   - a bare origin at $SCRATCH/remote-$1.git seeded with commit c1
#   - a seeder clone that can push more commits
#   - the fleet member working copy at $SCRATCH/work/$1, cloned at c1
# Echoes nothing; the bare path is derivable from the name.
mk_member_with_origin() {
    local name="$1"
    local bare="$SCRATCH/remote-$name.git"
    local seed="$SCRATCH/seed-$name"

    git init -q --bare -b main "$bare"

    mkdir -p "$seed"
    git -C "$seed" init -q -b main
    git -C "$seed" config user.email t@e.com
    git -C "$seed" config user.name t
    echo "one" > "$seed/file.txt"
    git -C "$seed" add -A
    git -C "$seed" commit -qm c1
    git -C "$seed" remote add origin "file://$bare"
    git -C "$seed" push -q origin main

    git clone -q "file://$bare" "$SCRATCH/work/$name"
    git -C "$SCRATCH/work/$name" config user.email t@e.com
    git -C "$SCRATCH/work/$name" config user.name t
}

# Pushes a new commit to $1's origin from the seeder, leaving the member behind.
advance_origin() {
    local name="$1"
    local seed="$SCRATCH/seed-$name"
    echo "two" >> "$seed/file.txt"
    git -C "$seed" commit -qam c2
    git -C "$seed" push -q origin main
}

@test "prep fleet -y pulls a member that is behind its origin (HEAD advances)" {
    mk_member_with_origin svc-a
    advance_origin svc-a
    write_fleet_config
    printf 'true\tsvc-a\t./svc-a\ttrue\tfile://%s\tmain\n' "$SCRATCH/remote-svc-a.git" \
        > "$SCRATCH/work/manifest.fleet.tsv"

    local before remote_tip
    before="$(git -C "$SCRATCH/work/svc-a" rev-parse HEAD)"
    remote_tip="$(git -C "$SCRATCH/remote-svc-a.git" rev-parse main)"
    [ "$before" != "$remote_tip" ]   # fixture sanity: member starts behind

    run_manifest prep fleet -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Applying because -y/--yes was provided."* ]]
    [[ "$output" == *"MANIFEST FLEET SYNC"* ]]
    [[ "$output" != *"(DRY RUN)"* ]]
    # operations.parallel=false routes through the sequential runner.
    [[ "$output" != *"Running in parallel mode..."* ]]
    [[ "$output" == *"[1] svc-a"* ]]
    [[ "$output" == *"svc-a: ✓ Updated"* ]]
    [[ "$output" == *"Summary: 0 cloned, 1 pulled, 0 failed (of 1 total)"* ]]
    # The pull really happened: the member's HEAD moved to the origin tip.
    [ "$(git -C "$SCRATCH/work/svc-a" rev-parse HEAD)" = "$remote_tip" ]
}

@test "prep fleet -y --parallel pulls every behind member (HEADs advance)" {
    mk_member_with_origin svc-a
    mk_member_with_origin svc-b
    advance_origin svc-a
    advance_origin svc-b
    write_fleet_config
    {
        printf 'true\tsvc-a\t./svc-a\ttrue\tfile://%s\tmain\n' "$SCRATCH/remote-svc-a.git"
        printf 'true\tsvc-b\t./svc-b\ttrue\tfile://%s\tmain\n' "$SCRATCH/remote-svc-b.git"
    } > "$SCRATCH/work/manifest.fleet.tsv"

    local tip_a tip_b
    tip_a="$(git -C "$SCRATCH/remote-svc-a.git" rev-parse main)"
    tip_b="$(git -C "$SCRATCH/remote-svc-b.git" rev-parse main)"

    run_manifest prep fleet -y --parallel

    [ "$status" -eq 0 ]
    [[ "$output" == *"Running in parallel mode..."* ]]
    [[ "$output" == *"svc-a: ✓ Updated"* ]]
    [[ "$output" == *"svc-b: ✓ Updated"* ]]
    [[ "$output" == *"Summary: 0 cloned, 2 pulled, 0 failed (of 2 total)"* ]]
    [ "$(git -C "$SCRATCH/work/svc-a" rev-parse HEAD)" = "$tip_a" ]
    [ "$(git -C "$SCRATCH/work/svc-b" rev-parse HEAD)" = "$tip_b" ]
}

@test "prep fleet without -y stays a preview: a behind member does NOT advance" {
    mk_member_with_origin svc-a
    advance_origin svc-a
    write_fleet_config
    printf 'true\tsvc-a\t./svc-a\ttrue\tfile://%s\tmain\n' "$SCRATCH/remote-svc-a.git" \
        > "$SCRATCH/work/manifest.fleet.tsv"

    local before
    before="$(git -C "$SCRATCH/work/svc-a" rev-parse HEAD)"

    run_manifest prep fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST FLEET SYNC (DRY RUN)"* ]]
    [[ "$output" == *"svc-a: would pull --rebase"* ]]
    # Preview is read-only even with a genuinely behind member.
    [ "$(git -C "$SCRATCH/work/svc-a" rev-parse HEAD)" = "$before" ]
}
