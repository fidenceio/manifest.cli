#!/usr/bin/env bats

# §2(a): key material has prevention (the KEY MATERIAL .gitignore block) but
# had no detection — a private key under a name the patterns miss
# (`credentials.json`, `deploy-secret.txt`) was caught by nothing, and a key
# committed before the block existed stayed tracked. `check_key_material`
# scans CONTENT for the PEM and PuTTY headers over two sets: `pending` (what
# `git add .` would newly land: modified + untracked, not ignored, and not a
# key HEAD already carries) and `tracked` (`git ls-files`). `manifest
# security` reports either as CRITICAL; the ship's sweep commit refuses on
# `pending` before `git add .` and only NAMES `tracked` — a key already in
# history has been pushed, and refusing would break every repo that commits
# fixture keys for its own tests (steward, 2026-11-07).
#
# Both listings are NUL-terminated. The first cut read porcelain v1 without
# -z, so a name git quotes (space, quote, backslash, non-ASCII) was carried
# with its quotes, did not exist, and `grep -s` skipped it silently: five
# planted keys read as two (steward, measured on BSD, GNU and BusyBox grep).
# The quoted-names test below fails against that cut and passes now.
#
# Fixture headers are assembled with printf so this file never contains a
# header the scanner would match — a guard must not speak the forbidden thing
# in its own jurisdiction (TRACKER, standing lessons).

load 'helpers/setup'

_pem_file() {
    # $1 path. A believable PEM body under an innocuous name.
    printf -- '-----BEGIN %s-----\nMIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Qu\n-----END %s-----\n' \
        'RSA PRIVATE KEY' 'RSA PRIVATE KEY' > "$1"
}

_putty_file() {
    printf '%s-2: ssh-rsa\nEncryption: none\n' 'PuTTY-User-Key-File' > "$1"
}

setup() {
    load_modules "system/manifest-security.sh" "git/manifest-git.sh"
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT/docs"
    cd "$MANIFEST_CLI_PROJECT_ROOT" || return 1
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    printf '46.10.0\n' > VERSION
    printf '.env\n.env.*.local\nmanifest.config.local.yaml\nid_rsa\n' > .gitignore
    git add VERSION .gitignore
    git commit -q -m "initial"
}

teardown() {
    cd /tmp || return 1
    rm -rf "$SCRATCH"
}

@test "positive control: an untracked PEM under an innocuous name is detected and named" {
    _pem_file deploy-secret.txt

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"deploy-secret.txt"* ]]
}

@test "positive control: a PuTTY key already TRACKED is detected (the pre-block case)" {
    _putty_file credentials.json
    git add credentials.json
    git commit -q -m "oops"

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"credentials.json"* ]]
}

@test "a modified tracked file that gains a key is detected" {
    printf 'config=1\n' > app.conf
    git add app.conf
    git commit -q -m "conf"
    _pem_file app.conf

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"app.conf"* ]]
}

@test "a clean repo passes, including prose that names private keys without a header" {
    printf '#!/bin/bash\n# never commit a private key; see docs/keys.md\n' > run.sh
    printf 'echo "BEGIN work"\n' > begin.sh

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 0 ]
}

@test "an IGNORED key is not reported: git add . would not stage it" {
    # The gitignore block is the prevention half; the scan covers what that
    # half lets through, not what it already stops.
    _pem_file id_rsa

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 0 ]
}

@test "outside a git repository the scan says so and passes rather than guessing" {
    rm -rf .git
    _pem_file deploy-secret.txt

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Not in a Git repository"* ]]
}

@test "manifest security reports key material as CRITICAL and exits 1" {
    _pem_file deploy-secret.txt

    run manifest_security --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"CRITICAL: Private key material"* ]]
    [[ "$output" == *"deploy-secret.txt"* ]]
    [[ "$output" == *"Security audit failed with 1 critical issue(s)"* ]]
}

@test "the ship's sweep commit refuses before git add . and leaves the index untouched" {
    _pem_file deploy-secret.txt
    printf 'harmless\n' > notes.sh
    local before
    before="$(git diff --cached --name-only)"

    run commit_changes "Auto-commit before Manifest process" "2026-11-07 00:00:00 UTC"

    [ "$status" -eq 1 ]
    [[ "$output" == *"deploy-secret.txt"* ]]
    [[ "$output" == *"refus"* ]]
    [ "$(git diff --cached --name-only)" = "$before" ]
    [ "$(git log --oneline | wc -l | tr -d ' ')" -eq 1 ]
}

