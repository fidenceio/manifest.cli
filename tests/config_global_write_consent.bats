#!/usr/bin/env bats

# §46 — a repo's committed config must not authorize a write to the user's
# GLOBAL config.
#
# `automation.auto_confirm` is a mapped key (manifest-yaml.sh), so any config
# file the CLI loads can assign MANIFEST_CLI_AUTO_CONFIRM. Layer 2 is the repo's
# own committed manifest.config.yaml and Layer 1.5 is a fleet root's, and
# auto_migrate_user_global_configuration runs AFTER every layer has loaded. So
# before the fix, three lines of YAML in a cloned repo made
# `manifest config get project.name` rewrite
# $HOME/.manifest-cli/manifest.config.global.yaml, leave a .bak.<stamp> beside
# it and drop a config-migration.last marker — no -y, no flag, no prompt.
#
# Every case here drives the REAL entrypoint (scripts/manifest-cli.sh; there is
# no bin/manifest — invoking one would silently no-op) against a sandboxed HOME.
#
# READ THE POSITIVE CONTROL FIRST. "No write observed" is worthless on its own:
# the migration only fires when the global config exists, carries a legacy or
# missing key, and is outside the 1440-minute cooldown. The first test proves
# this fixture satisfies all three and DOES rewrite the global config when the
# operator supplies MANIFEST_CLI_AUTO_CONFIRM=1 in the process environment. It
# must pass both before and after the fix; if it ever goes green-by-silence, the
# rest of this file is measuring nothing.
#
# The drift-WARNING assertions are the second control: a "fix" that simply
# disabled auto-migration outright would satisfy every byte-identical assertion
# below while destroying the notice the user is supposed to get.
#
# bats file_tags=smoke

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    # HOME is sandboxed for every case in this file. Nothing here may reach the
    # developer's real ~/.manifest-cli.
    SANDBOX_HOME="$SCRATCH/home"
    mkdir -p "$SANDBOX_HOME/.manifest-cli"
    GLOBAL_CFG="$SANDBOX_HOME/.manifest-cli/manifest.config.global.yaml"
    ENTRY="$TEST_REPO_ROOT/scripts/manifest-cli.sh"
    [ -f "$ENTRY" ]

    # Drifted on purpose: time.server1 is a legacy value and time.cache_ttl /
    # config.schema_version are absent, so _manifest_config_detect_issues emits
    # both a "legacy" and a "missing" row — the two actionable classes. No
    # config-migration.last exists, so the 1440-minute cooldown is satisfied.
    cat > "$GLOBAL_CFG" <<'YAML'
project:
  name: "Sandbox Global"
  organization: "Sandbox Org"
time:
  server1: "time.apple.com"
git:
  default_branch: "main"
YAML
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# A minimal git repo whose committed manifest.config.yaml is $2.
mk_repo() {
    local dir="$1" config_body="$2"
    mkdir -p "$dir"
    git -c init.defaultBranch=main init -q "$dir"
    git -C "$dir" config user.email "test@manifest.invalid"
    git -C "$dir" config user.name "Manifest Test"
    echo "1.0.0" > "$dir/VERSION"
    printf '%s' "$config_body" > "$dir/manifest.config.yaml"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "init"
}

# Drive the real entrypoint with the sandboxed HOME. Extra VAR=VALUE arguments
# are passed to `env` and so land in the PROCESS ENVIRONMENT of the CLI — the
# only place consent is allowed to come from.
run_cli() {
    local repo="$1"; shift
    cd "$repo"
    # `-u` MUST precede the first VAR=VALUE: env stops parsing options at the
    # first assignment, so `env HOME=... -u FOO cmd` tries to execute `-u` and
    # exits 127. That failure looked exactly like "the CLI made no write".
    run env -u MANIFEST_CLI_AUTO_CONFIRM HOME="$SANDBOX_HOME" "$@" \
        "$ENTRY" config get project.name
}

count_backups() {
    find "$SANDBOX_HOME" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' '
}

# `grep -c` prints 0 AND exits 1 on no match, which errexit would turn into a
# test abort rather than a readable assertion. Count without a pipeline instead.
output_has() {
    case "$output" in
        *"$1"*) return 0 ;;
        *) printf 'expected output to contain: %s\n' "$1" >&2; return 1 ;;
    esac
}

output_lacks() {
    case "$output" in
        *"$1"*) printf 'expected output NOT to contain: %s\n' "$1" >&2; return 1 ;;
        *) return 0 ;;
    esac
}

# The full "nothing outside the repo was touched" assertion: the global config
# is byte-identical, no timestamped backup was created, and no migration marker
# appeared anywhere under the sandboxed HOME.
assert_global_config_untouched() {
    local before="$1"
    [ "$(sha256_of "$GLOBAL_CFG")" = "$before" ]
    [ "$(count_backups)" -eq 0 ]
    refute test -f "$SANDBOX_HOME/.manifest-cli/config-migration.last"
}

