#!/bin/bash

# Manifest Configuration Module
# Handles environment variable loading, validation, and defaults

# Configuration file paths (in order of precedence)
MANIFEST_CLI_CONFIG_FILES=(
    "manifest.config.yaml"
    "manifest.config.local.yaml"
)
MANIFEST_CLI_GLOBAL_CONFIG="$HOME/.manifest-cli/manifest.config.global.yaml"

MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT=2

declare -gA _MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES=()

# -----------------------------------------------------------------------------
# §46: MANIFEST_CLI_AUTO_CONFIRM as it stood in the PROCESS ENVIRONMENT, snapshot
# at module-source time — before any YAML layer can assign it.
#
# `automation.auto_confirm` is a mapped key (manifest-yaml.sh), so EVERY config
# file the CLI loads can set MANIFEST_CLI_AUTO_CONFIRM — including Layer 2, the
# repo's own committed manifest.config.yaml, and Layer 1.5, a fleet root's. The
# global-config safety gate below must never read that variable directly: a
# cloned repo carrying three lines of YAML would otherwise authorize a rewrite of
# $HOME/.manifest-cli/manifest.config.global.yaml (plus a .bak and a migration
# marker) on a plain `manifest config get` — a write OUTSIDE the repo that
# supplied the consent, with no -y, no flag and no prompt. Repo-scope data does
# not get to authorize an out-of-repo write.
#
# This is the same ordering rule manifest-fleet.sh already applies in the other
# direction ("Set it after config resolution so member config cannot revoke that
# consent, and fleet consent cannot authorize incidental config migration").
#
# Deliberately NOT exported: a child `manifest` process takes its own snapshot
# from its own environment, and an in-process `export MANIFEST_CLI_AUTO_CONFIRM=1`
# (which is what the fleet ship path does) must not retroactively become
# process-start consent.
declare -g _MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV=""

_manifest_config_capture_auto_confirm_env() {
    _MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV="${MANIFEST_CLI_AUTO_CONFIRM:-}"
}

# The single predicate for "the operator authorized unattended writes to the
# user's global config". Literal "1" — matching the two other sites that read
# this consent, _manifest_repo_scope_auto_confirm_authorized
# (manifest-shared-utils.sh) and manifest_resolve_github_owner
# (manifest-shared-functions.sh) — so one spelling can no longer bypass one
# safety gate while another refuses it. Named rather than numbered: the previous
# form cited manifest-shared-utils.sh:1122, which was already the wrong line when
# it was written (the comparison was at :1100) and moves on every edit above it.
# is_truthy is deliberately NOT used: this is a consent check, not a config-value
# coercion, and `true`/`yes`/`on` were only ever reachable from a config file.
#
# This predicate is the NARROWER of the two consent predicates and must stay
# that way. The apply-target gate additionally honors fleet's in-process
# delegation (_MANIFEST_CLI_DELEGATED_APPLY_CONSENT); this one must not, because
# the global config lives OUTSIDE every repo in the fleet — which is exactly what
# manifest-fleet.sh's own comment promises ("fleet consent cannot authorize
# incidental config migration"). Pinned by tests/fleet_delegated_apply_consent.bats.
_manifest_config_auto_confirm_authorized() {
    [ "${_MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV:-0}" = "1" ]
}

_manifest_config_capture_process_env_overrides() {
    local entry env_var env_value
    local mapping_decl

    mapping_decl="$(declare -p _MANIFEST_ENV_TO_YAML 2>/dev/null || true)"
    case "$mapping_decl" in
        declare\ -A*) ;;
        *) return 0 ;;
    esac

    while IFS= read -r entry; do
        env_var="${entry%%=*}"
        env_value="${entry#*=}"
        [[ "$env_var" == MANIFEST_CLI_* ]] || continue
        [[ -n "${_MANIFEST_ENV_TO_YAML[$env_var]:-}" ]] || continue
        _MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES["$env_var"]="$env_value"
    done < <(env)
}

_manifest_config_apply_process_env_overrides() {
    local env_var

    for env_var in "${!_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[@]}"; do
        case "$(declare -p "$env_var" 2>/dev/null || true)" in
            declare\ -a*|declare\ -A*)
                unset "$env_var"
                ;;
        esac
        export "$env_var"="${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[$env_var]}"
        log_debug "load_configuration: process env override ${env_var}"
    done
}

_manifest_config_apply_secret_env_refs() {
    local ref_var="${MANIFEST_CLI_CLOUD_API_KEY_ENV:-}"

    if [ -z "$ref_var" ] || [ -n "${MANIFEST_CLI_CLOUD_API_KEY:-}" ]; then
        return 0
    fi

    if [[ ! "$ref_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        # UNSET before reporting, and report the name only after it is gone.
        # "Ignoring" previously meant "this function ignores it" while the value
        # stayed exported for every other consumer — including the redactor that
        # log_warning itself invokes, which expanded it indirectly and so
        # EXECUTED it. Rejecting a value has to mean removing it.
        unset MANIFEST_CLI_CLOUD_API_KEY_ENV
        log_warning "Ignoring invalid cloud.api_key_env value: $ref_var"
        return 0
    fi

    if [ -n "${!ref_var:-}" ]; then
        export MANIFEST_CLI_CLOUD_API_KEY="${!ref_var}"
    fi
}

_manifest_config_capture_process_env_overrides
_manifest_config_capture_auto_confirm_env

_manifest_config_warn() {
    local message="$1"
    if command -v log_warning >/dev/null 2>&1; then
        log_warning "$message"
    else
        echo "⚠️  $message"
    fi
}

# -----------------------------------------------------------------------------
# Function: _manifest_config_backup_before_migration
# -----------------------------------------------------------------------------
# §8.4b: snapshot the global config ONCE before the first in-place (`yq -i`)
# mutating write of a migration. A crash / Ctrl-C / disk-full mid-rewrite — or
# a yq bug — would otherwise destroy the user's only copy of their hand-tuned
# config. Mirrors the install-cli.sh pre-commit-hook backup pattern.
#
# Honors MANIFEST_CLI_CONFIG_SKIP_WRITES (no backup when writes are skipped).
# The backup is FATAL-on-failure: the whole point is not to lose the file, so
# if the snapshot can't be made we refuse to start mutating (return 1) rather
# than rewrite in place with no safety net.
#
# ARGUMENTS:
#   $1 - config file path to snapshot
#
# RETURNS:
#   0 on success (backup created) or skipped via SKIP_WRITES
#   1 if the backup could not be created (caller must abort the migration)
# -----------------------------------------------------------------------------
_manifest_config_backup_before_migration() {
    local config_file="$1"
    is_truthy "${MANIFEST_CLI_CONFIG_SKIP_WRITES:-0}" && return 0
    [ -f "$config_file" ] || return 0
    local stamp backup_file
    stamp="$(date +%Y%m%d_%H%M%S)"
    backup_file="${config_file}.bak.${stamp}"
    if cp -p "$config_file" "$backup_file" 2>/dev/null; then
        _manifest_config_warn "Backed up config before migration: $backup_file"
        return 0
    fi
    _manifest_config_warn "Could not back up config before migration: $config_file — aborting to avoid data loss."
    return 1
}

# -----------------------------------------------------------------------------
# Global Config Safety Gate
# -----------------------------------------------------------------------------
# The user's global config (~/.manifest-cli/manifest.config.global.yaml)
# persists across upgrades and contains user customizations. Every code path
# that modifies or deletes it MUST pass through this gate.
#
# ARGUMENTS:
#   $1 - action: "modify" | "delete" | "overwrite"
#   $2 - target: file path
#   $3 - reason: human description shown to the user
#
# RETURNS: 0 if approved, non-zero if denied
#
# ENV:
#   MANIFEST_CLI_AUTO_CONFIRM=1            bypass prompt (CI / scripted). Read
#       from the PROCESS ENVIRONMENT ONLY, via the source-time snapshot above —
#       a value assigned by any loaded config file (`automation.auto_confirm`)
#       is NOT consent to write a file outside the repo that supplied it. See
#       §46 and the comment on _MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV.
#   MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED=1   session-cached approval (modify only)
# -----------------------------------------------------------------------------
_confirm_global_config_write() {
    local action="$1"
    local target="$2"
    local reason="$3"

    if _manifest_config_auto_confirm_authorized; then
        _manifest_config_warn "Auto-confirming $action of $target ($reason) [MANIFEST_CLI_AUTO_CONFIRM=${_MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV}]"
        export MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED=1
        return 0
    fi

    if [ "$action" = "modify" ] && [ "${MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED:-0}" = "1" ]; then
        return 0
    fi

    if [ ! -t 0 ]; then
        log_error "Refusing to $action global config without confirmation."
        log_error "  File:   $target"
        log_error "  Reason: $reason"
        log_error "  Set MANIFEST_CLI_AUTO_CONFIRM=1 to authorize, or run interactively."
        return 1
    fi

    echo ""
    echo "⚠️  Global configuration $action requested"
    echo "    File:   $target"
    echo "    Reason: $reason"
    echo ""

    case "$action" in
        delete|overwrite)
            local ans1 ans2
            printf "    This is destructive. Type 'yes' to confirm (1/2): "
            read -r ans1 || return 1
            [ "$ans1" = "yes" ] || { echo "    Cancelled."; return 1; }
            printf "    Type 'yes' again to confirm (2/2): "
            read -r ans2 || return 1
            [ "$ans2" = "yes" ] || { echo "    Cancelled."; return 1; }
            ;;
        *)
            local ans
            printf "    Continue? (yes/no): "
            read -r ans || return 1
            [ "$ans" = "yes" ] || { echo "    Cancelled."; return 1; }
            ;;
    esac

    export MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED=1
    return 0
}

_manifest_config_state_dir() {
    echo "$HOME/.manifest-cli"
}

_manifest_config_warning_state_file() {
    echo "$(_manifest_config_state_dir)/config-warning.last"
}

_manifest_config_migration_state_file() {
    echo "$(_manifest_config_state_dir)/config-migration.last"
}

# Ensure the state directory exists. Callers that intend to write must invoke
# this; pure-read paths must not, so preview-mode commands never mutate disk.
_manifest_config_state_dir_ensure() {
    # Strictly read-only inspections (e.g. `manifest first`) set this so a
    # config load never touches disk — return non-zero so atomic writers abort.
    is_truthy "${MANIFEST_CLI_CONFIG_SKIP_WRITES:-0}" && return 1
    mkdir -p "$(_manifest_config_state_dir)" 2>/dev/null
}

