#!/bin/bash

# Repository Cleanup Tool - File Management
# Deletes temp files and moves old documentation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Simple logging
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_info() { echo -e "${YELLOW}ℹ️  $1${NC}"; }
log_warning() { echo -e "${BLUE}⚠️  $1${NC}"; }

# Find temp files
find_temp_files() {
    find . -name "*.tmp*" -o -name "*.temp*" -o -name "*.backup*" -o -name "*.bak*" -o -name "*.orig*" -o -name "*~" -o -name ".#*" -o -name "#*#" -o -name "*.swp*" -o -name "*.swo*" 2>/dev/null | grep -v ".git" | sort
}

# Find old documentation files (exclude current version)
find_old_docs() {
    local current_version=""
    if [ -f "VERSION" ]; then
        current_version=$(cat VERSION)
    fi
    
    if [ -z "$current_version" ]; then
        # If no VERSION file, find all versioned files
        find . -name "*_old*" -o -name "*_new*" -o -name "RELEASE_v*" -o -name "CHANGELOG_v*" 2>/dev/null | grep -v ".git" | sort
    else
        # Exclude current version files
        find . -name "*_old*" -o -name "*_new*" -o -name "RELEASE_v*" -o -name "CHANGELOG_v*" 2>/dev/null | grep -v ".git" | grep -v "_v${current_version}.md" | sort
    fi
}

# Clean temp files
clean_temp_files() {
    local temp_files
    temp_files=$(find_temp_files)
    
    if [[ -z "$temp_files" ]]; then
        log_info "No temp files found"
        return 0
    fi
    
    echo "Found temp files:"
    echo "$temp_files"
    echo ""
    
    read -p "Delete these temp files? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$temp_files" | xargs rm -f
        log_success "Temp files cleaned"
    else
        log_info "Temp files kept"
    fi
}

# Move old documentation to archive
archive_old_docs() {
    local old_docs
    old_docs=$(find_old_docs)
    
    if [[ -z "$old_docs" ]]; then
        log_info "No old documentation files found"
        return 0
    fi
    
    echo "Found old documentation files:"
    echo "$old_docs"
    echo ""
    
    # Create zArchive directory if it doesn't exist
    local archive_dir="docs/zArchive"
    if [[ ! -d "$archive_dir" ]]; then
        mkdir -p "$archive_dir"
        log_info "Created zArchive directory: $archive_dir"
    fi
    
    read -p "Move these files to $archive_dir? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$old_docs" | while read -r file; do
            if [[ -f "$file" ]]; then
                local basename_file=$(basename "$file")
                mv "$file" "$archive_dir/$basename_file"
                log_success "Moved: $file -> $archive_dir/$basename_file"
            fi
        done
    else
        log_info "Old documentation files kept"
    fi
}

# Clean up backup files
cleanup_backups() {
    local backup_files
    backup_files=$(find . -name "*.backup.*" -o -name "*.bak.*" 2>/dev/null | grep -v ".git" | sort)
    
    if [[ -z "$backup_files" ]]; then
        log_info "No backup files found"
        return 0
    fi
    
    echo "Found backup files:"
    echo "$backup_files"
    echo ""
    
    read -p "Delete these backup files? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$backup_files" | xargs rm -f
        log_success "Backup files cleaned"
    else
        log_info "Backup files kept"
    fi
}

# Show usage
show_usage() {
    cat << EOF
Repository Cleanup Tool - File Management

USAGE:
    $0 [command] [options]

COMMANDS:
    temp            Clean up temporary files
    archive         Move old documentation to archive
    backups         Clean up backup files
    all             Run all cleanup operations

OPTIONS:
    --force, -f     Skip confirmation prompts
    --help, -h      Show this help

EXAMPLES:
    $0 temp                    # Clean temp files
    $0 archive                 # Archive old docs
    $0 all                     # Run all cleanup
    $0 temp --force            # Clean temp files without confirmation

EOF
}

# Main processing
main() {
    # Check for help first
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    local command="${1:-all}"
    local force=false
    shift || true
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    case "$command" in
        temp)
            if [[ "$force" == "true" ]]; then
                local temp_files
                temp_files=$(find_temp_files)
                if [[ -n "$temp_files" ]]; then
                    echo "$temp_files" | xargs rm -f
                    log_success "Temp files cleaned"
                else
                    log_info "No temp files found"
                fi
            else
                clean_temp_files
            fi
            ;;
        archive)
            if [[ "$force" == "true" ]]; then
                local old_docs
                old_docs=$(find_old_docs)
                if [[ -n "$old_docs" ]]; then
                    local archive_dir="docs/zArchive"
                    mkdir -p "$archive_dir"
                    echo "$old_docs" | while read -r file; do
                        if [[ -f "$file" ]]; then
                            local basename_file=$(basename "$file")
                            mv "$file" "$archive_dir/$basename_file"
                            log_success "Moved: $file -> $archive_dir/$basename_file"
                        fi
                    done
                else
                    log_info "No old documentation files found"
                fi
            else
                archive_old_docs
            fi
            ;;
        backups)
            if [[ "$force" == "true" ]]; then
                local backup_files
                backup_files=$(find . -name "*.backup.*" -o -name "*.bak.*" 2>/dev/null | grep -v ".git" | sort)
                if [[ -n "$backup_files" ]]; then
                    echo "$backup_files" | xargs rm -f
                    log_success "Backup files cleaned"
                else
                    log_info "No backup files found"
                fi
            else
                cleanup_backups
            fi
            ;;
        all)
            log_info "Running all cleanup operations..."
            echo ""
            
            log_info "1. Cleaning temp files..."
            if [[ "$force" == "true" ]]; then
                local temp_files
                temp_files=$(find_temp_files)
                if [[ -n "$temp_files" ]]; then
                    echo "$temp_files" | xargs rm -f
                    log_success "Temp files cleaned"
                else
                    log_info "No temp files found"
                fi
            else
                clean_temp_files
            fi
            echo ""
            
            log_info "2. Archiving old documentation..."
            if [[ "$force" == "true" ]]; then
                local old_docs
                old_docs=$(find_old_docs)
                if [[ -n "$old_docs" ]]; then
                    local archive_dir="docs/zArchive"
                    mkdir -p "$archive_dir"
                    echo "$old_docs" | while read -r file; do
                        if [[ -f "$file" ]]; then
                            local basename_file=$(basename "$file")
                            mv "$file" "$archive_dir/$basename_file"
                            log_success "Moved: $file -> $archive_dir/$basename_file"
                        fi
                    done
                else
                    log_info "No old documentation files found"
                fi
            else
                archive_old_docs
            fi
            echo ""
            
            log_info "3. Cleaning backup files..."
            if [[ "$force" == "true" ]]; then
                local backup_files
                backup_files=$(find . -name "*.backup.*" -o -name "*.bak.*" 2>/dev/null | grep -v ".git" | sort)
                if [[ -n "$backup_files" ]]; then
                    echo "$backup_files" | xargs rm -f
                    log_success "Backup files cleaned"
                else
                    log_info "No backup files found"
                fi
            else
                cleanup_backups
            fi
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"