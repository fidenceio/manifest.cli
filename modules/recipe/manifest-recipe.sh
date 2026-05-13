#!/bin/bash

# Manifest Recipe Module
# Provides first-class, inspectable workflow definitions for stable CLI commands.

if [[ -n "${_MANIFEST_RECIPE_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_RECIPE_LOADED=1

_manifest_recipe_cli_root() {
    echo "${MANIFEST_CLI_CORE_MODULES_DIR%/modules}"
}

_manifest_recipe_builtin_dir() {
    echo "$(_manifest_recipe_cli_root)/recipes/builtin"
}

_manifest_recipe_project_dir() {
    echo "${PROJECT_ROOT:-$PWD}/.manifest/recipes"
}

_manifest_recipe_files() {
    local builtin_dir project_dir
    builtin_dir="$(_manifest_recipe_builtin_dir)"
    project_dir="$(_manifest_recipe_project_dir)"

    if [[ -d "$builtin_dir" ]]; then
        find "$builtin_dir" -type f -name '*.yaml' | sort
    fi
    if [[ -d "$project_dir" ]]; then
        find "$project_dir" -type f -name '*.yaml' | sort
    fi
}

_manifest_recipe_value() {
    local file="$1"
    local path="$2"
    local default="${3:-}"

    get_yaml_value "$file" "$path" "$default" 2>/dev/null || true
}

_manifest_recipe_file_for_id() {
    local wanted_id="$1"
    local file id

    if [[ -z "$wanted_id" ]]; then
        return 1
    fi

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        id="$(_manifest_recipe_value "$file" ".id")"
        if [[ "$id" == "$wanted_id" ]]; then
            echo "$file"
            return 0
        fi
    done < <(_manifest_recipe_files)

    return 1
}

manifest_recipe_id_for_command() {
    local command="$1"
    local scope="$2"
    local release_type="${3:-}"

    case "$command $scope $release_type" in
        "ship repo patch") echo "manifest.builtin.ship.repo.patch" ;;
        "ship repo minor") echo "manifest.builtin.ship.repo.minor" ;;
        "ship repo major") echo "manifest.builtin.ship.repo.major" ;;
        "ship repo revision") echo "manifest.builtin.ship.repo.revision" ;;
        "ship fleet patch") echo "manifest.builtin.ship.fleet.patch" ;;
        "ship fleet minor") echo "manifest.builtin.ship.fleet.minor" ;;
        "ship fleet major") echo "manifest.builtin.ship.fleet.major" ;;
        "ship fleet revision") echo "manifest.builtin.ship.fleet.revision" ;;
        *) return 1 ;;
    esac
}

manifest_recipe_list() {
    local file id command summary kind

    printf '%-42s %-8s %-32s %s\n' "ID" "KIND" "COMMAND" "SUMMARY"
    printf '%-42s %-8s %-32s %s\n' "--" "----" "-------" "-------"
    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        id="$(_manifest_recipe_value "$file" ".id")"
        kind="$(_manifest_recipe_value "$file" ".kind" "project")"
        command="$(_manifest_recipe_value "$file" ".command")"
        summary="$(_manifest_recipe_value "$file" ".summary")"
        [[ -n "$id" ]] || continue
        printf '%-42s %-8s %-32s %s\n' "$id" "$kind" "$command" "$summary"
    done < <(_manifest_recipe_files)
}

manifest_recipe_show() {
    local id="$1"
    local file

    if [[ -z "$id" ]]; then
        _render_help_error "recipe show requires an id" "manifest recipe show <id>"
        return 1
    fi

    if ! file="$(_manifest_recipe_file_for_id "$id")"; then
        log_error "Recipe not found: $id"
        return 1
    fi

    cat "$file"
}

