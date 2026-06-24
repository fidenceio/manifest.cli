#!/bin/bash

# =============================================================================
# Manifest Status Module (Tier 4 #17)
# =============================================================================
#
# Implements: manifest status [repo|fleet]
#
# PURPOSE:
#   Read-only snapshot of "what would happen if I ship now?". Zero side
#   effects. Designed to be the first command a user runs after install.
#
# OUTPUT INCLUDES:
#   - Repo slug + canonical-repo gate result
#   - Branch / upstream sync state
#   - Working-tree pending changes
#   - Current VERSION + previews of patch/minor/major bumps
#   - Single-repo status, or a fleet repository table when run at a fleet root
#   - Config layers detected
# =============================================================================

if [[ -n "${_MANIFEST_STATUS_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_STATUS_LOADED=1

# Compute next-version preview without writing anything.
# Args: $1 current_version, $2 increment_type
_status_preview_bump() {
    local current="$1"
    local kind="$2"
    local sep="${MANIFEST_CLI_VERSION_SEPARATOR:-.}"
    # Require strict X<sep>Y<sep>Z with numeric components (BSD cut otherwise
    # echoes the whole input back when the delimiter is absent).
    if [[ "$current" != *"$sep"*"$sep"* ]]; then echo "?"; return; fi
    local major minor patch
    major=$(echo "$current" | cut -d"$sep" -f1)
    minor=$(echo "$current" | cut -d"$sep" -f2)
    patch=$(echo "$current" | cut -d"$sep" -f3)
    if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]]; then
        echo "?"; return
    fi
    case "$kind" in
        patch) echo "${major}${sep}${minor}${sep}$((patch + 1))" ;;
        minor) echo "${major}${sep}$((minor + 1))${sep}0" ;;
        major) echo "$((major + 1))${sep}0${sep}0" ;;
    esac
}

# Render a single line aligned at column 14 for label, then value.
_status_line() {
    printf "  %-12s %s\n" "$1" "$2"
}

_status_git_porcelain_counts() {
    local path="$1"
    local modified=0
    local untracked=0
    local line status_code

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        status_code="${line:0:2}"
        if [[ "$status_code" == "??" ]]; then
            untracked=$((untracked + 1))
        else
            modified=$((modified + 1))
        fi
    done < <(git -C "$path" status --porcelain 2>/dev/null || true)

    printf '%s %s\n' "$modified" "$untracked"
}

_status_fleet_config_file() {
    local proj="$1"
    if [[ -f "$proj/manifest.fleet.config.yaml" ]]; then
        echo "$proj/manifest.fleet.config.yaml"
    elif [[ -f "$proj/manifest.fleet.yaml" ]]; then
        echo "$proj/manifest.fleet.yaml"
    fi
}

# The declared roster lives in manifest.fleet.tsv (see docs/FLEET_DESIGN_SPEC.md:
# "store declared, cache the corpus, derive labels"). The fleet config YAML is a
# derived projection that can lag or be empty while the TSV is current, so status
# and identity treat the TSV as the source of truth for membership and fall back
# to the YAML only when no TSV exists.
_status_fleet_tsv_file() {
    local proj="$1"
    [[ -f "$proj/manifest.fleet.tsv" ]] && echo "$proj/manifest.fleet.tsv"
    # Explicit success: when no TSV exists the `&&` above is the function's last
    # command and returns 1, which (via `fleet_tsv="$(_status_fleet_tsv_file …)"`)
    # would trip the entry script's `set -e` and abort `manifest status` in any
    # non-fleet repo. The empty stdout already signals "no TSV" to the caller.
    return 0
}

# Split a tab-separated line into a named array, preserving empty fields. A bare
# `IFS=$'\t' read` collapses runs of tabs and drops leading/empty fields because
# tab is whitespace — so an empty REMOTE_URL column would shift BRANCH left. The
# same x1f swap the fleet TSV reader uses (manifest-fleet-detect.sh) makes the
# delimiter non-whitespace so empty columns survive.
_status_tsv_split() {
    local line="$1"
    local _arr="$2"
    local -n _ref="$_arr"
    local sep=$'\x1f'
    line="${line//$'\t'/$sep}"
    IFS="$sep" read -r -a _ref <<< "$line"
}

