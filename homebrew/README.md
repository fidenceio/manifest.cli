# Manifest CLI - Homebrew Installation

This directory contains the Homebrew formula for installing the Manifest CLI on macOS and Linux.

## 🍺 Installation

### Quick Install

```bash
# Install Manifest CLI
brew install manifest

# Verify installation
manifest --help
```

### From Source

```bash
# Install from the formula file
brew install homebrew/manifest.rb

# Or install from GitHub
brew install fidenceio/manifest.local/manifest
```

## 🚀 Quick Start

After installation, you can use the Manifest CLI immediately:

```bash
# Show available commands
manifest help

# Check system health
manifest diagnose

# Automated version bump
manifest go patch

# Generate documentation
manifest docs
```

## 📁 Installation Structure

The Homebrew formula installs the following structure:

```
/opt/homebrew/bin/manifest          # CLI executable
/opt/homebrew/libexec/             # Application files
/opt/homebrew/etc/manifest/        # System configuration
/opt/homebrew/var/lib/manifest/    # Data directory
/opt/homebrew/var/log/manifest/    # Log directory
~/.manifest-local/                 # User configuration
```

## ⚙️ Configuration

### Automatic Configuration

The formula automatically creates:
- `~/.manifest-local/.env` - CLI configuration
- System directories for data and logs
- Example configuration files

### Manual Configuration

```bash
# Edit CLI configuration
nano ~/.manifest-local/.env

# Copy example configurations
cp /opt/homebrew/etc/manifest/env.example ~/.manifest-local/.env
cp /opt/homebrew/etc/manifest/.manifestrc.example ~/.manifest-local/.manifestrc
```

## 🔧 Dependencies

The formula automatically installs:
- **Node.js** (>=18.0.0) - Runtime environment
- **Git** - Version control system

## 🧪 Testing

Test the installation:

```bash
# Test CLI execution
manifest --help

# Test basic functionality
manifest diagnose

# Test in a git repository
cd /tmp
git init
manifest help
```

## 🚨 Troubleshooting

### Common Issues

#### "Command not found: manifest"
```bash
# Check if Homebrew is in PATH
echo $PATH | grep homebrew

# Reinstall the formula
brew uninstall manifest && brew install manifest
```

#### "Not in a git repository"
```bash
# Navigate to a git repository
cd /path/to/your/repo

# Or initialize git
git init
```

#### Permission Issues
```bash
# Fix permissions
chmod 755 /opt/homebrew/bin/manifest
chmod 600 ~/.manifest-local/.env
```

### Getting Help

```bash
# Check installation
brew list manifest

# View formula info
brew info manifest

# Check for updates
brew update && brew upgrade manifest
```

## 📚 Documentation

- **Full Documentation**: [GitHub Repository](https://github.com/fidenceio/manifest.local)
- **CLI Commands**: `manifest help`
- **System Health**: `manifest diagnose`

## 🔄 Updates

```bash
# Update Homebrew
brew update

# Upgrade Manifest CLI
brew upgrade manifest

# Check current version
manifest --version
```

## 🤝 Contributing

To contribute to the Homebrew formula:

1. Fork the repository
2. Modify `Formula/manifest.rb`
3. Test locally: `brew install Formula/manifest.rb`
4. Submit a pull request

## 📄 License

This formula is licensed under the MIT License, same as the main project.
