#!/usr/bin/env bats

load 'helpers/setup'

@test "bash completion includes plan and reconcile" {
    grep -Eq 'top_cmds=.*(^| )plan( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'top_cmds=.*(^| )reconcile( |")' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -Eq 'init\|quickstart\|plan\|reconcile' "$TEST_REPO_ROOT/completions/manifest.bash"
}

@test "zsh completion includes plan and reconcile" {
    grep -q "'plan:Generate an adoption plan'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -q "'reconcile:Validate and apply an adoption plan'" "$TEST_REPO_ROOT/completions/_manifest"
    grep -Eq 'init\|quickstart\|plan\|reconcile' "$TEST_REPO_ROOT/completions/_manifest"
}

@test "completions expose fleet adoption flags" {
    grep -q '"plan fleet"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q '"reconcile fleet"' "$TEST_REPO_ROOT/completions/manifest.bash"
    grep -q -- '--adopt-submodules' "$TEST_REPO_ROOT/completions/_manifest"
}
