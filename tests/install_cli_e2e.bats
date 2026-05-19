#!/usr/bin/env bats
#
# End-to-end verification that install-cli.sh, run non-interactively into
# an isolated HOME with brew stubbed out, produces the canonical set of
# install artifacts. Locks in the contract that the Cloud plugin's
# (now-deleted) install_cli was supposed to satisfy.
#
# Skipped on hosts that lack the bash 5 / yq / git toolchain — the
# installer itself rejects those hosts at validate_system time, so the
# test would fail for reasons unrelated to the install pipeline.

load 'helpers/setup'

setup() {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed on host"
    fi
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    # Pre-populate $HOME/.local/bin in PATH so configure_path skips its prompt.
    export MANIFEST_CLI_LOCAL_BIN_TEST="$HOME/.local/bin"
    mkdir -p "$MANIFEST_CLI_LOCAL_BIN_TEST"
    export PATH="$MANIFEST_CLI_LOCAL_BIN_TEST:$PATH"

    # Build a tool dir with symlinks to required real tools (git, yq, bash,
    # coreutils' timeout) plus stubs for docker (engine "running") and explicit
    # absence of brew so install-cli.sh's non-brew branch fires.
    export TOOL_DIR="$SCRATCH/tools"
    mkdir -p "$TOOL_DIR"
    local tool resolved
    for tool in git yq gtimeout timeout bash curl; do
        resolved="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v "$tool" 2>/dev/null || true)"
        [ -n "$resolved" ] && ln -sf "$resolved" "$TOOL_DIR/$tool"
    done
    # Docker stub — `docker` exists and `docker info` returns 0 (engine running).
    cat > "$TOOL_DIR/docker" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
    chmod +x "$TOOL_DIR/docker"
    # Filter brew out of PATH (and *only* expose TOOL_DIR + a sysroot floor)
    # so install-cli.sh sees no brew and takes the manual-install path.
    export PATH="$TOOL_DIR:/usr/bin:/bin"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "install-cli.sh non-brew run produces canonical artifacts under sandbox HOME" {
    # Trick install-cli.sh into thinking we're on Linux so the macOS-Homebrew
    # prompt branch in main() doesn't fire.
    cd "$TEST_REPO_ROOT"

    OSTYPE=linux-gnu run env \
        HOME="$HOME" \
        PATH="$PATH" \
        OSTYPE=linux-gnu \
        bash "$TEST_REPO_ROOT/install-cli.sh" < /dev/null

    if [ "$status" -ne 0 ]; then
        echo "install-cli.sh exited $status. Output:" >&2
        echo "$output" >&2
    fi
    [ "$status" -eq 0 ]

    # Canonical artifact set after a successful non-brew install:
    [ -x "$HOME/.local/bin/manifest" ]
    grep -q -E 'Manifest CLI|manifest-cli|MANIFEST_CLI' "$HOME/.local/bin/manifest"

    [ -d "$HOME/.manifest-cli" ]
    [ -d "$HOME/.manifest-cli/modules" ]
    [ -d "$HOME/.manifest-cli/modules/core" ]
    [ -d "$HOME/.manifest-cli/modules/system" ]
    [ -f "$HOME/.manifest-cli/manifest.config.global.yaml" ]

    # The plugin's old install_cli used to skip these; the canonical pipeline
    # produces them. Their presence is the regression-prevention check.
    [ -d "$HOME/.manifest-cli/docs" ]
    [ -d "$HOME/.manifest-cli/examples" ]
}

@test "installed bin script preserves install-paths module" {
    cd "$TEST_REPO_ROOT"
    OSTYPE=linux-gnu env \
        HOME="$HOME" \
        PATH="$PATH" \
        OSTYPE=linux-gnu \
        bash "$TEST_REPO_ROOT/install-cli.sh" < /dev/null >/dev/null 2>&1 || {
            skip "install-cli.sh failed in setup; covered by the previous test"
        }

    # Manifest-install-paths.sh must end up under the installed modules tree
    # — otherwise reinstall/uninstall flows running from $HOME/.manifest-cli
    # break.
    [ -f "$HOME/.manifest-cli/modules/system/manifest-install-paths.sh" ]
    [ -f "$HOME/.manifest-cli/modules/system/manifest-uninstall.sh" ]
}
