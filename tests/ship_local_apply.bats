#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Focused local-only APPLY coverage (CLI tracker §2.6).
#
# preview_no_write.bats proves `--local` *preview* writes nothing. This file
# proves the other half of the contract: `--local -y` *applies* — it makes the
# local writes (version bump, release commit, doc regen) AND never crosses the
# offline boundary. The offline boundary is enforced two ways at once:
#   1. A PATH-level `git` shim logs and REFUSES every network subcommand
#      (push/fetch/pull/clone) without contacting any host, then asserts no
#      `push` was ever attempted.
#   2. `gh` and `brew` stubs log every invocation; the test asserts the logs
#      stay empty.
# Local-only ship still runs a remote *sync* (`git pull`); that is allowed by
# the contract — the boundary we assert is "no push, no publish API" — so the
# shim refusing the pull (and the workflow continuing on local state) is the
# realistic offline scenario, not a failure.

load 'helpers/setup'

# Real git, captured before the shim is placed on PATH, so fixtures and
# assertions use the genuine binary while the CLI under test sees the shim.
REAL_GIT="$(command -v git)"

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME

    # Full module graph, exactly as scripts/manifest-cli.sh wires it, so the
    # apply path runs against the real orchestrator/git/fleet code. Fleet
    # config loading lives in a module core does not pull in, so add it.
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"

    # Neutralize the slow / networked / out-of-scope steps so each test is
    # deterministic and offline. These are NOT the contract under test — the
    # contract is "local writes happen, no push/publish" — so stubbing them
    # keeps the test focused on the boundary, not on doc-generation internals.
    get_time_timestamp() {
        MANIFEST_CLI_TIME_TIMESTAMP="1700000000"
        MANIFEST_CLI_TIME_SERVER="stub"
        MANIFEST_CLI_TIME_SERVER_IP="0.0.0.0"
        MANIFEST_CLI_TIME_OFFSET=0
        MANIFEST_CLI_TIME_UNCERTAINTY=0
        MANIFEST_CLI_TIME_METHOD="stub"
        export MANIFEST_CLI_TIME_TIMESTAMP MANIFEST_CLI_TIME_SERVER \
            MANIFEST_CLI_TIME_SERVER_IP MANIFEST_CLI_TIME_OFFSET \
            MANIFEST_CLI_TIME_UNCERTAINTY MANIFEST_CLI_TIME_METHOD
    }
    format_timestamp() { echo "2023-11-14 00:00:00 UTC"; }
    main_cleanup() { return 0; }
    validate_project() { return 0; }
    update_repository_metadata() { :; }
    fleet_validate() { return 0; }
    fleet_docs_dispatch() { return 0; }

    # The release gate runs the project's tests before any mutation; bypass it
    # so these tests exercise the ship path, not the suite-within-a-suite.
    export MANIFEST_CLI_RELEASE_GATE=none
    # Fleet's -y is consent for its members; mirror it for the single-repo path.
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=main
    # Fail fast offline: one git attempt, no retry sleeps.
    export MANIFEST_CLI_GIT_RETRIES=1

    NET_LOG="$SCRATCH/git-network.log"
    GH_LOG="$SCRATCH/gh-calls.log"
    BREW_LOG="$SCRATCH/brew-calls.log"
    : > "$NET_LOG"

    install_offline_shims
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
    unset MANIFEST_CLI_RELEASE_GATE MANIFEST_CLI_AUTO_CONFIRM \
        MANIFEST_CLI_GIT_DEFAULT_BRANCH MANIFEST_CLI_GIT_RETRIES \
        MANIFEST_CLI_FLEET_ROOT
}

# -----------------------------------------------------------------------------
# Offline boundary shims
# -----------------------------------------------------------------------------

# PATH-prepend a `git` that records and refuses any network subcommand without
# contacting a host, and a `gh`/`brew` that record every call. The git shim
# delegates all non-network subcommands to the real binary, so commit/tag/status
# behave normally. push/fetch/pull/clone are logged and rejected (exit 1) —
# proving both "no push" and "no network egress". A bash function override would
# miss the real call site: git_retry runs `timeout env git ...`, which resolves
# `git` via PATH, not via a shell function.
install_offline_shims() {
    local bin="$SCRATCH/bin"
    mkdir -p "$bin"

    cat > "$bin/git" <<SHIM
#!/usr/bin/env bash
REAL_GIT="$REAL_GIT"
NET_LOG="$NET_LOG"
# Find the git subcommand by skipping global options and their values.
args=("\$@"); i=0; sub=""
while [ \$i -lt \${#args[@]} ]; do
    a="\${args[\$i]}"
    case "\$a" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path) i=\$((i+2)); continue ;;
        -*) i=\$((i+1)); continue ;;
        *) sub="\$a"; break ;;
    esac
