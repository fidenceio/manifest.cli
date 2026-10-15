#!/usr/bin/env bats

load 'helpers/setup'

@test "bash completion offers supported scopes and guided init options" {
    # Exercise completion output, rather than only checking its source text.
    source "$TEST_REPO_ROOT/completions/manifest.bash"
    local verb
    COMP_CWORD=2
    for verb in plan reconcile discover update add validate topics; do
        COMP_WORDS=(manifest "$verb" "")
        _manifest_complete
        [ "${COMPREPLY[*]}" = fleet ]
    done
    COMP_WORDS=(manifest init "")
    _manifest_complete
    [[ " ${COMPREPLY[*]} " == *' repo '* ]]
    [[ " ${COMPREPLY[*]} " == *' fleet '* ]]
    [[ " ${COMPREPLY[*]} " == *' --yes '* ]]
    COMP_WORDS=(manifest revert "")
    _manifest_complete
    [ "${COMPREPLY[*]}" = 'repo fleet --help' ]
    COMP_CWORD=1
    COMP_WORDS=(manifest "")
    _manifest_complete
    [[ " ${COMPREPLY[*]} " == *' init '* ]]
    for verb in first refresh sync time fleet; do
        [[ " ${COMPREPLY[*]} " != *" $verb "* ]]
    done
}

@test "bash completion includes plan and reconcile" {
    grep -Eq 'top_cmds=.*(^| )plan( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'top_cmds=.*(^| )reconcile( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'top_cmds=.*(^| )recipe( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'plan\|reconcile\|discover' "$TEST_REPO_ROOT/completions/manifest.bash"
}

@test "bash completion includes init as a top command" {
    grep -Eq 'top_cmds="config init ' "$TEST_REPO_ROOT/completions/manifest.bash"
}

@test "zsh completion includes plan and reconcile" {
    grep -q "'plan:Generate an adoption plan'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -q "'reconcile:Validate and apply an adoption plan'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -q "'recipe:Inspect workflow recipes'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -Eq 'plan\|reconcile\|discover' "$TEST_REPO_ROOT/completions/_manifest"
}

@test "zsh completion includes init as a top command" {
    grep -q "'init:" "$TEST_REPO_ROOT/completions/_manifest"
}

@test "fish completion includes plan and reconcile" {
    grep -q "a plan .*-d 'Generate an adoption plan'" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q "a reconcile .*-d 'Validate and apply an adoption plan'" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q "a recipe .*-d 'Inspect workflow recipes'" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q "for cmd in plan reconcile discover" "$TEST_REPO_ROOT/completions/manifest.fish"
}

@test "fish completion includes init as a top command" {
    grep -q "a init " "$TEST_REPO_ROOT/completions/manifest.fish"
}

@test "completions expose fleet adoption flags" {
    grep -q '"plan fleet"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q '"reconcile fleet"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '--adopt-submodules' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q '__manifest_path reconcile fleet' "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q -- '--adopt-submodules' "$TEST_REPO_ROOT/completions/manifest.fish"
}

@test "completions expose recipe and explain surfaces" {
    grep -q 'list show explain help' "$TEST_REPO_ROOT/completions/manifest.bash"
    refute grep -q 'list show explain run help' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '--explain' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q 'recipe_subs=(list show explain help)' "$TEST_REPO_ROOT/completions/_manifest"
    refute grep -q 'recipe_subs=(list show explain run help)' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q -- '--explain' "$TEST_REPO_ROOT/completions/_manifest"

    grep -q "__manifest_path recipe.*-a 'list show explain help'" "$TEST_REPO_ROOT/completions/manifest.fish"
    refute grep -q "list show explain run help" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q -- '--explain' "$TEST_REPO_ROOT/completions/manifest.fish"
}

@test "completions expose safe-by-default PR apply and preview flags" {
    grep -q 'local pr_subs="create status checks ready merge update queue policy fleet help"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q '"pr create"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q '"pr fleet"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '-y --yes --dry-run --draft' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '-y --yes --dry-run --method' "$TEST_REPO_ROOT/completions/manifest.bash"

    grep -q 'pr_subs=(create status checks ready merge update queue policy fleet help)' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q '"pr create"' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q '"pr fleet"' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q -- '-y --yes --dry-run --draft' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q -- '-y --yes --dry-run --method' "$TEST_REPO_ROOT/completions/_manifest"

    grep -q "create status checks ready merge update queue policy fleet help" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q '__manifest_path pr create' "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q '__manifest_path pr fleet' "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q -- '-y --yes --dry-run --draft' "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q -- '-y --yes --dry-run --method' "$TEST_REPO_ROOT/completions/manifest.fish"
}

@test "completions expose uninstall and reinstall safe-by-default flags" {
    grep -q 'uninstall)' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q 'reinstall)' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '-y --yes --dry-run --force --help' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '-y --yes --dry-run --help' "$TEST_REPO_ROOT/completions/manifest.bash"

    grep -q 'uninstall)' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q 'reinstall)' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q -- '-y --yes --dry-run --force --help' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q -- '-y --yes --dry-run --help' "$TEST_REPO_ROOT/completions/_manifest"

    grep -q '__manifest_path uninstall' "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q '__manifest_path reinstall' "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q -- '-y --yes --dry-run --force --help' "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q -- '-y --yes --dry-run --help' "$TEST_REPO_ROOT/completions/manifest.fish"
}

@test "completions offer fleet as a read-only config list layer" {
    # 'fleet' is readable but not writable, so it must be offered to
    # `config list` and withheld from set/unset in every shell.
    grep -q 'read_layers="global project local fleet"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q 'write_layers="global project local"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q 'read_layers=(global project local fleet)' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q 'write_layers=(global project local)' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q -- "-a 'global project local fleet'" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q -- "-a 'global project local'" "$TEST_REPO_ROOT/completions/manifest.fish"
}
