#!/bin/bash

# Manifest Bash 4+ Compatibility Test Module
# Tests all critical CLI functionality with bash 4.0+

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

# Test 1: Bash 4+ environment detection
test_bash4_environment() {
    test_start "Bash 4+ Environment Detection"
    
    local bash_version=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
    local major_version=$(echo "$bash_version" | cut -d'.' -f1)
    local minor_version=$(echo "$bash_version" | cut -d'.' -f2)
    
    echo "   Bash version: $bash_version"
    
    if [ "$major_version" -ge 4 ]; then
        test_pass "Bash 4+ Environment Detection"
    else
        test_fail "Bash 4+ Environment Detection" "Expected bash 4.0+, got $bash_version"
    fi
}

# Test 2: Bash 4+ capability detection
test_bash4_capabilities() {
    test_start "Bash 4+ Capability Detection"
    
    # Test double bracket support (should be true for bash 4+)
    local result=$(bash -c 'source modules/system/manifest-os.sh >/dev/null 2>&1 && echo "[[ ]]: $MANIFEST_BASH_SUPPORTS_DOUBLE_BRACKETS, Arrays: $MANIFEST_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS"' 2>&1)
    
    if echo "$result" | grep -q "\[\[ \]\]: true" && echo "$result" | grep -q "Arrays: true"; then
        echo "   Result: $result"
        test_pass "Bash 4+ Capability Detection"
    else
        test_fail "Bash 4+ Capability Detection" "Incorrect capability detection: $result"
    fi
}

