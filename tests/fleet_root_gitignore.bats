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

@test "the .git refusal folds case, because macOS resolves .GIT to .git" {
    # The refusal compared case-SENSITIVELY at first, and APFS is
    # case-insensitive by default — so `.GIT` passed the check and `mv -f`
    # clobbered the gitfile, with the directory entry still reading `.git`
    # because APFS is also case-preserving. A check that decides whether a path
    # is dangerous has to fold, or it is correct only on Linux.
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    local bad
    for bad in '.GIT' '.Git' '.gIt' '.GITMODULES'; do
        printf 'fleet:\n  name: "x"\n  versioning: "date"\n  version_file: "%s"\n' "$bad" \
            > "$SCRATCH/manifest.fleet.config.yaml"
        [ "$(_fleet_root_version_name "$SCRATCH" 2>/dev/null)" = "FLEET_VERSION" ]
    done
}

@test "a version_file colliding with a coordination file is refused (it would destroy it)" {
    # `mv -f "$tmp" "$root/$name"` on manifest.fleet.tsv overwrites the fleet's
    # structure-of-record; on manifest.fleet.config.yaml it erases the file that
    # named it. The collision also makes _fleet_coordination_files emit a
    # duplicate, which pinned the root at preserved-stale with a
    # self-contradicting warning.
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    local bad
    for bad in 'manifest.fleet.tsv' 'manifest.fleet.config.yaml' '.gitignore' \
               'CHANGELOG_FLEET.md' 'MANIFEST.FLEET.TSV'; do
        printf 'fleet:\n  name: "x"\n  versioning: "date"\n  version_file: "%s"\n' "$bad" \
            > "$SCRATCH/manifest.fleet.config.yaml"
        [ "$(_fleet_root_version_name "$SCRATCH" 2>/dev/null)" = "FLEET_VERSION" ]
        run _fleet_root_version_name "$SCRATCH"
        [[ "$output" == *"collides with the coordination file"* || "$output" == *"is git metadata"* ]]
    done
    # CONTROL: a name that merely RESEMBLES one is still honoured, so the check
    # is a collision test and not a substring ban.
    printf 'fleet:\n  name: "x"\n  versioning: "date"\n  version_file: "manifest.fleet.tsv.version"\n' \
        > "$SCRATCH/manifest.fleet.config.yaml"
    [ "$(_fleet_root_version_name "$SCRATCH" 2>/dev/null)" = "manifest.fleet.tsv.version" ]
}

@test "a version_file naming a fleet CONFIG LAYER is refused (it would rewrite every member's policy)" {
    # Missed by the first collision list, and worse than the coordination-file
    # cases it did cover: <root>/manifest.config.yaml is the FLEET-SHARED layer
    # every member inherits, so replacing it with a bare version string
    # silently changes resolved policy — release.gate included — across the
    # whole fleet. manifest.config.local.yaml is deliberately untracked, and
    # naming it would also pull a host-local file into the allowlist, which
    # test "create_fleet_gitignore writes an allowlist on a fresh root"
    # explicitly asserts never happens.
    unset MANIFEST_CLI_FLEET_CONFIG_FILE
    local bad
    for bad in 'manifest.config.yaml' 'manifest.config.local.yaml' 'MANIFEST.CONFIG.YAML'; do
        printf 'fleet:\n  name: "x"\n  versioning: "date"\n  version_file: "%s"\n' "$bad" \
            > "$SCRATCH/manifest.fleet.config.yaml"
        [ "$(_fleet_root_version_name "$SCRATCH" 2>/dev/null)" = "FLEET_VERSION" ]
        run _fleet_root_version_name "$SCRATCH"
        [[ "$output" == *"collides with the coordination file"* ]]
    done
}

@test "the two .gitignore warnings do not claim a re-include is missing when it is present" {
    # Both arms asserted "does not re-include '<name>'" without testing it.
    # preserved-stale fires for ANY managed-block edit, so an operator whose
    # version line was already correct was told to add a line that was already
    # there — following the advice appends a duplicate and the warning returns
    # on the next run, with no way to clear it by doing as instructed.
    mk_initialised_root
    create_fleet_gitignore "$SCRATCH" >/dev/null          # converge, so !/FLEET.stamp is present
    grep -q '^!/FLEET.stamp$' "$SCRATCH/.gitignore"
    printf '/secrets\n' >> "$SCRATCH/.gitignore"          # an ordinary rule, in the managed block

    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "preserved-stale" ]

    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    refute grep -q "does not re-include" <<<"$output"
    [[ "$output" == *"is present and correct"* ]]

    # CONTROL: when it genuinely IS missing, the actionable wording is back.
    grep -v '^!/FLEET.stamp$' "$SCRATCH/.gitignore" > "$SCRATCH/.gi.tmp"
    mv "$SCRATCH/.gi.tmp" "$SCRATCH/.gitignore"
    run create_fleet_gitignore "$SCRATCH"
    [[ "$output" == *"does not re-include 'FLEET.stamp'"* ]]
    [[ "$output" == *"!/FLEET.stamp"* ]]
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

