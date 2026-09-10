#!/usr/bin/env bats
# §77(a) — the coordination root's file set is declared, not hard-coded.
#
# The root could only ever carry five names, all literals in the source, so a
# fleet coordinating on anything else — a host/port map, a runbook, an
# inventory — had no way to get it committed. Re-including it in .gitignore by
# hand was not enough: the stager force-adds by NAME, and the name was not on
# the list.
#
# The set stays an ALLOWLIST. A declared entry must be a plain file name at the
# root, so it can never reach a member repository, a parent directory, or the
# config layers Manifest itself reads.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/root"
    export HOME
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
    export MANIFEST_CLI_RELEASE_GATE=none
    export MANIFEST_CLI_DOCS_HANDOFF=off
    ROOT="$SCRATCH/root"
}

teardown() {
    unset MANIFEST_CLI_RELEASE_GATE MANIFEST_CLI_DOCS_HANDOFF MANIFEST_CLI_FLEET_ROOT
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT MANIFEST_CLI_TIME_RETRIES
    cd /tmp
    rm -rf "$SCRATCH"
}

# A coordination root whose config declares $@ as extra coordination files.
write_root() {
    git init -q -b main "$ROOT"
    git -C "$ROOT" config user.email t@example.com
    git -C "$ROOT" config user.name T
    {
        printf 'fleet:\n  name: "test-fleet"\n  versioning: "semver"\n  version_file: "FLEET_VERSION"\n'
        if [ "$#" -gt 0 ]; then
            printf '  coordination_files:\n'
            local n
            for n in "$@"; do printf '    - %s\n' "$n"; done
        fi
        printf 'services: {}\n'
    } > "$ROOT/manifest.fleet.config.yaml"
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\n' > "$ROOT/manifest.fleet.tsv"
    echo "1.0.0" > "$ROOT/FLEET_VERSION"
    git -C "$ROOT" commit -q --allow-empty -m "seed"
}

# The resolved set, one name per line.
coordination_set() {
    bash -c '
        cd "'"$ROOT"'" || exit 1
        export MANIFEST_CLI_CORE_MODULES_DIR="'"$TEST_REPO_ROOT"'/modules"
        export MANIFEST_CLI_FLEET_ROOT="'"$ROOT"'"
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-core.sh" >/dev/null 2>&1
        source "'"$TEST_REPO_ROOT"'/modules/fleet/manifest-fleet.sh" >/dev/null 2>&1
        _fleet_coordination_files "'"$ROOT"'" 2>/dev/null
    '
}

