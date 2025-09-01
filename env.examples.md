# 🌟 Manifest CLI Environment Configuration Examples

This document provides real-world examples of how to configure Manifest CLI for different organizations, versioning schemes, and workflows.

## 🏢 Enterprise Organization (4-Digit Versioning)

**Use Case**: Large enterprise with strict version control requirements

```bash
# =============================================================================
# Enterprise Configuration - 4-Digit Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_VERSION_FORMAT="XXXX.XXXX.XXXX"
MANIFEST_VERSION_SEPARATOR="."
MANIFEST_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_VERSION_MAX_VALUES="9999,9999,9999"
MANIFEST_GIT_TAG_PREFIX="v"
MANIFEST_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_DEFAULT_BRANCH="main"
MANIFEST_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_DEVELOPMENT_BRANCH="develop"
MANIFEST_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_GIT_COMMIT_TEMPLATE="[RELEASE] v{version} - {timestamp}"
MANIFEST_GIT_PRIMARY_REMOTE="origin"
MANIFEST_GIT_PUSH_STRATEGY="simple"
MANIFEST_GIT_PULL_STRATEGY="rebase"

# Documentation Configuration
MANIFEST_DOCS_FILENAME_PATTERN="RELEASE_{type}_{version}.md"
MANIFEST_DOCS_HISTORICAL_LIMIT=50

# Example versions: 0001.0001.0001, 0001.0002.0000, 0002.0000.0000
```

## 🚀 Startup Company (Semantic Versioning)

**Use Case**: Fast-moving startup with standard semantic versioning

```bash
# =============================================================================
# Startup Configuration - Standard Semantic Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_VERSION_FORMAT="X.X.X"
MANIFEST_VERSION_SEPARATOR="."
MANIFEST_VERSION_COMPONENTS="major,minor,patch"
MANIFEST_VERSION_MAX_VALUES="0,0,0"
MANIFEST_GIT_TAG_PREFIX="v"
MANIFEST_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_DEFAULT_BRANCH="main"
MANIFEST_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_DEVELOPMENT_BRANCH="develop"

# Git Configuration
MANIFEST_GIT_COMMIT_TEMPLATE="🚀 Release v{version} - {timestamp}"
MANIFEST_GIT_PRIMARY_REMOTE="origin"
MANIFEST_GIT_PUSH_STRATEGY="simple"
MANIFEST_GIT_PULL_STRATEGY="rebase"

# Documentation Configuration
MANIFEST_DOCS_FILENAME_PATTERN="{type}_v{version}.md"
MANIFEST_DOCS_HISTORICAL_LIMIT=20

# Example versions: 1.0.0, 1.1.0, 2.0.0
```

## 🏭 Manufacturing Company (Date-Based Versioning)

**Use Case**: Manufacturing company that releases based on production schedules

```bash
# =============================================================================
# Manufacturing Configuration - Date-Based Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_VERSION_FORMAT="YYYY.MM.DD"
MANIFEST_VERSION_SEPARATOR="."
MANIFEST_VERSION_COMPONENTS="year,month,day"
MANIFEST_VERSION_MAX_VALUES="0,0,0"
MANIFEST_GIT_TAG_PREFIX="PROD-"
MANIFEST_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_DEFAULT_BRANCH="production"
MANIFEST_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_DEVELOPMENT_BRANCH="development"
MANIFEST_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_GIT_COMMIT_TEMPLATE="[PRODUCTION] {version} - {timestamp}"
MANIFEST_GIT_PRIMARY_REMOTE="origin"
MANIFEST_GIT_PUSH_STRATEGY="simple"
MANIFEST_GIT_PULL_STRATEGY="merge"

# Documentation Configuration
MANIFEST_DOCS_FILENAME_PATTERN="{type}_{version}.md"
MANIFEST_DOCS_HISTORICAL_LIMIT=100

# Example versions: 2024.01.15, 2024.01.16, 2024.02.01
```

## 🏥 Healthcare Organization (Compliance-Focused)

**Use Case**: Healthcare company requiring strict audit trails and compliance

