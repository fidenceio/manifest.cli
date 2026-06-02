#!/usr/bin/env bats
# §5.6 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the per-run diagnostic ship log (CLI tracker §5.6): ship writes a
# timestamped log under $HOME/.manifest-cli/logs/ recording each step boundary,
# its exit status, and any captured stderr — every interpolated value routed
# through manifest_redact so no token-shaped value can leak. Keep-last-N
# rotation bounds growth. CRITICAL invariant: the log dir is NOT among the
# cache-sweep dirs, so the TTL-gated runtime cache sweep can never collect a
# forensic log.
#
# NOTE: the token fixture is assembled at runtime from harmless parts so no
# literal credential shape is committed (the repo secret scanner / CI gitleaks
# would otherwise block this file).

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    export TMPDIR="$SCRATCH/tmp"
    mkdir -p "$TMPDIR"
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-runtime-cleanup.sh"

    LOG_DIR="$HOME/.manifest-cli/logs"
    # Disable the rotate TTL gate so every run rotates deterministically.
    export MANIFEST_CLI_SHIP_LOG_ROTATE_PERIOD=0
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

gh_classic() { printf 'gh%s_%s' "p" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"; }

# --- log creation ------------------------------------------------------------

@test "diag log: begin creates a ship-<ts>.log under the logs dir and exports its path" {
    run manifest_ship_log_begin "manifest ship repo patch (publish)"
    [ "$status" -eq 0 ]
    [ -d "$LOG_DIR" ]
    [ -n "$output" ]
    [[ "$output" == "$LOG_DIR/ship-"*".log" ]]
    [ -f "$output" ]
}

@test "diag log: two runs starting in the same second get distinct log files" {
    # The date stamp is second-resolved; back-to-back begins (e.g. a ship and
    # its auto-followup-patch) must not append into one conflated file.
    local f1 f2
    f1="$(manifest_ship_log_begin "manifest ship repo patch")"
    f2="$(manifest_ship_log_begin "manifest ship repo patch")"
    [ "$f1" != "$f2" ]
    [ "$(find "$LOG_DIR" -maxdepth 1 -name 'ship-*.log' | wc -l | tr -d ' ')" -eq 2 ]
    # Each holds exactly one header banner (no append-conflation).
    [ "$(grep -c '^ship-log v1$' "$f1")" -eq 1 ]
    [ "$(grep -c '^ship-log v1$' "$f2")" -eq 1 ]
}

@test "diag log: header records command and the ship-log version banner" {
    local file; file="$(manifest_ship_log_begin "manifest ship repo minor (local)")"
    [ -f "$file" ]
    grep -q '^ship-log v1$' "$file"
    grep -q '^command: manifest ship repo minor (local)$' "$file"
    grep -q '^started: ' "$file"
}

@test "diag log: step boundary records label, exit status, and captured stderr" {
    local file; file="$(manifest_ship_log_begin "manifest ship repo patch")"
    export MANIFEST_CLI_SHIP_LOG_FILE="$file"
    manifest_ship_log_step "doc_generation" "0"
    manifest_ship_log_step "version_commit" "1" "fatal: nothing to commit"
    grep -q 'step=doc_generation  exit=0' "$file"
    grep -q 'step=version_commit  exit=1' "$file"
    grep -q 'stderr: fatal: nothing to commit' "$file"
}

@test "diag log: end footer records result and last step" {
    local file; file="$(manifest_ship_log_begin "manifest ship repo patch")"
    export MANIFEST_CLI_SHIP_LOG_FILE="$file"
    manifest_ship_log_end "failed" "push_changes"
    grep -q '^result:  failed$' "$file"
    grep -q '^last_step: push_changes$' "$file"
}

@test "diag log: step/end are no-ops when no log file is active (best-effort)" {
    unset MANIFEST_CLI_SHIP_LOG_FILE
    run manifest_ship_log_step "release_gate" "0" "some stderr"
    [ "$status" -eq 0 ]
    run manifest_ship_log_end "success" "release_gate"
    [ "$status" -eq 0 ]
}

# --- redaction (safety contract) ---------------------------------------------

@test "diag log: a token-shaped value in captured stderr is redacted" {
    local tok; tok="$(gh_classic)"
    local file; file="$(manifest_ship_log_begin "manifest ship repo patch")"
    export MANIFEST_CLI_SHIP_LOG_FILE="$file"
    manifest_ship_log_step "push_changes" "1" "remote: error using token $tok to push"
    run grep -F "$tok" "$file"
    [ "$status" -ne 0 ]
    grep -q '\[REDACTED\]' "$file"
}

@test "diag log: a token-shaped value in the command header is redacted" {
    local tok; tok="$(gh_classic)"
    local file; file="$(manifest_ship_log_begin "manifest ship repo patch $tok")"
    run grep -F "$tok" "$file"
    [ "$status" -ne 0 ]
    grep -q '\[REDACTED\]' "$file"
}

@test "diag log: the exact value of a known credential env var is redacted" {
    export GITHUB_TOKEN="supersecretvalue1234567890"
    local file; file="$(manifest_ship_log_begin "manifest ship repo patch")"
    export MANIFEST_CLI_SHIP_LOG_FILE="$file"
    manifest_ship_log_step "push_changes" "1" "auth failed with $GITHUB_TOKEN"
    run grep -F "supersecretvalue1234567890" "$file"
    [ "$status" -ne 0 ]
    grep -q '\[REDACTED\]' "$file"
}

# --- rotation (keep last N) --------------------------------------------------

@test "diag log: rotation keeps only the most recent N logs" {
    export MANIFEST_CLI_SHIP_LOG_KEEP=3
    mkdir -p "$LOG_DIR"
    # Seed seven logs with distinct, time-ordered names.
    local i
    for i in 1 2 3 4 5 6 7; do
        printf 'ship-log v1\n' > "$LOG_DIR/ship-2026010${i}T000000Z.log"
    done
    manifest_ship_log_rotate
    [ "$(find "$LOG_DIR" -maxdepth 1 -name 'ship-*.log' | wc -l | tr -d ' ')" -eq 3 ]
    # The three newest (by name) survive; the four oldest are gone.
    [ -f "$LOG_DIR/ship-20260107T000000Z.log" ]
    [ -f "$LOG_DIR/ship-20260106T000000Z.log" ]
    [ -f "$LOG_DIR/ship-20260105T000000Z.log" ]
    [ ! -f "$LOG_DIR/ship-20260101T000000Z.log" ]
}

@test "diag log: begin rotates so a stream of runs never exceeds the keep count" {
    export MANIFEST_CLI_SHIP_LOG_KEEP=2
    mkdir -p "$LOG_DIR"
    local i
    for i in 1 2 3 4 5; do
        printf 'ship-log v1\n' > "$LOG_DIR/ship-2026020${i}T000000Z.log"
    done
    # A fresh begin writes one new log then prunes back to the keep count.
    manifest_ship_log_begin "manifest ship repo patch" >/dev/null
    [ "$(find "$LOG_DIR" -maxdepth 1 -name 'ship-*.log' | wc -l | tr -d ' ')" -eq 2 ]
}

@test "diag log: KEEP < 1 disables rotation (keep everything)" {
    export MANIFEST_CLI_SHIP_LOG_KEEP=0
    mkdir -p "$LOG_DIR"
    local i
    for i in 1 2 3 4; do
        printf 'ship-log v1\n' > "$LOG_DIR/ship-2026030${i}T000000Z.log"
    done
    manifest_ship_log_rotate
    [ "$(find "$LOG_DIR" -maxdepth 1 -name 'ship-*.log' | wc -l | tr -d ' ')" -eq 4 ]
}

@test "diag log: rotation is TTL-gated via a marker (no re-prune inside the window)" {
    export MANIFEST_CLI_SHIP_LOG_KEEP=2
    export MANIFEST_CLI_SHIP_LOG_ROTATE_PERIOD=3600
    mkdir -p "$LOG_DIR"
    # A fresh marker means we are inside the window → no prune yet.
    date -u +%s > "$LOG_DIR/rotate.last"
    local i
    for i in 1 2 3 4; do
        printf 'ship-log v1\n' > "$LOG_DIR/ship-2026040${i}T000000Z.log"
    done
    manifest_ship_log_rotate
    [ "$(find "$LOG_DIR" -maxdepth 1 -name 'ship-*.log' | wc -l | tr -d ' ')" -eq 4 ]
}

# --- resume reads the prior log ----------------------------------------------

@test "diag log: latest returns the newest prior log, last_step reads its footer" {
    mkdir -p "$LOG_DIR"
    printf 'ship-log v1\n---\nresult:  failed\nlast_step: push_changes\n' \
        > "$LOG_DIR/ship-20260501T000000Z.log"
    printf 'ship-log v1\n---\nresult:  failed\nlast_step: create_tag\n' \
        > "$LOG_DIR/ship-20260502T000000Z.log"
    local latest; latest="$(manifest_ship_log_latest)"
    [ "$latest" = "$LOG_DIR/ship-20260502T000000Z.log" ]
    [ "$(manifest_ship_log_last_step "$latest")" = "create_tag" ]
}

@test "diag log: last_step falls back to the final step= line when no footer" {
    mkdir -p "$LOG_DIR"
    local file="$LOG_DIR/ship-20260601T000000Z.log"
    printf 'ship-log v1\n---\n' > "$file"
    printf '2026-06-01T00:00:00Z  step=doc_generation  exit=0\n' >> "$file"
    printf '2026-06-01T00:00:01Z  step=archive_sweep  exit=0\n' >> "$file"
    [ "$(manifest_ship_log_last_step "$file")" = "archive_sweep" ]
}

# --- NOT-SWEPT invariant (the critical safety property) ----------------------

@test "diag log: logs dir is NOT among the cache-sweep dirs (must never be swept)" {
    local cache_dirs
    cache_dirs="$(manifest_install_paths_cache_dirs)"
    [[ "$cache_dirs" != *"$LOG_DIR"* ]]
    [[ "$cache_dirs" != *".manifest-cli/logs"* ]]
}

@test "diag log: logs dir is a preserved subdir (survives an upgrade swap)" {
    run manifest_install_paths_preserved_subdirs
    [[ "$output" == *"logs"* ]]
}

@test "diag log: the runtime cache sweep does NOT delete a stale ship log" {
    # Wire the cache sweep over the real TMPDIR cache, then prove an aged ship
    # log under the preserved logs dir is untouched by it.
    mkdir -p "$LOG_DIR" "$TMPDIR/manifest-cli"
    local logfile="$LOG_DIR/ship-20000101T000000Z.log"
    printf 'ship-log v1\n' > "$logfile"
    touch -t 200001010000 "$logfile"          # ancient: well past any stale-age
    touch -t 200001010000 "$TMPDIR/manifest-cli/scratch.tmp"

    # No marker → TTL gate passes; sweep fires over cache_dirs only.
    _manifest_runtime_maybe_cleanup_cache

    [ -f "$logfile" ]                          # forensic log survives
    [ ! -f "$TMPDIR/manifest-cli/scratch.tmp" ] # cache file was swept (sanity)
}
