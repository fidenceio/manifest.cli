#!/bin/bash

# =============================================================================
# Manifest Doctor Module (Tier 4 #21)
# =============================================================================
#
# Implements: manifest doctor
#
# PURPOSE:
#   One command that answers "is my Manifest environment healthy?".
#   Composes: dependency checks (yq, git, bash), config doctor, repo status,
#   canonical-repo gate. Read-only — never modifies anything.
#
# EXIT CODE:
#   0 if no errors (warnings allowed)
#   1 if any check returns an error
# =============================================================================

if [[ -n "${_MANIFEST_DOCTOR_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_DOCTOR_LOADED=1

_doctor_ok()    { printf "  \033[32m✓\033[0m %-22s %s\n" "$1" "$2"; }
_doctor_warn()  { printf "  \033[33m⚠\033[0m %-22s %s\n" "$1" "$2"; _doctor_warns=$((_doctor_warns + 1)); }
_doctor_fail()  { printf "  \033[31m✗\033[0m %-22s %s\n" "$1" "$2"; _doctor_errs=$((_doctor_errs + 1)); }
_doctor_section() { echo ""; echo "$1"; }

_doctor_version_surface_report() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    declare -F manifest_version_surface_scan >/dev/null 2>&1 || return 0

    local policy_warning
    if declare -F manifest_version_surface_policy_warnings >/dev/null 2>&1; then
        while IFS= read -r policy_warning; do
            [[ -n "$policy_warning" ]] && _doctor_warn "Version surfaces" "$policy_warning"
        done < <(manifest_version_surface_policy_warnings)
    fi

    if ! manifest_version_surfaces_enabled; then
        _doctor_ok "Version surfaces" "disabled by policy"
        return 0
    fi

    local canonical_count=0 noncanonical_count=0
    local first_noncanonical=""
    local id role kind relationship rel_file version_value
    while IFS=$'\t' read -r id role kind relationship rel_file version_value; do
        [[ -n "$rel_file" ]] || continue
        if [[ "$relationship" == "canonical" ]]; then
            canonical_count=$((canonical_count + 1))
        else
            noncanonical_count=$((noncanonical_count + 1))
            [[ -z "$first_noncanonical" ]] && first_noncanonical="$rel_file"
        fi
    done < <(manifest_version_surface_scan "$root" 2>/dev/null || true)

    if [[ "$noncanonical_count" -gt 0 ]]; then
        _doctor_warn "Version surfaces" "${noncanonical_count} noncanonical detected; read-only unless listed in version.sync (first: ${first_noncanonical})"
    elif [[ "$canonical_count" -gt 0 ]]; then
        _doctor_ok "Version surfaces" "canonical only"
    else
        _doctor_ok "Version surfaces" "none detected"
    fi
}

manifest_doctor() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: manifest doctor"
        echo ""
        echo "Comprehensive read-only health check of your Manifest environment."
        return 0
    fi

    local _doctor_errs=0
    local _doctor_warns=0
    local proj="${PROJECT_ROOT:-$(pwd)}"

    echo ""
    echo "Manifest doctor"
    echo "==============="

    # -- Dependencies -------------------------------------------------------
    _doctor_section "Dependencies:"
    if command -v yq >/dev/null 2>&1; then
        local yq_ver
        yq_ver="$(manifest_requirement_yq_version_text yq)"
        if manifest_requirement_yq_text_is_supported "$yq_ver"; then
            _doctor_ok "yq" "$yq_ver"
        else
            _doctor_fail "yq" "need ${MANIFEST_CLI_REQUIRED_YQ_LABEL} ($yq_ver)"
        fi
    else
        _doctor_fail "yq" "missing — brew install yq"
    fi

    if command -v git >/dev/null 2>&1; then
        _doctor_ok "git" "$(git --version 2>&1)"
    else
        _doctor_fail "git" "missing"
    fi

    if manifest_requirement_coreutils_timeout_command; then
        _doctor_ok "coreutils" "${MANIFEST_CLI_REQUIRED_COREUTILS_LABEL}"
    else
        _doctor_fail "coreutils" "missing ${MANIFEST_CLI_REQUIRED_COREUTILS_LABEL}"
    fi

    if manifest_requirement_current_bash_is_supported; then
        _doctor_ok "Bash" "${BASH_VERSION}"
    else
        _doctor_fail "Bash" "need ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+, got ${BASH_VERSION}"
    fi

    if command -v gh >/dev/null 2>&1; then
        _doctor_ok "gh (optional)" "$(gh --version 2>&1 | head -n1)"
    else
        _doctor_warn "gh (optional)" "not installed — required for 'manifest pr'"
    fi

    # GNU sed: macOS source/development compatibility warning. Homebrew installs
    # include it; Linux ships GNU sed. Reports the runtime-resolved sed (after the
    # gnubin prepend), so it stays quiet when gnu-sed is installed but its gnubin
    # isn't on the login PATH.
    if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
        if manifest_requirement_runtime_sed_is_gnu; then
            _doctor_ok "GNU sed (optional)" "available"
        else
            _doctor_warn "GNU sed (optional)" "missing — brew install gnu-sed (recommended for macOS source/development installs)"
        fi
    fi

    # -- Configuration ------------------------------------------------------
    _doctor_section "Configuration:"
    local global="${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}"
    if [[ -f "$global" ]]; then
        _doctor_ok "Global config" "$global"
        local schema
        schema="$(get_yaml_value "$global" ".config.schema_version" "0" 2>/dev/null)"
        if [[ "$schema" = "${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT:-2}" ]]; then
            _doctor_ok "Schema version" "$schema (current)"
        else
            _doctor_warn "Schema version" "$schema — run 'manifest config doctor --dry-run'"
        fi
    else
        _doctor_warn "Global config" "missing — run 'manifest config setup'"
    fi

    # Detect drift via the existing detector (already returns one line per issue).
    if type _manifest_config_detect_issues >/dev/null 2>&1 && [[ -f "$global" ]]; then
        local drift_count=0
        while IFS= read -r line; do
            [[ -n "$line" ]] && drift_count=$((drift_count + 1))
        done < <(_manifest_config_detect_issues "$global")
        if [[ "$drift_count" -gt 0 ]]; then
            _doctor_warn "Config drift" "$drift_count issue(s) — run 'manifest config doctor --fix'"
        else
            _doctor_ok "Config drift" "none"
        fi
    fi

    # -- Repository ---------------------------------------------------------
    _doctor_section "Repository:"
    if git -C "$proj" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _doctor_ok "Git repository" "$proj"
        local origin
        origin="$(git -C "$proj" remote get-url origin 2>/dev/null || echo "")"
        if [[ -n "$origin" ]]; then
            _doctor_ok "Origin remote" "$origin"
        else
            _doctor_warn "Origin remote" "not set — run 'manifest prep repo' to add"
        fi

        if manifest_is_canonical_repo "$proj" 2>/dev/null; then
            _doctor_ok "Canonical repo" "yes — Homebrew tap formula publishes from here"
        else
            _doctor_ok "Canonical repo" "no (normal for user projects)"
        fi

        if [[ -f "$proj/VERSION" ]]; then
            _doctor_ok "VERSION file" "$(cat "$proj/VERSION" | tr -d '[:space:]')"
        else
            _doctor_warn "VERSION file" "missing — run 'manifest init repo'"
        fi
        _doctor_version_surface_report "$proj"
    else
        _doctor_warn "Git repository" "not in a git repo (skipping repo checks)"
    fi

    # -- Summary ------------------------------------------------------------
    echo ""
    if [[ "$_doctor_errs" -eq 0 && "$_doctor_warns" -eq 0 ]]; then
        printf "  \033[32mAll good.\033[0m\n"
    else
        printf "  Result: %d error(s), %d warning(s)\n" "$_doctor_errs" "$_doctor_warns"
    fi
    echo ""
    [[ "$_doctor_errs" -eq 0 ]]
}

export -f manifest_doctor
