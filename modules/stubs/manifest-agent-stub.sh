#!/bin/bash

# Agent Module Stub
# Loaded when Manifest Cloud is not installed

[ -n "$_MANIFEST_AGENT_STUB_LOADED" ] && return 0
_MANIFEST_AGENT_STUB_LOADED=1

agent_main() {
    log_warning "Manifest Agent requires Manifest Cloud."
    echo "  Install Manifest Cloud for agent support."
    return 1
}
