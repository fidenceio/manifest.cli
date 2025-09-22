# 🌟 Manifest CLI Environment Configuration Examples

This document provides real-world examples of how to configure Manifest CLI for different organizations, versioning schemes, and workflows using the current `MANIFEST_CLI_*` variable naming convention.

## 🏢 Enterprise Organization (4-Digit Versioning)

**Use Case**: Large enterprise with strict version control requirements

```bash
# =============================================================================
# Enterprise Configuration - 4-Digit Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XXXX.XXXX.XXXX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="9999,9999,9999"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[RELEASE] v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=600
MANIFEST_CLI_GIT_RETRIES=5

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=50

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_SERVER3="pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=10
MANIFEST_CLI_NTP_RETRIES=3

# Example versions: 0001.0001.0001, 0001.0002.0000, 0002.0000.0000
```

## 🚀 Startup Company (Semantic Versioning)

**Use Case**: Fast-moving startup with standard semantic versioning

```bash
# =============================================================================
# Startup Configuration - Standard Semantic Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=300
MANIFEST_CLI_GIT_RETRIES=3

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=2

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🏭 Manufacturing/Industrial (Date-Based Versioning)

**Use Case**: Manufacturing company with date-based versioning for compliance

```bash
# =============================================================================
# Manufacturing Configuration - Date-Based Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="YYYY.MM.DD"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="year,month,day"
MANIFEST_CLI_VERSION_MAX_VALUES="9999,12,31"
MANIFEST_CLI_GIT_TAG_PREFIX="release-"
MANIFEST_CLI_GIT_TAG_SUFFIX="-stable"

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="production"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="development"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[MANUFACTURING] Release {version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=600
MANIFEST_CLI_GIT_RETRIES=5

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=100

# NTP Configuration (Critical for manufacturing timestamps)
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_SERVER2="time.apple.com"
MANIFEST_CLI_NTP_SERVER3="pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=15
MANIFEST_CLI_NTP_RETRIES=5
MANIFEST_CLI_NTP_VERIFY=true

# Example versions: 2024.03.15, 2024.03.16, 2024.04.01
```

## 🎮 Gaming/Software (Alpha/Beta/Release)

**Use Case**: Game development with alpha/beta/stable release cycles

```bash
# =============================================================================
# Gaming Configuration - Alpha/Beta/Release Cycle
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[GAME] v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=300
MANIFEST_CLI_GIT_RETRIES=3

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=2

# Example versions: 1.0.0-alpha, 1.0.0-beta, 1.0.0
```

## 🏥 Healthcare/Medical (Compliance-Focused)

**Use Case**: Healthcare software with strict compliance and audit requirements

```bash
# =============================================================================
# Healthcare Configuration - Compliance-Focused
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[HEALTHCARE] Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=600
MANIFEST_CLI_GIT_RETRIES=5

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=200

# NTP Configuration (Critical for audit trails)
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_SERVER2="time.apple.com"
MANIFEST_CLI_NTP_SERVER3="pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=15
MANIFEST_CLI_NTP_RETRIES=5
MANIFEST_CLI_NTP_VERIFY=true

# Debug and Logging (Enhanced for compliance)
MANIFEST_CLI_DEBUG=true
MANIFEST_CLI_LOG_LEVEL="INFO"
MANIFEST_CLI_LOG_FILE="manifest-cli.log"

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🏦 Financial Services (High-Security)

**Use Case**: Financial institution with high-security requirements

```bash
# =============================================================================
# Financial Services Configuration - High-Security
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[FINANCIAL] Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=900
MANIFEST_CLI_GIT_RETRIES=10

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=500

# NTP Configuration (Critical for financial timestamps)
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_SERVER2="time.apple.com"
MANIFEST_CLI_NTP_SERVER3="pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=20
MANIFEST_CLI_NTP_RETRIES=10
MANIFEST_CLI_NTP_VERIFY=true

# Security Configuration
MANIFEST_CLI_DEBUG=false
MANIFEST_CLI_LOG_LEVEL="WARN"
MANIFEST_CLI_LOG_FILE="manifest-cli.log"
MANIFEST_CLI_INTERACTIVE_MODE=false

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🎯 Open Source Project (Community-Driven)

**Use Case**: Open source project with community contributions

```bash
# =============================================================================
# Open Source Configuration - Community-Driven
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=300
MANIFEST_CLI_GIT_RETRIES=3

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=2

# Interactive Mode (Community-friendly)
MANIFEST_CLI_INTERACTIVE_MODE=true
MANIFEST_CLI_DEBUG=false

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🔧 Development Team (Multi-Environment)

**Use Case**: Development team with multiple environments and complex workflows

```bash
# =============================================================================
# Development Team Configuration - Multi-Environment
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[TEAM] Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=600
MANIFEST_CLI_GIT_RETRIES=5

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=100

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_SERVER3="pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=10
MANIFEST_CLI_NTP_RETRIES=3

# Auto-Update Configuration
MANIFEST_CLI_AUTO_UPDATE=true
MANIFEST_CLI_UPDATE_COOLDOWN=60
MANIFEST_CLI_BREW_OPTION=true
MANIFEST_CLI_BREW_INTERACTIVE=false

# Debug Configuration
MANIFEST_CLI_DEBUG=true
MANIFEST_CLI_LOG_LEVEL="DEBUG"
MANIFEST_CLI_LOG_FILE="manifest-cli.log"

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 📱 Mobile App Development (Platform-Specific)

**Use Case**: Mobile app development with platform-specific releases

```bash
# =============================================================================
# Mobile App Configuration - Platform-Specific
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[MOBILE] Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=300
MANIFEST_CLI_GIT_RETRIES=3

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=2

# Auto-Update Configuration
MANIFEST_CLI_AUTO_UPDATE=true
MANIFEST_CLI_UPDATE_COOLDOWN=30
MANIFEST_CLI_BREW_OPTION=true
MANIFEST_CLI_BREW_INTERACTIVE=false

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🎨 Creative Agency (Client-Focused)

**Use Case**: Creative agency with client-specific projects

```bash
# =============================================================================
# Creative Agency Configuration - Client-Focused
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[CLIENT] Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=300
MANIFEST_CLI_GIT_RETRIES=3

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"

# NTP Configuration
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=2

# Interactive Mode (Client-friendly)
MANIFEST_CLI_INTERACTIVE_MODE=true
MANIFEST_CLI_DEBUG=false

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🔬 Research/Academic (Publication-Focused)

**Use Case**: Research institution with publication-focused versioning

```bash
# =============================================================================
# Research Configuration - Publication-Focused
# =============================================================================

# Versioning Configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_VERSION_SEPARATOR="."
MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_CLI_VERSION_MAX_VALUES="99,99,99"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="bugfix/"
MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="develop"
MANIFEST_CLI_GIT_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[RESEARCH] Release v{version} - {timestamp}"
MANIFEST_CLI_GIT_PUSH_STRATEGY="simple"
MANIFEST_CLI_GIT_PULL_STRATEGY="rebase"
MANIFEST_CLI_GIT_TIMEOUT=600
MANIFEST_CLI_GIT_RETRIES=5

# Documentation Configuration
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=200

# NTP Configuration (Critical for research timestamps)
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_SERVER2="time.apple.com"
MANIFEST_CLI_NTP_SERVER3="pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=15
MANIFEST_CLI_NTP_RETRIES=5
MANIFEST_CLI_NTP_VERIFY=true

# Debug Configuration (Research-friendly)
MANIFEST_CLI_DEBUG=true
MANIFEST_CLI_LOG_LEVEL="DEBUG"
MANIFEST_CLI_LOG_FILE="manifest-cli.log"

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🚀 Quick Start Templates

### Minimal Configuration
```bash
# Minimal setup for quick testing
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
```

### Production Configuration
```bash
# Production-ready setup
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_GIT_TAG_PREFIX="v"
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_TIMEOUT=10
MANIFEST_CLI_NTP_RETRIES=3
MANIFEST_CLI_DEBUG=false
```

### Development Configuration
```bash
# Development-friendly setup
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DEBUG=true
MANIFEST_CLI_INTERACTIVE_MODE=true
MANIFEST_CLI_AUTO_UPDATE=true
```

## 📋 Variable Reference

### Core Configuration
- `MANIFEST_CLI_VERSION_FORMAT` - Version format pattern
- `MANIFEST_CLI_VERSION_SEPARATOR` - Separator between version components
- `MANIFEST_CLI_VERSION_COMPONENTS` - Version component names
- `MANIFEST_CLI_VERSION_MAX_VALUES` - Maximum values for each component

### Git Configuration
- `MANIFEST_CLI_GIT_DEFAULT_BRANCH` - Default Git branch
- `MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX` - Feature branch prefix
- `MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX` - Hotfix branch prefix
- `MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX` - Release branch prefix
- `MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX` - Bugfix branch prefix
- `MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH` - Development branch name
- `MANIFEST_CLI_GIT_STAGING_BRANCH` - Staging branch name
- `MANIFEST_CLI_GIT_TAG_PREFIX` - Git tag prefix
- `MANIFEST_CLI_GIT_TAG_SUFFIX` - Git tag suffix
- `MANIFEST_CLI_GIT_COMMIT_TEMPLATE` - Commit message template
- `MANIFEST_CLI_GIT_PUSH_STRATEGY` - Git push strategy
- `MANIFEST_CLI_GIT_PULL_STRATEGY` - Git pull strategy
- `MANIFEST_CLI_GIT_TIMEOUT` - Git operation timeout
- `MANIFEST_CLI_GIT_RETRIES` - Git operation retry count

### Documentation Configuration
- `MANIFEST_CLI_DOCS_FOLDER` - Documentation folder
- `MANIFEST_CLI_DOCS_ARCHIVE_FOLDER` - Documentation archive folder
- `MANIFEST_CLI_DOCS_AUTO_GENERATE` - Auto-generate documentation
- `MANIFEST_CLI_DOCS_FILENAME_PATTERN` - Documentation filename pattern
- `MANIFEST_CLI_DOCS_HISTORICAL_LIMIT` - Historical documentation limit

### NTP Configuration
- `MANIFEST_CLI_NTP_SERVER1` - Primary NTP server
- `MANIFEST_CLI_NTP_SERVER2` - Secondary NTP server
- `MANIFEST_CLI_NTP_SERVER3` - Tertiary NTP server
- `MANIFEST_CLI_NTP_TIMEOUT` - NTP query timeout
- `MANIFEST_CLI_NTP_RETRIES` - NTP query retry count
- `MANIFEST_CLI_NTP_VERIFY` - Verify NTP timestamps

### System Configuration
- `MANIFEST_CLI_DEBUG` - Enable debug mode
- `MANIFEST_CLI_LOG_LEVEL` - Logging level
- `MANIFEST_CLI_LOG_FILE` - Log file path
- `MANIFEST_CLI_INTERACTIVE_MODE` - Enable interactive mode
- `MANIFEST_CLI_AUTO_UPDATE` - Enable auto-update
- `MANIFEST_CLI_UPDATE_COOLDOWN` - Update cooldown period
- `MANIFEST_CLI_BREW_OPTION` - Enable Homebrew integration
- `MANIFEST_CLI_BREW_INTERACTIVE` - Homebrew interactive mode

## 🎯 Best Practices

1. **Start Simple**: Begin with minimal configuration and add complexity as needed
2. **Environment-Specific**: Use different configurations for different environments
3. **Documentation**: Keep your configuration documented and version-controlled
4. **Testing**: Test your configuration in a safe environment before production
5. **Backup**: Always backup your configuration before making changes
6. **Validation**: Use `manifest config` to validate your configuration
7. **Incremental**: Make changes incrementally and test each change

## 🔧 Troubleshooting

### Common Issues
1. **Variable Not Found**: Ensure all variables are properly exported
2. **Invalid Format**: Check version format patterns and separators
3. **Git Errors**: Verify Git configuration and permissions
4. **NTP Timeouts**: Check network connectivity and NTP server availability
5. **Documentation Errors**: Ensure documentation paths are valid and writable

### Debug Commands
```bash
# Check current configuration
manifest config

# Validate configuration
manifest config --validate

# Test NTP connectivity
manifest ntp

# Check Git status
manifest git status

# View help
manifest --help
```

---

*This document is automatically generated and updated with the latest Manifest CLI variable naming conventions.*