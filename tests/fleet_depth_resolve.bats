#!/usr/bin/env bats
#
# §7.3: unified fleet --depth resolution — one flag, one meaning, one cap.
# `auto` is per-branch adaptive (one pruned scan; resolves to the DEEPEST depth
# that finds a git repo, capped); an explicit integer is clamped to [MIN, cap];
# bad specs are rejected.

load 'helpers/setup'

setup() {
    load_modules "fleet/manifest-fleet-detect.sh"
    SCRATCH="$(mk_scratch)"
    WS="$SCRATCH/ws"
    mkdir -p "$WS"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

mkrepo() { mkdir -p "$1" && git init -q "$1"; }

@test "depth: cap getter is the single downward ceiling" {
    run manifest_fleet_depth_cap
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "depth: explicit integer is clamped to [MIN, cap]" {
    [ "$(manifest_fleet_resolve_depth 3 "$WS")" = "3" ]
    [ "$(manifest_fleet_resolve_depth 0 "$WS")" = "1" ]
    [ "$(manifest_fleet_resolve_depth 99 "$WS")" = "10" ]
}

@test "depth: a non-integer, non-auto spec is rejected" {
    run manifest_fleet_resolve_depth "deep" "$WS"
    [ "$status" -ne 0 ]
}

@test "depth: auto settles at depth 1 for direct-child repos" {
    mkrepo "$WS/alpha"
    mkrepo "$WS/beta"
    [ "$(manifest_fleet_resolve_depth auto "$WS")" = "1" ]
}

@test "depth: auto reaches a repo nested below the top level" {
    mkrepo "$WS/group/gamma"   # repo at depth 2; nothing at depth 1
    [ "$(manifest_fleet_resolve_depth auto "$WS")" = "2" ]
}

@test "depth: auto reaches the DEEPEST repo in a mixed-depth workspace" {
    mkrepo "$WS/alpha"          # repo at depth 1
    mkrepo "$WS/group/gamma"    # repo at depth 2
    [ "$(manifest_fleet_resolve_depth auto "$WS")" = "2" ]
}

@test "depth: auto prunes nested repos (a repo inside a repo is not deeper)" {
    mkrepo "$WS/outer"
    mkrepo "$WS/outer/inner"    # nested repo — pruned, not a fleet member
    [ "$(manifest_fleet_resolve_depth auto "$WS")" = "1" ]
}

@test "depth: auto falls back to the cap when no repos exist" {
    mkdir -p "$WS/plain/sub"   # no git repos anywhere
    [ "$(manifest_fleet_resolve_depth auto "$WS")" = "10" ]
}

@test "depth: an empty spec defaults to auto" {
    mkrepo "$WS/alpha"
    [ "$(manifest_fleet_resolve_depth "" "$WS")" = "1" ]
}
