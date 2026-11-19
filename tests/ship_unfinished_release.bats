#!/usr/bin/env bats
# bats file_tags=smoke
#
# An unfinished release is finished by the ordinary ship — planned first,
# applied only with -y — and `resume` is gone.
#
# `manifest ship repo resume` was the one mutating route that applied without
# -y: its parser arm handed straight to the function that pushed, and the suite
# pinned that by calling the function bare and asserting the push. It is
# removed. A publishing ship now leaves an in-flight record under
# .git/manifest-ship/ from just before its tag until the release completes; the
# next `ship repo <type>` reads it, shows the unfinished release in its plan,
# and with -y finishes it without bumping.
#
# Every test drives the real entrypoint and reads the repositories afterwards.
# The stranded state is made the way it happens in the field: a real publish
# whose push fails (a pre-push hook, installed outside the tree, that refuses
# while a flag file exists).

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/repo" "$SCRATCH/hooks"
    export HOME
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
    export MANIFEST_CLI_RELEASE_GATE=none
    export MANIFEST_CLI_GIT_RETRIES=1
    # The canonical-CLI follow-up patch and the Homebrew publish belong to
    # Manifest's own repo; a scratch repo is not it.
    export MANIFEST_CLI_SHIP_FOLLOWUP_PATCH=false

    REPO="$SCRATCH/repo"
    ORIGIN="$SCRATCH/origin.git"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name T
    echo "1.2.3" > "$REPO/VERSION"
    echo "seed" > "$REPO/notes.txt"
    git -C "$REPO" add VERSION notes.txt
    git -C "$REPO" commit -qm "init 1.2.3"
    git init -q --bare "$ORIGIN"
    git -C "$REPO" remote add origin "$ORIGIN"
    git -C "$REPO" push -q -u origin main

    # A pre-push hook that refuses while the flag exists. Outside the tree, so
    # it is never a pending file the ship would sweep.
    printf '#!/bin/sh\nif [ -f "%s" ]; then echo "PUSH-FIXTURE: refusing this push" >&2; exit 1; fi\nexit 0\n' \
        "$SCRATCH/refuse-push" > "$SCRATCH/hooks/pre-push"
    chmod +x "$SCRATCH/hooks/pre-push"
    git -C "$REPO" config core.hooksPath "$SCRATCH/hooks"

    RECORD="$REPO/.git/manifest-ship/in-flight"
}

