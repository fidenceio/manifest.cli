# 📚 Manifest CLI Command Reference

**A powerful CLI tool for versioning, AI documenting, and repository operations.**

This document provides a complete reference for all commands, options, and functions available in the Manifest CLI.

## 🎯 About This Reference

This reference covers the current capabilities of Manifest CLI (version 8.6.7+) and outlines planned features for future versions. The tool is designed with extensibility in mind, allowing for continuous improvement and new functionality.

## 🎯 Command Overview

| Command | Description | Usage |
|---------|-------------|-------|
| `manifest go` | Main workflow command | `manifest go [type] [options]` |
| `manifest test` | Run tests | `manifest test [component] [options]` |
| `manifest ntp` | Get NTP timestamp | `manifest ntp [options]` |
| `manifest docs` | Generate documentation | `manifest docs [type] [options]` |
| `manifest sync` | Sync repository | `manifest sync [options]` |
| `manifest --help` | Show help | `manifest --help` |
| `manifest --version` | Show version | `manifest --version` |

## 🚀 Core Commands

## `manifest go` - Main Workflow

The primary command that orchestrates the entire release process with intelligent automation.

## Syntax
```bash
manifest go [type] [options]
```

## Parameters
- **`type`** (optional): Version increment type
  - `patch` (default): 1.0.0 → 1.0.1
  - `minor`: 1.0.0 → 1.1.0
  - `major`: 1.0.0 → 2.0.0
  - `revision`: 1.0.0 → 1.0.0.1

## Options
- `--interactive` or `-i`: Enable interactive mode
- `--dry-run` or `-d`: Show what would happen without executing
- `--force` or `-f`: Force execution even with warnings
- `--verbose` or `-v`: Enable verbose output
- `--debug`: Enable debug mode

## Examples
```bash
# Basic patch version bump
manifest go

# Minor version bump
manifest go minor

# Interactive major version bump
manifest go major --interactive

# Dry run to see what would happen
manifest go --dry-run
```

## Workflow Steps
1. **🕐 NTP Timestamp**: Get trusted timestamp from multiple servers
2. **📝 Change Detection**: Check for uncommitted changes and auto-commit
3. **🔄 Remote Sync**: Pull latest changes from remote
4. **📦 Version Bump**: Increment version according to type
5. **🤖 AI Documentation**: Generate intelligent release notes and changelog
6. **🏷️ Git Operations**: Commit, tag, and push to all remotes
7. **🍺 Homebrew Update**: Update formula if applicable

## `manifest test` - Testing Framework

Comprehensive testing suite for validating CLI functionality and workflow integrity.

## Syntax
```bash
manifest test [component] [options]
```

## Parameters
- **`component`** (optional): Specific test component
  - `all` (default): Run all tests
  - `versions`: Test version management
  - `ntp`: Test NTP functionality
  - `git`: Test Git operations
  - `docs`: Test documentation generation
  - `os`: Test OS detection

## Options
- `--verbose` or `-v`: Show detailed test output
- `--fail-fast`: Stop on first failure
- `--coverage`: Show test coverage
- `--timeout <seconds>`: Set test timeout

## Examples
```bash
# Run all tests
manifest test

# Test specific component
manifest test ntp

# Verbose testing
manifest test --verbose

# Test with timeout
manifest test --timeout 30
```

## Test Components

### Version Management Tests
- Version file detection and validation
- Version increment logic and arithmetic
- Package.json integration
- VERSION file handling
- Multi-format version support

#### NTP Tests
- Server connectivity and response time
- Timestamp accuracy and precision
- Timezone handling and conversion
- Fallback mechanisms and error handling
- Multi-server redundancy

#### Git Tests
- Repository status and configuration
- Remote configuration and authentication
- Branch information and management
- Push/pull operations
- Tag creation and management

#### Documentation Tests
- Template generation and validation
- File creation and permissions
- Content validation and formatting
- Link verification and integrity
- Template customization

