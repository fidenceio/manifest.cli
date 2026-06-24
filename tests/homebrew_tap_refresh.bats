#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-core.sh"
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/workspace/fidenceio.manifest.cli"
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT"
    git config --global init.defaultBranch main >/dev/null 2>&1 || true

    # Without this stub, manifest_homebrew_tap_checkout_candidates also walks
    # into $(brew --prefix)/Library/Taps/fidenceio/homebrew-tap on any dev
    # machine that has the real tap installed, polluting the refresh count.
    brew() { return 1; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

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

@test "safe fast-forward helper updates a clean checkout" {
    local remote tap
    remote="$(seed_tap_remote)"
    tap="$SCRATCH/tap"
    git clone -q "$remote" "$tap"
    push_tap_update "v2"

    run manifest_git_safe_fast_forward_checkout "$tap" "" "main" "origin"

    [ "$status" -eq 0 ]
    [ "$output" = "updated" ]
    [ "$(cat "$tap/Formula/manifest.rb")" = "v2" ]
}

@test "safe fast-forward helper skips dirty checkout" {
    local remote tap before
    remote="$(seed_tap_remote)"
    tap="$SCRATCH/tap"
    git clone -q "$remote" "$tap"
    before="$(git -C "$tap" rev-parse HEAD)"
    push_tap_update "v2"
    echo "local edit" >> "$tap/Formula/manifest.rb"

    run manifest_git_safe_fast_forward_checkout "$tap" "" "main" "origin"

    [ "$status" -eq 2 ]
    [ "$output" = "dirty" ]
    [ "$(git -C "$tap" rev-parse HEAD)" = "$before" ]
}

@test "Homebrew tap refresher updates sibling workspace checkout" {
    local remote tap
    remote="$(seed_tap_remote)"
    mkdir -p "$SCRATCH/workspace"
    tap="$SCRATCH/workspace/fidenceio.homebrew.tap"
    git clone -q "$remote" "$tap"
    push_tap_update "v2"
    export MANIFEST_CLI_HOMEBREW_TAP_SLUG=""

    run manifest_refresh_homebrew_tap_checkouts ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Refreshed local Homebrew tap checkout: $tap"* ]]
    [[ "$output" == *"1 current/updated, 0 skipped, 0 failed"* ]]
    [ "$(cat "$tap/Formula/manifest.rb")" = "v2" ]
}

@test "Homebrew tap refresher leaves dirty sibling checkout alone" {
    local remote tap before
    remote="$(seed_tap_remote)"
    mkdir -p "$SCRATCH/workspace"
    tap="$SCRATCH/workspace/fidenceio.homebrew.tap"
    git clone -q "$remote" "$tap"
    before="$(git -C "$tap" rev-parse HEAD)"
    push_tap_update "v2"
    echo "local edit" >> "$tap/Formula/manifest.rb"
    export MANIFEST_CLI_HOMEBREW_TAP_SLUG=""

    run manifest_refresh_homebrew_tap_checkouts ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped local Homebrew tap checkout: $tap (dirty)"* ]]
    [[ "$output" == *"0 current/updated, 1 skipped, 0 failed"* ]]
    [ "$(git -C "$tap" rev-parse HEAD)" = "$before" ]
}
