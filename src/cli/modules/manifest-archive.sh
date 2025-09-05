#!/bin/bash

# Manifest Archive Module
# Handles moving old documentation to zArchive and general repository cleanup

# Get the project root (three levels up from modules)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
ZARCHIVE_DIR="$PROJECT_ROOT/docs/zArchive"

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

# Ensure zArchive directory exists
ensure_zarchive_dir() {
    if [[ ! -d "$ZARCHIVE_DIR" ]]; then
        log_info "Creating zArchive directory: $ZARCHIVE_DIR"
        mkdir -p "$ZARCHIVE_DIR"
        log_success "zArchive directory created"
    fi
}

# Move old documentation to zArchive
archive_old_documentation() {
    local version="$1"
    local timestamp="$2"
    
    log_info "Archiving old documentation for version $version..."
    
    ensure_zarchive_dir
    
    local moved_count=0
    local skipped_count=0
    
    # Find all version-specific documentation files
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local filename="$(basename "$file")"
            local dest="$ZARCHIVE_DIR/$filename"
            
            # Skip if already in zArchive
            if [[ "$file" == *"/zArchive/"* ]]; then
                skipped_count=$((skipped_count + 1))
                continue
            fi
            
            # Move the file
            if mv "$file" "$dest" 2>/dev/null; then
                log_success "Moved: $filename"
                moved_count=$((moved_count + 1))
            else
                log_warning "Failed to move: $filename"
            fi
        fi
    done < <(find "$PROJECT_ROOT/docs" -name "CHANGELOG_v*.md" -o -name "RELEASE_v*.md" | grep -v "zArchive")
    
    log_success "Archived $moved_count files, skipped $skipped_count files"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    local cleaned_count=0
    
    # Remove common temporary files
    local temp_patterns=(
        "*.tmp"
        "*.temp"
        "*.bak"
        "*.backup"
        "*~"
        ".DS_Store"
        "Thumbs.db"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                cleaned_count=$((cleaned_count + 1))
            fi
        done < <(find "$PROJECT_ROOT" -name "$pattern" -type f 2>/dev/null || true)
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_success "Cleaned up $cleaned_count temporary files"
    else
        log_info "No temporary files found"
    fi
}

# Clean up empty directories
cleanup_empty_dirs() {
    log_info "Cleaning up empty directories..."
    
    local cleaned_count=0
    
    # Find and remove empty directories (except important ones)
    while IFS= read -r dir; do
        if [[ -d "$dir" && "$dir" != "$PROJECT_ROOT" && "$dir" != "$PROJECT_ROOT/.git" ]]; then
            if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                rmdir "$dir" 2>/dev/null && cleaned_count=$((cleaned_count + 1))
            fi
        fi
    done < <(find "$PROJECT_ROOT" -type d -empty 2>/dev/null || true)
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_success "Removed $cleaned_count empty directories"
    else
        log_info "No empty directories found"
    fi
}

# Validate repository state
validate_repository() {
    log_info "Validating repository state..."
    
    local issues=0
    
    # Check for uncommitted changes
    if ! git diff --quiet 2>/dev/null; then
        log_warning "Repository has uncommitted changes"
        issues=$((issues + 1))
    fi
    
    # Check for untracked files
    if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        log_warning "Repository has untracked files"
        issues=$((issues + 1))
    fi
    
    # Check zArchive directory
    if [[ ! -d "$ZARCHIVE_DIR" ]]; then
        log_warning "zArchive directory does not exist"
        issues=$((issues + 1))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Repository state is valid"
        return 0
    else
        log_warning "Repository has $issues issues"
        return 1
    fi
}

# Main cleanup function
main_cleanup() {
    local version="${1:-}"
    local timestamp="${2:-$(date -u +"%Y-%m-%d %H:%M:%S UTC")}"
    
    log_info "Starting repository cleanup..."
    log_info "Version: $version"
    log_info "Timestamp: $timestamp"
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Archive old documentation
    if [[ -n "$version" ]]; then
        archive_old_documentation "$version" "$timestamp"
    fi
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Clean up empty directories
    cleanup_empty_dirs
    
    # Validate repository state (don't fail on warnings)
    validate_repository || true
    
    log_success "Repository cleanup completed"
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "archive")
            main_cleanup "${2:-}" "${3:-}"
            ;;
        "clean")
            main_cleanup "" ""
            ;;
        "validate")
            validate_repository
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Archive Module"
            echo "======================"
            echo ""
            echo "Usage: $0 [command] [version] [timestamp]"
            echo ""
            echo "Commands:"
            echo "  archive [version] [timestamp]  - Archive old documentation and cleanup"
            echo "  clean                          - General cleanup (no archiving)"
            echo "  validate                       - Validate repository state"
            echo "  help                           - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 archive 15.28.0             # Archive docs for version 15.28.0"
            echo "  $0 clean                       # General cleanup"
            echo "  $0 validate                    # Check repository state"
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
