#!/usr/bin/env bats

# Coverage for `manifest init repo --connect` APPLY path and the connect phase
# (manifest-init-connect.sh). Pins: -y actually enumerates remotes and runs `git pull`
# (proven against a local bare origin — no network), the ENV-001 .env.example
# retrofit on apply, the ambiguous-target refusal (no origin, no AUTO_CONFIRM),
# and the AUTO_CONFIRM no-remote skip branch.

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh" "core/manifest-init.sh" "core/manifest-init-connect.sh"
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
# init repo --connect -y (apply)
# -----------------------------------------------------------------------------

@test "init repo --connect -y: pulls latest from origin and scaffolds .env.example" {
    make_behind_clone
    cd "$SCRATCH/work"
    [ ! -f "$SCRATCH/work/second.txt" ]

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_connect_repo -y
    [ "$status" -eq 0 ]

    # Apply-boundary contract: unambiguous target (named branch + origin)
    # applies on -y alone, no AUTO_CONFIRM needed.
    echo "$output" | grep -q "Auto-confirmed unambiguous target (apply via -y)"
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    # Banner wording changed with the fold: prep is now init's connect phase.
    echo "$output" | grep -q "Connecting repository: $SCRATCH/work"

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

@test "init repo --connect -y: ambiguous target (no origin) is refused, nothing written" {
    mkdir -p "$SCRATCH/work"
    cd "$SCRATCH/work"
    git init -q -b main

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_connect_repo -y < /dev/null
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Ambiguous apply target"
    echo "$output" | grep -q "MANIFEST_CLI_AUTO_CONFIRM=1"
    # Refusal happens at the apply gate — before the env scaffold write.
    [ ! -f "$SCRATCH/work/.env.example" ]
}

@test "init repo --connect -y: AUTO_CONFIRM cannot turn a missing origin into success" {
    mkdir -p "$SCRATCH/work"
    cd "$SCRATCH/work"
    git init -q -b main
    export MANIFEST_CLI_AUTO_CONFIRM=1
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_connect_repo -y < /dev/null
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Setup incomplete: no origin"
    [ ! -f "$SCRATCH/work/.env.example" ]
}

# The preview line and the artifact the apply path writes are one contract, and
# they drifted apart: the preview promised ".env.example (your env var names, no
# values)" while the shared renderer wrote NAME=<default> for every non-secret
# entry. Reading the promise and the file in a single test is what couples them —
# asserting the preview string on its own would have passed against the wrong text.
@test "init repo --connect: .env.example preview text matches what the apply actually writes" {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    make_behind_clone
    cd "$SCRATCH/work"
    cat > "$SCRATCH/work/service.spec.yaml" <<'YAML'
name: fidence.service.prepdemo
env:
  - name: FIDENCE_SERVICE_PREPDEMO_RETRIES
    description: retry budget
    required: false
    default: 7
  - name: FIDENCE_SERVICE_PREPDEMO_TOKEN
    description: upstream token
    required: true
    secret: true
YAML
    [ ! -f "$SCRATCH/work/.env.example" ]

    # 1. The promise. Preview must reach the env branch (positive control) and
    #    must still write nothing.
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_connect_repo < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create: .env.example"* ]]
    local preview="$output"
    [ ! -f "$SCRATCH/work/.env.example" ]

    # 2. The artifact the same command produces on apply.
    export MANIFEST_CLI_AUTO_CONFIRM=1
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_init_connect_repo -y < /dev/null
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/work/.env.example" ]
    grep -qx 'FIDENCE_SERVICE_PREPDEMO_RETRIES=7' "$SCRATCH/work/.env.example"
    grep -qx '# FIDENCE_SERVICE_PREPDEMO_TOKEN=' "$SCRATCH/work/.env.example"

    # 3. The coupling: a real value landed, so the preview must not have said the
    #    file would carry none.
    local claim
    claim="$(printf '%s\n' "$preview" \
        | grep -icE 'no values|without values|with no value|names only|names, not values' || true)"
    [ "$claim" -eq 0 ]
}
