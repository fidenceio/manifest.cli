#!/bin/bash

# Manifest CLI Test Module
# Provides comprehensive testing for all CLI functionality

# Test configuration
TEST_TIMEOUT=30
TEST_VERBOSE=false
MANIFEST_CLI_TEST_ISSUES_REPO="${MANIFEST_CLI_TEST_ISSUES_REPO:-fidenceio/fidenceio.manifest.cli}"

# Source the compatibility test modules
if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-zsh-compatibility-test.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-zsh-compatibility-test.sh"
fi

if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-bash4-compatibility-test.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-bash4-compatibility-test.sh"
fi

if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-fleet-test.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-fleet-test.sh"
fi

if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-yaml-test.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-yaml-test.sh"
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
        "time")
            test_time_functionality
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
        "cloud")
            echo "☁️  Testing Manifest Cloud MCP connectivity..."
            if declare -F test_mcp_connectivity >/dev/null 2>&1; then
                test_mcp_connectivity
            else
                echo "   ❌ Cloud test module not available"
                return 1
            fi
            ;;
        "agent")
            echo "🤖 Testing Manifest Agent functionality..."
            if declare -F test_agent >/dev/null 2>&1; then
                test_agent
            else
                echo "   ❌ Agent test module not available"
                return 1
            fi
            ;;
        "fleet")
            echo "🚢 Running fleet test suite..."
            if declare -F test_fleet >/dev/null 2>&1; then
                test_fleet
            else
                echo "   ❌ Fleet test module not available"
                return 1
            fi
            ;;
        "yaml"|"config-yaml")
            echo "📄 Running YAML & config test suite..."
            if declare -F test_yaml >/dev/null 2>&1; then
                test_yaml
            else
                echo "   ❌ YAML test module not available"
                return 1
            fi
            ;;
        "zsh")
            echo "🐚 Running zsh 5.9 compatibility tests..."
            run_zsh_compatibility_tests
            ;;
        "bash5")
            echo "🐍 Running bash 5+ compatibility tests..."
            run_bash4_compatibility_tests
            ;;
        "bash4")
            echo "ℹ️  'manifest test bash4' is deprecated; running bash 5+ suite."
            run_bash4_compatibility_tests
            ;;
        "bash")
            echo "🐍 Running bash compatibility tests..."
            local bash_version=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
            local major_version=$(echo "$bash_version" | cut -d'.' -f1)
            
            if [ "$major_version" -ge 5 ]; then
                echo "   Detected bash $bash_version - running bash 5+ tests..."
                run_bash4_compatibility_tests
            else
                echo "   Detected bash $bash_version - this project requires bash 5+."
                return 1
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

_manifest_test_logs_dir() {
    echo "$HOME/.manifest-cli/logs/tests"
}

_manifest_test_run_id() {
    date -u +"%Y%m%dT%H%M%SZ"
}

_manifest_test_sanitize_log() {
    local input_file="$1"
    local output_file="$2"
    local strict_redact="${3:-true}"

    if [ ! -f "$input_file" ]; then
        return 1
    fi

    sed -E \
        -e "s#${HOME}#~#g" \
        -e 's#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}#<redacted-email>#g' \
        -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+#\1<redacted-token>#gI' \
        -e 's#(MANIFEST_CLI_CLOUD_API_KEY=)[^[:space:]]+#\1<redacted>#g' \
        -e 's#(GH_TOKEN=|GITHUB_TOKEN=)[^[:space:]]+#\1<redacted>#g' \
        -e 's#(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]+#<redacted-github-token>#g' \
        -e 's#/Users/[^/[:space:]]+#/Users/<user>#g' \
        "$input_file" > "$output_file"

    if [ "$strict_redact" = "true" ]; then
        sed -E -i.bak \
            -e 's#([0-9]{1,3}\.){3}[0-9]{1,3}#<redacted-ip>#g' \
            -e 's#(https?://)github\.com/[^/[:space:]]+/[^/[:space:]]+#\1github.com/<redacted-org>/<redacted-repo>#g' \
            -e 's#([Hh]ostname:[[:space:]]*)[^[:space:]]+#\1<redacted-host>#g' \
            -e 's#([Uu]ser:[[:space:]]*)[^[:space:]]+#\1<redacted-user>#g' \
            "$output_file"
        rm -f "$output_file.bak"
    fi
}

