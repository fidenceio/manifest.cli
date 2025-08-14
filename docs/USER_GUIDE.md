# 📖 Manifest CLI User Guide

**A powerful CLI tool for versioning, AI documenting, and repository operations.**

Welcome to the Manifest CLI User Guide! This comprehensive guide will walk you through everything you need to know to use the Manifest CLI effectively for automating your software release workflow.

## 🎯 What is Manifest CLI?

Manifest CLI is an intelligent command-line interface designed to automate and streamline your entire software release workflow. It combines **version management**, **AI-powered documentation generation**, and **repository operations** into a single, powerful tool that ensures consistency, accuracy, and compliance across all your projects.

The tool is built with a modular architecture that handles:
- **Version Management**: Semantic versioning with automatic bumps
- **AI Documentation**: Intelligent generation of release notes and changelogs
- **Repository Operations**: Git workflow automation and synchronization
- **Timestamp Verification**: Trusted NTP-based timestamps for compliance
- **Homebrew Integration**: Automatic formula updates and maintenance

### **Current Capabilities**
- **Core Workflow Automation**: Complete release process from version bump to deployment
- **Cross-Platform Support**: Optimized for macOS, Linux, and BSD systems
- **Intelligent Testing**: Comprehensive validation before release
- **Custom Templates**: Flexible documentation and workflow customization

### **Future Capabilities**
- **Advanced AI**: Smarter commit analysis and intelligent categorization
- **Plugin System**: Extensible architecture for custom functionality
- **Cloud Integration**: Multi-cloud deployment and infrastructure automation
- **Security Features**: GPG signing, vulnerability scanning, and audit logging
- **Team Collaboration**: Multi-user workflows and approval processes

## 🚀 Getting Started

### Prerequisites

Before using Manifest CLI, ensure you have:

- **Git** installed and configured (2.20+ recommended)
- **Node.js** 16.0+ (for package.json support)
- **Bash** 4.0+ (for advanced features)
- A Git repository with proper remote configuration
- Internet access for NTP timestamp verification

### First Run

After installation, run the CLI for the first time:

```bash
manifest --help
```

This will show you all available commands and options.

## 📚 Core Commands Deep Dive

### 1. `manifest go` - The Main Workflow

The `manifest go` command is the heart of the CLI. It orchestrates the entire release process with intelligent automation:

```bash
# Basic usage (patch version bump)
manifest go

# Specific version bump types
manifest go patch      # 1.0.0 → 1.0.1
manifest go minor      # 1.0.0 → 1.1.0
manifest go major      # 1.0.0 → 2.0.0
manifest go revision   # 1.0.0 → 1.0.0.1
```

#### What Happens During `manifest go`:

1. **🕐 NTP Timestamp**: Gets a trusted timestamp from multiple NTP servers
2. **📝 Change Detection**: Checks for uncommitted changes and auto-commits them
3. **🔄 Remote Sync**: Pulls latest changes from remote repository
4. **📦 Version Bump**: Increments version according to specified type
5. **🤖 AI Documentation**: Generates intelligent release notes and changelog
6. **🏷️ Git Operations**: Creates commit, tag, and pushes to all remotes
7. **🍺 Homebrew Update**: Updates Homebrew formula if applicable

#### Interactive Mode

For more control, you can run in interactive mode:

```bash
manifest go --interactive
```

This will prompt you for confirmation at each step of the workflow.

### 2. `manifest test` - Testing Your Setup

The testing framework helps ensure everything is working correctly before you release:

```bash
# Run all tests
manifest test

# Test specific components
manifest test versions    # Test version management
manifest test ntp         # Test NTP connectivity
manifest test git         # Test Git operations
manifest test docs        # Test documentation generation
manifest test os          # Test OS detection
```

#### Test Output Example

