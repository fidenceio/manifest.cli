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

## **Current Version (22.0.0+)**
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

## Method 2: Direct Installation Script

Install directly from the repository:

```bash
# Download and run installation script
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

**What this script does:**
1. Downloads the CLI to `~/.local/bin/`
2. Creates project directory at `~/.manifest-cli/`
3. Sets up configuration files
4. Adds to PATH (current session)
5. Verifies installation

## Method 3: Manual Installation

For advanced users who want full control:

```bash
# Clone the repository
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli

# Run the installation script
./install-cli.sh
```

## Method 4: Package Managers

## Arch Linux (AUR)
```bash
# Using yay
yay -S manifest-cli

# Using paru
paru -S manifest-cli
```

## Nix/NixOS
```bash
# Add to configuration.nix
environment.systemPackages = with pkgs; [ manifest-cli ];

# Or install directly
nix-env -iA nixpkgs.manifest-cli
```

## 🖥️ Platform-Specific Instructions

## macOS

## Homebrew (Recommended)
```bash
brew install fidenceio/manifest/manifest
```

## Manual Installation
```bash
# Install dependencies
brew install coreutils git node

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
sudo apt install git nodejs npm curl

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## CentOS/RHEL/Fedora
```bash
# Install dependencies
sudo yum install git nodejs npm curl  # CentOS/RHEL
# or
sudo dnf install git nodejs npm curl  # Fedora

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## Arch Linux
```bash
# Install from AUR
yay -S manifest-cli

# Or manual installation
sudo pacman -S git nodejs npm curl
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli.git/main/install-cli.sh | bash
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

# Install Node.js
# Download from: https://nodejs.org/

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## PowerShell
```powershell
# Install using winget (Windows 10/11)
winget install fidenceio.manifest

# Or using Chocolatey
choco install manifest-cli
```

## BSD Systems

## FreeBSD
```bash
# Install dependencies
sudo pkg install git node npm curl

# Install CLI
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

## OpenBSD
```bash
# Install dependencies
sudo pkg_add git node npm curl

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

Add to your shell profile:

```bash
# For bash (~/.bashrc or ~/.bash_profile)
export PATH="$HOME/.local/bin:$PATH"

# For zsh (~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"

# For fish (~/.config/fish/config.fish)
set -gx PATH $HOME/.local/bin $PATH
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
MANIFEST_CLI_TAP_REPO="https://github.com/fidenceio/fidenceio-homebrew-tap.git"

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
- Check if `~/.local/bin` is in your PATH
- Restart your terminal
- Verify installation location: `which manifest`

## 2. Permission Denied

```bash
❌ Permission denied
```

**Solutions:**
- Check file permissions: `ls -la ~/.local/bin/manifest`
- Make executable: `chmod +x ~/.local/bin/manifest`
- Check directory permissions: `ls -la ~/.local/bin/`

## 3. Dependencies Missing

```bash
❌ Required command not found
```

**Solutions:**
- Install Git: `brew install git` (macOS) or `sudo apt install git` (Ubuntu)
- Install Node.js: `brew install node` (macOS) or `sudo apt install nodejs` (Ubuntu)
- Install coreutils: `brew install coreutils` (macOS)

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

**Node.js version too old:**
```bash
# Install NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
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
# Pull latest changes
cd ~/.manifest-cli
git pull origin main

# Reinstall if needed
./install-cli.sh
```

## Direct Installation Users

```bash
# Download and run latest installation script
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
# Remove CLI binary
rm ~/.local/bin/manifest

# Remove project directory
rm -rf ~/.manifest-cli

# Remove from PATH (edit shell profile)
# Remove the line: export PATH="$HOME/.local/bin:$PATH"
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
