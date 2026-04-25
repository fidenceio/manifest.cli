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

# Internal: ensure gh is installed; print install hint and return 1 if not.
_pr_require_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        log_error "'gh' (GitHub CLI) is required for 'manifest pr'."
        log_error "Install: brew install gh   then: gh auth login"
        return 1
    fi
    return 0
}

# Internal: confirm we're inside a git repo with a remote that gh recognizes.
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

# -----------------------------------------------------------------------------
# manifest pr create [--draft] [--title <t>] [--body <b>] [--base <branch>]
# -----------------------------------------------------------------------------
manifest_pr_create() {
    _pr_require_gh || return 1
    _pr_require_repo || return 1

    local args=()
    local draft=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --draft)        draft=true; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: manifest pr create [--draft] [--title <t>] [--body <b>] [--base <branch>]

Creates a pull request from the current branch using the GitHub CLI (gh).
Any flag not handled here is forwarded to 'gh pr create'.
EOF
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

    echo "→ ${cmd[*]}"
    "${cmd[@]}"
}

# -----------------------------------------------------------------------------
# manifest pr status [<number-or-branch>]
# -----------------------------------------------------------------------------
manifest_pr_status() {
    _pr_require_gh || return 1
    _pr_require_repo || return 1
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: manifest pr status [<number-or-branch>]"
        echo "Shows the current branch's PR by default; pass a number or branch to target another."
        return 0
    fi
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
    _pr_require_gh || return 1
    _pr_require_repo || return 1
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: manifest pr checks [<number-or-branch>] [--watch]"
        echo "Shows CI check status. Pass --watch to poll until complete."
        return 0
    fi
    gh pr checks "$@"
}

# -----------------------------------------------------------------------------
# manifest pr ready [<number-or-branch>]
# -----------------------------------------------------------------------------
manifest_pr_ready() {
    _pr_require_gh || return 1
    _pr_require_repo || return 1
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: manifest pr ready [<number-or-branch>]"
        echo "Marks a draft PR as ready for review."
        return 0
    fi
    gh pr ready "$@"
}

# -----------------------------------------------------------------------------
# manifest pr merge [<number-or-branch>] [--squash|--merge|--rebase] [--auto]
# -----------------------------------------------------------------------------
manifest_pr_merge() {
    _pr_require_gh || return 1
    _pr_require_repo || return 1
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: manifest pr merge [<number-or-branch>] [--squash|--merge|--rebase] [--auto]

Merges a PR. Default is squash. --auto enables GitHub auto-merge once checks
pass. For richer queue/policy control, see Cloud's 'manifest pr queue'.
EOF
        return 0
    fi
    local args=("$@")
    if ! printf '%s\n' "${args[@]}" | grep -q -- '--squash\|--merge\|--rebase'; then
        args+=(--squash)
    fi
    gh pr merge "${args[@]}"
}

# -----------------------------------------------------------------------------
# manifest pr update [<number-or-branch>]
# -----------------------------------------------------------------------------
# Updates a PR's branch with the latest from base (rebase or merge).
manifest_pr_update() {
    _pr_require_gh || return 1
    _pr_require_repo || return 1
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: manifest pr update [<number-or-branch>] [--rebase|--merge]"
        echo "Brings a PR branch up to date with its base."
        return 0
    fi
    gh pr update-branch "$@"
}

# -----------------------------------------------------------------------------
# manifest pr (interactive entry — when invoked with no subcommand)
# -----------------------------------------------------------------------------
# Shows current branch's PR if it exists, otherwise prompts to create one.
manifest_pr_interactive() {
    _pr_require_gh || return 1
    _pr_require_repo || return 1

    if gh pr view >/dev/null 2>&1; then
        echo "Current branch already has a PR:"
        echo ""
        gh pr view
        return 0
    fi

    echo "No PR exists for the current branch."
    if [[ -t 0 ]]; then
        printf "Create one now? (y/N) "
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
  manifest pr create [--draft]      Create a PR from current branch
  manifest pr status [<n|branch>]   View PR details
  manifest pr checks [<n|branch>]   Show CI check status (--watch to poll)
  manifest pr ready [<n|branch>]    Mark a draft PR as ready
  manifest pr merge [<n|branch>]    Merge a PR (defaults to squash)
  manifest pr update [<n|branch>]   Update PR branch with base

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
