#!/usr/bin/env bats
# bats file_tags=smoke
#
# The secret store is configuration, never a built-in (TRACKER §97).
#
# `manifest env generate` used to write every ExternalSecret with one vendor's
# store name and one fixed path layout, and nothing filled {env} per
# environment — so every adopter hand-patched the generated files and the next
# `generate -y` overwrote the patches. Now env.secrets.* (fleet root, repo
# override wins key by key) is the only source of the store and path, and:
#
#   fail closed   secrets declared + env.secrets unset → exit 1, nothing written
#   honoured      the configured store, kind, apiVersion, refresh, path and
#                 property templates land in the file exactly
#   {env} filled  a kustomize Component replaces the {env} segment from the
#                 env_label label; its index follows the path template
#   drift         --check and env validate NAME a store or path that differs
#   one source    the .env.example comment is rendered from the same template
#   no vendor     no default anywhere names a secret-store vendor
#
# Tagged smoke: fail-closed on a secret surface is a safety contract.

load 'helpers/setup'

_SECRETS_VARS=(MANIFEST_CLI_ENV_SECRETS_PROVIDER MANIFEST_CLI_ENV_SECRETS_STORE_KIND
    MANIFEST_CLI_ENV_SECRETS_STORE_NAME MANIFEST_CLI_ENV_SECRETS_API_VERSION
    MANIFEST_CLI_ENV_SECRETS_PATH MANIFEST_CLI_ENV_SECRETS_PROPERTY
    MANIFEST_CLI_ENV_SECRETS_REFRESH_INTERVAL MANIFEST_CLI_ENV_SECRETS_ENV_LABEL)

_clear_secrets_config() {
    local v
    for v in "${_SECRETS_VARS[@]}"; do unset "$v"; done
}

# The smallest valid external-secrets configuration.
_configure_store() {
    export MANIFEST_CLI_ENV_SECRETS_PROVIDER=external-secrets
    export MANIFEST_CLI_ENV_SECRETS_STORE_NAME=team-store
    export MANIFEST_CLI_ENV_SECRETS_PATH='secret/data/{env}/{identity}/{group}'
    export MANIFEST_CLI_ENV_SECRETS_ENV_LABEL=env
}

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    load_modules "system/manifest-env-naming.sh" "system/manifest-security.sh" \
        "core/manifest-init.sh" "core/manifest-env.sh"
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/acme.svc.billing"
    mkdir -p "$PROJ/k8s"
    export MANIFEST_CLI_PROJECT_ROOT="$PROJ"
    cd "$PROJ"
    _clear_secrets_config
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_PROJECT_ROOT MANIFEST_CLI_GLOBAL_CONFIG
    _clear_secrets_config
}

write_spec_with_secrets() {
    cat > "${1:-$PROJ}/app.spec.yaml" <<'YAML'
name: acme.svc.billing
env:
  - name: ACME_SVC_BILLING_LOG_LEVEL
    required: false
    default: info
    secret: false
  - name: ACME_SVC_BILLING_DB_PASSWORD
    required: true
    secret: true
    group: db
    framework_name: DATABASE_URL
  - name: ACME_SVC_BILLING_API_TOKEN
    required: true
    secret: true
YAML
}

write_spec_without_secrets() {
    cat > "${1:-$PROJ}/app.spec.yaml" <<'YAML'
name: acme.svc.billing
env:
  - name: ACME_SVC_BILLING_LOG_LEVEL
    required: false
    default: info
    secret: false
YAML
}

_no_artifacts_written() {
    [ ! -f "$PROJ/.env.example" ]
    [ ! -d "$PROJ/k8s/env" ]
}

# --- fail closed ---------------------------------------------------------------------

@test "fail closed: secrets declared and env.secrets unset → preview, --check and -y all exit 1 and write nothing" {
    write_spec_with_secrets

    run manifest_env_generate
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.provider is not set"* ]]
    [[ "$output" == *"ACME_SVC_BILLING_DB_PASSWORD"* ]]
    [[ "$output" == *"ACME_SVC_BILLING_API_TOKEN"* ]]
    [[ "$output" == *"Nothing was written"* ]]
    _no_artifacts_written

    run manifest_env_generate --check
    [ "$status" -eq 1 ]
    _no_artifacts_written

    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    _no_artifacts_written

    # env validate reports it as a configuration gap, not as stale output.
    run manifest_env_validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"secret store not configured"* ]]
    [[ "$output" != *"stale artifacts"* ]]
}

