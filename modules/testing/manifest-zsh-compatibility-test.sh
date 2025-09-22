#!/bin/bash

# Manifest Zsh Compatibility Test Module
# Tests all critical CLI functionality with zsh 5.9

# Enable strict error handling for critical operations
set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test result tracking
declare -a FAILED_TESTS=()

# Test helper functions
test_start() {
    local test_name="$1"
    echo -e "${BLUE}🧪 Testing: $test_name${NC}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

test_pass() {
    local test_name="$1"
    echo -e "${GREEN}✅ PASS: $test_name${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    local test_name="$1"
    local error="$2"
    echo -e "${RED}❌ FAIL: $test_name${NC}"
    echo -e "${RED}   Error: $error${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name: $error")
}

# Test 1: Basic zsh environment detection
test_zsh_environment() {
    test_start "Zsh Environment Detection"
    
    if command -v zsh >/dev/null 2>&1; then
        local zsh_version=$(zsh --version 2>/dev/null | head -1)
        echo "   Zsh version: $zsh_version"
        test_pass "Zsh Environment Detection"
    else
        test_fail "Zsh Environment Detection" "Zsh not found"
    fi
}

# Test 2: Bash detection in zsh environment
test_bash_detection_in_zsh() {
    test_start "Bash Detection in Zsh Environment"
    
    # Run bash detection in zsh
    local result=$(zsh -c 'source modules/system/manifest-os.sh && echo "Bash: $MANIFEST_CLI_OS_BASH_VERSION, [[ ]]: $MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS, Arrays: $MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS"' 2>&1)
    
    if echo "$result" | grep -q "Bash:"; then
        echo "   Result: $result"
        test_pass "Bash Detection in Zsh Environment"
    else
        test_fail "Bash Detection in Zsh Environment" "Failed to detect bash: $result"
    fi
}

