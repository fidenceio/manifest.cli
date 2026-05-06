#!/usr/bin/env bats

load 'helpers/setup'

@test "Homebrew formula installs Bash as a required dependency" {
    run grep -F 'depends_on "bash"' "$TEST_REPO_ROOT/formula/manifest.rb"

    [ "$status" -eq 0 ]
    [[ "$output" != *'=> :recommended'* ]]
}

@test "Homebrew wrapper re-execs into Bash 5 before sourcing core modules" {
    run grep -n 'ensure_bash5_or_reexec "$@"' "$TEST_REPO_ROOT/formula/manifest.rb"
    [ "$status" -eq 0 ]
    local guard_line="${output%%:*}"

    run grep -n 'source "$CLI_DIR/modules/core/manifest-core.sh"' "$TEST_REPO_ROOT/formula/manifest.rb"
    [ "$status" -eq 0 ]
    local source_line="${output%%:*}"

    [ "$guard_line" -lt "$source_line" ]
    grep -F '#{Formula["bash"].opt_bin}/bash' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    grep -F 'MANIFEST_CLI_BASH_REEXEC=1 exec "$candidate" "$0" "$@"' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
    ! grep -F 'if [ "${MANIFEST_CLI_BASH_REEXEC:-0}" = "1" ]; then' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
}

@test "Homebrew formula smoke-tests installed status command" {
    grep -F 'system bin/"manifest", "status"' "$TEST_REPO_ROOT/formula/manifest.rb" >/dev/null
}
