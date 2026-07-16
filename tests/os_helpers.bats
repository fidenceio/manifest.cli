#!/usr/bin/env bats

# Unit coverage for manifest-os.sh helpers: bash-compat comparison wrappers,
# the timeout fallback, timezone display, and platform command dispatch.
# (The detect_os banner/idempotency contract lives in os_detection_preamble.bats.)

load 'helpers/setup'

setup() {
    load_modules system/manifest-os.sh
    SCRATCH="$(mk_scratch)"
    unset MANIFEST_CLI_TIMEZONE
}

teardown() {
    rm -rf "$SCRATCH"
}

@test "os: compare_strings handles ==, =, and != operators" {
    compare_strings "abc" "==" "abc"
    compare_strings "abc" "=" "abc"
    compare_strings "abc" "!=" "abd"
    run compare_strings "abc" "==" "abd"
    [ "$status" -eq 1 ]
    run compare_strings "abc" "!=" "abc"
    [ "$status" -eq 1 ]
}

@test "os: compare_strings rejects unsupported operators with status 2" {
    run compare_strings "1" "-lt" "2"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unsupported operator '-lt'"* ]]
}

@test "os: check_string_empty distinguishes empty from non-empty" {
    check_string_empty ""
    run check_string_empty "non-empty"
    [ "$status" -eq 1 ]
}

@test "os: check_string_empty legacy single-bracket branch behaves identically" {
    MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS=false
    check_string_empty ""
    run check_string_empty "non-empty"
    [ "$status" -eq 1 ]
}

@test "os: check_directory_exists true for dirs, false for files and missing paths" {
    check_directory_exists "$SCRATCH"
    touch "$SCRATCH/a-file"
    run check_directory_exists "$SCRATCH/a-file"
    [ "$status" -eq 1 ]
    run check_directory_exists "$SCRATCH/does-not-exist"
    [ "$status" -eq 1 ]
}

@test "os: timeout_fallback returns 0 when the command completes before the deadline" {
    run timeout_fallback 1 true
    [ "$status" -eq 0 ]
}

@test "os: timeout_fallback kills an overrunning command and returns 124" {
    run timeout_fallback 1 sleep 10
    [ "$status" -eq 124 ]
}

@test "os: get_timezone_display returns UTC by default" {
    run get_timezone_display 1700000000
    [ "$status" -eq 0 ]
    [ "$output" = "UTC" ]
}

@test "os: get_timezone_display resolves a named timezone abbreviation" {
    export MANIFEST_CLI_TIMEZONE="America/New_York"
    # 1700000000 = 2023-11-14, after the DST switch: New York shows EST.
    run get_timezone_display 1700000000
    [ "$status" -eq 0 ]
    [ "$output" = "EST" ]
}

@test "os: setup_linux_commands selects GNU date form and plain timeout" {
    setup_linux_commands
    [ "$MANIFEST_CLI_OS_DATE_CMD" = "date -u -d" ]
    [ "$MANIFEST_CLI_OS_TIMEOUT_CMD" = "timeout" ]
    [ "$MANIFEST_CLI_OS_GREP_CMD" = "grep" ]
    [ "$MANIFEST_CLI_OS_SED_CMD" = "sed" ]
}

@test "os: setup_macos_commands selects GNU date form and gtimeout-or-fallback" {
    local expected="timeout_fallback"
    command -v gtimeout >/dev/null 2>&1 && expected="gtimeout"
    setup_macos_commands > "$SCRATCH/macos-setup.out"
    [ "$MANIFEST_CLI_OS_DATE_CMD" = "date -u -d" ]
    [ "$MANIFEST_CLI_OS_TIMEOUT_CMD" = "$expected" ]
    if [ "$expected" = "timeout_fallback" ]; then
        grep -q "gtimeout not found" "$SCRATCH/macos-setup.out"
    fi
}

@test "os: detect_os dispatches Linux command setup under a stubbed uname" {
    mkdir -p "$SCRATCH/bin"
    cat > "$SCRATCH/bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -r) echo "6.1.0-test" ;;
    *)  echo "Linux" ;;
esac
EOF
    chmod +x "$SCRATCH/bin/uname"
    run bash -c "
        export PATH=\"$SCRATCH/bin:\$PATH\"
        unset MANIFEST_CLI_OS_DETECTED MANIFEST_CLI_VERBOSE MANIFEST_CLI_DEBUG
        source \"$TEST_REPO_ROOT/modules/system/manifest-os.sh\"
        echo \"os=\$MANIFEST_CLI_OS_OS family=\$MANIFEST_CLI_OS_FAMILY version=\$MANIFEST_CLI_OS_VERSION\"
        echo \"timeout=\$MANIFEST_CLI_OS_TIMEOUT_CMD date=\$MANIFEST_CLI_OS_DATE_CMD\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"os=Linux family=unix version=6.1.0-test"* ]]
    [[ "$output" == *"timeout=timeout date=date -u -d"* ]]
}
