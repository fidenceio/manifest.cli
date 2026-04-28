#!/bin/bash

# PR Module Stub
#
# Loaded LAST in the PR module chain. Uses type-guards so it only defines
# functions that no earlier loader (native or Cloud plugin) provided.
# In practice this means: if a function reaches the stub, neither the native
# gh wrapper nor a Cloud plugin implements it — and we tell the user.

[ -n "$_MANIFEST_PR_STUB_LOADED" ] && return 0
_MANIFEST_PR_STUB_LOADED=1

_manifest_pr_not_available() {
    log_warning "PR feature requires Manifest Cloud."
    echo "  Install Manifest Cloud for queue / policy / advanced PR support."
    return 1
}

# Define-if-missing — native + Cloud both load before this and may override.
_pr_def() {
    local fn="$1"
    if ! type "$fn" &>/dev/null; then
        eval "$fn() { _manifest_pr_not_available; }"
    fi
}

_pr_def manifest_pr_interactive
_pr_def manifest_pr_create
_pr_def manifest_pr_update
_pr_def manifest_pr_status
_pr_def manifest_pr_ready
_pr_def manifest_pr_checks
_pr_def manifest_pr_merge
_pr_def manifest_pr_queue
_pr_def manifest_pr_policy_show
_pr_def manifest_pr_policy_validate
_pr_def manifest_pr_help
_pr_def manifest_fleet_pr_dispatch
_pr_def normalize_pr_selector
