#!/usr/bin/env bats
# bats file_tags=smoke
# Init prepares; it never invokes the release workflow. Real local Git remotes
# establish the behavior without any network or GitHub publication.
load 'helpers/setup'

setup() {
    export MANIFEST_CLI_RELEASE_GATE=local-tests
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work/scripts"
    git init -q --bare -b main "$SCRATCH/origin.git"
    export INIT_CHECK_LOG="$SCRATCH/check.log"
    cat > "$SCRATCH/work/scripts/run-tests.sh" <<'GATE'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$INIT_CHECK_LOG"
test -s VERSION
bash -n scripts/project-check.sh
GATE
    printf '#!/bin/sh\necho project-check\n' > "$SCRATCH/work/scripts/project-check.sh"
    chmod +x "$SCRATCH/work/scripts/run-tests.sh"
    export MANIFEST_CLI_GITHUB_OWNER=testowner
    cd "$SCRATCH/work"
}

teardown() { cd /tmp; rm -rf "$SCRATCH"; }
cli() { run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"; echo "$output"; }
assert_unreleased() {
    refute git -C "$SCRATCH/work" rev-parse --verify HEAD
    [ -z "$(git -C "$SCRATCH/work" tag)" ]
    [ -z "$(git -C "$SCRATCH/origin.git" for-each-ref)" ]
    [ "$(cat VERSION)" = "1.0.0" ]
}

@test "init readiness: empty directory previews private creation without writes or calls" {
    gh_stub_install
    local before
    before="$(find . -type f -exec sha256sum {} + | sort)"
    cli init
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create: .git/"* ]]
    [[ "$output" == *"would gh repo create: testowner/work (private)"* ]]
    [[ "$output" == *"readiness:"* ]]
    [ "$(find . -type f -exec sha256sum {} + | sort)" = "$before" ]
    [ ! -e .git ]
    [ ! -e "$INIT_CHECK_LOG" ]
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
    [ ! -e "$HOME/.manifest-cli" ]
}

@test "init readiness: empty remote prepares an unborn main branch; next ship previews cleanly" {
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"origin is empty — no pull needed"* ]]
    [[ "$output" == *"Repository prepared for ship"* ]]
    [ "$(git branch --show-current)" = main ]
    [ "$(git remote get-url origin)" = "$SCRATCH/origin.git" ]
    grep -qx -- '--tier full --jobs 1 --no-cache' "$INIT_CHECK_LOG"
    for file in VERSION README.md CHANGELOG.md .gitignore .env.example robots.txt ai.txt manifest.config.local.yaml; do
        [ -s "$file" ]
    done
    [ -d docs ]
    assert_unreleased
    cli ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship repo preview"* ]]
    [[ "$output" == *"1.0.1"* ]]
    assert_unreleased
    [ "$(wc -l < "$INIT_CHECK_LOG")" -eq 1 ]
}

@test "init readiness: default private remote creation and rerun are idempotent" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true
    export MANIFEST_CLI_GH_STUB_REMOTE_URL="$SCRATCH/origin.git"
    cli init -y
    [ "$status" -eq 0 ]
    grep -q -- '--private' "$MANIFEST_CLI_GH_STUB_LOG"
    [ "$(grep -c $'repo\tcreate' "$MANIFEST_CLI_GH_STUB_LOG")" -eq 1 ]
    printf 'custom readme\n' > README.md
    cli init -y
    [ "$status" -eq 0 ]
    [ "$(grep -c $'repo\tcreate' "$MANIFEST_CLI_GH_STUB_LOG")" -eq 1 ]
    [ "$(cat README.md)" = 'custom readme' ]
    [ "$(wc -l < "$INIT_CHECK_LOG")" -eq 2 ]
    assert_unreleased
}

