#!/usr/bin/env bats

# Fleet-root coordination repo: local git root + allowlist .gitignore.
# Covers create_fleet_gitignore() (the allowlist generator + no-clobber policy)
# and the init-fleet Phase 2 apply/preview wiring.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-discovery.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"

    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH-home"
    mkdir -p "$HOME"
    export HOME SCRATCH
    cd "$SCRATCH"
}

teardown() {
    rm -rf "$SCRATCH" "$SCRATCH-home"
}

run_manifest() {
    run bash -c '
        export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
        source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-execution-policy.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
        source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
        cd "$SCRATCH"
        manifest_init_fleet "$@"
    ' bash "$@"
}

@test "create_fleet_gitignore writes an allowlist on a fresh root" {
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = ".gitignore" ]
    [ -f "$SCRATCH/.gitignore" ]
    grep -q '^/\*$' "$SCRATCH/.gitignore"
    grep -q '^!/manifest.fleet.config.yaml$' "$SCRATCH/.gitignore"
    grep -q '^!/manifest.fleet.tsv$' "$SCRATCH/.gitignore"
    grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
    # host-local config is deliberately NOT tracked
    ! grep -q 'manifest.config.local.yaml' "$SCRATCH/.gitignore"
}

@test "create_fleet_gitignore preserves a populated .gitignore (no clobber)" {
    printf 'node_modules/\n*.log\n' > "$SCRATCH/.gitignore"
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = ".gitignore.manifest" ]
    grep -q '^node_modules/$' "$SCRATCH/.gitignore"
    ! grep -q '^/\*$' "$SCRATCH/.gitignore"
    [ -f "$SCRATCH/.gitignore.manifest" ]
    grep -q '^/\*$' "$SCRATCH/.gitignore.manifest"
}

@test "allowlist tracks only coordination files at the git level" {
    create_fleet_gitignore "$SCRATCH" >/dev/null
    git -C "$SCRATCH" init -q
    mkdir -p "$SCRATCH/apps/member" "$SCRATCH/secure"
    echo x > "$SCRATCH/apps/member/code.cs"
    echo s > "$SCRATCH/secure/appsettings.production.json"
    echo c > "$SCRATCH/manifest.fleet.config.yaml"
    echo t > "$SCRATCH/manifest.fleet.tsv"
    echo l > "$SCRATCH/manifest.config.local.yaml"
    git -C "$SCRATCH" add -A
    run git -C "$SCRATCH" ls-files
    [[ "$output" == *".gitignore"* ]]
    [[ "$output" == *"manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"manifest.fleet.tsv"* ]]
    [[ "$output" != *"secure/"* ]]
    [[ "$output" != *"apps/member"* ]]
    [[ "$output" != *"manifest.config.local.yaml"* ]]
}

@test "init fleet phase 2 git-inits the fleet root (local-only) + writes the allowlist" {
    mkdir -p "$SCRATCH/apps/web" "$SCRATCH/services/api"
    run_manifest -y            # Phase 1: generate TSV
    [ "$status" -eq 0 ]
    # Mark the TSV as edited so Phase 2 applies (no DEFAULT-SELECT-HASH => not stale).
    grep -v 'DEFAULT-SELECT-HASH' "$SCRATCH/manifest.fleet.tsv" > "$SCRATCH/tsv.tmp"
    mv "$SCRATCH/tsv.tmp" "$SCRATCH/manifest.fleet.tsv"
    run_manifest -y            # Phase 2: apply
    [ "$status" -eq 0 ]
    [ -d "$SCRATCH/.git" ]
    run git -C "$SCRATCH" remote
    [ -z "$output" ]           # local-only: no remote
    [ -f "$SCRATCH/.gitignore" ]
    grep -q '^/\*$' "$SCRATCH/.gitignore"
    run git -C "$SCRATCH" check-ignore apps/web
    [ "$status" -eq 0 ]        # member dir ignored by the allowlist
}

@test "init fleet phase 2 dry-run previews fleet-root git + allowlist, writes nothing" {
    mkdir -p "$SCRATCH/apps/web"
    run_manifest -y            # Phase 1
    [ "$status" -eq 0 ]
    run_manifest --dry-run     # Phase 2 preview
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet-root git repo"* ]]
    [[ "$output" == *".gitignore"* ]]
    [ ! -d "$SCRATCH/.git" ]   # preview wrote nothing
}

@test "create_fleet_gitignore is idempotent — re-run does not spawn .gitignore.manifest" {
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = ".gitignore" ]
    run create_fleet_gitignore "$SCRATCH"   # allowlist already present
    [ "$status" -eq 0 ]
    [ -z "$output" ]                        # clean no-op
    [ ! -f "$SCRATCH/.gitignore.manifest" ] # no redundant reference file
}

@test "_fleet_dir_is_own_git_repo: own repo yes, nested-in-parent no" {
    git init -q "$SCRATCH"
    mkdir -p "$SCRATCH/child"
    run _fleet_dir_is_own_git_repo "$SCRATCH"
    [ "$status" -eq 0 ]                     # SCRATCH is its own repo
    run _fleet_dir_is_own_git_repo "$SCRATCH/child"
    [ "$status" -ne 0 ]                     # child is only nested in the parent
    run git -C "$SCRATCH/child" rev-parse --is-inside-work-tree
    [ "$output" = "true" ]                  # ...which the old --is-inside-work-tree check wrongly passed
}
