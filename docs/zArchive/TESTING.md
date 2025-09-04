# 🧪 Testing Guide

## Overview

Manifest CLI includes comprehensive testing capabilities to ensure all functionality works correctly across different environments and use cases.

## 🚀 **Quick Start Testing**

### **Basic Test**
```bash
manifest test
```

### **Comprehensive Test**
```bash
manifest test all
```

### **Specific Component Tests**
```bash
manifest test versions      # Test version increment logic
manifest test security      # Test security functionality
manifest test config        # Test configuration functionality
manifest test docs          # Test documentation functionality
manifest test git           # Test Git functionality
manifest test ntp           # Test NTP functionality
manifest test os            # Test OS detection
manifest test modules       # Test module loading
manifest test integration   # Test workflow integration
```

## 📋 **Test Coverage Matrix**

| Component | Test Command | Coverage | Status |
|-----------|--------------|----------|---------|
| **Core CLI** | `manifest test` | Basic functionality | ✅ Complete |
| **Versioning** | `manifest test versions` | Increment logic | ✅ Complete |
| **Security** | `manifest test security` | Security commands | ✅ Complete |
| **Configuration** | `manifest test config` | Config management | ✅ Complete |
| **Documentation** | `manifest test docs` | Doc generation | ✅ Complete |
| **Git Operations** | `manifest test git` | Git functionality | ✅ Complete |
| **NTP Services** | `manifest test ntp` | Timestamp services | ✅ Complete |
| **OS Detection** | `manifest test os` | Platform detection | ✅ Complete |
| **Module Loading** | `manifest test modules` | Module system | ✅ Complete |
| **Integration** | `manifest test integration` | Workflow commands | ✅ Complete |
| **Comprehensive** | `manifest test all` | All components | ✅ Complete |

## 🔍 **Detailed Test Descriptions**

### **1. Version Increment Testing (`manifest test versions`)**

**What it tests:**
- Patch increment logic (rightmost component)
- Minor increment logic (middle component)
- Major increment logic (leftmost component)
- Revision increment logic (new component)

**Example output:**
```bash
🧪 Testing version increment functionality...
   📋 Current version: 12.0.1
   🔄 Testing patch increment...
      Would bump to: 12.0.2
   🔄 Testing minor increment...
      Would bump to: 12.1.0
   🔄 Testing major increment...
      Would bump to: 13.0.0
   🔄 Testing revision increment...
      Would bump to: 12.0.1.1
   ✅ Version increment testing completed
```

### **2. Security Testing (`manifest test security`)**

**What it tests:**
- Security command availability
- Security command execution
- Security module functionality

**Example output:**
```bash
🧪 Testing security functionality...
   ✅ Security command available
   ✅ Security command execution successful
   ✅ Security functionality testing completed
```

### **3. Configuration Testing (`manifest test config`)**

**What it tests:**
- Configuration command availability
- Configuration command execution
- Environment variable loading

**Example output:**
```bash
🧪 Testing configuration functionality...
   ✅ Config command available
   ✅ Config command execution successful
   ✅ Configuration functionality testing completed
```

### **4. Documentation Testing (`manifest test docs`)**

**What it tests:**
- Documentation file existence
- Documentation command execution
- Documentation generation

**Example output:**
```bash
🧪 Testing documentation functionality...
   ✅ Documentation file exists: README.md
   ✅ Documentation file exists: docs/USER_GUIDE.md
   ✅ Documentation file exists: docs/COMMAND_REFERENCE.md
   ✅ Documentation file exists: docs/INSTALLATION.md
   ✅ Docs command execution successful
   ✅ Documentation functionality testing completed
```

### **5. Git Testing (`manifest test git`)**

**What it tests:**
- Git command availability
- Git repository status
- Remote configuration
- Current branch

**Example output:**
```bash
🧪 Testing Git functionality...
   ✅ Git available: git version 2.39.5 (Apple Git-154)
   ✅ In Git repository
   📍 Remote: git@github.com:fidenceio/manifest.cli.git
   🏷️  Current branch: main
   ✅ Git functionality testing completed
```

### **6. NTP Testing (`manifest test ntp`)**

**What it tests:**
- NTP command availability (sntp, ntpdate)
- NTP command execution
- Timestamp services

**Example output:**
```bash
🧪 Testing NTP functionality...
   ✅ sntp command available
   ✅ NTP command execution successful
   ✅ NTP functionality testing completed
```

### **7. OS Testing (`manifest test os`)**

**What it tests:**
- Operating system detection
- Shell environment
- Current working directory

**Example output:**
```bash
🧪 Testing OS functionality...
   🖥️  OS Type: macOS
   🐚 Shell: /bin/zsh
   📍 Current directory: /Users/william/coderepos/fidenceio.manifest.cli
   ✅ OS functionality testing completed
```

