#!/bin/bash

# Manifest Git Module
# Handles Git operations, versioning, and workflow automation

# Git module - uses PROJECT_ROOT from core module
MANIFEST_CLI_GIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MANIFEST_CLI_GIT_SCRIPT_DIR/manifest-doc-review.sh"

# Git Configuration

# Enhanced input validation functions
validate_version_selection() {
    local selection="$1"
    local max_options="$2"
    
    # Check if it's a valid number
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Check if it's within valid range
    if [ "$selection" -lt 1 ] || [ "$selection" -gt "$max_options" ]; then
        return 1
    fi
    
    return 0
}

validate_increment_type() {
    local increment_type="$1"
    
    # Convert to lowercase and validate
    increment_type="$(echo "$increment_type" | tr '[:upper:]' '[:lower:]')"
    case "$increment_type" in
        patch|minor|major|revision) return 0 ;;
        *) return 1 ;;
    esac
}

manifest_git_timeout_command() {
    if [[ "$(uname -s 2>/dev/null || echo "")" == "Darwin" ]]; then
        if command -v gtimeout >/dev/null 2>&1; then
            echo "gtimeout"
            return 0
        fi
    elif command -v timeout >/dev/null 2>&1; then
        echo "timeout"
        return 0
    fi

    if command -v timeout >/dev/null 2>&1; then
        echo "timeout"
        return 0
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        echo "gtimeout"
        return 0
    fi

    return 1
}

# Shared retry function for git operations
git_retry() {
    local description="$1"
    local command="$2"
    local timeout="${MANIFEST_CLI_GIT_TIMEOUT:-300}"  # 5 minutes default timeout
    local max_retries="${MANIFEST_CLI_GIT_RETRIES:-3}"  # 3 retries default
    local success=false
    local timeout_cmd=""
    
    # Validate command input to prevent injection
    if [[ -z "$command" ]]; then
        echo "   ❌ Error: No command provided"
        return 1
    fi
    
    # Parse command into array to prevent injection
    local cmd_array=()
    IFS=' ' read -ra cmd_array <<< "$command"
    
    # Validate that it's a git command
    if [[ "${cmd_array[0]}" != "git" ]]; then
        echo "   ❌ Error: Only git commands are allowed"
        return 1
    fi
    
    # Configure git to use SSH connection multiplexing to reduce connection overhead
    local git_ssh_command="ssh -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=~/.ssh/control-%r@%h:%p"

    if ! timeout_cmd="$(manifest_git_timeout_command)"; then
        echo "   ❌ Missing timeout command. Install coreutils (gtimeout on macOS, timeout elsewhere)."
        return 1
    fi
    
    for attempt in $(seq 1 $max_retries); do
        echo "   $description (attempt $attempt/$max_retries)..."
        
        # Use GIT_SSH_COMMAND to enable connection multiplexing with safe array execution
        if "$timeout_cmd" "$timeout" env GIT_SSH_COMMAND="$git_ssh_command" "${cmd_array[@]}" 2>/dev/null; then
            echo "   ✅ $description successful"
            success=true
            break
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "   ⏰ $description timed out after ${timeout}s (attempt $attempt/$max_retries)"
            else
                echo "   ❌ $description failed (attempt $attempt/$max_retries)"
            fi
            
            if [ $attempt -lt $max_retries ]; then
                echo "   🔄 Retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done
    
    if [ "$success" = "false" ]; then
        echo "   ⚠️  All attempts failed for $description"
        return 1
    fi
    
    return 0
}

