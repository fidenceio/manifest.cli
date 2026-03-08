# 📚 Manifest CLI Command Reference

**A powerful CLI tool for versioning, AI documenting, and repository operations.**

This document provides a complete reference for all commands, options, and functions available in the Manifest CLI.

## 🎯 About This Reference

This reference covers the current capabilities of Manifest CLI (version 31.0.0+) and outlines planned features for future versions. The tool is designed with extensibility in mind, allowing for continuous improvement and new functionality.

## 🎯 Command Overview

| Command | Description | Usage |
|---------|-------------|-------|
| `manifest prep` | Main workflow command | `manifest prep [type] [options]` |
| `manifest pr` | Preferred PR landing command | `manifest pr [queue-options]` |
| `manifest fleet pr` | Preferred fleet PR landing command | `manifest fleet pr [queue-options]` |
| `manifest test` | Run tests | `manifest test [component] [options]` |
| `manifest ntp` | Get NTP timestamp | `manifest ntp [options]` |
| `manifest docs` | Generate documentation | `manifest docs [type] [options]` |
| `manifest sync` | Sync repository | `manifest sync [options]` |
| `manifest security` | Security audit | `manifest security [options]` |
| `manifest config` | Interactive configuration wizard | `manifest config [show|ntp|setup]` |
| `manifest cleanup` | Clean repository | `manifest cleanup [options]` |
| `manifest update` | Update CLI | `manifest update [options]` |
| `manifest uninstall` | Remove CLI | `manifest uninstall [options]` |
| `manifest cloud` | Cloud integration | `manifest cloud [command] [options]` |
| `manifest agent` | Containerized agent | `manifest agent [command] [options]` |
| `manifest --help` | Show help | `manifest --help` |
| `manifest --version` | Show version | `manifest --version` |

## 🚀 Core Commands

## `manifest prep` - Main Workflow

The primary command that orchestrates the entire release process with intelligent automation.

## Syntax
```bash
manifest prep [type] [options]
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
manifest prep

# Minor version bump
manifest prep minor

# Interactive major version bump
manifest prep major --interactive

# Dry run to see what would happen
manifest prep --dry-run
```

## Workflow Steps
1. **🕐 NTP Timestamp**: Get trusted timestamp from multiple servers
2. **📝 Change Detection**: Check for uncommitted changes and auto-commit
3. **🔄 Remote Sync**: Pull latest changes from remote
4. **📦 Version Bump**: Increment version according to type
5. **🤖 AI Documentation**: Generate intelligent release notes and changelog
6. **📁 Archive**: Archive previous version documentation
7. **🏷️ Git Operations**: Commit, tag, and push to all remotes

## `manifest pr` - Preferred PR Landing

The default PR command is now `manifest pr`, which behaves as shorthand for `manifest pr queue`.

## Syntax
```bash
manifest pr [options]
```

## Options
- `--pr <number|url|branch>`: Select an explicit PR target
- `--method <merge|squash|rebase>`: Choose merge strategy (default: `squash`)
- `--force`: Bypass readiness gate
- `--no-delete-branch`: Keep source branch after merge

## Examples
```bash
# Queue resolved PR with default method (squash)
manifest pr

# Queue specific PR with explicit method
manifest pr --pr 123 --method rebase

# Legacy equivalent (still supported)
manifest pr queue --method squash
```

## `manifest fleet pr` - Preferred Fleet PR Landing

For multi-repo fleets, `manifest fleet pr` now defaults to `manifest fleet pr queue`.

## Syntax
```bash
manifest fleet pr [options]
```

## Options
- `--method <merge|squash|rebase>`: Choose merge strategy for queued fleet PRs (default: `squash`)
- `--force`: Bypass readiness gate for fleet queueing
- `--no-delete-branch`: Keep source branches after merge

## Examples
```bash
# Queue fleet PRs with default method (squash)
manifest fleet pr

# Queue fleet PRs with explicit method
manifest fleet pr --method merge

# Explicit equivalent
manifest fleet pr queue --method merge
```

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
  - `cloud`: Test Manifest Cloud MCP connectivity
  - `agent`: Test Manifest Agent functionality

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

# Test cloud and agent paths
manifest test cloud
manifest test agent

# Verbose testing
manifest test --verbose

