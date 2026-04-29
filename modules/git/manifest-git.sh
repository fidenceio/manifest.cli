#!/bin/bash

# Manifest Git Module
# Handles Git operations, versioning, and workflow automation

# Git module - uses PROJECT_ROOT from core module

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

# Shared retry function for git operations
git_retry() {
    local description="$1"
    local command="$2"
    local timeout="${MANIFEST_CLI_GIT_TIMEOUT:-300}"  # 5 minutes default timeout
    local max_retries="${MANIFEST_CLI_GIT_RETRIES:-3}"  # 3 retries default
    local success=false
    
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
    
    for attempt in $(seq 1 $max_retries); do
        echo "   $description (attempt $attempt/$max_retries)..."
        
        # Use GIT_SSH_COMMAND to enable connection multiplexing with safe array execution
        if timeout "$timeout" env GIT_SSH_COMMAND="$git_ssh_command" "${cmd_array[@]}" 2>/dev/null; then
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
    

    
    echo "✅ Version bumped to $new_version"
    return 0
}

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
    echo "   Message: $message"
    
    # Change to project root directory
    cd "$PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $PROJECT_ROOT"
        return 1
    }
    
    git add .
    if git commit -m "$message"; then
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

create_tag() {
    local version="$1"
    local target_sha="${2:-}"
    local tag_prefix="${MANIFEST_CLI_GIT_TAG_PREFIX:-v}"
    local tag_suffix="${MANIFEST_CLI_GIT_TAG_SUFFIX:-}"
    local tag_name="${tag_prefix}${version}${tag_suffix}"

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

push_changes() {
    local version="$1"
    local tag_name="v$version"
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
        
        # Push branch and tags together in one operation to reduce SSH connections
        if ! git_retry "📤 Pushing $default_branch branch and tags to $remote" "git push --progress $remote $default_branch $tag_name"; then
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
        echo "   To continue development, create a new branch: git checkout -b new-branch"
    else
        echo "❌ Failed to revert to $selected_version"
        return 1
    fi
}

# PR workflows moved to modules/pr/manifest-pr.sh
