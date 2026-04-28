#!/bin/bash

# =============================================================================
# Manifest Config CRUD (Tier 4 #18)
# =============================================================================
#
# Implements: manifest config list / get / set / unset / describe
#
# These give programmatic, layer-aware access to all 83 mapped YAML keys
# without forcing users to read source code or example files.
#
# Layers (lowest → highest precedence):
#   defaults  → built into the CLI (set_default_configuration)
#   global    → ~/.manifest-cli/manifest.config.global.yaml
#   project   → ./manifest.config.yaml
#   local     → ./manifest.config.local.yaml
#
# Default --layer for set/unset is "local" (least invasive). Writing global
# triggers _confirm_global_config_write.
# =============================================================================

if [[ -n "${_MANIFEST_CONFIG_CRUD_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CONFIG_CRUD_LOADED=1

# Resolve a layer name to a file path. Echoes path or empty string.
_cfg_layer_path() {
    local layer="$1"
    case "$layer" in
        global)  echo "${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}" ;;
        project) echo "${PROJECT_ROOT:-$(pwd)}/manifest.config.yaml" ;;
        local)   echo "${PROJECT_ROOT:-$(pwd)}/manifest.config.local.yaml" ;;
        *)       echo "" ;;
    esac
}

# Normalize a key argument to a YAML dot-path. Accepts both dot-path
# (git.tag_prefix) and env-var name (MANIFEST_CLI_GIT_TAG_PREFIX).
_cfg_normalize_key() {
    local key="$1"
    if [[ "$key" =~ ^MANIFEST_CLI_ ]]; then
        env_var_to_yaml_path "$key"
    else
        echo "$key"
    fi
}

# Echo "$file:$value" for the highest-precedence layer containing the path,
# or empty string if not present in any layer.
_cfg_effective_value() {
    local path="$1"
    local layer val file
    for layer in local project global; do
        file="$(_cfg_layer_path "$layer")"
        if [[ -f "$file" ]]; then
            val="$(yq e "(.${path} // \"\")" "$file" 2>/dev/null)"
            if [[ -n "$val" && "$val" != "null" ]]; then
                echo "$layer:$val"
                return 0
            fi
        fi
    done
    return 1
}

# -----------------------------------------------------------------------------
# manifest config list [--layer <layer>]
# -----------------------------------------------------------------------------
manifest_config_list() {
    local filter_layer=""
    local emit_json=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --layer) filter_layer="$2"; shift 2 ;;
            --json) emit_json=true; shift ;;
            -h|--help)
                _render_help \
                    "manifest config list [--layer global|project|local] [--json]" \
                    "List all configuration keys with their effective value and source layer.
With --layer, list only keys explicitly set in that layer's file.
With --json, emit a machine-readable array." \
                    "Examples" "  manifest config list
  manifest config list --layer global
  manifest config list --json"
                return 0
                ;;
            *) _render_help_error "Unknown option: $1" "manifest config list [--layer ...] [--json]"; return 1 ;;
        esac
    done

    if [[ -n "$filter_layer" ]]; then
        local file
        file="$(_cfg_layer_path "$filter_layer")"
        if [[ -z "$file" ]]; then
            log_error "Unknown layer: $filter_layer (use global, project, or local)"
            return 1
        fi
        if [[ ! -f "$file" ]]; then
            if [[ "$emit_json" == "true" ]]; then
                echo "[]"
            else
                echo "($filter_layer layer not present at $file)"
            fi
            return 0
        fi
        if [[ "$emit_json" == "true" ]]; then
            _config_list_json_layer "$filter_layer" "$file"
        else
            echo "Keys in $filter_layer ($file):"
            local path
            for path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
                local val
                val="$(yq e "(.${path} // \"\")" "$file" 2>/dev/null)"
                if [[ -n "$val" && "$val" != "null" ]]; then
                    printf "  %-40s %s\n" "$path" "$val"
                fi
            done | sort
        fi
        return 0
    fi

    if [[ "$emit_json" == "true" ]]; then
        _config_list_json_effective
        return 0
    fi

    echo "Manifest configuration (effective values, all layers merged)"
    echo ""
    printf "  %-40s %-8s %s\n" "KEY" "LAYER" "VALUE"
    local path
    for path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
        local result layer val
        if result="$(_cfg_effective_value "$path")"; then
            layer="${result%%:*}"
            val="${result#*:}"
            printf "  %-40s %-8s %s\n" "$path" "$layer" "$val"
        fi
    done | sort
}

