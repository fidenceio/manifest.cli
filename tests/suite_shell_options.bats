#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Guards the guard: the suite must exercise module code under the SAME shell
# options the CLI ships with. manifest-core.sh:7 sets `set -eo pipefail` at top
# level, but that is the entrypoint module and the suite loads leaf modules
# directly, so load_modules has to set the options itself.
#
# What was actually broken (measured 2026-08-18): bats already runs test bodies
# under errexit, so `-e` was covered by accident. `pipefail` was NOT set, so a
# module pipeline that failed in an early element and succeeded in the last one
# returned 0 here while aborting in production.
#
# Without these assertions the omission is invisible — every test still passed,
# which is exactly how it survived. Test 2 is the one that was failing before
# the fix; test 1 documents the part bats gives us, so that if a future bats
# version stops providing it we find out here rather than in a release.

load 'helpers/setup'

setup() {
    load_modules
}

@test "shell options: errexit is active in the test body after load_modules" {
    [[ -o errexit ]]
}

@test "shell options: pipefail is active in the test body after load_modules" {
    [[ -o pipefail ]]
}

@test "shell options: errexit actually aborts on a bare failing command" {
    # Proves the option is load-bearing, not merely reported as set. Run in a
    # child so this test can observe the abort instead of suffering it: the
    # marker must NOT be reached.
    run bash -c 'set -eo pipefail; false; echo MARKER-REACHED'
    [ "$status" -ne 0 ]
    refute grep -q 'MARKER-REACHED' <<<"$output"
}

@test "shell options: pipefail actually propagates a mid-pipeline failure" {
    run bash -c 'set -eo pipefail; false | cat'
    [ "$status" -ne 0 ]
}

@test "shell options: the options the suite sets match the ones manifest-core ships" {
    # If manifest-core.sh's own `set` line changes, this test is the thing that
    # notices the suite has drifted away from production semantics.
    grep -qE '^set -eo pipefail$' "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    grep -qE '^\s*set -eo pipefail$' "$TEST_REPO_ROOT/tests/helpers/setup.bash"
}
