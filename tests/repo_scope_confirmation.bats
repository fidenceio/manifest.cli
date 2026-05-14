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
    echo "$output" | grep -q "Git root:.*$SCRATCH"
    echo "$output" | grep -q "Target:.*this Git repository only"
    ! echo "$output" | grep -q "Apply to this repository"
    ! echo "$output" | grep -q "Apply target repository"
}

@test "ship repo apply refuses non-interactive confirmation before mutation" {
    init_repo_fixture

    PROJECT_ROOT="$SCRATCH" run manifest_ship_repo patch -y < /dev/null

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Repo identity"
    echo "$output" | grep -q "Apply target repository"
    echo "$output" | grep -q "Changes will be made to this Git repository only"
    echo "$output" | grep -q "Git root: $SCRATCH"
    echo "$output" | grep -q "Repo confirmation requires an interactive terminal"
    ! echo "$output" | grep -q "Applying because -y/--yes was provided"
    [ "$(cat "$SCRATCH/VERSION")" = "1.2.3" ]
}

@test "repo confirmation refuses a declined interactive prompt" {
    if ! command -v script >/dev/null 2>&1; then
        skip "script command unavailable"
    fi
    if ! script -q -c true /dev/null >/dev/null 2>&1; then
        skip "script command does not support util-linux -c syntax"
    fi

    init_repo_fixture
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

    run bash -lc "printf 'n\n' | script -q -c '$SCRATCH/confirm-repo.sh' /dev/null"

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Apply target repository"
    echo "$output" | grep -q "Apply to this repository"
    echo "$output" | grep -q "Repository target was not confirmed"
}
