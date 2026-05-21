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