done
case "\$sub" in
    push|fetch|pull|clone)
        printf '%s\t%s\n' "\$sub" "\$*" >> "\$NET_LOG"
        echo "git-shim: refusing network op '\$sub' (offline test)" >&2
        exit 1
        ;;
esac
exec "\$REAL_GIT" "\$@"
SHIM
    chmod +x "$bin/git"

    printf '#!/usr/bin/env bash\nprintf "gh\\t%%s\\n" "$*" >> "%s"\nexit 0\n' \
        "$GH_LOG" > "$bin/gh"
    chmod +x "$bin/gh"

    printf '#!/usr/bin/env bash\nprintf "brew\\t%%s\\n" "$*" >> "%s"\nexit 0\n' \
        "$BREW_LOG" > "$bin/brew"
    chmod +x "$bin/brew"

    export PATH="$bin:$PATH"
}

# -----------------------------------------------------------------------------
# Fixture builders (use REAL_GIT so the shim only ever sees the CLI's calls)
# -----------------------------------------------------------------------------

# A single repo on `main`, one commit, a configured (unreachable) remote so the
# sync/push code paths have a remote to iterate. Echoes the repo path.
mk_repo() {
    local repo="$SCRATCH/repo" version="${1:-1.2.3}"
    mkdir -p "$repo"
    "$REAL_GIT" -C "$repo" init -q
    "$REAL_GIT" -C "$repo" symbolic-ref HEAD refs/heads/main
    "$REAL_GIT" -C "$repo" config user.email test@example.com
    "$REAL_GIT" -C "$repo" config user.name test
    echo "$version" > "$repo/VERSION"
    "$REAL_GIT" -C "$repo" add VERSION
    "$REAL_GIT" -C "$repo" commit -qm "init $version"
    "$REAL_GIT" -C "$repo" remote add origin "https://example.invalid/repo.git"
    echo "$repo"
}

# A one-member fleet under $SCRATCH/work with a releaseable service `svc`.
mk_fleet() {
    local work="$SCRATCH/work" version="${1:-1.2.3}"
    mkdir -p "$work/svc"
    cat > "$work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svc:
    path: "./svc"
    type: "service"
    branch: "main"
    release:
      enabled: true
YAML
    printf 'true\tsvc\t./svc\tservice\tfalse\t\tmain\t%s\n' "$version" \
        > "$work/manifest.fleet.tsv"

    "$REAL_GIT" -C "$work/svc" init -q
    "$REAL_GIT" -C "$work/svc" symbolic-ref HEAD refs/heads/main
    "$REAL_GIT" -C "$work/svc" config user.email test@example.com
    "$REAL_GIT" -C "$work/svc" config user.name test
    echo "$version" > "$work/svc/VERSION"
    "$REAL_GIT" -C "$work/svc" add VERSION
    "$REAL_GIT" -C "$work/svc" commit -qm "init $version"
    "$REAL_GIT" -C "$work/svc" remote add origin "https://example.invalid/svc.git"
    echo "$work"
}

mk_two_member_fleet_with_clean_skip() {
    local work="$SCRATCH/work" version="${1:-1.2.3}"
    mkdir -p "$work/clean-svc" "$work/dirty-svc"
    cat > "$work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  clean-svc:
    path: "./clean-svc"
    type: "service"
    branch: "main"
    release:
      enabled: true
  dirty-svc:
    path: "./dirty-svc"
    type: "service"
    branch: "main"
    release:
      enabled: true
YAML
    {
        printf 'true\tclean-svc\t./clean-svc\tservice\tfalse\t\tmain\t%s\n' "$version"
        printf 'true\tdirty-svc\t./dirty-svc\tservice\tfalse\t\tmain\t%s\n' "$version"
    } > "$work/manifest.fleet.tsv"

    local repo
    for repo in clean-svc dirty-svc; do
        "$REAL_GIT" -C "$work/$repo" init -q
        "$REAL_GIT" -C "$work/$repo" symbolic-ref HEAD refs/heads/main
        "$REAL_GIT" -C "$work/$repo" config user.email test@example.com
        "$REAL_GIT" -C "$work/$repo" config user.name test
        echo "$version" > "$work/$repo/VERSION"
        "$REAL_GIT" -C "$work/$repo" add VERSION
        "$REAL_GIT" -C "$work/$repo" commit -qm "init $version"
        "$REAL_GIT" -C "$work/$repo" tag "v$version"
        "$REAL_GIT" -C "$work/$repo" remote add origin "https://example.invalid/$repo.git"
    done

    echo "pending work" > "$work/dirty-svc/feature.txt"
    echo "$work"
}