#### OS Tests
- Platform detection and optimization
- Feature availability and compatibility
- Performance optimization
- Cross-platform compatibility
- Command availability

## `manifest ntp` - NTP Timestamp

Get trusted timestamps from NTP servers for verification, compliance, and audit purposes.

## Syntax
```bash
manifest ntp [options]
```

## Options
- `--servers <list>`: Custom NTP servers (comma-separated)
- `--format <format>`: Custom timestamp format
- `--verify`: Verify timestamp accuracy
- `--timeout <seconds>`: Connection timeout
- `--retries <count>`: Retry attempts
- `--json`: Output in JSON format

## Examples
```bash
# Get basic timestamp
manifest ntp

# Custom servers
manifest ntp --servers="time.google.com,pool.ntp.org"

# Custom format
manifest ntp --format="%Y-%m-%d %H:%M:%S UTC"

# Verify accuracy
manifest ntp --verify

# JSON output
manifest ntp --json
```

## Default NTP Servers
- `time.apple.com` (Apple)
- `time.google.com` (Google)
- `pool.ntp.org` (NTP Pool)

## Output Format
```bash
🕐 Getting trusted NTP timestamp...

📡 Connecting to NTP servers...
✅ Connected to time.apple.com
✅ Connected to time.google.com
✅ Connected to pool.ntp.org

🕐 Timestamp: 2025-01-13 15:30:45 UTC
📍 Timezone: UTC
🔒 Verification: Trusted (3 servers)
⏱️  Accuracy: ±0.001 seconds
🎯 Method: external
📊 Offset: +0.002 seconds
```

## `manifest docs` - AI-Powered Documentation

Automatically generate and update documentation with intelligent analysis and template processing.

## Syntax
```bash
manifest docs [type] [options]
```

## Parameters
- **`type`** (optional): Documentation type
  - `all` (default): Generate all documentation
  - `release`: Release notes only
  - `changelog`: Changelog only
  - `metadata`: Repository metadata

## Options
- `--template-dir <path>`: Custom template directory
- `--output-dir <path>`: Custom output directory
- `--force` or `-f`: Overwrite existing files
- `--dry-run` or `-d`: Show what would be generated
- `--version <version>`: Specify version for generation

## Examples
```bash
# Generate all documentation
manifest docs

# Generate specific type
manifest docs release

# Custom template directory
manifest docs --template-dir="./templates"

# Force overwrite
manifest docs --force
```

## Generated Files
- `docs/RELEASE_v{version}.md` - Professional release notes
- `docs/CHANGELOG_v{version}.md` - Intelligent changelog
- `README.md` updates - Version information synchronization

## `manifest sync` - Repository Synchronization

Keep local repository synchronized with remote repositories.

## Syntax
```bash
manifest sync [options]
```

## Options
- `--branch <name>`: Sync specific branch
- `--force` or `-f`: Force sync (overwrites local changes)
- `--prune`: Remove remote-tracking references
- `--depth <number>`: Shallow clone depth
- `--tags`: Sync tags

## Examples
```bash
# Basic sync
manifest sync

# Force sync
manifest sync --force

# Sync specific branch
manifest sync --branch=develop

# Prune remote references
manifest sync --prune
```

## 🔧 Global Options

These options are available for all commands:

## `--help` or `-h`
Show command help and usage information.

## `--version` or `-V`
Display CLI version information.

## `--verbose` or `-v`
Enable verbose output with detailed information.

## `--debug`
Enable debug mode with extensive logging.

## `--quiet` or `-q`
Suppress non-essential output.

## `--config <file>`
Specify custom configuration file.

## 🌍 Environment Variables

## Core Configuration
- `MANIFEST_DEBUG`: Enable debug mode
- `MANIFEST_VERBOSE`: Enable verbose output
- `MANIFEST_CONFIG`: Configuration file path
- `MANIFEST_LOG_LEVEL`: Logging level (DEBUG, INFO, WARN, ERROR)