run_manifest() {
    cd "$ROOT"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# --- resolution ------------------------------------------------------------

@test "CONTROL: with nothing declared the set is exactly the fixed five" {
    write_root
    local got; got="$(coordination_set)"
    [ "$(printf '%s\n' "$got" | grep -c .)" -eq 5 ]
    [[ "$got" == *".gitignore"* ]]
    [[ "$got" == *"manifest.fleet.config.yaml"* ]]
    [[ "$got" == *"manifest.fleet.tsv"* ]]
    [[ "$got" == *"FLEET_VERSION"* ]]
    [[ "$got" == *"CHANGELOG_FLEET.md"* ]]
}

@test "declared names join the set, after the fixed ones" {
    write_root host-ports.yaml runbook.md
    local got; got="$(coordination_set)"
    [[ "$got" == *"host-ports.yaml"* ]]
    [[ "$got" == *"runbook.md"* ]]
    # Order matters: the fixed names must not shift, or every existing root's
    # .gitignore reads stale and rewrites itself.
    # Captured and sliced, never piped into head (suite_shell_options.bats).
    [ "${got%%$'\n'*}" = ".gitignore" ]
    [ "$(printf '%s\n' "$got" | sed -n '5p')" = "CHANGELOG_FLEET.md" ]
}

@test "a comma-separated scalar is accepted as well as a YAML list" {
    git init -q -b main "$ROOT"
    git -C "$ROOT" config user.email t@example.com
    git -C "$ROOT" config user.name T
    printf 'fleet:\n  name: "f"\n  versioning: "none"\n  coordination_files: "host-ports.yaml, runbook.md"\nservices: {}\n' \
        > "$ROOT/manifest.fleet.config.yaml"
    git -C "$ROOT" commit -q --allow-empty -m seed
    local got; got="$(coordination_set)"
    [[ "$got" == *"host-ports.yaml"* ]]
    [[ "$got" == *"runbook.md"* ]]
}

# --- the allowlist stays an allowlist --------------------------------------

@test "a path escape is refused, so a declared entry can never leave the root" {
    write_root ../escape.yaml "sub/dir.yaml" "*.yaml"
    local got; got="$(coordination_set)"
    [[ "$got" != *"escape"* ]]
    [[ "$got" != *"sub/"* ]]
    [[ "$got" != *"*"* ]]
    [ "$(printf '%s\n' "$got" | grep -c .)" -eq 5 ]
}

@test "the config layers Manifest reads at a root are refused" {
    # manifest.config.yaml is the FLEET-SHARED layer every member inherits;
    # manifest.config.local.yaml is deliberately untracked and must never be
    # pulled into the allowlist.
    write_root manifest.config.yaml manifest.config.local.yaml
    local got; got="$(coordination_set)"
    [[ "$got" != *"manifest.config.yaml"* ]] || {
        # the fleet config is a different file; assert the plain layer is absent
        [ "$(printf '%s\n' "$got" | grep -cx 'manifest.config.yaml')" -eq 0 ]
    }
    [ "$(printf '%s\n' "$got" | grep -cx 'manifest.config.local.yaml')" -eq 0 ]
}

@test "git metadata names are refused, case-folded" {
    write_root .git .GIT .gitmodules
    local got; got="$(coordination_set)"
    [ "$(printf '%s\n' "$got" | grep -cix '\.git')" -eq 0 ]
    [ "$(printf '%s\n' "$got" | grep -cix '\.gitmodules')" -eq 0 ]
}

@test "duplicates and names already in the fixed set are dropped" {
    write_root host-ports.yaml host-ports.yaml FLEET_VERSION .gitignore
    local got; got="$(coordination_set)"
    [ "$(printf '%s\n' "$got" | grep -cx 'host-ports.yaml')" -eq 1 ]
    [ "$(printf '%s\n' "$got" | grep -cx 'FLEET_VERSION')" -eq 1 ]
    [ "$(printf '%s\n' "$got" | grep -cx '.gitignore')" -eq 1 ]
}

# --- end to end through the manager ----------------------------------------

@test "a declared file is re-included in .gitignore and committed by the manager" {
    write_root host-ports.yaml
    printf 'web: 8080\n' > "$ROOT/host-ports.yaml"
    printf 'secret: never\n' > "$ROOT/secrets.env"

    run_manifest ship fleet manager --local -y
    [ "$status" -eq 0 ]

    # The allowlist learned the name...
    grep -qx '!/host-ports.yaml' "$ROOT/.gitignore"
    # ...so the operator's own `git add .` sees it too.
    refute git -C "$ROOT" check-ignore -q host-ports.yaml
    # ...and it is tracked, while a non-declared file is not.
    git -C "$ROOT" ls-files --error-unmatch host-ports.yaml >/dev/null
    refute git -C "$ROOT" ls-files --error-unmatch secrets.env
    git -C "$ROOT" check-ignore -q secrets.env
}

@test "changing a declared file is picked up by the next manager run" {
    write_root host-ports.yaml
    printf 'web: 8080\n' > "$ROOT/host-ports.yaml"
    run_manifest ship fleet manager --local -y
    [ "$status" -eq 0 ]

    printf 'web: 8081\n' > "$ROOT/host-ports.yaml"
    run_manifest ship fleet manager --local -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"host-ports.yaml"* ]]
    local committed
    committed="$(git -C "$ROOT" show HEAD:host-ports.yaml)"
    [ "$committed" = "web: 8081" ]
    [ -z "$(git -C "$ROOT" status --porcelain)" ]
}

@test "CONTROL: an undeclared file at the root is never staged" {
    write_root
    printf 'web: 8080\n' > "$ROOT/host-ports.yaml"

    run_manifest ship fleet manager --local -y
    [ "$status" -eq 0 ]

    refute git -C "$ROOT" ls-files --error-unmatch host-ports.yaml
    git -C "$ROOT" check-ignore -q host-ports.yaml
}
