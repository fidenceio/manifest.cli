#!/usr/bin/env bats
# bats file_tags=smoke
#
# Fleet scope: an unfinished member release is finished by the ordinary
# `ship fleet <type>` — shown in the plan, applied only with -y — and
# `ship fleet resume` is gone (tests/ship_unfinished_release.bats covers the
# repo scope and the refusal of the removed word).
#
# Two layers:
#   1. Probe (manifest_ship_repo_finish_eligible) — unit, no fleet plumbing.
#      The git preconditions for finishing; true of every cleanly released
#      repo, which is why it no longer decides WHETHER anything is unfinished.
#   2. CLI driven — a real fleet whose member was stranded by a real publish
#      with its push refused, then planned and applied from the root.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    load_modules core/manifest-config.sh
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    export MANIFEST_CLI_FLEET_NAME="test-fleet"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
}

teardown() {
    cd /tmp || true
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# Initialize a member repo with VERSION and an initial commit on main.
mk_member_repo() {
    local repo="$1" version="${2:-1.2.3}"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b main
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    echo "$version" > "$repo/VERSION"
    git -C "$repo" add VERSION
    git -C "$repo" commit -qm "Bump version to $version"
}

# A member in the legacy stranded shape: VERSION + local tag + dirty formula.
# Modern ship does not dirty the source formula, but the finish preconditions
# still accept this historical shape.
mk_stranded_member() {
    local repo="$1" version="${2:-1.2.3}"
    mk_member_repo "$repo" "$version"
    mkdir -p "$repo/formula"
    echo "original formula" > "$repo/formula/manifest.rb"
    git -C "$repo" add formula/manifest.rb
    git -C "$repo" commit -qm "Add formula"
    git -C "$repo" tag "v$version"
    echo "post-tag formula edit" > "$repo/formula/manifest.rb"
}

# ------------------------------------------------------------------ probe ---

@test "probe: eligible — VERSION + local tag + clean tree (modulo formula)" {
    local repo="$SCRATCH/work/svca"
    mk_stranded_member "$repo" 1.2.3

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_finish_eligible"

    [ "$status" -eq 0 ]
    [[ "$output" == eligible\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: no-version — VERSION file missing" {
    local repo="$SCRATCH/work/svcb"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b main
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    echo "stub" > "$repo/stub.txt"
    git -C "$repo" add stub.txt
    git -C "$repo" commit -qm "initial"

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_finish_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == no-version* ]]
}

@test "probe: no-local-tag — VERSION present but tag does not exist" {
    local repo="$SCRATCH/work/svcc"
    mk_member_repo "$repo" 1.2.3
    # No tag created.

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_finish_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == no-local-tag\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: dirty-tree — unrelated file dirty disqualifies" {
    local repo="$SCRATCH/work/svcd"
    mk_stranded_member "$repo" 1.2.3
    echo "unrelated change" > "$repo/runtime.txt"

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_finish_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == dirty-tree\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: tag-not-ancestor — tag points at a commit outside HEAD's history" {
    local repo="$SCRATCH/work/svcf"
    mk_member_repo "$repo" 1.2.3
    # Build one commit ahead, tag it, then reset HEAD back so the tag points
    # at an orphaned commit that is NOT in HEAD's history.
    echo "ahead" > "$repo/ahead.txt"
    git -C "$repo" add ahead.txt
    git -C "$repo" commit -qm "B"
    git -C "$repo" tag v1.2.3
    git -C "$repo" reset --hard HEAD~1 >/dev/null 2>&1

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_finish_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == tag-not-ancestor\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: no-branch — detached HEAD disqualifies" {
    local repo="$SCRATCH/work/svcg"
    mk_stranded_member "$repo" 1.2.3
    # Detach HEAD off main; tag still points at HEAD's commit, just no branch.
    git -C "$repo" checkout --detach HEAD >/dev/null 2>&1

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_finish_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == no-branch\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: dirty formula/manifest.rb alone is still eligible" {
    local repo="$SCRATCH/work/svce"
    mk_stranded_member "$repo" 1.2.3
    # Formula already dirty from mk_stranded_member, no other changes.

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_finish_eligible"

    [ "$status" -eq 0 ]
    [[ "$output" == eligible* ]]
}

# ------------------------------------------------------------ CLI driven ---

run_fleet() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# A member with its own bare origin and a pre-push hook (outside the tree)
# that refuses while $SCRATCH/refuse-push-<name> exists.
mk_remote_member() {
    local name="$1" repo="$SCRATCH/work/$1" hooks="$SCRATCH/hooks-$1"
    mk_member_repo "$repo" 1.2.3
    echo "seed" > "$repo/notes.txt"
    git -C "$repo" add notes.txt
    git -C "$repo" commit -qm "seed"
    git init -q --bare "$SCRATCH/$name-origin.git"
    git -C "$repo" remote add origin "$SCRATCH/$name-origin.git"
    git -C "$repo" push -q -u origin main
    mkdir -p "$hooks"
    printf '#!/bin/sh\nif [ -f "%s" ]; then echo "PUSH-FIXTURE: refusing this push" >&2; exit 1; fi\nexit 0\n' \
        "$SCRATCH/refuse-push-$name" > "$hooks/pre-push"
    chmod +x "$hooks/pre-push"
    git -C "$repo" config core.hooksPath "$hooks"
}

# The coordination root, level with its own upstream, listing MEMBERS.
write_fleet_root() {
    local w="$SCRATCH/work" m
    git -C "$w" init -q -b main
    git -C "$w" config user.email t@example.com
    git -C "$w" config user.name T
    {
        printf 'fleet:\n  name: "test-fleet"\n  versioning: "none"\nservices:\n'
        for m in "$@"; do
            printf '  %s:\n    path: "./%s"\n    branch: "main"\n' "$m" "$m"
        done
    } > "$w/manifest.fleet.config.yaml"
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\n' > "$w/manifest.fleet.tsv"
    for m in "$@"; do
        printf 'true\t%s\t./%s\ttrue\tmain\n' "$m" "$m" >> "$w/manifest.fleet.tsv"
    done
    printf '/*\n!/.gitignore\n!/manifest.fleet.config.yaml\n!/manifest.fleet.tsv\n' > "$w/.gitignore"
    git -C "$w" add .gitignore manifest.fleet.config.yaml manifest.fleet.tsv
    git -C "$w" commit -qm "coordination"
    git init -q --bare "$SCRATCH/root-origin.git"
    git -C "$w" remote add origin "$SCRATCH/root-origin.git"
    git -C "$w" push -q -u origin main
}

# Strand member NAME the way it happens: its own publish, push refused.
strand_member() {
    local name="$1" repo="$SCRATCH/work/$1"
    : > "$SCRATCH/refuse-push-$name"
    cd "$repo"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship repo patch -y
    [ "$status" -ne 0 ]
    rm -f "$SCRATCH/refuse-push-$name"
    # Controls for the fixture: tagged here, recorded, not on its origin.
    [ "$(tr -d '[:space:]' < "$repo/VERSION")" = "1.2.4" ]
    git -C "$repo" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}' >/dev/null
    [ -f "$repo/.git/manifest-ship/in-flight" ]
    refute git --git-dir="$SCRATCH/$name-origin.git" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}'
}

