#!/usr/bin/env bats

# Focused unit tests for manifest_ship_restore_tap_ssh_origin.
#
# These tests intentionally avoid hardcoded literals for the tap-dir layout
# and the SSH URL. The tap-dir path comes from manifest_install_paths_homebrew_tap_dir
# (so if that helper ever changes the layout, this suite follows). The SSH URL
# comes from MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL with a per-test fixture value
# — we test the *contract* (helper writes the configured URL onto origin), not
# the production default.
#
# A separate test pins the production default explicitly so a silent change is
# caught.

load 'helpers/setup'

setup() {
    load_modules \
        "system/manifest-install-paths.sh" \
        "workflow/manifest-orchestrator.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL
}

# Create a fake tap dir at the path manifest_install_paths_homebrew_tap_dir
# resolves to under a stubbed BREW_PREFIX. Stubs are local to the caller's
# shell scope (which in bats is the test body).
seed_tap_under_stubbed_brew_prefix() {
    local prefix="$1"
    local origin_url="$2"
    local tap_dir="$prefix/Library/Taps/fidenceio/homebrew-tap"
    mkdir -p "$tap_dir"
    git init -q "$tap_dir"
    git -C "$tap_dir" remote add origin "$origin_url"
    echo "$tap_dir"
}

@test "rewrites origin to MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL" {
    local tap_dir
    tap_dir="$(seed_tap_under_stubbed_brew_prefix "$SCRATCH/prefix" "https://example.invalid/clone.git")"
    brew() { case "$1" in "--prefix") echo "$SCRATCH/prefix";; *) return 0;; esac; }
    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="ssh://fixture.example/tap.git"

    run manifest_ship_restore_tap_ssh_origin
    [ "$status" -eq 0 ]
    [ "$(git -C "$tap_dir" remote get-url origin)" = "ssh://fixture.example/tap.git" ]
}

@test "no-op when brew is absent (install-paths helper returns empty)" {
    # Force the install-paths helper to return empty by removing brew from
    # PATH for the duration of the helper call. The helper must NOT touch
    # any pre-existing tap dir on the developer's machine.
    PATH="/usr/bin:/bin" run manifest_ship_restore_tap_ssh_origin
    [ "$status" -eq 0 ]
}

@test "no-op when the tap dir does not exist on disk" {
    brew() { case "$1" in "--prefix") echo "$SCRATCH/empty-prefix";; *) return 0;; esac; }
    mkdir -p "$SCRATCH/empty-prefix"
    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="ssh://fixture.example/tap.git"

    run manifest_ship_restore_tap_ssh_origin
    [ "$status" -eq 0 ]
}

@test "no-op when the tap dir exists but has no .git" {
    brew() { case "$1" in "--prefix") echo "$SCRATCH/prefix";; *) return 0;; esac; }
    mkdir -p "$SCRATCH/prefix/Library/Taps/fidenceio/homebrew-tap"
    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="ssh://fixture.example/tap.git"

    run manifest_ship_restore_tap_ssh_origin
    [ "$status" -eq 0 ]
}

@test "drift guard: resolves tap dir via manifest_install_paths_homebrew_tap_dir" {
    # If the helper ever stops delegating to install-paths and inlines the
    # path itself, the inlined path won't match this fixture and the assertion
    # fails. This is the test that catches path drift between call sites.
    local fixture_tap="$SCRATCH/custom-tap-loc"
    git init -q "$fixture_tap"
    git -C "$fixture_tap" remote add origin "https://example.invalid/x.git"
    manifest_install_paths_homebrew_tap_dir() { echo "$fixture_tap"; }
    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="ssh://drift-guard.example/tap.git"

    run manifest_ship_restore_tap_ssh_origin
    [ "$status" -eq 0 ]
    [ "$(git -C "$fixture_tap" remote get-url origin)" = "ssh://drift-guard.example/tap.git" ]
}

@test "production default URL is the SSH form for fidenceio/homebrew-tap" {
    # Pin the production default so a silent change to the fallback (e.g. an
    # accidental switch to HTTPS) is caught. Other tests exercise behavior
    # via the env var override; this one tests the no-override path.
    local fixture_tap="$SCRATCH/default-tap"
    git init -q "$fixture_tap"
    git -C "$fixture_tap" remote add origin "https://example.invalid/x.git"
    manifest_install_paths_homebrew_tap_dir() { echo "$fixture_tap"; }
    unset MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL

    run manifest_ship_restore_tap_ssh_origin
    [ "$status" -eq 0 ]
    [ "$(git -C "$fixture_tap" remote get-url origin)" = "git@github.com:fidenceio/homebrew-tap.git" ]
}
