#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the .gitignore scaffolded at init time (create_default_gitignore /
# ensure_gitignore_smart). Pins universal hygiene: local/secret/generated config
# is ignored by default, .env value files are ignored with example/template
# carve-outs kept trackable, and NO blanket *.yaml/*.yml ignore (tracked
# authoring specs — service.spec.yaml, openapi.yaml, k8s manifests — must stay
# trackable).

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    GI="$PROJ/.gitignore"
    create_default_gitignore "$GI"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "gitignore: .env value files are ignored with example/template carve-outs" {
    grep -qx '.env' "$GI"
    grep -qx '.env.*' "$GI"
    grep -qx '!.env.example' "$GI"
    grep -qx '!.env.template' "$GI"
}

@test "gitignore: local config variants are ignored" {
    grep -qx '\*.local.yaml' "$GI"
    grep -qx '\*.local.yml' "$GI"
    grep -qx '\*.local.json' "$GI"
    grep -qx '\*.local.toml' "$GI"
}

@test "gitignore: secret config variants are ignored" {
    grep -qx '\*.secret.yaml' "$GI"
    grep -qx '\*.secret.json' "$GI"
    grep -qx '\*.secret.*' "$GI"
}

@test "gitignore: example/template authoring variants stay trackable" {
    grep -qx '!\*.example.yaml' "$GI"
    grep -qx '!\*.template.yaml' "$GI"
}

@test "gitignore: NO blanket *.yaml or *.yml ignore" {
    ! grep -qxE '\*\.ya?ml' "$GI"
}

@test "gitignore: an unignored authoring spec is not matched by the local/secret rules" {
    # Sanity: git honors the file — service.spec.yaml / openapi.yaml stay tracked.
    cd "$PROJ"
    git init -q .
    : > service.spec.yaml
    : > openapi.yaml
    : > config.local.yaml
    : > db.secret.yaml
    run git check-ignore service.spec.yaml openapi.yaml
    [ "$status" -ne 0 ]
    run git check-ignore config.local.yaml
    [ "$status" -eq 0 ]
    run git check-ignore db.secret.yaml
    [ "$status" -eq 0 ]
}
