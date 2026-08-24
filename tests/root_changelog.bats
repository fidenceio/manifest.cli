#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "docs/manifest-documentation.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_DOCS_RETAIN
}

# Write a changes_file shaped like analyze_changes output so the prepend
# helper has a body to extract.
seed_changes_file() {
    local file="$1"
    local version="$2"
    local body="${3:-### Summary
- Notable changes: 1

### Documentation
- Add fleet adoption planning}"

    cat > "$file" <<EOF
## Highlights for v${version}

${body}
EOF
}

# -----------------------------------------------------------------------------
# _manifest_build_changelog_entry
# -----------------------------------------------------------------------------

@test "build entry: extracts body, formats Keep-a-Changelog header" {
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"

    run _manifest_build_changelog_entry "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"
    [ "$status" -eq 0 ]
    grep -qE '^## \[46\.13\.6\] - 2026-05-05$' <<<"${output%%$'\n'*}"
    echo "$output" | grep -q '^\*\*Release Type:\*\* Patch$'
    echo "$output" | grep -q '^### Summary$'
    echo "$output" | grep -q '^- Notable changes: 1$'
    echo "$output" | grep -q '^### Documentation$'
    # No leftover scaffolding from analyze_changes header.
    refute grep -q '^## Highlights for v' <<<"$output"
}

@test "build entry: empty changes file → release-type line carries the no-changes suffix" {
    local empty="${SCRATCH}/empty.md"
    : > "$empty"

    run _manifest_build_changelog_entry "1.0.0" "2026-05-05 12:00:00 UTC" "minor" "$empty"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^## \[1\.0\.0\] - 2026-05-05$'
    echo "$output" | grep -qx '^\*\*Release Type:\*\* Minor — no user-facing changes\.$'
    # No filler Summary section, no leftover narrative paragraph.
    refute grep -q '^### ' <<<"$output"
    refute grep -q "No notable user-facing changes were detected" <<<"$output"
}

# -----------------------------------------------------------------------------
# prepend_root_changelog_entry
# -----------------------------------------------------------------------------

@test "prepend: creates root CHANGELOG.md with header on first ship" {
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"

    run prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"
    [ "$status" -eq 0 ]
    [ -f "${SCRATCH}/CHANGELOG.md" ]
    local first
    first="$(head -1 "${SCRATCH}/CHANGELOG.md")"
    [ "$first" = "# Changelog" ]
    grep -q '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md"
}

@test "prepend: writes via temp+rename and leaves no temp behind (TRACKER §9.23)" {
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"

    run prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"
    [ "$status" -eq 0 ]
    # The assembly temp is created beside the target, so a leftover would be a
    # tracked-directory turd the ship's own sweep would then have to remove.
    run bash -c "ls ${SCRATCH}/CHANGELOG.md.* 2>/dev/null"
    [ -z "$output" ]
}

@test "prepend: an existing CHANGELOG.md keeps its permission bits (TRACKER §9.23)" {
    # mktemp creates 0600. Switching from an in-place redirect to temp+rename
    # must not quietly make a published, tracked file owner-readable only.
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"
    printf '# Changelog\n\n## [46.0.0] - 2026-01-01\n\n- old\n' > "${SCRATCH}/CHANGELOG.md"
    chmod 644 "${SCRATCH}/CHANGELOG.md"

    run prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"
    [ "$status" -eq 0 ]
    [ "$(manifest_file_mode "${SCRATCH}/CHANGELOG.md")" = "644" ]
    # Positive control: the write actually happened.
    grep -q '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md"
}

@test "prepend: a new CHANGELOG.md is created readable, not 0600 (TRACKER §9.23)" {
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"

    run prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"
    [ "$status" -eq 0 ]
    [ "$(manifest_file_mode "${SCRATCH}/CHANGELOG.md")" != "600" ]
    grep -q '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md"
}

