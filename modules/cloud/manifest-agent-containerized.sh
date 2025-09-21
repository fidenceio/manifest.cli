#!/bin/bash

# Manifest Agent - Containerized Version
# Highly secure, minimal installation with maximum isolation

# Source shared utilities
SCRIPT_DIR="$(get_script_dir)"
source "$(dirname "$SCRIPT_DIR")/core/manifest-shared-utils.sh"

# Agent configuration (user-space only)
AGENT_DIR="$HOME/.manifest-agent"
AGENT_CONFIG="$AGENT_DIR/config.json"
AGENT_LOGS="$AGENT_DIR/logs"
AGENT_CACHE="$AGENT_DIR/cache"

# Agent modes
AGENT_MODE_DOCKER="docker"
AGENT_MODE_BINARY="binary" 
AGENT_MODE_SCRIPT="script"

# Initialize minimal agent (no persistent services)
init_agent() {
    local mode="${1:-script}"
    
    log_info "Initializing Manifest Agent (containerized mode: $mode)..."
    
    # Create minimal directory structure
    mkdir -p "$AGENT_DIR" "$AGENT_LOGS" "$AGENT_CACHE"
    
    # Create configuration
    cat > "$AGENT_CONFIG" << EOF
{
    "agent_id": "$(generate_agent_id)",
    "version": "1.0.0",
    "mode": "$mode",
    "installation_type": "containerized-minimal",
    "subscription_token": "",
    "github_token": "",
    "manifest_cloud_endpoint": "https://api.manifest.cloud",
    "network_mode": "on-demand-only",
    "audit_mode": true,
    "no_persistent_services": true,
    "last_operation": null
}
EOF
    
    # Log initialization
    log_operation "agent_initialized" "Agent initialized in $mode mode (containerized)"
    
    case "$mode" in
        "$AGENT_MODE_DOCKER")
            setup_docker_agent
            ;;
        "$AGENT_MODE_BINARY")
            setup_binary_agent
            ;;
        "$AGENT_MODE_SCRIPT")
            setup_script_agent
            ;;
    esac
    
    log_success "Containerized agent initialized successfully"
    log_info "Agent operates in $mode mode - no persistent services, on-demand only"
}

# Setup Docker-based agent (most secure)
setup_docker_agent() {
    log_info "Setting up Docker-based agent..."
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required for containerized mode"
        log_info "Install Docker from: https://www.docker.com/products/docker-desktop"
        return 1
    fi
    
    # Create Docker wrapper script
    cat > "$AGENT_DIR/manifest-agent-docker" << 'EOF'
#!/bin/bash
# Docker-based Manifest Agent wrapper

AGENT_DIR="$HOME/.manifest-agent"
AGENT_CONFIG="$AGENT_DIR/config.json"
AGENT_LOGS="$AGENT_DIR/logs"

# Read configuration
if [ ! -f "$AGENT_CONFIG" ]; then
    echo "Agent not initialized. Run 'manifest agent init docker' first."
    exit 1
fi

# Get configuration
MANIFEST_CLOUD_ENDPOINT=$(jq -r '.manifest_cloud_endpoint' "$AGENT_CONFIG")
SUBSCRIPTION_TOKEN=$(jq -r '.subscription_token // empty' "$AGENT_CONFIG")

# Docker command with strict security
docker run --rm \
    --network=host \
    -v "$(pwd)":/workspace:ro \
    -v "$AGENT_DIR":/agent-config:ro \
    -v "$AGENT_LOGS":/agent-logs \
    --read-only \
    --tmpfs /tmp \
    --user $(id -u):$(id -g) \
    --security-opt no-new-privileges \
    manifest/agent:latest \
    "$@"
EOF
    
    chmod +x "$AGENT_DIR/manifest-agent-docker"
    log_success "Docker agent wrapper created"
}

# Setup static binary agent
setup_binary_agent() {
    log_info "Setting up static binary agent..."
    
    # Create binary download script
    cat > "$AGENT_DIR/manifest-agent-binary" << 'EOF'
#!/bin/bash
# Static binary Manifest Agent

AGENT_DIR="$HOME/.manifest-agent"
BINARY_PATH="$AGENT_DIR/manifest-agent-bin"

# Download binary if not exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "Downloading manifest-agent binary..."
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    # Download from GitHub releases
    local download_url="https://github.com/manifest-cloud/agent/releases/latest/download/manifest-agent-${os}-${arch}"
    
    if curl -L -o "$BINARY_PATH" "$download_url"; then
        chmod +x "$BINARY_PATH"
        echo "Binary downloaded successfully"
    else
        echo "Failed to download binary"
        exit 1
    fi
fi

# Execute binary with restricted permissions
exec "$BINARY_PATH" --config "$AGENT_DIR/config.json" "$@"
EOF
    
    chmod +x "$AGENT_DIR/manifest-agent-binary"
    log_success "Binary agent wrapper created"
}

