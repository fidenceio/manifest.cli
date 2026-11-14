#!/usr/bin/env bats
# bats file_tags=smoke
#
# The three boolean flags of a spec `env:` entry — secret, required, public —
# are read by ONE predicate, and a value it cannot read as a boolean is
# refused by name (TRACKER §98).
#
# Every reader used to compare yq's PRINTED text with the string "true". So
# `secret: yes` (a string to this parser) and `secret: True` (a real YAML
# boolean that prints as `True`) both read as "not a secret": the entry's
# default went into k8s/env/configmap.yaml and into .env.example as a live
# assignment, exit 0 — and with no env.secrets configured at all, because the
# fail-closed store gate counts only the entries it reads as secret.
#
#   accepted    true / True / TRUE and the string "true"; false / False / FALSE,
#               the string "false", an absent flag, an explicit null
#   refused     everything else, naming the entry and the flag: preview,
#               --check and -y exit 1 and write nothing
#   every path  generate, validate, and the init-time .env.example scaffold
#
# Tagged smoke: which file a secret lands in is a safety contract.

load 'helpers/setup'

_SECRETS_VARS=(MANIFEST_CLI_ENV_SECRETS_PROVIDER MANIFEST_CLI_ENV_SECRETS_STORE_KIND
    MANIFEST_CLI_ENV_SECRETS_STORE_NAME MANIFEST_CLI_ENV_SECRETS_API_VERSION
    MANIFEST_CLI_ENV_SECRETS_PATH MANIFEST_CLI_ENV_SECRETS_PROPERTY
    MANIFEST_CLI_ENV_SECRETS_REFRESH_INTERVAL MANIFEST_CLI_ENV_SECRETS_ENV_LABEL)

_clear_secrets_config() {
    local v
    for v in "${_SECRETS_VARS[@]}"; do unset "$v"; done
}

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
    unset MANIFEST_CLI_PROJECT_ROOT
    _clear_secrets_config
}

# The value no file may ever carry.
_SENTINEL="hunter2-sentinel-default"

# One entry whose three flags are given verbatim (YAML source text), carrying
# a default so a misread secret has something to leak.
#   _write_spec <secret> [<required>] [<public>]
_write_spec() {
    cat > "$PROJ/app.spec.yaml" <<YAML
name: acme.svc.billing
env:
  - name: ACME_SVC_BILLING_LOG_LEVEL
    default: info
  - name: ACME_SVC_BILLING_API_TOKEN
    default: ${_SENTINEL}
    secret: ${1}
    required: ${2:-false}
    public: ${3:-false}
YAML
}

_no_artifacts_written() {
    [ ! -f "$PROJ/.env.example" ]
    [ ! -d "$PROJ/k8s/env" ]
}

_sentinel_nowhere() {
    refute grep -rq -- "$_SENTINEL" "$PROJ/.env.example" "$PROJ/k8s/env"
}

# --- the predicate ------------------------------------------------------------------