# Test with timeout
manifest test --timeout 30
```

## Test Logs and Issue Flow
- Every run writes logs to `~/.manifest-cli/logs/tests/<run-id>/`
- `raw.log`: full output
- `sanitized.log`: redacted output suitable for sharing (strict redaction by default)
- Use `--no-strict-redact` to relax sanitization
- Interactive runs prompt to optionally create a GitHub Issue from the sanitized log
- Issues are created in the main Manifest repository: `fidenceio/fidenceio.manifest.cli`

## Test Components

### Version Management Tests
- Version file detection and validation
- Version increment logic and arithmetic
- Package.json integration
- VERSION file handling
- Multi-format version support

### NTP Tests
- Server connectivity and response time
- Timestamp accuracy and precision
- Timezone handling and conversion
- Fallback mechanisms and error handling
- Multi-server redundancy

### Git Tests
- Repository status and configuration
- Remote configuration and authentication
- Branch information and management
- Push/pull operations
- Tag creation and management

### Documentation Tests
- Template generation and validation
- File creation and permissions
- Content validation and formatting
- Link verification and integrity
- Template customization

### OS Tests
- Platform detection and optimization
- Feature availability and compatibility
- Performance optimization
- Cross-platform compatibility
- Command availability

### Cross-Shell Compatibility Tests
- **Zsh 5.9 Testing**: `manifest test zsh`
  - Zsh environment detection
  - Bash compatibility within Zsh
  - Conditional function testing
  - String comparison validation
  - File and directory operations
  - Core CLI command execution
  - Error handling verification
  - Environment variable handling
  - Module loading validation
  - Cross-shell consistency checks

- **Bash 3.2 Testing**: `manifest test bash32`
  - Bash 3.2 environment detection
  - Capability detection validation
  - Conditional function compatibility
  - String comparison edge cases
  - File and directory checks
  - Core CLI command execution
  - Error handling verification
  - Environment variable handling
  - Module loading validation
  - Bash 3.2 specific syntax testing

- **Bash 4+ Testing**: `manifest test bash4`
  - Bash 4+ environment detection
  - Advanced capability detection
  - Conditional function testing
  - String comparison validation
  - File and directory operations
  - Core CLI command execution
  - Error handling verification
  - Environment variable handling
  - Module loading validation
  - Bash 4+ specific features (associative arrays, advanced parameter expansion)

- **Auto-Detection Testing**: `manifest test bash`
  - Automatically detects current Bash version
  - Runs appropriate compatibility tests
  - Provides version-specific feedback
  - Ensures optimal performance for current environment

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

## NTP Configuration Views
```bash
# NTP-only configuration
manifest config ntp
```

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

## `manifest security` - Security Audit

Perform comprehensive security audits and privacy protection scans.

## Syntax
```bash
manifest security [options]
```

## Options
- `--vulnerabilities`: Check for security vulnerabilities
- `--privacy`: Scan for privacy-sensitive information
- `--paths`: Validate file paths for security issues
- `--input`: Validate input parameters
- `--network`: Check network security settings
- `--verbose` or `-v`: Show detailed security information

## Examples
```bash
# Run full security audit
manifest security

# Check for vulnerabilities only
manifest security --vulnerabilities

# Privacy protection scan
manifest security --privacy

# Validate file paths
manifest security --paths

# Verbose security report
manifest security --verbose
```

## Security Features
- **Path Validation**: Prevents directory traversal attacks
- **Input Sanitization**: Validates and sanitizes user inputs
- **Command Injection Protection**: Prevents malicious command execution
- **Privacy Scanning**: Detects sensitive information in files
- **Network Security**: Validates URL and network configurations

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

All Manifest CLI environment variables use the `MANIFEST_CLI_` prefix for consistency and safety.

## Core Configuration
- `MANIFEST_CLI_DEBUG`: Enable debug mode (true/false)
- `MANIFEST_CLI_VERBOSE`: Enable verbose output (true/false)
- `MANIFEST_CLI_LOG_LEVEL`: Logging level (DEBUG, INFO, WARN, ERROR)
- `MANIFEST_CLI_INTERACTIVE`: Interactive mode (true/false)
- `MANIFEST_CLI_CONFIG`: Configuration file path

## NTP Configuration
- `MANIFEST_CLI_NTP_SERVERS`: Custom NTP server list (comma-separated)
- `MANIFEST_CLI_NTP_TIMEOUT`: Connection timeout in seconds (default: 5)
- `MANIFEST_CLI_NTP_RETRIES`: Retry attempt count (default: 3)
- `MANIFEST_CLI_NTP_VERIFY`: Enable timestamp verification (true/false)

## Git Configuration
- `MANIFEST_CLI_GIT_COMMIT_TEMPLATE`: Commit message template
- `MANIFEST_CLI_GIT_AUTHOR_NAME`: Default author name
- `MANIFEST_CLI_GIT_AUTHOR_EMAIL`: Default author email
- `MANIFEST_CLI_GIT_PUSH_STRATEGY`: Git push strategy (simple, upstream, current)
- `MANIFEST_CLI_GIT_PULL_STRATEGY`: Git pull strategy (rebase, merge, ff-only)
- `MANIFEST_CLI_GIT_TIMEOUT`: Git operation timeout in seconds (default: 300)
- `MANIFEST_CLI_GIT_RETRIES`: Number of retry attempts for failed operations (default: 3)
- Note: Manifest CLI automatically uses all configured git remotes with retry logic

## Documentation Configuration
- `MANIFEST_CLI_DOCS_TEMPLATE_DIR`: Template directory path
- `MANIFEST_CLI_DOCS_OUTPUT_DIR`: Output directory path
- `MANIFEST_CLI_DOCS_FORMAT`: Output format (markdown, html, json)
- `MANIFEST_CLI_DOCS_AUTO_GENERATE`: Auto-generate docs on release (true/false)

## Homebrew Configuration
- `MANIFEST_CLI_BREW_OPTION`: Control Homebrew functionality (enabled/disabled)
- `MANIFEST_CLI_BREW_INTERACTIVE`: Interactive Homebrew updates (yes/no)
- `MANIFEST_CLI_TAP_REPO`: Homebrew tap repository URL

## Auto-Update Configuration
- `MANIFEST_CLI_AUTO_UPDATE`: Enable automatic update checking (true/false, default: true)
- `MANIFEST_CLI_UPDATE_COOLDOWN`: Cooldown period between update checks in minutes (default: 30)

## OS Configuration
- `MANIFEST_CLI_OS_PLATFORM`: Override platform detection
- `MANIFEST_CLI_OS_ARCH`: Override architecture detection
- `MANIFEST_CLI_OS_VERSION`: Override OS version

## Cloud Configuration
- `MANIFEST_CLI_CLOUD_API_KEY`: Manifest Cloud API key
- `MANIFEST_CLI_CLOUD_ENDPOINT`: Manifest Cloud endpoint URL
- `MANIFEST_CLI_CLOUD_SKIP`: Skip cloud integration (true/false)
- `MANIFEST_CLI_OFFLINE_MODE`: Force offline mode (true/false)

## 📁 Configuration Files

## `.env.manifest.global`
Primary configuration file in project root:

```bash
# .env.manifest.global
# Core configuration
MANIFEST_CLI_DEBUG=false
MANIFEST_CLI_VERBOSE=false
MANIFEST_CLI_LOG_LEVEL="INFO"
MANIFEST_CLI_INTERACTIVE=true