_manifest_test_repo_slug() {
    local repo_url
    repo_url=$(git remote get-url origin 2>/dev/null || echo "")

    if [[ "$repo_url" =~ ^git@[^:]+:([^/]+)/([^/]+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "$repo_url" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    echo ""
    return 1
}

_manifest_test_create_issue_body() {
    local body_file="$1"
    local suite="$2"
    local run_id="$3"
    local sanitized_log="$4"
    local exit_code="$5"

    local repo_slug branch commit_sha cli_version
    repo_slug=$(_manifest_test_repo_slug || echo "unknown/unknown")
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    commit_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    cli_version=$(cat "$MANIFEST_CLI_VERSION_FILE" 2>/dev/null || echo "unknown")

    {
        echo "## Test Failure Report"
        echo ""
        echo "- **Command:** \`manifest test ${suite}\`"
        echo "- **Run ID:** \`${run_id}\`"
        echo "- **Exit Code:** \`${exit_code}\`"
        echo "- **Repository:** \`${repo_slug}\`"
        echo "- **Branch:** \`${branch}\`"
        echo "- **Commit:** \`${commit_sha}\`"
        echo "- **CLI Version:** \`${cli_version}\`"
        echo "- **Timestamp (UTC):** \`$(date -u +"%Y-%m-%d %H:%M:%S UTC")\`"
        echo ""
        echo "## Reproduction"
        echo ""
        echo '```bash'
        echo "manifest test ${suite}"
        echo '```'
        echo ""
        echo "## Sanitized Log (truncated)"
        echo ""
        echo '```text'
        sed -n '1,250p' "$sanitized_log"
        echo '```'
        echo ""
        echo "_Full sanitized log path on local machine: \`${sanitized_log}\`_"
    } > "$body_file"
}

_manifest_test_offer_issue_upload() {
    local suite="$1"
    local run_id="$2"
    local sanitized_log="$3"
    local exit_code="$4"

    if [ ! -t 0 ]; then
        return 0
    fi

    local upload_choice=""
    read -r -p "Create GitHub issue from sanitized test log? [y/N]: " upload_choice
    case "${upload_choice}" in
        y|Y|yes|YES)
            ;;
        *)
            return 0
            ;;
    esac

    if ! command -v gh >/dev/null 2>&1; then
        echo "⚠️  GitHub CLI ('gh') is not installed; cannot create issue."
        return 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "⚠️  GitHub CLI is not authenticated. Run: gh auth login"
        return 1
    fi

    local title body_file
    title="Test report: manifest test ${suite} (${run_id})"
    body_file="$(mktemp)"

    _manifest_test_create_issue_body "$body_file" "$suite" "$run_id" "$sanitized_log" "$exit_code"

    if gh issue create -R "$MANIFEST_CLI_TEST_ISSUES_REPO" --title "$title" --body-file "$body_file"; then
        echo "✅ GitHub issue created in ${MANIFEST_CLI_TEST_ISSUES_REPO} from sanitized log."
    else
        echo "❌ Failed to create GitHub issue."
        rm -f "$body_file"
        return 1
    fi

    rm -f "$body_file"
    return 0
}

run_manifest_test() {
    local suite=""
    local strict_redact="true"
    local passthrough_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strict-redact)
                strict_redact="true"
                shift
                ;;
            --no-strict-redact)
                strict_redact="false"
                shift
                ;;
            -h|--help)
                echo "Usage: manifest test [suite] [--strict-redact|--no-strict-redact]"
                echo ""
                echo "Suites include: all, versions, security, config, docs, git, time, os, modules,"
                echo "                integration, cloud, agent, fleet, yaml, zsh, bash5, bash (bash4 alias)"
                echo ""
                echo "Redaction:"
                echo "  --strict-redact     Enable strict redaction (default)"
                echo "  --no-strict-redact  Use basic redaction only"
                return 0
                ;;
            --*)
                passthrough_args+=("$1")
                shift
                ;;
            *)
                if [ -z "$suite" ]; then
                    suite="$1"
                else
                    passthrough_args+=("$1")
                fi
                shift
                ;;
        esac
    done

    suite="${suite:-all}"

    local run_id log_dir run_dir raw_log sanitized_log
    run_id=$(_manifest_test_run_id)
    log_dir=$(_manifest_test_logs_dir)
    run_dir="$log_dir/$run_id"
    raw_log="$run_dir/raw.log"
    sanitized_log="$run_dir/sanitized.log"

    mkdir -p "$run_dir"
    echo "🧾 Test run ID: $run_id"

    local test_exit=0
    if [ -t 1 ]; then
        set +e
        test_command "$suite" "${passthrough_args[@]}" 2>&1 | tee "$raw_log"
        test_exit=${PIPESTATUS[0]}
        set -e
    else
        set +e
        test_command "$suite" "${passthrough_args[@]}" > "$raw_log" 2>&1
        test_exit=$?
        set -e
        sed -n '1,$p' "$raw_log"
    fi

    if _manifest_test_sanitize_log "$raw_log" "$sanitized_log" "$strict_redact"; then
        echo ""
        echo "🗂️  Test logs saved:"
        echo "   raw:       $raw_log"
        echo "   sanitized: $sanitized_log"
        echo "   redaction: $( [ "$strict_redact" = "true" ] && echo "strict" || echo "basic" )"
    else
        echo "⚠️  Failed to generate sanitized test log."
    fi

    _manifest_test_offer_issue_upload "$suite" "$run_id" "$sanitized_log" "$test_exit" || true
    return "$test_exit"
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

