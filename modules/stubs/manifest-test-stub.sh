#!/bin/bash

# Test Module Stub
# Loaded when Manifest Cloud is not installed

[ -n "$_MANIFEST_TEST_STUB_LOADED" ] && return 0
_MANIFEST_TEST_STUB_LOADED=1

run_manifest_test() {
    log_warning "Test module requires Manifest Cloud."
    echo "  Install Manifest Cloud for extended diagnostics."
    echo ""
    echo "  Basic diagnostics available:"
    echo "    manifest version      Show CLI version"
    echo "    manifest config doctor  Detect config issues"
    return 1
}
