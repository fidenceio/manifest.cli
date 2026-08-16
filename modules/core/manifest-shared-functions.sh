#!/bin/bash

# Manifest Shared Functions Module
# Centralized functions used across multiple modules with clear separation of concerns

# =============================================================================
# VERSION MANAGEMENT FUNCTIONS
# =============================================================================

# Get current version from VERSION file
get_current_version() {
    if [ -f "$MANIFEST_CLI_PROJECT_ROOT/VERSION" ]; then
        cat "$MANIFEST_CLI_PROJECT_ROOT/VERSION" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# THE version arithmetic. Pure: takes a version STRING, echoes the next one,
# touches no file and prints no diagnostics (callers report in their own voice).
#
# Every version bump in the CLI resolves here — the repo writer (bump_version),
# the ship plan and interactive previews (get_next_version), the fleet-level
# bump (_fleet_next_version) and the status preview (_status_preview_bump).
# There were five separate copies and they agreed only while every version had
# exactly three segments, which is every repo right up until someone runs
# `ship repo revision` once. From 20.1.0.3 a `patch` produced 20.1.1.3 in the
# plan, 20.1.0.4 in the dry-run and 20.1.1 on disk. Do not add a sixth copy.
#
# ARBITRARY ARITY. A version is a list of numeric segments of any length, and
# bump levels are POSITIONAL: major=1, minor=2, patch=3, revision=4. Nothing
# here counts to three or four. The copies that did read the tail into a single
# trailing name, so 1.2.3.4.5 arrived as revision="4.5" and the arithmetic
# failed into 1.2.3 — a LOWER version than it started from, silently.
#
# Segments right of the bumped one are SUBORDINATE and do not survive it:
# 20.1.0.3 means "third revision of 20.1.0", so a patch lands on 20.1.1, which
# has had no revisions. Carrying it (20.1.1.3) would name a third revision of a
# patch whose first and second never existed; 21.0.0.3 asserts that about an
# entire major line.
#
# Returns non-zero without output for an unknown increment type or a version
# that is not a list of non-negative integers.
manifest_version_next() {
    local current_version="$1"
    local increment_type="$2"
    local separator="${3:-${MANIFEST_CLI_VERSION_SEPARATOR:-.}}"

    local level
    level="$(manifest_version_level "$increment_type")" || return 1

    local -a seg=()
    manifest_version_segments_into seg "$current_version" "$separator" || return 1

    # Pad so the target segment exists (revision from 1.2.3 -> 1.2.3.0).
    while [ "${#seg[@]}" -lt "$level" ]; do
        seg+=(0)
    done

    seg[level-1]=$(( ${seg[level-1]} + 1 ))

    # Zero any segment between the target and the minimum length, then drop
    # everything beyond. The minimum is the shape every consumer's version
    # pattern expects (see _MANIFEST_CLI_VERSION_ERE), so `major` yields 21.0.0,
    # not 21.
    local floor="${MANIFEST_CLI_VERSION_MIN_SEGMENTS:-3}"
    local keep=$(( level > floor ? level : floor ))
    local i
    for (( i = level; i < keep; i++ )); do
        seg[i]=0
    done
    seg=("${seg[@]:0:keep}")

    local IFS="$separator"
    echo "${seg[*]}"
}

# File-reading wrapper: the next version for the repo rooted at the current
# directory. Reports in the CLI's voice; the arithmetic is manifest_version_next.
get_next_version() {
    local increment_type="$1"
    local current_version=""

    # Read current version
    if [ -f "VERSION" ]; then
        current_version=$(cat VERSION 2>/dev/null || echo "1.0.0")
    else
        current_version="1.0.0"
    fi

    if ! manifest_version_level "$increment_type" >/dev/null; then
        show_validation_error "Invalid increment type: $increment_type"
        return 1
    fi

    local next
    if ! next="$(manifest_version_next "$current_version" "$increment_type")"; then
        show_validation_error "Unusable version '$current_version' — expected numbers separated by '${MANIFEST_CLI_VERSION_SEPARATOR:-.}'"
        return 1
    fi
    echo "$next"
}

# Names for the leading segment positions, in order. Config: `version.components`
# (env MANIFEST_CLI_VERSION_COMPONENTS), accepted as a bash array or a
# comma-separated string, matching _manifest_version_sync_targets.
#
# This is an ALIAS TABLE, not the set of levels that exist. The arithmetic
# addresses segments by NUMBER and has no upper bound, so a 7-segment version is
# bumped at its 7th segment by passing 7 whether or not position 7 has a name.
# Naming is a convenience over the positional truth, which is why a name's
# position is simply its index in this list — there is no second place to state
# it and therefore no way for the two to disagree.
#
# The standard four are the default, and are themselves overridable: a project
# that versions as `generation.major.minor.patch` sets
# `version.components: "generation,major,minor,patch"` and `manifest ship repo
# major` then addresses segment 2.
_MANIFEST_CLI_VERSION_COMPONENTS_DEFAULT=(major minor patch revision)

_manifest_version_component_names() {
    local decl
    decl="$(declare -p MANIFEST_CLI_VERSION_COMPONENTS 2>/dev/null || true)"
    case "$decl" in
        declare\ -a*|declare\ -ax*)
            printf '%s\n' "${MANIFEST_CLI_VERSION_COMPONENTS[@]}"
            return 0
            ;;
    esac

    local raw="${MANIFEST_CLI_VERSION_COMPONENTS:-}"
    if [ -z "$raw" ]; then
        printf '%s\n' "${_MANIFEST_CLI_VERSION_COMPONENTS_DEFAULT[@]}"
        return 0
    fi

    local item
    local -a items=()
    IFS=',' read -r -a items <<< "$raw"
    for item in "${items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [ -n "$item" ] && printf '%s\n' "$item"
    done
}

