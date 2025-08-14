# 🚀 Manifest CLI

> **A powerful CLI tool for versioning, AI documenting, and repository operations.**

[![Version](https://img.shields.io/badge/version-8.8.0-blue.svg)](VERSION)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-blue.svg)](docs/INSTALLATION.md)
[![Documentation](https://img.shields.io/badge/docs-complete-brightgreen.svg)](docs/)

---

## 🎯 What is Manifest CLI?

**Manifest CLI** is your all-in-one solution for modern software development workflows. Think of it as your personal DevOps assistant that automates the tedious parts of version management, documentation, and repository operations.

### 🌟 Why Manifest CLI?

- **🤖 AI-Powered**: Intelligent documentation generation that understands your project
- **⏰ Trusted Timestamps**: NTP-verified timestamps for compliance and audit trails
- **🔄 Automated Workflows**: One command handles versioning, docs, commits, and deployment
- **📚 Smart Documentation**: Automatically manages historical docs and keeps your project organized
- **🍺 Homebrew Ready**: Seamless integration with macOS package management
- **🔒 Enterprise Grade**: Built for teams, compliance, and production environments

---

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/fidenceio/fidenceio.manifest.cli.git
cd fidenceio.manifest.cli

# Install the CLI
./install-cli.sh

# Verify installation
manifest --help
```

### Your First Workflow

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

### Environment Variables

```bash
# NTP Configuration
export MANIFEST_NTP_SERVERS="time.nist.gov,time.google.com,pool.ntp.org"
export MANIFEST_NTP_TIMEOUT=5
export MANIFEST_NTP_RETRIES=3

# Homebrew Integration
export MANIFEST_BREW_OPTION=enabled
export MANIFEST_BREW_INTERACTIVE=no
export MANIFEST_TAP_REPO="https://github.com/your-org/your-tap.git"

# Git Configuration
export MANIFEST_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"
export MANIFEST_GIT_AUTHOR_NAME="Your Name"
export MANIFEST_GIT_AUTHOR_EMAIL="your.email@example.com"
```

### Configuration File

Create `.manifestrc` in your project root:

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
- **Project Configuration**: Use `.manifestrc` for project-specific settings
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
| **Current Version** | `8.8.0` |
| **Release Date** | `2025-08-14 00:39:51 UTC` |
| **Git Tag** | `v8.8.0` |
| **Branch** | `main` |
| **Last Updated** | `2025-08-14 00:39:51 UTC` |
| **CLI Version** | `8.8.0` |

---

<div align="center">

**🚀 Ready to revolutionize your development workflow?**

[Get Started →](docs/USER_GUIDE.md) • [View Examples →](docs/EXAMPLES.md) • [Join Community →](https://github.com/fidenceio/fidenceio.manifest.cli/discussions)

*Made with ❤️ by the Manifest CLI team*

</div>



