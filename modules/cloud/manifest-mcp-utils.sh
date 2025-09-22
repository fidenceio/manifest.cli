#!/bin/bash

# Manifest MCP Utilities Module
# Common utilities for MCP (Model Context Protocol) operations

# MCP Configuration
MCP_DEFAULT_ENDPOINT="https://api.manifest.cloud"
MCP_DEFAULT_TIMEOUT=30
MCP_DEFAULT_RETRIES=3

# Check if user wants to skip cloud operations
should_skip_cloud() {
    # Check environment variables for skip conditions
    if [ "${MANIFEST_CLOUD_SKIP:-false}" = "true" ]; then
        log_debug "Cloud operations skipped: MANIFEST_CLOUD_SKIP=true"
        return 0
    fi
    
    if [ "${MANIFEST_OFFLINE_MODE:-false}" = "true" ]; then
        log_debug "Cloud operations skipped: MANIFEST_OFFLINE_MODE=true"
        return 0
    fi
    
    return 1
}

# check_network_connectivity() and check_required_tools() - Now available from manifest-shared-functions.sh

# Check MCP prerequisites with detailed error reporting
check_mcp_prerequisites_with_details() {
    log_debug "Checking MCP prerequisites..."
    
    # Check if API key is configured
    if [ -z "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        log_error "MANIFEST_CLOUD_API_KEY is not set"
        log_info "Get your API key from: https://manifest.cloud/dashboard"
        log_info "Then set: export MANIFEST_CLOUD_API_KEY='your_api_key'"
        return 1
    fi
    
    # Check if endpoint is configured
    if [ -z "${MANIFEST_CLOUD_ENDPOINT:-}" ]; then
        log_debug "MANIFEST_CLOUD_ENDPOINT not set, using default: $MCP_DEFAULT_ENDPOINT"
        export MANIFEST_CLOUD_ENDPOINT="$MCP_DEFAULT_ENDPOINT"
    fi
    
    # Check network connectivity
    if ! check_network_connectivity; then
        log_warning "No network connectivity detected"
        return 0
    fi
    
    # Check required tools
    if ! check_required_tools; then
        return 1
    fi
    
    log_debug "MCP prerequisites check passed"
    return 0
}

# Send MCP request with retry logic
send_mcp_request_with_retry() {
    local mcp_context="$1"
    local attempt="$2"
    local endpoint="${MANIFEST_CLOUD_ENDPOINT:-$MCP_DEFAULT_ENDPOINT}"
    local timeout="${MCP_DEFAULT_TIMEOUT}"
    
    log_debug "Sending MCP request (attempt $attempt) to $endpoint"
    
    # Send request with timeout and retry logic
    local response
    response=$(curl -s --max-time "$timeout" \
        --retry 0 \
        --retry-delay 0 \
        -X POST "$endpoint/api/v1/mcp/analyze" \
        -H "Authorization: Bearer $MANIFEST_CLOUD_API_KEY" \
        -H "Content-Type: application/json" \
        -H "User-Agent: Manifest-CLI/1.0" \
        -d "$mcp_context" 2>/dev/null)
    
    local curl_exit_code=$?
    
    if [ $curl_exit_code -eq 0 ] && [ -n "$response" ]; then
        log_debug "MCP request successful"
        echo "$response"
        return 0
    else
        log_debug "MCP request failed (curl exit code: $curl_exit_code)"
        return 1
    fi
}

# Prepare MCP context
prepare_mcp_context() {
    local version="$1"
    local changes_file="$2"
    local release_type="${3:-patch}"
    
    # Validate inputs
    if [ -z "$version" ]; then
        show_validation_error "Version is required for MCP context"
        return 1
    fi
    
    if [ ! -f "$changes_file" ]; then
        show_file_error "Changes file not found: $changes_file"
        return 1
    fi
    
    # Sanitize inputs
    version="$(sanitize_version "$version")"
    release_type="$(echo "$release_type" | tr '[:upper:]' '[:lower:]')"
    
    # Get repository information using shared functions
    local repo_url=$(get_git_info "url")
    local repo_name=$(get_git_info "name")
    local repo_owner=$(get_git_info "owner")
    local branch=$(get_git_info "branch")
    local commit_hash=$(get_git_info "commit")
    
    # Read changes content
    local changes_content
    if ! changes_content=$(cat "$changes_file" 2>/dev/null); then
        show_file_error "Failed to read changes file: $changes_file"
        return 1
    fi
    
    # Create MCP context JSON
    cat << EOF
{
    "version": "$version",
    "release_type": "$release_type",
    "repository": {
        "url": "$repo_url",
        "name": "$repo_name",
        "owner": "$repo_owner",
        "branch": "$branch",
        "commit_hash": "$commit_hash"
    },
    "changes": "$(echo "$changes_content" | jq -R -s .)",
    "context": {
        "timestamp": "$(get_formatted_timestamp | sed 's/ UTC//' | sed 's/ /T/' | sed 's/$/Z/')",
        "cli_version": "1.0.0",
        "project_root": "$PROJECT_ROOT"
    }
}
EOF
}

# Process MCP response
process_mcp_response() {
    local response="$1"
    local version="$2"
    
    if [ -z "$response" ]; then
        show_validation_error "Empty response from Manifest Cloud"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$response" | jq empty 2>/dev/null; then
        show_validation_error "Invalid JSON response from Manifest Cloud"
        log_debug "Response content: $response"
        return 1
    fi
    
    # Check for error in response
    local error_message
    if error_message=$(echo "$response" | jq -r '.error // empty' 2>/dev/null); then
        if [ -n "$error_message" ]; then
            show_validation_error "Manifest Cloud returned error: $error_message"
            return 1
        fi
    fi
    
    # Extract documentation content
    local docs_content
    if docs_content=$(echo "$response" | jq -r '.documentation // empty' 2>/dev/null); then
        if [ -n "$docs_content" ]; then
            log_debug "Successfully extracted documentation from MCP response"
            echo "$docs_content"
            return 0
        fi
    fi
    
    show_validation_error "No documentation content found in MCP response"
    return 1
}

# Test MCP connectivity
test_mcp_connectivity() {
    log_info "Testing MCP connectivity to Manifest Cloud..."
    
    if ! check_mcp_prerequisites_with_details; then
        log_error "MCP prerequisites not met"
        return 1
    fi
    
    # Create a simple test context
    local test_context
    test_context=$(cat << EOF
{
    "version": "test",
    "release_type": "patch",
    "repository": {
        "url": "test",
        "name": "test",
        "owner": "test",
        "branch": "test",
        "commit_hash": "test"
    },
    "changes": "test",
    "context": {
        "timestamp": "$(get_formatted_timestamp | sed 's/ UTC//' | sed 's/ /T/' | sed 's/$/Z/')",
        "cli_version": "1.0.0",
        "test": true
    }
}
EOF
)
    
    # Send test request
    local response
    if response=$(send_mcp_request_with_retry "$test_context" 1); then
        log_success "MCP connectivity test successful"
        return 0
    else
        log_error "MCP connectivity test failed"
        return 1
    fi
}

# Configure MCP connection
configure_mcp_connection() {
    log_info "Configuring MCP connection to Manifest Cloud..."
    
    echo "Please visit: https://manifest.cloud/dashboard"
    echo "1. Sign in or create an account"
    echo "2. Get your API key from the dashboard"
    echo "3. Enter it below:"
    echo ""
    
    read -p "Manifest Cloud API Key: " -s api_key
    echo
    
    if [ -z "$api_key" ]; then
        show_validation_error "API key is required"
        return 1
    fi
    
    # Test the API key
    log_info "Testing API key..."
    local test_endpoint="${MANIFEST_CLOUD_ENDPOINT:-$MCP_DEFAULT_ENDPOINT}"
    local response
    response=$(curl -s --max-time 10 \
        -X GET "$test_endpoint/api/v1/agent/subscription/status" \
        -H "Authorization: Bearer $api_key")
    
    if echo "$response" | jq -e '.status' >/dev/null 2>&1; then
        export MANIFEST_CLOUD_API_KEY="$api_key"
        log_success "MCP connection configured successfully"
        log_info "API key saved to current session. Add to your shell profile for persistence:"
        echo "   export MANIFEST_CLOUD_API_KEY='$api_key'"
        return 0
    else
        show_validation_error "Invalid API key or connection failed"
        log_debug "Response: $response"
        return 1
    fi
}

# Show MCP status
show_mcp_status() {
    echo "Manifest Cloud MCP Status"
    echo "========================="
    echo ""
    
    # Check API key
    if [ -n "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        echo "  API Key: ✅ Configured"
    else
        echo "  API Key: ❌ Not configured"
    fi
    
    # Check endpoint
    local endpoint="${MANIFEST_CLOUD_ENDPOINT:-$MCP_DEFAULT_ENDPOINT}"
    echo "  Endpoint: $endpoint"
    
    # Check network connectivity
    if check_network_connectivity; then
        echo "  Network: ✅ Connected"
    else
        echo "  Network: ❌ No connectivity"
    fi
    
    # Check required tools
    if check_required_tools; then
        echo "  Tools: ✅ All available"
    else
        echo "  Tools: ❌ Missing required tools"
    fi
    
    # Check skip settings
    local skip_cloud="false"
    if [ "${MANIFEST_CLOUD_SKIP:-false}" = "true" ] || [ "${MANIFEST_OFFLINE_MODE:-false}" = "true" ]; then
        skip_cloud="true"
    fi
    echo "  Skip Cloud: $skip_cloud"
    
    echo ""
    echo "Configuration:"
    echo "  MANIFEST_CLOUD_API_KEY     - Your Manifest Cloud API key"
    echo "  MANIFEST_CLOUD_ENDPOINT    - Manifest Cloud endpoint (default: $MCP_DEFAULT_ENDPOINT)"
    echo "  MANIFEST_CLOUD_SKIP        - Skip Manifest Cloud and use local docs (true/false)"
    echo "  MANIFEST_OFFLINE_MODE      - Force offline mode, no cloud connectivity (true/false)"
}
