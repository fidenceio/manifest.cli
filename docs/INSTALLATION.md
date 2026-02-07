# 🚀 Manifest CLI Installation Guide

**A powerful CLI tool for versioning, AI documenting, and repository operations.**

This guide covers all installation methods for Manifest CLI across different platforms and environments.

## 🎯 Prerequisites

Before installing Manifest CLI, ensure you have:

- **Git** 2.20+ (recommended)
- **Bash** 3.2+ (Bash 4.0+ recommended for advanced features)
- **Zsh** 5.9+ (optional, for cross-shell compatibility testing)
- **Internet access** (for NTP timestamp verification)
- **Administrative privileges** (for some installation methods)

## **System Requirements**

## **Current Version (31.0.0+)**
- **Operating System**: macOS 10.15+, Linux (kernel 4.0+), BSD
- **Memory**: 512MB RAM minimum, 1GB recommended
- **Storage**: 100MB available disk space
- **Network**: Stable internet connection for NTP and updates
- **Shell Compatibility**: Bash 3.2+, Zsh 5.9+ (with comprehensive testing)
- **Security**: Input validation, path security, command injection protection

## **Future Versions**
- **Operating System**: Windows 10/11, additional Linux distributions
- **Memory**: 1GB RAM minimum, 2GB recommended
- **Storage**: 200MB available disk space
- **Network**: Enhanced offline capabilities and local NTP servers
- **Security**: Advanced GPG signing, vulnerability scanning

## 🍺 Installation Methods

## Method 1: Homebrew (Recommended)

The easiest way to install Manifest CLI on macOS and Linux:

```bash
# Add the Fidence.io tap
brew tap fidenceio/manifest

# Install the CLI
brew install manifest
```

**Verify installation:**
```bash
manifest --version
```

**Update to latest version:**
```bash
brew upgrade manifest
```

## Method 2: Install Script (with Homebrew auto-detection)

The install script automatically routes through Homebrew when available, or falls back to a manual installation:

```bash
# Download and run installation script
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

**What this script does:**

1. Detects if Homebrew is installed
2. If Homebrew is available: runs `brew tap fidenceio/tap && brew install manifest`
3. If Homebrew is not available: installs manually to `~/.manifest-cli/` with a symlink in `~/.local/bin/`
4. Cleans up any legacy manual installations if upgrading to Homebrew
5. Verifies installation

## Method 3: Manual Installation (Linux / CI environments)

For environments without Homebrew:

```bash
# Clone the repository
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli

# Run the installation script
./install-cli.sh
```

## 🖥️ Platform-Specific Instructions

## macOS

## Homebrew (Recommended)
```bash
brew tap fidenceio/manifest
brew install manifest
```

## Manual Installation
```bash
# Install dependencies
brew install coreutils git

# Clone and install
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli
./install-cli.sh
```

## Linux

## Ubuntu/Debian
```bash
# Install dependencies
sudo apt update
sudo apt install git curl

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## CentOS/RHEL/Fedora
```bash
# Install dependencies
sudo yum install git curl  # CentOS/RHEL
# or
sudo dnf install git curl  # Fedora

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## Arch Linux
```bash
# Manual installation
sudo pacman -S git curl
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## Windows

## WSL2 (Recommended)
```bash
# Install WSL2 with Ubuntu
wsl --install -d Ubuntu

# Follow Ubuntu installation instructions above
```

## Git Bash
```bash
# Install Git for Windows
# Download from: https://git-scm.com/download/win

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## BSD Systems

## FreeBSD
```bash
# Install dependencies
sudo pkg install git curl bash

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## OpenBSD
```bash
# Install dependencies
sudo pkg_add git curl bash

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## 🔧 Post-Installation Setup

## 1. Verify Installation

```bash
# Check CLI version
manifest --version

# Test basic functionality
manifest --help

# Run comprehensive tests
manifest test
```

## 2. Configure Git

Ensure Git is properly configured:

```bash
# Set your name and email
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Verify configuration
git config --list
```

## 3. Set Up SSH Keys (Recommended)

For secure repository access:

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your.email@example.com"

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copy public key to clipboard (macOS)
pbcopy < ~/.ssh/id_ed25519.pub

# Copy public key to clipboard (Linux)
xclip -selection clipboard < ~/.ssh/id_ed25519.pub
```

## 4. Environment Configuration

If you installed via Homebrew, no PATH changes are needed. For manual installations, add to your shell profile:

```bash
# For bash (~/.bashrc or ~/.bash_profile)
export PATH="$HOME/.local/bin:$PATH"

# For zsh (~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"
```

## 5. Custom Configuration

Create `.env.manifest.global` in your project root:

