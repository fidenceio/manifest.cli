#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# §44(1), through the COMMAND rather than the helper.
#
# tests/config_execution_keys.bats proves manifest_execution_preview_header
# discloses config-named programs. That helper is what `cleanup`, `pr` and the
# config CRUD previews print — and NOT what `ship repo` or `ship fleet` print.
# Their previews render their own plan block and never called the disclosure,
# so on the one command that actually executes the programs the preview said
# nothing while the apply header did. Found 2026-09-05 by reproducing the
# tracker's `--explain` lead against scripts/manifest-cli.sh: a gate command in
# manifest.config.local.yaml, a bare `ship repo patch`, no disclosure.
#
# These tests drive the real entrypoint so they hold the command to the
# contract, not a helper the command may or may not call. Each disclosure
# assertion is paired with the control that the same command without the key
# prints no disclosure at all, so a build that printed it unconditionally
# would fail too.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME SCRATCH
    # No auto-upgrade probe, no retry sleeps, no network.
    export MANIFEST_CLI_AUTO_UPDATE=false MANIFEST_CLI_GIT_RETRIES=1
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
    unset MANIFEST_CLI_AUTO_UPDATE MANIFEST_CLI_GIT_RETRIES
}

# A releasable single repo on main with one tagged version.
mk_repo() {
    local repo="$SCRATCH/repo"
    mkdir -p "$repo/docs"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name "Test"
    echo "1.0.0" > "$repo/VERSION"
    echo "# repo" > "$repo/README.md"
    echo "# docs" > "$repo/docs/INDEX.md"
    printf '# Changelog\n' > "$repo/CHANGELOG.md"
    printf 'manifest.config.local.yaml\n' > "$repo/.gitignore"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m init
    git -C "$repo" tag v1.0.0
    # Something to release: a clean tree at its tag short-circuits the preview
    # with "Nothing to release" before the plan — and the disclosure — render.
    echo "pending work" > "$repo/notes.md"
    echo "$repo"
}

# A one-member fleet root. The gate command goes in the ROOT's own local config,
# which is what the fleet command loads before it walks members.
mk_fleet() {
    local root="$SCRATCH/fleet"
    mkdir -p "$root/svc"
    git -C "$root/svc" init -q -b main
    git -C "$root/svc" config user.email test@example.com
    git -C "$root/svc" config user.name "Test"
    echo "1.0.0" > "$root/svc/VERSION"
    git -C "$root/svc" add VERSION
    git -C "$root/svc" commit -q -m init
    cat > "$root/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
YAML
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\n' > "$root/manifest.fleet.tsv"
    printf 'true\tsvc\t./svc\ttrue\tmain\n' >> "$root/manifest.fleet.tsv"
    # The entrypoint's pre-dispatch requires a git repository for `ship`, and a
    # fleet root is one: the coordination repo (see fleet_ship_manager.bats).
    git -C "$root" init -q -b main
    git -C "$root" config user.email test@example.com
    git -C "$root" config user.name "Test"
    printf 'manifest.config.local.yaml\n' > "$root/.gitignore"
    git -C "$root" add -- .gitignore manifest.fleet.config.yaml manifest.fleet.tsv
    git -C "$root" commit -q -m "fleet root"
    echo "$root"
}

run_cli_in() {
    local dir="$1"; shift
    cd "$dir"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

@test "ship repo preview discloses a config-named program from the user's .local.yaml, with its layer" {
    local repo; repo="$(mk_repo)"
    printf 'release:\n  gate_command: "/tmp/my-local-gate.sh"\n' > "$repo/manifest.config.local.yaml"

    run_cli_in "$repo" ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship repo preview"* ]]
    [[ "$output" == *"Programs this run may execute"* ]]
    [[ "$output" == *"/tmp/my-local-gate.sh"* ]]
    [[ "$output" == *"project-local layer"* ]]
}

@test "CONTROL: ship repo preview with no config-named program prints no disclosure" {
    local repo; repo="$(mk_repo)"

    run_cli_in "$repo" ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship repo preview"* ]]
    refute grep -q "Programs this run may execute" <<<"$output"
}

@test "ship repo --explain shows the static recipe and points at the preview for config-named programs" {
    # The tracker's lead: --explain loads config with the project-local layer
    # excluded, so it could disclose a different set than the preview. Resolved
    # by making --explain disclose NOTHING and say so — it explains the built-in
    # recipe, which is the same for every repository; what THIS repository's
    # configuration adds is the preview's job.
    local repo; repo="$(mk_repo)"
    printf 'release:\n  gate_command: "/tmp/my-local-gate.sh"\n' > "$repo/manifest.config.local.yaml"

    run_cli_in "$repo" ship repo patch --explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest.builtin.ship.repo.patch"* ]]
    refute grep -q "my-local-gate" <<<"$output"
    [[ "$output" == *"shown by the preview"* ]]
    [[ "$output" == *"manifest ship repo patch"* ]]
}

@test "ship fleet preview discloses the coordination root's config-named program and says members re-resolve their own" {
    local root; root="$(mk_fleet)"
    printf 'release:\n  gate_command: "/tmp/my-fleet-gate.sh"\n' > "$root/manifest.config.local.yaml"

    run_cli_in "$root" ship fleet patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Programs this run may execute"* ]]
    [[ "$output" == *"/tmp/my-fleet-gate.sh"* ]]
    [[ "$output" == *"re-resolves its own"* ]]
}

@test "CONTROL: ship fleet preview with no config-named program prints no disclosure" {
    local root; root="$(mk_fleet)"

    run_cli_in "$root" ship fleet patch
    [ "$status" -eq 0 ]
    refute grep -q "Programs this run may execute" <<<"$output"
}
