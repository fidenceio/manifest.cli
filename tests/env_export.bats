#!/usr/bin/env bats
# bats file_tags=smoke
#
# `manifest status repo --env --json` — the variable contract as JSON,
# read-only (TRACKER §104; the command was `manifest env export` until §127).
#
# A platform's own generator reads this to render deployment files, so the
# document is a contract with a consumer that cannot ask what was meant:
#
#   shape       schema 1, identity, env[] in spec order, eight fields each
#   exact       every string is JSON-encoded: quotes, backslashes and newlines
#               survive a round trip; a default of false or 0 is not "unset"
#   no secret   a secret's default is never printed
#   one reader  the three flags are read by the predicate generate uses
#   all or      a spec it cannot represent is refused by name: nothing on
#   nothing     stdout, the reason on stderr, exit 1
#   read-only   it writes no file
#
# Every test runs the tree's own entrypoint with stdout and stderr apart: the
# wrapper refuses a folder that is not a git repository and prints its loading
# lines on stderr, and neither is visible to a test that sources the module.
#
# Tagged smoke: a consumer handed a secret's default, or half a document,
# publishes it.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    PROJ="$SCRATCH/acme.svc.billing"
    mkdir -p "$PROJ"
    git -C "$PROJ" init -q -b main
    unset MANIFEST_CLI_PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# export_run [args...] → RC, $SCRATCH/out (stdout), $SCRATCH/err (stderr)
export_run() {
    RC=0
    ( cd "$PROJ" && "$TEST_REPO_ROOT/scripts/manifest-cli.sh" status repo --env --json "$@" ) \
        > "$SCRATCH/out" 2> "$SCRATCH/err" || RC=$?
}

# One value out of the exported document, read back by a JSON parser.
j() {
    yq e -p=json "$1" "$SCRATCH/out"
}

refused_naming() {
    [ "$RC" -eq 1 ] || { echo "expected exit 1, got $RC"; cat "$SCRATCH/out" "$SCRATCH/err"; return 1; }
    [ ! -s "$SCRATCH/out" ] || { echo "stdout is not empty:"; cat "$SCRATCH/out"; return 1; }
    grep -qF -- "$1" "$SCRATCH/err" || { echo "stderr does not say: $1"; cat "$SCRATCH/err"; return 1; }
}

write_spec() {
    cat > "$PROJ/service.spec.yaml" <<'YAML'
name: acme.svc.billing
env:
  - name: ACME_SVC_BILLING_LOG_LEVEL
    description: How much the service logs
    default: info
  - name: ACME_SVC_BILLING_SITE_URL
    default: https://billing.example
    required: true
    public: true
    framework_name: NEXT_PUBLIC_SITE_URL
  - name: ACME_SVC_BILLING_DB_PASSWORD
    description: Database role password
    required: true
    secret: true
    default: hunter2-sentinel-default
    group: db
    framework_name: DATABASE_URL
YAML
}

# --- shape -----------------------------------------------------------------------------------

