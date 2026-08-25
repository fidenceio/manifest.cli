#!/usr/bin/env bats
# TRACKER §43 — git.default_branch reached git in ARGUMENT position.
#
# git_retry took its command as one STRING and re-split it on spaces, so any
# value interpolated into that string could introduce further arguments. The
# comments at the split site said "prevent injection" and were true for SHELL
# injection and false for ARGUMENT injection, which is why the site read as
# already-hardened and nobody looked.
#
# git has arguments that run programs. Both of these executed a script:
#     git.default_branch: "--upload-pack=/path/probe.sh"    (pull side)
#     git.default_branch: "--exec=/path/probe.sh"           (push side)
# and this deleted a remote tag, transport-independently:
#     git.default_branch: "main --delete"
#
# THE ORACLE IS A MARKER FILE, NEVER A LOG LINE. A refusal message can be
# printed by code that then runs the command anyway; only the absence of the
# marker proves the program did not run. Same for the tag: read the remote's
# ref list, not the CLI's own report of what it did.
#
# TWO INDEPENDENT HALVES ARE UNDER TEST, and neither subsumes the other:
#   argv           kills "main --delete" -- it collapses to one literal refspec
#                  that fails to match -- but NOT "--upload-pack=", which git
#                  parses as an option even in argument position.
#   leading-dash   kills "--upload-pack=" / "--exec=" before git is invoked,
#                  and must run BEFORE `git check-ref-format`, which would
#                  itself consume the leading dash as one of its own flags.
# A fix carrying only one half leaves a live vector. The mutation tests below
# exist to prove each half is load-bearing.

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh"
    SCRATCH="$(mk_scratch)"

    PROBE="$SCRATCH/PROBE_FIRED"
    PROBE_SH="$SCRATCH/probe.sh"
    printf '#!/usr/bin/env bash\ntouch "%s"\nexit 1\n' "$PROBE" > "$PROBE_SH"
    chmod +x "$PROBE_SH"

    # A bare repo reachable by PATH, not URL: --upload-pack/--exec run LOCALLY
    # for a local-path remote, which is what makes the probe observable here.
    ORIGIN="$SCRATCH/origin.git"
    git init -q --bare "$ORIGIN"

    REPO="$SCRATCH/repo"
    git init -q "$REPO"
    git -C "$REPO" config user.email t@example.invalid
    git -C "$REPO" config user.name t
    git -C "$REPO" checkout -q -b main
    echo seed > "$REPO/f.txt"
    git -C "$REPO" add f.txt
    git -C "$REPO" commit -q -m seed
    git -C "$REPO" remote add origin "$ORIGIN"
    git -C "$REPO" push -q origin main
    git -C "$REPO" tag v1.0.1
    git -C "$REPO" push -q origin v1.0.1

    export MANIFEST_CLI_PROJECT_ROOT="$REPO"
    export MANIFEST_CLI_GIT_RETRIES=1
    export MANIFEST_CLI_GIT_TIMEOUT=20
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- positive controls ------------------------------------------------------
# Without these, "no marker appeared" is indistinguishable from a fixture that
# never invoked git at all -- and git_retry refuses outright when no timeout
# command exists, which would make every probe test below pass vacuously.

@test "positive control: the fixture can actually run git through git_retry" {
    command -v gtimeout >/dev/null 2>&1 || command -v timeout >/dev/null 2>&1 \
        || skip "no timeout command; git_retry cannot run and probes would be vacuous"
    cd "$REPO"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=main
    run sync_repository
    [ "$status" -eq 0 ]
}

@test "positive control: the probe script fires when something does run it" {
    [ ! -e "$PROBE" ]
    "$PROBE_SH" || true
    [ -e "$PROBE" ]
}

@test "positive control: the remote carries the tag before any delete attempt" {
    run git -C "$ORIGIN" tag -l v1.0.1
    [ "$status" -eq 0 ]
    [ "$output" = "v1.0.1" ]
}

