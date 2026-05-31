#!/usr/bin/env bats

# Coverage for secret redaction (CLI tracker 2.7): tokens must never reach
# stdout/stderr/logs/status files verbatim. manifest_redact catches both
# token-shaped strings and the exact values of known credential env vars, and
# every log_* routes through it.
#
# NOTE: token fixtures are assembled at runtime from harmless parts so no literal
# credential shape is committed — the repo's own pre-commit secret scanner (and
# CI gitleaks) would otherwise block this very test file.

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
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# --- fixture builders (assembled so no literal token shape is committed) -----
gh_classic()  { printf 'gh%s_%s' "p" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"; }
gh_fine()     { printf 'github_%s_%s' "pat" "11ABCDEFG0aBcDeFgHiJkLmNoPqRsTuVwXyZ"; }
aws_id()      { printf 'AK%s%s' "IA" "IOSFODNN7EXAMPLE"; }
openai()      { printf 'sk%s%s' "-" "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"; }
jwt()         { printf 'ey%s.%s.%s' "JhbGciOi" "eyJzdWIiOi" "SflKxwRJSMxyz"; }

# --- pattern-based redaction ------------------------------------------------

@test "redact: classic GitHub token shape is removed" {
    local t; t="$(gh_classic)"
    run manifest_redact "before $t after"
    [[ "$output" != *"$t"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: fine-grained GitHub PAT (github_pat_) is removed" {
    local t; t="$(gh_fine)"
    run manifest_redact "tok $t done"
    [[ "$output" != *"$t"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: AWS access key id is removed" {
    local t; t="$(aws_id)"
    run manifest_redact "key $t end"
    [[ "$output" != *"$t"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: OpenAI-style key is removed" {
    local t; t="$(openai)"
    run manifest_redact "x $t y"
    [[ "$output" != *"$t"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: JWT is removed" {
    local t; t="$(jwt)"
    run manifest_redact "auth $t done"
    [[ "$output" != *"$t"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: Bearer token is removed but the word Bearer stays" {
    run manifest_redact "Authorization: Bearer abcdef1234567890XYZ"
    [[ "$output" != *"abcdef1234567890XYZ"* ]]
    [[ "$output" == *"Bearer [REDACTED]"* ]]
}

# --- value-based redaction (known credential env vars) ----------------------

@test "redact: exact GITHUB_TOKEN value is removed even with an odd shape" {
    export GITHUB_TOKEN="weird-but-secret-value-123"
    run manifest_redact "the token weird-but-secret-value-123 leaked"
    [[ "$output" != *"weird-but-secret-value-123"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: MANIFEST_CLI_CLOUD_API_KEY value is removed" {
    export MANIFEST_CLI_CLOUD_API_KEY="cloudkey-abcdef-987654"
    run manifest_redact "calling cloud with cloudkey-abcdef-987654 now"
    [[ "$output" != *"cloudkey-abcdef-987654"* ]]
}

@test "redact: value of the var named by MANIFEST_CLI_CLOUD_API_KEY_ENV is removed" {
    export MY_CUSTOM_KEY_VAR="indirected-secret-7777"
    export MANIFEST_CLI_CLOUD_API_KEY_ENV="MY_CUSTOM_KEY_VAR"
    run manifest_redact "hydrated indirected-secret-7777 value"
    [[ "$output" != *"indirected-secret-7777"* ]]
}

@test "redact: short or empty env values do not over-redact" {
    export GITHUB_TOKEN="abc"   # < 8 chars: must NOT be used as a redaction needle
    run manifest_redact "the abc word and abcdef appear normally"
    [ "$output" = "the abc word and abcdef appear normally" ]
}

@test "redact: non-secret text is returned unchanged" {
    run manifest_redact "a perfectly ordinary release message"
    [ "$output" = "a perfectly ordinary release message" ]
}

# --- wiring proof: log_* route through the redactor -------------------------

@test "redact: log_error output redacts a leaked token" {
    export MANIFEST_CLI_LOG_LEVEL=ERROR
    local t; t="$(gh_classic)"
    run bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-requirements.sh" 2>/dev/null
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-shared-utils.sh"
        log_error "leak '"$t"'" 2>&1
    '
    [[ "$output" != *"$t"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: log_info output redacts a known env-var value" {
    export MANIFEST_CLI_LOG_LEVEL=INFO
    export HOMEBREW_GITHUB_API_TOKEN="hbsecretvalue-123456"
    run bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-requirements.sh" 2>/dev/null
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-shared-utils.sh"
        log_info "pushing with $HOMEBREW_GITHUB_API_TOKEN" 2>&1
    '
    [[ "$output" != *"hbsecretvalue-123456"* ]]
}
