#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Regression: bash parameter-default expansion does NOT tilde-expand. A default
# written as "${X:-~/...}" sets X to the literal string "~/..." — and any code
# that joined "$HOME/$X/..." then produced "$HOME/~/...". This test pins the
# install-path defaults to absolute, $HOME-rooted values.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    # Wipe inherited values so we exercise the defaults, not the host config.
    unset MANIFEST_CLI_INSTALL_DIR MANIFEST_CLI_BIN_DIR
    load_modules "core/manifest-config.sh"
    set_default_configuration
}

@test "MANIFEST_CLI_INSTALL_DIR default is absolute and rooted under \$HOME" {
    [ "${MANIFEST_CLI_INSTALL_DIR:0:1}" = "/" ]
    [ "$MANIFEST_CLI_INSTALL_DIR" = "$HOME/.manifest-cli" ]
}

@test "MANIFEST_CLI_BIN_DIR default is absolute and rooted under \$HOME" {
    [ "${MANIFEST_CLI_BIN_DIR:0:1}" = "/" ]
    [ "$MANIFEST_CLI_BIN_DIR" = "$HOME/.local/bin" ]
}

@test "no install-path default contains a literal tilde" {
    # A regression here means parameter expansion bit us again — the right side
    # of \${X:-...} is not tilde-expanded; use \$HOME explicitly.
    case "$MANIFEST_CLI_INSTALL_DIR" in *'~'*) return 1 ;; esac
    case "$MANIFEST_CLI_BIN_DIR" in *'~'*) return 1 ;; esac
}
