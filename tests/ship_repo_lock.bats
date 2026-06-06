#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the per-repo single-flight lock on `manifest ship repo ... -y`:
# two concurrent applies in the SAME repo (e.g. a human + a CI runner) must not
# race on the VERSION bump / tag creation / push and leave a half-shipped repo.
# The lock REUSES the battle-tested fleet lock primitives (atomic mkdir mutex,
# PID + start-token + same-host liveness, race-safe stale reclaim, TOCTOU grace);
# this suite exercises the repo-specific keying, guard/exemption logic, and the
# preview-never-locks contract. All writes are sandboxed under $HOME.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    # The lock primitives we reuse live in manifest-fleet.sh; the repo-lock
    # helpers live in manifest-ship.sh. Both are sourced into the same process
    # by the real loader (fleet before ship), so we mirror that order here.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
    # Keep contention tests fast: 2 attempts at 0.1s instead of 50.
    export MANIFEST_CLI_FLEET_LOCK_ATTEMPTS=2

    # A throwaway git repo to key the lock on.
    REPO="$SCRATCH/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q . >/dev/null 2>&1
    export REPO
    PROJECT_ROOT="$REPO"
    export PROJECT_ROOT
    # Clear any inherited exemption/marker env so each test starts clean.
    unset MANIFEST_CLI_AUDIT_SOURCE
    unset MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE
    unset MANIFEST_CLI_REPO_LOCK_HELD
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# --- Keying + mechanics -----------------------------------------------------

@test "repo lock: dir lives under the preserved locks/ subdir, repo- prefixed" {
    local dir
    dir="$(_manifest_repo_lock_dir_path)"
    [[ "$dir" == "$(manifest_install_paths_locks_dir)/repo-"*.lock.d ]]
    # locks is in the upgrade-preserved set so a swap can't delete a held lock.
    manifest_install_paths_preserved_subdirs | grep -qx "locks"
}

@test "repo lock: path is stable for the same repo regardless of cwd" {
    local a b
    a="$(_manifest_repo_lock_dir_path)"
    mkdir -p "$SCRATCH/elsewhere"
    b="$(cd "$SCRATCH/elsewhere" && PROJECT_ROOT="$REPO" _manifest_repo_lock_dir_path)"
    [ "$a" = "$b" ]
}

@test "repo lock: distinct repos get distinct lock dirs" {
    local a b
    a="$(_manifest_repo_lock_dir_path)"
    mkdir -p "$SCRATCH/other"
    git -C "$SCRATCH/other" init -q . >/dev/null 2>&1
    b="$(PROJECT_ROOT="$SCRATCH/other" _manifest_repo_lock_dir_path)"
    [ "$a" != "$b" ]
}

# --- Acquire / refusal / reclaim (reusing fleet primitives) -----------------

@test "repo lock: a second apply attempt is refused while the lock is held" {
    local dir
    dir="$(_manifest_repo_lock_dir_path)"
    mkdir -p "$dir"
    # Holder = this live test process -> a same-host live holder must NOT break.
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=%s\n' "$(_fleet_proc_start_token "$$")"
    } > "$dir/holder"
    run _manifest_ship_repo_lock_acquire
    [ "$status" -ne 0 ]
    # The repo-scoped banner + holder + lock path are surfaced.
    echo "$output" | grep -q "Another 'manifest ship repo' is already applying"
    echo "$output" | grep -q "Lock: $dir"
    rm -rf "$dir"
}

@test "repo lock: a stale lock from a dead PID is reclaimed and apply proceeds" {
    local dir
    dir="$(_manifest_repo_lock_dir_path)"
    mkdir -p "$dir"
    # 99999 is almost certainly not a live PID; kill -0 fails -> dead -> reclaim.
    {
        printf 'pid=99999\n'
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=stale-token\n'
    } > "$dir/holder"
    run _manifest_ship_repo_lock_acquire
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Reclaimed a stale"
    grep -q "^pid=$$\$" "$dir/holder"
    _fleet_lock_release "$dir"
}

@test "repo lock: a reused PID (alive pid, mismatched start token) is reclaimed" {
    local dir
    dir="$(_manifest_repo_lock_dir_path)"
    mkdir -p "$dir"
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=DEFINITELY-NOT-OUR-START-TOKEN\n'
    } > "$dir/holder"
    run _manifest_ship_repo_lock_acquire
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Reclaimed a stale"
    _fleet_lock_release "$dir"
}

