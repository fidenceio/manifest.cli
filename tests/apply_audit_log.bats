#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the apply-event audit log (CLI tracker §5.8): every apply that
# crosses the apply guard appends exactly one NDJSON event recording actor,
# source, command, scope, plan hash, and the authorization exit status. The log
# lives under the preserved global-state dir, never under the cache-sweep dirs,
# and every field is routed through manifest_redact.
#
# NOTE: the token fixture is assembled at runtime from harmless parts so no
# literal credential shape is committed (the repo secret scanner / CI gitleaks
# would otherwise block this file).

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-execution-policy.sh"

    AUDIT_FILE="$HOME/.manifest-cli/audit/apply-events.ndjson"
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

gh_classic() { printf 'gh%s_%s' "p" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"; }

# Create a fresh git repo so the apply guard's write-access preflight passes.
mk_git_repo() {
    local root="$1"
    mkdir -p "$root"
    git -C "$root" init -q
    git -C "$root" config user.email test@example.com
    git -C "$root" config user.name test
}

# --- direct emitter: format, path, fields ------------------------------------

@test "audit: emitter writes one NDJSON line under the preserved audit dir" {
    run manifest_audit_apply_event "cli" "manifest ship repo patch -y" "/repo" "abc123def456" "0"
    [ "$status" -eq 0 ]
    [ -f "$AUDIT_FILE" ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
}

@test "audit: event records source, command, scope, plan hash, and numeric exit status" {
    manifest_audit_apply_event "cli" "manifest ship repo patch -y" "/work/repo" "deadbeef0000" "0"
    line="$(cat "$AUDIT_FILE")"
    [[ "$line" == *'"source":"cli"'* ]]
    [[ "$line" == *'"command":"manifest ship repo patch -y"'* ]]
    [[ "$line" == *'"scope":"/work/repo"'* ]]
    [[ "$line" == *'"plan_hash":"deadbeef0000"'* ]]
    # exit_status is emitted unquoted (numeric)
    [[ "$line" == *'"exit_status":0'* ]]
    [[ "$line" == *'"ts":"'* ]]
    [[ "$line" == *'"actor":"'* ]]
}

@test "audit: MANIFEST_CLI_ACTOR overrides the recorded actor" {
    export MANIFEST_CLI_ACTOR="ci-bot"
    manifest_audit_apply_event "cli" "manifest ship repo patch -y" "/repo" "h" "0"
    [[ "$(cat "$AUDIT_FILE")" == *'"actor":"ci-bot"'* ]]
}

@test "audit: a token-shaped value in any field is redacted" {
    local tok; tok="$(gh_classic)"
    manifest_audit_apply_event "cli" "manifest ship repo patch -y $tok" "/repo" "h" "0"
    line="$(cat "$AUDIT_FILE")"
    [[ "$line" != *"$tok"* ]]
    [[ "$line" == *"[REDACTED]"* ]]
}

@test "audit: a control character in a field is \\u-escaped (line stays valid JSON)" {
    export MANIFEST_CLI_ACTOR="bad$(printf '\x0b')actor"
    manifest_audit_apply_event "cli" "manifest ship repo patch -y" "/repo" "h" "0"
    line="$(cat "$AUDIT_FILE")"
    # raw control byte must be gone; the \u escape must be present
    [[ "$line" == *'\u000b'* ]]
    run grep -c "$(printf '\x0b')" "$AUDIT_FILE"
    [ "$output" -eq 0 ]
    # and the line must parse as JSON where jq is available
    if command -v jq >/dev/null 2>&1; then
        echo "$line" | jq -e . >/dev/null
    fi
}

@test "audit: every emitted line parses as JSON (jq, when available)" {
    if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
    manifest_audit_apply_event "cli" 'cmd with "quotes" and \backslash' "/a/b" "h1" "0"
    manifest_audit_apply_event "cli-fleet" "cmd" "/c/d" "h2" "1"
    run jq -e . "$AUDIT_FILE"
    [ "$status" -eq 0 ]
    [ "$(jq -s 'length' "$AUDIT_FILE")" -eq 2 ]
}

@test "audit: log path is not among the cache-sweep dirs" {
    local cache_dirs
    cache_dirs="$(manifest_install_paths_cache_dirs)"
    [[ "$cache_dirs" != *"$HOME/.manifest-cli/audit"* ]]
}

@test "audit: audit dir is a preserved subdir (survives upgrade swap)" {
    run manifest_install_paths_preserved_subdirs
    [[ "$output" == *"audit"* ]]
}

# --- guard wiring: emission happens exactly at the apply boundary ------------

@test "audit: apply mode through the guard emits exactly one event (source cli)" {
    local repo="$SCRATCH/repo"
    mk_git_repo "$repo"
    export MANIFEST_CLI_AUTO_CONFIRM=1
    run manifest_execution_require_apply "apply" "$repo" "manifest ship repo patch -y" "fa11deadbeef"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
    line="$(cat "$AUDIT_FILE")"
    [[ "$line" == *'"source":"cli"'* ]]
    [[ "$line" == *'"plan_hash":"fa11deadbeef"'* ]]
    [[ "$line" == *'"exit_status":0'* ]]
}

@test "audit: preview mode through the guard emits nothing" {
    local repo="$SCRATCH/repo"
    mk_git_repo "$repo"
    run manifest_execution_require_apply "preview" "$repo" "manifest ship repo patch -y" "h"
    [ "$status" -eq 0 ]
    [ ! -f "$AUDIT_FILE" ]
}

@test "audit: MANIFEST_CLI_AUDIT_SOURCE marks the event as cli-fleet" {
    local repo="$SCRATCH/repo"
    mk_git_repo "$repo"
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_AUDIT_SOURCE="cli-fleet"
    manifest_execution_require_apply "apply" "$repo" "manifest ship repo patch -y" "h"
    [[ "$(cat "$AUDIT_FILE")" == *'"source":"cli-fleet"'* ]]
}

@test "audit: a fleet of N member applies appends one event per member with the same plan hash" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_AUDIT_SOURCE="cli-fleet"
    local i repo
    for i in 1 2 3; do
        repo="$SCRATCH/member-$i"
        mk_git_repo "$repo"
        manifest_execution_require_apply "apply" "$repo" "manifest ship fleet patch -y" "shared-plan-1"
    done
    [ "$(wc -l < "$AUDIT_FILE")" -eq 3 ]
    [ "$(grep -c '"plan_hash":"shared-plan-1"' "$AUDIT_FILE")" -eq 3 ]
    [ "$(grep -c '"source":"cli-fleet"' "$AUDIT_FILE")" -eq 3 ]
    # scope differs per member
    [ "$(grep -c '"scope":"' "$AUDIT_FILE")" -eq 3 ]
    [[ "$(cat "$AUDIT_FILE")" == *"member-1"* ]]
    [[ "$(cat "$AUDIT_FILE")" == *"member-3"* ]]
}

@test "audit: declined apply (non-interactive, ambiguous target) records non-zero exit status" {
    local repo="$SCRATCH/repo"
    mk_git_repo "$repo"
    # mk_git_repo has a named branch but NO origin. Under consent model C the
    # require_apply guard gates with origin_required=true (the default), so this
    # is an AMBIGUOUS non-interactive target without MANIFEST_CLI_AUTO_CONFIRM ->
    # the gate refuses. The attempt is still audited, with a non-zero exit
    # status. (Pre-model-C this refused purely for being non-interactive.)
    run manifest_execution_require_apply "apply" "$repo" "manifest ship repo patch -y" "h" </dev/null
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
    [[ "$(cat "$AUDIT_FILE")" != *'"exit_status":0'* ]]
}