```bash
# .env.manifest.global
# Core configuration
MANIFEST_CLI_DEBUG=false
MANIFEST_CLI_VERBOSE=false
MANIFEST_CLI_LOG_LEVEL="INFO"
MANIFEST_CLI_INTERACTIVE=true

# NTP configuration
MANIFEST_CLI_NTP_SERVERS="time.apple.com,time.google.com,pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=5
MANIFEST_CLI_NTP_RETRIES=3

# Git configuration with retry logic
MANIFEST_CLI_GIT_TIMEOUT=300
MANIFEST_CLI_GIT_RETRIES=3
MANIFEST_CLI_GIT_COMMIT_TEMPLATE="Release v{version} - {timestamp}"

# Documentation configuration
MANIFEST_CLI_DOCS_TEMPLATE_DIR="./templates"
MANIFEST_CLI_DOCS_OUTPUT_DIR="./docs"

# Homebrew configuration
MANIFEST_CLI_BREW_OPTION="enabled"
MANIFEST_CLI_BREW_INTERACTIVE="no"
MANIFEST_CLI_TAP_REPO="https://github.com/fidenceio/homebrew-tap.git"

# Cloud configuration
MANIFEST_CLI_CLOUD_API_KEY="your-api-key-here"
MANIFEST_CLI_CLOUD_ENDPOINT="https://api.manifest.cloud"
MANIFEST_CLI_CLOUD_SKIP=false
MANIFEST_CLI_OFFLINE_MODE=false
```

## 🧪 Testing Your Installation

## Basic Functionality Test

```bash
# Test CLI availability
manifest --help

# Test NTP functionality
manifest ntp

# Test Git operations
manifest test git

# Test documentation generation
manifest test docs
```

## Comprehensive Test

```bash
# Run all tests
manifest test all
```

## Cross-Shell Compatibility Test

Test your installation across different shell environments:

```bash
# Test Zsh 5.9 compatibility
manifest test zsh

# Test Bash 3.2 compatibility
manifest test bash32

# Test Bash 4+ compatibility
manifest test bash4

# Auto-detect current shell and test
manifest test bash
```

## Security Test

Test security features and validation:

```bash
# Run security audit
manifest security

# Test specific security features
manifest security --vulnerabilities
manifest security --privacy
manifest security --paths
```

## Workflow Test

```bash
# Test complete workflow (dry run)
manifest go --dry-run
```

## 🚨 Troubleshooting

## Common Installation Issues

## 1. Command Not Found

```bash
❌ manifest: command not found
```

**Solutions:**

- If installed via Homebrew: run `brew link manifest`
- If installed manually: check if `~/.local/bin` is in your PATH
- Restart your terminal
- Verify installation location: `which manifest`

## 2. Permission Denied

```bash
❌ Permission denied
```

**Solutions:**

- If installed via Homebrew: run `brew reinstall manifest`
- If installed manually: `chmod +x ~/.local/bin/manifest`

## 3. Dependencies Missing

```bash
❌ Required command not found
```

**Solutions:**

- Install Git: `brew install git` (macOS) or `sudo apt install git` (Ubuntu)
- Install coreutils: `brew install coreutils` (macOS, optional)

## 4. Network Issues

```bash
❌ Failed to download installation script
```

**Solutions:**
- Check internet connectivity
- Try different DNS servers
- Use VPN if behind corporate firewall
- Download manually and run locally

## Platform-Specific Issues

## macOS Issues

**Homebrew not found:**
```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Permission issues:**
```bash
# Fix Homebrew permissions
sudo chown -R $(whoami) /usr/local/bin /usr/local/lib /usr/local/sbin
```

## Linux Issues

**Package manager errors:**
```bash
# Update package lists
sudo apt update  # Ubuntu/Debian
sudo yum update  # CentOS/RHEL
sudo dnf update  # Fedora
```

## Windows Issues

**WSL2 not working:**
```bash
# Enable WSL2
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

**Git Bash issues:**
- Ensure Git for Windows is properly installed
- Check PATH environment variable
- Restart terminal after installation

## 🔄 Updating Manifest CLI

## Homebrew Users

```bash
# Update Homebrew
brew update

# Upgrade Manifest CLI
brew upgrade manifest
```

## Manual Installation Users

```bash
# Re-run the install script (auto-detects Homebrew and migrates if available)
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## 🗑️ Uninstalling Manifest CLI

## Homebrew Users

```bash
# Remove the CLI
brew uninstall manifest

# Remove the tap (optional)
brew untap fidenceio/manifest
```

## Manual Installation Users

```bash
# Use the built-in uninstall command
manifest uninstall

# Or remove manually:
rm -f ~/.local/bin/manifest
rm -rf ~/.manifest-cli
# Edit your shell profile to remove: export PATH="$HOME/.local/bin:$PATH"
```

## 📚 Next Steps

After successful installation:

1. **Read the [User Guide](USER_GUIDE.md)** for usage instructions
2. **Check the [Command Reference](COMMAND_REFERENCE.md)** for command details
3. **Try the examples** in the documentation
4. **Join the community** on GitHub Discussions
5. **Report issues** if you encounter problems

## 📞 Getting Help

- **Installation Issues**: Check this guide and troubleshooting section
- **Usage Questions**: See [User Guide](USER_GUIDE.md) and [Command Reference](COMMAND_REFERENCE.md)
- **Bug Reports**: [GitHub Issues](https://github.com/fidenceio/manifest.cli/issues)
- **Community Support**: [GitHub Discussions](https://github.com/fidenceio/manifest.cli/discussions)

---

*Happy installing! 🚀*
