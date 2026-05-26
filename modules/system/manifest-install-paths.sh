#!/bin/bash

# Manifest Install Paths
#
# Single source of truth for filesystem locations the Manifest CLI installs,
# inspects, and removes. Every installer/uninstaller/upgrader code path
# (install-cli.sh, uninstall-cli.sh, modules/system/manifest-uninstall.sh, the
# Cloud auto-upgrade plugin) reads from here.
#
# Returning newline-separated strings from getters (rather than exporting
# arrays) keeps this module portable across subshells and pre-bash-4
# environments — exported bash arrays don't cross either reliably.

[ -n "$_MANIFEST_INSTALL_PATHS_LOADED" ] && return 0
_MANIFEST_INSTALL_PATHS_LOADED=1

# --- Homebrew ---------------------------------------------------------------

manifest_install_paths_homebrew_formula() { echo "fidenceio/tap/manifest"; }
manifest_install_paths_homebrew_tap()     { echo "fidenceio/tap"; }

manifest_install_paths_homebrew_tap_dir() {
    command -v brew >/dev/null 2>&1 || return 0
    local prefix
    prefix="$(brew --prefix 2>/dev/null || true)"
    [ -z "$prefix" ] && return 0
    echo "$prefix/Library/Taps/fidenceio/homebrew-tap"
}

# --- Install layout ---------------------------------------------------------

manifest_install_paths_global_state_dir() {
    echo "$HOME/.manifest-cli"
}

manifest_install_paths_user_global_config() {
    echo "$HOME/.manifest-cli/manifest.config.global.yaml"
}

manifest_install_paths_legacy_install_dir() {
    echo "/usr/local/share/manifest-cli"
}

manifest_install_paths_runtime_root() {
    echo "${MANIFEST_CLI_INSTALL_LOCATION:-$HOME/.manifest-cli}/runtime"
}

manifest_install_paths_current_symlink() {
    echo "${MANIFEST_CLI_INSTALL_LOCATION:-$HOME/.manifest-cli}/current"
}

# Echo the versioned install directory for a given version. The caller may
# pass either "1.2.3" or "v1.2.3"; the helper normalizes to ensure the
# returned path always has a single leading 'v'. Never trust the caller.
manifest_install_paths_versioned_dir() {
    local version="$1"
    [ -n "$version" ] || return 1
    case "$version" in
        v*) ;;
        *) version="v$version" ;;
    esac
    echo "$(manifest_install_paths_runtime_root)/${version}"
}

# Subdirectories under the install root that hold user state and must never
# be touched by an upgrade swap. Returned one-per-line so callers can iterate
# without depending on bash arrays.
manifest_install_paths_preserved_subdirs() {
    echo "logs"
    echo "audit"
    echo "ide"
}

manifest_install_paths_install_dirs() {
    # Dedupe so the artifact list shown by uninstall/preview never repeats a
    # path (e.g. when MANIFEST_CLI_INSTALL_LOCATION points at $HOME/.manifest-cli,
    # the canonical install location).
    local seen="" path
    for path in \
        "$HOME/.manifest-cli" \
        "/usr/local/share/manifest-cli" \
        "${MANIFEST_CLI_INSTALL_LOCATION:-}" \
        "${MANIFEST_CLI_INSTALL_DIR:-}"; do
        [ -n "$path" ] || continue
        case ":${seen}:" in
            *":${path}:"*) continue ;;
        esac
        seen="${seen:+${seen}:}${path}"
        echo "$path"
    done
}

manifest_install_paths_user_bin_dir() {
    echo "$HOME/.local/bin"
}

manifest_install_paths_user_binary() {
    echo "$HOME/.local/bin/manifest"
}

manifest_install_paths_binary_candidates() {
    manifest_install_paths_user_binary
    echo "/usr/local/bin/manifest"
    echo "/opt/manifest-cli/bin/manifest"
}

# --- Config and runtime data ------------------------------------------------

manifest_install_paths_config_files() {
    echo "$HOME/.manifestrc"
    echo "$HOME/.manifest-cli.conf"
    echo "$HOME/.config/manifest-cli"
    manifest_install_paths_user_global_config
}

# Cache-sweep-safe roots only. The runtime-cleanup module reads exclusively
# from here; plugin data dirs are intentionally excluded so opportunistic
# cleanup cannot touch user-owned plugin state.
manifest_install_paths_cache_dirs() {
    local tmpdir_cache="${TMPDIR:-/tmp}/manifest-cli"
    echo "$tmpdir_cache"
    [ "/tmp/manifest-cli" != "$tmpdir_cache" ] && echo "/tmp/manifest-cli"
    return 0
}