cli_env() {
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
    export MANIFEST_CLI_RELEASE_GATE=none
    export MANIFEST_CLI_GIT_RETRIES=1
    export MANIFEST_CLI_SHIP_FOLLOWUP_PATCH=false
}

@test "CLI: the fleet plan marks an unfinished member 'would finish' and changes nothing" {
    cli_env
    mk_remote_member svca
    mk_remote_member svcb
    write_fleet_root svca svcb
    strand_member svca
    local head_a
    head_a="$(git -C "$SCRATCH/work/svca" rev-parse HEAD)"

    run_fleet ship fleet patch
    [ "$status" -eq 0 ]
    # svca: finished, not bumped — no transition to 1.2.5 is offered.
    [[ "$output" == *"1.2.4 (finish)"* ]]
    [[ "$output" == *"would finish"* ]]
    [[ "$output" != *"1.2.4->1.2.5"* ]]
    [[ "$output" == *"1 member(s) shown 'would finish' were tagged by a ship that did not complete."* ]]
    # CONTROL — svcb is at no tag and has commits, so it is an ordinary release:
    # the plan can still tell the two apart.
    [[ "$output" == *"1.2.3->1.2.4"* ]]

    [ "$(git -C "$SCRATCH/work/svca" rev-parse HEAD)" = "$head_a" ]
    refute git --git-dir="$SCRATCH/svca-origin.git" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}'
}

@test "CLI: ship fleet -y finishes the unfinished member without bumping it" {
    cli_env
    mk_remote_member svca
    write_fleet_root svca
    strand_member svca
    local count_before
    count_before="$(git -C "$SCRATCH/work/svca" rev-list --count HEAD)"

    run_fleet ship fleet patch -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"svca: finishing v1.2.4 (no bump)"* ]]
    [[ "$output" == *"Release v1.2.4 finished. Nothing was bumped."* ]]

    git --git-dir="$SCRATCH/svca-origin.git" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}' >/dev/null
    [ "$(tr -d '[:space:]' < "$SCRATCH/work/svca/VERSION")" = "1.2.4" ]
    [ "$(git -C "$SCRATCH/work/svca" rev-list --count HEAD)" = "$count_before" ]
    refute git -C "$SCRATCH/work/svca" rev-parse -q --verify 'refs/tags/v1.2.5^{commit}'
    [ ! -e "$SCRATCH/work/svca/.git/manifest-ship/in-flight" ]
}