@test "predicate: every spelling of a boolean reads as its value; an absent or null flag is false" {
    local spelling
    for spelling in true True TRUE '"true"' "'true'" '!!bool true' '!!str true'; do
        _write_spec "$spelling"
        run _manifest_env_spec_flag "$PROJ/app.spec.yaml" 1 secret
        [ "$status" -eq 0 ] || { echo "secret: $spelling → status $status"; false; }
        [ "$output" = "true" ] || { echo "secret: $spelling → '$output'"; false; }
    done
    for spelling in false False FALSE '"false"' '~' ''; do
        _write_spec "$spelling"
        run _manifest_env_spec_flag "$PROJ/app.spec.yaml" 1 secret
        [ "$status" -eq 0 ] || { echo "secret: $spelling → status $status"; false; }
        [ "$output" = "false" ] || { echo "secret: $spelling → '$output'"; false; }
    done
    # Absent: the first entry declares no flag at all.
    run _manifest_env_spec_flag "$PROJ/app.spec.yaml" 0 secret
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "predicate: a value that is not a boolean is refused — status 2, nothing printed, never 'false'" {
    local spelling
    # The last four are values a tag forces into a boolean: yq encodes
    # `!!bool 1` as false, so the encoding alone would read it as "not a secret".
    for spelling in yes Yes YES on off no y n 1 0 '"yes"' '"True"' '" true"' '[true]' '{a: true}' '"true\nx"' \
                    '!!bool 1' '!!bool 0' '!!bool banana' '!!bool yes'; do
        _write_spec "$spelling"
        run _manifest_env_spec_flag "$PROJ/app.spec.yaml" 1 secret
        [ "$status" -eq 2 ] || { echo "secret: $spelling → status $status, output '$output'"; false; }
        [ -z "$output" ] || { echo "secret: $spelling printed '$output'"; false; }
    done
}

@test "positive control: the old reading — printed text compared with \"true\" — calls a True or yes secret false" {
    # What every reader did before. If yq ever starts printing `true` for
    # these, the tests below stop proving anything and this says so.
    # (That comparing the flag with the boolean inside yq is also false for
    # `True` is recorded in the tracker row, not pinned here: the fix does not
    # depend on it, and the macOS CI leg installs whatever yq brew has.)
    local spelling
    for spelling in True yes; do
        _write_spec "$spelling"
        [ "$(yq e '.env[1].secret // false' "$PROJ/app.spec.yaml")" != "true" ]
    done
}

# --- generate refuses, in every mode ---------------------------------------------------

@test "generate: yes, on and 1 are refused for each flag — preview, --check and -y exit 1, name the entry and flag, write nothing" {
    _configure_store
    local flag spelling mode
    for flag in secret required public; do
        for spelling in yes on 1; do
            case "$flag" in
                secret)   _write_spec "$spelling" ;;
                required) _write_spec false "$spelling" ;;
                public)   _write_spec false false "$spelling" ;;
            esac
            for mode in "" "--check" "-y"; do
                # shellcheck disable=SC2086
                run manifest_env_generate $mode
                [ "$status" -eq 1 ] || { echo "$flag: $spelling ($mode) → status $status"; echo "$output"; false; }
                [[ "$output" == *"env spec — cannot generate"* ]]
                [[ "$output" == *"ACME_SVC_BILLING_API_TOKEN: ${flag} is "* ]] || { echo "$flag: $spelling ($mode)"; echo "$output"; false; }
                [[ "$output" == *"write true or false"* ]]
                [[ "$output" == *"Nothing was written."* ]]
                _no_artifacts_written
            done
        done
    done
}

@test "generate: the refusal quotes the value as written and names every bad flag, not just the first" {
    _write_spec yes on 1
    run manifest_env_generate
    [ "$status" -eq 1 ]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: secret is "yes" — write true or false'* ]]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: required is "on" — write true or false'* ]]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: public is 1 — write true or false'* ]]
    # The entry that is fine is not named.
    [[ "$output" != *"ACME_SVC_BILLING_LOG_LEVEL:"* ]]
}

@test "no env.secrets configured: secret: yes is refused, and its default reaches no file (the path that had no gate)" {
    # The store gate counts only entries it reads as secret, so this spec used
    # to pass it with nothing configured: exit 0, the default in the ConfigMap
    # and live in .env.example.
    _write_spec yes
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: secret is "yes"'* ]]
    _no_artifacts_written

    # Control: the same spec with the flag spelled true is a secret, and with
    # nothing configured the store gate is what refuses it.
    _write_spec true
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"env.secrets.provider is not set, but 1 secret variable(s) are declared: ACME_SVC_BILLING_API_TOKEN"* ]]
    _no_artifacts_written
}

@test "a tag that forces a non-boolean into one is refused as written: secret: !!bool 1 leaks nothing" {
    # yq's JSON encoding of `!!bool 1` is `false`. Read from the encoding
    # alone, this entry is "not a secret" and its default is published.
    _write_spec '!!bool 1'
    run manifest_env_generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: secret is 1 (under an explicit tag) — write true or false'* ]]
    _no_artifacts_written
}

