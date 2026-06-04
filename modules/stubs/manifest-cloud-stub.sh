#!/bin/bash

# Cloud / MCP Module Stub
# Loaded when Manifest Cloud is not installed

[ -n "$_MANIFEST_CLOUD_STUB_LOADED" ] && return 0
_MANIFEST_CLOUD_STUB_LOADED=1

_manifest_cloud_not_available() {
    log_warning "Manifest Cloud module not installed."
    echo "  Install Manifest Cloud for cloud features."
    return 1
}

# Apply-intent contract guard (workspace §1.1, CLI §3.1).
#
# Every Cloud-backed mutation must carry an explicit execution_mode=apply.
# Requests that omit the field — or that declare preview while asking the
# cloud to mutate — are rejected here, before any provider or analyzer runs.
# The check fails closed: an unset or unrecognized mode is treated as "not
# apply". This pins the contract on the stub now, so it is already enforced
# when §3.1 wires real Cloud calls and populates MANIFEST_CLI_CLOUD_EXECUTION_MODE
# from the parsed CLI execution mode.
manifest_cloud_require_apply_intent() {
    local execution_mode="${MANIFEST_CLI_CLOUD_EXECUTION_MODE:-}"
    if [[ "$execution_mode" != "apply" ]]; then
        log_error "Cloud request rejected: execution_mode=apply is required for cloud-backed mutation (got '${execution_mode:-unset}')."
        return 1
    fi
    return 0
}

send_to_manifest_cloud() {
    # Fail closed before reaching any provider/analyzer path.
    manifest_cloud_require_apply_intent || return $?
    _manifest_cloud_not_available
}

configure_mcp_connection()              { _manifest_cloud_not_available; }
show_mcp_status()                       { _manifest_cloud_not_available; }
