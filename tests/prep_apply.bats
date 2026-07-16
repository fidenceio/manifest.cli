#!/usr/bin/env bats

# Coverage for `manifest prep repo` APPLY path and `manifest prep` dispatch
# (manifest-prep.sh). Pins: -y actually enumerates remotes and runs `git pull`
# (proven against a local bare origin — no network), the ENV-001 .env.example
# retrofit on apply, the ambiguous-target refusal (no origin, no AUTO_CONFIRM),
# the AUTO_CONFIRM no-remote skip branch, and the dispatch help / empty /
# unknown-scope branches.

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh" "core/manifest-init.sh" "core/manifest-prep.sh"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_AUTO_CONFIRM
}

# Build a local bare origin with one commit, clone it to $SCRATCH/work, then
# advance origin by a second commit so the clone is one commit behind.
make_behind_clone() {
    git init -q --bare -b main "$SCRATCH/origin.git"

    git init -q -b main "$SCRATCH/seed"
    git -C "$SCRATCH/seed" config user.email "test@example.com"
    git -C "$SCRATCH/seed" config user.name "Test User"
    echo "one" > "$SCRATCH/seed/first.txt"
    git -C "$SCRATCH/seed" add first.txt
    git -C "$SCRATCH/seed" commit -qm "first"
    git -C "$SCRATCH/seed" remote add origin "$SCRATCH/origin.git"
    git -C "$SCRATCH/seed" push -q origin main

    git clone -q "$SCRATCH/origin.git" "$SCRATCH/work"
    git -C "$SCRATCH/work" config user.email "test@example.com"
    git -C "$SCRATCH/work" config user.name "Test User"

    echo "two" > "$SCRATCH/seed/second.txt"
    git -C "$SCRATCH/seed" add second.txt
    git -C "$SCRATCH/seed" commit -qm "second"
    git -C "$SCRATCH/seed" push -q origin main
}

# -----------------------------------------------------------------------------
# prep repo -y (apply)
# -----------------------------------------------------------------------------

@test "prep repo -y: pulls latest from origin and scaffolds .env.example" {
    make_behind_clone
    cd "$SCRATCH/work"
    [ ! -f "$SCRATCH/work/second.txt" ]

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_prep_repo -y
    [ "$status" -eq 0 ]

    # Apply-boundary contract: unambiguous target (named branch + origin)
    # applies on -y alone, no AUTO_CONFIRM needed.
    echo "$output" | grep -q "Auto-confirmed unambiguous target (apply via -y)"
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    echo "$output" | grep -q "Preparing repository: $SCRATCH/work"

    # The pull really ran against the local origin.
    echo "$output" | grep -q "Syncing with origin"
    echo "$output" | grep -q "Successfully synced with origin"
    echo "$output" | grep -q "Repository synced successfully"
    [ -f "$SCRATCH/work/second.txt" ]
    [ "$(cat "$SCRATCH/work/second.txt")" = "two" ]

    # ENV-001 retrofit: apply scaffolds the env schema template (no-clobber).
    [ -f "$SCRATCH/work/.env.example" ]
    grep -q "scaffolded by Manifest CLI" "$SCRATCH/work/.env.example"
}

@test "prep repo -y: ambiguous target (no origin) is refused, nothing written" {
    mkdir -p "$SCRATCH/work"
    cd "$SCRATCH/work"
    git init -q -b main

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_prep_repo -y < /dev/null
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Ambiguous apply target"
    echo "$output" | grep -q "MANIFEST_CLI_AUTO_CONFIRM=1"
    # Refusal happens at the apply gate — before the env scaffold write.
    [ ! -f "$SCRATCH/work/.env.example" ]
}

@test "prep repo -y: AUTO_CONFIRM + no remotes -> scaffolds env, skips sync" {
    mkdir -p "$SCRATCH/work"
    cd "$SCRATCH/work"
    git init -q -b main
    export MANIFEST_CLI_AUTO_CONFIRM=1

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_prep_repo -y < /dev/null
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Auto-confirmed repository target (MANIFEST_CLI_AUTO_CONFIRM=1)"
    echo "$output" | grep -q "No remotes configured and not in interactive mode. Skipping sync."
    # Apply still performed its local effect before the remote step bailed.
    [ -f "$SCRATCH/work/.env.example" ]
}

# -----------------------------------------------------------------------------
# prep dispatch branches
# -----------------------------------------------------------------------------

@test "prep dispatch: routes repo scope through to manifest_prep_repo" {
    mkdir -p "$SCRATCH/work"
    cd "$SCRATCH/work"
    git init -q -b main
    git remote add origin git@github.com:example/x.git

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_prep_dispatch repo --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run — manifest prep repo"
    echo "$output" | grep -q "Remotes that would be pulled"
    echo "$output" | grep -q "git@github.com:example/x.git"
}

@test "prep dispatch: help renders scopes and exits 0" {
    run manifest_prep_dispatch --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest prep <repo|fleet>"
    echo "$output" | grep -q "repo    Add remote if missing, pull latest from all remotes"
    echo "$output" | grep -q "fleet   Clone missing repos, pull existing ones"
}

@test "prep dispatch: empty scope is an error with usage" {
    run manifest_prep_dispatch
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "prep requires a scope"
    echo "$output" | grep -q "manifest prep <repo|fleet>"
}

@test "prep dispatch: unknown scope is an error naming the scope" {
    run manifest_prep_dispatch bogus
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown scope: bogus"
    echo "$output" | grep -q "manifest prep <repo|fleet>"
}
