#!/usr/bin/env bats

# Coverage for the ENV-001 naming law (check_env_naming /
# _manifest_env_name_allowed — STANDARD.md §2.7.1). Pins: the FIDENCE_ pass
# rule, the built-in framework allowlist (exact + prefix), the permanent
# MANIFEST_CLI_ carve-out, config-driven extra allows, compose-RHS scanning
# (LHS framework keys never checked), and that untracked local value files
# are advisory only.

load 'helpers/setup'

setup() {
    load_modules "system/manifest-env-naming.sh"
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/fidence.app.demo"
    mkdir -p "$PROJ"
    cd "$PROJ"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    printf '.env\n.env.*\n!.env.example\n!.env.template\n' > .gitignore
    git add .gitignore
    git commit -q -m "initial"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_ENV_NAMING_ALLOW
}

# --- the pass rule ---------------------------------------------------------------

@test "naming: FIDENCE_-prefixed names pass" {
    run _manifest_env_name_allowed "FIDENCE_APP_DEMO_LOG_LEVEL"
    [ "$status" -eq 0 ]
}

@test "naming: framework exact names pass (DATABASE_URL)" {
    run _manifest_env_name_allowed "DATABASE_URL"
    [ "$status" -eq 0 ]
}

@test "naming: framework prefixes pass (NEXT_PUBLIC_*)" {
    run _manifest_env_name_allowed "NEXT_PUBLIC_SITE_URL"
    [ "$status" -eq 0 ]
}

@test "naming: MANIFEST_CLI_ namespace is permanently exempt" {
    run _manifest_env_name_allowed "MANIFEST_CLI_AUTO_CONFIRM"
    [ "$status" -eq 0 ]
}

@test "naming: bare names fail" {
    run _manifest_env_name_allowed "MY_SECRET_TOKEN"
    [ "$status" -ne 0 ]
}

@test "naming: env.naming_allow exact entry passes only that name" {
    export MANIFEST_CLI_ENV_NAMING_ALLOW="LEGACY_TOKEN"
    run _manifest_env_name_allowed "LEGACY_TOKEN"
    [ "$status" -eq 0 ]
    run _manifest_env_name_allowed "LEGACY_TOKEN_2"
    [ "$status" -ne 0 ]
}

@test "naming: env.naming_allow trailing-underscore entry is a prefix" {
    export MANIFEST_CLI_ENV_NAMING_ALLOW="ARES_"
    run _manifest_env_name_allowed "ARES_POSTGRES_PASSWORD"
    [ "$status" -eq 0 ]
}

# --- repo audit surfaces -----------------------------------------------------------

@test "audit: clean repo (FIDENCE + framework names in tracked example) passes" {
    printf 'FIDENCE_APP_DEMO_LOG_LEVEL=info\nDATABASE_URL=\n' > .env.example
    git add .env.example && git commit -q -m "example"

    run check_env_naming "$PROJ"
    [ "$status" -eq 0 ]
}

@test "audit: bare name in a tracked .env.example is a violation" {
    printf 'MY_SECRET_TOKEN=abc\n' > .env.example
    git add .env.example && git commit -q -m "example"

    run check_env_naming "$PROJ"
    [ "$status" -ne 0 ]
    [[ "$output" == *"MY_SECRET_TOKEN"* ]]
}

@test "audit: spec env[].name violations are reported" {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    cat > app.spec.yaml <<'YAML'
env:
  - name: BARE_NAME
    secret: false
YAML
    run check_env_naming "$PROJ"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BARE_NAME"* ]]
}

@test "audit: compose RHS \${BARE} is a violation; LHS framework key is not" {
    cat > docker-compose.yml <<'YAML'
services:
  app:
    environment:
      DATABASE_URL: ${BARE_DB_URL}
YAML
    git add docker-compose.yml && git commit -q -m "compose"

    run check_env_naming "$PROJ"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BARE_DB_URL"* ]]
    [[ "$output" != *"❌"*"DATABASE_URL"* ]]
}

@test "audit: compose RHS \${FIDENCE_*} interpolation passes" {
    cat > docker-compose.yml <<'YAML'
services:
  app:
    environment:
      DATABASE_URL: ${FIDENCE_APP_DEMO_DATABASE_URL}
YAML
    git add docker-compose.yml && git commit -q -m "compose"

    run check_env_naming "$PROJ"
    [ "$status" -eq 0 ]
}

@test "audit: untracked local .env value files are advisory only" {
    printf 'TOTALLY_BARE=1\n' > .env

    run check_env_naming "$PROJ"
    [ "$status" -eq 0 ]
    [[ "$output" == *"advisory"* ]]
    [[ "$output" == *"TOTALLY_BARE"* ]]
}
