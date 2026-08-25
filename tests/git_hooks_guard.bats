#!/usr/bin/env bats
#
# The pre-commit home-path guard, and the installer that is supposed to put that
# hook where git will run it.
#
# Every hook assertion here runs the REAL hook through a REAL `git commit` in a
# throwaway repo under mk_scratch — never by re-implementing its grep, and never
# by committing in this repo.
#
# Two defects are pinned:
#
#   1. CHECK 6's pattern was unanchored, so any path merely CONTAINING a segment
#      named `home` or `Users` read as a developer's home directory. A bats
#      fixture's sandbox HOME (SCRATCH + a `home` segment) blocked a legitimate
#      commit. The guard is a PII control and must stay FAILING CLOSED, so the
#      leak fixtures below are as load-bearing as the false-positive one.
#   2. install_git_hooks copied the hook into .git/hooks and reported success
#      even when core.hooksPath was set — the setup .git-hooks/README.md and
#      CONTRIBUTING.md tell contributors to use — where git never reads it. The
#      user was told they were protected while nothing was scanning commits.
#
# Path-segment names are held in variables on purpose: spelling an absolute home
# path inline in this file would trip the very hook under test on the commit
# that adds it.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    # Sandbox HOME so sourcing install-cli.sh (which resolves user paths at
    # source time) can never touch the developer's real home.
    export HOME="$SCRATCH/sandbox-home"
    mkdir -p "$HOME"
    U="Users"
    H="home"
}

teardown() {
    cd /tmp || true
    rm -rf "$SCRATCH"
}

# A throwaway repo carrying the tracked hook plus a stub CLI, so CHECK 5 resolves
# to the stub and never shells out to the host's installed `manifest`.
# $1 = dir name. $2 (optional) = core.hooksPath to set BEFORE the initial commit.
_seed_repo() {
    local repo="$SCRATCH/$1"
    mkdir -p "$repo/.git-hooks" "$repo/scripts" "$repo/modules/core"
    cd "$repo"
    git init -q .
    git config user.email "test@manifest.invalid"
    git config user.name "Manifest Test"
    [ -n "${2:-}" ] && git config core.hooksPath "$2"
    cp "$TEST_REPO_ROOT/.git-hooks/pre-commit" .git-hooks/pre-commit
    chmod +x .git-hooks/pre-commit
    touch modules/core/manifest-core.sh
    printf '#!/usr/bin/env bash\necho "stub security ok"\nexit 0\n' > scripts/manifest-cli.sh
    chmod +x scripts/manifest-cli.sh
    printf '.env\n.env.local\n.env.*.local\nmanifest.config\n' > .gitignore
    git add -A
    git commit -q -m "seed"
}

# Repo wired the documented way: git runs the tracked hook directly.
_mk_hook_repo() { _seed_repo "${1:-hookrepo}" .git-hooks; }

# Repo with the hook SOURCE present but no hooks wiring yet — the state
# install_git_hooks is meant to fix. Tests set their own core.hooksPath.
_mk_installable_repo() { _seed_repo "${1:-installrepo}"; }

# Stage $1 with content $2 and try to commit. Sets $HOOK_STATUS / $HOOK_OUTPUT.
_try_commit() {
    local file="$1" content="$2"
    printf '%s\n' "$content" > "$file"
    git add "$file"
    HOOK_OUTPUT="$(git commit -m "fixture: $file" 2>&1)" && HOOK_STATUS=0 || HOOK_STATUS=$?
    return 0
}

# =============================================================================
# CHECK 6 — the fixture itself must be able to commit (positive control)
# =============================================================================

@test "hook fixture: a clean file commits (proves the fixture CAN produce a pass)" {
    _mk_hook_repo
    # _seed_repo's own initial commit already ran the hook; this proves a second,
    # ordinary commit also passes, so every BLOCKED assertion below is the
    # fixture reacting to content and not a repo that simply cannot commit.
    _try_commit clean.txt 'nothing to see here'

    [ "$HOOK_STATUS" -eq 0 ]
    grep -q "All security checks passed" <<<"$HOOK_OUTPUT"
    [ -n "$(git log --format=%s -1)" ]
}

# =============================================================================
# CHECK 6 — real leaks stay blocked (fail-closed side)
# =============================================================================

@test "hook blocks an absolute macOS home path in staged content" {
    _mk_hook_repo
    _try_commit leak_users.txt "CACHE_DIR=\"/$U/fakedev/projects/thing\""

    [ "$HOOK_STATUS" -ne 0 ]
    grep -q "absolute home paths found in staged content" <<<"$HOOK_OUTPUT"
    grep -q "COMMIT BLOCKED" <<<"$HOOK_OUTPUT"
}

