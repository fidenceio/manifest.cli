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