#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

write_fleet_config() {
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
YAML
}

write_selected_tsv() {
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svc	./svc	service	false			0.0.0
TSV
}

@test "init fleet --dry-run phase 1 previews TSV creation and writes nothing" {
    mkdir -p "$SCRATCH/work/svc" "$SCRATCH/work/plain"
    git -C "$SCRATCH/work/svc" init -q

    run_manifest init fleet --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest init fleet (Phase 1/2)"* ]]
    [[ "$output" == *"Inventory mode:"*"repo-depth defaults"* ]]
    [[ "$output" == *"Would list:"*"TSV rows"* ]]
    [[ "$output" == *"Would create:"*"manifest.fleet.tsv"* ]]
    [[ "$output" == *"No changes written"* ]]
    [ ! -f "$SCRATCH/work/manifest.fleet.tsv" ]
    [ ! -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
}

@test "init fleet --dry-run phase 2 previews selected rows and does not initialize dirs" {
    mkdir -p "$SCRATCH/work/svc"
    write_selected_tsv

    run_manifest init fleet --dry-run --name test-fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest init fleet (Phase 2/2)"* ]]
    [[ "$output" == *"Selected rows:"*"1"* ]]
    [[ "$output" == *"Would git init:"*"1"* ]]
    [[ "$output" == *"No changes written"* ]]
    [ ! -d "$SCRATCH/work/svc/.git" ]
    [ ! -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/work/manifest.config.local.yaml" ]
}

@test "quickstart fleet --dry-run previews config and inventory writes" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work/svc" init -q

    run_manifest quickstart fleet --dry-run --name test-fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest quickstart fleet"* ]]
    [[ "$output" == *"Would create:"*"manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"Would create:"*"manifest.fleet.tsv"* ]]
    [[ "$output" == *"Would list:"*"existing git repos"* ]]
    [[ "$output" == *"No changes written"* ]]
    [ ! -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/work/manifest.fleet.tsv" ]
}

@test "add fleet --dry-run previews YAML and leaves config unchanged" {
    mkdir -p "$SCRATCH/work/services/new-api"
    write_fleet_config
    before="$(cat "$SCRATCH/work/manifest.fleet.config.yaml")"

    run_manifest add fleet ./services/new-api --name new-api --type service --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest add fleet"* ]]
    [[ "$output" == *"Would update:"*"manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"new-api:"* ]]
    [[ "$output" == *"No changes written"* ]]
    [ "$(cat "$SCRATCH/work/manifest.fleet.config.yaml")" = "$before" ]
}

@test "docs fleet --dry-run previews generation and creates no docs" {
    mkdir -p "$SCRATCH/work/svc"
    write_fleet_config
    write_selected_tsv

    run_manifest docs fleet --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest docs fleet"* ]]
    [[ "$output" == *"Strategy:"*"both"* ]]
    [[ "$output" == *"Would write:"*"fleet-root docs"* ]]
    [[ "$output" == *"Would write:"*"per-service docs"* ]]
    [[ "$output" == *"No changes written"* ]]
    [ ! -d "$SCRATCH/work/docs" ]
    [ ! -d "$SCRATCH/work/svc/docs" ]
}