teardown() {
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT MANIFEST_CLI_TIME_RETRIES
    unset MANIFEST_CLI_RELEASE_GATE MANIFEST_CLI_GIT_RETRIES MANIFEST_CLI_SHIP_FOLLOWUP_PATCH
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$REPO"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# Strand a release the real way: publish 1.2.4 with the push refused.
strand_release() {
    : > "$SCRATCH/refuse-push"
    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    # Positive controls for the fixture itself, so no later assertion can pass
    # on a release that was never stranded.
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.4" ]
    git -C "$REPO" rev-parse -q --verify "refs/tags/v1.2.4^{commit}" >/dev/null
    origin_lacks_tag v1.2.4
    STRAND_OUTPUT="$output"
    rm -f "$SCRATCH/refuse-push"
}

origin_has_tag()   { git --git-dir="$ORIGIN" rev-parse -q --verify "refs/tags/$1^{commit}" >/dev/null 2>&1; }
origin_lacks_tag() { ! git --git-dir="$ORIGIN" rev-parse -q --verify "refs/tags/$1^{commit}" >/dev/null 2>&1; }
local_lacks_tag()  { ! git -C "$REPO" rev-parse -q --verify "refs/tags/$1^{commit}" >/dev/null 2>&1; }
commit_count()     { git -C "$REPO" rev-list --count HEAD; }

# --- the record --------------------------------------------------------------

@test "a publish that completes leaves no in-flight record" {
    run_manifest ship repo patch -y
    [ "$status" -eq 0 ]
    origin_has_tag v1.2.4          # control: this really was a publishing ship
    [ ! -e "$RECORD" ]
}

@test "a publish whose push fails leaves the record, naming the version, the tag's commit and the step" {
    strand_release

    [ -f "$RECORD" ]
    grep -q '^version=1\.2\.4$' "$RECORD"
    grep -q '^tag=v1\.2\.4$' "$RECORD"
    grep -q "^commit=$(git -C "$REPO" rev-parse 'v1.2.4^{commit}')\$" "$RECORD"
    grep -q '^stopped_at=push_changes$' "$RECORD"

    # The failure report sends the operator to the plan, not to a removed verb.
    [[ "$STRAND_OUTPUT" == *"Finish:      manifest ship repo patch"* ]]
    [[ "$STRAND_OUTPUT" != *"ship repo resume"* ]]
}

@test "a --local ship never writes the record (it makes no tag)" {
    run_manifest ship repo patch --local -y
    [ "$status" -eq 0 ]
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.4" ]   # control: it applied
    [ ! -e "$RECORD" ]
}

# --- the plan ----------------------------------------------------------------

@test "the next plan shows the unfinished release and changes nothing" {
    strand_release
    local head_before count_before
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    count_before="$(commit_count)"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unfinished release"* ]]
    [[ "$output" == *"v1.2.4 was tagged here (v1.2.4) by a ship that did not complete."* ]]
    [[ "$output" == *"Stopped at:  push_changes"* ]]
    [[ "$output" == *"This run finishes v1.2.4. It does NOT bump the version, commit, or create a tag."* ]]
    # Not the ordinary plan: no transition to the next version is offered.
    [[ "$output" != *"1.2.5"* ]]

    # Nothing moved, here or on origin.
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
    [ "$(commit_count)" = "$count_before" ]
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.4" ]
    origin_lacks_tag v1.2.4
    [ -f "$RECORD" ]
}

@test "the plan is the same whatever release type is named: a finish applies no increment" {
    strand_release
    run_manifest ship repo minor
    [ "$status" -eq 0 ]
    [[ "$output" == *"This run finishes v1.2.4."* ]]
    [[ "$output" != *"1.3.0"* ]]
}

@test "a run that ended without a failure report is still unfinished, and the plan says the step is not recorded" {
    strand_release
    # What a killed run leaves: the record, with no stopped_at line.
    grep -v '^stopped_at=' "$RECORD" > "$RECORD.tmp" && mv "$RECORD.tmp" "$RECORD"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unfinished release"* ]]
    [[ "$output" == *"Stopped at:  not recorded (the run ended without a failure report)"* ]]
}

# --- the apply ---------------------------------------------------------------

@test "-y finishes the release without bumping, and clears the record" {
    strand_release
    local tag_commit count_before
    tag_commit="$(git -C "$REPO" rev-parse 'v1.2.4^{commit}')"
    count_before="$(commit_count)"

    run_manifest ship repo patch -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship: finishing v1.2.4 (v1.2.4)"* ]]
    [[ "$output" == *"Release v1.2.4 finished. Nothing was bumped."* ]]

    # Published: origin has the tag at the same commit, and the branch.
    [ "$(git --git-dir="$ORIGIN" rev-parse 'v1.2.4^{commit}')" = "$tag_commit" ]
    [ "$(git --git-dir="$ORIGIN" rev-parse refs/heads/main)" = "$(git -C "$REPO" rev-parse HEAD)" ]

    # Not bumped: same version, same commits, no next tag anywhere.
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.4" ]
    [ "$(commit_count)" = "$count_before" ]
    local_lacks_tag v1.2.5
    origin_lacks_tag v1.2.5

    [ ! -e "$RECORD" ]
}

@test "after the finish, the same command is an ordinary ship again" {
    strand_release
    run_manifest ship repo patch -y
    [ "$status" -eq 0 ]

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unfinished release"* ]]
    [[ "$output" == *"Nothing to release: HEAD is at v1.2.4 and the working tree is clean."* ]]
    # Published, so the unpushed-tag note has nothing to say.
    [[ "$output" != *"is not on origin/main as last fetched"* ]]
}

@test "a stranded release with NO record is not offered as unfinished, and the run says what to push" {
    # What a Manifest older than the record leaves behind: the tag, here only.
    strand_release
    rm -f "$RECORD"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unfinished release"* ]]
    [[ "$output" == *"Nothing to release: HEAD is at v1.2.4 and the working tree is clean."* ]]
    [[ "$output" == *"Note: v1.2.4 is not on origin/main as last fetched. If that release was never pushed, push it:"* ]]
    [[ "$output" == *"git push origin main v1.2.4"* ]]
    # A note, not an action.
    origin_lacks_tag v1.2.4
}

@test "the no-record note names the remote and branch from the branch's config, not by splitting at a slash" {
    strand_release
    rm -f "$RECORD"
    # A second remote whose NAME contains a slash, tracked by the branch.
    git -C "$REPO" remote add team/hub "$ORIGIN"
    git -C "$REPO" fetch -q team/hub
    git -C "$REPO" branch -q --set-upstream-to=team/hub/main main

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Note: v1.2.4 is not on team/hub/main as last fetched."* ]]
    [[ "$output" == *"git push team/hub main v1.2.4"* ]]
    # The command a split at the first slash produced.
    [[ "$output" != *"git push team hub/main"* ]]
}

@test "commits made after the tag are named in the finish plan, because the push publishes them" {
    strand_release
    echo "later" >> "$REPO/notes.txt"
    git -C "$REPO" commit -qam "work done after the tag"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOTE: 1 commit(s) made after v1.2.4 are on this branch. Pushing the branch"* ]]
    [[ "$output" == *"work done after the tag"* ]]
    [[ "$output" == *"They are not part of v1.2.4 and are not released by this run"* ]]

    run_manifest ship repo patch -y
    [ "$status" -eq 0 ]
    # What the plan said: the branch went, with the later commit, and no bump.
    [ "$(git --git-dir="$ORIGIN" rev-parse refs/heads/main)" = "$(git -C "$REPO" rev-parse HEAD)" ]
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.4" ]
    local_lacks_tag v1.2.5
}

@test "CONTROL: with nothing after the tag, the finish plan carries no such note" {
    strand_release
    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Finish plan"* ]]
    [[ "$output" != *"made after v1.2.4 are on this branch"* ]]
}

@test "a ship that fails at the tag leaves no record, and its report offers no Finish line" {
    # Tag creation fails: every tag is to be signed, and the signer refuses.
    git -C "$REPO" config tag.gpgSign true
    git -C "$REPO" config gpg.program false

    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    # Controls: the release commit was made and the tag was not.
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.4" ]
    local_lacks_tag v1.2.4

    [ ! -e "$RECORD" ]
    [[ "$output" == *"failed step:        create_tag"* ]]
    [[ "$output" == *"The tag v1.2.4 was not created"* ]]
    [[ "$output" != *"Finish:"* ]]
}

@test "a finish that fails again keeps the record, so the release is still planned next time" {
    strand_release
    : > "$SCRATCH/refuse-push"
    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    [ -f "$RECORD" ]
    grep -q '^stopped_at=finish_push$' "$RECORD"
    origin_lacks_tag v1.2.4

    rm -f "$SCRATCH/refuse-push"
    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stopped at:  finish_push"* ]]
}

@test "unrelated working-tree changes block the finish: the plan says so and -y refuses" {
    strand_release
    echo "more" >> "$REPO/notes.txt"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCKED: this release cannot be finished from the current state (dirty-tree"* ]]
    [[ "$output" == *"This plan is BLOCKED: fix the cause above, then run the plan again."* ]]
    [[ "$output" != *"Re-run with -y to apply this plan"* ]]

    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot finish v1.2.4 with unrelated working-tree changes"* ]]
    origin_lacks_tag v1.2.4
    [ -f "$RECORD" ]
}

# --- the two ways out ----------------------------------------------------------

@test "--force-bump leaves the unfinished release and cuts the next one" {
    strand_release
    run_manifest ship repo patch --force-bump -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"force-bump: leaving v1.2.4 unfinished"* ]]
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.5" ]
    origin_has_tag v1.2.5
    # "Leaving it" means its tag was not published by the way.
    origin_lacks_tag v1.2.4
    # The superseded record is gone with the completed publish.
    [ ! -e "$RECORD" ]
}

