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

@test "upgrade: never reverses a decision written as a wider pattern (TRACKER §1(a))" {
    # The decision "keep .claude/settings.json out" written the way this repo
    # writes it: ignore the directory's content, re-include two subdirectories.
    # The old guard looked only for the literal line `.claude/settings.json`,
    # found nothing, and appended `!.claude/settings.json` — re-including the
    # file Claude Code writes absolute home paths into.
    printf 'node_modules/\n.claude/*\n!.claude/agents/\n!.claude/commands/\n' > "$GI"

    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    refute grep -qx '!.claude/settings.json' "$GI"
    # Same decision, same reason: nothing else under .claude/ is re-included.
    refute grep -qx '!.claude/skills/' "$GI"
    # `run` captures stderr with stdout, which is where the skip notice goes.
    [[ "$output" == *"skipped '!.claude/settings.json' — '.claude/*' already decides .claude/settings.json is ignored here"* ]]

    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    mkdir -p .claude && : > .claude/settings.json
    run git check-ignore -q .claude/settings.json
    [ "$status" -eq 0 ]
}

@test "upgrade: a wider decision to KEEP a path blocks the narrower rule to ignore it" {
    # The mirror image: `!*.key` is a decision to keep every .key file, so the
    # advised rule to ignore them is skipped.
    printf 'node_modules/\n!*.key\n' > "$GI"
    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    refute grep -qx '\*.key' "$GI"
    [[ "$output" == *"skipped '*.key' — '!*.key' already decides *.key is kept here"* ]]
    # id_rsa carries no .key suffix, so !*.key decides nothing about it: appended.
    grep -qx 'id_rsa' "$GI"
}

@test "positive control: a negation the file says nothing about IS still appended" {
    # The guard discriminates: with no .claude decision at all, the re-include
    # is advice the file lacks, and it lands as before.
    printf 'node_modules/\n' > "$GI"
    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    grep -qx '!.claude/settings.json' "$GI"
    grep -qx '.claude/\*' "$GI"
}

@test "upgrade: a positive rule the file seems to cover is still appended — one sample cannot prove coverage" {
    # `/.env` ignores the sample for the advised `.env` and says nothing about
    # `sub/.env`; `*.pyc` covers one member of `*.py[cod]`. The review found the
    # first cut skipping both on that evidence, losing depth on the security
    # rules the shipped upgrade appends. The cost is one redundant line.
    printf 'node_modules/\n/.env\n*.pyc\n*.log*\n' > "$GI"
    run manifest_gitignore_upgrade "$GI"
    [ "$status" -eq 0 ]
    grep -qx '.env' "$GI"
    grep -qx '\*.py\[cod\]' "$GI"
    grep -qx '\*.log' "$GI"
    [[ "$output" != *"already covers"* ]]

    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    mkdir -p sub && : > sub/.env && : > sub/x.pyo
    run git check-ignore -q sub/.env
    [ "$status" -eq 0 ]
    run git check-ignore -q sub/x.pyo
    [ "$status" -eq 0 ]
}

@test "decisions: the sample path stands in for globs, classes and directories" {
    printf '.claude/*\n*.py[cod]\n.DS_Store?\nbuild/\n' > "$GI"
    run _manifest_gitignore_decisions "$GI" $'!.claude/settings.json\n*.pyc\n.DS_Store?\n/build/\nnothing/here\n'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = ".claude/*" ]
    [ "${lines[1]}" = "*.py[cod]" ]
    [ "${lines[2]}" = ".DS_Store?" ]
    [ "${lines[3]}" = "build/" ]
    [ "${lines[4]:-}" = "" ]
}

@test "decisions: machine-local git state never speaks for the file (exported GIT_DIR, init.templateDir)" {
    # The review measured both leaks on the first cut: an exported GIT_DIR made
    # `git init` re-initialise THAT repository and check-ignore answer from its
    # info/exclude; a template directory carrying info/exclude was copied into
    # the scratch repo and consulted. Either way the upgrade printed
    # "skipped — '*.key' already covers it here" for a pattern the file does not
    # contain, and the user's .gitignore never got the key-material rule.
    printf 'node_modules/\n' > "$GI"
    local other="$SCRATCH/other"
    git init -q "$other"
    printf '*.key\n' > "$other/.git/info/exclude"
    run env GIT_DIR="$other/.git" GIT_WORK_TREE="$other" "$BASH" -c 'source "$1"; _manifest_gitignore_decisions "$2" "*.key"' _ "$TEST_REPO_ROOT/modules/core/manifest-init.sh" "$GI"
    [ "$status" -eq 0 ]
    [ "${lines[0]:-}" = "" ]
    # The scratch repository was made, not the other one re-initialised.
    [ -f "$other/.git/info/exclude" ]
    # An empty verdict is also what the git-less fallback prints, so prove the
    # scratch repo WORKED under that environment: the file's own rule decides.
    printf 'node_modules/\n*.key\n' > "$GI"
    run env GIT_DIR="$other/.git" GIT_WORK_TREE="$other" "$BASH" -c 'source "$1"; _manifest_gitignore_decisions "$2" "*.key"' _ "$TEST_REPO_ROOT/modules/core/manifest-init.sh" "$GI"
    [ "${lines[0]:-}" = "*.key" ]
    printf 'node_modules/\n' > "$GI"

    local tmpl="$SCRATCH/template"
    mkdir -p "$tmpl/info"
    printf '*.key\n' > "$tmpl/info/exclude"
    run env HOME="$SCRATCH" GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig" "$BASH" -c 'git config --global init.templateDir "$3"; source "$1"; _manifest_gitignore_decisions "$2" "*.key"' _ "$TEST_REPO_ROOT/modules/core/manifest-init.sh" "$GI" "$tmpl"
    [ "$status" -eq 0 ]
    [ "${lines[0]:-}" = "" ]

    # Positive control: the same two leaks DO decide a sample when the guard is
    # the stock `git init` + unfiltered check-ignore the first cut used.
    local scratch="$SCRATCH/leaky"
    mkdir -p "$scratch"
    run env GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig" "$BASH" -c 'git -C "$1" init -q && cp "$2" "$1/.gitignore" && printf "smp.key\n" | git -C "$1" -c core.excludesFile=/dev/null check-ignore -v -n --no-index --stdin' _ "$scratch" "$GI"
    [[ "$output" == *"info/exclude"*"*.key"* ]]
}

@test "decisions: without git, every rule reads as undecided and the upgrade appends as before" {
    printf '.claude/*\n' > "$GI"
    run env PATH=/nonexistent "$BASH" -c 'source "$1"; _manifest_gitignore_decisions "$2" "!.claude/settings.json"' _ "$TEST_REPO_ROOT/modules/core/manifest-init.sh" "$GI"
    [ "$status" -eq 0 ]
    [ "${lines[0]:-}" = "" ]
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
