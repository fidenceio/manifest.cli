#!/usr/bin/env bats
#
# apply_plan's Homebrew branch in uninstall-cli.sh: when the install is
# brew-managed, the plan must run `brew uninstall <formula>` and
# `brew untap <tap>` — through the destructive-brew sandbox tripwire.
#
# These are the inverse fixtures of uninstall_sandbox_tripwire.bats (there
# brew_package_present returns 1 so the brew branch never fires; here it
# returns 0 and a recording `brew` stub proves the exact commands). Under
# bats the tripwire refuses brew mutations, so the invocation itself is only
# reachable with MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 — safe here
# because `brew` is a recording function, never the real binary.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    BREW_LOG="$SCRATCH/brew-calls.log"
    : > "$BREW_LOG"
    export BREW_LOG
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Stub every plan-population helper: brew package + tap present, no filesystem
# artifacts, and a recording brew. Must run AFTER sourcing uninstall-cli.sh so
# the stubs shadow the real definitions.
_stub_brew_managed_plan() {
    found_install_dirs()      { :; }
    found_binaries()          { :; }
    found_configs()           { :; }
    found_data_dirs()         { :; }
    found_profile_files()     { :; }
    brew_completion_targets() { :; }
    brew_package_present()    { return 0; }
    brew_tap_present()        { return 0; }
    brew()                    { echo "$*" >> "$BREW_LOG"; return 0; }
    export -f found_install_dirs found_binaries found_configs found_data_dirs
    export -f found_profile_files brew_completion_targets
    export -f brew_package_present brew_tap_present brew
}

@test "apply_plan removes the Homebrew package and untaps (escape-hatched recording stub)" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/uninstall-cli.sh"
    _stub_brew_managed_plan
    MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 run apply_plan
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Uninstalling Homebrew package"
    echo "$output" | grep -q "Removed Homebrew package"
    echo "$output" | grep -q "Untapped fidenceio/tap"
    # Exact brew invocations, from the recording log.
    grep -qx "uninstall fidenceio/tap/manifest" "$BREW_LOG"
    grep -qx "untap fidenceio/tap" "$BREW_LOG"
    # The tap-qualified uninstall succeeded → no bare-name fallback call.
    ! grep -qx "uninstall manifest" "$BREW_LOG"
}

@test "apply_plan under bats without the escape hatch skips brew and calls nothing" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/uninstall-cli.sh"
    _stub_brew_managed_plan
    run apply_plan
    # Exactly one error is counted: the tripwire-skipped brew uninstall
    # (the untap skip warns without incrementing — see apply_plan).
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "brew uninstall skipped by sandbox tripwire"
    echo "$output" | grep -q "brew untap skipped by sandbox tripwire"
    # The recording stub was never invoked.
    [ ! -s "$BREW_LOG" ]
}