@test "control: with no secrets declared, env.secrets is not required and no secret bridge is written" {
    write_spec_without_secrets
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.env.example" ]
    [ -f "$PROJ/k8s/env/configmap.yaml" ]
    [ ! -f "$PROJ/k8s/env/external-secret.yaml" ]
    [ ! -d "$PROJ/k8s/env/component" ]
    # The base lists only what was written.
    [ "$(yq e '.resources | join(",")' "$PROJ/k8s/env/kustomization.yaml")" = "configmap.yaml" ]
}

@test "provider none: generate succeeds, no secret bridge is written, and the example says so" {
    write_spec_with_secrets
    export MANIFEST_CLI_ENV_SECRETS_PROVIDER=none
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ ! -f "$PROJ/k8s/env/external-secret.yaml" ]
    [ ! -d "$PROJ/k8s/env/component" ]
    grep -q "delivered outside Manifest (env.secrets.provider: none)" "$PROJ/.env.example"
    grep -q "^# ACME_SVC_BILLING_DB_PASSWORD=$" "$PROJ/.env.example"
}

@test "an unknown provider is refused by name" {
    write_spec_with_secrets
    export MANIFEST_CLI_ENV_SECRETS_PROVIDER=some-other-thing
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"'some-other-thing' is not recognised"* ]]
    _no_artifacts_written
}

@test "external-secrets with no store.name or path is refused, naming each missing key" {
    write_spec_with_secrets
    export MANIFEST_CLI_ENV_SECRETS_PROVIDER=external-secrets
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.store.name is not set"* ]]
    [[ "$output" == *"env.secrets.path is not set"* ]]
    _no_artifacts_written
}

# --- honoured exactly ------------------------------------------------------------------

@test "a configured store and path are honoured exactly" {
    write_spec_with_secrets
    export MANIFEST_CLI_ENV_SECRETS_PROVIDER=external-secrets
    export MANIFEST_CLI_ENV_SECRETS_STORE_KIND=SecretStore
    export MANIFEST_CLI_ENV_SECRETS_STORE_NAME=billing-store
    export MANIFEST_CLI_ENV_SECRETS_API_VERSION=external-secrets.io/v1beta1
    export MANIFEST_CLI_ENV_SECRETS_REFRESH_INTERVAL=30m
    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/{identity}/{group}'
    export MANIFEST_CLI_ENV_SECRETS_PROPERTY='{group}_{name}'
    export MANIFEST_CLI_ENV_SECRETS_ENV_LABEL=env

    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    local f="$PROJ/k8s/env/external-secret.yaml"
    [ "$(yq e '.apiVersion' "$f")" = "external-secrets.io/v1beta1" ]
    [ "$(yq e '.kind' "$f")" = "ExternalSecret" ]
    [ "$(yq e '.spec.refreshInterval' "$f")" = "30m" ]
    [ "$(yq e '.spec.secretStoreRef.kind' "$f")" = "SecretStore" ]
    [ "$(yq e '.spec.secretStoreRef.name' "$f")" = "billing-store" ]
    [ "$(yq e '.spec.data[0].secretKey' "$f")" = "DATABASE_URL" ]
    [ "$(yq e '.spec.data[0].remoteRef.key' "$f")" = "kv/{env}/acme.svc.billing/db" ]
    [ "$(yq e '.spec.data[0].remoteRef.property' "$f")" = "db_ACME_SVC_BILLING_DB_PASSWORD" ]
    # The second secret has no group → the `app` default, and no framework name.
    [ "$(yq e '.spec.data[1].secretKey' "$f")" = "ACME_SVC_BILLING_API_TOKEN" ]
    [ "$(yq e '.spec.data[1].remoteRef.key' "$f")" = "kv/{env}/acme.svc.billing/app" ]
    [ "$(yq e '.spec.data[1].remoteRef.property' "$f")" = "app_ACME_SVC_BILLING_API_TOKEN" ]
    # Secrets never land in the ConfigMap.
    refute grep -q "DB_PASSWORD\|API_TOKEN" "$PROJ/k8s/env/configmap.yaml"
}

@test "the defaults that are not required resolve without naming anything: kind, apiVersion, property, refresh" {
    write_spec_with_secrets
    _configure_store
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    local f="$PROJ/k8s/env/external-secret.yaml"
    [ "$(yq e '.spec.secretStoreRef.kind' "$f")" = "ClusterSecretStore" ]
    [ "$(yq e '.apiVersion' "$f")" = "external-secrets.io/v1" ]
    [ "$(yq e '.spec.refreshInterval' "$f")" = "1h" ]
    [ "$(yq e '.spec.data[0].remoteRef.property' "$f")" = "ACME_SVC_BILLING_DB_PASSWORD" ]
}

