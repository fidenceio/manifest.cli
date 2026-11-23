#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest_from_plain_dir() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

create_fake_install_artifacts() {
    mkdir -p "$HOME/.manifest-cli" "$HOME/.local/bin"
    printf 'schema_version: 1\n' > "$HOME/.manifest-cli/manifest.config.global.yaml"
    printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/manifest"
    chmod +x "$HOME/.local/bin/manifest"
    printf 'export MANIFEST_CLI_TEST=1\n' > "$HOME/.zshrc"
}

@test "uninstall defaults to preview and does not remove local artifacts" {
    create_fake_install_artifacts

    run_manifest_from_plain_dir uninstall

    [ "$status" -eq 0 ]
    grep -q "Preview - no changes written: manifest uninstall" <<<"$output"
    grep -q "Would remove installation directory: $HOME/.manifest-cli" <<<"$output"
    grep -q "Would remove CLI binary: $HOME/.local/bin/manifest" <<<"$output"
    grep -q "Would remove Manifest entries from shell profile: $HOME/.zshrc" <<<"$output"
    grep -q "manifest uninstall -y" <<<"$output"
    [ -d "$HOME/.manifest-cli" ]
    [ -f "$HOME/.local/bin/manifest" ]
    grep -q "MANIFEST_CLI_TEST" "$HOME/.zshrc"
}

@test "uninstall --force still previews unless -y is provided" {
    create_fake_install_artifacts

    run_manifest_from_plain_dir uninstall --force

    [ "$status" -eq 0 ]
    grep -q "Preview - no changes written: manifest uninstall" <<<"$output"
    grep -q "manifest uninstall --force -y" <<<"$output"
    [ -d "$HOME/.manifest-cli" ]
    [ -f "$HOME/.local/bin/manifest" ]
}

@test "reinstall defaults to preview and does not remove local artifacts" {
    create_fake_install_artifacts

    run_manifest_from_plain_dir reinstall

    [ "$status" -eq 0 ]
    grep -q "Preview - no changes written: manifest reinstall" <<<"$output"
    grep -q "Would run uninstall cleanup phase" <<<"$output"
    grep -q "Would remove installation directory: $HOME/.manifest-cli" <<<"$output"
    grep -q "Would reinstall" <<<"$output"
    grep -q "manifest reinstall -y" <<<"$output"
    [ -d "$HOME/.manifest-cli" ]
    [ -f "$HOME/.local/bin/manifest" ]
}

@test "uninstall --force -y applies only after explicit apply authorization" {
    create_fake_install_artifacts

    run_manifest_from_plain_dir uninstall --force -y

    [ "$status" -eq 0 ]
    grep -q "Applying because -y/--yes was provided." <<<"$output"
    grep -q "Manifest CLI uninstalled successfully" <<<"$output"
    [ ! -d "$HOME/.manifest-cli" ]
    [ ! -f "$HOME/.local/bin/manifest" ]
    [ -f "$HOME/.zshrc" ]
    refute grep -q "MANIFEST_CLI_TEST" "$HOME/.zshrc"
}

@test "uninstall removes manual shell-completion files (both channels swept)" {
    create_fake_install_artifacts
    # Manual-install completion files the installer writes — historically left
    # behind on uninstall. They live under the sandbox HOME so removal is in-scope.
    local bash_comp="$HOME/.local/share/bash-completion/completions/manifest"
    local zsh_comp="$HOME/.zsh/completions/_manifest"
    mkdir -p "$(dirname "$bash_comp")" "$(dirname "$zsh_comp")"
    : > "$bash_comp"
    : > "$zsh_comp"

    run_manifest_from_plain_dir uninstall --force -y

    [ "$status" -eq 0 ]
    grep -q "Manifest CLI uninstalled successfully" <<<"$output"
    [ ! -e "$bash_comp" ]
    [ ! -e "$zsh_comp" ]
}

@test "uninstall ignores unrelated manifest executable on PATH" {
    create_fake_install_artifacts
    mkdir -p "$SCRATCH/other-bin"
    printf '#!/usr/bin/env bash\necho unrelated\n' > "$SCRATCH/other-bin/manifest"
    chmod +x "$SCRATCH/other-bin/manifest"
    PATH="$SCRATCH/other-bin:$PATH"
    export PATH

    run_manifest_from_plain_dir uninstall --force -y

    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/other-bin/manifest" ]
    grep -q "Manifest CLI uninstalled successfully" <<<"$output"
    grep -q "CLI binary removed: $HOME/.local/bin/manifest" <<<"$output"
    refute grep -q "$SCRATCH/other-bin/manifest" <<<"$output"
}

@test "uninstall and reinstall help advertise preview and apply flags" {
    run_manifest_from_plain_dir uninstall --help
    [ "$status" -eq 0 ]
    grep -q -- "--dry-run" <<<"$output"
    grep -q -- "-y" <<<"$output"
    grep -q -- "--yes" <<<"$output"
    grep -q -- "--force" <<<"$output"

    run_manifest_from_plain_dir reinstall --help
    [ "$status" -eq 0 ]
    grep -q -- "--dry-run" <<<"$output"
    grep -q -- "-y" <<<"$output"
    grep -q -- "--yes" <<<"$output"
}