## NTP Configuration
- `MANIFEST_NTP_SERVERS`: Custom NTP server list
- `MANIFEST_NTP_TIMEOUT`: Connection timeout in seconds
- `MANIFEST_NTP_RETRIES`: Retry attempt count
- `MANIFEST_NTP_FALLBACK`: Fallback server list

## Git Configuration
- `MANIFEST_GIT_COMMIT_TEMPLATE`: Commit message template
- `MANIFEST_GIT_AUTHOR_NAME`: Default author name
- `MANIFEST_GIT_AUTHOR_EMAIL`: Default author email
- `MANIFEST_GIT_PUSH_STRATEGY`: Git push strategy (simple, upstream, current)
- `MANIFEST_GIT_PULL_STRATEGY`: Git pull strategy (rebase, merge, ff-only)
- `MANIFEST_GIT_TIMEOUT`: Git operation timeout in seconds (default: 300)
- `MANIFEST_GIT_RETRIES`: Number of retry attempts for failed operations (default: 3)
- Note: Manifest CLI automatically uses all configured git remotes with retry logic

## Documentation Configuration
- `MANIFEST_DOCS_TEMPLATE_DIR`: Template directory path
- `MANIFEST_DOCS_OUTPUT_DIR`: Output directory path
- `MANIFEST_DOCS_FORMAT`: Output format (markdown, html, json)

## Homebrew Configuration
- `MANIFEST_BREW_OPTION`: Control Homebrew functionality (enabled/disabled)
- `MANIFEST_BREW_INTERACTIVE`: Interactive Homebrew updates (yes/no)
- `MANIFEST_TAP_REPO`: Homebrew tap repository URL

## Auto-Update Configuration
- `MANIFEST_AUTO_UPDATE`: Enable automatic update checking (true/false, default: true)
- `MANIFEST_UPDATE_COOLDOWN`: Cooldown period between update checks in minutes (default: 30)

## OS Configuration
- `MANIFEST_OS_PLATFORM`: Override platform detection
- `MANIFEST_OS_ARCH`: Override architecture detection
- `MANIFEST_OS_VERSION`: Override OS version

## 📁 Configuration Files

## `.manifestrc`
Configuration file in project root or home directory:

```bash
# .manifestrc
NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org"
COMMIT_TEMPLATE="Release v{version} - {timestamp}"
DOCS_TEMPLATE_DIR="./templates"
DEBUG=false
INTERACTIVE=true
VERBOSE=false
LOG_LEVEL="INFO"
BREW_OPTION=enabled
BREW_INTERACTIVE=no
TAP_REPO="https://github.com/fidenceio/fidenceio-homebrew-tap.git"
```

## Configuration Priority
1. Command line options
2. Environment variables
3. `.manifestrc` in project root
4. `.manifestrc` in home directory
5. Default values

## 🔄 Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| `0` | Success | Command completed successfully |
| `1` | General Error | General error occurred |
| `2` | Usage Error | Invalid command or option |
| `3` | Configuration Error | Configuration file or environment issue |
| `4` | Network Error | Network connectivity issue |
| `5` | Git Error | Git operation failed |
| `6` | Permission Error | File or directory permission issue |
| `7` | Validation Error | Input validation failed |
| `8` | System Error | System-level error |

## 📊 Output Formats

## Standard Output
Default human-readable format with emojis and formatting.

## JSON Output
Machine-readable format for automation:

```bash
manifest ntp --json
```

```json
{
  "timestamp": "2025-01-13T15:30:45Z",
  "timezone": "UTC",
  "servers": ["time.apple.com", "time.google.com", "pool.ntp.org"],
  "accuracy": "±0.001",
  "verification": "trusted",
  "method": "external",
  "offset": "+0.002"
}
```

