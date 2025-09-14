#!/bin/bash

# Manifest Documentation Module
# Orchestrates document generation using atomized modules

# Documentation module - uses PROJECT_ROOT from core module

DOCS_DIR="$PROJECT_ROOT/docs"

# Import required modules
SCRIPT_DIR="$(get_script_dir)"
source "$(dirname "$SCRIPT_DIR")/git/manifest-git-changes.sh"
source "$(dirname "$SCRIPT_DIR")/docs/manifest-markdown-templates.sh"
source "$(dirname "$SCRIPT_DIR")/docs/manifest-markdown-validation.sh"

# Generate release notes
generate_release_notes() {
    local version="$1"
    local timestamp="$2"
    local release_type="$3"
    local changes_file="$4"
    
    log_info "Generating release notes for v$version..."
    
    local release_file="$DOCS_DIR/RELEASE_v$version.md"
    
    # Generate template
    local content=$(generate_release_notes_template "$version" "$timestamp" "$release_type")
    
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
    
    local changelog_file="$DOCS_DIR/CHANGELOG_v$version.md"
    
    # Generate template
    local content=$(generate_changelog_template "$version" "$timestamp" "$release_type")
    
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
    
    # Generate version section
    local version_section=$(generate_readme_version_section "$version" "$timestamp")
    
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
    
    local index_file="$DOCS_DIR/INDEX.md"
    
    cat > "$index_file" << EOF
# Manifest CLI Documentation

**Version:** $version  
**Last Updated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## 📚 Available Documentation

### Core Documentation
- [User Guide](USER_GUIDE.md) - Complete usage guide
- [Command Reference](COMMAND_REFERENCE.md) - All commands and options
- [Examples](EXAMPLES.md) - Usage examples and workflows
- [Installation Guide](INSTALLATION.md) - Installation instructions

### Release Information
- [Latest Release](RELEASE_v$version.md) - Current release notes
- [Latest Changelog](CHANGELOG_v$version.md) - Current changelog

### Archived Documentation
- [Archived Releases](zArchive/) - Previous release documentation

## 🚀 Quick Start

\`\`\`bash
# Install Manifest CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash

# Run complete workflow
manifest go

# Get help
manifest --help
\`\`\`

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | \`$version\` |
| **Documentation Version** | \`$version\` |
| **Last Updated** | \`$(date -u +"%Y-%m-%d %H:%M:%S UTC")\` |

---
*Generated by Manifest CLI v$version*
EOF
    
    log_success "Documentation index generated: $index_file"
}

# Update repository metadata
update_repository_metadata() {
    log_info "Updating repository metadata..."
    
    # This is a placeholder for repository metadata updates
    # Could include updating GitHub repository description, topics, etc.
    # For now, just log that it's being called
    log_success "Repository metadata update completed"
}

# Main document generation function
generate_documents() {
    local version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"
    
    log_info "Starting document generation for version $version..."
    
    # Ensure docs directory exists
    mkdir -p "$DOCS_DIR"
    
    # Create temporary changes file
    local changes_file=$(mktemp)
    
    # Get and analyze changes
    get_git_changes "$version" > "$changes_file"
    analyze_changes "$version" "$changes_file"
    
    # Generate documents
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
            local timestamp="${3:-$(date -u +"%Y-%m-%d %H:%M:%S UTC")}"
            local release_type="${4:-patch}"
            
            if [[ -z "$version" ]]; then
                show_required_arg_error "Version" "generate <version> [timestamp] [release_type]"
            fi
            
            generate_documents "$version" "$timestamp" "$release_type"
            ;;
        "analyze")
            local version="${2:-}"
            if [[ -z "$version" ]]; then
                show_required_arg_error "Version" "analyze <version>"
            fi
            
            local changes_file=$(mktemp)
            get_git_changes "$version" > "$changes_file"
            analyze_changes "$version" "$changes_file"
            cat "$changes_file"
            rm -f "$changes_file"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Documentation Module"
            echo "============================"
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  generate <version> [timestamp] [type]  - Generate all documents"
            echo "  analyze <version>                      - Analyze changes only"
            echo "  help                                   - Show this help"
            echo ""
            echo "Release Types:"
            echo "  patch, minor, major"
            echo ""
            echo "Examples:"
            echo "  $0 generate 15.28.0"
            echo "  $0 generate 15.28.0 '2025-01-27 10:00:00 UTC' minor"
            echo "  $0 analyze 15.28.0"
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
