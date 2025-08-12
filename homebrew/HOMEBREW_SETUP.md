# 🍺 Manifest CLI - Homebrew Setup Guide

This guide explains how to set up and maintain the Homebrew installation for the Manifest CLI.

## 📋 Overview

The Manifest CLI can now be installed via Homebrew, making it easy for developers to get started with:

```bash
brew install fidenceio/manifest.local/manifest
```

## 🏗️ Architecture

### **Formula Structure**
```
homebrew/
├── manifest.rb              # Homebrew formula
├── package.json             # Minimal dependencies
├── brew-release.sh          # Release automation script
├── README.md                # Installation guide
└── HOMEBREW_SETUP.md       # This file
```

### **Installation Structure**
```
/opt/homebrew/bin/manifest          # CLI executable
/opt/homebrew/libexec/             # Application files
/opt/homebrew/etc/manifest/        # System configuration
/opt/homebrew/var/lib/manifest/    # Data directory
/opt/homebrew/var/log/manifest/    # Log directory
~/.manifest-local/                 # User configuration
```

## 🚀 Release Process

### **1. Prepare Release**

```bash
# Ensure you're on the main branch with latest changes
git checkout main
git pull origin main

# Create and push a new tag
git tag v3.0.3
git push origin v3.0.3
```

### **2. Run Release Script**

```bash
# Navigate to homebrew directory
cd homebrew

# Run the release script
./brew-release.sh
```

The script will:
- ✅ Verify git tag exists
- 📦 Create release tarball
- 🔐 Calculate SHA256 hash
- 📝 Update formula with hash
- 🧪 Test formula locally
- 🎉 Provide next steps

### **3. Complete Release**

```bash
# Commit updated formula
git add homebrew/manifest.rb
git commit -m "Update Homebrew formula for v3.0.3"
git push origin main

# Create GitHub release
# - Tag: v3.0.3
# - Title: Release v3.0.3
# - Upload: manifest-3.0.3.tar.gz
```

## 📦 Formula Details

### **Dependencies**
- **Node.js** (>=18.0.0) - Runtime environment
- **Git** - Version control system

### **Installation Process**
1. Downloads release tarball from GitHub
2. Installs Node.js dependencies
3. Creates CLI executable
4. Sets up directory structure
5. Configures user environment
6. Provides post-install instructions

### **Configuration Files**
- `~/.manifest-local/.env` - CLI configuration
- `/opt/homebrew/etc/manifest/` - System configuration
- Example files copied from repository

## 🧪 Testing

### **Local Testing**

```bash
# Test formula installation
brew install --build-from-source homebrew/manifest.rb

# Test CLI functionality
manifest --help
manifest diagnose

# Clean up test installation
brew uninstall manifest
```

### **Integration Testing**

```bash
# Test in a real repository
cd /tmp
git init
manifest help
manifest diagnose
```

## 🔧 Maintenance

### **Updating Dependencies**

```bash
# Update Node.js dependencies
cd Formula
npm update

# Update package.json versions
# Commit changes
git add package.json package-lock.json
git commit -m "Update Homebrew dependencies"
```

### **Formula Updates**

```bash
# Update formula for new version
./brew-release.sh

# Test changes
brew install --build-from-source homebrew/manifest.rb

# Commit and push
git add homebrew/
git commit -m "Update Homebrew formula"
git push origin main
```

## 🚨 Troubleshooting

### **Common Issues**

#### **Formula Won't Install**
```bash
# Check Homebrew status
brew doctor

# Update Homebrew
brew update

# Check formula syntax
brew audit --strict homebrew/manifest.rb
```

#### **CLI Won't Run**
```bash
# Check installation
brew list manifest

# Check permissions
ls -la /opt/homebrew/bin/manifest

# Reinstall
brew uninstall manifest && brew install manifest
```

#### **Dependencies Missing**
```bash
# Check Node.js
node --version

# Check Git
git --version

# Install missing dependencies
brew install node git
```

### **Debug Mode**

```bash
# Verbose installation
brew install -v homebrew/manifest.rb

# Check logs
brew log manifest

# Uninstall and reinstall
brew uninstall manifest
brew install homebrew/manifest.rb
```

## 📚 User Installation

### **Standard Installation**

```bash
# Install from GitHub
brew install fidenceio/manifest.local/manifest

# Verify installation
manifest --help
```

### **Development Installation**

```bash
# Install from local formula
brew install homebrew/manifest.rb

# Test functionality
manifest diagnose
```

### **Updating**

```bash
# Update Homebrew
brew update

# Upgrade Manifest CLI
brew upgrade manifest

# Check version
manifest --version
```

## 🔄 CI/CD Integration

### **GitHub Actions**

```yaml
name: Homebrew Release
on:
  push:
    tags:
      - 'v*'

jobs:
  homebrew:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Homebrew
        run: |
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      - name: Test Formula
        run: |
          brew install --build-from-source Formula/manifest.rb
          manifest --help
```

### **Automated Releases**

```bash
# Create release script
#!/bin/bash
VERSION=$1
git tag v$VERSION
git push origin v$VERSION
cd Formula
./brew-release.sh
```

## 📊 Monitoring

### **Installation Metrics**

```bash
# Check installation count
brew analytics

# View formula info
brew info manifest

# Check dependencies
brew deps manifest
```

### **User Feedback**

- GitHub Issues for bug reports
- GitHub Discussions for questions
- Homebrew analytics for usage data

## 🎯 Best Practices

### **Release Management**
1. **Semantic Versioning** - Follow semver for releases
2. **Git Tags** - Always create git tags for releases
3. **Testing** - Test formula before releasing
4. **Documentation** - Update docs with each release

### **Formula Maintenance**
1. **Dependencies** - Keep dependencies up to date
2. **Testing** - Test formula changes locally
3. **Validation** - Use `brew audit` to check formula
4. **Backwards Compatibility** - Maintain compatibility when possible

### **User Experience**
1. **Clear Installation** - Simple one-command install
2. **Automatic Setup** - Minimal user configuration required
3. **Helpful Errors** - Clear error messages and solutions
4. **Documentation** - Comprehensive usage guides

## 🔮 Future Enhancements

### **Planned Features**
- **Multi-platform Support** - Windows, Linux variants
- **Cask Support** - GUI application version
- **Tap Management** - Easy tap installation
- **Auto-updates** - Automatic dependency updates

### **Integration Ideas**
- **VS Code Extension** - Direct integration
- **JetBrains Plugin** - IDE integration
- **Docker Support** - Containerized installation
- **CI/CD Templates** - Ready-to-use workflows

## 📞 Support

### **Getting Help**
- **GitHub Issues**: [Report bugs](https://github.com/fidenceio/manifest.local/issues)
- **GitHub Discussions**: [Ask questions](https://github.com/fidenceio/manifest.local/discussions)
- **Documentation**: [Full docs](https://github.com/fidenceio/manifest.local#readme)

### **Contributing**
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

---

**Happy brewing! 🍺✨**
