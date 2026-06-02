#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Broad preview no-write coverage matrix (TRACKER §2.5).
#
# Every preview path — default, explicit --dry-run, and MANIFEST_CLI_AUTO_CONFIRM=1
# under default — must leave the sandbox byte-identical. Focused per-command
# tests already assert specific files were not created; this matrix is the
# smoke alarm that catches stray writes anywhere else in the sandbox.

load 'helpers/setup'
load 'helpers/preview_no_write'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_AUTO_CONFIRM
    unset _MANIFEST_GH_VALIDATED_AT MANIFEST_CLI_GH_VALIDATION_TTL
    unset GH_STUB_LOG GH_STUB_EXIT GH_STUB_AUTH_EXIT GH_STUB_STDOUT GH_STUB_STDERR
    # Apply-hook markers exported by warn_deprecated_configuration /
    # auto_migrate_user_global_configuration. Subprocess exports cannot leak
    # back into the test shell, but unsetting is defensive against any
    # future helper that runs config-load in the parent shell.
    unset _MANIFEST_CLI_DEPRECATION_WARNED _MANIFEST_CLI_MIGRATION_NOTIFIED
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# -----------------------------------------------------------------------------
# Fixture builders
# -----------------------------------------------------------------------------

setup_bare_repo() {
    git -C "$SCRATCH/work" init -q
    echo "1.2.3" > "$SCRATCH/work/VERSION"
}

setup_repo_with_remote() {
    setup_bare_repo
    git -C "$SCRATCH/work" remote add origin https://example.invalid/example.git
}

setup_fleet_minimal() {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
docs:
  strategy: "both"
  fleet_root:
    folder: "docs"
  per_service:
    folder: "docs"
services:
  svc:
    path: "./svc"
    type: "service"
    branch: "main"
YAML
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svc	./svc	service	false
TSV
    echo "1.2.3" > "$SCRATCH/work/svc/VERSION"
}

setup_fleet_plan_yaml() {
    cat > "$SCRATCH/work/manifest.fleet.plan.yaml" <<'YAML'
plan:
  schema_version: "1"
  root: "/tmp/example"
fleet:
  name: "test-fleet"
entries:
  - name: "plain"
    kind: "plain_dir"
    source_path: "plain"
    target_path: "plain"
    action: "init"
    type: "service"
    has_git: false
    remote_url: ""
    branch: "main"
    version: "0.0.0"
    submodule: false
YAML
    mkdir -p "$SCRATCH/work/plain"
}

setup_install_artifacts() {
    mkdir -p "$HOME/.manifest-cli" "$HOME/.local/bin"
    printf 'schema_version: 1\n' > "$HOME/.manifest-cli/manifest.config.global.yaml"
    printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/manifest"
    chmod +x "$HOME/.local/bin/manifest"
    printf 'export MANIFEST_CLI_TEST=1\n' > "$HOME/.zshrc"
}

# Wrap a command run with a snapshot before/after invariant assertion.
# Usage: assert_preview_clean "<command words...>"
# Sets `status` and `output` from `run`. Caller can add further assertions.
assert_preview_clean() {
    local before after
    before="$(preview_snapshot)"
    run_manifest "$@"
    after="$(preview_snapshot)"
    assert_no_writes "$before" "$after"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# init repo
# -----------------------------------------------------------------------------

@test "init repo: default preview makes no writes" {
    assert_preview_clean init repo
}

@test "init repo: --dry-run makes no writes" {
    assert_preview_clean init repo --dry-run
}

@test "init repo: AUTO_CONFIRM=1 default still previews and makes no writes" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean init repo
}

# -----------------------------------------------------------------------------
# init fleet (phase 1: TSV creation)
# -----------------------------------------------------------------------------

@test "init fleet phase 1: default preview makes no writes" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work/svc" init -q
    assert_preview_clean init fleet
}

@test "init fleet phase 1: --dry-run makes no writes" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work/svc" init -q
    assert_preview_clean init fleet --dry-run
}

@test "init fleet phase 1: AUTO_CONFIRM=1 default still previews and makes no writes" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work/svc" init -q
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean init fleet
}

# -----------------------------------------------------------------------------
# init fleet (phase 2: existing TSV, generates config)
# -----------------------------------------------------------------------------

