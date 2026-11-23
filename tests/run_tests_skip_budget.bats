#!/usr/bin/env bats

# §5.10 skip accounting: run-tests.sh counts skipped tests and enforces
# MANIFEST_CLI_TEST_MAX_SKIPS (a count) and MANIFEST_CLI_TEST_EXPECTED_SKIPS
# (a list of the tests that may skip, each with its reason — what the
# container leg uses; tests/container_expected_skips.bats guards that list).
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
    # The container leg runs this file with its own list in the environment.
    # Each test here sets exactly the control it is about, so start from none:
    # an inherited list would fail the fixture's skip in every test.
    unset MANIFEST_CLI_TEST_EXPECTED_SKIPS MANIFEST_CLI_TEST_MAX_SKIPS
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
    grep -q "1 test(s) skipped" <<<"$output"
    grep -q "deliberately skipped by the budget fixture" <<<"$output"
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
    grep -q "budget exceeded: 1 skipped, at most 0 allowed" <<<"$output"
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
    grep -q "is not a count; failing closed" <<<"$output"
}

# --- the named list (MANIFEST_CLI_TEST_EXPECTED_SKIPS) ----------------------------
#
# The count above cannot tell which tests it is counting. The list names each
# test that may skip and the reason it gives; the container leg uses the list.

SKIP_NAME="budget fixture: a test that skips"
SKIP_WHY="deliberately skipped by the budget fixture"

# _write_list <name> <reason>  → $SCRATCH/expected.tsv
_write_list() {
    printf '# a comment line, and a blank one, are passed over\n\n%s\t%s\t%s\n' "$1" "$2" "fixture" > "$SCRATCH/expected.tsv"
}

@test "expected skips: a skip that is on the list, for the listed reason, passes" {
    _write_list "$SKIP_NAME" "$SKIP_WHY"
    MANIFEST_CLI_TEST_EXPECTED_SKIPS="$SCRATCH/expected.tsv" run RUNNER "$FIXTURE"
    [ "$status" -eq 0 ]
    refute grep -q "not expected to" <<<"$output"
}

@test "expected skips: a skip that is not on the list FAILS the run and is named — where a count of the same size says nothing" {
    # One expected skip went away and a different test started skipping: the
    # total is still one. This is the case the count cannot see.
    _write_list "some other test that used to skip here" "$SKIP_WHY"
    MANIFEST_CLI_TEST_MAX_SKIPS=1 run RUNNER "$FIXTURE"
    [ "$status" -eq 0 ]

    MANIFEST_CLI_TEST_EXPECTED_SKIPS="$SCRATCH/expected.tsv" run RUNNER "$FIXTURE"
    [ "$status" -ne 0 ]
    grep -qF "not on the list: $SKIP_NAME   (skipped: $SKIP_WHY)" <<<"$output"
    # Every test in the stream still passed: the list is what failed the run.
    refute grep -q "^not ok " <<<"$output"
}

@test "expected skips: a listed test that skips for another reason FAILS — a lost tool does not ride on an allowance" {
    _write_list "$SKIP_NAME" "root reads any file"
    MANIFEST_CLI_TEST_EXPECTED_SKIPS="$SCRATCH/expected.tsv" run RUNNER "$FIXTURE"
    [ "$status" -ne 0 ]
    grep -qF "listed for another reason: $SKIP_NAME   (skipped: $SKIP_WHY; listed: root reads any file)" <<<"$output"
}

@test "expected skips: a list that cannot be read fails closed" {
    MANIFEST_CLI_TEST_EXPECTED_SKIPS="$SCRATCH/no-such-list.tsv" run RUNNER "$FIXTURE"
    [ "$status" -ne 0 ]
    grep -qF "cannot be read; failing closed" <<<"$output"

    # An empty list allows nothing.
    : > "$SCRATCH/expected.tsv"
    MANIFEST_CLI_TEST_EXPECTED_SKIPS="$SCRATCH/expected.tsv" run RUNNER "$FIXTURE"
    [ "$status" -ne 0 ]
    grep -qF "not on the list: $SKIP_NAME" <<<"$output"
}

@test "expected skips: a listed test that runs after all is reported, and the run still passes" {
    _write_list "budget fixture: a test that passes" "it used to skip here"
    printf '%s\t%s\t%s\n' "$SKIP_NAME" "$SKIP_WHY" "fixture" >> "$SCRATCH/expected.tsv"
    MANIFEST_CLI_TEST_EXPECTED_SKIPS="$SCRATCH/expected.tsv" run RUNNER "$FIXTURE"
    [ "$status" -eq 0 ]
    grep -qF "on the expected-skips list, but ran here (not a failure):" <<<"$output"
    grep -qF "  - budget fixture: a test that passes" <<<"$output"
}

@test "expected skips: a relative path is read from the repository root, as the container leg passes it" {
    MANIFEST_CLI_TEST_EXPECTED_SKIPS="tests/containers/expected-skips.tsv" run RUNNER "$FIXTURE"
    # The fixture's skip is not one of the container's: read, and refused.
    [ "$status" -ne 0 ]
    grep -qF "not on the list: $SKIP_NAME" <<<"$output"
    refute grep -q "cannot be read" <<<"$output"
}
