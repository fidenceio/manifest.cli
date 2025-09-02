#!/bin/bash

# Manifest CLI Security Module
# Provides security auditing and privacy protection

# Security configuration
SECURITY_CONFIG_FILE="manifest.config"
PRIVATE_ENV_FILES=(".env" ".env.local" ".env.development" ".env.test" ".env.production" ".env.staging")

# Main security audit function
manifest_security() {
    local project_root=""
    
    # Detect project root
    if [ -f "VERSION" ] && [ -f "env.example" ]; then
        project_root="$(pwd)"
    elif [ -f "../VERSION" ] && [ -f "../env.example" ]; then
        project_root="$(cd .. && pwd)"
    else
        echo "❌ Could not determine project root. Please run from project directory."
        return 1
    fi
    
    echo "🔒 Manifest CLI Security Audit"
    echo "=============================="
    echo ""
    
    # Run security checks
    local critical_issues=0
    local warnings=0
    
    echo "🚨 Security Vulnerability Check:"
    echo "================================"
    
    # Check Git tracking of private files
    if check_git_tracking "$project_root"; then
        echo "   ✅ No private files are being tracked by Git"
    else
        echo "   ❌ CRITICAL: Private files are tracked by Git!"
        critical_issues=$((critical_issues + 1))
    fi
    
    # Check for actual sensitive data (not just patterns)
    if check_actual_sensitive_data "$project_root"; then
        echo "   ✅ No actual sensitive data found in public files"
    else
        echo "   ❌ CRITICAL: Actual sensitive data found in public files!"
        critical_issues=$((critical_issues + 1))
    fi
    
    # Check recent commits
    if check_recent_secret_commits "$project_root"; then
        echo "   ✅ No recent commits contain sensitive data"
    else
        echo "   ❌ CRITICAL: Recent commits contain sensitive data!"
        critical_issues=$((critical_issues + 1))
    fi
    
    echo ""
    echo "🛡️  Privacy Protection Check:"
    echo "=============================="
    
    # Check for actual PII (not just example patterns)
    if check_actual_pii "$project_root"; then
        echo "   ✅ No actual PII detected in code"
    else
        echo "   ⚠️  WARNING: Actual PII detected in code"
        warnings=$((warnings + 1))
    fi
    
    # Check for actual hardcoded credentials
    if check_actual_credentials "$project_root"; then
        echo "   ✅ No actual hardcoded credentials detected"
    else
        echo "   ❌ CRITICAL: Actual hardcoded credentials detected!"
        critical_issues=$((critical_issues + 1))
    fi
    
    # Check environment file security
    if check_environment_file_security "$project_root"; then
        echo "   ✅ Environment files are properly secured"
    else
        echo "   ❌ CRITICAL: Environment files not properly secured!"
        critical_issues=$((critical_issues + 1))
    fi
    
    echo ""
    
    # Summary
    if [ $critical_issues -eq 0 ] && [ $warnings -eq 0 ]; then
        echo "✅ Security audit passed with no issues."
        return 0
    elif [ $critical_issues -eq 0 ]; then
        echo "⚠️  Security audit passed with $warnings warning(s)."
        return 0
    else
        echo "❌ Security audit failed with $critical_issues critical issue(s) and $warnings warning(s)."
        echo ""
        echo "🚨 IMMEDIATE ACTION REQUIRED:"
        echo "   1. Fix critical security issues before committing any code"
        echo "   2. Review and remove any exposed sensitive data"
        echo "   3. Ensure private files are not tracked by Git"
        echo "   4. Run 'manifest security' again after fixes"
        return 1
    fi
}

# Check if private files are tracked by Git (CRITICAL)
check_git_tracking() {
    local project_root="$1"
    
    # Only check if we're in a Git repository
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "      ⚠️  Not in a Git repository, skipping Git tracking checks"
        return 0
    fi
    
    # Check if any private files are tracked
    for env_file in "${PRIVATE_ENV_FILES[@]}"; do
        if [ -f "$project_root/$env_file" ]; then
            if git -C "$project_root" ls-files "$env_file" >/dev/null 2>&1; then
                echo "      ❌ $env_file is tracked by Git (SECURITY RISK!)"
                return 1
            fi
        fi
    done
    
    return 0
}