# Emit the selected fleet roster as tab-separated rows: NAME PATH HAS_GIT
# REMOTE_URL BRANCH. Prefers the TSV (declared roster); each emitted name is the
# member identity used by every status/identity reader. parse_start_tsv is the
# canonical TSV reader (modules/fleet/manifest-fleet-detect.sh); a self-contained
# parser keeps this readable when the fleet module is not loaded (e.g. unit tests
# sourcing manifest-status.sh alone). Falls back to the YAML `.services` map when
# no TSV exists.
_status_fleet_roster_rows() {
    local proj="$1"
    local tsv config
    tsv="$(_status_fleet_tsv_file "$proj")"

    if [[ -n "$tsv" ]]; then
        if declare -F parse_start_tsv >/dev/null 2>&1; then
            parse_start_tsv "$tsv"
            return 0
        fi
        local line fields
        while IFS= read -r line; do
            local fields=()
            _status_tsv_split "$line" fields
            local select="${fields[0]:-}"
            [[ "$select" == \#* ]] && continue
            [[ -z "$select" ]] && continue
            [[ "$select" == "true" ]] || continue
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "${fields[1]:-}" "${fields[2]:-}" "${fields[3]:-}" "${fields[4]:-}" "${fields[5]:-}"
        done < "$tsv"
        return 0
    fi

    config="$(_status_fleet_config_file "$proj")"
    [[ -n "$config" ]] || return 0
    command -v yq >/dev/null 2>&1 || return 0
    local service raw_path branch
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        raw_path="$(SERVICE="$service" yq e '.services[strenv(SERVICE)].path // ""' "$config" 2>/dev/null)"
        branch="$(SERVICE="$service" yq e '.services[strenv(SERVICE)].branch // ""' "$config" 2>/dev/null)"
        printf '%s\t%s\t%s\t%s\t%s\n' "$service" "$raw_path" "" "" "${branch:-}"
    done < <(yq e '.services | keys | .[]' "$config" 2>/dev/null)
}

# Count of declared members, sourced from the same roster the tables render.
_status_fleet_roster_count() {
    local proj="$1"
    local count=0 line
    while IFS= read -r line; do
        [[ -n "$line" ]] && count=$((count + 1))
    done < <(_status_fleet_roster_rows "$proj")
    echo "$count"
}

_manifest_repo_identity_collect() {
    local proj="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    _MANIFEST_REPO_ID_GIT_ROOT="$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null || echo "$proj")"
    _MANIFEST_REPO_ID_ORIGIN="$(manifest_origin_repo_slug "$_MANIFEST_REPO_ID_GIT_ROOT" 2>/dev/null || echo "")"
    [[ -n "$_MANIFEST_REPO_ID_ORIGIN" ]] || _MANIFEST_REPO_ID_ORIGIN="(no origin remote)"
    _MANIFEST_REPO_ID_BRANCH="$(git -C "$_MANIFEST_REPO_ID_GIT_ROOT" branch --show-current 2>/dev/null || echo "(detached)")"
    _MANIFEST_REPO_ID_UPSTREAM="$(git -C "$_MANIFEST_REPO_ID_GIT_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "")"
    _MANIFEST_REPO_ID_FLEET_ROOT=""
    _MANIFEST_REPO_ID_FLEET_NAME=""
    _MANIFEST_REPO_ID_FLEET_MEMBER=""
    _MANIFEST_REPO_ID_WARNING=""

    local configured_root="${MANIFEST_CLI_FLEET_ROOT:-}"
    if [[ -n "$configured_root" && -d "$configured_root" ]]; then
        _MANIFEST_REPO_ID_FLEET_ROOT="$(cd "$configured_root" 2>/dev/null && pwd)"
    elif declare -F find_fleet_root >/dev/null 2>&1; then
        _MANIFEST_REPO_ID_FLEET_ROOT="$(find_fleet_root "$_MANIFEST_REPO_ID_GIT_ROOT" 2>/dev/null || echo "")"
    fi

    if [[ -z "$_MANIFEST_REPO_ID_FLEET_ROOT" ]]; then
        _MANIFEST_REPO_ID_FLEET_NAME="${MANIFEST_CLI_FLEET_NAME:-}"
        _MANIFEST_REPO_ID_FLEET_MEMBER="${MANIFEST_CLI_FLEET_MEMBER:-}"
        if [[ -n "$_MANIFEST_REPO_ID_FLEET_MEMBER" ]]; then
            _MANIFEST_REPO_ID_WARNING="fleet.member hint is present but no fleet root was detected"
        fi
        return 0
    fi

    local fleet_config=""
    fleet_config="$(_status_fleet_config_file "$_MANIFEST_REPO_ID_FLEET_ROOT")"
    if [[ -n "$fleet_config" && -f "$fleet_config" && "$(command -v yq 2>/dev/null)" ]]; then
        _MANIFEST_REPO_ID_FLEET_NAME="$(yq e '.fleet.name // "fleet"' "$fleet_config" 2>/dev/null)"
    fi
    # Membership is resolved from the declared roster (TSV-first), not the config
    # `.services` map, so identity is correct even when the YAML projection is
    # stale or empty.
    local roster_line service raw_path service_path service_root
    while IFS= read -r roster_line; do
        local fields=()
        _status_tsv_split "$roster_line" fields
        service="${fields[0]:-}"
        raw_path="${fields[1]:-}"
        [[ -z "$service" ]] && continue
        service_path="$(_status_resolve_member_path "$_MANIFEST_REPO_ID_FLEET_ROOT" "$raw_path")"
        [[ -n "$service_path" ]] || continue
        service_root="$(git -C "$service_path" rev-parse --show-toplevel 2>/dev/null || echo "$service_path")"
        if [[ "$service_root" == "$_MANIFEST_REPO_ID_GIT_ROOT" ]]; then
            _MANIFEST_REPO_ID_FLEET_MEMBER="$service"
            break
        fi
    done < <(_status_fleet_roster_rows "$_MANIFEST_REPO_ID_FLEET_ROOT")

    _MANIFEST_REPO_ID_FLEET_NAME="${_MANIFEST_REPO_ID_FLEET_NAME:-${MANIFEST_CLI_FLEET_NAME:-fleet}}"
    if [[ -n "${MANIFEST_CLI_FLEET_MEMBER:-}" && -n "$_MANIFEST_REPO_ID_FLEET_MEMBER" && "${MANIFEST_CLI_FLEET_MEMBER}" != "$_MANIFEST_REPO_ID_FLEET_MEMBER" ]]; then
        _MANIFEST_REPO_ID_WARNING="fleet.member hint '${MANIFEST_CLI_FLEET_MEMBER}' does not match fleet config member '${_MANIFEST_REPO_ID_FLEET_MEMBER}'"
    elif [[ -z "$_MANIFEST_REPO_ID_FLEET_MEMBER" && -n "${MANIFEST_CLI_FLEET_MEMBER:-}" ]]; then
        _MANIFEST_REPO_ID_FLEET_MEMBER="$MANIFEST_CLI_FLEET_MEMBER (hint, unverified)"
    elif [[ -z "$_MANIFEST_REPO_ID_FLEET_MEMBER" && "$_MANIFEST_REPO_ID_GIT_ROOT" != "$_MANIFEST_REPO_ID_FLEET_ROOT" ]]; then
        _MANIFEST_REPO_ID_WARNING="Git root is inside a fleet but is not configured as a fleet member"
    fi

    if [[ "$_MANIFEST_REPO_ID_GIT_ROOT" == "$_MANIFEST_REPO_ID_FLEET_ROOT" ]]; then
        if [[ -n "$_MANIFEST_REPO_ID_WARNING" ]]; then
            _MANIFEST_REPO_ID_WARNING="${_MANIFEST_REPO_ID_WARNING}; this targets only the fleet-root repo, not ship fleet"
        else
            _MANIFEST_REPO_ID_WARNING="This targets only the fleet-root repo, not ship fleet"
        fi
    fi
}

