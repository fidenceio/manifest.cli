# 🚀 Manifest CLI

A powerful command-line interface tool for managing manifest files, versioning, and repository operations with trusted NTP timestamp verification.


## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `6.6.0` |
| **Release Date** | `2025-08-12 15:55:18 UTC` |
| **Git Tag** | `v6.6.0` |
| **Commit Hash** | `7e1b280` |
| **Branch** | `main` |
| **Last Updated** | `2025-08-12 15:55:18 UTC` |
| **NTP Server** | `system (127.0.0.1)` |
| **NTP Offset** | `0.000000 seconds` |
| **Uncertainty** | `±0.000000 seconds` |

### 📚 Documentation Files
- **Release Notes**: [docs/RELEASE_v6.6.0.md](docs/RELEASE_v6.6.0.md)
- **Changelog**: [docs/CHANGELOG_v6.6.0.md](docs/CHANGELOG_v6.6.0.md)
- **Package Info**: [package.json](package.json)

---

- 🕐 **Trusted NTP Timestamps** - All operations verified with multiple NTP servers
- 🔄 **Automated Versioning** - Patch, minor, major, and revision increments
- 📚 **Documentation Generation** - Automatic RELEASE and CHANGELOG creation
- 🌐 **Repository Sync** - Seamless remote synchronization
- 🏷️ **Git Operations** - Automated commit, tag, and push workflows
- 📊 **Metadata Updates** - Repository description, topics, and homepage management
- 🧪 **Testing Modes** - Comprehensive testing scenarios without execution
- 🚀 **One-Command Workflow** - Complete automation with `manifest go`

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli

# Install CLI locally
./install-cli.sh

# Verify installation
manifest --help
```

### Basic Usage

```bash
# Complete workflow (recommended)
manifest go

# Specific version increments
manifest go patch    # 6.5.7 → 6.5.8
manifest go minor    # 6.5.7 → 6.6.0
manifest go major    # 6.5.7 → 7.0.0
manifest go revision # 6.5.7 → 6.5.7.1

# Testing modes
manifest go test
manifest go test versions
manifest go test all

# Individual operations
manifest sync
manifest docs
manifest ntp
```

## 📚 Documentation

- **[RELEASE_v6.5.7.md](docs/RELEASE_v6.5.7.md)** - Current release notes
- **[CHANGELOG_v6.5.7.md](docs/CHANGELOG_v6.5.7.md)** - Detailed change history

## 🔧 Configuration

The CLI automatically detects your repository provider (GitHub, GitLab, Bitbucket) and installs the necessary CLI tools locally.

### Environment Variables

```bash
# Optional: Set custom NTP servers
export MANIFEST_NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org,time.nist.gov"

# Optional: Set custom timeout
export MANIFEST_NTP_TIMEOUT=5
```

## 🏗️ Architecture

```
manifest.cli/
├── src/cli/
│   └── manifest-cli.sh      # Main CLI implementation
├── docs/                    # Generated documentation
├── install-cli.sh          # Installation script
├── package.json            # Project configuration
└── README.md               # This file
```

## 🧪 Testing

```bash
# Test version increments
manifest go test versions

# Test complete workflow
manifest go test all

# Test individual components
manifest sync
manifest docs
manifest ntp
```

## 🔍 Troubleshooting

### Common Issues

1. **NTP Unavailable**: Falls back to system time automatically
2. **Git Authentication**: Ensure SSH keys are configured
3. **Repository Access**: Verify remote permissions

### Getting Help

```bash
manifest --help
manifest go --help
manifest docs --help
```

## 📈 Version History

- **v6.5.7** - Complete project cleanup and CLI focus
- **v6.5.6** - NTP timestamp integration
- **v6.5.5** - Enhanced testing and documentation
- **v6.5.4** - Repository metadata automation
- **v6.5.3** - Comprehensive workflow automation
- **v6.5.2** - Initial CLI implementation
- **v6.5.1** - Project foundation

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `manifest go test`
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🌟 Support

- **Repository**: [fidenceio/manifest.cli](https://github.com/fidenceio/manifest.cli)
- **Issues**: [GitHub Issues](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: [GitHub Discussions](https://github.com/fidenceio/manifest.cli/discussions)

---

**Built with ❤️ by [Fidence.io](https://fidence.io)**
