#!/bin/bash

# Manifest AI Cloud Module
# Integrates with Manifest Cloud for intelligent documentation generation

# AI Cloud module - uses PROJECT_ROOT from core module

# Analyze code with Manifest Cloud
analyze_with_manifest_cloud() {
    local version="$1"
    local changes_file="$2"
    local release_type="${3:-patch}"
    
    log_info "Analyzing code with Manifest Cloud..."
    
    # Check prerequisites
    if ! check_manifest_cloud_prerequisites; then
        log_error "Manifest Cloud prerequisites not met"
        return 1
    fi
    
    # Prepare context for analysis
    local context=$(prepare_cloud_context "$version" "$changes_file" "$release_type")
    
    # Send to Manifest Cloud
    local response=$(send_to_manifest_cloud "$context")
    
    # Process response
    if process_cloud_response "$response" "$version"; then
        log_success "Manifest Cloud analysis completed"
        return 0
    else
        log_error "Manifest Cloud analysis failed"
        return 1
    fi
}

# Check Manifest Cloud prerequisites
check_manifest_cloud_prerequisites() {
    # Check API key
    if [ -z "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        log_error "MANIFEST_CLOUD_API_KEY not configured"
        return 1
    fi
    
    # Check endpoint
    if [ -z "${MANIFEST_CLOUD_ENDPOINT:-}" ]; then
        log_warning "MANIFEST_CLOUD_ENDPOINT not configured, using default"
        export MANIFEST_CLOUD_ENDPOINT="https://api.manifest.cloud"
    fi
    
    # Check connectivity
    if ! check_cloud_connectivity; then
        log_error "Cannot connect to Manifest Cloud"
        return 1
    fi
    
    return 0
}

# Check cloud connectivity
check_cloud_connectivity() {
    local endpoint="${MANIFEST_CLOUD_ENDPOINT}"
    local timeout=10
    
    log_info "Checking Manifest Cloud connectivity..."
    
    local response=$(curl -s --max-time "$timeout" \
        -H "Authorization: Bearer $MANIFEST_CLOUD_API_KEY" \
        "$endpoint/health" 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$response" | grep -q "healthy"; then
        log_success "Manifest Cloud is reachable"
        return 0
    else
        log_error "Manifest Cloud connectivity check failed"
        return 1
    fi
}

# Prepare context for Manifest Cloud
prepare_cloud_context() {
    local version="$1"
    local changes_file="$2"
    local release_type="$3"
    
    log_info "Preparing context for Manifest Cloud..."
    
    # Get repository information
    local repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    local repo_name=$(basename "$repo_url" .git 2>/dev/null || echo "")
    local branch=$(git branch --show-current 2>/dev/null || echo "")
    local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
    
    # Get code structure
    local code_structure=$(analyze_code_structure)
    
    # Get dependencies
    local dependencies=$(analyze_dependencies)
    
    # Get recent changes
    local recent_changes=$(cat "$changes_file" 2>/dev/null || echo "")
    
    # Create context JSON
    cat << EOF
{
    "version": "$version",
    "release_type": "$release_type",
    "repository": {
        "url": "$repo_url",
        "name": "$repo_name",
        "branch": "$branch",
        "commit": "$commit_hash"
    },
    "code_structure": $code_structure,
    "dependencies": $dependencies,
    "recent_changes": "$(echo "$recent_changes" | jq -R -s .)",
    "project_root": "$PROJECT_ROOT",
    "timestamp": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
}
EOF
}

# Analyze code structure
analyze_code_structure() {
    local structure=$(cat << EOF
{
    "languages": [],
    "frameworks": [],
    "files": [],
    "directories": []
}
EOF
)
    
    # Detect languages
    local languages=()
    if [ -f "package.json" ] || [ -f "yarn.lock" ] || [ -f "package-lock.json" ]; then
        languages+=("javascript")
        languages+=("nodejs")
    fi
    
    if [ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
        languages+=("python")
    fi
    
    if [ -f "Cargo.toml" ]; then
        languages+=("rust")
    fi
    
    if [ -f "go.mod" ]; then
        languages+=("go")
    fi
    
    if find . -name "*.sh" -type f | head -1 | grep -q .; then
        languages+=("bash")
    fi
    
    if find . -name "*.py" -type f | head -1 | grep -q .; then
        languages+=("python")
    fi
    
    # Count files by type
    local file_counts=$(find . -type f -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" | wc -l)
    
    # Get directory structure
    local dirs=$(find . -type d -maxdepth 2 | jq -R -s -c 'split("\n")[:-1]')
    
    # Build structure JSON
    local langs_json=$(printf '%s\n' "${languages[@]}" | jq -R . | jq -s .)
    
    cat << EOF
{
    "languages": $langs_json,
    "frameworks": [],
    "file_count": $file_counts,
    "directories": $dirs,
    "type": "cli"
}
EOF
}

# Analyze dependencies
analyze_dependencies() {
    local deps=$(cat << EOF
{
    "system": [],
    "runtime": [],
    "build": []
}
EOF
)
    
    # System dependencies
    local system_deps=()
    if command -v git >/dev/null 2>&1; then
        system_deps+=("git")
    fi
    if command -v curl >/dev/null 2>&1; then
        system_deps+=("curl")
    fi
    if command -v bash >/dev/null 2>&1; then
        system_deps+=("bash")
    fi
    
    # Runtime dependencies (from scripts)
    local runtime_deps=()
    if grep -r "command -v" . --include="*.sh" | grep -q "node"; then
        runtime_deps+=("node")
    fi
    if grep -r "command -v" . --include="*.sh" | grep -q "python"; then
        runtime_deps+=("python")
    fi
    
    # Build dependencies
    local build_deps=()
    if [ -f "Makefile" ]; then
        build_deps+=("make")
    fi
    if [ -f "install.sh" ] || [ -f "install-cli.sh" ]; then
        build_deps+=("bash")
    fi
    
    # Convert to JSON
    local system_json=$(printf '%s\n' "${system_deps[@]}" | jq -R . | jq -s .)
    local runtime_json=$(printf '%s\n' "${runtime_deps[@]}" | jq -R . | jq -s .)
    local build_json=$(printf '%s\n' "${build_deps[@]}" | jq -R . | jq -s .)
    
    cat << EOF
{
    "system": $system_json,
    "runtime": $runtime_json,
    "build": $build_json
}
EOF
}

# Send context to Manifest Cloud
send_to_manifest_cloud() {
    local context="$1"
    local endpoint="${MANIFEST_CLOUD_ENDPOINT}/api/v1/analyze"
    local timeout=30
    
    log_info "Sending context to Manifest Cloud..."
    
    local response=$(curl -s --max-time "$timeout" \
        -X POST "$endpoint" \
        -H "Authorization: Bearer $MANIFEST_CLOUD_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$context" 2>/dev/null)
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
        log_success "Context sent to Manifest Cloud"
        echo "$response"
    else
        log_error "Failed to send context to Manifest Cloud"
        echo "{}"
    fi
}

# Process Manifest Cloud response
process_cloud_response() {
    local response="$1"
    local version="$2"
    
    log_info "Processing Manifest Cloud response..."
    
    # Validate response
    if [ -z "$response" ] || [ "$response" = "{}" ]; then
        log_error "Empty response from Manifest Cloud"
        return 1
    fi
    
    # Parse response
    local release_notes=$(echo "$response" | jq -r '.release_notes // empty')
    local changelog=$(echo "$response" | jq -r '.changelog // empty')
    local readme_update=$(echo "$response" | jq -r '.readme_update // empty')
    
    # Generate documentation files
    if [ -n "$release_notes" ]; then
        echo "$release_notes" > "$PROJECT_ROOT/docs/RELEASE_v$version.md"
        log_success "Release notes generated from Manifest Cloud"
    fi
    
    if [ -n "$changelog" ]; then
        echo "$changelog" > "$PROJECT_ROOT/docs/CHANGELOG_v$version.md"
        log_success "Changelog generated from Manifest Cloud"
    fi
    
    if [ -n "$readme_update" ]; then
        update_readme_with_cloud_content "$readme_update"
        log_success "README updated from Manifest Cloud"
    fi
    
    return 0
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
            
            analyze_with_manifest_cloud "$version" "$changes_file" "$release_type"
            ;;
        "test")
            test_manifest_cloud
            ;;
        "config")
            show_cloud_config
            ;;
        "help"|"-h"|"--help")
            echo "Manifest AI Cloud Module"
            echo "======================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  analyze <version> <file> [type]  - Analyze with Manifest Cloud"
            echo "  test                             - Test cloud connectivity"
            echo "  config                           - Show configuration"
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
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# Show cloud configuration
show_cloud_config() {
    echo "Manifest Cloud Configuration"
    echo "============================"
    echo ""
    echo "API Key: ${MANIFEST_CLOUD_API_KEY:-Not configured}"
    echo "Endpoint: ${MANIFEST_CLOUD_ENDPOINT:-https://api.manifest.cloud (default)}"
    echo ""
    
    if [ -n "${MANIFEST_CLOUD_API_KEY:-}" ]; then
        echo "Status: Configured"
        if check_cloud_connectivity; then
            echo "Connectivity: ✅ Connected"
        else
            echo "Connectivity: ❌ Connection failed"
        fi
    else
        echo "Status: Not configured"
        echo "Connectivity: ❌ No API key"
    fi
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
