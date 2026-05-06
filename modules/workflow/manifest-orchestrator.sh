#!/bin/bash

# Manifest Orchestrator Module
# Coordinates the complete manifest workflow using atomized modules

# Orchestrator module - uses PROJECT_ROOT from core module

# Orchestrator module - modules are already sourced by manifest-core.sh

emit_ship_failure_report() {
    local failure_step="$1"
    local start_sha="$2"
    local version="$3"
    local tag_name="$4"
    local push_status="$5"
    local homebrew_status="$6"

    local branch upstream ahead behind commits_created
    branch="$(git branch --show-current 2>/dev/null || echo "unknown")"
    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "none")"
    ahead="unknown"
    behind="unknown"
    if [ "$upstream" != "none" ]; then
        local lr_counts=""
        lr_counts="$(git rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "")"
        if [ -n "$lr_counts" ]; then
            behind="$(echo "$lr_counts" | awk '{print $1}')"
            ahead="$(echo "$lr_counts" | awk '{print $2}')"
        fi
    fi

    commits_created="unknown"
    if [ -n "$start_sha" ] && git cat-file -e "$start_sha^{commit}" 2>/dev/null; then
        commits_created="$(git rev-list --count "${start_sha}..HEAD" 2>/dev/null || echo "unknown")"
    fi

    echo ""
    echo "🚨 Ship Failure Report"
    echo "======================"
    echo "   failed step:        ${failure_step}"
    echo "   target version:     ${version:-unknown}"
    echo "   commits created:    ${commits_created}"
    echo "   tag:                ${tag_name:-none}"
    echo "   push status:        ${push_status}"
    echo "   homebrew status:    ${homebrew_status}"
    echo "   branch:             ${branch}"
    echo "   upstream:           ${upstream}"
    echo "   ahead/behind:       ${ahead}/${behind}"
    echo "   start commit:       ${start_sha:-unknown}"
    echo ""
    echo "📋 Git status snapshot:"
    git status --short --branch 2>/dev/null || echo "   (unavailable)"
    echo ""
    echo "🛠️  Recovery commands:"
    if [ -n "$tag_name" ] && [ "$tag_name" != "none" ]; then
        echo "   Retry push:  git push origin ${branch} ${tag_name}"
        echo "   Resume:      manifest ship repo resume"
        echo "   Remove tag:  git tag -d ${tag_name}"
    else
        echo "   Retry push:  git push origin ${branch}"
    fi
    if [ -n "$start_sha" ]; then
        echo "   Roll back:   git reset --hard ${start_sha}"
    fi
    echo ""
	}

manifest_should_wait_for_github_actions() {
    ! is_falsy "${MANIFEST_CLI_GITHUB_ACTIONS_WAIT:-false}"
}

manifest_check_github_actions_for_head() {
    local head_sha="${1:-}"
    local wait_seconds="${MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS:-600}"
    local poll_seconds="${MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS:-5}"
    local elapsed=0
    local run_id=""

    if ! manifest_should_wait_for_github_actions; then
        echo "GitHub Actions: skipped (disabled by MANIFEST_CLI_GITHUB_ACTIONS_WAIT)"
        return 2
    fi
    if [[ -z "$head_sha" ]]; then
        echo "GitHub Actions: skipped (no HEAD SHA available)"
        return 2
    fi
    if ! command -v gh >/dev/null 2>&1; then
        echo "GitHub Actions: skipped (gh not installed)"
        return 2
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "GitHub Actions: skipped (gh not authenticated)"
        return 2
    fi

    echo "🧪 Checking GitHub Actions for ${head_sha:0:7}..."
    while (( elapsed <= wait_seconds )); do
        run_id="$(gh run list --commit "$head_sha" --limit 1 --json databaseId --jq '.[0].databaseId // ""' 2>/dev/null || true)"
        if [[ -n "$run_id" ]]; then
            break
        fi
        sleep "$poll_seconds"
        elapsed=$((elapsed + poll_seconds))
    done

    if [[ -z "$run_id" ]]; then
        echo "GitHub Actions: unavailable (no workflow run found within ${wait_seconds}s)"
        return 2
    fi

    echo "   Run: $run_id"
    if gh run watch "$run_id" --exit-status --interval "$poll_seconds"; then
        echo "GitHub Actions: passed"
        return 0
    fi

    echo "GitHub Actions: failed"
    echo "   Inspect: gh run view $run_id --log-failed"
    return 1
}

