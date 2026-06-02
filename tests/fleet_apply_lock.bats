#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the single-flight fleet lock (CLI tracker 1.7): concurrent
# `manifest ship fleet ... -y` runs in one workspace must not race on shared
# per-member version/tag/formula state. Portable mkdir mutex with PID-reuse-
# and cross-host-safe stale detection. All writes are sandboxed under $HOME.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    export MANIFEST_CLI_FLEET_ROOT="$SCRATCH/work"
    # Keep contention tests fast: 2 attempts at 0.1s instead of 50.
    export MANIFEST_CLI_FLEET_LOCK_ATTEMPTS=2
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

@test "fleet lock: acquire creates the lock + holder, release removes it" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    run _fleet_lock_acquire "$dir"
    [ "$status" -eq 0 ]
    [ -d "$dir" ]
    [ -r "$dir/holder" ]
    grep -q "^pid=$$\$" "$dir/holder"
    _fleet_lock_release "$dir"
    [ ! -d "$dir" ]
}

@test "fleet lock: lock dir lives under the preserved locks/ subdir" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    [[ "$dir" == "$(manifest_install_paths_locks_dir)/fleet-"*.lock.d ]]
    # locks is in the upgrade-preserved set so a swap can't delete a held lock.
    manifest_install_paths_preserved_subdirs | grep -qx "locks"
}

@test "fleet lock: path is stable for the same workspace regardless of cwd" {
    local a b
    a="$(_fleet_lock_dir_path)"
    mkdir -p "$SCRATCH/elsewhere"
    b="$(cd "$SCRATCH/elsewhere" && MANIFEST_CLI_FLEET_ROOT="$SCRATCH/work" _fleet_lock_dir_path)"
    [ "$a" = "$b" ]
}

@test "fleet lock: a second acquire is refused while the first is held" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    _fleet_lock_acquire "$dir"        # holder pid = this test process (alive)
    run _fleet_lock_acquire "$dir"    # same live holder -> must not break
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Another fleet ship is already running"
    _fleet_lock_release "$dir"
}

@test "fleet lock: a stale lock from a dead PID is reclaimed" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    mkdir -p "$dir"
    # 99999 is almost certainly not a live PID; kill -0 fails -> dead -> reclaim.
    {
        printf 'pid=99999\n'
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=stale-token\n'
    } > "$dir/holder"
    run _fleet_lock_acquire "$dir"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Reclaimed a stale fleet lock"
    grep -q "^pid=$$\$" "$dir/holder"
    _fleet_lock_release "$dir"
}

@test "fleet lock: a lock held on another host is NEVER broken" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    mkdir -p "$dir"
    # Foreign host + a dead-looking PID: must still be treated as held (NFS-safe).
    {
        printf 'pid=99999\n'
        printf 'host=some-other-host\n'
        printf 'start=x\n'
    } > "$dir/holder"
    run _fleet_lock_acquire "$dir"
    [ "$status" -ne 0 ]
    # The foreign holder file must be intact (not reclaimed/overwritten).
    grep -q "^host=some-other-host\$" "$dir/holder"
    rm -rf "$dir"
}

@test "fleet lock: a reused PID (alive pid, different start token) is reclaimed" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    mkdir -p "$dir"
    # Our own live PID but a start token that cannot match -> treated as reused.
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=DEFINITELY-NOT-OUR-START-TOKEN\n'
    } > "$dir/holder"
    run _fleet_lock_acquire "$dir"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Reclaimed a stale fleet lock"
    _fleet_lock_release "$dir"
}

@test "fleet lock: release is idempotent and safe on a missing lock" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    run _fleet_lock_release "$dir"   # never acquired
    [ "$status" -eq 0 ]
    _fleet_lock_acquire "$dir"
    _fleet_lock_release "$dir"
    run _fleet_lock_release "$dir"   # again
    [ "$status" -eq 0 ]
    [ ! -d "$dir" ]
}

# --- Acquire-then-write window (TOCTOU) -------------------------------------

@test "fleet lock: a freshly-created holder-less dir is NOT reclaimed (grace)" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    mkdir -p "$dir"          # winner created the dir but hasn't written holder
    [ ! -e "$dir/holder" ]
    # Within the grace window a racer must treat it as held, not break it.
    run _fleet_lock_acquire "$dir"
    [ "$status" -ne 0 ]
    rm -rf "$dir"
}

@test "fleet lock: an old holder-less dir IS reclaimed (winner crashed pre-write)" {
    local dir
    dir="$(_fleet_lock_dir_path)"
    mkdir -p "$dir"
    [ ! -e "$dir/holder" ]
    # grace=0 => any age qualifies as abandoned; the dir is reclaimed.
    MANIFEST_CLI_FLEET_LOCK_GRACE_SECONDS=0 run _fleet_lock_acquire "$dir"
    [ "$status" -eq 0 ]
    grep -q "^pid=$$\$" "$dir/holder"
    _fleet_lock_release "$dir"
}

# --- Wiring guards ----------------------------------------------------------
# Behavioral coverage above proves the lock mechanism. These guard that it
# stays wired into fleet_ship's apply path and is released on every exit.

@test "fleet lock: wired into fleet_ship apply with acquire + RETURN/INT/TERM release" {
    local f="$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # Acquire is invoked on the apply path.
    grep -q '_fleet_lock_acquire "\$fleet_lock"' "$f"
    # Released on normal return AND on signal (with re-raise).
    grep -q "_fleet_lock_release .* RETURN" "$f"
    grep -q "kill -INT \$\$' INT" "$f"
    grep -q "kill -TERM \$\$' TERM" "$f"
}

@test "fleet lock: acquired only after the read-only pre-flights, never in preview" {
    local f="$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    local preflight_line acquire_line preview_return_line
    acquire_line=$(grep -n '_fleet_lock_acquire "\$fleet_lock"' "$f" | head -1 | cut -d: -f1)
    # The pre-flight / preview-return strings appear in several fleet functions;
    # pick the occurrence in fleet_ship's body = the greatest line below acquire.
    preflight_line=$(grep -n "_fleet_preflight_on_default_branch" "$f" | cut -d: -f1 \
        | awk -v a="$acquire_line" '$1<a{m=$1} END{print m}')
    preview_return_line=$(grep -n 'execution_mode.*==.*preview' "$f" | cut -d: -f1 \
        | awk -v a="$acquire_line" '$1<a{m=$1} END{print m}')
    # Lock is taken after the default-branch pre-flight ...
    [ "$acquire_line" -gt "$preflight_line" ]
    # ... and after the preview early-return guard (so preview never locks).
    [ "$acquire_line" -gt "$preview_return_line" ]
}