# Setup script-based agent (most compatible)
setup_script_agent() {
    log_info "Setting up script-based agent..."
    
    # Create main agent script
    cat > "$AGENT_DIR/manifest-agent-script" << 'EOF'
#!/bin/bash
# Script-based Manifest Agent

AGENT_DIR="$HOME/.manifest-agent"
AGENT_CONFIG="$AGENT_DIR/config.json"
AGENT_LOGS="$AGENT_DIR/logs"

# Load configuration
if [ ! -f "$AGENT_CONFIG" ]; then
    echo "Agent not initialized. Run 'manifest agent init script' first."
    exit 1
fi

# Source configuration safely
while IFS='=' read -r key value; do
    # Validate variable name to prevent injection
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        export "$key"="$value"
    else
        log_warning "Invalid environment variable name: $key (skipping)"
    fi
done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$AGENT_CONFIG" 2>/dev/null || echo "")

# log_operation() and generate_agent_id() - Now available from manifest-shared-functions.sh

# Send heartbeat (on-demand only)
send_heartbeat() {
    if [ -z "$subscription_token" ]; then
        echo "No subscription token configured"
        return 1
    fi
    
    log_operation "heartbeat" "Sending heartbeat to Manifest Cloud"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local response=$(curl -s --max-time 10 \
        -X POST "$manifest_cloud_endpoint/api/v1/agent/heartbeat" \
        -H "Authorization: Bearer $subscription_token" \
        -H "Content-Type: application/json" \
        -d "{\"agent_id\":\"$agent_id\",\"timestamp\":\"$timestamp\"}")
    
    if [ $? -eq 0 ]; then
        log_operation "heartbeat_success" "Heartbeat successful"
        echo "Heartbeat successful"
    else
        log_operation "heartbeat_failed" "Heartbeat failed"
        echo "Heartbeat failed"
    fi
}

# Analyze code locally (metadata only)
analyze_code_metadata() {
    local version="$1"
    local changes_file="$2"
    local release_type="$3"
    
    log_operation "code_analysis" "Starting local code analysis for version $version"
    
    # Get repository information using shared functions
    local repo_url=$(get_git_info "url")
    local repo_name=$(get_git_info "name")
    local repo_owner=$(get_git_info "owner")
    local branch=$(get_git_info "branch")
    local commit_hash=$(get_git_info "commit")
    
    # Analyze project structure (no source code)
    local languages=()
    local file_count=0
    
    # Detect languages
    if [ -f "package.json" ]; then
        languages+=("javascript")
        languages+=("nodejs")
    fi
    if [ -f "requirements.txt" ] || [ -f "setup.py" ]; then
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
    
    # Count files (metadata only)
    file_count=$(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.sh" \) | wc -l)
    
    # Get changes summary (no source code)
    local changes_summary=""
    if [ -f "$changes_file" ]; then
        changes_summary=$(head -n 3 "$changes_file" | tr '\n' ' ' | sed 's/  */ /g')
    fi
    
    # Create metadata JSON (no source code)
    cat << JSON_EOF
{
    "agent_id": "$agent_id",
    "subscription_token": "$subscription_token",
    "repository": {
        "url": "$repo_url",
        "name": "$repo_name",
        "owner": "$repo_owner",
        "branch": "$branch",
        "commit_hash": "$commit_hash"
    },
    "project_metadata": {
        "languages": $(printf '%s\n' "${languages[@]}" | jq -R . | jq -s .),
        "file_count": $file_count,
        "type": "cli"
    },
    "changes": {
        "version": "$version",
        "release_type": "$release_type",
        "change_summary": "$changes_summary"
    },
    "context": {
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "agent_version": "1.0.0"
    }
}
JSON_EOF
}

# Send metadata to Manifest Cloud
send_metadata_to_cloud() {
    local metadata="$1"
    
    log_operation "cloud_request" "Sending metadata to Manifest Cloud"
    
    local response=$(curl -s --max-time 30 \
        -X POST "$manifest_cloud_endpoint/api/v1/agent/metadata/analyze" \
        -H "Authorization: Bearer $subscription_token" \
        -H "Content-Type: application/json" \
        -d "$metadata")
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        log_operation "cloud_success" "Successfully received response from Manifest Cloud"
        echo "$response"
    else
        log_operation "cloud_failed" "Failed to communicate with Manifest Cloud"
        return 1
    fi
}

# Main command handler
case "${1:-help}" in
    "heartbeat")
        send_heartbeat
        ;;
    "analyze")
        local version="$2"
        local changes_file="$3"
        local release_type="$4"
        
        if [ -z "$version" ] || [ -z "$changes_file" ]; then
            echo "Usage: $0 analyze <version> <changes_file> [release_type]"
            exit 1
        fi
        
        local metadata=$(analyze_code_metadata "$version" "$changes_file" "$release_type")
        send_metadata_to_cloud "$metadata"
        ;;
    "help"|*)
        echo "Manifest Agent Script"
        echo "===================="
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  heartbeat                    - Send heartbeat to Manifest Cloud"
        echo "  analyze <version> <file> [type] - Analyze code and send metadata"
        echo "  help                         - Show this help"
        ;;
