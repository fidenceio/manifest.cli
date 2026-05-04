#!/bin/bash

# =============================================================================
# MANIFEST FLEET APPLY MODULE
# =============================================================================
#
# Validates and reconciles manifest.fleet.plan.yaml. Dry-run by default.

if [[ -n "${_MANIFEST_FLEET_APPLY_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_FLEET_APPLY_LOADED=1

readonly MANIFEST_FLEET_APPLY_MODULE_VERSION="1.0.0"
readonly MANIFEST_FLEET_APPLY_MODULE_NAME="manifest-fleet-apply"

_fleet_plan_require_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq is required to read manifest.fleet.plan.yaml"
        return 1
    fi
}

_fleet_plan_entry_value() {
    local plan_file="$1"
    local idx="$2"
    local key="$3"
    yq e -r ".entries[$idx].$key // \"\"" "$plan_file"
}

_fleet_plan_entry_count() {
    local plan_file="$1"
    yq e '.entries | length' "$plan_file"
}

_fleet_config_service_exists() {
    local config_file="$1"
    local service="$2"
    [[ -f "$config_file" ]] || return 1
    grep -Eq "^  ${service}:" "$config_file"
}

_fleet_ensure_minimal_config() {
    local config_file="$1"
    local fleet_name="$2"
    if [[ -f "$config_file" ]]; then
        return 0
    fi
    {
        echo "fleet:"
        echo "  name: \"$fleet_name\""
        echo "  versioning: \"none\""
        echo "services:"
    } > "$config_file"
}

_fleet_plan_service_yaml() {
    local name="$1"
    local path="$2"
    local type="$3"
    local branch="$4"
    local url="$5"
    local submodule="$6"

    echo ""
    echo "  $name:"
    echo "    path: \"./$path\""
    [[ -n "$url" ]] && echo "    url: \"$url\""
    echo "    type: \"${type:-service}\""
    echo "    branch: \"${branch:-main}\""
    [[ "$submodule" == "true" ]] && echo "    submodule: true"
}

_fleet_plan_track_service() {
    local root_dir="$1"
    local config_file="$2"
    local fleet_name="$3"
    local name="$4"
    local target_path="$5"
    local type="$6"
    local branch="$7"
    local url="$8"
    local submodule="$9"

    _fleet_ensure_minimal_config "$config_file" "$fleet_name" || return 1
    if _fleet_config_service_exists "$config_file" "$name"; then
        return 0
    fi

    local yaml_content
    yaml_content=$(_fleet_plan_service_yaml "$name" "$target_path" "$type" "$branch" "$url" "$submodule")
    append_services_to_manifest "$config_file" "$yaml_content"
}

_fleet_plan_repo_dirty() {
    local repo_path="$1"
    [[ -d "$repo_path" ]] || return 1
    if git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        [[ -z "$(git -C "$repo_path" status --porcelain 2>/dev/null)" ]]
        return $?
    fi
    return 1
}

_fleet_plan_is_git_work_tree() {
    local repo_path="$1"
    [[ -d "$repo_path" ]] || return 1
    git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

_fleet_validate_plan_file() {
    local plan_file="$1"
    local root_dir="$2"
    local force="$3"
    local adopt_submodules="$4"

    _fleet_plan_require_yq || return 1
    [[ -f "$plan_file" ]] || {
        log_error "Plan file not found: $plan_file"
        echo "Run: manifest plan fleet --apply"
        return 1
    }

    local count
    count=$(_fleet_plan_entry_count "$plan_file") || return 1

    local errors=0
    local active_sources=()
    local active_targets=()

    local i
    for ((i = 0; i < count; i++)); do
        local name kind source_path target_path action remote_url parent_path
        name=$(_fleet_plan_entry_value "$plan_file" "$i" "name")
        kind=$(_fleet_plan_entry_value "$plan_file" "$i" "kind")
        source_path=$(_fleet_plan_entry_value "$plan_file" "$i" "source_path")
        target_path=$(_fleet_plan_entry_value "$plan_file" "$i" "target_path")
        action=$(_fleet_plan_entry_value "$plan_file" "$i" "action")
        remote_url=$(_fleet_plan_entry_value "$plan_file" "$i" "remote_url")
        parent_path=$(_fleet_plan_entry_value "$plan_file" "$i" "parent_path")

        case "$action" in
            track|move|init|adopt_submodule|skip) ;;
            *)
                log_error "Plan entry '$name' has unsupported action: $action"
                ((errors += 1))
                continue ;;
        esac

        [[ "$action" == "skip" ]] && continue

        if ! _fleet_path_is_safe_relative "$source_path"; then
            log_error "Plan entry '$name' has unsafe source_path: $source_path"
            ((errors += 1))
        fi
        if ! _fleet_path_is_safe_relative "$target_path"; then
            log_error "Plan entry '$name' has unsafe target_path: $target_path"
            ((errors += 1))
        fi

        local source_abs="$root_dir/${source_path#./}"
        local target_abs="$root_dir/${target_path#./}"

        if [[ "$action" != "track" && ! -e "$source_abs" ]]; then
            log_error "Plan entry '$name' source does not exist: $source_path"
            ((errors += 1))
        fi

        if [[ "$action" == "move" || "$action" == "adopt_submodule" || "$action" == "init" ]]; then
            if [[ "$source_path" == "$target_path" ]]; then
                if [[ "$action" != "init" ]]; then
                    log_error "Plan entry '$name' requires a distinct target_path for action '$action'"
                    ((errors += 1))
                fi
            elif [[ -e "$target_abs" ]]; then
                log_error "Plan entry '$name' target already exists: $target_path"
                ((errors += 1))
            fi
        fi

        if [[ "$action" == "adopt_submodule" ]]; then
            if [[ "$adopt_submodules" != "true" ]]; then
                log_error "Plan entry '$name' uses adopt_submodule; pass --adopt-submodules with --apply/--do"
                ((errors += 1))
            fi
            if [[ -z "$remote_url" ]]; then
                log_error "Plan entry '$name' cannot adopt submodule without remote_url"
                ((errors += 1))
            fi
            if [[ -z "$parent_path" ]]; then
                log_error "Plan entry '$name' cannot adopt submodule without parent_path"
                ((errors += 1))
            elif ! _fleet_plan_is_git_work_tree "$root_dir/${parent_path#./}"; then
                log_error "Plan entry '$name' parent is not a git repository: $parent_path"
                ((errors += 1))
            elif ! _fleet_plan_repo_dirty "$root_dir/${parent_path#./}"; then
                log_error "Plan entry '$name' parent repo has uncommitted changes: $parent_path"
                ((errors += 1))
            fi
        fi

        if [[ "$kind" == "git_repo" || "$kind" == "submodule" ]]; then
            if [[ -e "$source_abs" ]] && _fleet_plan_is_git_work_tree "$source_abs" && ! _fleet_plan_repo_dirty "$source_abs"; then
                log_error "Plan entry '$name' repo has uncommitted changes: $source_path"
                ((errors += 1))
            fi
        fi

        active_sources+=("$source_path")
        active_targets+=("$target_path")
    done

    local a b
    for ((a = 0; a < ${#active_targets[@]}; a++)); do
        for ((b = a + 1; b < ${#active_targets[@]}; b++)); do
            if [[ "${active_targets[$a]}" == "${active_targets[$b]}" ]]; then
                log_error "Plan has duplicate target_path: ${active_targets[$a]}"
                ((errors += 1))
            fi
            if [[ "${active_targets[$b]}" == "${active_targets[$a]}/"* || "${active_targets[$a]}" == "${active_targets[$b]}/"* ]]; then
                log_error "Plan selects nested target paths: ${active_targets[$a]} and ${active_targets[$b]}"
                ((errors += 1))
            fi
        done
    done

    [[ "$errors" -eq 0 ]]
}

_fleet_reconcile_summary() {
    local plan_file="$1"
    local count
    count=$(_fleet_plan_entry_count "$plan_file") || return 1
    local track=0 move=0 init=0 adopt=0 skip=0
    local i action
    for ((i = 0; i < count; i++)); do
        action=$(_fleet_plan_entry_value "$plan_file" "$i" "action")
        case "$action" in
            track) ((track += 1)) ;;
            move) ((move += 1)) ;;
            init) ((init += 1)) ;;
            adopt_submodule) ((adopt += 1)) ;;
            skip) ((skip += 1)) ;;
        esac
    done
    echo "Will apply:"
    echo "  track repos:        $track"
    echo "  move repos:         $move"
    echo "  init repos:         $init"
    echo "  adopt submodules:   $adopt"
    echo "  skip:               $skip"
}

_fleet_apply_adopt_submodule() {
    local root_dir="$1"
    local name="$2"
    local source_path="$3"
    local target_path="$4"
    local remote_url="$5"
    local parent_path="$6"
    local submodule_name="$7"
    local pinned_commit="$8"

    local target_abs="$root_dir/${target_path#./}"
    local parent_abs="$root_dir/${parent_path#./}"
    local submodule_rel="$source_path"
    if [[ "$parent_path" != "." && "$source_path" == "$parent_path/"* ]]; then
        submodule_rel="${source_path#"$parent_path"/}"
    fi

    mkdir -p "$(dirname "$target_abs")" || return 1
    git clone "$remote_url" "$target_abs" || return 1
    if [[ -n "$pinned_commit" && "$pinned_commit" != "null" ]]; then
        git -C "$target_abs" checkout "$pinned_commit" || return 1
    fi

    git -C "$parent_abs" rm -f "$submodule_rel" || return 1
    git -C "$parent_abs" config -f .gitmodules --remove-section "submodule.$submodule_name" 2>/dev/null || true
    [[ -f "$parent_abs/.gitmodules" ]] && git -C "$parent_abs" add .gitmodules
}

_fleet_apply_plan() {
    local plan_file="$1"
    local root_dir="$2"
    local force="$3"
    local adopt_submodules="$4"
    local commit="$5"
    local push="$6"

    local fleet_name
    fleet_name=$(yq e -r '.fleet.name // "fleet"' "$plan_file")
    local config_file="$root_dir/manifest.fleet.config.yaml"
    local count
    count=$(_fleet_plan_entry_count "$plan_file") || return 1

    local i
    for ((i = 0; i < count; i++)); do
        local name kind source_path target_path action type remote_url branch submodule parent_path submodule_name pinned_commit
        name=$(_fleet_plan_entry_value "$plan_file" "$i" "name")
        kind=$(_fleet_plan_entry_value "$plan_file" "$i" "kind")
        source_path=$(_fleet_plan_entry_value "$plan_file" "$i" "source_path")
        target_path=$(_fleet_plan_entry_value "$plan_file" "$i" "target_path")
        action=$(_fleet_plan_entry_value "$plan_file" "$i" "action")
        type=$(_fleet_plan_entry_value "$plan_file" "$i" "type")
        remote_url=$(_fleet_plan_entry_value "$plan_file" "$i" "remote_url")
        branch=$(_fleet_plan_entry_value "$plan_file" "$i" "branch")
        submodule=$(_fleet_plan_entry_value "$plan_file" "$i" "submodule")
        parent_path=$(_fleet_plan_entry_value "$plan_file" "$i" "parent_path")
        submodule_name=$(_fleet_plan_entry_value "$plan_file" "$i" "submodule_name")
        pinned_commit=$(_fleet_plan_entry_value "$plan_file" "$i" "pinned_commit")

        [[ "$action" == "skip" ]] && continue

        local source_abs="$root_dir/${source_path#./}"
        local target_abs="$root_dir/${target_path#./}"

        case "$action" in
            track)
                _fleet_plan_track_service "$root_dir" "$config_file" "$fleet_name" "$name" "$target_path" "$type" "$branch" "$remote_url" "$submodule" || return 1
                ;;
            init)
                if [[ "$source_path" != "$target_path" ]]; then
                    mkdir -p "$(dirname "$target_abs")" || return 1
                    mv "$source_abs" "$target_abs" || return 1
                fi
                git -C "$target_abs" init -q || return 1
                ensure_gitignore_smart "$target_abs" >/dev/null || return 1
                _fleet_plan_track_service "$root_dir" "$config_file" "$fleet_name" "$name" "$target_path" "$type" "$branch" "$remote_url" "false" || return 1
                ;;
            move)
                mkdir -p "$(dirname "$target_abs")" || return 1
                mv "$source_abs" "$target_abs" || return 1
                _fleet_plan_track_service "$root_dir" "$config_file" "$fleet_name" "$name" "$target_path" "$type" "$branch" "$remote_url" "false" || return 1
                ;;
            adopt_submodule)
                [[ "$adopt_submodules" == "true" ]] || return 1
                _fleet_apply_adopt_submodule "$root_dir" "$name" "$source_path" "$target_path" "$remote_url" "$parent_path" "$submodule_name" "$pinned_commit" || return 1
                _fleet_plan_track_service "$root_dir" "$config_file" "$fleet_name" "$name" "$target_path" "$type" "$branch" "$remote_url" "false" || return 1
                ;;
        esac
    done

    if [[ "$commit" == "true" ]]; then
        if git -C "$root_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local plan_add_path="$plan_file"
            [[ "$plan_add_path" == "$root_dir/"* ]] && plan_add_path="${plan_add_path#"$root_dir"/}"
            git -C "$root_dir" add manifest.fleet.config.yaml "$plan_add_path" 2>/dev/null || true
            if ! git -C "$root_dir" diff --cached --quiet; then
                git -C "$root_dir" commit -m "Reconcile fleet adoption plan" || return 1
            fi
            [[ "$push" == "true" ]] && git -C "$root_dir" push || return 1
        else
            log_warning "--commit requested, but fleet root is not a git repository"
        fi
    fi
}

