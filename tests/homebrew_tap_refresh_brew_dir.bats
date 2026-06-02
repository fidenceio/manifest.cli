#!/usr/bin/env bats

# E2e coverage for the brew-managed tap checkout candidate.
#
# tests/homebrew_tap_refresh.bats deliberately stubs `brew() { return 1; }` in
# its setup() so the candidate generator never walks into a real tap on the
# developer's machine. Correct for that file, but it means the production
# candidate — $(brew --prefix)/Library/Taps/fidenceio/homebrew-tap, emitted by
# manifest_homebrew_tap_checkout_candidates — is no longer exercised anywhere.
# That path runs on every `manifest refresh` and during ship's post-push
# auto-upgrade, so a regression in the candidate generator or in the refresher's
# iteration over the brew-managed dir would go uncaught.
#
# Here we do the opposite: stub `brew --prefix` to a scratch prefix (following
# the seed pattern in tests/homebrew_tap_ssh_restore.bats), seed a real tap
# checkout under its Library/Taps/fidenceio/homebrew-tap, and drive the
# refresher with two candidates present so the strict count summary is asserted.
# $HOME is isolated so git's global config never touches the real environment.

load 'helpers/setup'

setup() {
    load_modules "core/manifest-core.sh"
    SCRATCH="$(mk_scratch)"

    # Isolate $HOME so the per-checkout git config below cannot leak into (or
    # read from) the developer's real ~/.gitconfig.
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    git config --global init.defaultBranch main >/dev/null 2>&1 || true

    # PROJECT_ROOT points at a bare scratch dir with no workspace siblings so
    # the only candidates are the ones this file seeds deliberately.
    export PROJECT_ROOT="$SCRATCH/proj"
    mkdir -p "$PROJECT_ROOT"

    # Slug check is exercised by its own test below; the fast-forward/skip tests
    # bypass it the same way tests/homebrew_tap_refresh.bats does, so the seeded
    # origin can point at a local bare remote that is actually fetchable.
    export MANIFEST_CLI_HOMEBREW_TAP_SLUG=""
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_HOMEBREW_TAP_SLUG MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT
}

# Stub `brew --prefix` to the scratch prefix. Matches the seed-under-stubbed-
# brew-prefix pattern in tests/homebrew_tap_ssh_restore.bats; defined per test
# because bats stubs are scoped to the test body.
stub_brew_prefix() {
    brew() { case "$1" in "--prefix") echo "$SCRATCH/prefix";; *) return 0;; esac; }
}

# The brew-managed candidate path, resolved the same way the candidate generator
# resolves it. Not hardcoded into assertions beyond this single helper.
brew_managed_tap_dir() {
    echo "$SCRATCH/prefix/Library/Taps/fidenceio/homebrew-tap"
}

# Seed a bare remote with a single formula commit on `main`; echo its path.
seed_tap_remote() {
    local remote="$SCRATCH/homebrew-tap.git"
    local writer="$SCRATCH/writer"

    git init --bare -q "$remote"
    git clone -q "$remote" "$writer"
    git -C "$writer" checkout -q -b main
    git -C "$writer" config user.email "test@example.com"
    git -C "$writer" config user.name "Test"
    mkdir -p "$writer/Formula"
    echo "v1" > "$writer/Formula/manifest.rb"
    git -C "$writer" add Formula/manifest.rb
    git -C "$writer" commit -qm "Initial formula"
    git -C "$writer" push -q -u origin main
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

    echo "$remote"
}

push_tap_update() {
    local writer="$SCRATCH/writer"
    echo "$1" > "$writer/Formula/manifest.rb"
    git -C "$writer" add Formula/manifest.rb
    git -C "$writer" commit -qm "Update formula"
    git -C "$writer" push -q origin main
}

# Clone the seeded remote into a checkout dir, creating parents as needed.
clone_checkout() {
    local remote="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    git clone -q "$remote" "$dest"
}

@test "candidate generator emits the brew-managed tap dir under brew --prefix" {
    # Drift guard for manifest_homebrew_tap_checkout_candidates: if the
    # brew-managed path stops being generated (or its layout changes), this
    # fails and the regression is caught at the source rather than only as a
    # missing line in a count summary.
    stub_brew_prefix
    local got
    got="$(manifest_homebrew_tap_checkout_candidates "" | grep -F "$(brew_managed_tap_dir)")"
    [ "$got" = "$(brew_managed_tap_dir)" ]
}

