#!/usr/bin/env python3
"""
Document Cleanup Tool for Manifest CLI
Focused on cleaning up whitespace and formatting issues in any text file.
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import List, Set
import tempfile
import shutil
from datetime import datetime

class DocumentCleanup:
    def __init__(self, verbose: bool = False, debug: bool = False):
        self.verbose = verbose
        self.debug = debug
        self.backup_dir = Path(".document-backups")
        self.temp_patterns = [
            "*.tmp*", "*.temp*", "*.backup*", "*.bak*", "*.orig*",
            "*~", ".#*", "#*#", "*.swp*", "*.swo*"
        ]
        self.exclude_patterns = [
            "node_modules/*",
            ".git/*",
            ".document-backups/*",
            ".*"
        ]
    
    def log(self, message: str, level: str = "info"):
        """Simple logging function"""
        colors = {
            "info": "\033[0;34m",
            "success": "\033[0;32m",
            "warning": "\033[1;33m",
            "error": "\033[0;31m",
            "debug": "\033[0;35m"
        }
        icons = {
            "info": "ℹ️",
            "success": "✅",
            "warning": "⚠️",
            "error": "❌",
            "debug": "🐛"
        }
        
        if level == "debug" and not self.debug:
            return
            
        color = colors.get(level, "")
        icon = icons.get(level, "")
        reset = "\033[0m"
        
        print(f"{color}{icon} {message}{reset}")
    
    def find_files(self, include_patterns: List[str] = None, include_temp: bool = False) -> List[Path]:
        """Find files to clean up, including temp files if requested"""
        files = []
        
        for root, dirs, filenames in os.walk("."):
            # Skip excluded directories
            dirs[:] = [d for d in dirs if not any(
                Path(root) / d == Path(pattern.rstrip("/*")) for pattern in self.exclude_patterns
            )]
            
            for filename in filenames:
                file_path = Path(root) / filename
                
                # Check if file should be excluded
                if any(file_path.match(pattern) for pattern in self.exclude_patterns):
                    continue
                
                # Include regular files
                if include_patterns:
                    if any(file_path.match(pattern) for pattern in include_patterns):
                        files.append(file_path)
                else:
                    # Default: include common text files
                    if file_path.suffix.lower() in ['.md', '.txt', '.py', '.sh', '.js', '.ts', '.json', '.yaml', '.yml', '.xml', '.html', '.css']:
                        files.append(file_path)
                
                # Include temp files if requested
                if include_temp:
                    if any(file_path.match(pattern) for pattern in self.temp_patterns):
                        files.append(file_path)
        
        return sorted(files)
    
    def create_backup(self, file_path: Path) -> Path:
        """Create a backup of the file"""
        self.backup_dir.mkdir(exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = self.backup_dir / f"{file_path.name}.{timestamp}.backup"
        
        try:
            shutil.copy2(file_path, backup_path)
            self.log(f"Backup created: {backup_path}", "debug")
            return backup_path
        except Exception as e:
            self.log(f"Could not create backup: {e}", "warning")
            return None
    
    def clean_file(self, file_path: Path, create_backup: bool = True, dry_run: bool = False) -> bool:
        """Clean a single file iteratively, line by line"""
        if not file_path.exists():
            self.log(f"File not found: {file_path}", "error")
            return False
        
        if not file_path.is_file():
            self.log(f"Not a file: {file_path}", "error")
            return False
        
        self.log(f"Cleaning: {file_path.name}")
        
        if dry_run:
            self.log("DRY RUN - No changes will be made", "info")
            return True
        
        # Create backup if requested
        backup_path = None
        if create_backup:
            backup_path = self.create_backup(file_path)
        
        try:
            # Read file content
            with open(file_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            original_content = ''.join(lines)
            cleaned_lines = []
            
            # Process each line iteratively
            for line_num, line in enumerate(lines, 1):
                self.log(f"Processing line {line_num}", "debug")
                
                # Remove trailing whitespace (spaces and tabs)
                cleaned_line = line.rstrip(' \t')
                
                # Handle line endings - normalize to \n
                if cleaned_line.endswith('\r\n'):
                    cleaned_line = cleaned_line[:-2] + '\n'
                elif cleaned_line.endswith('\r'):
                    cleaned_line = cleaned_line[:-1] + '\n'
                elif not cleaned_line.endswith('\n') and line_num < len(lines):
                    # Add newline if it's not the last line and doesn't have one
                    cleaned_line += '\n'
                
                cleaned_lines.append(cleaned_line)
            
            # Join lines and handle multiple consecutive blank lines
            content = ''.join(cleaned_lines)
            
            # Fix multiple consecutive blank lines (replace 3+ with 2)
            content = re.sub(r'\n{3,}', '\n\n', content)
            
            # Remove any remaining whitespace-only lines at start/end
            content = re.sub(r'^[ \t]+$', '', content, flags=re.MULTILINE)
            
            # Ensure file ends with exactly one newline
            content = content.rstrip() + '\n'
            
            # Only write if content changed
            if content != original_content:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                self.log("File cleaned", "success")
                if backup_path:
                    self.log(f"Backup saved: {backup_path}")
            else:
                self.log("No changes needed", "info")
                if backup_path:
                    backup_path.unlink()  # Remove unnecessary backup
            
            return True
            
        except Exception as e:
            self.log(f"Error cleaning file {file_path}: {e}", "error")
            # Restore from backup if it exists
            if backup_path and backup_path.exists():
                shutil.copy2(backup_path, file_path)
                self.log("Restored from backup", "warning")
            return False
    
    def clean_all(self, files: List[Path], create_backup: bool = True, dry_run: bool = False, auto_cleanup: bool = False) -> bool:
        """Clean all files iteratively"""
        self.log("Cleaning files...")
        
        if create_backup and not dry_run:
            self.backup_dir.mkdir(exist_ok=True)
        
        success_count = 0
        for file_path in files:
            if self.clean_file(file_path, create_backup, dry_run):
                success_count += 1
            print()  # Empty line between files
        
        if not dry_run:
            self.log(f"Cleaned {success_count}/{len(files)} files", "success")
            
            if auto_cleanup and self.backup_dir.exists():
                self.log("Auto-cleaning up backup files...")
                shutil.rmtree(self.backup_dir)
                self.log("Backup files cleaned up!", "success")
            elif self.backup_dir.exists():
                self.log(f"Backups stored in: {self.backup_dir}")
        else:
            self.log("DRY RUN - No changes were made", "info")
        
        return success_count == len(files)
    
    def cleanup_backups(self) -> None:
        """Clean up backup files"""
        if self.backup_dir.exists():
            backup_count = len(list(self.backup_dir.glob("*.backup")))
            if backup_count > 0:
                self.log(f"Found {backup_count} backup files")
                response = input("🧹 Do you want to clean up all backup files? (y/N): ")
                if response.lower() in ['y', 'yes']:
                    shutil.rmtree(self.backup_dir)
                    self.log("Backup files cleaned up!", "success")
                else:
                    self.log(f"Backup files kept in: {self.backup_dir}")
            else:
                self.log("No backup files found")
        else:
            self.log("No backup directory found")

def main():
    parser = argparse.ArgumentParser(
        description="Document Cleanup Tool for Manifest CLI - Clean whitespace and formatting",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s clean                           # Clean all text files
  %(prog)s clean --dry-run                 # Show what would be cleaned
  %(prog)s clean --include-temp            # Include temp files
  %(prog)s clean --include "*.md" "*.txt"  # Clean specific file types
  %(prog)s clean --auto-cleanup            # Auto-cleanup backups
        """
    )
    
    parser.add_argument('command', choices=['clean', 'cleanup-backups'],
                       help='Command to execute')
    parser.add_argument('--include', action='append', help='Include specific file patterns')
    parser.add_argument('--include-temp', action='store_true', help='Include temporary files')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose output')
    parser.add_argument('--debug', '-d', action='store_true', help='Enable debug output')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without making changes')
    parser.add_argument('--no-backup', action='store_true', help='Skip backup creation')
    parser.add_argument('--auto-cleanup', action='store_true', help='Automatically clean up backups after cleaning')
    parser.add_argument('--exclude', action='append', help='Exclude patterns (can be used multiple times)')
    
    args = parser.parse_args()
    
    cleaner = DocumentCleanup(verbose=args.verbose, debug=args.debug)
    
    # Update exclude patterns if provided
    if args.exclude:
        cleaner.exclude_patterns.extend(args.exclude)
    
    # Get files to process
    files = cleaner.find_files(
        include_patterns=args.include,
        include_temp=args.include_temp
    )
    
    if not files:
        cleaner.log("No files found to clean", "warning")
        return 0
    
    # Execute command
    if args.command == 'clean':
        success = cleaner.clean_all(
            files,
            create_backup=not args.no_backup,
            dry_run=args.dry_run,
            auto_cleanup=args.auto_cleanup
        )
        return 0 if success else 1
    
    elif args.command == 'cleanup-backups':
        cleaner.cleanup_backups()
        return 0
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
