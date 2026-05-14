#!/usr/bin/env bats

load 'helpers/setup'

@test "requirements centralize Docker availability checks" {
    load_modules

    [ "$MANIFEST_CLI_REQUIRED_DOCKER_COMMAND" = "docker" ]
    [ -n "$MANIFEST_CLI_REQUIRED_DOCKER_LABEL" ]
    [ -n "$MANIFEST_CLI_REQUIRED_COREUTILS_LABEL" ]

    declare -F manifest_requirement_docker_command_exists >/dev/null
    declare -F manifest_requirement_docker_engine_is_running >/dev/null
    declare -F manifest_requirement_coreutils_timeout_command >/dev/null
}

@test "requirements preserve Bash 5 and Mike Farah yq as runtime contract" {
    load_modules

    [ "$MANIFEST_CLI_REQUIRED_BASH_MAJOR" = "5" ]
    [ "$MANIFEST_CLI_REQUIRED_YQ_MAJOR" = "4" ]
    [[ "$MANIFEST_CLI_REQUIRED_YQ_VENDOR" == *"github.com/mikefarah/yq"* ]]

    grep -F '| Bash | 5.0+ |' "$TEST_REPO_ROOT/README.md" >/dev/null
    grep -F '| yq | 4.0+ (Mike Farah' "$TEST_REPO_ROOT/README.md" >/dev/null
    grep -F '| coreutils | Any |' "$TEST_REPO_ROOT/README.md" >/dev/null
    ! grep -F 'MANIFEST_CLI_REQUIRED_SCRIPT' "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh" >/dev/null
}

@test "OS detection never installs host dependencies during runtime setup" {
    ! grep -F 'brew install coreutils' "$TEST_REPO_ROOT/modules/system/manifest-os.sh" >/dev/null
    grep -F 'using fallback timeout method' "$TEST_REPO_ROOT/modules/system/manifest-os.sh" >/dev/null
    grep -F 'Install coreutils for the supported macOS timeout command' "$TEST_REPO_ROOT/modules/system/manifest-os.sh" >/dev/null
}

@test "installer handles Homebrew before Docker before final validation" {
    local homebrew_line docker_line validate_line

    run grep -n "# On macOS, offer to install Homebrew" "$TEST_REPO_ROOT/install-cli.sh"
    [ "$status" -eq 0 ]
    homebrew_line="${output%%:*}"

    run grep -n "^[[:space:]]*ensure_docker_installed$" "$TEST_REPO_ROOT/install-cli.sh"
    [ "$status" -eq 0 ]
    docker_line="${output%%:*}"

    run grep -n "^[[:space:]]*validate_system$" "$TEST_REPO_ROOT/install-cli.sh"
    [ "$status" -eq 0 ]
    validate_line="${output%%:*}"

    [ "$homebrew_line" -lt "$docker_line" ]
    [ "$docker_line" -lt "$validate_line" ]
}

@test "installer offers Docker Desktop through Homebrew cask on macOS" {
    grep -F 'brew install --cask docker' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'Install Docker Desktop now?' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'open -a Docker' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
}

@test "installer sets up shell completions for IDE integrated terminals" {
    grep -F 'Copy shell completions' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'install_shell_completions' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'etc/bash_completion.d/manifest' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'share/zsh/site-functions/_manifest' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
}

@test "installer writes IDE and AI assistant command catalogs" {
    grep -F 'install_ide_command_catalog' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'manifest-cli-commands.md' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'manifest-cli-commands.json' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'AGENTS.md' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'CLAUDE.md' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'Mutating commands preview by default.' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
}
