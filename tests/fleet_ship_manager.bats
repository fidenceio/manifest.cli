#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# `manifest ship fleet manager` — the root-only scope (TRACKER §77(b)).
#
# The fleet root is a git repo carrying the coordination files. `ship fleet`
# reaches it only as the tail step of a member release, so a change to the
# coordination files THEMSELVES had no way to land short of a full fleet ship in
# which every member was a no-op. This verb commits and pushes the root alone.
#
# What these tests hold the verb to, in order of consequence:
#   1. It stages by allowlist NAME through the same writer the fleet release
#      uses — a secret or member source at the root is never committed, and a
#      non-coordination file the user staged makes it refuse before any commit.
#   2. Preview writes nothing and names exactly what apply will do.
#   3. The root gets no release treatment: no tag, and a fleet version stamp
#      only when the fleet has a scheme (never speculatively).
#   4. The push is the point, so it happens on apply and is skipped on --local.
# Every "X was not committed" assertion sits beside a positive control proving
# the commit happened at all, so a broken verb cannot pass by doing nothing.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    # A git identity for the fixtures that this verb itself git-inits.
    git config --global user.email test@example.com
    git config --global user.name "Test"

    # Full module graph, as scripts/manifest-cli.sh wires it, so the dispatch
    # tests run the real manifest_ship_fleet -> fleet_ship_manager path.
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-os.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-time.sh"

    # Hermetic trusted time for the date scheme: no NTP/HTTPS, deterministic.
    get_time_timestamp() { MANIFEST_CLI_TIME_TIMESTAMP=1700000000; return 0; }

    FLEET="$SCRATCH/fleet"
    REMOTE="$SCRATCH/remote.git"
    export FLEET REMOTE
    unset MANIFEST_CLI_FLEET_ACTIVE MANIFEST_CLI_FLEET_ROOT
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
    unset MANIFEST_CLI_FLEET_ROOT MANIFEST_CLI_FLEET_ACTIVE MANIFEST_CLI_FLEET_CONFIG_FILE
}

# A loadable fleet root: config + roster with one member.
#   $1 fleet.versioning scheme (default none)
#   $2 shape: remote  = git repo, allowlist, committed, pushed to a bare origin (default)
#             local   = git repo, allowlist, committed, no origin
#             plain   = files only — not a git repo yet
mk_fleet() {
    local scheme="${1:-none}" shape="${2:-remote}"
    mkdir -p "$FLEET/svc-a"
    git -C "$FLEET/svc-a" init -q -b main
    cat > "$FLEET/manifest.fleet.config.yaml" <<YAML
fleet:
  name: "test-fleet"
  versioning: "$scheme"
  version_file: "FLEET_VERSION"
YAML
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\n' > "$FLEET/manifest.fleet.tsv"
    printf 'true\tsvca\t./svc-a\ttrue\tmain\n' >> "$FLEET/manifest.fleet.tsv"
    export MANIFEST_CLI_FLEET_ROOT="$FLEET"
    [[ "$shape" == "plain" ]] && return 0

    git -C "$FLEET" init -q -b main
    create_fleet_gitignore "$FLEET" >/dev/null
    git -C "$FLEET" add -- .gitignore manifest.fleet.config.yaml manifest.fleet.tsv
    git -C "$FLEET" commit -q -m "fleet root"
    if [[ "$shape" == "remote" ]]; then
        git init -q --bare "$REMOTE"
        git -C "$FLEET" remote add origin "$REMOTE"
        git -C "$FLEET" push -q -u origin main
    fi
}

edit_config() { echo "  description: edited" >> "$FLEET/manifest.fleet.config.yaml"; }
remote_head() { git -C "$REMOTE" rev-parse refs/heads/main 2>/dev/null; }
root_head()   { git -C "$FLEET" rev-parse HEAD 2>/dev/null; }

# --- preview -----------------------------------------------------------------

@test "manager preview: a clean, pushed root has nothing to do and writes nothing" {
    mk_fleet none remote
    local before; before="$(root_head)"

    run fleet_ship_manager --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to commit or push"* ]]
    [[ "$output" == *"No changes written."* ]]
    # Nothing to apply, so no replay hint — a hint here would invite a no-op -y.
    refute grep -q "Re-run with -y" <<<"$output"
    [ "$(root_head)" = "$before" ]
}