@test "init readiness: existing remote content is connected before scaffolding" {
    git init -q -b main "$SCRATCH/seed"
    printf '# Remote readme\n' > "$SCRATCH/seed/README.md"
    printf 'REMOTE=value\n' > "$SCRATCH/seed/.env.example"
    git -C "$SCRATCH/seed" add .
    git -C "$SCRATCH/seed" commit -qm seed
    git -C "$SCRATCH/seed" remote add origin "$SCRATCH/origin.git"
    git -C "$SCRATCH/seed" push -q origin main
    local commit
    commit="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
    cli init repo --remote "$SCRATCH/origin.git" -y
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$commit" ]
    [ "$(git --git-dir="$SCRATCH/origin.git" rev-parse main)" = "$commit" ]
    [ "$(cat README.md)" = '# Remote readme' ]
    [ "$(cat .env.example)" = 'REMOTE=value' ]
    [ "$(git rev-parse --abbrev-ref '@{upstream}')" = origin/main ]
    [ -z "$(git tag)" ]
}

@test "init readiness: VERSION alone is backfilled and verified" {
    git init -q -b main
    git remote add origin "$SCRATCH/origin.git"
    printf '2.3.4\n' > VERSION
    cli init -y
    [ "$status" -eq 0 ]
    [ -f CHANGELOG.md ]
    [ -f .env.example ]
    [ "$(cat VERSION)" = 2.3.4 ]
    [ -s "$INIT_CHECK_LOG" ]
}

@test "init readiness: failing existing checks block success and are preserved" {
    printf 'if then\n' > scripts/project-check.sh
    local before
    before="$(sha256sum scripts/run-tests.sh)"
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Release check failed"* ]]
    refute grep -q 'Repository prepared for ship' <<< "$output"
    [ "$(sha256sum scripts/run-tests.sh)" = "$before" ]
    assert_unreleased
    # Positive recovery: the same readiness check passes after the actual error
    # is fixed. Init does not replace the gate with a permissive script.
    printf '#!/bin/sh\necho fixed\n' > scripts/project-check.sh
    cli init -y
    [ "$status" -eq 0 ]
    assert_unreleased
}

@test "init readiness: no declared verification reports the real blocker" {
    rm scripts/run-tests.sh
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"no build or test verification is declared"* ]]
    [[ "$output" == *"Setup incomplete"* ]]
    refute grep -q 'Repository prepared for ship' <<< "$output"
    assert_unreleased
}

@test "init readiness: a truly empty folder gets a real scaffold check that fails when code is added" {
    rm -r scripts
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"scaffold-only repository: verified"* ]]
    assert_unreleased
    cli ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship repo preview"* ]]
    assert_unreleased
    mkdir -p docs-site
    printf '# Managed by Manifest CLI docs site generation\n' > docs-site/_config.yml
    cli init -y
    [ "$status" -eq 0 ]
    assert_unreleased
    printf 'user_owned: true\n' > docs-site/_config.yml
    cli init -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"no build or test verification is declared"* ]]
    rm docs-site/_config.yml
    printf 'console.log("new application");\n' > app.js
    cli init -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"no build or test verification is declared"* ]]
    assert_unreleased
}

@test "init readiness: unreadable origin cannot be swallowed as a successful connection" {
    cli init --remote "$SCRATCH/nonexistent.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot read origin"* ]]
    refute grep -q 'Repository prepared for ship' <<< "$output"
    [ ! -f VERSION ]
    [ ! -f "$INIT_CHECK_LOG" ]
}

@test "init readiness: conflicting origin is preserved and refused" {
    git init -q -b main
    git remote add origin "$SCRATCH/origin.git"
    cli init --remote "$SCRATCH/different.git" -y
    [ "$status" -ne 0 ]
    [ "$(git remote get-url origin)" = "$SCRATCH/origin.git" ]
    [ ! -f VERSION ]
}

@test "init readiness: wrong release branch refuses without scaffolding or remote creation" {
    git init -q -b feature
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot release"* ]]
    [ ! -f VERSION ]
    refute git remote get-url origin
}

