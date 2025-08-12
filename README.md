# Manifest Local CLI

**Comprehensive Git operations and versioning automation tool with trusted NTP timestamp verification**

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `6.5.6` |
| **Release Date** | `2025-08-12 04:18:35 UTC` |
| **Git Tag** | `v6.5.6` |
| **Commit Hash** | `7ac8620` |
| **Branch** | `main` |
| **Last Updated** | `2025-08-12 04:18:35 UTC` |
| **NTP Server** | `system (127.0.0.1)` |
| **NTP Offset** | `0.000000 seconds` |
| **Uncertainty** | `±0.000000 seconds` |

### 📚 Documentation Files
- **Release Notes**: [docs/RELEASE_v6.5.6.md](docs/RELEASE_v6.5.6.md)
- **Changelog**: [docs/CHANGELOG_v6.5.6.md](docs/CHANGELOG_v6.5.6.md)
- **Package Info**: [package.json](package.json)

---

## 🚀 Overview

Manifest Local CLI is a powerful command-line tool that automates Git operations, version management, and documentation generation. It provides trusted NTP timestamps for all operations, ensuring accurate audit trails and compliance requirements.

## ✨ Key Features

- **🕐 Trusted NTP Timestamps**: Automatic timestamp verification from multiple NTP servers
- **🚀 Complete Workflow Automation**: Single command handles sync, docs, version, commit, push, and metadata
- **📚 Smart Documentation**: Auto-generates RELEASE notes, CHANGELOG, and README updates
- **🌐 Repository Integration**: Automatic metadata updates for GitHub/GitLab repositories
- **🧪 Enhanced Testing**: Comprehensive test modes for validation and debugging
- **📊 Version Management**: Semantic versioning with patch, minor, and major increments

## 🛠️ Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/fidenceio/manifest.local.git
cd manifest.local

# Install the CLI
bash install-cli.sh

# Verify installation
manifest help
```

### Manual Installation

```bash
# Make the CLI executable
chmod +x src/cli/manifest-cli.sh

# Create symlink (optional)
sudo ln -s $(pwd)/src/cli/manifest-cli.sh /usr/local/bin/manifest
```

## 📖 Usage

### Basic Commands

```bash
# Get help
manifest help

# Get trusted NTP timestamp
manifest ntp

# Complete automated workflow
manifest go [patch|minor|major]

# Test mode (no changes)
manifest go test

# Enhanced testing
manifest go test versions    # Test version increments
manifest go test all         # Comprehensive testing
```

### Complete Workflow

The `manifest go` command performs a complete automated workflow:

```bash
manifest go patch    # Increment patch version (6.5.6 → 6.5.7)
manifest go minor    # Increment minor version (6.5.6 → 6.6.0)
manifest go major    # Increment major version (6.5.6 → 7.0.0)
```

**Workflow Steps:**
1. 🔄 **Sync** with remote repository
2. 📚 **Generate** documentation (RELEASE, CHANGELOG, README)
3. 📦 **Bump** version number
4. 💾 **Commit** all changes with NTP timestamps
5. 🏷️ **Create** git tag
6. 🚀 **Push** to all remotes
7. 🏷️ **Update** repository metadata

### Individual Commands

```bash
# Sync with remote
manifest sync

# Generate documentation
manifest docs

# Update repository metadata
manifest docs metadata

# Version management
manifest version [patch|minor|major]

# Diagnostics
manifest diagnose
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file in your project root:

```bash
# Optional: Manifest Cloud service
MANIFEST_CLOUD_URL=https://your-cloud-service.com
MANIFEST_CLOUD_API_KEY=your-api-key
```

### Repository Setup

The CLI automatically detects your repository provider (GitHub, GitLab) and installs the appropriate CLI tools:

- **GitHub**: Installs `gh` CLI for repository metadata updates
- **GitLab**: Installs `glab` CLI for repository metadata updates

## 🧪 Testing

### Test Modes

```bash
# Basic test (no changes)
manifest go test

# Test version increments
manifest go test versions

# Comprehensive testing
manifest go test all
```

### What Tests Cover

- **Version Increments**: patch, minor, major scenarios
- **Environment Validation**: configuration, dependencies, security
- **Workflow Steps**: sync, docs, version, commit, push, metadata

## 🕐 NTP Timestamp Verification

Every manifest operation includes trusted NTP timestamps:

- **Multiple NTP Servers**: time.apple.com, time.google.com, pool.ntp.org, time.nist.gov
- **Fallback Handling**: Gracefully falls back to system time if NTP unavailable
- **Audit Trail**: Complete timestamp information in all generated files and commits
- **Compliance**: Meets requirements for timestamp verification and audit trails

## 📁 Project Structure

```
manifest.local/
├── src/cli/           # CLI implementation
├── docs/              # Generated documentation
├── install-cli.sh     # Installation script
├── package.json       # Project configuration
└── README.md          # This file
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: Check the generated docs in the `docs/` directory
- **Issues**: Report bugs and feature requests on GitHub
- **CLI Help**: Run `manifest help` for command documentation

---

**Built with ❤️ by the Fidenceio Team**
