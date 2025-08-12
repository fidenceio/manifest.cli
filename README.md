# 🚀 Manifest CLI

A powerful command-line interface tool for managing manifest files, versioning, and repository operations with trusted NTP timestamp verification.





## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `7.1.0` |
| **Release Date** | `2025-08-12 14:54:00 UTC` |
| **Git Tag** | `v7.1.0` |
| **Branch** | `main` |
| **Last Updated** | `2025-08-12 14:54:00 UTC` |
| **CLI Version** | `7.1.0` |

### 📚 Documentation Files
- **Package Info**: [package.json](package.json)
- **CLI Source**: [src/cli/](src/cli/)
- **Install Script**: [install-cli.sh](install-cli.sh)

---

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
│   ├── manifest-cli.sh      # Main CLI entry point
│   ├── manifest-cli-wrapper.sh  # CLI wrapper for installation
│   └── modules/             # CLI modules
│       ├── manifest-core.sh     # Core workflow orchestration
│       ├── manifest-docs.sh     # Documentation generation
│       ├── manifest-git.sh      # Git operations
│       ├── manifest-ntp.sh      # NTP timestamp handling
│       ├── manifest-os.sh       # OS compatibility
│       └── manifest-test.sh     # Testing functionality
├── docs/                    # Generated documentation
├── install-cli.sh          # Installation script
├── package.json            # Project configuration
└── README.md               # This file
```

## 📚 CLI Command Reference

### Core Commands

| Command | Description | Usage |
|---------|-------------|-------|
| `go` | Complete automated workflow | `manifest go [patch\|minor\|major\|revision] [-i]` |
| `test` | Test CLI functionality | `manifest test [versions\|all]` |
| `ntp` | Get trusted NTP timestamp | `manifest ntp` |
| `sync` | Sync with remote repository | `manifest sync` |
| `docs` | Generate documentation | `manifest docs [metadata]` |
| `version` | Bump version | `manifest version [patch\|minor\|major]` |
| `commit` | Commit changes | `manifest commit "message"` |
| `push` | Push changes to remote | `manifest push [patch\|minor\|major]` |

### Workflow Commands

- **`manifest go`** - Complete workflow: sync → docs → version → commit → push → metadata
- **`manifest go patch`** - Increment patch version (e.g., 7.1.0 → 7.1.1)
- **`manifest go minor`** - Increment minor version (e.g., 7.1.0 → 7.2.0)
- **`manifest go major`** - Increment major version (e.g., 7.1.0 → 8.0.0)
- **`manifest go revision`** - Increment revision (e.g., 7.1.0 → 7.1.0.1)

### Testing Commands

- **`manifest test`** - Basic functionality test
- **`manifest test versions`** - Test version increment logic
- **`manifest test all`** - Comprehensive system testing

### Timestamp Commands

- **`manifest ntp`** - Get trusted NTP timestamp with offset and uncertainty
- **`manifest ntp-config`** - Display NTP configuration and servers
- **`manifest ntp`** - Quick timestamp for manifest operations

## 🧪 Testing

```bash
# Test basic functionality
manifest test

# Test version increments
manifest test versions

# Test complete workflow
manifest test all

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
manifest help
manifest test
manifest docs
```

## 📈 Version History

- **v7.1.0** - **MAJOR REFACTOR**: Test commands moved to main arguments, legacy `go test` removed
- **v7.0.0** - Complete CLI architecture overhaul with modular design
- **v6.6.3** - Enhanced testing and documentation
- **v6.6.2** - Repository metadata automation
- **v6.6.1** - Comprehensive workflow automation
- **v6.6.0** - Initial CLI implementation
- **v6.5.7** - Project foundation and CLI focus

## 🔄 Recent Changes (v8.0.0)

### Breaking Changes
- **`manifest go test`** → **`manifest test`** (test commands are now main arguments)
- **`manifest go test versions`** → **`manifest test versions`**
- **`manifest go test all`** → **`manifest test all`**

### Major Improvements
- 🚀 **Complete NTP Module Refactor v2.0** - Simple, highly accurate timestamp service
- ⚡ **Performance Boost** - Reduced timeout from 5s to 3s, faster fallback
- 🎯 **Better Accuracy** - Improved NTP offset calculation and validation
- 🔧 **Simplified Code** - Cleaner, more maintainable NTP implementation
- 📱 **Cross-Platform** - Enhanced compatibility across Linux, macOS, and Unix systems

### Legacy Issue Resolution
- ✅ Removed nested test commands from `go` workflow
- ✅ Test commands now properly documented as main arguments
- ✅ Updated help text and documentation
- ✅ Fixed emoji display issues
- ✅ Updated install script to remove legacy references
- ✅ Comprehensive README documentation update

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `manifest test`
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🌟 Support

- **Repository**: [fidenceio/manifest.cli](https://github.com/fidenceio/manifest.cli)
- **Issues**: [GitHub Issues](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: [GitHub Discussions](https://github.com/fidenceio/manifest.cli/discussions)

---

**Built with ❤️ by [Fidence.io](https://fidence.io)**

## 📋 Version Information

| Field | Value |
|-------|-------|
| **Current Version** | `7.0.0` |
| **Last Updated** | `2025-08-12 19:02:11 UTC` |
| **NTP Server** | `system` |
| **NTP Offset** | `0.000000 seconds` |
| **Uncertainty** | `±0.000000 seconds` |

## 📋 Version Information

| Field | Value |
|-------|-------|
| **Current Version** | `7.1.0` |
| **Last Updated** | `2025-08-12 19:17:17 UTC` |
| **NTP Server** | `system` |
| **NTP Offset** | `0.000000 seconds` |
| **Uncertainty** | `±0.000000 seconds` |