manifest_repo_identity_block() {
    local proj="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    _manifest_repo_identity_collect "$proj"
    local current_repo="$_MANIFEST_REPO_ID_ORIGIN"
    if [[ "$current_repo" == "(no origin remote)" ]]; then
        current_repo="$(basename "$_MANIFEST_REPO_ID_GIT_ROOT")"
    fi

    echo "Repo identity"
    echo "-------------"
    _status_line "Current repo:" "$current_repo"
    _status_line "Git root:" "$_MANIFEST_REPO_ID_GIT_ROOT"
    _status_line "Origin:" "$_MANIFEST_REPO_ID_ORIGIN"
    if [[ -n "$_MANIFEST_REPO_ID_UPSTREAM" ]]; then
        _status_line "Branch:" "$_MANIFEST_REPO_ID_BRANCH → $_MANIFEST_REPO_ID_UPSTREAM"
    else
        _status_line "Branch:" "$_MANIFEST_REPO_ID_BRANCH  (no upstream)"
    fi
    if [[ -n "$_MANIFEST_REPO_ID_FLEET_ROOT" ]]; then
        _status_line "Fleet context:" "${_MANIFEST_REPO_ID_FLEET_NAME}  (${_MANIFEST_REPO_ID_FLEET_ROOT})"
        _status_line "Fleet member:" "${_MANIFEST_REPO_ID_FLEET_MEMBER:-not configured}"
    elif [[ -n "$_MANIFEST_REPO_ID_FLEET_NAME" || -n "$_MANIFEST_REPO_ID_FLEET_MEMBER" ]]; then
        _status_line "Fleet context:" "${_MANIFEST_REPO_ID_FLEET_NAME:-hint only}"
        _status_line "Fleet member:" "${_MANIFEST_REPO_ID_FLEET_MEMBER:-not configured}"
    else
        _status_line "Fleet context:" "not detected"
    fi
    _status_line "Mutation scope:" "this Git repository only"
    if [[ -n "$_MANIFEST_REPO_ID_WARNING" ]]; then
        _status_line "Warning:" "$_MANIFEST_REPO_ID_WARNING"
    fi
}

_status_fleet_member_count() {
    local config_file="$1"
    if command -v yq >/dev/null 2>&1; then
        yq e '.services | length' "$config_file" 2>/dev/null || echo "?"
    else
        echo "?"
    fi
}

