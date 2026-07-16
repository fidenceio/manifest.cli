#!/usr/bin/env bats
#
# Branch coverage for install-cli.sh beyond the happy-path e2e/atomic suites:
#   - main() argument handling (--help exits 0 with usage; unknown flag exits 2)
#   - ensure_docker_installed (docker present; macOS cask offer accept/decline/fail)
#   - validate_system hard-fail branches (docker engine down; yq missing)
#   - _wrapper_binaries_match content-hash compare
#   - configure_path WRITE branch (profile append) + non-interactive skip
#   - prune_old_versions no-op cases (fewer/equal versions than keep_n)
#
# Sandbox conventions mirror install_cli_e2e.bats / install_cli_atomic_upgrade.bats:
# isolated HOME under the bats scratch dir, OSTYPE forcing for full-script runs,
# tool dirs with recording stubs, no network and no real brew/docker.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Build $TOOL_DIR with symlinks to the named real tools (resolved from the
# standard host locations) — same fixture as install_cli_e2e.bats.
_build_tool_dir() {
    export TOOL_DIR="$SCRATCH/tools"
    mkdir -p "$TOOL_DIR"
    local tool resolved
    for tool in "$@"; do
        resolved="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v "$tool" 2>/dev/null || true)"
        [ -n "$resolved" ] && ln -sf "$resolved" "$TOOL_DIR/$tool"
    done
}

# PATH with a recording `brew` stub and NO docker anywhere, for the
# ensure_docker_installed cask-offer branch. The stub's exit code is
# controlled via MANIFEST_STUB_BREW_EXIT (default 0).
_docker_missing_env() {
    BREW_LOG="$SCRATCH/brew-calls.log"
    : > "$BREW_LOG"
    export BREW_LOG
    local stub="$SCRATCH/brewbin"
    mkdir -p "$stub"
    cat > "$stub/brew" <<EOF
#!/bin/bash
echo "\$*" >> "$BREW_LOG"
exit "\${MANIFEST_STUB_BREW_EXIT:-0}"
EOF
    chmod +x "$stub/brew"
    export PATH="$stub:/usr/bin:/bin"
}

# =============================================================================
# main() argument handling
# =============================================================================

@test "main: --help prints usage and exits 0 before any install work" {
    cd "$TEST_REPO_ROOT"
    run bash "$TEST_REPO_ROOT/install-cli.sh" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Usage: ./install-cli.sh"
    echo "$output" | grep -q -- "--manual, --no-brew"
    echo "$output" | grep -q -- "--brew, --homebrew"
    # --help exits inside arg parsing — zero filesystem footprint in the sandbox.
    [ ! -e "$HOME/.manifest-cli" ]
    [ ! -e "$HOME/.local/bin/manifest" ]
}

@test "main: unknown flag exits 2 with an error and a --help pointer" {
    cd "$TEST_REPO_ROOT"
    run bash "$TEST_REPO_ROOT/install-cli.sh" --frobnicate
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "Unknown option: --frobnicate"
    echo "$output" | grep -q "Run './install-cli.sh --help' for usage."
    [ ! -e "$HOME/.manifest-cli" ]
}

# =============================================================================
# ensure_docker_installed
# =============================================================================

@test "ensure_docker_installed: docker on PATH returns 0 with no prompting" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    local stub="$SCRATCH/dockerbin"
    mkdir -p "$stub"
    printf '#!/bin/bash\nexit 0\n' > "$stub/docker"
    chmod +x "$stub/docker"
    export PATH="$stub:/usr/bin:/bin"
    run ensure_docker_installed < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ensure_docker_installed: missing docker on macOS offers the cask; accepting installs it" {
    [[ "$OSTYPE" == darwin* ]] || skip "cask-offer branch is OSTYPE=darwin*-gated in source"
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    _docker_missing_env
    run ensure_docker_installed <<< "y"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Docker is required and is not installed"
    echo "$output" | grep -q "Docker Desktop installed"
    echo "$output" | grep -q "open -a Docker"
    # The recording stub proves the exact brew invocation.
    grep -qx "install --cask docker" "$BREW_LOG"
}