# Test 3: Conditional comparison functions
test_conditional_functions() {
    test_start "Conditional Comparison Functions"
    
    # Test each conditional function with appropriate arguments
    local test_cases=(
        "compare_strings 'test' '==' 'test'"
        "check_string_empty ''"
        "check_string_not_empty 'test'"
        "check_file_exists 'modules/system/manifest-os.sh'"
        "check_directory_exists 'modules'"
    )
    
    for test_case in "${test_cases[@]}"; do
        local func_name=$(echo "$test_case" | cut -d' ' -f1)
        local result=$(zsh -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && $test_case && echo 'PASS' || echo 'FAIL'" 2>&1)
        
        if echo "$result" | grep -q "PASS"; then
            echo "   ✅ $func_name: Working"
        else
            echo "   ❌ $func_name: Failed - $result"
            test_fail "Conditional Comparison Functions" "$func_name failed: $result"
            return 1
        fi
    done
    
    test_pass "Conditional Comparison Functions"
}

# Test 4: String comparison edge cases
test_string_comparisons() {
    test_start "String Comparison Edge Cases"
    
    # Test various string comparison scenarios
    local test_cases=(
        "compare_strings 'hello' '==' 'hello'"
        "compare_strings 'hello' '!=' 'world'"
        "check_string_empty ''"
        "check_string_not_empty 'hello'"
    )
    
    for test_case in "${test_cases[@]}"; do
        local result=$(zsh -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && $test_case && echo 'PASS' || echo 'FAIL'" 2>&1)
        
        if echo "$result" | grep -q "PASS"; then
            echo "   ✅ $test_case: Working"
        else
            echo "   ❌ $test_case: Failed - $result"
            test_fail "String Comparison Edge Cases" "$test_case failed: $result"
            return 1
        fi
    done
    
    test_pass "String Comparison Edge Cases"
}

# Test 5: File and directory checks
test_file_directory_checks() {
    test_start "File and Directory Checks"
    
    # Test file existence check
    local result1=$(zsh -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && check_file_exists 'modules/system/manifest-os.sh' && echo 'PASS' || echo 'FAIL'" 2>&1)
    
    # Test directory existence check
    local result2=$(zsh -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && check_directory_exists 'modules' && echo 'PASS' || echo 'FAIL'" 2>&1)
    
    if echo "$result1" | grep -q "PASS" && echo "$result2" | grep -q "PASS"; then
        echo "   ✅ File checks: Working"
        echo "   ✅ Directory checks: Working"
        test_pass "File and Directory Checks"
    else
        test_fail "File and Directory Checks" "File: $result1, Directory: $result2"
    fi
}

# Test 6: Core CLI commands
test_core_cli_commands() {
    test_start "Core CLI Commands"
    
    local commands=("--help" "ntp" "config" "test")
    
    for cmd in "${commands[@]}"; do
        local result=$(zsh -c "cd '$(pwd)' && manifest $cmd" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ] || [ $exit_code -eq 141 ]; then  # 141 is SIGPIPE, common with head commands
            echo "   ✅ manifest $cmd: Working (exit code: $exit_code)"
        else
            echo "   ❌ manifest $cmd: Failed (exit code: $exit_code)"
            test_fail "Core CLI Commands" "Command 'manifest $cmd' failed with exit code $exit_code"
            return 1
        fi
    done
    
    test_pass "Core CLI Commands"
}

# Test 7: Error handling
test_error_handling() {
    test_start "Error Handling"
    
    # Test invalid command - should show help message (user-friendly behavior)
    local result=$(zsh -c "cd '$(pwd)' && manifest invalidcommand" 2>&1)
    local exit_code=$?
    
    if echo "$result" | grep -q "Usage: manifest" && [ $exit_code -eq 0 ]; then
        echo "   ✅ Invalid command handling: Shows help message (user-friendly)"
        test_pass "Error Handling"
    else
        test_fail "Error Handling" "Invalid command should show help message but didn't"
    fi
}

# Test 8: Environment variable handling
test_environment_variables() {
    test_start "Environment Variable Handling"
    
    # Test environment variable detection and usage
    local result=$(zsh -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && echo \"OS: \$MANIFEST_CLI_OS_OS, Bash: \$MANIFEST_CLI_OS_BASH_VERSION\"" 2>&1)
    
    if echo "$result" | grep -q "OS:" && echo "$result" | grep -q "Bash:"; then
        echo "   Result: $result"
        test_pass "Environment Variable Handling"
    else
        test_fail "Environment Variable Handling" "Failed to handle environment variables: $result"
    fi
}

# Test 9: Module loading
test_module_loading() {
    test_start "Module Loading"
    
    # Test loading all critical modules
    local modules=("manifest-os.sh" "manifest-shared-utils.sh" "manifest-core.sh")
    
    for module in "${modules[@]}"; do
        local result=$(zsh -c "source modules/system/$module 2>&1 || source modules/core/$module 2>&1" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "   ✅ $module: Loaded successfully"
        else
            echo "   ❌ $module: Failed to load - $result"
            test_fail "Module Loading" "$module failed to load: $result"
            return 1
        fi
    done
    
    test_pass "Module Loading"
}

# Test 10: Cross-shell compatibility
test_cross_shell_compatibility() {
    test_start "Cross-Shell Compatibility"
    
    # Test that functions work the same in both bash and zsh
    local bash_result=$(bash -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && echo \"Bash: \$MANIFEST_CLI_OS_BASH_VERSION\"" 2>&1)
    local zsh_result=$(zsh -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && echo \"Bash: \$MANIFEST_CLI_OS_BASH_VERSION\"" 2>&1)
    
    if [ "$bash_result" = "$zsh_result" ]; then
        echo "   ✅ Consistent behavior between bash and zsh"
        test_pass "Cross-Shell Compatibility"
    else
        echo "   ❌ Inconsistent behavior:"
        echo "      Bash: $bash_result"
        echo "      Zsh: $zsh_result"
        test_fail "Cross-Shell Compatibility" "Inconsistent behavior between shells"
    fi
}

# Main test runner function (callable from other modules)
run_zsh_compatibility_tests() {
    echo "🐚 Zsh 5.9 Compatibility Test Suite"
    echo "===================================="
    echo ""
    
    # Run all tests
    test_zsh_environment
    test_bash_detection_in_zsh
    test_conditional_functions
    test_string_comparisons
    test_file_directory_checks
    test_core_cli_commands
    test_error_handling
    test_environment_variables
    test_module_loading
    test_cross_shell_compatibility
    
    # Summary
    echo ""
    echo "📊 Test Summary"
    echo "==============="
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo ""
        echo "❌ Failed Tests:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "   • $failed_test"
        done
        return 1
    else
        echo ""
        echo -e "${GREEN}🎉 All tests passed! Zsh 5.9 compatibility confirmed.${NC}"
        return 0
    fi
}

# Main function for direct execution
main() {
    run_zsh_compatibility_tests
    local exit_code=$?
    exit $exit_code
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
else
    # Script is being sourced - export the function
    export -f run_zsh_compatibility_tests
fi