# Check for actual sensitive data (CRITICAL)
check_actual_sensitive_data() {
    local project_root="$1"
    
    # Look for actual sensitive data patterns, not just variable names
    local actual_sensitive_patterns=(
        "password.*=.*['\"][^'\"]*['\"]"           # password = "actual_value"
        "secret.*=.*['\"][^'\"]*['\"]"             # secret = "actual_value"
        "api_key.*=.*['\"][^'\"]*['\"]"            # api_key = "actual_value"
        "private_key.*=.*['\"][^'\"]*['\"]"        # private_key = "actual_value"
        "database_url.*=.*['\"][^'\"]*['\"]"       # database_url = "actual_value"
        "aws_access.*=.*['\"][^'\"]*['\"]"         # aws_access = "actual_value"
        "github_token.*=.*['\"][^'\"]*['\"]"       # github_token = "actual_value"
        "access_token.*=.*['\"][^'\"]*['\"]"       # access_token = "actual_value"
        "bearer_token.*=.*['\"][^'\"]*['\"]"       # bearer_token = "actual_value"
        "jwt_token.*=.*['\"][^'\"]*['\"]"          # jwt_token = "actual_value"
    )
    
    local found_sensitive=0
    
    for pattern in "${actual_sensitive_patterns[@]}"; do
        local matches=$(grep -r "$pattern" "$project_root" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude-dir=docs \
            --exclude="*.env*" \
            --exclude="manifest.config" \
            --exclude="*.md" \
            --exclude="*.txt" \
            --exclude="*.rst" \
            --exclude="*.html" \
            --exclude="*.css" \
            --exclude="*.js" \
            --exclude="*.json" \
            --exclude="*.xml" \
            --exclude="*.yaml" \
            --exclude="*.yml" \
            --exclude="env.example" \
            --exclude="env.examples.md" \
            --exclude="SECURITY.md" \
            --exclude="CONFIG_VS_SECURITY.md" \
            --exclude="HUMAN_INTUITIVE_VERSIONING.md" \
            --exclude="TESTING.md" \
            --exclude="README.md" \
            --exclude="USER_GUIDE.md" \
            --exclude="COMMAND_REFERENCE.md" \
            --exclude="INSTALLATION.md" \
            --exclude="CONTRIBUTING.md" \
            --exclude="EXAMPLES.md" \
            --exclude="manifest-security.sh" \
            --exclude="manifest-config.sh" \
            2>/dev/null | grep -v "password.*=.*['\"]example['\"]" | grep -v "secret.*=.*['\"]example['\"]" | wc -l)
        
        if [ "$matches" -gt 0 ]; then
            echo "      ⚠️  Potential sensitive data pattern found: $pattern"
            found_sensitive=$((found_sensitive + 1))
        fi
    done
    
    [ $found_sensitive -eq 0 ]
}

# Check recent commits for sensitive data (CRITICAL)
check_recent_secret_commits() {
    local project_root="$1"
    
    # Only check if we're in a Git repository
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "      ⚠️  Not in a Git repository, skipping commit analysis"
        return 0
    fi
    
    # Check last 10 commits for actual sensitive data
    local actual_sensitive_patterns=("password.*=.*['\"][^'\"]*['\"]" "secret.*=.*['\"][^'\"]*['\"]" "api_key.*=.*['\"][^'\"]*['\"]")
    local secret_commits=0
    
    for pattern in "${actual_sensitive_patterns[@]}"; do
        local matches=$(git -C "$project_root" log -p -10 | grep -i "$pattern" | grep -v "password.*=.*['\"]example['\"]" | grep -v "secret.*=.*['\"]example['\"]" | wc -l)
        if [ "$matches" -gt 0 ]; then
            echo "      ❌ Recent commits contain pattern '$pattern' (may contain secrets!)"
            secret_commits=$((secret_commits + 1))
        fi
    done
    
    [ $secret_commits -eq 0 ]
}

