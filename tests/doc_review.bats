#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh" "git/manifest-git-changes.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH"
    cd "$SCRATCH"

    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit -q --allow-empty -m "initial"

    unset MANIFEST_CLI_DOC_REVIEW
    unset MANIFEST_CLI_DOC_REVIEW_PROVIDER
    unset MANIFEST_CLI_DOC_REVIEW_COMMAND
    unset MANIFEST_CLI_DOC_REVIEW_REQUIRED
    unset MANIFEST_CLI_DOC_REVIEW_OUTPUTS
    # Default report_dir is empty (writes to .git/manifest-doc-review/, never committed).
    # Most tests in this file exercise the opt-in committed-report path; explicitly
    # set the working-tree directory here so those assertions hold. The dedicated
    # default-behavior test below unsets the variable.
    export MANIFEST_CLI_DOC_REVIEW_REPORT_DIR="docs/documentation-reviews"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "documentation review detects command-surface changes without docs" {
    mkdir -p modules/core
    echo "# change" > modules/core/manifest-core.sh

    run manifest_smart_documentation_review "Add command"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Smart documentation review"* ]]
    [[ "$output" == *"Documentation impact detected; review docs before committing."* ]]
    report="$(ls docs/documentation-reviews/DOC_REVIEW_*.md)"
    [ -f "$report" ]
    grep -q "command_surface_changed: 1" "$report"
    grep -q "# Documentation Review" "$report"
}

@test "documentation review recognizes docs changes alongside runtime changes" {
    mkdir -p modules/fleet docs
    echo "# change" > modules/fleet/manifest-fleet-plan.sh
    echo "# Docs" > docs/COMMAND_REFERENCE.md

    run manifest_smart_documentation_review "Add fleet plan"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Documentation impact detected; documentation changes are present."* ]]
    report="$(ls docs/documentation-reviews/DOC_REVIEW_*.md)"
    grep -q "docs_changed: 1" "$report"
    grep -q "runtime_changed: 1" "$report"
}

@test "commit_changes commits documentation review report and commit body" {
    mkdir -p modules/core docs
    echo "# change" > modules/core/manifest-core.sh
    echo "# Docs" > docs/COMMAND_REFERENCE.md

    run commit_changes "Add command docs" ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Smart documentation review"* ]]
    [ "$(git log -1 --pretty=%s)" = "Add command docs" ]
    report="$(ls docs/documentation-reviews/DOC_REVIEW_*.md)"
    [ -f "$report" ]
    git log -1 --pretty=%B | grep -q "Documentation review:"
    git log -1 --pretty=%B | grep -q "Documentation files changed: 1"
    git show --name-only --pretty= HEAD | grep -q "modules/core/manifest-core.sh"
    git show --name-only --pretty= HEAD | grep -q "docs/documentation-reviews/DOC_REVIEW_"
    ! git show --name-only --pretty= HEAD | grep -q ".git/manifest-doc-review/latest.md"
}

@test "documentation review release notes are included in git changes" {
    mkdir -p modules/core docs
    echo "# change" > modules/core/manifest-core.sh
    echo "# Docs" > docs/COMMAND_REFERENCE.md
    commit_changes "Add command docs" "" >/dev/null

    run get_git_changes "1.0.0"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Documentation review:"* ]]
    [[ "$output" == *"documentation files"* ]]
}

@test "auto-commit release changes are summarized instead of filtered out" {
    git tag v0.9.0
    mkdir -p modules/recipe recipes/builtin docs/contracts tests
    echo "# recipe module" > modules/recipe/manifest-recipe.sh
    echo "id: manifest.builtin.ship.repo.patch" > recipes/builtin/manifest.builtin.ship.repo.patch.yaml
    echo "{}" > docs/contracts/recipe.schema.json
    echo "# tests" > tests/recipe.bats
    git add modules/recipe/manifest-recipe.sh recipes/builtin/manifest.builtin.ship.repo.patch.yaml docs/contracts/recipe.schema.json tests/recipe.bats
    git commit -q -m "Auto-commit before Manifest process (4 files: modules/recipe/manifest-recipe.sh, ...) [TS: 2026-05-06 15:19:55 UTC]"

    run get_git_changes "1.0.0"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Add recipe-backed workflow definitions and recipe introspection support"* ]]
    [[ "$output" == *"Add regression coverage for the changed CLI workflow"* ]]
    [[ "$output" != *"Auto-commit before Manifest process"* ]]
}