@test "--local cannot finish a release: it refuses in plan and apply, and writes nothing" {
    strand_release
    local head_before
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run_manifest ship repo patch --local
    [ "$status" -ne 0 ]
    [[ "$output" == *"--local cannot finish it"* ]]

    run_manifest ship repo patch --local -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"--local cannot finish it"* ]]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
    [ "$(tr -d '[:space:]' < "$REPO/VERSION")" = "1.2.4" ]
}

@test "a VERSION edited in the working tree does not hide the unfinished release: it blocks the finish" {
    strand_release
    echo "9.9.9" > "$REPO/VERSION"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"v1.2.4 was tagged here (v1.2.4) by a ship that did not complete."* ]]
    [[ "$output" == *"BLOCKED: this release cannot be finished from the current state (dirty-tree"* ]]
    # Not an ordinary plan that bumps past the stranded release.
    [[ "$output" != *"9.9.10"* ]]
}

# --- the post-push release gate ------------------------------------------------

# A repo whose origin is a GitHub URL for the gate's purposes and a local bare
# repository for the push, and a `gh` that records every call and answers the
# gate's questions from $SCRATCH/ci: a file named for a commit holds that
# commit's CI result (`green`, or anything else for red). No file means "no run
# found", which is what every commit gets until a test says otherwise.
gate_fixture() {
    mkdir -p "$SCRATCH/bin" "$SCRATCH/ci"
    GH_LOG="$SCRATCH/gh.log"
    : > "$GH_LOG"
    cat > "$SCRATCH/bin/gh" <<STUB
#!/bin/sh
echo "gh \$*" >> "$GH_LOG"
case "\$1 \$2" in
  "auth status") exit 0;;
  "run list") [ -n "\$4" ] && [ -f "$SCRATCH/ci/\$4" ] && echo "\$4"; exit 0;;
  "run watch") [ "\$(cat "$SCRATCH/ci/\$3" 2>/dev/null)" = green ] && exit 0; exit 1;;
  "release view") exit 1;;
  "release create") exit 0;;
