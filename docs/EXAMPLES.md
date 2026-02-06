# 🌟 Manifest CLI Examples

**A powerful CLI tool for versioning, AI documenting, and repository operations.**

This document provides real-world examples and use cases for Manifest CLI, demonstrating how to integrate it into various workflows and environments.

## 🚀 Basic Examples

## Simple Patch Release

The most common use case - releasing a bug fix or minor improvement:

```bash
# 1. Make your changes
git add .
git commit -m "Fix: resolve authentication issue with SSH keys"

# 2. Test everything works
manifest test

# 3. Release with patch version bump
manifest go

# 4. Verify the release
git log --oneline -3
git tag --list -3
```

**What happens:**
- Version: 1.0.0 → 1.0.1
- Documentation: Auto-generated release notes and changelog
- Git: Committed, tagged, and pushed to remote
- Security: Input validation and path security checks
- NTP: Trusted timestamp for compliance

## Feature Release

When adding new functionality that's backward compatible:

```bash
# 1. Complete feature development

git checkout -b feature/user-authentication
# ... implement authentication system ...

git add .

git commit -m "Feature: implement user authentication system"

# 2. Merge to main

git checkout main

git merge feature/user-authentication

# 3. Release with minor version bump

manifest go minor

# 4. Clean up feature branch

git branch -d feature/user-authentication

```

**What happens:**

- Version: 1.0.0 → 1.1.0

- Documentation: Enhanced release notes highlighting new features

- Git: Complete workflow with proper tagging

## Major Release

For breaking changes or significant rewrites:

```bash
# 1. Prepare for major release

manifest test all

# 2. Review breaking changes

git log --oneline $(git describe --tags --abbrev=0)..HEAD

# 3. Major version bump

manifest go major

# 4. Verify release documentation

manifest docs

cat docs/RELEASE_v$(cat VERSION).md

```

**What happens:**

- Version: 1.0.0 → 2.0.0

- Documentation: Comprehensive release notes with breaking changes

- Git: Full workflow execution

## 🔄 Workflow Examples

## Daily Development Workflow

A typical day in the life of a developer using Manifest CLI:

```bash
# Morning: Start development

git checkout main

git pull origin main

manifest sync

# Development: Make changes

git checkout -b feature/daily-improvement
# ... code, test, iterate ...

git add .

git commit -m "Improve: enhance error handling in CLI"

# Afternoon: Test and release

manifest test all

manifest go

# Evening: Verify and clean up

git log --oneline -5

git tag --list -5

git branch -d feature/daily-improvement

```

## Team Collaboration Workflow

Coordinating releases across multiple developers:

```bash
# 1. Team lead creates release branch

git checkout -b release/v1.2.0

manifest test all

# 2. Developers merge their features

git merge feature/user-dashboard

git merge feature/api-improvements

git merge feature/bug-fixes

# 3. Final testing

manifest test all

# 4. Release

manifest go minor

# 5. Clean up

git checkout main

git branch -d release/v1.2.0

```

## CI/CD Integration

Automating releases in continuous integration:

```yaml
# .github/workflows/release.yml

name: Release

on:

  push:

    tags:

      - 'v*'

jobs:

  release:

    runs-on: ubuntu-latest

    steps:

      - uses: actions/checkout@v3

      - name: Install Manifest CLI

        run: |

          curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash

      - name: Run tests

        run: manifest test all

      - name: Generate documentation

        run: manifest docs

      - name: Create release

        run: |

          git config --local user.email "action@github.com"

          git config --local user.name "GitHub Action"

          manifest go patch

```

## 🏢 Enterprise Examples

## Compliance and Audit Workflow

For organizations requiring strict compliance:

```bash
# 1. Get trusted timestamp for compliance

manifest ntp --verify

# 2. Run compliance checks

manifest test all

# 3. Generate audit trail

manifest go --interactive

# 4. Verify audit trail

echo "Release: v$(cat VERSION)"

echo "Timestamp: $(manifest ntp --format='%Y-%m-%d %H:%M:%S UTC')"

echo "NTP Source: $(env | grep MANIFEST_CLI_NTP_SERVER)"

```

