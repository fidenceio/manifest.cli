#!/bin/bash

# =============================================================================
# MANIFEST VERSION SURFACES MODULE
# =============================================================================
#
# Passive detection of version-bearing files. VERSION (or files.version) remains
# canonical; these helpers only discover and describe non-canonical surfaces for
# later status/doctor/fleet reporting unless an explicit writer opts in.
# =============================================================================

if [[ -n "${_MANIFEST_CLI_VERSION_SURFACES_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_VERSION_SURFACES_LOADED=1

readonly MANIFEST_CLI_VERSION_SURFACES_MODULE_VERSION="1.0.0"
readonly MANIFEST_CLI_VERSION_SURFACES_MODULE_NAME="manifest-version-surfaces"
readonly MANIFEST_CLI_VERSION_SURFACES_DEFAULT_DEPTH=5

_manifest_version_surfaces_module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_manifest_version_surfaces_modules_dir="$(dirname "$_manifest_version_surfaces_module_dir")"

if ! declare -F manifest_discovery_find_files >/dev/null 2>&1 || \
   ! declare -F _manifest_discovery_walk_recursive >/dev/null 2>&1 || \
   [[ -z "${MANIFEST_CLI_DISCOVERY_MAX_DEPTH_CAP+x}" ]]; then
    # shellcheck disable=SC1091
    source "$_manifest_version_surfaces_module_dir/manifest-discovery.sh"
fi

manifest_version_catalog_file() {
    local configured="${MANIFEST_CLI_VERSION_HANDLER_CATALOG:-}"
    if [[ -n "$configured" ]]; then
        echo "$configured"
    else
        echo "$_manifest_version_surfaces_modules_dir/catalog/version-handlers.tsv"
    fi
}

manifest_version_catalog_entries() {
    local catalog_file
    catalog_file="$(manifest_version_catalog_file)"
    if [[ -f "$catalog_file" ]]; then
        awk -F '\t' 'NF >= 4 && $1 !~ /^#/ { print }' "$catalog_file"
        return 0
    fi

    cat <<'TSV'
manifest-version-file	VERSION	canonical	text
npm-package	package.json	package-manifest	json
npm-lock	package-lock.json	lockfile	json
npm-shrinkwrap	npm-shrinkwrap.json	lockfile	json
pnpm-lock	pnpm-lock.yaml	lockfile	yaml
yarn-lock	yarn.lock	lockfile	text
pyproject	pyproject.toml	package-manifest	toml
poetry-lock	poetry.lock	lockfile	toml
cargo-manifest	Cargo.toml	package-manifest	toml
cargo-lock	Cargo.lock	lockfile	toml
go-module	go.mod	package-manifest	text
helm-chart	Chart.yaml	package-manifest	yaml
TSV
}

_manifest_version_catalog_file_names() {
    local id file role kind
    declare -A seen=()
    while IFS=$'\t' read -r id file role kind; do
        [[ -n "$file" ]] || continue
        if [[ -z "${seen[$file]+_}" ]]; then
            seen["$file"]=1
            echo "$file"
        fi
    done < <(manifest_version_catalog_entries)
}

_manifest_version_catalog_lookup() {
    local lookup_file="$1"
    local id file role kind
    while IFS=$'\t' read -r id file role kind; do
        if [[ "$file" == "$lookup_file" ]]; then
            printf "%s\t%s\t%s\n" "$id" "$role" "$kind"
            return 0
        fi
    done < <(manifest_version_catalog_entries)
    return 1
}

_manifest_version_surface_json_value() {
    local file="$1"
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
                        rest = substr(line, q + 1)
                        if (rest ~ /^[[:space:]]*:[[:space:]]*"/) {
                            sub(/^[[:space:]]*:[[:space:]]*"/, "", rest)
                            sub(/".*$/, "", rest)
                            print rest
                            exit
                        }
                    }
                    p = q + 1
                    continue
                }
                if (c == "{" || c == "[") { depth++; p++; continue }
                if (c == "}" || c == "]") { depth--; p++; continue }
                p++
            }
        }
    ' "$file" 2>/dev/null
}

_manifest_version_surface_read_value() {
    local abs_file="$1"
    local kind="$2"
    local rel_file="$3"

    case "$kind:$rel_file" in
        text:VERSION|text:*/VERSION|text:*)
            if [[ "$(basename "$rel_file")" == "VERSION" || "$rel_file" == "${MANIFEST_CLI_VERSION_FILE:-VERSION}" ]]; then
                tr -d '[:space:]' < "$abs_file" 2>/dev/null || true
                return 0
            fi
            ;;
    esac

    case "$kind" in
        json)
            _manifest_version_surface_json_value "$abs_file"
            ;;
        toml)
            sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$abs_file" 2>/dev/null | head -1
            ;;
        yaml)
            sed -n 's/^[[:space:]]*version[[:space:]]*:[[:space:]]*["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}[[:space:]]*$/\1/p' "$abs_file" 2>/dev/null | head -1
            ;;
        *)
            echo ""
            ;;
    esac
}

manifest_version_surface_scan() {
    local root_dir="${1:-$(pwd)}"
    local max_depth="${2:-${MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH:-$MANIFEST_CLI_VERSION_SURFACES_DEFAULT_DEPTH}}"
    local canonical_file="${MANIFEST_CLI_VERSION_FILE:-VERSION}"
    canonical_file="${canonical_file#./}"

    local file_names=()
    local name
    while IFS= read -r name; do
        [[ -n "$name" ]] && file_names+=("$name")
    done < <(_manifest_version_catalog_file_names)

    local canonical_basename
    canonical_basename="$(basename "$canonical_file")"
    local found_canonical_name=false
    for name in "${file_names[@]}"; do
        if [[ "$name" == "$canonical_basename" ]]; then
            found_canonical_name=true
            break
        fi
    done
    [[ "$found_canonical_name" == "true" ]] || file_names+=("$canonical_basename")

    local rel_file abs_file depth rel_dir basename id role kind relationship version_value lookup
    while IFS=$'\t' read -r rel_file abs_file depth rel_dir basename; do
        [[ -n "$rel_file" ]] || continue
        lookup="$(_manifest_version_catalog_lookup "$basename" || true)"
        if [[ -n "$lookup" ]]; then
            IFS=$'\t' read -r id role kind <<< "$lookup"
        else
            id="custom-version-file"
            role="canonical"
            kind="text"
        fi

        relationship="noncanonical"
        if [[ "$rel_file" == "$canonical_file" ]]; then
            relationship="canonical"
            role="canonical"
        fi

        version_value="$(_manifest_version_surface_read_value "$abs_file" "$kind" "$rel_file")"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$id" "$role" "$kind" "$relationship" "$rel_file" "$version_value"
    done < <(manifest_discovery_find_files "$root_dir" "$max_depth" 0 version "${file_names[@]}")
}

export -f _manifest_version_catalog_file_names
export -f _manifest_version_catalog_lookup
export -f _manifest_version_surface_json_value
export -f _manifest_version_surface_read_value
export -f manifest_version_catalog_file
export -f manifest_version_catalog_entries
export -f manifest_version_surface_scan