# --- one source for the docs -----------------------------------------------------------

@test "the .env.example secret comment and the ExternalSecret key are rendered from the same template" {
    write_spec_with_secrets
    _configure_store
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    local key
    key="$(yq e '.spec.data[0].remoteRef.key' "$PROJ/k8s/env/external-secret.yaml")"
    [ "$key" = "secret/data/{env}/acme.svc.billing/db" ]
    grep -qF "ClusterSecretStore/team-store at $key (property ACME_SVC_BILLING_DB_PASSWORD)" "$PROJ/.env.example"

    # Mutation: change the template; both surfaces move together, or the
    # comment is a second source and this test fails.
    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/{identity}/{group}/{name}'
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    key="$(yq e '.spec.data[0].remoteRef.key' "$PROJ/k8s/env/external-secret.yaml")"
    [ "$key" = "kv/{env}/acme.svc.billing/db/ACME_SVC_BILLING_DB_PASSWORD" ]
    grep -qF " at $key " "$PROJ/.env.example"
    refute grep -qF "secret/data/{env}" "$PROJ/.env.example"
}

# --- drift -----------------------------------------------------------------------------

@test "drift: changing the store in config is reported as store drift by --check and env validate" {
    write_spec_with_secrets
    _configure_store
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    run manifest_env_generate --check
    [ "$status" -eq 0 ]

    export MANIFEST_CLI_ENV_SECRETS_STORE_NAME=other-store
    run manifest_env_generate --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"would update: k8s/env/external-secret.yaml"* ]]
    [[ "$output" == *"store drift: file names ClusterSecretStore/team-store, config says ClusterSecretStore/other-store"* ]]
    [[ "$output" != *"path drift"* ]]

    run manifest_env_validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"stale artifacts"* ]]
    [[ "$output" == *"store drift: file names ClusterSecretStore/team-store, config says ClusterSecretStore/other-store"* ]]
}

@test "drift: changing the path template in config is reported as path drift" {
    write_spec_with_secrets
    _configure_store
    run manifest_env_generate -y
    [ "$status" -eq 0 ]

    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/{identity}/{group}'
    run manifest_env_generate --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"path drift: file's first key is secret/data/{env}/acme.svc.billing/db, config renders kv/{env}/{identity}/{group} as kv/{env}/acme.svc.billing/db"* ]]
    [[ "$output" != *"store drift"* ]]
}

# --- {env} per environment -------------------------------------------------------------

@test "the {env} segment index follows the path template, and the index addresses the placeholder" {
    write_spec_with_secrets
    _configure_store
    local template expected key segment index
    while IFS='|' read -r template expected; do
        export MANIFEST_CLI_ENV_SECRETS_PATH="$template"
        run manifest_env_generate -y
        [ "$status" -eq 0 ]
        index="$(yq e '.replacements[0].targets[0].options.index' "$PROJ/k8s/env/component/kustomization.yaml")"
        [ "$index" = "$expected" ]
        # Positive control: the segment at that index of the rendered key IS
        # the placeholder the replacement will overwrite.
        key="$(yq e '.spec.data[0].remoteRef.key' "$PROJ/k8s/env/external-secret.yaml")"
        segment="$(printf '%s' "$key" | cut -d/ -f$((expected + 1)))"
        [ "$segment" = "{env}" ]
    done <<'CASES'
secret/data/{env}/{identity}/{group}|2
kv/{env}/{identity}|1
{env}/{identity}/{group}|0
kv/{identity}/{env}|2
CASES

    local c="$PROJ/k8s/env/component/kustomization.yaml"
    [ "$(yq e '.kind' "$c")" = "Component" ]
    [ "$(yq e '.replacements[0].source.kind' "$c")" = "ExternalSecret" ]
    [ "$(yq e '.replacements[0].source.name' "$c")" = "acme.svc.billing-env" ]
    [ "$(yq e '.replacements[0].source.fieldPath' "$c")" = "metadata.labels.env" ]
    [ "$(yq e '.replacements[0].targets[0].fieldPaths[0]' "$c")" = "spec.data.*.remoteRef.key" ]
    [ "$(yq e '.replacements[0].targets[0].options.delimiter' "$c")" = "/" ]
}

