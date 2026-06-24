#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Covers `--force-bump` and the symmetric "nothing to release" gate (CLI tracker
# §8.x force-bump). Two halves:
#   1. ship repo  — a clean tree already at its release tag now SKIPS by default
#      (parity with ship fleet); --force-bump bypasses the skip to cut a
#      deliberate forward-only release.
#   2. ship fleet — --force-bump makes previously-skipped (clean, at-tag) members
#      ship, while policy gates (release-disabled, etc.) are still honored.
#
# Harness mirrors ship_local_apply.bats: full module graph + a PATH-level git
# shim that refuses (and logs) every network subcommand, plus gh/brew stubs, so
# nothing crosses the offline boundary.

load 'helpers/setup'

REAL_GIT="$(command -v git)"

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME

    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"

    # Neutralize slow / networked / out-of-scope steps (not the contract here).
    get_time_timestamp() {
        MANIFEST_CLI_TIME_TIMESTAMP="1700000000"
        MANIFEST_CLI_TIME_METHOD="stub"
        export MANIFEST_CLI_TIME_TIMESTAMP MANIFEST_CLI_TIME_METHOD
    }
    format_timestamp() { echo "2023-11-14 00:00:00 UTC"; }
    main_cleanup() { return 0; }
    validate_project() { return 0; }
    update_repository_metadata() { :; }
    fleet_validate() { return 0; }
    fleet_docs_dispatch() { return 0; }

    export MANIFEST_CLI_RELEASE_GATE=none
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=main
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
# Offline boundary shims (identical contract to ship_local_apply.bats)
# -----------------------------------------------------------------------------
install_offline_shims() {
    local bin="$SCRATCH/bin"
    mkdir -p "$bin"

    cat > "$bin/git" <<SHIM
#!/usr/bin/env bash
REAL_GIT="$REAL_GIT"
NET_LOG="$NET_LOG"
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

assert_no_remote_dispatch() {
    run grep -c '^push' "$NET_LOG"
    [ "$output" -eq 0 ]
    [ ! -s "$GH_LOG" ]
    [ ! -s "$BREW_LOG" ]
}

# -----------------------------------------------------------------------------
# Fixture builders (REAL_GIT so the shim only ever sees the CLI's own calls)
# -----------------------------------------------------------------------------

# A repo on `main`, one commit, NO tag, configured (unreachable) remote.
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

# Same, but TAGGED at HEAD (v<version>) and clean — the "nothing to release"
# state the new gate must skip.
mk_tagged_repo() {
    local repo version
    repo="$(mk_repo "${1:-1.2.3}")"
    "$REAL_GIT" -C "$repo" tag "v${1:-1.2.3}"
    echo "$repo"
}

# Initialize one fleet member repo: one commit, tagged at HEAD, clean, remote.
_mk_member() {
    local dir="$1" version="$2"
    "$REAL_GIT" -C "$dir" init -q
    "$REAL_GIT" -C "$dir" symbolic-ref HEAD refs/heads/main
    "$REAL_GIT" -C "$dir" config user.email test@example.com
    "$REAL_GIT" -C "$dir" config user.name test
    echo "$version" > "$dir/VERSION"
    "$REAL_GIT" -C "$dir" add VERSION
    "$REAL_GIT" -C "$dir" commit -qm "init $version"
    "$REAL_GIT" -C "$dir" tag "v$version"
    "$REAL_GIT" -C "$dir" remote add origin "https://example.invalid/$(basename "$dir").git"
}

# Two release-enabled members, both clean and at their tag → both "no changes".
mk_fleet_two_clean() {
    local work="$SCRATCH/work" version="${1:-1.2.3}"
    mkdir -p "$work/svc-a" "$work/svc-b"
    cat > "$work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svc-a:
    path: "./svc-a"
    type: "service"
    branch: "main"
    release:
      enabled: true
  svc-b:
    path: "./svc-b"
    type: "service"
    branch: "main"
    release:
      enabled: true
YAML
    {
        printf 'true\tsvc-a\t./svc-a\tfalse\t\tmain\t%s\n' "$version"
        printf 'true\tsvc-b\t./svc-b\tfalse\t\tmain\t%s\n' "$version"
    } > "$work/manifest.fleet.tsv"
    _mk_member "$work/svc-a" "$version"
    _mk_member "$work/svc-b" "$version"
    echo "$work"
}

# One release-enabled member + one release-DISABLED member, both clean at tag.
# Proves --force-bump honors policy gates (the disabled member never ships).
mk_fleet_clean_plus_disabled() {
    local work="$SCRATCH/work" version="${1:-1.2.3}"
    mkdir -p "$work/svc-on" "$work/svc-off"
    cat > "$work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svc-on:
    path: "./svc-on"
    type: "service"
    branch: "main"
    release:
      enabled: true
  svc-off:
    path: "./svc-off"
    type: "service"
    branch: "main"
    release:
      enabled: false
YAML
    {
        printf 'true\tsvc-on\t./svc-on\tfalse\t\tmain\t%s\n' "$version"
        printf 'true\tsvc-off\t./svc-off\tfalse\t\tmain\t%s\n' "$version"
    } > "$work/manifest.fleet.tsv"
    _mk_member "$work/svc-on" "$version"
    _mk_member "$work/svc-off" "$version"
    echo "$work"
}

# =============================================================================
# Commit 1 — ship repo: symmetric gate + --force-bump
# =============================================================================

@test "ship repo -y: clean repo at its release tag skips with a notice, cuts nothing" {
    local repo before
    repo="$(mk_tagged_repo 1.2.3)"
    before="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

    cd "$repo"
    MANIFEST_CLI_PROJECT_ROOT="$repo" run manifest_ship_repo patch -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to release"* ]]
    [[ "$output" == *"--force-bump"* ]]

    # Nothing was cut: VERSION, HEAD, and the tag set are all unchanged.
    [ "$(cat "$repo/VERSION")" = "1.2.3" ]
    [ "$("$REAL_GIT" -C "$repo" rev-parse HEAD)" = "$before" ]
    [ "$("$REAL_GIT" -C "$repo" tag)" = "v1.2.3" ]

    assert_no_remote_dispatch
}

@test "ship repo: clean repo at its release tag skips in PREVIEW too (exit 0)" {
    local repo
    repo="$(mk_tagged_repo 1.2.3)"

    cd "$repo"
    MANIFEST_CLI_PROJECT_ROOT="$repo" run manifest_ship_repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to release"* ]]
    # Preview wrote nothing.
    [ "$(cat "$repo/VERSION")" = "1.2.3" ]
}

@test "ship repo --force-bump --local -y: bumps a clean at-tag repo (forward-only)" {
    local repo before
    repo="$(mk_tagged_repo 1.2.3)"
    before="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

    cd "$repo"
    MANIFEST_CLI_PROJECT_ROOT="$repo" run manifest_ship_repo patch --force-bump --local -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"force-bump"* ]]
    [[ "$output" != *"Nothing to release"* ]]

    # The bump itself becomes the change: VERSION advances, a new commit lands.
    [ "$(cat "$repo/VERSION")" = "1.2.4" ]
    [ "$("$REAL_GIT" -C "$repo" rev-parse HEAD)" != "$before" ]

    assert_no_remote_dispatch
}

