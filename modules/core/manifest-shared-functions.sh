#!/bin/bash

# Manifest Shared Functions Module
# Centralized functions used across multiple modules with clear separation of concerns

# =============================================================================
# VERSION MANAGEMENT FUNCTIONS
# =============================================================================

# Get current version from VERSION file
get_current_version() {
    if [ -f "$PROJECT_ROOT/VERSION" ]; then
        cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Get next version based on increment type
get_next_version() {
    local increment_type="$1"
    local current_version=""
    
    # Read current version
    if [ -f "VERSION" ]; then
        current_version=$(cat VERSION 2>/dev/null || echo "1.0.0")
    else
        current_version="1.0.0"
    fi
    
    # Validate increment type
    case "$increment_type" in
        patch|minor|major|revision)
            ;;
        *)
            show_validation_error "Invalid increment type: $increment_type"
            return 1
            ;;
    esac
    
    # Parse version components
    local major minor patch revision
    IFS='.' read -r major minor patch revision <<< "$current_version"
    
    # Default values if missing
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    revision=${revision:-0}
    
    # Increment based on type
    case "$increment_type" in
        "patch")
            patch=$((patch + 1))
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "revision")
            revision=$((revision + 1))
            ;;
    esac
    
    # Return new version
    if [ "$revision" -gt 0 ]; then
        echo "$major.$minor.$patch.$revision"
    else
        echo "$major.$minor.$patch"
    fi
}

# Get latest version from GitHub API
get_latest_version() {
    local repo_url="${MANIFEST_REPO_URL:-https://api.github.com/repos/fidenceio/fidenceio.manifest.cli/releases/latest}"
    
    # Try to get latest version from GitHub API
    if command -v curl >/dev/null 2>&1; then
        local latest_version=$(curl -s "$repo_url" 2>/dev/null | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4)
        if [ -n "$latest_version" ]; then
            echo "$latest_version"
            return 0
        fi
    fi
    
    # Fallback: return current version
    get_current_version
}

# =============================================================================
# NETWORK AND CONNECTIVITY FUNCTIONS
# =============================================================================

# Check network connectivity
check_network_connectivity() {
    # Try to ping a reliable service
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_debug "Network connectivity check passed"
        return 0
    fi
    
    # Try alternative connectivity check
    if curl -s --max-time 5 --connect-timeout 3 https://www.google.com >/dev/null 2>&1; then
        log_debug "Network connectivity check passed (curl method)"
        return 0
    fi
    
    log_debug "Network connectivity check failed"
    return 1
}

# Check if required tools are available
check_required_tools() {
    local missing_tools=()
    
    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_tools+=("curl")
    fi
    
    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        show_dependency_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    log_debug "All required tools are available"
    return 0
}

# =============================================================================
# ID GENERATION AND LOGGING FUNCTIONS
# =============================================================================

# Generate unique agent ID
generate_agent_id() {
    local hostname=$(hostname)
    local user=$(whoami)
    local timestamp=$(date +%s)
    local random=$(openssl rand -hex 4 2>/dev/null || echo "$RANDOM")
    echo "${hostname}-${user}-${timestamp}-${random}" | tr '[:upper:]' '[:lower:]'
}

# Generate unique session ID
generate_session_id() {
    local timestamp=$(date +%s)
    local random=$(openssl rand -hex 8 2>/dev/null || echo "$RANDOM$RANDOM")
    echo "session-${timestamp}-${random}" | tr '[:upper:]' '[:lower:]'
}

# Log operation with timestamp
log_operation() {
    local operation="$1"
    local details="$2"
    local log_file="${3:-$HOME/.manifest-cli/logs/operations.log}"
    
    # Ensure log directory exists
    local log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir" 2>/dev/null
    
    # Log with timestamp
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - $operation: $details" >> "$log_file"
    log_debug "Operation logged: $operation"
}

# =============================================================================
# GIT OPERATIONS FUNCTIONS
# =============================================================================

# Get Git repository information
get_git_info() {
    local info_type="$1"
    
    case "$info_type" in
        "url")
            git remote get-url origin 2>/dev/null || echo ""
            ;;
        "name")
            local repo_url=$(git remote get-url origin 2>/dev/null || echo "")
            basename "$repo_url" .git 2>/dev/null || echo ""
            ;;
        "owner")
            local repo_url=$(git remote get-url origin 2>/dev/null || echo "")
            echo "$repo_url" | sed -n 's/.*[:/]\([^/]*\)\/\([^/]*\)\.git.*/\1/p'
            ;;
        "branch")
            git branch --show-current 2>/dev/null || echo ""
            ;;
        "commit")
            git rev-parse HEAD 2>/dev/null || echo ""
            ;;
        "status")
            git status --porcelain 2>/dev/null || echo ""
            ;;
        *)
            show_validation_error "Unknown Git info type: $info_type"
            return 1
            ;;
    esac
}

