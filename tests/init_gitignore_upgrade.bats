#!/usr/bin/env bats

# Coverage for manifest_gitignore_upgrade — the append-only migration that brings
# a .gitignore written by an older CLI up to the current advised set.
#
# The motivating case: a repo scaffolded before the KEY MATERIAL block existed
# has no rule for *.key / id_rsa / *.p12, and nothing would ever add one. The
# release commit is a bare `git add .` and no gate scans for key material, so
# such a repo ships a private key silently the first time one appears.
#
# The routine must never *reduce* protection or reverse a deliberate choice, so
# most of what is pinned here is what it refuses to do.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    GI="$PROJ/.gitignore"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- the migration itself -----------------------------------------------------

@test "upgrade: an old .gitignore gains the key-material rules" {
    printf 'node_modules/\n*.log\n' > "$GI"
    refute grep -qx '\*.key' "$GI"

    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    [[ "$output" == *":upgraded:"* ]]

    grep -qx '\*.key' "$GI"
    grep -qx 'id_rsa' "$GI"
    grep -qx '\*.p12' "$GI"
}

@test "upgrade: the pre-existing content is preserved verbatim" {
    printf 'node_modules/\n# my comment\n!keep-me.log\n*.log\n' > "$GI"
    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]

    # Original lines still present, still in their original relative order.
    run head -4 "$GI"
    [ "${lines[0]}" = "node_modules/" ]
    [ "${lines[1]}" = "# my comment" ]
    [ "${lines[2]}" = "!keep-me.log" ]
    [ "${lines[3]}" = "*.log" ]
}

@test "upgrade: appended negations still land after their rules (git honors them)" {
    printf 'node_modules/\n' > "$GI"
    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]

    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    : > server.key
    : > mykey.pub
    run git check-ignore server.key
    [ "$status" -eq 0 ]
    run git check-ignore mykey.pub
    [ "$status" -ne 0 ]
}

@test "upgrade: is idempotent — a second run appends nothing" {
    printf 'node_modules/\n' > "$GI"
    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    local after_first
    after_first="$(wc -l < "$GI")"

    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    [[ "$output" == *":current"* ]]
    [ "$(wc -l < "$GI")" -eq "$after_first" ]
}

@test "upgrade: a file already carrying the advice reports current, writes nothing" {
    create_default_gitignore "$GI"
    local before
    before="$(md5 -q "$GI" 2>/dev/null || md5sum "$GI" | cut -d' ' -f1)"

    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    [[ "$output" == *":current"* ]]
    [ "$(md5 -q "$GI" 2>/dev/null || md5sum "$GI" | cut -d' ' -f1)" = "$before" ]
}

# --- what it must refuse to do ------------------------------------------------

@test "upgrade: never reverses a deliberate re-include" {
    # A repo that has decided '!*.key' on purpose must not silently get '*.key'
    # appended underneath it, which would start ignoring the file they kept.
    printf 'node_modules/\n!*.key\n' > "$GI"

    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    refute grep -qx '\*.key' "$GI"

    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    : > server.key
    run git check-ignore server.key
    [ "$status" -ne 0 ]
}

@test "upgrade: refuses a missing file rather than creating one" {
    run manifest_gitignore_upgrade "$PROJ/does-not-exist"
    [ "$status" -eq 1 ]
    [ ! -e "$PROJ/does-not-exist" ]
}

# --- wiring: which callers may mutate ----------------------------------------

@test "ensure_gitignore_smart: defaults to report-only and writes nothing" {
    printf 'node_modules/\n' > "$GI"
    local before
    before="$(md5 -q "$GI" 2>/dev/null || md5sum "$GI" | cut -d' ' -f1)"

    run ensure_gitignore_smart "$PROJ"
    [ "$status" -eq 0 ]
    [[ "$output" == *".gitignore:preserved"* ]]
    [ "$(md5 -q "$GI" 2>/dev/null || md5sum "$GI" | cut -d' ' -f1)" = "$before" ]
}

@test "ensure_gitignore_smart: upgrade mode appends and reports the count" {
    printf 'node_modules/\n' > "$GI"
    run ensure_gitignore_smart "$PROJ" upgrade
    [ "$status" -eq 0 ]
    [[ "$output" == *".gitignore:upgraded:"* ]]
    grep -qx '\*.key' "$GI"
}

@test "ensure_gitignore_smart: an absent .gitignore is created, not upgraded" {
    run ensure_gitignore_smart "$PROJ" upgrade
    [ "$status" -eq 0 ]
    [[ "$output" == *".gitignore"* ]]
    [[ "$output" != *"upgraded"* ]]
    grep -qx '\*.key' "$GI"
}

@test "ship path does not opt into upgrade mode" {
    # The release path calls ensure_required_files with no mode, so a .gitignore
    # is never mutated during a ship. If this changes, the transaction map's
    # side-effect boundary changes with it.
    grep -qF 'ensure_required_files "$MANIFEST_CLI_PROJECT_ROOT"' \
        "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    refute grep -qE 'ensure_required_files "\$MANIFEST_CLI_PROJECT_ROOT" +"?upgrade' \
        "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
}