@test "ship repo --local -y: a repo with NO tag still ships (gate only fires at-tag)" {
    local repo
    repo="$(mk_repo 1.2.3)"

    cd "$repo"
    MANIFEST_CLI_PROJECT_ROOT="$repo" run manifest_ship_repo patch --local -y
    [ "$status" -eq 0 ]
    [[ "$output" != *"Nothing to release"* ]]
    [ "$(cat "$repo/VERSION")" = "1.2.4" ]

    assert_no_remote_dispatch
}

@test "ship repo --local -y: a dirty repo at its tag still ships (no flag needed)" {
    local repo
    repo="$(mk_tagged_repo 1.2.3)"
    echo "pending work" > "$repo/feature.txt"

    cd "$repo"
    MANIFEST_CLI_PROJECT_ROOT="$repo" run manifest_ship_repo patch --local -y
    [ "$status" -eq 0 ]
    [[ "$output" != *"Nothing to release"* ]]
    [ "$(cat "$repo/VERSION")" = "1.2.4" ]

    assert_no_remote_dispatch
}

# =============================================================================
# Commit 2 — ship fleet: --force-bump
# =============================================================================

@test "ship fleet --local -y: clean at-tag members are skipped by default" {
    local work
    work="$(mk_fleet_two_clean 1.2.3)"

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship patch --local -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"svc-a: skipped (no changes)"* ]]
    [[ "$output" == *"svc-b: skipped (no changes)"* ]]
    [ "$(cat "$work/svc-a/VERSION")" = "1.2.3" ]
    [ "$(cat "$work/svc-b/VERSION")" = "1.2.3" ]

    assert_no_remote_dispatch
}

@test "ship fleet --local --force-bump -y: ships clean at-tag members anyway" {
    local work a_before b_before
    work="$(mk_fleet_two_clean 1.2.3)"
    a_before="$("$REAL_GIT" -C "$work/svc-a" rev-parse HEAD)"
    b_before="$("$REAL_GIT" -C "$work/svc-b" rev-parse HEAD)"

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship patch --local --force-bump -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"svc-a: force-bumping patch"* ]]
    [[ "$output" == *"svc-b: force-bumping patch"* ]]

    # Both members advanced — the bump itself is the change.
    [ "$(cat "$work/svc-a/VERSION")" = "1.2.4" ]
    [ "$(cat "$work/svc-b/VERSION")" = "1.2.4" ]
    [ "$("$REAL_GIT" -C "$work/svc-a" rev-parse HEAD)" != "$a_before" ]
    [ "$("$REAL_GIT" -C "$work/svc-b" rev-parse HEAD)" != "$b_before" ]

    assert_no_remote_dispatch
}

@test "ship fleet --force-bump -y: still honors policy gates (release-disabled never ships)" {
    local work
    work="$(mk_fleet_clean_plus_disabled 1.2.3)"

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship patch --local --force-bump -y
    [ "$status" -eq 0 ]
    # Enabled member is forced; disabled member is still skipped (policy gate).
    [[ "$output" == *"svc-on: force-bumping patch"* ]]
    [[ "$output" == *"svc-off: skipped (release disabled)"* ]]
    [ "$(cat "$work/svc-on/VERSION")" = "1.2.4" ]
    [ "$(cat "$work/svc-off/VERSION")" = "1.2.3" ]

    assert_no_remote_dispatch
}

@test "ship fleet --force-bump (preview): labels forced members and notes the mode" {
    local work
    work="$(mk_fleet_two_clean 1.2.3)"

    export MANIFEST_CLI_FLEET_ROOT="$work"
    cd "$work"
    load_fleet_config "$work" >/dev/null 2>&1 || true

    run fleet_ship patch --force-bump
    [ "$status" -eq 0 ]
    [[ "$output" == *"would force"* ]]
    [[ "$output" == *"force-bump: members with no changes"* ]]
    # Preview wrote nothing.
    [ "$(cat "$work/svc-a/VERSION")" = "1.2.3" ]
    [ "$(cat "$work/svc-b/VERSION")" = "1.2.3" ]
}
