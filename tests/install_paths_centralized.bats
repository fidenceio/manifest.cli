#!/usr/bin/env bats
#
# Lock in the install-paths centralization invariant: install-cli.sh,
# uninstall-cli.sh, and the install/uninstall modules must read every
# canonical filesystem location from modules/system/manifest-install-paths.sh.
# A new caller that hardcodes a path adds a hit to one of these grep
# matches and fails the test, prompting the author to source the paths
# module instead.
#
# Whitelisted exceptions:
#   - manifest-install-paths.sh itself (the source of truth)
#   - uninstall-cli.sh's documented fallback block (used when the modules
#     tree is missing — kept inline by design so the script is usable on
#     broken installs)

load 'helpers/setup'

# Count files under the install/uninstall scope that contain a given literal.
# Scope is intentionally narrow: we don't yet attempt to centralize $HOME/.manifest-cli
# uses across runtime modules (manifest-core.sh, manifest-config.sh, etc.) —
# that's separate scope-creep work.
_files_with() {
    local literal="$1"
    grep -lE -- "$literal" \
        "$TEST_REPO_ROOT/install-cli.sh" \
        "$TEST_REPO_ROOT/uninstall-cli.sh" \
        "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh" \
        "$TEST_REPO_ROOT/modules/system/manifest-uninstall.sh" \
        2>/dev/null \
        | sort -u
}

@test "global state dir literal appears only in paths module + uninstall-cli.sh fallback" {
    local matches
    matches="$(_files_with '\$HOME/\.manifest-cli')"
    echo "Matches:" >&2
    echo "$matches" >&2
    [ -n "$matches" ]
    echo "$matches" | grep -q "modules/system/manifest-install-paths.sh$"
    # install-cli.sh and uninstall-cli.sh may still reference the literal
    # inside their fallback blocks / comments — capped at 3 total files.
    [ "$(echo "$matches" | wc -l | tr -d ' ')" -le 3 ]
}

@test "user binary literal is centralized (paths module + fallback only)" {
    local matches
    matches="$(_files_with '\$HOME/\.local/bin/manifest')"
    echo "Matches:" >&2
    echo "$matches" >&2
    [ -n "$matches" ]
    echo "$matches" | grep -q "modules/system/manifest-install-paths.sh$"
    # paths module + uninstall-cli.sh fallback
    [ "$(echo "$matches" | wc -l | tr -d ' ')" -le 2 ]
}

@test "legacy install dir literal is centralized (paths module + fallback only)" {
    local matches
    matches="$(_files_with '/usr/local/share/manifest-cli')"
    echo "Matches:" >&2
    echo "$matches" >&2
    [ -n "$matches" ]
    echo "$matches" | grep -q "modules/system/manifest-install-paths.sh$"
    [ "$(echo "$matches" | wc -l | tr -d ' ')" -le 2 ]
}

@test "homebrew formula slug is centralized in paths module" {
    local matches
    matches="$(_files_with 'fidenceio/tap/manifest')"
    echo "Matches:" >&2
    echo "$matches" >&2
    [ -n "$matches" ]
    echo "$matches" | grep -q "modules/system/manifest-install-paths.sh$"
    # Allowed: paths module, install-cli.sh docstring, uninstall-cli.sh fallback +
    # usage banner.
    [ "$(echo "$matches" | wc -l | tr -d ' ')" -le 3 ]
}

@test "homebrew tap slug is centralized in paths module" {
    local matches
    matches="$(_files_with 'fidenceio/tap[^/]')"
    echo "Matches:" >&2
    echo "$matches" >&2
    [ -n "$matches" ]
    echo "$matches" | grep -q "modules/system/manifest-install-paths.sh$"
    [ "$(echo "$matches" | wc -l | tr -d ' ')" -le 3 ]
}