@test "CLI: CONTROL — a member at its tag with NO record is skipped as done, not finished" {
    cli_env
    mk_remote_member svca
    git -C "$SCRATCH/work/svca" tag v1.2.3
    write_fleet_root svca

    run_fleet ship fleet patch
    [ "$status" -eq 0 ]
    [[ "$output" != *"would finish"* ]]
    [[ "$output" == *"no changes"* ]]
}

@test "CLI: --local cannot finish a member: the plan says BLOCKED and the apply refuses before touching any member" {
    cli_env
    mk_remote_member svca
    mk_remote_member svcb
    # The stranded member is LAST in the roster, so "svcb did not move" can
    # only hold if the refusal came before the member loop started.
    write_fleet_root svcb svca
    strand_member svca
    local head_b
    head_b="$(git -C "$SCRATCH/work/svcb" rev-parse HEAD)"

    run_fleet ship fleet patch --local
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"--local cannot finish one"* ]]

    run_fleet ship fleet patch --local -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"svca: v1.2.4 is an unfinished release; --local cannot finish it."* ]]
    [[ "$output" == *"No member was touched."* ]]
    [ "$(git -C "$SCRATCH/work/svcb" rev-parse HEAD)" = "$head_b" ]
    [ "$(tr -d '[:space:]' < "$SCRATCH/work/svcb/VERSION")" = "1.2.3" ]
}

@test "CLI: an unfinished member that cannot be finished is BLOCKED in the plan, and the apply touches no member" {
    cli_env
    mk_remote_member svca
    mk_remote_member svcb
    write_fleet_root svcb svca
    strand_member svca
    echo "work in progress" >> "$SCRATCH/work/svca/notes.txt"
    local head_b
    head_b="$(git -C "$SCRATCH/work/svcb" rev-parse HEAD)"

    run_fleet ship fleet patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"unfinished v1.2.4: dirty-tree"* ]]
    [[ "$output" != *"would finish"*"svca"* ]]

    run_fleet ship fleet patch -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"svca: v1.2.4 is an unfinished release and cannot be finished from its current state (unfinished v1.2.4: dirty-tree"* ]]
    [[ "$output" == *"No member was touched."* ]]
    # svcb is releaseable and FIRST: it would have shipped before the fleet
    # reached svca if the refusal had been left to the member's own finish.
    [ "$(git -C "$SCRATCH/work/svcb" rev-parse HEAD)" = "$head_b" ]
    [ "$(tr -d '[:space:]' < "$SCRATCH/work/svcb/VERSION")" = "1.2.3" ]
    refute git --git-dir="$SCRATCH/svcb-origin.git" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}'
}

@test "CLI: a member with its own tag prefix is planned as a finish, not as a new release" {
    # The fleet plan runs under the ROOT's configuration. The member's tag is
    # read from its own in-flight record, so the plan and the apply agree.
    cli_env
    mk_remote_member svca
    printf 'git:\n  tag_prefix: "rel-"\n' > "$SCRATCH/work/svca/manifest.config.yaml"
    git -C "$SCRATCH/work/svca" add manifest.config.yaml
    git -C "$SCRATCH/work/svca" commit -qm "own tag prefix"
    git -C "$SCRATCH/work/svca" push -q origin main
    write_fleet_root svca

    # Strand it the same way; its tag is rel-1.2.4.
    : > "$SCRATCH/refuse-push-svca"
    cd "$SCRATCH/work/svca"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship repo patch -y
    [ "$status" -ne 0 ]
    rm -f "$SCRATCH/refuse-push-svca"
    git -C "$SCRATCH/work/svca" rev-parse -q --verify 'refs/tags/rel-1.2.4^{commit}' >/dev/null
    grep -q '^tag=rel-1\.2\.4$' "$SCRATCH/work/svca/.git/manifest-ship/in-flight"

    run_fleet ship fleet patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.2.4 (finish)"* ]]
    [[ "$output" == *"would finish"* ]]
    [[ "$output" != *"1.2.4->1.2.5"* ]]

    run_fleet ship fleet patch -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"svca: finishing v1.2.4 (no bump)"* ]]
    git --git-dir="$SCRATCH/svca-origin.git" rev-parse -q --verify 'refs/tags/rel-1.2.4^{commit}' >/dev/null
    [ "$(tr -d '[:space:]' < "$SCRATCH/work/svca/VERSION")" = "1.2.4" ]
}
