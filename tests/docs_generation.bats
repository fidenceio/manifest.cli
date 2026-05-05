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

@test "release templates do not contain generic filler bullets" {
    source "$TEST_REPO_ROOT/modules/docs/manifest-markdown-templates.sh"
    export PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_CANONICAL_REPO_SLUGS="example/repo"
    mkdir -p "$SCRATCH/modules" "$SCRATCH/scripts" "$SCRATCH/formula" "$SCRATCH/docs"
    touch "$SCRATCH/install-cli.sh" "$SCRATCH/scripts/manifest-cli-wrapper.sh" "$SCRATCH/formula/manifest.rb"
    git init -q "$SCRATCH"
    git -C "$SCRATCH" remote add origin "git@github.com:example/repo.git"

    run generate_release_notes_template "99.1.0" "2026-05-04 17:00:00 UTC" "minor"

    [ "$status" -eq 0 ]
    [[ "$output" != *"This release includes various improvements and bug fixes."* ]]
    [[ "$output" != *"Enhanced CLI functionality"* ]]
    [[ "$output" != *"General improvements and bug fixes"* ]]
}

@test "generate_release_notes writes concrete highlights and current commands" {
    export PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_CANONICAL_REPO_SLUGS="example/repo"
    mkdir -p "$SCRATCH/modules" "$SCRATCH/scripts" "$SCRATCH/formula" "$SCRATCH/docs"
    touch "$SCRATCH/install-cli.sh" "$SCRATCH/scripts/manifest-cli-wrapper.sh" "$SCRATCH/formula/manifest.rb"
    git init -q "$SCRATCH"
    git -C "$SCRATCH" remote add origin "git@github.com:example/repo.git"
    source "$TEST_REPO_ROOT/modules/docs/manifest-documentation.sh"

    changes="$SCRATCH/changes.md"
    cat > "$changes" <<'EOF'
## Highlights for v99.1.0

### Summary
- Notable changes: 1

### New Features
- Add fleet adoption planning
EOF

    run generate_release_notes "99.1.0" "2026-05-04 17:00:00 UTC" "minor" "$changes"

    [ "$status" -eq 0 ]
    release_file="$SCRATCH/docs/RELEASE_v99.1.0.md"
    grep -q "## Highlights for v99.1.0" "$release_file"
    grep -q -- "- Add fleet adoption planning" "$release_file"
    # Release notes carry only version-specific content; install/usage
    # boilerplate was removed so each release file stays focused on the
    # actual changes.
    ! grep -q "## Installation" "$release_file"
    ! grep -q "## Usage" "$release_file"
    ! grep -q "curl -fsSL https://raw.githubusercontent.com/fidenceio" "$release_file"
    ! grep -q "Enhanced CLI functionality" "$release_file"
    ! grep -q "manifest prep patch" "$release_file"
}
