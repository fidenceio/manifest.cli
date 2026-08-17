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
    refute grep -q "Findings:" <<<"$output"
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
    # ...alongside untouched defaults. Uses a default that is actually READ by
    # the CLI: this line previously asserted "Format: XX.XX.XX", a key nothing
    # consumes, so it proved only that a string reached the screen.
    echo "$output" | grep -q "Separator: \."
    echo "$output" | grep -q "Tag Prefix: v"
    echo "$output" | grep -q "Server 1: https://www.cloudflare.com/cdn-cgi/trace"
    echo "$output" | grep -q "Auto-Upgrade: true"

    # The fifteen keys nothing read are GONE, not merely relabelled.
    # `config show` used to state "Major Target: 1 (which component increments)"
    # for a value the arithmetic has never consulted; an interim build listed
    # them under "Declared but NOT in force". Neither should survive.
    echo "$output" | grep -q "Segment Mapping"
    refute grep -q "which component increments" <<<"$output"
    refute grep -q "components reset to 0" <<<"$output"
    refute grep -q "Declared but NOT in force" <<<"$output"
    refute grep -qE "version\.(format|max_values|component_position|increment_target|reset_components)" <<<"$output"

    # version.validation read "Version Validation: true" while
    # validate_version_format() ran unconditionally — an opt-out that never
    # existed. Its live neighbour version.regex supplies that function's
    # pattern and must survive: retiring the wrong one of the pair would drop a
    # real setting.
    refute grep -q "Version Validation" <<<"$output"
    echo "$output" | grep -q "Version Regex:"
}

@test "show_configuration: segment mapping is derived, so renaming components moves it" {
    export MANIFEST_CLI_VERSION_COMPONENTS="generation,major,minor,patch"
    set_default_configuration
    run show_configuration
    [ "$status" -eq 0 ]
    # The whole point of the removal: position comes from the list, with no second key
    # able to contradict it.
    echo "$output" | grep -q "generation: segment 1"
    echo "$output" | grep -q "major: segment 2"
}

# -----------------------------------------------------------------------------
# Retired keys — an existing config that still carries them
# -----------------------------------------------------------------------------

write_retired_key_config() {
    cat > "$CFG" <<'YAML'
time:
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600
config:
  schema_version: 2
version:
  separator: "."
  components: "major,minor,patch,revision"
  regex: "^[0-9]+(\\.[0-9]+)*$"
  format: "XX.XX.XX"
  max_values: "0,0,0"
  validation: true
  component_position:
    major: 1
    minor: 2
  increment_target:
    major: 1
  reset_components:
    major: "2,3,4"
YAML
}

@test "config doctor: names retired version.* keys instead of ignoring them" {
    write_retired_key_config
    run config_doctor --file "$CFG"
    [ "$status" -eq 0 ]
    # The loader skips unmapped paths silently; without this the user would
    # never learn the keys stopped meaning anything.
    echo "$output" | grep -q "OBSOLETE: version.format is set but no longer exists"
    echo "$output" | grep -q "OBSOLETE: version.max_values"
    echo "$output" | grep -q "OBSOLETE: version.component_position"
    echo "$output" | grep -q "OBSOLETE: version.increment_target"
    echo "$output" | grep -q "OBSOLETE: version.reset_components"
    echo "$output" | grep -q "OBSOLETE: version.validation"
    # Read-only: still on disk.
    [ "$(yq e '.version.format' "$CFG")" = "XX.XX.XX" ]
}

@test "config doctor: live version keys are never reported as retired" {
    write_retired_key_config
    run config_doctor --file "$CFG"
    [ "$status" -eq 0 ]
    # version.regex sits directly beside the retired version.validation and IS
    # read by validate_version_format(); reporting it would be a false positive
    # that leads a user to delete a real setting.
    refute grep -q "OBSOLETE: version.regex" <<<"$output"
    refute grep -q "OBSOLETE: version.separator" <<<"$output"
    refute grep -q "OBSOLETE: version.components" <<<"$output"
}

@test "config doctor --fix (no -y): previews the removal, deletes nothing" {
    write_retired_key_config
    run config_doctor --fix --file "$CFG"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would-remove|version.format||"
    echo "$output" | grep -q "would-remove|version.component_position||"
    [ "$(yq e '.version.format' "$CFG")" = "XX.XX.XX" ]
    [ -z "$(find "$SCRATCH" -maxdepth 1 -name 'cfg.yaml.bak.*' -print -quit)" ]
}

