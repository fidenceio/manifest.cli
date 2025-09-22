#!/bin/bash

# Manifest MCP Connector Module (Simplified)
# Model Context Protocol connector for Manifest Cloud API

# Source MCP utilities
MANIFEST_CLI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MANIFEST_CLI_SCRIPT_DIR/manifest-mcp-utils.sh"

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
    
    # Try to use containerized agent first (most secure)
    if is_containerized_agent_available; then
        log_info "Containerized agent detected, using secure local agent communication"
        if send_via_containerized_agent "$version" "$changes_file" "$release_type"; then
            return 0
        fi
        log_warning "Containerized agent communication failed, falling back to direct MCP"
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

# Check if containerized agent is available
is_containerized_agent_available() {
    local agent_dir="$HOME/.manifest-agent"
    local agent_config="$agent_dir/config.json"
    
    # Check if agent is initialized
    if [ ! -f "$agent_config" ]; then
        log_debug "Containerized agent not initialized"
        return 1
    fi
    
    # Check if agent has subscription token
    local subscription_token=$(jq -r '.subscription_token // empty' "$agent_config")
    if [ -z "$subscription_token" ]; then
        log_debug "Containerized agent has no subscription token"
        return 1
    fi
    
    # Check if agent executable exists
    local mode=$(jq -r '.mode // "unknown"' "$agent_config")
    case "$mode" in
        "docker")
            [ -f "$agent_dir/manifest-agent-docker" ]
            ;;
        "binary")
            [ -f "$agent_dir/manifest-agent-binary" ]
            ;;
        "script")
            [ -f "$agent_dir/manifest-agent-script" ]
            ;;
        *)
            log_debug "Unknown containerized agent mode: $mode"
            return 1
            ;;
    esac
}

# Use containerized agent for cloud communication
send_via_containerized_agent() {
    local version="$1"
    local changes_file="$2"
    local release_type="${3:-patch}"
    
    log_info "Using containerized agent for secure cloud communication..."
    
    # Check if agent is available
    if ! is_containerized_agent_available; then
        log_warning "Containerized agent not available, falling back to direct MCP connection"
        return 1
    fi
    
    # Get agent configuration
    local agent_dir="$HOME/.manifest-agent"
    local agent_config="$agent_dir/config.json"
    local mode=$(jq -r '.mode // "unknown"' "$agent_config")
    
    # Execute agent based on mode
    case "$mode" in
        "docker")
            if [ -f "$agent_dir/manifest-agent-docker" ]; then
                log_info "Executing Docker-based agent..."
                if "$agent_dir/manifest-agent-docker" analyze "$version" "$changes_file" "$release_type"; then
                    log_success "Documentation generated via Docker agent"
                    return 0
                fi
            fi
            ;;
        "binary")
            if [ -f "$agent_dir/manifest-agent-binary" ]; then
                log_info "Executing binary agent..."
                if "$agent_dir/manifest-agent-binary" analyze "$version" "$changes_file" "$release_type"; then
                    log_success "Documentation generated via binary agent"
                    return 0
                fi
            fi
            ;;
        "script")
            if [ -f "$agent_dir/manifest-agent-script" ]; then
                log_info "Executing script agent..."
                if "$agent_dir/manifest-agent-script" analyze "$version" "$changes_file" "$release_type"; then
                    log_success "Documentation generated via script agent"
                    return 0
                fi
            fi
            ;;
    esac
    
    log_warning "Containerized agent execution failed, falling back to local generation"
    return 1
}

# Fallback to local documentation generation
fallback_to_local_docs() {
    local version="$1"
    local changes_file="$2"
    local release_type="${3:-patch}"
    
    log_info "Using local documentation generation as fallback..."
    
    # Check if local documentation module is available
    if [ -f "$SCRIPT_DIR/manifest-documentation.sh" ]; then
        # Source the local documentation module
        source "$(dirname "$(get_script_dir)")/docs/manifest-documentation.sh"
        
        # Generate documentation locally with NTP timestamp
        get_ntp_timestamp >/dev/null
        local timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
        
        log_info "Generating documentation locally for version $version..."
        
        # Generate release notes
        if generate_release_notes "$version" "$timestamp"; then
            log_success "Release notes generated locally"
        else
            log_warning "Failed to generate release notes locally"
        fi
        
        # Generate changelog
        if generate_changelog "$version" "$timestamp"; then
            log_success "Changelog generated locally"
        else
            log_warning "Failed to generate changelog locally"
        fi
        
        # Update README
        if update_readme "$version" "$timestamp"; then
            log_success "README updated locally"
        else
            log_warning "Failed to update README locally"
        fi
        
        # Generate index
        if generate_index; then
            log_success "Index generated locally"
        else
            log_warning "Failed to generate index locally"
        fi
        
        log_success "Local documentation generation completed"
        return 0
    else
        log_error "Local documentation module not available"
        return 1
    fi
}
