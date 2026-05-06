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
    yq e -r '.steps[] | [.id, .uses, (.when // "")] | @tsv' "$file" | while IFS=$'\t' read -r step_id uses when_clause; do
        if [[ -n "$when_clause" ]]; then
            echo "  - $step_id -> $uses [$when_clause]"
        else
            echo "  - $step_id -> $uses"
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
                "manifest recipe <list|show|explain|run> [id]" \
                "Inspect and run Manifest workflow recipes." \
                "Commands" "  list                List available built-in and project recipes
  show <id>           Print the recipe YAML definition
  explain <id>        Explain command mapping and ordered steps
  run <id> [options]  Run a wired recipe explicitly" \
                "Examples" "  manifest recipe list
  manifest recipe explain manifest.builtin.ship.repo.patch
  manifest ship repo patch --explain"
            ;;
        *)
            _render_help_error "Unknown recipe command: $subcommand" "manifest recipe <list|show|explain|run> [id]"
            return 1
            ;;
    esac
}

export -f manifest_recipe_id_for_command
export -f manifest_recipe_list
export -f manifest_recipe_show
export -f manifest_recipe_explain
export -f manifest_recipe_explain_command
export -f manifest_recipe_run
export -f manifest_recipe_dispatch
