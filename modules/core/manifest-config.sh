#!/bin/bash

# Manifest Configuration Module
# Handles environment variable loading, validation, and defaults

# Configuration file paths (in order of precedence)
MANIFEST_CLI_CONFIG_FILES=(
    "manifest.config.yaml"
    "manifest.config.local.yaml"
)
MANIFEST_CLI_GLOBAL_CONFIG="$HOME/.manifest-cli/manifest.config.global.yaml"

MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT=2

_manifest_config_warn() {
    local message="$1"
    if command -v log_warning >/dev/null 2>&1; then
        log_warning "$message"
    else
        echo "⚠️  $message"
    fi
}

# -----------------------------------------------------------------------------
# Global Config Safety Gate
# -----------------------------------------------------------------------------
# The user's global config (~/.manifest-cli/manifest.config.global.yaml)
# persists across upgrades and contains user customizations. Every code path
# that modifies or deletes it MUST pass through this gate.
#
# ARGUMENTS:
#   $1 - action: "modify" | "delete" | "overwrite"
#   $2 - target: file path
#   $3 - reason: human description shown to the user
#
# RETURNS: 0 if approved, non-zero if denied
#
# ENV:
#   MANIFEST_CLI_AUTO_CONFIRM=1            bypass prompt (CI / scripted)
#   _MANIFEST_GLOBAL_CONFIG_AUTHORIZED=1   session-cached approval (modify only)
# -----------------------------------------------------------------------------
_confirm_global_config_write() {
    local action="$1"
    local target="$2"
    local reason="$3"

    if [ "${MANIFEST_CLI_AUTO_CONFIRM:-0}" = "1" ]; then
        _manifest_config_warn "Auto-confirming $action of $target ($reason) [MANIFEST_CLI_AUTO_CONFIRM=1]"
        export _MANIFEST_GLOBAL_CONFIG_AUTHORIZED=1
        return 0
    fi

    if [ "$action" = "modify" ] && [ "${_MANIFEST_GLOBAL_CONFIG_AUTHORIZED:-0}" = "1" ]; then
        return 0
    fi

    if [ ! -t 0 ]; then
        log_error "Refusing to $action global config without confirmation."
        log_error "  File:   $target"
        log_error "  Reason: $reason"
        log_error "  Set MANIFEST_CLI_AUTO_CONFIRM=1 to authorize, or run interactively."
        return 1
    fi

    echo ""
    echo "⚠️  Global configuration $action requested"
    echo "    File:   $target"
    echo "    Reason: $reason"
    echo ""

    case "$action" in
        delete|overwrite)
            local ans1 ans2
            printf "    This is destructive. Type 'yes' to confirm (1/2): "
            read -r ans1 || return 1
            [ "$ans1" = "yes" ] || { echo "    Cancelled."; return 1; }
            printf "    Type 'yes' again to confirm (2/2): "
            read -r ans2 || return 1
            [ "$ans2" = "yes" ] || { echo "    Cancelled."; return 1; }
            ;;
        *)
            local ans
            printf "    Continue? (yes/no): "
            read -r ans || return 1
            [ "$ans" = "yes" ] || { echo "    Cancelled."; return 1; }
            ;;
    esac

    export _MANIFEST_GLOBAL_CONFIG_AUTHORIZED=1
    return 0
}

_manifest_config_warning_state_file() {
    local state_dir="$HOME/.manifest-cli"
    if ! mkdir -p "$state_dir" 2>/dev/null; then
        echo ""
        return 0
    fi
    echo "$state_dir/config-warning.last"
}

_manifest_config_migration_state_file() {
    local state_dir="$HOME/.manifest-cli"
    if ! mkdir -p "$state_dir" 2>/dev/null; then
        echo ""
        return 0
    fi
    echo "$state_dir/config-migration.last"
}

_manifest_config_should_emit_warnings() {
    local cooldown_minutes="${MANIFEST_CLI_CONFIG_WARNING_COOLDOWN_MINUTES:-1440}"
    if ! [[ "$cooldown_minutes" =~ ^[0-9]+$ ]] || [ "$cooldown_minutes" -lt 0 ]; then
        cooldown_minutes=1440
    fi

    [ "$cooldown_minutes" -eq 0 ] && return 0

    local state_file
    state_file=$(_manifest_config_warning_state_file)
    [ -n "$state_file" ] || return 0
    local now
    now=$(date +%s)
    local last=0

    if [ -f "$state_file" ]; then
        last=$(tr -d '[:space:]' < "$state_file" 2>/dev/null || echo "0")
        if ! [[ "$last" =~ ^[0-9]+$ ]]; then
            last=0
        fi
    fi

    if [ $((now - last)) -lt $((cooldown_minutes * 60)) ]; then
        return 1
    fi

    printf '%s\n' "$now" > "$state_file" 2>/dev/null || true
    return 0
}

_manifest_config_should_run_auto_migration() {
    local cooldown_minutes="${MANIFEST_CLI_CONFIG_MIGRATION_COOLDOWN_MINUTES:-1440}"
    if ! [[ "$cooldown_minutes" =~ ^[0-9]+$ ]] || [ "$cooldown_minutes" -lt 0 ]; then
        cooldown_minutes=1440
    fi

    [ "$cooldown_minutes" -eq 0 ] && return 0

    local state_file
    state_file=$(_manifest_config_migration_state_file)
    [ -n "$state_file" ] || return 0
    local now
    now=$(date +%s)
    local last=0

    if [ -f "$state_file" ]; then
        last=$(tr -d '[:space:]' < "$state_file" 2>/dev/null || echo "0")
        if ! [[ "$last" =~ ^[0-9]+$ ]]; then
            last=0
        fi
    fi

    if [ $((now - last)) -lt $((cooldown_minutes * 60)) ]; then
        return 1
    fi

    printf '%s\n' "$now" > "$state_file" 2>/dev/null || true
    return 0
}