## Quiet Output
Minimal output for scripting:

```bash
manifest go --quiet
```

## 🚨 Error Handling

## Error Types
- **Validation Errors**: Invalid input or configuration
- **Network Errors**: Connectivity or timeout issues
- **Permission Errors**: File system access issues
- **Git Errors**: Repository operation failures
- **System Errors**: OS-level problems

## Error Recovery
- Automatic retries for transient failures
- Fallback mechanisms for critical operations
- Detailed error messages with suggestions
- Logging for debugging and audit trails

## Debugging
Enable debug mode for detailed troubleshooting:

```bash
export MANIFEST_DEBUG=true
manifest go
```

## 🔗 Integration

## CI/CD Pipelines
```yaml
# GitHub Actions example
- name: Release
  run: |
    manifest test all
    manifest go patch
    manifest docs
```

## Scripts
```bash
#!/bin/bash
# Release script
manifest test all
manifest go minor
manifest docs
```

## Automation
```bash
# Automated release
if manifest test; then
  manifest go patch
  echo "Release successful"
else
  echo "Tests failed"
  exit 1
fi
```

## Homebrew Integration
```bash
# Update Homebrew formula
manifest docs homebrew

# Control Homebrew behavior
export MANIFEST_BREW_OPTION=enabled
export MANIFEST_BREW_INTERACTIVE=no
export MANIFEST_TAP_REPO="https://github.com/your-org/your-tap.git"
```

## 🌟 Advanced Features

## Future Capabilities

Manifest CLI is designed with extensibility in mind. Future versions will include:

- **Plugin System**: Extend functionality with custom plugins
- **REST API**: Remote operations via HTTP endpoints
- **Web Interface**: Browser-based management dashboard
- **Advanced AI**: Smarter commit message generation and analysis
- **Multi-language Support**: Python, Go, and Rust bindings
- **Cloud Integration**: AWS, Azure, and GCP deployment automation
- **Advanced Security**: GPG signing and vulnerability scanning
- **Performance Monitoring**: Real-time metrics and analytics
- **Team Collaboration**: Multi-user workflows and approvals
- **Advanced Templates**: Jinja2 and Handlebars support

## Custom NTP Servers
```bash
# Set custom NTP servers
export MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org"

# Set timeout and retry values
export MANIFEST_NTP_TIMEOUT=5
export MANIFEST_NTP_RETRIES=3
```

## Custom Documentation Templates
```bash
# Create custom templates
mkdir -p templates

# Custom release template
cat > templates/release.md << 'EOF'
# Release v{version}

**Date:** {timestamp}
**Author:** {author}

## Changes
{changes}

## Installation
{installation}

## Breaking Changes
{breaking_changes}
EOF
```

## Git Workflow Customization
```bash
# Custom commit templates
export MANIFEST_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# Author information
export MANIFEST_GIT_AUTHOR_NAME="Your Name"
export MANIFEST_GIT_AUTHOR_EMAIL="your.email@example.com"
```

## 📋 Examples

## Basic Release Workflow
```bash
# 1. Test everything
manifest test all

# 2. Run complete workflow
manifest go

# 3. Verify release
git log --oneline -5
git tag --list -5
```

## Feature Release
```bash
# 1. Complete feature
git checkout -b feature/new-feature
# ... make changes ...
git add .
git commit -m "Feature: Implement new feature"

# 2. Merge to main
git checkout main
git merge feature/new-feature

# 3. Release with minor version
manifest go minor
```

## Major Release
```bash
# 1. Prepare for major release
manifest test all

# 2. Review breaking changes
git log --oneline $(git describe --tags --abbrev=0)..HEAD

# 3. Major version bump
manifest go major

# 4. Verify release
manifest docs
cat docs/RELEASE_v$(cat VERSION).md
```

---

*For more examples and use cases, see the [User Guide](USER_GUIDE.md) and [Examples](EXAMPLES.md).*
