#!/bin/bash

# =============================================================================
# Manifest Config CRUD (Tier 4 #18)
# =============================================================================
#
# Implements: manifest config list / get / set / unset / describe
#
# These give programmatic, layer-aware access to every mapped YAML key without
# forcing users to read source code or example files.
#
# READ layers (highest → lowest precedence) — what get/list/describe resolve:
#   env       → exported MANIFEST_CLI_* captured at process start
#   local     → ./manifest.config.local.yaml
#   project   → ./manifest.config.yaml
#   fleet     → <fleet-root>/manifest.config.local.yaml, then
#               <fleet-root>/manifest.config.yaml   (members only; see below)
#   global    → ~/.manifest-cli/manifest.config.global.yaml
#   defaults  → built into the CLI (set_default_configuration)
#
# WRITE layers — what set/unset may touch: global | project | local. This set is
# deliberately narrower than the read set, and the difference is not an
# oversight:
#   - 'fleet' resolves to files in a DIFFERENT REPOSITORY. Writing it from
#     inside a member would mutate the fleet root behind the operator's back.
#     Fleet-wide values are set by running this command AT the fleet root, where
#     the same files are ordinary 'project'/'local' layers.
#   - 'env' and 'defaults' are virtual layers with no file to write.
# Keep _cfg_layer_path (the write resolver) closed. Read resolution goes through
# _cfg_build_read_layers / _cfg_resolve instead. Merging the two would let
# `config set --layer fleet` silently write the fleet root.
#
# The canonical description of the layer model is docs/USER_GUIDE.md#configuration;
# the implementation of record is load_configuration() in
# modules/core/manifest-config.sh.
#
# Default --layer for set/unset is "local" (least invasive). Writing global
# triggers _confirm_global_config_write.
# =============================================================================

if [[ -n "${_MANIFEST_CONFIG_CRUD_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CONFIG_CRUD_LOADED=1

# Ordered read-layer table ("layer<TAB>file", highest precedence first) and its
# memo key. Rebuilt whenever the project root / fleet root / global config path
# changes -- bats mutates those inside a single shell, so a once-only flag would
# be wrong.
declare -ga _CFG_READ_LAYERS=()
_CFG_LAYERS_CACHE_KEY=""
_CFG_FLEET_CACHE_KEY=""
_CFG_FLEET_CACHE_VAL=""

# Out-variables set by _cfg_resolve. _CFG_R_FILE is "" for virtual layers.
_CFG_R_LAYER=""
_CFG_R_FILE=""
_CFG_R_VALUE=""

# Single resolution point for the project root. The layer files AND the fleet
# walk must start from the same base, or the "is the project the fleet root?"
# test can disagree with the paths it is comparing.
_cfg_project_root() {
    printf '%s\n' "${MANIFEST_CLI_PROJECT_ROOT:-$(pwd)}"
}

# WRITE resolver: echoes the target file for a writable layer, or empty string.
# Deliberately closed to global/project/local -- see the module header. Do NOT
# teach this function about 'fleet': the [[ -z "$file" ]] guards in
# manifest_config_set/unset are the only thing standing between `--layer fleet`
# and a silent write into another repository.
_cfg_layer_path() {
    local layer="$1" root
    root="$(_cfg_project_root)"
    case "$layer" in
        global)  echo "${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}" ;;
        project) echo "$root/manifest.config.yaml" ;;
        local)   echo "$root/manifest.config.local.yaml" ;;
        *)       echo "" ;;
    esac
}

# True when $1 names a real layer that exists for reading but cannot be written.
# Lets set/unset explain themselves instead of claiming the layer is unknown --
# it isn't, `config list --layer fleet` accepts it.
_cfg_layer_is_readonly() {
    case "$1" in
        fleet|env|defaults) return 0 ;;
        *) return 1 ;;
    esac
}

