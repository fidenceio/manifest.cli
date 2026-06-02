#!/usr/bin/env bats

# Coverage for CLI tracker §1.1: a fleet member with release.strategy: pr is
# PR-gated. The ship-fleet PREVIEW must list it ('needs PR'), and APPLY must
# refuse (fail-closed) with a structured error plus a `manifest pr fleet ... -y`
# replay command. Silently shipping or skipping a PR-gated member is the
# half-shipped-fleet hazard §1.1 exists to prevent.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

init_git_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name "Test"
    echo "1.0.0" > "$dir/VERSION"
    git -C "$dir" add VERSION
    git -C "$dir" commit -q -m "version"
}

# Fleet of two members: one direct-release, one PR-gated (release.strategy: pr).
write_fleet_with_pr_gated_member() {
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work" config user.email test@example.com
    git -C "$SCRATCH/work" config user.name "Test"
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  direct-svc:
    path: "./direct-svc"
    type: "service"
    branch: "main"
    release:
      enabled: true
      strategy: "direct"
  gated-svc:
    path: "./gated-svc"
    type: "service"
    branch: "main"
    release:
      enabled: true
      strategy: "pr"
YAML
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	direct-svc	./direct-svc	service	true
true	gated-svc	./gated-svc	service	true
TSV
    init_git_repo "$SCRATCH/work/direct-svc"
    init_git_repo "$SCRATCH/work/gated-svc"
}

# --- Preview: PR-gated member is listed -------------------------------------

@test "fleet ship preview: PR-gated member is listed as 'needs PR', not shipped" {
    write_fleet_with_pr_gated_member
    run_manifest ship fleet patch --dry-run
    [ "$status" -eq 0 ]
    # Direct member is releaseable.
    echo "$output" | grep -E "direct-svc[[:space:]].*would ship" >/dev/null
    # PR-gated member renders the dedicated effect/decision and reason.
    echo "$output" | grep -E "gated-svc[[:space:]].*pr-gate[[:space:]].*needs PR" >/dev/null
    echo "$output" | grep -F "release.strategy: pr" >/dev/null
}

@test "fleet ship preview: summary counts pr-gated and prints the replay command" {
    write_fleet_with_pr_gated_member
    run_manifest ship fleet patch --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -E "Plan summary: 1 releaseable, 1 pr-gated, 0 skipped" >/dev/null
    echo "$output" | grep -F "are PR-gated (release.strategy: pr)" >/dev/null
    echo "$output" | grep -F "manifest pr fleet -y" >/dev/null
}

# --- Apply: fail-closed refusal + replay hint -------------------------------

@test "fleet ship -y refuses (fail-closed) when a member is PR-gated, with replay command" {
    write_fleet_with_pr_gated_member
    run_manifest ship fleet patch -y
    [ "$status" -ne 0 ]
    # Structured refusal naming the gated member.
    echo "$output" | grep -F "are PR-gated (release.strategy: pr) and cannot be shipped directly" >/dev/null
    echo "$output" | grep -E "gated-svc" >/dev/null
    # Replay command routes the release through review.
    echo "$output" | grep -F "manifest pr fleet -y" >/dev/null
    echo "$output" | grep -F "no fleet member was shipped" >/dev/null

    # Fail-closed: the direct member must NOT have been shipped (no new tag,
    # VERSION pinned) — refusal happens before any mutation.
    [ -z "$(git -C "$SCRATCH/work/direct-svc" tag 2>/dev/null)" ]
    [ "$(cat "$SCRATCH/work/direct-svc/VERSION")" = "1.0.0" ]
}
