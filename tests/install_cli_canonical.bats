#!/usr/bin/env bats
#
# Asserts that there is exactly one canonical install_cli pipeline:
# install-cli.sh in the Manifest CLI repo. The Cloud auto-upgrade plugin
# must not redefine install_cli or cleanup_old_installation, and the
# CLI's `reinstall` / `upgrade --force` non-brew paths must delegate to
# install-cli.sh.
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

@test "cloud plugin no longer defines install_cli" {
    local plugin
    plugin="$(_cloud_plugin_path)" || skip "Cloud plugin not reachable from $TEST_REPO_ROOT"

    # The plugin file must not contain a function definition for install_cli.
    # We grep for the canonical bash function-definition shape so a `install_cli`
    # *call* in a comment or string doesn't false-positive.
    ! grep -qE '^[[:space:]]*install_cli[[:space:]]*\(\)[[:space:]]*\{' "$plugin"
}

@test "cloud plugin no longer defines cleanup_old_installation" {
    local plugin
    plugin="$(_cloud_plugin_path)" || skip "Cloud plugin not reachable"

    ! grep -qE '^[[:space:]]*cleanup_old_installation[[:space:]]*\(\)[[:space:]]*\{' "$plugin"
}

@test "cloud plugin's upgrade_cli_internal delegates to install-cli.sh on non-brew hosts" {
    local plugin
    plugin="$(_cloud_plugin_path)" || skip "Cloud plugin not reachable"

    # The non-brew upgrade branch must invoke install-cli.sh from PROJECT_ROOT.
    grep -qF 'bash "$PROJECT_ROOT/install-cli.sh"' "$plugin"
    # And must NOT call the deleted helpers.
    ! grep -qE '(^|[^a-zA-Z_])install_cli[[:space:]]+"' "$plugin"
}

@test "manifest-core.sh reinstall non-brew path delegates to install-cli.sh" {
    grep -qF 'bash "$PROJECT_ROOT/install-cli.sh"' "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    # The dropped plugin-based reinstall pattern must be gone.
    ! grep -qE 'manifest_load_plugin "workflow/manifest-auto-upgrade.sh".*install_cli' \
        "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
}

@test "no CLI repo .sh file other than install-cli.sh defines install_cli" {
    # install_cli is install-cli.sh's job, full stop. Any other definition is
    # the partial-reimplementation pattern we just deleted.
    local offenders
    offenders="$(grep -rlE '^[[:space:]]*install_cli[[:space:]]*\(\)[[:space:]]*\{' \
        --include='*.sh' \
        "$TEST_REPO_ROOT/modules" \
        "$TEST_REPO_ROOT/scripts" \
        2>/dev/null || true)"

    # Strip any acceptable hits (currently none).
    if [ -n "$offenders" ]; then
        echo "Offending files:" >&2
        echo "$offenders" >&2
        return 1
    fi
}

@test "manifest_install_paths module is reachable from a fresh shell" {
    # Cloud plugin and the canonical install loop both depend on the paths
    # module being source-able from MANIFEST_CLI_CORE_MODULES_DIR.
    MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules" \
        bash -c 'source "$MANIFEST_CLI_CORE_MODULES_DIR/system/manifest-install-paths.sh" && [ -n "$(manifest_install_paths_homebrew_formula)" ]'
}
