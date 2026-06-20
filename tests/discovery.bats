#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-discovery.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "discovery: version profile scans workspace packages but ignores dependencies" {
    mkdir -p "$SCRATCH/packages/app" "$SCRATCH/node_modules/pkg"
    printf '{"version":"1.0.0"}\n' > "$SCRATCH/packages/app/package.json"
    printf '{"version":"9.9.9"}\n' > "$SCRATCH/node_modules/pkg/package.json"

    run manifest_discovery_find_files "$SCRATCH" 3 0 version package.json
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "packages/app/package.json"
    ! echo "$output" | grep -q "node_modules/pkg/package.json"
}

@test "discovery: fleet profile preserves fleet's package-directory pruning" {
    mkdir -p "$SCRATCH/packages/app"
    printf '{"version":"1.0.0"}\n' > "$SCRATCH/packages/app/package.json"

    run manifest_discovery_find_files "$SCRATCH" 3 0 fleet package.json
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "discovery: git repo finder emits relative path, absolute path, depth, submodule flag" {
    mkdir -p "$SCRATCH/svc"
    git -C "$SCRATCH/svc" init -q

    run manifest_discovery_find_git_repos "$SCRATCH" 2 true 1 fleet
    [ "$status" -eq 0 ]
    [ "${lines[0]%%$'\t'*}" = "svc" ]
    echo "$output" | grep -q "$SCRATCH/svc"
    echo "$output" | grep -q $'\t1\tfalse'
}

@test "discovery: git repo finder prunes at the first repo on a branch when asked" {
    mkdir -p "$SCRATCH/outer"
    git -C "$SCRATCH/outer" init -q
    mkdir -p "$SCRATCH/outer/inner"
    git -C "$SCRATCH/outer/inner" init -q

    # Default (no prune): the nested repo is discovered too.
    run manifest_discovery_find_git_repos "$SCRATCH" 5 true 1 fleet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q $'^outer\t'
    echo "$output" | grep -q "outer/inner"

    # Pruned: discovery stops at the outer repo; the nested repo is not emitted.
    run manifest_discovery_find_git_repos "$SCRATCH" 5 true 1 fleet true
    [ "$status" -eq 0 ]
    echo "$output" | grep -q $'^outer\t'
    ! echo "$output" | grep -q "outer/inner"
}
