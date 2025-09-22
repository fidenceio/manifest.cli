#!/bin/bash

# Manifest Documentation Module
# Simplified, atomic documentation generation

# Docs module - uses PROJECT_ROOT from core module

# Logging functions are sourced from manifest-shared-functions.sh

# Source core functions if available
if [[ -f "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-functions.sh" ]]; then
    source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-functions.sh"
fi

# Source required modules using environment variables
source "$MANIFEST_CLI_CORE_MODULES_DIR/git/manifest-git-changes.sh"
source "$MANIFEST_CLI_CORE_MODULES_DIR/docs/manifest-markdown-validation.sh"

# Source core modules for missing functions
if [[ -f "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-utils.sh" ]]; then
    source "$MANIFEST_CLI_CORE_MODULES_DIR/core/manifest-shared-utils.sh"
fi
if [[ -f "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-ntp.sh" ]]; then
    source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-ntp.sh"
fi

# Project metadata variables
PROJECT_NAME=""
PROJECT_TYPE=""
PROJECT_DESCRIPTION=""
PROJECT_VERSION=""

# Get docs directory using environment variable (consistent with core)
get_docs_folder() {
    echo "${MANIFEST_CLI_DOCS_FOLDER:-docs}"
}

# Detect project type
detect_project_type() {
    local project_root="$1"
    
    if [[ ! -d "$project_root" ]]; then
        echo "unknown"
        return 1
    fi
    
    cd "$project_root" || return 1
    
    # Check for Manifest CLI project (special case)
    if [[ -f "manifest-cli-wrapper.sh" && -d "modules" && -f "VERSION" ]]; then
        echo "manifest"
        return 0
    fi
    
    # Check for Python project
    if [[ -f "setup.py" || -f "pyproject.toml" || -f "requirements.txt" ]]; then
        echo "python"
        return 0
    fi
    
    # Check for Node.js project
    if [[ -f "package.json" ]]; then
        echo "nodejs"
        return 0
    fi
    
    # Check for Go project
    if [[ -f "go.mod" || -f "go.sum" ]]; then
        echo "go"
        return 0
    fi
    
    # Check for Rust project
    if [[ -f "Cargo.toml" || -f "Cargo.lock" ]]; then
        echo "rust"
        return 0
    fi
    
    # Check for Java project
    if [[ -f "pom.xml" || -f "build.gradle" ]]; then
        echo "java"
        return 0
    fi
    
    # Check for Shell project
    if [[ -f "*.sh" && ! -f "package.json" && ! -f "setup.py" ]]; then
        echo "shell"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# Extract project name
extract_project_name() {
    local project_root="$1"
    local project_type="$2"
    
    cd "$project_root" || return 1
    
    case "$project_type" in
        "python")
            if [[ -f "setup.py" ]]; then
                grep -E "^\s*name\s*=" setup.py 2>/dev/null | sed 's/.*name\s*=\s*["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/' | head -1
            elif [[ -f "pyproject.toml" ]]; then
                grep -E "^\s*name\s*=" pyproject.toml 2>/dev/null | sed 's/.*name\s*=\s*["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/' | head -1
            fi
            ;;
        "nodejs")
            if [[ -f "package.json" ]]; then
                grep -E '"name"\s*:' package.json 2>/dev/null | sed 's/.*"name"\s*:\s*"\([^"]*\)".*/\1/' | head -1
            fi
            ;;
        "go")
            if [[ -f "go.mod" ]]; then
                grep -E "^module\s+" go.mod 2>/dev/null | sed 's/^module\s\+\(.*\)/\1/' | head -1
            fi
            ;;
        "rust")
            if [[ -f "Cargo.toml" ]]; then
                grep -E "^name\s*=" Cargo.toml 2>/dev/null | sed 's/^name\s*=\s*"\([^"]*\)".*/\1/' | head -1
            fi
            ;;
        "java")
            if [[ -f "pom.xml" ]]; then
                grep -E "<artifactId>" pom.xml 2>/dev/null | head -1 | sed 's/.*<artifactId>\([^<]*\)<\/artifactId>.*/\1/'
            fi
            ;;
        "manifest")
            echo "Manifest CLI"
            ;;
        *)
            # Try to extract from README
            if [[ -f "README.md" ]]; then
                grep -E "^#\s+" README.md 2>/dev/null | head -1 | sed 's/^#\s*//'
            else
                basename "$project_root"
            fi
            ;;
    esac
}

