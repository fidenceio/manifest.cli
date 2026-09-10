#!/usr/bin/env bats
# §83 — the fleet ship tells the truth about what it did.
#
# It used to end on the same green line whether the fleet released, nothing
# happened, or the coordination-root commit failed — and exit 0 in all three;
# it ran the workspace policy gate (minutes, with image pulls) for a run that
# could do nothing; it streamed the gate's output unfiltered with no run log to
# keep it; the fleet root's outcome was conveyed by omission; and the recovery
# it recommended for a half-done root burned a version number.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
}

teardown() {
    unset MANIFEST_CLI_FLEET_GATE_HEARTBEAT_SECONDS
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT MANIFEST_CLI_TIME_RETRIES
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# The coordination root as a git repo with a committed FLEET_VERSION.
# $1 = fleet.versioning (none|semver); $2.. = member names (default: svca).
write_root() {
    local scheme="${1:-none}"; shift || true
    local -a members=("$@")
    [[ ${#members[@]} -gt 0 ]] || members=(svca)
    local w="$SCRATCH/work"
    git -C "$w" init -q -b main
    git -C "$w" config user.email t@example.com
    git -C "$w" config user.name T
    {
        printf 'fleet:\n  name: "test-fleet"\n  versioning: "%s"\n  version_file: "FLEET_VERSION"\nservices:\n' "$scheme"
        local m
        for m in "${members[@]}"; do
            printf '  %s:\n    path: "./%s"\n    branch: "main"\n' "$m" "$m"
        done
    } > "$w/manifest.fleet.config.yaml"
    # The header row is load-bearing: the loader resolves columns from it, and a
    # header-less roster is read as the LEGACY six-column layout, where BRANCH
    # sits one column further right — so a five-column row without the header
    # has no branch and every member defaults to main.
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\n' > "$w/manifest.fleet.tsv"
    # Column 5 is the member's release branch — the roster's word, which is what
    # the loader reads (the YAML services block's `branch:` is not consulted).
    local m
    for m in "${members[@]}"; do
        printf 'true\t%s\t./%s\tfalse\tmain\n' "$m" "$m" >> "$w/manifest.fleet.tsv"
    done
    echo "1.0.0" > "$w/FLEET_VERSION"
    git -C "$w" add manifest.fleet.config.yaml manifest.fleet.tsv FLEET_VERSION
    git -C "$w" commit -qm "coordination"
}

# Give the root an upstream it is level with.
root_level_with_upstream() {
    git init -q --bare "$SCRATCH/root-remote.git"
    git -C "$SCRATCH/work" remote add origin "$SCRATCH/root-remote.git"
    git -C "$SCRATCH/work" push -q -u origin main
}

# A member whose HEAD is at its tag: nothing to release.
write_member_at_tag() {
    local m="$SCRATCH/work/$1"
    mkdir -p "$m"
    git -C "$m" init -q -b main
    git -C "$m" config user.email t@example.com
    git -C "$m" config user.name T
    echo "1.2.3" > "$m/VERSION"
    git -C "$m" add VERSION
    git -C "$m" commit -qm "init 1.2.3"
    git -C "$m" tag v1.2.3
}

# A member with something to release (committed, never tagged).
write_member_releasable() {
    local m="$SCRATCH/work/$1"
    mkdir -p "$m"
    git -C "$m" init -q -b main
    git -C "$m" config user.email t@example.com
    git -C "$m" config user.name T
    echo "1.2.3" > "$m/VERSION"
    git -C "$m" add VERSION
    git -C "$m" commit -qm "init 1.2.3"
}

# A refusing pre-commit hook for REPO, installed outside every tree.
install_refusing_hook() {
    local repo="$1" hooks="$SCRATCH/hooks-$(basename "$repo")"
    mkdir -p "$hooks"
    printf '#!/bin/sh\necho "HOOK-FIXTURE: refusing this commit"\nexit 1\n' > "$hooks/pre-commit"
    chmod +x "$hooks/pre-commit"
    git -C "$repo" config core.hooksPath "$hooks"
}

write_gate() { # $1 = body
    mkdir -p "$SCRATCH/work/scripts"
    printf '#!/usr/bin/env bash\n%s\n' "$1" > "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"
    chmod +x "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"
}

fleet_run_log() {
    # The fleet process's own run log: the newest ship-*.log under this test's HOME.
    # Captured whole and sliced, not piped into head (suite_shell_options.bats).
    local logs
    logs="$(ls -t "$HOME"/.manifest-cli/logs/ship-*.log 2>/dev/null)"
    printf '%s' "${logs%%$'\n'*}"
}

# --- D2: nothing to do stops before the gate -------------------------------------

@test "nothing to release (versioning none, member at tag): says so, skips the gate, closes clean, exit 0" {
    write_root none
    write_member_at_tag svca
    write_gate "touch '$SCRATCH/work/gate-executed'; exit 0"

    run_manifest ship fleet patch -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to release: no member has changes since its tag, and fleet.versioning is none"* ]]
    [[ "$output" == *"--force-bump includes at-tag members"* ]]
    [ ! -e "$SCRATCH/work/gate-executed" ]
    [[ "$output" != *"Running workspace policy gate"* ]]
    [[ "$output" == *"Fleet ship workflow complete."* ]]
    [[ "$output" == *"members: 0 released"* ]]
    [[ "$output" == *"fleet root: nothing to do"* ]]
}

@test "nothing to release (semver, root level with upstream): the gate is not run" {
    write_root semver
    root_level_with_upstream
    write_member_at_tag svca
    write_gate "touch '$SCRATCH/work/gate-executed'; exit 0"

    run_manifest ship fleet patch -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"the fleet root is level with its upstream"* ]]
    [ ! -e "$SCRATCH/work/gate-executed" ]
    [ "$(cat "$SCRATCH/work/FLEET_VERSION")" = "1.0.0" ]
}

@test "CONTROL: a releaseable member means the gate DOES run" {
    write_root none
    write_member_releasable svca
    write_gate "touch '$SCRATCH/work/gate-executed'; exit 0"

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 0 ]
    [ -e "$SCRATCH/work/gate-executed" ]
    [[ "$output" == *"Workspace policy gate: OK"* ]]
}

# --- D1: closing block and exit code ----------------------------------------------

@test "clean local release: closing block counts members and names the root outcome; exit 0" {
    write_root none
    write_member_releasable svca

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"svca: shipping patch"* ]]
    [[ "$output" == *"Fleet ship workflow complete."* ]]
    [[ "$output" == *"members: 1 released · 0 skipped"* ]]
    # D4: the root says what it decided even when the answer is "nothing".
    [[ "$output" == *"fleet root: no version stamp (fleet.versioning: none)"* ]]
    [ "$(cat "$SCRATCH/work/svca/VERSION")" = "1.2.4" ]
}