@test "init fleet phase 2: default preview makes no writes" {
    mkdir -p "$SCRATCH/work/svc"
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svc	./svc	service	false
TSV
    assert_preview_clean init fleet --name test-fleet
}

@test "init fleet phase 2: --dry-run makes no writes" {
    mkdir -p "$SCRATCH/work/svc"
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svc	./svc	service	false
TSV
    assert_preview_clean init fleet --dry-run --name test-fleet
}

@test "init fleet phase 2: AUTO_CONFIRM=1 default still previews and makes no writes" {
    mkdir -p "$SCRATCH/work/svc"
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svc	./svc	service	false
TSV
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean init fleet --name test-fleet
}

# -----------------------------------------------------------------------------
# prep repo
# -----------------------------------------------------------------------------

@test "prep repo: default preview makes no writes" {
    setup_repo_with_remote
    assert_preview_clean prep repo
}

@test "prep repo: --dry-run makes no writes" {
    setup_repo_with_remote
    assert_preview_clean prep repo --dry-run
}

@test "prep repo: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_remote
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean prep repo
}

# -----------------------------------------------------------------------------
# prep fleet
# -----------------------------------------------------------------------------

@test "prep fleet: default preview makes no writes" {
    setup_fleet_minimal
    assert_preview_clean prep fleet
}

@test "prep fleet: --dry-run makes no writes" {
    setup_fleet_minimal
    assert_preview_clean prep fleet --dry-run
}

@test "prep fleet: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_fleet_minimal
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean prep fleet
}

# -----------------------------------------------------------------------------
# refresh repo
# -----------------------------------------------------------------------------

@test "refresh repo: default preview makes no writes" {
    setup_bare_repo
    assert_preview_clean refresh repo
}

@test "refresh repo: --dry-run makes no writes" {
    setup_bare_repo
    assert_preview_clean refresh repo --dry-run
}

@test "refresh repo: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_bare_repo
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean refresh repo
}

# -----------------------------------------------------------------------------
# refresh fleet
# -----------------------------------------------------------------------------

@test "refresh fleet: default preview makes no writes" {
    setup_fleet_minimal
    assert_preview_clean refresh fleet
}

@test "refresh fleet: --dry-run makes no writes" {
    setup_fleet_minimal
    assert_preview_clean refresh fleet --dry-run
}

@test "refresh fleet: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_fleet_minimal
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean refresh fleet
}

# -----------------------------------------------------------------------------
# ship repo (patch)
# -----------------------------------------------------------------------------

@test "ship repo patch: default preview makes no writes" {
    setup_repo_with_remote
    assert_preview_clean ship repo patch
}

@test "ship repo patch: --dry-run makes no writes" {
    setup_repo_with_remote
    assert_preview_clean ship repo patch --dry-run
}

@test "ship repo patch: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_remote
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean ship repo patch
}

# -----------------------------------------------------------------------------
# ship repo --local
# -----------------------------------------------------------------------------

@test "ship repo --local patch: default preview makes no writes" {
    setup_repo_with_remote
    assert_preview_clean ship repo patch --local
}

@test "ship repo --local patch: --dry-run makes no writes" {
    setup_repo_with_remote
    assert_preview_clean ship repo patch --local --dry-run
}

@test "ship repo --local patch: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_remote
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean ship repo patch --local
}

# -----------------------------------------------------------------------------
# ship fleet (patch)
# -----------------------------------------------------------------------------

@test "ship fleet patch: default preview makes no writes" {
    setup_fleet_minimal
    assert_preview_clean ship fleet patch
}

@test "ship fleet patch: --dry-run makes no writes" {
    setup_fleet_minimal
    assert_preview_clean ship fleet patch --dry-run
}

@test "ship fleet patch: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_fleet_minimal
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean ship fleet patch
}

# -----------------------------------------------------------------------------
# ship fleet --local
# -----------------------------------------------------------------------------

@test "ship fleet --local patch: default preview makes no writes" {
    setup_fleet_minimal
    assert_preview_clean ship fleet patch --local
}

@test "ship fleet --local patch: --dry-run makes no writes" {
    setup_fleet_minimal
    assert_preview_clean ship fleet patch --local --dry-run
}

@test "ship fleet --local patch: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_fleet_minimal
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean ship fleet patch --local
}

# -----------------------------------------------------------------------------
# pr create / ready / merge / update
#
# Each PR test uses the gh stub so we can also assert no gh subprocess was
# invoked (network silence is part of the preview contract).
# -----------------------------------------------------------------------------

