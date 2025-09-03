# 🚀 Manifest CLI

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `13.2.0` |
| **Release Date** | `2025-08-14 00:59:29 UTC` |
| **Git Tag** | `v13.2.0` |
| **Branch** | `main` |
| **Last Updated** | `2025-08-14 00:59:29 UTC` |
| **CLI Version** | `13.2.0` |

### 📚 Documentation Files
- **Version Info**: [VERSION](VERSION)
- **CLI Source**: [src/cli/](src/cli/)
- **Install Script**: [install-cli.sh](install-cli.sh)



> **A powerful CLI tool for versioning, AI documenting, and repository operations.**

[![Version](https://img.shields.io/badge/version-13.2.0-blue.svg)](VERSION)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-blue.svg)](docs/INSTALLATION.md)
[![Documentation](https://img.shields.io/badge/docs-complete-brightgreen.svg)](docs/)

---

## 🎯 What is Manifest CLI?

**Manifest CLI** is your personal DevOps assistant that automates the tedious parts of version management, documentation, and repository operations.

### 🌟 Why Manifest CLI?

- **🤖 AI-Powered**: Intelligent documentation generation that understands your project
- **⏰ Trusted Timestamps**: NTP-verified timestamps for compliance and audit trails
- **🔄 Automated Workflows**: One command handles versioning, docs, commits, and deployment
- **📚 Smart Documentation**: Automatically manages historical docs and keeps your project organized
- **🍺 Homebrew Ready**: Seamless integration with macOS package management
- **🔒 Enterprise Grade**: Built for teams, compliance, and production environments

---

## 🚀 Quick Start

### 1. Installation

```bash
# Clone the repository
git clone https://github.com/fidenceio/fidenceio.manifest.cli.git
cd fidenceio.manifest.cli

# Install the CLI
./install-cli.sh

# Verify installation
manifest --help
```

### 2. Configuration Setup ⚙️

**Quick Setup (Recommended):**

```bash
# Copy the example configuration
cp env.example .env

# Edit with your specific values
nano .env
```

**Essential Configuration:**

**🔧 Git Repository Setup:**
```bash
# Manifest CLI automatically uses all configured git remotes
# No need to configure remotes in .env - just use standard git commands:

# Add your primary remote (if not already set)
git remote add origin https://github.com/yourusername/yourrepo.git

# Add additional remotes as needed
git remote add upstream https://github.com/original/repo.git
git remote add staging https://github.com/yourorg/staging.git
```

**📝 Required Environment Variables:**
```bash
# Git Configuration (Required)
MANIFEST_GIT_AUTHOR_NAME="Your Name"
MANIFEST_GIT_AUTHOR_EMAIL="your.email@example.com"
MANIFEST_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# NTP Configuration (Required for timestamp verification)
MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org"

# Homebrew Integration (Required for macOS users)
MANIFEST_BREW_OPTION=enabled
MANIFEST_TAP_REPO="https://github.com/your-org/your-tap.git"
```

**Why This Configuration Matters:**
- **Git Operations**: Author info ensures proper commit attribution
- **Timestamp Verification**: NTP servers provide trusted timestamps for compliance
- **Homebrew Integration**: Enables automatic formula updates on macOS
- **Multi-Remote Support**: Works with all your configured git remotes automatically

### 3. Your First Workflow

```bash
# Make some changes to your code
echo "# New feature" >> README.md

# Run the complete workflow
manifest go patch

# That's it! Manifest CLI will:
# 1. Get trusted timestamp
# 2. Commit your changes
# 3. Sync with remote
# 4. Move old docs to past_releases
# 5. Bump version
# 6. Generate new documentation
# 7. Commit, tag, and push
```

---

## 🎭 Core Commands

### 🚀 `manifest go` - The Complete Workflow

Your one-command solution for everything:

```bash
# Patch version (bug fixes, small changes)
manifest go patch

# Minor version (new features, backward compatible)
manifest go minor

# Major version (breaking changes)
manifest go major

# Interactive mode (choose what to do)
manifest go minor -i
```

**What happens during `manifest go`:**
1. 🕐 **NTP Timestamp** - Get trusted timestamp from multiple servers
2. 📝 **Change Detection** - Identify and commit pending changes
3. 🔄 **Remote Sync** - Pull latest changes from remote
4. 📁 **Documentation Cleanup** - Move previous version docs to past_releases
5. 📦 **Version Bump** - Increment version according to type
6. 🤖 **AI Documentation** - Generate release notes and changelog
7. 🏷️ **Git Operations** - Commit, tag, and push changes
8. 🍺 **Homebrew Update** - Update formula if applicable

### 🕐 `manifest ntp` - Trusted Timestamps

Get verified timestamps for compliance and audit purposes:

```bash
# Basic timestamp
manifest ntp

# Custom format
manifest ntp --format="%Y-%m-%d %H:%M:%S UTC"

# Verify accuracy
manifest ntp --verify
```

**Perfect for:**
- Compliance requirements
- Audit trails
- Legal documentation
- Financial transactions
- Regulatory submissions

### 📚 `manifest docs` - Documentation Management

Automatically create and update documentation:

```bash
# Generate all documentation
manifest docs

# Specific types
manifest docs release     # Release notes only
manifest docs changelog   # Changelog only
manifest docs metadata    # Repository metadata
manifest docs cleanup     # Move historical docs to past_releases
```

### 🧹 `manifest cleanup` - Historical Documentation

Move historical documentation to keep the main docs folder clean:

```bash
# Move all historical documentation to past_releases
manifest cleanup
```

### ⚙️ `manifest config` - Configuration Management

View and manage your current configuration:

```bash
# Show current configuration
manifest config
```

This displays all environment variables, defaults, and current settings.

### 🔄 `manifest sync` - Repository Management

Keep your repository synchronized:

```bash
# Basic sync
manifest sync

# Force sync
manifest sync --force

# Branch-specific sync
manifest sync --branch=develop
```

### 🧪 `manifest test` - Validation Suite

Comprehensive testing to ensure everything works correctly:

```bash
# Run all tests
manifest test

# Test specific components
manifest test versions    # Version management
manifest test ntp         # NTP functionality
manifest test git         # Git operations
manifest test all         # Comprehensive testing
```

---

## 🏗️ Architecture

Manifest CLI is built with a modular, extensible architecture:

```
src/cli/
├── manifest-cli.sh          # Main entry point
├── manifest-cli-wrapper.sh  # Installation wrapper
└── modules/
    ├── manifest-core.sh     # Workflow orchestration
    ├── manifest-git.sh      # Git operations
    ├── manifest-ntp.sh      # NTP timestamp service
    ├── manifest-docs.sh     # Documentation generation
    ├── manifest-os.sh       # OS detection & optimization
    └── manifest-test.sh     # Testing framework
```

### 🔧 How It Works

1. **Command Parsing**: Your command is parsed and routed to the appropriate module
2. **Validation**: System requirements and prerequisites are checked
3. **Execution**: The selected workflow is executed step-by-step
4. **Feedback**: Rich, colored output keeps you informed of progress
5. **Error Handling**: Graceful fallbacks and helpful error messages

---

## 🔧 Configuration

### Critical Environment Variables ⚠️

**These variables MUST be configured for Manifest CLI to work properly:**

```bash
# NTP Configuration (Required for timestamp verification)
export MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org"
export MANIFEST_NTP_TIMEOUT=5
export MANIFEST_NTP_RETRIES=3

# Homebrew Integration (Required for macOS users)
export MANIFEST_BREW_OPTION=enabled
export MANIFEST_BREW_INTERACTIVE=no
export MANIFEST_TAP_REPO="https://github.com/your-org/your-tap.git"

# Git Configuration (Required for repository operations)
export MANIFEST_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"
export MANIFEST_GIT_AUTHOR_NAME="Your Name"
export MANIFEST_GIT_AUTHOR_EMAIL="your.email@example.com"
```

### Advanced Configuration Options 🚀

**Manifest CLI now supports extensive customization for different organizations with human-intuitive versioning:**

```bash
# Versioning Formats (Choose your organization's standard)
MANIFEST_VERSION_FORMAT="XX.XX.XX"           # Standard: 1.0.0
MANIFEST_VERSION_FORMAT="XXXX.XXXX.XXXX"     # Enterprise: 0001.0001.0001
MANIFEST_VERSION_FORMAT="YYYY.MM.DD"         # Date-based: 2024.01.15
MANIFEST_VERSION_FORMAT="X.X.X.X"            # Build numbers: 1.0.0.1

# Human-Intuitive Component Mapping
# LEFT components = More MAJOR changes (bigger impact)
# RIGHT components = More MINOR changes (smaller impact)
MANIFEST_MAJOR_COMPONENT_POSITION="1"        # First position (leftmost)
MANIFEST_MINOR_COMPONENT_POSITION="2"        # Second position (middle)
MANIFEST_PATCH_COMPONENT_POSITION="3"        # Third position (rightmost)
MANIFEST_REVISION_COMPONENT_POSITION="4"     # Fourth position (most right)

# Increment Behavior (which component each command affects)
MANIFEST_MAJOR_INCREMENT_TARGET="1"          # 'manifest go major' increments this
MANIFEST_MINOR_INCREMENT_TARGET="2"          # 'manifest go minor' increments this
MANIFEST_PATCH_INCREMENT_TARGET="3"          # 'manifest go patch' increments this
MANIFEST_REVISION_INCREMENT_TARGET="4"       # 'manifest go revision' increments this

# Reset Behavior (which components reset to 0)
MANIFEST_MAJOR_RESET_COMPONENTS="2,3,4"     # Reset minor/patch/revision when major changes
MANIFEST_MINOR_RESET_COMPONENTS="3,4"       # Reset patch/revision when minor changes
MANIFEST_PATCH_RESET_COMPONENTS="4"          # Reset revision when patch changes

# Branch Naming Conventions
MANIFEST_DEFAULT_BRANCH="main"               # Your default branch
MANIFEST_FEATURE_BRANCH_PREFIX="feature/"    # Feature branch prefix
MANIFEST_HOTFIX_BRANCH_PREFIX="hotfix/"     # Hotfix branch prefix

# Git Tag Customization
MANIFEST_GIT_TAG_PREFIX="v"                 # Tag prefix (v1.0.0)
MANIFEST_GIT_TAG_SUFFIX=""                  # Tag suffix (1.0.0-RELEASE)

# Documentation Patterns
MANIFEST_DOCS_FILENAME_PATTERN="{type}_v{version}.md"
MANIFEST_DOCS_HISTORICAL_LIMIT=20
```

**🧠 Why This Makes Sense:**
- **More digits after the last dot = More minor/specific changes**
- **Fewer digits after the last dot = More major/broad changes**
- **LEFT = Bigger impact, RIGHT = Smaller impact**

**See `env.examples.md` for complete configuration examples for different organization types.**

**What Happens Without These:**
- **NTP**: Timestamp verification will fail, affecting compliance
- **Homebrew**: Formula updates won't work on macOS
- **Git**: Repository operations may fail or use incorrect defaults

### Configuration File

Copy `env.example` to `.env` in your project root:

```bash
# Copy the example configuration
cp env.example .env

# Edit the configuration
nano .env
```

**Important**: The `.env` file is automatically ignored by git, so your custom configuration won't be committed to the repository.

**Key Configuration Options:**
- **Git Repository**: Use standard `git remote add/remove` commands (no .env config needed)
- **NTP Settings**: Customize timestamp servers and timeouts
- **Git Configuration**: Override user info and commit templates
- **Documentation**: Control auto-generation and historical limits
- **Development**: Enable debug, verbose, and interactive modes
- **Project-Specific**: Add custom variables for your project needs

**Git Remote Management:**
```bash
# Add remotes using standard git commands
git remote add origin https://github.com/yourusername/yourrepo.git
git remote add upstream https://github.com/original/repo.git

# Manifest CLI automatically works with all configured remotes
manifest go patch  # Pushes to ALL configured remotes
```

---

## 🌟 Use Cases

### **Software Development Teams**
- **Standardize Release Processes**: Everyone follows the same workflow
- **Automate Documentation**: No more manual changelog updates
- **Maintain Consistency**: Uniform versioning across all projects
- **Ensure Compliance**: Audit trails for regulatory requirements

### **DevOps & CI/CD**
- **Integrate with Pipelines**: Add to your automated deployment workflows
- **Generate Release Artifacts**: Automatic release notes and changelogs
- **Maintain Audit Trails**: Track every change with trusted timestamps
- **Streamline Releases**: One command handles the entire release process

### **Open Source Projects**
- **Professional Appearance**: Clean, organized documentation structure
- **Easy Contribution**: Clear workflows for contributors
- **Automated Maintenance**: Less manual work, more coding
- **Community Standards**: Consistent release processes

### **Enterprise & Compliance**
- **Regulatory Requirements**: NTP-verified timestamps for audits
- **Change Management**: Track every modification with full context
- **Documentation Standards**: Professional documentation for stakeholders
- **Security**: Trusted timestamp verification for sensitive operations

---

## 📚 Documentation Overview

- **[User Guide](docs/USER_GUIDE.md)** - Comprehensive guide for users
- **[Command Reference](docs/COMMAND_REFERENCE.md)** - Detailed reference for all CLI commands
- **[Installation Guide](docs/INSTALLATION.md)** - Step-by-step installation instructions
- **[Contributing Guidelines](docs/CONTRIBUTING.md)** - Guidelines for project contributors
- **[Examples](docs/EXAMPLES.md)** - Real-world usage examples and scenarios
- **[Human-Intuitive Versioning](docs/HUMAN_INTUITIVE_VERSIONING.md)** - How the versioning system matches human thinking
- **[Security Guide](docs/SECURITY.md)** - Security features and best practices
- **[Testing Guide](docs/TESTING.md)** - Comprehensive testing and validation
- **[Configuration vs Security](docs/CONFIG_VS_SECURITY.md)** - Clear distinction between commands
- **[Coverage Summary](docs/COVERAGE_SUMMARY.md)** - 100% testing and documentation coverage
- **[Configuration Examples](env.examples.md)** - Real-world configuration examples for different organizations

### **User Guide** (`docs/USER_GUIDE.md`)
Your comprehensive guide to using Manifest CLI effectively:

**What You'll Learn:**
- Getting started with your first project
- Understanding the workflow concepts
- Best practices for different project types
- Troubleshooting common issues
- Advanced configuration options

**Key Sections:**
- Current Capabilities: What works right now
- Future Capabilities: What's coming next
- Workflow Examples: Real-world scenarios
- Configuration Tips: Optimize for your needs

### **Command Reference** (`docs/COMMAND_REFERENCE.md`)
Complete reference for all commands and options:

**Comprehensive Coverage:**
- Every command with detailed explanations
- All available options and flags
- Example usage for each command
- Return codes and error handling
- Interactive mode options

**Special Features:**
- About This Reference: Understanding the documentation
- Future Capabilities: What's planned for upcoming versions
- Cross-references to examples and user guide

### **Installation Guide** (`docs/INSTALLATION.md`)
Step-by-step installation for all platforms:

**Platform Support:**
- macOS (with Homebrew integration)
- Linux (Ubuntu, CentOS, RHEL)
- Windows (WSL, Git Bash)
- Docker containers

**System Requirements:**
- Current Version: What works now
- Future Version: What's planned
- Dependencies and prerequisites
- Troubleshooting installation issues

### **Contributing Guidelines** (`docs/CONTRIBUTING.md`)
How to contribute to Manifest CLI development:

**Development Setup:**
- Current State: What's implemented
- Future Vision: Roadmap and goals
- Development environment setup
- Testing and quality assurance
- Code style and standards

**Getting Involved:**
- Issue reporting and bug fixes
- Feature requests and discussions
- Pull request guidelines
- Community guidelines

### **Examples & Use Cases** (`docs/EXAMPLES.md`)
Real-world examples and scenarios:

**Practical Examples:**
- Basic project setup
- CI/CD integration
- Team collaboration workflows
- Compliance and audit scenarios
- Open source project management

**Workflow Patterns:**
- Current Capabilities: What you can do now
- Future Capabilities: What's coming
- Best practices and tips
- Common pitfalls to avoid

---

## 🚀 Workflow Examples

### **Daily Development Workflow**

```bash
# 1. Start your day
manifest sync                    # Get latest changes

# 2. Make your changes
# ... edit your code ...

# 3. End your day
manifest go patch               # Commit, version, and push
```

### **Feature Release Workflow**

```bash
# 1. Create feature branch
git checkout -b feature/new-awesome-thing

# 2. Develop your feature
# ... code, test, iterate ...

# 3. Release the feature
manifest go minor               # New feature = minor version

# 4. Clean up
git branch -d feature/new-awesome-thing
```

### **Hotfix Workflow**

```bash
# 1. Create hotfix branch
git checkout -b hotfix/critical-bug

# 2. Fix the bug
# ... quick fix ...

# 3. Release the fix
manifest go patch               # Bug fix = patch version

# 4. Clean up
git branch -d hotfix/critical-bug
```

### **CI/CD Integration**

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
        run: ./install-cli.sh
      - name: Generate Release
        run: manifest docs
      - name: Create Release
        uses: actions/create-release@v1
```

---

## 🎯 Best Practices

### **Version Management**
- **Patch (8.8.0 → 8.8.1)**: Bug fixes, documentation updates
- **Minor (8.8.0 → 8.9.0)**: New features, backward compatible
- **Major (8.8.0 → 9.0.0)**: Breaking changes, major rewrites
- **Revision (8.8.0 → 8.8.0.1)**: Build numbers, metadata changes

### **Documentation**
- **Keep It Current**: Run `manifest docs` after significant changes
- **Use Descriptive Messages**: Clear commit messages help with changelog generation
- **Review Generated Docs**: Ensure accuracy before releases
- **Historical Management**: Let the system handle old documentation

### **Git Workflow**
- **Regular Syncs**: Use `manifest sync` to stay current
- **Meaningful Commits**: Each commit should represent a logical change
- **Tag Everything**: Tags are automatically created for versions
- **Branch Strategy**: Use feature branches for development

### **Configuration**
- **Environment Variables**: Use for machine-specific settings
- **Project Configuration**: Use `.env` for project-specific settings
- **Default Values**: Sensible defaults mean minimal configuration needed
- **Validation**: The CLI validates your configuration automatically

---

## 🔮 Future Roadmap

### **🤖 AI & Machine Learning**
- **Intelligent Changelog Generation**: AI-powered change analysis
- **Smart Version Recommendations**: ML-based version bump suggestions
- **Natural Language Commands**: "Release the new feature" instead of commands
- **Predictive Analytics**: Forecast release impact and dependencies

### **🔒 Security & Compliance**
- **Blockchain Timestamps**: Immutable timestamp verification
- **Digital Signatures**: Cryptographically signed releases
- **Compliance Frameworks**: Built-in support for SOC2, ISO27001, etc.
- **Audit Automation**: Automatic compliance reporting

### **☁️ Cloud Integration**
- **Multi-Cloud Support**: AWS, Azure, GCP integration
- **Container Orchestration**: Kubernetes, Docker Swarm support
- **Serverless Deployments**: Lambda, Cloud Functions integration
- **Infrastructure as Code**: Terraform, CloudFormation integration

### **👨‍💻 Developer Experience**
- **IDE Integration**: VS Code, IntelliJ, Vim plugins
- **Graphical Interface**: Web-based dashboard for non-CLI users
- **API Access**: RESTful API for programmatic access
- **Plugin System**: Extensible architecture for custom workflows

---

## 🆘 Support & Community

### **Getting Help**
- **Documentation**: Start with this README and the docs folder
- **Issues**: Report bugs and request features on GitHub
- **Discussions**: Join the community conversation
- **Examples**: Check the examples folder for real-world usage

### **Common Issues & Solutions**

**Configuration Problems:**
- **Git Remote Errors**: Ensure your repository has a valid remote origin
- **Homebrew Failures**: Check `MANIFEST_BREW_OPTION` and `MANIFEST_BREW_INTERACTIVE`
- **NTP Timeouts**: Verify `MANIFEST_NTP_SERVERS` and network connectivity
- **Permission Denied**: Ensure your `.env` file has correct permissions

**Quick Fixes:**
```bash
# Check your configuration
cat .env

# Verify git remote
git remote -v

# Test NTP connectivity
manifest ntp

# Run diagnostics
manifest test
```

### **Community Resources**
- **GitHub**: [fidenceio/fidenceio.manifest.cli](https://github.com/fidenceio/fidenceio.manifest.cli)
- **Issues**: [Bug Reports & Feature Requests](https://github.com/fidenceio/fidenceio.manifest.cli/issues)
- **Discussions**: [Community Q&A](https://github.com/fidenceio/fidenceio.manifest.cli/discussions)
- **Wiki**: [Additional Resources](https://github.com/fidenceio/fidenceio.manifest.cli/wiki)

### **Contributing**
We welcome contributions! See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for details on:
- Setting up your development environment
- Code style and standards
- Testing and quality assurance
- Pull request guidelines

---

## 🔗 Links

- **📚 [User Guide](docs/USER_GUIDE.md)** - Comprehensive usage guide
- **📖 [Command Reference](docs/COMMAND_REFERENCE.md)** - All commands and options
- **⚙️ [Installation](docs/INSTALLATION.md)** - Setup for all platforms
- **🤝 [Contributing](docs/CONTRIBUTING.md)** - How to contribute
- **💡 [Examples](docs/EXAMPLES.md)** - Real-world usage examples
- **🏠 [Homepage](https://github.com/fidenceio/fidenceio.manifest.cli)** - Project homepage

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **NTP Servers**: For providing trusted timestamp services
- **Git Community**: For the amazing version control system
- **Open Source Contributors**: For making this project possible
- **Users**: For feedback, bug reports, and feature requests

---

## 📊 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `13.2.0` |
| **Release Date** | `2025-08-14 01:18:27 UTC` |
| **Git Tag** | `v13.2.0` |
| **Branch** | `main` |
| **Last Updated** | `2025-08-14 01:18:27 UTC` |
| **CLI Version** | `13.2.0` |

---

<div align="center">

**🚀 Ready to revolutionize your development workflow?**

[Get Started →](docs/USER_GUIDE.md) • [View Examples →](docs/EXAMPLES.md) • [Join Community →](https://github.com/fidenceio/fidenceio.manifest.cli/discussions)

*Made with ❤️ by the Manifest CLI team*

</div>



