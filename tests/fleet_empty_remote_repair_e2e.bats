#!/usr/bin/env bats

# End-to-end coverage for the REPAIR-AND-PROCEED half of the empty-REMOTE_URL
# ship gate (_fleet_preflight_no_empty_remote).
#
# fleet_empty_remote_gate.bats proves the refusal end-to-end and the repair in
# isolation (direct gate call). This file proves the repair END-TO-END: a
# `ship fleet patch -y` through the entry script, where the member has NO
# local 'origin' but the fleet TSV declares a valid file:// REMOTE_URL. The
# gate must wire up origin from the TSV and the apply must continue PAST the
# refusal into the release mutations — in this all-local fixture the whole
# ship completes: version bumped, tagged, and pushed to the wired origin.
#
# Offline discipline: the origin is a local bare repo (file://), `gh` is the
# logging stub (the release step skips anyway — non-GitHub origin), the time
# cache is sandboxed and its server list points at a closed localhost port.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
    # Fail fast offline: one git attempt, no retry sleeps.
    export MANIFEST_CLI_GIT_RETRIES=1
    # Hermetic trusted-timestamp: private cache dir (never the machine-shared
    # one) and a closed localhost port → instant refusal → system-time fallback.
    export MANIFEST_CLI_CACHE_DIR="$SCRATCH/cache"
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    gh_stub_install
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
    unset MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_CACHE_DIR \
        MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT \
        MANIFEST_CLI_GIT_RETRIES
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# One-member fleet whose member svc-a has a commit history that EXISTS on the
# bare origin (seeded by an initial push) but whose local 'origin' remote has
# been removed — exactly the stranded shape the gate repairs from the TSV.
write_repairable_fleet() {
    git -C "$SCRATCH/work" init -q -b main
    git -C "$SCRATCH/work" config user.email t@e.com
    git -C "$SCRATCH/work" config user.name t

    local repo="$SCRATCH/work/svc-a"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email t@e.com
    git -C "$repo" config user.name t
    echo "1.0.0" > "$repo/VERSION"
    git -C "$repo" add -A
    git -C "$repo" commit -qm init

    BARE="$SCRATCH/remote-a.git"
    git init -q --bare -b main "$BARE"
    git -C "$repo" remote add origin "file://$BARE"
    git -C "$repo" push -q origin main
    git -C "$repo" remote remove origin

    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svca:
    path: "./svc-a"
    branch: "main"
YAML
    printf 'true\tsvca\t./svc-a\ttrue\tfile://%s\tmain\n' "$BARE" \
        > "$SCRATCH/work/manifest.fleet.tsv"
}

@test "ship fleet -y repairs origin from the TSV and proceeds past the empty-remote gate to a full release" {
    write_repairable_fleet
    # Fixture sanity: the member really starts with no origin.
    run git -C "$SCRATCH/work/svc-a" remote get-url origin
    [ "$status" -ne 0 ]

    run_manifest ship fleet patch -y

    # The gate REPAIRED instead of refusing...
    [[ "$output" == *"Wired up 'origin' for 1 member(s) from the fleet TSV"* ]]
    [[ "$output" == *"svc-a → file://$BARE"* ]]
    # ... so the refusal never fired.
    [[ "$output" != *"no 'origin' remote and no usable REMOTE_URL"* ]]
    [[ "$output" != *"no fleet member was shipped"* ]]
    # The repair is real on disk: origin now points at the TSV REMOTE_URL.
    run git -C "$SCRATCH/work/svc-a" remote get-url origin
    [ "$status" -eq 0 ]
    [ "$output" = "file://$BARE" ]
}

@test "ship fleet -y after the repair completes the release through the wired origin" {
    write_repairable_fleet

    run_manifest ship fleet patch -y

    # Past the gate, the apply entered the member's release mutation ...
    [[ "$output" == *"svca: shipping patch"* ]]
    # ... and, everything in this fixture being local, ran it to completion.
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fleet ship workflow complete."* ]]

    # Release state landed locally AND on the freshly wired origin.
    [ "$(cat "$SCRATCH/work/svc-a/VERSION")" = "1.0.1" ]
    [ "$(git -C "$SCRATCH/work/svc-a" tag)" = "v1.0.1" ]
    [ "$(git -C "$BARE" tag)" = "v1.0.1" ]
    [ "$(git -C "$BARE" rev-parse main)" = "$(git -C "$SCRATCH/work/svc-a" rev-parse HEAD)" ]

    # file:// origin is not GitHub: the Release step must skip, not call gh.
    [[ "$output" == *"GitHub Release: skipped (origin is not a GitHub repository)"* ]]
    ! grep -q $'\trelease\t' "$MANIFEST_CLI_GH_STUB_LOG"
}