```bash
# =============================================================================
# Healthcare Configuration - Compliance-Focused
# =============================================================================

# Versioning Configuration
MANIFEST_VERSION_FORMAT="XX.XX.XX.XX"
MANIFEST_VERSION_SEPARATOR="."
MANIFEST_VERSION_COMPONENTS="major,minor,patch,build"
MANIFEST_VERSION_MAX_VALUES="99,99,99,999"
MANIFEST_GIT_TAG_PREFIX="HC-"
MANIFEST_GIT_TAG_SUFFIX="-COMPLIANT"

# Branch Naming Configuration
MANIFEST_DEFAULT_BRANCH="main"
MANIFEST_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_DEVELOPMENT_BRANCH="development"
MANIFEST_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_GIT_COMMIT_TEMPLATE="[COMPLIANCE] v{version} - {timestamp} - {branch}"
MANIFEST_GIT_PRIMARY_REMOTE="origin"
MANIFEST_GIT_ADDITIONAL_REMOTES="audit,backup"
MANIFEST_GIT_PUSH_STRATEGY="matching"
MANIFEST_GIT_PULL_STRATEGY="rebase"

# NTP Configuration (Multiple trusted sources)
MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org,time.apple.com"
MANIFEST_NTP_TIMEOUT=10
MANIFEST_NTP_RETRIES=5
MANIFEST_NTP_VERIFY=true

# Documentation Configuration
MANIFEST_DOCS_FILENAME_PATTERN="{type}_v{version}_COMPLIANT.md"
MANIFEST_DOCS_HISTORICAL_LIMIT=200

# Example versions: 01.02.03.001, 01.02.04.000, 02.00.00.000
```

## 🎮 Gaming Studio (Build Number Versioning)

**Use Case**: Game development studio with frequent builds and releases

```bash
# =============================================================================
# Gaming Studio Configuration - Build Number Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_VERSION_FORMAT="X.X.X.X"
MANIFEST_VERSION_SEPARATOR="."
MANIFEST_VERSION_COMPONENTS="major,minor,patch,revision"
MANIFEST_VERSION_MAX_VALUES="0,0,0,0"
MANIFEST_GIT_TAG_PREFIX="BUILD-"
MANIFEST_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_DEFAULT_BRANCH="main"
MANIFEST_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_DEVELOPMENT_BRANCH="develop"
MANIFEST_STAGING_BRANCH="staging"

# Git Configuration
MANIFEST_GIT_COMMIT_TEMPLATE="🎮 BUILD v{version} - {timestamp}"
MANIFEST_GIT_PRIMARY_REMOTE="origin"
MANIFEST_GIT_PUSH_STRATEGY="simple"
MANIFEST_GIT_PULL_STRATEGY="rebase"

# Documentation Configuration
MANIFEST_DOCS_FILENAME_PATTERN="{type}_BUILD_{version}.md"
MANIFEST_DOCS_HISTORICAL_LIMIT=30

# Example versions: 1.0.0.1, 1.0.0.2, 1.0.1.0
```

## 🔬 Research Institution (Academic Versioning)

**Use Case**: Academic research institution with publication-based releases

```bash
# =============================================================================
# Research Configuration - Academic Versioning
# =============================================================================

# Versioning Configuration
MANIFEST_VERSION_FORMAT="YYYY.MM.XX"
MANIFEST_VERSION_SEPARATOR="."
MANIFEST_VERSION_COMPONENTS="year,month,publication"
MANIFEST_VERSION_MAX_VALUES="0,0,99"
MANIFEST_GIT_TAG_PREFIX="PUB-"
MANIFEST_GIT_TAG_SUFFIX=""

# Branch Naming Configuration
MANIFEST_DEFAULT_BRANCH="main"
MANIFEST_FEATURE_BRANCH_PREFIX="research/"
MANIFEST_HOTFIX_BRANCH_PREFIX="correction/"
MANIFEST_RELEASE_BRANCH_PREFIX="publication/"
MANIFEST_DEVELOPMENT_BRANCH="development"
MANIFEST_STAGING_BRANCH="review"

# Git Configuration
MANIFEST_GIT_COMMIT_TEMPLATE="[PUBLICATION] {version} - {timestamp} - {branch}"
MANIFEST_GIT_PRIMARY_REMOTE="origin"
MANIFEST_GIT_ADDITIONAL_REMOTES="archive,peer-review"
MANIFEST_GIT_PUSH_STRATEGY="simple"
MANIFEST_GIT_PULL_STRATEGY="rebase"

# Documentation Configuration
MANIFEST_DOCS_FILENAME_PATTERN="{type}_PUB_{version}.md"
MANIFEST_DOCS_HISTORICAL_LIMIT=1000

# Example versions: 2024.01.01, 2024.01.02, 2024.02.01
```