# Atomically record a timestamp into STATE_FILE.
#
# Race-safety: the temp file is PID-suffixed (private to this writer), and the
# rename(2) syscall is atomic on POSIX filesystems — concurrent readers never
# observe a partial file, and concurrent writers' last-write-wins is the
# correct semantic for a monotonic "epoch of last emission" marker.
_manifest_config_atomic_write_timestamp() {
    local state_file="$1"
    local now="$2"
    [ -n "$state_file" ] && [ -n "$now" ] || return 1
    _manifest_config_state_dir_ensure || return 1
    local tmp="${state_file}.tmp.$$"
    if printf '%s\n' "$now" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$state_file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    else
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
    return 0
}

# Pure read: returns 0 if the cooldown has elapsed and the next warning is
# permitted to emit, 1 otherwise. Never writes — the cooldown is advanced
# separately at apply-time via _manifest_execution_apply_hook.
_manifest_config_should_emit_warnings() {
    local cooldown_minutes="${MANIFEST_CLI_CONFIG_WARNING_COOLDOWN_MINUTES:-1440}"
    if ! [[ "$cooldown_minutes" =~ ^[0-9]+$ ]] || [ "$cooldown_minutes" -lt 0 ]; then
        cooldown_minutes=1440
    fi

    [ "$cooldown_minutes" -eq 0 ] && return 0

    local state_file
    state_file=$(_manifest_config_warning_state_file)
    [ -n "$state_file" ] || return 0
    local now
    now=$(date +%s)
    local last=0

    if [ -f "$state_file" ]; then
        last=$(tr -d '[:space:]' < "$state_file" 2>/dev/null || echo "0")
        if ! [[ "$last" =~ ^[0-9]+$ ]]; then
            last=0
        fi
    fi

    [ $((now - last)) -ge $((cooldown_minutes * 60)) ]
}

# Pure read: returns 0 if the migration cooldown has elapsed, 1 otherwise.
# Never writes — the cooldown is advanced separately when migration actually
# runs (apply path) or is announced (warn-only path advances at apply-time).
_manifest_config_should_run_auto_migration() {
    local cooldown_minutes="${MANIFEST_CLI_CONFIG_MIGRATION_COOLDOWN_MINUTES:-1440}"
    if ! [[ "$cooldown_minutes" =~ ^[0-9]+$ ]] || [ "$cooldown_minutes" -lt 0 ]; then
        cooldown_minutes=1440
    fi

    [ "$cooldown_minutes" -eq 0 ] && return 0

    local state_file
    state_file=$(_manifest_config_migration_state_file)
    [ -n "$state_file" ] || return 0
    local now
    now=$(date +%s)
    local last=0

    if [ -f "$state_file" ]; then
        last=$(tr -d '[:space:]' < "$state_file" 2>/dev/null || echo "0")
        if ! [[ "$last" =~ ^[0-9]+$ ]]; then
            last=0
        fi
    fi

    [ $((now - last)) -ge $((cooldown_minutes * 60)) ]
}

# Invoked from manifest_execution_apply_header at the apply boundary. Atomically
# advances any cooldowns whose notices fired during this CLI invocation. Lives
# in config.sh so execution-policy.sh stays free of config-state coupling.
_manifest_execution_apply_hook() {
    # Honour the read-only guard: a strictly-inspecting command must not advance
    # cooldown markers even if some path reaches the apply boundary.
    is_truthy "${MANIFEST_CLI_CONFIG_SKIP_WRITES:-0}" && return 0
    local now
    now=$(date +%s)
    if [ "${_MANIFEST_CLI_DEPRECATION_WARNED:-0}" = "1" ]; then
        _manifest_config_atomic_write_timestamp \
            "$(_manifest_config_warning_state_file)" "$now" 2>/dev/null || true
        unset _MANIFEST_CLI_DEPRECATION_WARNED
    fi
    if [ "${_MANIFEST_CLI_MIGRATION_NOTIFIED:-0}" = "1" ]; then
        _manifest_config_atomic_write_timestamp \
            "$(_manifest_config_migration_state_file)" "$now" 2>/dev/null || true
        unset _MANIFEST_CLI_MIGRATION_NOTIFIED
    fi
}

warn_deprecated_configuration() {
    if ! _manifest_config_should_emit_warnings; then
        return 0
    fi

    local warned=0

    if [ "${MANIFEST_CLI_TIME_SERVER1:-}" = "time.apple.com" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER2:-}" = "time.google.com" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER3:-}" = "pool.ntp.org" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER4:-}" = "time.nist.gov" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER1:-}" = "216.239.35.0" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER2:-}" = "216.239.35.4" ]; then
        _manifest_config_warn "Legacy time server defaults detected in time.server1..4. Recommended defaults are https://www.cloudflare.com/cdn-cgi/trace / https://www.google.com/generate_204 with https://www.apple.com for server3."
        warned=1
    fi

    if [ "${MANIFEST_CLI_TAP_REPO:-}" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        _manifest_config_warn "Legacy brew.tap_repo detected. Recommended value: https://github.com/fidenceio/homebrew-tap.git"
        warned=1
    fi

    if [ "$warned" -eq 1 ]; then
        _manifest_config_warn "Run 'manifest upgrade --force' (or reinstall) to apply safe config migrations automatically."
        # Marker: the apply hook will atomically advance config-warning.last
        # if this invocation reaches apply mode. Preview invocations never
        # write the throttle, satisfying the no-side-effects contract.
        export _MANIFEST_CLI_DEPRECATION_WARNED=1
    fi
}

# Config paths that were removed from the schema on 2026-08-16.
# Listed at the FAMILY level, not per leaf: deleting the four
# `version.component_position.*` children individually would leave an empty
# `component_position: {}` map behind, which reads as configuration that is
# merely blank rather than gone.
#
# Retiring a key silently would repeat the defect these were retired for. The
# loader skips unmapped paths without a word, so a config that still sets them
# would look accepted forever; `config doctor` names them instead, and --fix
# deletes them. Removal is safe by construction — no code path has ever read
# them, so deleting one cannot change any release outcome.
declare -ga _MANIFEST_CLI_CONFIG_RETIRED_KEYS=(
    "version.format"
    "version.max_values"
    "version.component_position"
    "version.increment_target"
    "version.reset_components"
    # Same defect, found while removing the others: `config show` printed
    # "Version Validation: true" for a key no code path read, so setting it
    # false offered an opt-out from validation that never existed —
    # validate_version_format() runs regardless. Its neighbour version.regex is
    # genuinely live (it supplies that function's pattern) and stays.
    "version.validation"
)

# True when a dot-path exists in the file with any non-null value. Kept separate
# from get_yaml_value because these paths may hold MAPS, whose multi-line
# serialization would corrupt the `|`-delimited finding protocol if echoed.
_manifest_config_path_present() {
    local config_file="$1"
    local path="$2"
    local raw
    raw="$(get_yaml_value "$config_file" ".${path}" "")" || return 1
    [ -n "$raw" ] && [ "$raw" != "null" ]
}

_manifest_config_detect_issues() {
    local config_file="$1"
    [ -f "$config_file" ] || return 1

    local _retired
    for _retired in "${_MANIFEST_CLI_CONFIG_RETIRED_KEYS[@]}"; do
        if _manifest_config_path_present "$config_file" "$_retired"; then
            # from/to deliberately empty: there is no replacement value, and the
            # present value may be a map.
            echo "obsolete|$_retired||"
        fi
    done

    local ts1 ts2 ts3 ts4 tap_repo
    ts1=$(get_yaml_value "$config_file" ".time.server1" "")
    ts2=$(get_yaml_value "$config_file" ".time.server2" "")
    ts3=$(get_yaml_value "$config_file" ".time.server3" "")
    ts4=$(get_yaml_value "$config_file" ".time.server4" "")
    tap_repo=$(get_yaml_value "$config_file" ".brew.tap_repo" "")

    if [ "$ts1" = "time.apple.com" ] || [ "$ts1" = "216.239.35.0" ]; then
        echo "legacy|time.server1|$ts1|https://www.cloudflare.com/cdn-cgi/trace"
    fi
    if [ "$ts2" = "time.google.com" ] || [ "$ts2" = "216.239.35.4" ]; then
        echo "legacy|time.server2|$ts2|https://www.google.com/generate_204"
    fi
    if [ "$ts3" = "pool.ntp.org" ]; then
        echo "legacy|time.server3|pool.ntp.org|https://www.apple.com"
    fi
    if [ "$ts4" = "time.nist.gov" ]; then
        echo "legacy|time.server4|time.nist.gov|"
    fi
    if [ "$tap_repo" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        echo "legacy|brew.tap_repo|https://github.com/fidenceio/fidenceio-homebrew-tap.git|https://github.com/fidenceio/homebrew-tap.git"
    fi

    local cache_ttl cache_cleanup cache_stale schema_ver
    cache_ttl=$(get_yaml_value "$config_file" ".time.cache_ttl" "")
    cache_cleanup=$(get_yaml_value "$config_file" ".time.cache_cleanup_period" "")
    cache_stale=$(get_yaml_value "$config_file" ".time.cache_stale_max_age" "")
    schema_ver=$(get_yaml_value "$config_file" ".config.schema_version" "")

    if [ -z "$cache_ttl" ]; then
        echo "missing|time.cache_ttl||120"
    fi
    if [ -z "$cache_cleanup" ]; then
        echo "missing|time.cache_cleanup_period||3600"
    fi
    if [ -z "$cache_stale" ]; then
        echo "missing|time.cache_stale_max_age||21600"
    fi
    if [ -z "$schema_ver" ]; then
        echo "missing|config.schema_version||${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT}"
    fi
}

_manifest_config_upsert_key() {
    local file="$1"
    local key="$2"
    local value="$3"
    [ -f "$file" ] || return 1

    # key is now a YAML dot-path (e.g. "time.server1")
    set_yaml_value "$file" "$key" "$value"
}

# Remove a dot-path outright. Only used for retired keys
# (_MANIFEST_CLI_CONFIG_RETIRED_KEYS); there is no set_yaml_value equivalent because
# `config unset` deletes through the key map, which by definition no longer
# holds these paths.
_manifest_config_delete_key() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    yq e "del(.${key})" -i "$file" 2>/dev/null || return 1

    # Removing the last child leaves `version: {}` behind — present but blank,
    # which is the same "looks like configuration, means nothing" shape these
    # keys were retired for. Prune a parent the delete just emptied. One level
    # is enough: every retired path is a direct child of `version`.
    local parent="${key%.*}"
    [ "$parent" = "$key" ] && return 0
    local remaining
    remaining="$(yq e ".${parent} | length" "$file" 2>/dev/null)" || return 0
    [ "$remaining" = "0" ] && yq e "del(.${parent})" -i "$file" 2>/dev/null
    return 0
}

