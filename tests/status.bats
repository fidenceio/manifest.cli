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
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\tws\tworkspaces\trepo\ttrue\tx\tmain\n"
        printf "true\tfe\tfrontend/fe\tservice\ttrue\tx\tmain\n"
        printf "true\tdbx\tdb/dbx\tservice\ttrue\tx\tmain\n"
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
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\ta\tapps/a\tservice\ttrue\tx\tmain\n"
        printf "true\tb\tapps/b/nested\tservice\ttrue\tx\tmain\n"
    } > "$SCRATCH/manifest.fleet.tsv"

    run _status_fleet_depth_profile_report "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MIXED"* ]]
    [[ "$output" == *"mixed-depth buckets: apps"* ]]
}

@test "depth profile: only git rows count; non-git scenery is excluded" {
    {
        echo "# Depth: 2"
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\tfe\tfrontend/fe\tservice\ttrue\tx\tmain\n"
        printf "false\tholding\tsecure/_holding\tscenery\tfalse\t\t\n"
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