# Extract project description
extract_project_description() {
    local project_root="$1"
    local project_type="$2"
    
    cd "$project_root" || return 1
    
    case "$project_type" in
        "python")
            if [[ -f "setup.py" ]]; then
                grep -E "^\s*description\s*=" setup.py 2>/dev/null | sed 's/.*description\s*=\s*["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/' | head -1
            elif [[ -f "pyproject.toml" ]]; then
                grep -E "^\s*description\s*=" pyproject.toml 2>/dev/null | sed 's/.*description\s*=\s*["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/' | head -1
            fi
            ;;
        "nodejs")
            if [[ -f "package.json" ]]; then
                grep -E '"description"\s*:' package.json 2>/dev/null | sed 's/.*"description"\s*:\s*"\([^"]*\)".*/\1/' | head -1
            fi
            ;;
        "rust")
            if [[ -f "Cargo.toml" ]]; then
                grep -E "^description\s*=" Cargo.toml 2>/dev/null | sed 's/^description\s*=\s*"\([^"]*\)".*/\1/' | head -1
            fi
            ;;
        "manifest")
            echo "A powerful CLI tool for versioning, AI documenting, and repository operations"
            ;;
        *)
            # Try to extract from README
            if [[ -f "README.md" ]]; then
                grep -A 5 -E "^#\s+" README.md 2>/dev/null | grep -v "^#" | head -1 | sed 's/^[[:space:]]*//'
            fi
            ;;
    esac
}

# Get project information
get_project_info() {
    local project_root="$1"
    
    log_info "Detecting project information..."
    
    PROJECT_TYPE=$(detect_project_type "$project_root")
    PROJECT_NAME=$(extract_project_name "$project_root" "$PROJECT_TYPE")
    PROJECT_DESCRIPTION=$(extract_project_description "$project_root" "$PROJECT_TYPE")
    
    # Get version from VERSION file
    if [[ -f "$project_root/VERSION" ]]; then
        PROJECT_VERSION=$(cat "$project_root/VERSION" 2>/dev/null || echo "")
    fi
    
    # Repository information is available via get_git_info "url" function
    
    log_success "Project detection completed"
    log_info "Project: $PROJECT_NAME ($PROJECT_TYPE)"
    log_info "Description: $PROJECT_DESCRIPTION"
    log_info "Version: $PROJECT_VERSION"
    
    return 0
}

# Get project metadata value
get_project_metadata() {
    local key="$1"
    case "$key" in
        "name") echo "$PROJECT_NAME" ;;
        "type") echo "$PROJECT_TYPE" ;;
        "description") echo "$PROJECT_DESCRIPTION" ;;
        "version") echo "$PROJECT_VERSION" ;;
        "repository") get_git_info "url" ;;
        *) echo "" ;;
    esac
}

# Load template from documentation_templates directory
load_template() {
    local template_name="$1"
    local project_root="$2"
    local template_file="$project_root/${MANIFEST_CLI_DOCS_TEMPLATE_DIR:-documentation_templates}/${template_name}.template"
    
    if [[ -f "$template_file" ]]; then
        log_info "Using custom template: $template_file"
        # Read template and substitute variables
        local template_content=$(cat "$template_file")
        # Get current timestamp for substitution
        local current_timestamp=$(get_formatted_timestamp 2>/dev/null || echo "$4")
        
        echo "$template_content" | sed -e "s/\${version}/$3/g" \
                                      -e "s/\${timestamp}/$4/g" \
                                      -e "s/\${release_type}/$5/g" \
                                      -e "s/\${project_name}/$6/g" \
                                      -e "s/\${project_description}/$7/g" \
                                      -e "s/\${project_type}/$8/g" \
                                      -e "s|\${PROJECT_REPOSITORY}|$(get_git_info "url")|g" \
                                      -e "s|\$(get_formatted_timestamp)|$current_timestamp|g"
        return 0
    fi
    
    # Fall back to default template
    generate_default_template "$template_name" "$@"
}