# The lock mechanism is shared with the fleet lock — see system/manifest-lock.sh.
# manifest-core.sh sources it before this module; guard anyway, because this
# module is also sourced standalone by tests and partial-tree subshells and an
# undefined primitive would surface only at the moment of a config write.
if ! declare -f _manifest_lock_acquire_dir >/dev/null 2>&1; then
    _manifest_config_lock_modules_dir="${MANIFEST_CLI_CORE_MODULES_DIR:-}"
    if [ -z "$_manifest_config_lock_modules_dir" ]; then
        _manifest_config_lock_modules_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi
    # shellcheck disable=SC1091
    source "$_manifest_config_lock_modules_dir/system/manifest-lock.sh"
    unset _manifest_config_lock_modules_dir
fi

# Lock dirs this process is holding, released by the EXIT/INT/TERM trap below.
_MANIFEST_CLI_CONFIG_HELD_LOCKS=()

# Release every config lock this process still holds. Registered as a trap so a
# writer killed mid-write does not leave the lock behind. Without this, the lock
# dir survived the dead process and every later write to that file spun for 5s
# and then refused — permanently, with no message explaining why.
_manifest_config_locks_release_all() {
    local d
    for d in "${_MANIFEST_CLI_CONFIG_HELD_LOCKS[@]:-}"; do
        [ -n "$d" ] && _manifest_lock_release_dir "$d"
    done
    _MANIFEST_CLI_CONFIG_HELD_LOCKS=()
}

_manifest_config_lock_trap_install() {
    [ -n "${_MANIFEST_CLI_CONFIG_LOCK_TRAP_SET:-}" ] && return 0
    # INT/TERM re-raise after cleanup so the caller still sees a signal death
    # rather than a plain exit code — the install lock's missing-SIGINT gap
    # (§14a) is the same bug seen from the other side.
    trap '_manifest_config_locks_release_all' EXIT
    trap '_manifest_config_locks_release_all; trap - INT; kill -INT $$' INT
    trap '_manifest_config_locks_release_all; trap - TERM; kill -TERM $$' TERM
    _MANIFEST_CLI_CONFIG_LOCK_TRAP_SET=1
    return 0
}

# Returns 0 holding the lock and sets _MANIFEST_CLI_CONFIG_LOCK_DIR; returns 1
# without taking it. Mirrors _manifest_ship_repo_lock_acquire.
#
# It sets a global instead of echoing the path, and that is load-bearing, not
# style. The old signature echoed, so every caller wrote
# `lock_dir=$(_manifest_config_lock_acquire "$f")` — a COMMAND SUBSTITUTION,
# which runs in a subshell. Any release bookkeeping (and the EXIT trap that acts
# on it) then belongs to that subshell and fires the instant the substitution
# closes, dropping the lock while the caller believes it is held. Returning
# through a global keeps acquisition in the caller's own shell.
_manifest_config_lock_acquire() {
    local target_file="$1"
    _MANIFEST_CLI_CONFIG_LOCK_DIR=""
    local lock_dir="${target_file}.lock.d"
    _manifest_config_lock_trap_install
    if ! _manifest_lock_acquire_dir \
            "$lock_dir" \
            "${MANIFEST_CLI_CONFIG_LOCK_ATTEMPTS:-50}" \
            "${MANIFEST_CLI_CONFIG_LOCK_GRACE_SECONDS:-15}" \
            "config lock"; then
        return 1
    fi
    _MANIFEST_CLI_CONFIG_HELD_LOCKS+=("$lock_dir")
    _MANIFEST_CLI_CONFIG_LOCK_DIR="$lock_dir"
    return 0
}

_manifest_config_lock_release() {
    local lock_dir="$1"
    [ -n "$lock_dir" ] || return 0
    _manifest_lock_release_dir "$lock_dir"
    # Drop it from the held list so the EXIT trap does not try again.
    local remaining=() d
    for d in "${_MANIFEST_CLI_CONFIG_HELD_LOCKS[@]:-}"; do
        [ -n "$d" ] && [ "$d" != "$lock_dir" ] && remaining+=("$d")
    done
    _MANIFEST_CLI_CONFIG_HELD_LOCKS=("${remaining[@]:-}")
}

_manifest_config_apply_migrations() {
    local config_file="$1"
    local dry_run="$2"
    local applied=0
    # §8.4b: snapshot the live config once, lazily, immediately before the FIRST
    # mutating write — so we never create a spurious backup when there is nothing
    # to migrate, and never start rewriting in place without a safety net.
    local backed_up=0

    # MANIFEST_CLI_CONFIG_SKIP_WRITES is the global "do not touch the config"
    # contract (read-only inspections set it). Honor it here too: degrade to a
    # write-free preview so neither a backup nor an in-place mutation happens.
    if is_truthy "${MANIFEST_CLI_CONFIG_SKIP_WRITES:-0}"; then
        dry_run="true"
    fi

    while IFS='|' read -r issue_type key from to; do
        [ -n "$issue_type" ] || continue
        case "$issue_type" in
            "legacy")
                if [ "$dry_run" = "true" ]; then
                    echo "would-update|$key|$from|$to"
                else
                    if [ "$backed_up" -eq 0 ]; then
                        _manifest_config_backup_before_migration "$config_file" || return 1
                        backed_up=1
                    fi
                    _manifest_config_upsert_key "$config_file" "$key" "$to" && applied=$((applied + 1))
                    echo "updated|$key|$from|$to"
                fi
                ;;
            "missing")
                if [ "$dry_run" = "true" ]; then
                    echo "would-add|$key||$to"
                else
                    if [ "$backed_up" -eq 0 ]; then
                        _manifest_config_backup_before_migration "$config_file" || return 1
                        backed_up=1
                    fi
                    _manifest_config_upsert_key "$config_file" "$key" "$to" && applied=$((applied + 1))
                    echo "added|$key||$to"
                fi
                ;;
            "obsolete")
                # Deleting a key the runtime never reads cannot change behavior,
                # and the backup below still runs first. Left in place, it would
                # be reported as a finding on every doctor run with no way to
                # clear it.
                if [ "$dry_run" = "true" ]; then
                    echo "would-remove|$key||"
                else
                    if [ "$backed_up" -eq 0 ]; then
                        _manifest_config_backup_before_migration "$config_file" || return 1
                        backed_up=1
                    fi
                    _manifest_config_delete_key "$config_file" "$key" && applied=$((applied + 1))
                    echo "removed|$key||"
                fi
                ;;
        esac
    done < <(_manifest_config_detect_issues "$config_file")

    if [ "$dry_run" = "false" ] && [ "$applied" -gt 0 ]; then
        _manifest_config_upsert_key "$config_file" "config.schema_version" "${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT}" >/dev/null 2>&1 || true
    fi
}

auto_migrate_user_global_configuration() {
    # Strictly read-only inspections (e.g. `manifest first`) set this so the
    # config load never rewrites — or nags about — the global config.
    is_truthy "${MANIFEST_CLI_CONFIG_SKIP_WRITES:-0}" && return 0
    local config_file="$MANIFEST_CLI_GLOBAL_CONFIG"
    [ -f "$config_file" ] || return 0
    if ! _manifest_config_should_run_auto_migration; then
        return 0
    fi

    # `obsolete` is deliberately NOT actionable here. Every global config the
    # installer has ever written carries version.format (install-cli.sh seeded
    # it), so treating retired keys as drift would put a warning in front of
    # essentially every existing user for a condition that cannot affect a
    # single release — nothing reads those keys. `manifest config doctor`
    # reports them on request and `--fix` removes them; that is the right place
    # for a cosmetic cleanup. Do not add "obsolete" to this list.
    local actionable=0
    while IFS='|' read -r issue_type _key _from _to; do
        case "$issue_type" in
            "legacy"|"missing")
                actionable=1
                break
                ;;
        esac
    done < <(_manifest_config_detect_issues "$config_file")

    [ "$actionable" -eq 1 ] || return 0

    # Auto-migration silently rewrites the global config on every CLI run.
    # That violates the "no silent modifications" rule. Default behavior is
    # now WARN-ONLY; users opt in to silent migration with MANIFEST_CLI_AUTO_CONFIRM=1
    # or run `manifest config doctor --fix` explicitly.
    #
    # §46: the opt-in must come from the PROCESS ENVIRONMENT. This gate is tested
    # with the same predicate as _confirm_global_config_write below, not a looser
    # one — otherwise a config-file `automation.auto_confirm` would skip the drift
    # WARNING here and then be refused at the gate, replacing the notice the user
    # is supposed to see with an error about missing confirmation.
    if ! _manifest_config_auto_confirm_authorized; then
        _manifest_config_warn "Configuration drift detected in $config_file."
        _manifest_config_warn "Run 'manifest config doctor --dry-run' to review, then '--fix' to apply."
        # Marker: the apply hook advances config-migration.last only if this
        # invocation reaches apply mode; preview-only runs leave the throttle
        # untouched so the notice continues to nudge the user.
        export _MANIFEST_CLI_MIGRATION_NOTIFIED=1
        return 0
    fi

    if ! _confirm_global_config_write "modify" "$config_file" "auto-migration of legacy/missing keys"; then
        return 0
    fi

    local lock_dir=""
    if ! _manifest_config_lock_acquire "$config_file"; then
        # Skipping is correct — a live holder is already migrating this file — but
        # it must not be silent. Before the lock gained stale reclaim, a crashed
        # writer left the lock behind and this line skipped the migration forever
        # while reporting success, which is why "auto-migration never ran" had no
        # symptom to search for.
        _manifest_config_warn "Config auto-migration skipped: $config_file is locked by another Manifest process."
        return 0
    fi
    lock_dir="$_MANIFEST_CLI_CONFIG_LOCK_DIR"
    local migration_output=""
    migration_output=$(_manifest_config_apply_migrations "$config_file" "false")
    _manifest_config_lock_release "$lock_dir"

    if [ -n "$migration_output" ]; then
        _manifest_config_warn "Applied safe configuration migrations to $config_file."
        _manifest_config_warn "Run 'manifest config doctor --dry-run' to review current drift status."
        # Migration actually applied: advance the throttle inline (this path
        # only runs under AUTO_CONFIRM, an explicit user authorization to
        # write the global config, so an inline atomic write is in scope).
        _manifest_config_atomic_write_timestamp \
            "$(_manifest_config_migration_state_file)" "$(date +%s)" 2>/dev/null || true
    fi
}

