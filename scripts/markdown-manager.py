#!/usr/bin/env python3
"""
Markdown Manager for Manifest CLI
Focused on markdown validation and template generation only.
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import List, Tuple
from datetime import datetime

class MarkdownManager:
    def __init__(self, verbose: bool = False, debug: bool = False):
        self.verbose = verbose
        self.debug = debug
        self.exclude_patterns = [
            "docs/zArchive/*",
            "node_modules/*",
            ".git/*",
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
    
    def find_markdown_files(self, include_patterns: List[str] = None) -> List[Path]:
        """Find all markdown files, excluding specified patterns"""
        files = []
        
        for root, dirs, filenames in os.walk("."):
            # Skip excluded directories
            dirs[:] = [d for d in dirs if not any(
                Path(root) / d == Path(pattern.rstrip("/*")) for pattern in self.exclude_patterns
            )]
            
            for filename in filenames:
                if filename.endswith('.md'):
                    file_path = Path(root) / filename
                    # Check if file should be excluded
                    if not any(file_path.match(pattern) for pattern in self.exclude_patterns):
                        files.append(file_path)
        
        return sorted(files)
    
    def validate_file(self, file_path: Path) -> Tuple[int, int]:
        """Validate a single markdown file. Returns (errors, warnings)"""
        errors = 0
        warnings = 0
        
        if not file_path.exists():
            self.log(f"File not found: {file_path}", "error")
            return 1, 0
        
        if not file_path.is_file():
            self.log(f"Not a file: {file_path}", "error")
            return 1, 0
        
        try:
            content = file_path.read_text(encoding='utf-8')
        except Exception as e:
            self.log(f"Cannot read file {file_path}: {e}", "error")
            return 1, 0
        
        self.log(f"Validating: {file_path.name}")
        
        # Check 1: Trailing whitespace
        if re.search(r'[ \t]+$', content, re.MULTILINE):
            self.log("Trailing whitespace found", "error")
            errors += 1
        
        # Check 2: Multiple consecutive blank lines (more than 2)
        if re.search(r'\n\s*\n\s*\n\s*\n', content):
            self.log("Multiple consecutive blank lines found", "error")
            errors += 1
        
        # Check 3: Proper heading hierarchy
        prev_level = 0
        for line_num, line in enumerate(content.split('\n'), 1):
            heading_match = re.match(r'^(#+)\s+', line)
            if heading_match:
                current_level = len(heading_match.group(1))
                if current_level > prev_level + 1:
                    self.log(f"Heading level skipped at line {line_num}: {line.strip()}", "error")
                    errors += 1
                prev_level = current_level
        
        # Check 4: Unclosed code blocks
        code_blocks = len(re.findall(r'^```', content, re.MULTILINE))
        if code_blocks > 0 and code_blocks % 2 != 0:
            self.log("Unclosed code block found", "error")
            errors += 1
        
        # Check 5: File should end with newline
        if content and not content.endswith('\n'):
            self.log("File should end with newline", "warning")
            warnings += 1
        
        # Check 6: Empty file
        if not content.strip():
            self.log("File is empty", "error")
            errors += 1
        
        # Check 7: Should start with header
        if content.strip() and not content.strip().startswith('#'):
            self.log("File should start with a header (# Title)", "warning")
            warnings += 1
        
        # Report results
        if errors == 0 and warnings == 0:
            self.log("Valid", "success")
        elif errors == 0:
            self.log(f"{warnings} warning(s)", "warning")
        else:
            self.log(f"{errors} error(s), {warnings} warning(s)", "error")
        
        return errors, warnings
    
    def validate_all(self, files: List[Path]) -> bool:
        """Validate all markdown files"""
        self.log("Validating markdown files...")
        
        total_errors = 0
        total_warnings = 0
        processed = 0
        
        for file_path in files:
            errors, warnings = self.validate_file(file_path)
            total_errors += errors
            total_warnings += warnings
            processed += 1
            print()  # Empty line between files
        
        self.log(f"Validation Summary:")
        self.log(f"  Files processed: {processed}")
        self.log(f"  Files with errors: {total_errors}")
        self.log(f"  Files with warnings: {total_warnings}")
        
        if total_errors == 0:
            self.log("All markdown files are valid!", "success")
            return True
        else:
            self.log(f"Found {total_errors} files with issues", "error")
            return False
    
    def generate_template(self, template_type: str, *args) -> str:
        """Generate markdown templates"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
        
        if template_type == "release":
            release_type = args[0] if args else "patch"
            
            return f"""# Release

**Release Date:** {timestamp}  
**Release Type:** {release_type}

## 🎯 What's New

This release includes various improvements and bug fixes.

## 🔧 Changes

- General improvements and bug fixes
- Enhanced CLI functionality
- Improved error handling

## 🚀 Installation

```bash
# Install the CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash

# Or clone and install manually
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli
./install-cli.sh
```

## 📋 Usage

```bash
# Complete workflow
manifest go

# Version bump
manifest go patch

# Documentation
manifest docs
```

## 📚 Documentation

- [User Guide](docs/USER_GUIDE.md)
- [Command Reference](docs/COMMAND_REFERENCE.md)
- [Examples](docs/EXAMPLES.md)

## 🔗 Links

- [GitHub Repository](https://github.com/fidenceio/fidenceio.manifest.cli)
- [Issues](https://github.com/fidenceio/fidenceio.manifest.cli/issues)
- [Discussions](https://github.com/fidenceio/fidenceio.manifest.cli/discussions)

---
*Generated by Manifest CLI*"""
        
        elif template_type == "changelog":
            release_type = args[0] if args else "patch"
            
            return f"""# Changelog

**Release Date:** {timestamp}  
**Release Type:** {release_type}

## 🆕 New Features

- Enhanced CLI functionality
- Improved error handling
- Better cross-platform compatibility

## 🔧 Improvements

- Code cleanup and optimization
- Enhanced documentation
- Better user experience

## 🐛 Bug Fixes

- Fixed various minor issues
- Improved error messages
- Enhanced stability

## 📚 Documentation

- Updated user guide
- Enhanced examples
- Improved command reference

## 🔄 Changes

- Updated dependencies
- Improved performance
- Enhanced security

---
*Generated by Manifest CLI*"""
        
        else:
            return f"Unknown template type: {template_type}"

