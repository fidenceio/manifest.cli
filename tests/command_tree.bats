#!/usr/bin/env bats
# bats file_tags=smoke

load 'helpers/setup'
load 'helpers/preview_no_write'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

@test "removed commands and flags refuse before changing any workspace files" {
    local command_line before after
    local -a args
    # Reach argument dispatch with a valid target; otherwise an earlier
    # missing-repository error could make this test pass for a live alias.
    git -C "$SCRATCH/work" init -q -b main
    printf 'fleet:\n  name: test-fleet\n  versioning: none\n' > "$SCRATCH/work/manifest.fleet.config.yaml"
    before="$(preview_snapshot)"
    while IFS= read -r command_line; do
        read -r -a args <<< "$command_line"
        run_manifest "${args[@]}"
        [ "$status" -eq 1 ]
        [[ "$output" == *"Unknown"* ]] || { printf '%s\n' "$command_line" "$output" >&2; return 1; }
        after="$(preview_snapshot)"
        assert_no_writes "$before" "$after"
    done <<'COMMANDS'
prep repo -y
prep fleet -y
refresh fleet -y
refresh repo -y
first -y
sync -y
time
fleet help
ship patch -y
ship minor -y
ship major -y
ship revision -y
recipe run manifest.builtin.ship.repo.patch -y
plan fleet --apply
plan fleet --do
reconcile fleet --apply
reconcile fleet --do
ship fleet patch --noprep -y
COMMANDS
}

@test "fleet --require-clean refuses a dirty member before either repo is committed" {
    local root="$SCRATCH/work"
    git -C "$root" init -q -b main
    cat > "$root/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: test-fleet
  versioning: none
YAML
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\ntrue\tsvca\t./svca\ttrue\tmain\n' > "$root/manifest.fleet.tsv"
    git -C "$root" add manifest.fleet.config.yaml manifest.fleet.tsv
    git -C "$root" commit -qm root
    git -C "$root" init -q -b main svca
    echo 1.0.0 > "$root/svca/VERSION"
    git -C "$root/svca" add VERSION
    git -C "$root/svca" commit -qm member
    git -C "$root/svca" tag v1.0.0
    echo pending > "$root/svca/change"
    local root_head member_head
    root_head="$(git -C "$root" rev-parse HEAD)"
    member_head="$(git -C "$root/svca" rev-parse HEAD)"

    run_manifest ship fleet patch --require-clean --local -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"has uncommitted changes; cannot use --require-clean"* ]]
    [ "$(git -C "$root" rev-parse HEAD)" = "$root_head" ]
    [ "$(git -C "$root/svca" rev-parse HEAD)" = "$member_head" ]
    [ "$(cat "$root/svca/VERSION")" = 1.0.0 ]
}

@test "removed routes and unknown commands fail before config loading or upgrade checks" {
    # A valid repo is deliberately unnecessary. Plant config and an install
    # footprint so startup writes, including marker changes, are observable.
    mkdir -p "$HOME/.manifest-cli"
    printf 'debug:\n  enabled: false\n' > "$HOME/.manifest-cli/manifest.config.global.yaml"
    local before after command_line suffix
    local -a args
    before="$(preview_snapshot)"
    for suffix in '' '--help' '-y'; do
        while IFS= read -r command_line; do
            read -r -a args <<< "$command_line $suffix"
            MANIFEST_CLI_AUTO_CONFIRM=1 run_manifest "${args[@]}"
            [ "$status" -eq 1 ]
            [[ "$output" == *"Unknown"* ]] || { printf '%s\n' "$command_line" "$output" >&2; return 1; }
            [[ "$output" != *"Not in a Git repository"* ]]
            after="$(preview_snapshot)"
            assert_no_writes "$before" "$after"
        done <<'COMMANDS'
first
refresh repo
refresh fleet
sync
time
fleet help
ship patch
ship minor
ship major
ship revision
recipe run manifest.builtin.ship.repo.patch
frobnicate
COMMANDS
    done
    # Positive control: retained inspection still works from this same folder.
    run_manifest recipe list
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest.builtin.ship.repo.patch"* ]]
    [[ "$output" != *"manifest.builtin.refresh.repo"* ]]
    [[ "$output" == *"manifest.builtin.init.repo.connect"* ]]
}
