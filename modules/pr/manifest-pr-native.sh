#!/bin/bash

# =============================================================================
# Manifest PR — Native Module (Tier 4 #23)
# =============================================================================
#
# Implements `manifest pr` basic operations as thin wrappers over `gh` (the
# GitHub CLI). PR workflows do not require Manifest Cloud — they're git
# operations that gh already handles.
#
# Provides:
#   pr create, pr status, pr checks, pr ready, pr merge, pr update
#
# Cloud plugin (when installed) may override any of these and additionally
# provides Cloud-only features (pr queue, pr policy).
#
# This module is loaded BEFORE the Cloud plugin and BEFORE the stub. Both
# subsequent loaders use type-guards so they only fill gaps left by native.
# =============================================================================

if [[ -n "${_MANIFEST_PR_NATIVE_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_PR_NATIVE_LOADED=1

# Internal: confirm we're inside a git repo with a remote that gh recognizes.
#
# gh installation + auth is handled by the shared `_manifest_require_gh`
# (in modules/core/manifest-shared-functions.sh), which adds TTL memoization
# and a real `gh auth status` pre-check vs. the legacy install-only probe.
_pr_require_repo() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Not inside a git repository."
        return 1
    fi
    if ! gh repo view --json name >/dev/null 2>&1; then
        log_error "gh cannot identify the repo. Set a GitHub remote or run 'gh auth login'."
        return 1
    fi
    return 0
}

# Internal: emit one apply-event audit record for a -y-gated PR mutation
# (CLI tracker §5.9). PR ops never reach the ship apply guard
# (manifest_execution_require_apply), so each PR apply boundary emits directly
# with MANIFEST_CLI_AUDIT_SOURCE=cli-pr. PR ops carry no version plan, so the
# plan_hash field is empty (the consumer tolerates an empty plan_hash). Scope
# is the repo's git root, mirroring the ship guard. Best-effort: the emitter
# itself never aborts, and we run after the gh call so $? is the gh exit code.
_pr_audit_apply() {
    local command="$1" exit_status="$2" git_root
    declare -F manifest_audit_apply_event >/dev/null 2>&1 || return 0
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
    MANIFEST_CLI_AUDIT_SOURCE="cli-pr" manifest_audit_apply_event \
        "cli-pr" "$command" "$git_root" "" "$exit_status"
}

# -----------------------------------------------------------------------------
# manifest pr create [--draft] [--title <t>] [--body <b>] [--base <branch>]
# -----------------------------------------------------------------------------
manifest_pr_create() {
    local args=()
    local draft=false
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --draft)        draft=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest pr create [-y|--yes] [--dry-run] [--draft] [--title <t>] [--body <b>] [--base <branch>]" \
                    "Preview or create a pull request from the current branch via the GitHub CLI (gh).
Any flag not handled here is forwarded to 'gh pr create'." \
                    "Examples" "  manifest pr create
  manifest pr create -y
  manifest pr create --draft -y
  manifest pr create --title 'fix: foo' --body 'closes #123' -y"
                return 0
                ;;
            *)              args+=("$1"); shift ;;
        esac
    done

    local cmd=(gh pr create)
    [[ "$draft" == "true" ]] && cmd+=(--draft)
    # Default to filling title/body from commits if user didn't pass them.
    if ! printf '%s\n' "${args[@]}" | grep -q -- '--title\|--body\|--fill'; then
        cmd+=(--fill)
    fi
    cmd+=("${args[@]}")

    if [[ "$execution_mode" == "preview" ]]; then
        manifest_execution_preview_header "manifest pr create"
        echo "Would run: ${cmd[*]}"
        local replay_command="manifest pr create"
        [[ "$draft" == "true" ]] && replay_command="$replay_command --draft"
        [[ ${#args[@]} -gt 0 ]] && replay_command="$replay_command ${args[*]}"
        manifest_execution_footer "$replay_command -y"
        return "$(manifest_preview_exit_code)"
    fi

    manifest_execution_apply_header
    _manifest_require_gh || return 1
    _pr_require_repo || return 1
    echo "→ ${cmd[*]}"
    "${cmd[@]}"
    local rc=$?
    _pr_audit_apply "${cmd[*]}" "$rc"
    return $rc
}

# -----------------------------------------------------------------------------
# manifest pr status [<number-or-branch>]
# -----------------------------------------------------------------------------
manifest_pr_status() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest pr status [<number-or-branch>]" \
            "Show the current branch's PR by default; pass a number or branch to target another."
        return 0
    fi
    _manifest_require_gh || return 1
    _pr_require_repo || return 1
    if [[ $# -gt 0 ]]; then
        gh pr view "$@"
    else
        gh pr view
    fi
}

# -----------------------------------------------------------------------------
# manifest pr checks [<number-or-branch>] [--watch]
# -----------------------------------------------------------------------------
manifest_pr_checks() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest pr checks [<number-or-branch>] [--watch]" \
            "Show CI check status. Pass --watch to poll until complete."
        return 0
    fi
    _manifest_require_gh || return 1
    _pr_require_repo || return 1
    gh pr checks "$@"
}

# -----------------------------------------------------------------------------
# manifest pr ready [<number-or-branch>]
# -----------------------------------------------------------------------------
manifest_pr_ready() {
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest pr ready [-y|--yes] [--dry-run] [<number-or-branch>]" \
            "Mark a draft PR as ready for review."
        return 0
    fi
    if [[ "$execution_mode" == "preview" ]]; then
        manifest_execution_preview_header "manifest pr ready"
        echo "Would run: gh pr ready $*"
        manifest_execution_footer "manifest pr ready $* -y"
        return "$(manifest_preview_exit_code)"
    fi
    manifest_execution_apply_header
    _manifest_require_gh || return 1
    _pr_require_repo || return 1
    gh pr ready "$@"
    local rc=$?
    _pr_audit_apply "gh pr ready $*" "$rc"
    return $rc
}

# -----------------------------------------------------------------------------
# manifest pr merge [<number-or-branch>] [--squash|--merge|--rebase] [--auto]
# -----------------------------------------------------------------------------
manifest_pr_merge() {
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest pr merge [-y|--yes] [--dry-run] [<number-or-branch>] [--squash|--merge|--rebase] [--auto]" \
            "Merge a PR. Default is squash. --auto enables GitHub auto-merge once checks pass.
For richer queue/policy control, see Cloud's 'manifest pr queue'." \
            "Examples" "  manifest pr merge
  manifest pr merge -y
  manifest pr merge --merge -y
  manifest pr merge 123 --auto -y"
        return 0
    fi
    local args=("$@")
    if ! printf '%s\n' "${args[@]}" | grep -q -- '--squash\|--merge\|--rebase'; then
        args+=(--squash)
    fi
    if [[ "$execution_mode" == "preview" ]]; then
        manifest_execution_preview_header "manifest pr merge"
        echo "Would run: gh pr merge ${args[*]}"
        manifest_execution_footer "manifest pr merge ${args[*]} -y"
        return "$(manifest_preview_exit_code)"
    fi
    manifest_execution_apply_header
    _manifest_require_gh || return 1
    _pr_require_repo || return 1
    gh pr merge "${args[@]}"
    local rc=$?
    _pr_audit_apply "gh pr merge ${args[*]}" "$rc"
    return $rc
}

# -----------------------------------------------------------------------------
# manifest pr update [<number-or-branch>]
# -----------------------------------------------------------------------------
# Updates a PR's branch with the latest from base (rebase or merge).
manifest_pr_update() {
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest pr update [-y|--yes] [--dry-run] [<number-or-branch>] [--rebase|--merge]" \
            "Bring a PR branch up to date with its base."
        return 0
    fi
    if [[ "$execution_mode" == "preview" ]]; then
        manifest_execution_preview_header "manifest pr update"
        echo "Would run: gh pr update-branch $*"
        manifest_execution_footer "manifest pr update $* -y"
        return "$(manifest_preview_exit_code)"
    fi
    manifest_execution_apply_header
    _manifest_require_gh || return 1
    _pr_require_repo || return 1
    gh pr update-branch "$@"
    local rc=$?
    _pr_audit_apply "gh pr update-branch $*" "$rc"
    return $rc
}

# -----------------------------------------------------------------------------
# manifest pr (interactive entry — when invoked with no subcommand)
# -----------------------------------------------------------------------------
# Shows current branch's PR if it exists, otherwise prompts to create one.
manifest_pr_interactive() {
    _manifest_require_gh || return 1
    _pr_require_repo || return 1

    if gh pr view >/dev/null 2>&1; then
        echo "Current branch already has a PR:"
        echo ""
        gh pr view
        return 0
    fi

    echo "No PR exists for the current branch."
    if [[ -t 0 ]]; then
        printf "Preview a PR creation plan now? (y/N) "
        local ans
        read -r ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            manifest_pr_create
        fi
    else
        echo "Run 'manifest pr create' to create one."
    fi
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
manifest_pr_help() {
    cat <<'EOF'
Manifest PR — native (gh wrapper)

Usage:
  manifest pr                       Show current PR or prompt to create
  manifest pr create [-y|--yes] [--dry-run] [--draft]
                                     Preview or create a PR from current branch
  manifest pr status [<n|branch>]   View PR details
  manifest pr checks [<n|branch>]   Show CI check status (--watch to poll)
  manifest pr ready [-y|--yes] [--dry-run] [<n|branch>]
                                     Preview or mark a draft PR as ready
  manifest pr merge [-y|--yes] [--dry-run] [<n|branch>]
                                     Preview or merge a PR (defaults to squash)
  manifest pr update [-y|--yes] [--dry-run] [<n|branch>]
                                     Preview or update PR branch with base
  manifest pr fleet [queue|create|status|checks|ready]
                                     Fleet-wide PR operations

Cloud-only (requires Manifest Cloud):
  manifest pr queue                 Auto-merge orchestration
  manifest pr policy show|validate  Org policy enforcement

Most arguments are forwarded to the underlying 'gh' command.
Run 'gh pr <command> --help' for the full set of options.
EOF
}

export -f manifest_pr_create
export -f manifest_pr_status
export -f manifest_pr_checks
export -f manifest_pr_ready
export -f manifest_pr_merge
export -f manifest_pr_update
export -f manifest_pr_interactive
export -f manifest_pr_help
