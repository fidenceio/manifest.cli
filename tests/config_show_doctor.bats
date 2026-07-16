#!/usr/bin/env bats

# Coverage for manifest-config.sh's user-facing views: config_doctor (missing
# file, drift findings, --fix preview vs --fix -y apply, clean verdict),
# show_configuration (renders effective values including overrides), and
# configure_interactive's non-TTY refusal.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    # HOME must be isolated before sourcing: manifest-config.sh resolves
    # MANIFEST_CLI_GLOBAL_CONFIG from $HOME at source time.
    load_modules "core/manifest-config.sh"
    CFG="$SCRATCH/cfg.yaml"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_GIT_DEFAULT_BRANCH MANIFEST_CLI_PROJECT_ROOT
}

write_legacy_config() {
    cat > "$CFG" <<'YAML'
time:
  server1: time.apple.com
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600
config:
  schema_version: 2
YAML
}

write_clean_config() {
    cat > "$CFG" <<'YAML'
time:
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600
config:
  schema_version: 2
YAML
}

# -----------------------------------------------------------------------------
# config doctor
# -----------------------------------------------------------------------------

@test "config doctor: missing config file is a hard, guided failure" {
    run config_doctor
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Config file not found: $HOME/.manifest-cli/manifest.config.global.yaml"
    echo "$output" | grep -q "manifest config setup"
}

@test "config doctor --file: reports legacy drift without mutating the file" {
    write_legacy_config
    run config_doctor --file "$CFG"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Manifest Config Doctor"
    echo "$output" | grep -q "Config file: $CFG"
    echo "$output" | grep -q "LEGACY: time.server1 uses 'time.apple.com' (recommended: 'https://www.cloudflare.com/cdn-cgi/trace')"
    echo "$output" | grep -q "Run 'manifest config doctor --fix' to apply safe migrations."
    # Read-only: the legacy value is still on disk.
    [ "$(yq e '.time.server1' "$CFG")" = "time.apple.com" ]
}

@test "config doctor --file --fix (no -y): previews the migration, writes nothing" {
    write_legacy_config
    run config_doctor --fix --file "$CFG"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Migration plan:"
    echo "$output" | grep -q "would-update|time.server1|time.apple.com|https://www.cloudflare.com/cdn-cgi/trace"
    echo "$output" | grep -q "Preview complete. Re-run with --fix -y to apply."
    [ "$(yq e '.time.server1' "$CFG")" = "time.apple.com" ]
    # No backup is taken for a preview.
    [ -z "$(find "$SCRATCH" -maxdepth 1 -name 'cfg.yaml.bak.*' -print -quit)" ]
}

@test "config doctor --file --fix -y: applies the migration and backs up first" {
    write_legacy_config
    run config_doctor --fix --file "$CFG" -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    echo "$output" | grep -q "updated|time.server1|time.apple.com|https://www.cloudflare.com/cdn-cgi/trace"
    echo "$output" | grep -q "✅ Safe migrations applied."
    [ "$(yq e '.time.server1' "$CFG")" = "https://www.cloudflare.com/cdn-cgi/trace" ]
    # §8.4b: the pre-migration snapshot exists and preserves the old value.
    local backup
    backup="$(find "$SCRATCH" -maxdepth 1 -name 'cfg.yaml.bak.*' -print -quit)"
    [ -n "$backup" ]
    [ "$(yq e '.time.server1' "$backup")" = "time.apple.com" ]
}

@test "config doctor --file: clean config reports no drift" {
    write_clean_config
    run config_doctor --file "$CFG"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "✅ No configuration drift detected."
    ! echo "$output" | grep -q "Findings:"
}

# -----------------------------------------------------------------------------
# show_configuration
# -----------------------------------------------------------------------------

@test "show_configuration: renders defaults and honors env overrides" {
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=trunk
    set_default_configuration
    run show_configuration
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Manifest CLI Configuration"
    # Override is reflected...
    echo "$output" | grep -q "Default Branch: trunk"
    # ...alongside untouched defaults.
    echo "$output" | grep -q "Format: XX.XX.XX"
    echo "$output" | grep -q "Tag Prefix: v"
    echo "$output" | grep -q "Server 1: https://www.cloudflare.com/cdn-cgi/trace"
    echo "$output" | grep -q "Auto-Upgrade: true"
}

# -----------------------------------------------------------------------------
# configure_interactive (wizard)
# -----------------------------------------------------------------------------

@test "configure_interactive: refuses without a TTY and points at config show" {
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    run configure_interactive < /dev/null
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Interactive config requires a TTY. Use: manifest config show"
    [ ! -f "$SCRATCH/manifest.config.local.yaml" ]
}