manifest_ship_post_push_steps() {
    local new_version="$1"
    local workflow_start_sha="$2"
    local workflow_tag_name="$3"
    local workflow_push_status="${4:-success}"
    local workflow_homebrew_status="skipped"

    # Update Homebrew formula only for the Manifest CLI canonical repository.
    if [ -f "$PROJECT_ROOT/formula/manifest.rb" ] && should_update_homebrew_for_repo; then
        workflow_homebrew_status="attempted"
        echo "🍺 Updating Homebrew formula..."
        if update_homebrew_formula; then
            # Commit the formula change to this repo
            if [ -n "$(git status --porcelain formula/manifest.rb 2>/dev/null)" ]; then
                git add formula/manifest.rb
                if ! git commit -m "Update Homebrew formula to v$new_version"; then
                    workflow_homebrew_status="failed"
                    log_error "Failed to commit Homebrew formula update."
                    emit_ship_failure_report "homebrew_commit" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
                    return 1
                fi
                if ! git push origin "${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"; then
                    workflow_homebrew_status="failed"
                    log_error "Failed to push Homebrew formula commit."
                    emit_ship_failure_report "homebrew_push" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
                    return 1
                fi
            fi
            workflow_homebrew_status="success"
            echo "✅ Homebrew formula updated"
        else
            workflow_homebrew_status="failed"
            log_error "Homebrew formula update failed; aborting ship workflow."
            emit_ship_failure_report "homebrew_update" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi
        echo ""
    elif [ -f "$PROJECT_ROOT/formula/manifest.rb" ]; then
        workflow_homebrew_status="skipped_non_canonical_repo"
        local origin_slug=""
        origin_slug="$(manifest_origin_repo_slug || echo "unknown")"
        echo "🍺 Skipping Homebrew formula update for non-canonical repo: ${origin_slug}"
        echo ""
    fi

    # Upgrade local Manifest CLI installation to the just-published version.
    echo "🔄 Upgrading local Manifest CLI installation..."
    if command -v brew &>/dev/null; then
        if brew update &>/dev/null && brew upgrade manifest 2>&1; then
            echo "✅ Local installation upgraded to v$new_version via Homebrew"
        else
            echo "⚠️  Homebrew upgrade did not complete — try 'brew update && brew upgrade manifest' manually"
        fi
    else
        if manifest upgrade --force 2>&1; then
            echo "✅ Local installation upgraded to v$new_version"
        else
            echo "⚠️  Local upgrade did not complete — try 'manifest upgrade --force' manually"
        fi
    fi
    echo ""

    _MANIFEST_SHIP_LAST_HOMEBREW_STATUS="$workflow_homebrew_status"
    return 0
}

manifest_ship_repo_resume() {
    if ! ensure_repository_root; then
        log_error "Repository root validation failed"
        return 1
    fi
    PROJECT_ROOT="$(pwd)"
    export PROJECT_ROOT

    local version tag_name tag_commit branch remote_branch_status remote_tag_status dirty_files non_formula_dirty
    version="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "")"
    if [[ -z "$version" ]]; then
        log_error "Cannot resume ship: VERSION file is missing or empty."
        return 1
    fi
    tag_name="$(manifest_release_tag_name "$version")"
    branch="$(git branch --show-current 2>/dev/null || echo "")"
    if [[ -z "$branch" ]]; then
        log_error "Cannot resume ship: detached HEAD is not supported."
        return 1
    fi

    if ! tag_commit="$(git rev-parse "${tag_name}^{commit}" 2>/dev/null)"; then
        log_error "Cannot resume ship: local tag ${tag_name} does not exist."
        log_error "Run a normal ship workflow or create the release tag first."
        return 1
    fi
    if ! git merge-base --is-ancestor "$tag_commit" HEAD 2>/dev/null; then
        log_error "Cannot resume ship: ${tag_name} does not point at an ancestor of HEAD."
        return 1
    fi

    dirty_files="$(git status --porcelain 2>/dev/null || true)"
    non_formula_dirty="$(printf '%s\n' "$dirty_files" | awk '$2 != "formula/manifest.rb" && $0 != "" { print; found=1 } END { exit found ? 0 : 1 }' || true)"
    if [[ -n "$non_formula_dirty" ]]; then
        log_error "Cannot resume ship with unrelated working-tree changes:"
        printf '%s\n' "$non_formula_dirty"
        return 1
    fi

    remote_branch_status="unknown"
    remote_tag_status="unknown"
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        remote_branch_status="present"
    else
        remote_branch_status="missing or unreachable"
    fi
    if git ls-remote --exit-code --tags origin "$tag_name" >/dev/null 2>&1; then
        remote_tag_status="present"
    else
        remote_tag_status="missing or unreachable"
    fi

    echo ""
    echo "Ship resume"
    echo "==========="
    echo "   version:       $version"
    echo "   tag:           $tag_name ($tag_commit)"
    echo "   branch:        $branch"
    echo "   remote branch: $remote_branch_status"
    echo "   remote tag:    $remote_tag_status"
    if [[ -n "$dirty_files" ]]; then
        echo "   working tree:  formula/manifest.rb pending"
    else
        echo "   working tree:  clean"
    fi
    echo ""

    if ! push_changes "$version"; then
        log_error "Resume failed while pushing branch/tag."
        emit_ship_failure_report "resume_push" "$(git rev-parse HEAD 2>/dev/null || echo "")" "$version" "$tag_name" "failed" "skipped"
        return 1
    fi
    echo ""

    if ! manifest_ship_post_push_steps "$version" "$(git rev-parse HEAD 2>/dev/null || echo "")" "$tag_name" "success"; then
        return 1
    fi

    update_repository_metadata
    echo ""
    echo "✅ Ship resume completed for v${version}"
}

