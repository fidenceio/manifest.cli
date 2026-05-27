#!/bin/bash
# Manifest CLI uninstaller (standalone, self-contained).
#
# Removes every known Manifest CLI artifact regardless of how it was
# installed: Homebrew, install-cli.sh, manual copy, or a half-broken
# install that never finished. Does not depend on a working `manifest`
# binary or sourceable internal module.
#
# Preview by default. Use -y to apply.
#
# Run from the repo root:  ./uninstall-cli.sh
# Or directly:             bash uninstall-cli.sh -y

# =============================================================================
# Configuration & Constants
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_header()  { echo -e "${BOLD}${CYAN}$1${NC}"; }

APPLY=0

usage() {
    cat <<EOF
Usage: ./uninstall-cli.sh [--dry-run | -y | --yes] [-h | --help]

Completely removes Manifest CLI from the system. Works for Homebrew
installs, install-cli.sh installs, manual copies, and partial or broken
installs. Self-contained: does not require a working \`manifest\` binary.

Options:
  --dry-run     Preview what would be removed (default).
  -y, --yes     Apply the removal.
  -h, --help    Show this help.

Artifacts considered:
  - Homebrew package fidenceio/tap/manifest and the fidenceio/tap tap
  - Install dirs: ~/.manifest-cli, /usr/local/share/manifest-cli
  - Binaries: ~/.local/bin/manifest, /usr/local/bin/manifest,
              /opt/manifest-cli/bin/manifest, and any \`manifest\` on PATH
              that carries Manifest CLI markers
  - Config: ~/.manifestrc, ~/.manifest-cli.conf, ~/.config/manifest-cli
  - Data: \$TMPDIR/manifest-cli, /tmp/manifest-cli, and any plugin-declared
          dirs from <plugin>.data-dirs files under ~/.manifest-cloud/cli-plugins/
  - Shell completions: manual (~/.local/share, ~/.zsh) and Homebrew bash/zsh targets
  - Shell-profile entries: MANIFEST_* exports, manifest-cli PATH adds,
    source/. lines referencing manifest, in zsh/bash/profile rc files
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)  APPLY=0 ;;
        -y|--yes)   APPLY=1 ;;
        -h|--help)  usage; exit 0 ;;
        *)          print_error "Unknown option: $1"; echo ""; usage; exit 2 ;;
    esac
    shift
done

# Source the canonical install-paths module. uninstall-cli.sh must stay usable
# when the modules tree is missing (broken/partial checkout), so we fall back
# to inline constants when the source fails. KEEP IN SYNC with
# modules/system/manifest-install-paths.sh.
_UNINSTALL_CLI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_UNINSTALL_CLI_PATHS_MOD="$_UNINSTALL_CLI_SCRIPT_DIR/modules/system/manifest-install-paths.sh"
if [ -f "$_UNINSTALL_CLI_PATHS_MOD" ]; then
    # shellcheck source=modules/system/manifest-install-paths.sh
    source "$_UNINSTALL_CLI_PATHS_MOD"
    INSTALL_DIRS=()
    BINARY_CANDIDATES=()
    CONFIG_PATHS=()
    DATA_DIRS=()
    SHELL_PROFILES=()
    while IFS= read -r _p; do [ -n "$_p" ] && INSTALL_DIRS+=("$_p"); done < <(manifest_install_paths_install_dirs)
    while IFS= read -r _p; do [ -n "$_p" ] && BINARY_CANDIDATES+=("$_p"); done < <(manifest_install_paths_binary_candidates)
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        # uninstall-cli.sh tracks the user global YAML separately under its
        # config-file removal block; skip it from the generic CONFIG_PATHS list
        # so the historical output ordering stays stable.
        [ "$_p" = "$(manifest_install_paths_user_global_config)" ] && continue
        CONFIG_PATHS+=("$_p")
    done < <(manifest_install_paths_config_files)
    while IFS= read -r _p; do [ -n "$_p" ] && DATA_DIRS+=("$_p"); done < <(manifest_install_paths_data_dirs)
    while IFS= read -r _p; do [ -n "$_p" ] && SHELL_PROFILES+=("$_p"); done < <(manifest_install_paths_shell_profiles)
    PROFILE_LINE_REGEX="$(manifest_install_paths_profile_line_regex)"
    BREW_FORMULA="$(manifest_install_paths_homebrew_formula)"
    BREW_TAP="$(manifest_install_paths_homebrew_tap)"
    unset _p
else
    # Fallback for broken/partial checkout.
    INSTALL_DIRS=(
        "$HOME/.manifest-cli"
        "/usr/local/share/manifest-cli"
    )
    BINARY_CANDIDATES=(
        "$HOME/.local/bin/manifest"
        "/usr/local/bin/manifest"
        "/opt/manifest-cli/bin/manifest"
    )
    CONFIG_PATHS=(
        "$HOME/.manifestrc"
        "$HOME/.manifest-cli.conf"
        "$HOME/.config/manifest-cli"
    )
    DATA_DIRS=(
        "${TMPDIR:-/tmp}/manifest-cli"
    )
    [ "/tmp/manifest-cli" != "${TMPDIR:-/tmp}/manifest-cli" ] && DATA_DIRS+=("/tmp/manifest-cli")
    # Inline copy of manifest_install_paths_plugin_data_dirs from
    # modules/system/manifest-install-paths.sh — keep in sync.
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
    while IFS= read -r _p; do [ -n "$_p" ] && DATA_DIRS+=("$_p"); done < <(manifest_install_paths_plugin_data_dirs)
    unset _p
    SHELL_PROFILES=(
        "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zsh_profile"
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"
    )
    PROFILE_LINE_REGEX='^[[:space:]]*(export[[:space:]]+MANIFEST_[A-Z_]+=|export[[:space:]]+PATH=.*\.manifest-cli|export[[:space:]]+PATH=.*\.local/bin.*PATH|(\.|source)[[:space:]]+.*manifest)'
    BREW_FORMULA="fidenceio/tap/manifest"
    BREW_TAP="fidenceio/tap"
fi

# =============================================================================
# Detection
# =============================================================================

# A binary is "ours" if it carries a Manifest CLI marker, lives in a known
# install dir, or matches the installer default path. Prevents nuking an
# unrelated `manifest` binary that happens to share the name.
is_owned_binary() {
    local path="$1" resolved d candidate
    [ -f "$path" ] || return 1
    # Fast-path: known canonical binary locations are unambiguously ours.
    for candidate in "${BINARY_CANDIDATES[@]}"; do
        [ "$path" = "$candidate" ] && return 0
    done
    grep -a -E 'Manifest CLI|manifest-cli|MANIFEST_CLI' "$path" >/dev/null 2>&1 && return 0
    resolved="$(readlink -f "$path" 2>/dev/null || echo "$path")"
    for d in "${INSTALL_DIRS[@]}"; do
        case "$resolved" in "$d"/*) return 0 ;; esac
    done
    return 1
}

found_install_dirs() {
    local d
    for d in "${INSTALL_DIRS[@]}"; do
        [ -d "$d" ] && echo "$d"
    done
}

found_binaries() {
    local out=() b cur seen x
    for b in "${BINARY_CANDIDATES[@]}"; do
        is_owned_binary "$b" && out+=("$b")
    done
    cur="$(command -v manifest 2>/dev/null || true)"
    if [ -n "$cur" ] && is_owned_binary "$cur"; then
        seen=0
        for x in "${out[@]}"; do [ "$x" = "$cur" ] && seen=1; done
        [ "$seen" = 0 ] && out+=("$cur")
    fi
    printf '%s\n' "${out[@]}"
}

found_configs() {
    local c
    for c in "${CONFIG_PATHS[@]}"; do
        [ -e "$c" ] && echo "$c"
    done
}

found_data_dirs() {
    local d
    for d in "${DATA_DIRS[@]}"; do
        [ -d "$d" ] && echo "$d"
    done
}

found_profile_files() {
    local profile
    for profile in "${SHELL_PROFILES[@]}"; do
        [ -f "$profile" ] || continue
        grep -q -E "$PROFILE_LINE_REGEX" "$profile" 2>/dev/null && echo "$profile"
    done
}

# Completion files to remove. Delegates to the canonical getter (manual + brew +
# legacy locations) when the install-paths module loaded, so the standalone
# uninstaller removes manual completions too — not just brew's. Falls back to
# brew-only for a partial checkout where the module is absent. Emits only files
# that currently exist (regular file or symlink, incl. broken symlinks).
brew_completion_targets() {
    local t
    if type manifest_install_paths_completion_targets >/dev/null 2>&1; then
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            if [ -e "$t" ] || [ -L "$t" ]; then echo "$t"; fi
        done < <(manifest_install_paths_completion_targets)
        return 0
    fi
    command -v brew >/dev/null 2>&1 || return 0
    local p b z
    p="$(brew --prefix 2>/dev/null || true)"
    [ -z "$p" ] && return 0
    b="$p/etc/bash_completion.d/manifest"
    z="$p/share/zsh/site-functions/_manifest"
    [ -e "$b" ] && echo "$b"
    [ -e "$z" ] && echo "$z"
}

brew_package_present() {
    # Delegate to the canonical provenance predicate when the install-paths
    # module loaded; fall back to the inline check for a partial checkout where
    # the module is absent (see the conditional source above).
    if type manifest_install_paths_is_brew_managed >/dev/null 2>&1; then
        manifest_install_paths_is_brew_managed
        return $?
    fi
    command -v brew >/dev/null 2>&1 || return 1
    brew list "$BREW_FORMULA" >/dev/null 2>&1 || brew list manifest >/dev/null 2>&1
}

brew_tap_present() {
    command -v brew >/dev/null 2>&1 || return 1
    local tap_dir
    if type manifest_install_paths_homebrew_tap_dir >/dev/null 2>&1; then
        tap_dir="$(manifest_install_paths_homebrew_tap_dir)"
    else
        local p; p="$(brew --prefix 2>/dev/null || true)"
        [ -n "$p" ] || return 1
        tap_dir="$p/Library/Taps/fidenceio/homebrew-tap"
    fi
    [ -n "$tap_dir" ] && [ -d "$tap_dir" ]
}

# =============================================================================
# Plan + Apply
# =============================================================================

print_plan() {
    echo "Plan"
    echo "----"
    local found=0 f

    brew_package_present && { echo "  brew uninstall $BREW_FORMULA"; found=1; }
    brew_tap_present     && { echo "  brew untap $BREW_TAP";          found=1; }

    while IFS= read -r f; do [ -n "$f" ] && { echo "  remove dir:        $f"; found=1; }; done < <(found_install_dirs)
    while IFS= read -r f; do [ -n "$f" ] && { echo "  remove binary:     $f"; found=1; }; done < <(found_binaries)
    while IFS= read -r f; do [ -n "$f" ] && { echo "  remove config:     $f"; found=1; }; done < <(found_configs)
    while IFS= read -r f; do [ -n "$f" ] && { echo "  remove data dir:   $f"; found=1; }; done < <(found_data_dirs)
    while IFS= read -r f; do [ -n "$f" ] && { echo "  remove completion: $f"; found=1; }; done < <(brew_completion_targets)
    while IFS= read -r f; do [ -n "$f" ] && { echo "  clean profile:     $f"; found=1; }; done < <(found_profile_files)

    if [ "$found" = "0" ]; then
        echo "  Nothing to do — no Manifest CLI artifacts detected."
        return 1
    fi
    return 0
}

remove_path() {
    local path="$1" privileged="${2:-no}"
    manifest_install_paths_assert_destructive_target_safe "$path" "rm" || return 1
    if [ "$privileged" = "yes" ]; then
        sudo rm -rf "$path" 2>/dev/null || rm -rf "$path" 2>/dev/null
    else
        rm -rf "$path" 2>/dev/null
    fi
}

apply_plan() {
    local errors=0 f privileged backup tmp

    if brew_package_present; then
        if ! manifest_install_paths_assert_destructive_brew_safe "brew uninstall manifest"; then
            print_warning "brew uninstall skipped by sandbox tripwire"
            errors=$((errors + 1))
        else
            print_status "Uninstalling Homebrew package..."
            if brew uninstall "$BREW_FORMULA" 2>/dev/null || brew uninstall manifest 2>/dev/null; then
                print_success "Removed Homebrew package"
            else
                print_warning "brew uninstall failed (continuing)"
                errors=$((errors + 1))
            fi
        fi
    fi

    if brew_tap_present; then
        if ! manifest_install_paths_assert_destructive_brew_safe "brew untap $BREW_TAP"; then
            print_warning "brew untap skipped by sandbox tripwire"
        else
            print_status "Untapping $BREW_TAP..."
            if brew untap "$BREW_TAP" 2>/dev/null; then
                print_success "Untapped $BREW_TAP"
            else
                print_warning "brew untap failed (continuing)"
            fi
        fi
    fi

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        privileged="no"; case "$f" in /usr/local/*|/opt/*) privileged="yes" ;; esac
        if remove_path "$f" "$privileged"; then
            print_success "Removed $f"
        else
            print_warning "Could not remove $f"; errors=$((errors + 1))
        fi
    done < <(found_install_dirs)

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        privileged="no"; case "$f" in /usr/local/*|/opt/*) privileged="yes" ;; esac
        if remove_path "$f" "$privileged"; then
            print_success "Removed $f"
        else
            print_warning "Could not remove $f"; errors=$((errors + 1))
        fi
    done < <(found_binaries)

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if remove_path "$f" "no"; then
            print_success "Removed $f"
        else
            print_warning "Could not remove $f"; errors=$((errors + 1))
        fi
    done < <(found_configs)

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if remove_path "$f" "no"; then
            print_success "Removed $f"
        else
            print_warning "Could not remove $f"; errors=$((errors + 1))
        fi
    done < <(found_data_dirs)

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if ! manifest_install_paths_assert_destructive_target_safe "$f" "rm completion"; then
            errors=$((errors + 1))
            continue
        fi
        if rm -f "$f" 2>/dev/null; then
            print_success "Removed $f"
        else
            print_warning "Could not remove $f"; errors=$((errors + 1))
        fi
    done < <(brew_completion_targets)

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if ! manifest_install_paths_assert_destructive_target_safe "$f" "profile-rewrite"; then
            continue
        fi
        backup="${f}.manifest-backup-$(date +%Y%m%d-%H%M%S)"
        tmp="$(mktemp)"
        cp "$f" "$backup"
        grep -v -E "$PROFILE_LINE_REGEX" "$f" > "$tmp" 2>/dev/null || true
        if cmp -s "$f" "$tmp"; then
            rm -f "$tmp" "$backup"
        else
            mv "$tmp" "$f"
            print_success "Cleaned $f (backup: $backup)"
        fi
    done < <(found_profile_files)

    return $errors
}

verify_clean() {
    echo ""
    echo "Verification"
    echo "------------"
    local remaining=0 f

    if brew_package_present; then
        print_warning "Still present: Homebrew package $BREW_FORMULA"
        remaining=$((remaining + 1))
    fi
    if brew_tap_present; then
        print_warning "Still present: Homebrew tap $BREW_TAP"
        remaining=$((remaining + 1))
    fi
    while IFS= read -r f; do [ -n "$f" ] && { print_warning "Still present: $f"; remaining=$((remaining + 1)); }; done < <(found_install_dirs)
    while IFS= read -r f; do [ -n "$f" ] && { print_warning "Still present: $f"; remaining=$((remaining + 1)); }; done < <(found_binaries)
    while IFS= read -r f; do [ -n "$f" ] && { print_warning "Still present: $f"; remaining=$((remaining + 1)); }; done < <(found_configs)
    while IFS= read -r f; do [ -n "$f" ] && { print_warning "Still present: $f"; remaining=$((remaining + 1)); }; done < <(found_data_dirs)
    while IFS= read -r f; do [ -n "$f" ] && { print_warning "Still present: $f"; remaining=$((remaining + 1)); }; done < <(brew_completion_targets)
    while IFS= read -r f; do [ -n "$f" ] && { print_warning "Profile entries remain in: $f"; remaining=$((remaining + 1)); }; done < <(found_profile_files)

    if [ "$remaining" = "0" ]; then
        print_success "All Manifest CLI artifacts removed."
        return 0
    fi
    print_error "$remaining artifact(s) remain — see above."
    return 1
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo
    print_header "============================================================================="
    print_header "🧹 Manifest CLI Uninstaller"
    print_header "============================================================================="
    echo

    if ! print_plan; then
        echo ""
        exit 0
    fi

    if [ "$APPLY" = "0" ]; then
        echo ""
        echo "No changes written. Re-run with -y to apply this plan:"
        echo "  ./uninstall-cli.sh -y"
        exit 0
    fi

    echo ""
    apply_plan
    local apply_errors=$?
    if [ "$apply_errors" -ne 0 ]; then
        print_warning "Encountered $apply_errors removal error(s) — see above"
    fi

    if verify_clean; then
        echo ""
        print_status "💡 Restart your terminal (or 'source ~/.zshrc' / equivalent) for shell-profile changes to take effect."
        exit 0
    else
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
else
    print_warning "⚠️  This script is designed to be executed, not sourced"
    print_warning "   Please run: ./uninstall-cli.sh"
fi
