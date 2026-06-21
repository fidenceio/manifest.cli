#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-discovery.sh" "core/manifest-version-surfaces.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "status preview bump: patch increments rightmost" {
    run _status_preview_bump "1.2.3" "patch"
    [ "$output" = "1.2.4" ]
}

@test "status preview bump: minor increments middle, zeros patch" {
    run _status_preview_bump "1.2.3" "minor"
    [ "$output" = "1.3.0" ]
}

@test "status preview bump: major increments leftmost, zeros minor+patch" {
    run _status_preview_bump "1.2.3" "major"
    [ "$output" = "2.0.0" ]
}

@test "status preview bump: malformed version yields '?' instead of crashing" {
    run _status_preview_bump "garbage" "patch"
    [ "$output" = "?" ]
}

@test "status: runs cleanly in a non-git directory (no crash, exit 0)" {
    cd "$SCRATCH"
    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "not a git repository"
}

@test "status: shows VERSION + bump previews when VERSION is present" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "3.7.1" > VERSION
    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Version:.*3.7.1"
    echo "$output" | grep -q "patch → 3.7.2"
    echo "$output" | grep -q "minor → 3.8.0"
    echo "$output" | grep -q "major → 4.0.0"
}

@test "status: reports noncanonical version surfaces without mutating them" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "3.7.1" > VERSION
    cat > package.json <<'JSON'
{
  "name": "demo",
  "version": "0.0.0"
}
JSON

    run manifest_status repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Version files:.*1 noncanonical detected"
    echo "$output" | grep -q "read-only"
    echo "$output" | grep -q "version.sync unset"
    [ "$(yq e -r '.version' package.json)" = "0.0.0" ]
}

@test "status: version surface list mode prints detected files" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "1.0.0" > VERSION
    printf '{"version":"0.1.0"}\n' > package.json
    export MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE="list"

    run manifest_status repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "package.json.*package-manifest.*json.*0.1.0"
}

@test "status: version surface reporting can be disabled by policy" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "1.0.0" > VERSION
    printf '{"version":"0.1.0"}\n' > package.json
    export MANIFEST_CLI_VERSION_SURFACES_ENABLED="false"

    run manifest_status repo
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Version files:"
}

@test "status: working-tree counts render as one clean line" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "1.0.0" > VERSION
    git add VERSION
    git commit -qm "initial"

    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Working:.*clean"
    ! echo "$output" | grep -qx "0 modified, 0"
    ! echo "$output" | grep -qx "0 untracked"
}

@test "status: working-tree counts separate modified and untracked files" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@e.com
    git config user.name t
    echo "1.0.0" > VERSION
    git add VERSION
    git commit -qm "initial"
    echo "1.0.1" > VERSION
    echo "new" > extra.txt

    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Working:.*1 modified, 1 untracked"
}

@test "status repo: identity block detects enclosing fleet member" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi

    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-config.sh"

    mkdir -p "$SCRATCH/fleet/svc-a"
    git -C "$SCRATCH/fleet/svc-a" init -q
    git -C "$SCRATCH/fleet/svc-a" config user.email t@e.com
    git -C "$SCRATCH/fleet/svc-a" config user.name t
    echo "1.0.0" > "$SCRATCH/fleet/svc-a/VERSION"
    git -C "$SCRATCH/fleet/svc-a" add VERSION
    git -C "$SCRATCH/fleet/svc-a" commit -qm "initial"

    cat > "$SCRATCH/fleet/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: test-fleet
services:
  svc-a:
    path: ./svc-a
YAML

    cd "$SCRATCH/fleet/svc-a"
    run manifest_status repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Repo identity"
    echo "$output" | grep -q "Current repo:.*svc-a"
    echo "$output" | grep -q "Fleet context:.*test-fleet"
    echo "$output" | grep -q "Fleet member:.*svc-a"
    echo "$output" | grep -q "Mutation scope:.*this Git repository only"
}

@test "status: fleet root prints repo table with version, timestamp, and latest commit" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi

    mkdir -p "$SCRATCH/svc-a" "$SCRATCH/svc-b"
    git -C "$SCRATCH/svc-a" init -q
    git -C "$SCRATCH/svc-a" config user.email t@e.com
    git -C "$SCRATCH/svc-a" config user.name t
    echo "1.2.3" > "$SCRATCH/svc-a/VERSION"
    printf '{"version":"0.1.0"}\n' > "$SCRATCH/svc-a/package.json"
    git -C "$SCRATCH/svc-a" add VERSION package.json
    GIT_AUTHOR_DATE="2026-05-01T12:00:00Z" GIT_COMMITTER_DATE="2026-05-01T12:00:00Z" \
        git -C "$SCRATCH/svc-a" commit -qm "Initial A"
    local branch_a
    branch_a="$(git -C "$SCRATCH/svc-a" branch --show-current)"

    git -C "$SCRATCH/svc-b" init -q
    git -C "$SCRATCH/svc-b" config user.email t@e.com
    git -C "$SCRATCH/svc-b" config user.name t
    echo "2.0.0" > "$SCRATCH/svc-b/VERSION"
    git -C "$SCRATCH/svc-b" add VERSION
    GIT_AUTHOR_DATE="2026-05-02T12:00:00Z" GIT_COMMITTER_DATE="2026-05-02T12:00:00Z" \
        git -C "$SCRATCH/svc-b" commit -qm "Initial B"
    local branch_b
    branch_b="$(git -C "$SCRATCH/svc-b" branch --show-current)"
    echo "dirty" > "$SCRATCH/svc-b/dirty.txt"

    cat > "$SCRATCH/manifest.fleet.yaml" <<YAML
