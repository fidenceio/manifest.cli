#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules \
        "core/manifest-status.sh" \
        "git/manifest-git.sh" \
        "git/manifest-git-changes.sh" \
        "recipe/manifest-recipe.sh" \
        "core/manifest-ship.sh"
    SCRATCH="$(mk_scratch)"
    # Isolate HOME so apply-path side effects (e.g. the §5.8 audit log under
    # $HOME/.manifest-cli/audit) land in the sandbox, never the real home.
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

init_repo_fixture() {
    cd "$SCRATCH"
    git init -q
    git config user.email t@example.com
    git config user.name "Test User"
    git remote add origin git@github.com:example/repo.git
    echo "1.2.3" > VERSION
}

@test "status repo fails outside a git repository" {
    cd "$SCRATCH"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" status repo

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "repo scope requires running inside a Git repository"
    echo "$output" | grep -q "Current directory: $SCRATCH"
    echo "$output" | grep -q "manifest status repo"
}

@test "ship repo preview fails outside a git repository" {
    cd "$SCRATCH"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship repo patch

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "repo scope requires running inside a Git repository"
    echo "$output" | grep -q "Current directory: $SCRATCH"
    echo "$output" | grep -q "manifest ship repo patch"
}

@test "ship repo preview shows identity and does not prompt" {
    init_repo_fixture

    PROJECT_ROOT="$SCRATCH" run manifest_ship_repo patch < /dev/null

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Repo identity"
    echo "$output" | grep -q "Current repo:.*example/repo"
    echo "$output" | grep -q "Git root:.*$SCRATCH"
    echo "$output" | grep -q "Mutation scope:.*this Git repository only"
    ! echo "$output" | grep -q "Apply to this repository"
    ! echo "$output" | grep -q "Apply target repository"
}

@test "ship repo apply refuses non-interactive confirmation before mutation" {
    init_repo_fixture

    PROJECT_ROOT="$SCRATCH" run manifest_ship_repo patch -y < /dev/null

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Repo identity"
    echo "$output" | grep -q "Current repo:.*example/repo"
    echo "$output" | grep -q "Apply target repository"
    echo "$output" | grep -q "Changes will be made to this Git repository only"
    echo "$output" | grep -q "Git root:"
    echo "$output" | grep -Fq "$SCRATCH"
    echo "$output" | grep -q "Repo confirmation requires an interactive terminal"
    ! echo "$output" | grep -q "Applying because -y/--yes was provided"
    [ "$(cat "$SCRATCH/VERSION")" = "1.2.3" ]
}

@test "ship repo apply fails before version bump when git index is locked" {
    init_repo_fixture
    touch "$SCRATCH/.git/index.lock"

    MANIFEST_CLI_AUTO_CONFIRM=1 PROJECT_ROOT="$SCRATCH" run manifest_ship_repo patch -y

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Git index lock already exists"
    echo "$output" | grep -q "refusing to mutate files before Git can commit"
    [ "$(cat "$SCRATCH/VERSION")" = "1.2.3" ]
}

@test "ship repo apply fails before version bump when git metadata is unwritable" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root bypasses chmod-based write restriction"
    fi
    init_repo_fixture
    chmod u-w "$SCRATCH/.git"

    MANIFEST_CLI_AUTO_CONFIRM=1 PROJECT_ROOT="$SCRATCH" run manifest_ship_repo patch -y
    rc="$status"
    out="$output"

    # Restore write permission immediately so teardown can clean up regardless
    # of whether assertions below pass or terminate the test.
    chmod u+w "$SCRATCH/.git"

    [ "$rc" -ne 0 ]
    echo "$out" | grep -q "Git metadata is not writable"
    echo "$out" | grep -q "refusing to mutate files before Git can commit"
    [ "$(cat "$SCRATCH/VERSION")" = "1.2.3" ]
}

@test "repo confirmation refuses a declined interactive prompt" {
    if [ "${MANIFEST_CLI_ENABLE_PTY_TESTS:-0}" != "1" ]; then
        skip "PTY prompt test is opt-in; script is not a Manifest runtime dependency"
    fi

    if ! command -v script >/dev/null 2>&1; then
        skip "script command unavailable"
    fi
    if ! script -q -e -c true /dev/null >/dev/null 2>&1; then
        skip "script command does not support util-linux -e -c syntax"
    fi

    init_repo_fixture
    script_status=0
    script -q -e -c "bash -c 'echo manifest-script-smoke; exit 7'" /dev/null > "$SCRATCH/script-smoke.out" 2>&1 || script_status="$?"
    if [ "$script_status" -ne 7 ] || ! grep -q "manifest-script-smoke" "$SCRATCH/script-smoke.out"; then
        skip "script command cannot execute bash child commands portably"
    fi

    cat > "$SCRATCH/confirm-repo.sh" <<SH
#!/usr/bin/env bash
set -e
source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
cd "$SCRATCH"
PROJECT_ROOT="$SCRATCH"
manifest_repo_scope_confirm_apply "$SCRATCH" "manifest ship repo patch -y"
SH
    chmod +x "$SCRATCH/confirm-repo.sh"

    status=0
    output="$(bash -lc "printf 'n\n' | script -q -e -c 'bash $SCRATCH/confirm-repo.sh' /dev/null" 2>&1)" || status="$?"
    if [ "$status" -eq 127 ]; then
        skip "script command cannot execute the confirmation fixture portably"
    fi

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Apply target repository"
    echo "$output" | grep -q "Apply to this repository"
    echo "$output" | grep -q "Repository target was not confirmed"
}