@test "auto-commit GitHub release and preview work gets smart release notes" {
    git tag v0.9.0
    mkdir -p modules/workflow modules/core examples tests
    echo "# orchestrator" > modules/workflow/manifest-orchestrator.sh
    echo "# ship" > modules/core/manifest-ship.sh
    echo "github:" > examples/manifest.config.yaml.example
    echo "# tests" > tests/github_actions_status.bats
    git add modules/workflow/manifest-orchestrator.sh modules/core/manifest-ship.sh examples/manifest.config.yaml.example tests/github_actions_status.bats
    git commit -q -m "Auto-commit before Manifest process (4 files: modules/workflow/manifest-orchestrator.sh, ...) [TS: 2026-05-08 12:00:00 UTC]"

    run get_git_changes "1.0.0"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Add GitHub Release publishing support"* ]]
    [[ "$output" == *"Add smart ship preview summaries"* ]]
    [[ "$output" == *"Update release copy and configuration examples"* ]]
    [[ "$output" == *"Add regression coverage for the changed CLI workflow"* ]]
}

@test "root changelog auto-commit gets a descriptive release note" {
    git tag v0.9.0
    echo "# Changelog" > CHANGELOG.md
    git add CHANGELOG.md
    git commit -q -m "Auto-commit before Manifest process (CHANGELOG.md) [TS: 2026-05-06 16:21:44 UTC]"

    run get_git_changes "1.0.0"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Backfill and clarify release history in the root changelog"* ]]
    [[ "$output" != *"Update 1 files before release"* ]]
}

@test "commit_changes fails when required documentation provider fails" {
    mkdir -p modules/core
    echo "# change" > modules/core/manifest-core.sh
    failing_provider="$SCRATCH/fail-provider"
    {
        echo '#!/usr/bin/env bash'
        echo 'exit 7'
    } > "$failing_provider"
    chmod +x "$failing_provider"

    MANIFEST_CLI_DOC_REVIEW_PROVIDER=command \
    MANIFEST_CLI_DOC_REVIEW_COMMAND="$failing_provider" \
    MANIFEST_CLI_DOC_REVIEW_REQUIRED=true \
        run commit_changes "Add command" ""

    [ "$status" -ne 0 ]
    [[ "$output" == *"Documentation review provider failed"* ]]
    [ "$(git log -1 --pretty=%s)" = "initial" ]
}

@test "external documentation provider can override subject body and release note" {
    mkdir -p modules/core docs
    echo "# change" > modules/core/manifest-core.sh
    echo "# Docs" > docs/COMMAND_REFERENCE.md
    provider="$SCRATCH/provider"
    {
        echo '#!/usr/bin/env bash'
        echo 'printf "%s\n" "Provider subject" > "$MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT_FILE"'
        echo 'printf "%s\n" "Provider commit body" > "$MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY_FILE"'
        echo 'printf "%s\n" "- Provider release note" > "$MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE_FILE"'
    } > "$provider"
    chmod +x "$provider"

    MANIFEST_CLI_DOC_REVIEW_PROVIDER=command \
    MANIFEST_CLI_DOC_REVIEW_COMMAND="$provider" \
        run commit_changes "Original subject" ""

    [ "$status" -eq 0 ]
    [ "$(git log -1 --pretty=%s)" = "Provider subject" ]
    git log -1 --pretty=%B | grep -q "Provider commit body"

    run get_git_changes "1.0.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Provider release note"* ]]
}

@test "documentation review report directory is configurable" {
    mkdir -p modules/core
    echo "# change" > modules/core/manifest-core.sh

    MANIFEST_CLI_DOC_REVIEW_REPORT_DIR="docs/reviews" run manifest_smart_documentation_review "Add command"

    [ "$status" -eq 0 ]
    report="$(ls docs/reviews/DOC_REVIEW_*.md)"
    [ -f "$report" ]
}

@test "default report_dir routes reports to .git/manifest-doc-review/, not the working tree" {
    mkdir -p modules/core
    echo "# change" > modules/core/manifest-core.sh

    unset MANIFEST_CLI_DOC_REVIEW_REPORT_DIR

    run manifest_smart_documentation_review "Add command"

    [ "$status" -eq 0 ]
    report="$(ls .git/manifest-doc-review/DOC_REVIEW_*.md 2>/dev/null)"
    [ -f "$report" ]
    grep -q "command_surface_changed: 1" "$report"
    [ ! -d "docs/documentation-reviews" ]
}