@test "root commit refused after members released: closing block names the root failure; exit 2" {
    write_root semver
    write_member_releasable svca
    install_refusing_hook "$SCRATCH/work"

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 2 ]
    [[ "$output" == *"svca: shipping patch"* ]]
    # The member released; the root did not; the hook's own line is visible.
    [ "$(cat "$SCRATCH/work/svca/VERSION")" = "1.2.4" ]
    [[ "$output" == *"HOOK-FIXTURE: refusing this commit"* ]]
    [[ "$output" == *"finished with a failure at the fleet root (exit 2"* ]]
    [[ "$output" == *"fleet root: FAILED: the coordination commit was refused"* ]]
    [[ "$output" != *"✅ Fleet ship workflow complete."* ]]
    # The stamp stays on disk, uncommitted, as the record of the intended version.
    [ "$(cat "$SCRATCH/work/FLEET_VERSION")" = "1.0.1" ]
    [ "$(git -C "$SCRATCH/work" show HEAD:FLEET_VERSION)" = "1.0.0" ]
}

@test "a member fails AFTER another released: exit 2 and the block says which stopped it" {
    write_root none svca svcb
    write_member_releasable svca
    write_member_releasable svcb
    install_refusing_hook "$SCRATCH/work/svcb"

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 2 ]
    [[ "$output" == *"Fleet ship workflow stopped at svcb."* ]]
    [[ "$output" == *"members: 1 released"* ]]
    [[ "$output" == *"1 failed (svcb)"* ]]
    [ "$(cat "$SCRATCH/work/svca/VERSION")" = "1.2.4" ]
}

@test "CONTROL: the FIRST member fails: nothing released, exit stays 1" {
    write_root none svca svcb
    write_member_releasable svca
    write_member_releasable svcb
    install_refusing_hook "$SCRATCH/work/svca"

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 1 ]
    [[ "$output" == *"Fleet ship workflow stopped at svca."* ]]
    [[ "$output" == *"members: 0 released"* ]]
}

