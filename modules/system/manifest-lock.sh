#!/bin/bash
# -----------------------------------------------------------------------------
# Manifest CLI — shared advisory lock primitives
# -----------------------------------------------------------------------------
# One implementation of "hold a directory lock, survive a crashed holder".
#
# WHY THIS MODULE EXISTS
# The fleet lock grew a correct implementation — holder identity, cross-host
# safety, PID-reuse detection, atomic stale reclaim — while the config lock
# stayed a bare `mkdir` spin with no trap and no reclaim, so a config writer
# killed mid-write wedged every later write to that file permanently. Copying
# the fleet logic into the config module would have made a second copy of a
# ~90-line derivation, which is the defect class TRACKER §6 exists to remove
# (§9.13 found five copies of one version calculation that agreed only by
# luck). Both callers now share these primitives; only their messages differ.
#
# LOCK LAYOUT
#   <lock_dir>/          the lock itself — created atomically by mkdir
#   <lock_dir>/holder    pid / host / start-token / since, written after winning
#
# The holder file is what makes reclaim safe: without it a racer cannot tell a
# live holder from an abandoned directory, and "delete it if it looks old" will
# eventually delete a lock somebody is holding.
# -----------------------------------------------------------------------------

# Process start-time token — distinguishes a live holder from a recycled PID.
# Linux: starttime (field 22 of /proc/<pid>/stat). The comm field (2) can
# contain spaces/parens, so parse the fields AFTER the final ')' — starttime is
# then the 20th. macOS/BSD: ps lstart. Empty if unknown.
_manifest_lock_proc_start_token() {
    local pid="$1"
    if [ -r "/proc/$pid/stat" ]; then
        sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $20}'
    else
        ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' '
    fi
}

# Modification time of a path in epoch seconds.
# GNU-first: the wrapper forces coreutils' gnubin onto PATH on macOS, so
# `stat -c %Y` is the clean mtime there. GNU MUST come first — BSD `stat -f %m`
# run first on Linux mis-parses `%m` as a filename, dumps garbage and exits 1 —
# so the BSD form is only a fallback, for contexts that ran without the prepend
# (a module sourced in isolation) or native BSDs without GNU stat.
_manifest_lock_dir_mtime_epoch() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# 0 if the recorded holder is a live process on THIS host (do not break it).
# 1 if reclaimable (abandoned). A holder on a different host is treated as alive
# (returns 0) so shared-$HOME / NFS setups are never broken cross-host.
_manifest_lock_holder_alive() {
    local lock_dir="$1"
    local grace="${2:-15}"
    local holder="$lock_dir/holder"
    if [ ! -r "$holder" ]; then
        # No holder file. Either a winner that hasn't written its holder yet
        # (the mkdir-then-write window) or a crash before the write. Treat a
        # freshly-created lock dir as alive for a short grace period so a racer
        # can never break a lock that was just legitimately acquired; only a
        # holder-less dir older than the grace window is abandoned/reclaimable.
        local mtime now
        mtime="$(_manifest_lock_dir_mtime_epoch "$lock_dir")"
        now="$(date +%s 2>/dev/null)"
        if [ -n "$mtime" ] && [ -n "$now" ] && [ "$((now - mtime))" -lt "$grace" ]; then
            return 0   # fresh, holder write likely in flight -> treat as alive
        fi
        return 1       # old and holder-less -> abandoned, reclaimable
    fi
    local h_pid h_host h_token now_token
    h_pid="$(sed -n 's/^pid=//p' "$holder" 2>/dev/null)"
    h_host="$(sed -n 's/^host=//p' "$holder" 2>/dev/null)"
    h_token="$(sed -n 's/^start=//p' "$holder" 2>/dev/null)"
    [ "$h_host" = "$(hostname 2>/dev/null)" ] || return 0   # cross-host: never break
    [ -n "$h_pid" ] || return 1
    kill -0 "$h_pid" 2>/dev/null || return 1                # pid gone: dead
    now_token="$(_manifest_lock_proc_start_token "$h_pid")"
    [ "$now_token" = "$h_token" ]                            # mismatch: pid reused
}

_manifest_lock_write_holder() {
    local lock_dir="$1"
    {
        printf 'pid=%s\n' "$$"
        printf 'host=%s\n' "$(hostname 2>/dev/null)"
        printf 'start=%s\n' "$(_manifest_lock_proc_start_token "$$")"
        printf 'since=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    } > "$lock_dir/holder" 2>/dev/null || true
}

# Acquire an advisory lock directory, reclaiming it if the recorded holder is
# gone. Returns 0 holding the lock, 1 if it could not be taken.
#   $1 lock_dir      directory to create
#   $2 max_attempts  retries at 0.1s each before giving up (default 50)
#   $3 grace_seconds holder-less grace window (default 15)
#   $4 label         what to call this lock in the reclaim warning (default "lock")
# Callers own their refusal message; this function is silent apart from the
# reclaim warning, which is a real event a user should see. The label is a
# parameter so the warning still names which lock was reclaimed — "Reclaimed a
# stale fleet lock" and "…config lock" are different operational events.
_manifest_lock_acquire_dir() {
    local lock_dir="$1"
    local max_attempts="${2:-50}"
    local grace="${3:-15}"
    local label="${4:-lock}"
    local attempts=0
    mkdir -p "$(dirname "$lock_dir")" 2>/dev/null || true
    while ! mkdir "$lock_dir" 2>/dev/null; do
        if ! _manifest_lock_holder_alive "$lock_dir" "$grace"; then
            # Snapshot the holder we judged dead, then reclaim by renaming the
            # dir aside (atomic; only one racer's mv can succeed — the source
            # vanishes for the others). After the rename, re-verify: if the
            # holder changed under us (someone acquired in the gap), we grabbed
            # a LIVE lock — restore it and retry instead of deleting it.
            local stale="${lock_dir}.stale.$$"
            local before_holder after_holder
            before_holder="$(cat "$lock_dir/holder" 2>/dev/null || echo "")"
            if mv "$lock_dir" "$stale" 2>/dev/null; then
                after_holder="$(cat "$stale/holder" 2>/dev/null || echo "")"
                if [ "$after_holder" != "$before_holder" ] && _manifest_lock_holder_alive "$stale" "$grace"; then
                    mv "$stale" "$lock_dir" 2>/dev/null || rm -rf "$stale" 2>/dev/null
                else
                    rm -rf "$stale" 2>/dev/null
                    if command -v log_warning >/dev/null 2>&1; then
                        log_warning "Reclaimed a stale $label (previous holder is gone)."
                    fi
                    continue
                fi
            fi
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$max_attempts" ]; then
            return 1
        fi
        sleep 0.1
    done
    _manifest_lock_write_holder "$lock_dir"
    return 0
}

_manifest_lock_release_dir() {
    local lock_dir="$1"
    [ -n "$lock_dir" ] && [ -d "$lock_dir" ] && rm -rf "$lock_dir" 2>/dev/null || true
}