bump_version() {
    local increment_type="$1"
    
    # Validate input
    if [[ -z "$increment_type" ]]; then
        show_required_arg_error "increment_type" "bump_version <patch|minor|major>"
        return 1
    fi
    
    # Enhanced input validation
    if ! validate_increment_type "$increment_type"; then
        show_validation_error "Invalid increment type: $increment_type (must be patch, minor, major, or revision)"
        return 1
    fi
    
    # Sanitize increment type
    increment_type="$(echo "$increment_type" | tr '[:upper:]' '[:lower:]')"
    local current_version=""
    local new_version=""
    
    # Change to project root directory
    cd "$PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $PROJECT_ROOT"
        return 1
    }
    
    # Read current version
    if [ -f "VERSION" ]; then
        current_version=$(cat VERSION)
    else
        echo "❌ No VERSION file found"
        return 1
    fi
    
    echo "📦 Bumping version..."
    echo "   Current version: $current_version"
    
    # Parse version components using configuration
    local separator="${MANIFEST_CLI_VERSION_SEPARATOR:-.}"
    local major=$(echo "$current_version" | cut -d"$separator" -f1)
    local minor=$(echo "$current_version" | cut -d"$separator" -f2)
    local patch=$(echo "$current_version" | cut -d"$separator" -f3)
    
    case "$increment_type" in
        "patch")
            patch=$((patch + 1))
            echo "   Incrementing patch version"
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            echo "   Incrementing minor version"
            ;;
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            echo "   Incrementing major version"
            ;;
        "revision")
            # Add revision number (e.g., 1.0.0.1)
            if [ -f "VERSION" ]; then
                local revision=$(echo "$current_version" | cut -d"$separator" -f4)
                if [ -z "$revision" ]; then
                    revision=1
                else
                    revision=$((revision + 1))
                fi
                new_version="${major}${separator}${minor}${separator}${patch}${separator}${revision}"
            else
                echo "   ❌ Revision increment only supported with VERSION file"
                return 1
            fi
            ;;
        *)
            echo "   ❌ Invalid increment type: $increment_type"
            return 1
            ;;
    esac
    
    # Generate new version if not already set
    if [ -z "$new_version" ]; then
        new_version="${major}${separator}${minor}${separator}${patch}"
    fi
    
    echo "   New version: $new_version"
    
    # Update VERSION file
    if [ -f "VERSION" ]; then
        echo "$new_version" > VERSION
        echo "   ✅ VERSION file updated: $new_version"
    fi

    # Mirror the new version into any opt-in version.sync targets (e.g.
    # package.json). No-op when unset. Targets resolve relative to the repo
    # root, which is the cwd here — the same as the VERSION write above.
    if declare -F manifest_version_sync_apply >/dev/null 2>&1; then
        manifest_version_sync_apply "$new_version"
    fi

    echo "✅ Version bumped to $new_version"
    return 0
}

# Emit one version.sync target per line. Mirrors the security private-files
# splitter (_manifest_security_private_env_files): accepts either a bash array
# or a comma-separated string; unset/empty means no sync (opt-in, fail-closed).
# Whitespace around each item is trimmed.
_manifest_version_sync_targets() {
    local decl
    decl="$(declare -p MANIFEST_CLI_VERSION_SYNC 2>/dev/null || true)"
    case "$decl" in
        declare\ -a*|declare\ -ax*)
            printf '%s\n' "${MANIFEST_CLI_VERSION_SYNC[@]}"
            return 0
            ;;
    esac
    local raw="${MANIFEST_CLI_VERSION_SYNC:-}"
    [ -n "$raw" ] || return 0
    local item
    local -a _mvs_items
    IFS=',' read -r -a _mvs_items <<< "$raw"
    for item in "${_mvs_items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [ -n "$item" ] && printf '%s\n' "$item"
    done
}

# Mirror the canonical version into the opt-in version.sync targets. Today only
# JSON files (package.json-style) are rewritten, via a surgical sed of the
# top-level "version" value — NO jq reserialize, so the diff is a single line
# and the file's existing formatting is preserved. Non-JSON targets
# (pyproject.toml / Cargo.toml, planned later) are recognized but skipped with a
# notice, so a partial implementation is never mistaken for a complete one.
# Fail-closed: a missing file or a missing "version" field is skipped, never
# created. Targets resolve relative to the cwd (the repo root during a bump).
manifest_version_sync_apply() {
    local new_version="$1"
    local target
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        if [ ! -f "$target" ]; then
            echo "   ⚠️  version.sync: $target not found — skipped"
            continue
        fi
        case "$target" in
            *.json)
                if ! grep -Eq '"version"[[:space:]]*:' "$target"; then
                    echo "   ⚠️  version.sync: no \"version\" field in $target — skipped"
                    continue
                fi
                # Rewrite only the top-level "version" value. The address range
                # 1,/"version":/ ends at the FIRST version line, so a deeper
                # "version": inside a nested object is out of range and left
                # alone. Portable across BSD/GNU sed (no GNU-only 0,/re/ and no
                # in-place -i flag — this helper can run before the §5.11
                # GNU-userland PATH prepend), so we edit via a temp file.
                local _tmp="${target}.manifest-sync.tmp"
                if sed -E "1,/\"version\"[[:space:]]*:/ s/(\"version\"[[:space:]]*:[[:space:]]*\")[^\"]*\"/\\1${new_version}\"/" "$target" > "$_tmp" 2>/dev/null && mv "$_tmp" "$target"; then
                    echo "   ✅ version.sync: $target -> $new_version"
                else
                    rm -f "$_tmp" 2>/dev/null
                    echo "   ⚠️  version.sync: failed to update $target"
                fi
                ;;
            *)
                echo "   ⚠️  version.sync: $target type not yet supported (JSON only) — skipped"
                ;;
        esac
    done < <(_manifest_version_sync_targets)
}