# A config-file `auto_confirm` must land the user on exactly the path they would
# be on with no consent anywhere: the drift NOTICE. Not silence (that would mean
# auto-migration was simply disabled), not a refusal error (that would mean only
# the gate was fixed and the warn-only branch still trusted the config value),
# and not an auto-confirm announcement.
assert_warn_only_path() {
    output_has "Configuration drift detected"
    output_lacks "Refusing to modify global config"
    output_lacks "Auto-confirming modify"
    output_lacks "Applied safe configuration migrations"
}

# -----------------------------------------------------------------------------
# POSITIVE CONTROL — must pass before AND after the fix.
# -----------------------------------------------------------------------------

@test "§46 positive control: MANIFEST_CLI_AUTO_CONFIRM=1 in the process env DOES migrate the global config" {
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli "$SCRATCH/repo" MANIFEST_CLI_AUTO_CONFIRM=1
    [ "$status" -eq 0 ]

    # The fixture really does reach the migration path.
    refute test "$(sha256_of "$GLOBAL_CFG")" = "$before"
    [ "$(count_backups)" -eq 1 ]
    [ -f "$SANDBOX_HOME/.manifest-cli/config-migration.last" ]
    output_has "Applied safe configuration migrations"
}

# -----------------------------------------------------------------------------
# THE DEFECT — a config file must not supply the consent.
# -----------------------------------------------------------------------------

@test "§46: repo manifest.config.yaml auto_confirm: true does NOT authorize a global config write" {
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\nautomation:\n  auto_confirm: true\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    assert_global_config_untouched "$before"
    assert_warn_only_path
}

@test "§46: repo auto_confirm: 1 does NOT authorize a global config write" {
    # The spelling that satisfies the literal-\"1\" predicate used by
    # manifest_repo_scope_confirm_apply, so this case is not covered by the
    # `true` one above.
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\nautomation:\n  auto_confirm: 1\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    assert_global_config_untouched "$before"
    assert_warn_only_path
}

@test "§46: repo auto_confirm: yes does NOT authorize a global config write" {
    # The spelling that satisfies is_truthy but not the literal-\"1\" predicate.
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\nautomation:\n  auto_confirm: "yes"\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    assert_global_config_untouched "$before"
    assert_warn_only_path
}

@test "§46: a FLEET ROOT config (Layer 1.5) does NOT authorize a global config write for a nested member" {
    # Layer 1.5 is inherited from an ancestor directory the member repo does not
    # own, so it is the same hazard one level further out.
    local fleet="$SCRATCH/fleet"
    mkdir -p "$fleet"
    printf 'fleet:\n  name: "sandbox-fleet"\n' > "$fleet/manifest.fleet.config.yaml"
    # `1`, not `true`, on purpose: `true` is refused by the collapsed literal-"1"
    # predicate on its own, so it would pass this test even if the ORDERING fix
    # were reverted. `1` isolates the ordering.
    printf 'automation:\n  auto_confirm: 1\n' > "$fleet/manifest.config.yaml"
    mk_repo "$fleet/member" $'project:\n  name: "Repo Under Test"\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli "$fleet/member"
    [ "$status" -eq 0 ]
    output_has "Inheriting fleet configuration from"   # the layer really loaded
    assert_global_config_untouched "$before"
    assert_warn_only_path
}

# -----------------------------------------------------------------------------
# The drift WARNING must survive — otherwise "disable auto-migration entirely"
# would pass every assertion above.
# -----------------------------------------------------------------------------

@test "§46: the drift warning still prints when no consent is present at all" {
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    output_has "Configuration drift detected"
    output_has "manifest config doctor"
    assert_global_config_untouched "$before"
}

@test "§46: a config-file auto_confirm leaves the user on the drift-warning path, not an error path" {
    # Guards the half of the fix that is easy to omit. If only
    # _confirm_global_config_write were switched to the process-env snapshot,
    # the warn-only branch in auto_migrate_user_global_configuration would still
    # read the config-supplied value, skip the notice, and hand the user
    # "Refusing to modify global config without confirmation" instead — a worse
    # message for a condition they did not cause.
    #
    # `1` again: it is the spelling that survives the literal-"1" predicate, so
    # this case fails on BOTH a reverted ordering fix and a reverted warn-branch
    # predicate. `true` would only catch the second.
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\nautomation:\n  auto_confirm: 1\n'

    run_cli "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    output_has "Configuration drift detected"
    output_lacks "Refusing to modify global config"
    output_lacks "Auto-confirming modify"
}

# -----------------------------------------------------------------------------
# Precedence: the operator's environment still wins over a config file that
# tries to revoke it. The env path is a deliberate operator choice and must keep
# working in both directions.
# -----------------------------------------------------------------------------

@test "§46: process-env consent survives a repo config that sets auto_confirm: false" {
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\nautomation:\n  auto_confirm: false\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli "$SCRATCH/repo" MANIFEST_CLI_AUTO_CONFIRM=1
    [ "$status" -eq 0 ]
    refute test "$(sha256_of "$GLOBAL_CFG")" = "$before"
    output_has "Applied safe configuration migrations"
}

