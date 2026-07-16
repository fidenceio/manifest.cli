#!/usr/bin/env bats

# Coverage for `manifest env` dispatch routing (manifest-env.sh —
# manifest_env_dispatch): generate/validate routes with flag passthrough, the
# help/-h/empty branches, the unknown-subcommand error, and env validate's
# behavior when no spec env: block exists. Generate/validate content semantics
# themselves are pinned in env_generate.bats.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    load_modules "system/manifest-env-naming.sh" "system/manifest-security.sh" \
        "core/manifest-init.sh" "core/manifest-env.sh"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    PROJ="$SCRATCH/fidence.app.demo"
    mkdir -p "$PROJ"
    export MANIFEST_CLI_PROJECT_ROOT="$PROJ"
    cd "$PROJ"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_PROJECT_ROOT
}

write_spec() {
    cat > "$PROJ/app.spec.yaml" <<'YAML'
name: fidence.app.demo
env:
  - name: FIDENCE_APP_DEMO_LOG_LEVEL
    description: Structured-log verbosity
    required: false
    default: info
    secret: false
YAML
}

@test "env dispatch: routes generate (no spec -> informative, exit 0)" {
    run manifest_env_dispatch generate
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "No spec env: block found"
    [ ! -f "$PROJ/.env.example" ]
}

@test "env dispatch: passes flags through to generate (--check drift gate)" {
    write_spec
    run manifest_env_dispatch generate --check
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Env drift check — $PROJ"
    echo "$output" | grep -q "would create: .env.example"
    echo "$output" | grep -q "env drift: 1 artifact(s) stale"
    # The drift gate is read-only.
    [ ! -f "$PROJ/.env.example" ]
}

@test "env dispatch: routes validate; no spec env: block is informative" {
    run manifest_env_dispatch validate
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Env validation — $PROJ"
    echo "$output" | grep -q "env prefix policy (prefix: FIDENCE_APP_DEMO_"
    echo "$output" | grep -q "no spec env: block — nothing generated yet"
    echo "$output" | grep -q "not a git repository — skipped"
    echo "$output" | grep -q "env validate: PASS"
}

@test "env dispatch: -h renders subcommand help and exits 0" {
    run manifest_env_dispatch -h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest env <generate|validate>"
    echo "$output" | grep -q "generate   Generate .env.example"
    echo "$output" | grep -q "validate   Env prefix policy + drift + gitignore hygiene"
}

@test "env dispatch: empty subcommand shows help but exits 1" {
    run manifest_env_dispatch
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "manifest env <generate|validate>"
}

@test "env dispatch: unknown subcommand is an error naming it" {
    run manifest_env_dispatch frobnicate
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown env subcommand: frobnicate"
    echo "$output" | grep -q "manifest env <generate|validate>"
}
