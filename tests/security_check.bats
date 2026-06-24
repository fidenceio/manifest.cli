#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "system/manifest-security.sh"
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT/docs"
    cd "$MANIFEST_CLI_PROJECT_ROOT"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    printf '46.10.0\n' > VERSION
    printf '.env\n.env.*.local\nmanifest.config.local.yaml\n' > .gitignore
    git add VERSION .gitignore
    git commit -q -m "initial"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "security --check is read-only and does not write reports" {
    run manifest_security --check

    [ "$status" -eq 0 ]
    [[ "$output" == *"Security audit passed with no issues."* ]]
    [ ! -e "$MANIFEST_CLI_PROJECT_ROOT/docs/SECURITY_ANALYSIS_REPORT.md" ]
    [ ! -d "$MANIFEST_CLI_PROJECT_ROOT/docs/zArchive" ]
}

@test "security without read-only flag writes reports" {
    run manifest_security

    [ "$status" -eq 0 ]
    [ -f "$MANIFEST_CLI_PROJECT_ROOT/docs/SECURITY_ANALYSIS_REPORT.md" ]
    find "$MANIFEST_CLI_PROJECT_ROOT/docs/zArchive" -name 'SECURITY_ANALYSIS_REPORT_v46.10.0_*.md' | grep -q .
}

@test "security: ignored private files are not reported as tracked" {
    touch .env

    run check_git_tracking "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 0 ]
    [[ "$output" != *".env is tracked by Git"* ]]
}

@test "security rejects unknown options" {
    run manifest_security --wat

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown security option: --wat"* ]]
}

@test "pre-commit hook uses explicit read-only security mode" {
    local skip_var="MANIFEST_CLI_SKIP_SECURITY""_REPORT"

    grep -q 'manifest security --check' "$TEST_REPO_ROOT/.git-hooks/pre-commit"
    grep -q 'security_output=' "$TEST_REPO_ROOT/.git-hooks/pre-commit"
    grep -q 'env -u MANIFEST_CLI_BASH_REEXEC' "$TEST_REPO_ROOT/.git-hooks/pre-commit"
    ! grep -q "$skip_var" "$TEST_REPO_ROOT/.git-hooks/pre-commit"
    ! grep -q "$skip_var" "$TEST_REPO_ROOT/modules/system/manifest-security.sh"
}

@test "pre-commit hook clears inherited bash re-exec sentinel for repo-local CLI" {
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT/.git-hooks" "$MANIFEST_CLI_PROJECT_ROOT/scripts" "$MANIFEST_CLI_PROJECT_ROOT/modules/core"
    cp "$TEST_REPO_ROOT/.git-hooks/pre-commit" "$MANIFEST_CLI_PROJECT_ROOT/.git-hooks/pre-commit"
    chmod +x "$MANIFEST_CLI_PROJECT_ROOT/.git-hooks/pre-commit"
    touch "$MANIFEST_CLI_PROJECT_ROOT/modules/core/manifest-core.sh"
    cat > "$MANIFEST_CLI_PROJECT_ROOT/scripts/manifest-cli.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ "${MANIFEST_CLI_BASH_REEXEC:-0}" = "1" ]; then
    echo "leaked MANIFEST_CLI_BASH_REEXEC"
    exit 12
fi
if [ "$1" != "security" ] || [ "$2" != "--check" ]; then
    echo "unexpected args: $*"
    exit 13
fi
echo "fake security check passed"
SCRIPT
    chmod +x "$MANIFEST_CLI_PROJECT_ROOT/scripts/manifest-cli.sh"

    run env MANIFEST_CLI_BASH_REEXEC=1 "$MANIFEST_CLI_PROJECT_ROOT/.git-hooks/pre-commit"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Manifest CLI security audit passed"* ]]
    [[ "$output" != *"leaked MANIFEST_CLI_BASH_REEXEC"* ]]
}
