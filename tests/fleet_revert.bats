#!/usr/bin/env bats
# bats file_tags=smoke

load 'helpers/setup'
load 'helpers/preview_no_write'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    ROOT="$SCRATCH/work"
    cd "$ROOT"
    git init -q -b main
    printf 'fleet:\n  name: test-fleet\n  versioning: none\n' > manifest.fleet.config.yaml
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\ntrue\talpha\t./alpha\ttrue\tmain\ntrue\tbeta\t./beta\ttrue\tmain\n' > manifest.fleet.tsv
    printf '/*\n!/.gitignore\n!/manifest.fleet.config.yaml\n!/manifest.fleet.tsv\n!/manifest.fleet.snapshot.json\n' > .gitignore
    local member
    for member in alpha beta; do
        git init -q -b main "$member"
        echo "old-$member" > "$member/content"
        echo 1.0.0 > "$member/VERSION"
        git -C "$member" add content VERSION
        git -C "$member" commit -qm old
        git -C "$member" tag v1.0.0
    done
    ALPHA_OLD="$(git -C alpha rev-parse HEAD)"
    BETA_OLD="$(git -C beta rev-parse HEAD)"
    jq -nS --arg a "$ALPHA_OLD" --arg b "$BETA_OLD" '{kind:"manifest.fleet.snapshot",schema:1,members:[{name:"alpha",path:"alpha",commit:$a},{name:"beta",path:"beta",commit:$b}]}' > manifest.fleet.snapshot.json
    git add .gitignore manifest.fleet.config.yaml manifest.fleet.tsv manifest.fleet.snapshot.json
    git commit -qm 'record fleet snapshot'
    SNAPSHOT="$(git rev-parse HEAD)"
    for member in alpha beta; do
        echo "new-$member" > "$member/content"
        git -C "$member" commit -qam new
        git -C "$member" tag v2.0.0
    done
    ALPHA_NEW="$(git -C alpha rev-parse HEAD)"
    BETA_NEW="$(git -C beta rev-parse HEAD)"
    printf '\n# later manager change\n' >> manifest.fleet.config.yaml
    git commit -qam 'later manager'
    MANAGER_NEW="$(git rev-parse HEAD)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@" < /dev/null
    printf '%s\n' "$output"
}

@test "fleet revert lists snapshots and previews every recorded commit without writes" {
    local before="$(preview_snapshot)"
    run_manifest revert fleet
    [ "$status" -eq 0 ]
    [[ "$output" == *"${SNAPSHOT:0:7}"* ]]
    MANIFEST_CLI_AUTO_CONFIRM=1 run_manifest revert fleet "$SNAPSHOT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"$ALPHA_OLD"* && "$output" == *"$BETA_OLD"* && "$output" == *"$SNAPSHOT"* ]]
    assert_no_writes "$before" "$(preview_snapshot)"
}

@test "fleet revert restores exact member commits and manager last without changing branches or tags" {
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 0 ]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_OLD" ]
    [ "$(git -C beta rev-parse HEAD)" = "$BETA_OLD" ]
    [ "$(git rev-parse HEAD)" = "$SNAPSHOT" ]
    [ "$(cat alpha/content)" = old-alpha ]
    [ "$(cat beta/content)" = old-beta ]
    [ "$(git rev-parse refs/heads/main)" = "$MANAGER_NEW" ]
    [ "$(git -C alpha rev-parse refs/heads/main)" = "$ALPHA_NEW" ]
    [ "$(git -C beta rev-parse refs/tags/v2.0.0)" = "$BETA_NEW" ]
    refute git symbolic-ref -q HEAD
    refute git -C alpha symbolic-ref -q HEAD
    local audit="$HOME/.manifest-cli/audit/apply-events.ndjson"
    [ "$(wc -l < "$audit" | tr -d ' ')" = 3 ]
}