@test "ensure_docker_installed: declining the cask offer skips installation and never calls brew" {
    [[ "$OSTYPE" == darwin* ]] || skip "cask-offer branch is OSTYPE=darwin*-gated in source"
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    _docker_missing_env
    run ensure_docker_installed <<< "n"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Skipping Docker installation"
    ! echo "$output" | grep -q "Docker Desktop installed"
    [ ! -s "$BREW_LOG" ]
}

@test "ensure_docker_installed: failed cask install reports the failure and returns 1" {
    [[ "$OSTYPE" == darwin* ]] || skip "cask-offer branch is OSTYPE=darwin*-gated in source"
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    _docker_missing_env
    export MANIFEST_STUB_BREW_EXIT=1
    run ensure_docker_installed <<< "y"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Docker Desktop installation failed"
    grep -qx "install --cask docker" "$BREW_LOG"
}

# =============================================================================
# validate_system hard-fail branches (full script runs, e2e-style sandbox)
# =============================================================================

@test "validate_system: docker present but engine down is a hard validation failure" {
    command -v yq >/dev/null 2>&1 || skip "yq not installed on host"
    command -v gtimeout >/dev/null 2>&1 || skip "gtimeout (coreutils) not installed on host"
    _build_tool_dir git yq gtimeout timeout bash curl
    # Docker stub: the binary exists but `docker info` fails (engine down).
    cat > "$TOOL_DIR/docker" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "info" ] && exit 1
exit 0
EOS
    chmod +x "$TOOL_DIR/docker"
    export PATH="$TOOL_DIR:/usr/bin:/bin"
    cd "$TEST_REPO_ROOT"

    OSTYPE=linux-gnu run env \
        HOME="$HOME" \
        PATH="$PATH" \
        OSTYPE=linux-gnu \
        bash "$TEST_REPO_ROOT/install-cli.sh" < /dev/null

    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Docker is installed, but the Docker engine is not running"
    echo "$output" | grep -q "System validation failed with 1 error(s)"
    # Validation fails before any staging: zero install footprint.
    [ ! -e "$HOME/.manifest-cli" ]
    [ ! -e "$HOME/.local/bin/manifest" ]
}

@test "validate_system: missing yq is rejected with the yq requirement" {
    command -v gtimeout >/dev/null 2>&1 || skip "gtimeout (coreutils) not installed on host"
    _build_tool_dir git gtimeout timeout bash curl   # deliberately NO yq
    cat > "$TOOL_DIR/docker" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
    chmod +x "$TOOL_DIR/docker"
    export PATH="$TOOL_DIR:/usr/bin:/bin"
    cd "$TEST_REPO_ROOT"

    OSTYPE=linux-gnu run env \
        HOME="$HOME" \
        PATH="$PATH" \
        OSTYPE=linux-gnu \
        bash "$TEST_REPO_ROOT/install-cli.sh" < /dev/null

    [ "$status" -eq 1 ]
    echo "$output" | grep -q "required for YAML config"
    echo "$output" | grep -q "System validation failed with 1 error(s)"
    [ ! -e "$HOME/.manifest-cli" ]
}

# =============================================================================
# _wrapper_binaries_match
# =============================================================================

@test "_wrapper_binaries_match: identical bytes match" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    printf '#!/bin/bash\necho manifest wrapper\n' > "$SCRATCH/src"
    cp "$SCRATCH/src" "$SCRATCH/dst"
    run _wrapper_binaries_match "$SCRATCH/src" "$SCRATCH/dst"
    [ "$status" -eq 0 ]
}

