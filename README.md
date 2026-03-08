# Manifest
A powerful command-line tool for automating Git workflows, version management, and documentation generation. The Manifest CLI streamlines your development process with intelligent versioning, automated commits, and seamless integration with Manifest Cloud for enhanced features.

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `35.2.0` |
| **Release Date** | `2026-03-08 02:38:56 UTC` |
| **Git Tag** | `v35.2.0` |
| **Branch** | `main` |
| **Last Updated** | `2026-03-08 02:38:56 UTC` |
| **CLI Version** | `35.2.0` |

### 📚 Documentation Files

- **Version Info**: [VERSION](VERSION)
- **CLI Modules**: [modules/](modules/)
- **Install Script**: [install-cli.sh](install-cli.sh)
## 🚀 Features

### Core Git Operations
- **Automated Version Management**: Bump versions with semantic versioning (patch, minor, major)
- **Smart Commit Handling**: Auto-commit changes with intelligent messages
- **Tag Management**: Automatic Git tagging with version numbers
- **Multi-Remote Support**: Push to all configured remotes automatically

### Documentation Generation
- **Release Notes**: Generate comprehensive release documentation
- **Changelog Creation**: Build detailed changelogs from commit history
- **README Updates**: Keep documentation in sync with versions
- **VERSION File Management**: Maintain a simple VERSION file for version tracking

### Advanced Workflows
- **One-Command Automation**: `manifest prep` for complete version bump → commit → tag → push workflow
- **Version Reversion**: Safely revert to previous versions with interactive selection
- **Conflict Resolution**: Automatic handling of common Git conflicts and sync issues
- **Health Diagnostics**: Built-in troubleshooting with `manifest diagnose`

### Optional Cloud Integration
- **Commit Analysis**: AI-powered commit analysis and recommendations
- **Intelligent Changelogs**: Generate rich changelogs using Manifest Cloud
- **Version Recommendations**: Get smart suggestions for version increments
- **API Change Detection**: Automatically detect breaking changes

## 📦 Installation

### Homebrew (Recommended)

```bash
# Add the Fidence.io tap and install
brew tap fidenceio/manifest
brew install manifest
```

### Update

```bash
brew upgrade manifest
```

### Install Script (auto-detects Homebrew)

```bash
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

For detailed installation instructions (Linux, CI/CD, manual install), see the [Installation Guide](docs/INSTALLATION.md).

## 🎯 Quick Start

### 1. Basic Version Management

```bash
# Check current version
cat VERSION

# Bump patch version (1.0.0 → 1.0.1)
manifest version patch

# Bump minor version (1.0.0 → 1.1.0)
manifest version minor

# Bump major version (1.0.0 → 2.0.0)
manifest version major
```

### 2. Automated Workflow

```bash
# Complete automated process (recommended)
manifest prep major    # Major version bump
manifest prep minor    # Minor version bump
manifest prep patch    # Patch version bump
manifest prep          # Auto-detect increment type
```

### 3. Documentation Generation

```bash
# Generate release notes and changelog
manifest docs

# Create custom commit
manifest commit "Add new feature X"

# Revert to previous version
manifest revert
```

## 📚 Command Reference

### Core Commands

#### `manifest prep [type]`
The main command for automated workflows. Automatically handles version bumping, committing, tagging, and pushing.

```bash
manifest prep major     # Increment major version
manifest prep minor     # Increment minor version
manifest prep patch     # Increment patch version
manifest prep revision  # Increment revision version
manifest prep           # Auto-detect increment type
```

**What it does:**
1. Checks for uncommitted changes
2. Analyzes commits (if cloud service configured)
3. Bumps version according to type
4. Updates VERSION file
5. Commits changes
6. Creates Git tag
7. Pushes to all remotes

#### `manifest version [type]`
Simple version bumping without the full workflow.

```bash
manifest version patch  # 1.0.0 → 1.0.1
manifest version minor  # 1.0.0 → 1.1.0
manifest version major  # 1.0.0 → 2.0.0
```

#### `manifest docs`
Generate comprehensive documentation for the current version.

**Creates:**
- `docs/RELEASE_vX.Y.Z.md` - Release notes
- `docs/CHANGELOG_vX.Y.Z.md` - Detailed changelog
- Updates `README.md` with changelog section

#### `manifest revert`
Interactive version reversion with safety confirmations.

```bash
manifest revert
# Shows available versions and prompts for selection
# Updates VERSION file and README.md
# Commits changes and creates tag
```

#### `manifest commit <message>`
Create a commit with a custom message.

```bash
manifest commit "Add new authentication feature"
```

#### `manifest diagnose`
Comprehensive health check and troubleshooting.

**Checks:**
- Git repository status
- Remote configuration
- SSH authentication
- VERSION file consistency
- Cloud service configuration
- Provides actionable solutions

### Utility Commands

#### `manifest analyze`
Analyze commits using Manifest Cloud service (requires configuration).

#### `manifest changelog`
Generate changelog using Manifest Cloud service (requires configuration).

#### `manifest help`
Show help information.

## 🔧 Configuration

### Environment Variables

Create `.env.manifest.global` in your project root for configuration:

```bash
# See examples/env.manifest.global.example for all options
MANIFEST_CLI_DEBUG=false
MANIFEST_CLI_VERBOSE=false
MANIFEST_CLI_NTP_SERVER1=time.apple.com
```

#### Git Configuration

The CLI automatically uses your existing Git configuration:

```bash
# Ensure SSH keys are configured
ssh-add ~/.ssh/id_rsa

