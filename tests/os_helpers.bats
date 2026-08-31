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

# The former "legacy single-bracket branch behaves identically" test is gone with
# the branch it exercised. It set MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS
# to false by hand to reach an arm the Bash 5+ runtime floor made unreachable —
# so the only thing keeping the dead code alive was a test falsifying a variable
# that could not be false in production. Its assertion was also self-defeating:
# it asserted the two arms behave identically, which is the argument for having
# one arm.
@test "os: the removed bash capability flags stay removed" {
    # A flag that can hold only one value invites callers to branch on it. This
    # asserts the module exposes no such probe, so the dead-branch pattern
    # cannot quietly return.
    #
    # `declare -p <name>`, not `set | grep <name>`. The first version grepped
    # `set` output and failed, because `set` prints BASH_EXECUTION_STRING — which
    # contains the grep's own pattern. The probe matched itself and reported the
    # variable as present. Asking about one name at a time cannot self-match.
    local flag
    for flag in MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS \
                MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS; do
        run bash -c "source '$TEST_REPO_ROOT/modules/system/manifest-os.sh' >/dev/null 2>&1; \
                     declare -p $flag >/dev/null 2>&1 && echo SET || echo UNSET"
        [ "$output" = "UNSET" ]
    done

    # Control, and it is load-bearing: the same probe must report SET for a
    # variable the module DOES still define, otherwise UNSET above would also be
    # what a failed source, a typo, or a broken `declare` looks like.
    run bash -c "source '$TEST_REPO_ROOT/modules/system/manifest-os.sh' >/dev/null 2>&1; \
                 declare -p MANIFEST_CLI_OS_BASH_MAJOR >/dev/null 2>&1 && echo SET || echo UNSET"
    [ "$output" = "SET" ]
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
    # Requires tzdata in the test image (see run-tests.Dockerfile). Missing
    # zoneinfo fails this assertion honestly — do not skip.
    # 1700000000 = 2023-11-14, after DST → EST.
    run get_timezone_display 1700000000
    [ "$status" -eq 0 ]
    [ "$output" = "EST" ]
}

@test "os: get_timezone_display falls back to IANA name when zoneinfo is missing" {
    export MANIFEST_CLI_TIMEZONE="Fake/NoSuchZone"
    run get_timezone_display 1700000000
    [ "$status" -eq 0 ]
    # Must not invent a short abbreviation (e.g. UTC / path fragment) when the
    # zone database entry is absent — surface the configured IANA name instead.
    [ "$output" = "Fake/NoSuchZone" ]
}

@test "os: get_timezone_display rejects path-traversal timezone values" {
    export MANIFEST_CLI_TIMEZONE="../../etc/passwd"
    run get_timezone_display 1700000000
    [ "$status" -eq 0 ]
    # Must not probe the filesystem via ..; echo the raw value unchanged.
    [ "$output" = "../../etc/passwd" ]
}

@test "os: setup_linux_commands selects GNU date form and plain timeout" {
    setup_linux_commands
    [ "$MANIFEST_CLI_OS_DATE_CMD" = "date -u -d" ]
    [ "$MANIFEST_CLI_OS_TIMEOUT_CMD" = "timeout" ]
    [ "$MANIFEST_CLI_OS_GREP_CMD" = "grep" ]
    [ "$MANIFEST_CLI_OS_SED_CMD" = "sed" ]
}

# Both macOS branches are pinned by constructing the PATH each one needs. The
# earlier single test derived its own expectation from whether the host had
# gtimeout, so it asserted a different contract on every machine and could not
# fail on either: a broken probe still "matched" whatever the host produced.

# PATH is swapped by explicit save/restore rather than a `VAR=x func` prefix:
# whether such an assignment survives a shell-function call differs between
# bash versions and POSIX mode, which is the very kind of ambient dependence
# these tests exist to remove.

@test "os: setup_macos_commands selects gtimeout when coreutils IS present" {
    local saved_path="$PATH"
    mkdir -p "$SCRATCH/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/bin/gtimeout"
    chmod +x "$SCRATCH/bin/gtimeout"

    PATH="$SCRATCH/bin:$PATH"
    # Advisories go to stderr now, so both streams are captured — otherwise this
    # would assert absence against a file the message never had a chance to
    # reach, and pass no matter what the function printed.
    setup_macos_commands > "$SCRATCH/macos-setup.out" 2>&1
    PATH="$saved_path"

    [ "$MANIFEST_CLI_OS_DATE_CMD" = "date -u -d" ]
    [ "$MANIFEST_CLI_OS_TIMEOUT_CMD" = "gtimeout" ]
    refute grep -q "gtimeout not found" "$SCRATCH/macos-setup.out"
}

@test "os: setup_macos_commands falls back and warns when coreutils is ABSENT" {
    local saved_path="$PATH"
    mkdir -p "$SCRATCH/empty-bin"

    # Verbose is required to see the advisory at all now: the module's contract
    # is silence by default, and this advisory used to breach it (see the
    # stdout-silence test in os_detection_preamble.bats). The fallback SELECTION
    # is unconditional — only the message is gated — which is what the two
    # command assertions below pin.
    PATH="$SCRATCH/empty-bin"
    MANIFEST_CLI_VERBOSE=1 setup_macos_commands > "$SCRATCH/macos-setup.out" 2>&1
    PATH="$saved_path"

    [ "$MANIFEST_CLI_OS_DATE_CMD" = "date -u -d" ]
    [ "$MANIFEST_CLI_OS_TIMEOUT_CMD" = "timeout_fallback" ]
    grep -q "gtimeout not found" "$SCRATCH/macos-setup.out"
    grep -q "Install coreutils" "$SCRATCH/macos-setup.out"

    # The advisory must be on stderr, not stdout: this module runs at source
    # time, so a byte on stdout prepends itself to the invoked command's output.
    local saved2="$PATH"
    PATH="$SCRATCH/empty-bin"
    MANIFEST_CLI_VERBOSE=1 setup_macos_commands > "$SCRATCH/stdout-only.out" 2>/dev/null
    PATH="$saved2"
    refute grep -q "gtimeout not found" "$SCRATCH/stdout-only.out"
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
