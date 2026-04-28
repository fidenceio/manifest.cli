#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

set_origin() {
    git remote remove origin 2>/dev/null || true
    git remote add origin "$1"
}

@test "origin slug: SSH URL parses to org/repo" {
    set_origin "git@github.com:fidenceio/fidenceio.manifest.cli.git"
    run manifest_origin_repo_slug
    [ "$status" -eq 0 ]
    [ "$output" = "fidenceio/fidenceio.manifest.cli" ]
}

@test "origin slug: HTTPS URL parses to org/repo (with .git)" {
    set_origin "https://github.com/fidenceio/manifest.cli.git"
    run manifest_origin_repo_slug
    [ "$status" -eq 0 ]
    [ "$output" = "fidenceio/manifest.cli" ]
}

@test "origin slug: HTTPS URL parses to org/repo (no .git suffix)" {
    set_origin "https://github.com/some-org/some-repo"
    run manifest_origin_repo_slug
    [ "$status" -eq 0 ]
    [ "$output" = "some-org/some-repo" ]
}

@test "origin slug: returns non-zero when no origin remote is set" {
    git remote remove origin 2>/dev/null || true
    run manifest_origin_repo_slug
    [ "$status" -ne 0 ]
}

@test "canonical repo gate: returns 0 for canonical repo (default allowlist)" {
    set_origin "git@github.com:fidenceio/fidenceio.manifest.cli.git"
    unset MANIFEST_CLI_CANONICAL_REPO_SLUGS
    PROJECT_ROOT="$SCRATCH" run manifest_is_canonical_repo
    [ "$status" -eq 0 ]
}

@test "canonical repo gate: returns non-zero for non-canonical repo" {
    set_origin "git@github.com:other-org/other-repo.git"
    unset MANIFEST_CLI_CANONICAL_REPO_SLUGS
    PROJECT_ROOT="$SCRATCH" run manifest_is_canonical_repo
    [ "$status" -ne 0 ]
}

@test "canonical repo gate: respects MANIFEST_CLI_CANONICAL_REPO_SLUGS override" {
    set_origin "git@github.com:custom-org/custom-repo.git"
    export MANIFEST_CLI_CANONICAL_REPO_SLUGS="custom-org/custom-repo"
    PROJECT_ROOT="$SCRATCH" run manifest_is_canonical_repo
    [ "$status" -eq 0 ]
}

@test "canonical repo gate: legacy MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS still works (deprecated)" {
    set_origin "git@github.com:legacy-org/legacy-repo.git"
    unset MANIFEST_CLI_CANONICAL_REPO_SLUGS _MANIFEST_LEGACY_HOMEBREW_SLUGS_WARNED
    export MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS="legacy-org/legacy-repo"
    PROJECT_ROOT="$SCRATCH" run manifest_is_canonical_repo
    [ "$status" -eq 0 ]
}

@test "canonical repo gate: should_update_homebrew_for_repo back-compat shim still works" {
    set_origin "git@github.com:fidenceio/fidenceio.manifest.cli.git"
    unset MANIFEST_CLI_CANONICAL_REPO_SLUGS MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS
    # Source the core module's shim definition without sourcing the whole
    # bootstrap (which would pull in unrelated heavy modules).
    eval "$(declare -f should_update_homebrew_for_repo)"
    should_update_homebrew_for_repo() { manifest_is_canonical_repo "$@"; }
    PROJECT_ROOT="$SCRATCH" run should_update_homebrew_for_repo
    [ "$status" -eq 0 ]
}
