#!/usr/bin/env bats
# bats file_tags=smoke
# These test report validation, never substitute invented hits for a real run.
load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    mkdir -p "$SCRATCH/modules" "$SCRATCH/scripts"
    for path in modules/example.sh scripts/manifest-cli.sh scripts/manifest-cli-wrapper.sh scripts/migrate-user-config.sh; do
        printf '#!/bin/bash\necho first\necho second\n' > "$SCRATCH/$path"
    done
    report="$SCRATCH/coverage.json"
    jq -n --arg root "$SCRATCH" '{
        percent_covered: "100.00", covered_lines: 8, total_lines: 8,
        files: (["modules/example.sh", "scripts/manifest-cli.sh", "scripts/manifest-cli-wrapper.sh", "scripts/migrate-user-config.sh"] |
            map({file: ($root + "/" + .), covered_lines: "2", total_lines: "2"}))
    }' > "$report"
}
teardown() { rm -rf "$SCRATCH"; }
check_report() { run bash "$TEST_REPO_ROOT/scripts/check-coverage.sh" "$report" "$SCRATCH" "$@"; }
mutate_report() { jq "$1" "$report" > "$report.tmp"; mv "$report.tmp" "$report"; }

@test "coverage: complete inventory and exact full line coverage pass" {
    check_report
    [ "$status" -eq 0 ]
    [[ "$output" == *"100.00% (8/8 executable lines; 4/4 files)"* ]]
}

@test "coverage: a never-loaded runtime module cannot disappear from a 100 percent headline" {
    mkdir -p "$SCRATCH/modules/nested"
    printf '#!/bin/bash\necho never-loaded\n' > "$SCRATCH/modules/nested/missing.sh"
    check_report
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing runtime files"* ]]
    [[ "$output" == *"nested/missing.sh"* ]]
    # A zero-hit inventory entry establishes the file without pretending it ran.
    mutate_report '.total_lines += 1 | .files += [{file: "'"$SCRATCH"'/modules/nested/missing.sh", covered_lines: 0, total_lines: 1}]'
    check_report
    [ "$status" -ne 0 ]
    [[ "$output" == *"1 executable lines remain uncovered"* ]]
}

@test "coverage: the rounded percentage never overrides uncovered executable lines" {
    mutate_report '.covered_lines = 7 | .files[0].covered_lines = 1'
    check_report
    [ "$status" -ne 0 ]
    [[ "$output" == *"87.50%"* ]]
    [[ "$output" == *"1 executable lines remain uncovered"* ]]
    check_report 87.5
    [ "$status" -eq 0 ]
}

@test "coverage: empty denominators and missing reports fail closed" {
    mutate_report '.covered_lines = 0 | .total_lines = 0 | .files |= map(.covered_lines=0 | .total_lines=0)'
    check_report
    [ "$status" -ne 0 ]
    [[ "$output" == *"internally inconsistent"* ]]
    rm "$report"
    check_report
    [ "$status" -ne 0 ]
}

@test "coverage: malformed counts and inconsistent aggregates cannot pass" {
    mutate_report '.files[0].covered_lines = "not-a-count"'
    check_report
    [ "$status" -ne 0 ]
    mutate_report '.files[0].covered_lines = 2 | .covered_lines = 99'
    check_report
    [ "$status" -ne 0 ]
    mutate_report '.covered_lines = 8 | .files[0].covered_lines = 3'
    check_report
    [ "$status" -ne 0 ]
}

@test "coverage: duplicate files and out-of-scope files cannot inflate the denominator" {
    mutate_report '.files[1].file = .files[0].file'
    check_report
    [ "$status" -ne 0 ]
    mutate_report '.files[1].file = "'"$SCRATCH"'/tests/not-runtime.bats"'
    check_report
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected files in the denominator"* ]]
}

@test "coverage: thresholds must be explicit valid percentages" {
    for invalid in -1 101 nan '100; echo forged'; do
        check_report "$invalid"
        [ "$status" -eq 2 ]
    done
}

@test "coverage: the gap report identifies the actual files without excluding them" {
    mutate_report '.covered_lines = 7 | .files[0].covered_lines = 1'
    export MANIFEST_CLI_COVERAGE_GAPS_FILE="$SCRATCH/gaps.tsv"
    check_report
    [ "$status" -ne 0 ]
    [ "$(cat "$SCRATCH/gaps.tsv")" = "$SCRATCH/modules/example.sh"$'\t1\t2\t1' ]
}
