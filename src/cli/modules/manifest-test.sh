#!/bin/bash

# Manifest CLI Test Module
# Provides comprehensive testing for all CLI functionality

# Test configuration
TEST_TIMEOUT=30
TEST_VERBOSE=false

# Test command dispatcher
test_command() {
    local test_type="$1"
    
    case "$test_type" in
        "versions")
            test_version_increments
            ;;
        "security")
            test_security_functionality
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
        "all"|*)
            test_all_functionality
            ;;
    esac
}

# Test version increment functionality
test_version_increments() {
    echo "🧪 Testing version increment functionality..."
    echo "   📋 Current version: $(cat VERSION 2>/dev/null || echo "unknown")"
    
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
    local doc_files=("README.md" "docs/USER_GUIDE.md" "docs/COMMAND_REFERENCE.md" "docs/INSTALLATION.md")
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
    local required_modules=("manifest-core.sh" "manifest-config.sh" "manifest-git.sh" "manifest-documentation.sh" "manifest-ntp.sh" "manifest-os.sh" "manifest-security.sh" "manifest-test.sh")
    local modules_dir="src/cli/modules"
    
    for module in "${required_modules[@]}"; do
        if [ -f "$modules_dir/$module" ]; then
            echo "   ✅ Module exists: $module"
        else
            echo "   ❌ Module missing: $module"
        fi
    done
    
    # Test module sourcing
    if [ -f "$modules_dir/manifest-core.sh" ]; then
        if source "$modules_dir/manifest-core.sh" >/dev/null 2>&1; then
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
    
    # Test basic workflow commands
    local workflow_commands=("sync" "version" "commit" "push" "cleanup")
    
    for cmd in "${workflow_commands[@]}"; do
        if command -v manifest >/dev/null 2>&1; then
            if manifest help | grep -q "$cmd"; then
                echo "   ✅ Workflow command available: $cmd"
            else
                echo "   ❌ Workflow command missing: $cmd"
            fi
        fi
    done
    
    # Test go command
    if command -v manifest >/dev/null 2>&1; then
        if manifest help | grep -q "go.*workflow"; then
            echo "   ✅ Go workflow command available"
        else
            echo "   ❌ Go workflow command missing"
        fi
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
    test_security_functionality
    echo ""
    
    echo "✅ Comprehensive testing completed"
}

# Get next version for testing
get_next_version() {
    local increment_type="$1"
    local current_version=$(cat VERSION 2>/dev/null || echo "1.0.0")
    
    case "$increment_type" in
        "patch")
            echo "$current_version" | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g'
            ;;
        "minor")
            echo "$current_version" | awk -F. '{$2 = $2 + 1; $3 = 0;} 1' | sed 's/ /./g'
            ;;
        "major")
            echo "$current_version" | awk -F. '{print $1 + 1 ".0.0"}'
            ;;
        "revision")
            echo "$current_version.1"
            ;;
        *)
            echo "$current_version"
            ;;
    esac
}
