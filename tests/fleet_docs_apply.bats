#!/usr/bin/env bats

# APPLY coverage for `manifest docs fleet` (fleet_docs_run) and the
# `docs fleet status` report (fleet_docs_status).
#
# fleet_dry_run.bats proves the preview writes nothing. This file proves the
# apply: with strategy "both", `docs fleet -y` writes the fleet-root docs
# (docs/INDEX.md + root CHANGELOG.md) AND per-service docs (each member's
# CHANGELOG.md + docs/INDEX.md); --fleet-only restricts the writes to the
# fleet root. The status subcommand reports the resolved configuration.
#
# Offline discipline: get_time_timestamp is pointed at a closed localhost
# port with a 1s timeout, so it fails fast and falls back to system time —
# no network egress, no multi-second stalls.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
    # Trusted-timestamp lookups must not leave the machine: one server, on a
    # closed localhost port, 1s cap → immediate refusal → system-time fallback.
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# A member repo with VERSION + an initial commit on main.
mk_member_repo() {
    local repo="$1" version="${2:-1.2.3}"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email t@e.com
    git -C "$repo" config user.name t
    echo "$version" > "$repo/VERSION"
    git -C "$repo" add -A
    git -C "$repo" commit -qm init
}

# One-member fleet with docs strategy "both" (fleet-root + per-service).
write_docs_fleet() {
    git -C "$SCRATCH/work" init -q -b main
    mk_member_repo "$SCRATCH/work/svc" "1.2.3"
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
docs:
  strategy: "both"
  fleet_root:
    folder: "docs"
  per_service:
    folder: "docs"
YAML
    printf 'true\tsvc\t./svc\ttrue\t\tmain\n' > "$SCRATCH/work/manifest.fleet.tsv"
}

@test "docs fleet -y (strategy both) writes fleet-root AND per-service docs" {
    write_docs_fleet

    run_manifest docs fleet -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Applying because -y/--yes was provided."* ]]
    [[ "$output" == *"Generating fleet-root documentation..."* ]]
    [[ "$output" == *"Generating per-service documentation..."* ]]
    [[ "$output" == *"svc: docs generated (v1.2.3)"* ]]

    # Fleet-root writes: the fleet docs index lists the member and its version.
    [ -f "$SCRATCH/work/docs/INDEX.md" ]
    grep -q '^# Fleet Documentation Index$' "$SCRATCH/work/docs/INDEX.md"
    grep -q '\*\*Fleet:\*\* test-fleet' "$SCRATCH/work/docs/INDEX.md"
    grep -q '| svc | v1.2.3 |' "$SCRATCH/work/docs/INDEX.md"
    # Fleet-root CHANGELOG.md is created with the service summary table.
    [ -f "$SCRATCH/work/CHANGELOG.md" ]
    grep -q '^# Changelog$' "$SCRATCH/work/CHANGELOG.md"
    grep -q '### Service Summary' "$SCRATCH/work/CHANGELOG.md"
    grep -q '| svc | v1.2.3 | patch |' "$SCRATCH/work/CHANGELOG.md"

    # Per-service writes: the member gets its own CHANGELOG entry + docs index.
    [ -f "$SCRATCH/work/svc/CHANGELOG.md" ]
    grep -q '^# Changelog$' "$SCRATCH/work/svc/CHANGELOG.md"
    grep -q '^## \[1.2.3\] - ' "$SCRATCH/work/svc/CHANGELOG.md"
    [ -f "$SCRATCH/work/svc/docs/INDEX.md" ]
}

@test "docs fleet -y --fleet-only writes fleet-root docs and skips members" {
    write_docs_fleet

    run_manifest docs fleet -y --fleet-only

    [ "$status" -eq 0 ]
    [[ "$output" == *"Generating fleet-root documentation..."* ]]
    [[ "$output" != *"Generating per-service documentation..."* ]]

    [ -f "$SCRATCH/work/docs/INDEX.md" ]
    [ -f "$SCRATCH/work/CHANGELOG.md" ]
    # The member was not touched.
    [ ! -f "$SCRATCH/work/svc/CHANGELOG.md" ]
    [ ! -d "$SCRATCH/work/svc/docs" ]
}

@test "docs fleet status reports strategy, folders, and per-service targets" {
    write_docs_fleet

    run_manifest docs fleet status

    [ "$status" -eq 0 ]
    [[ "$output" == *"Fleet Docs Configuration"* ]]
    [[ "$output" == *"Strategy: both"* ]]
    [[ "$output" == *"Fleet-Root Docs:  ENABLED"* ]]
    [[ "$output" == *"Folder:"*"/docs/"* ]]
    [[ "$output" == *"Per-Service Docs: ENABLED"* ]]
    [[ "$output" == *"Folder Name:    docs/"* ]]
    # The member is listed with its resolved version and docs target.
    [[ "$output" == *"- svc (v1.2.3):"*"/svc/docs/"* ]]
    [[ "$output" == *"Document Types:"* ]]
    # status is read-only: nothing was generated.
    [ ! -d "$SCRATCH/work/docs" ]
    [ ! -f "$SCRATCH/work/CHANGELOG.md" ]
}