@test "fleet revert refuses dirty member and manager before any checkout" {
    echo pending > beta/content
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'BLOCKED: beta'* ]]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
    [ "$(git rev-parse HEAD)" = "$MANAGER_NEW" ]
    git -C beta checkout -- content
    echo pending >> manifest.fleet.tsv
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'BLOCKED: manager'* ]]
    [ "$(git -C beta rev-parse HEAD)" = "$BETA_NEW" ]
}

commit_bad_snapshot() {
    local filter="$1"
    jq "$filter" manifest.fleet.snapshot.json > "$SCRATCH/map"
    cp "$SCRATCH/map" manifest.fleet.snapshot.json
    git add manifest.fleet.snapshot.json
    git commit -qm 'invalid snapshot fixture'
    BAD="$(git rev-parse HEAD)"
}

@test "fleet revert rejects absent commits malformed maps and incomplete member records" {
    commit_bad_snapshot '.members[1].commit = "0000000000000000000000000000000000000000"'
    run_manifest revert fleet "$BAD" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'Recorded commit is unavailable'* ]]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
    commit_bad_snapshot '.members[1].commit = null'
    run_manifest revert fleet "$BAD" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'Snapshot is invalid'* ]]
}

@test "fleet revert refuses traversal symlink escapes and duplicate repository paths" {
    commit_bad_snapshot '.members[1].path = "../outside"'
    run_manifest revert fleet "$BAD" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'outside the fleet'* ]]
    git init -q -b main "$SCRATCH/outside"
    ln -s "$SCRATCH/outside" escape
    commit_bad_snapshot '.members[1].path = "escape"'
    run_manifest revert fleet "$BAD" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'outside the fleet'* ]]
    commit_bad_snapshot '.members[1].path = "alpha"'
    run_manifest revert fleet "$BAD" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'duplicate or nested'* ]]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
}

@test "fleet revert refuses missing repositories before restoring any member" {
    mv beta "$SCRATCH/beta-away"
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 1 ]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
    [ "$(git rev-parse HEAD)" = "$MANAGER_NEW" ]
}

@test "fleet revert honors a locked later member before any checkout" {
    touch beta/.git/index.lock
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 1 ]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
    [ "$(git rev-parse HEAD)" = "$MANAGER_NEW" ]
}

@test "fleet revert reports partial checkout failure and preserves conflicting ignored files" {
    git -C beta rm -q content
    git -C beta commit -qm 'remove target file'
    local beta_before="$(git -C beta rev-parse HEAD)"
    echo content >> beta/.git/info/exclude
    echo private > beta/content
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 2 ]
    [[ "$output" == *'stopped at beta; 1 checkouts completed'* ]]
    [ "$(cat beta/content)" = private ]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_OLD" ]
    [ "$(git -C beta rev-parse HEAD)" = "$beta_before" ]
    [ "$(git rev-parse HEAD)" = "$MANAGER_NEW" ]
}

@test "fleet revert help works outside git and apply requires an explicit snapshot" {
    run_manifest revert fleet -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'Name a snapshot'* ]]
    mkdir "$SCRATCH/plain"
    cd "$SCRATCH/plain"
    run_manifest revert fleet --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'Usage: manifest revert fleet'* ]]
}

@test "fleet revert rejects conflicting modes unsupported flags and commits without snapshots" {
    local args
    for args in "--dry-run -y" "-y --dry-run" "--force" "--local"; do
        local -a argv
        read -r -a argv <<< "$args"
        run_manifest revert fleet "$SNAPSHOT" "${argv[@]}"
        [ "$status" -eq 1 ]
    done
    git rm -q manifest.fleet.snapshot.json
    git commit -qm 'remove snapshot fixture'
    run_manifest revert fleet HEAD -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'has no recorded fleet snapshot'* ]]
}

