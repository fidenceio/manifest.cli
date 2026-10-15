#!/usr/bin/env bats
#
# Repo init connects by default. Explicit --no-connect keeps scaffold-only
# behavior; -y is always required before GitHub creation or remote reads.
# Real local bare remotes and an observed gh stub distinguish creation from
# merely printing a plan. Existing release checks are preserved and executed.

load 'helpers/setup'

setup() {
    export MANIFEST_CLI_RELEASE_GATE=local-tests
    export MANIFEST_CLI_DOCS_FOLDER=docs
    # Source the full path the connect phase actually runs: it calls
    # ensure_env_files (manifest-init.sh) and sync_repository
    # (manifest-git.sh). Loading them here rather than per-test is not
    # tidiness — without them the phase still reaches `gh repo create` and
    # then dies 127 on its LAST line, so a test can assert the gh call
    # correctly while the run underneath it was half-broken.
    load_modules core/manifest-init.sh git/manifest-git.sh core/manifest-init-connect.sh core/manifest-config.sh workflow/manifest-orchestrator.sh
    SCRATCH="$(mk_scratch)"
    git init -q --bare "$SCRATCH/origin.git"
    export MANIFEST_CLI_GH_STUB_REMOTE_URL="$SCRATCH/origin.git"
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
    git init -q -b main "$dir"
    mkdir -p "$dir/scripts"
    printf '#!/bin/sh\ntest -f VERSION\n' > "$dir/scripts/run-tests.sh"
    chmod +x "$dir/scripts/run-tests.sh"
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


# -----------------------------------------------------------------------------
# Contract 1 — the fold's safety claim, with its own positive control
# -----------------------------------------------------------------------------

@test "init repo --no-connect -y invokes gh ZERO times" {
    gh_stub_install
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo --no-connect -y
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

@test "init repo preview names the connect phase as ON by default" {
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "connect phase:   ON"
    echo "$output" | grep -q "private"
}

@test "init repo --connect preview names the connect phase as ON and replays the default" {
    _mk_no_origin_repo "$SCRATCH/work"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_repo --connect
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "connect phase:   ON"
    # The replay hint must round-trip the flag, or following it drops the phase.
    echo "$output" | grep -q "manifest init repo -y"
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
# Retired routes are covered in command_tree.bats
# -----------------------------------------------------------------------------
