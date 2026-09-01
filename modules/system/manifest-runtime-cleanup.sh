#!/bin/bash

# Manifest Runtime Cleanup
#
# Opportunistic TTL-gated sweep of stale files under Manifest-owned cache
# roots. Wired from get_time_timestamp(), so it piggybacks on a code path
# already invoked by most real commands and is skipped entirely on
# fast-path invocations (--version, --help) that never fetch trusted time.
#
# Scope is strictly manifest_install_paths_cache_dirs() output. Plugin
# data dirs are intentionally excluded — they hold user-owned state, not
# regenerable cache. Defense-in-depth safety guards run per path before
# any delete: empty / "/" / "$HOME" / bare "/tmp" / "$TMPDIR" / anything
# without "manifest-cli" in the resolved path is refused.

[ -n "$_MANIFEST_CLI_RUNTIME_CLEANUP_LOADED" ] && return 0
_MANIFEST_CLI_RUNTIME_CLEANUP_LOADED=1

# shellcheck source=manifest-install-paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifest-install-paths.sh"

MANIFEST_CLI_RUNTIME_CLEANUP_PERIOD=${MANIFEST_CLI_RUNTIME_CLEANUP_PERIOD:-86400}
MANIFEST_CLI_RUNTIME_CLEANUP_STALE_AGE=${MANIFEST_CLI_RUNTIME_CLEANUP_STALE_AGE:-604800}

_manifest_runtime_cleanup_marker() {
    local first
    first=$(manifest_install_paths_cache_dirs | head -n1)
    [ -n "$first" ] && echo "${first}/runtime-cleanup.last"
}

