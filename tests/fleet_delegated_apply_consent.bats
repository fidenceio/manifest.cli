#!/usr/bin/env bats

# Apply-target consent has THREE possible origins, and each gate accepts a
# different subset. This file pins all of them at once, because fixing one in
# isolation is what produced the regression it guards.
#
#   (A) MANIFEST_CLI_AUTO_CONFIRM=1 in the PROCESS ENVIRONMENT AT PROCESS START
#       -- the operator typed it in their shell. Accepted by BOTH gates.
#   (B) automation.auto_confirm in a CONFIG FILE. That key is MAPPED, so a
#       cloned repo's committed manifest.config.yaml assigns
#       MANIFEST_CLI_AUTO_CONFIRM long after the modules were sourced. Accepted
#       by NEITHER gate (TRACKER §46).
#   (C) _MANIFEST_CLI_DELEGATED_APPLY_CONSENT=1 -- `manifest fleet ship -y`
#       delegating a member's apply IN-PROCESS. The operator's consent is real,
#       but it was given to the fleet command, so it can never appear in this
#       process's start environment. Accepted by the APPLY-TARGET gate only;
#       the global-config gate must keep ignoring it, which is what
#       manifest-fleet.sh's own comment promises ("fleet consent cannot
#       authorize incidental config migration").
#
# §46 collapsed (C) into (A)'s predicate, so every fleet member sitting on a
# detached HEAD or without an origin remote was refused as an "Ambiguous apply
# target" -- the exact states `fleet ship -y` exists to carry through.
#
# NOTE on hermeticity: helpers/setup.bash unsets MANIFEST_CLI_AUTO_CONFIRM
# BEFORE anything here runs, and manifest-config.sh snapshots the variable at
# SOURCE time. Every case below therefore starts from "no process-start consent"
# and must re-take the snapshot explicitly to simulate (A) -- see
# grant_auto_confirm_from_process_env, the same pattern safety_gate.bats uses.

load 'helpers/setup'

# Real git, captured before anything can shadow it, so fixtures use the genuine
# binary regardless of what the module graph puts on PATH.
REAL_GIT="$(command -v git)"

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    # HOME is set BEFORE the modules load: manifest-config.sh resolves
    # MANIFEST_CLI_GLOBAL_CONFIG from $HOME at source time, and a real global
    # config would otherwise be in scope for the load_configuration cases below.
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME

    # The FULL module graph, exactly as scripts/manifest-cli.sh wires it (plus
    # the fleet module core does not pull in). Two reasons, both load-bearing:
    #
    #  - The apply-target gate consults manifest-config.sh's process-start
    #    snapshot through a declare -F probe. Without that module the probe
    #    misses and the gate falls back to reading the live variable -- which is
    #    precisely the code path that CANNOT show a §46 regression. (This is why
    #    the existing repo_scope_confirmation.bats cases stayed green through
    #    the regression: helpers/setup.bash's load_modules does not source it.)
    #  - The end-to-end case at the bottom drives the real `fleet ship` path.
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"

    # Neutralize the slow / networked / out-of-scope steps of the ship path.
    # None of them is the contract under test.
    get_time_timestamp() {
        MANIFEST_CLI_TIME_TIMESTAMP="1700000000"
        MANIFEST_CLI_TIME_SERVER="stub"
        MANIFEST_CLI_TIME_SERVER_IP="0.0.0.0"
        MANIFEST_CLI_TIME_OFFSET=0
        MANIFEST_CLI_TIME_UNCERTAINTY=0
        MANIFEST_CLI_TIME_METHOD="stub"
        export MANIFEST_CLI_TIME_TIMESTAMP MANIFEST_CLI_TIME_SERVER \
            MANIFEST_CLI_TIME_SERVER_IP MANIFEST_CLI_TIME_OFFSET \
            MANIFEST_CLI_TIME_UNCERTAINTY MANIFEST_CLI_TIME_METHOD
    }
    format_timestamp() { echo "2023-11-14 00:00:00 UTC"; }
    main_cleanup() { return 0; }
    validate_project() { return 0; }
    update_repository_metadata() { :; }
    fleet_validate() { return 0; }
    fleet_docs_dispatch() { return 0; }

    export MANIFEST_CLI_RELEASE_GATE=none
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=main
    export MANIFEST_CLI_GIT_RETRIES=1

    unset MANIFEST_CLI_AUTO_CONFIRM _MANIFEST_CLI_DELEGATED_APPLY_CONSENT
    unset MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED
    # Re-take the snapshot with the variable unset: known "no consent at process
    # start" regardless of ambient env.
    _manifest_config_capture_auto_confirm_env
}

