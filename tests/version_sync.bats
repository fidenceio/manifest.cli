#!/usr/bin/env bats
#
# §7.2: opt-in package.json (JSON) version-sync. On a bump, VERSION stays
# canonical and each file listed in `version.sync` has its top-level "version"
# value mirrored via a surgical sed (no jq reserialize → minimal diff, existing
# formatting preserved). Fail-closed: missing file or missing field is skipped,
# never created. Non-JSON targets are recognized but skipped (JSON only, first cut).

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH"
    cd "$SCRATCH"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

write_version() { echo "$1" > VERSION; }

# --- splitter ----------------------------------------------------------------

@test "version-sync: splitter parses a comma-separated string and trims" {
    export MANIFEST_CLI_VERSION_SYNC="package.json , sub/app.json"
    run _manifest_version_sync_targets
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "package.json" ]
    [ "${lines[1]}" = "sub/app.json" ]
}

@test "version-sync: splitter emits nothing when unset (opt-in)" {
    unset MANIFEST_CLI_VERSION_SYNC
    run _manifest_version_sync_targets
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "version-sync: splitter accepts a bash array" {
    MANIFEST_CLI_VERSION_SYNC=("package.json" "app/package.json")
    run _manifest_version_sync_targets
    [ "${lines[0]}" = "package.json" ]
    [ "${lines[1]}" = "app/package.json" ]
}

# --- surgical apply via bump_version -----------------------------------------

@test "version-sync: bump mirrors the version into package.json, surgically" {
    write_version "1.2.3"
    cat > package.json <<'JSON'
{
  "name": "demo",
  "version": "1.2.3",
  "scripts": {
    "build": "tsc"
  }
}
JSON
    export MANIFEST_CLI_VERSION_SYNC="package.json"
    run bump_version "minor"
    [ "$status" -eq 0 ]
    [ "$(cat VERSION)" = "1.3.0" ]

    # Version mirrored; sibling data preserved.
    [ "$(jq -r '.version' package.json)" = "1.3.0" ]
    [ "$(jq -r '.name' package.json)" = "demo" ]
    [ "$(jq -r '.scripts.build' package.json)" = "tsc" ]

    # Surgical, not reserialized: original 2-space indentation and trailing
    # commas are intact (jq would have reflowed the whole file).
    grep -q '^  "version": "1.3.0",$' package.json
    grep -q '^  "name": "demo",$' package.json
}

@test "version-sync: only the first (top-level) version value is rewritten" {
    write_version "1.0.0"
    cat > package.json <<'JSON'
{
  "version": "1.0.0",
  "bundledDep": {
    "version": "9.9.9"
  }
}
JSON
    export MANIFEST_CLI_VERSION_SYNC="package.json"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.version' package.json)" = "1.0.1" ]
    [ "$(jq -r '.bundledDep.version' package.json)" = "9.9.9" ]
}

@test "version-sync: a missing target is skipped, not created (fail-closed)" {
    write_version "1.0.0"
    export MANIFEST_CLI_VERSION_SYNC="package.json"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    [ ! -f package.json ]
}

@test "version-sync: a JSON file with no version field is left untouched (fail-closed)" {
    write_version "1.0.0"
    printf '{"name":"x"}' > config.json
    export MANIFEST_CLI_VERSION_SYNC="config.json"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    [ "$(cat config.json)" = '{"name":"x"}' ]
}

@test "version-sync: a non-JSON target is recognized but skipped (JSON only)" {
    write_version "1.0.0"
    printf 'version = "1.0.0"\n' > pyproject.toml
    export MANIFEST_CLI_VERSION_SYNC="pyproject.toml"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "not yet supported"
    [ "$(cat pyproject.toml)" = 'version = "1.0.0"' ]
}

@test "version-sync: no sync targets leaves a stray package.json alone" {
    write_version "1.0.0"
    cat > package.json <<'JSON'
{
  "version": "0.0.0"
}
JSON
    unset MANIFEST_CLI_VERSION_SYNC
    run bump_version "patch"
    [ "$status" -eq 0 ]
    # Opt-in: untouched because version.sync was not set.
    [ "$(jq -r '.version' package.json)" = "0.0.0" ]
}

# --- §7.7: depth-aware targeting + semver guard ------------------------------

@test "version-sync: a nested 'version' that sorts BEFORE the top-level one is not mistaken for it (§7.7)" {
    write_version "1.0.0"
    # The corruption case: the FIRST "version": line is the nested one. The old
    # 1,/"version":/ range rewrote it; depth-aware targeting must skip it.
    cat > package.json <<'JSON'
{
  "bundledDep": {
    "version": "9.9.9"
  },
  "version": "1.0.0"
}
JSON
    export MANIFEST_CLI_VERSION_SYNC="package.json"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.version' package.json)" = "1.0.1" ]
    [ "$(jq -r '.bundledDep.version' package.json)" = "9.9.9" ]
}

@test "version-sync: braces inside a string value don't skew depth detection (§7.7)" {
    write_version "2.0.0"
    cat > package.json <<'JSON'
{
  "description": "uses {curly} and [square] brackets and a : colon",
  "nested": { "version": "9.9.9" },
  "version": "2.0.0"
}
JSON
    export MANIFEST_CLI_VERSION_SYNC="package.json"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.version' package.json)" = "2.0.1" ]
    [ "$(jq -r '.nested.version' package.json)" = "9.9.9" ]
    [ "$(jq -r '.description' package.json)" = "uses {curly} and [square] brackets and a : colon" ]
}

@test "version-sync: a JSON file with only a nested version (no top-level) is left untouched (§7.7)" {
    write_version "1.0.0"
    cat > package.json <<'JSON'
{
  "bundledDep": {
    "version": "9.9.9"
  }
}
JSON
    export MANIFEST_CLI_VERSION_SYNC="package.json"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "no top-level"
    [ "$(jq -r '.bundledDep.version' package.json)" = "9.9.9" ]
}

@test "version-sync: refuses an unsafe (non-semver) version string, leaving the file untouched (§7.7)" {
    cat > package.json <<'JSON'
{
  "version": "1.0.0"
}
JSON
    export MANIFEST_CLI_VERSION_SYNC="package.json"
    # A "/" in the value would corrupt the sed substitution; the guard refuses it.
    run manifest_version_sync_apply 'a/b&c'
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "unsafe"
    [ "$(jq -r '.version' package.json)" = "1.0.0" ]
}