@test "hook blocks an absolute Linux home path in staged content" {
    _mk_hook_repo
    _try_commit leak_home.txt "CACHE_DIR=\"/$H/fakedev/projects/thing\""

    [ "$HOOK_STATUS" -ne 0 ]
    grep -q "absolute home paths found in staged content" <<<"$HOOK_OUTPUT"
}

@test "hook blocks a home path behind a file:// URL — a slash is still a boundary" {
    # The anchor treats `/` as a path-start boundary precisely so triple-slash
    # URLs cannot smuggle a home path past it.
    _mk_hook_repo
    _try_commit leak_url.txt "docs: file:///$U/fakedev/notes.md"

    [ "$HOOK_STATUS" -ne 0 ]
    grep -q "absolute home paths found in staged content" <<<"$HOOK_OUTPUT"
}

@test "hook blocks a real leak sharing a line with an allowed placeholder" {
    # The exemption filter used to run per LINE, so one placeholder anywhere on
    # the line pardoned every other path on it. Per-MATCH filtering closes it.
    _mk_hook_repo
    _try_commit leak_mixed.txt "example=/$U/you/ok real=/$U/fakedev/leak"

    [ "$HOOK_STATUS" -ne 0 ]
    grep -q "absolute home paths found in staged content" <<<"$HOOK_OUTPUT"
}

# =============================================================================
# CHECK 6 — the false positive that blocked a legitimate commit
# =============================================================================

@test "hook allows a scratch path whose middle segment is named home" {
    # The reported incident, verbatim in shape: a bats sandbox HOME.
    _mk_hook_repo
    _try_commit scratch_home.bats "    mkdir -p \"\$SCRATCH/$H/.manifest-cli\""

    [ "$HOOK_STATUS" -eq 0 ]
    grep -q "No absolute home paths in staged content" <<<"$HOOK_OUTPUT"
}

@test "hook allows a directory literally named home nested under another path" {
    _mk_hook_repo
    _try_commit nested_home.txt "/tmp/sandbox/$H/.manifest-cli/config.yaml"

    [ "$HOOK_STATUS" -eq 0 ]
    grep -q "No absolute home paths in staged content" <<<"$HOOK_OUTPUT"
}

@test "hook allows a scratch path whose middle segment is named Users" {
    _mk_hook_repo
    _try_commit scratch_users.txt "dest=\"\$TMPDIR/$U/profile.json\""

    [ "$HOOK_STATUS" -eq 0 ]
    grep -q "No absolute home paths in staged content" <<<"$HOOK_OUTPUT"
}

# =============================================================================
# CHECK 6 — the documented placeholders keep working
# =============================================================================

@test "hook still allows every documented placeholder" {
    _mk_hook_repo
    local named=(you user username realuser nobody-here somebody-who-does-not-exist runner linuxbrew)
    local name
    for name in "${named[@]}"; do
        _try_commit "ph_$name.txt" "path=/$U/$name/work and /$H/$name/work"
        if [ "$HOOK_STATUS" -ne 0 ]; then
            printf 'placeholder %s was rejected:\n%s\n' "$name" "$HOOK_OUTPUT" >&2
            return 1
        fi
    done
    # The three character-class placeholders: a variable, an angle-bracket
    # template, and a brace template.
    _try_commit ph_var.txt "path=/$U/\$USER/work"
    [ "$HOOK_STATUS" -eq 0 ]
    _try_commit ph_angle.txt "path=/$U/<name>/work"
    [ "$HOOK_STATUS" -eq 0 ]
    _try_commit ph_brace.txt "path=/$U/{name}/work"
    [ "$HOOK_STATUS" -eq 0 ]
}

# =============================================================================
# CHECK 6 — the hook must not block the commit that ships it
# =============================================================================
# Declared control: this passes before and after the fix. It exists so a future
# edit to the hook's own comments (which necessarily discuss home paths) cannot
# make the file unshippable without a test saying so.

@test "hook does not flag its own source or the installer's" {
    _mk_hook_repo
    cp "$TEST_REPO_ROOT/.git-hooks/pre-commit" ./copy-of-pre-commit
    cp "$TEST_REPO_ROOT/install-cli.sh" ./copy-of-install-cli.sh
    git add copy-of-pre-commit copy-of-install-cli.sh
    HOOK_OUTPUT="$(git commit -m "ship self" 2>&1)" && HOOK_STATUS=0 || HOOK_STATUS=$?

    if [ "$HOOK_STATUS" -ne 0 ]; then
        printf 'the hook rejected its own shipped content:\n%s\n' "$HOOK_OUTPUT" >&2
        return 1
    fi
}

# =============================================================================
# install_git_hooks — ITEM 2: the advice must name something that exists
# =============================================================================