teardown() {
    cd /tmp
    unset MANIFEST_CLI_AUTO_CONFIRM _MANIFEST_CLI_DELEGATED_APPLY_CONSENT
    unset MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED
    unset MANIFEST_CLI_FLEET_ROOT MANIFEST_CLI_RELEASE_GATE \
        MANIFEST_CLI_GIT_DEFAULT_BRANCH MANIFEST_CLI_GIT_RETRIES
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# Origin (A): a CLI process that STARTED with the variable in its environment.
grant_auto_confirm_from_process_env() {
    export MANIFEST_CLI_AUTO_CONFIRM="${1:-1}"
    _manifest_config_capture_auto_confirm_env
}

# Origin (C): what manifest-fleet.sh does at its two delegated-apply call sites
# -- an in-process export of BOTH variables, made after config resolution.
grant_fleet_delegated_consent() {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export _MANIFEST_CLI_DELEGATED_APPLY_CONSENT=1
}

# An AMBIGUOUS apply target: real commit, then a detached HEAD and no origin.
# Both halves of the ambiguity are present so the case does not depend on which
# one the gate happens to notice first.
mk_ambiguous_repo() {
    local repo="$SCRATCH/member"
    mkdir -p "$repo"
    "$REAL_GIT" -C "$repo" init -q
    "$REAL_GIT" -C "$repo" config user.email t@example.invalid
    "$REAL_GIT" -C "$repo" config user.name "Test User"
    echo "1.2.3" > "$repo/VERSION"
    "$REAL_GIT" -C "$repo" add VERSION
    "$REAL_GIT" -C "$repo" commit -qm seed
    "$REAL_GIT" -C "$repo" checkout -q --detach HEAD
    echo "$repo"
}

# A one-member fleet whose member has NO origin remote, which is what makes its
# apply target ambiguous (origin_required defaults to true at the apply guard).
# --local is what keeps _fleet_preflight_no_empty_remote out of the way, so the
# run reaches the per-member apply gate rather than being stopped earlier.
mk_fleet_with_ambiguous_member() {
    local work="$SCRATCH/work" version="${1:-1.2.3}"
    mkdir -p "$work/svc"
    cat > "$work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svc:
    path: "./svc"
    type: "service"
    branch: "main"
    release:
      enabled: true
YAML
    printf 'true\tsvc\t./svc\tfalse\t\tmain\t%s\n' "$version" \
        > "$work/manifest.fleet.tsv"
    "$REAL_GIT" -C "$work/svc" init -q
    "$REAL_GIT" -C "$work/svc" symbolic-ref HEAD refs/heads/main
    "$REAL_GIT" -C "$work/svc" config user.email test@example.com
    "$REAL_GIT" -C "$work/svc" config user.name test
    echo "$version" > "$work/svc/VERSION"
    "$REAL_GIT" -C "$work/svc" add VERSION
    "$REAL_GIT" -C "$work/svc" commit -qm "init $version"
    echo "$work"
}

# -----------------------------------------------------------------------------
# The regression: origin (C) must authorize the apply-target gate again
# -----------------------------------------------------------------------------

@test "apply gate: fleet's in-process delegation authorizes an ambiguous target" {
    local repo
    repo="$(mk_ambiguous_repo)"
    grant_fleet_delegated_consent

    MANIFEST_CLI_PROJECT_ROOT="$repo" \
        run manifest_repo_scope_confirm_apply "$repo" "manifest ship -y" "false" < /dev/null

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Auto-confirmed repository target (delegated by fleet -y)"
    refute grep -q "Ambiguous apply target" <<<"$output"
}

@test "apply gate: the SAME runtime export without the delegation flag is still refused" {
    # The negative control for the case above: proves it passes on the strength
    # of the delegation flag, not merely because MANIFEST_CLI_AUTO_CONFIRM was
    # exported at runtime. A runtime export is indistinguishable from what a
    # config file does, so on its own it must still authorize nothing.
    local repo
    repo="$(mk_ambiguous_repo)"
    export MANIFEST_CLI_AUTO_CONFIRM=1

    MANIFEST_CLI_PROJECT_ROOT="$repo" \
        run manifest_repo_scope_confirm_apply "$repo" "manifest ship -y" "false" < /dev/null

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Ambiguous apply target"
}

# -----------------------------------------------------------------------------
# The §46 property that must NOT regress: origin (B) authorizes nothing
# -----------------------------------------------------------------------------

@test "apply gate: a repo's COMMITTED automation.auto_confirm does not authorize an ambiguous target" {
    local repo
    repo="$(mk_ambiguous_repo)"
    # `automation.auto_confirm` is the mapped spelling; verified against
    # _MANIFEST_YAML_TO_ENV by the closure case further down.
    printf 'schema_version: 2\nautomation:\n  auto_confirm: 1\n' \
        > "$repo/manifest.config.yaml"
    "$REAL_GIT" -C "$repo" add manifest.config.yaml
    "$REAL_GIT" -C "$repo" commit -qm "committed consent"

    export MANIFEST_CLI_PROJECT_ROOT="$repo"
    cd "$repo"
    load_configuration "$repo" >/dev/null 2>&1

    # POSITIVE CONTROL: the fixture really did reach the loader and really did
    # assign the variable. Without this the refusal below could mean nothing
    # more than "the config file was never read".
    [ "${MANIFEST_CLI_AUTO_CONFIRM:-}" = "1" ]
    # ... and it did so through a config layer, not the process env.
    [ "${_MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV:-}" != "1" ]
    # ... and it did not somehow set the delegation flag on the way.
    [ "${_MANIFEST_CLI_DELEGATED_APPLY_CONSENT:-unset}" = "unset" ]

    run manifest_repo_scope_confirm_apply "$repo" "manifest ship -y" "false" < /dev/null

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Ambiguous apply target"
    refute grep -q "Auto-confirmed repository target" <<<"$output"
}

# -----------------------------------------------------------------------------
# Origin (A) is unchanged
# -----------------------------------------------------------------------------

@test "apply gate: process-start consent still authorizes, and still says so" {
    local repo
    repo="$(mk_ambiguous_repo)"
    grant_auto_confirm_from_process_env

    MANIFEST_CLI_PROJECT_ROOT="$repo" \
        run manifest_repo_scope_confirm_apply "$repo" "manifest ship -y" "false" < /dev/null

    [ "$status" -eq 0 ]
    # The two origins are reported distinctly: a fleet member's log must not
    # name an environment variable the operator never set in their shell.
    echo "$output" | grep -q "Auto-confirmed repository target (MANIFEST_CLI_AUTO_CONFIRM=1)"
    refute grep -q "delegated by fleet" <<<"$output"
}

@test "apply gate: no consent at all still refuses an ambiguous target" {
    local repo
    repo="$(mk_ambiguous_repo)"

    MANIFEST_CLI_PROJECT_ROOT="$repo" \
        run manifest_repo_scope_confirm_apply "$repo" "manifest ship -y" "false" < /dev/null

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Ambiguous apply target"
}

# -----------------------------------------------------------------------------
# Gate A stays narrower than Gate B
# -----------------------------------------------------------------------------

@test "global-config gate: the fleet delegation flag does NOT authorize an out-of-repo write" {
    # manifest-fleet.sh promises "fleet consent cannot authorize incidental
    # config migration". The delegation flag is scoped to the apply-target gate
    # only; the global config lives outside every repo in the fleet.
    local target="$SCRATCH/global.yaml"
    : > "$target"
    grant_fleet_delegated_consent

    run _confirm_global_config_write "modify" "$target" "fleet-delegated origin"

    [ "$status" -ne 0 ]
    [ "${MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED:-0}" != "1" ]
}

@test "global-config gate: POSITIVE CONTROL — process-start consent does authorize it" {
    # Proves the case above refuses because of the flag's provenance, not
    # because the fixture cannot reach an approving path at all.
    local target="$SCRATCH/global.yaml"
    : > "$target"
    grant_auto_confirm_from_process_env

    run _confirm_global_config_write "modify" "$target" "process-env origin"

    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Closure: the delegation flag is unreachable from config data
# -----------------------------------------------------------------------------
# This is the property the whole design rests on. A name that a config file
# could assign would make origin (C) a superset of origin (B), reopening §46
# through a different variable.

@test "closure: the delegation variable is not a mapped config key" {
    local hit="" control=""
    local path
    for path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
        case "${_MANIFEST_YAML_TO_ENV[$path]}" in
            _MANIFEST_CLI_DELEGATED_APPLY_CONSENT) hit="$path" ;;
            MANIFEST_CLI_AUTO_CONFIRM)             control="$path" ;;
        esac
    done

    # POSITIVE CONTROL: the loop can find a target when one exists.
    [ "$control" = "automation.auto_confirm" ]
    [ -z "$hit" ]
}