# Emit the validated, ordered component names, one per line. Fails (with a
# diagnostic on stderr) on a name list that cannot be resolved unambiguously.
# A bad list must stop the release rather than fall back to the defaults: silently
# substituting `major,minor,patch,revision` for a project that configured
# `generation,major,minor,patch` would cut the release one segment off target.
manifest_version_components() {
    # An empty element in a POSITIONAL list is not a harmless blank: dropping it
    # shifts every name after it one segment left, so "major,,minor" would
    # quietly resolve minor to segment 2. (Unset/empty entirely is different —
    # that means "not configured" and yields the defaults.)
    local raw="${MANIFEST_CLI_VERSION_COMPONENTS:-}"
    if [ -n "$raw" ] && [[ "$raw" == *,* ]]; then
        case ",${raw// /}," in
            *,,*)
                echo "version.components: empty entry in '$raw' — a position cannot be left blank" >&2
                return 1
                ;;
        esac
    fi

    local -a names=()
    local n
    while IFS= read -r n; do
        [ -n "$n" ] && names+=("$n")
    done < <(_manifest_version_component_names)

    if [ "${#names[@]}" -eq 0 ]; then
        echo "version.components is empty — expected an ordered list of segment names" >&2
        return 1
    fi

    local i j
    for (( i = 0; i < ${#names[@]}; i++ )); do
        # An all-digit name is unusable: it cannot be told apart from the
        # segment number it would compete with.
        case "${names[i]}" in
            ''|*[!0-9]*) ;;
            *)
                echo "version.components: '${names[i]}' is all digits and would collide with segment numbering" >&2
                return 1
                ;;
        esac
        case "${names[i]}" in
            *[!a-zA-Z0-9_-]*)
                echo "version.components: '${names[i]}' contains unsupported characters (use letters, digits, '_' or '-')" >&2
                return 1
                ;;
        esac
        for (( j = 0; j < i; j++ )); do
            if [ "${names[i]}" = "${names[j]}" ]; then
                echo "version.components: '${names[i]}' is listed twice; a name must address one segment" >&2
                return 1
            fi
        done
    done

    printf '%s\n' "${names[@]}"
}

