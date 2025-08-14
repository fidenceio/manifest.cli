# 🚀 Manifest CLI

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `8.7.0` |
| **Release Date** | `2025-08-14 00:26:48 UTC` |
| **Git Tag** | `v8.7.0` |
| **Branch** | `main` |
| **Last Updated** | `2025-08-14 00:26:48 UTC` |
| **CLI Version** | `8.7.0` |

### 📚 Documentation Files
- **Package Info**: [package.json](package.json)
- **CLI Source**: [src/cli/](src/cli/)
- **Install Script**: [install-cli.sh](install-cli.sh)



**A powerful CLI tool for versioning, AI documenting, and repository operations.**

[![Version](https://img.shields.io/badge/version-8.6.7-blue.svg)](VERSION)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](package.json)

## ✨ What is Manifest CLI?

Manifest CLI is an intelligent command-line interface that automates and streamlines your entire software release workflow. It combines **version management**, **AI-powered documentation generation**, and **repository operations** into a single, powerful tool that ensures consistency, accuracy, and compliance across all your projects.

## 🌟 Key Features

### 🔄 **Intelligent Version Management**
- **Semantic Versioning**: Automatic patch, minor, major, and revision bumps
- **Multi-format Support**: Works with VERSION files, package.json, and custom formats
- **Smart Detection**: Automatically identifies and updates version files
- **Rollback Support**: Easy reversion to previous versions
- **Future**: Advanced versioning strategies and dependency management

### 🤖 **AI-Powered Documentation**
- **Auto-generated Release Notes**: Professional release documentation
- **Smart Changelog Creation**: Intelligent commit analysis and categorization
- **README Updates**: Automatic version information synchronization
- **Template System**: Customizable documentation templates
- **Future**: AI-powered commit message generation and intelligent categorization

### 🕐 **Trusted Timestamp Verification**
- **NTP Integration**: Multiple trusted time servers for accuracy
- **Audit Trail**: Verifiable timestamps for compliance
- **Cross-platform**: Optimized for macOS, Linux, and BSD systems
- **Fallback Mechanisms**: Graceful degradation when NTP unavailable
- **Future**: Blockchain timestamping and advanced cryptographic verification

### 🏷️ **Git Workflow Automation**
- **Complete Workflow**: Sync → Version → Document → Commit → Tag → Push
- **Change Detection**: Automatic handling of uncommitted changes
- **Multi-remote Support**: Push to all configured remotes
- **Branch Management**: Intelligent branch detection and handling
- **Future**: Advanced Git workflows, conflict resolution, and team collaboration

### 🍺 **Homebrew Integration**
- **Formula Updates**: Automatic Homebrew formula maintenance
- **Tap Management**: Seamless integration with custom taps
- **Version Synchronization**: Keep Homebrew and CLI versions in sync
- **Future**: Multi-package manager support (apt, yum, pacman, etc.)

### 🧪 **Comprehensive Testing**
- **Built-in Test Suite**: Validate all functionality before release
- **Component Testing**: Test individual modules independently
- **Workflow Validation**: Ensure complete release process integrity
- **Future**: Advanced testing frameworks, performance benchmarking, and security scanning

## 🚀 Quick Start

### Installation

#### Option 1: Homebrew (Recommended)
```bash
brew install fidenceio/manifest/manifest
```

#### Option 2: Direct Installation
```bash
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

#### Option 3: Manual Installation
```bash
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli
./install-cli.sh
```

### First Steps

```bash
# Verify installation
manifest --help

# Test functionality
manifest test

# Get trusted timestamp
manifest ntp

# Run complete workflow
manifest go
```

## 📚 Core Commands

### `manifest go` - The Complete Workflow

The heart of Manifest CLI that orchestrates your entire release process:

```bash
# Basic patch release
manifest go

# Specific version types
manifest go minor      # 1.0.0 → 1.1.0
manifest go major      # 1.0.0 → 2.0.0
manifest go revision   # 1.0.0 → 1.0.0.1

# Interactive mode
manifest go --interactive
```

**What happens during `manifest go`:**
1. 🕐 **NTP Timestamp** - Get trusted timestamp from multiple servers
2. 📝 **Change Detection** - Identify and commit pending changes
3. 🔄 **Remote Sync** - Pull latest changes from remote
4. 📦 **Version Bump** - Increment version according to type
5. 🤖 **AI Documentation** - Generate release notes and changelog
6. 🏷️ **Git Operations** - Commit, tag, and push changes
7. 🍺 **Homebrew Update** - Update formula if applicable

### `manifest test` - Validation Suite

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

### `manifest ntp` - Trusted Timestamps

Get verified timestamps for compliance and audit purposes:

```bash
# Basic timestamp
manifest ntp

# Custom format
manifest ntp --format="%Y-%m-%d %H:%M:%S UTC"

# Verify accuracy
manifest ntp --verify
```

### `manifest docs` - Documentation Generation

Automatically create and update documentation:

```bash
# Generate all documentation
manifest docs

# Specific types
manifest docs release     # Release notes only
manifest docs changelog   # Changelog only
manifest docs metadata    # Repository metadata
```

### `manifest sync` - Repository Management

Keep your repository synchronized:

```bash
# Basic sync
manifest sync

# Force sync
manifest sync --force

# Branch-specific sync
manifest sync --branch=develop
```

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

## 🌟 Use Cases

### **Software Development Teams**
- Standardize release processes across projects
- Automate documentation generation
- Maintain consistent versioning strategies
- Ensure compliance with audit requirements

### **DevOps & CI/CD**
- Integrate with automated deployment pipelines
- Generate release artifacts automatically
- Maintain deployment audit trails
- Streamline release management

### **Open Source Projects**
- Automate release workflows
- Generate professional documentation
- Maintain version consistency
- Simplify contributor onboarding

### **Enterprise Development**
- Compliance and audit trail requirements
- Standardized release processes
- Multi-team coordination
- Regulatory documentation needs

## 🚦 Requirements

- **Operating System**: macOS 10.15+, Linux (kernel 4.0+), BSD
- **Git**: 2.20+ (recommended)
- **Node.js**: 16.0+ (for package.json support)
- **Bash**: 4.0+ (for advanced features)
- **Network**: Internet access for NTP servers

## 📖 Documentation

- **[User Guide](docs/USER_GUIDE.md)** - Complete usage instructions
- **[Command Reference](docs/COMMAND_REFERENCE.md)** - Command reference
- **[Installation Guide](docs/INSTALLATION.md)** - Setup instructions
- **[Contributing](docs/CONTRIBUTING.md)** - Development guide
- **[Examples](docs/EXAMPLES.md)** - Real-world use cases

## 🔄 Workflow Examples

### Daily Development
```bash
# 1. Make changes
git add .
git commit -m "Feature: Add new functionality"

# 2. Test everything
manifest test

# 3. Release with patch version
manifest go

# 4. Verify release
git log --oneline -5
git tag --list -5
```

### Feature Release
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

# 4. Clean up
git branch -d feature/new-feature
```

### Major Release
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

## 🚀 Future Roadmap

Manifest CLI is built with extensibility and future growth in mind. Upcoming versions will include:

### **Advanced AI & Machine Learning**
- **Smart Commit Messages**: AI-generated commit messages based on code changes
- **Intelligent Categorization**: Automatic classification of changes and features
- **Predictive Analytics**: Suggest optimal release timing and versioning
- **Natural Language Processing**: Understand and process human-readable descriptions

### **Enhanced Security & Compliance**
- **GPG Signing**: Cryptographic verification of releases and commits
- **Vulnerability Scanning**: Integration with security tools and databases
- **Audit Logging**: Comprehensive audit trails for compliance requirements
- **Access Control**: Role-based permissions and team collaboration

### **Cloud & DevOps Integration**
- **Multi-Cloud Support**: AWS, Azure, GCP, and Kubernetes integration
- **CI/CD Enhancement**: Advanced pipeline automation and deployment
- **Infrastructure as Code**: Terraform, CloudFormation, and ARM template support
- **Monitoring & Alerting**: Real-time metrics and intelligent notifications

### **Developer Experience**
- **Plugin System**: Extend functionality with custom plugins
- **Web Interface**: Browser-based management and visualization
- **REST API**: Programmatic access and integration
- **Multi-language Bindings**: Python, Go, Rust, and JavaScript SDKs

## 🎯 Best Practices

### **Version Management**
- Use semantic versioning consistently
- Document breaking changes clearly
- Tag releases immediately after creation
- Keep version files synchronized

### **Documentation**
- Generate documentation for every release
- Keep templates up-to-date
- Review generated content before publishing
- Archive old documentation

### **Git Workflow**
- Always pull before releasing
- Use meaningful commit messages
- Tag releases with version numbers
- Keep branches clean and organized

### **Testing**
- Run tests before every release
- Test in different environments
- Validate generated artifacts
- Monitor for regressions

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](docs/CONTRIBUTING.md) for details on:

- Code style and standards
- Testing requirements
- Pull request process
- Development setup
- Community guidelines

## 📞 Support & Community

- **Documentation**: [Full Documentation](docs/)
- **Issues**: [GitHub Issues](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: [GitHub Discussions](https://github.com/fidenceio/manifest.cli/discussions)
- **Examples**: [Examples Directory](docs/EXAMPLES.md)
- **Changelog**: [Version History](docs/CHANGELOG.md)

## 🔗 Links

- **Repository**: https://github.com/fidenceio/manifest.cli
- **Homepage**: https://github.com/fidenceio/manifest.cli#readme
- **Releases**: https://github.com/fidenceio/manifest.cli/releases
- **Homebrew Tap**: https://github.com/fidenceio/fidenceio-homebrew-tap

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Made with ❤️ by [Fidence.io](https://fidence.io)**

*Transform your release workflow with intelligent automation and AI-powered documentation.*