_status_resolve_member_path() {
    local root="$1"
    local raw_path="$2"
    if [[ -z "$raw_path" || "$raw_path" == "null" ]]; then
        echo ""
    elif [[ "$raw_path" == /* ]]; then
        echo "$raw_path"
    else
        echo "$root/${raw_path#./}"
    fi
}

_status_repo_version() {
    local path="$1"
    if [[ -f "$path/VERSION" ]]; then
        tr -d '[:space:]' < "$path/VERSION"
    else
        echo "n/a"
    fi
}

_status_repo_branch() {
    local path="$1"
    git -C "$path" branch --show-current 2>/dev/null || echo "detached"
}

_status_repo_state() {
    local path="$1"
    local expected_branch="${2:-}"
    if [[ ! -d "$path" ]]; then
        echo "missing"
    elif ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "not-git"
    elif [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
        echo "dirty"
    else
        local branch
        branch="$(_status_repo_branch "$path")"
        if [[ -n "$expected_branch" && "$expected_branch" != "null" && "$branch" != "$expected_branch" ]]; then
            echo "branch"
        else
            echo "clean"
        fi
    fi
}

_status_repo_latest_commit() {
    local path="$1"
    if [[ -d "$path" ]] && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$path" log -1 --oneline 2>/dev/null || echo "n/a"
    else
        echo "n/a"
    fi
}

_status_repo_latest_commit_timestamp() {
    local path="$1"
    if [[ -d "$path" ]] && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local epoch=""
        epoch="$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo "")"
        if [[ -z "$epoch" ]]; then
            echo "n/a"
        else
            # GNU-first: the wrapper forces coreutils' gnubin onto PATH on macOS,
            # so this takes the GNU `-d @<epoch>` branch there too. BSD
            # `date -r <epoch>` is only a fallback — for contexts that ran without
            # the prepend (a module sourced in isolation) or native BSDs.
            date -d "@$epoch" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
                || date -r "$epoch" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
                || echo "n/a"
        fi
    else
        echo "n/a"
    fi
}

_status_version_sync_target_count() {
    local count=0 target
    if declare -F _manifest_version_sync_targets >/dev/null 2>&1; then
        while IFS= read -r target; do
            [[ -n "$target" ]] || continue
            count=$((count + 1))
        done < <(_manifest_version_sync_targets 2>/dev/null || true)
    fi
    echo "$count"
}

_status_version_surfaces_empty_json() {
    local policy_json
    if declare -F manifest_version_surface_policy_json >/dev/null 2>&1; then
        policy_json="$(manifest_version_surface_policy_json)"
    else
        policy_json='{"enabled":false,"notification_mode":"off","depth":0,"catalog":""}'
    fi
    printf '{"policy":%s,"canonical_count":0,"noncanonical_count":0,"sync_target_count":0,"items":[]}' "$policy_json"
}

_status_version_surfaces_json() {
    local root="$1"
    if [[ ! -d "$root" ]] || ! declare -F manifest_version_surface_scan >/dev/null 2>&1; then
        _status_version_surfaces_empty_json
        return 0
    fi

    local policy_json
    policy_json="$(manifest_version_surface_policy_json)"
    if ! manifest_version_surfaces_enabled; then
        printf '{"policy":%s,"canonical_count":0,"noncanonical_count":0,"sync_target_count":0,"items":[]}' "$policy_json"
        return 0
    fi

    local canonical_count=0 noncanonical_count=0 sync_count
    local items_json="" first=true
    local id role kind relationship rel_file version_value
    while IFS=$'\t' read -r id role kind relationship rel_file version_value; do
        [[ -n "$rel_file" ]] || continue
        case "$relationship" in
            canonical) canonical_count=$((canonical_count + 1)) ;;
            *) noncanonical_count=$((noncanonical_count + 1)) ;;
        esac
        local item
        item="{$(_json_kv_str "id" "$id"),$(_json_kv_str "role" "$role"),$(_json_kv_str "kind" "$kind"),$(_json_kv_str "relationship" "$relationship"),$(_json_kv_str "path" "$rel_file"),$(_json_kv_str "version" "$version_value")}"
        if [[ "$first" == "true" ]]; then
            items_json="$item"
            first=false
        else
            items_json="$items_json,$item"
        fi
    done < <(manifest_version_surface_scan "$root" 2>/dev/null || true)

    sync_count="$(_status_version_sync_target_count)"
    printf '{"policy":%s,"canonical_count":%s,"noncanonical_count":%s,"sync_target_count":%s,"items":[%s]}' \
        "$policy_json" "$canonical_count" "$noncanonical_count" "$sync_count" "$items_json"
}

_status_version_surfaces_report() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    declare -F manifest_version_surface_scan >/dev/null 2>&1 || return 0
    manifest_version_surfaces_enabled || return 0

    local mode
    mode="$(manifest_version_surface_notification_mode)"
    [[ "$mode" != "off" ]] || return 0

    local canonical_count=0 noncanonical_count=0 sync_count
    local rows=()
    local id role kind relationship rel_file version_value
    while IFS=$'\t' read -r id role kind relationship rel_file version_value; do
        [[ -n "$rel_file" ]] || continue
        if [[ "$relationship" == "canonical" ]]; then
            canonical_count=$((canonical_count + 1))
        else
            noncanonical_count=$((noncanonical_count + 1))
            rows+=("$(printf "    %-32s %-18s %-8s %s" "$rel_file" "$role" "$kind" "${version_value:-unknown}")")
        fi
    done < <(manifest_version_surface_scan "$root" 2>/dev/null || true)

    if [[ "$noncanonical_count" -eq 0 ]]; then
        return 0
    fi

    sync_count="$(_status_version_sync_target_count)"
    local sync_note="version.sync unset"
    if [[ "$sync_count" -gt 0 ]]; then
        sync_note="${sync_count} version.sync target(s)"
    fi

    _status_line "Version files:" "${noncanonical_count} noncanonical detected (read-only; ${sync_note})"

    if [[ "$mode" == "list" && "${#rows[@]}" -gt 0 ]]; then
        local row
        for row in "${rows[@]}"; do
            printf "%s\n" "$row"
        done
    fi
}

_status_version_surfaces_fleet_report() {
    local fleet_root="$1"
    local config_file="$2"
    [[ -f "$config_file" ]] || return 0
    declare -F manifest_version_surface_scan >/dev/null 2>&1 || return 0
    manifest_version_surfaces_enabled || return 0

    local mode
    mode="$(manifest_version_surface_notification_mode)"
    [[ "$mode" != "off" ]] || return 0

    local scanned=0 repos_with_surfaces=0 total_noncanonical=0
    local rows=()
    local service raw_path path id role kind relationship rel_file version_value
    while IFS= read -r service; do
        [[ -n "$service" ]] || continue
        raw_path="$(SERVICE="$service" yq e '.services[strenv(SERVICE)].path // ""' "$config_file" 2>/dev/null)"
        path="$(_status_resolve_member_path "$fleet_root" "$raw_path")"
        [[ -d "$path" ]] || continue
        scanned=$((scanned + 1))
        local repo_noncanonical=0 repo_rows=()
        while IFS=$'\t' read -r id role kind relationship rel_file version_value; do
            [[ -n "$rel_file" ]] || continue
            [[ "$relationship" != "canonical" ]] || continue
            repo_noncanonical=$((repo_noncanonical + 1))
            repo_rows+=("$(printf "    %-28s %-32s %-18s %-8s %s" "$service" "$rel_file" "$role" "$kind" "${version_value:-unknown}")")
        done < <(manifest_version_surface_scan "$path" 2>/dev/null || true)
        if [[ "$repo_noncanonical" -gt 0 ]]; then
            repos_with_surfaces=$((repos_with_surfaces + 1))
            total_noncanonical=$((total_noncanonical + repo_noncanonical))
            if [[ "$mode" == "list" ]]; then
                rows+=("${repo_rows[@]}")
            fi
        fi
    done < <(yq e '.services | keys | .[]' "$config_file" 2>/dev/null)

    [[ "$scanned" -gt 0 && "$total_noncanonical" -gt 0 ]] || return 0
    echo ""
    echo "Version surfaces"
    echo "  ${total_noncanonical} noncanonical detected across ${repos_with_surfaces} repo(s) (read-only)"
    if [[ "$mode" == "list" && "${#rows[@]}" -gt 0 ]]; then
        local row
        printf "    %-28s %-32s %-18s %-8s %s\n" "Repo" "Path" "Role" "Kind" "Version"
        for row in "${rows[@]}"; do
            printf "%s\n" "$row"
        done
    fi
}

# Derived depth profile + health. For each top-level bucket, the shallowest and
# deepest depth (root-relative) at which a git repo appears, computed from the
# manifest.fleet.tsv PATHs on demand (see docs/FLEET_DESIGN_SPEC.md). A bucket
# whose repos span more than one depth is flagged, since that usually means an
# accidental nested repo or a broken layout convention.
_status_fleet_depth_profile_report() {
    local proj="$1"
    local tsv="$proj/manifest.fleet.tsv"
    [[ -f "$tsv" ]] || return 0

    declare -A min_by_top=() max_by_top=() count_by_top=()
    local tops=()
    local global_min="" global_max=0
    local select name path has_git _rest
    while IFS=$'\t' read -r select name path has_git _rest; do
        [[ "$select" == \#* ]] && continue
        [[ -z "$name" ]] && continue
        [[ "$has_git" == "true" ]] || continue
        local top="${path%%/*}"
        [[ -n "$top" ]] || continue

        local depth=1 rest="$path"
        while [[ "$rest" == */* ]]; do rest="${rest#*/}"; depth=$((depth + 1)); done

        if [[ -z "${min_by_top[$top]+_}" ]]; then
            tops+=("$top")
            min_by_top[$top]=$depth
            max_by_top[$top]=$depth
            count_by_top[$top]=1
        else
            (( depth < min_by_top[$top] )) && min_by_top[$top]=$depth
            (( depth > max_by_top[$top] )) && max_by_top[$top]=$depth
            count_by_top[$top]=$(( count_by_top[$top] + 1 ))
        fi
        [[ -z "$global_min" ]] && global_min=$depth
        (( depth < global_min )) && global_min=$depth
        (( depth > global_max )) && global_max=$depth
    done < "$tsv"

    [[ "${#tops[@]}" -gt 0 ]] || return 0

    local sorted_tops
    mapfile -t sorted_tops < <(printf '%s\n' "${tops[@]}" | sort)

    local mixed=() top
    echo ""
    echo "Depth profile (derived from manifest.fleet.tsv)"
    printf "  %-28s %5s %5s %7s  %s\n" "Bucket" "min" "max" "repos" "note"
    for top in "${sorted_tops[@]}"; do
        local note="uniform"
        if (( min_by_top[$top] != max_by_top[$top] )); then
            note="MIXED"
            mixed+=("$top")
        fi
        printf "  %-28s %5s %5s %7s  %s\n" \
            "$top" "${min_by_top[$top]}" "${max_by_top[$top]}" "${count_by_top[$top]}" "$note"
    done
    echo "  global: shallowest ${global_min}, deepest ${global_max}"
    if [[ "${#mixed[@]}" -gt 0 ]]; then
        echo "  mixed-depth buckets: ${mixed[*]} (check for accidental nested repos)"
    else
        echo "  mixed-depth buckets: none"
    fi
}