## 🚀 Quick Start Templates

### Minimal Configuration
```bash
# Copy and customize for immediate use
cp env.example .env

# Essential variables only
MANIFEST_DEFAULT_BRANCH="main"
MANIFEST_VERSION_FORMAT="X.X.X"
MANIFEST_GIT_TAG_PREFIX="v"
MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com"
MANIFEST_BREW_OPTION=enabled
```

### Development Team Configuration
```bash
# For development teams
MANIFEST_DEFAULT_BRANCH="develop"
MANIFEST_FEATURE_BRANCH_PREFIX="feature/"
MANIFEST_HOTFIX_BRANCH_PREFIX="hotfix/"
MANIFEST_RELEASE_BRANCH_PREFIX="release/"
MANIFEST_DEVELOPMENT_BRANCH="main"
MANIFEST_STAGING_BRANCH="staging"
MANIFEST_GIT_PULL_STRATEGY="rebase"
MANIFEST_DEBUG=true
MANIFEST_VERBOSE=true
```

### Production Environment Configuration
```bash
# For production environments
MANIFEST_DEFAULT_BRANCH="main"
MANIFEST_GIT_PUSH_STRATEGY="simple"
MANIFEST_GIT_PULL_STRATEGY="fast-forward-only"
MANIFEST_DEBUG=false
MANIFEST_VERBOSE=false
MANIFEST_INTERACTIVE=false
MANIFEST_DOCS_AUTO_GENERATE=true
```

## 🔧 Configuration Validation

After creating your `.env` file, validate the configuration:

```bash
# Show current configuration
manifest config

# Test version parsing
manifest test versions

# Validate NTP configuration
manifest ntp
```

## 📚 Advanced Configuration

### Custom Version Parsing
```bash
# Custom regex for version parsing
MANIFEST_VERSION_REGEX="^v?([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:-([0-9A-Za-z-]+))?$"

# Custom validation rules
MANIFEST_VERSION_VALIDATION="major > 0, minor >= 0, patch >= 0"
```

### Environment-Specific Overrides
```bash
# .env.development
MANIFEST_DEBUG=true
MANIFEST_VERBOSE=true
MANIFEST_DEFAULT_BRANCH="develop"

# .env.production
MANIFEST_DEBUG=false
MANIFEST_VERBOSE=false
MANIFEST_DEFAULT_BRANCH="main"
```

### Multi-Repository Configuration
```bash
# Primary repository
MANIFEST_GIT_PRIMARY_REMOTE="origin"

# Additional repositories
MANIFEST_GIT_ADDITIONAL_REMOTES="upstream,staging,archive"

# Different strategies for different remotes
MANIFEST_GIT_PUSH_STRATEGY="simple"
MANIFEST_GIT_PULL_STRATEGY="rebase"
```

## 🎯 Best Practices

1. **Start Simple**: Begin with basic configuration and add complexity as needed
2. **Document Changes**: Keep track of configuration changes in your project
3. **Test Thoroughly**: Validate configuration before using in production
4. **Version Control**: Consider versioning your configuration files
5. **Team Alignment**: Ensure all team members understand the configuration
6. **Regular Review**: Periodically review and update configuration

## 🚨 Common Pitfalls

1. **Missing Separators**: Ensure version format contains the specified separator
2. **Invalid Patterns**: Test version patterns with your actual version numbers
3. **Branch Conflicts**: Avoid conflicts between configured and actual branch names
4. **Permission Issues**: Ensure proper file permissions for `.env` files
5. **Environment Conflicts**: Be careful with environment-specific overrides

## 🔍 Troubleshooting

### Configuration Not Loading
```bash
# Check file permissions
ls -la .env*

# Verify file syntax
grep -v "^#" .env | grep -v "^$"

# Test configuration loading
source .env && echo "Configuration loaded"
```

### Version Parsing Issues
```bash
# Test version format
echo "1.2.3" | cut -d"." -f1

# Validate separator
echo "$MANIFEST_VERSION_SEPARATOR"

# Check format pattern
echo "$MANIFEST_VERSION_FORMAT"
```

### Branch Name Conflicts
```bash
# List actual branches
git branch -a

# Check configured default
echo "$MANIFEST_DEFAULT_BRANCH"

# Verify remote branches
git remote show origin
```

---

*These examples demonstrate the flexibility of Manifest CLI's configuration system. Customize them for your specific needs and requirements.*