@test "closure: no mapped key targets a leading-underscore variable" {
    # The general form of the guarantee. load_yaml_to_env exports only names
    # taken from this table (never from the file's own key text), so as long as
    # no entry targets a leading-underscore internal name, no config file can
    # reach one -- this one included.
    local offenders=""
    local path
    for path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
        case "${_MANIFEST_YAML_TO_ENV[$path]}" in
            _*) offenders="${offenders}${path}=${_MANIFEST_YAML_TO_ENV[$path]} " ;;
        esac
    done

    # Non-empty table, so an empty offender list is not a vacuous pass.
    [ "${#_MANIFEST_YAML_TO_ENV[@]}" -gt 100 ]
    [ -z "$offenders" ]
}

@test "closure: a config file cannot set the delegation variable by any route" {
    # End-to-end rather than by inspection: every layer the loader reads, with
    # the name planted as a top-level key, as a nested key under a real section,
    # and as the VALUE of cloud.api_key_env (the one config key that names an
    # environment variable -- it only READS the named variable).
    local repo="$SCRATCH/planted"
    mkdir -p "$repo" "$HOME/.manifest-cli"

    cat > "$repo/manifest.config.yaml" <<'YAML'
schema_version: 2
automation:
  auto_confirm: 1
  _MANIFEST_CLI_DELEGATED_APPLY_CONSENT: 1
_MANIFEST_CLI_DELEGATED_APPLY_CONSENT: 1
cloud:
  api_key_env: _MANIFEST_CLI_DELEGATED_APPLY_CONSENT
YAML
    printf '_MANIFEST_CLI_DELEGATED_APPLY_CONSENT: 1\n' \
        > "$repo/manifest.config.local.yaml"
    printf 'schema_version: 2\n_MANIFEST_CLI_DELEGATED_APPLY_CONSENT: 1\n' \
        > "$HOME/.manifest-cli/manifest.config.global.yaml"
    MANIFEST_CLI_GLOBAL_CONFIG="$HOME/.manifest-cli/manifest.config.global.yaml"

    export MANIFEST_CLI_PROJECT_ROOT="$repo"
    cd "$repo"
    load_configuration "$repo" >/dev/null 2>&1

    # POSITIVE CONTROL: a MAPPED key from the same files did load, so the
    # loader ran and the negative result below is a verdict, not a no-op.
    [ "${MANIFEST_CLI_AUTO_CONFIRM:-}" = "1" ]
    [ "${MANIFEST_CLI_CLOUD_API_KEY_ENV:-}" = "_MANIFEST_CLI_DELEGATED_APPLY_CONSENT" ]

    # The unmapped name reached nothing.
    [ "${_MANIFEST_CLI_DELEGATED_APPLY_CONSENT:-unset}" = "unset" ]
    # ... and the api_key_env indirection READ it rather than writing it.
    [ -z "${MANIFEST_CLI_CLOUD_API_KEY:-}" ]
}