# Resolve an increment type to a 1-based segment index. Accepts a configured
# component name or any positive integer. Echoes the index; returns non-zero,
# echoing nothing, for anything else.
#
# Keeping this separate is the point: hard-coupling four words to four positions
# inside the arithmetic capped it at four segments, which is how a 5-segment
# version ended up unreachable by every increment type the CLI had.
manifest_version_level() {
    local level="$1"

    # A bare positive integer addresses that segment directly, named or not.
    case "$level" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$level" -ge 1 ]; then
                echo "$level"
                return 0
            fi
            return 1
            ;;
    esac

    local -a names=()
    local n
    while IFS= read -r n; do
        [ -n "$n" ] && names+=("$n")
    done < <(manifest_version_components) || return 1
    [ "${#names[@]}" -gt 0 ] || return 1

    local i
    for (( i = 0; i < ${#names[@]}; i++ )); do
        if [ "$level" = "${names[i]}" ]; then
            echo "$(( i + 1 ))"
            return 0
        fi
    done
    return 1
}

# Split VERSION_STRING into its numeric segments and assign them to the caller's
# array ARRAY_NAME. Returns non-zero, assigning nothing, when the string is not
# a separator-delimited list of non-negative integers.
#
# Refusing malformed input is the point. Bash arithmetic reads "3-rc1" as
# "3 - rc1" with rc1 an unset variable, so a prerelease version silently bumped
# to 1.2.4 as though the suffix were not there; a version carrying anything
# unexpected must stop the release, not be coerced into a plausible-looking
# wrong answer.
#
# Usage:  local -a seg=(); manifest_version_segments_into seg "1.2.3" "."
manifest_version_segments_into() {
    local __mvs_target="$1"
    local version="$2"
    local separator="${3:-${MANIFEST_CLI_VERSION_SEPARATOR:-.}}"

    # Trim surrounding whitespace (VERSION files carry a trailing newline).
    version="${version#"${version%%[![:space:]]*}"}"
    version="${version%"${version##*[![:space:]]}"}"
    [ -n "$version" ] || return 1

    local -a parts=()
    local IFS="$separator"
    read -r -a parts <<< "$version"
    [ "${#parts[@]}" -gt 0 ] || return 1

    local p
    for p in "${parts[@]}"; do
        # Non-negative integers only. Rejects "", "1a", "-1", "3-rc1", "01x".
        case "$p" in
            ''|*[!0-9]*) return 1 ;;
        esac
    done

    eval "$__mvs_target=(\"\${parts[@]}\")"
    return 0
}

# Get latest version from GitHub API with OS-dependent timeout
get_latest_version() {
    local repo_url="${MANIFEST_CLI_REPO_URL:-https://api.github.com/repos/fidenceio/fidenceio.manifest.cli/releases/latest}"
    
    # Use OS-dependent timeout strategy
    local timeout_cmd=""
    case "${MANIFEST_CLI_OS:-Unknown}" in
        "macOS")
            if command -v gtimeout >/dev/null 2>&1; then
                timeout_cmd="gtimeout"
            fi
            ;;
        "Linux"|"FreeBSD"|"OpenBSD"|"NetBSD")
            if command -v timeout >/dev/null 2>&1; then
                timeout_cmd="timeout"
            fi
            ;;
    esac
    
    # Try to get latest version from GitHub API with timeout
    if command -v curl >/dev/null 2>&1; then
        local latest_version=""
        local timeout_seconds="${MANIFEST_CLI_UPDATE_TIMEOUT:-10}"
        
        # Use secure curl request
        latest_version=$(secure_curl_request "$repo_url" "$timeout_seconds" 2>/dev/null | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$latest_version" ]; then
            echo "$latest_version"
            return 0
        fi
    fi
    
    # Fallback: return current version
    get_current_version
}

manifest_origin_repo_slug() {
    local repo_url=""
    repo_url="$(git -C "${1:-$MANIFEST_CLI_PROJECT_ROOT}" remote get-url origin 2>/dev/null || echo "")"

    if [[ "$repo_url" =~ ^git@[^:]+:([^/]+)/([^/]+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "$repo_url" =~ ^https?://[^/]+/([^/]+)/([^/]+)$ ]]; then
        local org="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]%.git}"
        echo "${org}/${repo}"
        return 0
    fi

    echo ""
    return 1
}

manifest_is_canonical_repo() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local origin_slug=""
    origin_slug="$(manifest_origin_repo_slug "$project_root" || echo "")"

    local allowed_slugs=""
    if [[ -n "${MANIFEST_CLI_CANONICAL_REPO_SLUGS:-}" ]]; then
        allowed_slugs="$MANIFEST_CLI_CANONICAL_REPO_SLUGS"
    else
        allowed_slugs="fidenceio/manifest.cli,fidenceio/fidenceio.manifest.cli"
    fi
    IFS=',' read -r -a allowed_array <<< "$allowed_slugs"
    local allowed=""
    for allowed in "${allowed_array[@]}"; do
        if [ "$origin_slug" = "$allowed" ]; then
            return 0
        fi
    done

    if [[ -f "$project_root/install-cli.sh" ]] && [[ -f "$project_root/scripts/manifest-cli-wrapper.sh" ]] && [[ -f "$project_root/formula/manifest.rb" ]] && [[ -d "$project_root/modules" ]]; then
        return 0
    fi

    return 1
}

manifest_repo_display_name() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    if manifest_is_canonical_repo "$project_root"; then
        echo "${MANIFEST_CLI_PROJECT_NAME:-Manifest CLI}"
        return 0
    fi

    if [[ -n "${MANIFEST_CLI_PROJECT_NAME:-}" ]] && [[ "${MANIFEST_CLI_PROJECT_NAME}" != "Manifest CLI" ]]; then
        echo "$MANIFEST_CLI_PROJECT_NAME"
        return 0
    fi

    basename "$project_root"
}

manifest_exec_manifest() {
    local -a env_args=(env -u MANIFEST_CLI_BASH_REEXEC)

    # Preserve the release recursion guard when callers set it as a shell-local
    # temporary assignment before invoking this function.
    if [[ -n "${MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE:-}" ]]; then
        env_args+=("MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE=$MANIFEST_CLI_SHIP_FOLLOWUP_PATCH_ACTIVE")
    fi

    "${env_args[@]}" manifest "$@"
}

manifest_git_safe_fast_forward_checkout() {
    local checkout_dir="$1"
    local expected_slug="${2:-}"
    local branch="${3:-main}"
    local remote="${4:-origin}"

    if [[ -z "$checkout_dir" || ! -d "$checkout_dir" ]]; then
        echo "missing"
        return 2
    fi

    if ! git -C "$checkout_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "not_git"
        return 2
    fi

    local origin_slug=""
    origin_slug="$(manifest_origin_repo_slug "$checkout_dir" || echo "")"
    if [[ -n "$expected_slug" && "$origin_slug" != "$expected_slug" ]]; then
        echo "wrong_remote:${origin_slug:-unknown}"
        return 2
    fi

    local current_branch=""
    current_branch="$(git -C "$checkout_dir" symbolic-ref --short -q HEAD 2>/dev/null || echo "")"
    if [[ "$current_branch" != "$branch" ]]; then
        echo "wrong_branch:${current_branch:-detached}"
        return 2
    fi

    if [[ -n "$(git -C "$checkout_dir" status --porcelain 2>/dev/null)" ]]; then
        echo "dirty"
        return 2
    fi

    if ! git -C "$checkout_dir" fetch "$remote" "$branch" >/dev/null 2>&1; then
        echo "fetch_failed"
        return 1
    fi

    local local_rev remote_rev base_rev
    local_rev="$(git -C "$checkout_dir" rev-parse HEAD 2>/dev/null || echo "")"
    remote_rev="$(git -C "$checkout_dir" rev-parse "$remote/$branch" 2>/dev/null || echo "")"
    base_rev="$(git -C "$checkout_dir" merge-base HEAD "$remote/$branch" 2>/dev/null || echo "")"

    if [[ -z "$local_rev" || -z "$remote_rev" || -z "$base_rev" ]]; then
        echo "rev_check_failed"
        return 1
    fi

    if [[ "$local_rev" == "$remote_rev" ]]; then
        echo "current"
        return 0
    fi

    if [[ "$base_rev" != "$local_rev" ]]; then
        echo "divergent"
        return 2
    fi

    if git -C "$checkout_dir" merge --ff-only "$remote/$branch" >/dev/null 2>&1; then
        echo "updated"
        return 0
    fi

    echo "ff_failed"
    return 1
}

# -----------------------------------------------------------------------------
# Function: _manifest_require_gh
# -----------------------------------------------------------------------------
# Verify the GitHub CLI is installed and authenticated. Used by any command
# that talks to GitHub via `gh` (init/prep --create-repo-*, manifest pr ...).
#
# Memoizes the success result for MANIFEST_CLI_GH_VALIDATION_TTL seconds (default
# 300) so a fleet loop calling this N times pays the `gh auth status` cost
# once. The TTL bounds staleness if `gh` is uninstalled or auth changes
# mid-session; failures are never cached.
# -----------------------------------------------------------------------------
_manifest_require_gh() {
    local ttl="${MANIFEST_CLI_GH_VALIDATION_TTL:-300}"
    local now
    now=$(date +%s)
    if [[ -n "${_MANIFEST_GH_VALIDATED_AT:-}" ]] \
        && (( now - _MANIFEST_GH_VALIDATED_AT < ttl )); then
        return 0
    fi
    if ! command -v gh >/dev/null 2>&1; then
        log_error "'gh' (GitHub CLI) is required for this command."
        log_error "Install: brew install gh   then: gh auth login"
        return 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        log_error "'gh' is not authenticated. Run: gh auth login"
        return 1
    fi
    _MANIFEST_GH_VALIDATED_AT=$now
    return 0
}

# -----------------------------------------------------------------------------
# Function: _manifest_dir_is_own_git_repository
# -----------------------------------------------------------------------------
# Returns success only when DIR owns Git metadata itself. A plain `git -C DIR`
# probe is not sufficient: Git walks upward and will happily report a parent
# repository for an ordinary child directory.
# -----------------------------------------------------------------------------
_manifest_dir_is_own_git_repository() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1

    # Normal repositories and linked worktrees/submodules respectively.
    [[ -d "$dir/.git" ]] && return 0
    [[ -f "$dir/.git" ]] && return 0

    # Bare repository support (kept aligned with manifest-discovery.sh).
    [[ -f "$dir/HEAD" && -d "$dir/objects" && -d "$dir/refs" ]]
}

# -----------------------------------------------------------------------------
# Function: manifest_github_owner_from_origin
# -----------------------------------------------------------------------------
# The owner half of origin's slug, or empty when the repo has no origin remote
# (or its URL is not a recognizable owner/name form). URL parsing is delegated
# to manifest_origin_repo_slug so this file keeps exactly one origin parser.
# -----------------------------------------------------------------------------
manifest_github_owner_from_origin() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"

    # Only an origin the directory OWNS may speak for it. `git -C DIR` walks
    # upward, so a member nested in a fleet root would otherwise inherit the
    # parent's namespace and create its repo in the wrong org.
    _manifest_dir_is_own_git_repository "$project_root" || return 0

    local slug=""
    slug="$(manifest_origin_repo_slug "$project_root" 2>/dev/null || true)"
    [[ "$slug" == */* ]] || return 0
    printf '%s\n' "${slug%%/*}"
}

# -----------------------------------------------------------------------------
# Function: manifest_resolve_github_owner
# -----------------------------------------------------------------------------
# The effective GitHub owner, in precedence order:
#   1. github.owner when set — an explicit choice always wins.
#   2. the origin remote's owner — the repo's own git metadata is a better
#      answer than "whoever gh happens to be authenticated as", and it needs
#      no prompt to obtain.
#   3. empty, preserving gh's authenticated-user default for a repo that has
#      no origin yet (the normal state during `--create-repo-*`).
#
# Silent in every ordinary case. The one situation worth interrupting for is a
# configured owner that disagrees with origin — nearly always a config copied
# from another repo or fleet member, which would create the repo in the wrong
# namespace. Interactive runs ask; non-interactive runs warn once and keep the
# configured value, so a CI ship never blocks on stdin.
# -----------------------------------------------------------------------------
manifest_resolve_github_owner() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local configured="${MANIFEST_CLI_GITHUB_OWNER:-}"
    local origin_owner=""
    origin_owner="$(manifest_github_owner_from_origin "$project_root")"

    if [[ -z "$configured" ]]; then
        printf '%s\n' "$origin_owner"
        return 0
    fi

    if [[ -z "$origin_owner" || "$origin_owner" == "$configured" ]]; then
        printf '%s\n' "$configured"
        return 0
    fi

    # Conflict. Warn at most once per process so a fleet run reports it for the
    # member that hit it without repeating on every subsequent resolve.
    case ":${_MANIFEST_CLI_GITHUB_OWNER_CONFLICT_WARNED:-}:" in
        *":${project_root}:"*) printf '%s\n' "$configured"; return 0 ;;
    esac
    export _MANIFEST_CLI_GITHUB_OWNER_CONFLICT_WARNED="${_MANIFEST_CLI_GITHUB_OWNER_CONFLICT_WARNED:-}:${project_root}"

    # Every human-facing line goes to stderr: this function's stdout IS its
    # return value, and a stray message there lands in the caller's owner
    # variable and fails validation.
    log_warning "github.owner is '${configured}' but origin belongs to '${origin_owner}'."

    if [[ -t 0 ]] && [[ "${MANIFEST_CLI_AUTO_CONFIRM:-0}" != "1" ]]; then
        local answer=""
        # `read -p` writes its prompt to stderr already.
        read -r -p "   Use '${origin_owner}' (from origin) instead of '${configured}'? [y/N] " answer
        case "$answer" in
            [Yy]*)
                echo "   Using '${origin_owner}'. Persist it with: manifest config set --layer local github.owner ${origin_owner}" >&2
                printf '%s\n' "$origin_owner"
                return 0
                ;;
        esac
    fi

    echo "   Keeping the configured owner '${configured}'." >&2
    printf '%s\n' "$configured"
}

# -----------------------------------------------------------------------------
# Function: _manifest_github_repo_target
# -----------------------------------------------------------------------------
# Resolves the target passed to `gh repo create`. github.owner is optional; when
# it is unset the owner is taken from the origin remote, and only a repo with
# neither falls through to gh's authenticated-user default. The configured owner
# is intentionally one fleet/repo-wide value, not a per-member override map.
# -----------------------------------------------------------------------------
_manifest_github_repo_target() {
    local project_root="$1"
    local name owner
    name="$(basename "$project_root")"
    owner="$(manifest_resolve_github_owner "$project_root")"

    if [[ -z "$owner" ]]; then
        printf '%s\n' "$name"
        return 0
    fi

    if [[ ! "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ || "$owner" == *- ]]; then
        log_error "Invalid github.owner: '$owner' (expected a GitHub user or organization name)"
        return 1
    fi

    printf '%s/%s\n' "$owner" "$name"
}

_manifest_github_repo_display_target() {
    local project_root="$1"
    local target
    target="$(_manifest_github_repo_target "$project_root")" || return 1
    if [[ "$target" == */* ]]; then
        printf '%s\n' "$target"
    else
        printf '<authenticated-user>/%s\n' "$target"
    fi
}

# -----------------------------------------------------------------------------
# Function: _manifest_parse_create_repo_flag
# -----------------------------------------------------------------------------
# Resolves --create-repo-private and --create-repo-public into a single
# visibility string, enforcing mutual exclusion.
#
# Args: $1 = current visibility ("" / "private" / "public")
#       $2 = flag being applied ("private" / "public")
# Echoes new visibility on success; returns 1 (with log_error) on conflict.
# -----------------------------------------------------------------------------
_manifest_parse_create_repo_flag() {
    local current="$1"
    local incoming="$2"
    if [[ -n "$current" && "$current" != "$incoming" ]]; then
        log_error "--create-repo-private and --create-repo-public are mutually exclusive."
        return 1
    fi
    echo "$incoming"
}

# -----------------------------------------------------------------------------
# Function: _manifest_gh_repo_create
# -----------------------------------------------------------------------------
# Create a GitHub repo named after the project root's basename and add it as
# `origin`. Caller is responsible for the dir already being a git repo.
#
# Args: $1 = project_root, $2 = visibility ("private" or "public")
# Returns 0 on success, 1 on failure (with log_error).
# -----------------------------------------------------------------------------
_manifest_gh_repo_create() {
    local project_root="$1"
    local visibility="$2"
    local target

    if ! _manifest_dir_is_own_git_repository "$project_root"; then
        log_error "Cannot create a GitHub repo: target is not its own Git repository: $project_root"
        return 1
    fi

    target="$(_manifest_github_repo_target "$project_root")" || return 1

    _manifest_require_gh || return 1

    local vis_flag
    case "$visibility" in
        private) vis_flag="--private" ;;
        public)  vis_flag="--public" ;;
        *)       log_error "Invalid visibility: $visibility"; return 1 ;;
    esac

    if git -C "$project_root" remote get-url origin >/dev/null 2>&1; then
        log_warning "origin already configured — skipping gh repo create."
        echo "  Existing origin: $(git -C "$project_root" remote get-url origin)"
        return 0
    fi

    echo "  Creating GitHub repo: $target ($visibility)..."
    local create_out
    if ! create_out=$(gh repo create "$target" "$vis_flag" \
            --source="$project_root" --remote=origin 2>&1); then
        log_error "gh repo create failed for: $target"
        local last_lines
        last_lines=$(printf '%s' "$create_out" | tail -3 | tr '\n' ' ')
        echo "  $last_lines"
        echo "  Common causes: name already exists, no permission for org, auth issue."
        echo "  Manual fallback: gh repo create $target $vis_flag --source=\"$project_root\" --remote=origin"
        return 1
    fi
    local url
    url="$(git -C "$project_root" remote get-url origin 2>/dev/null || echo "")"
    if [[ -z "$url" ]]; then
        log_error "gh repo create returned success but did not configure origin: $project_root"
        return 1
    fi
    echo "  ✓ Created GitHub repo: $target"
    echo "  Origin: $url"
    return 0
}

