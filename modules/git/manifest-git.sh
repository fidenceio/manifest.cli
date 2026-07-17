#!/bin/bash

# Manifest Git Module
# Handles Git operations, versioning, and workflow automation

# Git module - uses MANIFEST_CLI_PROJECT_ROOT from core module
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

# Bump the repo release version.
#
# Current writer contract: VERSION is the canonical release file. Additional
# package/version files are updated only when explicitly listed in version.sync.
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
    cd "$MANIFEST_CLI_PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $MANIFEST_CLI_PROJECT_ROOT"
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

# Print the 1-based line number of the top-level (object depth 1) "version" key
# in a JSON file, or nothing if there is none. The scan is string-aware — braces,
# brackets and colons inside string values don't skew the nesting depth — so the
# version.sync rewrite targets the REAL top-level version even when a nested
# "version" appears textually FIRST (the §7.7 corruption case the old
# 1,/"version":/ range got wrong). Assumes pretty-printed JSON (the top-level
# key:value on its own line), matching the surgical single-line sed below.
_manifest_json_toplevel_version_line() {
    awk '
        BEGIN { depth = 0; in_str = 0; esc = 0 }
        {
            line = $0
            m = length(line)
            p = 1
            while (p <= m) {
                c = substr(line, p, 1)
                if (in_str) {
                    if (esc) { esc = 0; p++; continue }
                    if (c == "\\") { esc = 1; p++; continue }
                    if (c == "\"") { in_str = 0; p++; continue }
                    p++; continue
                }
                if (c == "\"") {
                    q = p + 1
                    tok = ""
                    while (q <= m) {
                        cq = substr(line, q, 1)
                        if (cq == "\\") { q += 2; continue }
                        if (cq == "\"") break
                        tok = tok cq
                        q++
                    }
                    if (q > m) { in_str = 1; p = m + 1; continue }
                    if (depth == 1 && tok == "version") {
                        r = q + 1
                        while (r <= m && (substr(line, r, 1) == " " || substr(line, r, 1) == "\t")) r++
                        if (substr(line, r, 1) == ":") { print NR; exit }
                    }
                    p = q + 1
                    continue
                }
                if (c == "{" || c == "[") { depth++; p++; continue }
                if (c == "}" || c == "]") { depth--; p++; continue }
                p++
            }
        }
    ' "$1"
}

_manifest_toml_toplevel_version_line() {
    awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        /^[[:space:]]*\[/ { exit }
        /^[[:space:]]*version[[:space:]]*=/ { print NR; exit }
    ' "$1"
}

_manifest_yaml_toplevel_version_line() {
    awk '
        /^version:[[:space:]]*[^[:space:]#]/ { print NR; exit }
    ' "$1"
}

_manifest_replace_line() {
    local target="$1"
    local line_number="$2"
    local replacement="$3"
    local tmp="${target}.manifest-sync.tmp"

    if awk -v n="$line_number" -v repl="$replacement" 'NR == n { print repl; next } { print }' "$target" > "$tmp" 2>/dev/null && mv "$tmp" "$target"; then
        return 0
    fi

    rm -f "$tmp" 2>/dev/null
    return 1
}

_manifest_toml_version_replacement_line() {
    local line_text="$1"
    local new_version="$2"
    local double_re='^([[:space:]]*version[[:space:]]*=[[:space:]]*")([^"]*)(".*)$'
    local single_re="^([[:space:]]*version[[:space:]]*=[[:space:]]*')([^']*)('.*)$"

    if [[ "$line_text" =~ $double_re ]]; then
        printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_version" "${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "$line_text" =~ $single_re ]]; then
        printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_version" "${BASH_REMATCH[3]}"
        return 0
    fi

    return 1
}

_manifest_yaml_version_replacement_line() {
    local line_text="$1"
    local new_version="$2"
    local double_re='^(version:[[:space:]]*")([^"]*)(".*)$'
    local single_re="^(version:[[:space:]]*')([^']*)('.*)$"
    local bare_comment_re='^(version:[[:space:]]*)([0-9A-Za-z]([^#]*[^[:space:]])?)([[:space:]]+#.*)$'
    local bare_re='^(version:[[:space:]]*)([0-9A-Za-z]([^#]*[^[:space:]])?)([[:space:]]*)$'

    if [[ "$line_text" =~ $double_re ]]; then
        printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_version" "${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "$line_text" =~ $single_re ]]; then
        printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_version" "${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "$line_text" =~ $bare_comment_re ]]; then
        printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_version" "${BASH_REMATCH[4]}"
        return 0
    fi
    if [[ "$line_text" =~ $bare_re ]]; then
        printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_version" "${BASH_REMATCH[4]}"
        return 0
    fi

    return 1
}