## Multi-Environment Deployment

Managing releases across different environments:

```bash
#!/bin/bash
# deploy.sh - Multi-environment deployment script

ENVIRONMENT=$1

VERSION=$(cat VERSION)

case $ENVIRONMENT in

  "staging")

    echo "🚀 Deploying v$VERSION to staging..."

    manifest test all

    manifest go patch

    # Deploy to staging

    ;;

  "production")

    echo "🚀 Deploying v$VERSION to production..."

    manifest test all

    manifest go minor

    # Deploy to production

    ;;

  *)

    echo "❌ Unknown environment: $ENVIRONMENT"

    exit 1

    ;;

esac

echo "✅ Deployment to $ENVIRONMENT completed"

```

## Team Standardization

Standardizing release processes across teams:

```bash
#!/bin/bash
# team-release.sh - Standardized team release script

TEAM_NAME=$1

RELEASE_TYPE=${2:-patch}

echo "🏢 $TEAM_NAME Release Process"

echo "================================"

# 1. Pre-release checklist

echo "📋 Pre-release checklist..."

manifest test all

# 2. Get team approval

read -p "Does the team approve this release? (y/N): " approval

if [[ $approval != "y" ]]; then

    echo "❌ Release cancelled by team"

    exit 1

fi

# 3. Execute release

echo "🚀 Executing release..."

manifest go $RELEASE_TYPE

# 4. Team notification

echo "📢 Notifying team..."
# Send notification to team channel

echo "✅ Release completed successfully"

```

## 🧪 Testing Examples

## Comprehensive Testing Workflow

Thorough testing before release:

```bash
#!/bin/bash
# test-workflow.sh - Comprehensive testing script

echo "🧪 Manifest CLI Testing Workflow"
echo "================================="

# 1. Basic functionality tests
echo "📋 Testing basic functionality..."
manifest test

# 2. Component-specific tests
echo "📋 Testing NTP functionality..."
manifest test ntp

echo "📋 Testing Git operations..."
manifest test git

echo "📋 Testing documentation generation..."
manifest test docs

# 3. Cross-shell compatibility tests
echo "📋 Testing cross-shell compatibility..."
manifest test zsh
manifest test bash32
manifest test bash4

# 4. Security testing
echo "📋 Testing security features..."
manifest security

# 5. Integration tests
echo "📋 Testing complete workflow..."
manifest go --dry-run

# 6. Performance tests
echo "📋 Testing performance..."
time manifest ntp
time manifest test all

echo "✅ All tests completed successfully"
```

## Cross-Shell Compatibility Testing

Test your CLI across different shell environments:

```bash
#!/bin/bash
# cross-shell-test.sh - Cross-shell compatibility testing

echo "🐚 Cross-Shell Compatibility Testing"
echo "===================================="

# Test Zsh 5.9 compatibility
echo "📋 Testing Zsh 5.9 compatibility..."
if command -v zsh &> /dev/null; then
    manifest test zsh
    echo "✅ Zsh 5.9 tests completed"
else
    echo "⚠️  Zsh not available, skipping Zsh tests"
fi

# Test Bash 3.2 compatibility
echo "📋 Testing Bash 3.2 compatibility..."
manifest test bash32

# Test Bash 4+ compatibility
echo "📋 Testing Bash 4+ compatibility..."
manifest test bash4

# Auto-detect current shell
echo "📋 Testing current shell compatibility..."
manifest test bash

echo "✅ Cross-shell compatibility testing completed"
```

## Security Testing Examples

Comprehensive security validation:

```bash
#!/bin/bash
# security-test.sh - Security testing examples

echo "🔒 Security Testing Examples"
echo "============================"

# 1. Full security audit
echo "📋 Running full security audit..."
manifest security

# 2. Vulnerability scanning
echo "📋 Scanning for vulnerabilities..."
manifest security --vulnerabilities

# 3. Privacy protection scan
echo "📋 Scanning for privacy-sensitive information..."
manifest security --privacy

# 4. Path validation
echo "📋 Validating file paths..."
manifest security --paths

# 5. Input validation
echo "📋 Validating input parameters..."
manifest security --input

# 6. Network security check
echo "📋 Checking network security..."
manifest security --network

echo "✅ Security testing completed"
```

## Cross-Platform Testing

Testing across different operating systems:

```bash
#!/bin/bash
# cross-platform-test.sh - Test across platforms

echo "🖥️  Cross-Platform Testing"

echo "============================"

# Test on current platform

echo "📋 Testing on $(uname -s)..."

manifest test all

# Test with Docker (Linux)

if command -v docker &> /dev/null; then

    echo "📋 Testing on Linux (Docker)..."

    docker run -it --rm -v $(pwd):/app ubuntu:20.04 bash -c "

        cd /app

        apt-get update && apt-get install -y git nodejs npm curl

        ./install-cli.sh

        manifest test all

    "

fi

# Test with WSL (Windows)

if command -v wsl &> /dev/null; then

    echo "📋 Testing on Windows (WSL)..."

    wsl bash -c "

        cd $(pwd)

        manifest test all

    "

fi

echo "✅ Cross-platform testing completed"

```

## 🔧 Configuration Examples

## Environment Variable Configuration

Setting up standardized environment variables with the new `MANIFEST_CLI_` prefix:

```bash
#!/bin/bash
# setup-env-vars.sh - Environment variable configuration

echo "🔧 Environment Variable Configuration"
echo "===================================="

# Core configuration
export MANIFEST_CLI_DEBUG=false
export MANIFEST_CLI_VERBOSE=true
export MANIFEST_CLI_LOG_LEVEL="INFO"
export MANIFEST_CLI_INTERACTIVE=false

# NTP configuration
export MANIFEST_CLI_NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org"
export MANIFEST_CLI_NTP_TIMEOUT=5
export MANIFEST_CLI_NTP_RETRIES=3
export MANIFEST_CLI_NTP_VERIFY=true

# Git configuration with retry logic
export MANIFEST_CLI_GIT_TIMEOUT=300
export MANIFEST_CLI_GIT_RETRIES=3
export MANIFEST_CLI_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# Documentation configuration
export MANIFEST_CLI_DOCS_TEMPLATE_DIR="./templates"
export MANIFEST_CLI_DOCS_OUTPUT_DIR="./docs"
export MANIFEST_CLI_DOCS_AUTO_GENERATE=true

# Homebrew configuration
export MANIFEST_CLI_BREW_OPTION="enabled"
export MANIFEST_CLI_BREW_INTERACTIVE="no"
export MANIFEST_CLI_TAP_REPO="https://github.com/fidenceio/homebrew-manifest.git"

# Cloud configuration
export MANIFEST_CLI_CLOUD_API_KEY="your-api-key-here"
export MANIFEST_CLI_CLOUD_ENDPOINT="https://api.manifest.cloud"
export MANIFEST_CLI_CLOUD_SKIP=false
export MANIFEST_CLI_OFFLINE_MODE=false

echo "✅ Environment variables configured"
```

## Custom NTP Configuration

Setting up custom NTP servers for enterprise environments:

```bash
#!/bin/bash
# setup-enterprise-ntp.sh - Enterprise NTP configuration

echo "🏢 Enterprise NTP Configuration"
echo "================================"

# Set enterprise NTP servers
export MANIFEST_CLI_NTP_SERVERS="ntp.company.com,time.company.com,pool.ntp.org"

# Set longer timeouts for corporate networks
export MANIFEST_CLI_NTP_TIMEOUT=10
export MANIFEST_CLI_NTP_RETRIES=5

# Test configuration
echo "📋 Testing NTP configuration..."
manifest ntp --verify

# Verify with custom servers
echo "📋 Testing custom servers..."
manifest ntp --servers="ntp.company.com,time.company.com"

echo "✅ Enterprise NTP configuration completed"
```

