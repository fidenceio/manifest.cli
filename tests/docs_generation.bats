#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "git/manifest-git-changes.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "analyze_changes: empty input produces only the highlights header (no body)" {
    changes="$SCRATCH/changes.md"
    : > "$changes"

    run analyze_changes "99.0.0" "$changes"

    [ "$status" -eq 0 ]
    grep -qx '^## Highlights for v99.0.0$' "$changes"
    ! grep -q '^### ' "$changes"
    ! grep -q '^- ' "$changes"
    ! grep -q "No notable user-facing changes" "$changes"
}

@test "analyze_changes: cleaned bullets land under a single '### Changes' section" {
    changes="$SCRATCH/changes.md"
    cat > "$changes" <<'EOF'
- Add fleet adoption planning
- Fix release note generation
- Documentation review: Documentation impact appears low.
EOF

    run analyze_changes "99.1.0" "$changes"

    [ "$status" -eq 0 ]
    grep -qx '^## Highlights for v99.1.0$' "$changes"
    grep -qx '^### Changes$' "$changes"
    [ "$(grep -c '^### ' "$changes")" -eq 1 ]
    grep -qx '^- Add fleet adoption planning$' "$changes"
    grep -qx '^- Fix release note generation$' "$changes"
    # Trailing period stripped on the doc-review attachment line.
    grep -qx '^- Documentation review: Documentation impact appears low$' "$changes"
    # No counts table, no per-bucket headings.
    ! grep -q '^- Notable changes:' "$changes"
    ! grep -q '^### Bug Fixes$' "$changes"
    ! grep -q '^### New Features$' "$changes"
    ! grep -q '^### Improvements$' "$changes"
}

@test "analyze_changes: lowercase first letter is capitalized" {
    changes="$SCRATCH/changes.md"
    cat > "$changes" <<'EOF'
- add a thing
- fix another thing
EOF

    run analyze_changes "99.2.0" "$changes"

    [ "$status" -eq 0 ]
    grep -qx '^- Add a thing$' "$changes"
    grep -qx '^- Fix another thing$' "$changes"
}

@test "analyze_changes: heading and comment lines from raw input are dropped" {
    changes="$SCRATCH/changes.md"
    cat > "$changes" <<'EOF'
# stale heading
## another heading
- Real change
EOF

    run analyze_changes "99.3.0" "$changes"

    [ "$status" -eq 0 ]
    grep -qx '^- Real change$' "$changes"
    [ "$(grep -c '^- ' "$changes")" -eq 1 ]
}
