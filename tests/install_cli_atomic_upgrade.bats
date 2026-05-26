#!/usr/bin/env bats
#
# §5.7 atomic-upgrade refactor tests. Exercise the install-cli.sh
# manual-install path against a sandboxed $HOME and verify:
#   - the runtime/v<X>/ + current-symlink layout lands correctly
#   - upgrades atomically swap the symlink without touching user state
#   - shell profiles are not rewritten on upgrade (duplicate-write defect)
#   - prune_old_versions retains the right set of versioned dirs
#   - the install lock prevents concurrent installer runs
#
# Tests skip when the host toolchain can't satisfy the installer's
# validate_system pre-flight (matches install_cli_e2e.bats convention).

load 'helpers/setup'

setup() {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed on host"
    fi
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export MANIFEST_CLI_LOCAL_BIN_TEST="$HOME/.local/bin"
    mkdir -p "$MANIFEST_CLI_LOCAL_BIN_TEST"
    export PATH="$MANIFEST_CLI_LOCAL_BIN_TEST:$PATH"

    export TOOL_DIR="$SCRATCH/tools"
    mkdir -p "$TOOL_DIR"
    local tool resolved
    for tool in git yq gtimeout timeout bash curl; do
        resolved="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v "$tool" 2>/dev/null || true)"
        [ -n "$resolved" ] && ln -sf "$resolved" "$TOOL_DIR/$tool"
    done
    cat > "$TOOL_DIR/docker" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
    chmod +x "$TOOL_DIR/docker"
    # Strip brew off PATH so the manual install branch fires; keep the
    # sandbox bin dir on PATH so verify_installation finds the wrapper.
    export PATH="$MANIFEST_CLI_LOCAL_BIN_TEST:$TOOL_DIR:/usr/bin:/bin"

    # All tests live under the real CLI repo as $TEST_REPO_ROOT; cd-in so
    # validate_system finds scripts/manifest-cli-wrapper.sh.
    cd "$TEST_REPO_ROOT"

    INSTALLER_VERSION="$(tr -d '[:space:]' < "$TEST_REPO_ROOT/VERSION")"
    export INSTALLER_VERSION
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Run install-cli.sh in the configured sandbox. Returns its exit status
# via bats $status / $output.
_run_installer() {
    OSTYPE=linux-gnu run env \
        HOME="$HOME" \
        PATH="$PATH" \
        OSTYPE=linux-gnu \
        bash "$TEST_REPO_ROOT/install-cli.sh" --manual < /dev/null
}

@test "atomic-upgrade: fresh-install creates current symlink and versioned dir" {
    _run_installer
    if [ "$status" -ne 0 ]; then
        echo "install-cli.sh exited $status. Output:" >&2
        echo "$output" >&2
    fi
    [ "$status" -eq 0 ]

    # `current` is a symlink whose target is the versioned dir.
    [ -L "$HOME/.manifest-cli/current" ]
    local target
    target="$(readlink "$HOME/.manifest-cli/current")"
    [ "$target" = "runtime/v${INSTALLER_VERSION}" ]

    # Modules readable through the symlink.
    [ -r "$HOME/.manifest-cli/current/modules/core/manifest-core.sh" ]

    # Exactly one version dir under runtime/.
    local count
    count="$(find "$HOME/.manifest-cli/runtime" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d '[:space:]')"
    [ "$count" = "1" ]
}

@test "atomic-upgrade: upgrade swaps symlink atomically and preserves prior version" {
    # Pre-create a prior versioned install so the installer sees mode=upgrade.
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.1/modules"
    : > "$HOME/.manifest-cli/runtime/v0.0.1/modules/marker"
    echo "0.0.1" > "$HOME/.manifest-cli/runtime/v0.0.1/VERSION"
    ln -s "runtime/v0.0.1" "$HOME/.manifest-cli/current"

    _run_installer
    if [ "$status" -ne 0 ]; then
        echo "install-cli.sh exited $status. Output:" >&2
        echo "$output" >&2
    fi
    [ "$status" -eq 0 ]

    # current points at the new version.
    [ -L "$HOME/.manifest-cli/current" ]
    local target
    target="$(readlink "$HOME/.manifest-cli/current")"
    [ "$target" = "runtime/v${INSTALLER_VERSION}" ]

    # Old version still present and accessible.
    [ -d "$HOME/.manifest-cli/runtime/v0.0.1" ]
    [ -f "$HOME/.manifest-cli/runtime/v0.0.1/modules/marker" ]

    # New version also present and complete.
    [ -d "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}" ]
    [ -r "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}/modules/core/manifest-core.sh" ]
}

@test "atomic-upgrade: upgrade preserves user state (logs, audit, config)" {
    # Pre-create an active upgrade-mode install.
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.1/modules"
    echo "0.0.1" > "$HOME/.manifest-cli/runtime/v0.0.1/VERSION"
    ln -s "runtime/v0.0.1" "$HOME/.manifest-cli/current"

    mkdir -p "$HOME/.manifest-cli/logs" "$HOME/.manifest-cli/audit"
    echo "preserved-log-sentinel" > "$HOME/.manifest-cli/logs/op.log"
    echo "preserved-audit-sentinel" > "$HOME/.manifest-cli/audit/event.jsonl"
    # Use the shipped example config so the (always-runs) safe-key
    # migration in create_configuration doesn't error on a minimal stub.
    # We tag it with a sentinel marker we can verify wasn't overwritten.
    cp "$TEST_REPO_ROOT/examples/manifest.config.yaml.example" \
        "$HOME/.manifest-cli/manifest.config.global.yaml"
    printf '# preserved-config-sentinel\n' >> "$HOME/.manifest-cli/manifest.config.global.yaml"

    local logs_sha audit_sha config_sha
    logs_sha="$(shasum -a 256 "$HOME/.manifest-cli/logs/op.log" | awk '{print $1}')"
    audit_sha="$(shasum -a 256 "$HOME/.manifest-cli/audit/event.jsonl" | awk '{print $1}')"
    config_sha="$(shasum -a 256 "$HOME/.manifest-cli/manifest.config.global.yaml" | awk '{print $1}')"

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    # Each user-state file unchanged.
    [ "$(shasum -a 256 "$HOME/.manifest-cli/logs/op.log" | awk '{print $1}')" = "$logs_sha" ]
    [ "$(shasum -a 256 "$HOME/.manifest-cli/audit/event.jsonl" | awk '{print $1}')" = "$audit_sha" ]
    [ "$(shasum -a 256 "$HOME/.manifest-cli/manifest.config.global.yaml" | awk '{print $1}')" = "$config_sha" ]
}

@test "atomic-upgrade: upgrade does not rewrite shell profiles" {
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.1/modules"
    echo "0.0.1" > "$HOME/.manifest-cli/runtime/v0.0.1/VERSION"
    ln -s "runtime/v0.0.1" "$HOME/.manifest-cli/current"

    cat > "$HOME/.zshrc" <<'EOF'
# sentinel-zshrc
export FOO=bar
export PATH="$HOME/.local/bin:$PATH"
EOF
    local zshrc_sha
    zshrc_sha="$(shasum -a 256 "$HOME/.zshrc" | awk '{print $1}')"

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    # Zero backups produced.
    local n
    n="$(find "$HOME" -maxdepth 1 -name '.zshrc.manifest-backup-*' | wc -l | tr -d '[:space:]')"
    [ "$n" = "0" ]

    # Shasum unchanged.
    [ "$(shasum -a 256 "$HOME/.zshrc" | awk '{print $1}')" = "$zshrc_sha" ]
}

@test "atomic-upgrade: duplicate-write defect regression — zero backups on upgrade" {
    # Direct regression assertion for the duplicate cleanup_environment_variables
    # call that previously produced two backups per upgrade.
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.1/modules"
    echo "0.0.1" > "$HOME/.manifest-cli/runtime/v0.0.1/VERSION"
    ln -s "runtime/v0.0.1" "$HOME/.manifest-cli/current"

    cat > "$HOME/.zshrc" <<'EOF'
export MANIFEST_CLI_FOO=bar
export PATH="$HOME/.local/bin:$PATH"
EOF

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    local count
    count="$(ls "$HOME"/.zshrc.manifest-backup-* 2>/dev/null | wc -l | tr -d '[:space:]')"
    [ "$count" = "0" ]
}

@test "atomic-upgrade: prune keeps N most recent versions" {
    # Build a fixture with three prior versions, oldest → newest by mtime.
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.1/modules"
    echo "0.0.1" > "$HOME/.manifest-cli/runtime/v0.0.1/VERSION"
    touch -t 202001010000 "$HOME/.manifest-cli/runtime/v0.0.1"
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.2/modules"
    echo "0.0.2" > "$HOME/.manifest-cli/runtime/v0.0.2/VERSION"
    touch -t 202001020000 "$HOME/.manifest-cli/runtime/v0.0.2"
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.3/modules"
    echo "0.0.3" > "$HOME/.manifest-cli/runtime/v0.0.3/VERSION"
    touch -t 202001030000 "$HOME/.manifest-cli/runtime/v0.0.3"
    ln -s "runtime/v0.0.3" "$HOME/.manifest-cli/current"

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    # With keep_n=2, the new install version + previous active (v0.0.3)
    # are retained; the two oldest are removed.
    [ -d "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}" ]
    [ -d "$HOME/.manifest-cli/runtime/v0.0.3" ]
    [ ! -d "$HOME/.manifest-cli/runtime/v0.0.2" ]
    [ ! -d "$HOME/.manifest-cli/runtime/v0.0.1" ]
}

@test "atomic-upgrade: install lock prevents concurrent runs" {
    mkdir -p "$HOME/.manifest-cli"
    # Plant a lock owned by our own pid so kill -0 succeeds.
    {
        echo "$$"
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    } > "$HOME/.manifest-cli/.install.lock"

    _run_installer
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "already in progress"
    # runtime/ must not have been created or written by the rejected run.
    [ ! -d "$HOME/.manifest-cli/runtime" ]

    # Clean the lock so teardown succeeds.
    rm -f "$HOME/.manifest-cli/.install.lock"
}