@test "a path without {env} writes no Component; {env} inside a segment is refused" {
    write_spec_with_secrets
    _configure_store
    export MANIFEST_CLI_ENV_SECRETS_PATH='static/{identity}/{group}'
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ -f "$PROJ/k8s/env/external-secret.yaml" ]
    [ ! -d "$PROJ/k8s/env/component" ]
    [[ "$output" != *"component/kustomization.yaml"* ]]

    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/prod-{env}/{identity}'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"{env} must be a whole path segment"* ]]
}

@test "env_label is required when the path has {env}, and must be a plain name" {
    write_spec_with_secrets
    _configure_store
    unset MANIFEST_CLI_ENV_SECRETS_ENV_LABEL
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.env_label is not set"* ]]
    _no_artifacts_written

    export MANIFEST_CLI_ENV_SECRETS_ENV_LABEL='app.kubernetes.io/env'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a plain name"* ]]
    _no_artifacts_written
}

@test "fail closed: a quoted secret: \"true\" is gated like the boolean (one predicate for gate and renderers)" {
    # The renderers always treated the string "true" as a secret; a gate that
    # accepted only the YAML boolean let this spec generate with the secret in
    # no artifact at all.
    cat > "$PROJ/app.spec.yaml" <<'YAML'
name: acme.svc.billing
env:
  - name: ACME_SVC_BILLING_API_TOKEN
    required: true
    secret: "true"
YAML
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.provider is not set, but 1 secret variable(s) are declared: ACME_SVC_BILLING_API_TOKEN"* ]]
    _no_artifacts_written

    # Control: configured, it is bridged as a secret, never into the ConfigMap.
    _configure_store
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ "$(yq e '.spec.data[0].secretKey' "$PROJ/k8s/env/external-secret.yaml")" = "ACME_SVC_BILLING_API_TOKEN" ]
    refute grep -q "API_TOKEN" "$PROJ/k8s/env/configmap.yaml"
}

@test "values that would break the generated YAML or the replacement are refused by name" {
    write_spec_with_secrets
    _configure_store

    export MANIFEST_CLI_ENV_SECRETS_STORE_NAME='Team Store: prod'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.store.name 'Team Store: prod' must be a Kubernetes object name"* ]]
    _no_artifacts_written
    export MANIFEST_CLI_ENV_SECRETS_STORE_NAME=team-store

    export MANIFEST_CLI_ENV_SECRETS_REFRESH_INTERVAL='1 hour'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.refresh_interval '1 hour' is not a duration"* ]]
    # Bare 0 is the operator's "fetch once" and is accepted.
    export MANIFEST_CLI_ENV_SECRETS_REFRESH_INTERVAL='0'
    run manifest_env_generate
    [ "$status" -eq 0 ]
    unset MANIFEST_CLI_ENV_SECRETS_REFRESH_INTERVAL

    export MANIFEST_CLI_ENV_SECRETS_STORE_NAME='team..store'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a Kubernetes object name"* ]]
    export MANIFEST_CLI_ENV_SECRETS_STORE_NAME=team-store

    export MANIFEST_CLI_ENV_SECRETS_API_VERSION='external-secrets.io/v1 # beta'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.api_version 'external-secrets.io/v1 # beta' is not an API group/version"* ]]
    unset MANIFEST_CLI_ENV_SECRETS_API_VERSION

    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/"{identity}"/{group}'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.path may not contain quotes, backslashes or whitespace"* ]]

    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/{identity}/{env}'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.path may use {env} once"* ]]

    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/{identity}'
    export MANIFEST_CLI_ENV_SECRETS_PROPERTY='{name} '
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.property may not contain quotes, backslashes or whitespace"* ]]
    _no_artifacts_written
}

# --- the Component, built by kustomize itself ------------------------------------------------

_kustomize_build() {
    # Either binary; the caller skips when neither exists.
    if command -v kustomize >/dev/null 2>&1; then
        kustomize build "$1"
    else
        kubectl kustomize "$1"
    fi
}

