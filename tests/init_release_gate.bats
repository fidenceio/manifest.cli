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

@test "gate scaffold: the exact full-tier ship argv is accepted and runs to a verdict" {
    echo "1.0.0" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    # Exactly what _manifest_release_gate_test_command resolves to. No toolchain
    # is declared here, so the full tier reaches its fail-closed verdict — the
    # point is that --tier/--jobs/--no-cache all parse and the full path runs.
    run ./scripts/run-tests.sh --tier full --jobs 1 --no-cache
    echo "$output" | grep -q "run-tests: FAIL (tier: full)"
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

@test "gate scaffold: package.json scripts become host-native pm run checks; placeholder test skipped" {
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
    grep -q 'run_check npm run lint' "$PROJ/scripts/run-tests.sh"
    grep -q 'run_check npm run build' "$PROJ/scripts/run-tests.sh"
    ! grep -qE 'run_check npm run test' "$PROJ/scripts/run-tests.sh"
    # Host-native only: the neutral default never imposes a container.
    ! grep -q 'docker' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: node repo with build+test gets both via the detected pm" {
    cat > "$PROJ/package.json" << 'EOF'
{
  "name": "x",
  "scripts": { "build": "vite build", "test": "vitest run" }
}
EOF
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check npm run build' "$PROJ/scripts/run-tests.sh"
    grep -q 'run_check npm run test' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: package-manager detection — pnpm lockfile" {
    printf '{"scripts":{"build":"x","test":"y"}}\n' > "$PROJ/package.json"
    touch "$PROJ/pnpm-lock.yaml"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check pnpm run build' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'run_check npm run' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: package-manager detection — yarn lockfile" {
    printf '{"scripts":{"test":"y"}}\n' > "$PROJ/package.json"
    touch "$PROJ/yarn.lock"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check yarn run test' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: package-manager detection — bun lockfile" {
    printf '{"scripts":{"build":"b"}}\n' > "$PROJ/package.json"
    touch "$PROJ/bun.lockb"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check bun run build' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: package-manager detection — packageManager field wins over lockfile" {
    cat > "$PROJ/package.json" << 'EOF'
{ "packageManager": "pnpm@9.1.0", "scripts": { "build": "b" } }
EOF
    touch "$PROJ/yarn.lock"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check pnpm run build' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'run_check yarn run' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: Go repo gets host-native go build + go test" {
    printf 'module x\n\ngo 1.23\n' > "$PROJ/go.mod"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check go build ./\.\.\.' "$PROJ/scripts/run-tests.sh"
    grep -q 'run_check go test ./\.\.\.' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'docker' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: Makefile test target is a fallback when nothing more specific is declared" {
    printf 'build:\n\techo build\ntest:\n\techo test\n' > "$PROJ/Makefile"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check make build' "$PROJ/scripts/run-tests.sh"
    grep -q 'run_check make test' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: a declared toolchain suppresses the Makefile fallback" {
    touch "$PROJ/Cargo.toml"
    printf 'test:\n\techo test\n' > "$PROJ/Makefile"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check cargo test' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'run_check make test' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: .NET repo (.csproj, no package.json) gets a dotnet gate, not 'other'" {
    mkdir -p "$PROJ/src/Api"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$PROJ/src/Api/Api.csproj"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check dotnet build' "$PROJ/scripts/run-tests.sh"
    grep -q 'run_check dotnet test' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'cannot certify' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'docker' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: .NET solution at repo root is detected" {
    printf 'Microsoft Visual Studio Solution File\n' > "$PROJ/App.sln"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check dotnet build' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: compose/config repo (no app source) gets docker compose config -q" {
    printf 'services:\n  x:\n    image: nginx\n' > "$PROJ/docker-compose.yml"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check docker compose config -q' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: compose is a fallback — app source wins over compose" {
    touch "$PROJ/go.mod"
    printf 'services:\n  x:\n    image: nginx\n' > "$PROJ/docker-compose.yml"
    ensure_release_gate_script "$PROJ"
    grep -q 'run_check go build' "$PROJ/scripts/run-tests.sh"
    ! grep -q 'docker compose config' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: Docker-only repo is NOT auto-containerized — falls to the loud path" {
    echo "1.0.0" > "$PROJ/VERSION"
    printf 'FROM alpine:3.20\nCMD ["true"]\n' > "$PROJ/Dockerfile"
    ensure_release_gate_script "$PROJ"
    ! grep -q 'docker build' "$PROJ/scripts/run-tests.sh"
    grep -q 'cannot certify' "$PROJ/scripts/run-tests.sh"
}

@test "gate scaffold: no verification declared — full tier is LOUD and BLOCKS, not a silent pass" {
    echo "1.0.0" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    run ./scripts/run-tests.sh --tier full
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "cannot certify"
    echo "$output" | grep -q "release_gate=none"
    ! echo "$output" | grep -q "run-tests: PASS"
}

@test "gate scaffold: no verification declared — smoke tier stays a fast baseline preflight" {
    echo "1.0.0" > "$PROJ/VERSION"
    ensure_release_gate_script "$PROJ"
    cd "$PROJ"

    run ./scripts/run-tests.sh --tier smoke
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "run-tests: PASS (tier: smoke)"
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
