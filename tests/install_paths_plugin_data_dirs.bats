#!/usr/bin/env bats
#
# manifest_install_paths_plugin_data_dirs contract:
#   - scans ${MANIFEST_CLI_CLOUD_DIR:-$HOME/.manifest-cloud}/cli-plugins/ for
#     *.data-dirs files
#   - emits one path per line; literal $HOME is the only allowed substitution
#   - silently drops comments, blank lines, and paths that don't resolve
#     under $HOME/ (defense-in-depth — plugin manifests can't request the
#     uninstaller delete /etc)

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    export MANIFEST_CLI_CLOUD_DIR="$SCRATCH/cloud"
    mkdir -p "$HOME"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
}

_write_manifest() {
    local rel="$1"; shift
    local path="$MANIFEST_CLI_CLOUD_DIR/cli-plugins/$rel"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$@" > "$path"
}

@test "returns nothing when no plugins dir exists" {
    rm -rf "$MANIFEST_CLI_CLOUD_DIR"
    run manifest_install_paths_plugin_data_dirs
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "returns nothing when plugins dir exists but has no .data-dirs files" {
    mkdir -p "$MANIFEST_CLI_CLOUD_DIR/cli-plugins/cloud"
    echo 'plugin code' > "$MANIFEST_CLI_CLOUD_DIR/cli-plugins/cloud/some-plugin.sh"
    run manifest_install_paths_plugin_data_dirs
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "emits a declared absolute-under-HOME path" {
    _write_manifest "cloud/agent.data-dirs" '$HOME/.manifest-agent'
    run manifest_install_paths_plugin_data_dirs
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.manifest-agent" ]
}

@test "expands literal \$HOME substitution" {
    _write_manifest "cloud/x.data-dirs" '$HOME/.foo'
    run manifest_install_paths_plugin_data_dirs
    [ "$output" = "$HOME/.foo" ]
}

@test "ignores '#' line comments and trailing inline comments" {
    _write_manifest "cloud/x.data-dirs" \
        '# header comment' \
        '$HOME/.foo  # inline reason' \
        '   # indented comment' \
        '$HOME/.bar'
    run manifest_install_paths_plugin_data_dirs
    [ "${lines[0]}" = "$HOME/.foo" ]
    [ "${lines[1]}" = "$HOME/.bar" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "ignores blank and whitespace-only lines" {
    _write_manifest "cloud/x.data-dirs" \
        '' \
        '   ' \
        '$HOME/.foo' \
        ''
    run manifest_install_paths_plugin_data_dirs
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "$HOME/.foo" ]
}

@test "drops paths that don't resolve under \$HOME/" {
    _write_manifest "cloud/x.data-dirs" \
        '/etc' \
        '/tmp/bad' \
        '$HOME/.ok'
    run manifest_install_paths_plugin_data_dirs
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "$HOME/.ok" ]
}

@test "drops bare \$HOME (no trailing slash) — must be a subpath" {
    _write_manifest "cloud/x.data-dirs" '$HOME'
    run manifest_install_paths_plugin_data_dirs
    [ -z "$output" ]
}

@test "unions paths across multiple plugins" {
    _write_manifest "cloud/a.data-dirs" '$HOME/.a'
    _write_manifest "workflow/b.data-dirs" '$HOME/.b'
    run manifest_install_paths_plugin_data_dirs
    [ "${#lines[@]}" -eq 2 ]
    # find | sort orders by path, so workflow comes after cloud alphabetically
    echo "$output" | grep -qx "$HOME/.a"
    echo "$output" | grep -qx "$HOME/.b"
}

@test "data_dirs() includes plugin-declared dirs" {
    _write_manifest "cloud/agent.data-dirs" '$HOME/.manifest-agent'
    run manifest_install_paths_data_dirs
    echo "$output" | grep -qx "$HOME/.manifest-agent"
}

@test "data_dirs() no longer hardcodes ~/.manifest-agent when no plugin declares it" {
    # No .data-dirs files written — output must not contain the legacy hardcode.
    mkdir -p "$MANIFEST_CLI_CLOUD_DIR/cli-plugins"
    run manifest_install_paths_data_dirs
    ! echo "$output" | grep -qx "$HOME/.manifest-agent"
}