# Notice (not a prompt): list brand-new untracked files that a following
# `git add .` is about to sweep into the commit. Modifications to tracked
# files are the expected payload and stay silent; a never-committed file
# showing up in a release/refresh commit is the anomaly worth surfacing (see
# the v3.0.2 audit-doc leak). Notice only, never blocks — consistent with the
# notice-not-prompt consent model. A blanket "you have unstaged changes" prompt
# would defeat the point of auto-commit, so we only call out the new files.
#
# ARGUMENTS:
#   $1 - repo path (default ".") so callers using `git -C <path>` match.
#   $2 - line prefix (default "   ") for alignment / per-repo labeling.
manifest_notice_new_untracked_files() {
    local repo="${1:-.}"
    local prefix="${2:-   }"
    local _new_files=() _nf
    while IFS= read -r _nf; do
        [[ -n "$_nf" ]] && _new_files+=("$_nf")
    done < <(git -C "$repo" status --porcelain 2>/dev/null | sed -n 's/^?? //p')
    [[ ${#_new_files[@]} -gt 0 ]] || return 0
    local _nf_noun="files"
    [[ ${#_new_files[@]} -eq 1 ]] && _nf_noun="file"
    local _nf_joined
    printf -v _nf_joined '%s, ' "${_new_files[@]}"
    _nf_joined="${_nf_joined%, }"
    echo "${prefix}Also committing ${#_new_files[@]} new $_nf_noun: $_nf_joined"
}
export -f manifest_notice_new_untracked_files

commit_changes() {
    local message="$1"
    local timestamp="$2"
    
    if [ -z "$message" ]; then
        message="Auto-commit changes"
    fi
    
    if [ -n "$timestamp" ]; then
        message="$message [TS: $timestamp]"
    fi
    
    echo "💾 Committing changes..."
    
    # Change to project root directory
    cd "$PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $PROJECT_ROOT"
        return 1
    }

    if ! manifest_smart_documentation_review "$message"; then
        echo "❌ Documentation review failed"
        return 1
    fi

    if [[ -n "${MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT:-}" ]]; then
        message="$MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT"
    fi

    echo "   Message: $message"

    # Surface any brand-new untracked files this commit is about to sweep in.
    manifest_notice_new_untracked_files

    git add .
    local commit_ok=false
    if [[ -n "${MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY:-}" ]]; then
        git commit -m "$message" -m "$MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY" && commit_ok=true
    else
        git commit -m "$message" && commit_ok=true
    fi
    if [[ "$commit_ok" == "true" ]]; then
        echo "✅ Changes committed"
        return 0
    else
        echo "❌ Commit failed"
        return 1
    fi
}

resolve_tag_target_sha() {
    local version_commit_sha="$1"
    local raw="${MANIFEST_CLI_RELEASE_TAG_TARGET:-version_commit}"
    local target
    target="$(normalize_enum_value "$raw")"
    case "$target" in
        version_commit)
            echo "$version_commit_sha"
            ;;
        release_head)
            echo ""
            ;;
        final_release_commit)
            # Deprecated alias for release_head. Renamed because Homebrew
            # commits cannot be included (update_homebrew_formula needs the
            # GitHub tarball SHA256 of an already-pushed tag), so "final" was
            # misleading. Remove this alias one minor version after introduction.
            log_warning "MANIFEST_CLI_RELEASE_TAG_TARGET='final_release_commit' is deprecated; use 'release_head' instead"
            echo ""
            ;;
        *)
            log_warning "Unknown MANIFEST_CLI_RELEASE_TAG_TARGET='${raw}' (expected version_commit or release_head); falling back to version_commit"
            echo "$version_commit_sha"
            ;;
    esac
}

manifest_release_tag_name() {
    local version="$1"
    local tag_prefix="${MANIFEST_CLI_GIT_TAG_PREFIX:-v}"
    local tag_suffix="${MANIFEST_CLI_GIT_TAG_SUFFIX:-}"
    echo "${tag_prefix}${version}${tag_suffix}"
}

create_tag() {
    local version="$1"
    local target_sha="${2:-}"
    local tag_name
    tag_name="$(manifest_release_tag_name "$version")"

    echo "🏷️  Creating git tag..."
    echo "   Tag: $tag_name"
    if [[ -n "$target_sha" ]]; then
        echo "   Target: $target_sha"
    fi

    # Change to project root directory
    cd "$PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $PROJECT_ROOT"
        return 1
    }

    local tag_status=0
    if [[ -n "$target_sha" ]]; then
        git tag "$tag_name" "$target_sha"
        tag_status=$?
    else
        git tag "$tag_name"
        tag_status=$?
    fi

    if [[ $tag_status -eq 0 ]]; then
        echo "✅ Tag $tag_name created"
        return 0
    else
        echo "❌ Tag creation failed"
        return 1
    fi
}

