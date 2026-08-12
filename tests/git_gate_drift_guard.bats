#!/usr/bin/env bats
# manifest_unstage_gate_drift — the post-`git add .` guard that keeps work which
# landed AFTER a ship was requested out of that release. Origin: a full-tier
# release gate runs for minutes, and the auto-commit stages whatever the tree
# looks like once it finishes, so a concurrent session's in-flight files were
# swept into two manifest.cli releases (58.0.1, 58.0.2) that never meant to
# carry them.

load 'helpers/setup'

setup() {
    load_modules 'git/manifest-git.sh'
    SCRATCH="$(mk_scratch)"
    export GIT_AUTHOR_NAME="bats" GIT_AUTHOR_EMAIL="bats@example"
    export GIT_COMMITTER_NAME="bats" GIT_COMMITTER_EMAIL="bats@example"
    unset MANIFEST_CLI_GIT_ALLOW_GATE_DRIFT MANIFEST_CLI_GIT_PENDING_SNAPSHOT
    REPO="$SCRATCH/repo"
    mk_repo "$REPO"
    # commit_changes cds to the project root before staging.
    export MANIFEST_CLI_PROJECT_ROOT="$REPO"
    cd "$REPO"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_GIT_ALLOW_GATE_DRIFT MANIFEST_CLI_GIT_PENDING_SNAPSHOT
    unset MANIFEST_CLI_GIT_DRIFT_SKIPPED_COUNT MANIFEST_CLI_PROJECT_ROOT
}

mk_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "bats@example"
    git -C "$dir" config user.name "bats"
    echo "seed" > "$dir/seed.md"
    git -C "$dir" add seed.md
    git -C "$dir" commit -q -m "seed"
}

staged_paths() { git diff --cached --name-only | LC_ALL=C sort | tr '\n' ' '; }

@test "gate drift: a file appearing after the snapshot is left out of the commit" {
    echo "mine" >> seed.md                  # the operator's own work
    manifest_record_pending_snapshot
    echo "theirs" > concurrent.md           # lands during the gate
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [[ "$output" == *"Left out 1 file"* ]]
    [[ "$output" == *"concurrent.md"* ]]
    [ "$(staged_paths)" = "seed.md " ]
    [ -f concurrent.md ]                    # still in the working tree
}

@test "gate drift: everything present at snapshot time still ships" {
    echo "mine" >> seed.md
    echo "also mine" > extra.md
    manifest_record_pending_snapshot
    git add .
    local out; out="$(manifest_unstage_gate_drift)"
    [ -z "$out" ]
    [ "$(staged_paths)" = "extra.md seed.md " ]
    # Called in-shell (not via `run`, which subshells) so the export propagates.
    manifest_unstage_gate_drift >/dev/null
    [ "$MANIFEST_CLI_GIT_DRIFT_SKIPPED_COUNT" -eq 0 ]
}

@test "gate drift: .manifest-cli bookkeeping is exempt (the gate writes it mid-run)" {
    echo "mine" >> seed.md
    manifest_record_pending_snapshot
    mkdir -p .manifest-cli
    echo "1754400000" > .manifest-cli/release-gate-pass.epoch
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$(staged_paths)" == *".manifest-cli/release-gate-pass.epoch"* ]]
    [[ "$(staged_paths)" == *"seed.md"* ]]
}

@test "gate drift: opt-out records post-request changes as before" {
    echo "mine" >> seed.md
    manifest_record_pending_snapshot
    echo "theirs" > concurrent.md
    export MANIFEST_CLI_GIT_ALLOW_GATE_DRIFT=true
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$(staged_paths)" == *"concurrent.md"* ]]
}

@test "gate drift: no snapshot means no baseline, so nothing is withheld" {
    echo "mine" >> seed.md
    echo "other" > other.md
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(staged_paths)" = "other.md seed.md " ]
}

@test "gate drift: a rename recorded at snapshot time is not treated as drift" {
    git mv seed.md renamed.md
    manifest_record_pending_snapshot
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [[ "$output" != *"renamed.md"* ]]
    [[ "$(staged_paths)" == *"renamed.md"* ]]
}

@test "gate drift: commit_changes withholds drift end to end" {
    echo "mine" >> seed.md
    manifest_record_pending_snapshot
    echo "theirs" > concurrent.md
    run commit_changes "release" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Left out 1 file"* ]]
    # the release commit carries only the operator's file
    [ "$(git show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' ')" = "seed.md " ]
    # and the withheld file survives, uncommitted
    [ -f concurrent.md ]
    [ -n "$(git status --porcelain -- concurrent.md)" ]
}

