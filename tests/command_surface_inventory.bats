#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest_from_plain_dir() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

mutating_help_surfaces() {
    cat <<'EOF'
init repo --help
init fleet --help
quickstart fleet --help
prep repo --help
prep fleet --help
refresh repo --help
refresh fleet --help
ship repo --help
ship fleet --help
docs --help
docs fleet help
add fleet --help
update fleet --help
config doctor --help
config set --help
config unset --help
pr create --help
pr ready --help
pr merge --help
pr update --help
pr fleet help
uninstall --help
reinstall --help
EOF
}

@test "mutating command help surfaces advertise explicit preview and apply flags" {
    local command_line args

    while IFS= read -r command_line; do
        [[ -n "$command_line" ]] || continue
        read -r -a args <<< "$command_line"

        run_manifest_from_plain_dir "${args[@]}"
        [ "$status" -eq 0 ]
        [[ "$output" == *"--dry-run"* ]]
        [[ "$output" == *"-y"* ]]
        [[ "$output" == *"--yes"* ]]
    done < <(mutating_help_surfaces)
}

@test "documentation generation has no stale live symbol names" {
    local old_repo_symbol old_fleet_symbol old_yaml old_env
    old_repo_symbol="generate_""documents"
    old_fleet_symbol="fleet_docs_""generate"
    old_yaml="docs.auto_""generate"
    old_env="MANIFEST_CLI_DOCS_AUTO_""GENERATE"

    run bash -c '
        set -euo pipefail
        root="$1"
        shift
        find "$root" \
            \( -path "*/zArchive/*" -o -path "*/.git/*" \) -prune -o \
            -type f \
            ! -path "*/tests/command_surface_inventory.bats" \
            -print0 |
        xargs -0 grep -nE "$*" || true
    ' _ "$TEST_REPO_ROOT" "$old_repo_symbol|$old_fleet_symbol|$old_yaml|$old_env"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "public command docs do not invert scope grammar" {
    local bad_ship bad_refresh
    bad_ship="manifest repo ship"
    bad_refresh="manifest repo refresh"

    run bash -c '
        set -euo pipefail
        root="$1"
        shift
        find "$root" \
            \( -path "*/zArchive/*" -o -path "*/.git/*" \) -prune -o \
            -type f \
            ! -path "*/tests/command_surface_inventory.bats" \
            -print0 |
        xargs -0 grep -nE "$*" || true
    ' _ "$TEST_REPO_ROOT" "$bad_ship|$bad_refresh"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
