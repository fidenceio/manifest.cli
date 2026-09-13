#!/usr/bin/env bats

# manifest_git_commit — the one executor behind every commit Manifest writes (§82).
# Focus: a hook's refusal reaches the operator, the cause is classified from
# evidence rather than guessed, and sign-off follows git's own format.signOff.

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git-commit.sh"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH-home"; mkdir -p "$HOME"
    export HOME SCRATCH
    cd "$SCRATCH"
}

teardown() {
    cd /tmp || true
    rm -rf "$SCRATCH" "$SCRATCH-home"
}

# A repo with a repo-local identity and one file staged. Prints its path.
mk_repo() {
    local r="$SCRATCH/$1"
    git init -q -b main "$r"
    git -C "$r" config user.email test@example.com
    git -C "$r" config user.name "Test"
    printf 'a\n' > "$r/a.txt"
    git -C "$r" add a.txt
    printf '%s' "$r"
}

# Install a pre-commit hook through core.hooksPath that prints LINE to STDOUT
# and exits RC. $1 repo, $2 rc, $3 line.
mk_hook() {
    local r="$1" rc="$2" line="$3" hooks="$1/.hooks"
    mkdir -p "$hooks"
    cat > "$hooks/pre-commit" <<EOF
#!/bin/sh
echo "$line"
exit $rc
EOF
    chmod +x "$hooks/pre-commit"
    git -C "$r" config core.hooksPath "$hooks"
}

@test "executor: commits the staged set with the subject, returns 0; nothing staged returns 3" {
    local r; r="$(mk_repo plain)"
    run manifest_git_commit "$r" "chore(test): first"
    [ "$status" -eq 0 ]
    [ "$(git -C "$r" log -1 --format=%s)" = "chore(test): first" ]
    # Second call: nothing staged, and git's "nothing to commit" is never printed.
    run manifest_git_commit "$r" "chore(test): second"
    [ "$status" -eq 3 ]
    [ -z "$output" ]
    [ "$(git -C "$r" rev-list --count HEAD)" -eq 1 ]
}

@test "executor: a body becomes the second paragraph" {
    local r; r="$(mk_repo body)"
    manifest_git_commit "$r" "chore(test): with body" "Why this happened."
    [ "$(git -C "$r" log -1 --format=%b)" = "Why this happened." ]
}

@test "executor: a hook's STDOUT reaches the operator on failure, and the cause names the hook, not identity" {
    local r; r="$(mk_repo hooked)"
    mk_hook "$r" 1 "HOOK-FIXTURE: refusing this commit"
    run manifest_git_commit "$r" "chore(test): refused"
    [ "$status" -eq 5 ]
    grep -q "HOOK-FIXTURE: refusing this commit" <<<"$output"
    grep -q "hook active at" <<<"$output"
    grep -q "$r/.hooks" <<<"$output"
    refute grep -q "user.name" <<<"$output"
    # Nothing was committed.
    refute git -C "$r" rev-parse -q --verify HEAD
}

@test "CONTROL: a passing hook that prints to STDOUT does not disturb the result" {
    local r; r="$(mk_repo hookok)"
    mk_hook "$r" 0 "HOOK-FIXTURE: ok"
    run manifest_git_commit "$r" "chore(test): allowed"
    [ "$status" -eq 0 ]
    [ "$(git -C "$r" log -1 --format=%s)" = "chore(test): allowed" ]
    # What git and the hook printed is still shown — on stdout, as git would.
    grep -q "HOOK-FIXTURE: ok" <<<"$output"
}

@test "executor: a missing identity is named as identity, with the git config lines, not as a hook" {
    local r; r="$(mk_repo noident)"
    # Make git refuse to invent one on EVERY platform: macOS auto-detects an
    # identity from the account and hostname unless useConfigOnly is set
    # (measured 2026-09-08), Linux without a domain name fails outright.
    git -C "$r" config --unset user.email
    git -C "$r" config --unset user.name
    git -C "$r" config user.useConfigOnly true
    local empty_global="$SCRATCH/empty-gitconfig"; : > "$empty_global"
    # `env -u` flags must precede the assignments (BSD env parses options first).
    run env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
        GIT_CONFIG_GLOBAL="$empty_global" GIT_CONFIG_NOSYSTEM=1 \
        bash -c 'set -eo pipefail; export MANIFEST_CLI_CORE_MODULES_DIR="$1"; source "$1/core/manifest-shared-utils.sh"; source "$1/system/manifest-install-paths.sh"; source "$1/git/manifest-git-commit.sh"; manifest_git_commit "$2" "chore(test): who"' \
        _ "$TEST_REPO_ROOT/modules" "$r"
    [ "$status" -eq 5 ]
    grep -q "no git identity is configured" <<<"$output"
    grep -q "user.name" <<<"$output"
    grep -q "user.email" <<<"$output"
    refute grep -q "hook active at" <<<"$output"
    refute git -C "$r" rev-parse -q --verify HEAD
}

