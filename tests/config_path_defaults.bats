#!/usr/bin/env bats
#
# Regression: bash parameter-default expansion does NOT tilde-expand. A default
# written as "${X:-~/...}" sets X to the literal string "~/..." — and any code
# that joined "$HOME/$X/..." then produced "$HOME/~/...". This test pins the
# install-path defaults to absolute, $HOME-rooted values and the temp-list join
# to a non-doubling shape.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    # Wipe inherited values so we exercise the defaults, not the host config.
    unset MANIFEST_CLI_INSTALL_DIR MANIFEST_CLI_BIN_DIR MANIFEST_CLI_TEMP_DIR \
          MANIFEST_CLI_TEMP_LIST
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

@test "MANIFEST_CLI_TEMP_DIR default is absolute and rooted under \$HOME" {
    [ "${MANIFEST_CLI_TEMP_DIR:0:1}" = "/" ]
    [ "$MANIFEST_CLI_TEMP_DIR" = "$HOME/.manifest-cli" ]
}

@test "no install-path default contains a literal tilde" {
    # A regression here means parameter expansion bit us again — the right side
    # of \${X:-...} is not tilde-expanded; use \$HOME explicitly.
    case "$MANIFEST_CLI_INSTALL_DIR" in *'~'*) return 1 ;; esac
    case "$MANIFEST_CLI_BIN_DIR" in *'~'*) return 1 ;; esac
    case "$MANIFEST_CLI_TEMP_DIR" in *'~'*) return 1 ;; esac
}

@test "managed temp-list path does not double the HOME prefix" {
    # Source the function under test in this shell so we can probe the path it
    # would write. We don't actually invoke create_managed_temp_file — we just
    # verify the join shape used by shared-functions.sh agrees with the now
    # absolute MANIFEST_CLI_TEMP_DIR.
    local joined="$MANIFEST_CLI_TEMP_DIR/$MANIFEST_CLI_TEMP_LIST"
    case "$joined" in
        "$HOME"/'~'/*) return 1 ;;  # the old bug
        "$HOME"/*) ;;               # expected
        *) return 1 ;;
    esac
}