warn_deprecated_configuration() {
    if ! _manifest_config_should_emit_warnings; then
        return 0
    fi

    local warned=0

    if [ "${MANIFEST_CLI_TIME_SERVER1:-}" = "time.apple.com" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER2:-}" = "time.google.com" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER3:-}" = "pool.ntp.org" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER4:-}" = "time.nist.gov" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER1:-}" = "216.239.35.0" ] || \
       [ "${MANIFEST_CLI_TIME_SERVER2:-}" = "216.239.35.4" ]; then
        _manifest_config_warn "Legacy time server defaults detected in time.server1..4. Recommended defaults are https://www.cloudflare.com/cdn-cgi/trace / https://www.google.com/generate_204 with https://www.apple.com for server3."
        warned=1
    fi

    if [ "${MANIFEST_CLI_TAP_REPO:-}" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        _manifest_config_warn "Legacy brew.tap_repo detected. Recommended value: https://github.com/fidenceio/homebrew-tap.git"
        warned=1
    fi

    if [ "$warned" -eq 1 ]; then
        _manifest_config_warn "Run 'manifest upgrade --force' (or reinstall) to apply safe config migrations automatically."
    fi
}

_manifest_config_detect_issues() {
    local config_file="$1"
    [ -f "$config_file" ] || return 1

    local ts1 ts2 ts3 ts4 tap_repo
    ts1=$(get_yaml_value "$config_file" ".time.server1" "")
    ts2=$(get_yaml_value "$config_file" ".time.server2" "")
    ts3=$(get_yaml_value "$config_file" ".time.server3" "")
    ts4=$(get_yaml_value "$config_file" ".time.server4" "")
    tap_repo=$(get_yaml_value "$config_file" ".brew.tap_repo" "")

    if [ "$ts1" = "time.apple.com" ] || [ "$ts1" = "216.239.35.0" ]; then
        echo "legacy|time.server1|$ts1|https://www.cloudflare.com/cdn-cgi/trace"
    fi
    if [ "$ts2" = "time.google.com" ] || [ "$ts2" = "216.239.35.4" ]; then
        echo "legacy|time.server2|$ts2|https://www.google.com/generate_204"
    fi
    if [ "$ts3" = "pool.ntp.org" ]; then
        echo "legacy|time.server3|pool.ntp.org|https://www.apple.com"
    fi
    if [ "$ts4" = "time.nist.gov" ]; then
        echo "legacy|time.server4|time.nist.gov|"
    fi
    if [ "$tap_repo" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        echo "legacy|brew.tap_repo|https://github.com/fidenceio/fidenceio-homebrew-tap.git|https://github.com/fidenceio/homebrew-tap.git"
    fi

    local cache_ttl cache_cleanup cache_stale schema_ver
    cache_ttl=$(get_yaml_value "$config_file" ".time.cache_ttl" "")
    cache_cleanup=$(get_yaml_value "$config_file" ".time.cache_cleanup_period" "")
    cache_stale=$(get_yaml_value "$config_file" ".time.cache_stale_max_age" "")
    schema_ver=$(get_yaml_value "$config_file" ".config.schema_version" "")

    if [ -z "$cache_ttl" ]; then
        echo "missing|time.cache_ttl||120"
    fi
    if [ -z "$cache_cleanup" ]; then
        echo "missing|time.cache_cleanup_period||3600"
    fi
    if [ -z "$cache_stale" ]; then
        echo "missing|time.cache_stale_max_age||21600"
    fi
    if [ -z "$schema_ver" ]; then
        echo "missing|config.schema_version||${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT}"
    fi
}

_manifest_config_upsert_key() {
    local file="$1"
    local key="$2"
    local value="$3"
    [ -f "$file" ] || return 1

    # key is now a YAML dot-path (e.g. "time.server1")
    set_yaml_value "$file" "$key" "$value"
}

_manifest_config_lock_acquire() {
    local target_file="$1"
    local lock_dir="${target_file}.lock.d"
    local attempts=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 50 ]; then
            return 1
        fi
        sleep 0.1
    done
    echo "$lock_dir"
}

_manifest_config_lock_release() {
    local lock_dir="$1"
    [ -n "$lock_dir" ] && [ -d "$lock_dir" ] && rmdir "$lock_dir" 2>/dev/null || true
}

_manifest_config_apply_migrations() {
    local config_file="$1"
    local dry_run="$2"
    local applied=0

    while IFS='|' read -r issue_type key from to; do
        [ -n "$issue_type" ] || continue
        case "$issue_type" in
            "legacy")
                if [ "$dry_run" = "true" ]; then
                    echo "would-update|$key|$from|$to"
                else
                    _manifest_config_upsert_key "$config_file" "$key" "$to" && applied=$((applied + 1))
                    echo "updated|$key|$from|$to"
                fi
                ;;
            "missing")
                if [ "$dry_run" = "true" ]; then
                    echo "would-add|$key||$to"
                else
                    _manifest_config_upsert_key "$config_file" "$key" "$to" && applied=$((applied + 1))
                    echo "added|$key||$to"
                fi
                ;;
        esac
    done < <(_manifest_config_detect_issues "$config_file")

    if [ "$dry_run" = "false" ] && [ "$applied" -gt 0 ]; then
        _manifest_config_upsert_key "$config_file" "config.schema_version" "${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT}" >/dev/null 2>&1 || true
    fi
}

auto_migrate_user_global_configuration() {
    local config_file="$MANIFEST_CLI_GLOBAL_CONFIG"
    [ -f "$config_file" ] || return 0
    if ! _manifest_config_should_run_auto_migration; then
        return 0
    fi

    local actionable=0
    while IFS='|' read -r issue_type _key _from _to; do
        case "$issue_type" in
            "legacy"|"missing")
                actionable=1
                break
                ;;
        esac
    done < <(_manifest_config_detect_issues "$config_file")

    [ "$actionable" -eq 1 ] || return 0

    # Auto-migration silently rewrites the global config on every CLI run.
    # That violates the "no silent modifications" rule. Default behavior is
    # now WARN-ONLY; users opt in to silent migration with MANIFEST_CLI_AUTO_CONFIRM=1
    # or run `manifest config doctor --fix` explicitly.
    if [ "${MANIFEST_CLI_AUTO_CONFIRM:-0}" != "1" ]; then
        _manifest_config_warn "Configuration drift detected in $config_file."
        _manifest_config_warn "Run 'manifest config doctor --dry-run' to review, then '--fix' to apply."
        return 0
    fi

    if ! _confirm_global_config_write "modify" "$config_file" "auto-migration of legacy/missing keys"; then
        return 0
    fi

    local lock_dir=""
    lock_dir=$(_manifest_config_lock_acquire "$config_file") || return 0
    local migration_output=""
    migration_output=$(_manifest_config_apply_migrations "$config_file" "false")
    _manifest_config_lock_release "$lock_dir"

    if [ -n "$migration_output" ]; then
        _manifest_config_warn "Applied safe configuration migrations to $config_file."
        _manifest_config_warn "Run 'manifest config doctor --dry-run' to review current drift status."
    fi
}

