#!/usr/bin/env bats

# Coverage for CLI tracker §1.6: fleet-level resume entrypoint.
#
# Three layers:
#   1. Probe (manifest_ship_repo_resume_eligible) — unit, no fleet plumbing
#   2. Classifier (_fleet_resume_classify) — unit, real per-member git repos
#   3. CLI driven (manifest ship fleet resume) — end-to-end preview + empty apply

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    load_modules core/manifest-config.sh
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    export MANIFEST_CLI_FLEET_NAME="test-fleet"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"
}

teardown() {
    cd /tmp || true
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# Initialize a member repo with VERSION and an initial commit on main.
mk_member_repo() {
    local repo="$1" version="${2:-1.2.3}"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b main
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    echo "$version" > "$repo/VERSION"
    git -C "$repo" add VERSION
    git -C "$repo" commit -qm "Bump version to $version"
}

# Drop a member repo into a legacy stranded state: VERSION + local tag + dirty
# formula. Modern ship should not dirty the source formula, but resume still
# accepts this historical failure shape.
mk_stranded_member() {
    local repo="$1" version="${2:-1.2.3}"
    mk_member_repo "$repo" "$version"
    mkdir -p "$repo/formula"
    echo "original formula" > "$repo/formula/manifest.rb"
    git -C "$repo" add formula/manifest.rb
    git -C "$repo" commit -qm "Add formula"
    git -C "$repo" tag "v$version"
    echo "post-tag formula edit" > "$repo/formula/manifest.rb"
}

# ------------------------------------------------------------------ probe ---

@test "probe: eligible — VERSION + local tag + clean tree (modulo formula)" {
    local repo="$SCRATCH/work/svca"
    mk_stranded_member "$repo" 1.2.3

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_resume_eligible"

    [ "$status" -eq 0 ]
    [[ "$output" == eligible\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: no-version — VERSION file missing" {
    local repo="$SCRATCH/work/svcb"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b main
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    echo "stub" > "$repo/stub.txt"
    git -C "$repo" add stub.txt
    git -C "$repo" commit -qm "initial"

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_resume_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == no-version* ]]
}

@test "probe: no-local-tag — VERSION present but tag does not exist" {
    local repo="$SCRATCH/work/svcc"
    mk_member_repo "$repo" 1.2.3
    # No tag created.

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_resume_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == no-local-tag\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: dirty-tree — unrelated file dirty disqualifies" {
    local repo="$SCRATCH/work/svcd"
    mk_stranded_member "$repo" 1.2.3
    echo "unrelated change" > "$repo/runtime.txt"

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_resume_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == dirty-tree\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: tag-not-ancestor — tag points at a commit outside HEAD's history" {
    local repo="$SCRATCH/work/svcf"
    mk_member_repo "$repo" 1.2.3
    # Build one commit ahead, tag it, then reset HEAD back so the tag points
    # at an orphaned commit that is NOT in HEAD's history.
    echo "ahead" > "$repo/ahead.txt"
    git -C "$repo" add ahead.txt
    git -C "$repo" commit -qm "B"
    git -C "$repo" tag v1.2.3
    git -C "$repo" reset --hard HEAD~1 >/dev/null 2>&1

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_resume_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == tag-not-ancestor\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: no-branch — detached HEAD disqualifies" {
    local repo="$SCRATCH/work/svcg"
    mk_stranded_member "$repo" 1.2.3
    # Detach HEAD off main; tag still points at HEAD's commit, just no branch.
    git -C "$repo" checkout --detach HEAD >/dev/null 2>&1

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_resume_eligible"

    [ "$status" -eq 1 ]
    [[ "$output" == no-branch\|1.2.3\|v1.2.3\|* ]]
}

@test "probe: dirty formula/manifest.rb alone is still eligible" {
    local repo="$SCRATCH/work/svce"
    mk_stranded_member "$repo" 1.2.3
    # Formula already dirty from mk_stranded_member, no other changes.

    run bash -c "cd '$repo' && MANIFEST_CLI_PROJECT_ROOT='$repo' && \
        source '$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh' && \
        source '$TEST_REPO_ROOT/modules/git/manifest-git.sh' && \
        manifest_ship_repo_resume_eligible"

    [ "$status" -eq 0 ]
    [[ "$output" == eligible* ]]
}

# ------------------------------------------------------------ classifier ---

setup_three_member_fleet() {
    mk_stranded_member "$SCRATCH/work/svc-a" 1.2.3   # eligible
    mk_member_repo     "$SCRATCH/work/svc-b" 1.2.3   # nothing (no local tag)
    mk_member_repo     "$SCRATCH/work/svc-c" 1.2.3   # disabled (release_enabled=false)

    # Define the service set the classifier walks.
    export MANIFEST_CLI_FLEET_SERVICES="svca svcb svcc"

    # Stub get_fleet_service_property: returns paths, marks svcc release-disabled,
    # honors the trailing default for unknown props.
    get_fleet_service_property() {
        local svc="$1" prop="$2" default="${3:-}"
        case "$prop:$svc" in
            path:svca)            echo "$SCRATCH/work/svc-a" ;;
            path:svcb)            echo "$SCRATCH/work/svc-b" ;;
            path:svcc)            echo "$SCRATCH/work/svc-c" ;;
            release_enabled:svcc) echo "false" ;;
            *)                    echo "$default" ;;
        esac
    }
    export -f get_fleet_service_property
}

