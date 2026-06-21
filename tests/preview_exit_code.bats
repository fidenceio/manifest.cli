#!/usr/bin/env bats
# §2.2 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Coverage for the residual §2.2 preview/apply contract work:
#   - the shared plan-table renderer (manifest_plan_render_field /
#     manifest_plan_render_fingerprint_line) reused across ship/fleet/PR
#     previews,
#   - the preview fingerprint persisted at preview time and re-compared on
#     apply (manifest_plan_fingerprint_persist / *_warn_on_drift),
#   - and the distinct "preview happened, no consent" exit code, which is
#     opt-in (preview.exit_code=distinct) so the historical preview/apply and
#     --dry-run exit semantics stay intact (preview still exits 0 by default).

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    # Isolate the run/status dir under the sandbox so persisted fingerprints
    # never touch the developer's real cache.
    export TMPDIR="$SCRATCH/tmp"
    mkdir -p "$TMPDIR"
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
    unset MANIFEST_CLI_PREVIEW_EXIT_CODE
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

setup_repo_with_remote() {
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work" remote add origin https://example.invalid/example.git
    echo "1.2.3" > "$SCRATCH/work/VERSION"
}

# --- shared plan-table renderer ---------------------------------------------

@test "render_field aligns the value column to a shared width" {
    run manifest_plan_render_field "Release type" "minor"
    [ "$status" -eq 0 ]
    [ "$output" = "  Release type:     minor" ]
}

@test "render_fingerprint_line uses the shared field renderer and label" {
    run manifest_plan_render_fingerprint_line "abc123def456"
    [ "$status" -eq 0 ]
    [ "$output" = "  Plan fingerprint: abc123def456" ]
}

# --- preview exit code knob -------------------------------------------------

@test "preview_exit_code defaults to 0 (historical contract)" {
    run manifest_preview_exit_code
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "preview_exit_code: zero reads as 0" {
    MANIFEST_CLI_PREVIEW_EXIT_CODE=zero run manifest_preview_exit_code
    [ "$output" = "0" ]
}

@test "preview_exit_code: distinct reads as the dedicated no-consent code" {
    MANIFEST_CLI_PREVIEW_EXIT_CODE=distinct run manifest_preview_exit_code
    [ "$output" = "10" ]
}

@test "preview_exit_code: a bare integer is honored verbatim" {
    MANIFEST_CLI_PREVIEW_EXIT_CODE=7 run manifest_preview_exit_code
    [ "$output" = "7" ]
}

@test "preview_exit_code: unrecognized word falls back to the safe 0 default" {
    MANIFEST_CLI_PREVIEW_EXIT_CODE=banana run manifest_preview_exit_code
    [ "$output" = "0" ]
}

# --- persist + drift warning ------------------------------------------------

@test "fingerprint persist + matching apply does not warn and consumes the stash" {
    git -C "$SCRATCH/work" init -q
    manifest_plan_fingerprint_persist "ship-repo" "deadbeef0001" "$SCRATCH/work"
    run manifest_plan_fingerprint_warn_on_drift "ship-repo" "deadbeef0001" "$SCRATCH/work"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Plan changed since preview"
    # Second check is silent: the stash was consumed by the first apply.
    run manifest_plan_fingerprint_warn_on_drift "ship-repo" "deadbeef0001" "$SCRATCH/work"
    ! echo "$output" | grep -q "Plan changed since preview"
}

@test "fingerprint drift between preview and apply warns (never blocks)" {
    git -C "$SCRATCH/work" init -q
    manifest_plan_fingerprint_persist "ship-repo" "deadbeef0001" "$SCRATCH/work"
    run manifest_plan_fingerprint_warn_on_drift "ship-repo" "ffff99990002" "$SCRATCH/work"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Plan changed since preview: previewed deadbeef0001, applying ffff99990002"
}

@test "no persisted preview means the apply drift check is silent" {
    git -C "$SCRATCH/work" init -q
    run manifest_plan_fingerprint_warn_on_drift "ship-repo" "ffff99990002" "$SCRATCH/work"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- end-to-end exit semantics ----------------------------------------------

@test "ship repo preview exits 0 by default (existing contract preserved)" {
    setup_repo_with_remote
    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan"
}

@test "ship repo preview exits the distinct code when preview.exit_code=distinct" {
    setup_repo_with_remote
    export MANIFEST_CLI_PREVIEW_EXIT_CODE=distinct
    run_manifest ship repo patch
    [ "$status" -eq 10 ]
    # Still a plain preview: no writes happened.
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan"
}

@test "ship repo --dry-run still exits the distinct code under distinct (it is a preview)" {
    setup_repo_with_remote
    export MANIFEST_CLI_PREVIEW_EXIT_CODE=distinct
    run_manifest ship repo patch --dry-run
    # --dry-run remains a preview; its exit code follows the same opt-in knob,
    # and it must never be confused with an apply. The contract that matters is
    # that --dry-run never writes and never applies — proven by preview_no_write.
    [ "$status" -eq 10 ]
}

@test "ship repo preview persists a fingerprint matching the shown plan" {
    setup_repo_with_remote
    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    local shown stash_dir
    shown="$(echo "$output" | grep 'Plan fingerprint:' | head -1 | awk '{print $NF}')"
    [ -n "$shown" ]
    # The run dir is keyed by the git toplevel (resolved), so derive it the same
    # way the code does rather than hashing the literal sandbox path.
    stash_dir="$(manifest_plan_run_dir "$SCRATCH/work")"
    [ -f "$stash_dir/ship-repo.fingerprint" ]
    [ "$(tr -d '[:space:]' < "$stash_dir/ship-repo.fingerprint")" = "$shown" ]
}

@test "ship fleet preview exits 0 by default and the distinct code when opted in" {
    # The workspace root must itself be a git repo for fleet commands to run.
    git -C "$SCRATCH/work" init -q
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work/svc" init -q
    echo "1.2.3" > "$SCRATCH/work/svc/VERSION"
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svc:
    path: "./svc"
    type: "service"
    branch: "main"
YAML
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svc	./svc	false
TSV
    run_manifest ship fleet patch
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Plan fingerprint:"

    export MANIFEST_CLI_PREVIEW_EXIT_CODE=distinct
    run_manifest ship fleet patch
    [ "$status" -eq 10 ]
}
