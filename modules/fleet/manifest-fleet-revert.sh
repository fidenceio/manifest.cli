#!/usr/bin/env bash

# A snapshot is a manager commit containing this member map. The enclosing Git
# commit identifies the manager itself, avoiding a self-referential commit hash.
_manifest_fleet_snapshot_file() { echo manifest.fleet.snapshot.json; }

_manifest_fleet_snapshot_valid() {
    yq -p=json -e '
        .kind == "manifest.fleet.snapshot" and .schema == 1 and
        (.members | tag == "!!seq") and ((keys | length) == 3)
    ' - >/dev/null 2>&1
}

_manifest_fleet_snapshot_owned() {
    [[ -f "$1" && ! -L "$1" ]] && _manifest_fleet_snapshot_valid < "$1"
}

_manifest_fleet_snapshot_destination() {
    local file="$1/$(_manifest_fleet_snapshot_file)"
    if [[ -e "$file" || -L "$file" ]]; then
        _manifest_fleet_snapshot_owned "$file" || {
            log_error "Reserved fleet snapshot path is not a Manifest snapshot: $file"
            return 1
        }
    fi
    if { git -C "$1" ls-files --error-unmatch -- "$(_manifest_fleet_snapshot_file)" >/dev/null 2>&1 ||
         git -C "$1" cat-file -e "HEAD:$(_manifest_fleet_snapshot_file)" 2>/dev/null; } &&
       ! git -C "$1" diff --quiet HEAD -- "$(_manifest_fleet_snapshot_file)"; then
        log_error "Fleet snapshot has uncommitted edits or a deletion; preserve or resolve them before shipping."
        return 1
    fi
}

