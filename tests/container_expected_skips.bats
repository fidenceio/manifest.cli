#!/usr/bin/env bats

# tests/containers/expected-skips.tsv — the list of tests that may skip in the
# container leg. run-tests.sh enforces the list against a run
# (tests/run_tests_skip_budget.bats); this file keeps the list itself honest:
#
#   well-formed   three non-empty fields a row, no test named twice
#   not stale     every row names a test that exists, and a reason that the
#                 file holding that test still gives — so a renamed or deleted
#                 test cannot leave an allowance behind for something else
#   in use        the container runner and the coverage run hand this file
#                 to the runner, and neither sets a count
#
# NOTE: not smoke-tagged. This covers the test harness, not a runtime safety
# contract.

load 'helpers/setup'

LIST="$BATS_TEST_DIRNAME/containers/expected-skips.tsv"

# The rows, comments and blank lines dropped.
rows() { grep -v -e '^#' -e '^$' "$LIST"; }

@test "expected-skips list: every row has three non-empty fields, and no test is listed twice" {
    [ -r "$LIST" ]
    local n
    n="$(rows | grep -c .)"
    [ "$n" -gt 0 ]
    run awk -F'\t' 'NF != 3 || $1 == "" || $2 == "" || $3 == "" { print "bad row " NR ": " $0; bad = 1 } END { exit bad ? 1 : 0 }' <(rows)
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    local dupes
    dupes="$(rows | cut -f1 | sort | uniq -d)"
    [ -z "$dupes" ] || { echo "listed twice: $dupes"; return 1; }
}

@test "expected-skips list: every row names a test that exists and a reason its file still gives" {
    local name why note file stale=""
    while IFS=$'\t' read -r name why note; do
        # The test, by its whole @test line (-x: a commented-out copy, or a
        # longer name this one is a prefix of, is not a match); then the
        # reason, in the same file.
        file="$(grep -l -x -F -- "@test \"$name\" {" "$BATS_TEST_DIRNAME"/*.bats || true)"
        if [ -z "$file" ]; then
            stale+="no such test: $name"$'\n'
            continue
        fi
        if [ "$(printf '%s\n' "$file" | grep -c .)" -ne 1 ]; then
            stale+="named in more than one file: $name"$'\n'
            continue
        fi
        grep -q -F -- "$why" "$file" || stale+="$(basename "$file") no longer gives this reason: $why"$'\n'
    done < <(rows)
    [ -z "$stale" ] || { printf '%s' "$stale"; return 1; }
}

@test "expected-skips list: the container runner uses it, and sets no count of its own" {
    local runner="$TEST_REPO_ROOT/scripts/run-tests-container.sh"
    grep -qF 'MANIFEST_CLI_TEST_EXPECTED_SKIPS:-tests/containers/expected-skips.tsv' "$runner"
    grep -qF -- '-e MANIFEST_CLI_TEST_EXPECTED_SKIPS' "$runner"
    # A count set beside the list — a default or a plain assignment — would
    # be a second, weaker verdict. (`${VAR+x}`, the pass-through test, is not
    # an assignment and is not matched.)
    refute grep -qE 'MANIFEST_CLI_TEST_MAX_SKIPS(:[-=]|=)' "$runner"
}

@test "expected-skips list: no test is named so that the runner would misread it as a skip" {
    # bats does not escape `#` in a name, so TAP for a passing test named
    # "… # skip …" is indistinguishable from a skipped one. The runner then
    # fails closed on it; this says why before a run does.
    local odd
    odd="$(grep -n -E '^@test ".* # skip' "$BATS_TEST_DIRNAME"/*.bats || true)"
    [ -z "$odd" ] || { echo "a test name holds ' # skip':"; echo "$odd"; return 1; }
    # Positive control: the pattern does match such a line.
    grep -q -E '^@test ".* # skip' <<<'@test "passes but is named x # skip y" {'
}

@test "expected-skips list: the coverage run uses it too, and sets no count" {
    local coverage="$TEST_REPO_ROOT/scripts/coverage.sh"
    grep -qF -- '-e MANIFEST_CLI_TEST_EXPECTED_SKIPS="${MANIFEST_CLI_TEST_EXPECTED_SKIPS:-tests/containers/expected-skips.tsv}"' "$coverage"
    refute grep -qE -- '-e MANIFEST_CLI_TEST_MAX_SKIPS' "$coverage"
}
