# 🌟 Manifest CLI Configuration Examples

Real-world configuration examples for different organizations and use cases using the `MANIFEST_CLI_*` variable naming convention.

## 🚀 Quick Start Templates

### Minimal Setup
```bash
# Essential configuration for any project
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
```

### Development Setup
```bash
# Development-friendly configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_DEBUG=true
MANIFEST_CLI_INTERACTIVE_MODE=true
MANIFEST_CLI_AUTO_UPDATE=true
```

### Production Setup
```bash
# Production-ready configuration
MANIFEST_CLI_VERSION_FORMAT="XX.XX.XX"
MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
MANIFEST_CLI_DOCS_FOLDER="docs"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="docs/zArchive"
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_TIMEOUT=10
MANIFEST_CLI_NTP_RETRIES=3
MANIFEST_CLI_DEBUG=false
```

## 🏢 Enterprise Configurations

### 4-Digit Versioning (Large Enterprise)
```bash
# Enterprise with strict version control
MANIFEST_CLI_VERSION_FORMAT="XXXX.XXXX.XXXX"
MANIFEST_CLI_VERSION_MAX_VALUES="9999,9999,9999"
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[RELEASE] v{version} - {timestamp}"
MANIFEST_CLI_GIT_TIMEOUT=600
MANIFEST_CLI_GIT_RETRIES=5
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=50
# Example versions: 0001.0001.0001, 0001.0002.0000, 0002.0000.0000
```

### Date-Based Versioning (Manufacturing/Compliance)
```bash
# Manufacturing with date-based versioning
MANIFEST_CLI_VERSION_FORMAT="YYYY.MM.DD"
MANIFEST_CLI_VERSION_COMPONENTS="year,month,day"
MANIFEST_CLI_VERSION_MAX_VALUES="9999,12,31"
MANIFEST_CLI_GIT_TAG_PREFIX="release-"
MANIFEST_CLI_GIT_TAG_SUFFIX="-stable"
MANIFEST_CLI_GIT_DEFAULT_BRANCH="production"
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[MANUFACTURING] Release {version} - {timestamp}"
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_VERIFY=true
# Example versions: 2024.03.15, 2024.03.16, 2024.04.01
```

## 🔒 High-Security Configurations

### Healthcare/Medical (Compliance-Focused)
```bash
# Healthcare with strict compliance requirements
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[HEALTHCARE] Release v{version} - {timestamp}"
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=200
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_VERIFY=true
MANIFEST_CLI_DEBUG=true
MANIFEST_CLI_LOG_LEVEL="INFO"
```

### Financial Services (High-Security)
```bash
# Financial institution with high-security requirements
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[FINANCIAL] Release v{version} - {timestamp}"
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=500
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_TIMEOUT=20
MANIFEST_CLI_NTP_RETRIES=10
MANIFEST_CLI_NTP_VERIFY=true
MANIFEST_CLI_DEBUG=false
MANIFEST_CLI_LOG_LEVEL="WARN"
MANIFEST_CLI_INTERACTIVE_MODE=false
```

## 🎯 Specialized Configurations

### Open Source Project (Community-Driven)
```bash
# Open source with community contributions
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
MANIFEST_CLI_INTERACTIVE_MODE=true
MANIFEST_CLI_DEBUG=false
```

### Gaming/Software (Alpha/Beta/Release)
```bash
# Game development with alpha/beta cycles
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[GAME] v{version} - {timestamp}"
MANIFEST_CLI_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_CLI_DOCS_AUTO_GENERATE=true
# Example versions: 1.0.0-alpha, 1.0.0-beta, 1.0.0
```

### Research/Academic (Publication-Focused)
```bash
# Research institution with publication focus
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="[RESEARCH] Release v{version} - {timestamp}"
MANIFEST_CLI_DOCS_FOLDER="documentation"
MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/archive"
MANIFEST_CLI_DOCS_HISTORICAL_LIMIT=200
MANIFEST_CLI_NTP_SERVER1="time.nist.gov"
MANIFEST_CLI_NTP_VERIFY=true
MANIFEST_CLI_DEBUG=true
MANIFEST_CLI_LOG_LEVEL="DEBUG"
```

## 📋 Key Variables Reference

### Most Commonly Customized
- `MANIFEST_CLI_VERSION_FORMAT` - Version format pattern (XX.XX.XX, XXXX.XXXX.XXXX, YYYY.MM.DD)
- `MANIFEST_CLI_GIT_DEFAULT_BRANCH` - Default Git branch (main, develop, production)
- `MANIFEST_CLI_GIT_COMMIT_TEMPLATE` - Commit message template
- `MANIFEST_CLI_DOCS_FOLDER` - Documentation folder (docs, documentation)
- `MANIFEST_CLI_DOCS_ARCHIVE_FOLDER` - Archive folder location

### Security & Compliance
- `MANIFEST_CLI_NTP_SERVER1` - Primary NTP server (time.nist.gov for compliance)
- `MANIFEST_CLI_NTP_VERIFY` - Verify NTP timestamps (true for compliance)
- `MANIFEST_CLI_DEBUG` - Debug mode (false for production)
- `MANIFEST_CLI_LOG_LEVEL` - Logging level (WARN for production, DEBUG for development)

### Development & Workflow
- `MANIFEST_CLI_INTERACTIVE_MODE` - Interactive prompts (true for development)
- `MANIFEST_CLI_AUTO_UPDATE` - Auto-update (true for development)
- `MANIFEST_CLI_DOCS_AUTO_GENERATE` - Auto-generate docs (true for most projects)

## 🎯 Best Practices

1. **Start Simple**: Use minimal configuration and add complexity as needed
2. **Environment-Specific**: Different configs for dev/staging/production
3. **Compliance First**: Use NIST time servers and verification for regulated industries
4. **Documentation**: Keep configs documented and version-controlled
5. **Testing**: Test configurations in safe environments first

## 🔧 Quick Commands

```bash
# Check current configuration
manifest config

# Test NTP connectivity
manifest ntp

# Validate setup
manifest test

# Get help
manifest --help
```

---

*This document provides focused examples for common use cases. For complete variable reference, see `env.manifest.global.example`.*