# -----------------------------------------------------------------------------
# The second route through the same gate. §46 was filed on auto-migration only,
# where the content written is CLI-chosen; `config set --layer global` writes a
# USER-chosen key and value to the same file through the same
# _confirm_global_config_write. Measured on unfixed code: a repo config carrying
# `automation.auto_confirm: 1` made this succeed silently, so the repo's data was
# removing the last confirmation on an out-of-repo write. Not content injection
# (the value is the operator's own argument) — a suppressed confirmation.
# -----------------------------------------------------------------------------

run_cli_set_global() {
    local repo="$1"; shift
    cd "$repo"
    run env -u MANIFEST_CLI_AUTO_CONFIRM HOME="$SANDBOX_HOME" "$@" \
        "$ENTRY" config set --layer global brew.tap_repo example/homebrew-tap -y
}

@test "§46: a repo config cannot suppress the confirmation on 'config set --layer global'" {
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\nautomation:\n  auto_confirm: 1\n'
    local before; before="$(sha256_of "$GLOBAL_CFG")"

    run_cli_set_global "$SCRATCH/repo"
    [ "$status" -ne 0 ]
    output_has "Refusing to modify global config without confirmation"
    [ "$(sha256_of "$GLOBAL_CFG")" = "$before" ]
}

@test "§46 positive control: MANIFEST_CLI_AUTO_CONFIRM=1 in the process env DOES let 'config set --layer global' write" {
    mk_repo "$SCRATCH/repo" $'project:\n  name: "Repo Under Test"\n'

    run_cli_set_global "$SCRATCH/repo" MANIFEST_CLI_AUTO_CONFIRM=1
    [ "$status" -eq 0 ]
    output_has "Auto-confirming modify"
    [ "$(yq e '.brew.tap_repo' "$GLOBAL_CFG")" = "example/homebrew-tap" ]
}

# --- the second half of §46: the ambiguous-apply gate ------------------------
# manifest_repo_scope_confirm_apply is the OTHER reader of this consent, and it
# lives in manifest-shared-utils.sh rather than the config module. It refuses an
# ambiguous apply target -- a detached HEAD, or no origin remote -- unless
# consent is explicit. Reading the variable live let a cloned repo's committed
# `automation.auto_confirm: 1` take that branch, which is the half of §46 that
# widens where §44 fires: `ship -y` then proceeds in states the CLI exists to
# refuse. Only the literal "1" ever reached this gate, so `true`/`yes` are not
# regression cases here.
#
# Driven at function level: the ambiguity is a property of the repo, and going
# through a full ship would drag in the release gate and a remote.
# Consent is passed as TEST_GRANT_AUTO_CONFIRM, not MANIFEST_CLI_AUTO_CONFIRM,
# because helpers/setup.bash:12 unsets the real variable for hermeticity -- and
# it does so BEFORE load_modules sources the config module, so a value supplied
# the obvious way is erased before the snapshot is ever taken. That is a harness
# property, not the product: it made the positive control below fail while the
# defect test passed for the wrong reason (an empty snapshot authorizes nothing,
# so it "refused" without the fix doing any work). Re-capturing explicitly is
# what grant_auto_confirm_from_process_env does in safety_gate.bats.
run_ambiguous_apply() {
    local repo="$1" grant="${2:-0}"
    run env -u MANIFEST_CLI_AUTO_CONFIRM HOME="$SANDBOX_HOME" \
        TEST_GRANT_AUTO_CONFIRM="$grant" bash -c '
        source "$1/tests/helpers/setup.bash"
        load_modules "core/manifest-config.sh" "core/manifest-shared-utils.sh"
        # Operator consent: set and snapshot BEFORE any config layer loads,
        # which is exactly what the process-environment route does in production.
        if [ "${TEST_GRANT_AUTO_CONFIRM:-0}" = "1" ]; then
            export MANIFEST_CLI_AUTO_CONFIRM=1
            _manifest_config_capture_auto_confirm_env
        fi
        cd "$2" || exit 1
        export MANIFEST_CLI_PROJECT_ROOT="$2"
        load_configuration "$2" "false" >/dev/null 2>&1 || true
        manifest_repo_scope_confirm_apply "$2" "manifest ship -y" </dev/null
    ' _ "$TEST_REPO_ROOT" "$repo"
}

@test "§46: a repo config auto_confirm does not auto-confirm an ambiguous apply target" {
    # No origin remote == ambiguous. mk_repo adds no remote.
    mk_repo "$SCRATCH/ambig" $'automation:\n  auto_confirm: 1\n'

    run_ambiguous_apply "$SCRATCH/ambig"
    output_lacks "Auto-confirmed repository target"
}

@test "§46 positive control: process-env consent DOES auto-confirm an ambiguous target" {
    mk_repo "$SCRATCH/ambig2" $'project:\n  name: "Ambiguous"\n'

    run_ambiguous_apply "$SCRATCH/ambig2" 1
    output_has "Auto-confirmed repository target"
}