@test "refresher fast-forwards both candidates (env + brew-managed dir)" {
    stub_brew_prefix
    local remote env_tap brew_tap
    remote="$(seed_tap_remote)"

    env_tap="$SCRATCH/env-checkout"
    brew_tap="$(brew_managed_tap_dir)"
    clone_checkout "$remote" "$env_tap"
    clone_checkout "$remote" "$brew_tap"
    export MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT="$env_tap"

    push_tap_update "v2"

    run manifest_refresh_homebrew_tap_checkouts ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Refreshed local Homebrew tap checkout: $env_tap"* ]]
    [[ "$output" == *"Refreshed local Homebrew tap checkout: $brew_tap"* ]]
    [[ "$output" == *"2 current/updated, 0 skipped, 0 failed"* ]]
    [ "$(cat "$env_tap/Formula/manifest.rb")" = "v2" ]
    [ "$(cat "$brew_tap/Formula/manifest.rb")" = "v2" ]
}

@test "refresher skips a dirty brew-managed dir while fast-forwarding the clean candidate" {
    stub_brew_prefix
    local remote env_tap brew_tap brew_before
    remote="$(seed_tap_remote)"

    env_tap="$SCRATCH/env-checkout"
    brew_tap="$(brew_managed_tap_dir)"
    clone_checkout "$remote" "$env_tap"
    clone_checkout "$remote" "$brew_tap"
    export MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT="$env_tap"

    brew_before="$(git -C "$brew_tap" rev-parse HEAD)"
    push_tap_update "v2"
    echo "local edit" >> "$brew_tap/Formula/manifest.rb"

    run manifest_refresh_homebrew_tap_checkouts ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Refreshed local Homebrew tap checkout: $env_tap"* ]]
    [[ "$output" == *"Skipped local Homebrew tap checkout: $brew_tap (dirty)"* ]]
    [[ "$output" == *"1 current/updated, 1 skipped, 0 failed"* ]]
    [ "$(cat "$env_tap/Formula/manifest.rb")" = "v2" ]
    # The dirty brew-managed checkout is left untouched at its prior commit.
    [ "$(git -C "$brew_tap" rev-parse HEAD)" = "$brew_before" ]
}

@test "refresher skips a divergent brew-managed dir while fast-forwarding the clean candidate" {
    stub_brew_prefix
    local remote env_tap brew_tap brew_before
    remote="$(seed_tap_remote)"

    env_tap="$SCRATCH/env-checkout"
    brew_tap="$(brew_managed_tap_dir)"
    clone_checkout "$remote" "$env_tap"
    clone_checkout "$remote" "$brew_tap"
    export MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT="$env_tap"

    # Give the brew-managed checkout a local commit the remote does not have, so
    # HEAD is no longer an ancestor of origin/main → divergent (not fast-forwardable).
    git -C "$brew_tap" config user.email "test@example.com"
    git -C "$brew_tap" config user.name "Test"
    echo "local-only" > "$brew_tap/Formula/manifest.rb"
    git -C "$brew_tap" commit -qam "Local-only divergent commit"
    brew_before="$(git -C "$brew_tap" rev-parse HEAD)"
    push_tap_update "v2"

    run manifest_refresh_homebrew_tap_checkouts ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Refreshed local Homebrew tap checkout: $env_tap"* ]]
    [[ "$output" == *"Skipped local Homebrew tap checkout: $brew_tap (divergent)"* ]]
    [[ "$output" == *"1 current/updated, 1 skipped, 0 failed"* ]]
    [ "$(cat "$env_tap/Formula/manifest.rb")" = "v2" ]
    [ "$(git -C "$brew_tap" rev-parse HEAD)" = "$brew_before" ]
}

@test "refresher skips the brew-managed dir when its origin slug is wrong" {
    # Faithful to the production guard: with the default slug expectation in
    # force, a brew-managed checkout whose origin is not fidenceio/homebrew-tap
    # is skipped (wrong_remote) rather than fast-forwarded.
    stub_brew_prefix
    unset MANIFEST_CLI_HOMEBREW_TAP_SLUG
    local remote brew_tap brew_before
    remote="$(seed_tap_remote)"

    brew_tap="$(brew_managed_tap_dir)"
    clone_checkout "$remote" "$brew_tap"
    # Re-point origin at a slug-resolvable but non-canonical URL.
    git -C "$brew_tap" remote set-url origin "git@github.com:someone-else/homebrew-tap.git"
    brew_before="$(git -C "$brew_tap" rev-parse HEAD)"

    run manifest_refresh_homebrew_tap_checkouts ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped local Homebrew tap checkout: $brew_tap (wrong_remote:someone-else/homebrew-tap)"* ]]
    [[ "$output" == *"0 current/updated, 1 skipped, 0 failed"* ]]
    [ "$(git -C "$brew_tap" rev-parse HEAD)" = "$brew_before" ]
}
