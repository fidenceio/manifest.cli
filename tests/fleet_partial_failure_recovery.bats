#!/usr/bin/env bats

# Coverage for CLI tracker §1.2: fleet partial-failure recovery output.
# Exercises _fleet_emit_recovery_report directly with crafted status files
# so each classification path (pushed-then-stranded, local-only, unknown)
# is covered without needing a working ship pipeline.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    export MANIFEST_CLI_FLEET_NAME="test-fleet"
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

write_status_file() {
    local path="$1"
    shift
    : > "$path"
    while [[ $# -ge 2 ]]; do
        printf '%s=%s\n' "$1" "$2" >> "$path"
        shift 2
    done
}

@test "recovery report: pushed-then-stranded — release live, formula stranded, no rollback" {
    local sf="$SCRATCH/svcb.status"
    write_status_file "$sf" \
        result failed \
        failure_step homebrew_commit \
        push_status success \
        homebrew_status failed \
        version 1.2.3 \
        tag v1.2.3

    # Pre-populate completed/not_started/skipped arrays so the helper finds them
    # via dynamic scope (same pattern fleet_ship uses).
    local -a completed=("svca|./svc-a|$SCRATCH/svca.status")
    local -a not_started=("svcc|./svc-c")
    local -a skipped=()
    write_status_file "$SCRATCH/svca.status" result success version 1.2.3 tag v1.2.3

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch false

    [ "$status" -eq 0 ]
    [[ "$output" == *"Fleet ship: partial completion"* ]]
    [[ "$output" == *"✅ svca → v1.2.3"* ]]
    [[ "$output" == *"❌ svcb (./svc-b)"* ]]
    [[ "$output" == *"category: pushed-then-stranded"* ]]
    [[ "$output" == *"Release v1.2.3 is live"* ]]
    [[ "$output" == *"DO NOT rollback"* ]]
    [[ "$output" == *"manifest ship repo resume"* ]]
    [[ "$output" == *"⏸  svcc"* ]]
    # No "retry" advice for stranded state — resume only.
    [[ "$output" != *"Or retry:"* ]]
}

@test "recovery report: local-only — failure before push, safe to retry or rollback locally" {
    local sf="$SCRATCH/svcb.status"
    write_status_file "$sf" \
        result failed \
        failure_step version_commit \
        push_status not_attempted \
        homebrew_status not_applicable \
        version 1.2.3 \
        tag none

    local -a completed=("svca|./svc-a|$SCRATCH/svca.status")
    local -a not_started=("svcc|./svc-c")
    local -a skipped=("svcd|./svc-d|release disabled")
    write_status_file "$SCRATCH/svca.status" result success version 1.2.3 tag v1.2.3

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch false

    [ "$status" -eq 0 ]
    [[ "$output" == *"category: local-only"* ]]
    [[ "$output" == *"no remote state for this member"* ]]
    [[ "$output" == *"manifest ship repo resume"* ]]
    [[ "$output" == *"Or retry:"* ]]
    [[ "$output" == *"manifest ship repo patch -y"* ]]
    [[ "$output" != *"DO NOT rollback"* ]]
    [[ "$output" == *"⏭  svcd (release disabled)"* ]]
}

@test "recovery report: unknown — status file missing, defer to per-member report" {
    local sf="$SCRATCH/svcb.status"   # intentionally not created

    local -a completed=()
    local -a not_started=()
    local -a skipped=()

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch false

    [ "$status" -eq 0 ]
    [[ "$output" == *"category: unknown"* ]]
    [[ "$output" == *"Per-member status file missing"* ]]
    [[ "$output" == *"Completed (0):"* ]]
    [[ "$output" == *"(none)"* ]]
}

@test "recovery report: local mode is surfaced in header" {
    local sf="$SCRATCH/svcb.status"
    write_status_file "$sf" \
        result failed \
        failure_step version_commit \
        push_status not_attempted

    local -a completed=() not_started=() skipped=()

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch true

    [ "$status" -eq 0 ]
    [[ "$output" == *"Mode:      --local"* ]]
}

@test "orchestrator emit_ship_failure_report writes status file when MANIFEST_CLI_SHIP_STATUS_FILE is set" {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"

    local sf="$SCRATCH/orch.status"
    MANIFEST_CLI_SHIP_STATUS_FILE="$sf" \
        emit_ship_failure_report "homebrew_commit" "abc123" "1.2.3" "v1.2.3" "success" "failed" >/dev/null

    [ -f "$sf" ]
    grep -q "^result=failed$" "$sf"
    grep -q "^failure_step=homebrew_commit$" "$sf"
    grep -q "^push_status=success$" "$sf"
    grep -q "^version=1.2.3$" "$sf"
    grep -q "^tag=v1.2.3$" "$sf"
}

@test "orchestrator emit_ship_failure_report is a no-op for the status file when env var is unset" {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"

    local sf="$SCRATCH/should-not-exist.status"
    unset MANIFEST_CLI_SHIP_STATUS_FILE
    emit_ship_failure_report "version_commit" "" "1.2.3" "none" "not_attempted" "not_applicable" >/dev/null

    [ ! -f "$sf" ]
}
