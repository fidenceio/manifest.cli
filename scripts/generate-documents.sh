#!/bin/bash

# Document Generation Script
# Reviews code changes and generates documentation for new versions

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$PROJECT_ROOT/docs"

# Import markdown engine
MARKDOWN_ENGINE="$SCRIPT_DIR/markdown-engine.sh"
if [[ -f "$MARKDOWN_ENGINE" ]]; then
    source "$MARKDOWN_ENGINE"
else
    echo "❌ Markdown engine not found: $MARKDOWN_ENGINE"
    exit 1
fi

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Get git changes since last tag
get_git_changes() {
    local version="$1"
    local last_tag=""
    
    # Get the last tag
    last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [[ -n "$last_tag" ]]; then
        log_info "Getting changes since $last_tag"
        git log --oneline --pretty=format:"- %s" "$last_tag..HEAD" 2>/dev/null || true
    else
        log_info "No previous tags found, getting all changes"
        git log --oneline --pretty=format:"- %s" 2>/dev/null || true
    fi
}

# Analyze code changes
analyze_changes() {
    local version="$1"
    local changes_file="$2"
    
    log_info "Analyzing code changes for version $version..."
    
    local new_features=()
    local improvements=()
    local bug_fixes=()
    local breaking_changes=()
    local documentation=()
    
    # Analyze git changes
    while IFS= read -r line; do
        local change="${line#- }"
        
        # Categorize changes based on keywords
        case "$change" in
            *"feat"*|*"feature"*|*"add"*|*"new"*)
                new_features+=("$change")
                ;;
            *"fix"*|*"bug"*|*"issue"*)
                bug_fixes+=("$change")
                ;;
            *"break"*|*"BREAKING"*)
                breaking_changes+=("$change")
                ;;
            *"docs"*|*"documentation"*|*"readme"*)
                documentation+=("$change")
                ;;
            *"refactor"*|*"improve"*|*"optimize"*|*"enhance"*)
                improvements+=("$change")
                ;;
            *)
                improvements+=("$change")
                ;;
        esac
    done < "$changes_file"
    
    # Write analysis to file
    cat > "$changes_file" << EOF
# Change Analysis for v$version

## New Features
$(printf '%s\n' "${new_features[@]:-}")

## Improvements
$(printf '%s\n' "${improvements[@]:-}")

## Bug Fixes
$(printf '%s\n' "${bug_fixes[@]:-}")

## Breaking Changes
$(printf '%s\n' "${breaking_changes[@]:-}")

## Documentation
$(printf '%s\n' "${documentation[@]:-}")
EOF
    
    log_success "Change analysis completed"
    log_info "New features: ${#new_features[@]:-0}"
    log_info "Improvements: ${#improvements[@]:-0}"
    log_info "Bug fixes: ${#bug_fixes[@]:-0}"
    log_info "Breaking changes: ${#breaking_changes[@]:-0}"
    log_info "Documentation: ${#documentation[@]:-0}"
}

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
    
    # Generate the file
    if generate_markdown_file "$release_file" "$content"; then
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
    
    # Generate the file
    if generate_markdown_file "$changelog_file" "$content"; then
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
    generate_release_notes "$version" "$timestamp" "$release_type" "$changes_file"
    generate_changelog "$version" "$timestamp" "$release_type" "$changes_file"
    update_readme_version "$version" "$timestamp"
    generate_docs_index "$version"
    
    # Clean up
    rm -f "$changes_file"
    
    log_success "Document generation completed for version $version"
}

# Command-line interface
main() {
    case "${1:-help}" in
        "generate")
            local version="${2:-}"
            local timestamp="${3:-$(date -u +"%Y-%m-%d %H:%M:%S UTC")}"
            local release_type="${4:-patch}"
            
            if [[ -z "$version" ]]; then
                log_error "Version is required"
                echo "Usage: $0 generate <version> [timestamp] [release_type]"
                exit 1
            fi
            
            generate_documents "$version" "$timestamp" "$release_type"
            ;;
        "analyze")
            local version="${2:-}"
            if [[ -z "$version" ]]; then
                log_error "Version is required"
                echo "Usage: $0 analyze <version>"
                exit 1
            fi
            
            local changes_file=$(mktemp)
            get_git_changes "$version" > "$changes_file"
            analyze_changes "$version" "$changes_file"
            cat "$changes_file"
            rm -f "$changes_file"
            ;;
        "help"|"-h"|"--help")
            echo "Document Generation Script"
            echo "========================="
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
            echo "  $0 generate 15.27.0"
            echo "  $0 generate 15.27.0 '2025-09-05 13:41:28 UTC' minor"
            echo "  $0 analyze 15.27.0"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

