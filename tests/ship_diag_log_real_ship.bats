#!/usr/bin/env bats
# bats file_tags=smoke
#
# The per-run ship log, read after a REAL `ship repo` through this tree's
# entrypoint (scripts/manifest-cli.sh).
#
# tests/ship_diag_log.bats proves the log's writers one function at a time, and
# its four step/footer tests each open the log in a command substitution and
# then `export MANIFEST_CLI_SHIP_LOG_FILE="$file"` themselves. That export is
# the step the product omitted: `ship repo` opened its log the same way, the
# opener's own export died in the substitution's subshell, and every step and
# footer writer returned at its first line. From v52.0.0 until this was fixed,
# each `ship repo` log held its five header lines and nothing else, under a
# green suite, because no test drove the real command and then read the file.
#
# These tests supply nothing the product should supply: they run the entrypoint
# and read what it left behind.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/repo"
    export HOME
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
    export MANIFEST_CLI_RELEASE_GATE=none
    export MANIFEST_CLI_GIT_RETRIES=1
    LOG_DIR="$HOME/.manifest-cli/logs"

    local r="$SCRATCH/repo"
    git -C "$r" init -q -b main
    git -C "$r" config user.email t@example.com
    git -C "$r" config user.name T
    echo "1.2.3" > "$r/VERSION"
    git -C "$r" add VERSION
    git -C "$r" commit -qm "init 1.2.3"
    # A real origin: the apply-target gate refuses a repo without one, and a
    # local bare remote keeps the ship's sync offline.
    git init -q --bare "$SCRATCH/origin.git"
    git -C "$r" remote add origin "$SCRATCH/origin.git"
    git -C "$r" push -q -u origin main
}

teardown() {
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT MANIFEST_CLI_TIME_RETRIES
    unset MANIFEST_CLI_RELEASE_GATE MANIFEST_CLI_GIT_RETRIES
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/repo"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# The one ship log this test's HOME holds. Fails the test, naming what it found,
# when there is not exactly one — a count of zero must never read as "no lines".
only_ship_log() {
    local -a logs=()
    local f
    for f in "$LOG_DIR"/ship-*.log; do
        [ -f "$f" ] && logs+=("$f")
    done
    if [ "${#logs[@]}" -ne 1 ]; then
        echo "expected exactly one ship log under $LOG_DIR, found ${#logs[@]}" >&2
        return 1
    fi
    printf '%s' "${logs[0]}"
}

@test "real ship repo --local -y: the run log holds step lines and a result footer" {
    run_manifest ship repo patch --local -y
    [ "$status" -eq 0 ]

    local log
    log="$(only_ship_log)"
    # Positive control: the header is there, so the file is the right one and
    # the greps below are reading something.
    grep -q '^ship-log v1$' "$log"
    grep -q '^command: manifest ship repo patch (local)$' "$log"

    # The lines the product never wrote.
    grep -q '  step=version_bump  exit=0$' "$log"
    grep -q '  step=version_commit  exit=0$' "$log"
    grep -q '^result:  success$' "$log"
    grep -q '^last_step: ' "$log"

    # And the run names the same file it wrote to.
    [[ "$output" == *"run log:           $log"* ]]
}

@test "real ship repo --local -y that fails: the log records the failing step and a failed footer" {
    # A refusing pre-commit hook, installed outside the tree, stops the ship at
    # its first commit — the pre-bump sweep of the files a first ship scaffolds.
    # The ship reports that failure itself, so the footer must exist.
    local hooks="$SCRATCH/hooks"
    mkdir -p "$hooks"
    printf '#!/bin/sh\necho "HOOK-FIXTURE: refusing this commit" >&2\nexit 1\n' > "$hooks/pre-commit"
    chmod +x "$hooks/pre-commit"
    git -C "$SCRATCH/repo" config core.hooksPath "$hooks"

    run_manifest ship repo patch --local -y
    [ "$status" -ne 0 ]

    local log
    log="$(only_ship_log)"
    grep -q '^ship-log v1$' "$log"
    grep -q '  step=auto_commit  exit=[1-9]' "$log"
    grep -q '    stderr: .*HOOK-FIXTURE: refusing this commit' "$log"
    grep -q '^result:  failed$' "$log"
    grep -q '^last_step: auto_commit$' "$log"
}