@test "repo lock: acquire (in-shell) sets the lock dir + exported marker" {
    # Must run in the caller's shell (no command-sub) so the mkdir lock, the
    # _MANIFEST_CLI_SHIP_REPO_LOCK_DIR handoff, and the exported marker all persist.
    _manifest_ship_repo_lock_acquire
    [ -n "$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR" ]
    [ -d "$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR" ]
    [ -r "$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR/holder" ]
    grep -q "^pid=$$\$" "$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR/holder"
    [ -n "$MANIFEST_CLI_REPO_LOCK_HELD" ]
    _fleet_lock_release "$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR"
}

@test "repo lock: a DIFFERENT git root acquires successfully while this one is held" {
    # Locks are per-repo: holding REPO's lock must NOT block a second repo. Take
    # REPO's lock for real, then acquire another repo's lock from a DISTINCT live
    # process (a subshell with its own PID) — it must succeed, proving isolation.
    _manifest_ship_repo_lock_acquire
    local held="$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR"
    [ -d "$held" ]

    mkdir -p "$SCRATCH/other"
    git -C "$SCRATCH/other" init -q . >/dev/null 2>&1
    # Subshell = distinct $$; clear the inherited same-process marker so the
    # defense-in-depth guard doesn't short-circuit, and re-point PROJECT_ROOT.
    run bash -c '
        unset MANIFEST_CLI_REPO_LOCK_HELD
        source "$1/modules/system/manifest-install-paths.sh"
        source "$1/modules/git/manifest-git.sh"
        source "$1/modules/fleet/manifest-fleet.sh"
        source "$1/modules/core/manifest-ship.sh"
        PROJECT_ROOT="$2"
        _manifest_ship_repo_lock_acquire
        [ -d "$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR" ] || exit 1
        _fleet_lock_release "$_MANIFEST_CLI_SHIP_REPO_LOCK_DIR"
    ' _ "$TEST_REPO_ROOT" "$SCRATCH/other"
    [ "$status" -eq 0 ]

    # REPO's own lock is untouched by the other repo's acquire/release.
    [ -d "$held" ]
    _fleet_lock_release "$held"
}

# --- Release on completion AND on failure (RETURN-trap behavior) ------------
# The apply path wires `trap '_fleet_lock_release ...' RETURN` so the lock is
# freed whether the workflow returns 0 or non-zero. These tests reproduce that
# exact wiring around a stub workflow and assert the lock dir is gone afterward,
# rather than only grepping that the trap line exists.

@test "repo lock: released on NORMAL completion (RETURN trap fires on success)" {
    # The lock path is deterministic for this repo, so we can assert removal
    # without smuggling a value out of the (sub)function.
    local expected
    expected="$(_manifest_repo_lock_dir_path)"
    _apply_like_success() {
        _manifest_ship_repo_lock_acquire || return 1
        local repo_lock="${_MANIFEST_CLI_SHIP_REPO_LOCK_DIR:-}"
        # shellcheck disable=SC2064
        trap "_fleet_lock_release '${repo_lock:-}'" RETURN
        [ -d "$repo_lock" ]          # held during the "workflow"
        return 0                     # workflow succeeds
    }
    _apply_like_success
    [ ! -d "$expected" ]             # RETURN trap released it
}

@test "repo lock: released on FAILURE (lock dir gone after a workflow that fails mid-run)" {
    local expected
    expected="$(_manifest_repo_lock_dir_path)"
    _apply_like_failure() {
        _manifest_ship_repo_lock_acquire || return 1
        local repo_lock="${_MANIFEST_CLI_SHIP_REPO_LOCK_DIR:-}"
        # shellcheck disable=SC2064
        trap "_fleet_lock_release '${repo_lock:-}'" RETURN
        [ -d "$repo_lock" ]          # held mid-"workflow"
        return 7                     # workflow fails partway through
    }
    # Call directly (not via `run`) so the function's own RETURN trap fires in
    # THIS shell — `run`'s subshell would tear down and mask the release path.
    local rc=0
    _apply_like_failure || rc=$?
    [ "$rc" -eq 7 ]                  # failure status is preserved
    # The RETURN trap ran on the failure path: the lock dir is gone, so a
    # subsequent ship is not blocked by a half-shipped run's orphaned lock.
    [ ! -d "$expected" ]
}

