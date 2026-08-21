#!/usr/bin/env bats

# PLAT-001: CRLF safety. Two halves:
#   1. get_current_version must strip CRs — a CRLF VERSION file (Windows
#      checkout, editor default) otherwise poisons every version string with
#      a trailing \r.
#   2. .gitattributes must exist and pin eol=lf for everything bash executes
#      or the CLI parses byte-wise, so a CRLF checkout cannot happen via git.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp || true
    rm -rf "$SCRATCH"
}

@test "get_current_version strips CRLF from VERSION" {
    printf '1.2.3\r\n' > "$SCRATCH/VERSION"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run get_current_version

    [ "$status" -eq 0 ]
    [ "$output" = "1.2.3" ]
}

@test "positive control: LF VERSION reads unchanged; missing VERSION stays unknown" {
    printf '9.8.7\n' > "$SCRATCH/VERSION"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run get_current_version
    [ "$status" -eq 0 ]
    [ "$output" = "9.8.7" ]

    rm "$SCRATCH/VERSION"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run get_current_version
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test ".gitattributes pins eol=lf for shell code, VERSION, and TSV inputs" {
    local attrs
    attrs="$(git -C "$TEST_REPO_ROOT" check-attr eol -- \
        VERSION \
        modules/core/manifest-core.sh \
        tests/helpers/setup.bash \
        tests/doc_review.bats \
        completions/_manifest \
        completions/manifest.fish \
        modules/catalog/version-handlers.tsv \
        formula/manifest.rb)"
    # Every listed file must resolve to eol: lf; grep -v prints any offender,
    # and refute turns "an offender exists" into a test failure.
    refute grep -v 'eol: lf$' <<<"$attrs"
}

@test ".gitattributes normalizes everything else as text=auto" {
    local attr
    attr="$(git -C "$TEST_REPO_ROOT" check-attr text -- README.md)"
    [ "$attr" = "README.md: text: auto" ]
}
