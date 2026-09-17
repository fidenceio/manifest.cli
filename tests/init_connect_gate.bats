#!/usr/bin/env bats
#
# The connect phase of `manifest init` (TRACKER §11).
#
# `prep` folded into `init` as an opt-in connect phase. Two contracts fall out
# of that, and the full suite was green (2074 tests) while BOTH were broken or
# unguarded — which is why these assert `gh` invocations through a PATH stub
# rather than reading log lines:
#
#   1. `init <scope> -y` WITHOUT --connect makes no network call at all. This is
#      the load-bearing safety claim of the fold and of the help text. Nothing
#      asserted it before; `display_help` simply said so, and said so wrongly
#      for two releases (it claimed init "never touches the network" while
#      --create-repo-public published a repository).
#
#   2. `init repo --create-repo-* -y` DOES reach `gh repo create`. Folding
#      routed this through the connect phase's apply gate, whose
#      origin_required defaults to true — and the flag exists precisely for a
#      repo with no origin. The gate refused before the create call, so the flag
#      had no state in which it worked. Measured A/B with a stubbed gh:
#      pre-fold 2 invocations, post-fold 0, after the fix 2.
#
# tests/create_repo.bats covers --create-repo-* only under --dry-run on the repo
# scope (its apply-path coverage is the fleet scope), which is the hole this
# file fills.

load 'helpers/setup'

setup() {
    # Source the full path the connect phase actually runs: it calls
    # ensure_env_files (manifest-init.sh) and sync_repository
    # (manifest-git.sh). Loading them here rather than per-test is not
    # tidiness — without them the phase still reaches `gh repo create` and
    # then dies 127 on its LAST line, so a test can assert the gh call
    # correctly while the run underneath it was half-broken.
    load_modules core/manifest-init.sh git/manifest-git.sh core/manifest-prep.sh
    SCRATCH="$(mk_scratch)"
    # §9.2: keep _manifest_gh_repo_create's rate-limit state file inside the
    # scratch dir, never the developer's real HOME (create_repo.bats pattern).
    manifest_install_paths_global_state_dir() { echo "$SCRATCH/state"; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset _MANIFEST_GH_VALIDATED_AT MANIFEST_CLI_GH_VALIDATION_TTL
    unset MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_GH_STUB_EXIT MANIFEST_CLI_GH_STUB_AUTH_EXIT
    unset MANIFEST_CLI_GH_STUB_STDOUT MANIFEST_CLI_GH_STUB_STDERR
    unset MANIFEST_CLI_GH_STUB_ADD_REMOTE MANIFEST_CLI_GITHUB_OWNER
    unset _MANIFEST_CLI_INIT_CONNECT_NESTED _MANIFEST_CLI_INIT_CONNECT_ALIAS
}

# A git repo on a named branch with no origin — the state --create-repo-* is for.
_mk_no_origin_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git init -q "$dir"
    git -C "$dir" commit -q --allow-empty -m init
    # Named branch, no origin: the apply gate's "ambiguous target" test turns on
    # exactly these two facts.
    git -C "$dir" symbolic-ref -q HEAD >/dev/null
    run git -C "$dir" remote get-url origin
    [ "$status" -ne 0 ]
}

# `grep -c` PRINTS 0 and EXITS 1 on no-match, so the obvious
# `grep -c … || echo 0` emits "0\n0" and every downstream `[ … -ge 1 ]` dies
# with "integer expression expected" (rc 2) instead of failing cleanly. Assign
# first, then correct the exit status, so a real zero reads as a zero.
_gh_create_calls() {
    local n
    n="$(grep -c $'repo\tcreate' "$MANIFEST_CLI_GH_STUB_LOG" 2>/dev/null)" || n=0
    printf '%s' "${n:-0}"
}

# -----------------------------------------------------------------------------
# Contract 2 — the regression this file exists for
# -----------------------------------------------------------------------------

