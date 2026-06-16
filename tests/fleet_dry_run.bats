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
true	svc	./svc	service	false		
TSV
}

write_root_fleet_config() {
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  rootworkspace:
    path: "."
    type: "infrastructure"
    branch: "main"
  svc:
    path: "./svc"
    type: "service"
    branch: "main"
YAML
}

write_root_selected_tsv() {
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	rootworkspace	.	infrastructure	true		
true	svc	./svc	service	true		
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
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
    [[ "$output" == *"manifest init fleet -y"* ]]
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
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
    [[ "$output" == *"manifest init fleet --name test-fleet -y"* ]]
    [ ! -d "$SCRATCH/work/svc/.git" ]
    [ ! -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/work/manifest.config.local.yaml" ]
}

@test "init fleet --dry-run phase 2 on an initialized fleet previews preserve + backfill, writes nothing" {
    mkdir -p "$SCRATCH/work/svc"
    write_selected_tsv
    write_fleet_config
    before="$(cat "$SCRATCH/work/manifest.fleet.config.yaml")"

    run_manifest init fleet --dry-run --name test-fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest init fleet (Phase 2/2)"* ]]
    # Curated config is preserved, not overwritten, and the preview says so.
    [[ "$output" == *"Would preserve:"*"manifest.fleet.config.yaml"* ]]
    [[ "$output" != *"Would overwrite:"* ]]
    # Preview names the real apply work: no-clobber member scaffolding.
    [[ "$output" == *"Would scaffold:"*"VERSION/README/CHANGELOG"* ]]
    # Read-only: nothing changes on disk.
    [ "$(cat "$SCRATCH/work/manifest.fleet.config.yaml")" = "$before" ]
    [ ! -f "$SCRATCH/work/svc/VERSION" ]
}

@test "init fleet --dry-run phase 2 with --force previews config overwrite" {
    mkdir -p "$SCRATCH/work/svc"
    write_selected_tsv
    write_fleet_config

    run_manifest init fleet --dry-run --force --name test-fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"Would overwrite:"*"manifest.fleet.config.yaml"* ]]
    [[ "$output" != *"Would preserve:"* ]]
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
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
    [[ "$output" == *"manifest add fleet ./services/new-api -y"* ]]
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
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
    [[ "$output" == *"manifest docs fleet -y"* ]]
    [ ! -d "$SCRATCH/work/docs" ]
    [ ! -d "$SCRATCH/work/svc/docs" ]
}

@test "prep fleet --dry-run lists sync plan and exits successfully" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    write_fleet_config
    write_selected_tsv

    run_manifest prep fleet --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST FLEET SYNC (DRY RUN)"* ]]
    [[ "$output" == *"svc: would pull --rebase"* ]]
    [[ "$output" == *"Plan:"*"1 pull"* ]]
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
    [[ "$output" == *"manifest prep fleet --parallel -y"* ]]
}

@test "prep fleet defaults to preview" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    write_fleet_config
    write_selected_tsv

    run_manifest prep fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST FLEET SYNC (DRY RUN)"* ]]
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
    [[ "$output" == *"manifest prep fleet --parallel -y"* ]]
}

@test "ship fleet defaults to preview and does not call PR dispatch" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    echo "1.2.3" > "$SCRATCH/work/svc/VERSION"
    write_fleet_config
    write_selected_tsv
    cat >> "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
  svc:
    path: "./svc"
    type: "service"
    branch: "main"
YAML

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship fleet preview"* ]]
    [[ "$output" == *"Fleet scope"* ]]
    [[ "$output" == *"Fleet:"*"test-fleet"* ]]
    [[ "$output" == *"Root:"*"$SCRATCH/work"* ]]
    [[ "$output" == *"Config:"*"$SCRATCH/work/manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"Scope:"*"fleet"* ]]
    [[ "$output" == *"Mutation:"*"fleet repositories listed below"* ]]
    [[ "$output" == *"Services:"*"1"* ]]
    [[ "$output" == *"Fleet ship plan"* ]]
    [[ "$output" == *"Included repositories"* ]]
    [[ "$output" == *"Service"*"Type"*"Branch"*"Effect"*"Decision"*"Path / reason"* ]]
    [[ "$output" == *"svc"*"service"*"release"*"would ship"*"${SCRATCH}/work/svc"* ]]
    [[ "$output" == *"would ship"* ]]
    [[ "$output" != *"PR feature requires Manifest Cloud"* ]]
    [ "$(cat "$SCRATCH/work/svc/VERSION")" = "1.2.3" ]
}

@test "refresh fleet --dry-run does not rewrite manifest.fleet.tsv" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    write_fleet_config
    write_selected_tsv
    before="$(cat "$SCRATCH/work/manifest.fleet.tsv")"

    run_manifest refresh fleet --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST FLEET UPDATE (dry-run)"* ]]
    [[ "$output" == *"Would refresh manifest.fleet.tsv"* ]]
    [[ "$output" == *"Dry run complete"* ]]
    [ "$(cat "$SCRATCH/work/manifest.fleet.tsv")" = "$before" ]
    [ ! -f "$SCRATCH/work/manifest.fleet.tsv.tmp" ]
}