@test "closure: the process-env override capture cannot carry the delegation flag" {
    # The other generic-looking mechanism in manifest-config.sh. It admits a
    # name only when it is already in the process environment AND matches
    # MANIFEST_CLI_* AND is a mapped key; a leading-underscore, unmapped name
    # fails all three, so it can never be re-applied on top of a config layer.
    export _MANIFEST_CLI_DELEGATED_APPLY_CONSENT=1
    export MANIFEST_CLI_AUTO_CONFIRM=1
    _MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES=()
    _manifest_config_capture_process_env_overrides

    # POSITIVE CONTROL: the capture ran and did admit a mapped name.
    [ "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[MANIFEST_CLI_AUTO_CONFIRM]:-}" = "1" ]
    # The delegation flag was not admitted.
    [ -z "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[_MANIFEST_CLI_DELEGATED_APPLY_CONSENT]:-}" ]
}

# -----------------------------------------------------------------------------
# The fleet call sites actually deliver the delegation
# -----------------------------------------------------------------------------

@test "fleet: every delegated-apply consent export is paired with the delegation flag" {
    # The predicate is only half the fix. manifest-fleet.sh has exactly two
    # sites that hand a member's apply operator consent; each must set the
    # delegation flag before the delegated call, or the gate refuses the member
    # again. Comment lines are skipped so prose naming either variable cannot
    # satisfy the check.
    local verdict
    verdict="$(awk '
        /^[[:space:]]*#/ { next }
        /export MANIFEST_CLI_AUTO_CONFIRM=1/ { sites++; open=1; flag=0; next }
        open && /export _MANIFEST_CLI_DELEGATED_APPLY_CONSENT=1/ { flag=1; next }
        open && /manifest_ship_repo/ { if (flag) paired++; open=0; next }
        END { printf "sites=%d paired=%d", sites, paired }
    ' "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh")"

    [ "$verdict" = "sites=2 paired=2" ]
}