```bash
🧪 Running Manifest CLI tests...

✅ Version Management Tests
  ✓ Version file detection
  ✓ Version increment logic
  ✓ Version validation
  ✓ Package.json integration

✅ NTP Tests
  ✓ NTP server connectivity
  ✓ Timestamp accuracy
  ✓ Timezone handling
  ✓ Fallback mechanisms

✅ Git Tests
  ✓ Repository status
  ✓ Remote configuration
  ✓ Branch information
  ✓ Authentication

✅ Documentation Tests
  ✓ Template generation
  ✓ File creation
  ✓ Content validation
  ✓ Format checking

✅ OS Tests
  ✓ Platform detection
  ✓ Feature availability
  ✓ Performance optimization
  ✓ Compatibility checks

🎉 All tests passed! Your Manifest CLI is ready to use.
```

### 3. `manifest ntp` - Trusted Timestamps

Get verified timestamps for compliance and audit purposes:

```bash
# Get current NTP timestamp
manifest ntp

# Get timestamp in specific format
manifest ntp --format="%Y-%m-%d %H:%M:%S UTC"

# Verify timestamp accuracy
manifest ntp --verify
```

#### NTP Output Example

```bash
🕐 Getting trusted NTP timestamp...

📡 Connecting to NTP servers...
✅ Connected to time.nist.gov
✅ Connected to time.google.com
✅ Connected to pool.ntp.org

🕐 Timestamp: 2025-01-13 15:30:45 UTC
📍 Timezone: UTC
🔒 Verification: Trusted (3 servers)
⏱️  Accuracy: ±0.001 seconds
🎯 Method: external
📊 Offset: +0.002 seconds
```

### 4. `manifest docs` - AI-Powered Documentation

Automatically generate and update documentation with intelligent analysis:

```bash
# Generate all documentation
manifest docs

# Generate specific documentation types
manifest docs release    # Release notes only
manifest docs changelog  # Changelog only
manifest docs metadata   # Repository metadata
```

#### Generated Documentation

The CLI automatically creates:
- `docs/RELEASE_v{version}.md` - Professional release notes
- `docs/CHANGELOG_v{version}.md` - Intelligent changelog
- `README.md` updates - Version information synchronization

### 5. `manifest sync` - Repository Synchronization

Keep your local repository synchronized with remote:

```bash
# Sync with remote
manifest sync

# Force sync (overwrites local changes)
manifest sync --force

# Sync specific branches
manifest sync --branch=main
```

## 🔧 Advanced Usage

### Environment Variables

You can customize behavior with environment variables:

```bash
# Set custom NTP servers
export MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com"

# Set custom Git commit message template
export MANIFEST_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# Enable debug mode
export MANIFEST_DEBUG=true

# Set custom documentation templates
export MANIFEST_DOCS_TEMPLATE_DIR="/path/to/templates"
```

### Configuration Files

For advanced users, you can create a `.manifestrc` file in your project root:

```bash
# .manifestrc
NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org"
COMMIT_TEMPLATE="Release v{version} - {timestamp}"
DOCS_TEMPLATE_DIR="./templates"
DEBUG=false
INTERACTIVE=true
VERBOSE=false
LOG_LEVEL="INFO"
```

### Custom Documentation Templates

Create custom templates for release notes and changelogs:

```bash
# Create templates directory
mkdir -p templates

# Custom release template
cat > templates/release.md << 'EOF'
# Release v{version}

**Date:** {timestamp}
**Author:** {author}

## 🎯 What's New
{changes}

## 🚀 Installation
{installation}

## ⚠️ Breaking Changes
{breaking_changes}

## 🔧 Technical Details
- **Version:** {version}
- **Release Date:** {timestamp}
- **Generated:** {generated_timestamp}
EOF
```

## 🚨 Troubleshooting

### Common Issues

#### 1. NTP Connection Failed

```bash
❌ NTP connection failed
```

**Solutions:**
- Check internet connectivity
- Try different NTP servers
- Check firewall settings
- Use `manifest ntp --servers="time.google.com"`

#### 2. Git Authentication Issues

```bash
❌ Git push failed: authentication required
```

