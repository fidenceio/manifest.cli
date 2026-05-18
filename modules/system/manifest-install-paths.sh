#!/bin/bash

# Manifest Install Paths
#
# Single source of truth for filesystem locations the Manifest CLI installs,
# inspects, and removes. Every installer/uninstaller/upgrader code path
# (install-cli.sh, uninstall-cli.sh, modules/system/manifest-uninstall.sh, the
# Cloud auto-upgrade plugin) reads from here.
#
# Returning newline-separated strings from getters (rather than exporting
# arrays) keeps this module portable across subshells and pre-bash-4
# environments — exported bash arrays don't cross either reliably.

[ -n "$_MANIFEST_INSTALL_PATHS_LOADED" ] && return 0
_MANIFEST_INSTALL_PATHS_LOADED=1

# --- Homebrew ---------------------------------------------------------------

manifest_install_paths_homebrew_formula() { echo "fidenceio/tap/manifest"; }
manifest_install_paths_homebrew_tap()     { echo "fidenceio/tap"; }

manifest_install_paths_homebrew_tap_dir() {
    command -v brew >/dev/null 2>&1 || return 0
    local prefix
    prefix="$(brew --prefix 2>/dev/null || true)"
    [ -z "$prefix" ] && return 0
    echo "$prefix/Library/Taps/fidenceio/homebrew-tap"
}

manifest_install_paths_brew_completion_targets() {
    command -v brew >/dev/null 2>&1 || return 0
    local prefix
    prefix="$(brew --prefix 2>/dev/null || true)"
    [ -z "$prefix" ] && return 0
    echo "$prefix/etc/bash_completion.d/manifest"
    echo "$prefix/share/zsh/site-functions/_manifest"
}

# --- Install layout ---------------------------------------------------------

manifest_install_paths_global_state_dir() {
    echo "$HOME/.manifest-cli"
}

manifest_install_paths_user_global_config() {
    echo "$HOME/.manifest-cli/manifest.config.global.yaml"
}

manifest_install_paths_legacy_install_dir() {
    echo "/usr/local/share/manifest-cli"
}

manifest_install_paths_install_dirs() {
    echo "$HOME/.manifest-cli"
    echo "/usr/local/share/manifest-cli"
    [ -n "${MANIFEST_CLI_INSTALL_LOCATION:-}" ] && echo "$MANIFEST_CLI_INSTALL_LOCATION"
    [ -n "${MANIFEST_CLI_INSTALL_DIR:-}" ] && echo "$MANIFEST_CLI_INSTALL_DIR"
}

manifest_install_paths_user_bin_dir() {
    echo "$HOME/.local/bin"
}

manifest_install_paths_user_binary() {
    echo "$HOME/.local/bin/manifest"
}

manifest_install_paths_binary_candidates() {
    manifest_install_paths_user_binary
    echo "/usr/local/bin/manifest"
    echo "/opt/manifest-cli/bin/manifest"
}

# --- Config and runtime data ------------------------------------------------

manifest_install_paths_config_files() {
    echo "$HOME/.manifestrc"
    echo "$HOME/.manifest-cli.conf"
    echo "$HOME/.config/manifest-cli"
    manifest_install_paths_user_global_config
}

manifest_install_paths_data_dirs() {
    echo "$HOME/.manifest-agent"
    local tmpdir_cache="${TMPDIR:-/tmp}/manifest-cli"
    echo "$tmpdir_cache"
    [ "/tmp/manifest-cli" != "$tmpdir_cache" ] && echo "/tmp/manifest-cli"
}

# --- Shell profile cleanup --------------------------------------------------

manifest_install_paths_shell_profiles() {
    echo "$HOME/.zshrc"
    echo "$HOME/.zprofile"
    echo "$HOME/.zsh_profile"
    echo "$HOME/.bashrc"
    echo "$HOME/.bash_profile"
    echo "$HOME/.profile"
}

# Matches any shell-profile line that:
#   - exports a MANIFEST_* variable
#   - prepends .manifest-cli or .local/bin to PATH (installer-style)
#   - sources a manifest-related rc file
manifest_install_paths_profile_line_regex() {
    echo '^[[:space:]]*(export[[:space:]]+MANIFEST_[A-Z_]+=|export[[:space:]]+PATH=.*\.manifest-cli|export[[:space:]]+PATH=.*\.local/bin.*PATH|(\.|source)[[:space:]]+.*manifest)'
}