## Git Retry Configuration

Setting up robust git operations for unreliable networks:

```bash
#!/bin/bash
# setup-git-retry.sh - Git retry configuration for unreliable networks

echo "🔄 Git Retry Configuration"
echo "=========================="

# Configure git retry settings for unreliable networks
export MANIFEST_CLI_GIT_TIMEOUT="600"    # 10 minutes timeout
export MANIFEST_CLI_GIT_RETRIES="5"      # 5 retry attempts

# Test git operations
echo "📋 Testing git operations..."
manifest sync

# Test with different retry settings
echo "📋 Testing with aggressive retry settings..."
export MANIFEST_CLI_GIT_TIMEOUT="300"    # 5 minutes timeout
export MANIFEST_CLI_GIT_RETRIES="10"     # 10 retry attempts

manifest test git

echo "✅ Git retry configuration completed"
```

## Auto-Update Configuration

Setting up automatic updates for different environments:

```bash
#!/bin/bash
# setup-auto-update.sh - Auto-update configuration

echo "🔄 Auto-Update Configuration"
echo "============================"

# Development environment - frequent updates
echo "📋 Setting up development environment..."
export MANIFEST_CLI_AUTO_UPDATE="true"
export MANIFEST_CLI_UPDATE_COOLDOWN="5"  # Check every 5 minutes

# Production environment - conservative updates
echo "📋 Setting up production environment..."
export MANIFEST_CLI_AUTO_UPDATE="true"
export MANIFEST_CLI_UPDATE_COOLDOWN="1440"  # Check once per day

# Disable auto-update for CI/CD
echo "📋 Setting up CI/CD environment..."
export MANIFEST_CLI_AUTO_UPDATE="false"

# Test update functionality
echo "📋 Testing update functionality..."
manifest update --check

echo "✅ Auto-update configuration completed"
```

## Custom Documentation Templates

Creating organization-specific documentation:

```bash
#!/bin/bash
# setup-custom-templates.sh - Custom documentation templates

echo "📚 Custom Documentation Templates"

echo "=================================="

# Create templates directory

mkdir -p templates

# Company-specific release template

cat > templates/release.md << 'EOF'
# Release v{version}

**Company:** Your Company Name

**Release Date:** {timestamp}

**Release Manager:** {author}

**Approved By:** {approver}

## 🎯 Release Summary

{summary}

## 🆕 New Features

{new_features}

## 🔧 Improvements

{improvements}

## 🐛 Bug Fixes

{bug_fixes}

## ⚠️ Breaking Changes

{breaking_changes}

## 🚀 Deployment Instructions

{deployment}

## 📋 Testing Results

{testing}

## 🔍 Rollback Plan

{rollback}

---

*Generated by Manifest CLI v{version}*

EOF

# Company-specific changelog template

cat > templates/changelog.md << 'EOF'
# Changelog v{version}

**Release Date:** {timestamp}

**Company:** Your Company Name

## 🆕 Features Added

{features_added}

## 🔧 Improvements Made

{improvements_made}

## 🐛 Bugs Fixed

{bugs_fixed}

## ⚠️ Breaking Changes

{breaking_changes}

## 📊 Technical Details

- **Version:** {version}

- **Release Date:** {timestamp}

- **Generated:** {generated_timestamp}

- **Build:** {build_number}

---

*Generated by Manifest CLI v{version}*

EOF

echo "✅ Custom templates created successfully"

```

## Environment-Specific Configuration

Managing different environments:

```bash
#!/bin/bash
# setup-environments.sh - Environment-specific configuration

ENVIRONMENT=$1

case $ENVIRONMENT in

  "development")

    echo "🔧 Setting up development environment..."

    export MANIFEST_CLI_DEBUG=true

    export MANIFEST_CLI_VERBOSE=true

    export MANIFEST_CLI_LOG_LEVEL="DEBUG"

    export MANIFEST_CLI_INTERACTIVE=true

    ;;

  "staging")

    echo "🔧 Setting up staging environment..."

    export MANIFEST_CLI_DEBUG=false

    export MANIFEST_CLI_VERBOSE=true

    export MANIFEST_CLI_LOG_LEVEL="INFO"

    export MANIFEST_CLI_INTERACTIVE=false

    ;;

  "production")

    echo "🔧 Setting up production environment..."

    export MANIFEST_CLI_DEBUG=false

    export MANIFEST_CLI_VERBOSE=false

    export MANIFEST_CLI_LOG_LEVEL="WARN"

    export MANIFEST_CLI_INTERACTIVE=false

    export MANIFEST_CLI_BREW_OPTION=enabled

    ;;

  *)

    echo "❌ Unknown environment: $ENVIRONMENT"

    exit 1

    ;;

esac

# Create environment-specific config

cat > .manifestrc << EOF
# Environment: $ENVIRONMENT

NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org"

COMMIT_TEMPLATE="Release v{version} - {timestamp} [$ENVIRONMENT]"

DOCS_TEMPLATE_DIR="./templates"

DEBUG=$MANIFEST_CLI_DEBUG

INTERACTIVE=$MANIFEST_CLI_INTERACTIVE

VERBOSE=$MANIFEST_CLI_VERBOSE

LOG_LEVEL="$MANIFEST_CLI_LOG_LEVEL"

BREW_OPTION=$MANIFEST_CLI_BREW_OPTION

EOF

echo "✅ $ENVIRONMENT environment configured"

```

## 🚀 Advanced Examples

## Automated Release Pipeline

Complete CI/CD pipeline with Manifest CLI:

```yaml
# .github/workflows/automated-release.yml

name: Automated Release Pipeline

on:

  push:

    branches: [main]

  pull_request:

    branches: [main]

jobs:

  test:

    runs-on: ubuntu-latest

    steps:

      - uses: actions/checkout@v3

      - run: |

          curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash

      - run: manifest test all

  release:

    needs: test

    runs-on: ubuntu-latest

    if: github.ref == 'refs/heads/main'

    steps:

      - uses: actions/checkout@v3

        with:

          token: ${{ secrets.GITHUB_TOKEN }}

      - run: |

          curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash

      - run: |

          git config --local user.email "action@github.com"

          git config --local user.name "GitHub Action"

      - run: manifest go patch

      - run: manifest docs

```

## Multi-Repository Management

Managing releases across multiple repositories:

```bash
#!/bin/bash
# multi-repo-release.sh - Release across multiple repositories

echo "📚 Multi-Repository Release"

echo "============================"

REPOS=(

    "frontend-app"

    "backend-api"

    "mobile-app"

    "shared-lib"

)

VERSION_TYPE=${1:-patch}

for repo in "${REPOS[@]}"; do

    echo "📋 Processing repository: $repo"

    if [ -d "$repo" ]; then

        cd "$repo"

        # Check if it's a Git repository

        if [ -d ".git" ]; then

            echo "   🔄 Updating repository..."

            git pull origin main

            echo "   🧪 Running tests..."

            if manifest test all; then

                echo "   🚀 Releasing..."

                manifest go $VERSION_TYPE

                echo "   ✅ Release completed"

            else

                echo "   ❌ Tests failed, skipping release"

            fi

        else

            echo "   ⚠️  Not a Git repository, skipping"

        fi

        cd ..

    else

        echo "   ⚠️  Repository not found: $repo"

    fi

    echo ""

done

echo "🎉 Multi-repository release completed"

```

## Custom Release Workflows

Creating organization-specific release processes:

```bash
#!/bin/bash
# custom-release-workflow.sh - Custom release workflow

echo "🎯 Custom Release Workflow"

echo "=========================="

RELEASE_TYPE=${1:-patch}

RELEASE_NOTES=${2:-""}

# 1. Pre-release validation

echo "📋 Pre-release validation..."

manifest test all

# 2. Security scan (if available)

if command -v security-scan &> /dev/null; then

    echo "🔒 Running security scan..."

    security-scan

fi

# 3. Performance testing (if available)

if command -v performance-test &> /dev/null; then

    echo "⚡ Running performance tests..."

    performance-test

fi

# 4. Custom approval process

read -p "Enter release approval code: " approval_code

if [[ "$approval_code" != "RELEASE2024" ]]; then

    echo "❌ Invalid approval code"

    exit 1

fi

# 5. Execute release

echo "🚀 Executing release..."

manifest go $RELEASE_TYPE

# 6. Post-release tasks

echo "📋 Post-release tasks..."

manifest docs

# 7. Notify stakeholders

echo "📢 Notifying stakeholders..."
# Send notifications to various channels

echo "✅ Custom release workflow completed"

```

## 📊 Monitoring and Analytics

## Release Metrics Collection

Tracking release performance and metrics:

```bash
#!/bin/bash
# collect-metrics.sh - Collect release metrics

echo "📊 Release Metrics Collection"

echo "=============================="

# Collect basic metrics

RELEASE_VERSION=$(cat VERSION)

RELEASE_DATE=$(manifest ntp --format='%Y-%m-%d %H:%M:%S UTC')

RELEASE_TIME=$(date +%s)

# Performance metrics

echo "📋 Collecting performance metrics..."

NTP_TIME=$(time manifest ntp 2>&1 | grep real | awk '{print $2}')

TEST_TIME=$(time manifest test all 2>&1 | grep real | awk '{print $2}')

# Git metrics

GIT_COMMITS=$(git log --oneline $(git describe --tags --abbrev=0)..HEAD | wc -l)

GIT_FILES=$(git diff --name-only $(git describe --tags --abbrev=0)..HEAD | wc -l)

# Output metrics

cat > release-metrics.json << EOF

{

  "release": {

    "version": "$RELEASE_VERSION",

    "date": "$RELEASE_DATE",

    "timestamp": $RELEASE_TIME

  },

  "performance": {

    "ntp_time": "$NTP_TIME",

    "test_time": "$TEST_TIME"

  },

  "git": {

    "commits": $GIT_COMMITS,

    "files_changed": $GIT_FILES

  }

}

EOF

echo "✅ Metrics collected and saved to release-metrics.json"

```

## 🎉 Conclusion

These examples demonstrate the flexibility and power of Manifest CLI across different use cases and environments. The tool is designed to adapt to your specific needs while maintaining consistency and reliability.

## Current Capabilities

1. **Flexibility**: Manifest CLI adapts to various workflows and requirements

2. **Automation**: Reduces manual work and human error in releases

3. **Compliance**: Provides audit trails and trusted timestamps

4. **Integration**: Works seamlessly with existing CI/CD pipelines

5. **Customization**: Supports custom templates and configurations

## Future Capabilities

1. **Advanced AI**: Intelligent commit analysis and smart categorization

2. **Plugin Ecosystem**: Extensible architecture for custom functionality

3. **Cloud Native**: Multi-cloud deployment and infrastructure automation

4. **Security First**: Built-in security scanning and cryptographic verification

5. **Team Scale**: Multi-user workflows and enterprise collaboration features

## Next Steps

1. **Try the examples** above in your own environment

2. **Customize workflows** to match your organization's needs

3. **Integrate with CI/CD** for automated releases

4. **Create custom templates** for your documentation needs

5. **Contribute back** to the project with improvements

---

*Transform your release workflow with intelligent automation and AI-powered documentation! 🚀*

For more examples and use cases, see the [User Guide](USER_GUIDE.md) and [Command Reference](COMMAND_REFERENCE.md).