_manifest_version_sync_rewrite_line() {
    local target="$1"
    local line_number="$2"
    local new_version="$3"
    local format="$4"
    local line_text=""
    local replacement=""

    line_text="$(sed -n "${line_number}p" "$target")"
    case "$format" in
        toml)
            replacement="$(_manifest_toml_version_replacement_line "$line_text" "$new_version")" || return 1
            ;;
        yaml)
            replacement="$(_manifest_yaml_version_replacement_line "$line_text" "$new_version")" || return 1
            ;;
        *)
            return 1
            ;;
    esac

    _manifest_replace_line "$target" "$line_number" "$replacement"
}

# Mirror the canonical version into the opt-in version.sync targets. JSON,
# TOML, and YAML package/version files are rewritten via surgical single-line
# edits of a top-level version field, so diffs stay small and existing
# formatting is preserved where practical.
# Fail-closed: a missing file or a missing top-level "version" field is skipped,
# never created. Targets resolve relative to the cwd (the repo root during a bump).
manifest_version_sync_apply() {
    local new_version="$1"
    # Validate a safe semver shape before the value ever reaches a sed
    # replacement string: the helper trusts its caller, and a "/", "&" or "\"
    # in the value would corrupt the substitution. Callers pass clean
    # integer-arithmetic semver today; this fail-closes loudly if that changes.
    if ! [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]]; then
        echo "   ⚠️  version.sync: refusing unsafe version string '${new_version}' — skipped"
        return 1
    fi
    local target
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        if [ ! -f "$target" ]; then
            echo "   ⚠️  version.sync: $target not found — skipped"
            continue
        fi
        case "$target" in
            *.json)
                local _line
                _line="$(_manifest_json_toplevel_version_line "$target")"
                if [ -z "$_line" ]; then
                    echo "   ⚠️  version.sync: no top-level \"version\" field in $target — skipped"
                    continue
                fi
                # Rewrite ONLY the located top-level "version" line. Depth-aware
                # targeting (above) replaces the old 1,/"version":/ range, which
                # silently rewrote a nested "version" that sorted first. Portable
                # across BSD/GNU sed (numeric line address + -E, no GNU-only
                # 0,/re/ and no in-place -i flag — this helper can run before the
                # §5.11 GNU-userland PATH prepend), so we edit via a temp file.
                local _tmp="${target}.manifest-sync.tmp"
                if sed -E "${_line}s/(\"version\"[[:space:]]*:[[:space:]]*\")[^\"]*\"/\\1${new_version}\"/" "$target" > "$_tmp" 2>/dev/null && mv "$_tmp" "$target"; then
                    echo "   ✅ version.sync: $target -> $new_version"
                else
                    rm -f "$_tmp" 2>/dev/null
                    echo "   ⚠️  version.sync: failed to update $target"
                fi
                ;;
            *.toml)
                local _line
                _line="$(_manifest_toml_toplevel_version_line "$target")"
                if [ -z "$_line" ]; then
                    echo "   ⚠️  version.sync: no top-level \"version\" field in $target — skipped"
                    continue
                fi
                if _manifest_version_sync_rewrite_line "$target" "$_line" "$new_version" "toml"; then
                    echo "   ✅ version.sync: $target -> $new_version"
                else
                    echo "   ⚠️  version.sync: failed to update $target"
                fi
                ;;
            *.yaml|*.yml)
                local _line
                _line="$(_manifest_yaml_toplevel_version_line "$target")"
                if [ -z "$_line" ]; then
                    echo "   ⚠️  version.sync: no top-level \"version\" field in $target — skipped"
                    continue
                fi
                if _manifest_version_sync_rewrite_line "$target" "$_line" "$new_version" "yaml"; then
                    echo "   ✅ version.sync: $target -> $new_version"
                else
                    echo "   ⚠️  version.sync: failed to update $target"
                fi
                ;;
            *)
                echo "   ⚠️  version.sync: $target type not supported (JSON/TOML/YAML only) — skipped"
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