fleet:
  name: test-fleet
services:
  svc-a:
    path: ./svc-a
    branch: $branch_a
  svc-b:
    path: ./svc-b
    branch: $branch_b
YAML

    cd "$SCRATCH"
    run manifest_status
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Fleet:.*test-fleet"
    echo "$output" | grep -q "Config:.*manifest.fleet.yaml"
    echo "$output" | grep -q "Scope:.*fleet"
    echo "$output" | grep -q "Repos:.*2 total"
    echo "$output" | grep -q "Included repositories"
    echo "$output" | grep -q "Repo.*Branch.*State.*Version.*Timestamp.*Path.*Latest commit"
    echo "$output" | grep -q "svc-a.*${branch_a}.*clean.*1.2.3.*2026-05-01.*$SCRATCH/svc-a.*Initial A"
    echo "$output" | grep -q "svc-b.*${branch_b}.*dirty.*2.0.0.*2026-05-02.*$SCRATCH/svc-b.*Initial B"
    echo "$output" | grep -q "Version surfaces"
    echo "$output" | grep -q "1 noncanonical detected across 1 repo"
}

@test "runtime bash detection reports current interpreter, not PATH bash" {
    local fake_bin="$SCRATCH/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/bash" <<'SCRIPT'
#!/usr/bin/env sh
echo "GNU bash, version 3.2.57(1)-release"
SCRIPT
    chmod +x "$fake_bin/bash"
    PATH="$fake_bin:$PATH"

    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-os.sh" >/dev/null
    detect_bash_version

    [ "$MANIFEST_CLI_OS_BASH_MAJOR" = "${BASH_VERSINFO[0]}" ]
    [ "$MANIFEST_CLI_OS_BASH_MINOR" = "${BASH_VERSINFO[1]}" ]
    [[ "$MANIFEST_CLI_OS_BASH_VERSION" != "3.2"* ]]
}

@test "depth profile: uniform buckets report no mixed-depth health issue" {
    {
        echo "# Depth: 2"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\tws\tworkspaces\ttrue\tx\tmain\n"
        printf "true\tfe\tfrontend/fe\ttrue\tx\tmain\n"
        printf "true\tdbx\tdb/dbx\ttrue\tx\tmain\n"
    } > "$SCRATCH/manifest.fleet.tsv"

    run _status_fleet_depth_profile_report "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Depth profile"* ]]
    [[ "$output" == *"global: shallowest 1, deepest 2"* ]]
    [[ "$output" == *"mixed-depth buckets: none"* ]]
}

@test "depth profile: a bucket spanning two depths is flagged MIXED" {
    {
        echo "# Depth: 3"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\ta\tapps/a\ttrue\tx\tmain\n"
        printf "true\tb\tapps/b/nested\ttrue\tx\tmain\n"
    } > "$SCRATCH/manifest.fleet.tsv"

    run _status_fleet_depth_profile_report "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MIXED"* ]]
    [[ "$output" == *"mixed-depth buckets: apps"* ]]
}

@test "depth profile: only git rows count; non-git scenery is excluded" {
    {
        echo "# Depth: 2"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\tfe\tfrontend/fe\ttrue\tx\tmain\n"
        printf "false\tholding\tsecure/_holding\tfalse\t\t\n"
    } > "$SCRATCH/manifest.fleet.tsv"

    run _status_fleet_depth_profile_report "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"frontend"* ]]
    [[ "$output" != *"secure"* ]]
}

@test "depth profile: no TSV produces no output" {
    run _status_fleet_depth_profile_report "$SCRATCH"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# -- Roster sourced from the TSV (bug: status read empty config .services) ----

# Build a fleet workspace whose declared roster lives only in manifest.fleet.tsv
# and whose config .services map is EMPTY — the exact shape that made
# `manifest status fleet` report 0 repos.
_mk_tsv_only_fleet() {
    local root="$1"
    local present_count="${2:-3}"
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: $root"
        echo "# Depth: 2"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        local i
        for ((i = 1; i <= present_count; i++)); do
            mkdir -p "$root/svc/m$i"
            git -C "$root/svc/m$i" init -q
            git -C "$root/svc/m$i" config user.email t@e.com
            git -C "$root/svc/m$i" config user.name t
            echo "1.0.$i" > "$root/svc/m$i/VERSION"
            git -C "$root/svc/m$i" add VERSION
            git -C "$root/svc/m$i" commit -qm "init m$i"
            printf "true\tm%s\tsvc/m%s\ttrue\tgit@github.com:acme/m%s.git\tmain\n" "$i" "$i" "$i"
        done
    } > "$root/manifest.fleet.tsv"
    # Config exists but declares no services (the buggy state).
    cat > "$root/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: tsv-fleet
services: {}
YAML
}