fleet_reconcile() {
    local apply=false commit=false push=false force=false
    local plan_file="$(pwd)/$MANIFEST_FLEET_DEFAULT_PLAN_FILE"
    local adopt_submodules=false

    if ! _fleet_parse_apply_contract apply commit push force "$@"; then
        return 1
    fi
    set -- "${FLEET_PLAN_REMAINING_ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--plan requires a file path"
                    return 1
                fi
                plan_file="$2"; shift 2 ;;
            --adopt-submodules)
                adopt_submodules=true; shift ;;
            -h|--help|help)
                _render_help \
                    "manifest reconcile fleet [--apply|--do] [--plan FILE] [--commit] [--push]" \
                    "Validate and apply a fleet adoption plan. Dry-run by default." \
                    "Mutation" "  --apply, --do       Apply local filesystem/config changes
  --commit            Commit local changes; requires --apply/--do
  --push              Push commits; requires --commit
  --force             Reserved for explicit overrides; requires --apply/--do" \
                    "Dangerous Actions" "  --adopt-submodules  Allow adopt_submodule plan entries"
                return 0 ;;
            *)
                log_error "Unknown reconcile fleet option: $1"
                return 1 ;;
        esac
    done

    local root_dir
    root_dir=$(pwd)

    if [[ "$apply" != "true" ]]; then
        _fleet_plan_require_yq || return 1
        [[ -f "$plan_file" ]] || {
            log_error "Plan file not found: $plan_file"
            echo "Run: manifest plan fleet --apply"
            return 1
        }
        echo ""
        echo "Dry run - manifest reconcile fleet: $root_dir"
        echo ""
        _fleet_reconcile_summary "$plan_file" || return 1
        echo ""
        if _fleet_validate_plan_file "$plan_file" "$root_dir" "$force" "$adopt_submodules"; then
            echo "Validation: passed"
            echo ""
            echo "No changes written. Re-run with --apply or --do to apply."
            return 0
        fi
        echo ""
        echo "Validation: failed"
        echo "No changes written."
        return 1
    fi

    echo ""
    echo "Applying manifest reconcile fleet: $root_dir"
    echo ""
    _fleet_reconcile_summary "$plan_file" || return 1
    echo ""

    _fleet_validate_plan_file "$plan_file" "$root_dir" "$force" "$adopt_submodules" || return 1
    _fleet_apply_plan "$plan_file" "$root_dir" "$force" "$adopt_submodules" "$commit" "$push" || return 1
    echo "Fleet reconciliation applied."
}

export -f fleet_reconcile
