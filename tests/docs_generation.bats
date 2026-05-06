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

@test "analyze_changes reports no notable changes instead of empty sections" {
    changes="$SCRATCH/changes.md"
    : > "$changes"

    run analyze_changes "99.0.0" "$changes"

    [ "$status" -eq 0 ]
    grep -q "No notable user-facing changes were detected" "$changes"
    ! grep -q "### Improvements" "$changes"
    ! grep -q "### New Features" "$changes"
}

@test "analyze_changes keeps concrete categorized change bullets" {
    changes="$SCRATCH/changes.md"
    cat > "$changes" <<'EOF'
- Add fleet adoption planning
- Fix release note generation
- Documentation review: Documentation impact appears low.
EOF

    run analyze_changes "99.1.0" "$changes"

    [ "$status" -eq 0 ]
    grep -q "Notable changes: 3" "$changes"
    grep -q "### New Features" "$changes"
    grep -q -- "- Add fleet adoption planning" "$changes"
    grep -q "### Bug Fixes" "$changes"
    grep -q -- "- Fix release note generation" "$changes"
    grep -q "### Documentation" "$changes"
    grep -q -- "- Documentation review: Documentation impact appears low." "$changes"
}
