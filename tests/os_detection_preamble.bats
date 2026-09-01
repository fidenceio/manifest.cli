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

# The test above passed for the whole life of a defect it was written to catch,
# because it inherits the developer's PATH — and on a machine with Homebrew
# coreutils the advisory never fired. "Silent by default" was asserted only for
# the one platform configuration that had nothing to say. Until 2026-08-31 the
# platform setup emitted unconditional `echo`s on STDOUT at module-source time
# (two on a macOS host without gtimeout, one on any unmatched `uname -s`), and
# because detect_os runs on load they prepended themselves to the output of
# whatever command the user actually ran.
#
# Those advisories are now gone entirely, along with the per-platform command
# shims that produced them (TRACKER §65(3)) — the silence is structural rather
# than gated. **These tests are kept anyway**, and are stronger for it: they now
# assert that nothing in the arm-selection path prints, on arms the developer's
# own host never takes. A future arm that announces itself fails here.
#
# `uname` is stubbed rather than trusted, so these run identically on macOS and
# on the ubuntu CI leg. Stubbing is required, not tidiness: an assertion about
# the Darwin arm is unreachable on Linux, so a test that merely stripped PATH
# would assert the contract on exactly one platform — the mistake above,
# repeated.
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

@test "detect_os: silent by default on the Darwin arm with no platform tools" {
    # Darwin arm reached on any host, with a PATH that has no gtimeout — the
    # configuration that used to print two lines on stdout.
    local stub; stub="$(stub_uname Darwin)"
    run source_os_module \
        "export PATH=\"$stub:/usr/bin:/bin:/usr/sbin:/sbin\"; unset MANIFEST_CLI_VERBOSE; unset MANIFEST_CLI_DEBUG" \
        "printf 'OS=%s' \"\$MANIFEST_CLI_OS_NAME\""
    [ "$status" -eq 0 ]
    # Exact match asserts BOTH halves at once: nothing was printed, and the
    # Darwin arm really was entered — so silence is not from missing the path.
    [ "$output" = "OS=macOS" ]
}

@test "detect_os: silent by default on an unrecognized platform" {
    # The unmatched-uname arm, which used to announce itself unconditionally on
    # EVERY invocation for anyone outside the five known platforms.
    local stub; stub="$(stub_uname SunOS)"
    run source_os_module \
        "export PATH=\"$stub:\$PATH\"; unset MANIFEST_CLI_VERBOSE; unset MANIFEST_CLI_DEBUG" \
        "printf 'OS=%s' \"\$MANIFEST_CLI_OS_NAME\""
    [ "$status" -eq 0 ]
    [ "$output" = "OS=Unknown" ]
}

@test "positive control: a stubbed arm DOES produce output under verbose" {
    # Without this, both silence assertions above would pass against a module
    # that had stopped detecting anything at all — absent output reading as a
    # pass. Proves the stubbed path is live and can still speak when asked.
    #
    # This replaces two earlier controls that asserted the platform advisories
    # were reachable. Those advisories no longer exist, so asserting their
    # reachability would now pin behaviour the module deliberately dropped. The
    # banner is the output that remains, and it names the stubbed platform —
    # which is a stronger control than the advisories were, because it proves
    # the STUB took effect rather than merely that some text appeared.
    local stub; stub="$(stub_uname SunOS)"
    run source_os_module \
        "export PATH=\"$stub:\$PATH\"; export MANIFEST_CLI_VERBOSE=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detecting operating system"* ]]
    [[ "$output" == *"Detected: Unknown"* ]]
}

@test "the deleted platform-setup functions stay deleted" {
    # §65(3): the five setup_*_commands functions and timeout_fallback were
    # removed with the command shims they existed to populate. A test asserting
    # values nothing reads is what kept them alive through two prior audits, so
    # this asserts their ABSENCE instead.
    local fn
    for fn in setup_macos_commands setup_linux_commands setup_bsd_commands \
              setup_windows_commands setup_fallback_commands timeout_fallback; do
        run bash -c "source '$TEST_REPO_ROOT/modules/system/manifest-os.sh' >/dev/null 2>&1; \
                     declare -F $fn >/dev/null 2>&1 && echo PRESENT || echo ABSENT"
        [ "$output" = "ABSENT" ]
    done

    # Control: the same probe reports PRESENT for a function the module keeps,
    # so ABSENT above cannot be what a failed source looks like.
    run bash -c "source '$TEST_REPO_ROOT/modules/system/manifest-os.sh' >/dev/null 2>&1; \
                 declare -F format_timestamp_cross_platform >/dev/null 2>&1 && echo PRESENT || echo ABSENT"
    [ "$output" = "PRESENT" ]
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