esac
EOF
    
    chmod +x "$AGENT_DIR/manifest-agent-script"
    log_success "Script agent created"
}

# generate_agent_id() and log_operation() - Now available from manifest-shared-functions.sh

# GitHub OAuth setup (on-demand)
setup_github_auth() {
    log_info "Setting up GitHub OAuth authentication..."
    
    # Check if GitHub CLI is available
    if ! command -v gh >/dev/null 2>&1; then
        log_error "GitHub CLI (gh) is required for OAuth setup"
        log_info "Install it from: https://cli.github.com/"
        return 1
    fi
    
    # Authenticate with GitHub
    if gh auth status >/dev/null 2>&1; then
        log_info "GitHub CLI already authenticated"
        local token=$(gh auth token)
    else
        log_info "Starting GitHub authentication..."
        gh auth login
        local token=$(gh auth token)
    fi
    
    if [ -n "$token" ]; then
        # Store token in agent config
        jq --arg token "$token" '.github_token = $token' "$AGENT_CONFIG" > "$AGENT_CONFIG.tmp" && mv "$AGENT_CONFIG.tmp" "$AGENT_CONFIG"
        log_success "GitHub authentication configured"
        log_operation "github_auth" "GitHub OAuth configured successfully"
    else
        log_error "Failed to get GitHub token"
        return 1
    fi
}

# Manifest Cloud subscription setup (on-demand)
setup_manifest_auth() {
    log_info "Setting up Manifest Cloud subscription..."
    
    echo "Please visit: https://manifest.cloud/dashboard"
    echo "1. Sign in or create an account"
    echo "2. Get your API key from the dashboard"
    echo "3. Enter it below:"
    echo ""
    
    read -p "Manifest Cloud API Key: " -s api_key
    echo
    
    if [ -z "$api_key" ]; then
        log_error "API key is required"
        return 1
    fi
    
    # Test the API key
    log_info "Testing API key..."
    local response=$(curl -s --max-time 10 \
        -X GET "https://api.manifest.cloud/api/v1/agent/subscription/status" \
        -H "Authorization: Bearer $api_key")
    
    if echo "$response" | jq -e '.status' >/dev/null 2>&1; then
        # Store token in agent config
        jq --arg token "$api_key" '.subscription_token = $token' "$AGENT_CONFIG" > "$AGENT_CONFIG.tmp" && mv "$AGENT_CONFIG.tmp" "$AGENT_CONFIG"
        log_success "Manifest Cloud subscription configured"
        log_operation "manifest_auth" "Manifest Cloud API key configured successfully"
    else
        log_error "Invalid API key or connection failed"
        log_info "Response: $response"
        return 1
    fi
}

# Show agent status
show_agent_status() {
    echo "Manifest Agent Status (Containerized)"
    echo "====================================="
    echo ""
    
    # Check if agent is initialized
    if [ ! -f "$AGENT_CONFIG" ]; then
        echo "Status: Not initialized"
        echo "Run 'manifest agent init <mode>' to initialize"
        echo ""
        echo "Available modes:"
        echo "  docker  - Docker container (most secure)"
        echo "  binary  - Static binary (balanced)"
        echo "  script  - Shell script (most compatible)"
        return 0
    fi
    
    # Load configuration
    local agent_id=$(jq -r '.agent_id // "unknown"' "$AGENT_CONFIG")
    local mode=$(jq -r '.mode // "unknown"' "$AGENT_CONFIG")
    local github_token=$(jq -r '.github_token // empty' "$AGENT_CONFIG")
    local subscription_token=$(jq -r '.subscription_token // empty' "$AGENT_CONFIG")
    local last_operation=$(jq -r '.last_operation // "never"' "$AGENT_CONFIG")
    
    echo "Status: Initialized"
    echo "Mode: $mode (containerized)"
    echo "Agent ID: $agent_id"
    echo "GitHub Auth: $([ -n "$github_token" ] && echo "✅ Configured" || echo "❌ Not configured")"
    echo "Subscription: $([ -n "$subscription_token" ] && echo "✅ Configured" || echo "❌ Not configured")"
    echo "Last Operation: $last_operation"
    echo ""
    echo "Configuration: $AGENT_CONFIG"
    echo "Logs: $AGENT_LOGS"
    echo ""
    echo "Security Features:"
    echo "  ✅ No persistent services"
    echo "  ✅ On-demand execution only"
    echo "  ✅ User-space installation"
    echo "  ✅ Complete operation logging"
    echo "  ✅ No background processes"
}