@test "manager preview: names the changed coordination file and the push, and writes nothing" {
    mk_fleet none remote
    edit_config
    local before; before="$(root_head)"

    run fleet_ship_manager --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet manager"* ]]
    [[ "$output" == *"members are not touched"* ]]
    [[ "$output" == *"would commit manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"would push main to origin"* ]]
    [[ "$output" == *"manifest ship fleet manager -y"* ]]
    # Preview is read-only: no commit, nothing staged, no stamp.
    [ "$(root_head)" = "$before" ]
    [ -z "$(git -C "$FLEET" diff --cached --name-only)" ]
    [ ! -f "$FLEET/FLEET_VERSION" ]
}

# --- apply: the security property ---------------------------------------------

@test "manager apply: commits ONLY coordination files and pushes — never a secret or member source" {
    mk_fleet none remote
    edit_config
    mkdir -p "$FLEET/secure"
    echo 'Password=hunter2' > "$FLEET/secure/appsettings.production.json"
    echo 'src' > "$FLEET/svc-a/code.cs"
    echo 'stray' > "$FLEET/notes.txt"          # root-level, outside the allowlist

    run fleet_ship_manager -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"committed manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"pushed main"* ]]

    run git -C "$FLEET" log -1 --pretty=%s
    [ "$output" = "Fleet manager: update manifest.fleet.config.yaml" ]

    run git -C "$FLEET" ls-tree -r --name-only HEAD
    [[ "$output" == *"manifest.fleet.config.yaml"* ]]   # positive control: the commit carries the file
    [[ "$output" != *"secure/"* ]]                       # SECURITY: secret never committed
    [[ "$output" != *"svc-a"* ]]                         # member source never committed
    [[ "$output" != *"notes.txt"* ]]                     # outside the allowlist, even at the root
    [ "$(root_head)" = "$(remote_head)" ]                # pushed
    [ ! -f "$FLEET/FLEET_VERSION" ]                      # versioning none: no stamp, no tag
    [ -z "$(git -C "$FLEET" tag -l)" ]
}

@test "manager apply: REFUSES when a non-coordination file is staged, leaving the user's staging intact" {
    mk_fleet none remote
    edit_config
    echo 'Password=x' > "$FLEET/leak.json"
    git -C "$FLEET" add -f -- leak.json
    local before; before="$(root_head)"

    run fleet_ship_manager -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"REFUSED"* ]]
    [[ "$output" == *"leak.json"* ]]
    [ "$(root_head)" = "$before" ]                       # no commit
    run git -C "$FLEET" diff --cached --name-only
    [[ "$output" == *"leak.json"* ]]                     # the user's own staging is untouched

    # And the preview says so before -y is ever typed.
    run fleet_ship_manager --dry-run
    [[ "$output" == *"would REFUSE"* ]]
}

@test "manager apply: REFUSES on a detached HEAD before writing anything" {
    mk_fleet none remote
    edit_config
    git -C "$FLEET" checkout -q --detach
    local before; before="$(root_head)"

    run fleet_ship_manager -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"detached HEAD"* ]]
    [ "$(root_head)" = "$before" ]
    [ -z "$(git -C "$FLEET" diff --cached --name-only)" ]
}

@test "manager preview: on a detached HEAD it says -y would REFUSE, and offers no replay hint" {
    # The preview and the apply must read the same root the same way. The first
    # cut of the preview printed "would push HEAD" and the replay hint on a
    # detached root, then -y refused — found by the commit steward, not a test.
    mk_fleet none remote
    edit_config
    git -C "$FLEET" checkout -q --detach

    run fleet_ship_manager --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would REFUSE"* ]]
    [[ "$output" == *"detached HEAD"* ]]
    refute grep -q "Re-run with -y" <<<"$output"
    # Same for the other refusal: staged junk is named and the hint withheld.
    git -C "$FLEET" checkout -q main
    echo 'x' > "$FLEET/leak.json"
    git -C "$FLEET" add -f -- leak.json
    run fleet_ship_manager --dry-run
    [[ "$output" == *"would REFUSE"* ]]
    [[ "$output" == *"leak.json"* ]]
    refute grep -q "Re-run with -y" <<<"$output"
}

# --- apply: the stamp -----------------------------------------------------------

@test "manager apply: with fleet.versioning=date the commit also stamps the fleet version" {
    mk_fleet date remote
    edit_config

    run fleet_ship_manager -y
    [ "$status" -eq 0 ]
    local expected; expected="$(format_timestamp 1700000000 '+%Y.%m.%d.%H%M%S')"
    [ "$(cat "$FLEET/FLEET_VERSION")" = "$expected" ]
    [[ "$output" == *"stamped fleet version (unset) → $expected"* ]]
    run git -C "$FLEET" log -1 --pretty=%s
    [ "$output" = "Fleet manager: bump fleet version to $expected (updates: manifest.fleet.config.yaml)" ]
    run git -C "$FLEET" ls-tree -r --name-only HEAD
    [[ "$output" == *"FLEET_VERSION"* ]]
    [ "$(root_head)" = "$(remote_head)" ]
}

