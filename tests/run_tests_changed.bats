#!/usr/bin/env bats

# §5.10 change-aware selection: run-tests.sh --changed. Narrows the run to the
# tests mapped (tests/coverage-map.tsv) to what changed on the branch, always
# unioning the smoke tier, and fails SAFE to the full suite. These assert the
# *resolved plan* via --print-cmd, injecting the changed-path set through
# MANIFEST_CLI_TEST_CHANGED_PATHS so they never depend on the repo's live git
# state. --jobs 1 keeps output serial (no GNU parallel dependency). stdout is the
# bats line; the narrow-vs-full rationale is on stderr (--separate-stderr).
#
# NOTE: not smoke-tagged — this covers the test harness, not a runtime safety
# contract, so it belongs to the full tier only.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

RUN() { "$TEST_REPO_ROOT/scripts/run-tests.sh" "$@"; }

# A representative smoke-tagged file (safety contract) and a non-smoke file, used
# to assert "smoke is always unioned" and "other domains are excluded".
SMOKE_FILE="/safety_gate.bats"
NONSMOKE_FILE="/recipe.bats"

@test "changed: a mapped module change narrows to its tests plus the smoke tier" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="modules/pr/manifest-pr-native.sh" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [[ "$output" == bats\ * ]]
    # the pr module's mapped test is selected...
    [[ "$output" == *"/pr_native_safe_by_default.bats"* ]]
    # ...the smoke tier is unioned in...
    [[ "$output" == *"$SMOKE_FILE"* ]]
    # ...and an unrelated, non-smoke domain is NOT run.
    [[ "$output" != *"$NONSMOKE_FILE"* ]]
    # never the whole tests dir (that would be the full fallback)
    [[ "$output" != "bats $TEST_REPO_ROOT/tests" ]]
}

@test "changed: an unmapped path fails safe to the full suite" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="scripts/manifest-cli.sh" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats $TEST_REPO_ROOT/tests" ]
    [[ "$stderr" == *"fail-safe -> FULL"* ]]
    [[ "$stderr" == *"unmapped path changed: scripts/manifest-cli.sh"* ]]
}

@test "changed: a core-module change fails safe to full" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="modules/core/manifest-yaml.sh" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats $TEST_REPO_ROOT/tests" ]
    [[ "$stderr" == *"core module changed"* ]]
}

@test "changed: a tests/helpers change fails safe to full" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="tests/helpers/setup.bash" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats $TEST_REPO_ROOT/tests" ]
    [[ "$stderr" == *"test helper changed"* ]]
}

@test "changed: editing the coverage map itself fails safe to full" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="tests/coverage-map.tsv" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [ "$output" = "bats $TEST_REPO_ROOT/tests" ]
    [[ "$stderr" == *"coverage map changed"* ]]
}

@test "changed: a docs-only change runs the smoke tier (no module tests)" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="docs/USER_GUIDE.md" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    # smoke present, no mapped/full
    [[ "$output" == *"$SMOKE_FILE"* ]]
    [[ "$output" != *"$NONSMOKE_FILE"* ]]
    [[ "$output" != "bats $TEST_REPO_ROOT/tests" ]]
}

@test "changed: an edited test file runs itself (plus smoke)" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="tests/recipe.bats" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"/recipe.bats"* ]]
    [[ "$output" == *"$SMOKE_FILE"* ]]
    [[ "$output" != "bats $TEST_REPO_ROOT/tests" ]]
}

@test "changed: multiple mapped changes union their test sets" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="modules/pr/manifest-pr-native.sh modules/recipe/manifest-recipe.sh" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"/pr_native_safe_by_default.bats"* ]]  # pr row
    [[ "$output" == *"/recipe.bats"* ]]                     # recipe row
    [[ "$output" == *"/doc_review.bats"* ]]                 # recipe row also maps doc_review
}

@test "changed: no changed paths runs the smoke tier only" {
    # Set-but-empty injection means 'nothing changed' (distinct from unset=use git).
    MANIFEST_CLI_TEST_CHANGED_PATHS="" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SMOKE_FILE"* ]]
    [[ "$output" != *"$NONSMOKE_FILE"* ]]
    [[ "$stderr" == *"no changed paths"* ]]
}

@test "changed: a narrowed run is logged loudly (never silent)" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="modules/pr/manifest-pr-native.sh" \
        run --separate-stderr RUN --changed --jobs 1 --print-cmd
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"selection:"* ]]
    [[ "$stderr" == *"full would run all"* ]]
    [[ "$stderr" == *"run: pr_native_safe_by_default.bats"* ]]
}

@test "changed: combines with --jobs (parallel flag precedes the file list)" {
    if ! command -v parallel >/dev/null 2>&1 || ! parallel --version 2>/dev/null | grep -qi 'GNU parallel'; then
        skip "GNU parallel not installed in this environment"
    fi
    MANIFEST_CLI_TEST_CHANGED_PATHS="modules/pr/manifest-pr-native.sh" \
        run --separate-stderr RUN --changed --jobs 4 --print-cmd
    [ "$status" -eq 0 ]
    [[ "$output" == "bats --jobs 4 "* ]]
    [[ "$output" == *"/pr_native_safe_by_default.bats"* ]]
}

@test "changed: cannot combine with explicit test files (exit 2)" {
    MANIFEST_CLI_TEST_CHANGED_PATHS="modules/pr/manifest-pr-native.sh" \
        run RUN --changed --jobs 1 "$TEST_REPO_ROOT/tests/recipe.bats"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot combine with explicit test files"* ]]
}
