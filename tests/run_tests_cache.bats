#!/usr/bin/env bats

# §5.10 TTL'd green-run cache: run-tests.sh --cache / --no-cache. After a green
# run, run-tests.sh records a fingerprint (content of modules/ + tests/ + the
# script + the bats version, keyed by run scope) and, on a later run that matches
# within the window, skips re-running and reports a cache hit. The cache only ever
# skips byte-identical inputs that already passed; any doubt is a miss and runs.
#
# These drive a tiny fixture (tests/fixtures/cache_probe.bats) as the explicit
# target so a MISS costs one trivial test, not a real suite. The marker store is
# redirected to an isolated temp dir via MANIFEST_CLI_TEST_CACHE_DIR so nothing
# touches the repo's real .test-cache/, and the window via
# MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN. --print-cache-key is the hermetic seam
# for the fingerprint, mirroring step 3's --print-cmd.
#
# NOTE: not smoke-tagged — this covers the test harness, not a runtime safety
# contract, so it belongs to the full tier only.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

RUN() { "$TEST_REPO_ROOT/scripts/run-tests.sh" "$@"; }
PROBE() { printf '%s' "$TEST_REPO_ROOT/tests/fixtures/cache_probe.bats"; }

setup() {
    CACHE_DIR="$BATS_TEST_TMPDIR/test-cache"
    export MANIFEST_CLI_TEST_CACHE_DIR="$CACHE_DIR"
    # Deterministic default window for these tests unless a case overrides it.
    export MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN="4h"
}

# Seed a cache marker for the key the runner will compute for $1... (run args),
# stamped `now - $AGE_SECONDS` (default 0 = just now).
_seed_marker() {
    local age="${AGE_SECONDS:-0}" key now
    key="$(RUN --print-cache-key "$@")"
    [ -n "$key" ] || return 1
    mkdir -p "$CACHE_DIR"
    now="$(date +%s)"
    printf '%s\n' "$(( now - age ))" > "$CACHE_DIR/$key"
}

@test "cache: --print-cache-key emits a stable, non-empty fingerprint" {
    run RUN --print-cache-key "$(PROBE)"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # hex digest, no spaces
    [[ "$output" =~ ^[0-9a-f]+$ ]]
    local first="$output"
    run RUN --print-cache-key "$(PROBE)"
    [ "$output" = "$first" ]
}

@test "cache: the key is scoped — smoke vs full differ" {
    run RUN --print-cache-key --tier smoke "$(PROBE)"
    local smoke="$output"
    run RUN --print-cache-key --tier full "$(PROBE)"
    [ "$output" != "$smoke" ]
}

@test "cache: --jobs does NOT change the key (parallelism is not part of scope)" {
    run RUN --print-cache-key --jobs 1 "$(PROBE)"
    local serial="$output"
    run RUN --print-cache-key --jobs 4 "$(PROBE)"
    [ "$output" = "$serial" ]
}

@test "cache: a fresh marker is a hit — the run is skipped" {
    _seed_marker "$(PROBE)"
    run --separate-stderr RUN "$(PROBE)"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[cache] hit"* ]]
    # skipped: bats never ran, so no TAP output on stdout
    [[ "$output" != *"cache probe"* ]]
    [[ "$output" != *"1.."* ]]
}

@test "cache: an expired marker is a miss — the run proceeds" {
    AGE_SECONDS=99999 _seed_marker "$(PROBE)"   # older than the 4h window
    run --separate-stderr RUN "$(PROBE)"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[cache] stale"* ]]
    [[ "$output" == *"cache probe"* ]]   # the fixture actually ran
}

@test "cache: --no-cache forces a run even with a fresh marker" {
    _seed_marker "$(PROBE)"
    run --separate-stderr RUN --no-cache "$(PROBE)"
    [ "$status" -eq 0 ]
    [[ "$stderr" != *"[cache] hit"* ]]
    [[ "$output" == *"cache probe"* ]]
}

@test "cache: window 'off' disables the cache (fresh marker ignored)" {
    _seed_marker "$(PROBE)"
    MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN="off" \
        run --separate-stderr RUN "$(PROBE)"
    [ "$status" -eq 0 ]
    [[ "$stderr" != *"[cache] hit"* ]]
    [[ "$output" == *"cache probe"* ]]
}

@test "cache: an unparseable window warns and runs (fail-safe to off)" {
    _seed_marker "$(PROBE)"
    MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN="banana" \
        run --separate-stderr RUN "$(PROBE)"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"ignoring unrecognized test.skip_unchanged_within"* ]]
    [[ "$stderr" != *"[cache] hit"* ]]
    [[ "$output" == *"cache probe"* ]]
}

@test "cache: a green run records a marker that the next run hits" {
    [ ! -d "$CACHE_DIR" ] || [ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]
    # first run: cold cache → executes, records
    run --separate-stderr RUN "$(PROBE)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cache probe"* ]]
    [[ "$stderr" == *"[cache] recorded green run"* ]]
    [ -n "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]
    # second run: warm cache → hit, skipped
    run --separate-stderr RUN "$(PROBE)"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[cache] hit"* ]]
    [[ "$output" != *"cache probe"* ]]
}

@test "cache: a failing run is NOT cached (no marker written)" {
    # Point at a fixture-style target that fails by running a non-existent file.
    run --separate-stderr RUN "$BATS_TEST_TMPDIR/does-not-exist.bats"
    [ "$status" -ne 0 ]
    [ ! -d "$CACHE_DIR" ] || [ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]
}
