#!/usr/bin/env bats
# bats file_tags=smoke
#
# Tagged smoke because this is a WHOLE-TREE invariant, not a test of one module.
# `--changed` selects by path and always unions the smoke tier; a per-path map
# cannot express "this test compares every command surface at once", so without
# the tag no code change selects it (TRACKER §48).

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
first --help
init repo --help
init fleet --help
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
env generate --help
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