# Guard (runs right after a bulk `git add .`): unstage any NEWLY captured bare
# gitlink. A nested directory carrying its own `.git` but no .gitmodules entry
# gets recorded by a bulk add as a mode-160000 pointer to a foreign repo's
# commit — almost always an accident (separate repos nested under a tracked
# parent path), and from then on the parent reports phantom "modified" status
# every time the inner repo advances. Disposition per staged gitlink:
#   - declared submodule (.gitmodules lists the path)  → untouched, silent
#   - already tracked in HEAD                          → left staged (pointer
#     bumps keep today's behavior), notice recommends untrack + ignore
#   - new capture                                      → unstaged + notice
# Opt out with git.allow_new_gitlinks=true (MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS)
# to record bare gitlinks intentionally. Never blocks; skip-and-notice,
# consistent with the notice-not-prompt consent model. Sets
# MANIFEST_CLI_GITLINKS_SKIPPED_COUNT so callers can tell "index emptied by the
# guard" apart from "caller staged nothing".
#
# ARGUMENTS:
#   $1 - repo path (default ".") so callers using `git -C <path>` match.
#   $2 - line prefix (default "   ") for alignment / per-repo labeling.
manifest_unstage_accidental_gitlinks() {
    local repo="${1:-.}"
    local prefix="${2:-   }"
    export MANIFEST_CLI_GITLINKS_SKIPPED_COUNT=0
    if is_truthy "${MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS:-false}"; then
        return 0
    fi

    # Staged gitlinks: `ls-files --stage` lines are "mode sha stage<TAB>path".
    local _gl_entries=() _line _path _mode _sha _stage
    while IFS= read -r _line; do
        [[ "$_line" == 160000\ * ]] || continue
        _path="${_line#*$'\t'}"
        read -r _mode _sha _stage <<< "${_line%%$'\t'*}"
        [[ -n "$_path" && -n "$_sha" ]] && _gl_entries+=("${_sha}"$'\t'"${_path}")
    done < <(git -C "$repo" ls-files --stage 2>/dev/null)
    [[ ${#_gl_entries[@]} -gt 0 ]] || return 0

    # Declared submodule paths are legitimate gitlinks; never touch them.
    local _submodule_paths=$'\n' _key _val
    if [[ -f "$repo/.gitmodules" ]]; then
        while read -r _key _val; do
            [[ -n "$_val" ]] && _submodule_paths+="${_val}"$'\n'
        done < <(git -C "$repo" config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null)
    fi

    local _has_head=false
    git -C "$repo" rev-parse -q --verify HEAD >/dev/null 2>&1 && _has_head=true

    local _entry _head_entry _head_mode _head_type _head_sha
    for _entry in "${_gl_entries[@]}"; do
        _sha="${_entry%%$'\t'*}"
        _path="${_entry#*$'\t'}"
        [[ "$_submodule_paths" == *$'\n'"$_path"$'\n'* ]] && continue
        if [[ "$_has_head" == "true" ]]; then
            _head_entry="$(git -C "$repo" ls-tree HEAD -- "$_path" 2>/dev/null)"
            if [[ "$_head_entry" == 160000\ * ]]; then
                # Tracked bare gitlink: pointer bumps keep today's behavior but
                # get a notice; an unchanged pointer commits nothing — silent.
                read -r _head_mode _head_type _head_sha <<< "${_head_entry%%$'\t'*}"
                if [[ "$_head_sha" != "$_sha" ]]; then
                    echo "${prefix}⚠️  Bare gitlink already tracked: $_path — this commit moves its pinned commit; to stop tracking it: git rm --cached $_path + a .gitignore rule"
                fi
                continue
            fi
            git -C "$repo" reset -q HEAD -- "$_path" 2>/dev/null
        else
            # Unborn HEAD: rm --cached needs -f (no HEAD to verify against);
            # it only drops the index entry, the working dir is untouched.
            git -C "$repo" rm --cached -q -f -- "$_path" 2>/dev/null
        fi
        MANIFEST_CLI_GITLINKS_SKIPPED_COUNT=$((MANIFEST_CLI_GITLINKS_SKIPPED_COUNT + 1))
        echo "${prefix}⚠️  Skipped nested git repo: $_path (own .git, no .gitmodules entry — a bulk add would commit it as a bare gitlink)"
        echo "${prefix}   Keep it a separate repo (.gitignore rule: /$_path/), declare a real submodule, or set git.allow_new_gitlinks=true to record the pointer."
    done
    return 0
}
export -f manifest_unstage_accidental_gitlinks

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
    cd "$MANIFEST_CLI_PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $MANIFEST_CLI_PROJECT_ROOT"
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
    # Drop accidental bare-gitlink captures before they enter the commit.
    manifest_unstage_accidental_gitlinks
    if [[ "${MANIFEST_CLI_GITLINKS_SKIPPED_COUNT:-0}" -gt 0 ]] && git diff --cached --quiet 2>/dev/null; then
        echo "✅ Nothing to commit (only skipped nested git repos)"
        return 0
    fi
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
            # Deprecated alias for release_head. "Final" suggested downstream
            # publish work such as the tap formula belonged in the CLI release
            # tag; release_head is the precise in-repo boundary.
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
    # Idempotent prefixing: a VERSION file may already be prefix-prefixed
    # (e.g. v-prefixed CalVer like "v25.2.0"). Strip a single leading copy of
    # the configured prefix before prepending so "v25.2.0" with prefix "v"
    # yields "v25.2.0", never "vv25.2.0".
    if [[ -n "$tag_prefix" && "$version" == "$tag_prefix"* ]]; then
        version="${version#"$tag_prefix"}"
    fi
    echo "${tag_prefix}${version}${tag_suffix}"
}

# Echo the normalized tag-signing policy (release.tag_signing /
# MANIFEST_CLI_RELEASE_TAG_SIGNING). Rejects unknown values (return 2) so a typo
# can never silently weaken signing.
#   required  sign the tag; FAIL CLOSED if no signing key is configured
#   auto      sign when a key is configured, annotated-unsigned otherwise (default)
#   off       never sign (explicit escape hatch, like release_gate=none)
manifest_release_tag_signing_policy() {
    local norm
    norm="$(normalize_enum_value "${MANIFEST_CLI_RELEASE_TAG_SIGNING:-auto}")"
    case "$norm" in
        required|auto|off) printf '%s' "$norm" ;;
        *)
            log_error "Invalid release_tag_signing '${MANIFEST_CLI_RELEASE_TAG_SIGNING}'. Expected: required, auto, off."
            return 2
            ;;
    esac
}