config_doctor() {
    local fix="false"
    local dry_run="false"
    local config_file="$MANIFEST_CLI_GLOBAL_CONFIG"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            "--fix")
                fix="true"
                shift
                ;;
            "--dry-run")
                dry_run="true"
                shift
                ;;
            "--file")
                config_file="${2:-}"
                shift 2
                ;;
            *)
                echo "Unknown option for config doctor: $1"
                echo "Usage: manifest config doctor [--fix] [--dry-run] [--file <path>]"
                return 1
                ;;
        esac
    done

    if [ ! -f "$config_file" ]; then
        echo "⚠️  Config file not found: $config_file"
        echo "   Run 'manifest config setup' to create one, or copy the example:"
        echo "   mkdir -p ~/.manifest-cli && cp examples/manifest.config.yaml.example $config_file"
        return 1
    fi

    echo "🩺 Manifest Config Doctor"
    echo "========================="
    echo "   Config file: $config_file"
    echo ""

    local issues=()
    while IFS= read -r line; do
        [ -n "$line" ] && issues+=("$line")
    done < <(_manifest_config_detect_issues "$config_file")

    if [ ${#issues[@]} -eq 0 ]; then
        echo "✅ No configuration drift detected."
        return 0
    fi

    echo "Findings:"
    local issue
    for issue in "${issues[@]}"; do
        IFS='|' read -r issue_type key from to <<< "$issue"
        case "$issue_type" in
            "legacy")
                echo " - LEGACY: $key uses '$from' (recommended: '$to')"
                ;;
            "missing")
                echo " - MISSING: $key is not set (recommended default: '$to')"
                ;;
            "deprecated")
                echo " - DEPRECATED: $key is set ('$from'); use '$to'"
                ;;
        esac
    done

    if [ "$fix" = "true" ] || [ "$dry_run" = "true" ]; then
        echo ""
        echo "Migration plan:"
        if [ "$dry_run" = "true" ]; then
            _manifest_config_apply_migrations "$config_file" "$dry_run"
        else
            if [ "$config_file" = "$MANIFEST_CLI_GLOBAL_CONFIG" ] && \
               ! _confirm_global_config_write "modify" "$config_file" "applying ${#issues[@]} configuration migration(s)"; then
                echo "Migration cancelled."
                return 1
            fi
            local lock_dir=""
            lock_dir=$(_manifest_config_lock_acquire "$config_file") || {
                echo "❌ Could not acquire config lock for migration: ${config_file}.lock.d"
                return 1
            }
            _manifest_config_apply_migrations "$config_file" "$dry_run"
            _manifest_config_lock_release "$lock_dir"
        fi

        if [ "$dry_run" = "true" ]; then
            echo ""
            echo "ℹ️  Dry-run complete. Re-run with --fix to apply."
        else
            echo ""
            echo "✅ Safe migrations applied."
        fi
    else
        echo ""
        echo "ℹ️  Run 'manifest config doctor --fix' to apply safe migrations."
        echo "ℹ️  Run 'manifest config doctor --dry-run' to preview changes."
    fi
}

# Load configuration from YAML files
load_configuration() {
    local project_root="$1"
    local include_project_overrides="${2:-true}"

    if [ -z "$project_root" ]; then
        project_root="."
    fi

    # Fail fast if yq is missing (rather than later, mid-workflow).
    if ! require_yaml_parser; then
        return 1
    fi

    # Baseline defaults first (so YAML layers override them)
    set_default_configuration

    # Layer 1: User global configuration
    if [ -f "$MANIFEST_CLI_GLOBAL_CONFIG" ]; then
        echo "🔧 Loading user global configuration from: $MANIFEST_CLI_GLOBAL_CONFIG"
        load_yaml_to_env "$MANIFEST_CLI_GLOBAL_CONFIG"
    fi

    # Layer 2: Project shared configuration
    local project_shared="$project_root/manifest.config.yaml"
    if [ -f "$project_shared" ]; then
        echo "🔧 Loading project configuration from: manifest.config.yaml (Project: $project_root)"
        load_yaml_to_env "$project_shared"
    fi

    # Layer 3: Project local overrides (only when requested)
    if [ "$include_project_overrides" = "true" ]; then
        local project_local="$project_root/manifest.config.local.yaml"
        if [ -f "$project_local" ]; then
            echo "🔧 Loading project local configuration from: manifest.config.local.yaml (Project: $project_root)"
            load_yaml_to_env "$project_local"
        fi
    fi

    # Fill any remaining gaps with defaults
    set_default_configuration
    auto_migrate_user_global_configuration
    # Re-apply defaults in case auto-migration added missing values.
    set_default_configuration
    warn_deprecated_configuration
}

