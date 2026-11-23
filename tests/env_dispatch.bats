#!/usr/bin/env bats
# bats file_tags=smoke
#
# Where env work is reached now (TRACKER §127). `manifest env` is gone; its
# three subcommands are options of the commands they belong to:
#
#   env generate [-y]      →  init repo [-y]
#   env generate --check   →  init repo --check
#   env validate           →  init repo --check
#   env export             →  status repo --env --json
#
# Every test runs the tree's own entrypoint, because the routing under test is
# the entrypoint's: the early refusal of `env` happens before any
# configuration is loaded, and `--check` must be taken before init's connect
# defaults, which would otherwise plan a GitHub repository for a repo with no
# origin. Engine semantics (what drift is, what the export holds) are pinned
# in env_generate.bats and env_export.bats.
#
# Tagged smoke: a CI job that still runs `manifest env …` must fail, not pass
# on a command that did nothing.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    PROJ="$SCRATCH/fidence.app.demo"
    mkdir -p "$PROJ"
    git -C "$PROJ" init -q -b main
    unset MANIFEST_CLI_PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# cli args... → RC, $SCRATCH/out (stdout), $SCRATCH/err (stderr)
cli() {
    RC=0
    ( cd "$PROJ" && "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@" ) \
        > "$SCRATCH/out" 2> "$SCRATCH/err" || RC=$?
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

tree_listing() {
    ( cd "$PROJ" && find . -path ./.git -prune -o -print | sort )
}

# --- the removed command ------------------------------------------------------------

@test "manifest env: every former subcommand exits 1, names its replacement on stderr, and touches nothing" {
    write_spec
    local before sub
    before="$(tree_listing)"
    for sub in "generate -y" "generate" "generate --check" "validate" "export" "" "frobnicate"; do
        # shellcheck disable=SC2086  # the subcommand is split on purpose
        cli env $sub
        [ "$RC" -eq 1 ] || { echo "env $sub exited $RC"; return 1; }
        [ ! -s "$SCRATCH/out" ]
        grep -qF "manifest env was removed" "$SCRATCH/err"
        # Local-only, as env generate was: the table never sends a CI job to a
        # command that connects origin or creates a repository.
        grep -qF "manifest env generate -y      →  manifest init repo --no-connect -y" "$SCRATCH/err"
        grep -qF "manifest env validate         →  manifest init repo --check" "$SCRATCH/err"
        grep -qF "it can fail where env generate --check passed" "$SCRATCH/err"
        grep -qF "manifest env export           →  manifest status repo --env --json" "$SCRATCH/err"
        # Refused before configuration is loaded: no loading line at all.
        refute grep -q "Loading" "$SCRATCH/err"
    done
    [ "$(tree_listing)" = "$before" ]
    [ ! -e "$PROJ/.env.example" ]
}

@test "manifest help no longer lists env, and lists its replacements" {
    cli help
    [ "$RC" -eq 0 ]
    refute grep -qE '^ +env generate' "$SCRATCH/out"
    grep -qF -- "--check" "$SCRATCH/out"
    grep -qF "status repo --env [--json]" "$SCRATCH/out"
}

# --- init repo --check --------------------------------------------------------------

@test "init repo --check: read-only — reports drift, exits 1, writes nothing, and plans no GitHub repository" {
    write_spec
    local before
    before="$(tree_listing)"
    cli init repo --check
    [ "$RC" -eq 1 ]
    grep -qF "Env check — $PROJ" "$SCRATCH/out"
    grep -qF "stale artifacts — run: manifest init repo -y" "$SCRATCH/out"
    grep -qF "env check: FAIL" "$SCRATCH/out"
    # No origin, and still no connect phase: --check is taken first.
    refute grep -qi "gh repo create" "$SCRATCH/out" "$SCRATCH/err"
    [ "$(tree_listing)" = "$before" ]
}

@test "init repo --check: PASS once init -y has written .env.example; FAIL again after a spec edit" {
    write_spec
    cli init repo --no-connect -y
    [ "$RC" -eq 0 ] || { cat "$SCRATCH/out" "$SCRATCH/err"; return 1; }
    cli init repo --check
    [ "$RC" -eq 0 ] || { cat "$SCRATCH/out" "$SCRATCH/err"; return 1; }
    grep -qF "env check: PASS" "$SCRATCH/out"

    yq e -i '.env[0].default = "debug"' "$PROJ/app.spec.yaml"
    cli init repo --check
    [ "$RC" -eq 1 ]
}

@test "init repo --check: no spec is informative, not a failure" {
    cli init repo --check
    [ "$RC" -eq 0 ]
    grep -qF "no spec env: block — nothing generated yet (manifest init repo -y creates one)" "$SCRATCH/out"
    [ ! -e "$PROJ/service.spec.yaml" ]
}

@test "init repo --check refuses to be combined with anything that writes or connects" {
    local extra
    for extra in "-y" "--force" "--connect" "--remote $SCRATCH/x.git" "--create-repo-private"; do
        # shellcheck disable=SC2086
        cli init repo --check $extra
        [ "$RC" -ne 0 ] || { echo "--check $extra was accepted"; return 1; }
        grep -qF -- "--check is read-only" "$SCRATCH/out" "$SCRATCH/err"
    done
    [ ! -e "$PROJ/.env.example" ]
}

# --- the end of the §127 loop --------------------------------------------------------

@test "§127: init repo -y on a repo with no spec creates one, and the env check then reads it — no loop" {
    cli init repo --no-connect -y
    [ "$RC" -eq 0 ] || { cat "$SCRATCH/out" "$SCRATCH/err"; return 1; }
    [ -f "$PROJ/service.spec.yaml" ]
    cli init repo --check
    [ "$RC" -eq 0 ]
    refute grep -qF "no spec env: block" "$SCRATCH/out"
    grep -qF "artifacts match the spec env: block" "$SCRATCH/out"
}

# --- status repo --env --------------------------------------------------------------

@test "status repo --env: a line per variable; --json: the export document" {
    write_spec
    cli status repo --env
    [ "$RC" -eq 0 ]
    grep -qE '^  FIDENCE_APP_DEMO_LOG_LEVEL +optional += info$' "$SCRATCH/out"

    cli status repo --env --json
    [ "$RC" -eq 0 ]
    [ "$(yq e -p=json '.env[0].name' "$SCRATCH/out")" = "FIDENCE_APP_DEMO_LOG_LEVEL" ]
}

@test "status --env is a repository view: fleet, --bootstrap and --verify are refused" {
    write_spec
    local combo
    for combo in "fleet --env" "--env --bootstrap" "--env --verify"; do
        # shellcheck disable=SC2086
        cli status $combo
        [ "$RC" -eq 1 ] || { echo "status $combo exited $RC"; return 1; }
        grep -qF -- "--env is a repository view" "$SCRATCH/err"
    done
}

@test "help for init repo and status names the env options" {
    cli init repo --help
    [ "$RC" -eq 0 ]
    grep -qF -- "--check" "$SCRATCH/out"
    grep -qF "status repo --env --json" "$SCRATCH/out"
    cli status --help
    [ "$RC" -eq 0 ]
    grep -qF -- "--env" "$SCRATCH/out"
}
