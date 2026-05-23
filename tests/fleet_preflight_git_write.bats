#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    # Restore write perms before cleanup so rm -rf can drain read-only .git dirs.
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

write_two_member_fleet() {
    git -C "$SCRATCH/work" init -q
    mkdir -p "$SCRATCH/work/svc-a" "$SCRATCH/work/svc-b"
    git -C "$SCRATCH/work/svc-a" init -q
    git -C "$SCRATCH/work/svc-b" init -q
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
true	svca	./svc-a	service	true
true	svcb	./svc-b	service	true
TSV
}

@test "ship fleet -y refuses pre-flight when a member's .git is not writable" {
    write_two_member_fleet

    chmod a-w "$SCRATCH/work/svc-a/.git"

    run_manifest ship fleet patch -y

    [ "$status" -ne 0 ]
    [[ "$output" == *"Pre-flight: .git write denied"* ]]
    [[ "$output" == *"svca"* ]]
    [[ "$output" == *"sandboxed environment"* ]]
    [[ "$output" == *"rerun outside the sandbox"* ]]
    [[ "$output" == *"no fleet member was modified"* ]]

    # The writable member must not have been touched: no new tags, VERSION pinned.
    [ -z "$(git -C "$SCRATCH/work/svc-b" tag 2>/dev/null)" ]
    [ "$(cat "$SCRATCH/work/svc-b/VERSION")" = "1.0.0" ]
}

@test "ship fleet preview does not invoke .git writability pre-flight" {
    write_two_member_fleet

    chmod a-w "$SCRATCH/work/svc-a/.git"

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship fleet preview"* ]]
    [[ "$output" != *"Pre-flight: .git write denied"* ]]
}
