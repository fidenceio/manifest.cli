#!/usr/bin/env bats

load 'helpers/setup'

# Sibling of tests/docs_index_preserve.bats, same defect class on a worse file.
#
# update_readme_version called manifest_is_legacy_generated_readme and, on a
# match, handed the file to create_default_readme — a whole-file `cat >`. The
# predicate's three tests were content phrases:
#
#   "This project uses [Manifest CLI]"
#   "This repo is versioned and documented by [Manifest CLI]"
#   "| **CLI Version** |"
#
# The first two read exactly like an attribution line a human writes by hand,
# and the third like a row in someone's own version table. So crediting the tool
# in your README, or describing your version in a table, was enough to have your
# repo's front page replaced with a template.
#
# The contract pinned here: a managed block is the ONLY thing that authorises a
# write to an existing README.

setup() {
    load_modules "core/manifest-config.sh" "core/manifest-init.sh" "docs/manifest-documentation.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_PROJECT_ROOT

    # Every test here is about a repo Manifest MANAGES; the canonical repo takes
    # a different branch entirely.
    manifest_is_canonical_repo() { return 1; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# A README a human wrote, which happens to credit the tool that versions it.
curated_readme_crediting_manifest() {
    cat > "${SCRATCH}/README.md" <<'EOF'
# Ingest Service

The ingest service normalises upstream feeds before they reach the warehouse.

## Local development

    make dev

## Deploying

Deploys are cut from `main`. This project uses [Manifest CLI](https://github.com/fidenceio/manifest.cli)
to manage versions and changelogs.
EOF
}

# -----------------------------------------------------------------------------
# The defect
# -----------------------------------------------------------------------------

@test "readme: crediting Manifest in prose does not authorise replacing the README" {
    curated_readme_crediting_manifest

    run update_readme_version "9.9.9" "2026-01-01 00:00:00 UTC"
    [ "$status" -eq 0 ]

    grep -Fq "# Ingest Service" "${SCRATCH}/README.md"
    grep -Fq "normalises upstream feeds" "${SCRATCH}/README.md"
    grep -Fq "## Deploying" "${SCRATCH}/README.md"
}

@test "readme: a hand-written version table does not authorise replacing the README" {
    cat > "${SCRATCH}/README.md" <<'EOF'
# Ingest Service

| Property | Value |
|----------|-------|
| **CLI Version** | 3.1.0 |

## Local development

    make dev
EOF

    run update_readme_version "9.9.9" "2026-01-01 00:00:00 UTC"
    [ "$status" -eq 0 ]

    grep -Fq "# Ingest Service" "${SCRATCH}/README.md"
    grep -Fq "## Local development" "${SCRATCH}/README.md"
}

@test "readme: preserving means no write at all, not a rewrite" {
    curated_readme_crediting_manifest
    local before
    before="$(cksum < "${SCRATCH}/README.md")"

    run update_readme_version "9.9.9" "2026-01-01 00:00:00 UTC"
    [ "$status" -eq 0 ]

    [ "$(cksum < "${SCRATCH}/README.md")" = "$before" ]
}

# -----------------------------------------------------------------------------
# Positive controls — without these, the tests above pass whenever the fixture
# simply fails to reach update_readme_version at all.
# -----------------------------------------------------------------------------

@test "positive control: a README WITH the managed block is still updated in place" {
    cat > "${SCRATCH}/README.md" <<EOF
# Ingest Service

${MANIFEST_CLI_README_VERSION_START}
old block content
${MANIFEST_CLI_README_VERSION_END}

Hand-written paragraph that must also survive.
EOF

    run update_readme_version "9.9.9" "2026-01-01 00:00:00 UTC"
    [ "$status" -eq 0 ]

    grep -Fq "9.9.9" "${SCRATCH}/README.md"
    refute grep -Fq "old block content" "${SCRATCH}/README.md"
    grep -Fq "Hand-written paragraph that must also survive." "${SCRATCH}/README.md"
}

@test "positive control: a missing README is reported, not invented" {
    [ ! -f "${SCRATCH}/README.md" ]

    run update_readme_version "9.9.9" "2026-01-01 00:00:00 UTC"
    [ "$status" -eq 0 ]

    [ ! -f "${SCRATCH}/README.md" ]
}
