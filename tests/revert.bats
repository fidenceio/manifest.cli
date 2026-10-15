#!/usr/bin/env bats
# bats file_tags=smoke

load 'helpers/setup'
load 'helpers/preview_no_write'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    cd "$SCRATCH/work"
    git init -q -b main
    echo old > payload
    git add payload
    git commit -qm old
    OLD="$(git rev-parse HEAD)"
    git tag -am 'old version' v1.0.0
    echo new > payload
    echo keep > later
    git add payload later
    git commit -qm new
    NEW="$(git rev-parse HEAD)"
    git tag v2.0.0
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_revert() {
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" revert "$@" < /dev/null
}

@test "revert repo bare and explicit previews never write or check out, even with auto-confirm" {
    mkdir -p "$HOME/.manifest-cli"
    printf 'debug:\n  enabled: false\n' > "$HOME/.manifest-cli/manifest.config.global.yaml"
    local before="$(preview_snapshot)" args
    for args in 'repo' 'repo v1.0.0' 'repo v1.0.0 --dry-run'; do
        local -a argv
        read -r -a argv <<< "$args"
        MANIFEST_CLI_AUTO_CONFIRM=1 run_revert "${argv[@]}"
        [ "$status" -eq 0 ]
        [[ "$output" == *'No changes written'* ]]
        assert_no_writes "$before" "$(preview_snapshot)"
        [ "$(git rev-parse HEAD)" = "$NEW" ]
        [ "$(git branch --show-current)" = main ]
    done
}

@test "revert requires an explicit supported scope and refuses legacy targets without writes" {
    local before="$(preview_snapshot)" args
    for args in '' 'v1.0.0 -y' 'bogus -y'; do
        local -a argv
        read -r -a argv <<< "$args"
        run_revert "${argv[@]}"
        [ "$status" -eq 1 ]
        [[ "$output" == *'revert requires a scope'* || "$output" == *'Unknown revert scope'* ]]
        assert_no_writes "$before" "$(preview_snapshot)"
    done
}

@test "revert repo apply checks out the exact annotated tag despite a same-named branch and no origin" {
    git branch v1.0.0
    run_revert repo v1.0.0 -y
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$OLD" ]
    refute git symbolic-ref -q HEAD
    [ "$(git rev-parse refs/heads/main)" = "$NEW" ]
    [ "$(git rev-parse refs/heads/v1.0.0)" = "$NEW" ]
    [ "$(cat payload)" = old ]
    refute test -e later
    local audit="$HOME/.manifest-cli/audit/apply-events.ndjson"
    [ "$(wc -l < "$audit" | tr -d ' ')" = 1 ]
    jq -e '.command == "manifest revert repo v1.0.0 -y"' "$audit"
    run git switch -
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = main ]
    [ "$(git rev-parse HEAD)" = "$NEW" ]
}

@test "revert repo --yes works from detached HEAD" {
    git checkout -q --detach "$OLD"
    run_revert repo v2.0.0 --yes
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$NEW" ]
    refute git symbolic-ref -q HEAD
}

@test "revert repo requires a tag when applying without a terminal" {
    local before="$(preview_snapshot)"
    run_revert repo -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'Name a tag to apply non-interactively'* ]]
    assert_no_writes "$before" "$(preview_snapshot)"
}

@test "revert repo refuses branches revision expressions invalid options and conflicting modes" {
    local before="$(preview_snapshot)" args
    for args in 'main -y' 'missing -y' 'v1.0.0~0 -y' 'v1.0.0 v2.0.0 -y' 'v1.0.0 --force -y' 'v1.0.0 --local -y' 'v1.0.0 -y --dry-run' 'v1.0.0 --dry-run --yes'; do
        local -a argv
        read -r -a argv <<< "$args"
        run_revert repo "${argv[@]}"
        [ "$status" -eq 1 ]
        assert_no_writes "$before" "$(preview_snapshot)"
    done
}

@test "revert repo preserves tracked changes that conflict with the target" {
    echo pending > payload
    run_revert repo v1.0.0 -y
    [ "$status" -eq 1 ]
    [[ "$output" == *'would be overwritten'* ]]
    [ "$(cat payload)" = pending ]
    [ "$(git rev-parse HEAD)" = "$NEW" ]
    [ "$(git branch --show-current)" = main ]
}