# Emit `[{"key":..., "layer":..., "value":...}, ...]` of effective values.
# Sorted by key for stable diffing.
_config_list_json_effective() {
    local out=""
    local path
    while IFS= read -r path; do
        local result layer val
        if result="$(_cfg_effective_value "$path")"; then
            layer="${result%%:*}"
            val="${result#*:}"
            local entry
            entry="{$(_json_kv_str "key" "$path"),$(_json_kv_str "layer" "$layer"),$(_json_kv_raw "value" "$(_json_value "$val")")}"
            if [[ -z "$out" ]]; then
                out="$entry"
            else
                out="${out},${entry}"
            fi
        fi
    done < <(printf '%s\n' "${!_MANIFEST_YAML_TO_ENV[@]}" | sort)
    printf '[%s]\n' "$out"
}

# Emit `[{"key":..., "value":...}, ...]` for keys explicitly set in $file.
_config_list_json_layer() {
    local layer="$1" file="$2"
    local out=""
    local path
    while IFS= read -r path; do
        local val
        val="$(yq e "(.${path} // \"\")" "$file" 2>/dev/null)"
        if [[ -n "$val" && "$val" != "null" ]]; then
            local entry
            entry="{$(_json_kv_str "key" "$path"),$(_json_kv_str "layer" "$layer"),$(_json_kv_raw "value" "$(_json_value "$val")")}"
            if [[ -z "$out" ]]; then
                out="$entry"
            else
                out="${out},${entry}"
            fi
        fi
    done < <(printf '%s\n' "${!_MANIFEST_YAML_TO_ENV[@]}" | sort)
    printf '[%s]\n' "$out"
}

# -----------------------------------------------------------------------------
# manifest config get <key>
# -----------------------------------------------------------------------------
manifest_config_get() {
    if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest config get <key>" \
            "Print a config key's effective value (after layering)." \
            "Examples" "  manifest config get version.format
  manifest config get git.default_branch"
        return 1
    fi
    local path
    path="$(_cfg_normalize_key "$1")"
    if [[ -z "$path" ]]; then
        log_error "Unknown key: $1"
        return 1
    fi
    # Prefer explicit layer values (so user sees the actual file source). Fall
    # back to the env var, which carries the merged-and-defaulted result.
    local result
    if result="$(_cfg_effective_value "$path")"; then
        echo "${result#*:}"
        return 0
    fi
    local env_var
    env_var="$(yaml_path_to_env_var "$path")"
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# manifest config set [--layer <layer>] <key> <value>
# -----------------------------------------------------------------------------
manifest_config_set() {
    local layer="local"
    while [[ "${1:-}" == --* || "${1:-}" == -* ]]; do
        case "$1" in
            --layer) layer="$2"; shift 2 ;;
            -h|--help)
                _render_help \
                    "manifest config set [--layer global|project|local] <key> <value>" \
                    "Set a config key in a specific layer.
Default layer is 'local' (git-ignored). Writing 'global' prompts for
confirmation via the global-config safety gate." \
                    "Examples" "  manifest config set git.default_branch main
  manifest config set --layer project version.format semver
  manifest config set --layer global homebrew.formula_path Formula/manifest.rb"
                return 0
                ;;
            *) _render_help_error "Unknown option: $1" "manifest config set [--layer ...] <key> <value>"; return 1 ;;
        esac
    done

    local key="${1:-}"
    local value="${2:-}"
    if [[ -z "$key" || $# -lt 2 ]]; then
        _render_help_error \
            "set requires both a key and a value" \
            "manifest config set [--layer global|project|local] <key> <value>"
        return 1
    fi

    local path
    path="$(_cfg_normalize_key "$key")"
    if [[ -z "$path" ]]; then
        log_error "Unknown key: $key"
        return 1
    fi

    local file
    file="$(_cfg_layer_path "$layer")"
    if [[ -z "$file" ]]; then
        log_error "Unknown layer: $layer"
        return 1
    fi

    if [[ "$layer" == "global" ]]; then
        if ! _confirm_global_config_write "modify" "$file" "set $path = $value"; then
            return 1
        fi
    fi

    mkdir -p "$(dirname "$file")"
    set_yaml_value "$file" "$path" "$value" || return 1
    echo "✓ set ${layer}:${path} = ${value}"
    echo "  ${file}"
}

# -----------------------------------------------------------------------------
# manifest config unset [--layer <layer>] <key>
# -----------------------------------------------------------------------------
manifest_config_unset() {
    local layer="local"
    while [[ "${1:-}" == --* || "${1:-}" == -* ]]; do
        case "$1" in
            --layer) layer="$2"; shift 2 ;;
            -h|--help)
                _render_help \
                    "manifest config unset [--layer global|project|local] <key>" \
                    "Remove a config key from a specific layer." \
                    "Examples" "  manifest config unset git.default_branch
  manifest config unset --layer project version.format"
                return 0
                ;;
            *) _render_help_error "Unknown option: $1" "manifest config unset [--layer ...] <key>"; return 1 ;;
        esac
    done

    local key="${1:-}"
    if [[ -z "$key" ]]; then
        _render_help_error \
            "unset requires a key" \
            "manifest config unset [--layer global|project|local] <key>"
        return 1
    fi

    local path
    path="$(_cfg_normalize_key "$key")"
    [[ -z "$path" ]] && { log_error "Unknown key: $key"; return 1; }

    local file
    file="$(_cfg_layer_path "$layer")"
    [[ -z "$file" ]] && { log_error "Unknown layer: $layer"; return 1; }

    if [[ ! -f "$file" ]]; then
        echo "($layer file does not exist; nothing to unset)"
        return 0
    fi

    if [[ "$layer" == "global" ]]; then
        if ! _confirm_global_config_write "modify" "$file" "unset $path"; then
            return 1
        fi
    fi

    yq e "del(.${path})" -i "$file" 2>/dev/null
    echo "✓ unset ${layer}:${path}"
}