# Explain a rejected write layer and return 1. $1 layer, $2 verb (set|unset).
_cfg_reject_write_layer() {
    local layer="$1" verb="$2" fleet_root
    if ! _cfg_layer_is_readonly "$layer"; then
        log_error "Unknown layer: $layer (writable layers: global, project, local)"
        return 1
    fi
    if [[ "$layer" == "env" || "$layer" == "defaults" ]]; then
        log_error "--layer $layer is not writable: it is a virtual layer (process environment / built-in defaults), not a file."
        echo "  Write a file layer instead, e.g. manifest config $verb --layer local ..." >&2
        return 1
    fi
    fleet_root="$(_cfg_fleet_root)"
    if [[ -n "$fleet_root" ]]; then
        log_error "--layer fleet is read-only here: it belongs to a different repository ($fleet_root)."
        echo "  Fleet-wide:      cd \"$fleet_root\" && manifest config $verb --layer project ..." >&2
        echo "  This repo only:  manifest config $verb --layer local ..." >&2
    else
        log_error "--layer fleet is read-only, and this repository is not inside a fleet (no manifest.fleet.config.yaml in any ancestor)."
        echo "  Writable layers: global, project, local." >&2
    fi
    return 1
}

# Normalize a key argument to a YAML dot-path. Accepts both dot-path
# (git.tag_prefix) and env-var name (MANIFEST_CLI_GIT_TAG_PREFIX).
_cfg_normalize_key() {
    local key="$1"
    local path
    if [[ "$key" =~ ^MANIFEST_CLI_ ]]; then
        # env_var_to_yaml_path validates against the reverse map and returns
        # empty for env vars with no mapping.
        path="$(env_var_to_yaml_path "$key" 2>/dev/null)"
    else
        path="$key"
    fi
    # Reject keys that don't map to a known setting. Without this, `config set`
    # would happily write a dotted key the runtime loader never reads (it only
    # iterates _MANIFEST_YAML_TO_ENV), leaving inert YAML behind.
    if [[ -z "${_MANIFEST_YAML_TO_ENV[$path]:-}" ]]; then
        echo ""
        return 1
    fi
    echo "$path"
}

# True when manifest-config.sh's process-start override map is available. It is
# not, when this module is sourced standalone (some tests do exactly that), so
# every use must be guarded or an unbound-variable error lands on stderr and
# corrupts --json output.
_cfg_env_override_map_ready() {
    case "$(declare -p _MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES 2>/dev/null || true)" in
        declare\ -A*) return 0 ;;
        *) return 1 ;;
    esac
}

# Echo the fleet root ONLY when it applies as an inherited layer: found, and
# different from the canonical project root. Mirrors the guard in
# load_configuration (modules/core/manifest-config.sh) exactly -- when the
# project IS the fleet root, those files are already the project/local layers
# and must not be counted twice.
#
# Deliberately uses the loader's sentinel walk and NOT the fleet module's
# find_fleet_root: that one honors MANIFEST_CLI_FLEET_ROOT and starts from the
# git root, so it can name a root the loader never inherits from. Reporting a
# layer the runtime does not load would be a new lie in place of the old one.
_cfg_fleet_root() {
    local root key
    root="$(_cfg_project_root)"
    key="${root}|${MANIFEST_CLI_FLEET_CONFIG_FILENAME:-manifest.fleet.config.yaml}"
    if [[ "${_CFG_FLEET_CACHE_KEY:-}" == "$key" ]]; then
        printf '%s\n' "${_CFG_FLEET_CACHE_VAL:-}"
        return 0
    fi
    local val="" canon fr
    if declare -F _manifest_config_find_fleet_root >/dev/null 2>&1; then
        canon="$(cd "$root" 2>/dev/null && pwd -P)" || canon="$root"
        if fr="$(_manifest_config_find_fleet_root "$root")" \
           && [[ -n "$fr" && "$fr" != "$canon" ]]; then
            val="$fr"
        fi
    fi
    _CFG_FLEET_CACHE_KEY="$key"
    _CFG_FLEET_CACHE_VAL="$val"
    printf '%s\n' "$val"
}

# Populate _CFG_READ_LAYERS with "layer<TAB>file", highest precedence first.
# The fleet root contributes TWO files under the single 'fleet' id (its local
# file shadows its shared file, matching the loader's load order).
_cfg_build_read_layers() {
    local root fleet key
    root="$(_cfg_project_root)"
    fleet="$(_cfg_fleet_root)"
    key="${root}|${fleet}|${MANIFEST_CLI_GLOBAL_CONFIG:-}"
    [[ "${_CFG_LAYERS_CACHE_KEY:-}" == "$key" ]] && return 0
    _CFG_READ_LAYERS=(
        "local"$'\t'"$root/manifest.config.local.yaml"
        "project"$'\t'"$root/manifest.config.yaml"
    )
    if [[ -n "$fleet" ]]; then
        _CFG_READ_LAYERS+=(
            "fleet"$'\t'"$fleet/manifest.config.local.yaml"
            "fleet"$'\t'"$fleet/manifest.config.yaml"
        )
    fi
    _CFG_READ_LAYERS+=( "global"$'\t'"${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}" )
    _CFG_LAYERS_CACHE_KEY="$key"
    return 0
}

