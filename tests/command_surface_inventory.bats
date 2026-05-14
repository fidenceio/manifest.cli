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