# Check if in Git repository
is_git_repository() {
    git rev-parse --git-dir >/dev/null 2>&1
}

# =============================================================================
# FILE OPERATIONS FUNCTIONS
# =============================================================================

# Safe file read with error handling
safe_read_file() {
    local file="$1"
    local default="${2:-}"
    
    if [ -f "$file" ] && [ -r "$file" ]; then
        cat "$file" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# Safe file write with backup
safe_write_file() {
    local file="$1"
    local content="$2"
    local backup="${3:-true}"
    
    # Create backup if requested
    if [ "$backup" = "true" ] && [ -f "$file" ]; then
        cp "$file" "$file.backup.$(date +%s)" 2>/dev/null
    fi
    
    # Write content
    echo "$content" > "$file" || {
        show_file_error "Failed to write file: $file"
        return 1
    }
    
    log_debug "File written successfully: $file"
    return 0
}

# =============================================================================
# TEMPORARY FILE MANAGEMENT
# =============================================================================

# Create temporary file with cleanup tracking
create_managed_temp_file() {
    local prefix="${1:-manifest-}"
    local temp_file=$(mktemp -t "$prefix.XXXXXXXXXX" 2>/dev/null)
    
    if [ -z "$temp_file" ]; then
        show_file_error "Failed to create temporary file"
        return 1
    fi
    
    # Track for cleanup
    echo "$temp_file" >> "$HOME/.manifest-cli/temp-files.list" 2>/dev/null || true
    
    echo "$temp_file"
}

# Clean up tracked temporary files
cleanup_managed_temp_files() {
    local temp_list="$HOME/.manifest-cli/temp-files.list"
    
    if [ -f "$temp_list" ]; then
        while IFS= read -r temp_file; do
            if [ -f "$temp_file" ]; then
                rm -f "$temp_file" 2>/dev/null
                log_debug "Cleaned up temp file: $temp_file"
            fi
        done < "$temp_list"
        rm -f "$temp_list"
    fi
}

# =============================================================================
# CONFIGURATION MANAGEMENT FUNCTIONS
# =============================================================================

# Get configuration value with fallback
get_config_value() {
    local key="$1"
    local default="${2:-}"
    local config_file="${3:-$PROJECT_ROOT/.env}"
    
    # Try environment variable first
    if [ -n "${!key:-}" ]; then
        echo "${!key}"
        return 0
    fi
    
    # Try config file
    if [ -f "$config_file" ]; then
        local value=$(grep "^${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']\|["'\'']$//g')
        if [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
    fi
    
    # Return default
    echo "$default"
}

# Set configuration value
set_config_value() {
    local key="$1"
    local value="$2"
    local config_file="${3:-$PROJECT_ROOT/.env}"
    
    # Ensure config directory exists
    local config_dir=$(dirname "$config_file")
    mkdir -p "$config_dir" 2>/dev/null
    
    # Update or add configuration
    if [ -f "$config_file" ]; then
        # Update existing key
        if grep -q "^${key}=" "$config_file"; then
            sed -i.bak "s/^${key}=.*/${key}=\"${value}\"/" "$config_file"
            rm -f "$config_file.bak" 2>/dev/null
        else
            # Add new key
            echo "${key}=\"${value}\"" >> "$config_file"
        fi
    else
        # Create new config file
        echo "${key}=\"${value}\"" > "$config_file"
    fi
    
    log_debug "Configuration updated: $key=$value"
}

# =============================================================================
# JSON OPERATIONS FUNCTIONS
# =============================================================================

# Safe JSON read with error handling
safe_json_read() {
    local json_file="$1"
    local key="$2"
    local default="${3:-}"
    
    if [ ! -f "$json_file" ]; then
        echo "$default"
        return 0
    fi
    
    if command -v jq >/dev/null 2>&1; then
        jq -r ".${key} // empty" "$json_file" 2>/dev/null || echo "$default"
    else
        # Fallback to grep/sed
        grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$json_file" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "$default"
    fi
}

# Safe JSON write with validation
safe_json_write() {
    local json_file="$1"
    local key="$2"
    local value="$3"
    
    # Ensure directory exists
    local json_dir=$(dirname "$json_file")
    mkdir -p "$json_dir" 2>/dev/null
    
    if command -v jq >/dev/null 2>&1; then
        # Use jq for proper JSON handling
        if [ -f "$json_file" ]; then
            jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$json_file" > "$json_file.tmp" && mv "$json_file.tmp" "$json_file"
        else
            echo "{\"$key\": \"$value\"}" > "$json_file"
        fi
    else
        # Fallback to manual JSON construction
        show_file_error "jq not available for JSON operations"
        return 1
    fi
}

# =============================================================================
# FILE CREATION AND VALIDATION FUNCTIONS
# =============================================================================

# Check for required files and create them if missing
ensure_required_files() {
    local project_root="${1:-$PROJECT_ROOT}"
    local created_files=()
    
    log_info "Checking for required files in: $project_root"
    
    # Ensure VERSION file exists
    if [ ! -f "$project_root/VERSION" ]; then
        log_info "Creating VERSION file..."
        echo "1.0.0" > "$project_root/VERSION"
        created_files+=("VERSION")
        log_success "Created VERSION file with default version 1.0.0"
    fi
    
    # Ensure README.md exists
    if [ ! -f "$project_root/README.md" ]; then
        log_info "Creating README.md file..."
        create_default_readme "$project_root/README.md"
        created_files+=("README.md")
        log_success "Created README.md file"
    fi
    
    # Ensure docs directory exists
    if [ ! -d "$project_root/docs" ]; then
        log_info "Creating docs directory..."
        mkdir -p "$project_root/docs"
        created_files+=("docs/")
        log_success "Created docs directory"
    fi
    
    # Ensure CHANGELOG.md exists
    if [ ! -f "$project_root/CHANGELOG.md" ]; then
        log_info "Creating CHANGELOG.md file..."
        create_default_changelog "$project_root/CHANGELOG.md"
        created_files+=("CHANGELOG.md")
        log_success "Created CHANGELOG.md file"
    fi
    
    # Ensure .gitignore exists
    if [ ! -f "$project_root/.gitignore" ]; then
        log_info "Creating .gitignore file..."
        create_default_gitignore "$project_root/.gitignore"
        created_files+=(".gitignore")
        log_success "Created .gitignore file"
    fi
    
    # Report results
    if [ ${#created_files[@]} -gt 0 ]; then
        log_success "Created ${#created_files[@]} missing file(s): ${created_files[*]}"
        return 0
    else
        log_info "All required files are present"
        return 0
    fi
}

# Create default README.md content
create_default_readme() {
    local readme_file="$1"
    local project_name=$(basename "$(dirname "$readme_file")")
    local current_version=$(cat "$(dirname "$readme_file")/VERSION" 2>/dev/null || echo "1.0.0")
    
    cat > "$readme_file" << EOF
# $project_name

A project managed with Manifest CLI.

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | \`$current_version\` |
| **Release Date** | \`$(date -u +'%Y-%m-%d %H:%M:%S UTC')\` |
| **Git Tag** | \`v$current_version\` |
| **Branch** | \`$(git branch --show-current 2>/dev/null || echo 'main')\` |
| **Last Updated** | \`$(date -u +'%Y-%m-%d %H:%M:%S UTC')\` |

## 🚀 Getting Started

This project uses Manifest CLI for version management and automated workflows.

### Prerequisites

- Git
- Manifest CLI (install with: \`curl -sSL https://raw.githubusercontent.com/fidenceio/fidenceio.manifest.cli/main/install-cli.sh | bash\`)

### Basic Usage

\`\`\`bash
# Initialize version management
manifest init

# Bump version and create release
manifest go patch

# Generate documentation
manifest docs

# View help
manifest help
\`\`\`

## 📚 Documentation

- **Version Info**: [VERSION](VERSION)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- **Install Script**: [install-cli.sh](install-cli.sh)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run \`manifest go patch\` to version and release
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
EOF
}

# Create default CHANGELOG.md content
create_default_changelog() {
    local changelog_file="$1"
    local current_version=$(cat "$(dirname "$changelog_file")/VERSION" 2>/dev/null || echo "1.0.0")
    
    cat > "$changelog_file" << EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup
- Manifest CLI integration

## [$current_version] - $(date -u +'%Y-%m-%d')

### Added
- Initial release
- Basic project structure
- Version management with Manifest CLI

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A
EOF
}

# Create default .gitignore content
create_default_gitignore() {
    local gitignore_file="$1"
    
    cat > "$gitignore_file" << EOF
# Manifest CLI
.manifest-cli/
*.manifest-cli.log

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo
*~

# Logs
*.log
logs/

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Coverage directory used by tools like istanbul
coverage/

# nyc test coverage
.nyc_output

# Dependency directories
node_modules/
bower_components/

# Optional npm cache directory
.npm

# Optional REPL history
.node_repl_history

# Output of 'npm pack'
*.tgz

# Yarn Integrity file
.yarn-integrity

# dotenv environment variables file
.env
.env.test
.env.local
.env.production

# Temporary files
tmp/
temp/
*.tmp
*.temp

# Build outputs
dist/
build/
out/

# Archive directories
zArchive/
archive/
EOF
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all shared functions
export -f get_current_version get_next_version get_latest_version
export -f check_network_connectivity check_required_tools
export -f generate_agent_id generate_session_id log_operation
export -f get_git_info is_git_repository
export -f safe_read_file safe_write_file
export -f create_managed_temp_file cleanup_managed_temp_files
export -f get_config_value set_config_value
export -f safe_json_read safe_json_write
export -f ensure_required_files create_default_readme create_default_changelog create_default_gitignore
