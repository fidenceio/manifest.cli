#!/usr/bin/env bats

# §5.10 parallelization: run-tests.sh --jobs N|auto. GNU parallel is a required
# test dependency for parallel runs; --jobs 1 is the serial escape hatch. These
# assert the *resolved plan* via --print-cmd rather than executing the suite.
#
# NOTE: not smoke-tagged. This covers the test harness itself, not a runtime
# safety contract, so it belongs to the full tier only.

load 'helpers/setup'

RUNNER() { "$TEST_REPO_ROOT/scripts/run-tests.sh" "$@"; }

@test "jobs: bare run defaults to --jobs auto (parallel) when GNU parallel is present" {
    if ! command -v parallel >/dev/null 2>&1 || ! parallel --version 2>/dev/null | grep -qi 'GNU parallel'; then
        skip "GNU parallel not installed in this environment"
    fi
    run RUNNER --print-cmd
    [ "$status" -eq 0 ]
    # auto resolves to the CPU count; on any multi-core box that's a --jobs N flag.
    [[ "$output" == bats* ]]
    [[ "$output" == *"$TEST_REPO_ROOT/tests"* ]]
    # Either parallel (multi-core) or bare (single-core) — but never an error.
    [[ "$output" == *"--jobs "* || "$output" == "bats $TEST_REPO_ROOT/tests" ]]
}

@test "jobs: --jobs 1 is the serial escape hatch (no --jobs flag, no parallel dep)" {
    run RUNNER --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats $TEST_REPO_ROOT/tests" ]
    [[ "$output" != *"--jobs"* ]]
}

@test "jobs: an explicit count threads --jobs N to bats" {
    if ! command -v parallel >/dev/null 2>&1 || ! parallel --version 2>/dev/null | grep -qi 'GNU parallel'; then
        skip "GNU parallel not installed in this environment"
    fi
    run RUNNER --jobs 4 --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats --jobs 4 $TEST_REPO_ROOT/tests" ]
}

@test "jobs: --jobs combines with --tier (parallel flag precedes the tag filter)" {
    if ! command -v parallel >/dev/null 2>&1 || ! parallel --version 2>/dev/null | grep -qi 'GNU parallel'; then
        skip "GNU parallel not installed in this environment"
    fi
    run RUNNER --jobs 4 --tier smoke --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats --jobs 4 --filter-tags smoke $TEST_REPO_ROOT/tests" ]
}

@test "jobs: a non-numeric --jobs is rejected (exit 2), never silently run" {
    run RUNNER --jobs abc --print-cmd
    [ "$status" -eq 2 ]
    [[ "$output" == *"positive integer or 'auto'"* ]]
}

@test "jobs: --jobs 0 is rejected (exit 2)" {
    run RUNNER --jobs 0 --print-cmd
    [ "$status" -eq 2 ]
    [[ "$output" == *">= 1"* ]]
}

@test "jobs: --jobs=N form is accepted (equals syntax)" {
    if ! command -v parallel >/dev/null 2>&1 || ! parallel --version 2>/dev/null | grep -qi 'GNU parallel'; then
        skip "GNU parallel not installed in this environment"
    fi
    run RUNNER --jobs=3 --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats --jobs 3 $TEST_REPO_ROOT/tests" ]
}

@test "jobs: a parallel run without a GNU parallel is a hard error, not a serial downgrade" {
    # Shadow the real binary with a non-GNU 'parallel' (the moreutils-collision
    # case). Prepend a sandbox dir holding only that fake so it wins lookup; bash
    # still resolves from the inherited PATH. The runner must exit 2 with install
    # guidance rather than quietly run serially (which would misreport what ran).
    local sandbox="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$sandbox"
    cat >"$sandbox/parallel" <<'EOF'
#!/bin/sh
echo "parallel (moreutils-style) 0.0 — not GNU"
EOF
    chmod +x "$sandbox/parallel"

    run env PATH="$sandbox:$PATH" "$TEST_REPO_ROOT/scripts/run-tests.sh" --jobs 4 --print-cmd
    # run-tests.sh re-prepends Homebrew's bin on some hosts, which can re-expose a
    # real GNU parallel ahead of our fake. When that happens we can't simulate
    # absence here — skip honestly rather than assert a false negative.
    if [ "$status" -eq 0 ]; then
        skip "host PATH re-resolved a GNU parallel; cannot simulate its absence"
    fi
    [ "$status" -eq 2 ]
    [[ "$output" == *"GNU parallel is required"* ]]
    [[ "$output" == *"--jobs 1"* ]]
}
