#!/bin/bash

# Manifest CLI Test Module
# Provides comprehensive testing for all CLI functionality

# Test configuration
TEST_TIMEOUT=30
TEST_VERBOSE=false

# Source the compatibility test modules
if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-zsh-compatibility-test.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-zsh-compatibility-test.sh"
fi

if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-bash32-compatibility-test.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-bash32-compatibility-test.sh"
fi

if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-bash4-compatibility-test.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-bash4-compatibility-test.sh"
fi

# Security testing functions
test_security_validation() {
    echo "🔒 Testing security validation functions..."
    
    # Test path validation
    echo "   Testing path validation..."
    if validate_file_path "valid/path/file.txt"; then
        echo "   ✅ Valid path accepted"
    else
        echo "   ❌ Valid path rejected"
        return 1
    fi
    
    if ! validate_file_path "../malicious/path"; then
        echo "   ✅ Path traversal attempt blocked"
    else
        echo "   ❌ Path traversal not blocked"
        return 1
    fi
    
    if ! validate_file_path "/etc/passwd"; then
        echo "   ✅ Absolute path outside project blocked"
    else
        echo "   ❌ Absolute path outside project allowed"
        return 1
    fi
    
    # Test input validation
    echo "   Testing input validation..."
    if validate_increment_type "patch"; then
        echo "   ✅ Valid increment type accepted"
    else
        echo "   ❌ Valid increment type rejected"
        return 1
    fi
    
    if ! validate_increment_type "malicious"; then
        echo "   ✅ Invalid increment type blocked"
    else
        echo "   ❌ Invalid increment type allowed"
        return 1
    fi
    
    if validate_version_selection "1" "5"; then
        echo "   ✅ Valid version selection accepted"
    else
        echo "   ❌ Valid version selection rejected"
        return 1
    fi
    
    if ! validate_version_selection "10" "5"; then
        echo "   ✅ Invalid version selection blocked"
    else
        echo "   ❌ Invalid version selection allowed"
        return 1
    fi
    
    echo "   ✅ Security validation tests passed"
    return 0
}

test_command_injection_protection() {
    echo "🛡️  Testing command injection protection..."
    
    # Test git_retry with malicious input
    echo "   Testing git command injection protection..."
    if ! git_retry "Test" "rm -rf /" 2>/dev/null; then
        echo "   ✅ Malicious git command blocked"
    else
        echo "   ❌ Malicious git command allowed"
        return 1
    fi
    
    if ! git_retry "Test" "ls; rm -rf /" 2>/dev/null; then
        echo "   ✅ Command chaining blocked"
    else
        echo "   ❌ Command chaining allowed"
        return 1
    fi
    
    if ! git_retry "Test" "echo 'test' | cat" 2>/dev/null; then
        echo "   ✅ Non-git command blocked"
    else
        echo "   ❌ Non-git command allowed"
        return 1
    fi
    
    echo "   ✅ Command injection protection tests passed"
    return 0
}

test_network_security() {
    echo "🌐 Testing network security..."
    
    # Test secure curl with invalid URL
    echo "   Testing URL validation..."
    if ! secure_curl_request "invalid-url" 5 2>/dev/null; then
        echo "   ✅ Invalid URL blocked"
    else
        echo "   ❌ Invalid URL allowed"
        return 1
    fi
    
    if ! secure_curl_request "ftp://example.com" 5 2>/dev/null; then
        echo "   ✅ Non-HTTPS URL blocked"
    else
        echo "   ❌ Non-HTTPS URL allowed"
        return 1
    fi
    
    echo "   ✅ Network security tests passed"
    return 0
}

