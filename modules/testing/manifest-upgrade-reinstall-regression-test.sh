#!/bin/bash

# Manifest Upgrade/Reinstall Regression Test Harness
# Safe by default: runs non-destructive upgrade checks.
# Destructive operations (reinstall) require explicit opt-in.

set -uo pipefail

MANIFEST_BIN="${MANIFEST_BIN:-manifest}"
ALLOW_DESTRUCTIVE="false"
VERBOSE="false"
KEEP_LOGS="false"
LOG_DIR="${MANIFEST_CLI_REGRESSION_LOG_DIR:-$HOME/.manifest-cli/logs/regression}"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

usage() {
    echo "Manifest Upgrade/Reinstall Regression Test Harness"
    echo "=================================================="
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --manifest-bin <path|command>  Manifest binary or script path (default: manifest)"
    echo "  --allow-destructive            Enable reinstall test (destructive)"
    echo "  --verbose                      Print full command output for each test"
    echo "  --keep-logs                    Keep per-test logs in $LOG_DIR"
    echo "  -h, --help                     Show this help"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --manifest-bin /path/to/scripts/manifest-cli.sh"
    echo "  $0 --allow-destructive --verbose"
}

log_info() {
    echo "ℹ️  $*"
}

log_ok() {
    echo "✅ $*"
}

log_warn() {
    echo "⚠️  $*"
}

log_err() {
    echo "❌ $*"
}

manifest_exec() {
    if [ -f "$MANIFEST_BIN" ]; then
        bash "$MANIFEST_BIN" "$@"
    else
        "$MANIFEST_BIN" "$@"
    fi
}

resolve_manifest_binary() {
    if [ -f "$MANIFEST_BIN" ]; then
        return 0
    fi
    if command -v "$MANIFEST_BIN" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

run_test() {
    local test_name="$1"
    shift
    local log_file="$LOG_DIR/${test_name// /_}.log"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "🧪 Test: $test_name"

    mkdir -p "$LOG_DIR"

    if "$@" >"$log_file" 2>&1; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_ok "$test_name"
        if [ "$VERBOSE" = "true" ]; then
            sed -n '1,200p' "$log_file"
        fi
        if [ "$KEEP_LOGS" = "false" ]; then
            rm -f "$log_file"
        fi
        return 0
    fi

    FAILED_TESTS=$((FAILED_TESTS + 1))
    log_err "$test_name"
    echo "   Command failed. Output:"
    sed -n '1,200p' "$log_file"
    if [ "$KEEP_LOGS" = "false" ]; then
        rm -f "$log_file"
    fi
    return 1
}

skip_test() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    echo ""
    echo "⏭️  Test: $test_name"
    log_warn "Skipped"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manifest-bin)
                MANIFEST_BIN="${2:-}"
                shift 2
                ;;
            --allow-destructive)
                ALLOW_DESTRUCTIVE="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --keep-logs)
                KEEP_LOGS="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    echo "🔍 Manifest regression test harness"
    echo "   manifest bin:       $MANIFEST_BIN"
    echo "   destructive tests:  $ALLOW_DESTRUCTIVE"
    echo "   verbose:            $VERBOSE"
    echo "   keep logs:          $KEEP_LOGS"
    echo ""

    if ! resolve_manifest_binary; then
        log_err "Manifest binary not found: $MANIFEST_BIN"
        return 1
    fi

    run_test "upgrade_help" manifest_exec upgrade --help
    run_test "upgrade_check" manifest_exec upgrade --check
    run_test "upgrade_default" manifest_exec upgrade

    if [ "$ALLOW_DESTRUCTIVE" = "true" ]; then
        run_test "reinstall" manifest_exec reinstall
    else
        skip_test "reinstall (requires --allow-destructive)"
    fi

    echo ""
    echo "📊 Regression test summary"
    echo "   total:   $TOTAL_TESTS"
    echo "   passed:  $PASSED_TESTS"
    echo "   failed:  $FAILED_TESTS"
    echo "   skipped: $SKIPPED_TESTS"

    if [ "$FAILED_TESTS" -gt 0 ]; then
        return 1
    fi
    return 0
}

main "$@"