# --- the vectors ------------------------------------------------------------

@test "sync: --upload-pack= in git.default_branch does not execute a program" {
    cd "$REPO"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="--upload-pack=$PROBE_SH"
    run sync_repository
    [ ! -e "$PROBE" ]
    [ "$status" -ne 0 ]
}

@test "push: --exec= in git.default_branch does not execute a program" {
    cd "$REPO"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="--exec=$PROBE_SH"
    run push_changes v1.0.1
    [ ! -e "$PROBE" ]
}

@test "push: 'main --delete' does not delete the remote tag" {
    cd "$REPO"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main --delete"
    run push_changes v1.0.1
    # Read the remote, not the CLI's account of what it did.
    run git -C "$ORIGIN" tag -l v1.0.1
    [ "$output" = "v1.0.1" ]
}

@test "release-branch assert: an unsafe value is refused, not echoed as advice" {
    cd "$REPO"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="--force"
    run manifest_assert_release_branch "$REPO"
    [ "$status" -ne 0 ]
    # It must not hand the user `git checkout --force` as remediation.
    # Written as an explicit if/fail, NOT as `! echo ... | grep`: bash exempts a
    # `!`-negated command from errexit mid-test, which is how 114 assertions in
    # this suite were once unable to fail at all (TRACKER §6, instance 3).
    if echo "$output" | grep -q 'checkout --force'; then
        fail "refusal offered 'git checkout --force' as remediation: $output"
    fi
}

# --- the refusal contract ---------------------------------------------------

@test "the refusal names the key and says why, for each rejected shape" {
    for bad in "--upload-pack=/tmp/x" "--exec=/tmp/x" "main --delete" "-x" ""; do
        run manifest_git_assert_safe_ref_name "$bad" "git.default_branch"
        [ "$status" -ne 0 ]
        echo "$output" | grep -q 'git.default_branch' \
            || fail "refusal for [$bad] does not name the key: $output"
    done
}

@test "ordinary branch names are still accepted" {
    for good in main master develop feature/x release-1.2 v2; do
        run manifest_git_assert_safe_ref_name "$good" "git.default_branch"
        [ "$status" -eq 0 ] || fail "rejected a legitimate branch name: $good"
    done
}

# --- isolating the argv half -------------------------------------------------
# The two halves overlap for a hostile git.default_branch: check-ref-format
# happens to reject a leading-dash value too (git errors on the unknown flag),
# so disabling either one alone still leaves the vectors above covered, and a
# mutation of either passes. That redundancy is fine as defence in depth but it
# makes those tests blind to which half is doing the work.
#
# argv is load-bearing for a case the ref-name guard does NOT cover: $remote and
# $tag_name reach the same command and are not ref-name validated. $tag_name is
# config-derived via git.tag_prefix, so this is the same class, not a synthetic.
@test "git_retry passes each argument through as one word, unsplit" {
    cd "$REPO"
    # `git rev-parse --sq-quote` echoes its arguments shell-quoted, so this reads
    # the ACTUAL argv git received rather than trusting the caller's intent.
    run git_retry "probe" git rev-parse --sq-quote "one two"
    [ "$status" -eq 0 ]
    # argv:  one argument  -> 'one two'
    # split: two arguments -> 'one' 'two'
    echo "$output" | grep -q "'one two'" \
        || fail "argument was re-split; git received: $output"
}

@test "git_retry does not let a multi-word tag name introduce an option" {
    cd "$REPO"
    run git_retry "probe" git rev-parse --sq-quote "v1.0.1 --delete"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "'v1.0.1 --delete'" \
        || fail "a multi-word tag name was split into separate arguments: $output"
}

@test "git_retry still refuses a non-git command" {
    run git_retry "probe" rm -rf /
    [ "$status" -ne 0 ]
    echo "$output" | grep -q 'Only git commands are allowed'
}

@test "git_retry still refuses an empty command" {
    run git_retry "probe"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q 'No command provided'
}
