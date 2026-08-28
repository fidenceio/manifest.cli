#!/usr/bin/env bats
# bats file_tags=smoke

# The init preview must say what each file it would create is FOR.
#
# `manifest init repo --dry-run` listed eight scaffolded files. Six were bare
# filenames and two carried a parenthetical explanation, and the undescribed
# outliers included robots.txt and ai.txt — the two files a user reported finding
# in their repo afterwards without being able to say why they were there. Nothing
# in USER_GUIDE.md, COMMAND_REFERENCE.md, README.md or the runtime help named
# those two files at all, so the preview was the only place they could have been
# explained, and it did not explain them.
#
# This is written as a STRUCTURAL contract rather than a list of expected strings:
# it asserts that no "would create:" line lacks a gloss. A hand-kept list of
# filenames here would just be one more surface to drift (TRACKER §11), and a
# per-string assertion would go green the moment someone added a ninth file.
# Phrasing is free to change; a silent file is what fails.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$PROJ"
    export MANIFEST_CLI_PROJECT_ROOT="$PROJ"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Lines the preview says it would create, one per line.
would_create_lines() {
    manifest_init_repo --dry-run 2>/dev/null | grep -F 'would create:' || true
}

@test "init preview: every file it would create carries a purpose" {
    local lines
    lines="$(would_create_lines)"

    # Control: the extraction found something. Without this, a preview that
    # printed nothing at all — or a changed label — would satisfy the loop below
    # by vacuum, which is the absent-input-reads-as-pass shape this repo keeps
    # paying for.
    [ -n "$lines" ]
    local count
    count="$(printf '%s\n' "$lines" | grep -c .)"
    [ "$count" -ge 8 ]

    local line undescribed=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # A gloss is a parenthesised phrase after the filename.
        if ! grep -qE '\(.+\)' <<<"$line"; then
            undescribed+="  $line"$'\n'
        fi
    done <<< "$lines"

    if [ -n "$undescribed" ]; then
        printf 'preview names files without saying what they are for:\n%s' "$undescribed" >&2
        return 1
    fi
}

@test "init preview: the crawl-privacy files are named and explained" {
    # Not a phrasing assertion — these two specifically were the silent ones, and
    # a regression that dropped their gloss while keeping the others would still
    # satisfy a purely structural check if they were also dropped from the list.
    local lines
    lines="$(would_create_lines)"

    grep -F 'robots.txt' <<<"$lines" | grep -qE '\(.+\)'
    grep -F 'ai.txt' <<<"$lines" | grep -qE '\(.+\)'
}

@test "purpose helper: never returns an empty string, even for an unknown file" {
    # The preview interpolates this directly, so an empty return would print
    # "would create:  thing   ()" — a gloss that discloses nothing while passing
    # a naive presence check.
    run _manifest_scaffold_purpose "some-file-nobody-added-yet.txt"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "purpose helper: each known scaffold file gets a distinct purpose" {
    local f purposes=""
    for f in VERSION README.md CHANGELOG.md .gitignore robots.txt ai.txt \
             docs/ scripts/run-tests.sh .env.example manifest.config.local.yaml; do
        purposes+="$(_manifest_scaffold_purpose "$f")"$'\n'
    done

    local total distinct
    total="$(printf '%s' "$purposes" | grep -c .)"
    distinct="$(printf '%s' "$purposes" | sort -u | grep -c .)"
    [ "$total" -eq 10 ]
    # All ten differ: a copy-paste that gave two files the same description would
    # read as an explanation while explaining one of them wrongly.
    [ "$distinct" -eq "$total" ]
}
