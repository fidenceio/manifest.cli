#!/bin/bash

# Manifest Documentation Module
# Orchestrates document generation using atomized modules

# Documentation module - uses PROJECT_ROOT from core module

# Get configurable documentation directory
get_docs_dir() {
    get_docs_folder "$PROJECT_ROOT"
}

# Import required modules
MANIFEST_CLI_SCRIPT_DIR="$(get_script_dir)"
source "$(dirname "$MANIFEST_CLI_SCRIPT_DIR")/git/manifest-git-changes.sh"
source "$(dirname "$MANIFEST_CLI_SCRIPT_DIR")/docs/manifest-markdown-templates.sh"
source "$(dirname "$MANIFEST_CLI_SCRIPT_DIR")/docs/manifest-markdown-validation.sh"

# Generate release notes
generate_release_notes() {
    local version="$1"
    local timestamp="$2"
    local release_type="$3"
    local changes_file="$4"
    
    log_info "Generating release notes for v$version..."
    
    local release_file="$(get_docs_dir)/RELEASE_v$version.md"
    
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
    
    local changelog_file="$(get_docs_dir)/CHANGELOG_v$version.md"
    
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
# Preserves user-crafted README content. Only updates inline version strings
# and the version metadata section if one already exists. Never prepends a
# new metadata block to a README that doesn't have one.
update_readme_version() {
    local version="$1"
    local timestamp="$2"

    log_info "Updating README version information..."

    local readme_file="$PROJECT_ROOT/README.md"

    if [[ ! -f "$readme_file" ]]; then
        log_warning "README.md not found, skipping version update"
        return 0
    fi

    local temp_file=$(mktemp)

    if grep -q "## 📋 Version Information" "$readme_file"; then
        # README has a version metadata section — replace it in place
        local version_section=$(generate_readme_version_section "$version" "$timestamp")
        local version_section_file=$(mktemp)
        echo "$version_section" > "$version_section_file"

        local start_line=$(grep -n "## 📋 Version Information" "$readme_file" | head -1 | cut -d: -f1)
        local end_line=$(tail -n +$((start_line + 1)) "$readme_file" | grep -n "^## " | head -1 | cut -d: -f1)

        if [[ -n "$end_line" ]]; then
            end_line=$((start_line + end_line - 1))
        else
            end_line=$(wc -l < "$readme_file")
        fi

        if [[ "$start_line" -gt 1 ]]; then
            head -n $((start_line - 1)) "$readme_file" > "$temp_file"
        else
            : > "$temp_file"
        fi
        cat "$version_section_file" >> "$temp_file"
        tail -n +$((end_line + 1)) "$readme_file" >> "$temp_file"

        rm -f "$version_section_file"
        mv "$temp_file" "$readme_file"
    else
        rm -f "$temp_file"
        # No version metadata section — update inline version strings only.
        # Match patterns like `39.0.0` or **Version** `39.0.0` and update them.
        local old_version=""
        if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
            # The VERSION file already has the new version; derive the old one
            # by looking at what's currently in the README.
            old_version=$(grep -oE '`[0-9]+\.[0-9]+\.[0-9]+`' "$readme_file" | head -1 | tr -d '`')
        fi
        if [[ -n "$old_version" ]] && [[ "$old_version" != "$version" ]]; then
            sed -i'' -e "s|\`${old_version}\`|\`${version}\`|g" "$readme_file"
            # Also update release note links in README (e.g., RELEASE_v39.2.1.md)
            sed -i'' -e "s|RELEASE_v[0-9][0-9.]*\.md|RELEASE_v${version}.md|g" "$readme_file"
            # Clean up sed backup files (macOS creates these)
            rm -f "${readme_file}-e"
            log_debug "Updated inline version references: $old_version -> $version"
        fi
    fi

    log_success "README version information updated"
}

# Generate documentation index
# If an INDEX.md already exists, updates version numbers and release note
# links in place, preserving user-crafted structure and formatting.
# Only creates the file from a template when it doesn't exist at all.
generate_docs_index() {
    local version="$1"

    log_info "Generating documentation index..."

    local index_file="$(get_docs_dir)/INDEX.md"

    if [[ -f "$index_file" ]]; then
        # Preserve existing INDEX.md — only update version references and release links.

        # Update version strings (e.g., `38.2.0` -> `39.0.0`)
        local old_version=""
        old_version=$(grep -oE '`[0-9]+\.[0-9]+\.[0-9]+`' "$index_file" | head -1 | tr -d '`')
        if [[ -n "$old_version" ]] && [[ "$old_version" != "$version" ]]; then
            sed -i'' -e "s|\`${old_version}\`|\`${version}\`|g" "$index_file"
        fi

        # Update **Version:** header line
        sed -i'' -e "s|^\*\*Version:\*\* [0-9][0-9.]*|\*\*Version:\*\* $version|" "$index_file"

        # Update release note file links and display text
        sed -i'' -e "s|RELEASE_v[0-9][0-9.]*\.md|RELEASE_v${version}.md|g" "$index_file"
        sed -i'' -e "s|CHANGELOG_v[0-9][0-9.]*\.md|CHANGELOG_v${version}.md|g" "$index_file"
        # Update version in link display text (e.g., "Release Notes v39.2.1" -> "v39.2.2")
        sed -i'' -e "s|Notes v[0-9][0-9.]*|Notes v${version}|g" "$index_file"
        sed -i'' -e "s|Changelog v[0-9][0-9.]*|Changelog v${version}|g" "$index_file"

        # Update date if present
        local today=$(date -u '+%Y-%m-%d')
        sed -i'' -e "s|^\*\*Updated:\*\* [0-9-]*|\*\*Updated:\*\* $today|" "$index_file"

        # Clean up sed backup files (macOS creates these)
        rm -f "${index_file}-e"

        log_success "Documentation index updated: $index_file"
        return 0
    fi

    # File does not exist — create from template
    cat > "$index_file" << EOF
# Manifest CLI Documentation

**Version:** $version | **Updated:** $(date -u '+%Y-%m-%d')

---

## Getting Started

| Document | Description |
| -------- | ----------- |
| [Installation Guide](INSTALLATION.md) | Setup, upgrade, uninstall, and troubleshooting |
| [User Guide](USER_GUIDE.md) | Workflows, daily commands, and configuration |
| [Examples](EXAMPLES.md) | Real-world workflow recipes |

## Reference

| Document | Description |
| -------- | ----------- |
| [Command Reference](COMMAND_REFERENCE.md) | Every command, flag, and option |
| [Git Hooks](GIT_HOOKS.md) | Pre-commit secret protection and hook management |

## Current Release

| Document | Description |
| -------- | ----------- |
| [Release Notes v${version}](RELEASE_v${version}.md) | What's new in this release |
| [Changelog v${version}](CHANGELOG_v${version}.md) | Detailed change log |
| [Archived Releases](zArchive/) | Previous version documentation |

---

## Quick Start

\`\`\`bash
# Install
brew tap fidenceio/tap && brew install manifest

# Prepare a release locally
manifest prep patch

# Publish a release
manifest ship minor

# Get help
manifest --help
\`\`\`

<!-- Manifest CLI v$version -->
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
    mkdir -p "$(get_docs_dir)"
    
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
            local timestamp="${3:-}"
            
            # Get trusted timestamp if not provided
            if [ -z "$timestamp" ]; then
                get_time_timestamp >/dev/null
                timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            fi
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
