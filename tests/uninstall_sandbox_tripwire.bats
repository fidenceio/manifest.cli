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

# ============================================================================
# End-to-end coverage: remaining destructive sites in manifest-uninstall.sh
#
# Each test plants a decoy file/dir at a real-home-shaped path OUTSIDE
# $BATS_TEST_TMPDIR, overrides path-yielding helpers so the destructive
# function targets the decoy, then asserts the decoy survives. Filesystem
# state is the decisive check — return codes alone aren't reliable because
# some functions `continue` past refusals without bubbling an error.
# ============================================================================

@test "remove_cli_binary refuses real-home-shaped target end-to-end" {
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/modules/system/manifest-uninstall.sh"
    local decoy_dir="/tmp/manifest-tripwire-bin.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy="$decoy_dir/fake-manifest"
    : > "$decoy"
    run remove_cli_binary "$decoy"
    [ "$status" -ne 0 ]
    [ -f "$decoy" ]
    rm -rf "$decoy_dir"
}

@test "cleanup_config_files refuses config-file rm against real-home-shaped target" {
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/modules/system/manifest-uninstall.sh"
    local decoy_dir="/tmp/manifest-tripwire-config.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy="$decoy_dir/fake-config.yaml"
    echo "user_settings: keep-me" > "$decoy"
    manifest_install_paths_config_files() { printf '%s\n' "$decoy"; }
    manifest_install_paths_data_dirs() { :; }
    manifest_install_paths_user_global_config() { echo "$decoy_dir/__nonexistent__"; }
    export -f manifest_install_paths_config_files
    export -f manifest_install_paths_data_dirs
    export -f manifest_install_paths_user_global_config
    run cleanup_config_files true
    [ -f "$decoy" ]
    [ "$(cat "$decoy")" = "user_settings: keep-me" ]
    rm -rf "$decoy_dir"
}

@test "cleanup_config_files refuses data-dir rm against real-home-shaped target" {
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/modules/system/manifest-uninstall.sh"
    local decoy_dir="/tmp/manifest-tripwire-data.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir/fake-data-dir"
    echo "important data" > "$decoy_dir/fake-data-dir/keep.txt"
    manifest_install_paths_config_files() { :; }
    manifest_install_paths_data_dirs() { printf '%s\n' "$decoy_dir/fake-data-dir"; }
    manifest_install_paths_user_global_config() { echo "$decoy_dir/__nonexistent__"; }
    export -f manifest_install_paths_config_files
    export -f manifest_install_paths_data_dirs
    export -f manifest_install_paths_user_global_config
    run cleanup_config_files true
    [ -d "$decoy_dir/fake-data-dir" ]
    [ "$(cat "$decoy_dir/fake-data-dir/keep.txt")" = "important data" ]
    rm -rf "$decoy_dir"
}

@test "cleanup_environment_variables refuses profile rewrite against real-home-shaped target" {
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/modules/system/manifest-uninstall.sh"
    local decoy_dir="/tmp/manifest-tripwire-profile.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy="$decoy_dir/fake-zshrc"
    cat > "$decoy" <<'EOF'
# User's real config — must not be touched
export PATH="$HOME/bin:$PATH"
export MANIFEST_CLI_FAKE=oops
alias ll='ls -la'
EOF
    local original_sum
    original_sum="$(shasum "$decoy" | awk '{print $1}')"
    manifest_install_paths_shell_profiles() { printf '%s\n' "$decoy"; }
    export -f manifest_install_paths_shell_profiles
    manifest_make_scratch_path() { echo "$BATS_TEST_TMPDIR"; }
    export -f manifest_make_scratch_path
    run cleanup_environment_variables
    [ -f "$decoy" ]
    local current_sum
    current_sum="$(shasum "$decoy" | awk '{print $1}')"
    [ "$current_sum" = "$original_sum" ]
    ! ls "$decoy".manifest-backup-* >/dev/null 2>&1
    rm -rf "$decoy_dir"
}

# ============================================================================
# End-to-end coverage: every destructive site in install-cli.sh
# ============================================================================

@test "install-cli cleanup_homebrew_install refuses user_bin rm against real-home-shaped target" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    local decoy_dir="/tmp/manifest-tripwire-installcli-bin.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy_bin="$decoy_dir/fake-manifest"
    : > "$decoy_bin"
    manifest_install_paths_user_binary() { echo "$decoy_bin"; }
    manifest_install_paths_global_state_dir() { echo "$decoy_dir/__no_state__"; }
    manifest_install_paths_legacy_install_dir() { echo "$decoy_dir/__no_legacy__"; }
    export -f manifest_install_paths_user_binary
    export -f manifest_install_paths_global_state_dir
    export -f manifest_install_paths_legacy_install_dir
    cleanup_environment_variables() { :; }
    export -f cleanup_environment_variables
    run cleanup_homebrew_install
    [ -f "$decoy_bin" ]
    rm -rf "$decoy_dir"
}