_manifest_status_fleet_json() {
    local proj="$1"
    local config_file tsv_file
    config_file="$(_status_fleet_config_file "$proj")"
    tsv_file="$(_status_fleet_tsv_file "$proj")"
    if [[ -z "$config_file" && -z "$tsv_file" ]]; then
        printf '{"fleet":null,"repositories":[]}\n'
        return 0
    fi

    local fleet_name="fleet"
    if [[ -n "$config_file" ]] && command -v yq >/dev/null 2>&1; then
        fleet_name="$(yq e '.fleet.name // "fleet"' "$config_file" 2>/dev/null)"
    fi
    local repos_json="" first=true
    local roster_line service raw_path remote_url expected_branch
    while IFS= read -r roster_line; do
        local fields=()
        _status_tsv_split "$roster_line" fields
        service="${fields[0]:-}"
        raw_path="${fields[1]:-}"
        remote_url="${fields[3]:-}"
        expected_branch="${fields[4]:-}"
        [[ -z "$service" ]] && continue
        local path branch state version commit commit_timestamp surfaces_json
        path="$(_status_resolve_member_path "$proj" "$raw_path")"
        if [[ -d "$path" ]] && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            branch="$(_status_repo_branch "$path")"
        else
            branch="n/a"
        fi
        state="$(_status_repo_state "$path" "$expected_branch")"
        version="$(_status_repo_version "$path")"
        commit="$(_status_repo_latest_commit "$path")"
        commit_timestamp="$(_status_repo_latest_commit_timestamp "$path")"
        surfaces_json="$(_status_version_surfaces_json "$path")"
        local item
        item="{$(_json_kv_str "name" "$service"),$(_json_kv_str "path" "$path"),$(_json_kv_str "remote_url" "$remote_url"),$(_json_kv_str "branch" "$branch"),$(_json_kv_str "state" "$state"),$(_json_kv_str "version" "$version"),$(_json_kv_str "latest_commit_timestamp" "$commit_timestamp"),$(_json_kv_str "latest_commit" "$commit"),$(_json_kv_raw "version_surfaces" "$surfaces_json")}"
        if [[ "$first" == "true" ]]; then
            repos_json="$item"
            first=false
        else
            repos_json="$repos_json,$item"
        fi
    done < <(_status_fleet_roster_rows "$proj")

    printf '{"fleet":{%s,%s},"repositories":[%s]}\n' \
        "$(_json_kv_str "name" "$fleet_name")" \
        "$(_json_kv_str "root" "$proj")" \
        "$repos_json"
}

