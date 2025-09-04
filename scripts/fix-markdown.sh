#!/bin/bash

# Robust Iterative Markdown Fix Script
set -euo pipefail

# Configuration
MAX_ITERATIONS=10
TIMEOUT_SECONDS=30
BACKUP_DIR=".markdown-backups"
AUTO_CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup)
            AUTO_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--cleanup] [--help]"
            echo "  --cleanup    Automatically clean up backup files after fixing"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🔧 Robust Markdown Fixer"
echo "========================"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Find all markdown files (excluding zArchive and temp files)
markdown_files=$(find . -name "*.md" -not -path "./docs/zArchive/*" -not -path "./node_modules/*" -not -path "./.git/*" -not -path "./$BACKUP_DIR/*" -not -name ".*")

echo "📁 Found markdown files:"
echo "$markdown_files"
echo ""

# Function to check if file has issues
check_markdown_issues() {
    local file="$1"
    local issues=0
    
    # Check for trailing whitespace
    if grep -q '[[:space:]]$' "$file" 2>/dev/null; then
        echo "   ⚠️  Trailing whitespace found"
        issues=$((issues + 1))
    fi
    
    # Check for multiple consecutive blank lines (more than 2)
    if awk '/^[[:space:]]*$/{blank++; if(blank>2) {found=1; exit 1}} {blank=0} END{if(found) exit 1; exit 0}' "$file" 2>/dev/null; then
        echo "   ⚠️  Multiple consecutive blank lines found"
        issues=$((issues + 1))
    fi
    
    # Check for unclosed code blocks
    local code_blocks=$(grep -c '^```' "$file" 2>/dev/null || echo "0")
    if [ $((code_blocks % 2)) -ne 0 ]; then
        echo "   ⚠️  Unclosed code blocks found"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Function to fix a single file iteratively
fix_file() {
    local file="$1"
    local iteration=1
    local max_iterations="$2"
    
    echo "🔧 Fixing: $file"
    
    # Create timestamped backup
    local backup_file="$BACKUP_DIR/$(basename "$file").$(date +%Y%m%d_%H%M%S).backup"
    if cp "$file" "$backup_file" 2>/dev/null; then
        echo "   💾 Backup created: $backup_file"
    else
        echo "   ⚠️  Could not create backup (permissions issue)"
    fi
    
    while [ $iteration -le $max_iterations ]; do
        echo "   🔄 Iteration $iteration/$max_iterations"
        
        # Check if file has issues
        if ! check_markdown_issues "$file" >/dev/null 2>&1; then
            echo "   ✅ No issues found, file is clean!"
            break
        fi
        
        # Create temp file for this iteration
        local temp_file="${file}.tmp.$$"
        
        # Fix 1: Remove trailing whitespace (safe)
        if grep -q '[[:space:]]$' "$file" 2>/dev/null; then
            echo "   🔧 Removing trailing whitespace..."
            sed 's/[[:space:]]*$//' "$file" > "$temp_file" && mv "$temp_file" "$file"
        fi
        
        # Fix 2: Fix multiple consecutive blank lines (safe)
        echo "   🔧 Fixing multiple blank lines..."
        awk 'BEGIN{blank=0} 
             /^[[:space:]]*$/{blank++; if(blank<=2) print; next} 
             {blank=0; print}' "$file" > "$temp_file" && mv "$temp_file" "$file"
        
        # Fix 3: Ensure proper line endings
        echo "   🔧 Normalizing line endings..."
        tr -d '\r' < "$file" > "$temp_file" && mv "$temp_file" "$file"
        
        # Fix 4: Remove empty lines at end of file
        echo "   🔧 Removing trailing empty lines..."
        sed -e :a -e '/^\s*$/N;ba' -e 's/\n*$//' "$file" > "$temp_file" && mv "$temp_file" "$file"
        
        # Check if we made progress
        if ! check_markdown_issues "$file" >/dev/null 2>&1; then
            echo "   ✅ All issues fixed in iteration $iteration!"
            break
        fi
        
        iteration=$((iteration + 1))
        
        # Safety check - if we're not making progress, stop
        if [ $iteration -gt $max_iterations ]; then
            echo "   ⚠️  Maximum iterations reached, some issues may remain"
            break
        fi
    done
    
    # Final validation
    echo "   🔍 Final validation..."
    if check_markdown_issues "$file" >/dev/null 2>&1; then
        echo "   ✅ File is now clean!"
    else
        echo "   ⚠️  Some issues may remain - check manually"
    fi
}

# Process each file
for file in $markdown_files; do
    if [ -f "$file" ]; then
        # Use timeout to prevent hanging
        if timeout "$TIMEOUT_SECONDS" bash -c "
            # Source the functions in the subshell
            $(declare -f check_markdown_issues)
            $(declare -f fix_file)
            fix_file '$file' $MAX_ITERATIONS
        "; then
            echo "   ✅ Completed: $file"
        else
            echo "   ❌ Timeout or error processing: $file"
        fi
        echo ""
    fi
done

echo "✅ Markdown fixing completed!"
echo "📝 Backups stored in: $BACKUP_DIR/"

# Handle backup cleanup
if [ "$AUTO_CLEANUP" = true ]; then
    echo "🧹 Auto-cleaning up backup files..."
    rm -rf "$BACKUP_DIR"
    echo "✅ Backup files cleaned up!"
else
    # Ask user if they want to clean up backups
    echo ""
    read -p "🧹 Do you want to clean up backup files? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🧹 Cleaning up backup files..."
        rm -rf "$BACKUP_DIR"
        echo "✅ Backup files cleaned up!"
    else
        echo "📝 Backups kept in: $BACKUP_DIR/"
        echo "🧹 Run 'rm -rf $BACKUP_DIR' to clean up later"
    fi
fi