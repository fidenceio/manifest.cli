#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the config write lock (TRACKER §8.2 / §9.20 Block C; audit rows
# ATOM-006 and ATOM-CFGLOCK — one defect filed twice).
#
# The lock was a bare `mkdir` spin: no trap, no holder identity, no stale
# reclaim. A writer killed mid-write left `<file>.lock.d` behind, and every
# later write to that file then spun for 5s and refused — permanently, with no
# message saying why. It now shares system/manifest-lock.sh with the fleet lock,
# so it inherits holder identity, PID-reuse detection, cross-host safety and
# stale reclaim, plus an EXIT/INT/TERM trap of its own.
#
# All writes are sandboxed under $SCRATCH.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    load_modules "core/manifest-config.sh"
    CFG="$SCRATCH/manifest.config.yaml"
    printf 'project:\n  name: demo\n' > "$CFG"
    # Keep contention tests fast: 2 attempts at 0.1s instead of 50.
    export MANIFEST_CLI_CONFIG_LOCK_ATTEMPTS=2
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

@test "config lock: acquire creates the lock + holder, release removes it" {
    # NOT `run`: bats runs the command in a subshell, and acquisition must happen
    # in the caller's own shell for the EXIT trap to belong to the right process.
    # That is the same reason the function returns through a global rather than
    # echoing a path into a command substitution.
    _manifest_config_lock_acquire "$CFG"
    [ "$_MANIFEST_CLI_CONFIG_LOCK_DIR" = "$CFG.lock.d" ]
    [ -d "$CFG.lock.d" ]
    # A holder file is what makes stale reclaim safe — without it a racer cannot
    # tell a live holder from an abandoned directory.
    [ -r "$CFG.lock.d/holder" ]
    grep -q "^pid=$$\$" "$CFG.lock.d/holder"
    _manifest_config_lock_release "$CFG.lock.d"
    [ ! -d "$CFG.lock.d" ]
}

@test "config lock: a stale lock from a dead PID is reclaimed, not wedged" {
    # THE defect: this used to spin and refuse forever.
    mkdir -p "$CFG.lock.d"
    {
        printf 'pid=99999\n'
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=stale-token\n'
    } > "$CFG.lock.d/holder"

    _manifest_config_lock_acquire "$CFG"

    grep -q "^pid=$$\$" "$CFG.lock.d/holder"
    _manifest_config_lock_release "$CFG.lock.d"
}

@test "config lock: a reused PID (alive pid, mismatched start token) is reclaimed" {
    mkdir -p "$CFG.lock.d"
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=not-the-real-start-token\n'
    } > "$CFG.lock.d/holder"

    _manifest_config_lock_acquire "$CFG"

    [ -d "$CFG.lock.d" ]
    _manifest_config_lock_release "$CFG.lock.d"
}

@test "config lock: a lock held on another host is NEVER broken" {
    # Shared-\$HOME / NFS safety: a foreign host is treated as alive even when the
    # recorded PID looks dead locally.
    mkdir -p "$CFG.lock.d"
    {
        printf 'pid=99999\n'
        printf 'host=some-other-host\n'
        printf 'start=x\n'
    } > "$CFG.lock.d/holder"

    run _manifest_config_lock_acquire "$CFG"

    [ "$status" -ne 0 ]
    [ -d "$CFG.lock.d" ]
    grep -q '^host=some-other-host$' "$CFG.lock.d/holder"
}

@test "config lock: a live holder is refused rather than reclaimed" {
    _manifest_config_lock_acquire "$CFG"
    [ -d "$CFG.lock.d" ]
    # Second acquire while the holder is this very live process -> must refuse,
    # and must leave _MANIFEST_CLI_CONFIG_LOCK_DIR empty so a caller that ignores
    # the return value cannot mistake a failure for a held lock.
    run _manifest_config_lock_acquire "$CFG"
    [ "$status" -ne 0 ]
    [ -d "$CFG.lock.d" ]
    _manifest_config_lock_release "$CFG.lock.d"
}

@test "config lock: released by the trap when the holding process dies" {
    # The trap is the half a stale-reclaim cannot cover: reclaim needs the NEXT
    # writer to come along, whereas the trap frees the lock immediately. Run a
    # real child shell that acquires and then exits without releasing.
    run bash -c '
        set -eo pipefail
        export MANIFEST_CLI_CORE_MODULES_DIR="$1/modules"
        source "$1/modules/core/manifest-shared-utils.sh"
        source "$1/modules/core/manifest-yaml.sh"
        source "$1/modules/core/manifest-config.sh"
        _manifest_config_lock_acquire "$2" >/dev/null
        [ -d "$2.lock.d" ] || exit 1
        # Exit WITHOUT calling release — the EXIT trap must clean up.
    ' _ "$TEST_REPO_ROOT" "$CFG"

    [ "$status" -eq 0 ]
    [ ! -d "$CFG.lock.d" ]
}

@test "config lock: released by the trap on SIGTERM" {
    # The holder waits via `sleep & wait`, NOT a foreground `sleep`. Bash defers a
    # trap until the current FOREGROUND command finishes, and `sleep` is an
    # external command — so a foreground sleep makes the trap fire up to 30s
    # late, which passes when run alone and fails under a loaded parallel suite.
    # `wait` is a builtin and is interrupted by the signal, so the trap runs at
    # once. (Found by this very test flaking in the full run.)
    bash -c '
        export MANIFEST_CLI_CORE_MODULES_DIR="$1/modules"
        source "$1/modules/core/manifest-shared-utils.sh"
        source "$1/modules/core/manifest-yaml.sh"
        source "$1/modules/core/manifest-config.sh"
        _manifest_config_lock_acquire "$2" >/dev/null
        # Signal readiness only after the lock is held AND the trap is installed,
        # so the parent never races the setup.
        touch "$3"
        # Short hold: the parent kills us as soon as the marker appears, and a
        # long sleep would outlive us as an orphan that bats then waits on.
        sleep 2 &
        wait $!
    ' _ "$TEST_REPO_ROOT" "$CFG" "$SCRATCH/holder.ready" &
    local child=$!

    local waited=0
    while [ ! -e "$SCRATCH/holder.ready" ] && [ "$waited" -lt 200 ]; do
        sleep 0.05
        waited=$((waited + 1))
    done
    [ -e "$SCRATCH/holder.ready" ]
    [ -d "$CFG.lock.d" ]

    kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true

    # The trap ran during the child's death, so the lock is gone with no reclaim.
    [ ! -d "$CFG.lock.d" ]
}