_manifest_status_fleet() {
    local proj="$1"
    local emit_json="${2:-false}"
    local bootstrap_mode="${3:-off}"
    local config_file tsv_file
    config_file="$(_status_fleet_config_file "$proj")"
    tsv_file="$(_status_fleet_tsv_file "$proj")"

    if [[ -z "$config_file" && -z "$tsv_file" ]]; then
        if [[ "$emit_json" == "true" ]]; then
            printf '{"fleet":null,"repositories":[]}\n'
        else
            echo ""
            echo "Manifest status"
            echo "==============="
            echo ""
            _status_line "Fleet:" "(not a fleet root)"
            _status_line "Path:" "$proj"
            echo ""
        fi
        return 0
    fi

    if [[ "$emit_json" == "true" ]]; then
        _manifest_status_fleet_json "$proj"
        return $?
    fi

    local fleet_name="fleet"
    if [[ -n "$config_file" ]] && command -v yq >/dev/null 2>&1; then
        fleet_name="$(yq e '.fleet.name // "fleet"' "$config_file" 2>/dev/null)"
    fi

    local total=0 clean=0 dirty=0 other=0
    local rows=()
    # Members with a declared remote that are absent locally — the bootstrap set.
    local bootstrap_names=() bootstrap_urls=() bootstrap_paths=()
    # Members absent locally with no remote to clone from — unrecoverable; flag.
    local lost_names=()
    local roster_line service raw_path remote_url expected_branch
    while IFS= read -r roster_line; do
        local fields=()
        _status_tsv_split "$roster_line" fields
        service="${fields[0]:-}"
        raw_path="${fields[1]:-}"
        remote_url="${fields[3]:-}"
        expected_branch="${fields[4]:-}"
        [[ -z "$service" ]] && continue
        local path branch state version commit commit_timestamp
        path="$(_status_resolve_member_path "$proj" "$raw_path")"
        if [[ -d "$path" ]] && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            branch="$(_status_repo_branch "$path")"
        else
            branch="n/a"
        fi
        state="$(_status_repo_state "$path" "$expected_branch")"
        version="$(_status_repo_version "$path")"
        commit="$(_status_repo_latest_commit "$path")"
        commit_timestamp="$(_status_repo_latest_commit_timestamp "$path")"
        rows+=("$(printf "%-36s  %-12s  %-8s  %-9s  %-25s  %-40s  %s" "$service" "$branch" "$state" "$version" "$commit_timestamp" "$path" "$commit")")
        total=$((total + 1))
        case "$state" in
            clean) clean=$((clean + 1)) ;;
            dirty) dirty=$((dirty + 1)) ;;
            *) other=$((other + 1)) ;;
        esac
        # A declared member absent on disk is Uncloned (has a remote, restorable)
        # or Lost (no remote) per FLEET_DESIGN_SPEC.md.
        if [[ "$state" == "missing" ]]; then
            if [[ -n "$remote_url" && "$remote_url" != "null" ]]; then
                bootstrap_names+=("$service")
                bootstrap_urls+=("$remote_url")
                bootstrap_paths+=("$path")
            else
                lost_names+=("$service")
            fi
        fi
    done < <(_status_fleet_roster_rows "$proj")

    echo ""
    echo "Manifest status"
    echo "==============="
    echo ""
    _status_line "Fleet:" "$fleet_name"
    _status_line "Root:" "$proj"
    # The roster (membership) is sourced from the TSV when present, else the
    # config YAML. Show whichever was the truth source for this table.
    if [[ -n "$tsv_file" ]]; then
        _status_line "Roster:" "$tsv_file"
        [[ -n "$config_file" ]] && _status_line "Config:" "$config_file"
    else
        _status_line "Config:" "$config_file"
    fi
    _status_line "Scope:" "fleet"
    _status_line "Repos:" "$total total, $clean clean, $dirty dirty, $other other"
    echo ""
    echo "Included repositories"
    printf "%-36s  %-12s  %-8s  %-9s  %-25s  %-40s  %s\n" "Repo" "Branch" "State" "Version" "Timestamp" "Path" "Latest commit"
    printf "%-36s  %-12s  %-8s  %-9s  %-25s  %-40s  %s\n" "------------------------------------" "------------" "--------" "---------" "-------------------------" "----------------------------------------" "----------------------------------------"
    local row
    for row in "${rows[@]}"; do
        printf "%s\n" "$row"
    done
    if [[ -n "$config_file" ]]; then
        _status_version_surfaces_fleet_report "$proj" "$config_file"
    fi
    _status_fleet_depth_profile_report "$proj"

    _status_fleet_bootstrap_report \
        "$proj" "$bootstrap_mode" \
        bootstrap_names bootstrap_urls bootstrap_paths lost_names

    echo ""
    echo "Next actions"
    echo "  manifest status repo            Show status for this repo only"
    echo "  manifest status fleet           Show this fleet table explicitly"
    if [[ "${#bootstrap_names[@]}" -gt 0 && "$bootstrap_mode" == "off" ]]; then
        echo "  manifest status fleet --bootstrap   Preview cloning absent members"
    fi
    echo "  manifest update fleet           Re-scan fleet membership"
    echo ""
}

# Bootstrap report for declared members that are absent locally. Uses the
# observed Local x declared Remote axes from FLEET_DESIGN_SPEC.md: a member with
# a remote is Uncloned (restorable by clone); one without is Lost (flagged).
#
# Modes:
#   off       Only surface a one-line hint that absent members exist.
#   preview   List exactly what WOULD be cloned, write nothing (default opt-in).
#   apply     Reserved for an explicit live clone; gated, never reached here.
#
# Args: $1 fleet root, $2 mode, then four array names by reference:
#   $3 member names, $4 remote URLs, $5 target paths (all index-aligned),
#   $6 names of Lost members (absent, no remote).
_status_fleet_bootstrap_report() {
    local proj="$1"
    local mode="$2"
    local -n _names_ref="$3"
    local -n _urls_ref="$4"
    local -n _paths_ref="$5"
    local -n _lost_ref="$6"

    local pending="${#_names_ref[@]}"
    local lost="${#_lost_ref[@]}"

    if [[ "$mode" == "off" ]]; then
        if [[ "$pending" -gt 0 || "$lost" -gt 0 ]]; then
            echo ""
            local note="${pending} member(s) declared but absent locally"
            [[ "$lost" -gt 0 ]] && note="${note}; ${lost} unrecoverable (no remote)"
            _status_line "Bootstrap:" "$note — run 'manifest status fleet --bootstrap' to preview"
        fi
        return 0
    fi

    echo ""
    echo "Bootstrap preview"
    echo "-----------------"
    if [[ "$pending" -eq 0 && "$lost" -eq 0 ]]; then
        echo "  All declared members are present locally — nothing to clone."
        return 0
    fi

    local i
    for ((i = 0; i < pending; i++)); do
        printf "  %-36s would clone from %s -> %s\n" \
            "${_names_ref[$i]}" "${_urls_ref[$i]}" "${_paths_ref[$i]}"
    done
    local name
    for name in "${_lost_ref[@]}"; do
        printf "  %-36s LOST — absent and no remote declared (unrecoverable)\n" "$name"
    done

    echo ""
    echo "Plan: ${pending} clone, ${lost} unrecoverable"
    if [[ "$pending" -gt 0 ]]; then
        echo ""
        echo "No changes written. To restore the absent members, clone each remote"
        echo "into its declared path, or run the fleet sync apply path:"
        echo "  manifest prep fleet --clone-only -y"
    fi
}

