#!/bin/bash

# Manifest MCP Connector Module
# Model Context Protocol connector for Manifest Cloud API

# MCP Connector module - uses PROJECT_ROOT from core module

# Send code context to Manifest Cloud via MCP with comprehensive error handling
send_to_manifest_cloud() {
    local version="$1"
    local changes_file="$2"
    local release_type="${3:-patch}"
    local max_retries="${4:-3}"
    local fallback_to_local="${5:-true}"
    
    log_info "Connecting to Manifest Cloud via MCP..."
    
    # Check if user wants to skip cloud
    if should_skip_cloud; then
        log_info "Manifest Cloud skipped by user preference"
        if [ "$fallback_to_local" = "true" ]; then
            fallback_to_local_docs "$version" "$changes_file" "$release_type"
            return $?
        else
            return 1
        fi
    fi
    
    # Check prerequisites with detailed error reporting
    if ! check_mcp_prerequisites_with_details; then
        log_error "MCP prerequisites not met"
        if [ "$fallback_to_local" = "true" ]; then
            log_info "Falling back to local documentation generation..."
            fallback_to_local_docs "$version" "$changes_file" "$release_type"
            return $?
        else
            return 1
        fi
    fi
    
    # Prepare MCP context with error handling
    local mcp_context
    if ! mcp_context=$(prepare_mcp_context "$version" "$changes_file" "$release_type"); then
        log_error "Failed to prepare MCP context"
        if [ "$fallback_to_local" = "true" ]; then
            fallback_to_local_docs "$version" "$changes_file" "$release_type"
            return $?
        else
            return 1
        fi
    fi
    
    # Send via MCP to Manifest Cloud with retry logic
    local response
    local attempt=1
    while [ $attempt -le $max_retries ]; do
        log_info "Attempting MCP request (attempt $attempt/$max_retries)..."
        
        if response=$(send_mcp_request_with_retry "$mcp_context" "$attempt"); then
            # Process MCP response
            if process_mcp_response "$response" "$version"; then
                log_success "Manifest Cloud analysis completed via MCP"
                return 0
            else
                log_error "Failed to process MCP response"
                break
            fi
        else
            log_warning "MCP request attempt $attempt failed"
            
            if [ $attempt -eq $max_retries ]; then
                log_error "All MCP request attempts failed after $max_retries tries"
                break
            fi
            
            # Wait before retry with exponential backoff
            local wait_time=$((2 ** attempt))
            log_info "Waiting ${wait_time}s before retry..."
            sleep $wait_time
            attempt=$((attempt + 1))
        fi
    done
    
    # All attempts failed - fallback to local
    if [ "$fallback_to_local" = "true" ]; then
        log_warning "Manifest Cloud unavailable, falling back to local documentation generation..."
        fallback_to_local_docs "$version" "$changes_file" "$release_type"
        return $?
    else
        log_error "Manifest Cloud MCP analysis failed and fallback disabled"
        return 1
    fi
}

# Check if user wants to skip cloud
should_skip_cloud() {
    # Check environment variable
    if [ "${MANIFEST_CLOUD_SKIP:-false}" = "true" ]; then
        return 0
    fi
    
    # Check if offline mode is requested
    if [ "${MANIFEST_OFFLINE_MODE:-false}" = "true" ]; then
        return 0
    fi
    
    # Check if network connectivity is available
    if ! check_network_connectivity; then
        log_warning "No network connectivity detected"
        return 0
    fi
    
    return 1
}

