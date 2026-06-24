#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-discovery.sh" "core/manifest-version-surfaces.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# -----------------------------------------------------------------------------
# Low-level helpers
# -----------------------------------------------------------------------------

@test "_json_escape: passes ASCII through untouched" {
    run _json_escape "hello world"
    [ "$output" = "hello world" ]
}

@test "_json_escape: escapes embedded double quotes" {
    run _json_escape 'a "b" c'
    [ "$output" = 'a \"b\" c' ]
}

@test "_json_escape: escapes backslashes before quotes" {
    run _json_escape 'a\b'
    [ "$output" = 'a\\b' ]
}

@test "_json_escape: escapes embedded newlines and tabs" {
    local v
    v=$'a\nb\tc'
    run _json_escape "$v"
    [ "$output" = 'a\nb\tc' ]
}

@test "_json_value: classifies booleans/null as raw" {
    run _json_value "true";  [ "$output" = "true" ]
    run _json_value "false"; [ "$output" = "false" ]
    run _json_value "null";  [ "$output" = "null" ]
}

@test "_json_value: classifies plain integers as numbers" {
    run _json_value "42"
    [ "$output" = "42" ]
}

@test "_json_value: quotes regular strings" {
    run _json_value "hello"
    [ "$output" = '"hello"' ]
}

@test "_json_value: empty string -> empty quoted string" {
    run _json_value ""
    [ "$output" = '""' ]
}

# -----------------------------------------------------------------------------
# manifest status --json
# -----------------------------------------------------------------------------

@test "status --json: emits valid one-line JSON in non-git directory" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    cd "$SCRATCH"
    run manifest_status --json
    [ "$status" -eq 0 ]
    # Single line of JSON.
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
    # Top-level keys present.
    echo "$output" | grep -q '"repository":{'
    echo "$output" | grep -q '"branch":{'
    echo "$output" | grep -q '"version":'
    echo "$output" | grep -q '"fleet":{'
    echo "$output" | grep -q '"config":{'
    echo "$output" | grep -q '"version_surfaces":{'
    # Non-git directory -> in_git false, no version.
    echo "$output" | grep -q '"in_git":false'
    echo "$output" | grep -q '"version":null'
}

@test "status --json: includes detected noncanonical version surfaces" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "1.2.3" > VERSION
    printf '{"version":"0.1.0"}\n' > package.json

    run manifest_status --json
    [ "$status" -eq 0 ]
    echo "$output" | yq e '.' - >/dev/null
    [ "$(echo "$output" | yq e '.version_surfaces.noncanonical_count' -)" = "1" ]
    [ "$(echo "$output" | yq e '.version_surfaces.items[] | select(.relationship == "noncanonical") | .path' -)" = "package.json" ]
    [ "$(echo "$output" | yq e '.version_surfaces.items[] | select(.path == "package.json") | .relationship' -)" = "noncanonical" ]
}

@test "status fleet --json: includes per-repository version surfaces" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    mkdir -p "$SCRATCH/svc-a"
    git -C "$SCRATCH/svc-a" init -q
    git -C "$SCRATCH/svc-a" config user.email t@e.com
    git -C "$SCRATCH/svc-a" config user.name t
    echo "1.2.3" > "$SCRATCH/svc-a/VERSION"
    printf '{"version":"0.1.0"}\n' > "$SCRATCH/svc-a/package.json"
    cat > "$SCRATCH/manifest.fleet.yaml" <<'YAML'
fleet:
  name: test-fleet
services:
  svc-a:
    path: ./svc-a
YAML

    cd "$SCRATCH"
    run manifest_status fleet --json
    [ "$status" -eq 0 ]
    echo "$output" | yq e '.' - >/dev/null
    [ "$(echo "$output" | yq e '.repositories[0].version_surfaces.noncanonical_count' -)" = "1" ]
    [ "$(echo "$output" | yq e '.repositories[0].version_surfaces.items[] | select(.relationship == "noncanonical") | .path' -)" = "package.json" ]
}

@test "status --json: includes version + numeric bump previews when VERSION exists" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "3.7.1" > VERSION
    run manifest_status --json
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"current":"3.7.1"'
    # Bump previews are still strings (semver pieces — not numbers), so quoted.
    echo "$output" | grep -q '"next_patch":"3.7.2"'
    echo "$output" | grep -q '"next_minor":"3.8.0"'
    echo "$output" | grep -q '"next_major":"4.0.0"'
    # Numeric counters are bare numbers.
    echo "$output" | grep -qE '"ahead":[0-9]+'
    echo "$output" | grep -qE '"modified":[0-9]+'
}

@test "status --json: validates as JSON via yq" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "1.2.3" > VERSION
    run manifest_status --json
    [ "$status" -eq 0 ]
    echo "$output" | yq e '.' - >/dev/null
}

@test "status --json: rejects unknown options" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    cd "$SCRATCH"
    run manifest_status --bogus
    [ "$status" -eq 1 ]
}

# -----------------------------------------------------------------------------
# manifest config list --json
# -----------------------------------------------------------------------------

@test "config list --json: empty layer returns []" {
    source "$TEST_REPO_ROOT/modules/core/manifest-config-crud.sh"
    cd "$SCRATCH"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_config_list --layer project --json
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "config list --json --layer: returns array of explicit keys" {
    source "$TEST_REPO_ROOT/modules/core/manifest-config-crud.sh"
    cd "$SCRATCH"
    cat > "$SCRATCH/manifest.config.yaml" <<'EOF'
git:
  default_branch: main
project:
  name: demo
EOF
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_config_list --layer project --json
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"key":"git.default_branch"'
    echo "$output" | grep -q '"key":"project.name"'
    echo "$output" | grep -q '"value":"main"'
    echo "$output" | grep -q '"value":"demo"'
    # Single-line JSON array.
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
    echo "$output" | yq e '.' - >/dev/null
    echo "$output" | yq e 'type == "!!seq"' - | grep -q true
}