# --- D3: the gate's output is captured, summarised, and kept -----------------------

@test "a failing gate shows its last 40 lines and the run log path; the log holds all of it" {
    write_root none
    write_member_releasable svca
    write_gate 'for i in $(seq 1 200); do echo "gate-line $i"; done; echo "BLOCKING-FINDING-XYZ" >&2; exit 1'

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 1 ]
    [[ "$output" == *"Workspace policy gate: FAILED (exit 1). Last 40 of 201 line(s):"* ]]
    [[ "$output" == *"gate-line 200"* ]]
    [[ "$output" == *"BLOCKING-FINDING-XYZ"* ]]
    [[ "$output" != *"gate-line 100"* ]]
    [[ "$output" == *"full output: "* ]]
    [[ "$output" == *"Pre-flight refused before any mutation; no fleet member was shipped."* ]]
    local log; log="$(fleet_run_log)"
    [ -n "$log" ]
    grep -q "gate-line 1$" "$log"
    grep -q "step=workspace_gate  exit=1" "$log"
    [ "$(cat "$SCRATCH/work/svca/VERSION")" = "1.2.3" ]
}

@test "a passing gate prints one OK line, not its output" {
    write_root none
    write_member_releasable svca
    write_gate 'for i in $(seq 1 50); do echo "gate-line $i"; done; exit 0'

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Workspace policy gate: OK (50 line(s) captured to the run log)"* ]]
    [[ "$output" != *"gate-line 7"* ]]
}

@test "a slow gate prints a heartbeat while it runs" {
    write_root none
    write_member_releasable svca
    write_gate 'sleep 3; exit 0'
    export MANIFEST_CLI_FLEET_GATE_HEARTBEAT_SECONDS=1

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"workspace policy gate still running ("* ]]
}

# --- D4: the root line in preview -----------------------------------------------

@test "preview: the fleet root says what it would do even when that is nothing" {
    write_root none
    write_member_releasable svca

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet root: no version stamp (fleet.versioning: none)"* ]]
}

# --- D5: a pending stamp is landed, never re-bumped ---------------------------------

@test "manager lands a pending stamp at the version on disk instead of bumping past it" {
    write_root semver
    echo "1.0.1" > "$SCRATCH/work/FLEET_VERSION"     # left by an earlier run that could not commit

    run_manifest ship fleet manager

    [ "$status" -eq 0 ]
    [[ "$output" == *"would land the pending fleet version 1.0.1"* ]]

    run_manifest ship fleet manager --local -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"landing the pending fleet version 1.0.1"* ]]
    # The fixture root has no allowlist .gitignore yet, so the manager writes one
    # and names it in the subject's "(updates: …)" — the version is what matters.
    [[ "$(git -C "$SCRATCH/work" log -1 --format=%s)" == "Fleet manager: bump fleet version to 1.0.1"* ]]
    [ "$(git -C "$SCRATCH/work" show HEAD:FLEET_VERSION)" = "1.0.1" ]
}

@test "manager with a bump word REFUSES while a pending stamp is on disk" {
    write_root semver
    echo "1.0.1" > "$SCRATCH/work/FLEET_VERSION"
    local before; before="$(git -C "$SCRATCH/work" rev-parse HEAD)"

    run_manifest ship fleet manager patch --local -y

    [ "$status" -ne 0 ]
    [[ "$output" == *"a fleet version stamp 1.0.1 is on disk and not committed"* ]]
    [ "$(git -C "$SCRATCH/work" rev-parse HEAD)" = "$before" ]
}

@test "CONTROL: with no pending stamp the manager bumps from HEAD's version" {
    write_root semver

    run_manifest ship fleet manager patch --local -y

    [ "$status" -eq 0 ]
    [ "$(git -C "$SCRATCH/work" show HEAD:FLEET_VERSION)" = "1.0.1" ]
    [[ "$(git -C "$SCRATCH/work" log -1 --format=%s)" == "Fleet manager: bump fleet version to 1.0.1"* ]]
}

# --- D6: the branch pre-flight ---------------------------------------------------

@test "plan: an at-tag member parked on another branch says so instead of a bare 'no changes'" {
    write_root none
    write_member_at_tag svca
    git -C "$SCRATCH/work/svca" checkout -q -b feature/x

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"(no changes; on feature/x, not main)"* ]]
}