@test "gate drift: a cleared snapshot lets Manifest's own release commit through" {
    # Lifecycle contract: ship clears the snapshot after the auto-commit, because
    # VERSION / CHANGELOG / regenerated docs all post-date it by design. If the
    # baseline outlived that step, the release commit would be withheld and ship
    # would fail its completion-clean invariant with a dirty tree.
    echo "mine" >> seed.md
    manifest_record_pending_snapshot
    git add .
    manifest_unstage_gate_drift >/dev/null
    unset MANIFEST_CLI_GIT_PENDING_SNAPSHOT      # what the orchestrator does
    echo "1.2.4" > VERSION                       # generated after the snapshot
    echo "notes" > CHANGELOG.md
    run commit_changes "Bump version to 1.2.4" ""
    [ "$status" -eq 0 ]
    [[ "$output" != *"Left out"* ]]
    local files; files="$(git show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' ')"
    [[ "$files" == *"VERSION"* ]]
    [[ "$files" == *"CHANGELOG.md"* ]]
    [ -z "$(git status --porcelain)" ]           # tree clean, as ship requires
}

@test "gate drift: drift-only tree reports nothing to commit and creates no commit" {
    manifest_record_pending_snapshot
    echo "theirs" > concurrent.md
    local before; before="$(git rev-parse HEAD)"
    run commit_changes "release" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to commit"* ]]
    [ "$(git rev-parse HEAD)" = "$before" ]
    [ -f concurrent.md ]
}

# Regression: files staged under a wholly-untracked DIRECTORY before the ship was
# requested were reported as post-request drift and withheld. `git status
# --porcelain` collapses such a directory to one `?? dir/` entry, but the staged
# set is compared path-for-path against `git diff --cached --name-only`, which
# always names individual files — so `.claude/` never matched
# `.claude/agents/<x>.md` and all of them looked foreign. Downstream (v20.0.0)
# this printed "Left out 10 files" naming work the operator had staged himself.
@test "gate drift: files under a new untracked directory are not drift" {
    mkdir -p .claude/agents .claude/commands
    echo "p" > .claude/agents/persona.md
    echo "q" > .claude/agents/persona2.md
    echo "c" > .claude/commands/cmd.md
    manifest_record_pending_snapshot
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [[ "$output" != *"Left out"* ]]
    [ "$(staged_paths)" = ".claude/agents/persona.md .claude/agents/persona2.md .claude/commands/cmd.md " ]
}

# Same root cause, opposite direction: a directory that appears mid-gate must
# still be caught per-file now that the snapshot is file-granular.
@test "gate drift: a directory appearing after the snapshot is still withheld" {
    echo "mine" >> seed.md
    manifest_record_pending_snapshot
    mkdir -p theirs
    echo "a" > theirs/a.md
    echo "b" > theirs/b.md
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [[ "$output" == *"Left out 2 files"* ]]
    [ "$(staged_paths)" = "seed.md " ]
}

# manifest_pending_commit_paths — what ship's "Auto-committing N pending file(s)"
# line and its commit-subject hint are built from.
#
# Regression: the snapshot was interpolated into an awk one-liner via `-v`, but a
# literal newline in a -v value aborts awk ("newline in string <first entry>...
# at source line 1"). Any pending set with more than one path therefore produced
# an empty list, and ship announced "Auto-committing 0 pending file(s)" while
# committing correctly — the log libeling its own commit. Single-path sets worked,
# which is what kept it alive through v58.0.3/v58.0.4.
@test "pending paths: a multi-file pending set is counted, not zeroed by awk" {
    echo "mine" >> seed.md
    echo "also mine" > extra.md
    echo "third" > third.md
    manifest_record_pending_snapshot
    run manifest_pending_commit_paths
    [ "$status" -eq 0 ]
    [[ "$output" != *"newline in string"* ]]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
    [[ "$output" == *"extra.md"* ]]
    [[ "$output" == *"seed.md"* ]]
    [[ "$output" == *"third.md"* ]]
}

@test "pending paths: post-snapshot drift is excluded but exempt bookkeeping counts" {
    echo "mine" >> seed.md
    echo "also mine" > extra.md
    manifest_record_pending_snapshot
    echo "theirs" > concurrent.md              # drift: must not be counted
    mkdir -p .manifest-cli
    echo "1" > .manifest-cli/release-gate-pass.epoch   # exempt: must be counted
    run manifest_pending_commit_paths
    [ "$status" -eq 0 ]
    [[ "$output" != *"concurrent.md"* ]]
    [[ "$output" == *".manifest-cli/release-gate-pass.epoch"* ]]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
}

@test "pending paths: a rename is counted under its destination" {
    mkdir -p s
    echo "hello" > s/old.md
    git add s/old.md
    git commit -q -m "add"
    git mv s/old.md s/new.md
    manifest_record_pending_snapshot
    run manifest_pending_commit_paths
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
    [ "$output" = "s/new.md" ]
}

@test "pending paths: no snapshot means everything pending is counted" {
    echo "mine" >> seed.md
    echo "also mine" > extra.md
    run manifest_pending_commit_paths
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

# The notice must count what actually gets committed. It read the same collapsed
# `?? dir/` entry, so ten new files under a new directory were announced as one.
@test "untracked notice: names each new file under a new directory" {
    mkdir -p .claude/agents
    echo "p" > .claude/agents/persona.md
    echo "q" > .claude/agents/persona2.md
    run manifest_notice_new_untracked_files
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 new files"* ]]
    [[ "$output" == *".claude/agents/persona.md"* ]]
    [[ "$output" == *".claude/agents/persona2.md"* ]]
}
