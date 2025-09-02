# ⚙️ Configuration vs 🔒 Security: Understanding the Difference

## Overview

Manifest CLI has two distinct commands that serve very different purposes. Understanding when to use each one is crucial for effective CLI usage.

## 🔧 **`manifest config` - Configuration Management**

### **Purpose**
Show your current environment variables and settings for the Manifest CLI.

### **What It Does**
- Displays all current `MANIFEST_*` environment variables
- Shows versioning configuration (format, separator, components)
- Lists branch naming conventions
- Displays Git configuration (remotes, tags, strategies)
- Explains how the human-intuitive versioning system works

### **When to Use**
- **"What are my current settings?"**
- **"How is Manifest configured?"**
- **"What versioning format am I using?"**
- **"What branch naming conventions are set?"**

### **Example Output**
```bash
$ manifest config

🔧 Manifest CLI Configuration
==============================

📋 Versioning Configuration:
   Format: XX.XX.XX
   Separator: .
   Components: major,minor,patch

🧠 Human-Intuitive Component Mapping:
   Major Position: 1 (leftmost = biggest impact)
   Minor Position: 2 (middle = moderate impact)
   Patch Position: 3 (rightmost = least impact)
```

## 🔒 **`manifest security` - Security Audit**

### **Purpose**
Check your repository for security vulnerabilities and privacy risks.

### **What It Does**
- Scans for private files being tracked by Git (CRITICAL)
- Detects sensitive data patterns in public files (CRITICAL)
- Checks recent commits for potential secrets (CRITICAL)
- Identifies PII exposure in code (WARNING)
- Finds hardcoded credentials (CRITICAL)
- Validates environment file security (CRITICAL)

### **When to Use**
- **"Am I about to expose sensitive data?"**
- **"Is my repository secure?"**
- **"Did I accidentally commit secrets?"**
- **"Are my private files protected?"**

### **Example Output**
```bash
$ manifest security

🔒 Manifest CLI Security Audit
==============================

🚨 Security Vulnerability Check:
================================
   ✅ No private files are being tracked by Git
   ❌ CRITICAL: Sensitive data may be exposed in public files!
   ✅ No recent commits contain sensitive data

🛡️  Privacy Protection Check:
==============================
   ⚠️  WARNING: Potential PII detected in code
   ❌ CRITICAL: Hardcoded credentials detected!
   ✅ Environment files are properly secured
```

## 📊 **Command Comparison Matrix**

| Aspect | `manifest config` | `manifest security` |
|--------|-------------------|---------------------|
| **Purpose** | Show current settings | Detect security risks |
| **Focus** | Configuration values | Security vulnerabilities |
| **Risk Level** | Information only | Critical security alerts |
| **Use Case** | Daily configuration | Pre-commit security check |
| **Output** | Current settings | Security status + alerts |

## 🎯 **When to Use Each Command**

### **Use `manifest config` when:**
- ✅ Setting up a new project
- ✅ Checking your current configuration
- ✅ Understanding how versioning works
- ✅ Verifying branch naming conventions
- ✅ Debugging configuration issues

### **Use `manifest security` when:**
- 🚨 Before committing code
- 🚨 After pulling from remote
- 🚨 When adding new files
- 🚨 Before pushing to public repositories
- 🚨 Regular security audits

## 🔄 **Typical Workflow**

```bash
# 1. Check your configuration
manifest config

# 2. Make changes to your code

# 3. Security audit before commit
manifest security

# 4. If security passes, commit your code
git add .
git commit -m "Your changes"

# 5. If security fails, fix issues first!
```

## 🚨 **Security Command Priority**

The `manifest security` command uses a clear priority system:

- **🔴 CRITICAL**: Must fix before proceeding
- **🟡 WARNING**: Should review and address
- **🟢 SAFE**: No issues detected

## 💡 **Best Practices**

### **Configuration Management**
- Use `manifest config` to understand your setup
- Customize settings via `.env` file
- Keep `env.example` updated for team members

### **Security Auditing**
- Run `manifest security` before every commit
- Fix critical issues immediately
- Address warnings promptly
- Make security checks part of your workflow

## 🔍 **Troubleshooting**

### **Config Issues**
```bash
# Check current configuration
manifest config

# Verify environment variables
echo $MANIFEST_VERSION_FORMAT
```

### **Security Issues**
```bash
# Run security audit
manifest security

# Fix critical issues first
git rm --cached .env  # if private file is tracked

# Re-run security check
manifest security
```

## 📚 **Related Documentation**

- **[Configuration Examples](env.examples.md)** - Real-world configuration examples
- **[Security Guide](SECURITY.md)** - Comprehensive security documentation
- **[Human-Intuitive Versioning](HUMAN_INTUITIVE_VERSIONING.md)** - Versioning system explanation

## 🎯 **Summary**

- **`manifest config`** = "What are my settings?" (Configuration Management)
- **`manifest security`** = "Am I secure?" (Security Audit)

Both commands are essential but serve completely different purposes. Use `config` for daily configuration management and `security` for protecting your repository from vulnerabilities and privacy risks.
