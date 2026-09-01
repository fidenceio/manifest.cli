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

# The two `timeout_fallback` tests are gone with the function (TRACKER §65(3)).
# They were the only callers it ever had: it existed solely as the value
# MANIFEST_CLI_OS_TIMEOUT_CMD took when `gtimeout` was absent, and that variable
# had no consumer in the product. The pair also cost ~11s of wall clock per run
# sleeping against a deadline, to exercise a code path nothing reached.
#
# Absence is asserted in os_detection_preamble.bats rather than here, alongside
# the setup_*_commands functions removed in the same change.

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

# The three setup_*_commands tests that stood here are gone with the functions
# (TRACKER §65(3)). They are worth a note because of WHY they were misleading.
#
# Each one called a setup function and then asserted the four variables that
# function had just assigned — a closed loop that could not fail for any reason
# a user would care about. They reported the shims as covered, which is how the
# layer survived two audits: §21a saw "no consumers" and said delete, §65 saw
# the same and said wire up, and both times the test file said "but it is
# tested." A test that reads only what the code under test just wrote measures
# nothing except that assignment happened.
#
# What replaced them is not a like-for-like: `os_detection_preamble.bats` asserts
# the functions are ABSENT, and `os_var_name_agreement.bats` asserts the one OS
# variable that does have a consumer is spelled the same at both ends. That is
# the property that was actually broken for months.

@test "os: detect_os records the platform under a stubbed uname" {
    # The surviving half of the old dispatch test. It used to also assert the
    # per-platform command variables; now it pins only what detect_os still
    # produces — which is what a consumer can actually read.
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
        echo \"os=\$MANIFEST_CLI_OS_NAME family=\$MANIFEST_CLI_OS_FAMILY version=\$MANIFEST_CLI_OS_VERSION\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"os=Linux family=unix version=6.1.0-test"* ]]
}