@test "revert repo preserves unrelated tracked changes during checkout" {
    git checkout -q -b newer
    echo unchanged > unrelated
    git add unrelated
    git commit -qm 'add unrelated file'
    git tag v3.0.0
    echo latest > payload
    git commit -qam latest
    echo pending > unrelated
    run_revert repo v3.0.0 -y
    [ "$status" -eq 0 ]
    [ "$(cat payload)" = new ]
    [ "$(cat unrelated)" = pending ]
    [ "$(git diff --name-only)" = unrelated ]
}

@test "revert repo preserves conflicting untracked files" {
    git checkout -q --detach "$OLD"
    echo pending > later
    run_revert repo v2.0.0 -y
    [ "$status" -eq 1 ]
    [ "$(cat later)" = pending ]
    [ "$(git rev-parse HEAD)" = "$OLD" ]
}

@test "revert repo preserves conflicting ignored files" {
    git checkout -q --detach "$OLD"
    echo later >> .git/info/exclude
    echo pending > later
    run_revert repo v2.0.0 -y
    [ "$status" -eq 1 ]
    [ "$(cat later)" = pending ]
    [ "$(git rev-parse HEAD)" = "$OLD" ]
}

@test "revert repo honors the Git write-access guard before checkout" {
    touch .git/index.lock
    run_revert repo v1.0.0 -y
    [ "$status" -eq 1 ]
    [ "$(git rev-parse HEAD)" = "$NEW" ]
    [ "$(cat payload)" = new ]
}

@test "revert repo never recurses into submodule working trees even with recurse enabled" {
    git init -q -b main "$SCRATCH/child"
    echo first > "$SCRATCH/child/content"
    git -C "$SCRATCH/child" add content
    git -C "$SCRATCH/child" commit -qm first
    local first="$(git -C "$SCRATCH/child" rev-parse HEAD)"
    echo second > "$SCRATCH/child/content"
    git -C "$SCRATCH/child" commit -qam second
    git -c protocol.file.allow=always submodule add -q "$SCRATCH/child" nested
    git commit -qam 'add submodule at second'
    git tag v3.0.0
    git -C nested checkout -q --detach "$first"
    git add nested
    git commit -qm 'submodule at first'
    git config submodule.recurse true

    run_revert repo v3.0.0 -y
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse v3.0.0)" ]
    [ "$(git -C nested rev-parse HEAD)" = "$first" ]
    [ "$(cat nested/content)" = first ]
}

@test "revert completion offers the actual local tags and apply flags" {
    source "$TEST_REPO_ROOT/completions/manifest.bash"
    COMP_CWORD=3
    COMP_WORDS=(manifest revert repo '')
    _manifest_complete
    [[ " ${COMPREPLY[*]} " == *' v1.0.0 '* ]]
    [[ " ${COMPREPLY[*]} " == *' v2.0.0 '* ]]
    [[ " ${COMPREPLY[*]} " == *' --yes '* ]]
    [[ " ${COMPREPLY[*]} " != *' fleet '* ]]
    COMP_CWORD=4
    COMP_WORDS=(manifest revert repo v1.0.0 --)
    _manifest_complete
    [[ " ${COMPREPLY[*]} " == *' --yes '* ]]
    [[ " ${COMPREPLY[*]} " != *' --local '* ]]
    [[ " ${COMPREPLY[*]} " != *' --force '* ]]
}

@test "revert help works without git and no-tag inspection reports missing local tags" {
    git tag -d v1.0.0 v2.0.0
    run_revert repo
    [ "$status" -eq 1 ]
    [[ "$output" == *'No version tags found'* ]]
    mkdir "$SCRATCH/plain"
    cd "$SCRATCH/plain"
    run_revert repo --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'Usage: manifest revert repo'* ]]
    [[ "$output" == *'--dry-run'* ]]
    run_revert repo v1.0.0
    [ "$status" -eq 1 ]
    [[ "$output" == *'repo scope requires running inside a Git repository'* ]]
}
