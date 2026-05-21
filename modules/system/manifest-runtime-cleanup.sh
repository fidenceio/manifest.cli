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

[ -n "$_MANIFEST_RUNTIME_CLEANUP_LOADED" ] && return 0
_MANIFEST_RUNTIME_CLEANUP_LOADED=1

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
