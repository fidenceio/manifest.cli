#!/bin/bash
# Manifest Cleanup Module
# Provides centralized, iterative file cleanup utilities

# Common file patterns for cleanup
declare -a COMMON_TEMP_PATTERNS=(
    "*.tmp"
    "*.backup"
    "*~"
    "*.orig"
    "*.swp"
    "*.swo"
    ".DS_Store"
    "*.log"
    "*.pid"
    "*.lock"
)

# Iterative file removal with retry logic
remove_files_iteratively() {
    local patterns=("$@")
    local max_attempts="${MANIFEST_CLEANUP_MAX_ATTEMPTS:-3}"
    local delay="${MANIFEST_CLEANUP_DELAY:-1}"
    local cleaned_count=0
    local failed_count=0
    
    echo "🧹 Starting iterative file cleanup..."
    
    for pattern in "${patterns[@]}"; do
        local attempt=1
        local pattern_cleaned=0
        
        while [ $attempt -le $max_attempts ]; do
            local files_found=0
            
            # Find files matching pattern
            while IFS= read -r -d '' file; do
                if [ -f "$file" ]; then
                    files_found=$((files_found + 1))
                    
                    # Attempt to remove file
                    if rm -f "$file" 2>/dev/null; then
                        echo "   🗑️  Removed: $(basename "$file")"
                        cleaned_count=$((cleaned_count + 1))
                        pattern_cleaned=$((pattern_cleaned + 1))
                    else
                        echo "   ⚠️  Failed to remove: $(basename "$file")"
                        failed_count=$((failed_count + 1))
                    fi
                fi
            done < <(find . -name "$pattern" -type f -print0 2>/dev/null)
            
            # If no files found or all cleaned, move to next pattern
            if [ $files_found -eq 0 ] || [ $pattern_cleaned -eq $files_found ]; then
                break
            fi
            
            # If some files failed, retry after delay
            if [ $attempt -lt $max_attempts ]; then
                echo "   🔄 Retrying pattern '$pattern' in ${delay}s... (attempt $((attempt + 1))/$max_attempts)"
                sleep $delay
            fi
            
            attempt=$((attempt + 1))
        done
    done
    
    # Summary
    if [ $cleaned_count -gt 0 ]; then
        echo "   ✅ Successfully cleaned $cleaned_count file(s)"
    fi
    
    if [ $failed_count -gt 0 ]; then
        echo "   ⚠️  Failed to clean $failed_count file(s)"
        return 1
    fi
    
    if [ $cleaned_count -eq 0 ] && [ $failed_count -eq 0 ]; then
        echo "   ✅ No files found to clean"
    fi
    
    return 0
}

# Clean up temporary files using common patterns
cleanup_temp_files() {
    echo "🧹 Cleaning up temporary files..."
    remove_files_iteratively "${COMMON_TEMP_PATTERNS[@]}"
}

# Clean up specific directory with pattern
cleanup_directory() {
    local directory="$1"
    local pattern="$2"
    local max_files="${3:-20}"
    
    if [ ! -d "$directory" ]; then
        echo "   ⚠️  Directory $directory does not exist"
        return 0
    fi
    
    echo "🧹 Cleaning up $directory (keeping $max_files most recent)..."
    
    # Count files matching pattern
    local file_count=$(find "$directory" -name "$pattern" -type f | wc -l)
    
    if [ $file_count -le $max_files ]; then
        echo "   ✅ Directory has $file_count files, no cleanup needed"
        return 0
    fi
    
    # Get files sorted by modification time (oldest first)
    local files_to_remove=$(find "$directory" -name "$pattern" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -n $((file_count - max_files)) | cut -d' ' -f2-)
    
    if [ -n "$files_to_remove" ]; then
        echo "$files_to_remove" | while read -r file; do
            if [ -f "$file" ]; then
                rm -f "$file"
                echo "   🗑️  Removed old file: $(basename "$file")"
            fi
        done
        echo "   ✅ Cleanup completed, kept $max_files most recent files"
    fi
}

# Clean up zArchive directory (specialized function)
cleanup_zArchive() {
    echo "🧹 Cleaning up zArchive directory..."
    
    # Create zArchive directory if it doesn't exist
    mkdir -p docs/zArchive
    
    # Clean up old documentation files
    cleanup_directory "docs/zArchive" "*.md" 20
    
    echo "   ✅ zArchive cleanup completed"
}

# Comprehensive cleanup (all types)
comprehensive_cleanup() {
    echo "🧹 Starting comprehensive cleanup..."
    
    # Clean temporary files
    cleanup_temp_files
    
    # Clean zArchive
    cleanup_zArchive
    
    # Clean any other specified directories
    if [ -n "$MANIFEST_CLEANUP_DIRS" ]; then
        IFS=',' read -ra dirs <<< "$MANIFEST_CLEANUP_DIRS"
        for dir in "${dirs[@]}"; do
            cleanup_directory "$dir" "*" 10
        done
    fi
    
    echo "✅ Comprehensive cleanup completed"
}

# Force cleanup (removes everything matching patterns)
force_cleanup() {
    echo "🧹 Starting force cleanup..."
    local patterns=("$@")
    
    if [ ${#patterns[@]} -eq 0 ]; then
        patterns=("${COMMON_TEMP_PATTERNS[@]}")
    fi
    
    remove_files_iteratively "${patterns[@]}"
    echo "✅ Force cleanup completed"
}