config_doctor() {
    local fix="false"
    local dry_run="false"
    local config_file="$MANIFEST_CLI_GLOBAL_CONFIG"
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()

    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            "-h"|"--help"|"help")
                echo "Usage: manifest config doctor [--fix] [-y|--yes] [--dry-run] [--file <path>]"
                echo ""
                echo "Options:"
                echo "  --dry-run     Explicit preview; no config writes"
                echo "  -y, --yes     Apply fixes when used with --fix"
                echo "  --fix         Repair detected config drift"
                echo "  --file <path> Inspect a specific config file"
                return 0
                ;;
            "--fix")
                fix="true"
                shift
                ;;
            "--dry-run")
                dry_run="true"
                shift
                ;;
            "--file")
                config_file="${2:-}"
                shift 2
                ;;
            *)
                echo "Unknown option for config doctor: $1"
                echo "Usage: manifest config doctor [--fix] [-y|--yes] [--dry-run] [--file <path>]"
                return 1
                ;;
        esac
    done

    if [[ "$fix" == "true" && "$execution_mode" == "preview" ]]; then
        dry_run="true"
    fi

    if [ ! -f "$config_file" ]; then
        echo "⚠️  Config file not found: $config_file"
        echo "   Run 'manifest config setup' to create one, or copy the example:"
        echo "   mkdir -p ~/.manifest-cli && cp examples/manifest.config.yaml.example $config_file"
        return 1
    fi

    echo "🩺 Manifest Config Doctor"
    echo "========================="
    echo "   Config file: $config_file"
    echo ""

    local issues=()
    while IFS= read -r line; do
        [ -n "$line" ] && issues+=("$line")
    done < <(_manifest_config_detect_issues "$config_file")

    if [ ${#issues[@]} -eq 0 ]; then
        echo "✅ No configuration drift detected."
        return 0
    fi

    echo "Findings:"
    local issue
    for issue in "${issues[@]}"; do
        IFS='|' read -r issue_type key from to <<< "$issue"
        case "$issue_type" in
            "legacy")
                echo " - LEGACY: $key uses '$from' (recommended: '$to')"
                ;;
            "missing")
                echo " - MISSING: $key is not set (recommended default: '$to')"
                ;;
            "deprecated")
                echo " - DEPRECATED: $key is set ('$from'); use '$to'"
                ;;
            "obsolete")
                echo " - OBSOLETE: $key is set but no longer exists; nothing reads it (removed 2026-08-16). Safe to delete."
                ;;
        esac
    done

    if [ "$fix" = "true" ] || [ "$dry_run" = "true" ]; then
        echo ""
        echo "Migration plan:"
        if [ "$dry_run" = "true" ]; then
            _manifest_config_apply_migrations "$config_file" "$dry_run"
        else
            manifest_execution_apply_header
            if [ "$config_file" = "$MANIFEST_CLI_GLOBAL_CONFIG" ] && \
               ! _confirm_global_config_write "modify" "$config_file" "applying ${#issues[@]} configuration migration(s)"; then
                echo "Migration cancelled."
                return 1
            fi
            local lock_dir=""
            if ! _manifest_config_lock_acquire "$config_file"; then
                echo "❌ Could not acquire config lock for migration: ${config_file}.lock.d"
                return 1
            fi
            lock_dir="$_MANIFEST_CLI_CONFIG_LOCK_DIR"
            _manifest_config_apply_migrations "$config_file" "$dry_run"
            _manifest_config_lock_release "$lock_dir"
        fi

        if [ "$dry_run" = "true" ]; then
            echo ""
            echo "ℹ️  Preview complete. Re-run with --fix -y to apply."
        else
            echo ""
            echo "✅ Safe migrations applied."
        fi
    else
        echo ""
        echo "ℹ️  Run 'manifest config doctor --fix' to apply safe migrations."
        echo "ℹ️  Run 'manifest config doctor --dry-run' to preview changes."
    fi
}