# Resolve how a tag should be signed in the current repo, echoing one of:
#   ssh:<key>   sign with SSH; <key> is the resolved user.signingkey
#   gpg         sign with GPG (git's default format); a key is configured
#   none        no signing material is configured
#
# Honors gpg.format (ssh|openpgp). For SSH, user.signingkey must be present (it
# is the literal key or a path to one). For GPG, signing works off the configured
# user.signingkey OR the default secret key bound to user.email, so the presence
# check is necessarily best-effort: an explicit user.signingkey is treated as
# configured, otherwise we report none and let the policy decide.
manifest_git_tag_signing_method() {
    local repo="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local fmt signingkey
    fmt="$(git -C "$repo" config --get gpg.format 2>/dev/null || echo "openpgp")"
    signingkey="$(git -C "$repo" config --get user.signingkey 2>/dev/null || echo "")"

    case "$fmt" in
        ssh)
            if [[ -n "$signingkey" ]]; then
                printf 'ssh:%s' "$signingkey"
            else
                printf 'none'
            fi
            ;;
        *)
            if [[ -n "$signingkey" ]]; then
                printf 'gpg'
            else
                printf 'none'
            fi
            ;;
    esac
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
    cd "$MANIFEST_CLI_PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $MANIFEST_CLI_PROJECT_ROOT"
        return 1
    }

    local signing_policy
    signing_policy="$(manifest_release_tag_signing_policy)" || return 1

    # Decide signing arguments. A signed tag is annotated, so it always carries a
    # message; an unsigned tag stays lightweight to preserve prior behavior.
    local -a sign_args=()
    local annotate=false
    if [[ "$signing_policy" != "off" ]]; then
        local method
        method="$(manifest_git_tag_signing_method "$MANIFEST_CLI_PROJECT_ROOT")"
        case "$method" in
            ssh:*)
                sign_args=(-c gpg.format=ssh -c "user.signingkey=${method#ssh:}")
                annotate=true
                echo "   Signing: SSH"
                ;;
            gpg)
                annotate=true
                echo "   Signing: GPG"
                ;;
            none)
                if [[ "$signing_policy" == "required" ]]; then
                    log_error "Tag signing is required (release_tag_signing=required) but no signing key is configured."
                    log_error "Configure SSH signing (git config gpg.format ssh; git config user.signingkey <key>)"
                    log_error "or GPG signing (git config user.signingkey <key>), or set release_tag_signing=off to opt out."
                    return 1
                fi
                echo "   Signing: none (no signing key configured; creating an unsigned tag)"
                ;;
        esac
    fi

    local tag_status=0
    if [[ "$annotate" == "true" ]]; then
        local tag_message="${tag_name}"
        if [[ -n "$target_sha" ]]; then
            git "${sign_args[@]}" tag -s -m "$tag_message" "$tag_name" "$target_sha"
            tag_status=$?
        else
            git "${sign_args[@]}" tag -s -m "$tag_message" "$tag_name"
            tag_status=$?
        fi
    elif [[ -n "$target_sha" ]]; then
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
        if [[ "$annotate" == "true" ]]; then
            log_error "Signed tag creation failed; the signing key may be unavailable or rejected."
        fi
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
    cd "$MANIFEST_CLI_PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $MANIFEST_CLI_PROJECT_ROOT"
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
    cd "$MANIFEST_CLI_PROJECT_ROOT" || {
        echo "❌ Failed to change to project root: $MANIFEST_CLI_PROJECT_ROOT"
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