@test "profile-line regex is centralized" {
    # The full canonical regex with the MANIFEST_ prefix marker.
    local matches
    matches="$(_files_with 'export\[\[:space:\]\]\+MANIFEST_\[A-Z_\]')"
    echo "Matches:" >&2
    echo "$matches" >&2
    [ -n "$matches" ]
    echo "$matches" | grep -q "modules/system/manifest-install-paths.sh$"
    # paths module + uninstall-cli.sh fallback
    [ "$(echo "$matches" | wc -l | tr -d ' ')" -le 2 ]
}

@test "paths module getters are functions, not exported arrays" {
    # Exported bash arrays don't cross subshells reliably — verify the design
    # contract that all centralizers are stdout-producing functions.
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    declare -F manifest_install_paths_install_dirs >/dev/null
    declare -F manifest_install_paths_binary_candidates >/dev/null
    declare -F manifest_install_paths_config_files >/dev/null
    declare -F manifest_install_paths_data_dirs >/dev/null
    declare -F manifest_install_paths_plugin_data_dirs >/dev/null
    declare -F manifest_install_paths_cache_dirs >/dev/null
    declare -F manifest_install_paths_shell_profiles >/dev/null
    declare -F manifest_install_paths_profile_line_regex >/dev/null
    declare -F manifest_install_paths_homebrew_formula >/dev/null
    declare -F manifest_install_paths_homebrew_tap >/dev/null
    declare -F manifest_install_paths_user_global_config >/dev/null
    declare -F manifest_install_paths_global_state_dir >/dev/null
    declare -F manifest_install_paths_user_binary >/dev/null
    declare -F manifest_install_paths_user_bin_dir >/dev/null
    declare -F manifest_install_paths_legacy_install_dir >/dev/null

    # And every getter must return a non-empty result for the well-known ones.
    [ -n "$(manifest_install_paths_homebrew_formula)" ]
    [ -n "$(manifest_install_paths_homebrew_tap)" ]
    [ -n "$(manifest_install_paths_global_state_dir)" ]
    [ -n "$(manifest_install_paths_user_global_config)" ]
}

@test "paths module is idempotent under repeated sourcing" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    local before="$_MANIFEST_INSTALL_PATHS_LOADED"
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    local after="$_MANIFEST_INSTALL_PATHS_LOADED"
    [ "$before" = "$after" ]
    [ "$before" = "1" ]
}

# ----- New runtime path helpers (Phase 1 of §5.7) -------------------------

@test "runtime_root resolves under HOME by default" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    unset MANIFEST_CLI_INSTALL_LOCATION
    [ "$(manifest_install_paths_runtime_root)" = "$HOME/.manifest-cli/runtime" ]
}

@test "runtime_root honours MANIFEST_CLI_INSTALL_LOCATION override" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    MANIFEST_CLI_INSTALL_LOCATION="/opt/manifest-cli-alt" \
        run -0 manifest_install_paths_runtime_root
    [ "$output" = "/opt/manifest-cli-alt/runtime" ]
}

@test "current_symlink resolves under HOME by default" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    unset MANIFEST_CLI_INSTALL_LOCATION
    [ "$(manifest_install_paths_current_symlink)" = "$HOME/.manifest-cli/current" ]
}

@test "current_symlink honours MANIFEST_CLI_INSTALL_LOCATION override" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    MANIFEST_CLI_INSTALL_LOCATION="/opt/manifest-cli-alt" \
        run -0 manifest_install_paths_current_symlink
    [ "$output" = "/opt/manifest-cli-alt/current" ]
}

@test "versioned_dir prefixes 'v' when caller omits it" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    unset MANIFEST_CLI_INSTALL_LOCATION
    [ "$(manifest_install_paths_versioned_dir 2.5.0)" = "$HOME/.manifest-cli/runtime/v2.5.0" ]
}

@test "versioned_dir does not double-prefix when caller passes leading v" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    unset MANIFEST_CLI_INSTALL_LOCATION
    [ "$(manifest_install_paths_versioned_dir v2.5.0)" = "$HOME/.manifest-cli/runtime/v2.5.0" ]
}

@test "versioned_dir fails when version is empty" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    run manifest_install_paths_versioned_dir ""
    [ "$status" -ne 0 ]
}

