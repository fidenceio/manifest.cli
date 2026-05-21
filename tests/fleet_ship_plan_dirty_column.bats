#!/usr/bin/env bats

# Coverage for CLI tracker §1.1 (preview side): the fleet ship plan must
# expose dirty-tree state per member so `-y` is an informed consent.
# Apply-side disclosure shipped in CLI 5ffb5c22 (the "⚠️ Auto-committing
# N pending file(s)" notice in manifest-orchestrator.sh); the last test
# below is a grep-guard that prevents that line from being silently
# removed by future refactors.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# Initialize a minimal git repo with a tracked file so status --porcelain
# can distinguish modified vs untracked vs clean.
init_git_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name "Test"
    echo "initial" > "$dir/README"
    git -C "$dir" add README
    git -C "$dir" commit -q -m "initial"
}

source_git_changes() {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-doc-review.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git-changes.sh"
}

# --- manifest_git_changes_dirty_summary unit tests --------------------------

@test "dirty_summary: clean repo returns empty" {
    init_git_repo "$SCRATCH/repo"
    source_git_changes
    run manifest_git_changes_dirty_summary "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "dirty_summary: modified-only returns Nm+0u" {
    init_git_repo "$SCRATCH/repo"
    echo "edit" >> "$SCRATCH/repo/README"
    source_git_changes
    run manifest_git_changes_dirty_summary "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    [ "$output" = "1m+0u" ]
}

@test "dirty_summary: untracked-only returns 0m+Nu" {
    init_git_repo "$SCRATCH/repo"
    : > "$SCRATCH/repo/new.file"
    source_git_changes
    run manifest_git_changes_dirty_summary "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    [ "$output" = "0m+1u" ]
}

@test "dirty_summary: mixed dirt returns Nm+Mu with correct counts" {
    init_git_repo "$SCRATCH/repo"
    echo "edit" >> "$SCRATCH/repo/README"
    : > "$SCRATCH/repo/new1.file"
    : > "$SCRATCH/repo/new2.file"
    source_git_changes
    run manifest_git_changes_dirty_summary "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    [ "$output" = "1m+2u" ]
}

@test "dirty_summary: only formula/manifest.rb dirty → empty (excluded)" {
    init_git_repo "$SCRATCH/repo"
    # Track the formula first so a later edit produces ` M formula/manifest.rb`
    # (the form the awk filter excludes). An untracked formula directory
    # would render as `?? formula/` and isn't what production ever produces.
    mkdir -p "$SCRATCH/repo/formula"
    echo "class Manifest" > "$SCRATCH/repo/formula/manifest.rb"
    git -C "$SCRATCH/repo" add formula/manifest.rb
    git -C "$SCRATCH/repo" commit -q -m "add formula"
    echo "edit" >> "$SCRATCH/repo/formula/manifest.rb"

    source_git_changes
    run manifest_git_changes_dirty_summary "$SCRATCH/repo"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "dirty_summary: non-git path returns empty silently" {
    mkdir -p "$SCRATCH/not-a-repo"
    source_git_changes
    run manifest_git_changes_dirty_summary "$SCRATCH/not-a-repo"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- _fleet_ship_plan integration tests -------------------------------------

write_fleet_with_two_members() {
    # Fleet root itself must be a git repo for `manifest ship` to proceed
    # past its repo-root validation.
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work" config user.email test@example.com
    git -C "$SCRATCH/work" config user.name "Test"
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  clean-svc:
    path: "./clean-svc"
    type: "service"
    branch: "main"
    release_enabled: true
  dirty-svc:
    path: "./dirty-svc"
    type: "service"
    branch: "main"
    release_enabled: true
YAML
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	clean-svc	./clean-svc	service	false
true	dirty-svc	./dirty-svc	service	false
TSV
    init_git_repo "$SCRATCH/work/clean-svc"
    init_git_repo "$SCRATCH/work/dirty-svc"
    # Dirty the second member: one modified + one untracked.
    echo "edit" >> "$SCRATCH/work/dirty-svc/README"
    : > "$SCRATCH/work/dirty-svc/new.file"
}

@test "fleet ship preview: Dirty column header appears between Branch and Effect" {
    write_fleet_with_two_members
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet patch --dry-run
    [ "$status" -eq 0 ]
    # Header row must list "Dirty" between "Branch" and "Effect".
    echo "$output" | grep -E "Service.*Type.*Branch.*Dirty.*Effect.*Decision.*Path" >/dev/null
}

@test "fleet ship preview: clean member shows no dirty marker, dirty member shows 1m+1u" {
    write_fleet_with_two_members
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet patch --dry-run
    [ "$status" -eq 0 ]
    # dirty-svc row must contain the 1m+1u marker.
    echo "$output" | grep -E "dirty-svc[[:space:]].*1m\+1u" >/dev/null
    # clean-svc row must NOT contain any Nm+Nu marker.
    ! echo "$output" | grep -E "clean-svc[[:space:]].*[0-9]+m\+[0-9]+u" >/dev/null
}

# --- Apply-side regression guardrail ----------------------------------------

@test "orchestrator preserves auto-commit notice (5ffb5c22 guardrail)" {
    # The "⚠️ Auto-committing N pending file(s)" line is the apply-side
    # half of §1.1's option-(b) disclosure. Without it, dirty trees get
    # swept into release commits silently again. Guard the literal so it
    # cannot vanish in a refactor without a test failure flagging it.
    grep -F '⚠️  Auto-committing' \
        "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh" \
        >/dev/null
}
