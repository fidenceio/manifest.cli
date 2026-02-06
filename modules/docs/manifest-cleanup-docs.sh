#!/bin/bash

# Manifest Cleanup Docs Module
# Handles moving old documentation to zArchive and general repository cleanup

# Cleanup-docs module - uses PROJECT_ROOT from core module

# Get configurable documentation paths
get_zarchive_dir() {
    get_docs_archive_folder "$PROJECT_ROOT"
}

# Ensure zArchive directory exists
ensure_zarchive_dir() {
    local zarchive_dir=$(get_zarchive_dir)
    if [[ ! -d "$zarchive_dir" ]]; then
        log_info "Creating zArchive directory: $zarchive_dir"
        mkdir -p "$zarchive_dir"
        log_success "zArchive directory created"
    fi
}


# Clean up temporary files (enhanced version)
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
    local zarchive_dir=$(get_zarchive_dir)
    if [[ ! -d "$zarchive_dir" ]]; then
        log_warning "zArchive directory does not exist: $zarchive_dir"
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

# Main cleanup function - handles archiving and general cleanup
main_cleanup() {
    local version="${1:-}"
    local timestamp="${2:-}"
    
    # Get NTP timestamp if not provided
    if [ -z "$timestamp" ]; then
        get_ntp_timestamp >/dev/null
        timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    fi
    
    log_info "Starting repository cleanup..."
    log_info "Version: $version"
    log_info "Timestamp: $timestamp"
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Archive old documentation
    if [[ -n "$version" ]]; then
        log_info "Archiving old documentation for version $version..."
        
        ensure_zarchive_dir
        
        local moved_count=0
        local skipped_count=0
        
        # Find all version-specific documentation files
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                local filename="$(basename "$file")"
                local dest="$(get_zarchive_dir)/$filename"
                
                # Skip if already in archive directory
                if [[ "$file" == "$(get_zarchive_dir)"/* ]]; then
                    skipped_count=$((skipped_count + 1))
                    continue
                fi
                
                # Skip if this is the current version file
                if [[ "$filename" == *"v$version"* ]]; then
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
        done < <(find "$(get_docs_folder "$PROJECT_ROOT")" -name "CHANGELOG_v*.md" -o -name "RELEASE_v*.md" -o -name "SECURITY_ANALYSIS_REPORT_v*.md" | grep -v "$(get_zarchive_dir)")
        
        log_success "Archived $moved_count files, skipped $skipped_count files"
    fi
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Clean up empty directories
    cleanup_empty_dirs
    
    log_success "Repository cleanup completed"
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "archive")
            main_cleanup "${2:-}" "${3:-}"
            ;;
        "clean")
            # For clean command, archive all old documentation files
            local latest_version=""
            if [ -f "$PROJECT_ROOT/VERSION" ]; then
                latest_version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "")
            fi
            # Get NTP timestamp for cleanup
            get_ntp_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            main_cleanup "$latest_version" "$timestamp"
            ;;
        "validate")
            validate_repository
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Cleanup Docs Module"
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
            show_usage_error "$1"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