### **8. Module Testing (`manifest test modules`)**

**What it tests:**
- Required module existence
- Module sourcing capability
- Module system integrity

**Example output:**
```bash
🧪 Testing module loading...
   ✅ Module exists: manifest-core.sh
   ✅ Module exists: manifest-config.sh
   ✅ Module exists: manifest-git.sh
   ✅ Module exists: manifest-docs.sh
   ✅ Module exists: manifest-ntp.sh
   ✅ Module exists: manifest-os.sh
   ✅ Module exists: manifest-security.sh
   ✅ Module exists: manifest-test.sh
   ✅ Core module sourcing successful
   ✅ Module loading testing completed
```

### **9. Integration Testing (`manifest test integration`)**

**What it tests:**
- Workflow command availability
- Command integration
- Workflow completeness

**Example output:**
```bash
🧪 Testing integration workflows...
   ✅ Workflow command available: sync
   ✅ Workflow command available: version
   ✅ Workflow command available: commit
   ✅ Workflow command available: push
   ✅ Workflow command available: cleanup
   ✅ Go workflow command available
   ✅ Integration workflow testing completed
```

## 🧪 **Running Tests**

### **Individual Tests**
```bash
# Test specific functionality
manifest test versions
manifest test security
manifest test config

# Test multiple components
manifest test git
manifest test ntp
manifest test os
```

### **Comprehensive Testing**
```bash
# Run all tests
manifest test all

# This will test:
# 1. OS functionality
# 2. Git functionality
# 3. NTP functionality
# 4. Module loading
# 5. Integration workflows
# 6. Documentation functionality
# 7. Configuration functionality
# 8. Security functionality
```

## 🔧 **Test Configuration**

### **Environment Variables**
```bash
# Test timeout (seconds)
TEST_TIMEOUT=30

# Verbose output
TEST_VERBOSE=false
```

### **Test Directories**
```bash
# Module directory
src/cli/modules/

# Test files
src/cli/modules/manifest-test.sh
```

## 📊 **Test Results Interpretation**

### **✅ Success Indicators**
- All required components available
- Commands execute successfully
- Files and modules exist
- Functionality works as expected

### **⚠️ Warning Indicators**
- Some components missing (non-critical)
- Commands execute with minor issues
- Optional functionality unavailable

### **❌ Error Indicators**
- Critical components missing
- Commands fail to execute
- Core functionality broken

## 🚨 **Troubleshooting Test Failures**

### **Common Issues**

#### **1. Command Not Found**
```bash
❌ manifest command not available
```
**Solution:** Install the CLI using `./install-cli.sh`

#### **2. Git Repository Issues**
```bash
❌ Not in a Git repository
```
**Solution:** Navigate to a Git repository or initialize one

#### **3. Module Loading Failures**
```bash
❌ Module missing: manifest-core.sh
```
**Solution:** Check module file existence and permissions

#### **4. Permission Issues**
```bash
❌ Permission denied
```
**Solution:** Check file permissions and ownership

### **Debug Mode**
```bash
# Enable verbose output
export TEST_VERBOSE=true
manifest test all

# Check specific module
ls -la src/cli/modules/
```

## 📈 **Continuous Testing**

### **Pre-commit Testing**
```bash
# Run tests before committing
manifest test all

# Only proceed if all tests pass
if [ $? -eq 0 ]; then
    git add .
    git commit -m "Your changes"
else
    echo "Tests failed, fix issues before committing"
fi
```

### **CI/CD Integration**
```bash
# GitHub Actions example
- name: Run Manifest CLI Tests
  run: |
    ./install-cli.sh
    manifest test all
```

## 🎯 **Testing Best Practices**

### **1. Regular Testing**
- Run `manifest test all` before major changes
- Test individual components during development
- Verify functionality after updates

### **2. Environment Testing**
- Test on different operating systems
- Test with different Git configurations
- Test with various environment variables

### **3. Edge Case Testing**
- Test with missing files
- Test with corrupted configurations
- Test with network issues

### **4. Integration Testing**
- Test complete workflows
- Test command combinations
- Test error handling

## 📚 **Related Documentation**

- **[User Guide](USER_GUIDE.md)** - General CLI usage
- **[Command Reference](COMMAND_REFERENCE.md)** - All available commands
- **[Security Guide](SECURITY.md)** - Security testing and validation
- **[Configuration Guide](CONFIG_VS_SECURITY.md)** - Config vs security distinction

## 🎉 **Test Success Criteria**

A successful test run should show:
- ✅ All core functionality working
- ✅ All modules loading correctly
- ✅ All commands executing properly
- ✅ No critical errors
- ✅ Minimal warnings (acceptable for optional features)

Remember: **Testing is not just about finding bugs, it's about ensuring reliability and confidence in your CLI tool!**
