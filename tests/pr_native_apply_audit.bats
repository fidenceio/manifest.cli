#!/usr/bin/env bats
# §5.9 PR apply-event audit coverage.
#
# Every -y-gated PR mutation (create / merge / ready / update) must append
# exactly one apply event to the audit log, sourced as `cli-pr`, recording the
# gh-backed command that ran, with redaction applied. PR ops carry no version
# plan, so plan_hash is empty (the consumer tolerates that). Preview mode emits
# nothing.
#
# NOTE: the token fixture is assembled at runtime from harmless parts so no
# literal credential shape is committed (the repo secret scanner / CI gitleaks
# would otherwise block this file).

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    load_modules "system/manifest-install-paths.sh" "pr/manifest-pr-native.sh"
    gh_stub_install
    cd "$SCRATCH"
    git init -q
    AUDIT_FILE="$HOME/.manifest-cli/audit/apply-events.ndjson"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset _MANIFEST_GH_VALIDATED_AT MANIFEST_CLI_GH_VALIDATION_TTL
    unset MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_GH_STUB_EXIT MANIFEST_CLI_GH_STUB_AUTH_EXIT MANIFEST_CLI_GH_STUB_STDOUT MANIFEST_CLI_GH_STUB_STDERR
}

gh_classic() { printf 'gh%s_%s' "p" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"; }

@test "pr create -y emits exactly one cli-pr event recording the gh command" {
    run manifest_pr_create -y --draft --base main
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
    line="$(cat "$AUDIT_FILE")"
    [[ "$line" == *'"source":"cli-pr"'* ]]
    [[ "$line" == *'"command":"gh pr create --draft --fill --base main"'* ]]
    [[ "$line" == *'"exit_status":0'* ]]
}

@test "pr merge -y emits one cli-pr event with the merged command" {
    run manifest_pr_merge -y 123 --auto
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
    line="$(cat "$AUDIT_FILE")"
    [[ "$line" == *'"source":"cli-pr"'* ]]
    [[ "$line" == *'"command":"gh pr merge 123 --auto --squash"'* ]]
}

@test "pr ready -y emits one cli-pr event" {
    run manifest_pr_ready -y 123
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
    [[ "$(cat "$AUDIT_FILE")" == *'"command":"gh pr ready 123"'* ]]
}

@test "pr update -y emits one cli-pr event" {
    run manifest_pr_update -y 123 --rebase
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
    [[ "$(cat "$AUDIT_FILE")" == *'"command":"gh pr update-branch 123 --rebase"'* ]]
}

@test "pr apply event records an empty plan_hash (PR ops carry no version plan)" {
    manifest_pr_ready -y 123
    [[ "$(cat "$AUDIT_FILE")" == *'"plan_hash":""'* ]]
}

@test "pr apply event scope is the repo git root" {
    local root; root="$(git rev-parse --show-toplevel)"
    manifest_pr_ready -y 123
    [[ "$(cat "$AUDIT_FILE")" == *"\"scope\":\"$root\""* ]]
}

@test "pr apply event redacts a token-shaped value in the command" {
    local tok; tok="$(gh_classic)"
    manifest_pr_create -y --title "fix: foo $tok"
    line="$(cat "$AUDIT_FILE")"
    [[ "$line" != *"$tok"* ]]
    [[ "$line" == *"[REDACTED]"* ]]
}

@test "pr apply event records the gh mutation's non-zero exit status" {
    # Shadow `gh` with a stub that lets the auth + repo-view preflight pass but
    # fails the actual `pr ready` mutation, so the boundary is reached and the
    # failure exit status is recorded.
    cat > "$SCRATCH/.gh-stub/gh" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "auth" || "$1" == "repo" ]] && exit 0
exit 7
STUB
    chmod +x "$SCRATCH/.gh-stub/gh"
    run manifest_pr_ready -y 123
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$AUDIT_FILE")" -eq 1 ]
    [[ "$(cat "$AUDIT_FILE")" != *'"exit_status":0'* ]]
}

@test "pr preview mode emits no audit event" {
    run manifest_pr_merge 123 --auto
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Would run: gh pr merge 123 --auto --squash"
    [ ! -f "$AUDIT_FILE" ]
}