@test "classifier: three-member fleet splits across all three buckets" {
    setup_three_member_fleet

    local -a eligible=() nothing=() disabled=()
    _fleet_resume_classify

    [ "${#eligible[@]}" -eq 1 ]
    [[ "${eligible[0]}" == svca\|*svc-a\|1.2.3\|v1.2.3 ]]

    [ "${#nothing[@]}" -eq 1 ]
    [[ "${nothing[0]}" == svcb\|*svc-b\|no-local-tag\|* ]]

    [ "${#disabled[@]}" -eq 1 ]
    [[ "${disabled[0]}" == svcc\|*svc-c\|* ]]
}

@test "classifier: all clean fleet yields empty eligible array" {
    mk_member_repo "$SCRATCH/work/svc-a" 1.2.3
    mk_member_repo "$SCRATCH/work/svc-b" 1.2.3
    export MANIFEST_CLI_FLEET_SERVICES="svca svcb"
    get_fleet_service_property() {
        local svc="$1" prop="$2" default="${3:-}"
        case "$prop:$svc" in
            path:svca) echo "$SCRATCH/work/svc-a" ;;
            path:svcb) echo "$SCRATCH/work/svc-b" ;;
            *)         echo "$default" ;;
        esac
    }
    export -f get_fleet_service_property

    local -a eligible=() nothing=() disabled=()
    _fleet_resume_classify

    [ "${#eligible[@]}" -eq 0 ]
    [ "${#nothing[@]}" -eq 2 ]
    [ "${#disabled[@]}" -eq 0 ]
}

@test "classifier: member without .git is classified as disabled (not a git repo)" {
    mkdir -p "$SCRATCH/work/svc-x"
    echo "1.2.3" > "$SCRATCH/work/svc-x/VERSION"
    # No git init — static release-target classification returns "not a git repo".
    export MANIFEST_CLI_FLEET_SERVICES="svcx"
    get_fleet_service_property() {
        local svc="$1" prop="$2" default="${3:-}"
        case "$prop:$svc" in
            path:svcx) echo "$SCRATCH/work/svc-x" ;;
            *)         echo "$default" ;;
        esac
    }
    export -f get_fleet_service_property

    local -a eligible=() nothing=() disabled=()
    _fleet_resume_classify

    [ "${#eligible[@]}" -eq 0 ]
    [ "${#nothing[@]}" -eq 0 ]
    [ "${#disabled[@]}" -eq 1 ]
    [[ "${disabled[0]}" == svcx\|*svc-x\|"not a git repo" ]]
}

# ------------------------------------------------------------ CLI driven ---

write_fleet_config() {
    # Two members: svc-a stranded (eligible), svc-b clean (nothing).
    mk_stranded_member "$SCRATCH/work/svc-a" 1.2.3
    mk_member_repo     "$SCRATCH/work/svc-b" 1.2.3
    git -C "$SCRATCH/work" init -q 2>/dev/null || true

    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svca:
    path: "./svc-a"
    type: "service"
    branch: "main"
  svcb:
    path: "./svc-b"
    type: "service"
    branch: "main"
YAML

    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svca	./svc-a	true
true	svcb	./svc-b	true
TSV
}

@test "CLI: ship fleet resume preview classifies eligible vs nothing" {
    write_fleet_config

    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet resume

    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship fleet resume preview"* ]]
    [[ "$output" == *"Fleet resume plan"* ]]
    [[ "$output" == *"Eligible (1):"* ]]
    [[ "$output" == *"🔧 svca → resume v1.2.3"* ]]
    [[ "$output" == *"Nothing to resume (1):"* ]]
    [[ "$output" == *"✓  svcb (no-local-tag)"* ]]
    # Preview must not mutate.
    [ -z "$(git -C "$SCRATCH/work/svc-a" log --oneline @{u}.. 2>/dev/null || true)" ]
}

