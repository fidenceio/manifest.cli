#!/usr/bin/env bats

# Fleet-root coordination repo: local git root + allowlist .gitignore.
# Covers create_fleet_gitignore() (the allowlist generator + no-clobber policy)
# and the init-fleet Phase 2 apply/preview wiring.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-discovery.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"

    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH-home"
    mkdir -p "$HOME"
    export HOME SCRATCH
    cd "$SCRATCH"
}

teardown() {
    rm -rf "$SCRATCH" "$SCRATCH-home"
}

run_manifest() {
    run bash -c '
        export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
        source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-execution-policy.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
        source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
        cd "$SCRATCH"
        manifest_init_fleet "$@"
    ' bash "$@"
}

@test "create_fleet_gitignore writes an allowlist on a fresh root" {
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = ".gitignore" ]
    [ -f "$SCRATCH/.gitignore" ]
    grep -q '^/\*$' "$SCRATCH/.gitignore"
    grep -q '^!/manifest.fleet.config.yaml$' "$SCRATCH/.gitignore"
    grep -q '^!/manifest.fleet.tsv$' "$SCRATCH/.gitignore"
    grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
    # host-local config is deliberately NOT tracked
    refute grep -q 'manifest.config.local.yaml' "$SCRATCH/.gitignore"
}

@test "create_fleet_gitignore re-includes the CONFIGURED version file, not the literal default (TRACKER §77(c))" {
    # The allowlist used to be stated three times — the .gitignore writer, the
    # stager, the staged-set verifier — and the .gitignore's copy hard-coded
    # /FLEET_VERSION while the stager force-added whatever fleet.version_file
    # named. All three now render one list; this is the case where they used to
    # disagree.
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    cat > "$SCRATCH/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "custom"
  versioning: "date"
  version_file: "FLEET.stamp"
YAML
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    grep -q '^!/FLEET.stamp$' "$SCRATCH/.gitignore"
    refute grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
    # The stager reads the same list, so it names the same file.
    run _fleet_coordination_files "$SCRATCH"
    [[ "$output" == *"FLEET.stamp"* ]]
    refute grep -qx 'FLEET_VERSION' <<<"$output"
    # Positive control for the refutations: without the key, the default is back.
    rm -f "$SCRATCH/.gitignore" "$SCRATCH/manifest.fleet.config.yaml"
    run create_fleet_gitignore "$SCRATCH"
    grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
}

@test "a version_file that is not a plain name falls back to the default rather than widening the allowlist" {
    # `!/*` would un-ignore every root entry, member directories included, for
    # the user's own `git add .`; a `/` could never be re-included past `/*`.
    # Both are refused at the one reader, so the .gitignore, the stager and the
    # loader all see the default name.
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    local bad
    for bad in '*' 'sub/FLEET_VERSION' 'a b'; do
        rm -f "$SCRATCH/.gitignore"
        printf 'fleet:\n  name: "x"\n  versioning: "date"\n  version_file: "%s"\n' "$bad" \
            > "$SCRATCH/manifest.fleet.config.yaml"
        # stdout only: the fallback is announced on stderr, and that warning is
        # part of the contract (a silently-substituted name reads as a bug).
        [ "$(_fleet_root_version_name "$SCRATCH" 2>/dev/null)" = "FLEET_VERSION" ]
        run _fleet_root_version_name "$SCRATCH"
        [[ "$output" == *"not a plain file name"* ]]
        run create_fleet_gitignore "$SCRATCH"
        [ "$status" -eq 0 ]
        refute grep -qF "!/$bad" "$SCRATCH/.gitignore"
        grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
    done
    # Positive control: a plain custom name is honoured verbatim, silently.
    rm -f "$SCRATCH/.gitignore"
    printf 'fleet:\n  name: "x"\n  versioning: "date"\n  version_file: "FLEET.stamp"\n' \
        > "$SCRATCH/manifest.fleet.config.yaml"
    run _fleet_root_version_name "$SCRATCH"
    [ "$output" = "FLEET.stamp" ]
}

@test "the three well-formed names that must still be refused: '.', '..' and '.git'" {
    # These PASS the [A-Za-z0-9._-] shape check — the check was written against
    # the two shapes its own comment names (a path, a glob) and a dot-name is
    # neither. `.git` is the one that bites: _fleet_root_write_version_file does
    # `mv -f "$tmp" "$root/.git"`, and where .git is a GITFILE (linked worktree
    # or submodule) rather than a directory, mv -f overwrites it and detaches
    # the root from its repository.
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    local bad
    for bad in '.' '..' '.git'; do
        printf 'fleet:\n  name: "x"\n  versioning: "date"\n  version_file: "%s"\n' "$bad" \
            > "$SCRATCH/manifest.fleet.config.yaml"
        [ "$(_fleet_root_version_name "$SCRATCH" 2>/dev/null)" = "FLEET_VERSION" ]
        run _fleet_root_version_name "$SCRATCH"
        # Announced, and NOT as a shape problem — these are well-formed names,
        # so the old "not a plain file name" wording would have been misleading.
        [[ "$output" == *"directory reference"* || "$output" == *"overwrite the repository's own .git"* ]]
    done
}