# JSON sibling of manifest_status — same data, machine-readable.
# Keys are stable; absent values are emitted as null.
_manifest_status_json() {
    local proj="$1"
    local in_git="false" slug="" canonical="false" branch="" upstream=""
    local ahead=0 behind=0 modified=0 untracked=0
    local current_version="" patch="" minor_v="" major_v=""
    local fleet_mode="single-repo" fleet_count=""
    local g="${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}"
    local ps="$proj/manifest.config.yaml"
    local pl="$proj/manifest.config.local.yaml"

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        in_git="true"
        slug="$(manifest_origin_repo_slug "$proj" 2>/dev/null || echo "")"
        if [[ -n "$slug" ]] && manifest_is_canonical_repo "$proj" 2>/dev/null; then
            canonical="true"
        fi
        branch="$(git -C "$proj" branch --show-current 2>/dev/null || echo "")"
        upstream="$(git -C "$proj" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "")"
        if [[ -n "$upstream" ]]; then
            local lr
            lr="$(git -C "$proj" rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "0	0")"
            behind="$(echo "$lr" | awk '{print $1}')"
            ahead="$(echo "$lr" | awk '{print $2}')"
        fi
        read -r modified untracked < <(_status_git_porcelain_counts "$proj")
    fi

    if [[ -f "$proj/VERSION" ]]; then
        current_version="$(cat "$proj/VERSION" 2>/dev/null | tr -d '[:space:]')"
        patch="$(_status_preview_bump "$current_version" "patch")"
        minor_v="$(_status_preview_bump "$current_version" "minor")"
        major_v="$(_status_preview_bump "$current_version" "major")"
    fi

    local fleet_config fleet_tsv
    fleet_config="$(_status_fleet_config_file "$proj")"
    fleet_tsv="$(_status_fleet_tsv_file "$proj")"
    if [[ -n "$fleet_tsv" ]]; then
        # TSV present (with or without a config): the declared roster is truth.
        fleet_mode="fleet"
        fleet_count="$(_status_fleet_roster_count "$proj")"
    elif [[ -n "$fleet_config" ]]; then
        fleet_mode="fleet"
        if command -v yq >/dev/null 2>&1; then
            fleet_count="$(yq e '.services | length' "$fleet_config" 2>/dev/null || echo "")"
        fi
    elif [[ -f "$proj/manifest.fleet.tsv" ]]; then
        fleet_mode="fleet-phase1"
    fi

    # Build ahead/behind as numbers — guard malformed inputs.
    [[ "$ahead" =~ ^[0-9]+$ ]] || ahead=0
    [[ "$behind" =~ ^[0-9]+$ ]] || behind=0
    [[ "$modified" =~ ^[0-9]+$ ]] || modified=0
    [[ "$untracked" =~ ^[0-9]+$ ]] || untracked=0

    local repo_json branch_json version_json fleet_json config_json surfaces_json
    repo_json="{$(_json_kv_raw "in_git" "$in_git"),$(_json_kv_str "slug" "$slug"),$(_json_kv_raw "canonical" "$canonical"),$(_json_kv_str "path" "$proj")}"
    branch_json="{$(_json_kv_str "name" "$branch"),$(_json_kv_str "upstream" "$upstream"),$(_json_kv_raw "ahead" "$ahead"),$(_json_kv_raw "behind" "$behind"),$(_json_kv_raw "modified" "$modified"),$(_json_kv_raw "untracked" "$untracked")}"
    if [[ -n "$current_version" ]]; then
        local p_json m_json M_json
        p_json="$(_json_value "$patch")"
        m_json="$(_json_value "$minor_v")"
        M_json="$(_json_value "$major_v")"
        version_json="{$(_json_kv_str "current" "$current_version"),$(_json_kv_raw "next_patch" "$p_json"),$(_json_kv_raw "next_minor" "$m_json"),$(_json_kv_raw "next_major" "$M_json")}"
    else
        version_json="null"
    fi
    if [[ "$fleet_mode" == "fleet" && -n "$fleet_count" && "$fleet_count" != "?" ]]; then
        fleet_json="{$(_json_kv_str "mode" "fleet"),$(_json_kv_raw "members" "$fleet_count")}"
    else
        fleet_json="{$(_json_kv_str "mode" "$fleet_mode"),$(_json_kv_raw "members" "null")}"
    fi
    local g_p p_p l_p
    g_p="$([ -f "$g" ] && echo true || echo false)"
    p_p="$([ -f "$ps" ] && echo true || echo false)"
    l_p="$([ -f "$pl" ] && echo true || echo false)"
    config_json="{\"global\":{$(_json_kv_str "path" "$g"),$(_json_kv_raw "present" "$g_p")},\"project\":{$(_json_kv_str "path" "$ps"),$(_json_kv_raw "present" "$p_p")},\"local\":{$(_json_kv_str "path" "$pl"),$(_json_kv_raw "present" "$l_p")}}"
    surfaces_json="$(_status_version_surfaces_json "$proj")"

    printf '{%s,%s,%s,%s,%s,%s}\n' \
        "$(_json_kv_raw "repository" "$repo_json")" \
        "$(_json_kv_raw "branch" "$branch_json")" \
        "$(_json_kv_raw "version" "$version_json")" \
        "$(_json_kv_raw "fleet" "$fleet_json")" \
        "$(_json_kv_raw "config" "$config_json")" \
        "$(_json_kv_raw "version_surfaces" "$surfaces_json")"
}

