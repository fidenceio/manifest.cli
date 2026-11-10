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
    # The docs folders as set_default_configuration sets them: with neither
    # set, the docs writers resolve to the root and the release scope is the
    # whole tree — the degenerate case, tested by name below.
    export MANIFEST_CLI_DOCS_FOLDER=docs MANIFEST_CLI_DOCS_ARCHIVE_FOLDER=docs/zArchive
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
    unset MANIFEST_CLI_DOCS_FOLDER MANIFEST_CLI_DOCS_ARCHIVE_FOLDER MANIFEST_CLI_GIT_RELEASE_HELD_OUT
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

@test "gate drift: a name git quotes is compared bare — it ships in the auto-commit and is not called drift (TRACKER §4 lead)" {
    # Positive control: porcelain v1 quotes the name, the staged listing does
    # not, and that mismatch is what held `a b.txt` out of the auto-commit as
    # "changed after this ship was requested" and under-counted the commit.
    echo "mine" > 'a b.txt'
    [[ "$(git status --porcelain)" == *'"a b.txt"'* ]]
    git add -- 'a b.txt'
    [[ "$(git diff --cached --name-only)" == 'a b.txt' ]]
    git reset -q

    manifest_record_pending_snapshot
    [ "$MANIFEST_CLI_GIT_PENDING_SNAPSHOT" = "a b.txt" ]
    [ "$(manifest_pending_commit_paths)" = "a b.txt" ]
    git add .
    run manifest_unstage_gate_drift
    [ "$status" -eq 0 ]
    [[ "$output" != *"Left out"* ]]
    [ "$(staged_paths)" = "a b.txt " ]
}

# --- the release commit: release scope (TRACKER §4) ----------------------------

# A tree with every kind of release write and two foreign writes in the window
# between the auto-commit and the release commit.
mk_release_window() {
    mkdir -p docs src
    echo "1.2.3" > VERSION
    echo "old" > docs/old.md
    echo "app" > src/app.sh
    echo "# readme" > README.md
    git add -A . && git commit -qm "pre-release state"
    # Manifest's own release writes:
    echo "1.2.4" > VERSION
    echo "notes" > CHANGELOG.md
    echo "# readme 1.2.4" > README.md
    echo "index" > docs/INDEX.md
    mkdir -p docs/zArchive && mv docs/old.md docs/zArchive/old.md
    mkdir -p docs-site && echo "title: x" > docs-site/_config.yml
    # Foreign writes in the same window:
    echo "edited" >> src/app.sh
    echo "TOKEN=1" > secret.env
}

committed_paths() { git show --name-status --format= HEAD | LC_ALL=C sort | tr '\t' ' ' | tr '\n' ';'; }

@test "release scope: stages every release write area, including the archive move, and nothing else" {
    mk_release_window
    # Called directly, not through `run`: the held-out set is exported for the
    # completion check, and a subshell would not hand it back.
    local rc=0 output
    commit_changes "Bump version to 1.2.4" "" release > "$SCRATCH/commit.out" 2>&1 || rc=$?
    output="$(cat "$SCRATCH/commit.out")"
    [ "$rc" -eq 0 ]
    local files; files="$(committed_paths)"
    [[ "$files" == *"M VERSION;"* ]]
    [[ "$files" == *"A CHANGELOG.md;"* ]]
    [[ "$files" == *"M README.md;"* ]]
    [[ "$files" == *"A docs/INDEX.md;"* ]]
    [[ "$files" == *"docs/old.md"* ]]            # the move: D + A, or R
    [[ "$files" == *"docs/zArchive/old.md;"* ]]
    [[ "$files" == *"A docs-site/_config.yml;"* ]]
    [[ "$files" != *"src/app.sh"* ]]
    [[ "$files" != *"secret.env"* ]]
    # Named, recorded, and still in the working tree.
    [[ "$output" == *"Left out 2 files this release did not write: secret.env, src/app.sh"* ]]
    [[ "$output" == *"stay in your working tree"* ]]
    [ "$MANIFEST_CLI_GIT_RELEASE_HELD_OUT" = $'secret.env\nsrc/app.sh' ]
    [ "$(git status --porcelain | LC_ALL=C sort | tr '\n' ';')" = " M src/app.sh;?? secret.env;" ]
}

@test "release scope: a held-out name that is also a glob is compared literally" {
    # `VERSIO[N]` as a bare pathspec matches the staged VERSION, so the first
    # cut read the dirty file as staged, never announced it, and the completion
    # check then refused it after the push (review finding, measured).
    echo "1.2.3" > VERSION && git add VERSION && git commit -qm "v"
    echo "1.2.4" > VERSION
    echo "x" > 'VERSIO[N]'
    local rc=0 output
    commit_changes "Bump version to 1.2.4" "" release > "$SCRATCH/commit.out" 2>&1 || rc=$?
    output="$(cat "$SCRATCH/commit.out")"
    [ "$rc" -eq 0 ]
    [[ "$output" == *"Left out 1 file this release did not write: VERSIO[N]"* ]]
    [ "$MANIFEST_CLI_GIT_RELEASE_HELD_OUT" = 'VERSIO[N]' ]
    [[ "$(committed_paths)" == *"M VERSION;"* ]]
    [[ "$(committed_paths)" != *"VERSIO[N]"* ]]
}