# =============================================================================
# NETWORK AND CONNECTIVITY FUNCTIONS
# =============================================================================

# Secure curl request with security headers and validation
secure_curl_request() {
    local url="$1"
    local timeout="${2:-10}"
    local additional_args=("${@:3}")
    
    # Validate URL to prevent injection
    if ! [[ "$url" =~ ^https?:// ]]; then
        echo "Error: Invalid URL format" >&2
        return 1
    fi
    
    # Add security headers and options
    local security_args=(
        "--max-time" "$timeout"
        "--connect-timeout" "5"
        "--retry" "0"
        "--retry-delay" "0"
        "--fail"
        "--silent"
        "--show-error"
        "--location"
        "--compressed"
        "--user-agent" "Manifest-CLI/$(cat "$MANIFEST_CLI_VERSION_FILE" 2>/dev/null || echo "unknown")"
    )
    
    # Execute curl with security options
    curl "${security_args[@]}" "${additional_args[@]}" "$url"
}

# Check network connectivity with OS-dependent timeout
check_network_connectivity() {
    # Use OS-dependent timeout strategy
    local timeout_cmd=""
    case "${MANIFEST_CLI_OS:-Unknown}" in
        "macOS")
            if command -v gtimeout >/dev/null 2>&1; then
                timeout_cmd="gtimeout"
            fi
            ;;
        "Linux"|"FreeBSD"|"OpenBSD"|"NetBSD")
            if command -v timeout >/dev/null 2>&1; then
                timeout_cmd="timeout"
            fi
            ;;
    esac
    
    # Try to ping a reliable service with timeout
    local ping_timeout=3
    if [ -n "$timeout_cmd" ]; then
        if $timeout_cmd "$ping_timeout" ping -c 1 -W "$ping_timeout" 8.8.8.8 >/dev/null 2>&1; then
            log_debug "Network connectivity check passed (ping with timeout)"
            return 0
        fi
    else
        # Fallback: use ping with built-in timeout
        if ping -c 1 -W "$ping_timeout" 8.8.8.8 >/dev/null 2>&1; then
            log_debug "Network connectivity check passed (ping fallback)"
            return 0
        fi
    fi
    
    # Try alternative connectivity check with secure curl
    local curl_timeout=5
    if secure_curl_request "https://www.google.com" "$curl_timeout" >/dev/null 2>&1; then
        log_debug "Network connectivity check passed (secure curl)"
        return 0
    fi
    
    log_debug "Network connectivity check failed"
    return 1
}

