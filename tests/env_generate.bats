#!/usr/bin/env bats

# Coverage for `manifest env generate|validate` (manifest-env.sh — ENV-001,
# STANDARD.md §2.7). Pins: preview-by-default (no writes), -y writes the
# artifact set (.env.example, k8s/env bridges, Dockerfile publics block),
# --check as the drift gate, ESO bridge orientation (secretKey = framework
# name, remoteRef.property = FIDENCE stored name), Dockerfile block
# idempotency, and env validate's aggregate verdict.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    load_modules "system/manifest-env-naming.sh" "system/manifest-security.sh" \
        "core/manifest-init.sh" "core/manifest-env.sh"
    SCRATCH="$(mk_scratch)"
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
  - name: FIDENCE_APP_DEMO_DB_PASSWORD
    description: Cockroach role password
    required: true
    secret: true
    group: db
    framework_name: DATABASE_URL
  - name: FIDENCE_APP_DEMO_SITE_URL
    description: Public site origin
    required: true
    default: https://demo.fidence.io
    secret: false
    public: true
    framework_name: NEXT_PUBLIC_SITE_URL
YAML
}

# --- guard rails -----------------------------------------------------------------

@test "env generate: no spec env: block is informative, not drift" {
    run manifest_env_generate --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"No spec env: block"* ]]
}

@test "env generate: preview is the default and writes nothing" {
    write_spec
    run manifest_env_generate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [[ "$output" == *"would create: .env.example"* ]]
    [ ! -f "$PROJ/.env.example" ]
}

@test "env generate: rejects contradictory --dry-run -y" {
    write_spec
    run manifest_env_generate --dry-run -y
    [ "$status" -ne 0 ]
}

# --- apply -------------------------------------------------------------------------

@test "env generate -y: writes .env.example and k8s env bridges" {
    write_spec
    mkdir -p "$PROJ/k8s"

    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.env.example" ]
    [ -f "$PROJ/k8s/env/configmap.yaml" ]
    [ -f "$PROJ/k8s/env/external-secret.yaml" ]

    # Non-secret bridge: injected name = framework name (or FIDENCE name).
    grep -q 'NEXT_PUBLIC_SITE_URL: "https://demo.fidence.io"' "$PROJ/k8s/env/configmap.yaml"
    grep -q 'FIDENCE_APP_DEMO_LOG_LEVEL: "info"' "$PROJ/k8s/env/configmap.yaml"
    # Secrets never appear in the ConfigMap.
    refute grep -q "DB_PASSWORD" "$PROJ/k8s/env/configmap.yaml"

    # Secret bridge orientation (D-ENV-3/§2.7.2): secretKey = framework name,
    # property = FIDENCE stored name, path = secret/{env}/{slug}/{group}.
    grep -q "secretKey: DATABASE_URL" "$PROJ/k8s/env/external-secret.yaml"
    grep -q "property: FIDENCE_APP_DEMO_DB_PASSWORD" "$PROJ/k8s/env/external-secret.yaml"
    grep -q "key: secret/data/{env}/fidence.app.demo/db" "$PROJ/k8s/env/external-secret.yaml"
}

@test "env generate -y: Dockerfile publics bridge block, applied idempotently" {
    write_spec
    printf 'FROM scratch\n' > "$PROJ/Dockerfile"

    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    grep -q "ARG FIDENCE_APP_DEMO_SITE_URL" "$PROJ/Dockerfile"
    grep -q 'ENV NEXT_PUBLIC_SITE_URL=${FIDENCE_APP_DEMO_SITE_URL}' "$PROJ/Dockerfile"

    # Re-apply must not duplicate the block.
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ "$(grep -c "ARG FIDENCE_APP_DEMO_SITE_URL" "$PROJ/Dockerfile")" -eq 1 ]
}

# --- the drift gate ----------------------------------------------------------------

@test "env generate --check: clean right after apply, stale after a spec edit" {
    write_spec
    run manifest_env_generate -y
    [ "$status" -eq 0 ]

    run manifest_env_generate --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"env drift: clean"* ]]

    yq e -i '.env += [{"name": "FIDENCE_APP_DEMO_NEW_FLAG", "required": false, "default": "off", "secret": false}]' "$PROJ/app.spec.yaml"

    run manifest_env_generate --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"env drift"* ]]
}

# --- validate ------------------------------------------------------------------------

@test "env validate: PASS on a clean generated repo" {
    write_spec
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    printf '.env\n.env.*\n!.env.example\n!.env.template\n' > .gitignore
    manifest_env_generate -y >/dev/null
    git add -A && git commit -q -m "initial"

    run manifest_env_validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"env validate: PASS"* ]]
}

@test "env validate: FAIL when generated artifacts are stale" {
    write_spec
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    printf '.env\n.env.*\n!.env.example\n!.env.template\n' > .gitignore
    manifest_env_generate -y >/dev/null
    yq e -i '.env += [{"name": "FIDENCE_APP_DEMO_NEW_FLAG", "required": false, "default": "off", "secret": false}]' "$PROJ/app.spec.yaml"

    run manifest_env_validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"stale artifacts"* ]]
}

# --- help text vs. what the renderer actually emits ---------------------------------
#
# `env generate --help` shipped ".env.example  the variable names, with no values"
# while _manifest_env_render_example emitted `NAME=<default>` for every non-secret
# entry — only secrets are valueless. The claim was self-consistent and simply
# false, so a test that pinned the help string alone would have passed against the
# wrong text; it took a reader trusting the help into a wrong root cause instead.
#
# This test therefore measures the rendered artifact first and makes the help
# answer to it. Both halves have to stay true: if the renderer stops emitting
# defaults, (a)/(c) fail; if the help regains a "no values" claim, (d) fails.
@test "env generate: .env.example carries non-secret defaults, and the help says so" {
    write_spec
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.env.example" ]

    # (a) BEHAVIOUR — a non-secret entry renders NAME=<default>, value included.
    grep -qx 'FIDENCE_APP_DEMO_LOG_LEVEL=info' "$PROJ/.env.example"
    grep -qx 'FIDENCE_APP_DEMO_SITE_URL=https://demo.fidence.io' "$PROJ/.env.example"

    # (b) BEHAVIOUR — a secret is commented out and left valueless, and never
    #     appears as a live assignment (D-ENV-3: no secret literal in any .env).
    grep -qx '# FIDENCE_APP_DEMO_DB_PASSWORD=' "$PROJ/.env.example"
    refute grep -qE '^FIDENCE_APP_DEMO_DB_PASSWORD=' "$PROJ/.env.example"

    # (c) Measure, rather than assume, that a value is present. This is the fact
    #     the help text has to agree with. `grep -c` exits 1 when it counts zero,
    #     so it is captured as a number and compared — never used as a boolean.
    local valued
    valued="$(grep -cE '^[A-Z][A-Z0-9_]*=.+$' "$PROJ/.env.example" || true)"
    [ "$valued" -ge 1 ]

    # (d) TEXT — given (c), the help must not tell the reader the file has no
    #     values. Matched as a family of phrasings, not the one string that was
    #     wrong, so a reworded version of the same false claim is still caught.
    run manifest_env_generate --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Files written"* ]]   # positive control: the block rendered
    local claim
    claim="$(printf '%s\n' "$output" \
        | grep -icE 'no values|without values|with no value|names only|names, not values' || true)"
    [ "$claim" -eq 0 ]
}