@test "preserved_subdirs lists logs, audit, ide, locks one-per-line" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    local out
    out="$(manifest_install_paths_preserved_subdirs)"
    [ "$(echo "$out" | wc -l | tr -d ' ')" = "4" ]
    echo "$out" | grep -qx 'logs'
    echo "$out" | grep -qx 'audit'
    echo "$out" | grep -qx 'ide'
    echo "$out" | grep -qx 'locks'
}

# ----- Canonical cleanup_profile_entries (Phase 1 of §5.7) ----------------

# Sandbox HOME under BATS_TEST_TMPDIR so the destructive tripwire allows the
# profile rewrite and the test never reaches into the developer's real home.
_setup_seeded_profile_home() {
    SANDBOX_HOME="$BATS_TEST_TMPDIR/sandbox-home"
    mkdir -p "$SANDBOX_HOME"
    HOME="$SANDBOX_HOME"
    cat > "$SANDBOX_HOME/.zshrc" <<'EOF'
# user content above
alias ll='ls -la'
export MANIFEST_CLI_FAKE=oops
export PATH="$HOME/.manifest-cli/bin:$PATH"
# user content below
EOF
}

@test "cleanup_profile_entries removes seeded MANIFEST entry and writes exactly one backup" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    _setup_seeded_profile_home
    # Restrict scan to the seeded profile only.
    manifest_install_paths_shell_profiles() { echo "$SANDBOX_HOME/.zshrc"; }
    run -0 manifest_install_paths_cleanup_profile_entries 0 0
    # Seeded MANIFEST line must be gone, unrelated content preserved.
    ! grep -q 'MANIFEST_CLI_FAKE' "$SANDBOX_HOME/.zshrc"
    grep -q "alias ll='ls -la'" "$SANDBOX_HOME/.zshrc"
    # Exactly one backup written for this profile.
    local backups
    backups=$(ls "$SANDBOX_HOME"/.zshrc.manifest-backup-* 2>/dev/null | wc -l | tr -d ' ')
    [ "$backups" = "1" ]
}

@test "cleanup_profile_entries refuses to operate outside BATS_TEST_TMPDIR (tripwire armed)" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    # Seed a profile-shaped file OUTSIDE BATS_TEST_TMPDIR.
    local decoy_dir="/tmp/manifest-pathmod-tripwire.$$"
    rm -rf "$decoy_dir" 2>/dev/null || true
    mkdir -p "$decoy_dir"
    local decoy="$decoy_dir/fake-zshrc"
    cat > "$decoy" <<'EOF'
export MANIFEST_CLI_FAKE=oops
alias gs='git status'
EOF
    local original_sum
    original_sum="$(shasum "$decoy" | awk '{print $1}')"
    manifest_install_paths_shell_profiles() { echo "$decoy"; }
    run manifest_install_paths_cleanup_profile_entries 0 0
    # Tripwire must skip the rewrite; file untouched, no backup written.
    [ -f "$decoy" ]
    [ "$(shasum "$decoy" | awk '{print $1}')" = "$original_sum" ]
    ! ls "$decoy".manifest-backup-* >/dev/null 2>&1
    rm -rf "$decoy_dir"
}

@test "cleanup_profile_entries with unset_env=1 unsets MANIFEST-prefixed vars in-process" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    _setup_seeded_profile_home
    manifest_install_paths_shell_profiles() { echo "$SANDBOX_HOME/.zshrc"; }
    export MANIFEST_CLI_TEST_SENTINEL=1
    manifest_install_paths_cleanup_profile_entries 1 1
    [ -z "${MANIFEST_CLI_TEST_SENTINEL:-}" ]
}

@test "cleanup_profile_entries with unset_env=0 leaves MANIFEST-prefixed vars in-process" {
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    _setup_seeded_profile_home
    manifest_install_paths_shell_profiles() { echo "$SANDBOX_HOME/.zshrc"; }
    export MANIFEST_CLI_TEST_SENTINEL=1
    manifest_install_paths_cleanup_profile_entries 0 0
    [ "${MANIFEST_CLI_TEST_SENTINEL:-}" = "1" ]
}