@test "CLI: ship fleet resume -y exits 0 cleanly when nothing eligible" {
    # All members clean — nothing to resume.
    mk_member_repo "$SCRATCH/work/svc-a" 1.2.3
    mk_member_repo "$SCRATCH/work/svc-b" 1.2.3
    git -C "$SCRATCH/work" init -q 2>/dev/null || true

    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svca:
    path: "./svc-a"
    type: "service"
    branch: "main"
  svcb:
    path: "./svc-b"
    type: "service"
    branch: "main"
YAML
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svca	./svc-a	true
true	svcb	./svc-b	true
TSV

    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet resume -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Eligible (0):"* ]]
    [[ "$output" == *"Nothing to resume across fleet."* ]]
}

@test "CLI: ship fleet resume --local is refused" {
    write_fleet_config

    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet resume --local

    [ "$status" -ne 0 ]
    [[ "$output" == *"does not support --local"* ]]
}

@test "CLI: ship fleet resume --dry-run is an explicit preview (same as bare resume)" {
    write_fleet_config

    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet resume --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship fleet resume preview"* ]]
    [[ "$output" == *"🔧 svca → resume v1.2.3"* ]]
    # Still no mutation: svc-a's formula remains dirty (unrecovered).
    [ -n "$(git -C "$SCRATCH/work/svc-a" status --porcelain 2>/dev/null)" ]
}

@test "fleet_resume -y delegates to per-repo resume; aborts fail-fast on first failure" {
    # Three eligible members; stub per-repo resume to succeed on svca, fail on
    # svcb. svcc must never be reached (fail-fast). Stubbing the per-repo
    # function isolates the fleet-walker logic from the real push pipeline.
    mk_stranded_member "$SCRATCH/work/svc-a" 1.2.3
    mk_stranded_member "$SCRATCH/work/svc-b" 1.2.3
    mk_stranded_member "$SCRATCH/work/svc-c" 1.2.3

    local repo gate
    for repo in svc-a svc-b svc-c; do
        case "$repo" in
            svc-a) gate="none" ;;
            svc-b) gate="remote-ci" ;;
            *)     gate="all" ;;
        esac
        printf 'release:\n  gate: "%s"\n' "$gate" \
            > "$SCRATCH/work/$repo/manifest.config.yaml"
        git -C "$SCRATCH/work/$repo" add manifest.config.yaml
        git -C "$SCRATCH/work/$repo" commit -qm "Configure $gate release gate"
    done

    export MANIFEST_CLI_FLEET_SERVICES="svca svcb svcc"
    get_fleet_service_property() {
        local svc="$1" prop="$2" default="${3:-}"
        case "$prop:$svc" in
            path:svca) echo "$SCRATCH/work/svc-a" ;;
            path:svcb) echo "$SCRATCH/work/svc-b" ;;
            path:svcc) echo "$SCRATCH/work/svc-c" ;;
            *)         echo "$default" ;;
        esac
    }
    export -f get_fleet_service_property

    # Bypass fleet config + git-writability checks; that plumbing is tested
    # elsewhere. We're testing the walker.
    _fleet_require_initialized() { return 0; }
    _fleet_scope_block() { :; }
    _fleet_preflight_git_writability() { return 0; }
    export -f _fleet_require_initialized _fleet_scope_block _fleet_preflight_git_writability

    : > "$SCRATCH/resume-calls.log"
    manifest_ship_repo_resume() {
        local repo
        repo=$(basename "$PWD")
        echo "$repo:$MANIFEST_CLI_RELEASE_GATE" >> "$SCRATCH/resume-calls.log"
        [[ "$repo" == "svc-b" ]] && return 1
        return 0
    }
    export -f manifest_ship_repo_resume

    # Member YAML gate resolution is the behavior under test; the per-repo
    # workflow is stubbed, so dropping the harness gate override stays hermetic.
    clear_release_gate_env_override

    run fleet_resume -y

    [ "$status" -ne 0 ]
    # svca was attempted and succeeded
    [[ "$output" == *"svca: resuming v1.2.3"* ]]
    [[ "$output" == *"✅ svca → v1.2.3"* ]]
    # svcb was attempted and failed
    [[ "$output" == *"svcb: resuming v1.2.3"* ]]
    [[ "$output" == *"❌ svcb → v1.2.3"* ]]
    # Each delegated resume observed that member's own YAML policy.
    grep -q '^svc-a:none$' "$SCRATCH/resume-calls.log"
    grep -q '^svc-b:remote-ci$' "$SCRATCH/resume-calls.log"
    # svcc must never have been attempted (fail-fast)
    [[ "$output" != *"svcc: resuming"* ]]
    ! grep -q '^svc-c:' "$SCRATCH/resume-calls.log"
    # Aborts with structured error
    [[ "$output" == *"Fleet resume aborted at svcb"* ]]
}

@test "CLI: ship fleet resume --help renders fleet-specific guidance" {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship fleet resume --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest ship fleet resume"* ]]
    [[ "$output" == *"sequential and fail-fast"* ]]
}
