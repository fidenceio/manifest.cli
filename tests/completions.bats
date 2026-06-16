#!/usr/bin/env bats

load 'helpers/setup'

@test "bash completion includes plan and reconcile" {
    grep -Eq 'top_cmds=.*(^| )plan( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'top_cmds=.*(^| )reconcile( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'top_cmds=.*(^| )recipe( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'first\|init\|plan\|reconcile' "$TEST_REPO_ROOT/completions/manifest.bash"
    ! grep -q 'quickstart' "$TEST_REPO_ROOT/completions/manifest.bash"
}

@test "bash completion includes first as a top command" {
    grep -Eq 'top_cmds="first ' "$TEST_REPO_ROOT/completions/manifest.bash"
}

@test "zsh completion includes plan and reconcile" {
    grep -q "'plan:Generate an adoption plan'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -q "'reconcile:Validate and apply an adoption plan'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -q "'recipe:Inspect workflow recipes'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -Eq 'first\|init\|plan\|reconcile' "$TEST_REPO_ROOT/completions/_manifest"
    ! grep -q 'quickstart' "$TEST_REPO_ROOT/completions/_manifest"
}

@test "zsh completion includes first as a top command and no longer offers quickstart" {
    grep -q "'first:" "$TEST_REPO_ROOT/completions/_manifest"
    ! grep -q 'quickstart' "$TEST_REPO_ROOT/completions/_manifest"
}

@test "fish completion includes plan and reconcile" {
    grep -q "a plan .*-d 'Generate an adoption plan'" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q "a reconcile .*-d 'Validate and apply an adoption plan'" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q "a recipe .*-d 'Inspect workflow recipes'" "$TEST_REPO_ROOT/completions/manifest.fish"
    grep -q "first init plan reconcile" "$TEST_REPO_ROOT/completions/manifest.fish"
    ! grep -q 'quickstart' "$TEST_REPO_ROOT/completions/manifest.fish"
}

@test "fish completion includes first as a top command and no longer offers quickstart" {
    grep -q "a first " "$TEST_REPO_ROOT/completions/manifest.fish"
    ! grep -q "a quickstart " "$TEST_REPO_ROOT/completions/manifest.fish"
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
    ! grep -q 'list show explain run help' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '--explain' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q 'recipe_subs=(list show explain help)' "$TEST_REPO_ROOT/completions/_manifest"
    ! grep -q 'recipe_subs=(list show explain run help)' "$TEST_REPO_ROOT/completions/_manifest"
    grep -q -- '--explain' "$TEST_REPO_ROOT/completions/_manifest"

    grep -q "__manifest_path recipe.*-a 'list show explain help'" "$TEST_REPO_ROOT/completions/manifest.fish"
    ! grep -q "list show explain run help" "$TEST_REPO_ROOT/completions/manifest.fish"
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
