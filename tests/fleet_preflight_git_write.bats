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
true	svca	./svc-a	true
true	svcb	./svc-b	true
TSV
}

@test "ship fleet -y refuses pre-flight when a member's .git is not writable" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root bypasses chmod-based write restriction (covered by the non-root macOS CI leg)"
    fi
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

@test "ship fleet -y fails closed on workspace policy gate before mutation" {
    write_two_member_fleet
    mkdir -p "$SCRATCH/work/scripts"
    cat > "$SCRATCH/work/scripts/manifest-fleet-preflight.sh" <<'SH'
#!/usr/bin/env bash
echo "dependency policy blocked"
exit 42
SH
    chmod +x "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"

    run_manifest ship fleet patch -y --local

    [ "$status" -ne 0 ]
    [[ "$output" == *"dependency policy blocked"* ]]
    [[ "$output" == *"workspace policy gate failed"* ]]
    [[ "$output" == *"no fleet member was shipped"* ]]
    [ -z "$(git -C "$SCRATCH/work/svc-a" tag 2>/dev/null)" ]
    [ "$(cat "$SCRATCH/work/svc-a/VERSION")" = "1.0.0" ]
}

# Contract history, 2026-08-21. 282f875 briefly made preview EXECUTE this gate,
# to stop preview closing with "re-run with -y" for an apply guaranteed to
# refuse (found live on a 19-releaseable plan). The default was then inverted to
# announce, before either behavior shipped: the gate is a workspace-supplied
# script the CLI does not own, and in someone else's fleet it may be slow or
# side-effectful, so a preview must not run it unasked.
#
# So this test's original claim — preview does not execute the gate — holds
# again, and now carries a second half: preview must still NAME the gate, or the
# -y recommendation keeps the false confidence 282f875 set out to fix.
#
# Opt-in execution (MANIFEST_CLI_FLEET_PREVIEW_POLICY_GATE=run) and the verdict
# surface are covered in fleet_workspace_policy.bats.
@test "ship fleet preview announces the workspace policy gate without running it" {
    write_two_member_fleet
    mkdir -p "$SCRATCH/work/scripts"
    cat > "$SCRATCH/work/scripts/manifest-fleet-preflight.sh" <<'SH'
#!/usr/bin/env bash
touch invoked
exit 42
SH
    chmod +x "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    # Not executed — the stub's marker file is the proof, not the absence of a
    # log line, which a refactor could drop without changing behaviour.
    [ ! -e "$SCRATCH/work/invoked" ]
    # But named, so preview is not silent about what apply is going to do.
    [[ "$output" == *"not run in preview; apply refuses if it fails"* ]]
}