@test "executor: a repo with NO identity of its own but one git can still find, plus a refusing hook, names the hook" {
    local r; r="$(mk_repo hooknoident)"
    git -C "$r" config --unset user.email
    git -C "$r" config --unset user.name
    mk_hook "$r" 1 "HOOK-FIXTURE: refusing this commit"
    # The identity lives in the GLOBAL config, never the repo's — so a probe for
    # a CONFIGURED identity at repo level still fires here and blames identity
    # for the hook's refusal, which is the misattribution this test exists to
    # catch. What it must NOT depend on is git's auto-detection: that succeeds
    # on macOS (hostname resolves) and FAILS in the Linux test container, where
    # git refuses `root@…(none)` — so this test passed locally and was red on
    # the containerized leg for the whole v61 batch, invisible because the local
    # gate is macOS-only (§33, §74). Supplying the identity makes the
    # precondition the test's own, not the platform's.
    local host_global="$SCRATCH/host-gitconfig"
    cat > "$host_global" <<'GITCFG'
[user]
	name = Executor Fixture
	email = executor-fixture@example.invalid
GITCFG
    run env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
        GIT_CONFIG_GLOBAL="$host_global" GIT_CONFIG_NOSYSTEM=1 \
        bash -c 'set -eo pipefail; export MANIFEST_CLI_CORE_MODULES_DIR="$1"; source "$1/core/manifest-shared-utils.sh"; source "$1/system/manifest-install-paths.sh"; source "$1/git/manifest-git-commit.sh"; manifest_git_commit "$2" "chore(test): hook first"' \
        _ "$TEST_REPO_ROOT/modules" "$r"
    [ "$status" -eq 5 ]
    grep -q "HOOK-FIXTURE: refusing this commit" <<<"$output"
    grep -q "hook active at" <<<"$output"
    refute grep -q "no git identity is configured" <<<"$output"
}

@test "executor: on success each stream goes back where git put it — a passing hook's text stays on stderr, git's summary on stdout" {
    local r; r="$(mk_repo streams)"
    local hooks="$r/.hooks"
    mkdir -p "$hooks"
    printf '#!/bin/sh\necho "HOOK-OUT"\necho "HOOK-ERR" >&2\nexit 0\n' > "$hooks/pre-commit"
    chmod +x "$hooks/pre-commit"
    git -C "$r" config core.hooksPath "$hooks"
    manifest_git_commit "$r" "chore(test): streams" >"$SCRATCH/out.txt" 2>"$SCRATCH/err.txt"
    # Measured 2026-09-09 (git 2.55): git redirects a hook's stdout to stderr,
    # so BOTH hook lines arrive on stderr; git's own summary is on stdout.
    grep -q "HOOK-OUT" "$SCRATCH/err.txt"
    grep -q "HOOK-ERR" "$SCRATCH/err.txt"
    refute grep -q "HOOK-" "$SCRATCH/out.txt"
    grep -q "1 file changed" "$SCRATCH/out.txt"
    refute grep -q "1 file changed" "$SCRATCH/err.txt"
    [ "$(git -C "$r" log -1 --format=%s)" = "chore(test): streams" ]
}

@test "executor: bad arguments return 1 and commit nothing" {
    local r; r="$(mk_repo args)"
    run manifest_git_commit "" "chore(test): x"
    [ "$status" -eq 1 ]
    run manifest_git_commit "$r" ""
    [ "$status" -eq 1 ]
    refute git -C "$r" rev-parse -q --verify HEAD
}

@test "sign-off: follows git's own format.signOff — trailer present when true, subject untouched" {
    local r; r="$(mk_repo signoff)"
    git -C "$r" config format.signOff true
    manifest_git_commit "$r" "chore(test): signed"
    [ "$(git -C "$r" log -1 --format=%s)" = "chore(test): signed" ]
    grep -q "^Signed-off-by: Test <test@example.com>$" <<<"$(git -C "$r" log -1 --format=%B)"
}

@test "CONTROL sign-off: absent when format.signOff is unset" {
    local r; r="$(mk_repo nosignoff)"
    manifest_git_commit "$r" "chore(test): unsigned"
    refute grep -q "Signed-off-by" <<<"$(git -C "$r" log -1 --format=%B)"
}

@test "sign-off hint: fires only when a rejection mentions a sign-off AND format.signOff is off" {
    local r; r="$(mk_repo hint)"
    mk_hook "$r" 1 "commit-msg: Signed-off-by trailer is required (DCO)"
    run manifest_git_commit "$r" "chore(test): dco"
    [ "$status" -eq 5 ]
    grep -q "format.signOff true" <<<"$output"

    # Same hook, sign-off already on: the hook still refuses, but no hint —
    # the operator has done the thing the hint would ask for.
    git -C "$r" config format.signOff true
    run manifest_git_commit "$r" "chore(test): dco again"
    [ "$status" -eq 5 ]
    refute grep -q "appears to require a sign-off" <<<"$output"
}

@test "CONTROL sign-off hint: a rejection that says nothing about sign-off gets no hint" {
    local r; r="$(mk_repo nohint)"
    mk_hook "$r" 1 "HOOK-FIXTURE: trailing whitespace"
    run manifest_git_commit "$r" "chore(test): ws"
    [ "$status" -eq 5 ]
    refute grep -q "format.signOff" <<<"$output"
}