@test "e2e: a real 'ship fleet --local -y' carries consent to an ambiguous member" {
    # The behavioural counterpart of the structural case above, and the only
    # case here that proves the two halves of the fix meet: the real fleet_ship
    # path runs, the real delegation exports happen inside the real per-member
    # subshell, and the real apply gate decides. No process-start consent exists
    # anywhere in this process (setup() cleared it and re-took the snapshot), so
    # authorization can only have come from the delegation.
    #
    # Only the member's ship BODY is replaced -- everything above it in
    # fleet_ship, and the gate below it, is the shipping code.
    local work
    work="$(mk_fleet_with_ambiguous_member 1.2.3)"
    GATE_LOG="$SCRATCH/gate.log"
    export GATE_LOG
    : > "$GATE_LOG"

    manifest_ship_repo() {
        manifest_repo_scope_confirm_apply \
            "$MANIFEST_CLI_PROJECT_ROOT" "manifest ship repo -y" >> "$GATE_LOG" 2>&1
        echo "gate_rc=$?" >> "$GATE_LOG"
        return 0
    }

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship patch --local -y
    [ "$status" -eq 0 ]

    # The gate ran at all (guards against a vacuous pass where fleet skipped the
    # member and the assertions below matched an empty file).
    [ -s "$GATE_LOG" ]
    grep -q "gate_rc=0" "$GATE_LOG"
    grep -q "Auto-confirmed repository target (delegated by fleet -y)" "$GATE_LOG"
    refute grep -q "Ambiguous apply target" "$GATE_LOG"
    # And the member really was the ambiguous shape this case is about.
    run "$REAL_GIT" -C "$work/svc" remote get-url origin
    [ "$status" -ne 0 ]
}