@test "POSITIVE CONTROL: a gitfile .git is exactly the shape mv -f would clobber" {
    # Without this, the test above asserts a refusal against a hazard nobody
    # has shown to exist. A linked worktree's .git is a FILE, and `mv -f` over a
    # file succeeds silently — which is the whole reason the name is refused.
    printf 'gitdir: /somewhere/real\n' > "$SCRATCH/.git"
    [ -f "$SCRATCH/.git" ]
    printf 'clobbered\n' > "$SCRATCH/tmp-stamp"
    mv -f "$SCRATCH/tmp-stamp" "$SCRATCH/.git"
    [ "$(cat "$SCRATCH/.git")" = "clobbered" ]
    rm -f "$SCRATCH/.git"
}

# ---------------------------------------------------------------------------
# The CHANGE path (TRACKER §77(c), 2026-09-07).
#
# Everything above this block exercises CREATE. That is exactly why §77(c)
# shipped half-fixed: the decision function answered `current` on a header +
# `/*` check alone, so a root created before fleet.version_file changed kept
# re-including the old name forever, and no test could see it because no test
# ever ran the function against an ALREADY-CORRECT-LOOKING file whose config
# had moved on.
#
# Each branch is paired with the control that distinguishes it, because the
# whole difficulty here is telling a file that is ours to rewrite from one the
# operator has edited.
# ---------------------------------------------------------------------------

# An initialised root: allowlist written for the DEFAULT version file, then the
# config moves to a different name. This is the reported shape.
mk_initialised_root() {
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    rm -f "$SCRATCH/manifest.fleet.config.yaml"
    create_fleet_gitignore "$SCRATCH" >/dev/null
    cat > "$SCRATCH/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "custom"
  versioning: "date"
  version_file: "FLEET.stamp"
YAML
}

@test "an existing root whose version_file changed is STALE, not current (§77(c))" {
    mk_initialised_root
    # Pre-state: the old name is what is re-included.
    grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
    run _fleet_gitignore_decision "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = "stale" ]
}

@test "CONTROL: an existing root whose version_file did NOT change is current" {
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    rm -f "$SCRATCH/manifest.fleet.config.yaml"
    create_fleet_gitignore "$SCRATCH" >/dev/null
    run _fleet_gitignore_decision "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = "current" ]
}

@test "create_fleet_gitignore CONVERGES a stale root, announces it, and names the file it replaced" {
    mk_initialised_root
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *".gitignore:stale-updated"* ]]
    # The announcement is the point: a silent rewrite of a tracked file is the
    # class §73 was filed for.
    [[ "$output" == *"FLEET_VERSION"* ]]
    grep -q '^!/FLEET.stamp$' "$SCRATCH/.gitignore"
    refute grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
    # Converged means converged: a second run is a clean no-op.
    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "current" ]
}

@test "the converged allowlist makes the new version file visible to git, without widening" {
    mk_initialised_root
    create_fleet_gitignore "$SCRATCH" >/dev/null
    git -C "$SCRATCH" init -q
    echo "2026.09.07" > "$SCRATCH/FLEET.stamp"
    mkdir -p "$SCRATCH/member"; echo x > "$SCRATCH/member/code.txt"
    # The symptom, gone: check-ignore exits 1 for a re-included file.
    run git -C "$SCRATCH" check-ignore -q FLEET.stamp
    [ "$status" -eq 1 ]
    # The control that the repair did not widen the allowlist.
    run git -C "$SCRATCH" check-ignore -q member/code.txt
    [ "$status" -eq 0 ]
}

@test "a stale root the OPERATOR has edited is preserved-stale: announced, never written" {
    mk_initialised_root
    printf '!/RUNBOOK.md\n' >> "$SCRATCH/.gitignore"
    local before; before="$(cat "$SCRATCH/.gitignore")"

    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "preserved-stale" ]

    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *".gitignore:preserved-stale"* ]]
    # Names the exact repair.
    [[ "$output" == *"!/FLEET.stamp"* ]]
    # Byte-for-byte untouched — the operator's line is why this file is theirs.
    [ "$(cat "$SCRATCH/.gitignore")" = "$before" ]
    grep -q '^!/RUNBOOK.md$' "$SCRATCH/.gitignore"
}

