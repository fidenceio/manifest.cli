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
    # commits_created is a VERIFIED positive count — the only state in which the
    # report may claim a local rollback is safe (§9.10).
    write_status_file "$sf" \
        result failed \
        failure_step version_commit \
        push_status not_attempted \
        homebrew_status not_applicable \
        version 1.2.3 \
        tag none \
        commits_created 2

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

@test "recovery report: completion_clean after successful push is stranded, never rollback-safe (RED-001)" {
    # The fleet's own copy of the post-push step set omitted completion_clean,
    # so this member was classified local-only and offered rollback advice for
    # a release that was already public. The shared classifier closes that.
    local sf="$SCRATCH/svcb.status"
    write_status_file "$sf" \
        result failed \
        failure_step completion_clean \
        push_status success \
        homebrew_status success \
        version 1.2.3 \
        tag v1.2.3 \
        commits_created 2

    local -a completed=() not_started=() skipped=()

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch false

    [ "$status" -eq 0 ]
    [[ "$output" == *"category: pushed-then-stranded"* ]]
    [[ "$output" == *"DO NOT rollback"* ]]
    [[ "$output" != *"Safe to retry or rollback locally"* ]]
    [[ "$output" != *"Or retry:"* ]]
}

@test "recovery report: partial multi-remote push is never rollback-safe (§8.1a)" {
    local sf="$SCRATCH/svcb.status"
    write_status_file "$sf" \
        result failed \
        failure_step push_changes \
        push_status partial \
        homebrew_status skipped \
        version 1.2.3 \
        tag v1.2.3 \
        commits_created 1

    local -a completed=() not_started=() skipped=()

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch false

    [ "$status" -eq 0 ]
    [[ "$output" == *"category: partial-push"* ]]
    [[ "$output" == *"public where it landed"* ]]
    [[ "$output" == *"DO NOT rollback"* ]]
    [[ "$output" != *"Safe to retry or rollback locally"* ]]
    [[ "$output" == *"manifest ship repo resume"* ]]
    [[ "$output" != *"Or retry:"* ]]
}

@test "recovery report: local-only with zero commits never claims rollback is safe (§9.10)" {
    local sf="$SCRATCH/svcb.status"
    write_status_file "$sf" \
        result failed \
        failure_step version_commit \
        push_status not_attempted \
        homebrew_status not_applicable \
        version 1.2.3 \
        tag none \
        commits_created 0

    local -a completed=() not_started=() skipped=()

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch false

    [ "$status" -eq 0 ]
    [[ "$output" == *"category: local-only"* ]]
    [[ "$output" == *"do NOT hard-reset"* ]]
    [[ "$output" != *"Safe to retry or rollback locally"* ]]
    [[ "$output" == *"Or retry:"* ]]
}

@test "recovery report: local-only with unverifiable commit count suppresses the rollback claim (§9.10)" {
    # No commits_created key at all (an older or truncated status file):
    # absence is not a value — the report must not claim rollback is safe.
    local sf="$SCRATCH/svcb.status"
    write_status_file "$sf" \
        result failed \
        failure_step version_commit \
        push_status not_attempted \
        homebrew_status not_applicable \
        version 1.2.3 \
        tag none

    local -a completed=() not_started=() skipped=()

    run _fleet_emit_recovery_report svcb ./svc-b "$sf" patch false

    [ "$status" -eq 0 ]
    [[ "$output" == *"category: local-only"* ]]
    [[ "$output" == *"Commits-created count unverified"* ]]
    [[ "$output" != *"Safe to retry or rollback locally"* ]]
    [[ "$output" != *"rollback locally"* ]]
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
    # §9.10: the fleet recovery report classifies rollback safety from this key.
    # (Value not pinned: "abc123" is an abbreviation the host object store may
    # or may not resolve; presence of the key is the contract.)
    grep -q "^commits_created=" "$sf"
}

@test "orchestrator emit_ship_failure_report is a no-op for the status file when env var is unset" {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"

    local sf="$SCRATCH/should-not-exist.status"
    unset MANIFEST_CLI_SHIP_STATUS_FILE
    emit_ship_failure_report "version_commit" "" "1.2.3" "none" "not_attempted" "not_applicable" >/dev/null

    [ ! -f "$sf" ]
}