# Check network connectivity
check_network_connectivity() {
    # Try to ping a reliable service
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    
    # Try to ping another reliable service
    if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Check MCP prerequisites with detailed error reporting
check_mcp_prerequisites_with_details() {
    local errors=0
    
    # Check API key
    if [ -z "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        log_error "MANIFEST_CLOUD_API_KEY not configured"
        echo ""
        echo "To use Manifest Cloud, you need an API key."
        echo "Get your API key from: https://manifest.cloud/dashboard"
        echo "Then set: export MANIFEST_CLOUD_API_KEY='your_api_key'"
        echo "Or add to your .env file: MANIFEST_CLOUD_API_KEY='your_api_key'"
        echo ""
        echo "Alternatively, set MANIFEST_CLOUD_SKIP=true to skip cloud and use local docs"
        errors=$((errors + 1))
    fi
    
    # Check endpoint
    if [ -z "${MANIFEST_CLOUD_ENDPOINT:-}" ]; then
        export MANIFEST_CLOUD_ENDPOINT="https://api.manifest.cloud"
        log_info "Using default Manifest Cloud endpoint: $MANIFEST_CLOUD_ENDPOINT"
    fi
    
    # Check network connectivity
    if ! check_network_connectivity; then
        log_error "No network connectivity available"
        echo "Please check your internet connection or set MANIFEST_OFFLINE_MODE=true"
        errors=$((errors + 1))
    fi
    
    # Check cloud connectivity
    if ! check_cloud_connectivity; then
        log_error "Cannot connect to Manifest Cloud"
        echo "Please check:"
        echo "  - Your internet connection"
        echo "  - Manifest Cloud service status"
        echo "  - Your API key validity"
        echo "  - Firewall/proxy settings"
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Check MCP prerequisites (simplified version for backward compatibility)
check_mcp_prerequisites() {
    check_mcp_prerequisites_with_details >/dev/null 2>&1
}

# Check cloud connectivity
check_cloud_connectivity() {
    local endpoint="${MANIFEST_CLOUD_ENDPOINT}"
    local timeout=10
    
    log_info "Checking Manifest Cloud connectivity..."
    
    local response=$(curl -s --max-time "$timeout" \
        -H "Authorization: Bearer $MANIFEST_CLOUD_API_KEY" \
        -H "Content-Type: application/json" \
        "$endpoint/health" 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$response" | grep -q "healthy"; then
        log_success "Manifest Cloud is reachable"
        return 0
    else
        log_error "Manifest Cloud connectivity check failed"
        return 1
    fi
}

# Prepare MCP context for Manifest Cloud
prepare_mcp_context() {
    local version="$1"
    local changes_file="$2"
    local release_type="$3"
    
    log_info "Preparing MCP context for Manifest Cloud..."
    
    # Get repository information
    local repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    local repo_name=$(basename "$repo_url" .git 2>/dev/null || echo "")
    local branch=$(git branch --show-current 2>/dev/null || echo "")
    local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
    
    # Get code structure for MCP
    local code_structure=$(prepare_code_structure_for_mcp)
    
    # Get recent changes
    local recent_changes=$(cat "$changes_file" 2>/dev/null || echo "")
    
    # Create MCP-compatible context
    cat << EOF
{
    "mcp_version": "1.0",
    "request_type": "documentation_generation",
    "version": "$version",
    "release_type": "$release_type",
    "repository": {
        "url": "$repo_url",
        "name": "$repo_name",
        "branch": "$branch",
        "commit": "$commit_hash"
    },
    "code_context": $code_structure,
    "recent_changes": "$(echo "$recent_changes" | jq -R -s .)",
    "project_root": "$PROJECT_ROOT",
    "timestamp": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
    "mcp_metadata": {
        "client": "manifest-cli",
        "client_version": "16.3.0",
        "protocol": "mcp-1.0"
    }
}
EOF
}

# Prepare code structure for MCP
prepare_code_structure_for_mcp() {
    # Create comprehensive code structure for Manifest Cloud to analyze
    local structure=$(cat << EOF
{
    "files": [],
    "directories": [],
    "languages": [],
    "frameworks": [],
    "dependencies": {},
    "configuration": {},
    "git_history": {}
}
EOF
)
    
    # Get file structure
    local files=$(find . -type f -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" -o -name "*.md" | head -50 | jq -R . | jq -s .)
    
    # Get directory structure
    local dirs=$(find . -type d -maxdepth 3 | jq -R . | jq -s .)
    
    # Detect languages
    local languages=()
    if find . -name "*.sh" -type f | head -1 | grep -q .; then
        languages+=("bash")
    fi
    if find . -name "*.py" -type f | head -1 | grep -q .; then
        languages+=("python")
    fi
    if find . -name "*.js" -type f | head -1 | grep -q .; then
        languages+=("javascript")
    fi
    if find . -name "*.ts" -type f | head -1 | grep -q .; then
        languages+=("typescript")
    fi
    if find . -name "*.go" -type f | head -1 | grep -q .; then
        languages+=("go")
    fi
    if find . -name "*.rs" -type f | head -1 | grep -q .; then
        languages+=("rust")
    fi
    
    # Get dependencies
    local dependencies=$(cat << EOF
{
    "system": ["git", "curl", "bash"],
    "runtime": [],
    "build": []
}
EOF
)
    
    # Get configuration files
    local config_files=$(find . -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" -o -name "*.env*" -o -name "package.json" -o -name "requirements.txt" | head -10 | jq -R . | jq -s .)
    
    # Get recent git history
    local git_history=$(git log --oneline -10 2>/dev/null | jq -R . | jq -s . || echo "[]")
    
    # Convert languages to JSON
    local langs_json=$(printf '%s\n' "${languages[@]}" | jq -R . | jq -s .)
    
    # Build final structure
    cat << EOF
{
    "files": $files,
    "directories": $dirs,
    "languages": $langs_json,
    "frameworks": [],
    "dependencies": $dependencies,
    "configuration_files": $config_files,
    "git_history": $git_history,
    "project_type": "cli"
}
EOF
}

# Send MCP request to Manifest Cloud with retry logic
send_mcp_request_with_retry() {
    local mcp_context="$1"
    local attempt="$2"
    local endpoint="${MANIFEST_CLOUD_ENDPOINT}/mcp/v1/analyze"
    
    # Increase timeout with each attempt
    local timeout=$((30 + (attempt * 15)))
    
    log_info "Sending MCP request to Manifest Cloud (timeout: ${timeout}s)..."
    
    # Create temporary file for response
    local response_file=$(mktemp)
    local error_file=$(mktemp)
    
    # Send request with detailed error capture
    local curl_exit_code
    curl -s --max-time "$timeout" \
        -X POST "$endpoint" \
        -H "Authorization: Bearer $MANIFEST_CLOUD_API_KEY" \
        -H "Content-Type: application/json" \
        -H "X-MCP-Version: 1.0" \
        -H "X-Client: manifest-cli" \
        -H "X-Attempt: $attempt" \
        -d "$mcp_context" \
        --write-out "HTTP_STATUS:%{http_code}" \
        --output "$response_file" \
        --stderr "$error_file"
    
    curl_exit_code=$?
    local http_status=$(grep "HTTP_STATUS:" "$response_file" | cut -d: -f2)
    local response=$(sed '/HTTP_STATUS:/d' "$response_file")
    local error_output=$(cat "$error_file")
    
    # Clean up temporary files
    rm -f "$response_file" "$error_file"
    
    # Check for various error conditions
    if [ $curl_exit_code -ne 0 ]; then
        log_error "Curl error (exit code: $curl_exit_code)"
        if [ -n "$error_output" ]; then
            log_error "Error details: $error_output"
        fi
        return 1
    fi
    
    if [ -z "$http_status" ]; then
        log_error "No HTTP status received"
        return 1
    fi
    
    if [ "$http_status" -ge 500 ]; then
        log_error "Server error (HTTP $http_status)"
        return 1
    elif [ "$http_status" -ge 400 ]; then
        log_error "Client error (HTTP $http_status)"
        if [ "$http_status" -eq 401 ]; then
            log_error "Authentication failed - check your API key"
        elif [ "$http_status" -eq 403 ]; then
            log_error "Access forbidden - check your API key permissions"
        elif [ "$http_status" -eq 429 ]; then
            log_error "Rate limited - too many requests"
        fi
        return 1
    fi
    
    if [ -z "$response" ] || [ "$response" = "{}" ]; then
        log_error "Empty response from Manifest Cloud"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        log_error "Invalid JSON response from Manifest Cloud"
        return 1
    fi
    
    log_success "MCP request successful (HTTP $http_status)"
    echo "$response"
    return 0
}

# Send MCP request to Manifest Cloud (simplified version for backward compatibility)
send_mcp_request() {
    send_mcp_request_with_retry "$1" 1
}

# Process MCP response from Manifest Cloud
process_mcp_response() {
    local response="$1"
    local version="$2"
    
    log_info "Processing MCP response from Manifest Cloud..."
    
    # Validate response
    if [ -z "$response" ] || [ "$response" = "{}" ]; then
        log_error "Empty response from Manifest Cloud"
        return 1
    fi
    
    # Parse MCP response
    local release_notes=$(echo "$response" | jq -r '.release_notes // empty')
    local changelog=$(echo "$response" | jq -r '.changelog // empty')
    local readme_update=$(echo "$response" | jq -r '.readme_update // empty')
    local analysis_metadata=$(echo "$response" | jq -r '.metadata // {}')
    
    # Log analysis metadata
    if [ "$analysis_metadata" != "{}" ] && [ "$analysis_metadata" != "null" ]; then
        log_info "Analysis metadata: $analysis_metadata"
    fi
    
    # Generate documentation files
    if [ -n "$release_notes" ] && [ "$release_notes" != "null" ]; then
        echo "$release_notes" > "$PROJECT_ROOT/docs/RELEASE_v$version.md"
        log_success "Release notes generated from Manifest Cloud"
    fi
    
    if [ -n "$changelog" ] && [ "$changelog" != "null" ]; then
        echo "$changelog" > "$PROJECT_ROOT/docs/CHANGELOG_v$version.md"
        log_success "Changelog generated from Manifest Cloud"
    fi
    
    if [ -n "$readme_update" ] && [ "$readme_update" != "null" ]; then
        update_readme_with_cloud_content "$readme_update"
        log_success "README updated from Manifest Cloud"
    fi
    
    return 0
}

# Fallback to local documentation generation
fallback_to_local_docs() {
    local version="$1"
    local changes_file="$2"
    local release_type="$3"
    
    log_info "Using local documentation generation as fallback..."
    
    # Check if local documentation module is available
    if [ -f "$SCRIPT_DIR/manifest-documentation.sh" ]; then
        # Source the local documentation module
        source "$SCRIPT_DIR/manifest-documentation.sh"
        
        # Generate documentation locally
        local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
        
        log_info "Generating documentation locally for version $version..."
        
        # Ensure docs directory exists
        mkdir -p "$PROJECT_ROOT/docs"
        
        # Generate documents using local templates
        if generate_documents "$version" "$timestamp" "$release_type"; then
            log_success "Local documentation generation completed"
            return 0
        else
            log_error "Local documentation generation failed"
            return 1
        fi
    else
        log_error "Local documentation module not available"
        return 1
    fi
}

# Update README with cloud content
update_readme_with_cloud_content() {
    local content="$1"
    local readme_file="$PROJECT_ROOT/README.md"
    
    if [[ ! -f "$readme_file" ]]; then
        log_warning "README.md not found, creating new one"
        echo "$content" > "$readme_file"
        return 0
    fi
    
    # Find version section and replace it
    local temp_file=$(mktemp)
    
    # Copy content before version section
    if grep -q "## 📋 Version Information" "$readme_file"; then
        local start_line=$(grep -n "## 📋 Version Information" "$readme_file" | cut -d: -f1)
        head -n $((start_line - 1)) "$readme_file" > "$temp_file"
    else
        cat "$readme_file" > "$temp_file"
    fi
    
    # Add new version section
    echo "" >> "$temp_file"
    echo "$content" >> "$temp_file"
    
    # Copy content after version section
    if grep -q "## 📋 Version Information" "$readme_file"; then
        local start_line=$(grep -n "## 📋 Version Information" "$readme_file" | cut -d: -f1)
        local end_line=$(tail -n +$((start_line + 1)) "$readme_file" | grep -n "^## " | head -1 | cut -d: -f1)
        
        if [[ -n "$end_line" ]]; then
            end_line=$((start_line + end_line - 1))
            tail -n +$((end_line + 1)) "$readme_file" >> "$temp_file"
        fi
    fi
    
    # Replace original file
    mv "$temp_file" "$readme_file"
}

# Test MCP connectivity
test_mcp_connectivity() {
    log_info "Testing MCP connectivity to Manifest Cloud..."
    
    if ! check_mcp_prerequisites; then
        return 1
    fi
    
    # Test MCP health endpoint
    local endpoint="${MANIFEST_CLOUD_ENDPOINT}/mcp/v1/health"
    local response=$(curl -s --max-time 10 \
        -H "Authorization: Bearer $MANIFEST_CLOUD_API_KEY" \
        -H "X-MCP-Version: 1.0" \
        "$endpoint" 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$response" | grep -q "healthy"; then
        log_success "MCP connectivity test passed"
        
        # Parse MCP version from response
        local mcp_version=$(echo "$response" | jq -r '.mcp_version // "unknown"')
        log_info "Manifest Cloud MCP version: $mcp_version"
        
        return 0
    else
        log_error "MCP connectivity test failed"
        return 1
    fi
}

# Configure MCP connection with comprehensive options
configure_mcp_connection() {
    echo "Manifest Cloud MCP Configuration"
    echo "================================"
    echo ""
    
    # Check current configuration
    echo "Current configuration:"
    echo "  API Key: ${MANIFEST_CLOUD_API_KEY:+Set (hidden)}"
    echo "  Endpoint: ${MANIFEST_CLOUD_ENDPOINT:-https://api.manifest.cloud (default)}"
    echo "  MCP Version: 1.0"
    echo "  Skip Cloud: ${MANIFEST_CLOUD_SKIP:-false}"
    echo "  Offline Mode: ${MANIFEST_OFFLINE_MODE:-false}"
    echo ""
    
    # Configuration options
    echo "Configuration Options:"
    echo "  1) Configure API key"
    echo "  2) Test connectivity"
    echo "  3) Set offline mode"
    echo "  4) Skip cloud permanently"
    echo "  5) Reset configuration"
    echo "  6) Show detailed status"
    echo ""
    
    read -p "Select option (1-6): " option
    
    case "$option" in
        1)
            configure_api_key
            ;;
        2)
            test_mcp_connectivity
            ;;
        3)
            configure_offline_mode
            ;;
        4)
            configure_skip_cloud
            ;;
        5)
            reset_mcp_configuration
            ;;
        6)
            show_detailed_mcp_status
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

# Configure API key
configure_api_key() {
    echo ""
    echo "API Key Configuration"
    echo "===================="
    echo ""
    
    if [ -n "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        echo "Current API key is set."
        read -p "Do you want to update it? (y/N): " update
        if [[ ! "$update" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    echo "To use Manifest Cloud MCP, you need an API key."
    echo "Get your API key from: https://manifest.cloud/dashboard"
    echo ""
    read -p "Enter your Manifest Cloud API key: " api_key
    
    if [ -n "$api_key" ]; then
        # Add to .env file
        if [ -f "$PROJECT_ROOT/.env" ]; then
            if grep -q "MANIFEST_CLOUD_API_KEY" "$PROJECT_ROOT/.env"; then
                sed -i.bak "s/MANIFEST_CLOUD_API_KEY=.*/MANIFEST_CLOUD_API_KEY=\"$api_key\"/" "$PROJECT_ROOT/.env"
            else
                echo "MANIFEST_CLOUD_API_KEY=\"$api_key\"" >> "$PROJECT_ROOT/.env"
            fi
        else
            echo "MANIFEST_CLOUD_API_KEY=\"$api_key\"" > "$PROJECT_ROOT/.env"
        fi
        
        export MANIFEST_CLOUD_API_KEY="$api_key"
        log_success "API key configured"
        
        # Test the new key
        echo ""
        read -p "Test the new API key now? (Y/n): " test_now
        if [[ ! "$test_now" =~ ^[Nn]$ ]]; then
            test_mcp_connectivity
        fi
    else
        log_warning "No API key provided"
    fi
}

# Configure offline mode
configure_offline_mode() {
    echo ""
    echo "Offline Mode Configuration"
    echo "========================="
    echo ""
    
    if [ "${MANIFEST_OFFLINE_MODE:-false}" = "true" ]; then
        echo "Offline mode is currently enabled."
        read -p "Do you want to disable it? (y/N): " disable
        if [[ "$disable" =~ ^[Yy]$ ]]; then
            unset MANIFEST_OFFLINE_MODE
            if [ -f "$PROJECT_ROOT/.env" ]; then
                sed -i.bak '/MANIFEST_OFFLINE_MODE/d' "$PROJECT_ROOT/.env"
            fi
            log_success "Offline mode disabled"
        fi
    else
        echo "Offline mode is currently disabled."
        read -p "Do you want to enable it? (y/N): " enable
        if [[ "$enable" =~ ^[Yy]$ ]]; then
            if [ -f "$PROJECT_ROOT/.env" ]; then
                echo "MANIFEST_OFFLINE_MODE=true" >> "$PROJECT_ROOT/.env"
            else
                echo "MANIFEST_OFFLINE_MODE=true" > "$PROJECT_ROOT/.env"
            fi
            export MANIFEST_OFFLINE_MODE=true
            log_success "Offline mode enabled"
        fi
    fi
}

# Configure skip cloud
configure_skip_cloud() {
    echo ""
    echo "Skip Cloud Configuration"
    echo "======================="
    echo ""
    
    if [ "${MANIFEST_CLOUD_SKIP:-false}" = "true" ]; then
        echo "Cloud is currently skipped."
        read -p "Do you want to enable cloud usage? (y/N): " enable
        if [[ "$enable" =~ ^[Yy]$ ]]; then
            unset MANIFEST_CLOUD_SKIP
            if [ -f "$PROJECT_ROOT/.env" ]; then
                sed -i.bak '/MANIFEST_CLOUD_SKIP/d' "$PROJECT_ROOT/.env"
            fi
            log_success "Cloud usage enabled"
        fi
    else
        echo "Cloud is currently enabled."
        read -p "Do you want to skip cloud permanently? (y/N): " skip
        if [[ "$skip" =~ ^[Yy]$ ]]; then
            if [ -f "$PROJECT_ROOT/.env" ]; then
                echo "MANIFEST_CLOUD_SKIP=true" >> "$PROJECT_ROOT/.env"
            else
                echo "MANIFEST_CLOUD_SKIP=true" > "$PROJECT_ROOT/.env"
            fi
            export MANIFEST_CLOUD_SKIP=true
            log_success "Cloud usage disabled"
        fi
    fi
}

# Reset MCP configuration
reset_mcp_configuration() {
    echo ""
    echo "Reset Configuration"
    echo "=================="
    echo ""
    
    read -p "Are you sure you want to reset all MCP configuration? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Remove from environment
        unset MANIFEST_CLOUD_API_KEY
        unset MANIFEST_CLOUD_ENDPOINT
        unset MANIFEST_CLOUD_SKIP
        unset MANIFEST_OFFLINE_MODE
        
        # Remove from .env file
        if [ -f "$PROJECT_ROOT/.env" ]; then
            sed -i.bak '/MANIFEST_CLOUD_/d' "$PROJECT_ROOT/.env"
            sed -i.bak '/MANIFEST_OFFLINE_MODE/d' "$PROJECT_ROOT/.env"
        fi
        
        log_success "MCP configuration reset"
    fi
}

# Show detailed MCP status
show_detailed_mcp_status() {
    echo ""
    echo "Detailed MCP Status"
    echo "==================="
    echo ""
    
    echo "Configuration:"
    echo "  API Key: ${MANIFEST_CLOUD_API_KEY:+Set (hidden)}"
    echo "  Endpoint: ${MANIFEST_CLOUD_ENDPOINT:-https://api.manifest.cloud (default)}"
    echo "  MCP Version: 1.0"
    echo "  Skip Cloud: ${MANIFEST_CLOUD_SKIP:-false}"
    echo "  Offline Mode: ${MANIFEST_OFFLINE_MODE:-false}"
    echo ""
    
    echo "Connectivity Tests:"
    
    # Test network connectivity
    if check_network_connectivity; then
        echo "  Network: ✅ Connected"
    else
        echo "  Network: ❌ No internet connection"
    fi
    
    # Test cloud connectivity
    if [ -n "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        echo "  Status: Configured"
        if test_mcp_connectivity; then
            echo "  Manifest Cloud: ✅ Connected"
        else
            echo "  Manifest Cloud: ❌ Connection failed"
        fi
    else
        echo "  Status: Not configured"
        echo "  Manifest Cloud: ❌ No API key"
    fi
    
    echo ""
    echo "Fallback Options:"
    if [ -f "$SCRIPT_DIR/manifest-documentation.sh" ]; then
        echo "  Local Documentation: ✅ Available"
    else
        echo "  Local Documentation: ❌ Not available"
    fi
    
    echo ""
    echo "Environment Variables:"
    echo "  MANIFEST_CLOUD_API_KEY: ${MANIFEST_CLOUD_API_KEY:+Set}"
    echo "  MANIFEST_CLOUD_ENDPOINT: ${MANIFEST_CLOUD_ENDPOINT:-Not set (using default)}"
    echo "  MANIFEST_CLOUD_SKIP: ${MANIFEST_CLOUD_SKIP:-Not set (false)}"
    echo "  MANIFEST_OFFLINE_MODE: ${MANIFEST_OFFLINE_MODE:-Not set (false)}"
}

# Show MCP status (simplified version)
show_mcp_status() {
    echo "Manifest Cloud MCP Status"
    echo "========================="
    echo ""
    
    echo "Configuration:"
    echo "  API Key: ${MANIFEST_CLOUD_API_KEY:+Set (hidden)}"
    echo "  Endpoint: ${MANIFEST_CLOUD_ENDPOINT:-https://api.manifest.cloud (default)}"
    echo "  MCP Version: 1.0"
    echo "  Skip Cloud: ${MANIFEST_CLOUD_SKIP:-false}"
    echo "  Offline Mode: ${MANIFEST_OFFLINE_MODE:-false}"
    echo ""
    
    if [ -n "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        echo "Status: Configured"
        if test_mcp_connectivity; then
            echo "Connectivity: ✅ Connected"
        else
            echo "Connectivity: ❌ Connection failed"
        fi
    else
        echo "Status: Not configured"
        echo "Connectivity: ❌ No API key"
    fi
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "analyze")
            local version="${2:-}"
            local changes_file="${3:-}"
            local release_type="${4:-patch}"
            
            if [[ -z "$version" || -z "$changes_file" ]]; then
                show_required_arg_error "Version and changes file" "analyze <version> <changes_file> [release_type]"
            fi
            
            send_to_manifest_cloud "$version" "$changes_file" "$release_type"
            ;;
        "test")
            test_mcp_connectivity
            ;;
        "config")
            configure_mcp_connection
            ;;
        "status")
            show_mcp_status
            ;;
        "help"|"-h"|"--help")
            echo "Manifest MCP Connector Module"
            echo "============================"
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  analyze <version> <file> [type]  - Analyze with Manifest Cloud via MCP"
            echo "  test                             - Test MCP connectivity"
            echo "  config                           - Configure MCP connection"
            echo "  status                           - Show MCP status"
            echo "  help                             - Show this help"
            echo ""
            echo "Configuration:"
            echo "  MANIFEST_CLOUD_API_KEY          - API key for Manifest Cloud"
            echo "  MANIFEST_CLOUD_ENDPOINT         - Cloud endpoint URL"
            echo ""
            echo "Examples:"
            echo "  $0 analyze 1.2.3 /tmp/changes.md patch"
            echo "  $0 test"
            echo "  $0 config"
            echo "  $0 status"
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
