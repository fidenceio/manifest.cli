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

# Provenance predicate — the SINGLE source of truth for "is the Manifest CLI
# currently installed *and managed by Homebrew*". This is deliberately distinct
# from "is brew available on this machine" (`command -v brew`): conflating the
# two is what let a bare `install-cli.sh` re-run silently convert a --manual
# source install onto the shipped formula. Every site that must decide
# brew-vs-source provenance (installer routing, uninstall, doctor reinstall,
# post-ship self-upgrade) routes here so the answer can never drift.
#
# Checks the tap-qualified formula first, then the bare leaf name, matching how
# a tap install registers. Silent; returns 0 (brew-managed) / 1 (not).
manifest_install_paths_is_brew_managed() {
    command -v brew >/dev/null 2>&1 || return 1
    brew list "$(manifest_install_paths_homebrew_formula)" >/dev/null 2>&1 && return 0
    brew list manifest >/dev/null 2>&1 && return 0
    return 1
}

# Ensure Homebrew will keep loading the Manifest formula once tap-trust is
# enforced. Newer Homebrew warns that non-official taps are untrusted, and once
# HOMEBREW_REQUIRE_TAP_TRUST=1 becomes the default (slated for Homebrew 5.2/6.0)
# it *ignores* untrusted formulae — so `brew install`/`brew upgrade manifest`
# (incl. the post-push auto-upgrade) would silently no-op: no error, no new
# version. Pre-empt that by trusting the formula narrowly (least privilege: this
# formula, not the whole tap). Idempotent; safe to call before every
# install/upgrade. Verified against Homebrew 5.1.15: `brew trust --formula
# <target>`, state in ~/.homebrew/trust.json.
#
# Version-guarded — older Homebrew has no `trust` subcommand. Return codes let
# callers report with their own UI helpers:
#   0 - trust ensured (or already trusted)
#   1 - `trust` present but the trust call failed (worth surfacing)
#   2 - nothing to do (brew absent, or this Homebrew has no `trust` subcommand)
manifest_install_paths_ensure_brew_trust() {
    command -v brew >/dev/null 2>&1 || return 2
    brew trust --help >/dev/null 2>&1 || return 2
    brew trust --formula "$(manifest_install_paths_homebrew_formula)" >/dev/null 2>&1 || return 1
    return 0
}

# Companion predicate — is there a --manual (source-tree) install? The manual
# install writes the version-agnostic wrapper to the user-bin location; a
# Homebrew install never does (it symlinks into $(brew --prefix)/bin instead),
# so the presence of this binary unambiguously marks the source channel.
# Silent; returns 0 (manual install present) / 1 (not).
manifest_install_paths_is_manual_install() {
    [ -f "$(manifest_install_paths_user_binary)" ]
}

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
    echo "locks"
}

# Directory holding single-flight lock dirs (e.g. concurrent fleet ships).
# Lives under the preserved global-state root so an upgrade swap can never
# delete a lock that a running operation still holds.
manifest_install_paths_locks_dir() {
    echo "$(manifest_install_paths_global_state_dir)/locks"
}

# Directory holding per-run diagnostic ship logs (CLI tracker §5.6 — the
# *what-happened-for-debug* record). Lives under the preserved global-state
# root (in preserved_subdirs, so an upgrade swap never wipes it) and is
# deliberately NOT under manifest_install_paths_cache_dirs: diagnostic logs are
# forensic, not transient, so the TTL-gated runtime cache sweep must never
# collect them. Their own keep-last-N rotation bounds growth instead.
manifest_install_paths_logs_dir() {
    echo "$(manifest_install_paths_global_state_dir)/logs"
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

# --- Shell completions ------------------------------------------------------
#
# Manual-install completion files (the user-writable locations install-cli.sh
# owns). Emitted one per line, bash target first then zsh, so install can read
# them positionally and uninstall can sweep them. Single source of truth — the
# installer writes exactly these and the uninstaller removes exactly these, so
# the set can never drift.
manifest_install_paths_user_completion_targets() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/manifest"
    echo "$HOME/.zsh/completions/_manifest"
}