# Check if required tools are available
check_required_tools() {
    local missing_tools=()
    
    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_tools+=("curl")
    fi
    
    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        show_dependency_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    log_debug "All required tools are available"
    return 0
}

# =============================================================================
# ID GENERATION AND LOGGING FUNCTIONS
# =============================================================================

# Generate unique agent ID
# Generate unique session ID
generate_session_id() {
    local timestamp=$(date +%s)
    local random=$(openssl rand -hex 8 2>/dev/null || echo "$RANDOM$RANDOM")
    echo "session-${timestamp}-${random}" | tr '[:upper:]' '[:lower:]'
}

# Log operation with timestamp
log_operation() {
    local operation="$1"
    local details="$2"
    local log_file="${3:-$HOME/.manifest-cli/logs/operations.log}"
    
    # Ensure log directory exists
    local log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir" 2>/dev/null
    
    # Log with timestamp
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - $operation: $details" >> "$log_file"
    log_debug "Operation logged: $operation"
}

# =============================================================================
# GIT OPERATIONS FUNCTIONS
# =============================================================================

# Get Git repository information
# Check if in Git repository
is_git_repository() {
    git rev-parse --git-dir >/dev/null 2>&1
}

# =============================================================================
# FILE OPERATIONS FUNCTIONS
# =============================================================================

