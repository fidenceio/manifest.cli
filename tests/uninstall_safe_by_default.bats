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
    echo "$output" | grep -q "Preview - no changes written: manifest uninstall"
    echo "$output" | grep -q "Would remove installation directory: $HOME/.manifest-cli"
    echo "$output" | grep -q "Would remove CLI binary: $HOME/.local/bin/manifest"
    echo "$output" | grep -q "Would remove Manifest entries from shell profile: $HOME/.zshrc"
    echo "$output" | grep -q "manifest uninstall -y"
    [ -d "$HOME/.manifest-cli" ]
    [ -f "$HOME/.local/bin/manifest" ]
    grep -q "MANIFEST_CLI_TEST" "$HOME/.zshrc"
}

@test "uninstall --force still previews unless -y is provided" {
    create_fake_install_artifacts

    run_manifest_from_plain_dir uninstall --force

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Preview - no changes written: manifest uninstall"
    echo "$output" | grep -q "manifest uninstall --force -y"
    [ -d "$HOME/.manifest-cli" ]
    [ -f "$HOME/.local/bin/manifest" ]
}

@test "reinstall defaults to preview and does not remove local artifacts" {
    create_fake_install_artifacts

    run_manifest_from_plain_dir reinstall

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Preview - no changes written: manifest reinstall"
    echo "$output" | grep -q "Would run uninstall cleanup phase"
    echo "$output" | grep -q "Would remove installation directory: $HOME/.manifest-cli"
    echo "$output" | grep -q "Would reinstall"
    echo "$output" | grep -q "manifest reinstall -y"
    [ -d "$HOME/.manifest-cli" ]
    [ -f "$HOME/.local/bin/manifest" ]
}

@test "uninstall --force -y applies only after explicit apply authorization" {
    create_fake_install_artifacts

    run_manifest_from_plain_dir uninstall --force -y

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    echo "$output" | grep -q "Manifest CLI uninstalled successfully"
    [ ! -d "$HOME/.manifest-cli" ]
    [ ! -f "$HOME/.local/bin/manifest" ]
    [ -f "$HOME/.zshrc" ]
    ! grep -q "MANIFEST_CLI_TEST" "$HOME/.zshrc"
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
    echo "$output" | grep -q "Manifest CLI uninstalled successfully"
    echo "$output" | grep -q "CLI binary removed: $HOME/.local/bin/manifest"
    ! echo "$output" | grep -q "$SCRATCH/other-bin/manifest"
}

@test "uninstall and reinstall help advertise preview and apply flags" {
    run_manifest_from_plain_dir uninstall --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "--dry-run"
    echo "$output" | grep -q -- "-y"
    echo "$output" | grep -q -- "--yes"
    echo "$output" | grep -q -- "--force"

    run_manifest_from_plain_dir reinstall --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "--dry-run"
    echo "$output" | grep -q -- "-y"
    echo "$output" | grep -q -- "--yes"
}