# Test 3: Conditional functions with bash 4+
test_conditional_functions_bash4() {
    test_start "Conditional Functions with Bash 4+"
    
    # Test each conditional function
    local test_cases=(
        "compare_strings 'test' '==' 'test'"
        "check_string_empty ''"
        "check_string_not_empty 'test'"
        "check_file_exists 'modules/system/manifest-os.sh'"
        "check_directory_exists 'modules'"
    )
    
    for test_case in "${test_cases[@]}"; do
        local func_name=$(echo "$test_case" | cut -d' ' -f1)
        local result=$(bash -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && $test_case && echo 'PASS' || echo 'FAIL'" 2>&1)
        
        if echo "$result" | grep -q "PASS"; then
            echo "   ✅ $func_name: Working"
        else
            echo "   ❌ $func_name: Failed - $result"
            test_fail "Conditional Functions with Bash 4+" "$func_name failed: $result"
            return 1
        fi
    done
    
    test_pass "Conditional Functions with Bash 4+"
}

# Test 4: String comparison edge cases with bash 4+
test_string_comparisons_bash4() {
    test_start "String Comparison Edge Cases with Bash 4+"
    
    # Test various string comparison scenarios
    local test_cases=(
        "compare_strings 'hello' '==' 'hello'"
        "compare_strings 'hello' '!=' 'world'"
        "check_string_empty ''"
        "check_string_not_empty 'hello'"
    )
    
    for test_case in "${test_cases[@]}"; do
        local result=$(bash -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && $test_case && echo 'PASS' || echo 'FAIL'" 2>&1)
        
        if echo "$result" | grep -q "PASS"; then
            echo "   ✅ $test_case: Working"
        else
            echo "   ❌ $test_case: Failed - $result"
            test_fail "String Comparison Edge Cases with Bash 4+" "$test_case failed: $result"
            return 1
        fi
    done
    
    test_pass "String Comparison Edge Cases with Bash 4+"
}

# Test 5: File and directory checks with bash 4+
test_file_directory_checks_bash4() {
    test_start "File and Directory Checks with Bash 4+"
    
    # Test file existence check
    local result1=$(bash -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && check_file_exists 'modules/system/manifest-os.sh' && echo 'PASS' || echo 'FAIL'" 2>&1)
    
    # Test directory existence check
    local result2=$(bash -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && check_directory_exists 'modules' && echo 'PASS' || echo 'FAIL'" 2>&1)
    
    if echo "$result1" | grep -q "PASS" && echo "$result2" | grep -q "PASS"; then
        echo "   ✅ File checks: Working"
        echo "   ✅ Directory checks: Working"
        test_pass "File and Directory Checks with Bash 4+"
    else
        test_fail "File and Directory Checks with Bash 4+" "File: $result1, Directory: $result2"
    fi
}

# Test 6: Core CLI commands with bash 4+
test_core_cli_commands_bash4() {
    test_start "Core CLI Commands with Bash 4+"
    
    local commands=("--help" "ntp" "config" "test")
    
    for cmd in "${commands[@]}"; do
        local result=$(bash -c "cd '$(pwd)' && manifest $cmd" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ] || [ $exit_code -eq 141 ]; then  # 141 is SIGPIPE, common with head commands
            echo "   ✅ manifest $cmd: Working (exit code: $exit_code)"
        else
            echo "   ❌ manifest $cmd: Failed (exit code: $exit_code)"
            test_fail "Core CLI Commands with Bash 4+" "Command 'manifest $cmd' failed with exit code $exit_code"
            return 1
        fi
    done
    
    test_pass "Core CLI Commands with Bash 4+"
}

# Test 7: Error handling with bash 4+
test_error_handling_bash4() {
    test_start "Error Handling with Bash 4+"
    
    # Test invalid command - should show help message (user-friendly behavior)
    local result=$(bash -c "cd '$(pwd)' && manifest invalidcommand" 2>&1)
    local exit_code=$?
    
    if echo "$result" | grep -q "Usage: manifest" && [ $exit_code -eq 0 ]; then
        echo "   ✅ Invalid command handling: Shows help message (user-friendly)"
        test_pass "Error Handling with Bash 4+"
    else
        test_fail "Error Handling with Bash 4+" "Invalid command should show help message but didn't"
    fi
}

# Test 8: Environment variable handling with bash 4+
test_environment_variables_bash4() {
    test_start "Environment Variable Handling with Bash 4+"
    
    # Test environment variable detection and usage
    local result=$(bash -c "source modules/system/manifest-os.sh >/dev/null 2>&1 && echo \"OS: \$MANIFEST_OS, Bash: \$MANIFEST_BASH_VERSION\"" 2>&1)
    
    if echo "$result" | grep -q "OS:" && echo "$result" | grep -q "Bash:"; then
        echo "   Result: $result"
        test_pass "Environment Variable Handling with Bash 4+"
    else
        test_fail "Environment Variable Handling with Bash 4+" "Failed to handle environment variables: $result"
    fi
}

# Test 9: Module loading with bash 4+
test_module_loading_bash4() {
    test_start "Module Loading with Bash 4+"
    
    # Test loading all critical modules
    local modules=("manifest-os.sh" "manifest-shared-utils.sh" "manifest-core.sh")
    
    for module in "${modules[@]}"; do
        local result=$(bash -c "source modules/system/$module 2>&1 || source modules/core/$module 2>&1" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "   ✅ $module: Loaded successfully"
        else
            echo "   ❌ $module: Failed to load - $result"
            test_fail "Module Loading with Bash 4+" "$module failed to load: $result"
            return 1
        fi
    done
    
    test_pass "Module Loading with Bash 4+"
}

# Test 10: Bash 4+ specific features
test_bash4_specific_features() {
    test_start "Bash 4+ Specific Features"
    
    # Test associative arrays (bash 4+ feature)
    local result=$(bash -c 'declare -A test_array; test_array[key]="value"; echo "${test_array[key]}"' 2>&1)
    
    if echo "$result" | grep -q "value"; then
        echo "   ✅ Associative arrays: Working"
    else
        echo "   ❌ Associative arrays: Failed - $result"
        test_fail "Bash 4+ Specific Features" "Associative arrays failed: $result"
        return 1
    fi
    
    # Test advanced parameter expansion
    local result2=$(bash -c 'test_var="hello world"; echo "${test_var^^}"' 2>&1)
    
    if echo "$result2" | grep -q "HELLO WORLD"; then
        echo "   ✅ Advanced parameter expansion: Working"
    else
        echo "   ❌ Advanced parameter expansion: Failed - $result2"
        test_fail "Bash 4+ Specific Features" "Advanced parameter expansion failed: $result2"
        return 1
    fi
    
    test_pass "Bash 4+ Specific Features"
}

# Test 11: Modern bash syntax compatibility
test_modern_bash_syntax() {
    test_start "Modern Bash Syntax Compatibility"
    
    # Test that we can use modern bash features when available
    local syntax_tests=(
        "[[ 'hello' == 'hello' ]]"
        "[[ 'hello' != 'world' ]]"
        "[[ -n 'hello' ]]"
        "[[ -z '' ]]"
    )
    
    for syntax_test in "${syntax_tests[@]}"; do
        local result=$(bash -c "$syntax_test && echo 'PASS' || echo 'FAIL'" 2>&1)
        
        if echo "$result" | grep -q "PASS"; then
            echo "   ✅ $syntax_test: Working"
        else
            echo "   ❌ $syntax_test: Failed - $result"
            test_fail "Modern Bash Syntax Compatibility" "$syntax_test failed: $result"
            return 1
        fi
    done
    
    test_pass "Modern Bash Syntax Compatibility"
}

# Main test runner function (callable from other modules)
run_bash4_compatibility_tests() {
    echo "🐍 Bash 4+ Compatibility Test Suite"
    echo "===================================="
    echo ""
    
    # Run all tests
    test_bash4_environment
    test_bash4_capabilities
    test_conditional_functions_bash4
    test_string_comparisons_bash4
    test_file_directory_checks_bash4
    test_core_cli_commands_bash4
    test_error_handling_bash4
    test_environment_variables_bash4
    test_module_loading_bash4
    test_bash4_specific_features
    test_modern_bash_syntax
    
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
        echo -e "${GREEN}🎉 All tests passed! Bash 4+ compatibility confirmed.${NC}"
        return 0
    fi
}

# Main function for direct execution
main() {
    run_bash4_compatibility_tests
    local exit_code=$?
    exit $exit_code
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
else
    # Script is being sourced - export the function
    export -f run_bash4_compatibility_tests
fi