# Main ship workflow: version bump, docs, commit, tag, push, Homebrew.
# With publish_release=false this stops short of tag/push (the --local path).
manifest_ship_workflow() {
    local increment_type="$1"
    local interactive="$2"
    local publish_release="${3:-false}"
    local workflow_start_sha=""
    local workflow_tag_name="none"
    local workflow_push_status="not_attempted"
    local workflow_homebrew_status="not_applicable"
    local workflow_actions_status="not_applicable"
    local workflow_version_commit_sha=""

    if [ "$publish_release" = "true" ]; then
        workflow_homebrew_status="skipped"
    fi
    
    # Ensure we're running from repository root
    if ! ensure_repository_root; then
        log_error "Repository root validation failed"
        return 1
    fi
    
    # Update PROJECT_ROOT to the actual current directory (in case we changed)
    PROJECT_ROOT="$(pwd)"
    export PROJECT_ROOT
    workflow_start_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
    
    # Determine version increment type
    if [ -z "$increment_type" ]; then
        increment_type="patch"
    fi
    
    echo "🚀 Starting automated Manifest process..."
    echo ""
    echo "   git repo:          $(git remote get-url origin 2>/dev/null || echo 'none')"
    echo "   git branch (remote): $(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo 'none')"
    echo "   git branch (local):  $(git branch --show-current 2>/dev/null || echo 'unknown')"
    echo "   working folder:    $PROJECT_ROOT"
    echo "   docs folder:       $(get_docs_folder "$PROJECT_ROOT")"
    echo "   archive folder:    $(get_zarchive_dir)"
    echo "   previous version:  $(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo 'unknown')"
    echo ""

    # Ensure required files exist before proceeding
    echo "🔍 Checking for required files..."
    if ! ensure_required_files "$PROJECT_ROOT"; then
        log_error "Failed to ensure required files are present"
        return 1
    fi
    echo ""
    
    # Interactive confirmation for safety
    local interactive_mode=false
    
    # Enable interactive mode with explicit flag values.
    if [ "$interactive" = "-i" ] || [ "$interactive" = "--interactive" ] || [ "$interactive" = "true" ] || [ "$interactive" = "1" ]; then
        interactive_mode=true
    fi
    
    # Enable interactive mode if environment variable is set to true
    if is_truthy "${MANIFEST_CLI_INTERACTIVE_MODE:-false}"; then
        interactive_mode=true
    fi
    
    # Disable interactive mode if not in a terminal (CI/CD environments)
    if [ ! -t 0 ]; then
        interactive_mode=false
    fi
    
    if [ "$interactive_mode" = "true" ]; then
        echo "🔍 Safety Check - CI/CD & Collaborative Environment Protection"
        echo "=============================================================="
        echo ""
        echo "📋 Version increment type: $increment_type"
        echo "📍 Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
        echo "🏷️  Current version: $(cat VERSION 2>/dev/null || echo 'unknown')"
        echo ""
        echo "⚠️  This will perform a complete version bump workflow including:"
        echo "   • Sync with remote repository"
        echo "   • Bump version to next $increment_type"
        echo "   • Generate documentation and release notes"
        echo "   • Commit local changes"
        if [ "$publish_release" = "true" ]; then
            echo "   • Create Git tag and push to remote repository"
            echo "   • Update Homebrew formula"
        else
            echo "   • No remote pushes/tags (local-only prep mode)"
        fi
        echo ""
        echo "🤔 What would you like to do?"
        echo ""
        echo "   1) 🧪 Run test/dry-run first (recommended)"
        echo "   2) 🚀 Go ahead and execute $increment_type version bump now"
        echo "   3) ❌ Cancel and exit"
        echo ""
        
        while true; do
            read -r -p "   Enter your choice (1-3): " choice
            case $choice in
                1)
                    echo ""
                    echo "🧪 Running test/dry-run first..."
                    echo "================================"
                    manifest_test_dry_run "$increment_type"
                    echo ""
                    echo "🤔 Test completed. Would you like to proceed with the actual version bump?"
                    read -r -p "   Proceed with $increment_type version bump? (y/N): " proceed
                    case $proceed in
                        [Yy]|[Yy][Ee][Ss])
                            echo ""
                            echo "🚀 Proceeding with $increment_type version bump..."
                            break
                            ;;
                        *)
                            echo "❌ Version bump cancelled by user."
                            return 0
                            ;;
                    esac
                    ;;
                2)
                    echo ""
                    echo "🚀 Proceeding with $increment_type version bump..."
                    break
                    ;;
                3)
                    echo "❌ Version bump cancelled by user."
                    return 0
                    ;;
                *)
                    echo "   ❌ Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
        echo ""
    fi
    
    # Get trusted timestamp
    get_time_timestamp
    
    echo "📋 Version increment type: $increment_type"
    echo ""
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "📝 Uncommitted changes detected. Committing first..."
        local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
        # Add a scope hint to the auto-commit subject so `git log --oneline`
        # alone tells you what got swept up. Hint covers tracked changes
        # AND untracked files, since `commit_changes` runs `git add .`.
        local _ac_files _ac_count _ac_first _ac_hint=""
        _ac_files="$(git status --porcelain | sed 's/^...//')"
        _ac_count=$(printf '%s\n' "$_ac_files" | grep -c .)
        _ac_first=$(printf '%s\n' "$_ac_files" | head -1)
        if [ "$_ac_count" -eq 1 ] && [ -n "$_ac_first" ]; then
            _ac_hint=" ($_ac_first)"
        elif [ "$_ac_count" -gt 1 ]; then
            _ac_hint=" ($_ac_count files: $_ac_first, ...)"
        fi
        commit_changes "Auto-commit before Manifest process$_ac_hint" "$timestamp"
        echo ""
    fi
    
    # Sync with remote
    echo "🔄 Syncing with remote..."
    sync_repository
    echo ""
    
    # Bump version
    echo "📦 Bumping version..."
    if ! bump_version "$increment_type"; then
        log_error "Version bump failed"
        return 1
    fi
    
    # Get new version
    local new_version=""
    if [ -f "VERSION" ]; then
        new_version=$(cat VERSION)
    fi
    
    if [ -z "$new_version" ]; then
        log_error "Could not determine new version"
        return 1
    fi
    
    echo ""
    
    # Generate documentation using new architecture
    local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    echo "📚 Generating documentation and release notes..."
    if generate_documents "$new_version" "$timestamp" "$increment_type"; then
        echo "✅ Documentation generated successfully"
    else
        echo "⚠️  Documentation generation had issues, but continuing..."
    fi
    echo ""
    
    # Archive previous version documentation to zArchive (now that new version is created)
    echo "📁 Archiving previous version documentation..."
    if ! main_cleanup "$new_version" "$timestamp"; then
        log_error "Archive sweep aborted; aborting ship workflow."
        emit_ship_failure_report "archive_sweep" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    echo ""
    
    # Final markdown validation and fixing (before commit)
    echo "🔍 Final markdown validation and fixing..."
    if validate_project "true"; then
        echo "✅ Markdown validation completed"
    else
        echo "⚠️  Markdown validation found issues, but continuing..."
    fi
    echo ""
    
    # Commit version changes
    echo "💾 Committing version changes..."
    local pre_version_commit_sha
    pre_version_commit_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
    if ! commit_changes "Bump version to $new_version" "$timestamp"; then
        log_error "Failed to commit version bump; aborting ship workflow."
        emit_ship_failure_report "version_commit" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    workflow_version_commit_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
    if [[ -z "$workflow_version_commit_sha" || "$workflow_version_commit_sha" == "$pre_version_commit_sha" ]]; then
        log_error "Version commit did not advance HEAD (pre=${pre_version_commit_sha:-unknown} post=${workflow_version_commit_sha:-unknown}); aborting ship workflow."
        emit_ship_failure_report "version_commit" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
        return 1
    fi
    echo ""

    # Validate repository state after commit
    echo "🔍 Validating repository state..."
    validate_repository || true
    echo ""
    
    if [ "$publish_release" = "true" ]; then
        workflow_tag_name="$(manifest_release_tag_name "$new_version")"

        # Resolve which commit the release tag should point at.
        # version_commit — the explicit "Bump version to X" commit, even when
        #                  a CHANGELOG commit follows it. Default.
        # release_head   — current HEAD at tagging time (post-CHANGELOG,
        #                  pre-Homebrew). Homebrew commits cannot be included
        #                  because update_homebrew_formula needs the GitHub
        #                  tarball SHA256 of an already-pushed tag.
        local tag_target_sha
        tag_target_sha="$(resolve_tag_target_sha "$workflow_version_commit_sha")"

        # Create git tag
        if ! create_tag "$new_version" "$tag_target_sha"; then
            log_error "Tag creation failed; aborting ship workflow."
            emit_ship_failure_report "create_tag" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi
        echo ""
        
        # Push changes
        workflow_push_status="attempted"
        if ! push_changes "$new_version"; then
            workflow_push_status="failed"
            log_error "Push failed; aborting ship workflow."
            emit_ship_failure_report "push_changes" "$workflow_start_sha" "$new_version" "$workflow_tag_name" "$workflow_push_status" "$workflow_homebrew_status"
            return 1
        fi
        workflow_push_status="success"
        echo ""

        if ! manifest_ship_post_push_steps "$new_version" "$workflow_start_sha" "$workflow_tag_name" "$workflow_push_status"; then
            return 1
        fi
        workflow_homebrew_status="${_MANIFEST_SHIP_LAST_HOMEBREW_STATUS:-skipped}"

        workflow_actions_status="attempted"
        local workflow_final_head_sha
        workflow_final_head_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
        if manifest_check_github_actions_for_head "$workflow_final_head_sha"; then
            workflow_actions_status="passed"
        else
            local actions_rc=$?
            if [[ "$actions_rc" -eq 1 ]]; then
                workflow_actions_status="failed"
                echo "⚠️  GitHub Actions failed after publish. Release artifacts were already pushed."
            else
                workflow_actions_status="skipped"
            fi
        fi
        echo ""
    else
        echo "🧰 Prep mode complete: skipped tag/push/Homebrew publish steps."
        echo ""
    fi

    # Update repository metadata
    update_repository_metadata
    echo ""
    
    # Success message
    echo "🎉 Manifest process completed successfully!"
    echo ""
    
    # Summary
    echo "📋 Summary:"
    echo "   - Version: $new_version"
    if [ "$publish_release" = "true" ]; then
        echo "   - Tag: $workflow_tag_name"
        echo "   - Remotes: All pushed successfully"
        echo "   - GitHub Actions: $workflow_actions_status"
    else
        echo "   - Tag: (not created in prep mode)"
        echo "   - Remotes: (no pushes in prep mode)"
    fi
    echo "   - Timestamp: $timestamp"
    echo "   - Source: $MANIFEST_CLI_TIME_SERVER ($MANIFEST_CLI_TIME_SERVER_IP)"
    echo "   - Offset: $MANIFEST_CLI_TIME_OFFSET seconds"
    echo "   - Uncertainty: ±$MANIFEST_CLI_TIME_UNCERTAINTY seconds"
    echo "   - Method: $MANIFEST_CLI_TIME_METHOD"
}

