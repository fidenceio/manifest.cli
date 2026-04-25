#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
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
    # Non-git directory -> in_git false, no version.
    echo "$output" | grep -q '"in_git":false'
    echo "$output" | grep -q '"version":null'
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

@test "status --json: validates as JSON via python (when available)" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed"
    fi
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "1.2.3" > VERSION
    run manifest_status --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c 'import json,sys; json.loads(sys.stdin.read())'
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
    PROJECT_ROOT="$SCRATCH" run manifest_config_list --layer project --json
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
    PROJECT_ROOT="$SCRATCH" run manifest_config_list --layer project --json
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"key":"git.default_branch"'
    echo "$output" | grep -q '"key":"project.name"'
    echo "$output" | grep -q '"value":"main"'
    echo "$output" | grep -q '"value":"demo"'
    # Single-line JSON array.
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
    # Validates if python is around.
    if command -v python3 >/dev/null 2>&1; then
        echo "$output" | python3 -c 'import json,sys; arr=json.loads(sys.stdin.read()); assert isinstance(arr, list)'
    fi
}