@test "release scope: a configured docs folder and version.sync targets are areas" {
    mkdir -p documentation
    echo '{"version": "1.2.3"}' > package.json
    git add -A . && git commit -qm "pre"
    echo "1.2.4" > VERSION
    echo '{"version": "1.2.4"}' > package.json
    echo "idx" > documentation/INDEX.md
    echo "x" > stray.txt
    MANIFEST_CLI_DOCS_FOLDER=documentation MANIFEST_CLI_VERSION_SYNC=package.json \
        run commit_changes "Bump version to 1.2.4" "" release
    [ "$status" -eq 0 ]
    local files; files="$(committed_paths)"
    [[ "$files" == *"M package.json;"* ]]
    [[ "$files" == *"A documentation/INDEX.md;"* ]]
    [[ "$files" != *"stray.txt"* ]]
}

@test "release scope: nothing foreign leaves the tree clean, as the ship's completion invariant requires" {
    echo "1.2.4" > VERSION
    echo "notes" > CHANGELOG.md
    run commit_changes "Bump version to 1.2.4" "" release
    [ "$status" -eq 0 ]
    [[ "$output" != *"Left out"* ]]
    [ -z "$(git status --porcelain)" ]
    [ -z "${MANIFEST_CLI_GIT_RELEASE_HELD_OUT:-}" ]
}

@test "release scope: git.allow_gate_drift restores the whole-tree sweep" {
    mk_release_window
    MANIFEST_CLI_GIT_ALLOW_GATE_DRIFT=true run commit_changes "Bump version to 1.2.4" "" release
    [ "$status" -eq 0 ]
    [[ "$(committed_paths)" == *"secret.env"* ]]
    [ -z "$(git status --porcelain)" ]
}

@test "release scope: the default scope is still the whole tree, and an unknown scope is refused" {
    mk_release_window
    run commit_changes "Auto-commit" "" bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown scope 'bogus'"* ]]
    run commit_changes "Auto-commit" ""
    [ "$status" -eq 0 ]
    [[ "$(committed_paths)" == *"secret.env"* ]]
}

@test "release areas: derived from config, present paths only, never outside the root" {
    run manifest_release_write_areas "$REPO"
    [ "$status" -eq 0 ]
    # A fresh repo has only VERSION... which this fixture lacks: nothing is listed.
    [ -z "$output" ]
    echo "1" > VERSION; mkdir -p docs
    run manifest_release_write_areas "$REPO"
    [ "$output" = $'VERSION\ndocs' ]
    # The writers' resolvers join root and folder with a slash, so a folder
    # written as `/etc` lands at `<root>/etc` — and that is the area, because
    # the area is wherever the sweep went. A folder that escapes the root is
    # not an area at all.
    mkdir -p etc
    MANIFEST_CLI_DOCS_FOLDER=../outside MANIFEST_CLI_DOCS_ARCHIVE_FOLDER=/etc \
        run manifest_release_write_areas "$REPO"
    # Literal `docs` stays listed whatever docs.folder says: validate_project
    # cleans that tree by its literal name.
    [ "$output" = $'VERSION\netc\ndocs' ]
    # `.manifest-cli/` is never an area, tracked or not: nothing writes there
    # between the two commits, and naming it tracked-but-ignored makes `git
    # add` print its "paths are ignored" hint and exit 1 (measured by review).
    mkdir -p .manifest-cli && echo "1" > .manifest-cli/release-gate-pass.epoch
    echo ".manifest-cli/" > .gitignore
    git add -f .manifest-cli/release-gate-pass.epoch && git commit -qm "tracked bookkeeping"
    run manifest_release_write_areas "$REPO"
    [ "$output" = $'VERSION\ndocs' ]
    # An ignored, untracked folder that IS a writer's target is left out too.
    mkdir -p docs-site && echo "x" > docs-site/_config.yml
    echo "docs-site/" >> .gitignore
    run manifest_release_write_areas "$REPO"
    [ "$output" = $'VERSION\ndocs' ]
    rm -rf .gitignore docs-site
    # A configured review report directory is an area; the literal README.md
    # is one beside a configured `files.readme`.
    mkdir -p reviews && echo "r" > reviews/x.md && echo "# r" > README.md && echo "# o" > OTHER.md
    MANIFEST_CLI_DOC_REVIEW_REPORT_DIR=reviews MANIFEST_CLI_README_FILE=OTHER.md \
        run manifest_release_write_areas "$REPO"
    [ "$output" = $'VERSION\nREADME.md\nOTHER.md\nreviews\ndocs' ]
    rm -rf reviews README.md OTHER.md
    # An empty docs folder resolves to the root itself: the area is the root,
    # the scope is the whole tree, and that is said plainly rather than by a
    # list that would hold out the index the release just wrote there.
    MANIFEST_CLI_DOCS_FOLDER= run manifest_release_write_areas "$REPO"
    [ "$output" = "." ]
    echo "x" > stray.txt
    MANIFEST_CLI_DOCS_FOLDER= run commit_changes "Bump version to 1" "" release
    [ "$status" -eq 0 ]
    [[ "$output" != *"Left out"* ]]
    [[ "$(committed_paths)" == *"stray.txt"* ]]
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