@test "normal fleet ship records the actual member commits in the manager history" {
    printf '\n# pending manager change\n' >> manifest.fleet.config.yaml
    run_manifest ship fleet patch --local -y
    [ "$status" -eq 0 ]
    local map="$(git show HEAD:manifest.fleet.snapshot.json)"
    local alpha_after="$(git -C alpha rev-parse HEAD)" beta_after="$(git -C beta rev-parse HEAD)"
    jq -e --arg a "$alpha_after" --arg b "$beta_after" '.members[0].commit==$a and .members[1].commit==$b' <<< "$map"
    [ "$(git tag | wc -l | tr -d ' ')" = 0 ]
    [ "$alpha_after" != "$ALPHA_OLD" ]
    [ "$beta_after" != "$BETA_OLD" ]
    local latest="$(git rev-parse HEAD)"
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$SNAPSHOT" ]
    run_manifest revert fleet
    [ "$status" -eq 0 ]
    [[ "$output" == *"${latest:0:7}"* ]]
}

@test "fleet ship refuses a user file at the reserved snapshot path before releasing members" {
    echo private > manifest.fleet.snapshot.json
    git add manifest.fleet.snapshot.json
    git commit -qm 'user file fixture'
    echo releasable > alpha/new-file
    run_manifest ship fleet patch --local -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'Reserved fleet snapshot path'* ]]
    [ "$(cat manifest.fleet.snapshot.json)" = private ]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
    git checkout "$SNAPSHOT" -- manifest.fleet.snapshot.json
    git commit -qm 'restore owned snapshot'
    git rm -q manifest.fleet.snapshot.json
    run_manifest ship fleet patch --local -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'uncommitted edits or a deletion'* ]]
    refute test -e manifest.fleet.snapshot.json
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
}

@test "first fleet snapshot is committed even when a preserved gitignore ignores the map" {
    git rm -q manifest.fleet.snapshot.json
    printf '/*\n!/.gitignore\n!/manifest.fleet.config.yaml\n!/manifest.fleet.tsv\n' > .gitignore
    git add .gitignore
    git commit -qm 'legacy fleet without snapshot'
    local legacy="$(git rev-parse HEAD)"
    printf '\n# manager work\n' >> manifest.fleet.config.yaml
    run_manifest ship fleet patch --local
    [ "$status" -eq 0 ]
    [[ "$output" == *'manifest.fleet.snapshot.json'* ]]
    refute test -e manifest.fleet.snapshot.json
    run_manifest ship fleet patch --local -y
    [ "$status" -eq 0 ]
    git cat-file -e HEAD:manifest.fleet.snapshot.json
    git ls-files --error-unmatch manifest.fleet.snapshot.json
    refute git diff --quiet "$legacy" HEAD -- manifest.fleet.snapshot.json
    run_manifest revert fleet HEAD --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"$(git -C alpha rev-parse HEAD)"* ]]
}

@test "fleet revert uses the required yq parser without needing jq at runtime" {
    mkdir "$SCRATCH/bin"
    printf '#!/bin/sh\necho unexpected-jq >&2\nexit 99\n' > "$SCRATCH/bin/jq"
    chmod +x "$SCRATCH/bin/jq"
    PATH="$SCRATCH/bin:$PATH" run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 0 ]
    [[ "$output" != *unexpected-jq* ]]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_OLD" ]
}

@test "fleet snapshots restore from cloned manager and member history" {
    git clone -q "$ROOT" "$SCRATCH/cloned"
    git clone -q "$ROOT/alpha" "$SCRATCH/cloned/alpha"
    git clone -q "$ROOT/beta" "$SCRATCH/cloned/beta"
    cd "$SCRATCH/cloned"
    run_manifest revert fleet "$SNAPSHOT" -y
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$SNAPSHOT" ]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_OLD" ]
    [ "$(git -C beta rev-parse HEAD)" = "$BETA_OLD" ]
}

@test "fleet revert refuses invalid member shapes and control characters before checkouts" {
    commit_bad_snapshot '.members[0].path = "alpha\u0000"'
    run_manifest revert fleet "$BAD" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'Snapshot is invalid'* ]]
    commit_bad_snapshot '.members[0] = {name: [], path: "alpha", commit: "bad"}'
    run_manifest revert fleet "$BAD" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'Snapshot is invalid'* ]]
    [ "$(git -C alpha rev-parse HEAD)" = "$ALPHA_NEW" ]
    [ "$(git -C beta rev-parse HEAD)" = "$BETA_NEW" ]
}