# Shared offline-boundary assertions: no push attempted, no gh, no brew.
assert_no_remote_dispatch() {
    # The git shim logs every network subcommand it refused; none may be push.
    run grep -c '^push' "$NET_LOG"
    [ "$output" -eq 0 ]
    # gh / brew stubs only create their log on first invocation.
    [ ! -s "$GH_LOG" ]
    [ ! -s "$BREW_LOG" ]
}

# -----------------------------------------------------------------------------
# ship repo --local -y
# -----------------------------------------------------------------------------

@test "ship repo --local -y: applies local bump + commit, never pushes or publishes" {
    local repo
    repo="$(mk_repo 1.2.3)"
    local before
    before="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

    cd "$repo"
    PROJECT_ROOT="$repo" run manifest_ship_repo minor --local -y
    [ "$status" -eq 0 ]

    # Local writes DID happen.
    [ "$(cat "$repo/VERSION")" = "1.3.0" ]
    [ "$("$REAL_GIT" -C "$repo" rev-parse HEAD)" != "$before" ]
    [[ "$("$REAL_GIT" -C "$repo" log -1 --pretty=%s)" == *"1.3.0"* ]]
    # ... but no release tag (tagging is a publish step, skipped under --local).
    [ -z "$("$REAL_GIT" -C "$repo" tag)" ]

    assert_no_remote_dispatch
}

@test "ship repo --local -y: output states no remote operations" {
    local repo
    repo="$(mk_repo 1.2.3)"

    cd "$repo"
    PROJECT_ROOT="$repo" run manifest_ship_repo patch --local -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"no remote operations"* ]]
    [[ "$output" == *"skipped tag/push/Homebrew publish steps"* ]]

    assert_no_remote_dispatch
}

# -----------------------------------------------------------------------------
# Apply-event audit: authorization + completion (CLI tracker §8.3a / §8.3b)
#
# The apply guard emits an "authorized" event (was the confirmation OK); after
# the workflow runs, ship emits a "completed" event carrying the REAL workflow
# rc and the release-gate disposition. These tests drive the real ship path and
# assert BOTH lines land in the durable apply-events log.
# -----------------------------------------------------------------------------

AUDIT_FILE() { echo "$HOME/.manifest-cli/audit/apply-events.ndjson"; }

@test "ship audit: a successful local ship logs an authorized AND a completed event (exit 0)" {
    local repo audit
    repo="$(mk_repo 1.2.3)"
    audit="$(AUDIT_FILE)"

    cd "$repo"
    PROJECT_ROOT="$repo" run manifest_ship_repo minor --local -y
    [ "$status" -eq 0 ]

    [ -f "$audit" ]
    # Both events exist for the one apply.
    [ "$(grep -c '"event":"authorized"' "$audit")" -eq 1 ]
    [ "$(grep -c '"event":"completed"' "$audit")" -eq 1 ]
    # The completion event records the REAL workflow outcome (success -> 0) and
    # the gate disposition (release_gate=none in setup -> bypassed).
    run grep '"event":"completed"' "$audit"
    [[ "$output" == *'"exit_status":0'* ]]
    [[ "$output" == *'"gate_status":"bypassed"'* ]]
    [[ "$output" == *'"source":"cli"'* ]]
}

@test "ship audit: a failing workflow logs a completed event with a NON-zero exit_status" {
    local repo audit
    repo="$(mk_repo 1.2.3)"
    audit="$(AUDIT_FILE)"

    # Force the workflow to fail AFTER the apply guard has emitted authorization,
    # the way the §8.3a fix must surface outcome (not just authorization). Stub
    # the orchestrator entrypoint to fail with a distinctive status.
    manifest_ship_workflow() { return 37; }

    cd "$repo"
    PROJECT_ROOT="$repo" run manifest_ship_repo minor --local -y
    [ "$status" -eq 37 ]

    [ -f "$audit" ]
    # Authorization still recorded (it ran before the workflow).
    [ "$(grep -c '"event":"authorized"' "$audit")" -eq 1 ]
    # Completion recorded with the real, non-zero workflow rc.
    [ "$(grep -c '"event":"completed"' "$audit")" -eq 1 ]
    run grep '"event":"completed"' "$audit"
    [[ "$output" == *'"exit_status":37'* ]]
    [[ "$output" != *'"exit_status":0'* ]]
}

