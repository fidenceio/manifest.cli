#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH"
    cd "$SCRATCH"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

write_version() {
    echo "$1" > VERSION
}

@test "bump_version: patch increments rightmost component" {
    write_version "1.2.3"
    run bump_version "patch"
    [ "$status" -eq 0 ]
    [ "$(cat VERSION)" = "1.2.4" ]
}

@test "bump_version: minor increments middle and zeros patch" {
    write_version "1.2.3"
    run bump_version "minor"
    [ "$status" -eq 0 ]
    [ "$(cat VERSION)" = "1.3.0" ]
}

@test "bump_version: major increments leftmost and zeros minor+patch" {
    write_version "1.2.3"
    run bump_version "major"
    [ "$status" -eq 0 ]
    [ "$(cat VERSION)" = "2.0.0" ]
}

@test "bump_version: revision adds a fourth component on first call" {
    write_version "1.2.3"
    run bump_version "revision"
    [ "$status" -eq 0 ]
    [ "$(cat VERSION)" = "1.2.3.1" ]
}

@test "bump_version: revision increments existing fourth component" {
    write_version "1.2.3.4"
    run bump_version "revision"
    [ "$status" -eq 0 ]
    [ "$(cat VERSION)" = "1.2.3.5" ]
}

@test "bump_version: rejects unknown increment type" {
    write_version "1.0.0"
    run bump_version "garbage"
    [ "$status" -ne 0 ]
    [ "$(cat VERSION)" = "1.0.0" ]
}

@test "bump_version: fails when VERSION file is absent" {
    [ ! -f VERSION ]
    run bump_version "patch"
    [ "$status" -ne 0 ]
}