# Walk up from a starting directory to the nearest fleet root — the closest
# ancestor (the directory itself included) that holds the fleet config file.
# Echoes the canonical path and returns 0 when found; returns 1 otherwise.
# Terminates at the filesystem root, so it can never loop. Kept local to the
# config loader rather than reusing the fleet module's find_fleet_root, so core
# carries no dependency on the fleet layer.
_manifest_config_find_fleet_root() {
    local start="$1"
    local config_filename="${MANIFEST_CLI_FLEET_CONFIG_FILENAME:-manifest.fleet.config.yaml}"
    local dir
    dir="$(cd "$start" 2>/dev/null && pwd -P)" || return 1
    while :; do
        if [ -f "$dir/$config_filename" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        [ "$dir" = "/" ] && return 1
        dir="$(dirname "$dir")"
    done
}

# Load configuration from YAML files
load_configuration() {
    local project_root="$1"
    local include_project_overrides="${2:-true}"

    if [ -z "$project_root" ]; then
        project_root="."
    fi

    # Fail fast if yq is missing (rather than later, mid-workflow).
    if ! require_yaml_parser; then
        return 1
    fi

    # Baseline defaults first (so YAML layers override them)
    set_default_configuration

    # §8.4a: a config file that is PRESENT but unparseable is FATAL. Silently
    # reverting to defaults on a malformed file (the old behavior) would let a
    # ship proceed with the wrong branch/gate/policy. An ABSENT file stays
    # non-fatal exactly as before — the `[ -f ... ]` guards establish presence,
    # so a nonzero return here can only mean present-but-broken.
    # Layer 1: User global configuration
    if [ -f "$MANIFEST_CLI_GLOBAL_CONFIG" ]; then
        # Progress goes to stderr: `manifest config ... --json` and friends load
        # configuration before emitting, so anything on stdout here lands inside
        # the JSON document and makes it unparseable.
        echo "🔧 Loading user global configuration from: $MANIFEST_CLI_GLOBAL_CONFIG" >&2
        if ! load_yaml_to_env "$MANIFEST_CLI_GLOBAL_CONFIG"; then
            log_error "Refusing to continue: user global configuration is present but could not be parsed: $MANIFEST_CLI_GLOBAL_CONFIG"
            return 1
        fi
    fi

    # Layer 1.5: Inherited fleet configuration.
    # A repo nested inside a fleet inherits the fleet root's configuration as a
    # baseline — e.g. github.owner — so a fleet-wide setting applies to every
    # member without being copied into each repo. The member's own config
    # (Layers 2-3) and the environment still override it. This is the fleet's
    # environment, not a per-repo override, so it loads independently of
    # include_project_overrides (which governs only the CURRENT repo's local
    # file — `manifest init repo`, for one, passes false yet must still create
    # the repo under the fleet's org). load_yaml_to_env maps only known keys, so
    # an inherited file can set recognized MANIFEST_CLI_* config and nothing
    # else. Skipped when the project IS the fleet root (Layers 2-3 already load
    # those files) and when the repo is not inside any fleet.
    local canonical_project_root fleet_root
    canonical_project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || canonical_project_root="$project_root"
    if fleet_root="$(_manifest_config_find_fleet_root "$project_root")" \
       && [ -n "$fleet_root" ] && [ "$fleet_root" != "$canonical_project_root" ]; then
        local fleet_shared="$fleet_root/manifest.config.yaml"
        if [ -f "$fleet_shared" ]; then
            echo "🔧 Inheriting fleet configuration from: manifest.config.yaml (Fleet: $fleet_root)" >&2
            if ! load_yaml_to_env "$fleet_shared"; then
                log_error "Refusing to continue: fleet configuration is present but could not be parsed: $fleet_shared"
                return 1
            fi
        fi
        local fleet_local="$fleet_root/manifest.config.local.yaml"
        if [ -f "$fleet_local" ]; then
            echo "🔧 Inheriting fleet local configuration from: manifest.config.local.yaml (Fleet: $fleet_root)" >&2
            if ! load_yaml_to_env "$fleet_local"; then
                log_error "Refusing to continue: fleet local configuration is present but could not be parsed: $fleet_local"
                return 1
            fi
        fi
    fi

    # Layer 2: Project shared configuration
    local project_shared="$project_root/manifest.config.yaml"
    if [ -f "$project_shared" ]; then
        echo "🔧 Loading project configuration from: manifest.config.yaml (Project: $project_root)" >&2
        if ! load_yaml_to_env "$project_shared"; then
            log_error "Refusing to continue: project configuration is present but could not be parsed: $project_shared"
            return 1
        fi
    fi

    # Layer 3: Project local overrides (only when requested)
    if [ "$include_project_overrides" = "true" ]; then
        local project_local="$project_root/manifest.config.local.yaml"
        if [ -f "$project_local" ]; then
            echo "🔧 Loading project local configuration from: manifest.config.local.yaml (Project: $project_root)" >&2
            if ! load_yaml_to_env "$project_local"; then
                log_error "Refusing to continue: project local configuration is present but could not be parsed: $project_local"
                return 1
            fi
        fi
    fi

    # Exported MANIFEST_CLI_* values supplied at process startup are the
    # highest-precedence layer. This keeps CI and legacy env-based automation
    # working while the same settings become first-class YAML keys.
    _manifest_config_apply_process_env_overrides
    _manifest_config_apply_secret_env_refs

    # Fill any remaining gaps with defaults
    set_default_configuration
    auto_migrate_user_global_configuration
    # Re-apply defaults in case auto-migration added missing values.
    set_default_configuration
    warn_deprecated_configuration
}

# Set default configuration values
set_default_configuration() {
    # Versioning Configuration.
    #
    # These two keys are the whole versioning surface, and both are read by the
    # bump arithmetic. Fifteen further version.* keys were retired 2026-08-16
    # because nothing read them: a name's position is its index
    # in `components`, and clearing every segment right of the bumped one is
    # intrinsic to the bump, so component_position.* / increment_target.* /
    # reset_components.* each restated a fact that already had one home — and
    # `config show` reported them as behavior in force. version.format and
    # version.max_values described a shape the arithmetic never consulted.
    export MANIFEST_CLI_VERSION_SEPARATOR="${MANIFEST_CLI_VERSION_SEPARATOR:-.}"
    # Ordered segment names; position is the index in this list. `revision` is
    # included because it is a real increment level — omitting it left the one
    # config key that names segments disagreeing with the four the CLI accepted.
    export MANIFEST_CLI_VERSION_COMPONENTS="${MANIFEST_CLI_VERSION_COMPONENTS:-major,minor,patch,revision}"

    # Git Configuration
    export MANIFEST_CLI_GIT_TAG_PREFIX="${MANIFEST_CLI_GIT_TAG_PREFIX:-v}"
    export MANIFEST_CLI_GIT_TAG_SUFFIX="${MANIFEST_CLI_GIT_TAG_SUFFIX:-}"
    # Bulk-add gitlink policy — false unstages NEWLY captured bare gitlinks
    # (nested repo, no .gitmodules entry) after `git add .`; declared submodules
    # and gitlinks already tracked in HEAD are never touched.
    export MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS="${MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS:-false}"

    # Release Policy
    export MANIFEST_CLI_RELEASE_TAG_TARGET="${MANIFEST_CLI_RELEASE_TAG_TARGET:-version_commit}"
    # Release gate — what must be green before a release is published.
    #   none        no verification (loud, audited bypass)
    #   local-tests run the project's test command before any mutation (default)
    #   remote-ci   require the pushed commit's GitHub checks to be green before publish
    #   all         local-tests AND remote-ci
    export MANIFEST_CLI_RELEASE_GATE="${MANIFEST_CLI_RELEASE_GATE:-local-tests}"
    # Command run for the local-tests phase. Empty = auto-detect ./scripts/run-tests.sh.
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="${MANIFEST_CLI_RELEASE_GATE_COMMAND:-}"
    # Test tier the local gate runs when it auto-detects ./scripts/run-tests.sh.
    #   full   the entire suite (default — preserves "nothing releases without a full run")
    #   smoke  the safety-contract subset (faster local ship; CI still enforces full on main)
    # Ignored when release_gate_command is set — a custom command owns its own tiering.
    export MANIFEST_CLI_RELEASE_GATE_TIER="${MANIFEST_CLI_RELEASE_GATE_TIER:-full}"
    # How long a recorded gate PASS stays fresh before a no-delta --force-bump
    # version stamp must re-run the gate. A clean, at-tag force-bump has no code
    # to verify (skipped-stamp-only), but if the last verified pass is older than
    # this window the gate RUNS anyway, so a tree never re-releases indefinitely
    # on stale verification. Whole days; 0 = always re-run (never skip on age).
    # The freshness clock advances only on a real PASS — a stamp-only skip never
    # bumps it, so repeated stamps can never keep the window green without tests.
    export MANIFEST_CLI_RELEASE_GATE_FRESHNESS_DAYS="${MANIFEST_CLI_RELEASE_GATE_FRESHNESS_DAYS:-30}"
    # §9.27(a): CI's verdict binds the ship. Before any mutation, a publishing
    # ship reads origin's latest COMPLETED `tests` workflow run on the default
    # branch and REFUSES when it concluded failure (the local gate proves this
    # host's OS only; CI proves the other leg). false keeps the pre-flight and
    # its printed finding but never refuses. Degraded states (no gh, no run yet,
    # gh errors) are announced as "unverified" and proceed — absence is not a
    # verdict (§6).
    export MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN="${MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN:-true}"
    # How long a green test run stays reusable before run-tests.sh re-runs it
    # (§5.10 TTL'd cache). English-reading duration: 4h / 30m / 90s / 2d, or
    # 'off' to always run. Accelerates dev/CI loops only — the release gate
    # passes --no-cache, so nothing ever releases on a cached result.
    export MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN="${MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN:-4h}"
    # Env prefix policy. ON by default: custom app env-var names must start with
    # this repo's prefix; framework names and the MANIFEST_CLI_ namespace are
    # always allowed. Empty (the default) = the prefix is DERIVED from the
    # project name (vendor-neutral: `fidence.app.kanizsa` → `FIDENCE_APP_KANIZSA_`,
    # `my-tool` → `MY_TOOL_`). Set an explicit value (e.g. `ACME_`) to require
    # that instead. Set `off` (or `none`) to disable the policy entirely.
    export MANIFEST_CLI_ENV_PREFIX="${MANIFEST_CLI_ENV_PREFIX:-}"
    # Prefix-policy enforcement level. strict (default) = violations block the
    # naming audit (fail-closed); warn = advisory only. naming_allow adds extra
    # allowlist entries, comma-separated (trailing `_` = prefix, else exact).
    export MANIFEST_CLI_ENV_NAMING_ENFORCEMENT="${MANIFEST_CLI_ENV_NAMING_ENFORCEMENT:-strict}"
    export MANIFEST_CLI_ENV_NAMING_ALLOW="${MANIFEST_CLI_ENV_NAMING_ALLOW:-}"
    export MANIFEST_CLI_GITHUB_RELEASE_ENABLED="${MANIFEST_CLI_GITHUB_RELEASE_ENABLED:-true}"
    export MANIFEST_CLI_GITHUB_RELEASE_REQUIRED="${MANIFEST_CLI_GITHUB_RELEASE_REQUIRED:-false}"
    export MANIFEST_CLI_GITHUB_RELEASE_DRAFT="${MANIFEST_CLI_GITHUB_RELEASE_DRAFT:-false}"
    export MANIFEST_CLI_GITHUB_RELEASE_PRERELEASE="${MANIFEST_CLI_GITHUB_RELEASE_PRERELEASE:-false}"
    # §9.2: gh mutation pacing — content-generating calls (repo create/edit,
    # release create, workflow dispatch) per rolling hour, on by default so
    # fleet-scale loops stay under GitHub's secondary limits (~80/min, 500/hr
    # content-generating). A fixed 60/min floor always applies alongside it.
    # 0 disables pacing entirely. Reads are never paced.
    export MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR="${MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR:-150}"
    export MANIFEST_CLI_INTERACTIVE_MODE="${MANIFEST_CLI_INTERACTIVE_MODE:-false}"
    
    # Branch Naming Configuration
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    export MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="${MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX:-feature/}"
    export MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="${MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX:-hotfix/}"
    export MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="${MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX:-release/}"
    export MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="${MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX:-bugfix/}"
    export MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="${MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH:-develop}"
    export MANIFEST_CLI_GIT_STAGING_BRANCH="${MANIFEST_CLI_GIT_STAGING_BRANCH:-staging}"
    
    # Trusted Timestamps Configuration
    export MANIFEST_CLI_TIME_SERVER1="${MANIFEST_CLI_TIME_SERVER1:-https://www.cloudflare.com/cdn-cgi/trace}"
    export MANIFEST_CLI_TIME_SERVER2="${MANIFEST_CLI_TIME_SERVER2:-https://www.google.com/generate_204}"
    export MANIFEST_CLI_TIME_SERVER3="${MANIFEST_CLI_TIME_SERVER3:-https://www.apple.com}"
    export MANIFEST_CLI_TIME_SERVER4="${MANIFEST_CLI_TIME_SERVER4:-}"
    export MANIFEST_CLI_TIME_TIMEOUT="${MANIFEST_CLI_TIME_TIMEOUT:-5}"
    export MANIFEST_CLI_TIME_RETRIES="${MANIFEST_CLI_TIME_RETRIES:-3}"
    export MANIFEST_CLI_TIME_VERIFY="${MANIFEST_CLI_TIME_VERIFY:-true}"
    export MANIFEST_CLI_TIME_CACHE_TTL="${MANIFEST_CLI_TIME_CACHE_TTL:-120}"
    export MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD="${MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD:-3600}"
    export MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE="${MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE:-21600}"

    # Timezone Configuration (defaults to UTC)
    # Can be overridden in manifest.config.local.yaml with IANA timezone names like:
    # America/New_York, America/Los_Angeles, Europe/London, Asia/Tokyo, etc.
    export MANIFEST_CLI_TIMEZONE="${MANIFEST_CLI_TIMEZONE:-UTC}"
    
    # Git Operations
    export MANIFEST_CLI_GIT_COMMIT_TEMPLATE="${MANIFEST_CLI_GIT_COMMIT_TEMPLATE:-Release v{version} - {timestamp}}"
    export MANIFEST_CLI_GIT_PUSH_STRATEGY="${MANIFEST_CLI_GIT_PUSH_STRATEGY:-simple}"
    export MANIFEST_CLI_GIT_PULL_STRATEGY="${MANIFEST_CLI_GIT_PULL_STRATEGY:-rebase}"
    export MANIFEST_CLI_GIT_TIMEOUT="${MANIFEST_CLI_GIT_TIMEOUT:-300}"
    export MANIFEST_CLI_GIT_RETRIES="${MANIFEST_CLI_GIT_RETRIES:-3}"
    
    # Homebrew Configuration
    export MANIFEST_CLI_BREW_OPTION="${MANIFEST_CLI_BREW_OPTION:-enabled}"
    export MANIFEST_CLI_BREW_INTERACTIVE="${MANIFEST_CLI_BREW_INTERACTIVE:-no}"
    export MANIFEST_CLI_TAP_REPO="${MANIFEST_CLI_TAP_REPO:-https://github.com/fidenceio/homebrew-tap.git}"
    
    # Documentation Configuration
    export MANIFEST_CLI_DOCS_FOLDER="${MANIFEST_CLI_DOCS_FOLDER:-docs}"
    export MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER:-docs/zArchive}"
    export MANIFEST_CLI_DOCS_RETAIN="${MANIFEST_CLI_DOCS_RETAIN:-10 versions}"
    export MANIFEST_CLI_DOCS_TEMPLATE_DIR="${MANIFEST_CLI_DOCS_TEMPLATE_DIR:-}"
    export MANIFEST_CLI_DOCS_GENERATE_ENABLED="${MANIFEST_CLI_DOCS_GENERATE_ENABLED:-true}"
    export MANIFEST_CLI_DOCS_GENERATE_CHANGELOG="${MANIFEST_CLI_DOCS_GENERATE_CHANGELOG:-true}"
    export MANIFEST_CLI_DOCS_GENERATE_README_VERSION="${MANIFEST_CLI_DOCS_GENERATE_README_VERSION:-true}"
    export MANIFEST_CLI_DOCS_GENERATE_INDEX="${MANIFEST_CLI_DOCS_GENERATE_INDEX:-true}"
    export MANIFEST_CLI_DOCS_GENERATE_ARCHIVE_CLEANUP="${MANIFEST_CLI_DOCS_GENERATE_ARCHIVE_CLEANUP:-true}"
    export MANIFEST_CLI_DOCS_GENERATE_SITE="${MANIFEST_CLI_DOCS_GENERATE_SITE:-true}"
    export MANIFEST_CLI_DOCS_GENERATE_SITE_WORKFLOW="${MANIFEST_CLI_DOCS_GENERATE_SITE_WORKFLOW:-true}"
    export MANIFEST_CLI_DOCS_SITE_ENABLED="${MANIFEST_CLI_DOCS_SITE_ENABLED:-false}"
    export MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES="${MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES:-true}"
    export MANIFEST_CLI_DOCS_SITE_SOURCE_DIR="${MANIFEST_CLI_DOCS_SITE_SOURCE_DIR:-docs-site}"
    export MANIFEST_CLI_DOCS_SITE_PUBLISH_MODE="${MANIFEST_CLI_DOCS_SITE_PUBLISH_MODE:-actions}"
    export MANIFEST_CLI_DOCS_SITE_BRANDING="${MANIFEST_CLI_DOCS_SITE_BRANDING:-auto}"
    export MANIFEST_CLI_DOCS_SITE_THEME="${MANIFEST_CLI_DOCS_SITE_THEME:-manifest}"
    export MANIFEST_CLI_DOCS_SITE_TITLE="${MANIFEST_CLI_DOCS_SITE_TITLE:-}"
    export MANIFEST_CLI_DOCS_SITE_DESCRIPTION="${MANIFEST_CLI_DOCS_SITE_DESCRIPTION:-}"
    export MANIFEST_CLI_DOCS_SITE_CUSTOM_CSS="${MANIFEST_CLI_DOCS_SITE_CUSTOM_CSS:-}"
    export MANIFEST_CLI_DOCS_SITE_PALETTE_PRIMARY="${MANIFEST_CLI_DOCS_SITE_PALETTE_PRIMARY:-#2563eb}"
    export MANIFEST_CLI_DOCS_SITE_PALETTE_ACCENT="${MANIFEST_CLI_DOCS_SITE_PALETTE_ACCENT:-#14b8a6}"
    export MANIFEST_CLI_DOCS_SITE_PALETTE_BACKGROUND="${MANIFEST_CLI_DOCS_SITE_PALETTE_BACKGROUND:-#ffffff}"
    export MANIFEST_CLI_DOCS_SITE_PALETTE_SURFACE="${MANIFEST_CLI_DOCS_SITE_PALETTE_SURFACE:-#f8fafc}"
    export MANIFEST_CLI_DOCS_SITE_PALETTE_TEXT="${MANIFEST_CLI_DOCS_SITE_PALETTE_TEXT:-#111827}"
    export MANIFEST_CLI_DOCS_SITE_PALETTE_MUTED="${MANIFEST_CLI_DOCS_SITE_PALETTE_MUTED:-#64748b}"
    export MANIFEST_CLI_DOC_REVIEW="${MANIFEST_CLI_DOC_REVIEW:-true}"
    export MANIFEST_CLI_DOC_REVIEW_OUTPUTS="${MANIFEST_CLI_DOC_REVIEW_OUTPUTS:-commit_body,report,release_notes}"
    export MANIFEST_CLI_DOC_REVIEW_REPORT_DIR="${MANIFEST_CLI_DOC_REVIEW_REPORT_DIR:-}"
    export MANIFEST_CLI_DOC_REVIEW_PROVIDER="${MANIFEST_CLI_DOC_REVIEW_PROVIDER:-local}"
    export MANIFEST_CLI_DOC_REVIEW_COMMAND="${MANIFEST_CLI_DOC_REVIEW_COMMAND:-}"
    export MANIFEST_CLI_DOC_REVIEW_REQUIRED="${MANIFEST_CLI_DOC_REVIEW_REQUIRED:-false}"
    export MANIFEST_CLI_RELEASE_NOTES_PROVIDER="${MANIFEST_CLI_RELEASE_NOTES_PROVIDER:-local}"
    export MANIFEST_CLI_RELEASE_NOTES_COMMAND="${MANIFEST_CLI_RELEASE_NOTES_COMMAND:-}"
    export MANIFEST_CLI_RELEASE_NOTES_REQUIRED="${MANIFEST_CLI_RELEASE_NOTES_REQUIRED:-false}"
    
    # File and directory names
    export MANIFEST_CLI_README_FILE="${MANIFEST_CLI_README_FILE:-README.md}"
    export MANIFEST_CLI_VERSION_FILE="${MANIFEST_CLI_VERSION_FILE:-VERSION}"
    export MANIFEST_CLI_GITIGNORE_FILE="${MANIFEST_CLI_GITIGNORE_FILE:-.gitignore}"
    export MANIFEST_CLI_DOCUMENTATION_ARCHIVE_DIR="${MANIFEST_CLI_DOCUMENTATION_ARCHIVE_DIR:-zArchive}"
    export MANIFEST_CLI_GIT_DIR="${MANIFEST_CLI_GIT_DIR:-.git}"
    export MANIFEST_CLI_MODULES_DIR="${MANIFEST_CLI_MODULES_DIR:-modules}"
    
    # File extensions
    export MANIFEST_CLI_MARKDOWN_EXT="${MANIFEST_CLI_MARKDOWN_EXT:-*.md}"
    
    # Installation paths
    export MANIFEST_CLI_INSTALL_DIR="${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest-cli}"
    export MANIFEST_CLI_BIN_DIR="${MANIFEST_CLI_BIN_DIR:-$HOME/.local/bin}"

    # Configuration file names
    export MANIFEST_CLI_CONFIG_GLOBAL="${MANIFEST_CLI_CONFIG_GLOBAL:-manifest.config.global.yaml}"
    export MANIFEST_CLI_CONFIG_LOCAL="${MANIFEST_CLI_CONFIG_LOCAL:-manifest.config.local.yaml}"
    export MANIFEST_CLI_CONFIG_SCHEMA_VERSION="${MANIFEST_CLI_CONFIG_SCHEMA_VERSION:-${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT}}"
    
    # Project Configuration
    export MANIFEST_CLI_PROJECT_NAME="${MANIFEST_CLI_PROJECT_NAME:-Manifest CLI}"
    export MANIFEST_CLI_PROJECT_TEAM="${MANIFEST_CLI_PROJECT_TEAM:-}"
    
    # Auto-Upgrade Configuration
    export MANIFEST_CLI_AUTO_UPDATE="${MANIFEST_CLI_AUTO_UPDATE:-true}"
    export MANIFEST_CLI_UPDATE_COOLDOWN="${MANIFEST_CLI_UPDATE_COOLDOWN:-30}"
    export MANIFEST_CLI_PROJECT_DESCRIPTION="${MANIFEST_CLI_PROJECT_DESCRIPTION:-A powerful CLI tool for versioning, AI documenting, and repository operations}"
    export MANIFEST_CLI_ORGANIZATION="${MANIFEST_CLI_ORGANIZATION:-Your Organization}"

    # Automation / deprecations / network / Cloud
    export MANIFEST_CLI_AUTO_CONFIRM="${MANIFEST_CLI_AUTO_CONFIRM:-false}"
    export MANIFEST_CLI_QUIET_DEPRECATIONS="${MANIFEST_CLI_QUIET_DEPRECATIONS:-false}"
    export MANIFEST_CLI_OFFLINE_MODE="${MANIFEST_CLI_OFFLINE_MODE:-false}"
    export MANIFEST_CLI_CLOUD_SKIP="${MANIFEST_CLI_CLOUD_SKIP:-false}"
    export MANIFEST_CLI_CLOUD_API_KEY_ENV="${MANIFEST_CLI_CLOUD_API_KEY_ENV:-MANIFEST_CLI_CLOUD_API_KEY}"
    
    # Advanced Configuration
    # version.regex is live: validate_version_format() reads it. version.validation
    # sat beside it until 2026-08-16 doing nothing — see _MANIFEST_CLI_CONFIG_RETIRED_KEYS.
    export MANIFEST_CLI_VERSION_REGEX="${MANIFEST_CLI_VERSION_REGEX:-^[0-9]+(\.[0-9]+)*$}"
    export MANIFEST_CLI_VERSION_SURFACES_ENABLED="${MANIFEST_CLI_VERSION_SURFACES_ENABLED:-true}"
    export MANIFEST_CLI_VERSION_HANDLER_CATALOG="${MANIFEST_CLI_VERSION_HANDLER_CATALOG:-}"
    export MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH="${MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH:-5}"
    export MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE="${MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE:-summary}"
    
    # Development & Debugging
    export MANIFEST_CLI_DEBUG="${MANIFEST_CLI_DEBUG:-false}"
    export MANIFEST_CLI_VERBOSE="${MANIFEST_CLI_VERBOSE:-false}"
    export MANIFEST_CLI_LOG_LEVEL="${MANIFEST_CLI_LOG_LEVEL:-INFO}"
    export MANIFEST_CLI_INTERACTIVE="${MANIFEST_CLI_INTERACTIVE:-false}"

    # PR Policy
    export MANIFEST_CLI_PR_PROFILE="${MANIFEST_CLI_PR_PROFILE:-solo}"
    export MANIFEST_CLI_PR_ENFORCE_READY="${MANIFEST_CLI_PR_ENFORCE_READY:-true}"

    # Fleet-aware repo identity hints. These are verified against fleet config
    # when present; they are not authoritative by themselves.
    export MANIFEST_CLI_FLEET_NAME="${MANIFEST_CLI_FLEET_NAME:-}"
    export MANIFEST_CLI_FLEET_MEMBER="${MANIFEST_CLI_FLEET_MEMBER:-}"
    export MANIFEST_CLI_FLEET_MODE="${MANIFEST_CLI_FLEET_MODE:-auto}"
    export MANIFEST_CLI_FLEET_ROOT="${MANIFEST_CLI_FLEET_ROOT:-}"
    export MANIFEST_CLI_FLEET_CONFIG_FILENAME="${MANIFEST_CLI_FLEET_CONFIG_FILENAME:-manifest.fleet.config.yaml}"

}