# --- accepted spellings mean what they say ------------------------------------------------

@test "secret: True and \"true\" are secrets: gated with no store, bridged with one, and the default is in no file" {
    local spelling
    for spelling in True TRUE '"true"'; do
        rm -rf "$PROJ/k8s/env" "$PROJ/.env.example"
        _clear_secrets_config
        _write_spec "$spelling"
        run manifest_env_generate -y
        [ "$status" -eq 1 ] || { echo "secret: $spelling ungated → status $status"; echo "$output"; false; }
        [[ "$output" == *"1 secret variable(s) are declared: ACME_SVC_BILLING_API_TOKEN"* ]]
        _no_artifacts_written

        _configure_store
        run manifest_env_generate -y
        [ "$status" -eq 0 ] || { echo "secret: $spelling → status $status"; echo "$output"; false; }
        [ "$(yq e '.spec.data[0].secretKey' "$PROJ/k8s/env/external-secret.yaml")" = "ACME_SVC_BILLING_API_TOKEN" ]
        refute grep -q "API_TOKEN" "$PROJ/k8s/env/configmap.yaml"
        grep -q '^# ACME_SVC_BILLING_API_TOKEN=$' "$PROJ/.env.example"
        _sentinel_nowhere
    done
}

@test "positive control: with secret: false the same default DOES land in the ConfigMap and .env.example" {
    # Proves the sentinel assertions above can fail.
    _write_spec false
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    grep -q -- "$_SENTINEL" "$PROJ/k8s/env/configmap.yaml"
    grep -q "^ACME_SVC_BILLING_API_TOKEN=${_SENTINEL}\$" "$PROJ/.env.example"
}

@test "required: True and public: True are read as true by the example and the Dockerfile bridge" {
    printf 'FROM scratch\n' > "$PROJ/Dockerfile"
    _write_spec false True True
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    grep -q '^# ACME_SVC_BILLING_API_TOKEN (required, public (build-time))$' "$PROJ/.env.example"
    grep -q '^ARG ACME_SVC_BILLING_API_TOKEN$' "$PROJ/Dockerfile"

    # Control: false renders optional, and no block.
    rm -f "$PROJ/.env.example"; printf 'FROM scratch\n' > "$PROJ/Dockerfile"
    _write_spec false False False
    run manifest_env_generate -y
    [ "$status" -eq 0 ]
    grep -q '^# ACME_SVC_BILLING_API_TOKEN (optional)$' "$PROJ/.env.example"
    refute grep -q '^ARG ' "$PROJ/Dockerfile"
}

# --- the other two paths ---------------------------------------------------------------------

@test "env validate: a refused flag is reported as a spec problem naming the entry, and validate FAILS" {
    _write_spec yes
    run manifest_env_validate
    [ "$status" -eq 1 ]
    [[ "$output" == *"spec flags — a secret, required or public flag is neither true nor false"* ]]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: secret is "yes" — write true or false'* ]]
    # Not misreported as stale output or as a store gap.
    [[ "$output" != *"stale artifacts"* ]]
    [[ "$output" != *"secret store not configured"* ]]
}

@test "init scaffold: a spec with secret: yes gets NO .env.example, and the entry and flag are named" {
    # ensure_env_files renders .env.example at init time, through none of
    # generate's gates. It used to write the default as a live assignment.
    _write_spec yes
    run ensure_env_files "$PROJ"
    [ "$status" -eq 1 ]
    [ ! -f "$PROJ/.env.example" ]
    [[ "$output" == *"app.spec.yaml env: has a flag that is neither true nor false"* ]]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: secret is "yes" — write true or false'* ]]

    # Control: spelled true, the scaffold writes the example with the secret
    # commented out and valueless.
    _write_spec true
    run ensure_env_files "$PROJ"
    [ "$status" -eq 0 ]
    grep -q '^# ACME_SVC_BILLING_API_TOKEN=$' "$PROJ/.env.example"
    refute grep -q -- "$_SENTINEL" "$PROJ/.env.example"
}

