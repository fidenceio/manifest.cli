#!/usr/bin/env bats

# Coverage for .env.example scaffolding at init/prep time (ensure_env_files /
# _manifest_env_prefix_for_repo). Pins: prefix derivation from the repo
# directory name under a configured env.prefix (and the neutral empty default),
# the three scaffold paths (spec with env:, spec without env: → seeded starter
# block, no spec → starter), secret entries never emitted as live assignments,
# and no-clobber.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    # Default policy: no explicit env.prefix, so the prefix is DERIVED from the
    # project name. Cases that need an explicit value or the disabled state set
    # MANIFEST_CLI_ENV_PREFIX themselves.
    unset MANIFEST_CLI_ENV_PREFIX
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_ENV_PREFIX
}

mk_proj() {
    local name="$1"
    PROJ="$SCRATCH/$name"
    mkdir -p "$PROJ"
}

# --- prefix derivation ---------------------------------------------------------

@test "env prefix: fidence.app.kanizsa → FIDENCE_APP_KANIZSA_" {
    mk_proj "fidence.app.kanizsa"
    run _manifest_env_prefix_for_repo "$PROJ"
    [ "$output" = "FIDENCE_APP_KANIZSA_" ]
}

@test "env prefix: dots and hyphens map to underscores" {
    mk_proj "fidence.service.risk.fcra.microbilt-transunion"
    run _manifest_env_prefix_for_repo "$PROJ"
    [ "$output" = "FIDENCE_SERVICE_RISK_FCRA_MICROBILT_TRANSUNION_" ]
}

@test "env prefix: derived default is vendor-neutral (my-tool → MY_TOOL_)" {
    mk_proj "my-tool"
    run _manifest_env_prefix_for_repo "$PROJ"
    [ "$output" = "MY_TOOL_" ]
}

@test "env prefix: an explicit prefix overrides the derived default" {
    export MANIFEST_CLI_ENV_PREFIX="ACME_"
    mk_proj "acme.web"
    run _manifest_env_prefix_for_repo "$PROJ"
    [ "$output" = "ACME_WEB_" ]
}

@test "env prefix: env.prefix off → empty (policy disabled)" {
    export MANIFEST_CLI_ENV_PREFIX="off"
    mk_proj "fidence.app.demo"
    run _manifest_env_prefix_for_repo "$PROJ"
    [ "$output" = "" ]
}

# --- scaffold: no spec -----------------------------------------------------------

@test "env scaffold: no spec → starter carries the derived prefix (policy on)" {
    mk_proj "fidence.app.demo"
    run ensure_env_files "$PROJ"
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.env.example" ]
    grep -q "scaffolded by Manifest CLI" "$PROJ/.env.example"
    grep -q "Env prefix policy is on" "$PROJ/.env.example"
    grep -q "FIDENCE_APP_DEMO_LOG_LEVEL=info" "$PROJ/.env.example"
}

@test "env scaffold: env.prefix off → neutral starter, no organization prefix" {
    export MANIFEST_CLI_ENV_PREFIX="off"
    mk_proj "my-tool"
    run ensure_env_files "$PROJ"
    [ "$status" -eq 0 ]
    grep -q "Env prefix policy is off" "$PROJ/.env.example"
    grep -qE "^# LOG_LEVEL=info$" "$PROJ/.env.example"
    ! grep -q "FIDENCE_" "$PROJ/.env.example"
}

@test "env scaffold: no-clobber — an existing .env.example is never touched" {
    mk_proj "fidence.app.demo"
    printf '# mine\nCUSTOM=1\n' > "$PROJ/.env.example"
    run ensure_env_files "$PROJ"
    [ "$status" -eq 0 ]
    grep -q "CUSTOM=1" "$PROJ/.env.example"
    ! grep -q "scaffolded by Manifest CLI" "$PROJ/.env.example"
}

# --- scaffold: spec with env: -----------------------------------------------------

@test "env scaffold: spec env: block generates the example (secrets commented)" {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    mk_proj "fidence.app.demo"
    cat > "$PROJ/app.spec.yaml" <<'YAML'
name: fidence.app.demo
env:
  - name: FIDENCE_APP_DEMO_LOG_LEVEL
    description: Structured-log verbosity
    required: false
    default: info
    secret: false
  - name: FIDENCE_APP_DEMO_DB_PASSWORD
    description: Cockroach role password
    required: true
    secret: true
    group: db
    framework_name: DATABASE_URL
YAML

    run ensure_env_files "$PROJ"
    [ "$status" -eq 0 ]
    grep -q "^FIDENCE_APP_DEMO_LOG_LEVEL=info$" "$PROJ/.env.example"
    # The secret is documented but never a live assignment (D-ENV-3).
    grep -q "^# FIDENCE_APP_DEMO_DB_PASSWORD=$" "$PROJ/.env.example"
    grep -q "secret/{env}/fidence.app.demo/db" "$PROJ/.env.example"
    grep -q "DATABASE_URL" "$PROJ/.env.example"
    ! grep -q "^FIDENCE_APP_DEMO_DB_PASSWORD=" "$PROJ/.env.example"
}

# --- scaffold: spec without env: --------------------------------------------------

@test "env scaffold: spec without env: is seeded with a starter block first" {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    mk_proj "fidence.service.demo"
    printf 'name: fidence.service.demo\n' > "$PROJ/service.spec.yaml"

    run ensure_env_files "$PROJ"
    [ "$status" -eq 0 ]

    # The spec gained the starter env: block (source of truth, D-ENV-2)…
    [ "$(yq e '.env | length' "$PROJ/service.spec.yaml")" = "2" ]
    yq e '.env[].name' "$PROJ/service.spec.yaml" | grep -q "FIDENCE_SERVICE_DEMO_LOG_LEVEL"
    yq e '.env[].name' "$PROJ/service.spec.yaml" | grep -q "FIDENCE_SERVICE_DEMO_SERVICE_FQN"

    # …and the example was generated from it.
    grep -q "^FIDENCE_SERVICE_DEMO_LOG_LEVEL=info$" "$PROJ/.env.example"
    grep -q "generated by Manifest CLI" "$PROJ/.env.example"
}
