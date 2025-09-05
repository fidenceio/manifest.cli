#!/bin/bash

# Manifest Documentation Module
# Handles documentation generation, README updates, and release notes
# Now uses the new script architecture for better separation of concerns

# Get the project root (three levels up from modules)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# Import the new script architecture
REPO_CLEANUP_SCRIPT="$PROJECT_ROOT/scripts/repo-cleanup.sh"
GENERATE_DOCS_SCRIPT="$PROJECT_ROOT/scripts/generate-documents.sh"
MARKDOWN_VALIDATION_SCRIPT="$PROJECT_ROOT/scripts/markdown-validation.sh"

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

# Check if required scripts exist
check_required_scripts() {
    local missing_scripts=()
    
    if [[ ! -f "$REPO_CLEANUP_SCRIPT" ]]; then
        missing_scripts+=("repo-cleanup.sh")
    fi
    
    if [[ ! -f "$GENERATE_DOCS_SCRIPT" ]]; then
        missing_scripts+=("generate-documents.sh")
    fi
    
    if [[ ! -f "$MARKDOWN_VALIDATION_SCRIPT" ]]; then
        missing_scripts+=("markdown-validation.sh")
    fi
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "Missing required scripts: ${missing_scripts[*]}"
        log_error "Please ensure all scripts are in the scripts/ directory"
        return 1
    fi
    
    return 0
}

# Archive old documentation using repo-cleanup script
archive_old_documentation() {
    local version="$1"
    local timestamp="$2"
    
    log_info "Archiving old documentation using repo-cleanup script..."
    
    if [[ -f "$REPO_CLEANUP_SCRIPT" ]]; then
        if "$REPO_CLEANUP_SCRIPT" archive "$version" "$timestamp"; then
            log_success "Old documentation archived successfully"
            return 0
        else
            log_error "Failed to archive old documentation"
            return 1
        fi
    else
        log_error "Repository cleanup script not found: $REPO_CLEANUP_SCRIPT"
        return 1
    fi
}

# Generate documentation using generate-documents script
generate_documentation() {
    local version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"
    
    log_info "Generating documentation using generate-documents script..."
    
    if [[ -f "$GENERATE_DOCS_SCRIPT" ]]; then
        if "$GENERATE_DOCS_SCRIPT" generate "$version" "$timestamp" "$release_type"; then
            log_success "Documentation generated successfully"
            return 0
        else
            log_error "Failed to generate documentation"
            return 1
        fi
    else
        log_error "Document generation script not found: $GENERATE_DOCS_SCRIPT"
        return 1
    fi
}

# Validate markdown using markdown-validation script
validate_markdown() {
    log_info "Validating markdown using markdown-validation script..."
    
    if [[ -f "$MARKDOWN_VALIDATION_SCRIPT" ]]; then
        if "$MARKDOWN_VALIDATION_SCRIPT" project; then
            log_success "Markdown validation completed successfully"
            return 0
        else
            log_warning "Markdown validation found issues"
            return 1
        fi
    else
        log_warning "Markdown validation script not found: $MARKDOWN_VALIDATION_SCRIPT"
        log_info "Skipping markdown validation"
        return 0
    fi
}

# Main documentation workflow
generate_documentation_workflow() {
    local version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"
    
    log_info "Starting documentation workflow for version $version..."
    
    # Check required scripts
    if ! check_required_scripts; then
        return 1
    fi
    
    # Step 1: Archive old documentation
    if ! archive_old_documentation "$version" "$timestamp"; then
        log_error "Failed to archive old documentation"
        return 1
    fi
    
    # Step 2: Generate new documentation
    if ! generate_documentation "$version" "$timestamp" "$release_type"; then
        log_error "Failed to generate documentation"
        return 1
    fi
    
    # Step 3: Validate markdown
    if ! validate_markdown; then
        log_warning "Markdown validation found issues, but continuing..."
    fi
    
    log_success "Documentation workflow completed successfully"
    return 0
}

# Legacy function for backward compatibility
generate_release_notes() {
    local version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"
    
    log_warning "Using legacy generate_release_notes function"
    log_info "Consider using generate_documentation_workflow instead"
    
    return generate_documentation_workflow "$version" "$timestamp" "$release_type"
}

# Legacy function for backward compatibility
generate_changelog() {
    local version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"
    
    log_warning "Using legacy generate_changelog function"
    log_info "Consider using generate_documentation_workflow instead"
    
    return generate_documentation_workflow "$version" "$timestamp" "$release_type"
}

# Legacy function for backward compatibility
update_readme_version() {
    local version="$1"
    local timestamp="$2"
    
    log_warning "Using legacy update_readme_version function"
    log_info "Consider using generate_documentation_workflow instead"
    
    return generate_documentation_workflow "$version" "$timestamp" "patch"
}

# Legacy function for backward compatibility
move_previous_documentation() {
    local version="$1"
    local timestamp="$2"
    
    log_warning "Using legacy move_previous_documentation function"
    log_info "Consider using archive_old_documentation instead"
    
    return archive_old_documentation "$version" "$timestamp"
}

# Legacy function for backward compatibility
move_existing_historical_docs() {
    log_warning "Using legacy move_existing_historical_docs function"
    log_info "This function is now handled by repo-cleanup.sh"
    
    # Call repo-cleanup script for general cleanup
    if [[ -f "$REPO_CLEANUP_SCRIPT" ]]; then
        "$REPO_CLEANUP_SCRIPT" clean
    else
        log_error "Repository cleanup script not found"
        return 1
    fi
}

# Main function for command-line usage
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
            
            generate_documentation_workflow "$version" "$timestamp" "$release_type"
            ;;
        "archive")
            local version="${2:-}"
            local timestamp="${3:-$(date -u +"%Y-%m-%d %H:%M:%S UTC")}"
            
            if [[ -z "$version" ]]; then
                log_error "Version is required"
                echo "Usage: $0 archive <version> [timestamp]"
                exit 1
            fi
            
            archive_old_documentation "$version" "$timestamp"
            ;;
        "validate")
            validate_markdown
            ;;
        "check")
            check_required_scripts
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Documentation Module"
            echo "============================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  generate <version> [timestamp] [type]  - Complete documentation workflow"
            echo "  archive <version> [timestamp]          - Archive old documentation only"
            echo "  validate                               - Validate markdown only"
            echo "  check                                  - Check required scripts"
            echo "  help                                   - Show this help"
            echo ""
            echo "Release Types:"
            echo "  patch, minor, major"
            echo ""
            echo "Examples:"
            echo "  $0 generate 15.27.0"
            echo "  $0 generate 15.27.0 '2025-09-05 13:41:28 UTC' minor"
            echo "  $0 archive 15.27.0"
            echo "  $0 validate"
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