# -----------------------------------------------------------------------------
# manifest config describe <key>
# -----------------------------------------------------------------------------
manifest_config_describe() {
    if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        _render_help \
            "manifest config describe <key>" \
            "Show where a key's value comes from across layers, plus its env-var name." \
            "Examples" "  manifest config describe version.format
  manifest config describe homebrew.formula_path"
        return 1
    fi
    local path env_var
    path="$(_cfg_normalize_key "$1")"
    if [[ -z "$path" ]]; then
        log_error "Unknown key: $1"
        return 1
    fi
    env_var="$(yaml_path_to_env_var "$path")"

    # Compute the effective value the same way 'get' does — layer files first,
    # env-var fallback. (The 'config' command pre-dispatch loads with project
    # overrides off, so reading the env directly would miss local-layer values.)
    local effective="(unset)"
    local layer_result
    if layer_result="$(_cfg_effective_value "$path")"; then
        effective="${layer_result#*:}  (from ${layer_result%%:*})"
    elif [[ -n "${!env_var:-}" ]]; then
        effective="${!env_var}  (from defaults)"
    fi

    echo "Key:       $path"
    echo "Env var:   $env_var"
    echo "Effective: $effective"
    echo ""
    echo "Layers (highest precedence first):"
    local layer file val
    for layer in local project global; do
        file="$(_cfg_layer_path "$layer")"
        if [[ -f "$file" ]]; then
            val="$(yq e "(.${path} // \"\")" "$file" 2>/dev/null)"
            if [[ -n "$val" && "$val" != "null" ]]; then
                printf "  %-8s %s   (%s)\n" "$layer" "$val" "$file"
            else
                printf "  %-8s %s   (%s)\n" "$layer" "·" "$file"
            fi
        else
            printf "  %-8s %s   (%s — not present)\n" "$layer" "·" "$file"
        fi
    done
}

export -f manifest_config_list
export -f manifest_config_get
export -f manifest_config_set
export -f manifest_config_unset
export -f manifest_config_describe
export -f _config_list_json_effective
export -f _config_list_json_layer
