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
  - Data: ~/.manifest-agent, \$TMPDIR/manifest-cli, /tmp/manifest-cli
  - Shell completions: brew bash/zsh completion targets
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
    "$HOME/.manifest-agent"
    "${TMPDIR:-/tmp}/manifest-cli"
)
[ "/tmp/manifest-cli" != "${TMPDIR:-/tmp}/manifest-cli" ] && DATA_DIRS+=("/tmp/manifest-cli")
SHELL_PROFILES=(
    "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zsh_profile"
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"
)
PROFILE_LINE_REGEX='^[[:space:]]*(export[[:space:]]+MANIFEST_[A-Z_]+=|export[[:space:]]+PATH=.*\.manifest-cli|export[[:space:]]+PATH=.*\.local/bin.*PATH|(\.|source)[[:space:]]+.*manifest)'

# =============================================================================
# Detection
# =============================================================================

# A binary is "ours" if it carries a Manifest CLI marker, lives in a known
# install dir, or matches the installer default path. Prevents nuking an
# unrelated `manifest` binary that happens to share the name.
is_owned_binary() {
    local path="$1" resolved d
    [ -f "$path" ] || return 1
    case "$path" in
        "$HOME/.local/bin/manifest") return 0 ;;
    esac
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

brew_completion_targets() {
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
    command -v brew >/dev/null 2>&1 || return 1
    brew list fidenceio/tap/manifest >/dev/null 2>&1 || brew list manifest >/dev/null 2>&1
}

brew_tap_present() {
    command -v brew >/dev/null 2>&1 || return 1
    local p; p="$(brew --prefix 2>/dev/null || true)"
    [ -n "$p" ] && [ -d "$p/Library/Taps/fidenceio/homebrew-tap" ]
}

# =============================================================================
# Plan + Apply
# =============================================================================

print_plan() {
    echo "Plan"
    echo "----"
    local found=0 f

    brew_package_present && { echo "  brew uninstall fidenceio/tap/manifest"; found=1; }
    brew_tap_present     && { echo "  brew untap fidenceio/tap";              found=1; }

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
    if [ "$privileged" = "yes" ]; then
        sudo rm -rf "$path" 2>/dev/null || rm -rf "$path" 2>/dev/null
    else
        rm -rf "$path" 2>/dev/null
    fi
}

apply_plan() {
    local errors=0 f privileged backup tmp

    if brew_package_present; then
        print_status "Uninstalling Homebrew package..."
        if brew uninstall fidenceio/tap/manifest 2>/dev/null || brew uninstall manifest 2>/dev/null; then
            print_success "Removed Homebrew package"
        else
            print_warning "brew uninstall failed (continuing)"
            errors=$((errors + 1))
        fi
    fi

    if brew_tap_present; then
        print_status "Untapping fidenceio/tap..."
        if brew untap fidenceio/tap 2>/dev/null; then
            print_success "Untapped fidenceio/tap"
        else
            print_warning "brew untap failed (continuing)"
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
        if rm -f "$f" 2>/dev/null; then
            print_success "Removed $f"
        else
            print_warning "Could not remove $f"; errors=$((errors + 1))
        fi
    done < <(brew_completion_targets)

    while IFS= read -r f; do
        [ -n "$f" ] || continue
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
        print_warning "Still present: Homebrew package fidenceio/tap/manifest"
        remaining=$((remaining + 1))
    fi
    if brew_tap_present; then
        print_warning "Still present: Homebrew tap fidenceio/tap"
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