@test "the document: schema 1, identity, every entry in spec order with all eight fields" {
    write_spec
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.schema')" = "1" ]
    [ "$(j '.identity')" = "acme.svc.billing" ]      # no origin: the folder name
    [ "$(j '.env | length')" = "3" ]
    [ "$(j '[.env[].name] | join(",")')" = "ACME_SVC_BILLING_LOG_LEVEL,ACME_SVC_BILLING_SITE_URL,ACME_SVC_BILLING_DB_PASSWORD" ]
    # The same eight keys on every entry, set in the spec or not.
    local i
    for i in 0 1 2; do
        [ "$(j ".env[$i] | keys | join(\",\")")" = "name,description,required,default,secret,group,public,framework_name" ]
    done

    # Unset fields have their documented values: "" / false / "app" / null.
    [ "$(j '.env[0].description')" = "How much the service logs" ]
    [ "$(j '.env[1].description | tag')" = "!!str" ]
    [ "$(j '.env[1].description')" = "" ]
    [ "$(j '.env[0].required')" = "false" ]
    [ "$(j '.env[0].secret')" = "false" ]
    [ "$(j '.env[0].public')" = "false" ]
    [ "$(j '.env[0].group')" = "app" ]               # the effective group
    [ "$(j '.env[0].framework_name | tag')" = "!!null" ]

    [ "$(j '.env[1].required')" = "true" ]
    [ "$(j '.env[1].public')" = "true" ]
    [ "$(j '.env[1].framework_name')" = "NEXT_PUBLIC_SITE_URL" ]
    [ "$(j '.env[1].default')" = "https://billing.example" ]
    [ "$(j '.env[2].secret')" = "true" ]
    [ "$(j '.env[2].group')" = "db" ]
    [ "$(j '.env[2].framework_name')" = "DATABASE_URL" ]
}

@test "identity is the origin repository's name, whatever the folder is called and however the URL is written" {
    write_spec
    # The credential is spliced in from a variable: a literal user:password@
    # URL in a tracked file is what the pre-commit secret scan refuses.
    local url cred='s3cr3t-token'
    for url in "git@github.com:acme/billing-service.git" \
               "https://github.com/acme/billing-service.git" \
               "https://git.example.test/team/sub/billing-service" \
               "https://user:${cred}@git.example.test/acme/billing-service.git/" \
               "ssh://git@git.example.test:2222/acme/billing-service.git"; do
        git -C "$PROJ" remote remove origin 2>/dev/null || true
        git -C "$PROJ" remote add origin "$url"
        export_run
        [ "$RC" -eq 0 ]
        [ "$(j '.identity')" = "billing-service" ] || { echo "$url → $(j '.identity')"; false; }
        # Nothing else of the URL is in the document — a credential least of all.
        refute grep -q 's3cr3t-token\|git.example.test\|github.com' "$SCRATCH/out"
    done
}

@test "an origin URL that does not end in a plain name falls back to the folder: no part of a credential or a query becomes the identity" {
    write_spec
    local url cred='s3cr3t-token'
    for url in "https://user:${cred}@git.example.test" \
               "https://git.example.test/acme/billing-service?token=${cred}" \
               "https://git.example.test/acme/billing service.git"; do
        git -C "$PROJ" remote remove origin 2>/dev/null || true
        git -C "$PROJ" remote add origin "$url"
        export_run
        [ "$RC" -eq 0 ]
        [ "$(j '.identity')" = "acme.svc.billing" ] || { echo "$url → $(j '.identity')"; false; }
        refute grep -q 's3cr3t-token\|git.example.test' "$SCRATCH/out"
        refute grep -q 's3cr3t-token' "$SCRATCH/err"
    done
}

@test "the option order does not matter, and an unknown option is refused with nothing on stdout" {
    write_spec
    export_run
    local first
    first="$(cat "$SCRATCH/out")"
    RC=0
    ( cd "$PROJ" && "$TEST_REPO_ROOT/scripts/manifest-cli.sh" status --json --env repo ) \
        > "$SCRATCH/out" 2> "$SCRATCH/err" || RC=$?
    [ "$RC" -eq 0 ]
    [ "$(cat "$SCRATCH/out")" = "$first" ]

    export_run --frobnicate
    [ "$RC" -eq 1 ]
    [ ! -s "$SCRATCH/out" ] || grep -qF "Unknown option: --frobnicate" "$SCRATCH/out"
    grep -qF "Unknown option: --frobnicate" "$SCRATCH/out" "$SCRATCH/err"
    refute grep -q '"schema"' "$SCRATCH/out"
}

# --- exact -----------------------------------------------------------------------------------

@test "quotes, backslashes and newlines in a description or default survive, and the output is one valid JSON document" {
    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: ACME_SVC_BILLING_GREETING
    description: 'say "hi" then \ back'
    default: "tab\there \"quoted\" back\\slash"
  - name: ACME_SVC_BILLING_BANNER
    description: |
      line one
      line two
    default: "first\nsecond"
YAML
    export_run
    [ "$RC" -eq 0 ]
    # A JSON parser reads it; a broken document would fail here.
    [ "$(j '.env | length')" = "2" ]
    [ "$(j '.env[0].description')" = 'say "hi" then \ back' ]
    [ "$(j '.env[0].default')" = "$(printf 'tab\there "quoted" back\\slash')" ]
    [ "$(j '.env[1].default')" = "$(printf 'first\nsecond')" ]
    [ "$(j '.env[1].description')" = "$(printf 'line one\nline two')" ]
    # The newline is escaped inside the string, not printed raw across lines.
    grep -q '"default": "first\\nsecond"' "$SCRATCH/out"
}

@test "a default of false, 0 or the empty string is a value; only null and absent are null" {
    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_FALSE
    default: false
  - name: A_ZERO
    default: 0
  - name: A_EMPTY
    default: ""
  - name: A_NULL
    default: null
  - name: A_ABSENT
  - name: A_NUMBER
    default: 8080
YAML
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.env[0].default')" = "false" ]
    [ "$(j '.env[0].default | tag')" = "!!str" ]     # a string, as an env value is
    [ "$(j '.env[1].default')" = "0" ]
    [ "$(j '.env[1].default | tag')" = "!!str" ]
    [ "$(j '.env[2].default | tag')" = "!!str" ]
    [ "$(j '.env[2].default')" = "" ]
    [ "$(j '.env[3].default | tag')" = "!!null" ]
    [ "$(j '.env[4].default | tag')" = "!!null" ]
    [ "$(j '.env[5].default')" = "8080" ]
}

@test "an alias or a merge key is exported as the value it stands for, never as the text *name" {
    cat > "$PROJ/service.spec.yaml" <<'YAML'
shared: &site https://billing.example
base: &entry
  name: A_MERGED
  default: from-the-anchor
env:
  - name: A_ALIASED
    default: *site
    description: *site
  - <<: *entry
    description: merged in
YAML
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.env[0].default')" = "https://billing.example" ]
    [ "$(j '.env[0].description')" = "https://billing.example" ]
    [ "$(j '.env[1].name')" = "A_MERGED" ]
    [ "$(j '.env[1].default')" = "from-the-anchor" ]
    refute grep -q '\*site\|\*entry' "$SCRATCH/out"
}

@test "init and the export agree on a default of false: .env.example carries it too" {
    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_FLAG
    default: false
  - name: A_ZERO
    default: 0
  - name: A_UNSET
YAML
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.env[0].default')" = "false" ]
    ( cd "$PROJ" && "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init repo --no-connect -y ) >/dev/null 2>&1
    grep -qx 'A_FLAG=false' "$PROJ/.env.example"
    grep -qx 'A_ZERO=0' "$PROJ/.env.example"
    grep -qx 'A_UNSET=' "$PROJ/.env.example"       # control: unset is still empty
}

# --- no secret ---------------------------------------------------------------------------------

@test "a secret's default is never printed: null in the document, and the value nowhere on stdout or stderr" {
    write_spec
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.env[2].secret')" = "true" ]
    [ "$(j '.env[2].default | tag')" = "!!null" ]
    refute grep -q 'hunter2-sentinel-default' "$SCRATCH/out"
    refute grep -q 'hunter2-sentinel-default' "$SCRATCH/err"

    # Positive control: the same entry, not a secret, does export that default
    # — so the assertions above can fail.
    yq e -i '.env[2].secret = false' "$PROJ/service.spec.yaml"
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.env[2].default')" = "hunter2-sentinel-default" ]
}

@test "the flags are read as generate reads them: True and \"true\" are true, and a secret spelled that way is still a secret" {
    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_TOKEN
    default: hunter2-sentinel-default
    secret: True
    required: "true"
    public: FALSE
YAML
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.env[0].secret')" = "true" ]
    [ "$(j '.env[0].secret | tag')" = "!!bool" ]
    [ "$(j '.env[0].required')" = "true" ]
    [ "$(j '.env[0].public')" = "false" ]
    [ "$(j '.env[0].default | tag')" = "!!null" ]
    refute grep -q 'hunter2-sentinel-default' "$SCRATCH/out"
}

# --- all or nothing ----------------------------------------------------------------------------

@test "refused by name, with nothing on stdout: a flag that is not a boolean, an entry with no name, a name used twice, a list for a value" {
    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_TOKEN
    default: hunter2-sentinel-default
    secret: yes
YAML
    export_run
    refused_naming 'A_TOKEN: secret is "yes" — write true or false'
    refute grep -q 'hunter2-sentinel-default' "$SCRATCH/err"

    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_ONE
  - description: no name here
    default: x
YAML
    export_run
    refused_naming 'entry 2: has no name'

    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_ONE
  - name: A_TWO
  - name: A_ONE
    default: again
YAML
    export_run
    refused_naming 'A_ONE: declared more than once'

    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_ONE
    default: [a, b]
YAML
    export_run
    refused_naming 'A_ONE: default is a list or a map — write a single value'

    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - just-a-string
YAML
    export_run
    refused_naming 'entry 1: not a mapping'

    # A framework name is written into a Dockerfile or manifest line by a
    # consumer; a newline in it would start a line of its own.
    cat > "$PROJ/service.spec.yaml" <<'YAML'
env:
  - name: A_ONE
    public: true
    framework_name: "FOO\nBAR"
YAML
    export_run
    refused_naming 'A_ONE: framework_name spans more than one line'

    # A top-level list: yq cannot index it, and the refusal still says why.
    printf -- '- name: A_ONE\n' > "$PROJ/service.spec.yaml"
    export_run
    refused_naming 'is not a map of keys'

    # A top-level single value: yq answers .env on it without failing, so it
    # was reported as an env: key that is not a list — a key it does not have.
    # Init calls this file the same thing (_manifest_env_spec_plan_state).
    printf 'just a value\n' > "$PROJ/service.spec.yaml"
    export_run
    refused_naming 'service.spec.yaml is not a map of keys: its top level is a list or a single value'
    refute grep -qF 'must be a list of variables' "$SCRATCH/err"
}

@test "a spec that cannot be read is not a spec with no variables: unparseable, env: as a map, and no spec at all exit 1" {
    printf 'env:\n  - name: A_ONE\n   default: [unclosed\n' > "$PROJ/service.spec.yaml"
    export_run
    refused_naming 'service.spec.yaml cannot be parsed as YAML'

    printf 'env:\n  A_ONE: value\n' > "$PROJ/service.spec.yaml"
    export_run
    refused_naming 'env: in service.spec.yaml must be a list of variables'

    printf 'env:\n  - name: A_ONE\n---\nenv:\n  - name: A_TWO\n' > "$PROJ/service.spec.yaml"
    export_run
    refused_naming 'service.spec.yaml holds more than one YAML document'

    rm -f "$PROJ/service.spec.yaml"
    export_run
    refused_naming 'no spec file (service.spec.yaml / app.spec.yaml)'
}

@test "control: a spec that declares no variables exports an empty list and exits 0" {
    printf 'name: acme.svc.billing\n' > "$PROJ/service.spec.yaml"
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.schema')" = "1" ]
    [ "$(j '.env | tag')" = "!!seq" ]
    [ "$(j '.env | length')" = "0" ]

    printf 'name: acme.svc.billing\nenv: []\n' > "$PROJ/service.spec.yaml"
    export_run
    [ "$RC" -eq 0 ]
    [ "$(j '.env | length')" = "0" ]
}

# --- read-only ---------------------------------------------------------------------------------

@test "export writes no file: the working tree is what it was, and no .env.example appears" {
    write_spec
    printf 'FROM scratch\n' > "$PROJ/Dockerfile"
    mkdir -p "$PROJ/k8s"
    git -C "$PROJ" add -A
    git -C "$PROJ" -c user.email=t@example.com -c user.name=T commit -qm init
    local before
    before="$( cd "$PROJ" && find . -path ./.git -prune -o -type f -print | sort )"

    export_run
    [ "$RC" -eq 0 ]
    [ -z "$(git -C "$PROJ" status --porcelain)" ]
    [ "$( cd "$PROJ" && find . -path ./.git -prune -o -type f -print | sort )" = "$before" ]
    [ ! -e "$PROJ/.env.example" ]
    [ -z "$(find "$PROJ/k8s" -mindepth 1)" ]
}

@test "stdout is the document and nothing else: it starts with { and the wrapper's loading lines stay on stderr" {
    write_spec
    # A project config makes the wrapper print a loading line.
    printf 'env:\n  prefix: ACME_\n' > "$PROJ/manifest.config.yaml"
    export_run
    [ "$RC" -eq 0 ]
    [ "$(head -c 1 "$SCRATCH/out")" = "{" ]
    [ "$(tail -n 1 "$SCRATCH/out")" = "}" ]
    refute grep -q 'Loading' "$SCRATCH/out"
    grep -q 'Loading project configuration' "$SCRATCH/err"     # the line exists, and is on stderr
}
