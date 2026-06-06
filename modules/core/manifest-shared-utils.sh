#!/bin/bash

# Manifest Shared Utilities Module
# Provides common functions, colors, and patterns used across all modules

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging configuration
MANIFEST_CLI_LOG_LEVEL="${MANIFEST_CLI_LOG_LEVEL:-INFO}"

# Logging levels (numeric for comparison)
MANIFEST_CLI_SHARED_LOG_LEVEL_DEBUG=0
MANIFEST_CLI_SHARED_LOG_LEVEL_INFO=1
MANIFEST_CLI_SHARED_LOG_LEVEL_WARN=2
MANIFEST_CLI_SHARED_LOG_LEVEL_ERROR=3

# Get current log level
get_log_level() {
    local level="$(echo "${MANIFEST_CLI_LOG_LEVEL}" | tr '[:lower:]' '[:upper:]')"
    case "$level" in
        DEBUG) echo $MANIFEST_CLI_SHARED_LOG_LEVEL_DEBUG ;;
        INFO)  echo $MANIFEST_CLI_SHARED_LOG_LEVEL_INFO ;;
        WARN)  echo $MANIFEST_CLI_SHARED_LOG_LEVEL_WARN ;;
        ERROR) echo $MANIFEST_CLI_SHARED_LOG_LEVEL_ERROR ;;
        *)     echo $MANIFEST_CLI_SHARED_LOG_LEVEL_INFO ;;
    esac
}

# Enhanced logging functions with levels
# Every log_* message is passed through manifest_redact so a token that slips
# into a log/error/verbose line is never printed verbatim.
log_debug() {
    if [[ $(get_log_level) -le $MANIFEST_CLI_SHARED_LOG_LEVEL_DEBUG ]]; then
        echo -e "${PURPLE}🐛 DEBUG: $(manifest_redact "$1")${NC}" >&2
    fi
}

log_info() {
    if [[ $(get_log_level) -le $MANIFEST_CLI_SHARED_LOG_LEVEL_INFO ]]; then
        echo -e "${BLUE}ℹ️  INFO: $(manifest_redact "$1")${NC}" >&2
    fi
}

log_success() {
    if [[ $(get_log_level) -le $MANIFEST_CLI_SHARED_LOG_LEVEL_INFO ]]; then
        echo -e "${GREEN}✅ SUCCESS: $(manifest_redact "$1")${NC}" >&2
    fi
}

log_warning() {
    if [[ $(get_log_level) -le $MANIFEST_CLI_SHARED_LOG_LEVEL_WARN ]]; then
        echo -e "${YELLOW}⚠️  WARN: $(manifest_redact "$1")${NC}" >&2
    fi
}

log_error() {
    if [[ $(get_log_level) -le $MANIFEST_CLI_SHARED_LOG_LEVEL_ERROR ]]; then
        echo -e "${RED}❌ ERROR: $(manifest_redact "$1")${NC}" >&2
    fi
}

log_trace() {
    if [[ $(get_log_level) -le $MANIFEST_CLI_SHARED_LOG_LEVEL_DEBUG ]]; then
        echo -e "${CYAN}🔍 TRACE: $(manifest_redact "$1")${NC}" >&2
    fi
}

# -----------------------------------------------------------------------------
# Config value normalization — forgiving grammar for YAML/env-driven settings.
# -----------------------------------------------------------------------------
# YAML config flows through MANIFEST_CLI_* env vars. Without normalization,
# a trailing space, a capital letter, or an alternate spelling silently fails
# the dispatch and falls back to defaults — invisible to the user.
#
# These helpers are the canonical answer:
#   - is_truthy   : 0 if the value means "yes/on" (1|true|yes|on, case-insensitive)
#   - is_falsy    : 0 if the value means "no/off" (0|false|no|off|empty, case-insensitive)
#   - normalize_enum_value : trim + lowercase, for closed-set enum dispatch
#
# All three trim leading/trailing whitespace and are case-insensitive.
# is_truthy/is_falsy are NOT strict inverses — "garbage" is neither truthy
# nor falsy; callers decide how to treat unknown values.
# -----------------------------------------------------------------------------

# Trim leading/trailing whitespace.  Echoes the trimmed value.
_trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Trim whitespace and lowercase.  Used by is_truthy/is_falsy and by enum
# dispatch sites that want forgiving config matching.
normalize_enum_value() {
    local s
    s="$(_trim_ws "$1")"
    printf '%s' "${s,,}"
}

# Returns 0 if $1 normalizes to a recognized truthy token, 1 otherwise.
# Recognized: 1, true, yes, on (case-insensitive, whitespace-tolerant).
is_truthy() {
    case "$(normalize_enum_value "${1:-}")" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Returns 0 if $1 normalizes to a recognized falsy token, 1 otherwise.
# Recognized: 0, false, no, off, empty string (case-insensitive,
# whitespace-tolerant).  Useful for "explicitly off" vs "unset" distinctions.
is_falsy() {
    case "$(normalize_enum_value "${1:-}")" in
        0|false|no|off|'') return 0 ;;
        *) return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Deprecation warning — single source of truth for legacy aliases.
# -----------------------------------------------------------------------------
# Args:
#   $1 — old name (e.g. "manifest update")
#   $2 — new name (e.g. "manifest upgrade")
#   $3 — optional context note (e.g. "syntax changed in v42")
#
# Behavior:
#   - Emits at most once per old name per session (tracked in the
#     MANIFEST_CLI_DEPRECATIONS_WARNED env var).
#   - Suppressed entirely when MANIFEST_CLI_QUIET_DEPRECATIONS=1.
#   - Always goes to stderr via log_warning so it never mixes with stdout.
# -----------------------------------------------------------------------------
log_deprecated() {
    is_truthy "${MANIFEST_CLI_QUIET_DEPRECATIONS:-0}" && return 0

    local old="$1"
    local new="$2"
    local note="${3:-}"

    # Idempotent per old-name. Use a delimited string instead of an
    # associative array so this works even when no `declare -gA` is in
    # scope yet (e.g. very early-loading callers).
    case ":${MANIFEST_CLI_DEPRECATIONS_WARNED:-}:" in
        *":${old}:"*) return 0 ;;
    esac
    export MANIFEST_CLI_DEPRECATIONS_WARNED="${MANIFEST_CLI_DEPRECATIONS_WARNED:-}:${old}"

    local msg="'${old}' is deprecated. Use '${new}' instead."
    [[ -n "$note" ]] && msg="${msg} (${note})"
    log_warning "${msg}  Silence with MANIFEST_CLI_QUIET_DEPRECATIONS=1"
}

