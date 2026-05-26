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

# Run install-cli.sh with a MANIFEST_CLI_INSTALL_FAIL_AT fault injection.
# Used by the Phase 3 fault-injection suite.
_run_installer_with_fail_at() {
    local phase="$1"
    OSTYPE=linux-gnu run env \
        HOME="$HOME" \
        PATH="$PATH" \
        OSTYPE=linux-gnu \
        MANIFEST_CLI_INSTALL_FAIL_AT="$phase" \
        bash "$TEST_REPO_ROOT/install-cli.sh" --manual < /dev/null
}

# Seed a prior versioned install at runtime/v<version>/ with a sentinel
# marker, a `current` symlink pointing at it, and a working wrapper at
# ~/.local/bin/manifest. Used by the fault-injection tests to construct
# the "prior install" witness baseline before each fault is injected.
_seed_prior_install() {
    local version="$1"
    local state_dir="$HOME/.manifest-cli"
    local vdir="$state_dir/runtime/v$version"

    mkdir -p "$vdir/modules/core"
    : > "$vdir/modules/core/marker"
    printf 'sentinel-%s\n' "$version" > "$vdir/modules/core/marker"
    echo "$version" > "$vdir/VERSION"
    # Copy a real core module so the wrapper would actually source through
    # the symlink if invoked.
    cp "$TEST_REPO_ROOT/modules/core/manifest-core.sh" \
        "$vdir/modules/core/manifest-core.sh"

    ln -sfn "runtime/v$version" "$state_dir/current"

    # Install the wrapper so PATH-based discovery succeeds.
    mkdir -p "$MANIFEST_CLI_LOCAL_BIN_TEST"
    cp "$TEST_REPO_ROOT/scripts/manifest-cli-wrapper.sh" \
        "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest"
    chmod +x "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest"
}

