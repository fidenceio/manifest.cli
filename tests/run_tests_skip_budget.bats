#!/usr/bin/env bats

# §5.10 skip accounting: run-tests.sh counts skipped tests and enforces
# MANIFEST_CLI_TEST_MAX_SKIPS.
#
# A skipped bats test emits `ok N name # skip reason`, so every TAP consumer —
# including this runner's own pass count — scores it as a pass. That makes lost
# coverage indistinguishable from a green run: an image that stops shipping
# `yq`, or a probe that quietly stops matching, reports the same 100%. The
# budget turns that silence into a failure in the one environment whose tooling
# we control (the test container), while a developer host, which legitimately
# lacks some tools, only gets the report.
#
# NOTE: not smoke-tagged. This covers the test harness itself, not a runtime
# safety contract, so it belongs to the full tier only.

load 'helpers/setup'

# Fixture bodies are emitted with the test keyword passed as a printf argument
# rather than written literally. bats preprocesses a file by matching that
# keyword at the start of any line — leading whitespace included — with no
# regard for whether the line sits inside a heredoc, so a literal fixture would
# register phantom tests in THIS file.
_write_fixture() {
    local file="$1" mode="$2"
    {
        printf '#!/usr/bin/env bats\n\n'
        printf '%s "budget fixture: a test that passes" {\n' '@test'
        printf '    [ 1 -eq 1 ]\n}\n\n'
        if [ "$mode" = "with-skip" ]; then
            printf '%s "budget fixture: a test that skips" {\n' '@test'
            printf '    skip "deliberately skipped by the budget fixture"\n}\n'
        fi
    } > "$file"
}

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    FIXTURE="$SCRATCH/skipper.bats"
    _write_fixture "$FIXTURE" with-skip
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# Always serial + uncached: the fixture's verdict must come from this run, and
# --jobs 1 keeps the TAP stream ordered.
RUNNER() { "$TEST_REPO_ROOT/scripts/run-tests.sh" --jobs 1 --no-cache "$@"; }

@test "skips: a skipped test is reported, not silently counted as a pass" {
    run RUNNER "$FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "1 test(s) skipped"
    echo "$output" | grep -q "deliberately skipped by the budget fixture"
}

@test "skips: no budget set means report-only (a developer host still passes)" {
    unset MANIFEST_CLI_TEST_MAX_SKIPS
    run RUNNER "$FIXTURE"
    [ "$status" -eq 0 ]
    refute grep -q "budget exceeded" <<<"$output"
}

@test "skips: exceeding the budget FAILS the run even though every test passed" {
    MANIFEST_CLI_TEST_MAX_SKIPS=0 run RUNNER "$FIXTURE"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "budget exceeded: 1 skipped, at most 0 allowed"
    # The fixture's own TAP stream is still all-green — that is the whole point.
    refute grep -q "^not ok " <<<"$output"
}

@test "skips: a budget at or above the count passes" {
    MANIFEST_CLI_TEST_MAX_SKIPS=1 run RUNNER "$FIXTURE"
    [ "$status" -eq 0 ]
    refute grep -q "budget exceeded" <<<"$output"
}

@test "skips: a zero budget passes when nothing skips" {
    _write_fixture "$SCRATCH/clean.bats" no-skip
    MANIFEST_CLI_TEST_MAX_SKIPS=0 run RUNNER "$SCRATCH/clean.bats"
    [ "$status" -eq 0 ]
    refute grep -q "test(s) skipped" <<<"$output"
}

@test "skips: a non-numeric budget fails closed rather than being ignored" {
    MANIFEST_CLI_TEST_MAX_SKIPS="lots" run RUNNER "$FIXTURE"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "is not a count; failing closed"
}