# -----------------------------------------------------------------------------
# Subcommand help renderer — single source of truth for `manifest X --help`.
# -----------------------------------------------------------------------------
# Args:
#   $1 — usage line (e.g. "manifest ship repo <patch|minor|major|revision> [--local]")
#   $2 — description (1-3 lines; can contain embedded newlines)
#   $3+ — alternating "Section" "body" pairs. Body lines are emitted verbatim,
#         so callers control alignment. Common sections: "Options", "Scopes",
#         "Examples", "Flow".
#
# Example:
#   _render_help \
#       "manifest ship repo <patch|minor|major|revision> [--local] [-i]" \
#       "Publish a release: version bump, docs, commit, tag, push." \
#       "Options" "  --local            Local only (no tag, push, Homebrew)
#   -i|--interactive   Enable interactive safety prompts" \
#       "Examples" "  manifest ship repo patch
#   manifest ship repo minor --local"
# -----------------------------------------------------------------------------
_render_help() {
    local usage="$1"; shift
    local description="$1"; shift

    echo "Usage: $usage"
    echo ""
    printf '%s\n' "$description"

    while [[ $# -ge 2 ]]; do
        local heading="$1"; shift
        local body="$1"; shift
        echo ""
        echo "${heading}:"
        printf '%s\n' "$body"
    done
}

# -----------------------------------------------------------------------------
# Subcommand error renderer — emits "Unknown option" / "missing arg" plus usage.
# Always returns 1 so callers can `_render_help_error ... && return 1` or
# `_render_help_error ...; return $?`.
# -----------------------------------------------------------------------------
_render_help_error() {
    local message="$1"
    local usage="$2"
    log_error "$message"
    echo "Usage: $usage" >&2
    return 1
}

# -----------------------------------------------------------------------------
# Short, portable hash for fingerprinting (NOT for security).
# Reads stdin, prints a hex digest. Uses md5 on macOS, md5sum on Linux,
# falls back to cksum if neither is installed.
# -----------------------------------------------------------------------------
_manifest_hash_short() {
    if command -v md5 >/dev/null 2>&1; then
        md5 -q
    elif command -v md5sum >/dev/null 2>&1; then
        md5sum | awk '{print $1}'
    else
        cksum | awk '{print $1}'
    fi
}

# -----------------------------------------------------------------------------
# Plan fingerprint — a stable, short digest of a release plan's salient inputs.
# Each argument is one plan field; order matters. The same fields produce the
# same fingerprint, so a preview and its later apply can be compared, and the
# future apply-event audit log can record exactly which plan was applied.
# Truncated to 12 hex chars — identification, not cryptographic integrity.
# Usage: manifest_plan_fingerprint "$increment_type" "$current" "$next" "$tag"
# -----------------------------------------------------------------------------
manifest_plan_fingerprint() {
    local digest
    digest="$(printf '%s\n' "$@" | _manifest_hash_short)"
    printf '%s' "${digest:0:12}"
}

# -----------------------------------------------------------------------------
# Shared plan-table renderer — one source of truth for the preview key/value
# rows and the fingerprint line, so ship/fleet/PR previews stop hand-rolling
# their own alignment and label wording (CLI tracker §2.2). Callers still
# choose WHICH fields to show; this only fixes how a field and the fingerprint
# line are rendered, keeping every surface visually consistent.
# -----------------------------------------------------------------------------
# A single "  Label: value" row, label left-padded to a shared column width.
manifest_plan_render_field() {
    printf '  %-17s %s\n' "${1}:" "${2}"
}

# The "Plan fingerprint: <hash>" row. Shared so the literal label never drifts
# between the surface that prints it at preview time and the apply-time drift
# check that re-reads it.
manifest_plan_render_fingerprint_line() {
    manifest_plan_render_field "Plan fingerprint" "${1}"
}

# -----------------------------------------------------------------------------
# Preview fingerprint persistence + apply-time drift warning (CLI tracker §2.2).
#
# At preview time we stash the fingerprint the user actually read under a
# repo-scoped run/status dir. At apply time we re-read it and warn (never block)
# if the freshly-recomputed fingerprint differs — i.e. the plan changed between
# the preview the user approved and the apply they authorized. Purely additive:
# a missing or unreadable stash is silent, so the historical apply path is
# unchanged when no preview was persisted.
# -----------------------------------------------------------------------------
# Run/status dir for a repo's persisted preview state. Lives under the same
# TTL-swept cache root as other scratch, keyed by the repo's git root so two
# checkouts never collide. $1 = repo root (defaults to PROJECT_ROOT/PWD).
manifest_plan_run_dir() {
    local repo_root="${1:-${PROJECT_ROOT:-$PWD}}"
    local git_root key root
    git_root="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null || echo "$repo_root")"
    key="$(printf '%s' "$git_root" | _manifest_hash_short)"
    root="${TMPDIR:-/tmp}/manifest-cli/run/${key}"
    mkdir -p "$root" 2>/dev/null || return 1
    printf '%s' "$root"
}

# Persist the previewed fingerprint for a named plan kind (e.g. "ship-repo").
# $1 = plan kind, $2 = fingerprint, $3 = repo root (optional). Best-effort.
manifest_plan_fingerprint_persist() {
    local kind="$1" fingerprint="$2" repo_root="${3:-${PROJECT_ROOT:-$PWD}}"
    [[ -n "$kind" && -n "$fingerprint" ]] || return 0
    local dir
    dir="$(manifest_plan_run_dir "$repo_root")" || return 0
    printf '%s\n' "$fingerprint" > "${dir}/${kind}.fingerprint" 2>/dev/null || return 0
    return 0
}

# At apply time, compare the recomputed fingerprint against the persisted one.
# $1 = plan kind, $2 = recomputed fingerprint, $3 = repo root (optional).
# Warns to stderr when they differ; silent when no preview was persisted or the
# fingerprints match. Always returns 0 — this is advisory, not a gate.
manifest_plan_fingerprint_warn_on_drift() {
    local kind="$1" current="$2" repo_root="${3:-${PROJECT_ROOT:-$PWD}}"
    [[ -n "$kind" && -n "$current" ]] || return 0
    local dir file previewed
    dir="$(manifest_plan_run_dir "$repo_root")" || return 0
    file="${dir}/${kind}.fingerprint"
    [[ -r "$file" ]] || return 0
    previewed="$(tr -d '[:space:]' < "$file" 2>/dev/null)"
    [[ -n "$previewed" ]] || return 0
    if [[ "$previewed" != "$current" ]]; then
        log_warning "Plan changed since preview: previewed ${previewed}, applying ${current}. Re-preview to review the new plan."
    fi
    rm -f "$file" 2>/dev/null
    return 0
}

# -----------------------------------------------------------------------------
# Preview exit code — the single self-describing knob that lets CI wrappers
# distinguish "preview happened, no consent" from "applied successfully" (both
# historically exited 0). Config key preview.exit_code reads in English:
#   "zero"     -> previews exit 0 (the historical contract; the default)
#   "distinct" -> previews exit 10 ("preview happened, no consent")
# A bare integer is also honored. --dry-run and apply exit semantics are
# untouched: this only colors the no-consent preview return.
# -----------------------------------------------------------------------------
MANIFEST_CLI_PREVIEW_NO_CONSENT_EXIT_CODE=10

manifest_preview_exit_code() {
    case "$(normalize_enum_value "${MANIFEST_CLI_PREVIEW_EXIT_CODE:-zero}")" in
        ''|zero|0) printf '0' ;;
        distinct)  printf '%s' "$MANIFEST_CLI_PREVIEW_NO_CONSENT_EXIT_CODE" ;;
        *[!0-9]*)  printf '0' ;;  # unrecognized word -> safe historical default
        *)         printf '%s' "$(normalize_enum_value "${MANIFEST_CLI_PREVIEW_EXIT_CODE}")" ;;
    esac
}