**Solutions:**
- Ensure SSH keys are configured
- Check Git credentials
- Verify remote URL format
- Use `git remote -v` to check configuration

#### 3. Version Bump Failed

```bash
❌ Version bump failed
```

**Solutions:**
- Check VERSION file permissions
- Verify package.json format
- Ensure no syntax errors
- Check for conflicting version files

#### 4. Documentation Generation Failed

```bash
❌ Documentation generation failed
```

**Solutions:**
- Check write permissions in docs/ directory
- Verify template syntax
- Ensure required files exist
- Check disk space

### Debug Mode

Enable debug mode for detailed troubleshooting:

```bash
export MANIFEST_DEBUG=true
manifest go
```

This will show detailed information about each step of the process.

### Log Files

Check log files for detailed error information:

```bash
# View recent logs
tail -f ~/.manifest-cli/logs/manifest.log

# Search for specific errors
grep "ERROR" ~/.manifest-cli/logs/manifest.log
```

## 🔄 Workflow Examples

### Daily Development Workflow

```bash
# 1. Make your changes
git add .
git commit -m "Feature: Add new functionality"

# 2. Run tests
manifest test

# 3. Release with patch version
manifest go

# 4. Verify release
git log --oneline -5
git tag --list -5
```

### Feature Release Workflow

```bash
# 1. Complete feature development
git checkout -b feature/new-feature
# ... make changes ...
git add .
git commit -m "Feature: Implement new feature"

# 2. Merge to main
git checkout main
git merge feature/new-feature

# 3. Release with minor version
manifest go minor

# 4. Clean up
git branch -d feature/new-feature
```

### Major Release Workflow

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

### CI/CD Integration

```bash
# GitHub Actions example
- name: Release
  run: |
    manifest test all
    manifest go patch
    manifest docs
```

## 📊 Best Practices

### 1. Version Management

- Use semantic versioning consistently
- Document breaking changes clearly
- Tag releases immediately after creation
- Keep version files in sync

### 2. Git Workflow

- Always pull before releasing
- Use meaningful commit messages
- Tag releases with version numbers
- Keep branches clean and organized

### 3. Documentation

- Generate documentation for every release
- Keep templates up-to-date
- Review generated content before publishing
- Archive old documentation

### 4. Testing

- Run tests before every release
- Test in different environments
- Validate generated artifacts
- Monitor for regressions

### 5. NTP Configuration

- Use multiple NTP servers for redundancy
- Set appropriate timeouts for your network
- Monitor NTP server availability
- Have fallback mechanisms in place

## 🌟 Advanced Features

### Custom NTP Servers

```bash
# Set custom NTP servers
export MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org"

# Set timeout and retry values
export MANIFEST_NTP_TIMEOUT=5
export MANIFEST_NTP_RETRIES=3
```

### Homebrew Integration

```bash
# Control Homebrew functionality
export MANIFEST_BREW_OPTION=enabled
export MANIFEST_BREW_INTERACTIVE=no

# Custom tap repository
export MANIFEST_TAP_REPO="https://github.com/your-org/your-tap.git"
```

### Git Configuration

```bash
# Custom commit templates
export MANIFEST_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# Author information
export MANIFEST_GIT_AUTHOR_NAME="Your Name"
export MANIFEST_GIT_AUTHOR_EMAIL="your.email@example.com"
```

## 🎉 Next Steps

Now that you're familiar with the basics:

1. **Try the examples** above in your own repository
2. **Explore advanced features** like custom templates
3. **Integrate with CI/CD** pipelines
4. **Customize workflows** for your team's needs
5. **Contribute** to the project

## 📞 Need Help?

- **Documentation**: Check other docs in this directory
- **Issues**: Report bugs on [GitHub](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: Ask questions on [GitHub Discussions](https://github.com/fidenceio/manifest.cli/discussions)
- **Examples**: See the [examples directory](docs/EXAMPLES.md) for more use cases
- **Command Reference**: See [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md) for complete command details

---

*Transform your release workflow with intelligent automation and AI-powered documentation! 🚀*
