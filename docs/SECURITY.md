# 🔒 Security Guide

## Overview

Manifest CLI includes comprehensive security features to protect your repository from security vulnerabilities and privacy risks.

## 🚨 **Critical Security Features**

### 1. **Private File Protection**
- **`.env` files are NEVER uploaded to GitHub**
- **`.gitignore` automatically excludes all private environment files**
- **Git tracking validation prevents accidental commits**

### 2. **Security Vulnerability Detection**
- **Sensitive data exposure scanning**
- **PII (Personally Identifiable Information) detection**
- **Hardcoded credentials identification**
- **Recent commit security analysis**

### 3. **Security Command**
- **`manifest security` - Comprehensive security audit**
- **Real-time vulnerability detection**
- **Immediate alerts for security issues**

## 🔍 **Security Commands**

### **`manifest security`**
Run a comprehensive security audit:

```bash
manifest security
```

**What it checks:**
- ✅ Private files being tracked by Git (CRITICAL)
- ✅ Sensitive data in public files (CRITICAL)
- ✅ Recent commits containing secrets (CRITICAL)
- ✅ PII exposure in code (WARNING)
- ✅ Hardcoded credentials (CRITICAL)
- ✅ Environment file security (CRITICAL)

## 📁 **File Security Matrix**

| File Type | Purpose | Git Tracked | Security Level |
|-----------|---------|-------------|----------------|
| `.env` | **PRIVATE** - Your personal config | ❌ NEVER | 🔴 Critical |
| `.env.local` | **PRIVATE** - Local overrides | ❌ NEVER | 🔴 Critical |
| `.env.*` | **PRIVATE** - Environment-specific | ❌ NEVER | 🔴 Critical |
| `env.example` | **PUBLIC** - Community template | ✅ YES | 🟢 Safe |
| `manifest.config` | **INTERNAL** - CLI configuration | ❌ NEVER | 🟡 Internal |
| `.gitignore` | **PUBLIC** - Security rules | ✅ YES | 🟢 Safe |

## 🛡️ **Security Best Practices**

### **1. Never Commit Private Files**
```bash
# ❌ WRONG - This will expose your secrets!
git add .env
git commit -m "Add configuration"

# ✅ CORRECT - Use env.example instead
cp env.example .env
# Edit .env with your private values
# .env is automatically ignored by Git
```

### **2. Use Environment-Specific Files**
```bash
# Development
.env.development

# Production  
.env.production

# Testing
.env.test

# Local overrides (highest priority)
.env.local
```

### **3. Regular Security Audits**
```bash
# Run security check before commits
manifest security

# Check Git tracking status
git status

# Verify .gitignore is working
git check-ignore .env
```

## 🔧 **Configuration vs Security**

### **`manifest config` - Configuration Management**
- **Purpose**: Show current environment variables and settings
- **Scope**: Versioning, Git remotes, branch naming, documentation patterns
- **Use Case**: "What are my current settings?" / "How is Manifest configured?"

### **`manifest security` - Security & Privacy Protection**  
- **Purpose**: Check for security vulnerabilities and privacy risks
- **Scope**: PII exposure, private file leaks, accidental secret commits
- **Use Case**: "Am I about to expose sensitive data?" / "Is my repo secure?"

## 🚨 **Security Alerts**

### **Critical Issues**
- ❌ Private `.env` file being tracked by Git
- ❌ Sensitive data patterns in public files
- ❌ Recent commits contain potential secrets
- ❌ Hardcoded credentials detected
- ❌ Environment files not properly secured

### **Warnings**
- ⚠️ Potential PII detected in code
- ⚠️ Multiple `.env` files causing conflicts
- ⚠️ Old `.manifestrc` files detected

## 🔍 **Troubleshooting Security Issues**

### **Issue: Private file is being tracked by Git**
```bash
# Remove from Git tracking (keeps local file)
git rm --cached .env

# Verify it's now ignored
git status

# Run security check
manifest security
```

### **Issue: .gitignore not working**
```bash
# Check .gitignore syntax
cat .gitignore

# Verify patterns are correct
git check-ignore .env

# Re-run security check
manifest security
```

### **Issue: Sensitive data detected**
```bash
# Search for sensitive patterns
grep -r "password" . --exclude-dir=.git

# Remove or secure sensitive data
# Use environment variables instead

# Re-run security check
manifest security
```

## 📋 **Security Checklist**

Before committing code, ensure:

- [ ] `.env` files are NOT being tracked by Git
- [ ] `.gitignore` properly excludes private files
- [ ] No sensitive data in public files
- [ ] No hardcoded credentials
- [ ] No PII in code
- [ ] `manifest security` command passes all checks

## 🆘 **Emergency Security Response**

If you accidentally commit a private file:

```bash
# 1. Remove from Git tracking immediately
git rm --cached .env

# 2. Add to .gitignore
echo ".env" >> .gitignore

# 3. Commit the fix
git add .gitignore
git commit -m "SECURITY: Add .env to .gitignore"

# 4. Run security check
manifest security

# 5. Consider rotating any exposed secrets
```

## 🔐 **Advanced Security Features**

### **Automatic Security Validation**
- Runs before major operations
- Prevents insecure configurations
- Real-time threat detection

### **Pattern-Based Detection**
- Sensitive data pattern scanning
- PII pattern recognition
- Credential pattern identification

### **Git History Analysis**
- Recent commit security review
- Secret exposure detection
- Historical vulnerability scanning

## 📞 **Security Support**

If you encounter security issues:

1. **Run `manifest security`** for immediate diagnosis
2. **Check the troubleshooting section** above
3. **Review security best practices** in this guide
4. **Open a security issue** on GitHub if needed

## 🎯 **Security Goals**

- **Zero private file exposure** ✅
- **Zero sensitive data leaks** ✅  
- **Zero PII exposure** ✅
- **Zero hardcoded credentials** ✅
- **Real-time vulnerability detection** ✅

Remember: **Security is everyone's responsibility**. Use `manifest security` regularly to ensure your repository remains secure!