manifest_recipe_explain() {
    local id="$1"
    local file title command scope summary entrypoint

    if [[ -z "$id" ]]; then
        _render_help_error "recipe explain requires an id" "manifest recipe explain <id>"
        return 1
    fi

    if ! file="$(_manifest_recipe_file_for_id "$id")"; then
        log_error "Recipe not found: $id"
        return 1
    fi

    title="$(_manifest_recipe_value "$file" ".title")"
    command="$(_manifest_recipe_value "$file" ".command")"
    scope="$(_manifest_recipe_value "$file" ".scope")"
    summary="$(_manifest_recipe_value "$file" ".summary")"
    entrypoint="$(_manifest_recipe_value "$file" ".entrypoint")"

    echo "$title"
    echo ""
    echo "ID:         $id"
    echo "Command:    $command"
    echo "Scope:      $scope"
    echo "Entrypoint: ${entrypoint:-not executable directly}"
    echo "Definition: $file"
    if [[ -n "$summary" ]]; then
        echo ""
        echo "$summary"
    fi
    echo ""
    echo "Steps:"
    yq e -r '.steps[] | [.id, .uses, (.effect // "unspecified"), (.when // "")] | @tsv' "$file" | while IFS=$'\t' read -r step_id uses effect when_clause; do
        local suffix=" {effect: $effect}"
        if [[ -n "$when_clause" ]]; then
            echo "  - $step_id -> $uses$suffix [$when_clause]"
        else
            echo "  - $step_id -> $uses$suffix"
        fi
    done
}

manifest_recipe_explain_command() {
    local recipe_id

    if ! recipe_id="$(manifest_recipe_id_for_command "$@")"; then
        log_error "No built-in recipe is registered for: manifest $*"
        return 1
    fi
    manifest_recipe_explain "$recipe_id"
}

_manifest_recipe_trim_condition_token() {
    local token="$1"

    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    token="${token//(/}"
    token="${token//)/}"
    echo "$token"
}

_manifest_recipe_condition_token_active() {
    local token="$1"
    local execution_mode="$2"
    local local_only="$3"
    local publish_release="$4"
    local negate=false

    token="$(_manifest_recipe_trim_condition_token "$token")"
    while [[ "$token" == !* ]]; do
        negate=true
        token="${token#!}"
        token="$(_manifest_recipe_trim_condition_token "$token")"
    done

    local active=true
    case "$token" in
        ""|true) active=true ;;
        false) active=false ;;
        apply) [[ "$execution_mode" == "apply" ]] && active=true || active=false ;;
        preview) [[ "$execution_mode" == "preview" ]] && active=true || active=false ;;
        local) [[ "$local_only" == "true" ]] && active=true || active=false ;;
        publish_release) [[ "$publish_release" == "true" ]] && active=true || active=false ;;
        github.release.enabled) is_truthy "${MANIFEST_CLI_GITHUB_RELEASE_ENABLED:-true}" && active=true || active=false ;;
        *)
            # Unknown conditions are treated as active so policy validation fails
            # closed instead of allowing an unmodeled remote write in local mode.
            active=true
            ;;
    esac

    if [[ "$negate" == "true" ]]; then
        [[ "$active" == "true" ]] && active=false || active=true
    fi

    [[ "$active" == "true" ]]
}

_manifest_recipe_when_active() {
    local when_clause="$1"
    local execution_mode="$2"
    local local_only="$3"
    local publish_release="$4"
    local token

    [[ -n "$when_clause" ]] || return 0
    while IFS= read -r token; do
        if ! _manifest_recipe_condition_token_active "$token" "$execution_mode" "$local_only" "$publish_release"; then
            return 1
        fi
    done <<< "${when_clause//&&/$'\n'}"

    return 0
}

manifest_recipe_validate_local_apply_file() {
    local file="$1"
    local label="$2"
    local execution_mode="$3"
    local local_only="$4"
    local publish_release="$5"
    local step_id when_clause offenders=""

    if [[ "$execution_mode" != "apply" || "$local_only" != "true" ]]; then
        return 0
    fi

    while IFS=$'\t' read -r step_id when_clause; do
        [[ -n "$step_id" ]] || continue
        if _manifest_recipe_when_active "$when_clause" "$execution_mode" "$local_only" "$publish_release"; then
            offenders="${offenders}${offenders:+, }${step_id}"
        fi
    done < <(yq e -r '.steps[] | select(.effect == "remote-write") | [.id, (.when // "")] | @tsv' "$file")

    if [[ -n "$offenders" ]]; then
        log_error "Refusing local apply because recipe '$label' would activate remote-write step(s): $offenders"
        echo "Use the non-local command with -y when remote publish effects are intended."
        return 1
    fi

    return 0
}

