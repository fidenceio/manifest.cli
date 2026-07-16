#!/usr/bin/env bats
#
# manifest_install_paths_is_manual_install — the companion provenance predicate
# to is_brew_managed (modules/system/manifest-install-paths.sh). A manual
# (source-tree) install writes the version-agnostic wrapper to
# $HOME/.local/bin/manifest; a Homebrew install never does. These unit tests
# mirror the is_brew_managed fixture style in local_install_upgrade.bats.

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

@test "is_manual_install: wrapper at ~/.local/bin/manifest marks the source channel" {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/bash\n# Manifest CLI wrapper\n' > "$HOME/.local/bin/manifest"
    run manifest_install_paths_is_manual_install
    [ "$status" -eq 0 ]
}

@test "is_manual_install: no wrapper binary means no manual install" {
    mkdir -p "$HOME/.local/bin"   # dir exists, wrapper file does not
    run manifest_install_paths_is_manual_install
    [ "$status" -eq 1 ]
}

@test "is_manual_install: a brew-shaped layout without the wrapper is NOT a manual install" {
    # Brew-managed fixture (Cellar keg, mirrors local_install_upgrade.bats §8.13
    # tests) — the predicate must key ONLY off the user-bin wrapper, never off
    # brew state, so the two provenance predicates stay independent.
    local cellar="$SCRATCH/cellar"
    mkdir -p "$cellar/manifest/1.2.3"
    brew() {
        case "$1" in
            --cellar) echo "$cellar"; return 0 ;;
            *)        return 0 ;;
        esac
    }
    run manifest_install_paths_is_manual_install
    [ "$status" -eq 1 ]
}