@test "manager apply: an explicit bump word stamps a semver fleet even when nothing else changed" {
    mk_fleet semver remote
    echo "1.2.3" > "$FLEET/FLEET_VERSION"
    git -C "$FLEET" add -- FLEET_VERSION
    git -C "$FLEET" commit -q -m "v1.2.3"
    git -C "$FLEET" push -q origin main

    # No bump word, clean root: nothing to do — a stamp is never speculative.
    run fleet_ship_manager --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to commit or push"* ]]

    # With one, the stamp IS the change.
    run fleet_ship_manager minor -y
    [ "$status" -eq 0 ]
    [ "$(cat "$FLEET/FLEET_VERSION")" = "1.3.0" ]
    run git -C "$FLEET" log -1 --pretty=%s
    [ "$output" = "Fleet manager: bump fleet version to 1.3.0" ]
    [ "$(root_head)" = "$(remote_head)" ]
}

# --- apply: the push ------------------------------------------------------------

@test "manager apply --local: commits but does not push" {
    mk_fleet none remote
    edit_config
    local remote_before; remote_before="$(remote_head)"

    run fleet_ship_manager -y --local
    [ "$status" -eq 0 ]
    [[ "$output" == *"committed manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"--local: nothing pushed"* ]]
    [ "$(remote_head)" = "$remote_before" ]              # remote received nothing
    [ "$(root_head)" != "$remote_before" ]               # ...while the local commit exists
}

@test "manager apply: a clean root with unpushed commits is pushed without a new commit" {
    mk_fleet none remote
    git -C "$FLEET" commit -q --allow-empty -m "root-only change"   # ahead by 1
    local before; before="$(root_head)"

    run fleet_ship_manager -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"pushed main"* ]]
    refute grep -q "committed" <<<"$output"
    [ "$(root_head)" = "$before" ]
    [ "$(remote_head)" = "$before" ]
}

@test "manager apply: a fresh root that is not a git repo yet is initialised, allowlisted and committed; no origin is reported" {
    mk_fleet none plain

    run fleet_ship_manager -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"wrote the allowlist .gitignore"* ]]
    [[ "$output" == *"no origin remote"* ]]
    grep -qxF '/*' "$FLEET/.gitignore"
    run git -C "$FLEET" ls-tree -r --name-only HEAD
    [[ "$output" == *".gitignore"* ]]
    [[ "$output" == *"manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"manifest.fleet.tsv"* ]]
    [[ "$output" != *"svc-a"* ]]
}

# --- dispatch: the command as typed ----------------------------------------------

@test "manager dispatch: 'manifest ship fleet manager' previews, and -y applies through the same path" {
    mk_fleet none remote
    edit_config

    run manifest_ship_dispatch fleet manager
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship fleet manager preview — no changes written"* ]]
    [[ "$output" == *"would commit manifest.fleet.config.yaml"* ]]

    # The execution contract still applies: --dry-run and -y cannot be combined.
    run manifest_ship_dispatch fleet manager --dry-run -y
    [ "$status" -ne 0 ]

    run manifest_ship_dispatch fleet manager -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Applying because -y/--yes was provided."* ]]
    [[ "$output" == *"Fleet manager complete"* ]]
    [ "$(root_head)" = "$(remote_head)" ]
}

@test "manager dispatch: --explain shows the manager recipe and runs nothing" {
    mk_fleet none remote
    edit_config
    local before; before="$(root_head)"

    run manifest_ship_dispatch fleet manager --explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest.builtin.ship.fleet.manager"* ]]
    [[ "$output" == *"commit-coordination-root"* ]]
    [ "$(root_head)" = "$before" ]
    [ -z "$(git -C "$FLEET" diff --cached --name-only)" ]
}

@test "manager: --help describes the scope and its limits" {
    run fleet_ship_manager --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"coordination root ONLY"* ]]
    [[ "$output" == *"no VERSION bump"* ]]
}

@test "manager: an unknown option is refused by name" {
    mk_fleet none remote
    run fleet_ship_manager --noprep
    [ "$status" -ne 0 ]
    [[ "$output" == *"--noprep"* ]]
}