# Test command dispatcher
test_command() {
    local test_type="$1"
    
    case "$test_type" in
        "versions")
            test_version_increments
            ;;
        "security")
            echo "🔒 Running security test suite..."
            test_security_validation
            test_command_injection_protection
            test_network_security
            echo "✅ Security tests completed"
            ;;
        "config")
            test_config_functionality
            ;;
        "docs")
            test_documentation_functionality
            ;;
        "git")
            test_git_functionality
            ;;
        "ntp")
            test_ntp_functionality
            ;;
        "os")
            test_os_functionality
            ;;
        "modules")
            test_module_loading
            ;;
        "integration")
            test_integration_workflows
            ;;
        "zsh")
            echo "🐚 Running zsh 5.9 compatibility tests..."
            run_zsh_compatibility_tests
            ;;
        "bash32")
            echo "🐍 Running bash 3.2 compatibility tests..."
            run_bash32_compatibility_tests
            ;;
        "bash4")
            echo "🐍 Running bash 4+ compatibility tests..."
            run_bash4_compatibility_tests
            ;;
        "bash")
            echo "🐍 Running bash compatibility tests..."
            local bash_version=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
            local major_version=$(echo "$bash_version" | cut -d'.' -f1)
            
            if [ "$major_version" -ge 4 ]; then
                echo "   Detected bash $bash_version - running bash 4+ tests..."
                run_bash4_compatibility_tests
            else
                echo "   Detected bash $bash_version - running bash 3.2 tests..."
                run_bash32_compatibility_tests
            fi
            ;;
        "all")
            test_all_functionality
            ;;
        *)
            echo "🧪 Running basic functionality tests..."
            test_all_functionality
            ;;
    esac
}

# Test version increment functionality
test_version_increments() {
    echo "🧪 Testing version increment functionality..."
    echo "   📋 Current version: $(cat "$MANIFEST_CLI_VERSION_FILE" 2>/dev/null || echo "unknown")"
    
    # Test each increment type
    local increment_types=("patch" "minor" "major" "revision")
    for increment_type in "${increment_types[@]}"; do
        echo "   🔄 Testing $increment_type increment..."
        local next_version=$(get_next_version "$increment_type")
        echo "      Would bump to: $next_version"
    done
    
    echo "   ✅ Version increment testing completed"
}

# Test security functionality
test_security_functionality() {
    echo "🧪 Testing security functionality..."
    
    # Test security command availability
    if command -v manifest >/dev/null 2>&1; then
        echo "   ✅ Security command available"
        
        # Test security command execution
        if manifest security >/dev/null 2>&1; then
            echo "   ✅ Security command execution successful"
        else
            echo "   ⚠️  Security command execution had issues"
        fi
    else
        echo "   ❌ Security command not available"
    fi
    
    echo "   ✅ Security functionality testing completed"
}

# Test configuration functionality
test_config_functionality() {
    echo "🧪 Testing configuration functionality..."
    
    # Test config command availability
    if command -v manifest >/dev/null 2>&1; then
        echo "   ✅ Config command available"
        
        # Test config command execution
        if manifest config >/dev/null 2>&1; then
            echo "   ✅ Config command execution successful"
        else
            echo "   ⚠️  Config command execution had issues"
        fi
    else
        echo "   ❌ Config command not available"
    fi
    
    echo "   ✅ Configuration functionality testing completed"
}

# Test documentation functionality
test_documentation_functionality() {
    echo "🧪 Testing documentation functionality..."
    
    # Check if documentation files exist
    local docs_dir=$(get_docs_folder)
    local doc_files=("$MANIFEST_CLI_README_FILE" "$(basename "$docs_dir")/USER_GUIDE.md" "$(basename "$docs_dir")/COMMAND_REFERENCE.md" "$(basename "$docs_dir")/INSTALLATION.md")
    for doc_file in "${doc_files[@]}"; do
        if [ -f "$doc_file" ]; then
            echo "   ✅ Documentation file exists: $doc_file"
        else
            echo "   ❌ Documentation file missing: $doc_file"
        fi
    done
    
    # Test docs command if available
    if command -v manifest >/dev/null 2>&1; then
        if manifest docs >/dev/null 2>&1; then
            echo "   ✅ Docs command execution successful"
        else
            echo "   ⚠️  Docs command execution had issues"
        fi
    fi
    
    echo "   ✅ Documentation functionality testing completed"
}

# Test Git functionality
test_git_functionality() {
    echo "🧪 Testing Git functionality..."
    
    # Check Git availability
    if command -v git >/dev/null 2>&1; then
        echo "   ✅ Git available: $(git --version)"
        
        # Check if we're in a Git repository
        if git rev-parse --git-dir >/dev/null 2>&1; then
            echo "   ✅ In Git repository"
            echo "   📍 Remote: $(git remote get-url origin 2>/dev/null || echo "none")"
            echo "   🏷️  Current branch: $(git branch --show-current)"
        else
            echo "   ⚠️  Not in a Git repository"
        fi
    else
        echo "   ❌ Git not available"
    fi
    
    echo "   ✅ Git functionality testing completed"
}