@test "prepend: subsequent ships add new entry above existing ones" {
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"
    prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"

    seed_changes_file "$changes" "46.13.7"
    prepend_root_changelog_entry "$SCRATCH" "46.13.7" "2026-05-06 12:00:00 UTC" "patch" "$changes"

    grep -q '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[46\.13\.7\]' "${SCRATCH}/CHANGELOG.md"
    local p_new p_old
    p_new=$(grep -n '^## \[46\.13\.7\]' "${SCRATCH}/CHANGELOG.md" | cut -d: -f1)
    p_old=$(grep -n '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md" | cut -d: -f1)
    [ "$p_new" -lt "$p_old" ]
    # Single # Changelog header (no duplication).
    [ "$(grep -c '^# Changelog$' "${SCRATCH}/CHANGELOG.md")" -eq 1 ]
}

@test "prepend: re-shipping the same version replaces the existing entry, not duplicates" {
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6" "### Summary
- First take"
    prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"

    seed_changes_file "$changes" "46.13.6" "### Summary
- Updated body"
    prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"

    [ "$(grep -c '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md")" -eq 1 ]
    grep -q "Updated body" "${SCRATCH}/CHANGELOG.md"
    refute grep -q "First take" "${SCRATCH}/CHANGELOG.md"
}

@test "docs index: inline version and updated metadata are both refreshed" {
    mkdir -p "${SCRATCH}/docs"
    cat > "${SCRATCH}/docs/INDEX.md" <<'EOF'
# Manifest CLI Documentation

**Version:** 1.0.0 | **Updated:** 2026-05-08
EOF
    manifest_is_canonical_repo() { return 0; }

    run generate_docs_index "1.2.3"

    [ "$status" -eq 0 ]
    grep -qxF "**Version:** 1.2.3 | **Updated:** $(date -u '+%Y-%m-%d')" "${SCRATCH}/docs/INDEX.md"
}

@test "prepend: legacy auto-generated content is replaced, not preserved" {
    cat > "${SCRATCH}/CHANGELOG.md" <<'EOF'
# Old Auto-Generated Changelog

Generated by Manifest CLI v45.0.0
EOF
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"

    prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"

    refute grep -q "Generated by Manifest CLI v45.0.0" "${SCRATCH}/CHANGELOG.md"
    local first
    first="$(head -1 "${SCRATCH}/CHANGELOG.md")"
    [ "$first" = "# Changelog" ]
    grep -q '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md"
}

@test "prepend: hand-crafted root content is preserved unchanged" {
    cat > "${SCRATCH}/CHANGELOG.md" <<'EOF'
# Changelog

## [45.0.0] - 2026-01-01

**Release Type:** Major

### Notes
Hand-crafted entry.
EOF
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "46.13.6"

    prepend_root_changelog_entry "$SCRATCH" "46.13.6" "2026-05-05 12:00:00 UTC" "patch" "$changes"

    grep -q "Hand-crafted entry" "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[45\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[46\.13\.6\]' "${SCRATCH}/CHANGELOG.md"
}

# -----------------------------------------------------------------------------
# _manifest_prune_root_changelog
# -----------------------------------------------------------------------------

@test "prune: 'N versions' keeps top N sections, drops older" {
    local changes="${SCRATCH}/changes.md"
    local v
    for v in 1.0.0 2.0.0 3.0.0 4.0.0 5.0.0; do
        seed_changes_file "$changes" "$v"
        prepend_root_changelog_entry "$SCRATCH" "$v" "2026-05-0${v%%.*} 12:00:00 UTC" "minor" "$changes"
    done

    # Now apply 3-version retention.
    _manifest_prune_root_changelog "${SCRATCH}/CHANGELOG.md" "3 versions"

    grep -q '^## \[5\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[4\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[3\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    refute grep -q '^## \[2\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    refute grep -q '^## \[1\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
}

@test "prune: revision sections (X.Y.Z.R) count toward the retention budget" {
    # A `revision` ship writes "## [X.Y.Z.R]". While the section pattern required
    # exactly three segments those headings were not recognized as section starts,
    # so revision entries escaped retention entirely: never counted, never pruned.
    local changes="${SCRATCH}/changes.md"
    local v
    for v in 1.0.0 1.0.0.1 1.0.0.2 2.0.0 3.0.0; do
        seed_changes_file "$changes" "$v"
        prepend_root_changelog_entry "$SCRATCH" "$v" "2026-05-0${v%%.*} 12:00:00 UTC" "revision" "$changes"
    done

    _manifest_prune_root_changelog "${SCRATCH}/CHANGELOG.md" "2 versions"

    # Newest two survive; everything older goes, revision entries included.
    # Negative assertions go through `run` deliberately: a bare `! grep …` is
    # exempt from errexit, so unless it is the test's final command it cannot
    # fail the test — and the absorbed-section bug this test exists to catch
    # shows up precisely in the middle assertions.
    grep -q '^## \[3\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[2\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    run grep -q '^## \[1\.0\.0\.2\]' "${SCRATCH}/CHANGELOG.md"
    [ "$status" -ne 0 ]
    run grep -q '^## \[1\.0\.0\.1\]' "${SCRATCH}/CHANGELOG.md"
    [ "$status" -ne 0 ]
    run grep -q '^## \[1\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    [ "$status" -ne 0 ]
}

@test "prune: a revision section is retained when it is inside the budget" {
    local changes="${SCRATCH}/changes.md"
    local v
    for v in 1.0.0 2.0.0 2.0.0.1; do
        seed_changes_file "$changes" "$v"
        prepend_root_changelog_entry "$SCRATCH" "$v" "2026-05-0${v%%.*} 12:00:00 UTC" "revision" "$changes"
    done

    _manifest_prune_root_changelog "${SCRATCH}/CHANGELOG.md" "2 versions"

    grep -q '^## \[2\.0\.0\.1\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[2\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    run grep -q '^## \[1\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    [ "$status" -ne 0 ]
}

@test "docs index: a revision version refreshes the inline reference" {
    mkdir -p "${SCRATCH}/docs"
    cat > "${SCRATCH}/docs/INDEX.md" <<'EOF'
# Manifest CLI Documentation

**Version:** 20.1.0 | **Updated:** 2026-05-08

Current release is `20.1.0`.
EOF
    manifest_is_canonical_repo() { return 0; }

    run generate_docs_index "20.1.0.1"

    [ "$status" -eq 0 ]
    grep -qF 'Current release is `20.1.0.1`.' "${SCRATCH}/docs/INDEX.md"
}

@test "docs index: an inline reference already at a revision version is refreshed again" {
    # The regression that motivated this: once the file carried X.Y.Z.R, the
    # three-segment scan stopped matching it and every later ship was a no-op.
    mkdir -p "${SCRATCH}/docs"
    cat > "${SCRATCH}/docs/INDEX.md" <<'EOF'
# Manifest CLI Documentation

**Version:** 20.1.0.1 | **Updated:** 2026-05-08

Current release is `20.1.0.1`.
EOF
    manifest_is_canonical_repo() { return 0; }

    run generate_docs_index "20.1.0.2"

    [ "$status" -eq 0 ]
    grep -qF 'Current release is `20.1.0.2`.' "${SCRATCH}/docs/INDEX.md"
}

@test "prune: 'off' keeps every entry" {
    local changes="${SCRATCH}/changes.md"
    local v
    for v in 1.0.0 2.0.0 3.0.0; do
        seed_changes_file "$changes" "$v"
        prepend_root_changelog_entry "$SCRATCH" "$v" "2026-05-0${v%%.*} 12:00:00 UTC" "minor" "$changes"
    done

    _manifest_prune_root_changelog "${SCRATCH}/CHANGELOG.md" "off"

    grep -q '^## \[1\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[2\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    grep -q '^## \[3\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
}

@test "prune: 'N days' keeps entries newer than cutoff" {
    # Build a CHANGELOG.md by hand with explicit dates so we can reason
    # about the cutoff without depending on prepend timestamps.
    cat > "${SCRATCH}/CHANGELOG.md" <<EOF
# Changelog

## [3.0.0] - $(date -u '+%Y-%m-%d')

**Release Type:** Minor

Recent.

## [2.0.0] - 2026-04-01

**Release Type:** Minor

Mid.

## [1.0.0] - 2025-01-01

**Release Type:** Major

Old.
EOF

    _manifest_prune_root_changelog "${SCRATCH}/CHANGELOG.md" "30 days"

    grep -q '^## \[3\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    refute grep -q '^## \[2\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
    refute grep -q '^## \[1\.0\.0\]' "${SCRATCH}/CHANGELOG.md"
}

@test "prune: malformed retain spec leaves file untouched" {
    local changes="${SCRATCH}/changes.md"
    seed_changes_file "$changes" "1.0.0"
    prepend_root_changelog_entry "$SCRATCH" "1.0.0" "2026-05-05 12:00:00 UTC" "minor" "$changes"

    local before
    before="$(cat "${SCRATCH}/CHANGELOG.md")"

    run _manifest_prune_root_changelog "${SCRATCH}/CHANGELOG.md" "banana"
    [ "$status" -eq 0 ]
    [ "$(cat "${SCRATCH}/CHANGELOG.md")" = "$before" ]
}

# -----------------------------------------------------------------------------
# _manifest_parse_retention (moved from cleanup-docs)
# -----------------------------------------------------------------------------

@test "parse retention: '10 versions' → versions / 10" {
    local k v
    _manifest_parse_retention "10 versions" k v
    [ "$k" = "versions" ]
    [ "$v" = "10" ]
}

@test "parse retention: '30 days' → days / 30" {
    local k v
    _manifest_parse_retention "30 days" k v
    [ "$k" = "days" ]
    [ "$v" = "30" ]
}

@test "parse retention: 'off' / empty → off" {
    local k v
    _manifest_parse_retention "off" k v
    [ "$k" = "off" ]
    _manifest_parse_retention "" k v
    [ "$k" = "off" ]
}

@test "parse retention: malformed input returns 1" {
    local k v
    run _manifest_parse_retention "ten versions" k v
    [ "$status" -ne 0 ]
    run _manifest_parse_retention "5 weeks" k v
    [ "$status" -ne 0 ]
}