@test "kustomize fills {env} from the label with the generated Component, and the documented layering is the one that works" {
    command -v kustomize >/dev/null 2>&1 || command -v kubectl >/dev/null 2>&1 || skip "neither kustomize nor kubectl available"
    write_spec_with_secrets
    _configure_store
    run manifest_env_generate -y
    [ "$status" -eq 0 ]

    # The recipe the generated Component's own header prescribes: the label one
    # layer down, then that layer and the Component together.
    # The bridge directory is a buildable base (kustomize refuses a FILE
    # outside the referencing directory, so the layer references the directory).
    [ "$(yq e '.resources | join(",")' "$PROJ/k8s/env/kustomization.yaml")" = "configmap.yaml,external-secret.yaml" ]
    mkdir -p "$PROJ/k8s/overlays/prod/env"
    cat > "$PROJ/k8s/overlays/prod/env/kustomization.yaml" <<'YAML'
resources: [ ../../../env ]
labels: [ { pairs: { env: prod } } ]
YAML
    cat > "$PROJ/k8s/overlays/prod/kustomization.yaml" <<'YAML'
resources: [ env ]
components: [ ../../env/component ]
YAML
    run _kustomize_build "$PROJ/k8s/overlays/prod"
    [ "$status" -eq 0 ]
    [[ "$output" == *'key: secret/data/prod/acme.svc.billing/db'* ]]
    [[ "$output" == *'key: secret/data/prod/acme.svc.billing/app'* ]]
    [[ "$output" != *'{env}'* ]]

    # Negative control, and the reason the recipe has two layers: the label
    # beside `components:` in ONE kustomization is applied after the Component
    # ran, so the replacement finds no source and the build fails.
    mkdir -p "$PROJ/k8s/overlays/flat"
    cat > "$PROJ/k8s/overlays/flat/kustomization.yaml" <<'YAML'
resources: [ ../../env ]
components: [ ../../env/component ]
labels: [ { pairs: { env: prod } } ]
YAML
    run _kustomize_build "$PROJ/k8s/overlays/flat"
    [ "$status" -ne 0 ]
    [[ "$output" == *'metadata.labels.env'* ]]

    # Second negative control, and the reason k8s/env/kustomization.yaml is
    # generated: a FILE outside the referencing kustomization's directory is
    # refused, so the labelled layer cannot point at external-secret.yaml.
    mkdir -p "$PROJ/k8s/overlays/byfile/env"
    cat > "$PROJ/k8s/overlays/byfile/env/kustomization.yaml" <<'YAML'
resources: [ ../../../env/external-secret.yaml ]
labels: [ { pairs: { env: prod } } ]
YAML
    cat > "$PROJ/k8s/overlays/byfile/kustomization.yaml" <<'YAML'
resources: [ env ]
components: [ ../../env/component ]
YAML
    run _kustomize_build "$PROJ/k8s/overlays/byfile"
    [ "$status" -ne 0 ]
    [[ "$output" == *'not in or below'* ]]
}

@test "a hand-authored k8s/env/kustomization.yaml is left untouched by -y, and is not drift" {
    write_spec_with_secrets
    _configure_store
    mkdir -p "$PROJ/k8s/env"
    local theirs='resources:
  - configmap.yaml
  - external-secret.yaml
  - pdb.yaml
namePrefix: billing-
'
    printf '%s' "$theirs" > "$PROJ/k8s/env/kustomization.yaml"

    run manifest_env_generate
    [ "$status" -eq 0 ]
    [[ "$output" == *"hand-authored, left untouched: k8s/env/kustomization.yaml (list configmap.yaml and external-secret.yaml in it yourself)"* ]]
    [[ "$output" != *"would update: k8s/env/kustomization.yaml"* ]]

    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"left:  k8s/env/kustomization.yaml (hand-authored)"* ]]
    [ "$(cat "$PROJ/k8s/env/kustomization.yaml")" = "${theirs%$'\n'}" ]
    [ -f "$PROJ/k8s/env/external-secret.yaml" ]

    # Everything else is current, and their file is not counted as drift.
    run manifest_env_generate --check
    [ "$status" -eq 0 ]

    # Positive control: a file carrying our marker IS ours to update.
    printf '# Generated by Manifest CLI from app.spec.yaml `env:`.\nresources: []\n' > "$PROJ/k8s/env/kustomization.yaml"
    run manifest_env_generate --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"would update: k8s/env/kustomization.yaml"* ]]
}

@test "unknown tokens are refused, and {env} is refused in the property template" {
    write_spec_with_secrets
    _configure_store
    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/{cluster}/{identity}'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown token {cluster}"* ]]

    export MANIFEST_CLI_ENV_SECRETS_PATH='kv/{env}/{identity}'
    export MANIFEST_CLI_ENV_SECRETS_PROPERTY='{env}-{name}'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.property may not use {env}"* ]]
}