# -----------------------------------------------------------------------------
# Secret redaction — keep tokens out of stdout/stderr, logs, and status files.
# -----------------------------------------------------------------------------
# Two layers: the exact values of known credential env vars (so a token leaks
# nothing even if its shape is unusual), plus token-shaped patterns (so a secret
# from an unknown source is still caught). Not a security boundary — defense in
# depth so an accidental echo/verbose-dump never prints a live credential.

# Names of env vars whose VALUES must never appear in output. Includes the var
# named by MANIFEST_CLI_CLOUD_API_KEY_ENV (the cloud key is indirected).
_manifest_redaction_env_var_names() {
    printf '%s\n' \
        GITHUB_TOKEN GH_TOKEN HOMEBREW_GITHUB_API_TOKEN \
        MANIFEST_CLI_CLOUD_API_KEY MANIFEST_CLI_CLOUD_API_TOKEN
    [ -n "${MANIFEST_CLI_CLOUD_API_KEY_ENV:-}" ] && printf '%s\n' "$MANIFEST_CLI_CLOUD_API_KEY_ENV"
    return 0
}

# Redact secrets from the single string argument; echoes the redacted text.
manifest_redact() {
    local text="${1-}"
    [ -n "$text" ] || { printf '%s' "$text"; return 0; }

    # Value-based: replace the exact value of each known credential env var.
    # Pure bash substitution (no fork) keeps this cheap on the logging hot path.
    local var val
    while IFS= read -r var; do
        [ -n "$var" ] || continue
        val="${!var-}"
        # Require a non-trivial length so a short/empty value can't over-redact.
        [ -n "$val" ] && [ "${#val}" -ge 8 ] && text="${text//"$val"/[REDACTED]}"
    done < <(_manifest_redaction_env_var_names)

    # Pattern-based: only fork sed when a token sigil is actually present.
    case "$text" in
        *gh[pousr]_*|*github_pat_*|*AKIA*|*sk-*|*eyJ*|*[Bb]earer\ *)
            text="$(printf '%s' "$text" | sed -E \
                -e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED]/g' \
                -e 's/gh[pousr]_[A-Za-z0-9]{20,}/[REDACTED]/g' \
                -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \
                -e 's/sk-[A-Za-z0-9]{20,}/[REDACTED]/g' \
                -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED]/g' \
                -e 's/([Bb]earer )[A-Za-z0-9._-]{12,}/\1[REDACTED]/g')"
            ;;
    esac
    printf '%s' "$text"
}

# -----------------------------------------------------------------------------
# JSON helpers — minimal hand-rolled emitters so --json works without jq.
# We only support the small subset of JSON the CLI actually emits: strings,
# numbers/booleans/null (caller-classified), and flat arrays/objects.
# -----------------------------------------------------------------------------