@test "install-cli cleanup_homebrew_install refuses state_dir rm against real-home-shaped target" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    local decoy_dir="/tmp/manifest-tripwire-installcli-state.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir/fake-state"
    echo "important" > "$decoy_dir/fake-state/keep.txt"
    manifest_install_paths_user_binary() { echo "$decoy_dir/__no_bin__"; }
    manifest_install_paths_global_state_dir() { echo "$decoy_dir/fake-state"; }
    manifest_install_paths_legacy_install_dir() { echo "$decoy_dir/__no_legacy__"; }
    export -f manifest_install_paths_user_binary
    export -f manifest_install_paths_global_state_dir
    export -f manifest_install_paths_legacy_install_dir
    cleanup_environment_variables() { :; }
    export -f cleanup_environment_variables
    run cleanup_homebrew_install
    [ -d "$decoy_dir/fake-state" ]
    [ "$(cat "$decoy_dir/fake-state/keep.txt")" = "important" ]
    rm -rf "$decoy_dir"
}

@test "install-cli cleanup_legacy_locations refuses rm against real-home-shaped target" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    local decoy_dir="/tmp/manifest-tripwire-installcli-legacy.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir/fake-legacy"
    echo "important" > "$decoy_dir/fake-legacy/keep.txt"
    manifest_install_paths_legacy_install_dir() { echo "$decoy_dir/fake-legacy"; }
    export -f manifest_install_paths_legacy_install_dir
    run cleanup_legacy_locations
    [ -d "$decoy_dir/fake-legacy" ]
    [ "$(cat "$decoy_dir/fake-legacy/keep.txt")" = "important" ]
    rm -rf "$decoy_dir"
}

@test "install-cli cleanup_environment_variables refuses profile rewrite against real-home-shaped target" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    local decoy_dir="/tmp/manifest-tripwire-installcli-profile.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy="$decoy_dir/fake-bashrc"
    cat > "$decoy" <<'EOF'
# User's real bashrc
export MANIFEST_CLI_GHOST=oops
alias gs='git status'
EOF
    local original_sum
    original_sum="$(shasum "$decoy" | awk '{print $1}')"
    manifest_install_paths_shell_profiles() { printf '%s\n' "$decoy"; }
    export -f manifest_install_paths_shell_profiles
    run cleanup_environment_variables
    [ -f "$decoy" ]
    local current_sum
    current_sum="$(shasum "$decoy" | awk '{print $1}')"
    [ "$current_sum" = "$original_sum" ]
    ! ls "$decoy".manifest-backup-* >/dev/null 2>&1
    rm -rf "$decoy_dir"
}

# ============================================================================
# End-to-end coverage: every destructive site in uninstall-cli.sh
#
# remove_path is the chokepoint for install_dirs/binaries/configs/data_dirs
# blocks in apply_plan — one direct test covers all four. Completion rm and
# profile rewrite have their own predicate sites and need their own tests.
# ============================================================================

@test "uninstall-cli remove_path refuses real-home-shaped target" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/uninstall-cli.sh"
    local decoy_dir="/tmp/manifest-tripwire-uninstallcli-path.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir/fake-target"
    echo "important" > "$decoy_dir/fake-target/keep.txt"
    run remove_path "$decoy_dir/fake-target" "no"
    [ "$status" -ne 0 ]
    [ -d "$decoy_dir/fake-target" ]
    [ "$(cat "$decoy_dir/fake-target/keep.txt")" = "important" ]
    rm -rf "$decoy_dir"
}

@test "uninstall-cli completion rm in apply_plan refuses real-home-shaped target" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/uninstall-cli.sh"
    local decoy_dir="/tmp/manifest-tripwire-uninstallcli-completion.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy="$decoy_dir/fake-completion"
    : > "$decoy"
    found_install_dirs()      { :; }
    found_binaries()          { :; }
    found_configs()           { :; }
    found_data_dirs()         { :; }
    found_profile_files()     { :; }
    brew_package_present()    { return 1; }
    brew_tap_present()        { return 1; }
    brew_completion_targets() { printf '%s\n' "$decoy"; }
    export -f found_install_dirs found_binaries found_configs found_data_dirs
    export -f found_profile_files brew_package_present brew_tap_present
    export -f brew_completion_targets
    run apply_plan
    [ -f "$decoy" ]
    rm -rf "$decoy_dir"
}

@test "uninstall-cli profile rewrite in apply_plan refuses real-home-shaped target" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/uninstall-cli.sh"
    local decoy_dir="/tmp/manifest-tripwire-uninstallcli-profile.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy="$decoy_dir/fake-zshrc"
    cat > "$decoy" <<'EOF'
# User's real zshrc
export MANIFEST_CLI_OOPS=1
export PATH="$HOME/.manifest-cli/bin:$PATH"
alias x='echo y'
EOF
    local original_sum
    original_sum="$(shasum "$decoy" | awk '{print $1}')"
    found_install_dirs()      { :; }
    found_binaries()          { :; }
    found_configs()           { :; }
    found_data_dirs()         { :; }
    brew_completion_targets() { :; }
    brew_package_present()    { return 1; }
    brew_tap_present()        { return 1; }
    found_profile_files()     { printf '%s\n' "$decoy"; }
    export -f found_install_dirs found_binaries found_configs found_data_dirs
    export -f brew_completion_targets brew_package_present brew_tap_present
    export -f found_profile_files
    run apply_plan
    [ -f "$decoy" ]
    local current_sum
    current_sum="$(shasum "$decoy" | awk '{print $1}')"
    [ "$current_sum" = "$original_sum" ]
    ! ls "$decoy".manifest-backup-* >/dev/null 2>&1
    rm -rf "$decoy_dir"
}