@test "init readiness: missing identity blocks success without inventing an author" {
    git init -q -b main
    git config user.name ''
    git config user.email ''
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"identity is missing"* ]]
    [ -z "$(git config user.name)" ]
    assert_unreleased
}

@test "init readiness: contradictory connection options refuse before Git initialization" {
    cli init --no-connect --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [ ! -d .git ]
    cli init --remote "$SCRATCH/origin.git" --create-repo-public -y
    [ "$status" -ne 0 ]
    [ ! -d .git ]
}

seed_remote_history() {
    git init -q -b main "$SCRATCH/seed"
    printf 'base\n' > "$SCRATCH/seed/shared.txt"
    git -C "$SCRATCH/seed" add .
    git -C "$SCRATCH/seed" commit -qm base
    git -C "$SCRATCH/seed" remote add origin "$SCRATCH/origin.git"
    git -C "$SCRATCH/seed" push -q origin main
    git init -q -b main
    git remote add origin "$SCRATCH/origin.git"
    git fetch -q origin
    git merge -q --ff-only origin/main
}

@test "init readiness: diverged histories stop without merging or changing either head" {
    seed_remote_history
    printf 'local\n' > local.txt
    git add local.txt
    git commit -qm local
    printf 'remote\n' > "$SCRATCH/seed/remote.txt"
    git -C "$SCRATCH/seed" add remote.txt
    git -C "$SCRATCH/seed" commit -qm remote
    git -C "$SCRATCH/seed" push -q origin main
    local local_head remote_head
    local_head="$(git rev-parse HEAD)"
    remote_head="$(git --git-dir="$SCRATCH/origin.git" rev-parse main)"
    cli init -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot fast-forward"* ]]
    [ "$(git rev-parse HEAD)" = "$local_head" ]
    [ "$(git --git-dir="$SCRATCH/origin.git" rev-parse main)" = "$remote_head" ]
    [ "$(cat local.txt)" = local ]
    [ ! -f VERSION ]
    [ ! -f "$INIT_CHECK_LOG" ]
}

@test "init readiness: remote update conflicting with local content is preserved and refused" {
    seed_remote_history
    printf 'new remote content\n' > "$SCRATCH/seed/shared.txt"
    git -C "$SCRATCH/seed" commit -qam update
    git -C "$SCRATCH/seed" push -q origin main
    printf 'local uncommitted content\n' > shared.txt
    local head
    head="$(git rev-parse HEAD)"
    cli init -y
    [ "$status" -ne 0 ]
    [ "$(git rev-parse HEAD)" = "$head" ]
    [ "$(cat shared.txt)" = 'local uncommitted content' ]
    [ ! -f VERSION ]
}

@test "init readiness: disabled verification is not called verified or silently re-enabled" {
    export MANIFEST_CLI_RELEASE_GATE=none
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot certify test readiness"* ]]
    [ ! -f "$INIT_CHECK_LOG" ]
    assert_unreleased
}

@test "init readiness: invalid VERSION is caught even when the project's check passes" {
    printf 'invalid\n' > VERSION
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"VERSION is invalid"* ]]
    [ "$(cat VERSION)" = invalid ]
    [ -s "$INIT_CHECK_LOG" ]
}

@test "init readiness: public visibility is explicit in the preview and has no side effects" {
    gh_stub_install
    cli init --create-repo-public
    [ "$status" -eq 0 ]
    [[ "$output" == *"testowner/work (public)"* ]]
    [[ "$output" == *"manifest init repo --create-repo-public -y"* ]]
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
    [ ! -d .git ]
}

@test "init readiness: a directory blocking a required file cannot be reported ready" {
    mkdir README.md
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Required scaffold files are missing"* ]]
    [ -d README.md ]
    refute grep -q 'Repository prepared for ship' <<< "$output"
    assert_unreleased
}