# NTP configuration
MANIFEST_CLI_NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=3

# Git configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_TIMEOUT=300
MANIFEST_CLI_GIT_RETRIES=3

# Documentation configuration
MANIFEST_CLI_DOCS_TEMPLATE_DIR="./templates"
MANIFEST_CLI_DOCS_OUTPUT_DIR="./docs"

# Homebrew configuration
MANIFEST_CLI_BREW_OPTION="enabled"
MANIFEST_CLI_BREW_INTERACTIVE="no"
MANIFEST_CLI_TAP_REPO="https://github.com/fidenceio/homebrew-tap.git"

# Cloud configuration
MANIFEST_CLI_CLOUD_API_KEY="your-api-key-here"
MANIFEST_CLI_CLOUD_ENDPOINT="https://api.manifest.cloud"
MANIFEST_CLI_CLOUD_SKIP=false
MANIFEST_CLI_OFFLINE_MODE=false
```

## Configuration Priority
1. Command line options
2. Environment variables
3. `.env.manifest.global` in project root
4. `.env.manifest.local` in project root (for local overrides)
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
manifest prep --quiet
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
export MANIFEST_CLI_DEBUG=true
manifest prep
```

## 🔗 Integration

## CI/CD Pipelines
```yaml
# GitHub Actions example
- name: Release
  run: |
    manifest test all
    manifest prep patch
    manifest docs
```

## Scripts
```bash
#!/bin/bash
# Release script
manifest test all
manifest prep minor
manifest docs
```

## Automation
```bash
# Automated release
if manifest test; then
  manifest prep patch
  echo "Release successful"
else
  echo "Tests failed"
  exit 1
fi
```

## Homebrew Integration
```bash
# Install via Homebrew
brew tap fidenceio/manifest
brew install manifest

# Upgrade to latest version
brew upgrade manifest

# Homebrew configuration variables
export MANIFEST_CLI_BREW_OPTION=enabled
export MANIFEST_CLI_TAP_REPO="https://github.com/fidenceio/homebrew-tap.git"
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
export MANIFEST_CLI_NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org"

# Set timeout and retry values
export MANIFEST_CLI_NTP_TIMEOUT=5
export MANIFEST_CLI_NTP_RETRIES=3
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
export MANIFEST_CLI_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# Author information
export MANIFEST_CLI_GIT_AUTHOR_NAME="Your Name"
export MANIFEST_CLI_GIT_AUTHOR_EMAIL="your.email@example.com"
```

## 📋 Examples

## Basic Release Workflow
```bash
# 1. Test everything
manifest test all

# 2. Run complete workflow
manifest prep

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
manifest prep minor
```

## Major Release
```bash
# 1. Prepare for major release
manifest test all

# 2. Review breaking changes
git log --oneline $(git describe --tags --abbrev=0)..HEAD

# 3. Major version bump
manifest prep major

# 4. Verify release
manifest docs
cat docs/RELEASE_v$(cat VERSION).md
```

---

*For more examples and use cases, see the [User Guide](USER_GUIDE.md) and [Examples](EXAMPLES.md).*