# Generate default template
generate_default_template() {
    local template_name="$1"
    shift
    
    case "$template_name" in
        "release_notes")
            generate_release_notes_template "$@"
            ;;
        "changelog")
            generate_changelog_template "$@"
            ;;
        "readme_version")
            generate_readme_version_template "$@"
            ;;
        "docs_index")
            generate_docs_index_template "$@"
            ;;
        *)
            log_error "Unknown template: $template_name"
            return 1
            ;;
    esac
}

# Generate release notes template
generate_release_notes_template() {
    local version="$1"
    local timestamp="$2"
    local release_type="$3"
    local project_name="$4"
    local project_description="$5"
    local project_type="$6"
    
    cat << EOF
# Release v${version}

**Release Date:** ${timestamp}  
**Release Type:** ${release_type}  
**Project:** ${project_name}

## 🎯 What's New

This release includes various improvements and bug fixes for ${project_name}.

## 🔧 Changes

- General improvements and bug fixes
- Enhanced functionality
- Improved error handling

## 🚀 Getting Started

\`\`\`bash
# Clone the repository
git clone $(get_git_info "url")
cd ${project_name}

# Follow the instructions in README.md
\`\`\`

## 📋 Usage

\`\`\`bash
# Basic usage
./${project_name}

# With options
./${project_name} --help
\`\`\`

## 📚 Documentation

- [User Guide]($(basename "$(get_docs_folder)")/USER_GUIDE.md)
- [Command Reference]($(basename "$(get_docs_folder)")/COMMAND_REFERENCE.md)
- [Examples]($(basename "$(get_docs_folder)")/EXAMPLES.md)

## 🔗 Links

- [GitHub Repository]($(get_git_info "url"))
- [Issues]($(get_git_info "url")/issues)
- [Discussions]($(get_git_info "url")/discussions)

---
*Generated by Manifest CLI v${version}*
EOF
}

# Generate changelog template
generate_changelog_template() {
    local version="$1"
    local timestamp="$2"
    local release_type="$3"
    local project_name="$4"
    
    cat << EOF
# Changelog v${version}

**Release Date:** ${timestamp}  
**Release Type:** ${release_type}  
**Project:** ${project_name}

## 🆕 New Features

- Enhanced functionality
- Improved error handling
- Better cross-platform compatibility

## 🔧 Improvements

- Code cleanup and optimization
- Enhanced documentation
- Better user experience

## 🐛 Bug Fixes

- Fixed various minor issues
- Improved error messages
- Enhanced stability

## 📚 Documentation

- Updated user guide
- Enhanced examples
- Improved command reference

## 🔄 Changes

- Updated dependencies
- Improved performance
- Enhanced security

---
*Generated by Manifest CLI v${version}*
EOF
}

# Generate README version template
generate_readme_version_template() {
    local version="$1"
    local timestamp="$2"
    local project_name="$3"
    local project_type="$4"
    
    cat << EOF
## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | \`${version}\` |
| **Release Date** | \`${timestamp}\` |
| **Git Tag** | \`v${version}\` |
| **Branch** | \`main\` |
| **Last Updated** | \`${timestamp}\` |
| **Project Type** | \`${project_type}\` |

### 📚 Documentation Files

- **Version Info**: [VERSION](VERSION)
- **Project Source**: [src/](src/) or [lib/](lib/) or [app/](app/)
EOF
}

# Generate docs index template
generate_docs_index_template() {
    local version="$1"
    local project_name="$2"
    local project_description="$3"
    local project_type="$4"
    
    cat << EOF
# ${project_name} Documentation

**Version:** ${version}  
**Last Updated:** $(get_formatted_timestamp)  
**Project Type:** ${project_type}

## 📚 Available Documentation

### Core Documentation
- [User Guide](USER_GUIDE.md) - Complete usage guide
- [Command Reference](COMMAND_REFERENCE.md) - All commands and options
- [Examples](EXAMPLES.md) - Usage examples and workflows
- [Installation Guide](INSTALLATION.md) - Installation instructions

### Release Information
- [Latest Release](RELEASE_v${version}.md) - Current release notes
- [Latest Changelog](CHANGELOG_v${version}.md) - Current changelog

### Archived Documentation
- [Archived Releases](zArchive/) - Previous release documentation

## 🚀 Quick Start

\`\`\`bash
# Clone and explore
git clone $(get_git_info "url")
cd ${project_name}
ls -la
\`\`\`

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | \`${version}\` |
| **Documentation Version** | \`${version}\` |
| **Last Updated** | \`$(get_formatted_timestamp)\` |
| **Project Type** | \`${project_type}\` |

---
*Generated by Manifest CLI v${version}*
EOF
}

# Generate release notes
generate_release_notes() {
    local version="$1"
    local timestamp="$2"
    local release_type="$3"
    local changes_file="$4"
    
    log_info "Generating release notes for v$version..."
    
    local release_file="$(get_docs_folder)/RELEASE_v$version.md"
    
    # Get project metadata
    local project_name=$(get_project_metadata "name")
    local project_description=$(get_project_metadata "description")
    local project_type=$(get_project_metadata "type")
    
    # Generate template using template system
    local content=$(load_template "release_notes" "$PROJECT_ROOT" "$version" "$timestamp" "$release_type" "$project_name" "$project_description" "$project_type")
    
    # Add actual changes if available
    if [[ -f "$changes_file" ]]; then
        local changes=$(cat "$changes_file" | sed 's/\x1b\[[0-9;]*m//g')  # Remove color codes
        # Append changes to the end of the document
        content="${content}

## 🔧 Actual Changes

${changes}"
    fi
    
    # Write the file with proper newline
    echo "$content" > "$release_file"
    echo "" >> "$release_file"
    
    if [[ -f "$release_file" ]]; then
        log_success "Release notes generated: $release_file"
        return 0
    else
        log_error "Failed to generate release notes"
        return 1
    fi
}

# Generate changelog
generate_changelog() {
    local version="$1"
    local timestamp="$2"
    local release_type="$3"
    local changes_file="$4"
    
    log_info "Generating changelog for v$version..."
    
    local changelog_file="$(get_docs_folder)/CHANGELOG_v$version.md"
    
    # Get project metadata
    local project_name=$(get_project_metadata "name")
    
    # Generate template using template system
    local content=$(load_template "changelog" "$PROJECT_ROOT" "$version" "$timestamp" "$release_type" "$project_name")
    
    # Add actual changes if available
    if [[ -f "$changes_file" ]]; then
        local changes=$(cat "$changes_file" | sed 's/\x1b\[[0-9;]*m//g')  # Remove color codes
        # Append changes to the end of the document
        content="${content}

## 🔧 Actual Changes

${changes}"
    fi
    
    # Write the file with proper newline
    echo "$content" > "$changelog_file"
    echo "" >> "$changelog_file"
    
    if [[ -f "$changelog_file" ]]; then
        log_success "Changelog generated: $changelog_file"
        return 0
    else
        log_error "Failed to generate changelog"
        return 1
    fi
}

# Update README version information
update_readme_version() {
    local version="$1"
    local timestamp="$2"
    
    log_info "Updating README version information..."
    
    local readme_file="$PROJECT_ROOT/README.md"
    
    if [[ ! -f "$readme_file" ]]; then
        log_warning "README.md not found, skipping version update"
        return 0
    fi
    
    # Get project metadata
    local project_name=$(get_project_metadata "name")
    local project_type=$(get_project_metadata "type")
    
    # Generate version section using template system
    local version_section=$(load_template "readme_version" "$PROJECT_ROOT" "$version" "$timestamp" "$project_name" "$project_type")
    
    # Update README
    local temp_file=$(mktemp)
    
    # Replace or add version section
    if grep -q "## 📋 Version Information" "$readme_file"; then
        # Replace existing version section using sed
        local version_section_file=$(mktemp)
        echo "$version_section" > "$version_section_file"
        
        # Find the start and end of the version section
        local start_line=$(grep -n "## 📋 Version Information" "$readme_file" | cut -d: -f1)
        local end_line=$(tail -n +$((start_line + 1)) "$readme_file" | grep -n "^## " | head -1 | cut -d: -f1)
        
        if [[ -n "$end_line" ]]; then
            end_line=$((start_line + end_line - 1))
        else
            end_line=$(wc -l < "$readme_file")
        fi
        
        # Create new file with replacement
        head -n $((start_line - 1)) "$readme_file" > "$temp_file"
        cat "$version_section_file" >> "$temp_file"
        tail -n +$((end_line + 1)) "$readme_file" >> "$temp_file"
        
        rm -f "$version_section_file"
    else
        # Add version section at the beginning
        echo "$version_section" > "$temp_file"
        echo "" >> "$temp_file"
        cat "$readme_file" >> "$temp_file"
    fi
    
    # Replace original file
    mv "$temp_file" "$readme_file"
    
    log_success "README version information updated"
}

# Generate documentation index
generate_docs_index() {
    local version="$1"
    
    log_info "Generating documentation index..."
    
    local index_file="$(get_docs_folder)/INDEX.md"
    
    # Get project metadata
    local project_name=$(get_project_metadata "name")
    local project_description=$(get_project_metadata "description")
    local project_type=$(get_project_metadata "type")
    
    # Generate template using template system
    local content=$(load_template "docs_index" "$PROJECT_ROOT" "$version" "$project_name" "$project_description" "$project_type")
    
    # Write the file
    echo "$content" > "$index_file"
    
    if [[ -f "$index_file" ]]; then
        log_success "Documentation index generated: $index_file"
        return 0
    else
        log_error "Failed to generate documentation index"
        return 1
    fi
}

# Main document generation function
generate_documents() {
    local version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"
    
    log_info "Starting document generation for version $version..."
    
    # Detect project information
    if ! get_project_info "$PROJECT_ROOT"; then
        log_warning "Project detection failed, using generic templates"
    fi
    
    # Ensure docs directory exists
    mkdir -p "$(get_docs_folder)"
    
    # Create temporary changes file
    local changes_file=$(mktemp)
    
    # Get and analyze changes
    get_git_changes "$version" > "$changes_file"
    analyze_changes "$version" "$changes_file"
    
    # Generate documents using template system
    if ! generate_release_notes "$version" "$timestamp" "$release_type" "$changes_file"; then
        log_warning "Release notes generation failed, but continuing..."
    fi
    if ! generate_changelog "$version" "$timestamp" "$release_type" "$changes_file"; then
        log_warning "Changelog generation failed, but continuing..."
    fi
    if ! update_readme_version "$version" "$timestamp"; then
        log_warning "README version update failed, but continuing..."
    fi
    if ! generate_docs_index "$version"; then
        log_warning "Documentation index generation failed, but continuing..."
    fi
    
    # Clean up
    rm -f "$changes_file"
    
    log_success "Document generation completed for version $version"
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "generate")
            local version="${2:-}"
            local timestamp="${3:-}"
            
            # Get NTP timestamp if not provided
            if [ -z "$timestamp" ]; then
                get_ntp_timestamp >/dev/null
                timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            fi
            local release_type="${4:-patch}"
            
            if [[ -z "$version" ]]; then
                echo "Usage: $0 generate <version> [timestamp] [release_type]"
                return 1
            fi
            
            generate_documents "$version" "$timestamp" "$release_type"
            ;;
        "detect")
            get_project_info "$PROJECT_ROOT"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Documentation Module"
            echo "============================"
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  generate <version> [timestamp] [type]  - Generate all documents"
            echo "  detect                                 - Detect project information"
            echo "  help                                   - Show this help"
            echo ""
            echo "Release Types:"
            echo "  patch, minor, major"
            echo ""
            echo "Examples:"
            echo "  $0 generate 1.0.0"
            echo "  $0 generate 1.0.0 '2025-01-01 12:00:00 UTC' minor"
            echo "  $0 detect"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