# Show agent logs
show_agent_logs() {
    if [ ! -d "$AGENT_LOGS" ]; then
        log_error "Agent logs not found. Agent may not be initialized."
        return 1
    fi
    
    echo "=== Agent Operations Log ==="
    if [ -f "$AGENT_LOGS/operations.log" ]; then
        tail -n 20 "$AGENT_LOGS/operations.log"
    else
        echo "No operation logs found"
    fi
}

# Test agent functionality
test_agent() {
    log_info "Testing containerized agent functionality..."
    
    if [ ! -f "$AGENT_CONFIG" ]; then
        log_error "Agent not initialized. Run 'manifest agent init <mode>' first."
        return 1
    fi
    
    local mode=$(jq -r '.mode // "unknown"' "$AGENT_CONFIG")
    
    case "$mode" in
        "docker")
            if [ -f "$AGENT_DIR/manifest-agent-docker" ]; then
                log_info "Testing Docker agent..."
                "$AGENT_DIR/manifest-agent-docker" heartbeat
            else
                log_error "Docker agent not found"
                return 1
            fi
            ;;
        "binary")
            if [ -f "$AGENT_DIR/manifest-agent-binary" ]; then
                log_info "Testing binary agent..."
                "$AGENT_DIR/manifest-agent-binary" heartbeat
            else
                log_error "Binary agent not found"
                return 1
            fi
            ;;
        "script")
            if [ -f "$AGENT_DIR/manifest-agent-script" ]; then
                log_info "Testing script agent..."
                "$AGENT_DIR/manifest-agent-script" heartbeat
            else
                log_error "Script agent not found"
                return 1
            fi
            ;;
        *)
            log_error "Unknown agent mode: $mode"
            return 1
            ;;
    esac
}

# Uninstall agent completely
uninstall_agent() {
    log_info "Uninstalling containerized agent..."
    
    # Remove agent directory
    if [ -d "$AGENT_DIR" ]; then
        rm -rf "$AGENT_DIR"
        log_success "Agent directory removed"
    fi
    
    log_success "Containerized agent uninstalled completely"
    log_info "No system services, no background processes - clean removal"
}

# Main agent command handler
agent_main() {
    case "${1:-help}" in
        "init")
            local mode="${2:-script}"
            case "$mode" in
                "docker"|"binary"|"script")
                    init_agent "$mode"
                    ;;
                *)
                    echo "Usage: manifest agent init {docker|binary|script}"
                    echo ""
                    echo "Modes:"
                    echo "  docker  - Docker container (most secure, requires Docker)"
                    echo "  binary  - Static binary (balanced, downloads from GitHub)"
                    echo "  script  - Shell script (most compatible, no dependencies)"
                    ;;
            esac
            ;;
        "auth")
            case "${2:-}" in
                "github")
                    setup_github_auth
                    ;;
                "manifest")
                    setup_manifest_auth
                    ;;
                *)
                    echo "Usage: manifest agent auth {github|manifest}"
                    ;;
            esac
            ;;
        "status")
            show_agent_status
            ;;
        "logs")
            show_agent_logs
            ;;
        "test")
            test_agent
            ;;
        "uninstall")
            uninstall_agent
            ;;
        "help"|"-h"|"--help"|*)
            echo "Manifest Agent (Containerized)"
            echo "============================="
            echo ""
            echo "Usage: manifest agent <command>"
            echo ""
            echo "Commands:"
            echo "  init <mode>                 - Initialize agent (docker|binary|script)"
            echo "  auth github                 - Set up GitHub OAuth authentication"
            echo "  auth manifest               - Set up Manifest Cloud subscription"
            echo "  status                      - Show agent status and configuration"
            echo "  logs                        - Show agent operation logs"
            echo "  test                        - Test agent functionality"
            echo "  uninstall                   - Remove agent completely"
            echo ""
            echo "Security Features:"
            echo "  ✅ No persistent services"
            echo "  ✅ On-demand execution only"
            echo "  ✅ User-space installation"
            echo "  ✅ Complete operation logging"
            echo "  ✅ No background processes"
            echo ""
            echo "Examples:"
            echo "  manifest agent init docker"
            echo "  manifest agent auth github"
            echo "  manifest agent status"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    agent_main "$@"
fi