_manifest_runtime_cache_path_is_safe() {
    local path="$1"
    [ -n "$path" ] || return 1
    [ "$path" != "/" ] || return 1
    [ "$path" != "$HOME" ] || return 1
    [ "$path" != "/tmp" ] || return 1
    [ -n "$TMPDIR" ] && [ "$path" = "${TMPDIR%/}" ] && return 1
    case "$path" in
        */manifest-cli|*/manifest-cli/*) return 0 ;;
        *) return 1 ;;
    esac
}

_manifest_runtime_maybe_cleanup_cache() {
    local marker period stale_age now last mmin path
    marker=$(_manifest_runtime_cleanup_marker)
    [ -n "$marker" ] || return 0

    period="${MANIFEST_CLI_RUNTIME_CLEANUP_PERIOD:-86400}"
    [[ "$period" =~ ^[0-9]+$ ]] && [ "$period" -ge 3600 ] || period=86400
    stale_age="${MANIFEST_CLI_RUNTIME_CLEANUP_STALE_AGE:-604800}"
    [[ "$stale_age" =~ ^[0-9]+$ ]] && [ "$stale_age" -ge 86400 ] || stale_age=604800

    now=$(date -u +%s)
    last=0
    if [ -f "$marker" ]; then
        last=$(tr -d '[:space:]' < "$marker" 2>/dev/null || echo 0)
        [[ "$last" =~ ^[0-9]+$ ]] || last=0
    fi
    [ $((now - last)) -lt "$period" ] && return 0

    mmin=$((stale_age / 60))
    while IFS= read -r path; do
        _manifest_runtime_cache_path_is_safe "$path" || continue
        [ -d "$path" ] || continue
        find "$path" -type f -mmin +"$mmin" -delete 2>/dev/null || true
    done < <(manifest_install_paths_cache_dirs)

    mkdir -p "$(dirname "$marker")" 2>/dev/null || return 0
    printf '%s\n' "$now" > "$marker" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# On-demand host-state cleanup — `manifest cleanup state`
#
# The sweep above is opportunistic: gated on a 24h period and a 7d stale age,
# and reachable only via get_time_timestamp(). That is right for an automatic
# background sweep and useless when a user actually wants to clear something
# now. These two functions are the on-demand front door.
#
# WHAT IS IN SCOPE: manifest_install_paths_cache_dirs() only — the designated
# cache root — with every path still passed through
# _manifest_runtime_cache_path_is_safe. Plus a forced keep-last-N ship-log
# rotation, which reuses manifest_ship_log_rotate rather than reimplementing
# retention.
#
# WHAT IS DELIBERATELY NOT, and why each one would be a bug:
#   * manifest.config.global.yaml — the user's configuration. `rm -rf
#     ~/.manifest-cli` destroying this is the very problem this command exists
#     to give people an alternative to.
#   * audit/ — the who-authorized-what compliance record. Forensic by design,
#     which is why it sits outside cache_dirs in the first place.
#   * gh-rate/ — NOT a cache despite the name. It holds `mutation-epochs`, the
#     ledger _manifest_gh_rate_state_file() uses to pace GitHub mutations.
#     Clearing it tells Manifest it has made zero recent mutations, which
#     removes the pacing that keeps a user under GitHub's rate limit. Deleting
#     it trades a few kilobytes for a rate-limit ban.
#   * locks/ — a live lock is a running operation. Stale-lock reclaim already
#     exists per-lock in the ship lock module and is not re-derived here.
#   * ide/ — user state, in preserved_subdirs.
#
# Files younger than MANIFEST_CLI_CLEANUP_STATE_MIN_AGE (default 1h) are left
# alone even on demand: a concurrent manifest process may be mid-write to a
# scratch file, and "cleanup deleted another run's temp file" is a far worse
# outcome than leaving an hour of scratch on disk.
# ---------------------------------------------------------------------------

MANIFEST_CLI_CLEANUP_STATE_MIN_AGE=${MANIFEST_CLI_CLEANUP_STATE_MIN_AGE:-3600}

_manifest_runtime_state_min_age() {
    local age="${MANIFEST_CLI_CLEANUP_STATE_MIN_AGE:-3600}"
    [[ "$age" =~ ^[0-9]+$ ]] || age=3600
    printf '%s' "$age"
}

# Add host-state rows to the shared dry-run summary.
manifest_runtime_state_report() {
    local group="Host runtime state"
    local keep_group="Kept (never cleaned)"
    local age mmin path bytes n
    age="$(_manifest_runtime_state_min_age)"
    mmin=$((age / 60))

    while IFS= read -r path; do
        _manifest_runtime_cache_path_is_safe "$path" || continue
        [ -d "$path" ] || continue
        n="$(find "$path" -type f -mmin +"$mmin" 2>/dev/null | wc -l | tr -d '[:space:]')"
        [[ "$n" =~ ^[0-9]+$ ]] || n=0
        [ "$n" -gt 0 ] || continue
        bytes="$(find "$path" -type f -mmin +"$mmin" -exec du -sk {} + 2>/dev/null | awk '{s+=$1} END {print s*1024}')"
        [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=""
        manifest_execution_summary_add delete "$group" "$path ($n stale file(s))" "$bytes"
    done < <(manifest_install_paths_cache_dirs)

    # Ship logs beyond the keep-N window.
    local logs_dir keep over
    if declare -F manifest_install_paths_logs_dir >/dev/null 2>&1; then
        logs_dir="$(manifest_install_paths_logs_dir)"
        keep="${MANIFEST_CLI_SHIP_LOG_KEEP:-20}"
        [[ "$keep" =~ ^[0-9]+$ ]] || keep=20
        if [ -d "$logs_dir" ] && [ "$keep" -ge 1 ]; then
            over="$(find "$logs_dir" -maxdepth 1 -type f -name 'ship-*.log' 2>/dev/null | wc -l | tr -d '[:space:]')"
            [[ "$over" =~ ^[0-9]+$ ]] || over=0
            if [ "$over" -gt "$keep" ]; then
                manifest_execution_summary_add delete "$group" \
                    "$logs_dir ($((over - keep)) ship log(s) past the keep-$keep window)"
            fi
        fi
    fi

    # Name the boundary explicitly. A cleanup command that silently declines to
    # touch things is indistinguishable from one that forgot they exist.
    local state_dir
    if declare -F manifest_install_paths_global_state_dir >/dev/null 2>&1; then
        state_dir="$(manifest_install_paths_global_state_dir)"
        [ -f "$state_dir/manifest.config.global.yaml" ] && \
            manifest_execution_summary_note "$keep_group" "$state_dir/manifest.config.global.yaml — your configuration"
        [ -d "$state_dir/audit" ] && \
            manifest_execution_summary_note "$keep_group" "$state_dir/audit — compliance record, forensic"
        [ -d "$state_dir/gh-rate" ] && \
            manifest_execution_summary_note "$keep_group" "$state_dir/gh-rate — GitHub rate-limit pacing ledger"
        [ -d "$state_dir/locks" ] && \
            manifest_execution_summary_note "$keep_group" "$state_dir/locks — live operation locks"
    fi
    return 0
}

# Apply the on-demand host-state cleanup. Best-effort throughout: this must
# never abort a cleanup run whose other scopes succeeded.
manifest_runtime_state_apply() {
    local age mmin path removed=0 n
    age="$(_manifest_runtime_state_min_age)"
    mmin=$((age / 60))

    while IFS= read -r path; do
        _manifest_runtime_cache_path_is_safe "$path" || continue
        [ -d "$path" ] || continue
        n="$(find "$path" -type f -mmin +"$mmin" 2>/dev/null | wc -l | tr -d '[:space:]')"
        [[ "$n" =~ ^[0-9]+$ ]] || n=0
        find "$path" -type f -mmin +"$mmin" -delete 2>/dev/null || true
        # The TTL sweep is `-type f` only, so empty scratch dirs accumulate
        # forever. Depth-first so nested empties collapse in one pass; -maxdepth
        # is not used because scratch nests by purpose.
        find "$path" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        removed=$((removed + n))
    done < <(manifest_install_paths_cache_dirs)

    # Force the keep-N prune past its 1h TTL gate rather than duplicating the
    # retention rule here.
    if declare -F manifest_ship_log_rotate >/dev/null 2>&1; then
        MANIFEST_CLI_SHIP_LOG_ROTATE_PERIOD=0 manifest_ship_log_rotate || true
    fi

    if [ "$removed" -gt 0 ]; then
        log_success "Removed $removed stale runtime file(s)"
    else
        log_info "No stale runtime files to remove"
    fi
    return 0
}
