#!/usr/bin/env bats

# Coverage for the opportunistic runtime-cache cleanup substrate:
# manifest_install_paths_cache_dirs() returns cache-sweep-safe roots only,
# and _manifest_runtime_maybe_cleanup_cache() honors its TTL gate, scope
# guards, and stale-age threshold.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
}

teardown() {
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# --- manifest_install_paths_cache_dirs --------------------------------------

@test "cache_dirs: emits TMPDIR cache and /tmp/manifest-cli when distinct" {
    export TMPDIR="$SCRATCH/custom-tmp"
    mkdir -p "$TMPDIR"
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    run manifest_install_paths_cache_dirs
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "$SCRATCH/custom-tmp/manifest-cli"
    echo "$output" | grep -q "^/tmp/manifest-cli$"
}

@test "cache_dirs: collapses to single line when TMPDIR is /tmp" {
    export TMPDIR=/tmp
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    run manifest_install_paths_cache_dirs
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
    [ "$output" = "/tmp/manifest-cli" ]
}

@test "cache_dirs: excludes plugin data dirs (safety boundary)" {
    local plugins_dir="$SCRATCH/cli-plugins"
    mkdir -p "$plugins_dir"
    echo '$HOME/.manifest-agent' > "$plugins_dir/cloud.data-dirs"
    export MANIFEST_CLI_CLOUD_DIR="$SCRATCH"
    export HOME="$SCRATCH"
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    run manifest_install_paths_cache_dirs
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "manifest-agent"
}

@test "cache_dirs: excludes \$HOME/.manifest-cli (user config state)" {
    export HOME="$SCRATCH"
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    run manifest_install_paths_cache_dirs
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -qF "$SCRATCH/.manifest-cli"
}

# --- _manifest_runtime_maybe_cleanup_cache ----------------------------------

@test "runtime cleanup: TTL marker fresh → no-op (stale file survives)" {
    export TMPDIR="$SCRATCH"
    local cache="$SCRATCH/manifest-cli"
    mkdir -p "$cache"
    touch -t 200001010000 "$cache/stale.file"
    date -u +%s > "$cache/runtime-cleanup.last"

    source "$TEST_REPO_ROOT/modules/system/manifest-runtime-cleanup.sh"
    _manifest_runtime_maybe_cleanup_cache

    [ -f "$cache/stale.file" ]
}

@test "runtime cleanup: TTL elapsed → stale files deleted, marker refreshed" {
    export TMPDIR="$SCRATCH"
    local cache="$SCRATCH/manifest-cli"
    mkdir -p "$cache"
    touch -t 200001010000 "$cache/stale.file"
    # No marker yet → TTL gate passes on first fire.

    source "$TEST_REPO_ROOT/modules/system/manifest-runtime-cleanup.sh"
    _manifest_runtime_maybe_cleanup_cache

    [ ! -f "$cache/stale.file" ]
    [ -f "$cache/runtime-cleanup.last" ]
}

@test "runtime cleanup: recent files survive sweep" {
    export TMPDIR="$SCRATCH"
    local cache="$SCRATCH/manifest-cli"
    mkdir -p "$cache"
    touch "$cache/recent.file"

    source "$TEST_REPO_ROOT/modules/system/manifest-runtime-cleanup.sh"
    _manifest_runtime_maybe_cleanup_cache

    [ -f "$cache/recent.file" ]
}

@test "runtime cleanup: cache directory and subdirs preserved after sweep" {
    export TMPDIR="$SCRATCH"
    local cache="$SCRATCH/manifest-cli"
    mkdir -p "$cache/time"
    touch -t 200001010000 "$cache/time/stale.cache"

    source "$TEST_REPO_ROOT/modules/system/manifest-runtime-cleanup.sh"
    _manifest_runtime_maybe_cleanup_cache

    [ -d "$cache" ]
    [ -d "$cache/time" ]
    [ ! -f "$cache/time/stale.cache" ]
}

@test "runtime cleanup: plugin data dirs never touched" {
    export HOME="$SCRATCH"
    export TMPDIR="$SCRATCH/tmp"
    mkdir -p "$TMPDIR/manifest-cli"
    local plugin_data="$SCRATCH/.manifest-agent"
    mkdir -p "$plugin_data"
    touch -t 200001010000 "$plugin_data/stale-but-protected.file"

    # Wire plugin manifest so the path is plugin-declared (would be returned
    # by plugin_data_dirs but must never be returned by cache_dirs).
    mkdir -p "$SCRATCH/cli-plugins"
    echo '$HOME/.manifest-agent' > "$SCRATCH/cli-plugins/cloud.data-dirs"
    export MANIFEST_CLI_CLOUD_DIR="$SCRATCH"

    source "$TEST_REPO_ROOT/modules/system/manifest-runtime-cleanup.sh"
    _manifest_runtime_maybe_cleanup_cache

    [ -f "$plugin_data/stale-but-protected.file" ]
}

@test "runtime cleanup: refuses paths failing safety guard" {
    # Inject a hostile cache_dirs override that returns /, $HOME, /tmp,
    # and a sibling path missing 'manifest-cli'. None should be swept.
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    touch -t 200001010000 "$HOME/important.file"
    local sibling="$SCRATCH/not-our-namespace"
    mkdir -p "$sibling"
    touch -t 200001010000 "$sibling/sibling.file"

    source "$TEST_REPO_ROOT/modules/system/manifest-runtime-cleanup.sh"

    # Override cache_dirs() in-process to return unsafe paths.
    manifest_install_paths_cache_dirs() {
        echo "/"
        echo "$HOME"
        echo "/tmp"
        echo "$sibling"
    }

    _manifest_runtime_maybe_cleanup_cache

    [ -f "$HOME/important.file" ]
    [ -f "$sibling/sibling.file" ]
}
