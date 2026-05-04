#!/bin/bash

# =============================================================================
# MANIFEST FLEET PLAN MODULE
# =============================================================================
#
# Builds a generated, editable adoption plan for messy polyrepo workspaces.
# Commands are dry-run by default; --apply and --do are exact aliases.

if [[ -n "${_MANIFEST_FLEET_PLAN_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_FLEET_PLAN_LOADED=1

readonly MANIFEST_FLEET_PLAN_MODULE_VERSION="1.0.0"
readonly MANIFEST_FLEET_PLAN_MODULE_NAME="manifest-fleet-plan"
readonly MANIFEST_FLEET_DEFAULT_PLAN_FILE="manifest.fleet.plan.yaml"

_fleet_plan_yaml_quote() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

_fleet_plan_bool() {
    [[ "${1:-}" == "true" ]] && printf "true" || printf "false"
}

_fleet_parse_apply_contract() {
    local _apply_var="$1"
    local _commit_var="$2"
    local _push_var="$3"
    local _force_var="$4"
    shift 4
    local -n _apply_ref="$_apply_var"
    local -n _commit_ref="$_commit_var"
    local -n _push_ref="$_push_var"
    local -n _force_ref="$_force_var"

    local apply_value=false commit_value=false push_value=false force_value=false
    local rest=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply|--do)
                apply_value=true; shift ;;
            --dry-run)
                shift ;;
            --commit)
                commit_value=true; shift ;;
            --push)
                push_value=true; shift ;;
            --force|-f)
                force_value=true; shift ;;
            *)
                rest+=("$1"); shift ;;
        esac
    done

    if [[ "$push_value" == "true" && "$commit_value" != "true" ]]; then
        log_error "--push requires --commit"
        return 1
    fi
    if [[ "$commit_value" == "true" && "$apply_value" != "true" ]]; then
        log_error "--commit requires --apply or --do"
        return 1
    fi
    if [[ "$force_value" == "true" && "$apply_value" != "true" ]]; then
        log_error "--force requires --apply or --do"
        return 1
    fi

    _apply_ref="$apply_value"
    _commit_ref="$commit_value"
    _push_ref="$push_value"
    _force_ref="$force_value"
    FLEET_PLAN_REMAINING_ARGS=("${rest[@]}")
}

