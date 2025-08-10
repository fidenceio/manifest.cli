#!/bin/bash

# Manifest Cloud - Comprehensive Test Runner
# This script runs all test suites in the correct order

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}🧪 $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

print_section() {
    echo -e "\n${PURPLE}📋 $1${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

print_failure() {
    echo -e "${RED}❌ $1${NC}"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_result() {
    echo -e "\n${BLUE}📊 Test Report${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}📈 Overall Results:${NC}"
    echo -e "   Total Tests: ${TOTAL_TESTS}"
    echo -e "   Passed: ${PASSED_TESTS} ${GREEN}✅${NC}"
    echo -e "   Failed: ${FAILED_TESTS} ${RED}❌${NC}"
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        SUCCESS_RATE=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc -l)
        echo -e "   Success Rate: ${SUCCESS_RATE}%"
    fi
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All tests passed! The system is secure and fully functional.${NC}"
        exit 0
    else
        echo -e "\n${RED}⚠️  Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if we're in a container
    if [ -f /.dockerenv ]; then
        print_info "Running inside Docker container"
    else
        print_info "Running on host system"
    fi
    
    # Check Node.js
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node --version)
        print_success "Node.js found: $NODE_VERSION"
    else
        print_failure "Node.js not found"
        return 1
    fi
    
    # Check npm
    if command -v npm >/dev/null 2>&1; then
        NPM_VERSION=$(npm --version)
        print_success "npm found: $NPM_VERSION"
    else
        print_failure "npm not found"
        return 1
    fi
    
    # Check if tests directory exists
    if [ -d "tests" ]; then
        print_success "Tests directory found"
    else
        print_failure "Tests directory not found"
        return 1
    fi
    
    # Check if test files exist
    if [ -f "tests/security-test.js" ] && [ -f "tests/package-security-test.js" ] && [ -f "tests/core-functionality-test.js" ]; then
        print_success "All test files found"
    else
        print_failure "Some test files are missing"
        return 1
    fi
}

# Function to run security tests
run_security_tests() {
    print_section "Security Tests"
    
    if [ -f "tests/security-test.js" ]; then
        print_info "Running security tests..."
        if node tests/security-test.js; then
            print_success "Security Tests - PASSED"
        else
            print_failure "Security Tests - FAILED"
        fi
    else
        print_failure "Security test file not found"
    fi
}

# Function to run package security tests
run_package_security_tests() {
    print_section "Package Security Tests"
    
    if [ -f "tests/package-security-test.js" ]; then
        print_info "Running package security tests..."
        if node tests/package-security-test.js; then
            print_success "Package Security Tests - PASSED"
        else
            print_failure "Package Security Tests - FAILED"
        fi
    else
        print_failure "Package security test file not found"
    fi
}

# Function to run core functionality tests
run_core_functionality_tests() {
    print_section "Core Functionality Tests"
    
    if [ -f "tests/core-functionality-test.js" ]; then
        print_info "Running core functionality tests..."
        if node tests/core-functionality-test.js; then
            print_success "Core Functionality Tests - PASSED"
        else
            print_failure "Core Functionality Tests - FAILED"
        fi
    else
        print_failure "Core functionality test file not found"
    fi
}

# Function to run container-specific tests
run_container_tests() {
    print_section "Container Tests"
    
    # Test if we're running as non-root
    if [ "$(id -u)" -eq 0 ]; then
        print_failure "Running as root user (security risk)"
    else
        print_success "Running as non-root user"
    fi
    
    # Test if we have necessary tools
    if command -v git >/dev/null 2>&1; then
        print_success "Git available"
    else
        print_failure "Git not available"
    fi
    
    if command -v gh >/dev/null 2>&1; then
        print_success "GitHub CLI available"
    else
        print_failure "GitHub CLI not available"
    fi
    
    # Test if we can access SSH keys
    if [ -d "/root/.ssh" ] || [ -d "$HOME/.ssh" ]; then
        print_success "SSH directory accessible"
    else
        print_info "SSH directory not accessible (may be expected in test environment)"
    fi
}

# Function to run all tests
run_all_tests() {
    print_header "Running All Test Suites"
    
    # Run tests in order
    run_security_tests
    run_package_security_tests
    run_core_functionality_tests
    run_container_tests
    
    # Print final results
    print_result
}

# Function to show help
show_help() {
    echo -e "${BLUE}Manifest Cloud - Test Runner${NC}"
    echo -e "${CYAN}Usage: $0 [OPTION]${NC}"
    echo ""
    echo -e "${PURPLE}Options:${NC}"
    echo -e "  ${GREEN}all${NC}           Run all tests (default)"
    echo -e "  ${GREEN}security${NC}      Run security tests only"
    echo -e "  ${GREEN}packages${NC}      Run package security tests only"
    echo -e "  ${GREEN}functionality${NC} Run core functionality tests only"
    echo -e "  ${GREEN}container${NC}     Run container tests only"
    echo -e "  ${GREEN}check${NC}         Check prerequisites only"
    echo -e "  ${GREEN}help${NC}          Show this help message"
    echo ""
    echo -e "${PURPLE}Examples:${NC}"
    echo -e "  $0                    # Run all tests"
    echo -e "  $0 security           # Run security tests only"
    echo -e "  $0 check              # Check prerequisites"
    echo ""
}

# Main function
main() {
    case "${1:-all}" in
        "all")
            check_prerequisites
            run_all_tests
            ;;
        "security")
            check_prerequisites
            run_security_tests
            print_result
            ;;
        "packages")
            check_prerequisites
            run_package_security_tests
            print_result
            ;;
        "functionality")
            check_prerequisites
            run_core_functionality_tests
            print_result
            ;;
        "container")
            check_prerequisites
            run_container_tests
            print_result
            ;;
        "check")
            check_prerequisites
            print_info "Prerequisites check completed"
            ;;
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
