#!/usr/bin/env bats

# Verifies the destructive-target sandbox tripwire in
# modules/system/manifest-install-paths.sh. The tripwire's job: when a bats
# process tries to destroy a path that is NOT under $BATS_TEST_TMPDIR, refuse
# loudly instead of nuking the developer's real install footprint.
#
# Adding a bats test that intentionally calls a destructive function against
# a real-shaped path is the safest way to prove the gate works — the gate is
# what stops the call from actually doing anything.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "predicate refuses empty path" {
    run manifest_install_paths_assert_destructive_target_safe "" "rm"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "empty target path"
}

@test "predicate refuses '/' and other system roots" {
    for sys in / /Users /home /usr /var /etc /opt /private; do
        run manifest_install_paths_assert_destructive_target_safe "$sys" "rm"
        [ "$status" -ne 0 ]
        echo "$output" | grep -q "system path"
    done
}

@test "predicate refuses bare \$HOME" {
    run manifest_install_paths_assert_destructive_target_safe "$HOME" "rm"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "is \$HOME"
}

@test "predicate accepts paths under \$BATS_TEST_TMPDIR" {
    run manifest_install_paths_assert_destructive_target_safe "$HOME/.manifest-cli" "rm"
    [ "$status" -eq 0 ]
}

@test "predicate refuses real-home target when bats is active" {
    # Simulate a future test that forgot to redirect HOME — point the candidate
    # at a real-user path while BATS_TEST_TMPDIR is set (which it always is
    # under bats).
    local real_target="/Users/somebody-who-does-not-exist/.manifest-cli"
    run manifest_install_paths_assert_destructive_target_safe "$real_target" "rm"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "running under bats"
    echo "$output" | grep -q "sandbox tripwire"
    echo "$output" | grep -q "MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE"
}

@test "escape hatch MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 is honored with warning" {
    local real_target="/Users/somebody-who-does-not-exist/.manifest-cli"
    MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 run manifest_install_paths_assert_destructive_target_safe "$real_target" "rm"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "permitted by MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1"
}

@test "brew predicate refuses brew operations under bats" {
    run manifest_install_paths_assert_destructive_brew_safe "brew uninstall manifest"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "refusing brew uninstall manifest"
}

@test "brew predicate honors escape hatch" {
    MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 run manifest_install_paths_assert_destructive_brew_safe "brew uninstall manifest"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "permitted by MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1"
}

@test "remove_installation_directory refuses real-home target under bats" {
    # End-to-end: drive the actual destructive function (not the predicate
    # directly) against a real-shaped path. The function MUST refuse and
    # return non-zero without touching the filesystem.
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/modules/system/manifest-uninstall.sh"
    # Synthesize a fake target inside SCRATCH but outside what the predicate
    # accepts (give it a sibling path that BATS_TEST_TMPDIR does not cover).
    local outside_target="/Users/nobody-here/.manifest-cli"
    # Don't create the dir — the function early-returns on missing dirs, so
    # plant a real dir at a path that simulates "wrong HOME".
    # Instead: temporarily lie to the function by passing a real-shaped path
    # that does exist on disk but is NOT under BATS_TEST_TMPDIR.
    # The system /tmp directory is guaranteed to exist on macOS/linux and is
    # NOT under BATS_TEST_TMPDIR.
    if [ -d "/tmp/manifest-tripwire-decoy" ]; then
        rm -rf "/tmp/manifest-tripwire-decoy" 2>/dev/null || true
    fi
    mkdir -p "/tmp/manifest-tripwire-decoy"
    run remove_installation_directory "/tmp/manifest-tripwire-decoy"
    [ "$status" -ne 0 ]
    # The decoy directory MUST still exist — the tripwire blocked the rm.
    [ -d "/tmp/manifest-tripwire-decoy" ]
    rmdir "/tmp/manifest-tripwire-decoy"
}

@test "remove_installation_directory proceeds for sandboxed target" {
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/modules/system/manifest-uninstall.sh"
    local sandboxed="$SCRATCH/fake-install"
    mkdir -p "$sandboxed"
    run remove_installation_directory "$sandboxed"
    [ "$status" -eq 0 ]
    [ ! -d "$sandboxed" ]
}