# Escape a string for inclusion as a JSON string literal.
# Echoes the escaped value WITHOUT surrounding quotes.
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"     # backslash first
    s="${s//\"/\\\"}"     # double quote
    s="${s//$'\n'/\\n}"   # newline
    s="${s//$'\r'/\\r}"   # carriage return
    s="${s//$'\t'/\\t}"   # tab
    # Any remaining C0 control byte must be \u-escaped (RFC 8259) or the line is
    # invalid JSON — matters for the apply-event audit log, whose value is being
    # machine-parseable. Only pay the per-char loop when one is actually present;
    # the common path (no control bytes) skips it entirely.
    if [[ "$s" == *[$'\x01'-$'\x1f']* ]]; then
        local out="" c i
        for (( i=0; i<${#s}; i++ )); do
            c="${s:i:1}"
            [[ "$c" == [$'\x01'-$'\x1f'] ]] && printf -v c '\\u%04x' "'$c"
            out+="$c"
        done
        s="$out"
    fi
    printf '%s' "$s"
}

# Emit `"key":"value"` with the value quoted-and-escaped. Caller handles
# trailing commas if any.
_json_kv_str() {
    printf '"%s":"%s"' "$(_json_escape "$1")" "$(_json_escape "$2")"
}

# Emit `"key":<value>` raw — for booleans, numbers, or pre-built JSON.
_json_kv_raw() {
    printf '"%s":%s' "$(_json_escape "$1")" "$2"
}

# Detect whether a value should be JSON-classified as bool/null/number, else
# fall through to a quoted string. Echoes the JSON form.
_json_value() {
    local v="$1"
    case "$v" in
        true|false|null) printf '%s' "$v" ;;
        '') printf '""' ;;
        *)
            if [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                printf '%s' "$v"
            else
                printf '"%s"' "$(_json_escape "$v")"
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Apply-event audit log (CLI tracker §5.8). Append-only NDJSON record of every
# apply that crosses the apply boundary: who authorized which plan, when, and
# whether the authorization succeeded. This is the *who-authorized-what-when*
# compliance record; per-run diagnostic logs (§5.6) are the separate
# *what-happened-for-debug* record. Mirrors workspace cross-cut §1.2.
#
# One line per apply attempt. Every string field is routed through
# manifest_redact so no token-shaped value can land in the audit log. The log
# lives under the preserved global-state dir (in preserved_subdirs, so an
# upgrade swap never wipes it; NOT under manifest_install_paths_cache_dirs, so
# the runtime cache sweep never collects it). Best-effort: a failure to write
# the audit line must never abort the apply, so every error path returns 0.
#
# Two events are emitted per apply (CLI tracker §8.3a): an "authorized" event at
# the apply guard recording who authorized which plan and whether the
# *confirmation* succeeded, and a "completed" event after the workflow runs
# carrying the REAL workflow rc. An auditor reading only the authorization event
# would see a clean success for a ship that later failed at push/gate; the
# completion event closes that gap. The optional gate_status field (§8.3b)
# records the release-gate disposition (none/unverified/verified-local/...) so a
# fail-open or env-var bypass is observable in the durable log.
#
# Usage: manifest_audit_apply_event SOURCE COMMAND SCOPE PLAN_HASH EXIT_STATUS \
#                                   [EVENT] [GATE_STATUS]
#   EVENT       defaults to "authorized" (the pre-apply guard event); the
#               completion path passes "completed".
#   GATE_STATUS optional release-gate disposition; emitted only when non-empty.
# Existing 5-arg callers are unchanged: EVENT/GATE_STATUS are trailing optionals.
# -----------------------------------------------------------------------------
manifest_audit_apply_event() {
    local event_source="$1" command="$2" scope="$3" plan_hash="$4" exit_status="$5"
    local event="${6:-authorized}" gate_status="${7:-}"
    local actor ts state_dir audit_dir audit_file line

    actor="${MANIFEST_CLI_ACTOR:-${USER:-$(id -un 2>/dev/null || echo unknown)}}"
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    if declare -F manifest_install_paths_global_state_dir >/dev/null 2>&1; then
        state_dir="$(manifest_install_paths_global_state_dir)"
    else
        state_dir="$HOME/.manifest-cli"
    fi
    audit_dir="$state_dir/audit"
    audit_file="$audit_dir/apply-events.ndjson"
    # The audit log is the compliance record a missed token shape would sit in,
    # so lock it down (§8.3d): dir 0700, file 0600. umask 077 in a subshell makes
    # the create-with-mode atomic (no 0644 window). Best-effort: a umask/mkdir
    # failure must never abort the apply (the "audit never aborts a ship"
    # contract), and chmod after the fact repairs a dir that pre-existed 0755.
    ( umask 077; mkdir -p "$audit_dir" ) 2>/dev/null || return 0
    chmod 700 "$audit_dir" 2>/dev/null || true

    # Single O_APPEND write of one short line: atomic on local POSIX filesystems
    # regardless of PIPE_BUF (that governs pipes, not regular-file appends).
    # Fleet ship is sequential, so the only concurrency is independent manifest
    # processes; on a network filesystem append-atomicity is not guaranteed.

    line="{$(_json_kv_str "ts" "$ts"),"
    line+="$(_json_kv_str "actor" "$(manifest_redact "$actor")"),"
    line+="$(_json_kv_str "source" "$(manifest_redact "$event_source")"),"
    line+="$(_json_kv_str "event" "$(manifest_redact "$event")"),"
    line+="$(_json_kv_str "command" "$(manifest_redact "$command")"),"
    line+="$(_json_kv_str "scope" "$(manifest_redact "$scope")"),"
    line+="$(_json_kv_str "plan_hash" "$(manifest_redact "$plan_hash")"),"
    # Gate disposition is part of the completion record; emit only when present
    # so the authorization event's shape is unchanged for existing consumers.
    if [ -n "$gate_status" ]; then
        line+="$(_json_kv_str "gate_status" "$(manifest_redact "$gate_status")"),"
    fi
    line+="$(_json_kv_raw "exit_status" "$(_json_value "$exit_status")")}"

    # Create the file 0600 before the first append (umask 077 covers the touch),
    # so the record is never world-readable even for a single write window.
    if [ ! -e "$audit_file" ]; then
        ( umask 077; : >> "$audit_file" ) 2>/dev/null || true
        chmod 600 "$audit_file" 2>/dev/null || true
    fi
    printf '%s\n' "$line" >> "$audit_file" 2>/dev/null || return 0
    return 0
}

# -----------------------------------------------------------------------------
# Per-run diagnostic ship log (CLI tracker §5.6). A timestamped plain-text log
# of one ship run — each step boundary, the step's exit status, and any captured
# stderr — so when a ship leaves the install or repo in an unexpected state,
# diagnosis is "read the file" instead of guessing from git log + brew Cellar
# timestamps. This is the *what-happened-for-debug* record; the apply-event
# audit log above is the separate *who-authorized-what-when* compliance record.
#
# The log lives under manifest_install_paths_logs_dir() — in preserved_subdirs
# (an upgrade swap never wipes it) and deliberately NOT under
# manifest_install_paths_cache_dirs (the TTL-gated runtime cache sweep must
# never collect a forensic log). Growth is bounded by keep-last-N rotation
# (manifest_ship_log_rotate), not by the cache sweep.
#
# Every line that can carry interpolated values — step labels and captured
# stderr — is routed through manifest_redact so a token-shaped value can never
# land in the log. Best-effort throughout: a logging failure must never abort a
# ship, so every error path returns 0. The active log path is carried in
# MANIFEST_CLI_SHIP_LOG_FILE for the duration of the run.
# -----------------------------------------------------------------------------

# Resolve the logs dir, tolerating shared-utils being sourced before
# install-paths (mirrors the audit emitter's fallback).
_manifest_ship_log_dir() {
    if declare -F manifest_install_paths_logs_dir >/dev/null 2>&1; then
        manifest_install_paths_logs_dir
    else
        echo "$HOME/.manifest-cli/logs"
    fi
}

# Number of past ship logs to retain. One self-describing knob: an integer count
# of runs to keep. <1 disables rotation (keep everything).
MANIFEST_CLI_SHIP_LOG_KEEP=${MANIFEST_CLI_SHIP_LOG_KEEP:-20}

# Begin a per-run log. Echoes the log path (also exported as
# MANIFEST_CLI_SHIP_LOG_FILE) so the caller can reference it; returns 0 even if
# the file can't be created so a ship never aborts on logging.
# Usage: manifest_ship_log_begin COMMAND
manifest_ship_log_begin() {
    local command="$1"
    local dir ts file
    dir="$(_manifest_ship_log_dir)"
    # Diagnostic logs can carry captured stderr that a missed redaction pattern
    # left token-shaped, so lock them down like the audit log (§8.3d): dir 0700,
    # files 0600, created with mode under umask 077 to avoid a 0644 window.
    # Best-effort: a perm failure must never abort a ship.
    ( umask 077; mkdir -p "$dir" ) 2>/dev/null || { export MANIFEST_CLI_SHIP_LOG_FILE=""; return 0; }
    chmod 700 "$dir" 2>/dev/null || true
    # ship-<ts> sorts logs by start time. The date stamp is only second-resolved,
    # so a PID + $RANDOM suffix guarantees uniqueness when two runs start in the
    # same second (e.g. a ship and its auto-followup-patch) — otherwise they
    # would append into one file and the diagnostic record would conflate runs.
    ts="$(date -u +"%Y%m%dT%H%M%SZ")"
    file="$dir/ship-${ts}-$$${RANDOM}.log"
    ( umask 077; : >> "$file" ) 2>/dev/null || true
    chmod 600 "$file" 2>/dev/null || true
    {
        printf 'ship-log v1\n'
        printf 'started: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf 'command: %s\n' "$(manifest_redact "$command")"
        printf 'actor:   %s\n' "$(manifest_redact "${MANIFEST_CLI_ACTOR:-${USER:-$(id -un 2>/dev/null || echo unknown)}}")"
        printf -- '---\n'
    } >> "$file" 2>/dev/null || { export MANIFEST_CLI_SHIP_LOG_FILE=""; return 0; }
    export MANIFEST_CLI_SHIP_LOG_FILE="$file"
    manifest_ship_log_rotate
    printf '%s' "$file"
    return 0
}

# Record a step boundary with its exit status and optional captured stderr.
# Usage: manifest_ship_log_step STEP EXIT_STATUS [CAPTURED_STDERR]
manifest_ship_log_step() {
    local step="$1" exit_status="$2" captured="${3:-}"
    local file="${MANIFEST_CLI_SHIP_LOG_FILE:-}"
    [ -n "$file" ] || return 0
    {
        printf '%s  step=%s  exit=%s\n' \
            "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            "$(manifest_redact "$step")" \
            "$exit_status"
        if [ -n "$captured" ]; then
            # Indent and redact every captured stderr line so no token leaks.
            while IFS= read -r line || [ -n "$line" ]; do
                printf '    stderr: %s\n' "$(manifest_redact "$line")"
            done <<< "$captured"
        fi
    } >> "$file" 2>/dev/null || return 0
    return 0
}

# Close out a per-run log with the overall result and the step it stopped at.
# Usage: manifest_ship_log_end RESULT [LAST_STEP]
manifest_ship_log_end() {
    local result="$1" last_step="${2:-}"
    local file="${MANIFEST_CLI_SHIP_LOG_FILE:-}"
    [ -n "$file" ] || return 0
    {
        printf -- '---\n'
        printf 'ended:   %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf 'result:  %s\n' "$(manifest_redact "$result")"
        [ -n "$last_step" ] && printf 'last_step: %s\n' "$(manifest_redact "$last_step")"
    } >> "$file" 2>/dev/null || return 0
    return 0
}

# Keep only the most recent MANIFEST_CLI_SHIP_LOG_KEEP ship logs; delete older
# ones. Tied to a TTL marker (rotate.last) so the prune runs at most once per
# MANIFEST_CLI_SHIP_LOG_ROTATE_PERIOD seconds — a burst of ships in one window
# doesn't re-scan the dir on every run. Best-effort; returns 0 always.
MANIFEST_CLI_SHIP_LOG_ROTATE_PERIOD=${MANIFEST_CLI_SHIP_LOG_ROTATE_PERIOD:-3600}
manifest_ship_log_rotate() {
    local keep="${MANIFEST_CLI_SHIP_LOG_KEEP:-20}"
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=20
    [ "$keep" -lt 1 ] && return 0

    local dir marker period now last
    dir="$(_manifest_ship_log_dir)"
    [ -d "$dir" ] || return 0
    marker="$dir/rotate.last"
    period="${MANIFEST_CLI_SHIP_LOG_ROTATE_PERIOD:-3600}"
    [[ "$period" =~ ^[0-9]+$ ]] || period=3600

    now="$(date -u +%s)"
    last=0
    if [ -f "$marker" ]; then
        last="$(tr -d '[:space:]' < "$marker" 2>/dev/null || echo 0)"
        [[ "$last" =~ ^[0-9]+$ ]] || last=0
    fi
    # period 0 disables the TTL gate (rotate every call) — used by tests.
    if [ "$period" -gt 0 ] && [ $((now - last)) -lt "$period" ]; then
        return 0
    fi

    # Newest-first by name (the ship-<ts> stamp sorts lexically by time); drop
    # everything past the keep count. The rotate marker itself is not a log.
    local f n=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        n=$((n + 1))
        [ "$n" -le "$keep" ] && continue
        rm -f "$f" 2>/dev/null || true
    done < <(find "$dir" -maxdepth 1 -type f -name 'ship-*.log' 2>/dev/null | sort -r)

    printf '%s\n' "$now" > "$marker" 2>/dev/null || true
    return 0
}

# Echo the path of the most recent prior ship log (newest by name), or nothing.
# Used by resume to report "picking up from step X" from the last run's record.
manifest_ship_log_latest() {
    local dir
    dir="$(_manifest_ship_log_dir)"
    [ -d "$dir" ] || return 0
    find "$dir" -maxdepth 1 -type f -name 'ship-*.log' 2>/dev/null | sort -r | head -n1
    return 0
}

# Echo the last recorded step label from a ship log, for resume's "picking up
# from step X" report. Reads the trailing `last_step:` footer if present, else
# the final `step=` boundary line.
# Usage: manifest_ship_log_last_step LOGFILE
manifest_ship_log_last_step() {
    local file="$1"
    [ -n "$file" ] && [ -f "$file" ] || return 0
    local footer
    footer="$(grep '^last_step: ' "$file" 2>/dev/null | tail -n1)"
    if [ -n "$footer" ]; then
        printf '%s' "${footer#last_step: }"
        return 0
    fi
    local last
    last="$(grep '  step=' "$file" 2>/dev/null | tail -n1)"
    [ -n "$last" ] || return 0
    last="${last#*step=}"
    printf '%s' "${last%%  exit=*}"
    return 0
}

# Common validation functions
# Common path resolution utilities
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

get_script_parent_dir() {
    echo "$(dirname "$(get_script_dir)")"
}

get_project_root() {
    # Try to find project root by looking for VERSION file
    local current_dir="$(pwd)"
    local search_dir="$current_dir"
    
    # Search up to 5 levels for VERSION file
    for i in {1..5}; do
        if [[ -f "$search_dir/VERSION" ]]; then
            echo "$search_dir"
            return 0
        fi
        search_dir="$(dirname "$search_dir")"
    done
    
    # Fallback to current directory
    echo "$current_dir"
}

# Check if we're running from the installation directory
is_installation_directory() {
    local current_dir="$1"
    local install_location="${INSTALL_LOCATION:-$HOME/.manifest-cli}"

    if [ -z "$current_dir" ]; then
        current_dir="$(pwd)"
    fi

    # Check if current directory is the installation directory
    if [[ "$current_dir" == "$install_location" ]]; then
        return 0
    fi

    # Check if current directory is a subdirectory of installation directory
    if [[ "$current_dir" == "$install_location"/* ]]; then
        return 0
    fi

    # Also check legacy location for security
    local legacy_path="/usr/local/share/manifest-cli"
    if [[ "$current_dir" == "$legacy_path" ]] || [[ "$current_dir" == "$legacy_path"/* ]]; then
        return 0
    fi

    return 1
}

# Validate and ensure we're running from repository root
validate_repository_root() {
    local current_dir="$(pwd)"
    local git_root=""
    
    # SECURITY: Prevent running from installation directory
    if is_installation_directory "$current_dir"; then
        log_error "❌ SECURITY ERROR: Cannot run Manifest CLI from installation directory"
        log_error "   Installation directory: ${INSTALL_LOCATION:-$HOME/.manifest-cli}"
        log_error "   Current directory: $current_dir"
        log_error ""
        log_error "💡 Please run Manifest CLI from your project directory instead:"
        log_error "   cd /path/to/your/project"
        log_error "   manifest [command]"
        return 1
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a Git repository. Please run Manifest from within a Git repository."
        return 1
    fi
    
    # Get the git repository root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if check_string_empty "$git_root"; then
        log_error "Could not determine Git repository root"
        return 1
    fi
    
    # Check if current directory is the repository root
    if compare_strings "$current_dir" "!=" "$git_root"; then
        log_error "Manifest must be run from the repository root directory"
        log_error "Current directory: $current_dir"
        log_error "Repository root: $git_root"
        log_error ""
        log_error "Please run: cd \"$git_root\" && manifest $*"
        return 1
    fi
    
    # Additional validation: ensure we have a .git directory
    if ! check_directory_exists ".git"; then
        log_error "No .git directory found in current location"
        return 1
    fi
    
    log_debug "Repository root validation passed: $current_dir"
    return 0
}

# Ensure we're in repository root and change directory if needed
ensure_repository_root() {
    local current_dir="$(pwd)"
    local git_root=""
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a Git repository. Please run Manifest from within a Git repository."
        return 1
    fi
    
    # Get the git repository root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if check_string_empty "$git_root"; then
        log_error "Could not determine Git repository root"
        return 1
    fi
    
    # Check if current directory is the repository root
    if compare_strings "$current_dir" "!=" "$git_root"; then
        log_warning "Not running from repository root. Changing to repository root..."
        log_warning "From: $current_dir"
        log_warning "To: $git_root"
        
        # Change to repository root
        if ! cd "$git_root"; then
            log_error "Failed to change to repository root: $git_root"
            return 1
        fi
        
        log_success "Changed to repository root: $git_root"
    fi
    
    # Additional validation: ensure we have a .git directory
    if ! check_directory_exists ".git"; then
        log_error "No .git directory found in current location"
        return 1
    fi
    
    log_debug "Repository root ensured: $(pwd)"
    return 0
}

manifest_repo_scope_require_git() {
    local replay_command="${1:-manifest status repo}"
    local current_dir
    current_dir="$(pwd)"

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    log_error "repo scope requires running inside a Git repository."
    log_error "Current directory: $current_dir"
    log_error ""
    log_error "Run from the intended repository folder:"
    log_error "  cd /path/to/repo"
    log_error "  $replay_command"
    return 1
}

manifest_git_preflight_write_access() {
    local project_root="${1:-${PROJECT_ROOT:-$(pwd)}}"
    local operation="${2:-manifest apply}"
    local index_lock probe_dir probe_file

    if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Cannot verify Git write access outside a Git work tree."
        log_error "Operation: $operation"
        return 1
    fi

    index_lock="$(git -C "$project_root" rev-parse --git-path index.lock 2>/dev/null || true)"
    probe_dir="$(git -C "$project_root" rev-parse --git-path "manifest-preflight-write-$$-${RANDOM}" 2>/dev/null || true)"
    if [[ -z "$index_lock" || -z "$probe_dir" ]]; then
        log_error "Could not resolve Git metadata paths before apply."
        log_error "Operation: $operation"
        return 1
    fi

    case "$index_lock" in
        /*) ;;
        *) index_lock="$project_root/$index_lock" ;;
    esac
    case "$probe_dir" in
        /*) ;;
        *) probe_dir="$project_root/$probe_dir" ;;
    esac
    probe_file="$probe_dir/probe"

    if [[ -e "$index_lock" ]]; then
        log_error "Git index lock already exists; refusing to mutate files before Git can commit."
        log_error "Lock path: $index_lock"
        log_error "Operation: $operation"
        return 1
    fi

    # Probe Git metadata writability by creating a uniquely-named subdir + file
    # under .git/. Do NOT probe by writing to .git/index.lock — that's a real
    # Git lock; clobbering it (or leaking it on cleanup failure) would block
    # subsequent git operations. If .git/ is writable and index.lock does not
    # exist (checked above), git will be able to claim the lock when it needs to.
    if ! mkdir "$probe_dir" 2>/dev/null; then
        log_error "Git metadata is not writable; refusing to mutate files before Git can commit."
        log_error "Probe path: $probe_dir"
        log_error "Operation: $operation"
        log_error "Run release/apply commands outside restrictive execution sandboxes, or grant the command Git write access."
        return 1
    fi

    if ! : > "$probe_file" 2>/dev/null; then
        rm -rf "$probe_dir" 2>/dev/null || true
        log_error "Git metadata probe file could not be written."
        log_error "Probe path: $probe_file"
        log_error "Operation: $operation"
        return 1
    fi

    if ! rm -f "$probe_file" 2>/dev/null || ! rmdir "$probe_dir" 2>/dev/null; then
        log_error "Git metadata preflight cleanup failed; refusing to continue before mutation."
        log_error "Probe path: $probe_dir"
        log_error "Operation: $operation"
        return 1
    fi
    return 0
}

# Consent model C: is the apply target unambiguous enough to auto-confirm in a
# non-interactive context (after apply intent was given via -y)? Returns 0 iff:
#   * HEAD is a NAMED branch (not detached). `symbolic-ref --short -q HEAD`
#     prints the branch name even for an unborn branch on a fresh `git init`
#     (e.g. "main" with no commits) — that counts as unambiguous. Detached HEAD
#     prints nothing → ambiguous.
#   * if origin_required is true: `git remote get-url origin` succeeds (a
#     non-empty origin remote exists).
# git-root existence is guaranteed by the manifest_repo_scope_require_git call
# at the top of the gate, so it is not re-checked here.
manifest_repo_scope_target_unambiguous() {
    local git_root="$1"
    local origin_required="${2:-true}"
    local head_ref

    head_ref="$(git -C "$git_root" symbolic-ref --short -q HEAD 2>/dev/null)"
    [[ -n "$head_ref" ]] || return 1

    if [[ "$origin_required" == "true" ]]; then
        git -C "$git_root" remote get-url origin >/dev/null 2>&1 || return 1
    fi
    return 0
}

manifest_repo_scope_confirm_apply() {
    local project_root="${1:-${PROJECT_ROOT:-$(pwd)}}"
    local replay_command="${2:-manifest command -y}"
    local origin_required="${3:-true}"
    local git_root branch origin answer

    if ! manifest_repo_scope_require_git "$replay_command"; then
        return 1
    fi

    git_root="$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null || echo "$project_root")"
    branch="$(git -C "$git_root" branch --show-current 2>/dev/null || echo "(detached)")"
    origin="$(git -C "$git_root" remote get-url origin 2>/dev/null || echo "(no origin remote)")"

    echo ""
    if declare -F manifest_repo_identity_block >/dev/null 2>&1; then
        manifest_repo_identity_block "$git_root"
        echo ""
    fi
    echo "Apply target repository"
    echo "-----------------------"
    echo "  Changes will be made to this Git repository only."
    echo "  Git root: $git_root"
    echo "  Origin:   $origin"
    echo "  Branch:   $branch"
    echo "  Command:  $replay_command"
    echo ""

    # Explicit override: authorize even an ambiguous target. Stays the escape
    # hatch for detached HEAD / no-origin non-interactive applies.
    if [[ "${MANIFEST_CLI_AUTO_CONFIRM:-0}" == "1" ]]; then
        echo "Auto-confirmed repository target (MANIFEST_CLI_AUTO_CONFIRM=1): $git_root"
        manifest_git_preflight_write_access "$git_root" "$replay_command"
        return $?
    fi

    # Non-interactive (no TTY to answer the target prompt). Under model C an
    # unambiguous target (named branch + origin when required) is auto-confirmed
    # on the strength of -y alone; an ambiguous one still refuses.
    if [[ ! -t 0 ]]; then
        if manifest_repo_scope_target_unambiguous "$git_root" "$origin_required"; then
            echo "Auto-confirmed unambiguous target (non-interactive apply via -y): $git_root"
            manifest_git_preflight_write_access "$git_root" "$replay_command"
            return $?
        fi
        log_error "Ambiguous apply target in a non-interactive context (no origin remote, or detached HEAD)."
        log_error "Run interactively to confirm, run from the intended repo, or set MANIFEST_CLI_AUTO_CONFIRM=1 to authorize explicitly."
        log_error "  Target: $git_root"
        return 1
    fi

    printf "Apply to this repository? [y/N] "
    read -r answer || return 1
    case "$answer" in
        y|Y|yes|YES|Yes)
            echo "Confirmed repository target: $git_root"
            manifest_git_preflight_write_access "$git_root" "$replay_command"
            return $?
            ;;
        *)
            log_error "Repository target was not confirmed; no changes written."
            return 1
            ;;
    esac
}

get_modules_dir() {
    local script_dir="$(get_script_dir)"
    # If we're in a module subdirectory, go up to modules root
    if [[ "$script_dir" == */modules/* ]]; then
        echo "$(dirname "$(dirname "$script_dir")")/modules"
    else
        echo "$script_dir/modules"
    fi
}

# Common file operations
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            return 1
        }
    fi
}

# Common help function pattern
# Standardized error message functions
show_file_error() {
    log_error "File operation failed: $1"
    return 1
}

show_git_error() {
    log_error "Git operation failed: $1"
    return 1
}

show_config_error() {
    log_error "Configuration error: $1"
    return 1
}

show_validation_error() {
    log_error "Validation failed: $1"
    return 1
}

show_permission_error() {
    log_error "Permission denied: $1"
    return 1
}

show_dependency_error() {
    log_error "Missing dependency: $1"
    echo "Please install $1 and try again"
    return 1
}

# Common error handling functions
show_usage_error() {
    local command="$1"
    log_error "Unknown command: $command"
    echo "Use '$0 help' for usage information"
    exit 1
}

show_required_arg_error() {
    local arg_name="$1"
    local usage="$2"
    log_error "$arg_name is required"
    echo "Usage: $0 $usage"
    return 1
}

# create_main_function() - Removed: unused function that generated boilerplate code

# Input sanitization and validation functions
sanitize_filename() {
    local filename="$1"
    # Remove dangerous characters and limit length
    echo "$filename" | sed 's/[^a-zA-Z0-9._-]//g' | cut -c1-255
}

sanitize_version() {
    local version="$1"
    # Only allow alphanumeric, dots, and hyphens
    echo "${version//[^a-zA-Z0-9.-]/}"
}

sanitize_path() {
    local path="$1"
    # Remove path traversal attempts and normalize
    path="${path//../}"
    path="${path//\/\//\/}"
    path="${path#//}"
    echo "$path"
}

validate_version_format() {
    local version="$1"
    local pattern="${MANIFEST_CLI_VERSION_REGEX:-^[0-9]+(\.[0-9]+)*$}"
    
    # Skip validation for template patterns
    if [[ "$version" == *"X"* ]] || [[ "$version" == *"XX"* ]]; then
        log_debug "Skipping validation for template version: $version"
        return 0
    fi
    
    if [[ ! "$version" =~ $pattern ]]; then
        show_validation_error "Invalid version format: $version (expected pattern: $pattern)"
        return 1
    fi
    return 0
}

validate_file_exists() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        show_file_error "File not found: $file"
        return 1
    fi
    return 0
}

validate_directory_exists() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        show_file_error "Directory not found: $dir"
        return 1
    fi
    return 0
}

# Export functions for use in other modules
export -f log_debug log_info log_success log_warning log_error log_trace
export -f ensure_directory
export -f show_usage_error show_required_arg_error
export -f _trim_ws normalize_enum_value is_truthy is_falsy
export -f _render_help _render_help_error _manifest_hash_short manifest_plan_fingerprint
export -f manifest_plan_render_field manifest_plan_render_fingerprint_line
export -f manifest_plan_run_dir manifest_plan_fingerprint_persist manifest_plan_fingerprint_warn_on_drift
export -f manifest_preview_exit_code
export -f manifest_redact _manifest_redaction_env_var_names
export -f _json_escape _json_kv_str _json_kv_raw _json_value
export -f manifest_audit_apply_event
export -f _manifest_ship_log_dir manifest_ship_log_begin manifest_ship_log_step
export -f manifest_ship_log_end manifest_ship_log_rotate
export -f manifest_ship_log_latest manifest_ship_log_last_step
export -f get_script_dir get_script_parent_dir get_project_root get_modules_dir
export -f is_installation_directory validate_repository_root ensure_repository_root
export -f manifest_repo_scope_require_git manifest_git_preflight_write_access manifest_repo_scope_confirm_apply manifest_repo_scope_target_unambiguous
export -f show_file_error show_git_error show_config_error
export -f show_validation_error show_permission_error show_dependency_error
export -f sanitize_filename sanitize_version sanitize_path validate_version_format
export -f validate_file_exists validate_directory_exists