manifest_recipe_validate_command_effects() {
    local command="$1"
    local scope="$2"
    local release_type="$3"
    local execution_mode="$4"
    local local_only="$5"
    local publish_release="$6"
    local recipe_id file

    if ! recipe_id="$(manifest_recipe_id_for_command "$command" "$scope" "$release_type")"; then
        log_error "No built-in recipe is registered for: manifest $command $scope $release_type"
        return 1
    fi

    if ! file="$(_manifest_recipe_file_for_id "$recipe_id")"; then
        log_error "Recipe not found: $recipe_id"
        return 1
    fi

    manifest_recipe_validate_local_apply_file \
        "$file" "manifest $command $scope $release_type" \
        "$execution_mode" "$local_only" "$publish_release"
}

manifest_recipe_run() {
    local id="$1"
    local file command
    shift || true

    if [[ -z "$id" ]]; then
        _render_help_error "recipe run requires an id" "manifest recipe run <id> [recipe options]"
        return 1
    fi

    if ! file="$(_manifest_recipe_file_for_id "$id")"; then
        log_error "Recipe not found: $id"
        return 1
    fi

    command="$(_manifest_recipe_value "$file" ".command")"
    log_deprecated "manifest recipe run" "${command:-mapped first-class command}" "recipes are inspectable contracts; run the named command instead"
    case "$command" in
        "manifest ship repo patch") manifest_ship_repo patch "$@" ;;
        "manifest ship repo minor") manifest_ship_repo minor "$@" ;;
        "manifest ship repo major") manifest_ship_repo major "$@" ;;
        "manifest ship repo revision") manifest_ship_repo revision "$@" ;;
        "manifest ship fleet patch") manifest_ship_fleet patch "$@" ;;
        "manifest ship fleet minor") manifest_ship_fleet minor "$@" ;;
        "manifest ship fleet major") manifest_ship_fleet major "$@" ;;
        "manifest ship fleet revision") manifest_ship_fleet revision "$@" ;;
        "manifest prep repo") manifest_prep_repo "$@" ;;
        "manifest refresh repo") manifest_refresh_repo "$@" ;;
        "manifest pr ready") manifest_pr_ready "$@" ;;
        "manifest security --check") manifest_security --check "$@" ;;
        *)
            log_error "Recipe run is not wired for command: $command"
            echo "Use 'manifest recipe show $id' to inspect the definition."
            return 1
            ;;
    esac
}

manifest_recipe_dispatch() {
    local subcommand="${1:-list}"
    shift || true

    case "$subcommand" in
        list)
            manifest_recipe_list "$@"
            ;;
        show)
            manifest_recipe_show "$@"
            ;;
        explain)
            manifest_recipe_explain "$@"
            ;;
        run)
            manifest_recipe_run "$@"
            ;;
        help|-h|--help)
            _render_help \
                "manifest recipe <list|show|explain> [id]" \
                "Inspect Manifest workflow recipes behind first-class commands." \
                "Commands" "  list                List available built-in and project recipes
  show <id>           Print the recipe YAML definition
  explain <id>        Explain command mapping and ordered steps" \
                "Examples" "  manifest recipe list
  manifest recipe explain manifest.builtin.ship.repo.patch
  manifest ship repo patch --explain"
            ;;
        *)
            _render_help_error "Unknown recipe command: $subcommand" "manifest recipe <list|show|explain> [id]"
            return 1
            ;;
    esac
}

export -f manifest_recipe_id_for_command
export -f manifest_recipe_list
export -f manifest_recipe_show
export -f manifest_recipe_explain
export -f manifest_recipe_explain_command
export -f manifest_recipe_validate_local_apply_file
export -f manifest_recipe_validate_command_effects
export -f manifest_recipe_run
export -f manifest_recipe_dispatch