@test "status fleet: counts the TSV roster, not the empty config .services" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_tsv_only_fleet "$SCRATCH" 3

    cd "$SCRATCH"
    run _manifest_status_fleet "$SCRATCH" "false" "off"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Fleet:.*tsv-fleet"
    echo "$output" | grep -q "Roster:.*manifest.fleet.tsv"
    echo "$output" | grep -q "Repos:.*3 total"
    echo "$output" | grep -q "m1"
    echo "$output" | grep -q "m3"
    # Proof of the bug fix: the count must not be 0 just because .services is {}.
    ! echo "$output" | grep -q "Repos:.*0 total"
}

@test "status fleet --json: repositories array reflects the TSV roster" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_tsv_only_fleet "$SCRATCH" 2

    run _manifest_status_fleet "$SCRATCH" "true" "off"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | yq e '.repositories | length' -)" = "2" ]
    [ "$(echo "$output" | yq e '.repositories[0].name' -)" = "m1" ]
    [ "$(echo "$output" | yq e '.repositories[0].remote_url' -)" = "git@github.com:acme/m1.git" ]
}

@test "status fleet: roster is read via parse_start_tsv when fleet module loaded" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    # Load the fleet detect module so parse_start_tsv is the active reader; this
    # asserts the canonical TSV reader and the inline fallback agree.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-config.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    declare -F parse_start_tsv >/dev/null

    _mk_tsv_only_fleet "$SCRATCH" 3
    run _status_fleet_roster_count "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "identity: enclosing member resolved from the TSV roster, not config" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-config.sh"
    _mk_tsv_only_fleet "$SCRATCH" 2

    cd "$SCRATCH/svc/m2"
    run manifest_status repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Repo identity"
    echo "$output" | grep -q "Fleet context:.*tsv-fleet"
    # The member name comes from the TSV row even though config .services is {}.
    echo "$output" | grep -q "Fleet member:.*m2"
}

# -- Bootstrap preview (declared-but-absent members) --------------------------

@test "status fleet --bootstrap: lists absent members WITHOUT cloning" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_tsv_only_fleet "$SCRATCH" 2
    # Declare a third member that exists in the roster but is absent on disk,
    # plus a fourth that is absent with no remote (Lost).
    printf "true\tghost\tsvc/ghost\ttrue\tgit@github.com:acme/ghost.git\tmain\n" >> "$SCRATCH/manifest.fleet.tsv"
    printf "true\tlostone\tsvc/lostone\ttrue\t\tmain\n" >> "$SCRATCH/manifest.fleet.tsv"

    [ ! -d "$SCRATCH/svc/ghost" ]

    run _manifest_status_fleet "$SCRATCH" "false" "preview"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Bootstrap preview"
    echo "$output" | grep -q "ghost.*would clone from git@github.com:acme/ghost.git"
    echo "$output" | grep -q "Plan: 1 clone, 1 unrecoverable"
    echo "$output" | grep -q "lostone.*LOST"
    echo "$output" | grep -q "No changes written"

    # Hard proof nothing was cloned: the target path must still be absent.
    [ ! -d "$SCRATCH/svc/ghost" ]
    [ ! -e "$SCRATCH/svc/ghost/.git" ]
}

@test "status fleet (no --bootstrap): only hints that absent members exist" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_tsv_only_fleet "$SCRATCH" 1
    printf "true\tghost\tsvc/ghost\ttrue\tgit@github.com:acme/ghost.git\tmain\n" >> "$SCRATCH/manifest.fleet.tsv"

    run _manifest_status_fleet "$SCRATCH" "false" "off"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Bootstrap:.*1 member(s) declared but absent"
    echo "$output" | grep -q "manifest status fleet --bootstrap"
    ! echo "$output" | grep -q "Bootstrap preview"
    [ ! -d "$SCRATCH/svc/ghost" ]
}

@test "status fleet --bootstrap: all members present says nothing to clone" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_tsv_only_fleet "$SCRATCH" 2

    run _manifest_status_fleet "$SCRATCH" "false" "preview"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Bootstrap preview"
    echo "$output" | grep -q "nothing to clone"
}

@test "status: --bootstrap flag routes to fleet scope and preview mode" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_tsv_only_fleet "$SCRATCH" 1
    printf "true\tghost\tsvc/ghost\ttrue\tgit@github.com:acme/ghost.git\tmain\n" >> "$SCRATCH/manifest.fleet.tsv"

    PROJECT_ROOT="$SCRATCH" run manifest_status --bootstrap
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Bootstrap preview"
    echo "$output" | grep -q "ghost.*would clone"
    [ ! -d "$SCRATCH/svc/ghost" ]
}