@test "config doctor --fix -y: deletes retired keys whole and keeps the live ones" {
    write_retired_key_config
    run config_doctor --fix --file "$CFG" -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "removed|version.format||"

    [ "$(yq e '.version.format' "$CFG")" = "null" ]
    [ "$(yq e '.version.max_values' "$CFG")" = "null" ]
    # Deleted at the FAMILY level: a per-leaf delete would leave
    # `component_position: {}` behind, which reads as blank config, not absent.
    [ "$(yq e '.version.component_position' "$CFG")" = "null" ]
    [ "$(yq e '.version.increment_target' "$CFG")" = "null" ]
    [ "$(yq e '.version.reset_components' "$CFG")" = "null" ]
    [ "$(yq e '.version.validation' "$CFG")" = "null" ]

    # The keys that are actually read survive untouched — including
    # version.regex, whose retired neighbour version.validation was removed in
    # the same pass.
    [ "$(yq e '.version.separator' "$CFG")" = "." ]
    [ "$(yq e '.version.components' "$CFG")" = "major,minor,patch,revision" ]
    [ "$(yq e '.version.regex' "$CFG")" != "null" ]

    # §8.4b: pre-migration snapshot still holds the removed values.
    local backup
    backup="$(find "$SCRATCH" -maxdepth 1 -name 'cfg.yaml.bak.*' -print -quit)"
    [ -n "$backup" ]
    [ "$(yq e '.version.format' "$backup")" = "XX.XX.XX" ]
}

@test "config doctor: a config with no retired keys reports clean" {
    write_clean_config
    run config_doctor --file "$CFG"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "✅ No configuration drift detected."
    refute grep -q "OBSOLETE" <<<"$output"
}

@test "config doctor --fix -y: an emptied version section is pruned, not left blank" {
    # A config whose entire version section is retired keys — the shape the old
    # installer produced. Deleting the children must not leave `version: {}`,
    # which reads as configuration that is merely blank rather than absent.
    cat > "$CFG" <<'YAML'
time:
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600
config:
  schema_version: 2
version:
  format: "XX.XX.XX"
  component_position:
    major: 3
YAML
    run config_doctor --fix --file "$CFG" -y
    [ "$status" -eq 0 ]
    [ "$(yq e '.version' "$CFG")" = "null" ]
    refute grep -q "version: {}" "$CFG"
    # Unrelated sections are untouched.
    [ "$(yq e '.time.cache_ttl' "$CFG")" = "120" ]
}

@test "config doctor --fix -y: a version section keeping live keys is NOT pruned" {
    write_retired_key_config
    run config_doctor --fix --file "$CFG" -y
    [ "$status" -eq 0 ]
    [ "$(yq e '.version.separator' "$CFG")" = "." ]
    [ "$(yq e '.version.components' "$CFG")" = "major,minor,patch,revision" ]
}

@test "auto-migration: retired keys alone are not drift, so users are not nagged" {
    # install-cli.sh seeded version.format into every global config it ever
    # wrote, so counting obsolete keys as drift would warn nearly every existing
    # user about something that cannot change a release outcome.
    write_retired_key_config
    export MANIFEST_CLI_CONFIG_MIGRATION_COOLDOWN_MINUTES=0
    export MANIFEST_CLI_GLOBAL_CONFIG="$CFG"
    run auto_migrate_user_global_configuration
    [ "$status" -eq 0 ]
    refute grep -q "Configuration drift detected" <<<"$output"
    # Untouched on disk: warn-only would still be a mutation-free path, but this
    # pins that no silent delete happened either.
    [ "$(yq e '.version.format' "$CFG")" = "XX.XX.XX" ]
}

@test "installer: the seeded global config carries no retired version keys" {
    # Regression: the installer template wrote `version.format`, so every fresh
    # install would have been born already flagged by config doctor.
    local installer="$BATS_TEST_DIRNAME/../install-cli.sh"
    [ -f "$installer" ]
    refute grep -qE '^[[:space:]]*(format|max_values|component_position|increment_target|reset_components):' "$installer"
    grep -qE '^[[:space:]]*components: "major,minor,patch,revision"' "$installer"
}

@test "config set/get: a retired key is rejected, not written as inert YAML" {
    load_modules "core/manifest-config-crud.sh"
    run _cfg_normalize_key "version.format"
    [ "$status" -ne 0 ]
    run _cfg_normalize_key "version.separator"
    [ "$status" -eq 0 ]
    [ "$output" = "version.separator" ]
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
