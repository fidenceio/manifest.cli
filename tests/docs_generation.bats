#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "git/manifest-git-changes.sh" "docs/manifest-documentation.sh"
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

prepare_docs_site_repo() {
    mkdir -p "$SCRATCH/repo/docs"
    printf '# Test Repo\n' > "$SCRATCH/repo/README.md"
    printf '# Changelog\n' > "$SCRATCH/repo/CHANGELOG.md"
    printf '# Index\n' > "$SCRATCH/repo/docs/INDEX.md"
}

@test "docs site generation writes managed Jekyll source without build artifacts" {
    prepare_docs_site_repo

    PROJECT_ROOT="$SCRATCH/repo" \
    MANIFEST_CLI_DOCS_GENERATE_SITE=true \
    MANIFEST_CLI_DOCS_GENERATE_SITE_WORKFLOW=true \
    MANIFEST_CLI_DOCS_SITE_SOURCE_DIR="docs-site" \
    run _manifest_docs_generate_site "99.4.0" "2026-05-18 12:00:00 UTC" "repo" "$SCRATCH/repo" "$SCRATCH/repo/docs"

    [ "$status" -eq 0 ]
    grep -q "Managed by Manifest CLI docs site generation" "$SCRATCH/repo/docs-site/_config.yml"
    grep -q "Managed by Manifest CLI docs site generation" "$SCRATCH/repo/docs-site/index.md"
    grep -q "Managed by Manifest CLI docs site generation" "$SCRATCH/repo/docs-site/_layouts/default.html"
    grep -q "Managed by Manifest CLI docs site generation" "$SCRATCH/repo/docs-site/assets/css/manifest.css"
    grep -q "_site/" "$SCRATCH/repo/docs-site/.gitignore"
    [ -f "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml" ]
    grep -q ".manifest-pages-src" "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    grep -q "cp README.md" "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    # Pages-availability detection guard: build/deploy run only when Pages is enabled,
    # so the workflow goes green-by-skipping on repos without Pages (e.g. private repos
    # on a plan tier without Pages) and auto-activates once Pages is enabled.
    grep -q "Detect GitHub Pages availability" "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    grep -q "needs.build.outputs.pages_enabled == 'true'" "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    # Current pinned action versions (kept in lockstep with the working public-repo copy).
    grep -q "actions/configure-pages@v6" "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    grep -q "actions/deploy-pages@v5" "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    # Regression guard: the GitHub expression and $GITHUB_OUTPUT must survive the
    # generator heredoc as literals, NOT be expanded to empty at generation time.
    grep -qF 'repos/${{ github.repository }}/pages' "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    grep -qF '>> "$GITHUB_OUTPUT"' "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml"
    [ ! -d "$SCRATCH/repo/docs-site/_site" ]
    [ ! -d "$SCRATCH/repo/docs-site/.jekyll-cache" ]
    [ ! -d "$SCRATCH/repo/docs-site/.bundle" ]
}

@test "docs site generation refuses unmanaged collisions" {
    prepare_docs_site_repo
    mkdir -p "$SCRATCH/repo/docs-site"
    printf 'user-owned\n' > "$SCRATCH/repo/docs-site/index.md"

    PROJECT_ROOT="$SCRATCH/repo" \
    MANIFEST_CLI_DOCS_GENERATE_SITE=true \
    run _manifest_docs_generate_site "99.5.0" "2026-05-18 12:00:00 UTC" "repo" "$SCRATCH/repo" "$SCRATCH/repo/docs"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to overwrite unmanaged docs site file"* ]]
    [ "$(cat "$SCRATCH/repo/docs-site/index.md")" = "user-owned" ]
}

@test "docs site generation can request GitHub Pages workflow publishing through gh" {
    prepare_docs_site_repo
    git -C "$SCRATCH/repo" init -q
    git -C "$SCRATCH/repo" remote add origin git@github.com:example/docs-site-test.git
    gh_stub_install "$SCRATCH/gh"

    PROJECT_ROOT="$SCRATCH/repo" \
    MANIFEST_CLI_DOCS_GENERATE_SITE=true \
    MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES=true \
    run _manifest_docs_generate_site "99.6.0" "2026-05-18 12:00:00 UTC" "repo" "$SCRATCH/repo" "$SCRATCH/repo/docs"

    [ "$status" -eq 0 ]
    grep -q $'\tapi\t--method\tPOST\trepos/example/docs-site-test/pages\t-f\tbuild_type=workflow' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "docs site generation never fails when GitHub Pages cannot be enabled" {
    prepare_docs_site_repo
    git -C "$SCRATCH/repo" init -q
    git -C "$SCRATCH/repo" remote add origin git@github.com:example/private-docs-test.git
    gh_stub_install "$SCRATCH/gh"

    PROJECT_ROOT="$SCRATCH/repo" \
    MANIFEST_CLI_DOCS_GENERATE_SITE=true \
    MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES=true \
    MANIFEST_CLI_GH_STUB_EXIT=1 \
    MANIFEST_CLI_GH_STUB_STDERR="HTTP 422: Your current plan does not support GitHub Pages for this repository." \
    run _manifest_docs_generate_site "99.7.0" "2026-05-18 12:00:00 UTC" "repo" "$SCRATCH/repo" "$SCRATCH/repo/docs"

    # Pages enablement failed, but the run still succeeds and the site is committed.
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/repo/.github/workflows/manifest-docs-pages.yml" ]
    [[ "$output" == *"GitHub Pages was not enabled"* ]]
    [[ "$output" == *"does not include Pages for private repositories"* ]]
}
