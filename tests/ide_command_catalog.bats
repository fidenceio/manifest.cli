#!/usr/bin/env bats
# bats file_tags=smoke

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    export MANIFEST_CLI_INSTALL_LOCATION="$SCRATCH/install"
    mkdir -p "$HOME" "$SCRATCH/work"
    source "$TEST_REPO_ROOT/install-cli.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "generated IDE and assistant catalogs teach retained commands" {
    run install_ide_command_catalog
    [ "$status" -eq 0 ]
    local filename removed
    for filename in manifest-cli-commands.md manifest-cli-commands.json AGENTS.md CLAUDE.md; do
        [ -s "$MANIFEST_CLI_IDE_SUPPORT_DIR/$filename" ]
        for removed in 'manifest first' 'manifest prep' 'manifest refresh' 'manifest sync' 'manifest time' 'manifest fleet ' 'manifest recipe run'; do
            refute grep -F "$removed" "$MANIFEST_CLI_IDE_SUPPORT_DIR/$filename"
        done
    done
    local catalog="$MANIFEST_CLI_IDE_SUPPORT_DIR/manifest-cli-commands.json"
    jq -e '.commands | index("manifest init") != null' "$catalog"
    jq -e '.commands | index("manifest init repo --connect") != null' "$catalog"
    jq -e '.commands | index("manifest ship fleet manager") != null' "$catalog"
    jq -e '.commands | index("manifest docs metadata") != null' "$catalog"
}

@test "setup release and documentation commands advertised to assistants have working help" {
    install_ide_command_catalog
    local command_line
    local -a args
    cd "$SCRATCH/work"
    while IFS= read -r command_line; do
        read -r -a args <<< "$command_line"
        run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "${args[@]:1}" --help
        [ "$status" -eq 0 ] || { printf '%s\n' "$command_line" "$output" >&2; return 1; }
        [[ "$output" == *"Usage:"* ]]
    done < <(jq -r '.commands[] | select(test("^manifest (init|ship|docs|revert)( |$)"))' \
        "$MANIFEST_CLI_IDE_SUPPORT_DIR/manifest-cli-commands.json")
}