# --- fleet value, repo override ----------------------------------------------------------

@test "a repo override beats the fleet value, key by key, and reaches the generated file" {
    # The config loader is not part of load_modules; source it so the layers
    # are the real ones (fleet root → project), not a stand-in.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    export MANIFEST_CLI_GLOBAL_CONFIG="$SCRATCH/nonexistent.global.yaml"

    local fleet="$SCRATCH/fleet"
    local member="$fleet/acme.svc.billing"
    local plain="$fleet/acme.svc.ledger"
    mkdir -p "$member/k8s" "$plain/k8s"
    : > "$fleet/manifest.fleet.config.yaml"
    cat > "$fleet/manifest.config.yaml" <<'YAML'
env:
  secrets:
    provider: external-secrets
    store:
      name: fleet-store
    path: "kv/{env}/{identity}/{group}"
    env_label: env
YAML
    cat > "$member/manifest.config.yaml" <<'YAML'
env:
  secrets:
    store:
      name: billing-store
YAML
    write_spec_with_secrets "$member"
    write_spec_with_secrets "$plain"

    # The overriding member: its store, the fleet's path.
    load_configuration "$member" true >/dev/null 2>&1
    [ "$MANIFEST_CLI_ENV_SECRETS_STORE_NAME" = "billing-store" ]
    [ "$MANIFEST_CLI_ENV_SECRETS_PATH" = "kv/{env}/{identity}/{group}" ]
    [ "$MANIFEST_CLI_ENV_SECRETS_PROVIDER" = "external-secrets" ]
    MANIFEST_CLI_PROJECT_ROOT="$member" run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ "$(yq e '.spec.secretStoreRef.name' "$member/k8s/env/external-secret.yaml")" = "billing-store" ]
    [ "$(yq e '.spec.data[0].remoteRef.key' "$member/k8s/env/external-secret.yaml")" = "kv/{env}/acme.svc.billing/db" ]

    # Control: a member with no override inherits the fleet's store.
    _clear_secrets_config
    load_configuration "$plain" true >/dev/null 2>&1
    [ "$MANIFEST_CLI_ENV_SECRETS_STORE_NAME" = "fleet-store" ]
    MANIFEST_CLI_PROJECT_ROOT="$plain" run manifest_env_generate -y
    [ "$status" -eq 0 ]
    [ "$(yq e '.spec.secretStoreRef.name' "$plain/k8s/env/external-secret.yaml")" = "fleet-store" ]
}

# --- no vendor in any default -------------------------------------------------------------

_vendor_pattern='openbao|vault|hashicorp|aws|gcp|azure|doppler|1password|infisical|akeyless|bitwarden'

@test "no vendor name appears in any default: resolver, config defaults, renderers, example comment" {
    # The three places a default can live, extracted by function body / export
    # block so a vendor string in a comment elsewhere cannot hide or inflate.
    local resolver defaults renderers hits
    resolver="$(awk '/^_manifest_env_secrets_setting\(\)/,/^}/' "$TEST_REPO_ROOT/modules/core/manifest-init.sh")"
    defaults="$(grep -E '^\s*export MANIFEST_CLI_ENV_SECRETS_' "$TEST_REPO_ROOT/modules/core/manifest-config.sh")"
    renderers="$(awk '/^_manifest_env_render_external_secret\(\)/,/^}/; /^_manifest_env_render_env_component\(\)/,/^}/; /^_manifest_env_secret_example_comment\(\)/,/^}/' \
        "$TEST_REPO_ROOT/modules/core/manifest-env.sh" "$TEST_REPO_ROOT/modules/core/manifest-init.sh")"
    [ -n "$resolver" ]
    [ -n "$defaults" ]
    [ -n "$renderers" ]
    hits="$(printf '%s\n%s\n%s\n' "$resolver" "$defaults" "$renderers" | grep -ciE "$_vendor_pattern" || true)"
    [ "$hits" -eq 0 ]

    # Resolved defaults with nothing configured: no provider, no store.
    [ -z "$(_manifest_env_secrets_setting provider)" ]
    [ -z "$(_manifest_env_secrets_setting store_name)" ]
    [ -z "$(_manifest_env_secrets_setting path)" ]
}

@test "positive control: the vendor scan fires on a planted vendor string" {
    local hits
    hits="$(printf 'name: openbao-customer\n' | grep -ciE "$_vendor_pattern" || true)"
    [ "$hits" -eq 1 ]
}