# Resolve a snapshot member strictly inside the fleet, at its own Git root.
_manifest_fleet_revert_path() {
    local root="$1" relative="$2" actual git_root
    case "$relative" in
        ""|/*|..|../*|*/../*|*/..|.git|.git/*|*$'\n'*|*$'\t'*) return 1 ;;
    esac
    actual="$(cd "$root/$relative" 2>/dev/null && pwd -P)" || return 1
    [[ "$actual" == "$root/"* ]] || return 1
    git_root="$(git -C "$actual" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ "$actual" -ef "$git_root" ]] || return 1
    printf '%s' "$actual"
}

_manifest_fleet_snapshot_render() {
    local root="$1" service path actual commit rows='' row
    root="$(cd "$root" && pwd -P)" || return 1
    for service in ${MANIFEST_CLI_FLEET_SERVICES:-}; do
        path="$(get_fleet_service_property "$service" path)"
        # The manager is represented by the enclosing commit, once only.
        actual="$path"
        [[ "$path" == /* ]] || actual="$root/$path"
        actual="$(cd "$actual" 2>/dev/null && pwd -P)" || actual=''
        [[ "$actual" != "$root" ]] || continue
        [[ "$actual" != "$root/"* ]] || path="${actual#"$root/"}"
        commit=''
        if actual="$(_manifest_fleet_revert_path "$root" "$path")"; then
            commit="$(git -C "$actual" rev-parse --verify HEAD 2>/dev/null)" || commit=''
            path="${actual#"$root/"}"
        fi
        row="{$(_json_kv_str name "$service"),$(_json_kv_str path "$path"),"
        if [[ -n "$commit" ]]; then row+="$(_json_kv_str commit "$commit")}"; else row+='"commit":null}'; fi
        [[ -z "$rows" ]] || rows+=','
        rows+="$row"
    done
    printf '{"kind":"manifest.fleet.snapshot","members":[%s],"schema":1}\n' "$rows" \
        | yq -p=json -o=json '.members |= sort_by(.name) | sort_keys(..)' -

}

_manifest_fleet_snapshot_needed() {
    local root="$1" current next
    _manifest_fleet_snapshot_owned "$root/$(_manifest_fleet_snapshot_file)" || return 0
    current="$(cat "$root/$(_manifest_fleet_snapshot_file)")" || return 0
    next="$(_manifest_fleet_snapshot_render "$root")" || return 0
    [[ "$current" != "$next" ]]
}

_manifest_fleet_snapshot_write() {
    local root="$1" tmp
    _manifest_fleet_snapshot_destination "$root" || return 1
    tmp="$(mktemp "$root/.manifest-fleet-snapshot.XXXXXX")" || return 1
    if ! _manifest_fleet_snapshot_render "$root" > "$tmp"; then
        rm -f "$tmp"; return 1
    fi
    if [[ -f "$root/$(_manifest_fleet_snapshot_file)" ]] && cmp -s "$tmp" "$root/$(_manifest_fleet_snapshot_file)"; then
        rm -f "$tmp"
    else
        mv -f "$tmp" "$root/$(_manifest_fleet_snapshot_file)" || { rm -f "$tmp"; return 1; }
    fi
}

manifest_revert_fleet() (
    local execution_mode=preview local_only=false args=() snapshot='' arg root manager data
    manifest_execution_parse execution_mode local_only args "$@" || return 1
    [[ "$local_only" != true ]] || { log_error "Fleet revert is already local; --local is not supported."; return 1; }
    for arg in "${args[@]}"; do
        case "$arg" in
            help|-h|--help)
                _render_help "manifest revert fleet [<snapshot>] [-y|--yes] [--dry-run]" \
                    "Check out the manager and members at a recorded fleet snapshot.
A snapshot is a manager Git commit containing manifest.fleet.snapshot.json.
With no snapshot, list the available manager commits. Applying requires a target.
All checkouts become detached HEAD. Branches and published releases stay intact." \
                    "Options" "  --dry-run   Explicit preview; no writes or checkouts
  -y, --yes   Apply local checkouts; never push" \
                    "Examples" "  manifest revert fleet
  manifest revert fleet <manager-commit>
  manifest revert fleet <manager-commit> -y"
                return 0 ;;
            -*) log_error "Unknown fleet revert option: $arg"; return 1 ;;
            *) [[ -z "$snapshot" ]] || { log_error "Specify one fleet snapshot."; return 1; }; snapshot="$arg" ;;
        esac
    done
    manifest_repo_scope_require_git "manifest revert fleet" || return 1
    root="$(git rev-parse --show-toplevel)" || return 1
    root="$(cd "$root" && pwd -P)" || return 1
    local config
    config="$(_fleet_resolve_config "$root")"
    if [[ ! -f "$config" ]] || [[ "$(cd "$(dirname "$config")" 2>/dev/null && pwd -P)" != "$root" ]]; then
        log_error "Run fleet revert from the manager repository."
        return 1
    fi
    if [[ -z "$snapshot" ]]; then
        echo "Recorded fleet snapshots (manager commits):"
        git -C "$root" log --all -10 --format='%h %s' -- "$(_manifest_fleet_snapshot_file)"
        if [[ "$execution_mode" == apply ]]; then
            log_error "Name a snapshot: manifest revert fleet <manager-commit> -y"
            return 1
        fi
        echo "Only commits containing a recorded member map support fleet revert."
        manifest_execution_footer "manifest revert fleet <manager-commit> -y"
        return 0
    fi
    manager="$(git -C "$root" rev-parse --verify "$snapshot^{commit}" 2>/dev/null)" || {
        log_error "Unknown manager snapshot: $snapshot"; return 1;
    }
    data="$(git -C "$root" show "$manager:$(_manifest_fleet_snapshot_file)" 2>/dev/null)" || {
        log_error "That manager commit has no recorded fleet snapshot; member versions cannot be reconstructed."
        return 1
    }
    if ! _manifest_fleet_snapshot_valid <<< "$data"; then
        log_error "Snapshot is invalid."
        return 1
    fi

    local -a paths=() commits=() names=() locks=()
    local row name path commit actual other dirty blocked=false
    while IFS= read -r row; do
        if ! yq -p=json -e '(.name | tag == "!!str") and (.path | tag == "!!str") and
            (.commit | tag == "!!str") and ((.name + .path) | test("[[:cntrl:]]") | not)' - <<< "$row" >/dev/null 2>&1; then
            log_error "Snapshot is invalid or contains a member without a recorded commit."
            return 1
        fi
        name="$(yq -p=json -r '.name' - <<< "$row")"
        path="$(yq -p=json -r '.path' - <<< "$row")"
        commit="$(yq -p=json -r '.commit' - <<< "$row")"
        if [[ ! "$commit" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
            log_error "Snapshot is invalid: malformed member commit."
            return 1
        fi
        actual="$(_manifest_fleet_revert_path "$root" "$path")" || {
            log_error "Snapshot member is missing, outside the fleet, or not its own repository: $path"
            return 1
        }
        for other in "${paths[@]}"; do
            if [[ "$actual" == "$other" || "$actual" == "$other/"* || "$other" == "$actual/"* ]]; then
                log_error "Snapshot contains duplicate or nested member repositories: $path"
                return 1
            fi
        done
        git -C "$actual" cat-file -e "$commit^{commit}" 2>/dev/null || {
            log_error "Recorded commit is unavailable in $name: $commit (fetch it before retrying)."
            return 1
        }
        paths+=("$actual"); commits+=("$commit"); names+=("$name")
    done < <(yq -p=json -o=json -I=0 '.members[]' - <<< "$data")
    paths+=("$root"); commits+=("$manager"); names+=(manager)
    echo "Fleet snapshot: $manager"
    echo "Checkout order: members first, manager last; all become detached HEAD."
    local i
    for i in "${!paths[@]}"; do
        printf '  %s: %s -> %s\n' "${names[$i]}" "${paths[$i]}" "${commits[$i]}"
        dirty="$(git --no-optional-locks -C "${paths[$i]}" status --porcelain --untracked-files=all)" || return 1
        if [[ -n "$dirty" ]]; then
            echo "  BLOCKED: ${names[$i]} has uncommitted or untracked files. Preserve them before applying."
            blocked=true
        fi
    done
    if [[ "$execution_mode" == preview ]]; then
        manifest_execution_preview_header "manifest revert fleet $manager"
        manifest_execution_footer "manifest revert fleet $manager -y"
        [[ "$blocked" == false ]]
        return $?
    fi
    [[ "$blocked" == false ]] || return 1

    # Share the shipping locks. Hold every repository lock until the entire
    # operation ends; release acquired locks on failure and signals as well.
    local fleet_lock
    MANIFEST_CLI_FLEET_ROOT="$root"
    fleet_lock="$(_fleet_lock_dir_path)"
    trap 'for lock in "${locks[@]}"; do _fleet_lock_release "$lock" || true; done' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _fleet_lock_acquire "$fleet_lock" || return 1
    locks+=("$fleet_lock")
    local lock
    for actual in "${paths[@]}"; do
        lock="$(MANIFEST_CLI_PROJECT_ROOT="$actual" _manifest_repo_lock_dir_path)"
        _fleet_lock_acquire "$lock" || return 1
        locks+=("$lock")
        manifest_execution_require_apply apply "$actual" "manifest revert fleet $manager -y" "" false false || return 1
        [[ -z "$(git --no-optional-locks -C "$actual" status --porcelain --untracked-files=all)" ]] || {
            log_error "Checkout state changed during preflight: $actual"; return 1;
        }
    done
    manifest_execution_apply_header
    local done_count=0
    for i in "${!paths[@]}"; do
        if ! git -C "${paths[$i]}" checkout --detach --no-overwrite-ignore --no-recurse-submodules "${commits[$i]}"; then
            log_error "Fleet revert stopped at ${names[$i]}; $done_count checkouts completed. No automatic rollback was attempted."
            [[ "$done_count" -eq 0 ]] && return 1
            return 2
        fi
        done_count=$((done_count+1))
        echo "Restored ${names[$i]} to ${commits[$i]}"
    done
    echo "Fleet checkout restored to snapshot $manager."
)