# --- Guard / exemption logic (the important ones) ---------------------------
# Assert the guard helper's decision directly: robust + cannot hang.

@test "guard: lock is taken by default (no exemptions set)" {
    run _manifest_ship_repo_should_lock
    [ "$status" -eq 0 ]
}

@test "guard EXEMPTION: cli-fleet child SKIPS acquisition even with a lock dir present" {
    # Pre-create a live-holder lock dir; a fleet child must NOT even try to take
    # it (it already holds the fleet lock + runs members sequentially).
    local dir
    dir="$(_manifest_repo_lock_dir_path)"
    mkdir -p "$dir"
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=%s\n' "$(_fleet_proc_start_token "$$")"
    } > "$dir/holder"
    # Guard decision: skip.
    MANIFEST_CLI_AUDIT_SOURCE=cli-fleet run _manifest_ship_repo_should_lock
    [ "$status" -ne 0 ]
    # And the acquire wrapper returns success without refusing the lock.
    MANIFEST_CLI_AUDIT_SOURCE=cli-fleet run _manifest_ship_repo_lock_acquire
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "already applying"
    rm -rf "$dir"
}

@test "guard EXEMPTION: follow-up patch SKIPS acquisition" {
    local dir
    dir="$(_manifest_repo_lock_dir_path)"
    mkdir -p "$dir"
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=%s\n' "$(_fleet_proc_start_token "$$")"
    } > "$dir/holder"
    MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE=1 run _manifest_ship_repo_should_lock
    [ "$status" -ne 0 ]
    MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE=1 run _manifest_ship_repo_lock_acquire
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "already applying"
    rm -rf "$dir"
}

@test "guard defense-in-depth: same-root MANIFEST_CLI_REPO_LOCK_HELD SKIPS" {
    local root
    root="$(_manifest_repo_lock_git_root)"
    MANIFEST_CLI_REPO_LOCK_HELD="$root" run _manifest_ship_repo_should_lock
    [ "$status" -ne 0 ]   # same root already held -> skip
}

@test "guard defense-in-depth: a DIFFERENT root's marker does NOT skip" {
    MANIFEST_CLI_REPO_LOCK_HELD="/some/other/git/root" run _manifest_ship_repo_should_lock
    [ "$status" -eq 0 ]   # different root -> still lock
}

# --- Wiring guards ----------------------------------------------------------
# Behavioral coverage above proves the mechanism; these guard that it stays
# wired into the apply paths (and only the apply paths) and is released on exit.

@test "repo lock: acquired ONLY on apply, never on preview" {
    local f="$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
    local acquire_line preview_return_line
    acquire_line=$(grep -n '_manifest_ship_repo_lock_acquire' "$f" \
        | grep -v '_manifest_ship_repo_lock_acquire()' | tail -1 | cut -d: -f1)
    # The preview early-return guard (writes nothing -> needs no lock).
    preview_return_line=$(grep -n 'execution_mode.*==.*preview' "$f" | head -1 | cut -d: -f1)
    [ -n "$acquire_line" ]
    [ -n "$preview_return_line" ]
    # Acquisition is wired AFTER the preview early-return, so preview never locks.
    [ "$acquire_line" -gt "$preview_return_line" ]
}

@test "repo lock: wired into ship repo apply with acquire + RETURN/INT/TERM release" {
    local f="$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
    grep -q '_manifest_ship_repo_lock_acquire' "$f"
    grep -q "_fleet_lock_release .* RETURN" "$f"
    grep -q "kill -INT \$\$' INT" "$f"
    grep -q "kill -TERM \$\$' TERM" "$f"
}

@test "repo lock: wired into ship repo resume apply with acquire + traps" {
    local f="$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    grep -q '_manifest_ship_repo_lock_acquire' "$f"
    grep -q "_fleet_lock_release .* RETURN" "$f"
    grep -q "kill -INT \$\$' INT" "$f"
    grep -q "kill -TERM \$\$' TERM" "$f"
}