@test "POSITIVE CONTROL: without the count guard an operator line would be silently dropped" {
    # Proves the `<= 1 variable re-include` clause is load-bearing rather than
    # defensive padding. The operator-edited file normalizes IDENTICALLY to the
    # canonical text (both lose all non-fixed re-includes), so normalization
    # alone would classify it `stale` and the rewrite would drop !/RUNBOOK.md.
    mk_initialised_root
    printf '!/RUNBOOK.md\n' >> "$SCRATCH/.gitignore"

    run _fleet_gitignore_variable_include_count "$SCRATCH/.gitignore"
    [ "$output" -eq 2 ]

    local canonical normalized_file normalized_canonical
    canonical="$(_fleet_render_allowlist_gitignore "$SCRATCH")"
    normalized_file="$(_fleet_gitignore_normalize < "$SCRATCH/.gitignore")"
    normalized_canonical="$(printf '%s\n' "$canonical" | _fleet_gitignore_normalize)"
    # The normalized texts MATCH, which is precisely why the count is needed.
    [ "$normalized_file" = "$normalized_canonical" ]
}

@test "create_fleet_gitignore preserves a populated .gitignore (no clobber)" {
    printf 'node_modules/\n*.log\n' > "$SCRATCH/.gitignore"
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = ".gitignore:preserved" ]
    grep -q '^node_modules/$' "$SCRATCH/.gitignore"
    refute grep -q '^/\*$' "$SCRATCH/.gitignore"
    # Nothing is written beside a curated .gitignore.
    [ ! -e "$SCRATCH/.gitignore.manifest" ]
}

@test "allowlist tracks only coordination files at the git level" {
    create_fleet_gitignore "$SCRATCH" >/dev/null
    git -C "$SCRATCH" init -q
    mkdir -p "$SCRATCH/apps/member" "$SCRATCH/secure"
    echo x > "$SCRATCH/apps/member/code.cs"
    echo s > "$SCRATCH/secure/appsettings.production.json"
    echo c > "$SCRATCH/manifest.fleet.config.yaml"
    echo t > "$SCRATCH/manifest.fleet.tsv"
    echo l > "$SCRATCH/manifest.config.local.yaml"
    git -C "$SCRATCH" add -A
    run git -C "$SCRATCH" ls-files
    [[ "$output" == *".gitignore"* ]]
    [[ "$output" == *"manifest.fleet.config.yaml"* ]]
    [[ "$output" == *"manifest.fleet.tsv"* ]]
    [[ "$output" != *"secure/"* ]]
    [[ "$output" != *"apps/member"* ]]
    [[ "$output" != *"manifest.config.local.yaml"* ]]
}

@test "init fleet phase 2 git-inits the fleet root (local-only) + writes the allowlist" {
    mkdir -p "$SCRATCH/apps/web" "$SCRATCH/services/api"
    run_manifest -y            # Phase 1: generate TSV
    [ "$status" -eq 0 ]
    # Mark the TSV as edited so Phase 2 applies (no DEFAULT-SELECT-HASH => not stale).
    grep -v 'DEFAULT-SELECT-HASH' "$SCRATCH/manifest.fleet.tsv" > "$SCRATCH/tsv.tmp"
    mv "$SCRATCH/tsv.tmp" "$SCRATCH/manifest.fleet.tsv"
    run_manifest -y            # Phase 2: apply
    [ "$status" -eq 0 ]
    [ -d "$SCRATCH/.git" ]
    run git -C "$SCRATCH" remote
    [ -z "$output" ]           # local-only: no remote
    [ -f "$SCRATCH/.gitignore" ]
    grep -q '^/\*$' "$SCRATCH/.gitignore"
    run git -C "$SCRATCH" check-ignore apps/web
    [ "$status" -eq 0 ]        # member dir ignored by the allowlist
}

@test "init fleet phase 2 dry-run previews fleet-root git + allowlist, writes nothing" {
    mkdir -p "$SCRATCH/apps/web"
    run_manifest -y            # Phase 1
    [ "$status" -eq 0 ]
    run_manifest --dry-run     # Phase 2 preview
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet-root git repo"* ]]
    [[ "$output" == *".gitignore"* ]]
    [ ! -d "$SCRATCH/.git" ]   # preview wrote nothing
}

@test "create_fleet_gitignore is idempotent — re-run is a clean no-op" {
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = ".gitignore" ]
    run create_fleet_gitignore "$SCRATCH"   # allowlist already present
    [ "$status" -eq 0 ]
    [ -z "$output" ]                        # clean no-op
    [ ! -e "$SCRATCH/.gitignore.manifest" ] # sidecars no longer exist
}

@test "_fleet_dir_is_own_git_repo: own repo yes, nested-in-parent no" {
    git init -q "$SCRATCH"
    mkdir -p "$SCRATCH/child"
    run _fleet_dir_is_own_git_repo "$SCRATCH"
    [ "$status" -eq 0 ]                     # SCRATCH is its own repo
    run _fleet_dir_is_own_git_repo "$SCRATCH/child"
    [ "$status" -ne 0 ]                     # child is only nested in the parent
    run git -C "$SCRATCH/child" rev-parse --is-inside-work-tree
    [ "$output" = "true" ]                  # ...which the old --is-inside-work-tree check wrongly passed
}
