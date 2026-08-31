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

# The test above passed for the whole life of the defect below, because it
# inherits the developer's PATH — and on a machine with Homebrew coreutils the
# advisory it needed to catch never fires. "Silent by default" was asserted only
# for the one platform configuration that had nothing to say.
#
# The three tests here strip PATH to the base system, or stub `uname`, so the
# advisory paths are actually entered. Before the fix each of these produced
# output on STDOUT at module-source time: two lines on a macOS host without
# gtimeout, one on any platform `uname -s` does not match. Since detect_os is
# called on load, that output prepends itself to whatever the invoked command
# was asked to print — including JSON and anything a caller parses.

# `uname` is stubbed rather than trusted, so these run identically on macOS and
# on the ubuntu CI leg. Stubbing is required, not tidiness: the macOS advisory
# is unreachable on Linux, so a test that merely stripped PATH would assert the
# contract on exactly one platform — the mistake described above, repeated.
stub_uname() {
    local os_name="$1" dir="$BATS_TEST_TMPDIR/stub-$os_name"
    mkdir -p "$dir"
    cat > "$dir/uname" <<EOF
#!/usr/bin/env bash
case "\$1" in
    -r) echo "0.0-test" ;;
    *)  echo "$os_name" ;;
esac
EOF
    chmod +x "$dir/uname"
    printf '%s\n' "$dir"
}

@test "detect_os: silent by default when the macOS platform tools are ABSENT" {
    # Darwin arm, PATH with no gtimeout: setup_macos_commands takes its fallback
    # and previously announced it on stdout, twice.
    local stub; stub="$(stub_uname Darwin)"
    run source_os_module \
        "export PATH=\"$stub:/usr/bin:/bin:/usr/sbin:/sbin\"; unset MANIFEST_CLI_VERBOSE; unset MANIFEST_CLI_DEBUG" \
        "printf 'TIMEOUT=%s' \"\$MANIFEST_CLI_OS_TIMEOUT_CMD\""
    [ "$status" -eq 0 ]
    # Exact match asserts BOTH halves at once: nothing was advised, and the
    # fallback arm really was entered — so silence is not from missing the path.
    [ "$output" = "TIMEOUT=timeout_fallback" ]
}

@test "detect_os: silent by default on an unrecognized platform" {
    # setup_fallback_commands' advisory was unconditional, so EVERY invocation
    # on a platform outside the five known arms emitted a line.
    local stub; stub="$(stub_uname SunOS)"
    run source_os_module \
        "export PATH=\"$stub:\$PATH\"; unset MANIFEST_CLI_VERBOSE; unset MANIFEST_CLI_DEBUG" \
        "printf 'OS=%s' \"\$MANIFEST_CLI_OS_OS\""
    [ "$status" -eq 0 ]
    [ "$output" = "OS=Unknown" ]
}

@test "positive control: the macOS advisory IS still reachable under verbose" {
    # Without this, the silence assertions above would all pass against a module
    # that had simply stopped advising — absent output reading as a pass.
    local stub; stub="$(stub_uname Darwin)"
    run source_os_module \
        "export PATH=\"$stub:/usr/bin:/bin:/usr/sbin:/sbin\"; export MANIFEST_CLI_VERBOSE=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gtimeout not found"* ]]
}

@test "positive control: the unknown-platform advisory IS still reachable" {
    local stub; stub="$(stub_uname SunOS)"
    run source_os_module \
        "export PATH=\"$stub:\$PATH\"; export MANIFEST_CLI_VERBOSE=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unknown platform"* ]]
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
