#!/usr/bin/env bats
#
# Asserts the canonical install_cli pipeline: install-cli.sh in this repo,
# with Cloud auto-upgrade and CLI reinstall/upgrade non-brew paths delegating
# to it.
#
# The Cloud plugin file lives in a sibling repo (fidenceio.manifest.cloud).
# Tests skip if the sibling isn't reachable so the CLI repo can be tested
# in isolation (CI, fresh clones).

load 'helpers/setup'

_cloud_plugin_path() {
    local p="$TEST_REPO_ROOT/../fidenceio.manifest.cloud/cli-plugins/workflow/manifest-auto-upgrade.sh"
    [ -f "$p" ] || return 1
    echo "$p"
}

@test "cloud plugin's upgrade_cli_internal delegates to install-cli.sh on non-brew hosts" {
    local plugin
    plugin="$(_cloud_plugin_path)" || skip "Cloud plugin not reachable from $TEST_REPO_ROOT"

    grep -qF 'bash "$MANIFEST_CLI_PROJECT_ROOT/install-cli.sh"' "$plugin"
}

@test "manifest-core.sh reinstall non-brew path delegates to install-cli.sh" {
    grep -qF 'bash "$MANIFEST_CLI_PROJECT_ROOT/install-cli.sh"' "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
}

@test "install_cli is defined only in install-cli.sh among CLI shell sources" {
    local offenders
    offenders="$(grep -rlE '^[[:space:]]*install_cli[[:space:]]*\(\)[[:space:]]*\{' \
        --include='*.sh' \
        "$TEST_REPO_ROOT/modules" \
        "$TEST_REPO_ROOT/scripts" \
        2>/dev/null || true)"

    if [ -n "$offenders" ]; then
        echo "Offending files:" >&2
        echo "$offenders" >&2
        return 1
    fi
}

@test "manifest_install_paths module is reachable from a fresh shell" {
    MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules" \
        bash -c 'source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-install-paths.sh" && [ -n "$(manifest_install_paths_homebrew_formula)" ]'
}