@test "pre-flight judges each member by ITS roster branch, not the root's default (master under a main root ships)" {
    write_root none
    write_member_releasable svca
    # The roster (TSV column 5) says this member releases from master, and so
    # does the member's own config.
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\ntrue\tsvca\t./svca\tfalse\tmaster\n' > "$SCRATCH/work/manifest.fleet.tsv"
    git -C "$SCRATCH/work" commit -qam "roster: svca on master"
    git -C "$SCRATCH/work/svca" branch -m main master
    printf 'git:\n  default_branch: "master"\n' > "$SCRATCH/work/svca/manifest.config.yaml"
    git -C "$SCRATCH/work/svca" add manifest.config.yaml
    git -C "$SCRATCH/work/svca" commit -qm "config"

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"svca: shipping patch"* ]]
    [[ "$output" != *"Cannot release: HEAD is on"* ]]
    [ "$(cat "$SCRATCH/work/svca/VERSION")" = "1.2.4" ]
}

# --- Found by the pre-commit steward review of the first cut; fixed before shipping ---

@test "a gate that fails with NO output reports 0 lines cleanly (grep -c exits 1 on an empty file)" {
    write_root none
    write_member_releasable svca
    write_gate 'exit 1'

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 1 ]
    [[ "$output" == *"Workspace policy gate: FAILED (exit 1). Last 0 of 0 line(s):"* ]]
    [[ "$output" != *"arithmetic syntax error"* ]]
    [ "$(cat "$SCRATCH/work/svca/VERSION")" = "1.2.3" ]
}

@test "the gate runs in the FOREGROUND: it does not start with SIGINT ignored, so Ctrl-C reaches it" {
    # A child started with `&` inherits an IGNORED SIGINT, and `trap -p INT`
    # inside it prints that ignore; a foreground child prints nothing. Control:
    # if this harness already ignores SIGINT the foreground shape inherits it
    # too and the two are indistinguishable here — skip rather than pass
    # vacuously.
    if [[ "$(trap -p INT)" == "trap -- '' SIGINT" ]]; then
        skip "SIGINT is already ignored by the harness; the disposition is not observable"
    fi
    write_root none
    write_member_releasable svca
    write_gate 'trap -p INT; echo "GATE-RAN"; exit 1'

    run_manifest ship fleet patch --local -y

    [ "$status" -eq 1 ]
    [[ "$output" == *"GATE-RAN"* ]]
    [[ "$output" != *"trap -- '' SIGINT"* ]]
}

@test "a PR-gated member with changes is refused with its replay line, not reported as nothing to release" {
    write_root none
    write_member_releasable svca
    # Appended under the only service in the root config's services block.
    printf '    release:\n      strategy: "pr"\n' >> "$SCRATCH/work/manifest.fleet.config.yaml"

    run_manifest ship fleet patch -y

    [ "$status" -eq 1 ]
    [[ "$output" == *"PR-gated (release.strategy: pr)"* ]]
    [[ "$output" == *"Replay:      manifest pr fleet -y"* ]]
    [[ "$output" != *"Nothing to release"* ]]
    [[ "$output" != *"Fleet ship workflow complete."* ]]
    [ "$(cat "$SCRATCH/work/svca/VERSION")" = "1.2.3" ]
}

@test "a whitespace-only difference in the version file is NOT a pending stamp" {
    write_root semver
    printf '1.0.0 \n' > "$SCRATCH/work/FLEET_VERSION"      # HEAD carries "1.0.0"

    run_manifest ship fleet manager

    [ "$status" -eq 0 ]
    [[ "$output" != *"pending"* ]]

    run_manifest ship fleet manager patch --local -y

    [ "$status" -eq 0 ]
    [ "$(git -C "$SCRATCH/work" show HEAD:FLEET_VERSION)" = "1.0.1" ]
    [[ "$(git -C "$SCRATCH/work" log -1 --format=%s)" == "Fleet manager: bump fleet version to 1.0.1"* ]]
}

@test "nothing to release with a pending stamp on disk names it and points at the manager" {
    write_root semver
    root_level_with_upstream
    write_member_at_tag svca
    echo "1.0.1" > "$SCRATCH/work/FLEET_VERSION"

    run_manifest ship fleet patch -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"A fleet version stamp 1.0.1 is on disk and not committed; 'manifest ship fleet manager' lands it."* ]]
}
