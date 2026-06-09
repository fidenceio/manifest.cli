#!/usr/bin/env bats

load 'helpers/setup'

@test "Homebrew formula template installs Bash as a required dependency" {
    run grep -F 'depends_on "bash"' "$TEST_REPO_ROOT/formula/manifest.rb"

    [ "$status" -eq 0 ]
    [[ "$output" != *'=> :recommended'* ]]
}

@test "Homebrew formula template installs coreutils as a required dependency" {
    run grep -F 'depends_on "coreutils"' "$TEST_REPO_ROOT/formula/manifest.rb"

    [ "$status" -eq 0 ]
    [[ "$output" != *'=> :optional'* ]]
}

@test "Homebrew wrapper re-execs into Bash 5 before sourcing core modules" {
    run grep -n 'ensure_bash5_or_reexec "$@"' "$TEST_REPO_ROOT/formula/manifest.rb"
    [ "$status" -eq 0 ]
    local guard_line="${output%%:*}"

    run grep -n 'source "$CLI_DIR/modules/core/manifest-core.sh"' "$TEST_REPO_ROOT/formula/manifest.rb"
    [ "$status" -eq 0 ]
    local source_line="${output%%:*}"

    [ "$guard_line" -lt "$source_line" ]
    # The bash-candidate list must be fully static — no build-time #{...}
    # interpolation — so install output is byte-identical across platforms and a
    # single :all bottle is valid (lets brew upgrade skip the source-build gate).
    ! grep -F '#{Formula["bash"].opt_bin}' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    grep -F '/opt/homebrew/bin/bash' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    grep -F '/home/linuxbrew/.linuxbrew/bin/bash' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    grep -F 'MANIFEST_CLI_BASH_REEXEC=1 exec "$candidate" "$0" "$@"' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    ! grep -F 'if [ "${MANIFEST_CLI_BASH_REEXEC:-0}" = "1" ]; then' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
}

@test "Homebrew formula template smoke-tests installed status command" {
    grep -F 'system bin/"manifest", "status"' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
}

@test "Homebrew formula template installs shell completions" {
    grep -F 'bash_completion.install libexec/"completions/manifest.bash" => "manifest"' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    grep -F 'zsh_completion.install libexec/"completions/_manifest"' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
}

@test "Homebrew formula template caveats describe uninstall preview and apply commands" {
    grep -F 'To preview a clean uninstall:' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    grep -F 'To uninstall cleanly (removes config and env vars too):' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    grep -F 'manifest uninstall -y' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
}
