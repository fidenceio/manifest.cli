#!/bin/bash

# =============================================================================
# Manifest Execution Policy
# =============================================================================
#
# Central contract for safe-by-default command execution:
#   default       -> preview
#   --dry-run     -> explicit preview
#   -y, --yes     -> apply
#   --local -y    -> apply local effects only
#
# MANIFEST_CLI_AUTO_CONFIRM intentionally does not imply apply. It only answers
# prompts after the user has explicitly selected apply mode.
# =============================================================================

if [[ -n "${_MANIFEST_EXECUTION_POLICY_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_EXECUTION_POLICY_LOADED=1

manifest_execution_parse() {
    local -n mode_ref="$1"
    local -n local_ref="$2"
    local -n remaining_ref="$3"
    shift 3

    local saw_dry_run=false
    local saw_yes=false
    local saw_local=false
    local remaining=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                saw_dry_run=true
                shift
                ;;
            -y|--yes)
                saw_yes=true
                shift
                ;;
            --local)
                saw_local=true
                shift
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    if [[ "$saw_dry_run" == "true" && "$saw_yes" == "true" ]]; then
        log_error "Cannot combine --dry-run with -y/--yes. Preview is already the default; remove --dry-run to apply."
        return 1
    fi

    local mode="preview"
    [[ "$saw_yes" == "true" ]] && mode="apply"

    mode_ref="$mode"
    local_ref="$saw_local"
    remaining_ref=("${remaining[@]}")
}

manifest_execution_preview_header() {
    local label="$1"
    echo "Preview - no changes written: $label"
}

manifest_execution_apply_header() {
    echo "Applying because -y/--yes was provided."
    # Lazy hook: modules loaded after execution-policy (e.g. manifest-config.sh)
    # can register _manifest_execution_apply_hook to perform apply-only writes
    # at the apply boundary — keeping preview commands side-effect-free without
    # coupling execution-policy.sh to those modules' internals.
    if declare -F _manifest_execution_apply_hook >/dev/null 2>&1; then
        _manifest_execution_apply_hook
    fi
}

# Build the apply replay hint for a base command: "<base> -y". Single source
# of truth so every preview footer and confirm prompt spells apply the same way.
manifest_execution_replay_hint() {
    local base="$1"
    printf '%s -y' "$base"
}

# Apply guard: in apply mode, require confirmation before mutating; no-op in
# preview mode. Centralizes the "if apply: confirm, abort on decline" block
# that ship/prep/refresh each carried, so the apply boundary stays uniform
# (and is the natural single place for the future apply-event audit log).
# Returns non-zero if apply was declined or write access failed.
manifest_execution_require_apply() {
    local mode="$1"
    local project_root="$2"
    local replay_hint="$3"
    local plan_hash="${4:-}"
    [[ "$mode" == "apply" ]] || return 0

    local rc git_root
    manifest_repo_scope_confirm_apply "$project_root" "$replay_hint"
    rc=$?

    # Audit every apply attempt that reached this boundary (CLI tracker §5.8):
    # record who authorized which plan, when, and whether authorization +
    # write-access preflight succeeded ($rc). Emitted here, the single
    # apply-guard, so each -y-gated repo apply emits exactly once. Source is
    # cli by default; fleet ship exports MANIFEST_CLI_AUDIT_SOURCE=cli-fleet so
    # its per-member applies are distinguishable. Best-effort — never alters $rc.
    if declare -F manifest_audit_apply_event >/dev/null 2>&1; then
        git_root="$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null || echo "$project_root")"
        manifest_audit_apply_event \
            "${MANIFEST_CLI_AUDIT_SOURCE:-cli}" \
            "$replay_hint" \
            "$git_root" \
            "$plan_hash" \
            "$rc"
    fi

    return $rc
}

manifest_execution_footer() {
    local apply_command="${1:-}"
    echo ""
    if [[ -n "$apply_command" ]]; then
        echo "No changes written. Re-run with -y to apply this plan:"
        echo "  $apply_command"
    else
        echo "No changes written. Re-run with -y to apply this plan."
    fi
}

export -f manifest_execution_parse
export -f manifest_execution_preview_header
export -f manifest_execution_apply_header
export -f manifest_execution_footer
export -f manifest_execution_replay_hint
export -f manifest_execution_require_apply
