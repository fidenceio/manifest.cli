#!/usr/bin/env bats

load 'helpers/setup'

# generate_docs_index used to decide a docs index was "legacy generated" from
# its TITLE alone and then replace the whole file with an 11-line stub.
# manifest_is_legacy_generated_index matched either "<!-- Manifest CLI v" or the
# literal "# Manifest CLI Documentation" — and the marker half was only ever
# written by the CANONICAL-repo template, never by write_external_docs_index.
# So for every repo Manifest manages, the title match was the only reachable
# test, which made the branch's only reachable behaviour "delete the owner's
# hand-written content because they used the obvious title".
#
# The contract pinned here: a docs index carrying no Manifest-managed block is
# PRESERVED, whatever it is titled and whatever marker it carries. A managed
# block is the only thing that authorises a write.

setup() {
    load_modules "core/manifest-config.sh" "docs/manifest-documentation.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_PROJECT_ROOT
    mkdir -p "${SCRATCH}/docs"

    # Every test here is about a repo Manifest MANAGES; the canonical repo takes
    # a different branch entirely. Pin it rather than letting the filesystem
    # signature fallback in manifest_is_canonical_repo decide from the fixture.
    manifest_is_canonical_repo() { return 1; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# A docs index a human wrote, titled the way anyone would title it — and the way
# Manifest's own canonical template titles it.
curated_index() {
    cat > "${SCRATCH}/docs/INDEX.md" <<'EOF'
# Manifest CLI Documentation

Hand-written orientation paragraph the owner of this repo wrote.

## Architecture

| Component | Owner    |
| --------- | -------- |
| ingest    | platform |

## Runbooks

- [On-call](RUNBOOK.md)
EOF
}

managed_index() {
    cat > "${SCRATCH}/docs/INDEX.md" <<EOF
# Some Repo Documentation

${MANIFEST_CLI_INDEX_METADATA_START}
**Version:** 1.0.0 | **Updated:** 2026-01-01
${MANIFEST_CLI_INDEX_METADATA_END}

Hand-written paragraph that must also survive.

## Current Release
${MANIFEST_CLI_INDEX_CURRENT_RELEASE_START}
| Document | Description |
| -------- | ----------- |
| [CHANGELOG.md](../CHANGELOG.md) | All releases, newest first |
${MANIFEST_CLI_INDEX_CURRENT_RELEASE_END}
EOF
}

# -----------------------------------------------------------------------------
# The defect
# -----------------------------------------------------------------------------

@test "docs index: a curated index titled like the generated one is preserved" {
    curated_index

    run generate_docs_index "9.9.9"
    [ "$status" -eq 0 ]

    grep -Fq "Hand-written orientation paragraph" "${SCRATCH}/docs/INDEX.md"
    grep -Fq "## Architecture" "${SCRATCH}/docs/INDEX.md"
    grep -Fq "## Runbooks" "${SCRATCH}/docs/INDEX.md"
    grep -Fq "[On-call](RUNBOOK.md)" "${SCRATCH}/docs/INDEX.md"
}

@test "docs index: a curated index carrying the legacy marker is preserved too" {
    curated_index
    printf '\n<!-- Manifest CLI v1.0.0 -->\n' >> "${SCRATCH}/docs/INDEX.md"

    run generate_docs_index "9.9.9"
    [ "$status" -eq 0 ]

    grep -Fq "Hand-written orientation paragraph" "${SCRATCH}/docs/INDEX.md"
    grep -Fq "## Architecture" "${SCRATCH}/docs/INDEX.md"
}

@test "docs index: preserving means no write at all, not a rewrite" {
    curated_index
    local before
    before="$(cksum < "${SCRATCH}/docs/INDEX.md")"

    run generate_docs_index "9.9.9"
    [ "$status" -eq 0 ]

    [ "$(cksum < "${SCRATCH}/docs/INDEX.md")" = "$before" ]
}

# -----------------------------------------------------------------------------
# Positive controls — without these, the tests above pass whenever the fixture
# simply fails to reach generate_docs_index at all.
# -----------------------------------------------------------------------------

@test "positive control: an index WITH managed blocks is still updated in place" {
    managed_index

    run generate_docs_index "9.9.9"
    [ "$status" -eq 0 ]

    grep -Fq "**Version:** 9.9.9" "${SCRATCH}/docs/INDEX.md"
    refute grep -Fq "**Version:** 1.0.0" "${SCRATCH}/docs/INDEX.md"
    # The owner's prose between the managed blocks is not collateral.
    grep -Fq "Hand-written paragraph that must also survive." "${SCRATCH}/docs/INDEX.md"
}

@test "positive control: a missing index is still created with managed blocks" {
    [ ! -f "${SCRATCH}/docs/INDEX.md" ]

    run generate_docs_index "9.9.9"
    [ "$status" -eq 0 ]

    [ -f "${SCRATCH}/docs/INDEX.md" ]
    grep -Fq "$MANIFEST_CLI_INDEX_METADATA_START" "${SCRATCH}/docs/INDEX.md"
    grep -Fq "**Version:** 9.9.9" "${SCRATCH}/docs/INDEX.md"
}