@test "refresh fleet --dry-run treats configured fleet root as discovered" {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    write_root_fleet_config
    write_root_selected_tsv
    before="$(cat "$SCRATCH/work/manifest.fleet.tsv")"

    run_manifest refresh fleet --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST FLEET UPDATE (dry-run)"* ]]
    [[ "$output" != *"Missing repositories"* ]]
    [[ "$output" == *"- Missing:   0"* ]]
    [[ "$output" == *"Would refresh manifest.fleet.tsv"* ]]
    [ "$(cat "$SCRATCH/work/manifest.fleet.tsv")" = "$before" ]
}

@test "refresh fleet writes TSV from git repos, not every subdirectory" {
    mkdir -p "$SCRATCH/work/svc/src"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    write_root_fleet_config
    write_root_selected_tsv

    run_manifest refresh fleet -y

    [ "$status" -eq 0 ]
    grep -q $'^true\trootworkspace\t.\tinfrastructure\ttrue' "$SCRATCH/work/manifest.fleet.tsv"
    grep -q $'^true\tsvc\tsvc\tservice\ttrue' "$SCRATCH/work/manifest.fleet.tsv"
    ! grep -q $'\tsvc/src\t' "$SCRATCH/work/manifest.fleet.tsv"
}

@test "ship fleet preview Service column preserves dots via path basename" {
    mkdir -p "$SCRATCH/work/fidenceio.manifest.cli" "$SCRATCH/work/fidenceio.homebrew.tap/Formula"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/fidenceio.manifest.cli" init -q
    git -C "$SCRATCH/work/fidenceio.homebrew.tap" init -q
    echo "1.0.0" > "$SCRATCH/work/fidenceio.manifest.cli/VERSION"
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  rootworkspace:
    path: "."
    type: "infrastructure"
    branch: "main"
  fidenceiomanifestcli:
    path: "./fidenceio.manifest.cli"
    type: "tool"
    branch: "main"
  fidenceiohomebrewtap:
    path: "./fidenceio.homebrew.tap"
    type: "infrastructure"
    branch: "main"
YAML
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	rootworkspace	.	infrastructure	true
true	fidenceiomanifestcli	./fidenceio.manifest.cli	tool	true
true	fidenceiohomebrewtap	./fidenceio.homebrew.tap	infrastructure	true
TSV

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Fleet ship plan"* ]]
    # Path-derived display name: dots preserved for non-root entries.
    [[ "$output" == *"fidenceio.manifest.cli"* ]]
    [[ "$output" == *"fidenceio.homebrew.tap"* ]]
    # YAML key (dot-free slug) still shows for the workspace-root entry,
    # where basename(".") would be uninformative.
    [[ "$output" == *"rootworkspace"* ]]
    # The de-dotted slugs must NOT appear as the Service column value;
    # they are the YAML keys, not user-facing names.
    [[ "$output" != *"fidenceiomanifestcli"* ]]
    [[ "$output" != *"fidenceiohomebrewtap"* ]]
}

@test "refresh fleet --dry-run classifies dotted CLI and Homebrew tap repo names" {
    mkdir -p "$SCRATCH/work/fidenceio.manifest.cli" "$SCRATCH/work/fidenceio.homebrew.tap/Formula"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/fidenceio.manifest.cli" init -q
    git -C "$SCRATCH/work/fidenceio.homebrew.tap" init -q
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  fidenceiomanifestcli:
    path: "./fidenceio.manifest.cli"
    type: "tool"
    branch: "main"
  fidenceiohomebrewtap:
    path: "./fidenceio.homebrew.tap"
    type: "infrastructure"
    branch: "main"
YAML
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	fidenceiomanifestcli	./fidenceio.manifest.cli	tool	true		
true	fidenceiohomebrewtap	./fidenceio.homebrew.tap	infrastructure	true		
TSV
    before="$(cat "$SCRATCH/work/manifest.fleet.tsv")"

    run_manifest refresh fleet --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST FLEET UPDATE (dry-run)"* ]]
    [[ "$output" == *"~ Changed:   0"* ]]
    [[ "$output" == *"= Unchanged: 2"* ]]
    [ "$(cat "$SCRATCH/work/manifest.fleet.tsv")" = "$before" ]
}