@test "installer's not-a-git-repo advice names core.hooksPath, not a script that does not exist" {
    [ ! -e "$TEST_REPO_ROOT/install-git-hooks.sh" ]

    mkdir -p "$SCRATCH/notarepo"
    cd "$SCRATCH/notarepo"
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"

    run install_git_hooks
    [ "$status" -eq 0 ]
    grep -q "Not in a Git repository" <<<"$output"
    grep -q "core.hooksPath .git-hooks" <<<"$output"
    refute grep -q "install-git-hooks.sh" <<<"$output"
}

@test "no installer code path can print the nonexistent install-git-hooks.sh" {
    # Any occurrence outside a comment is code — a string the installer could
    # put in front of a user. `[^#]*` cannot cross a `#`, so the explanatory
    # comment that records why the script does not exist is not a match.
    refute grep -qE '^[^#]*install-git-hooks\.sh' "$TEST_REPO_ROOT/install-cli.sh"
}

# =============================================================================
# install_git_hooks — ITEM 3: no success message for a hook git will never run
# =============================================================================

@test "installer honors a configured core.hooksPath instead of the ignored .git/hooks" {
    _mk_installable_repo hooks_custom
    mkdir -p custom-hooks
    git config core.hooksPath custom-hooks
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"

    run install_git_hooks
    [ "$status" -eq 0 ]
    [ -x custom-hooks/pre-commit ]
    # Nothing may be left in the directory git ignores — that copy is the
    # false assurance this test exists to prevent.
    [ ! -e .git/hooks/pre-commit ]

    # The claim is only true if a commit that SHOULD be blocked actually is.
    _try_commit leak.txt "CACHE_DIR=\"/$U/fakedev/x\""
    [ "$HOOK_STATUS" -ne 0 ]
    grep -q "absolute home paths found in staged content" <<<"$HOOK_OUTPUT"
}

@test "installer reports accurately when core.hooksPath already points at the shipped hook" {
    _mk_installable_repo hooks_self
    git config core.hooksPath .git-hooks
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"

    run install_git_hooks
    [ "$status" -eq 0 ]
    grep -q "already active" <<<"$output"
    [ ! -e .git/hooks/pre-commit ]
    # A cp/backup onto itself would litter the TRACKED source directory.
    local litter
    litter="$(find .git-hooks -name 'pre-commit.backup.*')"
    [ -z "$litter" ]
    # Still armed.
    _try_commit leak.txt "CACHE_DIR=\"/$H/fakedev/x\""
    [ "$HOOK_STATUS" -ne 0 ]
}

@test "installer will not write into a hooks directory outside this repo" {
    # An absolute core.hooksPath is typically a user-wide hooks dir shared by
    # every repo they own. The installer must not write there — and must not
    # fall back to the .git/hooks copy git is ignoring either.
    _mk_installable_repo hooks_outside
    mkdir -p "$SCRATCH/global-hooks"
    git config core.hooksPath "$SCRATCH/global-hooks"
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"

    run install_git_hooks
    [ "$status" -eq 0 ]
    grep -q "points outside this repo" <<<"$output"
    [ ! -e "$SCRATCH/global-hooks/pre-commit" ]
    [ ! -e .git/hooks/pre-commit ]
    refute grep -q "installed successfully" <<<"$output"
}

@test "installer refuses to conjure a hooks directory at a configured path that does not exist" {
    _mk_installable_repo hooks_missing
    git config core.hooksPath nowhere-hooks
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"

    run install_git_hooks
    [ "$status" -eq 0 ]
    grep -q "does not exist" <<<"$output"
    [ ! -e nowhere-hooks ]
    # And no consolation copy in the location git is ignoring.
    [ ! -e .git/hooks/pre-commit ]
    refute grep -q "installed successfully" <<<"$output"
}

@test "installer still installs into .git/hooks when core.hooksPath is unset" {
    # Declared control: passes before and after the fix. It pins the default
    # path so honoring core.hooksPath cannot regress the ordinary case.
    _mk_installable_repo hooks_default
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"

    run install_git_hooks
    [ "$status" -eq 0 ]
    [ -x .git/hooks/pre-commit ]
    grep -q "installed successfully" <<<"$output"

    _try_commit leak.txt "CACHE_DIR=\"/$U/fakedev/x\""
    [ "$HOOK_STATUS" -ne 0 ]
}

@test "post-install summary does not claim a hook that core.hooksPath diverts" {
    _mk_installable_repo hooks_stale
    mkdir -p .git/hooks custom-hooks
    # A stale copy in the location git no longer reads.
    cp .git-hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    git config core.hooksPath custom-hooks
    set --
    # shellcheck disable=SC1090
    source "$TEST_REPO_ROOT/install-cli.sh"

    run display_post_install_info
    [ "$status" -eq 0 ]
    refute grep -q "Pre-commit security hook installed" <<<"$output"
}
