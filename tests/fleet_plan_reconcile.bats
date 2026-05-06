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

write_plan() {
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
}

@test "plan fleet defaults to dry-run and writes no plan file" {
    mkdir -p "$SCRATCH/work/services/api"
    git -C "$SCRATCH/work/services/api" init -q

    run_manifest plan fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest plan fleet"* ]]
    [[ "$output" == *"Would write:"*"manifest.fleet.plan.yaml"* ]]
    [[ "$output" == *"No changes written. Re-run with --apply or --do to apply."* ]]
    [ ! -f "$SCRATCH/work/manifest.fleet.plan.yaml" ]
}

@test "plan fleet --do writes manifest.fleet.plan.yaml" {
    mkdir -p "$SCRATCH/work/services/api"
    git -C "$SCRATCH/work/services/api" init -q

    run_manifest plan fleet --do --name test-fleet

    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/work/manifest.fleet.plan.yaml" ]
    grep -q 'name: "test-fleet"' "$SCRATCH/work/manifest.fleet.plan.yaml"
    grep -q 'action: "track"' "$SCRATCH/work/manifest.fleet.plan.yaml"
}

@test "plan fleet --apply and --do are compatible aliases" {
    mkdir -p "$SCRATCH/work/services/api"
    git -C "$SCRATCH/work/services/api" init -q

    run_manifest plan fleet --apply --do --name test-fleet

    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/work/manifest.fleet.plan.yaml" ]
}

@test "reconcile fleet defaults to dry-run and does not initialize plain dirs" {
    mkdir -p "$SCRATCH/work/plain"
    write_plan

    run_manifest reconcile fleet

    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run - manifest reconcile fleet"* ]]
    [[ "$output" == *"init repos:"*"1"* ]]
    [[ "$output" == *"Validation: passed"* ]]
    [[ "$output" == *"No changes written. Re-run with --apply or --do to apply."* ]]
    [ ! -d "$SCRATCH/work/plain/.git" ]
    [ ! -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
}

@test "reconcile fleet --apply initializes plain dir and tracks it" {
    mkdir -p "$SCRATCH/work/plain"
    write_plan

    run_manifest reconcile fleet --apply

    [ "$status" -eq 0 ]
    [ -d "$SCRATCH/work/plain/.git" ]
    [ -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
    grep -q '^  plain:' "$SCRATCH/work/manifest.fleet.config.yaml"
}

@test "reconcile fleet --do behaves like --apply" {
    mkdir -p "$SCRATCH/work/plain"
    write_plan

    run_manifest reconcile fleet --do

    [ "$status" -eq 0 ]
    [ -d "$SCRATCH/work/plain/.git" ]
    grep -q '^  plain:' "$SCRATCH/work/manifest.fleet.config.yaml"
}

@test "mutation ladder rejects commit push and force without prerequisites" {
    mkdir -p "$SCRATCH/work/plain"
    write_plan

    run_manifest reconcile fleet --commit
    [ "$status" -ne 0 ]
    [[ "$output" == *"--commit requires --apply or --do"* ]]

    run_manifest reconcile fleet --apply --push
    [ "$status" -ne 0 ]
    [[ "$output" == *"--push requires --commit"* ]]

    run_manifest reconcile fleet --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"--force requires --apply or --do"* ]]
}

@test "reconcile fleet blocks target collisions" {
    mkdir -p "$SCRATCH/work/plain" "$SCRATCH/work/existing"
    write_plan
    yq e '.entries[0].target_path = "existing"' -i "$SCRATCH/work/manifest.fleet.plan.yaml"

    run_manifest reconcile fleet

    [ "$status" -ne 0 ]
    [[ "$output" == *"target already exists: existing"* ]]
    [[ "$output" == *"Validation: failed"* ]]
}

@test "reconcile fleet blocks nested active target paths" {
    mkdir -p "$SCRATCH/work/a" "$SCRATCH/work/a/b"
    cat > "$SCRATCH/work/manifest.fleet.plan.yaml" <<'YAML'
fleet:
  name: "test-fleet"
entries:
  - name: "a"
    kind: "plain_dir"
    source_path: "a"
    target_path: "a"
    action: "init"
  - name: "b"
    kind: "plain_dir"
    source_path: "a/b"
    target_path: "a/b"
    action: "init"
YAML

    run_manifest reconcile fleet

    [ "$status" -ne 0 ]
    [[ "$output" == *"Plan selects nested target paths"* ]]
}

