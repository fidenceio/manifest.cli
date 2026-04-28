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
        yq_ver="$(yq --version 2>&1 | head -n1)"
        if echo "$yq_ver" | grep -q "mikefarah\|version v4"; then
            _doctor_ok "yq" "$yq_ver"
        else
            _doctor_fail "yq" "wrong fork — need Mike Farah's Go yq v4+ ($yq_ver)"
        fi
    else
        _doctor_fail "yq" "missing — brew install yq"
    fi

    if command -v git >/dev/null 2>&1; then
        _doctor_ok "git" "$(git --version 2>&1)"
    else
        _doctor_fail "git" "missing"
    fi

    if [[ "${BASH_VERSINFO[0]:-0}" -ge 4 ]]; then
        _doctor_ok "Bash" "${BASH_VERSION}"
    else
        _doctor_fail "Bash" "need 4+, got ${BASH_VERSION}"
    fi

    if command -v gh >/dev/null 2>&1; then
        _doctor_ok "gh (optional)" "$(gh --version 2>&1 | head -n1)"
    else
        _doctor_warn "gh (optional)" "not installed — required for 'manifest pr'"
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
            _doctor_ok "Canonical repo" "yes — Homebrew formula updates apply here"
        else
            _doctor_ok "Canonical repo" "no (normal for user projects)"
        fi

        if [[ -f "$proj/VERSION" ]]; then
            _doctor_ok "VERSION file" "$(cat "$proj/VERSION" | tr -d '[:space:]')"
        else
            _doctor_warn "VERSION file" "missing — run 'manifest init repo'"
        fi
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