# Test time functionality
test_time_functionality() {
    echo "🧪 Testing timestamp functionality..."

    # Check timestamp command availability
    if command -v curl >/dev/null 2>&1; then
        echo "   ✅ curl command available (HTTPS timestamps)"
    else
        echo "   ⚠️  curl not available (HTTPS timestamps require curl)"
    fi

    # Test timestamp command if available
    if command -v manifest >/dev/null 2>&1; then
        if manifest time >/dev/null 2>&1; then
            echo "   ✅ Timestamp service working"
        else
            echo "   ⚠️  Timestamp service had issues"
        fi
    fi

    echo "   ✅ Timestamp functionality testing completed"
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
    local required_modules=("core/manifest-core.sh" "core/manifest-config.sh" "git/manifest-git.sh" "docs/manifest-documentation.sh" "system/manifest-time.sh" "system/manifest-os.sh" "system/manifest-security.sh" "testing/manifest-test.sh")
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

    # Test default PR queue shorthand help exposure
    if echo "$help_output" | grep -q "pr \[options\].*shorthand\|pr queue.*auto-merge"; then
        echo "   ✅ PR shorthand/queue commands available"
    else
        echo "   ❌ PR shorthand/queue commands missing"
    fi

    # Test fleet PR queue shorthand help exposure
    local fleet_help_output
    fleet_help_output=$(manifest fleet --help 2>/dev/null)
    if echo "$fleet_help_output" | grep -q "fleet pr \[options\].*shorthand\|fleet pr queue"; then
        echo "   ✅ Fleet PR shorthand/queue commands available"
    else
        echo "   ❌ Fleet PR shorthand/queue commands missing"
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
    test_time_functionality
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

    if declare -F test_yaml >/dev/null 2>&1; then
        test_yaml
        echo ""
    fi

    if declare -F test_fleet >/dev/null 2>&1; then
        test_fleet
        echo ""
    fi

    echo "✅ Comprehensive testing completed"
}

# get_next_version() - Now available from manifest-shared-functions.sh