# Compute the sha256 of a file (portable across bats hosts).
_sha() {
    shasum -a 256 "$1" | awk '{print $1}'
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

@test "atomic-upgrade: legacy flat layout migrates only shipped subdirs" {
    # Pre-create a pre-§5.7 flat install with one shipped artifact in
    # each allowlist slot plus user-state files at the top level.
    mkdir -p "$HOME/.manifest-cli/modules/core" "$HOME/.manifest-cli/docs" \
             "$HOME/.manifest-cli/logs"
    : > "$HOME/.manifest-cli/modules/core/marker"
    echo "legacy-docs" > "$HOME/.manifest-cli/docs/index.md"
    echo "0.1.0" > "$HOME/.manifest-cli/VERSION"
    echo "preserved-log-sentinel" > "$HOME/.manifest-cli/logs/op.log"
    # Use the shipped example config so the safe-key migration in
    # create_configuration doesn't error.
    cp "$TEST_REPO_ROOT/examples/manifest.config.yaml.example" \
        "$HOME/.manifest-cli/manifest.config.global.yaml"
    printf '# preserved-config-sentinel\n' >> "$HOME/.manifest-cli/manifest.config.global.yaml"

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    # The legacy version dir is created and now holds the relocated
    # shipped artifacts.
    [ -d "$HOME/.manifest-cli/runtime/v0.1.0" ]
    [ -f "$HOME/.manifest-cli/runtime/v0.1.0/modules/core/marker" ]
    [ -f "$HOME/.manifest-cli/runtime/v0.1.0/docs/index.md" ]
    [ -f "$HOME/.manifest-cli/runtime/v0.1.0/VERSION" ]

    # User-state files are NOT moved.
    [ -f "$HOME/.manifest-cli/logs/op.log" ]
    grep -q 'preserved-log-sentinel' "$HOME/.manifest-cli/logs/op.log"
    [ -f "$HOME/.manifest-cli/manifest.config.global.yaml" ]
    grep -q 'preserved-config-sentinel' "$HOME/.manifest-cli/manifest.config.global.yaml"

    # The current symlink exists. After the migration the installer falls
    # through to upgrade flow, so current now points at the NEWLY-staged
    # version dir (the installer's own VERSION); the legacy dir lives
    # alongside it under runtime/.
    [ -L "$HOME/.manifest-cli/current" ]
    [ -d "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}" ]
}

@test "atomic-upgrade: legacy migration is idempotent on a second run" {
    mkdir -p "$HOME/.manifest-cli/modules/core" "$HOME/.manifest-cli/docs"
    : > "$HOME/.manifest-cli/modules/core/marker"
    echo "0.1.0" > "$HOME/.manifest-cli/VERSION"

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    # Run the installer a SECOND time — it should see mode=upgrade now
    # (the legacy modules dir is gone, current is a real symlink) and
    # not re-attempt the migration.
    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    [ -L "$HOME/.manifest-cli/current" ]
    [ -d "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}" ]
    # The legacy version dir is still present (prune_old_versions keeps
    # current + 1 most recent other).
    [ -d "$HOME/.manifest-cli/runtime/v0.1.0" ]
}

@test "atomic-upgrade: legacy migration falls back to 0.0.0-legacy when VERSION absent" {
    mkdir -p "$HOME/.manifest-cli/modules/core"
    : > "$HOME/.manifest-cli/modules/core/marker"
    # NO VERSION file.

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    [ -d "$HOME/.manifest-cli/runtime/v0.0.0-legacy" ]
    [ -f "$HOME/.manifest-cli/runtime/v0.0.0-legacy/modules/core/marker" ]
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

# =============================================================================
# Phase 3: Fault-injection regression suite (§5.7)
#
# These tests use the MANIFEST_CLI_INSTALL_FAIL_AT hook to simulate a
# mid-flight failure at each phase boundary of the atomic-upgrade
# pipeline (stage, swap, prune). The contract under test:
#
#   - Failure BEFORE the symlink swap leaves the prior install fully
#     intact: `current` still points at the old version, modules are
#     readable, the wrapper still runs, shell profiles are unchanged.
#
#   - Failure DURING the swap is itself atomic: rename(2) either ran
#     (current → new) or it didn't (current → old). Never a half-state.
#     The new versioned dir is fully populated; re-running the installer
#     idempotently completes the swap.
#
#   - Failure during PRUNE happens after the atomic moment, so `current`
#     stays at the new version even though prune was best-effort.
#
#   - Concurrent installer runs are blocked by the pidfile lock and do
#     not touch any user state.
#
#   - Stale locks (pid no longer alive) are reclaimed with a warning so
#     a crashed prior installer doesn't permanently block upgrades.
# =============================================================================

@test "fault: stage_version_dir failure preserves prior install" {
    _seed_prior_install "0.0.1"

    # Sentinel ~/.zshrc that must NOT be touched by the failed installer.
    cat > "$HOME/.zshrc" <<'EOF'
# sentinel-zshrc
export PATH="$HOME/.local/bin:$PATH"
EOF

    local zshrc_sha marker_sha wrapper_sha target
    zshrc_sha="$(_sha "$HOME/.zshrc")"
    marker_sha="$(_sha "$HOME/.manifest-cli/runtime/v0.0.1/modules/core/marker")"
    wrapper_sha="$(_sha "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest")"
    target="$(readlink "$HOME/.manifest-cli/current")"
    [ "$target" = "runtime/v0.0.1" ]

    _run_installer_with_fail_at "stage_version_dir"
    [ "$status" -ne 0 ]
    # Fault marker visible on stderr.
    echo "$output" | grep -q "simulated failure at stage_version_dir"

    # current still points at the prior version.
    [ -L "$HOME/.manifest-cli/current" ]
    [ "$(readlink "$HOME/.manifest-cli/current")" = "runtime/v0.0.1" ]

    # Prior version modules untouched.
    [ -r "$HOME/.manifest-cli/runtime/v0.0.1/modules/core/marker" ]
    [ "$(_sha "$HOME/.manifest-cli/runtime/v0.0.1/modules/core/marker")" = "$marker_sha" ]

    # Shell profile untouched.
    [ "$(_sha "$HOME/.zshrc")" = "$zshrc_sha" ]

    # Wrapper still in place and executable.
    [ -x "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest" ]
    [ "$(_sha "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest")" = "$wrapper_sha" ]

    # No leftover .tmp staging dirs from the aborted stage.
    local tmp_count
    tmp_count="$(find "$HOME/.manifest-cli/runtime" -maxdepth 1 -mindepth 1 -name 'v*.tmp' 2>/dev/null | wc -l | tr -d '[:space:]')"
    [ "$tmp_count" = "0" ]

    # Lock released by EXIT trap.
    [ ! -e "$HOME/.manifest-cli/.install.lock" ]

    # Wrapper still resolves the symlink and reaches the prior version's
    # modules — the "still works" sanity check.
    [ -r "$HOME/.manifest-cli/current/modules/core/marker" ]
}

@test "fault: swap_current_symlink failure leaves new version staged but symlink unchanged" {
    _seed_prior_install "0.0.1"

    local wrapper_sha
    wrapper_sha="$(_sha "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest")"

    _run_installer_with_fail_at "swap_current_symlink"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "simulated failure at swap_current_symlink"

    # Stage completed: new version dir exists and has shipped modules.
    [ -d "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}" ]
    [ -r "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}/modules/core/manifest-core.sh" ]

    # current still points at the prior version — swap did NOT happen.
    [ -L "$HOME/.manifest-cli/current" ]
    [ "$(readlink "$HOME/.manifest-cli/current")" = "runtime/v0.0.1" ]

    # Wrapper unchanged (or at most refreshed to the same bytes from the
    # source tree; either way, still executable and resolves the prior
    # symlink target).
    [ -x "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest" ]
    [ -r "$HOME/.manifest-cli/current/modules/core/marker" ]

    # Lock released.
    [ ! -e "$HOME/.manifest-cli/.install.lock" ]

    # Idempotent re-run completes the swap without any fault injection.
    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    # current now points at the staged version; the prior version remains
    # under runtime/.
    [ "$(readlink "$HOME/.manifest-cli/current")" = "runtime/v${INSTALLER_VERSION}" ]
    [ -d "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}" ]

    # No leftover .tmp staging dirs after the successful re-run.
    local tmp_count
    tmp_count="$(find "$HOME/.manifest-cli/runtime" -maxdepth 1 -mindepth 1 -name 'v*.tmp' 2>/dev/null | wc -l | tr -d '[:space:]')"
    [ "$tmp_count" = "0" ]
}

@test "fault: prune_old_versions failure does not roll back the new version" {
    _seed_prior_install "0.0.1"

    # Add a fake older version so prune actually has something to do.
    mkdir -p "$HOME/.manifest-cli/runtime/v0.0.0/modules"
    echo "0.0.0" > "$HOME/.manifest-cli/runtime/v0.0.0/VERSION"
    touch -t 202001010000 "$HOME/.manifest-cli/runtime/v0.0.0"

    _run_installer_with_fail_at "prune_old_versions"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "simulated failure at prune_old_versions"

    # The atomic moment (symlink swap) already passed, so current points
    # at the new version even though prune blew up.
    [ -L "$HOME/.manifest-cli/current" ]
    [ "$(readlink "$HOME/.manifest-cli/current")" = "runtime/v${INSTALLER_VERSION}" ]
    [ -r "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}/modules/core/manifest-core.sh" ]

    # The wrapper still resolves through the new symlink.
    [ -r "$HOME/.manifest-cli/current/modules/core/manifest-core.sh" ]

    # Lock released.
    [ ! -e "$HOME/.manifest-cli/.install.lock" ]
}

@test "fault: lock contention from a live pid blocks the installer and touches no user state" {
    # No prior install — fresh sandbox.
    cat > "$HOME/.zshrc" <<'EOF'
# sentinel-zshrc-pre-contention
export PATH="$HOME/.local/bin:$PATH"
EOF
    local zshrc_sha
    zshrc_sha="$(_sha "$HOME/.zshrc")"

    mkdir -p "$HOME/.manifest-cli"
    # Live-pid lock: our own $$ is by definition alive, so kill -0 succeeds
    # and the installer must treat it as a real concurrent run.
    {
        echo "$$"
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    } > "$HOME/.manifest-cli/.install.lock"

    _run_installer
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "already in progress"

    # Zero user-visible state changes.
    [ ! -d "$HOME/.manifest-cli/runtime" ]
    [ ! -e "$HOME/.manifest-cli/current" ]
    [ ! -e "$MANIFEST_CLI_LOCAL_BIN_TEST/manifest" ]
    [ "$(_sha "$HOME/.zshrc")" = "$zshrc_sha" ]

    # Clean the manual lock so teardown isn't surprised.
    rm -f "$HOME/.manifest-cli/.install.lock"
}

@test "fault: stale lock with a dead pid is reclaimed and install proceeds" {
    mkdir -p "$HOME/.manifest-cli"
    # Pid 99999999 is well above the linux pid_max default and reliably
    # absent on every host that runs this suite — kill -0 fails, so the
    # installer must treat the lock as stale and overwrite it.
    {
        echo "99999999"
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    } > "$HOME/.manifest-cli/.install.lock"

    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    # Stale-lock warning surfaced on stderr (informs the operator).
    echo "$output" | grep -q "stale install lock"

    # Install completed: current symlink is in place and points at the
    # installer's version.
    [ -L "$HOME/.manifest-cli/current" ]
    [ "$(readlink "$HOME/.manifest-cli/current")" = "runtime/v${INSTALLER_VERSION}" ]
    [ -r "$HOME/.manifest-cli/current/modules/core/manifest-core.sh" ]

    # Lock released by the EXIT trap (the stale one was overwritten,
    # ours released cleanly).
    [ ! -e "$HOME/.manifest-cli/.install.lock" ]
}

@test "fault: idempotent re-run after partial stage completes the upgrade" {
    _seed_prior_install "0.0.1"

    # First run: fault injected at swap, leaving a staged-but-unpublished
    # new version on disk.
    _run_installer_with_fail_at "swap_current_symlink"
    [ "$status" -ne 0 ]
    [ -d "$HOME/.manifest-cli/runtime/v${INSTALLER_VERSION}" ]
    [ "$(readlink "$HOME/.manifest-cli/current")" = "runtime/v0.0.1" ]

    # Second run: no fault injection. The installer must notice the
    # already-staged version dir and complete the swap.
    _run_installer
    [ "$status" -eq 0 ] || { echo "$output" >&2; false; }

    [ "$(readlink "$HOME/.manifest-cli/current")" = "runtime/v${INSTALLER_VERSION}" ]
    [ -r "$HOME/.manifest-cli/current/modules/core/manifest-core.sh" ]

    # No duplicate .tmp staging dirs survive the successful re-run.
    local tmp_count
    tmp_count="$(find "$HOME/.manifest-cli/runtime" -maxdepth 1 -mindepth 1 -name 'v*.tmp' 2>/dev/null | wc -l | tr -d '[:space:]')"
    [ "$tmp_count" = "0" ]
}