# Check for actual PII (WARNING)
check_actual_pii() {
    local project_root="$1"
    
    # Look for actual PII patterns, not just example patterns
    local actual_pii_patterns=(
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"  # Real email patterns
        "[0-9]{3}-[0-9]{3}-[0-9]{4}"                      # Real phone patterns
        "[0-9]+ [A-Za-z ]+ [A-Za-z]+"                      # Real address patterns
    )
    
    local pii_found=0
    
    for pattern in "${actual_pii_patterns[@]}"; do
        local matches=$(grep -r "$pattern" "$project_root" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude-dir=docs \
            --exclude="*.env*" \
            --exclude="manifest.config" \
            --exclude="*.md" \
            --exclude="*.txt" \
            --exclude="*.rst" \
            --exclude="*.html" \
            --exclude="*.css" \
            --exclude="*.js" \
            --exclude="*.json" \
            --exclude="*.xml" \
            --exclude="*.yaml" \
            --exclude="*.yml" \
            --exclude="env.example" \
            --exclude="env.examples.md" \
            --exclude="SECURITY.md" \
            --exclude="CONFIG_VS_SECURITY.md" \
            --exclude="HUMAN_INTUITIVE_VERSIONING.md" \
            --exclude="TESTING.md" \
            --exclude="README.md" \
            --exclude="USER_GUIDE.md" \
            --exclude="COMMAND_REFERENCE.md" \
            --exclude="INSTALLATION.md" \
            --exclude="CONTRIBUTING.md" \
            --exclude="EXAMPLES.md" \
            --exclude="manifest-security.sh" \
            --exclude="manifest-config.sh" \
            2>/dev/null | grep -v "john.doe@example.com" | grep -v "jane.smith@company.com" | grep -v "555-123-4567" | grep -v "123 Main St" | grep -v "admin@localhost" | wc -l)
        
        if [ "$matches" -gt 0 ]; then
            echo "      ⚠️  Potential actual PII pattern found: $pattern"
            pii_found=$((pii_found + 1))
        fi
    done
    
    [ $pii_found -eq 0 ]
}

# Check for actual hardcoded credentials (CRITICAL)
check_actual_credentials() {
    local project_root="$1"
    
    # Look for actual credential assignments, not just variable names
    local actual_credential_patterns=(
        "password.*=.*['\"][^'\"]*['\"]"     # password = "actual_value"
        "secret.*=.*['\"][^'\"]*['\"]"       # secret = "actual_value"
        "api_key.*=.*['\"][^'\"]*['\"]"      # api_key = "actual_value"
        "token.*=.*['\"][^'\"]*['\"]"        # token = "actual_value"
    )
    
    local credentials_found=0
    
    for pattern in "${actual_credential_patterns[@]}"; do
        local matches=$(grep -r "$pattern" "$project_root" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude-dir=docs \
            --exclude="*.env*" \
            --exclude="manifest.config" \
            --exclude="*.md" \
            --exclude="*.txt" \
            --exclude="*.rst" \
            --exclude="*.html" \
            --exclude="*.css" \
            --exclude="*.js" \
            --exclude="*.json" \
            --exclude="*.xml" \
            --exclude="*.yaml" \
            --exclude="*.yml" \
            --exclude="env.example" \
            --exclude="env.examples.md" \
            --exclude="SECURITY.md" \
            --exclude="CONFIG_VS_SECURITY.md" \
            --exclude="HUMAN_INTUITIVE_VERSIONING.md" \
            --exclude="TESTING.md" \
            --exclude="README.md" \
            --exclude="USER_GUIDE.md" \
            --exclude="COMMAND_REFERENCE.md" \
            --exclude="INSTALLATION.md" \
            --exclude="CONTRIBUTING.md" \
            --exclude="EXAMPLES.md" \
            --exclude="manifest-security.sh" \
            --exclude="manifest-config.sh" \
            2>/dev/null | grep -v "password.*=.*['\"]example['\"]" | grep -v "secret.*=.*['\"]example['\"]" | grep -v "api_key.*=.*['\"]example['\"]" | grep -v "token.*=.*['\"]example['\"]" | wc -l)
        
        if [ "$matches" -gt 0 ]; then
            echo "      ❌ Actual hardcoded credentials pattern found: $pattern"
            credentials_found=$((credentials_found + 1))
        fi
    done
    
    [ $credentials_found -eq 0 ]
}

# Check environment file security (CRITICAL)
check_environment_file_security() {
    local project_root="$1"
    
    # Only check if we're in a Git repository
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "      ⚠️  Not in a Git repository, skipping Git ignore checks"
        return 0
    fi
    
    # Check if .env files exist and are properly ignored
    local security_issues=0
    
    for env_file in "${PRIVATE_ENV_FILES[@]}"; do
        if [ -f "$project_root/$env_file" ]; then
            # Check if file is properly ignored by Git
            if ! git -C "$project_root" check-ignore "$env_file" >/dev/null 2>&1; then
                echo "      ❌ $env_file exists but is NOT ignored by Git (SECURITY RISK!)"
                security_issues=$((security_issues + 1))
            fi
        fi
    done
    
    [ $security_issues -eq 0 ]
}