# Echo the "layer<TAB>file" entries a --layer filter selects, highest first.
# Returns 1 for a name that is not a readable layer at all.
_cfg_filter_layer_files() {
    local want="$1" entry
    case "$want" in
        local|project|fleet|global) ;;
        *) return 1 ;;
    esac
    _cfg_build_read_layers
    for entry in "${_CFG_READ_LAYERS[@]}"; do
        [[ "${entry%%$'\t'*}" == "$want" ]] && printf '%s\n' "$entry"
    done
    return 0
}

# Resolve a key across every layer in RUNTIME precedence order, setting
# _CFG_R_LAYER / _CFG_R_FILE / _CFG_R_VALUE. Returns 1 when the key is set
# nowhere at all. Out-variables rather than a packed "layer:value" string: it
# avoids a fork per key, and values legitimately contain colons and newlines
# (sequence-valued keys come back multi-line), which a packed string mangles.
_cfg_resolve() {
    local path="$1"
    _CFG_R_LAYER=""; _CFG_R_FILE=""; _CFG_R_VALUE=""
    local env_var="${_MANIFEST_YAML_TO_ENV[$path]:-}"

    # Highest layer: an override exported into this process BEFORE startup.
    # This must come from the captured snapshot, never from live ${!env_var} --
    # load_configuration ends by exporting every mapped key, so reading the live
    # environment would attribute every single key to 'env'.
    local env_suppressed=false
    if [[ -n "$env_var" ]] && _cfg_env_override_map_ready; then
        if [[ -n "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[$env_var]+x}" ]]; then
            if [[ -n "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[$env_var]}" ]]; then
                _CFG_R_LAYER="env"
                _CFG_R_VALUE="${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[$env_var]}"
                return 0
            fi
            # Exported but empty: re-exported over every YAML layer, then
            # refilled by set_default_configuration's ${VAR:-default}. So it
            # carries no value of its own -- it only suppresses the files.
            env_suppressed=true
        fi
    fi

    if [[ "$env_suppressed" != true ]]; then
        local entry layer file val
        _cfg_build_read_layers
        for entry in "${_CFG_READ_LAYERS[@]}"; do
            layer="${entry%%$'\t'*}"
            file="${entry#*$'\t'}"
            [[ -f "$file" ]] || continue
            val="$(yq e "(.${path} // \"\")" "$file" 2>/dev/null)"
            if [[ -n "$val" && "$val" != "null" ]]; then
                _CFG_R_LAYER="$layer"; _CFG_R_FILE="$file"; _CFG_R_VALUE="$val"
                return 0
            fi
        done
    fi

    # Lowest layer: the built-in default, observed through the already-loaded
    # environment. Sound because the walk above covers every file the loader
    # reads, so anything still set can only have come from a default.
    if [[ -n "$env_var" && -n "${!env_var:-}" ]]; then
        _CFG_R_LAYER="defaults"; _CFG_R_VALUE="${!env_var}"
        return 0
    fi
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
                    "manifest config list [--layer global|fleet|project|local] [--json]" \
                    "List all configuration keys with their effective value and source layer.
With --layer, list only keys explicitly set in that layer's file.
'fleet' is a read-only layer inherited from the fleet root; it cannot be written.
With --json, emit a machine-readable array." \
                    "Examples" "  manifest config list
  manifest config list --layer global
  manifest config list --layer fleet
  manifest config list --json"
                return 0
                ;;
            *) _render_help_error "Unknown option: $1" "manifest config list [--layer ...] [--json]"; return 1 ;;
        esac
    done

    if [[ -n "$filter_layer" ]]; then
        local filter_out entry file
        if ! filter_out="$(_cfg_filter_layer_files "$filter_layer")"; then
            log_error "Unknown layer: $filter_layer (readable: global, fleet, project, local; writable: global, project, local)"
            return 1
        fi
        # A layer can map to more than one file (fleet contributes its local and
        # shared config); earlier entries are higher precedence.
        local cand=() files=()
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            file="${entry#*$'\t'}"
            cand+=( "$file" )
            [[ -f "$file" ]] && files+=( "$file" )
        done <<< "$filter_out"

        if [[ ${#files[@]} -eq 0 ]]; then
            if [[ "$emit_json" == "true" ]]; then
                echo "[]"
            elif [[ ${#cand[@]} -eq 0 ]]; then
                echo "($filter_layer layer does not apply here; this repository is not inside a fleet)"
            else
                echo "($filter_layer layer not present at ${cand[0]})"
            fi
            return 0
        fi
        if [[ "$emit_json" == "true" ]]; then
            _config_list_json_layer "$filter_layer" "${files[@]}"
        else
            echo "Keys in $filter_layer (${files[*]}):"
            local path
            for path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
                local val=""
                for file in "${files[@]}"; do
                    val="$(yq e "(.${path} // \"\")" "$file" 2>/dev/null)"
                    [[ -n "$val" && "$val" != "null" ]] && break
                    val=""
                done
                if [[ -n "$val" ]]; then
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
        # Keys that resolve only to a built-in default are omitted, as before --
        # listing all of them would bury the ones an operator actually set.
        if _cfg_resolve "$path" && [[ "$_CFG_R_LAYER" != "defaults" ]]; then
            printf "  %-40s %-8s %s\n" "$path" "$_CFG_R_LAYER" "$_CFG_R_VALUE"
        fi
    done | sort
}

# Emit `[{"key":..., "layer":..., "file":..., "value":...}, ...]` of effective
# values. Sorted by key for stable diffing. "file" is "" for the virtual layers
# (env, defaults); without it a consumer cannot tell WHICH fleet file won.
_config_list_json_effective() {
    local out=""
    local path
    while IFS= read -r path; do
        if _cfg_resolve "$path" && [[ "$_CFG_R_LAYER" != "defaults" ]]; then
            local entry
            entry="{$(_json_kv_str "key" "$path"),$(_json_kv_str "layer" "$_CFG_R_LAYER"),$(_json_kv_str "file" "$_CFG_R_FILE"),$(_json_kv_raw "value" "$(_json_value "$_CFG_R_VALUE")")}"
            if [[ -z "$out" ]]; then
                out="$entry"
            else
                out="${out},${entry}"
            fi
        fi
    done < <(printf '%s\n' "${!_MANIFEST_YAML_TO_ENV[@]}" | sort)
    printf '[%s]\n' "$out"
}

# Emit `[{"key":..., "layer":..., "file":..., "value":...}, ...]` for keys
# explicitly set in the given files. $1 layer id, $2.. files in descending
# precedence (a layer may map to more than one file).
_config_list_json_layer() {
    local layer="$1"; shift
    local files=( "$@" )
    local out=""
    local path
    while IFS= read -r path; do
        local val="" src="" file
        for file in "${files[@]}"; do
            val="$(yq e "(.${path} // \"\")" "$file" 2>/dev/null)"
            if [[ -n "$val" && "$val" != "null" ]]; then
                src="$file"
                break
            fi
            val=""
        done
        if [[ -n "$val" ]]; then
            local entry
            entry="{$(_json_kv_str "key" "$path"),$(_json_kv_str "layer" "$layer"),$(_json_kv_str "file" "$src"),$(_json_kv_raw "value" "$(_json_value "$val")")}"
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
    # Report what the CLI will ACTUALLY use, layer for layer. An exported
    # MANIFEST_CLI_* captured at process start outranks every file, so the file
    # layers cannot be preferred here without misreporting that case.
    if _cfg_resolve "$path"; then
        echo "$_CFG_R_VALUE"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# manifest config set [--layer <layer>] <key> <value>
# -----------------------------------------------------------------------------
manifest_config_set() {
    local layer="local"
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ "${1:-}" == --* || "${1:-}" == -* ]]; do
        case "$1" in
            --layer) layer="$2"; shift 2 ;;
            -h|--help)
                _render_help \
                    "manifest config set [-y|--yes] [--dry-run] [--layer global|project|local] <key> <value>" \
                    "Set a config key in a specific layer.
Default layer is 'local' (git-ignored). Writing 'global' prompts for
confirmation via the global-config safety gate.
Writable layers are global, project and local. The 'fleet' layer is read-only
here — set fleet-wide values by running this command at the fleet root." \
                    "Examples" "  manifest config set git.default_branch main
  manifest config set --layer project version.format semver
  manifest config set --layer global brew.tap_repo fidenceio/homebrew.tap"
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
        _cfg_reject_write_layer "$layer" set
        return 1
    fi

    if [[ "$execution_mode" == "preview" ]]; then
        manifest_execution_preview_header "manifest config set"
        echo "Would set ${layer}:${path} = ${value}"
        echo "Would write: ${file}"
        manifest_execution_footer "manifest config set --layer $layer $key $value -y"
        return 0
    fi

    manifest_execution_apply_header
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
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ "${1:-}" == --* || "${1:-}" == -* ]]; do
        case "$1" in
            --layer) layer="$2"; shift 2 ;;
            -h|--help)
                _render_help \
                    "manifest config unset [-y|--yes] [--dry-run] [--layer global|project|local] <key>" \
                    "Remove a config key from a specific layer.
Writable layers are global, project and local. The 'fleet' layer is read-only
here — remove fleet-wide values by running this command at the fleet root." \
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
    [[ -z "$file" ]] && { _cfg_reject_write_layer "$layer" unset; return 1; }

    if [[ ! -f "$file" ]]; then
        echo "($layer file does not exist; nothing to unset)"
        return 0
    fi

    if [[ "$execution_mode" == "preview" ]]; then
        manifest_execution_preview_header "manifest config unset"
        echo "Would unset ${layer}:${path}"
        echo "Would write: ${file}"
        manifest_execution_footer "manifest config unset --layer $layer $key -y"
        return 0
    fi

    manifest_execution_apply_header
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
  manifest config describe brew.tap_repo"
        return 1
    fi
    local path env_var
    path="$(_cfg_normalize_key "$1")"
    if [[ -z "$path" ]]; then
        log_error "Unknown key: $1"
        return 1
    fi
    env_var="$(yaml_path_to_env_var "$path")"

    # Compute the effective value exactly as 'get' does, i.e. as the runtime
    # resolves it. (The 'config' command pre-dispatch loads with project
    # overrides off, so reading the env directly would miss local-layer values.)
    local effective="(unset)"
    if _cfg_resolve "$path"; then
        effective="${_CFG_R_VALUE}  (from ${_CFG_R_LAYER})"
    fi
    local win_layer="$_CFG_R_LAYER" win_value="$_CFG_R_VALUE"

    local fleet_root
    fleet_root="$(_cfg_fleet_root)"

    echo "Key:       $path"
    echo "Env var:   $env_var"
    [[ -n "$fleet_root" ]] && echo "Fleet:     $fleet_root"
    echo "Effective: $effective"
    echo ""
    echo "Layers (highest precedence first):"

    # env: the process-start snapshot, not the live variable. An entry that was
    # exported EMPTY is shown explicitly -- it silently suppresses every file
    # layer, which is otherwise baffling to diagnose.
    if [[ -n "$env_var" ]] && _cfg_env_override_map_ready \
       && [[ -n "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[$env_var]+x}" ]]; then
        local ev="${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[$env_var]}"
        if [[ -n "$ev" ]]; then
            printf "  %-8s %s   (%s — exported at process start)\n" "env" "$ev" "$env_var"
        else
            printf "  %-8s %s   (%s — exported empty; suppresses all file layers)\n" "env" "(empty)" "$env_var"
        fi
    else
        printf "  %-8s %s   (%s — not exported at process start)\n" "env" "·" "$env_var"
    fi

    local entry layer file val
    _cfg_build_read_layers
    for entry in "${_CFG_READ_LAYERS[@]}"; do
        layer="${entry%%$'\t'*}"
        file="${entry#*$'\t'}"
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

    if [[ "$win_layer" == "defaults" ]]; then
        printf "  %-8s %s   (built-in)\n" "defaults" "$win_value"
    else
        printf "  %-8s %s   (built-in)\n" "defaults" "·"
    fi
}

export -f manifest_config_list
export -f manifest_config_get
export -f manifest_config_set
export -f manifest_config_unset
export -f manifest_config_describe
export -f _config_list_json_effective
export -f _config_list_json_layer