@test "a renderer handed a refused flag stops with a non-zero status; it never renders the entry as a non-secret" {
    # The renderers are callable on their own (the scaffold does), so the
    # refusal lives in them and not only in generate's gate.
    _write_spec yes
    run _manifest_env_render_configmap "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -ne 0 ]
    [[ "$output" != *"$_SENTINEL"* ]]
    run _manifest_env_render_example "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -ne 0 ]
    [[ "$output" != *"$_SENTINEL"* ]]
    run _manifest_env_spec_secret_names "$PROJ/app.spec.yaml"
    [ "$status" -ne 0 ]
    _configure_store
    run _manifest_env_render_external_secret "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -ne 0 ]

    # The other two flags stop the renderers that read them.
    _write_spec false yes
    run _manifest_env_render_example "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -ne 0 ]
    _write_spec false false yes
    run _manifest_env_render_example "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -ne 0 ]
    run _manifest_env_render_dockerfile_bridge "$PROJ/app.spec.yaml"
    [ "$status" -ne 0 ]

    # Control: the same four calls succeed on a spec whose flags are booleans.
    _write_spec true true true
    run _manifest_env_render_configmap "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -eq 0 ]
    run _manifest_env_render_example "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -eq 0 ]
    run _manifest_env_render_external_secret "$PROJ/app.spec.yaml" "$PROJ"
    [ "$status" -eq 0 ]
    run _manifest_env_render_dockerfile_bridge "$PROJ/app.spec.yaml"
    [ "$status" -eq 0 ]
}

# --- through the real entrypoint -----------------------------------------------------------

@test "through scripts/manifest-cli.sh: secret: yes with no env.secrets exits 1 and writes nothing" {
    # The wrapper refuses a folder that is not a git repository, loads config
    # from the repo, and is what an adopter actually runs.
    git -C "$PROJ" init -q -b main
    _write_spec yes
    local home="$SCRATCH/home"
    mkdir -p "$home"
    run env HOME="$home" "$TEST_REPO_ROOT/scripts/manifest-cli.sh" env generate -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'ACME_SVC_BILLING_API_TOKEN: secret is "yes" — write true or false'* ]]
    _no_artifacts_written
}

# --- one reader ---------------------------------------------------------------------------------

# A yq path that names one of the three flags: `.secret`, `.required` or
# `.public` standing as a path of its own — not the tail of a dotted config key
# (docs.review.required) and not a file pattern (*.secret.yaml).
_FLAG_PATH='(^|[^A-Za-z0-9_])\.(secret|required|public)([^A-Za-z0-9_.]|$)'

@test "no module names a spec flag in a yq path: the only reader is _manifest_env_spec_flag" {
    # The predicate reads `.env[$index].$flag` and so names no flag itself; any
    # hit is a second reader, whatever it does with the value.
    run grep -rnE -- "$_FLAG_PATH" "$TEST_REPO_ROOT/modules"
    [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "positive control: that scan fires on every reader shape, and not on a config key or a file pattern" {
    local probe="$SCRATCH/probe.sh" shape
    for shape in \
        'secret="$(yq e ".env[$i].secret // false" "$spec_file")"' \
        "yq e '.env[] | select((.secret // false | tostring) == \"true\")'" \
        'public="$(yq e ".env[$i].public | tostring" "$spec_file")"' \
        "yq e '.env[] | select(.secret == true) | .name'" \
        'required="$(yq e ".env[$2].required" "$spec_file")"' \
        "yq e '.env[] | select(.public)'"; do
        printf '%s\n' "$shape" > "$probe"
        grep -qE -- "$_FLAG_PATH" "$probe" || { echo "not caught: $shape"; false; }
    done
    for shape in \
        '    ["docs.review.required"]="MANIFEST_CLI_DOC_REVIEW_REQUIRED"' \
        '*.secret.yaml' \
        '# falls back unless docs.release_notes.required is true.'; do
        printf '%s\n' "$shape" > "$probe"
        refute grep -qE -- "$_FLAG_PATH" "$probe"
    done
}