esac
exit 1
STUB
    chmod +x "$SCRATCH/bin/gh"
    export PATH="$SCRATCH/bin:$PATH"
    git -C "$REPO" remote set-url origin "https://github.com/acme/widget.git"
    git -C "$REPO" remote set-url --push origin "$ORIGIN"
    export MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS=4
}

@test "a release stopped by the post-push gate is NOT published by running the command again" {
    gate_fixture
    export MANIFEST_CLI_RELEASE_GATE=remote-ci

    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    # Controls: the push landed, the gate is what stopped it, nothing was published.
    origin_has_tag v1.2.4
    [[ "$output" == *"failed step:        release_gate_post_push"* ]]
    [ "$(grep -c '^gh release create' "$GH_LOG")" -eq 0 ]
    [ -f "$RECORD" ]
    # The tag is public, so the first report must not advise undoing it either.
    [[ "$output" == *"Release artifacts are already pushed."* ]]
    [[ "$output" != *"git tag -d"* ]]
    [[ "$output" != *"reset --hard"* ]]

    : > "$GH_LOG"
    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Ship: finishing v1.2.4 (v1.2.4)"* ]]
    # The gate ran again, failed again, and the release was not created.
    [ "$(grep -c '^gh run list' "$GH_LOG")" -ge 1 ]
    [ "$(grep -c '^gh release create' "$GH_LOG")" -eq 0 ]
    [[ "$output" == *"failed step:        finish_release_gate"* ]]
    [[ "$output" == *"Do NOT delete the tag or reset"* ]]
    [[ "$output" != *"git tag -d"* ]]
    [[ "$output" != *"reset --hard"* ]]
    [ -f "$RECORD" ]
    grep -q '^stopped_at=finish_release_gate$' "$RECORD"

    unset MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS
}

@test "the finish gate reads the TAGGED commit's CI: a green fix committed on top does not publish a red release" {
    gate_fixture
    export MANIFEST_CLI_RELEASE_GATE=remote-ci
    export MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS=1

    # Strand v1.2.4 at the post-push gate (no CI run exists for it yet).
    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    [ -f "$RECORD" ]
    local tag_sha fix_sha
    tag_sha="$(git -C "$REPO" rev-parse 'v1.2.4^{commit}')"

    # CI for the released commit comes back RED. The ordinary response: commit
    # a fix on top. That commit's own run is GREEN.
    echo red > "$SCRATCH/ci/$tag_sha"
    echo "fix" > "$REPO/fix.txt"
    git -C "$REPO" add fix.txt
    git -C "$REPO" commit -qm "fix the red build"
    fix_sha="$(git -C "$REPO" rev-parse HEAD)"
    [ "$fix_sha" != "$tag_sha" ]
    echo green > "$SCRATCH/ci/$fix_sha"

    : > "$GH_LOG"
    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Ship: finishing v1.2.4 (v1.2.4)"* ]]
    # The gate asked about the tag's commit and never about the fix.
    grep -q "^gh run list --commit $tag_sha " "$GH_LOG"
    ! grep -q "^gh run list --commit $fix_sha " "$GH_LOG"
    [[ "$output" == *"remote CI did not pass for the released commit ${tag_sha:0:7}"* ]]
    [[ "$output" == *"failed step:        finish_release_gate"* ]]
    [ "$(grep -c '^gh release create' "$GH_LOG")" -eq 0 ]
    [ -f "$RECORD" ]

    # CONTROL: the same state with the released commit's CI green does publish,
    # so the refusal above is the gate's verdict and not a broken fixture.
    echo green > "$SCRATCH/ci/$tag_sha"
    : > "$GH_LOG"
    run_manifest ship repo patch -y
    [ "$status" -eq 0 ]
    grep -q "^gh run list --commit $tag_sha " "$GH_LOG"
    [ "$(grep -c '^gh release create v1.2.4' "$GH_LOG")" -eq 1 ]
    [[ "$output" == *"Release v1.2.4 finished. Nothing was bumped."* ]]
    [ ! -e "$RECORD" ]

    unset MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS
}