_fleet_path_is_safe_relative() {
    local path="$1"
    [[ -n "$path" ]] || return 1
    [[ "$path" != /* ]] || return 1
    [[ "$path" != "." ]] || return 1
    [[ "$path" != *".."* ]] || return 1
    return 0
}

_fleet_plan_kind_for_entry() {
    local has_git="$1"
    local is_submodule="$2"
    if [[ "$is_submodule" == "true" ]]; then
        echo "submodule"
    elif [[ "$has_git" == "true" ]]; then
        echo "git_repo"
    else
        echo "plain_dir"
    fi
}

_fleet_plan_default_action_for_entry() {
    local kind="$1"
    case "$kind" in
        git_repo) echo "track" ;;
        submodule) echo "adopt_submodule" ;;
        *) echo "skip" ;;
    esac
}

_fleet_plan_split_discovery_line() {
    local line="$1"
    local _name_var="$2"
    local _path_var="$3"
    local _type_var="$4"
    local _branch_var="$5"
    local _version_var="$6"
    local _url_var="$7"
    local _submodule_var="$8"
    local _has_git_var="$9"
    local _has_remote_var="${10}"
    local -n _name_ref="$_name_var"
    local -n _path_ref="$_path_var"
    local -n _type_ref="$_type_var"
    local -n _branch_ref="$_branch_var"
    local -n _version_ref="$_version_var"
    local -n _url_ref="$_url_var"
    local -n _submodule_ref="$_submodule_var"
    local -n _has_git_ref="$_has_git_var"
    local -n _has_remote_ref="$_has_remote_var"
    local sep=$'\x1f'
    local parsed_name parsed_path parsed_type parsed_branch parsed_version parsed_url parsed_submodule parsed_has_git parsed_has_remote

    line="${line//$'\t'/$sep}"
    IFS="$sep" read -r parsed_name parsed_path parsed_type parsed_branch parsed_version parsed_url parsed_submodule parsed_has_git parsed_has_remote <<< "$line"

    _name_ref="$parsed_name"
    _path_ref="$parsed_path"
    _type_ref="$parsed_type"
    _branch_ref="$parsed_branch"
    _version_ref="$parsed_version"
    _url_ref="$parsed_url"
    _submodule_ref="$parsed_submodule"
    _has_git_ref="$parsed_has_git"
    _has_remote_ref="$parsed_has_remote"
}

_fleet_plan_emit_entry() {
    local name="$1"
    local kind="$2"
    local source_path="$3"
    local target_path="$4"
    local action="$5"
    local type="$6"
    local has_git="$7"
    local remote_url="$8"
    local branch="$9"
    local version="${10}"
    local submodule="${11}"
    local parent_path="${12:-}"
    local pinned_commit="${13:-}"
    local submodule_name="${14:-}"

    echo "  - name: $(_fleet_plan_yaml_quote "$name")"
    echo "    kind: $(_fleet_plan_yaml_quote "$kind")"
    echo "    source_path: $(_fleet_plan_yaml_quote "$source_path")"
    echo "    target_path: $(_fleet_plan_yaml_quote "$target_path")"
    echo "    action: $(_fleet_plan_yaml_quote "$action")"
    echo "    type: $(_fleet_plan_yaml_quote "${type:-service}")"
    echo "    has_git: $(_fleet_plan_bool "$has_git")"
    echo "    remote_url: $(_fleet_plan_yaml_quote "$remote_url")"
    echo "    branch: $(_fleet_plan_yaml_quote "${branch:-main}")"
    echo "    version: $(_fleet_plan_yaml_quote "${version:-0.0.0}")"
    echo "    submodule: $(_fleet_plan_bool "$submodule")"
    if [[ -n "$parent_path" ]]; then
        echo "    parent_path: $(_fleet_plan_yaml_quote "$parent_path")"
    fi
    if [[ -n "$pinned_commit" ]]; then
        echo "    pinned_commit: $(_fleet_plan_yaml_quote "$pinned_commit")"
    fi
    if [[ -n "$submodule_name" ]]; then
        echo "    submodule_name: $(_fleet_plan_yaml_quote "$submodule_name")"
    fi
}

_fleet_plan_emit_submodules() {
    local root_dir="$1"
    local _emitted_arr_name="${2:-}"
    local _local_emitted=()
    [[ -z "$_emitted_arr_name" ]] && _emitted_arr_name="_local_emitted"
    local -n _emitted_ref="$_emitted_arr_name"
    local parent_rel parent_abs section path url branch commit name

    while IFS= read -r -d '' gitmodules; do
        parent_abs=$(dirname "$gitmodules")
        parent_rel="${parent_abs#"$root_dir"/}"
        [[ "$parent_rel" == "$parent_abs" ]] && parent_rel="."

        while IFS= read -r section; do
            [[ -z "$section" ]] && continue
            name="${section#submodule.}"
            path=$(git -C "$parent_abs" config -f .gitmodules --get "${section}.path" 2>/dev/null || true)
            [[ -z "$path" ]] && continue
            url=$(git -C "$parent_abs" config -f .gitmodules --get "${section}.url" 2>/dev/null || true)
            branch=$(git -C "$parent_abs" config -f .gitmodules --get "${section}.branch" 2>/dev/null || true)
            commit=$(git -C "$parent_abs" ls-tree HEAD "$path" 2>/dev/null | awk '{print $3}' || true)

            local source_path="$path"
            [[ "$parent_rel" != "." ]] && source_path="$parent_rel/$path"
            local already_emitted=false
            local emitted_path
            for emitted_path in "${_emitted_ref[@]}"; do
                if [[ "$emitted_path" == "$source_path" ]]; then
                    already_emitted=true
                    break
                fi
            done
            [[ "$already_emitted" == "true" ]] && continue

            _fleet_plan_emit_entry \
                "$name" "submodule" "$source_path" "$source_path" "adopt_submodule" \
                "service" "true" "$url" "${branch:-main}" "0.0.0" "true" \
                "$parent_rel" "$commit" "$name"
            _emitted_ref+=("$source_path")
        done < <(git -C "$parent_abs" config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null | sed 's/\.path$//')
    done < <(find "$root_dir" -name .gitmodules -type f -not -path '*/.git/*' -print0 2>/dev/null)
}

generate_fleet_plan_yaml() {
    local root_dir="${1:-$(pwd)}"
    local max_scan_depth="${2:-auto}"
    local safety_cap="${3:-10}"
    local fleet_name="${4:-}"

    [[ "$max_scan_depth" == "auto" ]] && max_scan_depth="$safety_cap"
    if ! [[ "$max_scan_depth" =~ ^[0-9]+$ ]]; then
        log_error "max scan depth must be 'auto' or a non-negative integer"
        return 1
    fi

    if [[ ! -d "$root_dir" ]]; then
        log_error "Fleet root does not exist: $root_dir"
        return 1
    fi

    root_dir=$(cd "$root_dir" && pwd)
    fleet_name="${fleet_name:-$(basename "$root_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-')}"

    local generated_at
    generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "# Manifest Fleet Plan"
    echo "# Generated by: manifest plan fleet"
    echo "plan:"
    echo "  schema_version: \"1\""
    echo "  generated_at: $(_fleet_plan_yaml_quote "$generated_at")"
    echo "  root: $(_fleet_plan_yaml_quote "$root_dir")"
    echo "fleet:"
    echo "  name: $(_fleet_plan_yaml_quote "$fleet_name")"
    echo "discovery:"
    echo "  max_scan_depth: $(_fleet_plan_yaml_quote "${2:-auto}")"
    echo "  safety_cap: $safety_cap"
    echo "rules:"
    echo "  - path: \"apps\""
    echo "    repo_depths: [1]"
    echo "  - path: \"services\""
    echo "    repo_depths: [1, 2]"
    echo "entries:"

    local emitted_paths=()
    local discovered
    discovered=$(discover_all_directories "$root_dir" "$max_scan_depth")
    if [[ -n "$discovered" ]]; then
        local line
        while IFS= read -r line; do
            local name path type branch version url submodule has_git _has_remote
            _fleet_plan_split_discovery_line "$line" name path type branch version url submodule has_git _has_remote
            [[ -z "$name" ]] && continue
            local kind action
            kind=$(_fleet_plan_kind_for_entry "$has_git" "$submodule")
            action=$(_fleet_plan_default_action_for_entry "$kind")
            _fleet_plan_emit_entry "$name" "$kind" "$path" "$path" "$action" "$type" "$has_git" "$url" "$branch" "$version" "$submodule"
            [[ "$kind" != "plain_dir" ]] && emitted_paths+=("$path")
        done <<< "$discovered"
    fi

    _fleet_plan_emit_submodules "$root_dir" emitted_paths
}

_fleet_plan_summary() {
    local plan_content="$1"
    local track=0 move=0 init=0 adopt=0 skip=0 other=0
    while IFS= read -r line; do
        case "$line" in
            *'action: "track"'*) ((track += 1)) ;;
            *'action: "move"'*) ((move += 1)) ;;
            *'action: "init"'*) ((init += 1)) ;;
            *'action: "adopt_submodule"'*) ((adopt += 1)) ;;
            *'action: "skip"'*) ((skip += 1)) ;;
            *'action: '*) ((other += 1)) ;;
        esac
    done <<< "$plan_content"

    echo "Plan summary:"
    echo "  track repos:        $track"
    echo "  move repos:         $move"
    echo "  init repos:         $init"
    echo "  adopt submodules:   $adopt"
    echo "  skip:               $skip"
    [[ "$other" -gt 0 ]] && echo "  other actions:      $other"
    return 0
}

fleet_plan() {
    local apply=false commit=false push=false force=false
    local depth="auto"
    local safety_cap=10
    local plan_file="$(pwd)/$MANIFEST_FLEET_DEFAULT_PLAN_FILE"
    local fleet_name=""

    if ! _fleet_parse_apply_contract apply commit push force "$@"; then
        return 1
    fi
    set -- "${FLEET_PLAN_REMAINING_ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth|--max-scan-depth)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "$1 requires a value"
                    return 1
                fi
                depth="$2"; shift 2 ;;
            --safety-cap)
                if [[ -z "${2:-}" ]] || ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    log_error "--safety-cap requires a numeric value"
                    return 1
                fi
                safety_cap="$2"; shift 2 ;;
            --plan)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--plan requires a file path"
                    return 1
                fi
                plan_file="$2"; shift 2 ;;
            --name|-n)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--name requires a value"
                    return 1
                fi
                fleet_name="$2"; shift 2 ;;
            -h|--help|help)
                _render_help \
                    "manifest plan fleet [--apply|--do] [--depth auto|N] [--plan FILE]" \
                    "Generate a fleet adoption plan. Dry-run by default." \
                    "Mutation" "  --apply, --do   Write the validated plan file
  --dry-run       Explicit no-op; dry-run is already the default" \
                    "Options" "  --depth N|auto  Scan depth guardrail (default: auto)
  --safety-cap N  Auto-depth ceiling (default: 10)
  --plan FILE     Plan file path (default: manifest.fleet.plan.yaml)
  --name NAME     Fleet name written into the plan"
                return 0 ;;
            *)
                log_error "Unknown plan fleet option: $1"
                return 1 ;;
        esac
    done

    local root_dir
    root_dir=$(pwd)

    local plan_content
    plan_content=$(generate_fleet_plan_yaml "$root_dir" "$depth" "$safety_cap" "$fleet_name") || return 1

    if [[ "$apply" != "true" ]]; then
        echo ""
        echo "Dry run - manifest plan fleet: $root_dir"
        echo ""
        echo "Would write: $plan_file"
        _fleet_plan_summary "$plan_content"
        echo ""
        echo "No changes written. Re-run with --apply or --do to apply."
        return 0
    fi

    if [[ -f "$plan_file" && "$force" != "true" ]]; then
        log_error "Plan file already exists: $plan_file"
        echo "Use --apply --force to overwrite it."
        return 1
    fi

    printf "%s\n" "$plan_content" > "$plan_file"
    echo "Created: $plan_file"
    _fleet_plan_summary "$plan_content"
}

export -f fleet_plan
export -f generate_fleet_plan_yaml