def main():
    parser = argparse.ArgumentParser(
        description="Markdown Manager for Manifest CLI - Validation and Template Generation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s validate                           # Validate all markdown files
  %(prog)s template release patch             # Generate release template
  %(prog)s template changelog minor           # Generate changelog template
        """
    )
    
    parser.add_argument('command', choices=['validate', 'template'],
                       help='Command to execute')
    parser.add_argument('files', nargs='*', help='Specific files to process')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose output')
    parser.add_argument('--debug', '-d', action='store_true', help='Enable debug output')
    parser.add_argument('--exclude', action='append', help='Exclude patterns (can be used multiple times)')
    
    args = parser.parse_args()
    
    manager = MarkdownManager(verbose=args.verbose, debug=args.debug)
    
    # Update exclude patterns if provided
    if args.exclude:
        manager.exclude_patterns.extend(args.exclude)
    
    # Get files to process (skip for template command)
    if args.command == 'template':
        files = []
    elif args.files:
        files = [Path(f) for f in args.files if f.endswith('.md')]
    else:
        files = manager.find_markdown_files()
    
    if not files and args.command != 'template':
        manager.log("No markdown files found", "warning")
        return 0
    
    # Execute command
    if args.command == 'validate':
        success = manager.validate_all(files)
        return 0 if success else 1
    
    elif args.command == 'template':
        if len(args.files) < 1:
            manager.log("Template command requires template type", "error")
            return 1
        
        template_type = args.files[0]
        template_args = args.files[1:] if len(args.files) > 1 else []
        
        result = manager.generate_template(template_type, *template_args)
        print(result)
        return 0
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