# Scratch directory for short-lived temp files. Every site that previously
# called raw `mktemp` should funnel through here so the TTL-gated cache
# sweep ([[runtime-cleanup]]) eventually collects leaked files instead of
# stranding them in the system $TMPDIR where the sweep cannot reach.
#
# Sites that need a same-filesystem atomic-replace temp (write-then-mv) are
# the exception: they must use `mktemp "${target}.XXXXXX"` next to the
# target. See modules/fleet/manifest-fleet-detect.sh:1501 for the canonical
# example.
manifest_make_scratch_path() {
    local purpose="${1:-misc}"
    local root="${TMPDIR:-/tmp}/manifest-cli"
    local dir="${root}/scratch/${purpose}"
    mkdir -p "$dir" 2>/dev/null || return 1
    echo "$dir"
}

manifest_install_paths_data_dirs() {
    manifest_install_paths_cache_dirs
    manifest_install_paths_plugin_data_dirs
}

# Plugin-declared data dirs. Each cli-plugin under
# ${MANIFEST_CLI_CLOUD_DIR:-$HOME/.manifest-cloud}/cli-plugins/ may ship a
# sibling <name>.data-dirs file listing absolute paths it owns at runtime, so
# uninstall sweeps plugin-owned state without hardcoding plugin internals.
# Per-line format: absolute path; literal $HOME is the only allowed
# substitution; '#' starts a comment; paths must resolve under $HOME/.
manifest_install_paths_plugin_data_dirs() {
    [ -n "$HOME" ] || return 0
    local plugins_dir="${MANIFEST_CLI_CLOUD_DIR:-$HOME/.manifest-cloud}/cli-plugins"
    [ -d "$plugins_dir" ] || return 0
    local manifest line path
    while IFS= read -r manifest; do
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [ -n "$line" ] || continue
            path="${line//\$HOME/$HOME}"
            case "$path" in "$HOME"/*) echo "$path" ;; esac
        done < "$manifest"
    done < <(find "$plugins_dir" -type f -name '*.data-dirs' 2>/dev/null | sort)
}

# --- Shell profile cleanup --------------------------------------------------

manifest_install_paths_shell_profiles() {
    echo "$HOME/.zshrc"
    echo "$HOME/.zprofile"
    echo "$HOME/.zsh_profile"
    echo "$HOME/.bashrc"
    echo "$HOME/.bash_profile"
    echo "$HOME/.profile"
}

# --- Destructive-target sandbox tripwire -----------------------------------
#
# Every code path that destroys install footprint (rm -rf, rm -f, sudo rm,
# brew uninstall, profile rewrite) must call this predicate before acting.
# It refuses to proceed if the target looks like a real-system path while
# the process is running inside bats (BATS_TEST_TMPDIR is set), so a test
# that forgets to redirect HOME cannot wipe the real install footprint.
#
# To override (exceedingly rare — only when a legitimately-needed bats test
# operates outside its sandbox), export MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1.
# A loud stderr warning is emitted in that case so it cannot be enabled silently.
manifest_install_paths_assert_destructive_target_safe() {
    local path="$1"
    local kind="${2:-rm}"

    if [ -z "$path" ]; then
        echo "manifest: refusing destructive ${kind}: empty target path" >&2
        return 1
    fi
    case "$path" in
        /|/Users|/Users/|/home|/home/|/usr|/usr/|/var|/var/|/etc|/etc/|/opt|/opt/|/private|/private/)
            echo "manifest: refusing destructive ${kind}: system path '$path'" >&2
            return 1
            ;;
    esac
    if [ -n "${HOME:-}" ] && { [ "$path" = "$HOME" ] || [ "$path" = "$HOME/" ]; }; then
        echo "manifest: refusing destructive ${kind}: target is \$HOME ('$HOME') itself" >&2
        return 1
    fi

    if [ -n "${BATS_TEST_TMPDIR:-}" ]; then
        if [ "${MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE:-}" = "1" ]; then
            echo "manifest: warning: destructive ${kind} on '$path' permitted by MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1" >&2
            return 0
        fi
        case "$path" in
            "$BATS_TEST_TMPDIR"/*) ;;
            *)
                echo "manifest: refusing destructive ${kind} on '$path': running under bats (BATS_TEST_TMPDIR=$BATS_TEST_TMPDIR) but target is not inside it." >&2
                echo "manifest: this is the test sandbox tripwire. Sandbox your test by setting HOME under \$BATS_TEST_TMPDIR (see tests/helpers/setup.bash), or set MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 to explicitly override." >&2
                return 1
                ;;
        esac
    fi

    return 0
}

# Same tripwire for brew (where there is no path argument — refuse all
# brew-uninstall/untap calls under bats unless the escape hatch is set).
manifest_install_paths_assert_destructive_brew_safe() {
    local op="${1:-brew}"
    if [ -n "${BATS_TEST_TMPDIR:-}" ]; then
        if [ "${MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE:-}" = "1" ]; then
            echo "manifest: warning: ${op} permitted by MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 under bats" >&2
            return 0
        fi
        echo "manifest: refusing ${op}: running under bats (BATS_TEST_TMPDIR=$BATS_TEST_TMPDIR). Set MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 to explicitly override." >&2
        return 1
    fi
    return 0
}

# Matches any shell-profile line that:
#   - exports a Manifest-owned variable (current or legacy namespace)
#   - prepends .manifest-cli or .local/bin to PATH (installer-style)
#   - sources a manifest-related rc file
#
# Legacy-cleanup exception: the export pattern intentionally matches the bare
# Manifest prefix used before namespacing, so uninstall sweeps stale exports
# from pre-namespace installs. All non-uninstall code must scope to the
# MANIFEST_CLI namespace.
manifest_install_paths_profile_line_regex() {
    echo '^[[:space:]]*(export[[:space:]]+MANIFEST_[A-Z_]+=|export[[:space:]]+PATH=.*\.manifest-cli|export[[:space:]]+PATH=.*\.local/bin.*PATH|(\.|source)[[:space:]]+.*manifest)'
}

# Canonical implementation of the shell-profile sweep. Both install-cli.sh
# and modules/system/manifest-uninstall.sh delegate here so the regex,
# tripwire, backup-naming, and cmp-then-mv pattern have a single home.
#
# Arguments:
#   quiet=0|1     when 1, suppress the per-profile "Cleaned" line and the
#                 "No entries found" summary (uninstall caller wants the
#                 echoes; install caller prints its own banner)
#   unset_env=0|1 when 1, additionally unset MANIFEST_-prefixed env vars in this
#                 process (uninstall semantics; legacy-prefix sweep). When
#                 0, leave the process env alone (install semantics — the
#                 installer relies on these vars during its own run).
#
# Callers should print their own banner (this function does not). Emits
# plain `echo` output for the per-profile lines so it has zero dependency
# on the print_* helpers defined in install-cli.sh.
manifest_install_paths_cleanup_profile_entries() {
    local quiet="${1:-0}"
    local unset_env="${2:-0}"

    local removed_count=0
    local profile_regex
    profile_regex="$(manifest_install_paths_profile_line_regex)"

    local profile_file backup_file temp_file
    while IFS= read -r profile_file; do
        [ -n "$profile_file" ] || continue
        [ -f "$profile_file" ] || continue
        if ! manifest_install_paths_assert_destructive_target_safe "$profile_file" "profile-rewrite"; then
            continue
        fi
        backup_file="${profile_file}.manifest-backup-$(date +%Y%m%d-%H%M%S)"
        cp "$profile_file" "$backup_file"
        temp_file=$(mktemp "$(manifest_make_scratch_path system)/tmp.XXXXXXXX")
        grep -v -E "$profile_regex" "$profile_file" > "$temp_file" || true
        if ! cmp -s "$profile_file" "$temp_file"; then
            mv "$temp_file" "$profile_file"
            if [ "$quiet" != "1" ]; then
                echo "  ✅ Cleaned: $profile_file (backup: $backup_file)"
            fi
            removed_count=$((removed_count + 1))
        else
            rm -f "$temp_file" "$backup_file"
        fi
    done < <(manifest_install_paths_shell_profiles)

    if [ "$quiet" != "1" ]; then
        if [ $removed_count -eq 0 ]; then
            echo "  No Manifest CLI entries found in shell profiles"
        else
            echo "  ✅ Cleaned $removed_count shell profile(s) — restart your terminal to apply"
        fi
    fi

    # Best-effort in-process unset (uninstall semantics; legacy-prefix sweep).
    # Legacy-cleanup exception: matches both the current MANIFEST_CLI
    # namespace and the bare Manifest prefix used before namespacing. New
    # code must scope to MANIFEST_CLI; only uninstall paths broaden the
    # pattern.
    if [ "$unset_env" = "1" ]; then
        local var
        for var in $(env | grep -E '^MANIFEST_(CLI_)?[A-Z_]+=' | cut -d'=' -f1); do
            unset "$var"
        done
    fi

    return 0
}