# Test NTP functionality
test_ntp_functionality() {
    echo "🧪 Testing NTP functionality..."
    
    # Check NTP command availability
    if command -v sntp >/dev/null 2>&1; then
        echo "   ✅ sntp command available"
    elif command -v ntpdate >/dev/null 2>&1; then
        echo "   ✅ ntpdate command available"
    else
        echo "   ⚠️  No NTP command available"
    fi
    
    # Test NTP command if available
    if command -v manifest >/dev/null 2>&1; then
        if manifest ntp >/dev/null 2>&1; then
            echo "   ✅ NTP command execution successful"
        else
            echo "   ⚠️  NTP command execution had issues"
        fi
    fi
    
    echo "   ✅ NTP functionality testing completed"
}

# Test OS functionality
test_os_functionality() {
    echo "🧪 Testing OS functionality..."
    
    # Detect OS
    local os_type=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macOS"
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        os_type="Cygwin"
    elif [[ "$OSTYPE" == "msys" ]]; then
        os_type="MSYS"
    elif [[ "$OSTYPE" == "win32" ]]; then
        os_type="Windows"
    else
        os_type="Unknown: $OSTYPE"
    fi
    
    echo "   🖥️  OS Type: $os_type"
    echo "   🐚 Shell: $SHELL"
    echo "   📍 Current directory: $(pwd)"
    
    echo "   ✅ OS functionality testing completed"
}

# Test module loading
test_module_loading() {
    echo "🧪 Testing module loading..."
    
    # Check if all required modules exist
    local required_modules=("core/manifest-core.sh" "core/manifest-config.sh" "git/manifest-git.sh" "docs/manifest-documentation.sh" "system/manifest-ntp.sh" "system/manifest-os.sh" "system/manifest-security.sh" "testing/manifest-test.sh")
    local modules_dir="modules"
    
    for module in "${required_modules[@]}"; do
        if [ -f "$modules_dir/$module" ]; then
            echo "   ✅ Module exists: $module"
        else
            echo "   ❌ Module missing: $module"
        fi
    done
    
    # Test module sourcing
    if [ -f "$modules_dir/core/manifest-core.sh" ]; then
        if source "$modules_dir/core/manifest-core.sh" >/dev/null 2>&1; then
            echo "   ✅ Core module sourcing successful"
        else
            echo "   ⚠️  Core module sourcing had issues"
        fi
    fi
    
    echo "   ✅ Module loading testing completed"
}

# Test integration workflows
test_integration_workflows() {
    echo "🧪 Testing integration workflows..."
    
    # Test basic workflow commands by checking if they exist in the help text
    local workflow_commands=("sync" "version" "commit" "cleanup")
    
    for cmd in "${workflow_commands[@]}"; do
        # Check if the command exists in the help text
        local help_output
        help_output=$(manifest --help 2>/dev/null)
        if echo "$help_output" | grep -q "$cmd"; then
            echo "   ✅ Workflow command available: $cmd"
        else
            echo "   ❌ Workflow command missing: $cmd"
        fi
    done
    
    # Test prep command
    local help_output
    help_output=$(manifest --help 2>/dev/null)
    if echo "$help_output" | grep -q "ship.*release command\|prep.*Prepare changes before shipping"; then
        echo "   ✅ Ship/prep workflow commands available"
    else
        echo "   ❌ Ship/prep workflow commands missing"
    fi
    
    echo "   ✅ Integration workflow testing completed"
}

# Test all functionality
test_all_functionality() {
    echo "🧪 Running comprehensive functionality tests..."
    
    # Test each component
    test_os_functionality
    echo ""
    test_git_functionality
    echo ""
    test_ntp_functionality
    echo ""
    test_module_loading
    echo ""
    test_integration_workflows
    echo ""
    test_documentation_functionality
    echo ""
    test_config_functionality
    echo ""
    test_security_validation
    test_command_injection_protection
    test_network_security
    echo ""
    
    echo "✅ Comprehensive testing completed"
}

# get_next_version() - Now available from manifest-shared-functions.sh