# Validate file path to prevent directory traversal attacks
validate_file_path() {
    local file_path="$1"
    
    # Check for path traversal attempts
    if [[ "$file_path" =~ \.\./ ]] || [[ "$file_path" =~ \.\.\\ ]]; then
        return 1
    fi
    
    # Check for absolute paths outside project (if MANIFEST_CLI_PROJECT_ROOT is set)
    if [[ "$file_path" =~ ^/ ]] && [[ -n "${MANIFEST_CLI_PROJECT_ROOT:-}" ]] && [[ ! "$file_path" =~ ^$MANIFEST_CLI_PROJECT_ROOT ]]; then
        return 1
    fi
    
    # Check for null bytes or other dangerous characters
    if [[ "$file_path" =~ $'\0' ]]; then
        return 1
    fi
    
    return 0
}

# Safe file read with error handling and path validation
safe_read_file() {
    local file="$1"
    local default="${2:-}"
    
    # Validate file path to prevent traversal attacks
    if ! validate_file_path "$file"; then
        echo "Error: Invalid file path" >&2
        echo "$default"
        return 1
    fi
    
    if [ -f "$file" ] && [ -r "$file" ]; then
        cat "$file" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# Safe file write with backup and path validation
safe_write_file() {
    local file="$1"
    local content="$2"
    local backup="${3:-true}"
    
    # Validate file path to prevent traversal attacks
    if ! validate_file_path "$file"; then
        echo "Error: Invalid file path" >&2
        return 1
    fi
    
    # Create backup if requested
    if [ "$backup" = "true" ] && [ -f "$file" ]; then
        cp "$file" "$file.backup.$(date +%s)" 2>/dev/null
    fi
    
    # Write content
    echo "$content" > "$file" || {
        show_file_error "Failed to write file: $file"
        return 1
    }
    
    log_debug "File written successfully: $file"
    return 0
}

# =============================================================================
# CONFIGURATION MANAGEMENT FUNCTIONS
# =============================================================================

# Get configuration value with fallback
# Set configuration value
set_config_value() {
    local key="$1"
    local value="$2"
    local config_file="${3:-$MANIFEST_CLI_PROJECT_ROOT/.env}"

    # Ensure config directory exists
    local config_dir=$(dirname "$config_file")
    mkdir -p "$config_dir" 2>/dev/null

    case "$config_file" in
        *.yaml|*.yml)
            # YAML config: convert env var name to YAML dot-path
            local yaml_path=""
            if declare -F env_var_to_yaml_path >/dev/null 2>&1; then
                yaml_path=$(env_var_to_yaml_path "$key")
            fi
            if [ -z "$yaml_path" ]; then
                # Unknown key — write under custom section
                yaml_path="custom.${key}"
            fi
            set_yaml_value "$config_file" "$yaml_path" "$value"
            ;;
        *)
            # Legacy .env config
            if [ -f "$config_file" ]; then
                if grep -q "^${key}=" "$config_file"; then
                    sed -i.bak "s/^${key}=.*/${key}=\"${value}\"/" "$config_file"
                    rm -f "$config_file.bak" 2>/dev/null
                else
                    echo "${key}=\"${value}\"" >> "$config_file"
                fi
            else
                echo "${key}=\"${value}\"" > "$config_file"
            fi
            ;;
    esac

    log_debug "Configuration updated: $key=$value"
}