# Refuse to start a publish if HEAD isn't on the branch the release will push.
#
# push_changes() below pushes the *literal* default-branch ref
# (${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}), but the version commit and tag are
# created on whatever HEAD is checked out. When HEAD differs, the commit+tag land
# on the wrong branch and `git push origin <default>` pushes a stale default
# branch — the v4.0.0 mishap (tag public, main never advanced). The workflow
# cannot run correctly off the default branch, so we stop and hand the user the
# git steps to fix it rather than wrapping/auto-fixing git. The comparison uses
# the same env var push_changes uses, so a configured non-main default (e.g.
# master) is honored without an override knob.
#
# ARGUMENTS:
#   $1 - repo path (default ".") so callers using `git -C <path>` match.
#   $2 - line prefix (default "   ") for alignment / per-repo labeling.
# RETURNS: 0 if on the default branch; 1 (with remediation output) otherwise.
manifest_assert_release_branch() {
    local repo="${1:-.}"
    local prefix="${2:-   }"
    local default_branch="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    local current
    current="$(git -C "$repo" branch --show-current 2>/dev/null)"

    [[ "$current" == "$default_branch" ]] && return 0

    local where="branch '$current'"
    [[ -z "$current" ]] && where="a detached HEAD"
    echo "${prefix}❌ Cannot release: HEAD is on $where, not '$default_branch'."
    echo "${prefix}   Ship pushes the '$default_branch' branch and the new tag, but the"
    echo "${prefix}   version commit and tag would land on $where — so '$default_branch'"
    echo "${prefix}   would be pushed unchanged and the tag would point off '$default_branch'."
    echo "${prefix}   Resolve with git, then re-run ship:"
    if [[ -n "$current" ]]; then
        echo "${prefix}     git checkout $default_branch && git merge $current   # bring the work onto '$default_branch'"
    fi
    echo "${prefix}     git checkout $default_branch                          # if the work is already on '$default_branch'"
    return 1
}
export -f manifest_assert_release_branch

push_changes() {
    local version="$1"
    local tag_name
    tag_name="$(manifest_release_tag_name "$version")"
    local default_branch="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    
    echo "🚀 Pushing to all remotes..."
    
    # Change to project root directory
    cd "$PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $PROJECT_ROOT"
        return 1
    }
    
    # Get list of remotes
    local remotes=$(git remote)
    
    for remote in $remotes; do
        echo "   Pushing to $remote..."
        
        # Push branch and the exact release tag together in one operation.
        if ! git_retry "📤 Pushing $default_branch branch and $tag_name to $remote" "git push --progress $remote $default_branch $tag_name"; then
            echo "   ❌ Failed to push to $remote"
            return 1
        fi
    done
    
    echo "✅ All remotes updated successfully"
    return 0
}

sync_repository() {
    echo "🔄 Syncing with remote..."
    local default_branch="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    
    # Change to project root directory
    cd "$PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $PROJECT_ROOT"
        return 1
    }
    
    # Get list of remotes
    local remotes=$(git remote)
    
    for remote in $remotes; do
        echo "   Syncing with $remote..."
        
        # Use git pull directly (which does fetch + merge in one operation)
        # This reduces SSH connections from 2 to 1 per remote
        if ! git_retry "📥 Syncing with $remote/$default_branch" "git pull $remote $default_branch"; then
            echo "   ⚠️  All sync attempts failed for $remote, continuing with local state"
        else
            echo "   ✅ Successfully synced with $remote"
        fi
    done
    
    echo "✅ Repository synced successfully"
    return 0
}

revert_version() {
    echo "🔄 Reverting to previous version..."
    
    # Get list of available versions
    local available_versions=()
    local tags=$(git tag --sort=-version:refname | head -10)
    
    for tag in $tags; do
        available_versions+=("$tag")
    done
    
    if [ ${#available_versions[@]} -eq 0 ]; then
        echo "❌ No version tags found"
        return 1
    fi
    
    echo "📋 Available versions:"
    for i in "${!available_versions[@]}"; do
        local version=${available_versions[$i]}
        echo "   $((i+1)). $version"
    done
    
    echo ""
    read -p "Select version to revert to (1-${#available_versions[@]}) or 'q' to quit: " selection
    
    if [ "$selection" = "q" ]; then
        echo "🔄 Revert cancelled"
        return 0
    fi
    
    # Enhanced input validation
    if ! validate_version_selection "$selection" "${#available_versions[@]}"; then
        echo "❌ Invalid selection. Please enter a number between 1 and ${#available_versions[@]} or 'q' to quit."
        return 1
    fi
    
    local selected_version=${available_versions[$((selection-1))]}
    echo "🔄 Reverting to $selected_version..."
    
    if git checkout "$selected_version"; then
        echo "✅ Successfully reverted to $selected_version"
        echo "💡 Note: You are now in 'detached HEAD' state"
    else
        echo "❌ Failed to revert to $selected_version"
        return 1
    fi
}

# PR workflows moved to modules/pr/manifest-pr.sh
