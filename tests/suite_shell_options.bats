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

# The two guards below ban one mechanism with two spellings. load_modules sets
# `set -eo pipefail`; when a pipeline's consumer exits early (grep -q at its
# first match, head after N lines) the still-writing EXTERNAL producer takes
# SIGPIPE and the pipeline reports status 141, which errexit turns into a test
# failure — intermittently, a different test each run. That intermittency is
# the tell: both incidents passed locally and failed only CI's Linux leg.
#
# Both scans skip full-line comments (a comment cannot SIGPIPE, and two prior
# incident write-ups in the suite quote the banned shapes verbatim). Their
# regex fixtures are assembled at runtime from ${pipe} so this file can never
# trip its own scan, and each scan asserts it visited a believable number of
# files so a broken glob cannot pass vacuously (the positive-control pattern
# from help_dispatch_parity.bats).

# Incident (2026-08-21, and the v59.3.0 push): _first_line in
# homebrew_tap_trust.bats and ship_pretag_reentrancy.bats:106 each fed a
# streaming grep into head; head closed the pipe after one line and the Linux
# leg failed with 141 while macOS passed. Both were fixed with grep -m1, which
# stops reading without killing a producer. head as a pipeline consumer is
# banned outright — not just behind external producers — because every safe
# instance has a cheaper spelling, so per-site safety analysis is review
# burden with no payoff:
#   first grep hit only   ->  grep -m1 pat file
#   first line of "$var"  ->  "${var%%$'\n'*}"
#   first line of a file  ->  "$(head -1 file)"   (no pipe, no SIGPIPE)
@test "suite portability: no pipeline feeds head — use grep -m1 or capture-and-slice" {
    local pat='\|[[:space:]]*head([^[:alnum:]_./-]|$)'

    # Positive controls: the regex still recognizes the banned shape, ignores
    # the sanctioned replacement, and the glob still finds the suite.
    local pipe='|'
    grep -qE "$pat" <<<"git tag --list ${pipe} head -1"
    refute grep -qE "$pat" <<<"grep -m1 needle file.txt"
    local files=("$TEST_REPO_ROOT"/tests/*.bats)
    [ "${#files[@]}" -gt 50 ]

    local offenders
    offenders="$(grep -nE "$pat" "${files[@]}" \
        | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"

    if [ -n "$offenders" ]; then
        echo "Pipeline(s) feeding head in the suite:" >&2
        echo "$offenders" >&2
        echo "Use grep -m1, or capture whole and slice: \"\${v%%\$'\\n'*}\"." >&2
        return 1
    fi
}

# Incident (measured 2026-08-19): env_scaffold.bats fed yq into grep -q and
# failed 1 run in 8; 14 external-producer sites were converted that day to
# capture-then-match, and 0 failures in 15 runs followed:
#     v="$(producer ...)"        # producer status stays observable
#     grep -q needle <<<"$v"
# Always two lines — folding into one herestring around a command substitution
# discards the producer's exit status.
#
# Design: a denylist of the external producers observed in this suite, not a
# parser. Builtin producers are SAFE — echo/printf make one small write that
# fits the pipe buffer, so grep's early exit cannot SIGPIPE them — and ~646
# such pipelines exist here; flagging by consumer alone would drown the suite
# in rewrites carrying zero flake risk. Stated limits: (1) line-based — a
# denylisted word anywhere before the pipe on the same line trips it, even
# quoted as data; rewrite to capture-then-match either way. (2) a NEW external
# producer, or a shell-function producer, is invisible until listed — when one
# bites, add it beside its incident. `head` must stay FIRST in the alternation
# so this pattern's own text never contains a pipe character directly before
# the word head, which the guard above scans for.
@test "suite portability: no external producer is piped into grep -q — capture, then match" {
    local pat='(^|[^[:alnum:]_./-])(head|git|gh|yq|jq|find|cat|sed|awk|curl|ls|tail|tr|cut|parallel)[[:space:]][^|]*\|[[:space:]]*grep[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*-[[:alnum:]]*q'

    # Positive controls: the regex flags an external producer anywhere in the
    # pipeline, and does NOT flag the builtin-producer form the suite uses
    # hundreds of times.
    local pipe='|'
    grep -qE "$pat" <<<"yq e '.k' cfg.yaml ${pipe} grep -q v"
    grep -qE "$pat" <<<"echo x ${pipe} sed s/x/y/ ${pipe} grep -q y"
    refute grep -qE "$pat" <<<"echo \"\$x\" ${pipe} grep -q needle"
    local files=("$TEST_REPO_ROOT"/tests/*.bats)
    [ "${#files[@]}" -gt 50 ]

    local offenders
    offenders="$(grep -nE "$pat" "${files[@]}" \
        | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"

    if [ -n "$offenders" ]; then
        echo "External producer(s) piped into grep -q in the suite:" >&2
        echo "$offenders" >&2
        echo "Capture first, then match on a second line:" >&2
        echo "    v=\"\$(producer ...)\"" >&2
        echo "    grep -q needle <<<\"\$v\"" >&2
        return 1
    fi
}
