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

send_to_manifest_cloud()                { _manifest_cloud_not_available; }
configure_mcp_connection()              { _manifest_cloud_not_available; }
show_mcp_status()                       { _manifest_cloud_not_available; }
should_skip_cloud()                     { return 0; }
check_mcp_prerequisites_with_details()  { _manifest_cloud_not_available; }
send_mcp_request_with_retry()           { _manifest_cloud_not_available; }
prepare_mcp_context()                   { _manifest_cloud_not_available; }
process_mcp_response()                  { _manifest_cloud_not_available; }
test_mcp_connectivity()                 { _manifest_cloud_not_available; }
is_containerized_agent_available()      { return 1; }
send_via_containerized_agent()          { _manifest_cloud_not_available; }
fallback_to_local_docs()                { _manifest_cloud_not_available; }
