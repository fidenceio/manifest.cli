#!/usr/bin/env bats
#
# install_via_homebrew() and remove_brew_managed_install() in install-cli.sh,
# driven end-to-end by a recording `brew` stub on PATH. The stub's --cellar
# answer points at a sandbox Cellar dir, so the canonical provenance predicate
# (manifest_install_paths_is_brew_managed) is exercised for real: an empty
# Cellar routes to `brew install`, a present manifest keg routes to
# `brew upgrade` / the uninstall path. No real brew, no network.
#
# remove_brew_managed_install goes through the destructive-brew sandbox
# tripwire; under bats the tripwire refuses, so the uninstall invocation is
# only reachable via MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 against the
# stub (same escape-hatch pattern as uninstall_sandbox_tripwire.bats).

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"

    BREW_LOG="$SCRATCH/brew-calls.log"
    : > "$BREW_LOG"
    export BREW_LOG
    CELLAR="$SCRATCH/cellar"
    mkdir -p "$CELLAR"
    export CELLAR

    # Recording brew stub: every invocation is appended to BREW_LOG.
    # `--cellar` answers with the sandbox Cellar; `list` fails (nothing
    # installed as far as brew's stateful query is concerned); everything
    # else (tap, trust, install, upgrade, uninstall) succeeds.
    STUB="$SCRATCH/bin"
    mkdir -p "$STUB"
    cat > "$STUB/brew" <<EOF
#!/bin/bash
echo "\$*" >> "$BREW_LOG"
case "\$1" in
    --cellar) echo "$CELLAR"; exit 0 ;;
    list)     exit 1 ;;
    *)        exit 0 ;;
esac
EOF
    chmod +x "$STUB/brew"
    export PATH="$STUB:$PATH"

    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "install_via_homebrew: fresh machine taps, trusts, and installs the formula" {
    run install_via_homebrew
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Tapped fidenceio/tap"
    echo "$output" | grep -q "Trusted formula fidenceio/tap/manifest"
    echo "$output" | grep -q "Manifest CLI installed via Homebrew"
    # Exact brew subcommands, in the recording log.
    grep -qx "tap fidenceio/tap" "$BREW_LOG"
    grep -qx "trust --formula fidenceio/tap/manifest" "$BREW_LOG"
    grep -qx "install fidenceio/tap/manifest" "$BREW_LOG"
    # Fresh machine → the upgrade branch must not fire.
    ! grep -q "^upgrade" "$BREW_LOG"
}

@test "install_via_homebrew: existing brew-managed install routes to upgrade, not install" {
    # A manifest keg in the Cellar is the authoritative brew-managed signal.
    mkdir -p "$CELLAR/manifest/1.0.0"
    run install_via_homebrew
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "already installed via Homebrew, upgrading"
    echo "$output" | grep -q "Manifest CLI installed via Homebrew"
    grep -qx "upgrade fidenceio/tap/manifest" "$BREW_LOG"
    ! grep -qx "install fidenceio/tap/manifest" "$BREW_LOG"
}

@test "install_via_homebrew: failed tap aborts with an error before any install" {
    # Re-point the stub: `tap` fails, everything else still records.
    cat > "$STUB/brew" <<EOF
#!/bin/bash
echo "\$*" >> "$BREW_LOG"
case "\$1" in
    tap) exit 1 ;;
    *)   exit 0 ;;
esac
EOF
    run install_via_homebrew
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Failed to tap fidenceio/tap"
    # Nothing beyond the failed tap was attempted.
    ! grep -q "install" "$BREW_LOG"
    ! grep -q "upgrade" "$BREW_LOG"
}

@test "remove_brew_managed_install: no brew-managed copy is a silent no-op" {
    # Empty Cellar + failing `brew list` → not brew-managed → early return 0.
    run remove_brew_managed_install
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    ! grep -q "uninstall" "$BREW_LOG"
}

@test "remove_brew_managed_install: sandbox tripwire blocks brew uninstall under bats" {
    mkdir -p "$CELLAR/manifest/1.0.0"
    run remove_brew_managed_install
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Removing Homebrew-managed Manifest"
    echo "$output" | grep -q "brew uninstall skipped by sandbox tripwire"
    # The stub was never asked to uninstall anything.
    ! grep -q "uninstall" "$BREW_LOG"
}

@test "remove_brew_managed_install: escape hatch drives brew uninstall of the tap formula" {
    mkdir -p "$CELLAR/manifest/1.0.0"
    MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 run remove_brew_managed_install
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Removed Homebrew-managed Manifest"
    grep -qx "uninstall fidenceio/tap/manifest" "$BREW_LOG"
    # The tap-qualified uninstall succeeded → no bare-name fallback call.
    ! grep -qx "uninstall manifest" "$BREW_LOG"
}
