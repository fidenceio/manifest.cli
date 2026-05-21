#!/usr/bin/env bats

# Regression coverage for the OS-detection preamble: sourcing
# manifest-os.sh must be silent by default and only emit the
# 🔍/✅/🔧/🐍 banner under verbose/debug mode. Idempotency is also
# asserted so re-sourcing (or callers that invoke detect_os a second
# time) cannot reprint the banner.

load 'helpers/setup'

source_os_module() {
    # Run in a subshell so the MANIFEST_CLI_OS_DETECTED sentinel and
    # other globals do not bleed between tests.
    bash -c "
        set -e
        $1
        source \"$TEST_REPO_ROOT/modules/system/manifest-os.sh\"
        ${2:-true}
    "
}

@test "detect_os: silent by default" {
    run source_os_module "unset MANIFEST_CLI_VERBOSE; unset MANIFEST_CLI_DEBUG"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "detect_os: emits banner under MANIFEST_CLI_DEBUG=1" {
    run source_os_module "export MANIFEST_CLI_DEBUG=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detecting operating system"* ]]
    [[ "$output" == *"Detected:"* ]]
    [[ "$output" == *"Platform:"* ]]
    [[ "$output" == *"Bash:"* ]]
}

@test "detect_os: emits banner under MANIFEST_CLI_VERBOSE=1" {
    run source_os_module "export MANIFEST_CLI_VERBOSE=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detecting operating system"* ]]
}

@test "detect_os: idempotent — banner prints once across repeated calls" {
    run source_os_module \
        "export MANIFEST_CLI_DEBUG=1" \
        "detect_os; detect_os"
    [ "$status" -eq 0 ]
    # The banner phrase must appear exactly once even though detect_os
    # was invoked three times total (once via source, twice explicitly).
    local count
    count=$(echo "$output" | grep -c "Detecting operating system" || true)
    [ "$count" = "1" ]
}
