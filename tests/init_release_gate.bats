#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for release-gate scaffolding at init time (ensure_release_gate_script /
# create_default_run_tests). Since v56 the release gate is fail-closed — a
# releaseable repo with no test command refuses to release, and `ship fleet`
# aborts at the first such member. Init therefore scaffolds the
# scripts/run-tests.sh gate the orchestrator auto-detects, so a fleet's FIRST
# `ship fleet` cannot die on a gate-less member. These tests pin: creation,
# executability, the ship argv contract (--tier/--jobs/--no-cache), no-clobber,
# scaffold-time toolchain detection, and that the baseline floor is real
# verification (it can fail), not a disguised `exit 0`.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- creation ----------------------------------------------------------------

@test "gate scaffold: creates an executable, parseable scripts/run-tests.sh" {
    run ensure_release_gate_script "$PROJ"
    [ "$status" -eq 0 ]
    [ -x "$PROJ/scripts/run-tests.sh" ]
    bash -n "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: no-clobber — an existing gate is never touched" {
    mkdir -p "$PROJ/scripts"
    printf '#!/bin/sh\necho mine\n' > "$PROJ/scripts/run-tests.sh"

    run ensure_release_gate_script "$PROJ"
    [ "$status" -eq 0 ]
    grep -q 'echo mine' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'scaffolded by Manifest CLI' "$PROJ/scripts/run-tests.sh"
}

# --- the ship argv contract ----------------------------------------------------

@test "gate scaffold: baseline-only repo passes under the exact ship argv" {
    echo "1.0.0" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    # Exactly what _manifest_release_gate_test_command resolves to.
    run ./scripts/run-tests.sh --tier full --jobs 1 --no-cache
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "run-tests: PASS"
}

@test "gate scaffold: --tier smoke runs baseline only and passes" {
    echo "2.3.4" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    run ./scripts/run-tests.sh --tier smoke --jobs 1 --no-cache
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "run-tests: PASS (tier: smoke)"
}

# --- the floor is real verification -------------------------------------------

@test "gate scaffold: fails on a missing VERSION file" {
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    run ./scripts/run-tests.sh --tier smoke
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "VERSION file missing"
}

@test "gate scaffold: fails on a shell script with a syntax error" {
    echo "1.0.0" > "$PROJ/VERSION"
    printf 'if then fi (\n' > "$PROJ/broken.sh"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    run ./scripts/run-tests.sh --tier smoke
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "shell syntax: broken.sh"
}

@test "gate scaffold: fails on a non-semver VERSION" {
    echo "not-a-version" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    run ./scripts/run-tests.sh --tier smoke
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "not semver-shaped"
}

# --- scaffold-time toolchain detection ----------------------------------------

@test "gate scaffold: Cargo.toml repo gets a cargo test project check" {
    touch "$PROJ/Cargo.toml"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check cargo test' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: package.json scripts become npm run checks; placeholder test skipped" {
    cat > "$PROJ/package.json" << 'EOF'
{
  "name": "x",
  "scripts": {
    "lint": "eslint .",
    "build": "next build",
    "test": "echo \"Error: no test specified\" && exit 1"
  }
}
EOF
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check npm run --silent lint' "$PROJ/scripts/run-tests.sh"
    grep -q 'run_check npm run --silent build' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'run --silent test' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: Dockerfile test stage wins over other toolchains" {
    touch "$PROJ/Cargo.toml"
    printf 'FROM rust:1 AS build\nFROM build AS test\n' > "$PROJ/Dockerfile"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check docker build --target test .' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'run_check cargo test' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: no toolchain detected — gate still real, notes baseline-only" {
    echo "1.0.0" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    run ./scripts/run-tests.sh --tier full
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "no project checks defined yet"
}

# --- wiring: init repo + gate auto-detect --------------------------------------

@test "init repo -y: scaffolds the gate alongside the required files" {
    cd "$PROJ"
    git init -q

    MANIFEST_CLI_PROJECT_ROOT="$PROJ" run manifest_init_repo -y
    [ "$status" -eq 0 ]
    [ -x "$PROJ/scripts/run-tests.sh" ]
}

@test "init repo --dry-run: previews the gate" {
    cd "$PROJ"

    MANIFEST_CLI_PROJECT_ROOT="$PROJ" run manifest_init_repo --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would create:.*scripts/run-tests.sh"
}

@test "scaffolded gate satisfies the orchestrator's auto-detect" {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    echo "1.0.0" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"

    MANIFEST_CLI_PROJECT_ROOT="$PROJ" _manifest_release_gate_test_command "full"
    [ "${MANIFEST_CLI_RELEASE_GATE_ARGV[0]}" = "./scripts/run-tests.sh" ]
}
