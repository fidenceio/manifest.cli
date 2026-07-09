#!/usr/bin/env bats

# Coverage for the env prefix policy (check_env_naming /
# _manifest_env_name_allowed / _manifest_env_effective_prefix). Pins: the policy
# is ON by default and enforces a prefix DERIVED from the project name; an
# explicit env.prefix overrides it; env.prefix: off disables it. The built-in
# framework allowlist (exact + prefix) always passes; the permanent
# MANIFEST_CLI_ carve-out; config-driven extra allows; compose-RHS scanning
# (LHS framework keys never checked); and untracked local value files advisory.

load 'helpers/setup'

setup() {
    load_modules "system/manifest-env-naming.sh"
    SCRATCH="$(mk_scratch)"
    # Repo name → derived prefix ACME_APP_DEMO_ under the default policy.
    PROJ="$SCRATCH/acme.app.demo"
    mkdir -p "$PROJ"
    cd "$PROJ"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    printf '.env\n.env.*\n!.env.example\n!.env.template\n' > .gitignore
    git add .gitignore
    git commit -q -m "initial"
    unset MANIFEST_CLI_ENV_PREFIX
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_ENV_NAMING_ALLOW
    unset MANIFEST_CLI_ENV_PREFIX
}

# --- effective-prefix resolution -------------------------------------------------

@test "effective prefix: unset → DERIVED from the project name" {
    run _manifest_env_effective_prefix "$PROJ"
    [ "$output" = "ACME_APP_DEMO_" ]
}

@test "effective prefix: explicit env.prefix overrides the derived default" {
    export MANIFEST_CLI_ENV_PREFIX="ACME_"
    run _manifest_env_effective_prefix "$PROJ"
    [ "$output" = "ACME_" ]
}

@test "effective prefix: env.prefix off → empty (policy disabled)" {
    export MANIFEST_CLI_ENV_PREFIX="off"
    run _manifest_env_effective_prefix "$PROJ"
    [ "$output" = "" ]
}

# --- the name primitive (given an effective prefix) ------------------------------

@test "primitive: prefixed names pass, unprefixed custom names fail" {
    run _manifest_env_name_allowed "ACME_TOKEN" "ACME_"
    [ "$status" -eq 0 ]
    run _manifest_env_name_allowed "FOO_TOKEN" "ACME_"
    [ "$status" -ne 0 ]
}

@test "primitive: empty effective prefix (policy off) accepts any name" {
    run _manifest_env_name_allowed "FOO_TOKEN" ""
    [ "$status" -eq 0 ]
}

@test "primitive: framework exact names pass regardless of prefix (DATABASE_URL)" {
    run _manifest_env_name_allowed "DATABASE_URL" "ACME_"
    [ "$status" -eq 0 ]
}

@test "primitive: framework prefixes pass (NEXT_PUBLIC_*)" {
    run _manifest_env_name_allowed "NEXT_PUBLIC_SITE_URL" "ACME_"
    [ "$status" -eq 0 ]
}

@test "primitive: MANIFEST_CLI_ namespace is permanently exempt" {
    run _manifest_env_name_allowed "MANIFEST_CLI_AUTO_CONFIRM" "ACME_"
    [ "$status" -eq 0 ]
}

@test "primitive: env.naming_allow exact entry passes only that name" {
    export MANIFEST_CLI_ENV_NAMING_ALLOW="LEGACY_TOKEN"
    run _manifest_env_name_allowed "LEGACY_TOKEN" "ACME_"
    [ "$status" -eq 0 ]
    run _manifest_env_name_allowed "LEGACY_TOKEN_2" "ACME_"
    [ "$status" -ne 0 ]
}

@test "primitive: env.naming_allow trailing-underscore entry is a prefix" {
    export MANIFEST_CLI_ENV_NAMING_ALLOW="ARES_"
    run _manifest_env_name_allowed "ARES_POSTGRES_PASSWORD" "ACME_"
    [ "$status" -eq 0 ]
}

# --- repo audit surfaces (default policy = derived prefix, enforced) -------------

@test "audit: with NO explicit config, the DERIVED prefix is enforced — bare name flagged" {
    printf 'MY_SECRET_TOKEN=abc\n' > .env.example
    git add .env.example && git commit -q -m "example"

    run check_env_naming "$PROJ"
    [ "$status" -ne 0 ]
    [[ "$output" == *"MY_SECRET_TOKEN"* ]]
    [[ "$output" == *"ACME_APP_DEMO_"* ]]
}

@test "audit: clean repo (derived-prefixed + framework names) passes" {
    printf 'ACME_APP_DEMO_LOG_LEVEL=info\nDATABASE_URL=\n' > .env.example
    git add .env.example && git commit -q -m "example"

    run check_env_naming "$PROJ"
    [ "$status" -eq 0 ]
}

@test "audit: env.prefix off is the explicit opt-out — a bare name is NOT flagged" {
    export MANIFEST_CLI_ENV_PREFIX="off"
    printf 'MY_SECRET_TOKEN=abc\n' > .env.example
    git add .env.example && git commit -q -m "example"

    run check_env_naming "$PROJ"
    [ "$status" -eq 0 ]
}

@test "audit: an explicit env.prefix is enforced instead of the derived one" {
    export MANIFEST_CLI_ENV_PREFIX="ACME_"
    printf 'ACME_TOKEN=1\nFOO_TOKEN=2\n' > .env.example
    git add .env.example && git commit -q -m "example"

    run check_env_naming "$PROJ"
    [ "$status" -ne 0 ]
    [[ "$output" == *"FOO_TOKEN"* ]]
    [[ "$output" != *"❌"*"ACME_TOKEN"* ]]
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

@test "audit: compose RHS derived-prefixed interpolation passes" {
    cat > docker-compose.yml <<'YAML'
services:
  app:
    environment:
      DATABASE_URL: ${ACME_APP_DEMO_DATABASE_URL}
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