@test "init readiness: existing red origin CI is reported before the next ship" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT=$'31\tfailure\thttps://example.invalid/runs/31'
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"CI is red"* ]]
    refute grep -q 'Repository prepared for ship' <<< "$output"
    assert_unreleased
}

@test "init readiness: project config selects the same branch and gate as the next ship" {
    clear_release_gate_env_override
    cat > manifest.config.local.yaml <<'CONFIG'
git:
  default_branch: trunk
release:
  gate: local-tests
  gate_command: ./scripts/configured-check.sh
CONFIG
    printf '#!/bin/sh\nexit 71\n' > scripts/run-tests.sh
    cat > scripts/configured-check.sh <<'CHECK'
#!/usr/bin/env bash
set -e
test -s VERSION
bash -n scripts/project-check.sh
echo configured >> "$INIT_CHECK_LOG"
CHECK
    chmod +x scripts/configured-check.sh
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = trunk ]
    [ "$(cat "$INIT_CHECK_LOG")" = configured ]
    [[ "$output" == *"Release check: ./scripts/configured-check.sh"* ]]
    assert_unreleased
    cli ship repo patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"./scripts/configured-check.sh"* ]]
    assert_unreleased
}

@test "init readiness: config fetched from origin is loaded before local scaffolding" {
    git init -q -b main "$SCRATCH/seed"
    printf 'docs:\n  folder: project-docs\n' > "$SCRATCH/seed/manifest.config.yaml"
    git -C "$SCRATCH/seed" add .
    git -C "$SCRATCH/seed" commit -qm config
    git -C "$SCRATCH/seed" remote add origin "$SCRATCH/origin.git"
    git -C "$SCRATCH/seed" push -q origin main
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -eq 0 ]
    [ -d project-docs ]
    [ ! -d docs ]
    [[ "$output" == *"Repository prepared for ship"* ]]
}

@test "init readiness: an empty folder can complete its first local ship after init without publishing" {
    rm -r scripts
    # A failed, local-only time endpoint keeps this real workflow offline.
    mkdir -p "$SCRATCH/bin"
    printf '#!/bin/sh\nexit 7\n' > "$SCRATCH/bin/curl"
    chmod +x "$SCRATCH/bin/curl"
    export PATH="$SCRATCH/bin:$PATH"
    export MANIFEST_CLI_TIME_RETRIES=1 MANIFEST_CLI_TIME_TIMEOUT=1
    cli init --remote "$SCRATCH/origin.git" -y
    [ "$status" -eq 0 ]
    assert_unreleased
    cli ship repo patch --local -y
    [ "$status" -eq 0 ]
    [ "$(cat VERSION)" = 1.0.1 ]
    git rev-parse --verify HEAD
    [ -z "$(git status --porcelain)" ]
    [ -z "$(git tag)" ]
    [ -z "$(git -C "$SCRATCH/origin.git" for-each-ref)" ]
}

@test "init readiness: remote preview and replay redact credentials while preserving ordinary URLs" {
    local remote needle plain
    remote="$(printf 'https://%s:%s@example.invalid/org/repo.git' review-user review-only-token)"
    needle="$(printf '%s:%s@' review-user review-only-token)"
    cli init repo --remote "$remote"
    [ "$status" -eq 0 ]
    refute grep -Fq "$needle" <<< "$output"
    refute grep -Fq review-only-token <<< "$output"
    [[ "$output" == *REDACTED* ]]
    [[ "$output" == *example.invalid/org/repo.git* ]]
    [[ "$output" == *"manifest init repo --remote"* ]]
    [ ! -e .git ]
    [ ! -e "$INIT_CHECK_LOG" ]
    plain=https://example.invalid/org/repo.git
    cli init repo --remote "$plain"
    [ "$status" -eq 0 ]
    [[ "$output" == *"would connect origin: $plain"* ]]
    [[ "$output" == *"manifest init repo --remote $plain -y"* ]]
    [ ! -e .git ]
}