# Get configuration value with fallback
_manifest_config_git_infer_default_branch() {
    local branch=""
    branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
    if [ -n "$branch" ]; then
        echo "$branch"
        return 0
    fi

    branch=$(git config --get init.defaultBranch 2>/dev/null || echo "")
    if [ -n "$branch" ]; then
        echo "$branch"
        return 0
    fi

    echo "main"
}

_manifest_config_git_infer_repo_name() {
    local remote_url=""
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$remote_url" ]; then
        basename "$remote_url" .git
        return 0
    fi

    basename "$(pwd)"
}

_manifest_config_git_infer_org() {
    local remote_url=""
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$remote_url" ]; then
        echo ""
        return 0
    fi

    if [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/([^/]+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$remote_url" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    echo ""
}

_manifest_config_prompt_value() {
    local prompt="$1"
    local default_value="${2:-}"
    local user_input=""

    if [ -n "$default_value" ]; then
        read -r -p "$prompt [$default_value]: " user_input
    else
        read -r -p "$prompt: " user_input
    fi
    echo "${user_input:-$default_value}"
}

# -----------------------------------------------------------------------------
# Tier 3 #14 — review-and-confirm helper for the interactive wizard.
# Prints every value the user just entered grouped by section, then asks for
# a single y/N. Returns 0 to proceed, 1 to abort.
#
# Args (positional, in this exact order — keep in sync with caller):
#   1: config_file path (destination)
#   2-4: project: name, description, organization
#   5-9: git: default, feature, hotfix, release, bugfix
#  10-13: time: server1..4
#  14-17: time: timeout, retries, verify, timezone
#  18-19: docs: folder, archive
#  20-21: auto_update: enabled, cooldown
#  22-23: pr: profile, enforce_ready
#
# Bypassed (returns 0 immediately) when MANIFEST_CLI_AUTO_CONFIRM=1 — for CI
# / `manifest config --auto-confirm` use cases. The same env var the
# global-config gate honours, so users don't have to learn a second knob.
# -----------------------------------------------------------------------------
_manifest_config_review_and_confirm() {
    local config_file="$1"
    local project_name="$2" project_description="$3" organization="$4"
    local default_branch="$5" feature_prefix="$6" hotfix_prefix="$7" release_prefix="$8" bugfix_prefix="$9"
    shift 9
    local time_server1="$1" time_server2="$2" time_server3="$3" time_server4="$4"
    local time_timeout="$5" time_retries="$6" time_verify="$7" timezone="$8"
    shift 8
    local docs_folder="$1" docs_archive="$2" docs_limit="$3"
    local auto_update="$4" update_cooldown="$5"
    local pr_profile="$6" pr_enforce_ready="$7"

    echo ""
    echo "Review your settings"
    echo "===================="
    echo "Destination: $config_file"
    echo ""
    echo "Project:"
    printf "  %-30s %s\n" "name" "$project_name"
    printf "  %-30s %s\n" "description" "$project_description"
    printf "  %-30s %s\n" "organization" "$organization"
    echo ""
    echo "Git:"
    printf "  %-30s %s\n" "default_branch" "$default_branch"
    printf "  %-30s %s\n" "feature_prefix" "$feature_prefix"
    printf "  %-30s %s\n" "hotfix_prefix" "$hotfix_prefix"
    printf "  %-30s %s\n" "release_prefix" "$release_prefix"
    printf "  %-30s %s\n" "bugfix_prefix" "$bugfix_prefix"
    echo ""
    echo "Time:"
    printf "  %-30s %s\n" "server1" "$time_server1"
    printf "  %-30s %s\n" "server2" "$time_server2"
    printf "  %-30s %s\n" "server3" "$time_server3"
    printf "  %-30s %s\n" "server4" "$time_server4"
    printf "  %-30s %s\n" "timeout" "$time_timeout"
    printf "  %-30s %s\n" "retries" "$time_retries"
    printf "  %-30s %s\n" "verify" "$time_verify"
    printf "  %-30s %s\n" "timezone" "$timezone"
    echo ""
    echo "Docs / automation / PR:"
    printf "  %-30s %s\n" "docs.folder" "$docs_folder"
    printf "  %-30s %s\n" "docs.archive_folder" "$docs_archive"
    printf "  %-30s %s\n" "auto_update.enabled" "$auto_update"
    printf "  %-30s %s\n" "auto_update.cooldown" "$update_cooldown"
    printf "  %-30s %s\n" "pr.profile" "$pr_profile"
    printf "  %-30s %s\n" "pr.enforce_ready" "$pr_enforce_ready"
    echo ""

    if is_truthy "${MANIFEST_CLI_AUTO_CONFIRM:-0}"; then
        echo "MANIFEST_CLI_AUTO_CONFIRM=${MANIFEST_CLI_AUTO_CONFIRM} — proceeding without prompt."
        return 0
    fi

    local confirm
    read -r -p "Write these settings to $config_file? [y/N] " confirm
    case "$confirm" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

configure_interactive() {
    if [ ! -t 0 ]; then
        log_error "Interactive config requires a TTY. Use: manifest config show"
        return 1
    fi

    local config_file="$MANIFEST_CLI_PROJECT_ROOT/manifest.config.local.yaml"
    local inferred_repo_name inferred_org inferred_default_branch
    inferred_repo_name=$(_manifest_config_git_infer_repo_name)
    inferred_org=$(_manifest_config_git_infer_org)
    inferred_default_branch=$(_manifest_config_git_infer_default_branch)

    echo "🛠️  Manifest Config Setup"
    echo "========================="
    echo "This writes overrides to: $config_file"
    echo ""
    echo "Press Enter to keep each default."
    echo ""

    local project_name project_description organization
    local default_branch feature_prefix hotfix_prefix release_prefix bugfix_prefix
    local time_server1 time_server2 time_server3 time_server4 time_timeout time_retries time_verify timezone
    local docs_folder docs_archive
    local auto_update update_cooldown pr_profile pr_enforce_ready

    project_name=$(_manifest_config_prompt_value "Project name" "${MANIFEST_CLI_PROJECT_NAME:-$inferred_repo_name}")
    project_description=$(_manifest_config_prompt_value "Project description" "${MANIFEST_CLI_PROJECT_DESCRIPTION:-A powerful CLI tool for versioning, AI documenting, and repository operations}")
    organization=$(_manifest_config_prompt_value "Organization" "${MANIFEST_CLI_ORGANIZATION:-$inferred_org}")

    echo ""
    echo "Git settings:"
    default_branch=$(_manifest_config_prompt_value "Default branch" "${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-$inferred_default_branch}")
    feature_prefix=$(_manifest_config_prompt_value "Feature branch prefix" "${MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX:-feature/}")
    hotfix_prefix=$(_manifest_config_prompt_value "Hotfix branch prefix" "${MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX:-hotfix/}")
    release_prefix=$(_manifest_config_prompt_value "Release branch prefix" "${MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX:-release/}")
    bugfix_prefix=$(_manifest_config_prompt_value "Bugfix branch prefix" "${MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX:-bugfix/}")

    echo ""
    echo "Time server settings:"
    time_server1=$(_manifest_config_prompt_value "Time server 1" "${MANIFEST_CLI_TIME_SERVER1:-https://www.cloudflare.com/cdn-cgi/trace}")
    time_server2=$(_manifest_config_prompt_value "Time server 2" "${MANIFEST_CLI_TIME_SERVER2:-https://www.google.com/generate_204}")
    time_server3=$(_manifest_config_prompt_value "Time server 3" "${MANIFEST_CLI_TIME_SERVER3:-https://www.apple.com}")
    time_server4=$(_manifest_config_prompt_value "Time server 4" "${MANIFEST_CLI_TIME_SERVER4:-}")
    time_timeout=$(_manifest_config_prompt_value "Time server timeout (seconds)" "${MANIFEST_CLI_TIME_TIMEOUT:-5}")
    time_retries=$(_manifest_config_prompt_value "Time server retries" "${MANIFEST_CLI_TIME_RETRIES:-3}")
    time_verify=$(_manifest_config_prompt_value "Verify time server responses (true/false)" "${MANIFEST_CLI_TIME_VERIFY:-true}")
    timezone=$(_manifest_config_prompt_value "Timezone (IANA, e.g. UTC, America/New_York)" "${MANIFEST_CLI_TIMEZONE:-UTC}")

    echo ""
    echo "Docs + automation:"
    docs_folder=$(_manifest_config_prompt_value "Docs folder" "${MANIFEST_CLI_DOCS_FOLDER:-docs}")
    docs_archive=$(_manifest_config_prompt_value "Docs archive folder" "${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER:-docs/zArchive}")
    auto_update=$(_manifest_config_prompt_value "Auto-upgrade enabled (true/false)" "${MANIFEST_CLI_AUTO_UPDATE:-true}")
    update_cooldown=$(_manifest_config_prompt_value "Upgrade cooldown (minutes)" "${MANIFEST_CLI_UPDATE_COOLDOWN:-30}")

    echo ""
    echo "PR policy:"
    pr_profile=$(_manifest_config_prompt_value "PR profile (solo|team|regulated)" "${MANIFEST_CLI_PR_PROFILE:-solo}")
    pr_enforce_ready=$(_manifest_config_prompt_value "Enforce PR ready gate (true/false)" "${MANIFEST_CLI_PR_ENFORCE_READY:-true}")

    if ! [[ "$time_timeout" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid time server timeout '$time_timeout'; using existing/default value."
        time_timeout="${MANIFEST_CLI_TIME_TIMEOUT:-5}"
    fi
    if ! [[ "$time_retries" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid time server retries '$time_retries'; using existing/default value."
        time_retries="${MANIFEST_CLI_TIME_RETRIES:-3}"
    fi
    if ! [[ "$update_cooldown" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid upgrade cooldown '$update_cooldown'; using existing/default value."
        update_cooldown="${MANIFEST_CLI_UPDATE_COOLDOWN:-30}"
    fi

    # Review-and-confirm step (Tier 3 #14). Show every value the user just
    # entered, plus the destination file, before writing anything. One
    # fat-finger up to this point still costs zero — they can abort and re-run.
    if ! _manifest_config_review_and_confirm "$config_file" \
        "$project_name" "$project_description" "$organization" \
        "$default_branch" "$feature_prefix" "$hotfix_prefix" "$release_prefix" "$bugfix_prefix" \
        "$time_server1" "$time_server2" "$time_server3" "$time_server4" \
        "$time_timeout" "$time_retries" "$time_verify" "$timezone" \
        "$docs_folder" "$docs_archive" \
        "$auto_update" "$update_cooldown" \
        "$pr_profile" "$pr_enforce_ready"; then
        echo ""
        echo "Aborted. No changes written."
        return 1
    fi

    set_yaml_value "$config_file" "project.name" "$project_name"
    set_yaml_value "$config_file" "project.description" "$project_description"
    set_yaml_value "$config_file" "project.organization" "$organization"
    set_yaml_value "$config_file" "git.default_branch" "$default_branch"
    set_yaml_value "$config_file" "git.feature_prefix" "$feature_prefix"
    set_yaml_value "$config_file" "git.hotfix_prefix" "$hotfix_prefix"
    set_yaml_value "$config_file" "git.release_prefix" "$release_prefix"
    set_yaml_value "$config_file" "git.bugfix_prefix" "$bugfix_prefix"
    set_yaml_value "$config_file" "time.server1" "$time_server1"
    set_yaml_value "$config_file" "time.server2" "$time_server2"
    set_yaml_value "$config_file" "time.server3" "$time_server3"
    set_yaml_value "$config_file" "time.server4" "$time_server4"
    set_yaml_value "$config_file" "time.timeout" "$time_timeout"
    set_yaml_value "$config_file" "time.retries" "$time_retries"
    set_yaml_value "$config_file" "time.verify" "$time_verify"
    set_yaml_value "$config_file" "time.timezone" "$timezone"
    set_yaml_value "$config_file" "docs.folder" "$docs_folder"
    set_yaml_value "$config_file" "docs.archive_folder" "$docs_archive"
    set_yaml_value "$config_file" "auto_update.enabled" "$auto_update"
    set_yaml_value "$config_file" "auto_update.cooldown" "$update_cooldown"
    set_yaml_value "$config_file" "pr.profile" "$pr_profile"
    set_yaml_value "$config_file" "pr.enforce_ready" "$pr_enforce_ready"

    echo ""
    echo "✅ Saved configuration to $config_file"
    echo "ℹ️  Run 'manifest config show' to review effective values."
}

# Validate version format configuration
# Parse version components based on configuration
# Generate next version based on configuration
# Display current configuration
show_configuration() {
    echo "🔧 Manifest CLI Configuration"
    echo "=============================="
    echo ""
    
    echo "📋 Versioning Configuration:"
    echo "   Separator: ${MANIFEST_CLI_VERSION_SEPARATOR}"
    echo "   Components: ${MANIFEST_CLI_VERSION_COMPONENTS}"
    echo ""
    
    # Resolved from version.components, which is what the arithmetic actually
    # reads. This block used to print MANIFEST_CLI_*_COMPONENT_POSITION and
    # MANIFEST_CLI_*_INCREMENT_TARGET, which nothing has ever consulted: setting
    # version.component_position.major=3 made this screen report that `major`
    # increments the third segment while the bump still hit the first. Report
    # the mapping in force, never a value that merely looks like configuration.
    echo "🧠 Segment Mapping (name → position, from version.components):"
    local _cfg_names _cfg_i=0 _cfg_n
    if _cfg_names="$(manifest_version_components 2>/dev/null)"; then
        while IFS= read -r _cfg_n; do
            [ -n "$_cfg_n" ] || continue
            _cfg_i=$((_cfg_i + 1))
            echo "   ${_cfg_n}: segment ${_cfg_i}"
        done <<< "$_cfg_names"
        echo "   (leftmost = biggest impact; any segment is also addressable by number)"
    else
        echo "   ⚠️  version.components is unusable — see 'manifest config doctor'"
    fi
    echo ""
    
    echo "🌿 Branch Configuration:"
    echo "   Default Branch: ${MANIFEST_CLI_GIT_DEFAULT_BRANCH}"
    echo "   Feature Prefix: ${MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX}"
    echo "   Hotfix Prefix: ${MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX}"
    echo "   Release Prefix: ${MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX}"
    echo "   Bugfix Prefix: ${MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX}"
    echo "   Development Branch: ${MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH}"
    echo "   Staging Branch: ${MANIFEST_CLI_GIT_STAGING_BRANCH}"
    echo ""
    
    echo "🏷️  Git Configuration:"
    echo "   Tag Prefix: ${MANIFEST_CLI_GIT_TAG_PREFIX}"
    echo "   Tag Suffix: ${MANIFEST_CLI_GIT_TAG_SUFFIX}"
    echo "   Release Tag Target: ${MANIFEST_CLI_RELEASE_TAG_TARGET}"
    echo "   Release Gate: ${MANIFEST_CLI_RELEASE_GATE}"
    echo "   Release Gate Freshness: ${MANIFEST_CLI_RELEASE_GATE_FRESHNESS_DAYS} days"
    echo "   GitHub Release: ${MANIFEST_CLI_GITHUB_RELEASE_ENABLED}"
    echo "   Push Strategy: ${MANIFEST_CLI_GIT_PUSH_STRATEGY}"
    echo "   Pull Strategy: ${MANIFEST_CLI_GIT_PULL_STRATEGY}"
    echo "   Timeout: ${MANIFEST_CLI_GIT_TIMEOUT} seconds"
    echo "   Retries: ${MANIFEST_CLI_GIT_RETRIES} attempts"
    echo "   Remotes: Uses all configured git remotes automatically"
    echo ""

    echo "🕐 Time Server Configuration:"
    echo "   Server 1: ${MANIFEST_CLI_TIME_SERVER1}"
    echo "   Server 2: ${MANIFEST_CLI_TIME_SERVER2}"
    echo "   Server 3: ${MANIFEST_CLI_TIME_SERVER3}"
    echo "   Server 4: ${MANIFEST_CLI_TIME_SERVER4}"
    echo "   Timeout: ${MANIFEST_CLI_TIME_TIMEOUT} seconds"
    echo "   Retries: ${MANIFEST_CLI_TIME_RETRIES} attempts"
    echo "   Verify: ${MANIFEST_CLI_TIME_VERIFY}"
    echo ""
    
    echo "📚 Documentation Configuration:"
    echo "   Docs Folder: ${MANIFEST_CLI_DOCS_FOLDER}"
    echo "   Archive Folder: ${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER}"
    echo "   Retain: ${MANIFEST_CLI_DOCS_RETAIN}"
    echo "   Release Notes Provider: ${MANIFEST_CLI_RELEASE_NOTES_PROVIDER}"
    if [ -n "${MANIFEST_CLI_RELEASE_NOTES_COMMAND}" ]; then
        echo "   Release Notes Command: ${MANIFEST_CLI_RELEASE_NOTES_COMMAND}"
    fi
    echo ""
    
    echo "🏢 Project Configuration:"
    echo "   Project Name: ${MANIFEST_CLI_PROJECT_NAME}"
    echo "   Description: ${MANIFEST_CLI_PROJECT_DESCRIPTION}"
    echo "   Organization: ${MANIFEST_CLI_ORGANIZATION}"
    echo ""
    
    echo "📍 Installation Configuration:"
    echo "   Binary Location: ${BINARY_LOCATION:-Not set}"
    echo "   Install Location: ${MANIFEST_CLI_INSTALL_LOCATION:-Not set}"
    echo "   Project Root: ${MANIFEST_CLI_PROJECT_ROOT:-Not set}"
    echo ""
    
    echo "⚙️  Advanced Configuration:"
    echo "   Version Regex: ${MANIFEST_CLI_VERSION_REGEX}"
    echo "   Version Surface Detection: ${MANIFEST_CLI_VERSION_SURFACES_ENABLED}"
    echo "   Version Surface Catalog: ${MANIFEST_CLI_VERSION_HANDLER_CATALOG:-built-in}"
    echo "   Version Surface Depth: ${MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH}"
    echo "   Version Surface Notifications: ${MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE}"
    echo ""
    
    echo "🔄 Auto-Upgrade Configuration:"
    echo "   Auto-Upgrade: ${MANIFEST_CLI_AUTO_UPDATE}"
    echo "   Upgrade Cooldown: ${MANIFEST_CLI_UPDATE_COOLDOWN} minutes"
    echo "   Config Schema Version: ${MANIFEST_CLI_CONFIG_SCHEMA_VERSION}"
    echo ""
    
    echo "💡 How This Works:"
    echo "   • LEFT components = More MAJOR changes (bigger impact)"
    echo "   • RIGHT components = More MINOR changes (smaller impact)"
    echo "   • More digits after last dot = More specific/precise changes"
    echo "   • 'manifest ship repo <name>' increments that name's segment (see the mapping above)"
    echo "   • 'manifest ship repo <N>' increments segment N directly, named or not"
    echo "   • Bumping a segment clears every segment to its right"
    echo ""
    echo "Quick views:"
    echo "   • manifest config          # Interactive setup wizard"
    echo "   • manifest config show     # Full effective configuration"
    echo "   • manifest config time     # Time server configuration view"
    echo "   • manifest config doctor   # Drift/deprecation diagnostics"
}

# Get documentation folder path
get_docs_folder() {
    local project_root="$1"
    if [ -z "$project_root" ]; then
        project_root="$MANIFEST_CLI_PROJECT_ROOT"
    fi
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    echo "$project_root/$MANIFEST_CLI_DOCS_FOLDER"
}

# Get documentation archive folder path
get_docs_archive_folder() {
    local project_root="$1"
    if [ -z "$project_root" ]; then
        project_root="$MANIFEST_CLI_PROJECT_ROOT"
    fi
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    echo "$project_root/$MANIFEST_CLI_DOCS_ARCHIVE_FOLDER"
}

# Export functions for use in other modules
export -f load_configuration
export -f set_default_configuration
export -f show_configuration
export -f config_doctor
export -f configure_interactive
export -f _manifest_config_review_and_confirm
export -f get_docs_folder
export -f get_docs_archive_folder

# Note: Configuration loading is handled explicitly by the main CLI module
# to ensure proper initialization order and avoid duplicate loading