# Test/dry-run function for safety
manifest_test_dry_run() {
    local increment_type="$1"
    local current_version=$(cat VERSION 2>/dev/null || echo "unknown")
    local next_version=""
    
    echo "🧪 Manifest Test/Dry-Run Mode"
    echo "============================="
    echo ""
    echo "   git repo:          $(git remote get-url origin 2>/dev/null || echo 'none')"
    echo "   git branch (remote): $(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo 'none')"
    echo "   git branch (local):  $(git branch --show-current 2>/dev/null || echo 'unknown')"
    echo "   working folder:    $PROJECT_ROOT"
    echo "   docs folder:       $(get_docs_folder "$PROJECT_ROOT")"
    echo "   archive folder:    $(get_zarchive_dir)"
    echo "   previous version:  $(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo 'unknown')"
    echo ""

    # Test file requirements
    echo "📁 File Requirements Testing:"
    if ensure_required_files "$PROJECT_ROOT"; then
        echo "   ✅ All required files are present or created"
    else
        echo "   ❌ Failed to ensure required files"
    fi
    echo ""
    
    # Test version increment logic
    echo "📋 Version Testing:"
    echo "   Current version: $current_version"
    
    case "$increment_type" in
        "patch")
            next_version=$(echo "$current_version" | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')
            ;;
        "minor")
            next_version=$(echo "$current_version" | awk -F. '{$2 = $2 + 1; $3 = 0;} 1' | sed 's/ /./g')
            ;;
        "major")
            next_version=$(echo "$current_version" | awk -F. '{print $1 + 1 ".0.0"}')
            ;;
        "revision")
            next_version="$current_version.1"
            ;;
    esac
    
    echo "   Next version: $next_version"
    echo "   Increment type: $increment_type"
    echo ""
    
    # Test Git status
    echo "🔍 Git Status Check:"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo "   ✅ In Git repository"
        echo "   📍 Current branch: $(git branch --show-current)"
        echo "   📡 Remote: $(git remote get-url origin 2>/dev/null || echo 'none')"
        
        # Check for uncommitted changes
        if [ -n "$(git status --porcelain)" ]; then
            echo "   ⚠️  Uncommitted changes detected"
        else
            echo "   ✅ Working directory clean"
        fi
    else
        echo "   ❌ Not in a Git repository"
    fi
    echo ""
    
    # Test timestamp functionality
    echo "🕐 Timestamp Testing:"
    if command -v curl >/dev/null 2>&1; then
        echo "   ✅ curl command available (HTTPS timestamps)"
    else
        echo "   ⚠️  curl not available (will use system time)"
    fi
    echo ""
    
    # Test documentation generation
    echo "📚 Documentation Testing:"
    if [ -f "README.md" ]; then
        echo "   ✅ README.md exists"
    else
        echo "   ❌ README.md missing"
    fi
    
    local docs_dir=$(get_docs_folder)
    if [ -d "$docs_dir" ]; then
        echo "   ✅ Documentation directory exists: $(basename "$docs_dir")/"
    else
        echo "   ❌ Documentation directory missing: $(basename "$docs_dir")/"
    fi
    echo ""
    
    # Test configuration
    echo "⚙️  Configuration Testing:"
    if [ -f "env.example" ]; then
        echo "   ✅ env.example exists"
    else
        echo "   ❌ env.example missing"
    fi
    
    if [ -f "manifest.config" ]; then
        echo "   ✅ manifest.config exists"
    else
        echo "   ❌ manifest.config missing"
    fi
    echo ""
    
    # Test security
    echo "🔒 Security Testing:"
    if manifest security --check >/dev/null 2>&1; then
        echo "   ✅ Security audit passed"
    else
        echo "   ⚠️  Security audit had issues (check with 'manifest security --check')"
    fi
    echo ""
    
    echo "✅ Test/dry-run completed successfully!"
    echo "   All systems appear ready for version bump."
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "ship"|"prep")
            local increment_type="${2:-patch}"
            local interactive="${3:-false}"
            manifest_ship_workflow "$increment_type" "$interactive" "false"
            ;;
        "test")
            local increment_type="${2:-patch}"
            manifest_test_dry_run "$increment_type"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Orchestrator Module"
            echo "==========================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  ship [type] [interactive]  - Complete ship workflow (local-only)"
            echo "  test [type]              - Test/dry-run mode"
            echo "  help                     - Show this help"
            echo ""
            echo "Options:"
            echo "  type: patch, minor, major, revision (default: patch)"
            echo "  interactive: -i for interactive mode"
            echo ""
            echo "Examples:"
            echo "  $0 ship minor"
            echo "  $0 ship patch -i"
            echo "  $0 test major"
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# Back-compat: old name forwards to the renamed function. Remove once external
# callers (if any) have migrated.
manifest_prep_workflow() {
    manifest_ship_workflow "$@"
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