@test "_wrapper_binaries_match: differing bytes do not match" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    printf '#!/bin/bash\necho manifest wrapper\n' > "$SCRATCH/src"
    printf '#!/bin/bash\necho manifest wrapper v2\n' > "$SCRATCH/dst"
    run _wrapper_binaries_match "$SCRATCH/src" "$SCRATCH/dst"
    [ "$status" -eq 1 ]
}

@test "_wrapper_binaries_match: missing installed wrapper does not match" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    printf '#!/bin/bash\necho manifest wrapper\n' > "$SCRATCH/src"
    run _wrapper_binaries_match "$SCRATCH/src" "$SCRATCH/does-not-exist"
    [ "$status" -eq 1 ]
}

# =============================================================================
# configure_path
# =============================================================================

@test "configure_path: non-interactive run warns and skips the profile write" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    # Precondition of the write branch: the sandbox HOME's .local/bin is not on PATH.
    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]
    run configure_path < /dev/null
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "is not in your PATH"
    echo "$output" | grep -q "To make this permanent"
    echo "$output" | grep -q "Non-interactive shell detected; skipping automatic profile edit"
    # No profile file gained the PATH line.
    [ ! -f "$HOME/.bashrc" ]
    [ ! -f "$HOME/.bash_profile" ]
    [ ! -f "$HOME/.zshrc" ]
}

@test "configure_path: interactive accept appends the PATH export to the sandbox profile" {
    # The profile append is gated on [ -t 0 ], so the function runs under a
    # pty allocated by script(1). Input 'y' is sent only once the prompt has
    # appeared in the captured output — no timing race.
    command -v /usr/bin/script >/dev/null 2>&1 || skip "script(1) not available for pty allocation"
    local bash5
    bash5="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v bash)"
    local out="$SCRATCH/pty-out.txt"
    local runner="$SCRATCH/pty-runner.sh"
    cat > "$runner" <<EOF
export HOME="$HOME"
export PATH="/usr/bin:/bin"
source "$TEST_REPO_ROOT/install-cli.sh"
configure_path
EOF

    (
        for _ in $(seq 1 100); do
            grep -q "Would you like me to add this" "$out" 2>/dev/null && break
            perl -e 'select(undef,undef,undef,0.1)'
        done
        printf 'y\n'
        # Hold stdin open briefly so EOF cannot race the single-char read.
        perl -e 'select(undef,undef,undef,0.5)'
    ) | /usr/bin/script -q /dev/null "$bash5" "$runner" > "$out" 2>&1

    grep -q "Added to $HOME/.bashrc" "$out"
    [ -f "$HOME/.bashrc" ]
    grep -qxF "export PATH=\"$HOME/.local/bin:\$PATH\"" "$HOME/.bashrc"
    # Exactly one line was appended.
    [ "$(grep -c 'local/bin' "$HOME/.bashrc")" -eq 1 ]
}

# =============================================================================
# prune_old_versions no-op cases
# =============================================================================

@test "prune_old_versions: fewer versions than keep_n deletes nothing" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    local rt="$HOME/.manifest-cli/runtime"
    mkdir -p "$rt/v1.0.0" "$rt/v2.0.0"
    ln -sfn "runtime/v2.0.0" "$HOME/.manifest-cli/current"
    run prune_old_versions 5
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Pruned"
    [ -d "$rt/v1.0.0" ]
    [ -d "$rt/v2.0.0" ]
}

@test "prune_old_versions: version count equal to default keep_n deletes nothing" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    local rt="$HOME/.manifest-cli/runtime"
    mkdir -p "$rt/v1.0.0" "$rt/v2.0.0"
    ln -sfn "runtime/v2.0.0" "$HOME/.manifest-cli/current"
    run prune_old_versions
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Pruned"
    [ -d "$rt/v1.0.0" ]
    [ -d "$rt/v2.0.0" ]
}

@test "prune_old_versions: absent runtime root is a silent no-op" {
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"
    [ ! -d "$HOME/.manifest-cli/runtime" ]
    run prune_old_versions
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