# Every shell-completion file ANY Manifest version may have installed, across
# channels — for uninstall to remove "everything, brew or manual". Adds the
# Homebrew-prefix completion paths to the manual set; those same brew-prefix
# paths are also where pre-2026 manual installs wrote completions (before they
# moved to the user-writable locations above — see install-cli.sh history), so
# sweeping them covers that legacy manual layout too.
manifest_install_paths_completion_targets() {
    manifest_install_paths_user_completion_targets
    command -v brew >/dev/null 2>&1 || return 0
    local prefix
    prefix="$(brew --prefix 2>/dev/null || true)"
    [ -n "$prefix" ] || return 0
    echo "$prefix/etc/bash_completion.d/manifest"
    echo "$prefix/share/zsh/site-functions/_manifest"
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
#
# Always refuses obviously-catastrophic targets (empty, system roots, $HOME
# itself). Beyond that it enforces SANDBOX CONFINEMENT: when running in a test
# or sandbox context — under bats (BATS_TEST_TMPDIR set) OR a plain run whose
# HOME is a temp dir (manifest_install_paths_home_looks_sandboxed) — destructive
# ops must stay inside the sandbox tree. A target outside it is refused, so a
# test (or a careless manual repro) cannot delete real-system files such as
# /opt/homebrew/bin/manifest. That confinement refusal returns 3 ("sandbox
# skip") — a distinct non-zero code callers may treat as a protective skip
# rather than a hard failure; the catastrophic-target refusals above return 1.
#
# To override (exceedingly rare), export MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1.
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

    local sandbox_root=""
    if [ -n "${BATS_TEST_TMPDIR:-}" ]; then
        sandbox_root="$BATS_TEST_TMPDIR"
    elif manifest_install_paths_home_looks_sandboxed; then
        sandbox_root="$HOME"
    fi
    if [ -n "$sandbox_root" ]; then
        if [ "${MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE:-}" = "1" ]; then
            echo "manifest: warning: destructive ${kind} on '$path' permitted by MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1" >&2
            return 0
        fi
        case "$path" in
            "$sandbox_root"/*) return 0 ;;
        esac
        if [ -n "${BATS_TEST_TMPDIR:-}" ]; then
            echo "manifest: refusing destructive ${kind} on '$path': running under bats (BATS_TEST_TMPDIR=$BATS_TEST_TMPDIR) but target is not inside it." >&2
            echo "manifest: this is the test sandbox tripwire. Sandbox your test by setting HOME under \$BATS_TEST_TMPDIR (see tests/helpers/setup.bash), or set MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 to explicitly override." >&2
        else
            echo "manifest: refusing destructive ${kind} on '$path': HOME ('$HOME') looks like a temp/sandbox dir but target is outside it — real-system files left untouched." >&2
            echo "manifest: sandbox tripwire — set MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 to explicitly override." >&2
        fi
        return 3
    fi

    return 0
}

# Heuristic: is $HOME a throwaway sandbox (a temp dir) rather than a real user
# home? A genuine uninstall runs against the user's actual home; only tests and
# ad-hoc sandboxes redirect HOME into a temp tree. This matters specifically for
# brew: brew operations are GLOBAL (HOME-independent), so a redirected HOME gives
# a false sense of isolation — `brew uninstall` from a fake HOME still hits the
# host's real install (this is exactly how a manual repro once removed the real
# Homebrew manifest). A sandboxed HOME is therefore a strong signal that a brew
# mutation is unintended, so the brew tripwire refuses it regardless of bats.
manifest_install_paths_home_looks_sandboxed() {
    [ -n "${BATS_TEST_TMPDIR:-}" ] && return 0
    local home="${HOME:-}"
    [ -n "$home" ] || return 1
    local tmp="${TMPDIR:-/tmp}"; tmp="${tmp%/}"
    case "$home" in
        "$tmp"/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;;
    esac
    return 1
}

# Tripwire for brew (no path argument — brew mutations are global). Refuse all
# brew-uninstall/untap calls when running under bats OR against a sandboxed HOME
# (see manifest_install_paths_home_looks_sandboxed), unless the escape hatch is
# set. The HOME check is what makes this hold for any invocation — a plain
# `bash` run against a temp HOME, not just bats — so a real Homebrew install can
# never be removed from a fake home.
manifest_install_paths_assert_destructive_brew_safe() {
    local op="${1:-brew}"
    if [ -n "${BATS_TEST_TMPDIR:-}" ] || manifest_install_paths_home_looks_sandboxed; then
        if [ "${MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE:-}" = "1" ]; then
            echo "manifest: warning: ${op} permitted by MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 (sandboxed HOME / bats)" >&2
            return 0
        fi
        echo "manifest: refusing ${op}: HOME ('${HOME:-}') looks like a temp/sandbox dir or running under bats — global brew left untouched. Set MANIFEST_CLI_ALLOW_DESTRUCTIVE_TEST_ESCAPE=1 to explicitly override." >&2
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