@test "plan fleet detects gitmodules as adopt_submodule entries" {
    mkdir -p "$SCRATCH/work/shell/infra"
    git -C "$SCRATCH/work/shell" init -q
    cat > "$SCRATCH/work/shell/.gitmodules" <<'GITMODULES'
[submodule "infra"]
	path = infra
	url = https://example.invalid/infra.git
GITMODULES

    run_manifest plan fleet --apply

    [ "$status" -eq 0 ]
    grep -q 'kind: "submodule"' "$SCRATCH/work/manifest.fleet.plan.yaml"
    grep -q 'action: "adopt_submodule"' "$SCRATCH/work/manifest.fleet.plan.yaml"
}

@test "reconcile fleet blocks adopt_submodule unless explicitly opted in" {
    mkdir -p "$SCRATCH/work/shell/infra"
    git -C "$SCRATCH/work/shell" init -q
    git -C "$SCRATCH/work/shell" config user.email test@example.invalid
    git -C "$SCRATCH/work/shell" config user.name Test
    cat > "$SCRATCH/work/shell/.gitmodules" <<'GITMODULES'
[submodule "infra"]
	path = infra
	url = https://example.invalid/infra.git
GITMODULES
    git -C "$SCRATCH/work/shell" add .gitmodules
    git -C "$SCRATCH/work/shell" commit -m "add gitmodules" >/dev/null
    cat > "$SCRATCH/work/manifest.fleet.plan.yaml" <<'YAML'
fleet:
  name: "test-fleet"
entries:
  - name: "infra"
    kind: "submodule"
    source_path: "shell/infra"
    target_path: "infra"
    action: "adopt_submodule"
    remote_url: "https://example.invalid/infra.git"
    parent_path: "shell"
    submodule_name: "infra"
YAML

    run_manifest reconcile fleet

    [ "$status" -ne 0 ]
    [[ "$output" == *"uses adopt_submodule; pass --adopt-submodules"* ]]
}

@test "reconcile fleet adopts nested submodule using parent-relative git rm path" {
    git init -q "$SCRATCH/infra-src"
    git -C "$SCRATCH/infra-src" config user.email test@example.invalid
    git -C "$SCRATCH/infra-src" config user.name Test
    echo "infra" > "$SCRATCH/infra-src/README.md"
    git -C "$SCRATCH/infra-src" add README.md
    git -C "$SCRATCH/infra-src" commit -m "seed infra" >/dev/null
    git clone --bare "$SCRATCH/infra-src" "$SCRATCH/infra.git" >/dev/null 2>&1

    mkdir -p "$SCRATCH/work/shell"
    git -C "$SCRATCH/work/shell" init -q
    git -C "$SCRATCH/work/shell" config user.email test@example.invalid
    git -C "$SCRATCH/work/shell" config user.name Test
    git -C "$SCRATCH/work/shell" -c protocol.file.allow=always submodule add "$SCRATCH/infra.git" infra >/dev/null
    git -C "$SCRATCH/work/shell" commit -m "add infra submodule" >/dev/null

    cat > "$SCRATCH/work/manifest.fleet.plan.yaml" <<YAML
fleet:
  name: "test-fleet"
entries:
  - name: "infra"
    kind: "submodule"
    source_path: "shell/infra"
    target_path: "standalone/infra"
    action: "adopt_submodule"
    type: "service"
    remote_url: "$SCRATCH/infra.git"
    branch: "main"
    submodule: true
    parent_path: "shell"
    submodule_name: "infra"
YAML

    run_manifest reconcile fleet --apply --adopt-submodules

    [ "$status" -eq 0 ]
    [ -d "$SCRATCH/work/standalone/infra/.git" ]
    [ -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
    grep -q '^  infra:' "$SCRATCH/work/manifest.fleet.config.yaml"
    git -C "$SCRATCH/work/shell" status --porcelain | grep -q 'infra'
    [ ! -e "$SCRATCH/work/shell/infra" ]
}