# =============================================================================
# JSON OPERATIONS FUNCTIONS
# =============================================================================

# Safe JSON read with error handling
# Safe JSON write with validation
safe_json_write() {
    local json_file="$1"
    local key="$2"
    local value="$3"
    
    # Ensure directory exists
    local json_dir=$(dirname "$json_file")
    mkdir -p "$json_dir" 2>/dev/null
    
    if command -v jq >/dev/null 2>&1; then
        # Use jq for proper JSON handling
        if [ -f "$json_file" ]; then
            jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$json_file" > "$json_file.tmp" && mv "$json_file.tmp" "$json_file"
        else
            echo "{\"$key\": \"$value\"}" > "$json_file"
        fi
    else
        # Fallback to manual JSON construction
        show_file_error "jq not available for JSON operations"
        return 1
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all shared functions
export -f get_current_version get_next_version get_latest_version
export -f manifest_origin_repo_slug manifest_is_canonical_repo manifest_repo_display_name
export -f _manifest_require_gh _manifest_dir_is_own_git_repository
export -f _manifest_github_repo_target _manifest_github_repo_display_target
export -f _manifest_parse_create_repo_flag _manifest_gh_repo_create
export -f secure_curl_request check_network_connectivity check_required_tools
export -f generate_session_id log_operation
export -f is_git_repository
export -f safe_read_file safe_write_file
export -f set_config_value
export -f safe_json_write