@test "CONTROL: with no post-push gate configured, the same finish does publish the GitHub Release" {
    gate_fixture
    export MANIFEST_CLI_RELEASE_GATE=remote-ci
    run_manifest ship repo patch -y
    [ "$status" -ne 0 ]
    [ -f "$RECORD" ]

    : > "$GH_LOG"
    export MANIFEST_CLI_RELEASE_GATE=none
    run_manifest ship repo patch -y
    [ "$status" -eq 0 ]
    [ "$(grep -c '^gh release create v1.2.4' "$GH_LOG")" -eq 1 ]
    [[ "$output" == *"Release v1.2.4 finished. Nothing was bumped."* ]]
    [ ! -e "$RECORD" ]

    unset MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS
}

# --- records that do not describe this tree ---------------------------------

@test "a record for another version is ignored" {
    strand_release
    # Finish it properly, then plant a record for a version the tree is not at.
    run_manifest ship repo patch -y
    [ "$status" -eq 0 ]
    mkdir -p "$REPO/.git/manifest-ship"
    printf 'version=9.9.9\ntag=v9.9.9\ncommit=%s\n' "$(git -C "$REPO" rev-parse HEAD)" > "$RECORD"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unfinished release"* ]]
}

@test "a record whose commit is not the one the tag points at is ignored" {
    strand_release
    sed 's/^commit=.*/commit=0000000000000000000000000000000000000000/' "$RECORD" > "$RECORD.tmp" && mv "$RECORD.tmp" "$RECORD"

    run_manifest ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unfinished release"* ]]
}

# --- the removed word ----------------------------------------------------------

@test "ship repo resume is refused by name, with or without -y, and pushes nothing" {
    strand_release

    run_manifest ship repo resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"'manifest ship repo resume' was removed"* ]]
    [[ "$output" == *"manifest ship repo patch -y     (finish it)"* ]]
    # It does not promise a plan that a release with no record will never
    # get: it says what to do when the plan does not show it, and states the
    # fact (no record) without asserting which cause produced it.
    [[ "$output" == *"If the plan does not show it, Manifest holds no record of an unfinished release there (one started by an older Manifest leaves none). Push it by hand:"* ]]
    [[ "$output" == *"git push origin <branch> <tag>"* ]]
    # THE regression this file exists for: a bare `ship repo resume` used to
    # push the branch and the tag with no -y. The push hook is not refusing
    # here, so a push would have landed.
    origin_lacks_tag v1.2.4

    run_manifest ship repo resume -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"'manifest ship repo resume' was removed"* ]]
    origin_lacks_tag v1.2.4
    [ -f "$RECORD" ]
}

@test "ship fleet resume is refused by name" {
    run_manifest ship fleet resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"'manifest ship fleet resume' was removed"* ]]
    # At fleet scope the by-hand push is per member.
    [[ "$output" == *"Push it by hand, in each member it applies to:"* ]]

    run_manifest ship fleet resume -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"'manifest ship fleet resume' was removed"* ]]
}

@test "help no longer offers resume, and says how an unfinished release is finished" {
    run_manifest ship repo --help
    [ "$status" -eq 0 ]
    [[ "$output" != *"resume"* ]]
    [[ "$output" == *"Unfinished releases"* ]]

    run_manifest ship fleet --help
    [ "$status" -eq 0 ]
    [[ "$output" != *"resume"* ]]
    [[ "$output" == *"'would finish'"* ]]
}