@test "pr create: default preview makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr create --draft --base main
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr create: --dry-run makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr create --draft --base main --dry-run
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr create: AUTO_CONFIRM=1 default still previews, no writes, no gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    export MANIFEST_CLI_AUTO_CONFIRM=1
    setup_bare_repo
    assert_preview_clean pr create --draft --base main
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr ready: default preview makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr ready 123
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr ready: --dry-run makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr ready 123 --dry-run
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr ready: AUTO_CONFIRM=1 default still previews, no writes, no gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    export MANIFEST_CLI_AUTO_CONFIRM=1
    setup_bare_repo
    assert_preview_clean pr ready 123
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr merge: default preview makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr merge 123 --auto
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr merge: --dry-run makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr merge 123 --auto --dry-run
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr merge: AUTO_CONFIRM=1 default still previews, no writes, no gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    export MANIFEST_CLI_AUTO_CONFIRM=1
    setup_bare_repo
    assert_preview_clean pr merge 123 --auto
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr update: default preview makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr update 123 --rebase
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr update: --dry-run makes no writes and does not call gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    setup_bare_repo
    assert_preview_clean pr update 123 --rebase --dry-run
    [ ! -s "$GH_STUB_LOG" ]
}

@test "pr update: AUTO_CONFIRM=1 default still previews, no writes, no gh" {
    gh_stub_install
    export GH_STUB_AUTH_EXIT=99 GH_STUB_EXIT=99
    export MANIFEST_CLI_AUTO_CONFIRM=1
    setup_bare_repo
    assert_preview_clean pr update 123 --rebase
    [ ! -s "$GH_STUB_LOG" ]
}

# -----------------------------------------------------------------------------
# config set / unset
# -----------------------------------------------------------------------------

@test "config set: default preview makes no writes" {
    assert_preview_clean config set --layer project version.format semver
}

@test "config set: --dry-run makes no writes" {
    assert_preview_clean config set --layer project version.format semver --dry-run
}

@test "config set: AUTO_CONFIRM=1 default still previews and makes no writes" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean config set --layer project version.format semver
}

@test "config unset: default preview makes no writes" {
    assert_preview_clean config unset --layer project version.format
}

@test "config unset: --dry-run makes no writes" {
    assert_preview_clean config unset --layer project version.format --dry-run
}

@test "config unset: AUTO_CONFIRM=1 default still previews and makes no writes" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean config unset --layer project version.format
}

# -----------------------------------------------------------------------------
# uninstall
# -----------------------------------------------------------------------------

@test "uninstall: default preview makes no writes" {
    setup_install_artifacts
    assert_preview_clean uninstall
}

@test "uninstall: --dry-run makes no writes" {
    setup_install_artifacts
    assert_preview_clean uninstall --dry-run
}

@test "uninstall: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_install_artifacts
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean uninstall
}

# -----------------------------------------------------------------------------
# reinstall
# -----------------------------------------------------------------------------

@test "reinstall: default preview makes no writes" {
    setup_install_artifacts
    assert_preview_clean reinstall
}

@test "reinstall: --dry-run makes no writes" {
    setup_install_artifacts
    assert_preview_clean reinstall --dry-run
}

@test "reinstall: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_install_artifacts
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean reinstall
}

# -----------------------------------------------------------------------------
# plan fleet  (apply contract uses --apply/--do, not -y; default is preview)
# -----------------------------------------------------------------------------

@test "plan fleet: default preview makes no writes" {
    mkdir -p "$SCRATCH/work/services/api"
    git -C "$SCRATCH/work/services/api" init -q
    assert_preview_clean plan fleet
}

@test "plan fleet: AUTO_CONFIRM=1 default still previews and makes no writes" {
    mkdir -p "$SCRATCH/work/services/api"
    git -C "$SCRATCH/work/services/api" init -q
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean plan fleet
}

# -----------------------------------------------------------------------------
# reconcile fleet  (apply contract uses --apply/--do, not -y; default is preview)
# -----------------------------------------------------------------------------

@test "reconcile fleet: default preview makes no writes" {
    setup_fleet_plan_yaml
    assert_preview_clean reconcile fleet
}

@test "reconcile fleet: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_fleet_plan_yaml
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean reconcile fleet
}
