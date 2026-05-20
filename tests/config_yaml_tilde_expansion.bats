#!/usr/bin/env bats
#
# Regression: bash does NOT tilde-expand values read from YAML, so a literal
# "~/.manifest-cli" or "$HOME/.manifest-cli" in a config file would be
# exported into MANIFEST_CLI_* env vars with the leading "~" / literal
# "$HOME" intact. Downstream joins then produce broken paths like
# "$HOME/~/.manifest-cli/...".
#
# This test pins the YAML-side fix: load_yaml_to_env() expands a leading
# "~/" or leading "$HOME/" to the actual value of $HOME before exporting.
# Cases 1-6 exercise the smallest internal helper
# (_manifest_yaml_expand_home_prefix) directly because the loader entry
# point requires a real yq install and a YAML file per case, while the
# helper is what actually implements the rule. Case 7 covers the
# end-to-end loader path.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    # Wipe inherited values so we exercise the loader, not the host env.
    unset MANIFEST_CLI_TEMP_DIR MANIFEST_CLI_INSTALL_DIR MANIFEST_CLI_BIN_DIR
    load_modules
}

@test "leading ~/ is expanded to \$HOME/..." {
    run _manifest_yaml_expand_home_prefix '~/.manifest-cli'
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.manifest-cli" ]
}

@test "leading \$HOME/ is expanded to \$HOME/..." {
    run _manifest_yaml_expand_home_prefix '$HOME/.manifest-cli'
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.manifest-cli" ]
}

@test "absolute path is unchanged" {
    run _manifest_yaml_expand_home_prefix '/etc/something'
    [ "$status" -eq 0 ]
    [ "$output" = "/etc/something" ]
}

@test "relative path is unchanged" {
    run _manifest_yaml_expand_home_prefix 'relative/path'
    [ "$status" -eq 0 ]
    [ "$output" = "relative/path" ]
}

@test "non-path scalar is unchanged" {
    run _manifest_yaml_expand_home_prefix 'not-a-path-at-all'
    [ "$status" -eq 0 ]
    [ "$output" = "not-a-path-at-all" ]
}

@test "bare ~ (no slash) is unchanged — we require ~/ specifically" {
    run _manifest_yaml_expand_home_prefix '~'
    [ "$status" -eq 0 ]
    [ "$output" = "~" ]
}

@test "load_yaml_to_env expands ~/.manifest-cli on install.temp_dir" {
    # Skip if yq is unavailable — the loader's parser requirement is hard.
    command -v yq >/dev/null 2>&1 || skip "yq not installed"

    local cfg="$SCRATCH/manifest.yaml"
    cat > "$cfg" <<'YAML'
install:
  temp_dir: "~/.manifest-cli"
YAML

    # NOTE: `run` executes in a subshell, so any env vars exported by
    # load_yaml_to_env would die with that subshell. Call directly.
    load_yaml_to_env "$cfg"
    [ "$MANIFEST_CLI_TEMP_DIR" = "$HOME/.manifest-cli" ]
    case "$MANIFEST_CLI_TEMP_DIR" in *'~'*) return 1 ;; esac
}