# Configure Git user
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## 🏗️ Project Structure

```
manifest.cli/
├── install-cli.sh             # Installation script
├── VERSION                    # Current version
├── scripts/                   # CLI entry points
│   ├── manifest-cli.sh        # Main CLI script
│   └── manifest-cli-wrapper.sh # Installed wrapper
├── modules/                   # Modular CLI functionality
│   ├── core/                  # Core modules (config, env, git)
│   ├── docs/                  # Documentation generation
│   ├── system/                # System modules (install, uninstall, security)
│   └── workflow/              # Workflow orchestration
├── examples/                  # Configuration templates
├── formula/                   # Homebrew formula
├── docs/                      # Documentation
└── README.md
```

## 🔄 Workflow Examples

### Standard Release Process

```bash
# 1. Generate documentation
manifest docs

# 2. Commit documentation
manifest commit "Add documentation for v2.1.0"

# 3. Automated release
manifest prep minor

# Result: Version bumped, committed, tagged, and pushed
```

### Hotfix Process

```bash
# Quick patch release
manifest prep patch

# Result: 2.1.0 → 2.1.1, committed, tagged, and pushed
```

### Major Version Release

```bash
# Major version with full workflow
manifest prep major

# Result: 2.1.1 → 3.0.0, committed, tagged, and pushed
```

## 🚨 Troubleshooting

### Common Issues

#### "Not in a git repository"
```bash
# Initialize git repository
git init
git remote add origin <your-repo-url>
```

#### "Permission denied (publickey)"
```bash
# Check SSH key
ssh-add ~/.ssh/id_rsa
ssh -T git@github.com
```

#### "Remote is ahead, cannot fast-forward"
```bash
# Use diagnose to check status
manifest diagnose

# Manually sync if needed
git pull origin main --rebase
```

#### VERSION file out of sync
```bash
# Regenerate VERSION file
manifest version patch
```

### Getting Help

```bash
# Comprehensive health check
manifest diagnose

# Show help
manifest help

# Check git status
git status
```

## 🔗 Manifest Cloud Integration

The Manifest CLI can optionally integrate with Manifest Cloud for enhanced features:

### Benefits
- **AI-Powered Analysis**: Intelligent commit analysis and recommendations
- **Rich Documentation**: Generate detailed changelogs with context
- **Version Intelligence**: Get smart suggestions for version increments
- **API Change Detection**: Automatically identify breaking changes

### Setup
1. Configure environment variables in `.env.manifest.global` or `.env.manifest.local`
2. Use `manifest analyze` and `manifest changelog` commands
3. Enhanced `manifest prep` workflow with intelligent recommendations

### Fallback Behavior
If Manifest Cloud is not configured or unavailable, the CLI gracefully falls back to basic functionality:
- Basic changelog generation from Git history
- Standard version incrementing
- Full Git workflow automation

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

This project is open source and available under the MIT License.

## 🆘 Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: [GitHub Discussions](https://github.com/fidenceio/manifest.cli/discussions)

---

**Built with ❤️ by the Fidence.io team**

## 📋 Changelog

### [v16.2.7] - 2025-09-05 23:00:00 UTC
- **Patch Release**: Various improvements and bug fixes
- Enhanced CLI functionality
- Improved error handling
- Better cross-platform compatibility

### [v16.2.6] - 2025-09-05 22:55:00 UTC
- **Patch Release**: Various improvements and bug fixes
- Enhanced CLI functionality
- Improved error handling
- Better cross-platform compatibility
- # Change Analysis for v16.2.6

## New Features

### [v3.0.0] - 2025-08-11
- **Major Release**: Complete CLI rewrite with enhanced automation
- **New Commands**: `manifest prep`, `manifest docs`, `manifest diagnose`
- **VERSION File**: Automatic VERSION file management
- **Conflict Resolution**: Automatic handling of common Git conflicts
- **Cloud Integration**: Optional Manifest Cloud service integration
- **Documentation**: Comprehensive documentation generation

### [v2.0.2] - 2025-08-11
- Added VERSION file management
- Enhanced conflict resolution in push operations
- Added comprehensive diagnostics command
- Improved error handling and user feedback

See the latest [CHANGELOG files](docs/) for full details.