@test "create_fleet_gitignore CONVERGES a stale root by ADDING the configured name" {
    mk_initialised_root
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *".gitignore:stale-updated"* ]]
    # The announcement is the point: a silent rewrite of a tracked file is the
    # class §73 was filed for. It names what was ADDED — never the carried
    # line, which the first cut announced as the outgoing version file even
    # when it was the operator's own.
    [[ "$output" == *"FLEET.stamp"* ]]
    [[ "$output" == *"kept every existing rule"* ]]
    grep -q '^!/FLEET.stamp$' "$SCRATCH/.gitignore"
    # Converged means converged: a second run is a clean no-op.
    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "current" ]
}

@test "convergence is ADDITIVE: an operator's only variable re-include survives (§77(c))" {
    # THE REGRESSION THIS REPLACES A COUNT GUARD WITH.
    #
    # The first cut classified a file as ours to rewrite when it normalized to
    # canonical AND carried at most one variable re-include line, on the theory
    # that the CLI only ever writes one. The theory says nothing about WHICH
    # name that one line holds. An operator who deletes the re-include for a
    # version file their scheme never creates and adds one of their own has a
    # count of exactly one — so the file classified as ours and the line was
    # dropped, with the warning naming it as the outgoing version file.
    #
    # Reproduced before the fix: count=1, decision=stale, !/RUNBOOK.md LOST.
    # Authorship of a re-include line is not recoverable from the file, so the
    # write is additive and the question no longer has to be answered.
    mk_initialised_root
    grep -v '^!/FLEET_VERSION$' "$SCRATCH/.gitignore" > "$SCRATCH/.gi.tmp"
    mv "$SCRATCH/.gi.tmp" "$SCRATCH/.gitignore"
    printf '!/RUNBOOK.md\n' >> "$SCRATCH/.gitignore"

    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "stale" ]

    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *".gitignore:stale-updated"* ]]
    # Both survive: the operator's line kept, the configured name added.
    grep -q '^!/RUNBOOK.md$' "$SCRATCH/.gitignore"
    grep -q '^!/FLEET.stamp$' "$SCRATCH/.gitignore"
    # And it settles — a carried line must not keep the root perpetually stale.
    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "current" ]
}

@test "convergence carries a superseded version name forward too, and does not duplicate it" {
    # The other kind of variable line: genuinely ours, now superseded. Kept for
    # the same reason — the file cannot prove which kind it is — and a stale
    # re-include for an absent file is inert in git.
    mk_initialised_root
    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    grep -q '^!/FLEET_VERSION$' "$SCRATCH/.gitignore"
    grep -q '^!/FLEET.stamp$' "$SCRATCH/.gitignore"
    # No name appears twice, however many times convergence runs.
    create_fleet_gitignore "$SCRATCH" >/dev/null
    [ "$(grep -c '^!/FLEET.stamp$' "$SCRATCH/.gitignore")" -eq 1 ]
    [ "$(grep -c '^!/FLEET_VERSION$' "$SCRATCH/.gitignore")" -eq 1 ]
    [ "$(grep -c '^!/.gitignore$' "$SCRATCH/.gitignore")" -eq 1 ]
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

@test "an operator re-include BESIDE the version line also survives convergence" {
    # The same additive property with the version line still present. Under the
    # original count guard this file was refused outright (count == 2), which
    # was safe but left the root diverged forever; it now converges and keeps
    # the operator's line, so safety no longer costs the fix.
    mk_initialised_root
    printf '!/RUNBOOK.md\n' >> "$SCRATCH/.gitignore"

    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "stale" ]

    run create_fleet_gitignore "$SCRATCH"
    [ "$status" -eq 0 ]
    grep -q '^!/RUNBOOK.md$' "$SCRATCH/.gitignore"
    grep -q '^!/FLEET.stamp$' "$SCRATCH/.gitignore"
    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "current" ]
}

@test "an EDITED managed block stays preserved-stale — only the re-include set may be regenerated" {
    # The line between the two stale answers. A carried re-include is safe to
    # regenerate because it is re-emitted; an edit anywhere else in the block
    # is not recoverable, so that file is never written.
    mk_initialised_root
    printf '\n# my own rule\n!secrets.env\n' >> "$SCRATCH/.gitignore"
    local before; before="$(cat "$SCRATCH/.gitignore")"

    run _fleet_gitignore_decision "$SCRATCH"
    [ "$output" = "preserved-stale" ]
    run create_fleet_gitignore "$SCRATCH"
    [[ "$output" == *".gitignore:preserved-stale"* ]]
    [ "$(cat "$SCRATCH/.gitignore")" = "$before" ]
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
