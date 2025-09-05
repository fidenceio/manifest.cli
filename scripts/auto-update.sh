#!/bin/bash

# Manifest CLI Auto-Update Script
# Checks for latest version and updates if needed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/fidenceio/manifest.cli"
REPO_API_URL="https://api.github.com/repos/fidenceio/manifest.cli"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh"
VERSION_FILE_URL="https://raw.githubusercontent.com/fidenceio/manifest.cli/main/VERSION"

# Get current version
get_current_version() {
    if [ -f "$HOME/.manifest-cli/VERSION" ]; then
        cat "$HOME/.manifest-cli/VERSION"
    elif [ -f "./VERSION" ]; then
        cat "./VERSION"
    else
        echo "0.0.0"
    fi
}

# Get latest version from GitHub
get_latest_version() {
    local latest_version=""
    
    # Try to get from GitHub API first
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s "$REPO_API_URL/releases/latest" | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$' | sed 's/^v//')
    fi
    
    # Fallback to direct VERSION file
    if [ -z "$latest_version" ] && command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s "$VERSION_FILE_URL" | tr -d '\n\r')
    fi
    
    # Fallback to git if available
    if [ -z "$latest_version" ] && command -v git >/dev/null 2>&1; then
        latest_version=$(git ls-remote --tags "$REPO_URL.git" | grep -o 'refs/tags/v[0-9]*\.[0-9]*\.[0-9]*' | sort -V | tail -1 | sed 's/refs\/tags\/v//')
    fi
    
    echo "$latest_version"
}

# Compare versions (returns 0 if v1 >= v2, 1 otherwise)
version_compare() {
    local v1="$1"
    local v2="$2"
    
    # Remove 'v' prefix if present
    v1=$(echo "$v1" | sed 's/^v//')
    v2=$(echo "$v2" | sed 's/^v//')
    
    # Use sort -V for version comparison
    if [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v2" ]; then
        return 0  # v1 >= v2
    else
        return 1  # v1 < v2
    fi
}

# Download and install latest version
update_cli() {
    echo -e "${BLUE}🔄 Updating Manifest CLI...${NC}"
    
    # Download and run the install script
    if command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}📥 Downloading latest version...${NC}"
        curl -fsSL "$INSTALL_SCRIPT_URL" | bash
    elif command -v wget >/dev/null 2>&1; then
        echo -e "${YELLOW}📥 Downloading latest version...${NC}"
        wget -qO- "$INSTALL_SCRIPT_URL" | bash
    else
        echo -e "${RED}❌ Error: Neither curl nor wget is available${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Manifest CLI updated successfully!${NC}"
}

# Main update check function
check_and_update() {
    local force_update="$1"
    local current_version
    local latest_version
    
    echo -e "${BLUE}🔍 Checking for Manifest CLI updates...${NC}"
    
    # Get current version
    current_version=$(get_current_version)
    echo -e "${YELLOW}📋 Current version: $current_version${NC}"
    
    # Get latest version
    latest_version=$(get_latest_version)
    if [ -z "$latest_version" ]; then
        echo -e "${RED}❌ Error: Could not determine latest version${NC}"
        return 1
    fi
    echo -e "${YELLOW}📋 Latest version: $latest_version${NC}"
    
    # Compare versions
    if [ "$force_update" = "true" ]; then
        echo -e "${YELLOW}🔄 Force update requested...${NC}"
        update_cli
    elif version_compare "$current_version" "$latest_version"; then
        echo -e "${GREEN}✅ Manifest CLI is up to date!${NC}"
        return 0
    else
        echo -e "${YELLOW}🔄 Update available: $current_version → $latest_version${NC}"
        echo -e "${BLUE}📥 Would you like to update? (y/N): ${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            update_cli
        else
            echo -e "${YELLOW}⏭️  Update skipped${NC}"
        fi
    fi
}

# Show help
show_help() {
    echo "Manifest CLI Auto-Update Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force    Force update regardless of current version"
    echo "  -c, --check    Check for updates only (don't update)"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Check and optionally update"
    echo "  $0 --force      # Force update to latest version"
    echo "  $0 --check      # Check version only"
}

# Main script logic
main() {
    local force_update="false"
    local check_only="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_update="true"
                shift
                ;;
            -c|--check)
                check_only="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [ "$check_only" = "true" ]; then
        # Check only mode
        current_version=$(get_current_version)
        latest_version=$(get_latest_version)
        echo -e "${BLUE}📋 Current version: $current_version${NC}"
        echo -e "${BLUE}📋 Latest version: $latest_version${NC}"
        
        if version_compare "$current_version" "$latest_version"; then
            echo -e "${GREEN}✅ Manifest CLI is up to date!${NC}"
            exit 0
        else
            echo -e "${YELLOW}🔄 Update available: $current_version → $latest_version${NC}"
            exit 1
        fi
    else
        # Normal check and update mode
        check_and_update "$force_update"
    fi
}

# Run main function with all arguments
main "$@"