# Set default configuration values
set_default_configuration() {
    # Versioning Configuration
    export MANIFEST_CLI_VERSION_FORMAT="${MANIFEST_CLI_VERSION_FORMAT:-XX.XX.XX}"
    export MANIFEST_CLI_VERSION_SEPARATOR="${MANIFEST_CLI_VERSION_SEPARATOR:-.}"
    export MANIFEST_CLI_VERSION_COMPONENTS="${MANIFEST_CLI_VERSION_COMPONENTS:-major,minor,patch}"
    export MANIFEST_CLI_VERSION_MAX_VALUES="${MANIFEST_CLI_VERSION_MAX_VALUES:-0,0,0}"
    
    # Human-Intuitive Component Mapping (defaults to standard semantic versioning)
    export MANIFEST_CLI_MAJOR_COMPONENT_POSITION="${MANIFEST_CLI_MAJOR_COMPONENT_POSITION:-1}"
    export MANIFEST_CLI_MINOR_COMPONENT_POSITION="${MANIFEST_CLI_MINOR_COMPONENT_POSITION:-2}"
    export MANIFEST_CLI_PATCH_COMPONENT_POSITION="${MANIFEST_CLI_PATCH_COMPONENT_POSITION:-3}"
    export MANIFEST_CLI_REVISION_COMPONENT_POSITION="${MANIFEST_CLI_REVISION_COMPONENT_POSITION:-4}"
    
    # Increment Behavior (defaults to standard semantic versioning)
    export MANIFEST_CLI_MAJOR_INCREMENT_TARGET="${MANIFEST_CLI_MAJOR_INCREMENT_TARGET:-1}"
    export MANIFEST_CLI_MINOR_INCREMENT_TARGET="${MANIFEST_CLI_MINOR_INCREMENT_TARGET:-2}"
    export MANIFEST_CLI_PATCH_INCREMENT_TARGET="${MANIFEST_CLI_PATCH_INCREMENT_TARGET:-3}"
    export MANIFEST_CLI_REVISION_INCREMENT_TARGET="${MANIFEST_CLI_REVISION_INCREMENT_TARGET:-4}"
    
    # Reset Behavior (defaults to standard semantic versioning)
    export MANIFEST_CLI_MAJOR_RESET_COMPONENTS="${MANIFEST_CLI_MAJOR_RESET_COMPONENTS:-2,3,4}"
    export MANIFEST_CLI_MINOR_RESET_COMPONENTS="${MANIFEST_CLI_MINOR_RESET_COMPONENTS:-3,4}"
    export MANIFEST_CLI_PATCH_RESET_COMPONENTS="${MANIFEST_CLI_PATCH_RESET_COMPONENTS:-4}"
    export MANIFEST_CLI_REVISION_RESET_COMPONENTS="${MANIFEST_CLI_REVISION_RESET_COMPONENTS:-}"
    
    # Git Configuration
    export MANIFEST_CLI_GIT_TAG_PREFIX="${MANIFEST_CLI_GIT_TAG_PREFIX:-v}"
    export MANIFEST_CLI_GIT_TAG_SUFFIX="${MANIFEST_CLI_GIT_TAG_SUFFIX:-}"
    
    # Branch Naming Configuration
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    export MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX="${MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX:-feature/}"
    export MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX="${MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX:-hotfix/}"
    export MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX="${MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX:-release/}"
    export MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX="${MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX:-bugfix/}"
    export MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH="${MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH:-develop}"
    export MANIFEST_CLI_GIT_STAGING_BRANCH="${MANIFEST_CLI_GIT_STAGING_BRANCH:-staging}"
    
    # Trusted Timestamps Configuration
    export MANIFEST_CLI_TIME_SERVER1="${MANIFEST_CLI_TIME_SERVER1:-https://www.cloudflare.com/cdn-cgi/trace}"
    export MANIFEST_CLI_TIME_SERVER2="${MANIFEST_CLI_TIME_SERVER2:-https://www.google.com/generate_204}"
    export MANIFEST_CLI_TIME_SERVER3="${MANIFEST_CLI_TIME_SERVER3:-https://www.apple.com}"
    export MANIFEST_CLI_TIME_SERVER4="${MANIFEST_CLI_TIME_SERVER4:-}"
    export MANIFEST_CLI_TIME_TIMEOUT="${MANIFEST_CLI_TIME_TIMEOUT:-5}"
    export MANIFEST_CLI_TIME_RETRIES="${MANIFEST_CLI_TIME_RETRIES:-3}"
    export MANIFEST_CLI_TIME_VERIFY="${MANIFEST_CLI_TIME_VERIFY:-true}"
    export MANIFEST_CLI_TIME_CACHE_TTL="${MANIFEST_CLI_TIME_CACHE_TTL:-120}"
    export MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD="${MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD:-3600}"
    export MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE="${MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE:-21600}"

    # Timezone Configuration (defaults to UTC)
    # Can be overridden in manifest.config.local.yaml with IANA timezone names like:
    # America/New_York, America/Los_Angeles, Europe/London, Asia/Tokyo, etc.
    export MANIFEST_CLI_TIMEZONE="${MANIFEST_CLI_TIMEZONE:-UTC}"
    
    # Git Operations
    export MANIFEST_CLI_GIT_COMMIT_TEMPLATE="${MANIFEST_CLI_GIT_COMMIT_TEMPLATE:-Release v{version} - {timestamp}}"
    export MANIFEST_CLI_GIT_PUSH_STRATEGY="${MANIFEST_CLI_GIT_PUSH_STRATEGY:-simple}"
    export MANIFEST_CLI_GIT_PULL_STRATEGY="${MANIFEST_CLI_GIT_PULL_STRATEGY:-rebase}"
    export MANIFEST_CLI_GIT_TIMEOUT="${MANIFEST_CLI_GIT_TIMEOUT:-300}"
    export MANIFEST_CLI_GIT_RETRIES="${MANIFEST_CLI_GIT_RETRIES:-3}"
    
    # Homebrew Configuration
    export MANIFEST_CLI_BREW_OPTION="${MANIFEST_CLI_BREW_OPTION:-enabled}"
    export MANIFEST_CLI_BREW_INTERACTIVE="${MANIFEST_CLI_BREW_INTERACTIVE:-no}"
    export MANIFEST_CLI_TAP_REPO="${MANIFEST_CLI_TAP_REPO:-https://github.com/fidenceio/homebrew-tap.git}"
    
    # Documentation Configuration
    export MANIFEST_CLI_DOCS_FOLDER="${MANIFEST_CLI_DOCS_FOLDER:-docs}"
    export MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER:-docs/zArchive}"
    export MANIFEST_CLI_DOCS_TEMPLATE_DIR="${MANIFEST_CLI_DOCS_TEMPLATE_DIR:-}"
    export MANIFEST_CLI_DOCS_AUTO_GENERATE="${MANIFEST_CLI_DOCS_AUTO_GENERATE:-true}"
    export MANIFEST_CLI_DOCS_HISTORICAL_LIMIT="${MANIFEST_CLI_DOCS_HISTORICAL_LIMIT:-20}"
    export MANIFEST_CLI_DOCS_FILENAME_PATTERN="${MANIFEST_CLI_DOCS_FILENAME_PATTERN:-RELEASE_vVERSION.md}"
    
    # File and directory names
    export MANIFEST_CLI_README_FILE="${MANIFEST_CLI_README_FILE:-README.md}"
    export MANIFEST_CLI_VERSION_FILE="${MANIFEST_CLI_VERSION_FILE:-VERSION}"
    export MANIFEST_CLI_GITIGNORE_FILE="${MANIFEST_CLI_GITIGNORE_FILE:-.gitignore}"
    export MANIFEST_CLI_DOCUMENTATION_ARCHIVE_DIR="${MANIFEST_CLI_DOCUMENTATION_ARCHIVE_DIR:-zArchive}"
    export MANIFEST_CLI_GIT_DIR="${MANIFEST_CLI_GIT_DIR:-.git}"
    export MANIFEST_CLI_MODULES_DIR="${MANIFEST_CLI_MODULES_DIR:-modules}"
    
    # File extensions
    export MANIFEST_CLI_MARKDOWN_EXT="${MANIFEST_CLI_MARKDOWN_EXT:-*.md}"
    
    # Installation paths
    export MANIFEST_CLI_INSTALL_DIR="${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest-cli}"
    export MANIFEST_CLI_BIN_DIR="${MANIFEST_CLI_BIN_DIR:-~/.local/bin}"
    
    # Temporary file paths
    export MANIFEST_CLI_TEMP_DIR="${MANIFEST_CLI_TEMP_DIR:-~/.manifest-cli}"
    export MANIFEST_CLI_TEMP_LIST="${MANIFEST_CLI_TEMP_LIST:-temp-files.list}"
    
    # Configuration file names
    export MANIFEST_CLI_CONFIG_GLOBAL="${MANIFEST_CLI_CONFIG_GLOBAL:-manifest.config.global.yaml}"
    export MANIFEST_CLI_CONFIG_LOCAL="${MANIFEST_CLI_CONFIG_LOCAL:-manifest.config.local.yaml}"
    export MANIFEST_CLI_CONFIG_SCHEMA_VERSION="${MANIFEST_CLI_CONFIG_SCHEMA_VERSION:-${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT}}"
    
    # Project Configuration
    export MANIFEST_CLI_PROJECT_NAME="${MANIFEST_CLI_PROJECT_NAME:-Manifest CLI}"
    
    # Auto-Upgrade Configuration
    export MANIFEST_CLI_AUTO_UPDATE="${MANIFEST_CLI_AUTO_UPDATE:-true}"
    export MANIFEST_CLI_UPDATE_COOLDOWN="${MANIFEST_CLI_UPDATE_COOLDOWN:-30}"
    export MANIFEST_CLI_PROJECT_DESCRIPTION="${MANIFEST_CLI_PROJECT_DESCRIPTION:-A powerful CLI tool for versioning, AI documenting, and repository operations}"
    export MANIFEST_CLI_ORGANIZATION="${MANIFEST_CLI_ORGANIZATION:-Your Organization}"
    
    # Advanced Configuration
    export MANIFEST_CLI_VERSION_REGEX="${MANIFEST_CLI_VERSION_REGEX:-^[0-9]+(\.[0-9]+)*$}"
    export MANIFEST_CLI_VERSION_VALIDATION="${MANIFEST_CLI_VERSION_VALIDATION:-true}"
    
    # Development & Debugging
    export MANIFEST_CLI_DEBUG="${MANIFEST_CLI_DEBUG:-false}"
    export MANIFEST_CLI_VERBOSE="${MANIFEST_CLI_VERBOSE:-false}"
    export MANIFEST_CLI_LOG_LEVEL="${MANIFEST_CLI_LOG_LEVEL:-INFO}"
    export MANIFEST_CLI_INTERACTIVE="${MANIFEST_CLI_INTERACTIVE:-false}"

    # PR Policy
    export MANIFEST_CLI_PR_PROFILE="${MANIFEST_CLI_PR_PROFILE:-solo}"
    export MANIFEST_CLI_PR_ENFORCE_READY="${MANIFEST_CLI_PR_ENFORCE_READY:-true}"

}

