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

manifest_execution_is_preview() {
    [[ "${1:-${MANIFEST_CLI_EXECUTION_MODE:-preview}}" == "preview" ]]
}

manifest_execution_is_apply() {
    [[ "${1:-${MANIFEST_CLI_EXECUTION_MODE:-preview}}" == "apply" ]]
}

manifest_execution_preview_header() {
    local label="$1"
    echo "Preview - no changes written: $label"
}

manifest_execution_apply_header() {
    echo "Applying because -y/--yes was provided."
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

manifest_execution_strip_apply_flags() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run|-y|--yes) ;;
            *) printf '%s\n' "$arg" ;;
        esac
    done
}

export -f manifest_execution_parse
export -f manifest_execution_is_preview
export -f manifest_execution_is_apply
export -f manifest_execution_preview_header
export -f manifest_execution_apply_header
export -f manifest_execution_footer
export -f manifest_execution_strip_apply_flags