@test "guard: commit_changes refuses on the pending set before its git add ." {
    # Ordering is the property: a scan after `git add .` would see a staged
    # key, and the §3 precedent says the sweep must never stage what it then
    # has to unstage. The refusing call is the one that passes `pending`;
    # the `tracked` call beside it only names, and the `declare -F` probe
    # above both carries no argument — so this matches exactly one call.
    #
    # QA (2026-11-07) showed the first cut of this guard could not go red:
    # `grep -n` emits in file order, so "first number < second" held for
    # any order. The property is WHICH line comes first, so that is what is
    # asserted; the count is the control that both lines were found.
    local module matches first
    module="$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    matches="$(awk '/^commit_changes\(\)/,/^}/' "$module" | grep -E 'check_key_material "[^"]*" pending|^[[:space:]]*git add \.')"

    [ "$(grep -c . <<< "$matches")" -eq 2 ]
    first="$(sed -n '1p' <<< "$matches")"
    [[ "$first" == *'check_key_material "'* ]]
}

@test "positive control: names git would quote (space, quote, non-ASCII) are scanned, not skipped" {
    # Porcelain v1 without -z prints these as "my file.txt" etc.; the quoted
    # string is not a path, and `grep -s` says nothing about a missing file.
    _pem_file 'my file.txt'
    _pem_file 'q"uote.txt'
    _pem_file 'café.txt'

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"my file.txt"* ]]
    [[ "$output" == *'q"uote.txt'* ]]
    [[ "$output" == *"café.txt"* ]]
}

@test "a staged rename does not desynchronise the pending parse" {
    # With -z a rename is two records, `XY dst\0src\0`; the parser must eat
    # exactly one source record, or the untracked key listed after it is
    # skipped (eat two) or `src` is scanned under a mangled name (eat none).
    printf 'plain\n' > a.txt
    git add a.txt
    git commit -q -m "a"
    git mv a.txt z-renamed.txt
    _pem_file zz-key.txt

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT" pending

    [ "$status" -eq 1 ]
    [[ "$output" == *"zz-key.txt"* ]]
    [ "$(grep -c 'private key material' <<< "$output")" -eq 1 ]
}

@test "a key written into an unmerged (UD) path is pending: git add . stages it as resolved" {
    # `UD`/`DU` match the deletion skip by shape, but the worktree file is
    # present and `git add .` stages it as the resolution; the ship can reach
    # commit_changes with a conflicted tree because sync_repository's pull
    # only warns on failure (§4). Steward, 2026-11-08.
    printf 'base\n' > f.txt
    git add f.txt
    git commit -q -m base
    git checkout -q -b theirs
    git rm -q f.txt
    git commit -q -m del
    git checkout -q -
    printf 'ours\n' > f.txt
    git commit -q -am ours
    git merge -q theirs 2>/dev/null || true
    _pem_file f.txt

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT" pending

    [ "$status" -eq 1 ]
    [[ "$output" == *"f.txt"* ]]
}

@test "set semantics: a key already in HEAD is tracked, not pending" {
    _putty_file credentials.json
    git add credentials.json
    git commit -q -m "oops"

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT" pending
    [ "$status" -eq 0 ]

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT" tracked
    [ "$status" -eq 1 ]
    [[ "$output" == *"credentials.json"* ]]
}

@test "set semantics: a modified tracked file whose key HEAD already carries stays tracked" {
    _pem_file app.conf
    git add app.conf
    git commit -q -m "fixture key"
    printf 'extra=1\n' >> app.conf

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT" pending
    [ "$status" -eq 0 ]

    run check_key_material "$MANIFEST_CLI_PROJECT_ROOT" tracked
    [ "$status" -eq 1 ]
}

@test "the ship's sweep commit names a tracked fixture key and still commits" {
    _putty_file credentials.json
    git add credentials.json
    git commit -q -m "fixture"
    printf 'harmless\n' > notes.sh

    run commit_changes "Auto-commit before Manifest process" "2026-11-07 00:00:00 UTC"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already in this repository's history"* ]]
    [[ "$output" == *"credentials.json"* ]]
    [[ "$output" != *"Commit refused"* ]]
    # initial + fixture + the sweep commit itself
    [ "$(git log --oneline | wc -l | tr -d ' ')" -eq 3 ]
}

@test "the ship's sweep commit refuses a tracked file that gains a key now" {
    printf 'config=1\n' > app.conf
    git add app.conf
    git commit -q -m "conf"
    _pem_file app.conf

    run commit_changes "Auto-commit before Manifest process" "2026-11-07 00:00:00 UTC"

    [ "$status" -eq 1 ]
    [[ "$output" == *"app.conf"* ]]
    [[ "$output" == *"Commit refused"* ]]
    # initial + conf, and nothing written by the refused sweep
    [ "$(git log --oneline | wc -l | tr -d ' ')" -eq 2 ]
}

@test "guard: the scanner's patterns do not match their own source text" {
    # The scan runs over this repo's tracked files on every ship; if the
    # module's own regex text matched the regex, every canonical ship would
    # refuse itself.
    run check_key_material "$TEST_REPO_ROOT"

    [ "$status" -eq 0 ]
}
