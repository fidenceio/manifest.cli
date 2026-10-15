#!/usr/bin/env bats

# Execute the workflow's actual planning script. These guards catch loss of
# a required platform without replacing the real native macOS suite.
load 'helpers/setup'

_run_ci_plan() {
    local event="$1" ref="$2" script needle
    script="$(yq -r '.jobs.plan.steps[0].run' "$TEST_REPO_ROOT/.github/workflows/test.yml")"
    needle='${{ github.event_name }}'
    script="${script//"$needle"/"$event"}"
    needle='${{ github.ref }}'
    script="${script//"$needle"/"$ref"}"
    printf '%s\n' "$script" > "$BATS_TEST_TMPDIR/ci-plan.sh"
    : > "$BATS_TEST_TMPDIR/ci-output"
    GITHUB_OUTPUT="$BATS_TEST_TMPDIR/ci-output" bash "$BATS_TEST_TMPDIR/ci-plan.sh"
}

@test "CI plan: every merge and release confidence event runs full uncached Linux and macOS suites" {
    local event
    for event in pull_request schedule workflow_dispatch push unknown; do
        run _run_ci_plan "$event" refs/heads/main
        [ "$status" -eq 0 ]
        grep -Fx 'tier=full' "$BATS_TEST_TMPDIR/ci-output"
        grep -Fx 'changed=false' "$BATS_TEST_TMPDIR/ci-output"
        grep -Fx 'no_cache=true' "$BATS_TEST_TMPDIR/ci-output"
        grep -Fx 'os=["ubuntu-latest","macos-latest"]' "$BATS_TEST_TMPDIR/ci-output"
    done
}

@test "CI plan control: feature pushes retain the Linux change-aware smoke lane" {
    run _run_ci_plan push refs/heads/example
    [ "$status" -eq 0 ]
    grep -Fx 'tier=smoke' "$BATS_TEST_TMPDIR/ci-output"
    grep -Fx 'changed=true' "$BATS_TEST_TMPDIR/ci-output"
    grep -Fx 'no_cache=false' "$BATS_TEST_TMPDIR/ci-output"
    grep -Fx 'os=["ubuntu-latest"]' "$BATS_TEST_TMPDIR/ci-output"
}