# Get configuration value with fallback
get_config() {
    local key="$1"
    local default="$2"
    
    local value="${!key}"
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

_manifest_config_git_infer_default_branch() {
    local branch=""
    branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
    if [ -n "$branch" ]; then
        echo "$branch"
        return 0
    fi

    branch=$(git config --get init.defaultBranch 2>/dev/null || echo "")
    if [ -n "$branch" ]; then
        echo "$branch"
        return 0
    fi

    echo "main"
}

_manifest_config_git_infer_repo_name() {
    local remote_url=""
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$remote_url" ]; then
        basename "$remote_url" .git
        return 0
    fi

    basename "$(pwd)"
}

_manifest_config_git_infer_org() {
    local remote_url=""
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$remote_url" ]; then
        echo ""
        return 0
    fi

    if [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/([^/]+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$remote_url" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    echo ""
}

_manifest_config_prompt_value() {
    local prompt="$1"
    local default_value="${2:-}"
    local user_input=""

    if [ -n "$default_value" ]; then
        read -r -p "$prompt [$default_value]: " user_input
    else
        read -r -p "$prompt: " user_input
    fi
    echo "${user_input:-$default_value}"
}

configure_interactive() {
    if [ ! -t 0 ]; then
        log_error "Interactive config requires a TTY. Use: manifest config show"
        return 1
    fi

    local config_file="$PROJECT_ROOT/manifest.config.local.yaml"
    local inferred_repo_name inferred_org inferred_default_branch
    inferred_repo_name=$(_manifest_config_git_infer_repo_name)
    inferred_org=$(_manifest_config_git_infer_org)
    inferred_default_branch=$(_manifest_config_git_infer_default_branch)

    echo "🛠️  Manifest Config Setup"
    echo "========================="
    echo "This writes overrides to: $config_file"
    echo ""
    echo "Press Enter to keep each default."
    echo ""

    local project_name project_description organization
    local default_branch feature_prefix hotfix_prefix release_prefix bugfix_prefix
    local time_server1 time_server2 time_server3 time_server4 time_timeout time_retries time_verify timezone
    local docs_folder docs_archive docs_limit
    local auto_update update_cooldown pr_profile pr_enforce_ready

    project_name=$(_manifest_config_prompt_value "Project name" "${MANIFEST_CLI_PROJECT_NAME:-$inferred_repo_name}")
    project_description=$(_manifest_config_prompt_value "Project description" "${MANIFEST_CLI_PROJECT_DESCRIPTION:-A powerful CLI tool for versioning, AI documenting, and repository operations}")
    organization=$(_manifest_config_prompt_value "Organization" "${MANIFEST_CLI_ORGANIZATION:-$inferred_org}")

    echo ""
    echo "Git settings:"
    default_branch=$(_manifest_config_prompt_value "Default branch" "${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-$inferred_default_branch}")
    feature_prefix=$(_manifest_config_prompt_value "Feature branch prefix" "${MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX:-feature/}")
    hotfix_prefix=$(_manifest_config_prompt_value "Hotfix branch prefix" "${MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX:-hotfix/}")
    release_prefix=$(_manifest_config_prompt_value "Release branch prefix" "${MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX:-release/}")
    bugfix_prefix=$(_manifest_config_prompt_value "Bugfix branch prefix" "${MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX:-bugfix/}")

    echo ""
    echo "Time server settings:"
    time_server1=$(_manifest_config_prompt_value "Time server 1" "${MANIFEST_CLI_TIME_SERVER1:-https://www.cloudflare.com/cdn-cgi/trace}")
    time_server2=$(_manifest_config_prompt_value "Time server 2" "${MANIFEST_CLI_TIME_SERVER2:-https://www.google.com/generate_204}")
    time_server3=$(_manifest_config_prompt_value "Time server 3" "${MANIFEST_CLI_TIME_SERVER3:-https://www.apple.com}")
    time_server4=$(_manifest_config_prompt_value "Time server 4" "${MANIFEST_CLI_TIME_SERVER4:-}")
    time_timeout=$(_manifest_config_prompt_value "Time server timeout (seconds)" "${MANIFEST_CLI_TIME_TIMEOUT:-5}")
    time_retries=$(_manifest_config_prompt_value "Time server retries" "${MANIFEST_CLI_TIME_RETRIES:-3}")
    time_verify=$(_manifest_config_prompt_value "Verify time server responses (true/false)" "${MANIFEST_CLI_TIME_VERIFY:-true}")
    timezone=$(_manifest_config_prompt_value "Timezone (IANA, e.g. UTC, America/New_York)" "${MANIFEST_CLI_TIMEZONE:-UTC}")

    echo ""
    echo "Docs + automation:"
    docs_folder=$(_manifest_config_prompt_value "Docs folder" "${MANIFEST_CLI_DOCS_FOLDER:-docs}")
    docs_archive=$(_manifest_config_prompt_value "Docs archive folder" "${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER:-docs/zArchive}")
    docs_limit=$(_manifest_config_prompt_value "Historical docs limit" "${MANIFEST_CLI_DOCS_HISTORICAL_LIMIT:-20}")
    auto_update=$(_manifest_config_prompt_value "Auto-upgrade enabled (true/false)" "${MANIFEST_CLI_AUTO_UPDATE:-true}")
    update_cooldown=$(_manifest_config_prompt_value "Upgrade cooldown (minutes)" "${MANIFEST_CLI_UPDATE_COOLDOWN:-30}")

    echo ""
    echo "PR policy:"
    pr_profile=$(_manifest_config_prompt_value "PR profile (solo|team|regulated)" "${MANIFEST_CLI_PR_PROFILE:-solo}")
    pr_enforce_ready=$(_manifest_config_prompt_value "Enforce PR ready gate (true/false)" "${MANIFEST_CLI_PR_ENFORCE_READY:-true}")

    if ! [[ "$time_timeout" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid time server timeout '$time_timeout'; using existing/default value."
        time_timeout="${MANIFEST_CLI_TIME_TIMEOUT:-5}"
    fi
    if ! [[ "$time_retries" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid time server retries '$time_retries'; using existing/default value."
        time_retries="${MANIFEST_CLI_TIME_RETRIES:-3}"
    fi
    if ! [[ "$docs_limit" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid docs limit '$docs_limit'; using existing/default value."
        docs_limit="${MANIFEST_CLI_DOCS_HISTORICAL_LIMIT:-20}"
    fi
    if ! [[ "$update_cooldown" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid upgrade cooldown '$update_cooldown'; using existing/default value."
        update_cooldown="${MANIFEST_CLI_UPDATE_COOLDOWN:-30}"
    fi

    set_yaml_value "$config_file" "project.name" "$project_name"
    set_yaml_value "$config_file" "project.description" "$project_description"
    set_yaml_value "$config_file" "project.organization" "$organization"
    set_yaml_value "$config_file" "git.default_branch" "$default_branch"
    set_yaml_value "$config_file" "git.feature_prefix" "$feature_prefix"
    set_yaml_value "$config_file" "git.hotfix_prefix" "$hotfix_prefix"
    set_yaml_value "$config_file" "git.release_prefix" "$release_prefix"
    set_yaml_value "$config_file" "git.bugfix_prefix" "$bugfix_prefix"
    set_yaml_value "$config_file" "time.server1" "$time_server1"
    set_yaml_value "$config_file" "time.server2" "$time_server2"
    set_yaml_value "$config_file" "time.server3" "$time_server3"
    set_yaml_value "$config_file" "time.server4" "$time_server4"
    set_yaml_value "$config_file" "time.timeout" "$time_timeout"
    set_yaml_value "$config_file" "time.retries" "$time_retries"
    set_yaml_value "$config_file" "time.verify" "$time_verify"
    set_yaml_value "$config_file" "time.timezone" "$timezone"
    set_yaml_value "$config_file" "docs.folder" "$docs_folder"
    set_yaml_value "$config_file" "docs.archive_folder" "$docs_archive"
    set_yaml_value "$config_file" "docs.historical_limit" "$docs_limit"
    set_yaml_value "$config_file" "auto_update.enabled" "$auto_update"
    set_yaml_value "$config_file" "auto_update.cooldown" "$update_cooldown"
    set_yaml_value "$config_file" "pr.profile" "$pr_profile"
    set_yaml_value "$config_file" "pr.enforce_ready" "$pr_enforce_ready"

    echo ""
    echo "✅ Saved configuration to $config_file"
    echo "ℹ️  Run 'manifest config show' to review effective values."
}

# Validate version format configuration
validate_version_config() {
    local format="$MANIFEST_CLI_VERSION_FORMAT"
    local separator="$MANIFEST_CLI_VERSION_SEPARATOR"
    
    # Basic validation
    if [ -z "$format" ]; then
        echo "❌ MANIFEST_CLI_VERSION_FORMAT is not set"
        return 1
    fi
    
    if [ -z "$separator" ]; then
        echo "❌ MANIFEST_CLI_VERSION_SEPARATOR is not set"
        return 1
    fi
    
    # Check if format contains the separator
    if [[ "$format" != *"$separator"* ]]; then
        echo "❌ MANIFEST_CLI_VERSION_FORMAT must contain MANIFEST_CLI_VERSION_SEPARATOR"
        return 1
    fi
    
    echo "✅ Version configuration validated"
    return 0
}

# Parse version components based on configuration
parse_version_components() {
    local version="$1"
    local format="$MANIFEST_CLI_VERSION_FORMAT"
    local separator="$MANIFEST_CLI_VERSION_SEPARATOR"
    
    if [ -z "$version" ] || [ -z "$format" ]; then
        return 1
    fi
    
    # Split format into components
    IFS="$separator" read -ra format_components <<< "$format"
    IFS="$separator" read -ra version_components <<< "$version"
    
    # Create associative array for components
    declare -A components
    local i=0
    for component in "${format_components[@]}"; do
        if [ $i -lt ${#version_components[@]} ]; then
            components["$component"]="${version_components[$i]}"
        else
            components["$component"]="0"
        fi
        ((i++))
    done
    
    # Return components based on format
    case "$format" in
        *"X"*)
            # Standard semantic versioning (X.X.X)
            echo "${components[X]:-0}"
            ;;
        *"XX"*)
            # Two-digit components (XX.XX.XX)
            echo "${components[XX]:-00}"
            ;;
        *"XXX"*)
            # Three-digit components (XXX.XXX.XXX)
            echo "${components[XXX]:-000}"
            ;;
        *"XXXX"*)
            # Four-digit components (XXXX.XXXX.XXXX)
            echo "${components[XXXX]:-0000}"
            ;;
        *"YYYY"*)
            # Year-based components (YYYY.MM.DD)
            echo "${components[YYYY]:-$(date +%Y)}"
            ;;
        *)
            # Fallback to first component
            echo "${version_components[0]:-0}"
            ;;
    esac
}

# Generate next version based on configuration
generate_next_version() {
    local current_version="$1"
    local increment_type="$2"
    local format="$MANIFEST_CLI_VERSION_FORMAT"
    local separator="$MANIFEST_CLI_VERSION_SEPARATOR"
    
    if [ -z "$current_version" ] || [ -z "$format" ]; then
        return 1
    fi
    
    # Parse current version components
    IFS="$separator" read -ra current_components <<< "$current_version"
    IFS="$separator" read -ra format_components <<< "$format"
    
    # Create new version array
    local new_components=("${current_components[@]}")
    
    # Apply increment based on type and format
    case "$increment_type" in
        "patch")
            # Increment last component
            local last_index=$((${#new_components[@]} - 1))
            new_components[$last_index]=$((${new_components[$last_index]} + 1))
            ;;
        "minor")
            # Increment second-to-last component, reset last
            if [ ${#new_components[@]} -ge 2 ]; then
                local minor_index=$((${#new_components[@]} - 2))
                new_components[$minor_index]=$((${new_components[$minor_index]} + 1))
                new_components[$((${#new_components[@]} - 1))]=0
            fi
            ;;
        "major")
            # Increment first component, reset others
            new_components[0]=$((${new_components[0]} + 1))
            for i in $(seq 1 $((${#new_components[@]} - 1))); do
                new_components[$i]=0
            done
            ;;
        "revision")
            # Add revision component if supported
            if [[ "$format" == *"X"* ]]; then
                new_components+=("1")
            fi
            ;;
    esac
    
    # Join components with separator
    local new_version=""
    for i in "${!new_components[@]}"; do
        if [ $i -eq 0 ]; then
            new_version="${new_components[$i]}"
        else
            new_version="${new_version}${separator}${new_components[$i]}"
        fi
    done
    
    echo "$new_version"
}

# Display current configuration
show_configuration() {
    echo "🔧 Manifest CLI Configuration"
    echo "=============================="
    echo ""
    
    echo "📋 Versioning Configuration:"
    echo "   Format: ${MANIFEST_CLI_VERSION_FORMAT}"
    echo "   Separator: ${MANIFEST_CLI_VERSION_SEPARATOR}"
    echo "   Components: ${MANIFEST_CLI_VERSION_COMPONENTS}"
    echo "   Max Values: ${MANIFEST_CLI_VERSION_MAX_VALUES}"
    echo ""
    
    echo "🧠 Human-Intuitive Component Mapping:"
    echo "   Major Position: ${MANIFEST_CLI_MAJOR_COMPONENT_POSITION} (leftmost = biggest impact)"
    echo "   Minor Position: ${MANIFEST_CLI_MINOR_COMPONENT_POSITION} (middle = moderate impact)"
    echo "   Patch Position: ${MANIFEST_CLI_PATCH_COMPONENT_POSITION} (rightmost = least impact)"
    echo "   Revision Position: ${MANIFEST_CLI_REVISION_COMPONENT_POSITION} (most right = most specific)"
    echo ""
    
    echo "📈 Increment Behavior:"
    echo "   Major Target: ${MANIFEST_CLI_MAJOR_INCREMENT_TARGET} (which component increments)"
    echo "   Minor Target: ${MANIFEST_CLI_MINOR_INCREMENT_TARGET} (which component increments)"
    echo "   Patch Target: ${MANIFEST_CLI_PATCH_INCREMENT_TARGET} (which component increments)"
    echo "   Revision Target: ${MANIFEST_CLI_REVISION_INCREMENT_TARGET} (which component increments)"
    echo ""
    
    echo "🔄 Reset Behavior:"
    echo "   Major Reset: ${MANIFEST_CLI_MAJOR_RESET_COMPONENTS} (components reset to 0)"
    echo "   Minor Reset: ${MANIFEST_CLI_MINOR_RESET_COMPONENTS} (components reset to 0)"
    echo "   Patch Reset: ${MANIFEST_CLI_PATCH_RESET_COMPONENTS} (components reset to 0)"
    echo "   Revision Reset: ${MANIFEST_CLI_REVISION_RESET_COMPONENTS} (components reset to 0)"
    echo ""
    
    echo "🌿 Branch Configuration:"
    echo "   Default Branch: ${MANIFEST_CLI_GIT_DEFAULT_BRANCH}"
    echo "   Feature Prefix: ${MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX}"
    echo "   Hotfix Prefix: ${MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX}"
    echo "   Release Prefix: ${MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX}"
    echo "   Bugfix Prefix: ${MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX}"
    echo "   Development Branch: ${MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH}"
    echo "   Staging Branch: ${MANIFEST_CLI_GIT_STAGING_BRANCH}"
    echo ""
    
    echo "🏷️  Git Configuration:"
    echo "   Tag Prefix: ${MANIFEST_CLI_GIT_TAG_PREFIX}"
    echo "   Tag Suffix: ${MANIFEST_CLI_GIT_TAG_SUFFIX}"
    echo "   Push Strategy: ${MANIFEST_CLI_GIT_PUSH_STRATEGY}"
    echo "   Pull Strategy: ${MANIFEST_CLI_GIT_PULL_STRATEGY}"
    echo "   Timeout: ${MANIFEST_CLI_GIT_TIMEOUT} seconds"
    echo "   Retries: ${MANIFEST_CLI_GIT_RETRIES} attempts"
    echo "   Remotes: Uses all configured git remotes automatically"
    echo ""

    echo "🕐 Time Server Configuration:"
    echo "   Server 1: ${MANIFEST_CLI_TIME_SERVER1}"
    echo "   Server 2: ${MANIFEST_CLI_TIME_SERVER2}"
    echo "   Server 3: ${MANIFEST_CLI_TIME_SERVER3}"
    echo "   Server 4: ${MANIFEST_CLI_TIME_SERVER4}"
    echo "   Timeout: ${MANIFEST_CLI_TIME_TIMEOUT} seconds"
    echo "   Retries: ${MANIFEST_CLI_TIME_RETRIES} attempts"
    echo "   Verify: ${MANIFEST_CLI_TIME_VERIFY}"
    echo ""
    
    echo "📚 Documentation Configuration:"
    echo "   Docs Folder: ${MANIFEST_CLI_DOCS_FOLDER}"
    echo "   Archive Folder: ${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER}"
    echo "   Filename Pattern: ${MANIFEST_CLI_DOCS_FILENAME_PATTERN}"
    echo "   Historical Limit: ${MANIFEST_CLI_DOCS_HISTORICAL_LIMIT}"
    echo ""
    
    echo "🏢 Project Configuration:"
    echo "   Project Name: ${MANIFEST_CLI_PROJECT_NAME}"
    echo "   Description: ${MANIFEST_CLI_PROJECT_DESCRIPTION}"
    echo "   Organization: ${MANIFEST_CLI_ORGANIZATION}"
    echo ""
    
    echo "📍 Installation Configuration:"
    echo "   Binary Location: ${BINARY_LOCATION:-Not set}"
    echo "   Install Location: ${INSTALL_LOCATION:-Not set}"
    echo "   Project Root: ${PROJECT_ROOT:-Not set}"
    echo ""
    
    echo "⚙️  Advanced Configuration:"
    echo "   Version Regex: ${MANIFEST_CLI_VERSION_REGEX}"
    echo "   Version Validation: ${MANIFEST_CLI_VERSION_VALIDATION}"
    echo ""
    
    echo "🔄 Auto-Upgrade Configuration:"
    echo "   Auto-Upgrade: ${MANIFEST_CLI_AUTO_UPDATE}"
    echo "   Upgrade Cooldown: ${MANIFEST_CLI_UPDATE_COOLDOWN} minutes"
    echo "   Config Schema Version: ${MANIFEST_CLI_CONFIG_SCHEMA_VERSION}"
    echo ""
    
    echo "💡 How This Works:"
    echo "   • LEFT components = More MAJOR changes (bigger impact)"
    echo "   • RIGHT components = More MINOR changes (smaller impact)"
    echo "   • More digits after last dot = More specific/precise changes"
    echo "   • 'manifest prep major' increments component ${MANIFEST_CLI_MAJOR_INCREMENT_TARGET}"
    echo "   • 'manifest prep minor' increments component ${MANIFEST_CLI_MINOR_INCREMENT_TARGET}"
    echo "   • 'manifest prep patch' increments component ${MANIFEST_CLI_PATCH_INCREMENT_TARGET}"
    echo "   • 'manifest prep revision' increments component ${MANIFEST_CLI_REVISION_INCREMENT_TARGET}"
    echo ""
    echo "Quick views:"
    echo "   • manifest config          # Interactive setup wizard"
    echo "   • manifest config show     # Full effective configuration"
    echo "   • manifest config time     # Time server configuration view"
    echo "   • manifest config doctor   # Drift/deprecation diagnostics"
}

# Get documentation folder path
get_docs_folder() {
    local project_root="$1"
    if [ -z "$project_root" ]; then
        project_root="$PROJECT_ROOT"
    fi
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    echo "$project_root/$MANIFEST_CLI_DOCS_FOLDER"
}

# Get documentation archive folder path
get_docs_archive_folder() {
    local project_root="$1"
    if [ -z "$project_root" ]; then
        project_root="$PROJECT_ROOT"
    fi
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    echo "$project_root/$MANIFEST_CLI_DOCS_ARCHIVE_FOLDER"
}

# Export functions for use in other modules
export -f load_configuration
export -f set_default_configuration
export -f get_config
export -f validate_version_config
export -f parse_version_components
export -f generate_next_version
export -f show_configuration
export -f config_doctor
export -f configure_interactive
export -f get_docs_folder
export -f get_docs_archive_folder

# Note: Configuration loading is handled explicitly by the main CLI module
# to ensure proper initialization order and avoid duplicate loading