@test "init repo --create-repo-private -y reaches gh repo create on a repo with no origin" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true
    export MANIFEST_CLI_GITHUB_OWNER=testowner
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo --create-repo-private -y
    [ "$status" -eq 0 ]

    # The observation that matters: gh was actually invoked. Asserting on
    # output text would have passed against the broken tree, because the
    # refusal is also printed text.
    [ "$(_gh_create_calls)" -ge 1 ]
    grep -q -- "--private" "$MANIFEST_CLI_GH_STUB_LOG"
    grep -q -- "testowner/work" "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "init repo --create-repo-public -y reaches gh repo create too (the publishing flag)" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true
    export MANIFEST_CLI_GITHUB_OWNER=testowner
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo --create-repo-public -y
    [ "$status" -eq 0 ]

    [ "$(_gh_create_calls)" -ge 1 ]
    grep -q -- "--public" "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "the deprecated prep repo spelling reaches gh repo create identically" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true
    export MANIFEST_CLI_GITHUB_OWNER=testowner
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_prep_repo --create-repo-private -y
    [ "$status" -eq 0 ]

    [ "$(_gh_create_calls)" -ge 1 ]
}

# -----------------------------------------------------------------------------
# Contract 1 — the fold's safety claim, with its own positive control
# -----------------------------------------------------------------------------

@test "init repo -y without --connect invokes gh ZERO times" {
    gh_stub_install
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo -y
    [ "$status" -eq 0 ]

    # An empty log is only meaningful if this harness CAN record a call. The
    # control is the next test: same stub, same repo, --create-repo-private,
    # count >= 1. Without it, a broken stub path would satisfy this assertion
    # exactly as well as correct behaviour (§12b).
    [ "$(wc -l < "$MANIFEST_CLI_GH_STUB_LOG" | tr -d ' ')" -eq 0 ]
}

@test "positive control: the same harness DOES record gh when --connect is asked for" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true
    export MANIFEST_CLI_GITHUB_OWNER=testowner
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo --create-repo-private -y
    [ "$status" -eq 0 ]

    # Same stub, same scratch layout, same install — so a zero in the test
    # above is a fact about init, not about the harness.
    [ "$(wc -l < "$MANIFEST_CLI_GH_STUB_LOG" | tr -d ' ')" -gt 0 ]
}

# -----------------------------------------------------------------------------
# The preview is the consent surface, so the phase has to appear in it
# -----------------------------------------------------------------------------

@test "init repo preview names the connect phase as off by default" {
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "connect phase:   off"
    echo "$output" | grep -q -- "--connect"
}

@test "init repo --connect preview names the connect phase as ON and replays --connect" {
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo --connect
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "connect phase:   ON"
    # The replay hint must round-trip the flag, or following it drops the phase.
    echo "$output" | grep -q "manifest init repo --connect -y"
}

@test "init repo --create-repo-private preview replays the flag, not a bare --connect" {
    export MANIFEST_CLI_GITHUB_OWNER=testowner
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo --create-repo-private
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "connect phase:   ON"
    echo "$output" | grep -q "manifest init repo --create-repo-private -y"
}

# -----------------------------------------------------------------------------
# The deprecated verb still works and says so
# -----------------------------------------------------------------------------

@test "prep repo announces the replacement and still previews" {
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_prep_repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest init repo --connect"
    # The replay hint echoes the spelling the user typed, not the new one —
    # telling someone to re-run a command they did not type is its own defect.
    echo "$output" | grep -q "manifest prep repo -y"
}

@test "manifest sync forwards to the connect phase, not to the deprecated prep verb" {
    # `sync` used to alias `prep repo`. Once prep was itself deprecated that
    # emitted two warnings for one command, the first naming a deprecated verb
    # as the replacement for a deprecated verb.
    run grep -n 'log_deprecated "manifest sync"' "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest init repo --connect"
    echo "$output" | grep -vq "manifest prep repo"
}