@test "ship audit: the completion event carries the gate_status disposition (§8.3b)" {
    local repo audit
    repo="$(mk_repo 1.2.3)"
    audit="$(AUDIT_FILE)"

    # release_gate=none is set in setup; assert the durable record shows it so a
    # force-bypass is observable after the fact (not only in the ephemeral var).
    cd "$repo"
    PROJECT_ROOT="$repo" run manifest_ship_repo patch --local -y
    [ "$status" -eq 0 ]

    run grep '"event":"completed"' "$audit"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"gate_status":"bypassed"'* ]]
}

@test "ship audit: fleet members each log a cli-fleet completion event with their real rc" {
    local work audit
    work="$(mk_fleet 1.2.3)"
    audit="$(AUDIT_FILE)"

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship minor --local -y
    [ "$status" -eq 0 ]

    [ -f "$audit" ]
    # The member's apply (run in the fleet child subshell) records both events,
    # tagged cli-fleet, and the completion carries the member's real ship rc.
    [ "$(grep -c '"source":"cli-fleet"' "$audit")" -ge 2 ]
    run grep '"event":"completed"' "$audit"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"source":"cli-fleet"'* ]]
    [[ "$output" == *'"exit_status":0'* ]]
}

# -----------------------------------------------------------------------------
# refresh repo --local -y
#
# refresh never has remote operations regardless of --local; this proves the
# apply path regenerates docs locally and stays inside the offline boundary,
# without bumping the version.
# -----------------------------------------------------------------------------

@test "refresh repo --local -y: regenerates docs locally, no push or publish" {
    local repo
    repo="$(mk_repo 2.5.4)"
    # Local marker proves the regen step ran in-tree.
    manifest_docs_generate() { echo regenerated > "$PROJECT_ROOT/.refresh-marker"; return 0; }

    cd "$repo"
    PROJECT_ROOT="$repo" run manifest_refresh_repo --local -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Refresh complete."* ]]

    # Doc regen ran; version is unchanged (refresh never bumps).
    [ -f "$repo/.refresh-marker" ]
    [ "$(cat "$repo/VERSION")" = "2.5.4" ]

    assert_no_remote_dispatch
}

# -----------------------------------------------------------------------------
# ship fleet --local -y
#
# Drives the full fleet apply path: load config -> pre-flights -> single-flight
# lock -> per-member `manifest ship repo --local -y`. The member is bumped and
# committed locally; nothing is pushed, no PR/API call is made.
# -----------------------------------------------------------------------------

@test "ship fleet --local -y: applies each member locally, never pushes or publishes" {
    local work
    work="$(mk_fleet 1.2.3)"
    local before
    before="$("$REAL_GIT" -C "$work/svc" rev-parse HEAD)"

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship minor --local -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fleet ship workflow complete."* ]]

    # The member's local state advanced ...
    [ "$(cat "$work/svc/VERSION")" = "1.3.0" ]
    [ "$("$REAL_GIT" -C "$work/svc" rev-parse HEAD)" != "$before" ]
    # ... with no release tag pushed or created.
    [ -z "$("$REAL_GIT" -C "$work/svc" tag)" ]

    assert_no_remote_dispatch
}

@test "ship fleet --local -y: skips unchanged tagged members" {
    local work
    work="$(mk_two_member_fleet_with_clean_skip 1.2.3)"
    local clean_before dirty_before
    clean_before="$("$REAL_GIT" -C "$work/clean-svc" rev-parse HEAD)"
    dirty_before="$("$REAL_GIT" -C "$work/dirty-svc" rev-parse HEAD)"

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship patch --local -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean-svc: skipped (no changes)"* ]]
    [[ "$output" == *"dirty-svc: shipping patch"* ]]

    [ "$(cat "$work/clean-svc/VERSION")" = "1.2.3" ]
    [ "$("$REAL_GIT" -C "$work/clean-svc" rev-parse HEAD)" = "$clean_before" ]
    [ "$(cat "$work/dirty-svc/VERSION")" = "1.2.4" ]
    [ "$("$REAL_GIT" -C "$work/dirty-svc" rev-parse HEAD)" != "$dirty_before" ]

    assert_no_remote_dispatch
}
