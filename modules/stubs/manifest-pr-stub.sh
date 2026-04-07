#!/bin/bash

# PR Module Stub
# Loaded when Manifest Cloud is not installed

[ -n "$_MANIFEST_PR_STUB_LOADED" ] && return 0
_MANIFEST_PR_STUB_LOADED=1

_manifest_pr_not_available() {
    log_warning "PR module requires Manifest Cloud."
    echo "  Install Manifest Cloud for PR support."
    return 1
}

manifest_pr_interactive()       { _manifest_pr_not_available; }
manifest_pr_create()            { _manifest_pr_not_available; }
manifest_pr_update()            { _manifest_pr_not_available; }
manifest_pr_status()            { _manifest_pr_not_available; }
manifest_pr_ready()             { _manifest_pr_not_available; }
manifest_pr_checks()            { _manifest_pr_not_available; }
manifest_pr_queue()             { _manifest_pr_not_available; }
manifest_pr_policy_show()       { _manifest_pr_not_available; }
manifest_pr_policy_validate()   { _manifest_pr_not_available; }
manifest_pr_help()              { _manifest_pr_not_available; }
manifest_fleet_pr_dispatch()    { _manifest_pr_not_available; }
normalize_pr_selector()         { _manifest_pr_not_available; }