_manifest_status_repo() {
    local proj="$1"
    local emit_json="${2:-false}"
    cd "$proj" 2>/dev/null || { echo "❌ Cannot enter $proj"; return 1; }

    if [[ "$emit_json" == "true" ]]; then
        _manifest_status_json "$proj"
        return $?
    fi

    echo ""
    echo "Manifest status"
    echo "==============="

    # -- Repository identity ------------------------------------------------
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _status_line "Repository:" "(not a git repository)"
        _status_line "Path:" "$proj"
        echo ""
        return 0
    fi

    local slug canonical_marker=""
    slug="$(manifest_origin_repo_slug "$proj" 2>/dev/null || echo "")"
    if [[ -z "$slug" ]]; then
        slug="(no origin remote)"
    elif manifest_is_canonical_repo "$proj" 2>/dev/null; then
        canonical_marker="  (canonical — Homebrew tap formula publishes from here)"
    fi
    _status_line "Repository:" "${slug}${canonical_marker}"

    # -- Branch + upstream sync --------------------------------------------
    local branch upstream sync_state
    branch="$(git -C "$proj" branch --show-current 2>/dev/null || echo "(detached)")"
    upstream="$(git -C "$proj" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "")"
    if [[ -z "$upstream" ]]; then
        sync_state="no upstream"
        _status_line "Branch:" "$branch  ($sync_state)"
    else
        local lr ahead behind
        lr="$(git -C "$proj" rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "0	0")"
        behind="$(echo "$lr" | awk '{print $1}')"
        ahead="$(echo "$lr" | awk '{print $2}')"
        if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
            sync_state="in sync"
        else
            sync_state="ahead ${ahead}, behind ${behind}"
        fi
        _status_line "Branch:" "$branch → $upstream  ($sync_state)"
    fi

    echo ""
    manifest_repo_identity_block "$proj"

    # -- Working tree -------------------------------------------------------
    local modified untracked
    read -r modified untracked < <(_status_git_porcelain_counts "$proj")
    if [[ "$modified" == "0" && "$untracked" == "0" ]]; then
        _status_line "Working:" "clean"
    else
        _status_line "Working:" "${modified} modified, ${untracked} untracked"
    fi

    # -- Version + bump previews -------------------------------------------
    if [[ -f "$proj/VERSION" ]]; then
        local current
        current="$(cat "$proj/VERSION" 2>/dev/null | tr -d '[:space:]')"
        _status_line "Version:" "$current"
        local p m M
        p="$(_status_preview_bump "$current" "patch")"
        m="$(_status_preview_bump "$current" "minor")"
        M="$(_status_preview_bump "$current" "major")"
        printf "  %-12s patch → %s\n" "" "$p"
        printf "  %-12s minor → %s\n" "" "$m"
        printf "  %-12s major → %s\n" "" "$M"
    else
        _status_line "Version:" "(no VERSION file — run 'manifest init repo')"
    fi
    _status_version_surfaces_report "$proj"

    # -- Single-repo vs fleet ----------------------------------------------
    local fleet_mode="single-repo"
    local fleet_count=""
    local fleet_config fleet_tsv
    fleet_config="$(_status_fleet_config_file "$proj")"
    fleet_tsv="$(_status_fleet_tsv_file "$proj")"
    if [[ -n "$fleet_tsv" ]]; then
        fleet_mode="fleet"
        fleet_count="$(_status_fleet_roster_count "$proj")"
    elif [[ -n "$fleet_config" ]]; then
        fleet_mode="fleet"
        fleet_count="$(_status_fleet_member_count "$fleet_config")"
    fi
    if [[ -n "$fleet_count" && "$fleet_count" != "0" && "$fleet_count" != "?" ]]; then
        _status_line "Mode:" "$fleet_mode  ($fleet_count members)"
    else
        _status_line "Mode:" "$fleet_mode"
    fi

    # -- Config layers ------------------------------------------------------
    local g="${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}"
    local ps="$proj/manifest.config.yaml"
    local pl="$proj/manifest.config.local.yaml"
    _status_line "Config:" "$([ -f "$g" ]  && echo "✓" || echo "·") global   $g"
    _status_line ""        "$([ -f "$ps" ] && echo "✓" || echo "·") project  $ps"
    _status_line ""        "$([ -f "$pl" ] && echo "✓" || echo "·") local    $pl"

    echo ""
    return 0
}

manifest_status() {
    local emit_json=false
    local scope="auto"
    local explicit_repo_scope=false
    local bootstrap_mode="off"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            repo)
                scope="$1"
                explicit_repo_scope=true
                shift
                ;;
            fleet) scope="$1"; shift ;;
            --json) emit_json=true; shift ;;
            --bootstrap)
                scope="fleet"
                bootstrap_mode="preview"
                shift
                ;;
            -v|--verbose)
                scope="fleet"
                shift
                ;;
            -h|--help)
                _render_help \
                    "manifest status [repo|fleet] [--json] [--bootstrap]" \
                    "Read-only snapshot of repo or fleet state." \
                    "Scopes" "  repo     Force current-repo status
  fleet    Force fleet repository table" \
                    "Options" "  --json        Emit machine-readable JSON instead of the human view
  --bootstrap   Preview which declared-but-absent fleet members would be
                cloned (read-only; clones nothing)" \
                    "Examples" "  manifest status
  manifest status repo
  manifest status fleet
  manifest status fleet --bootstrap"
                return 0
                ;;
            *)
                _render_help_error "Unknown option: $1" "manifest status [repo|fleet] [--json] [--bootstrap]"
                return 1
                ;;
        esac
    done

    local proj="${MANIFEST_CLI_PROJECT_ROOT:-$(pwd)}"
    cd "$proj" 2>/dev/null || { echo "❌ Cannot enter $proj"; return 1; }

    if [[ "$explicit_repo_scope" == "true" ]]; then
        if ! manifest_repo_scope_require_git "manifest status repo"; then
            return 1
        fi
    fi

    if [[ "$scope" == "auto" ]]; then
        # A fleet root is recognized by its config YAML or its declared roster
        # TSV — either alone is enough to render the fleet table.
        if [[ -n "$(_status_fleet_config_file "$proj")" || -n "$(_status_fleet_tsv_file "$proj")" ]]; then
            scope="fleet"
        else
            scope="repo"
        fi
    fi

    case "$scope" in
        repo) _manifest_status_repo "$proj" "$emit_json" ;;
        fleet) _manifest_status_fleet "$proj" "$emit_json" "$bootstrap_mode" ;;
    esac
}

export -f manifest_status
export -f _manifest_status_json
export -f manifest_repo_identity_block
