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

# Same theme as the options above: a suite assertion that cannot fail is worse
# than a missing one. `shasum` is a Perl script macOS ships and the Alpine CI
# container does not, so a bare call there exits 127 — and pipefail decides
# whether that is loud or silent:
#
#   with pipefail    status.bats FAILED on every Linux leg since 62adae6
#   without pipefail awk swallowed the 127, the captured sum was EMPTY, and
#                    `[ "$after" = "$before" ]` compared "" to "" and PASSED
#
# The silent form had disabled twenty assertions across the uninstall and
# path-modification tripwires — the ones that exist to prove a decoy file was
# never touched. Proved by mutation 2026-08-21: corrupting the decoy on purpose
# still passed on Alpine and failed on macOS. Route file hashing through
# sha256_of (helpers/setup.bash), which resolves the tool itself.
@test "suite portability: files are hashed via sha256_of, never a bare shasum call" {
    # Only the file-hashing form is flagged: `... | shasum -a 256 | cut` hashes
    # stdin and is already portable where it appears under a `command -v` probe.
    local pat='(shasum|sha256sum)([[:space:]]+-a[[:space:]]+256)?[[:space:]]+"'

    # Positive control. sha256_of's own two branches are the only legitimate
    # hits; if the pattern or the path stops matching, the scan below would
    # report a clean suite forever — the exact failure mode being guarded.
    local control
    control="$(grep -cE "$pat" "$TEST_REPO_ROOT/tests/helpers/setup.bash")"
    [ "$control" -eq 2 ]

    local offenders
    offenders="$(grep -rnE "$pat" "$TEST_REPO_ROOT/tests" \
        | grep -v '/helpers/setup.bash:' || true)"

    if [ -n "$offenders" ]; then
        echo "Bare file-hashing shasum/sha256sum call(s) in the suite:" >&2
        echo "$offenders" >&2
        echo "Use sha256_of \"\$file\" — it resolves shasum or sha256sum per host." >&2
        return 1
    fi
}
