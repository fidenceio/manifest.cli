#!/bin/bash
# Manifest CLI installer.
#
# Validates the host (centralized requirements, Git, Docker), copies the CLI tree to
# ~/.manifest-cli, configures PATH, sets up the global YAML config, and
# optionally installs a pre-commit security hook in the current repo.
#
# Run from the repo root:  ./install-cli.sh
# Or via Homebrew:          brew install fidenceio/tap/manifest
# To install from THIS source tree (skip Homebrew routing): ./install-cli.sh --manual

set -e

# Re-exec under Bash 5+ if the running interpreter is older.
# macOS ships /bin/bash 3.2, which lacks associative arrays (declare -gA) used
# by the YAML module. Honor PATH so Homebrew's bash 5+ is picked up automatically;
# otherwise fail with the same "need Bash 5+" message the validator uses.
if [ -z "${MANIFEST_CLI_INSTALL_REEXEC:-}" ] && [ "${BASH_VERSINFO[0]:-0}" -lt 5 ]; then
    _better_bash="$(command -v bash 2>/dev/null || true)"
    if [ -n "$_better_bash" ] && [ "$_better_bash" != "${BASH:-/bin/bash}" ]; then
        _better_major="$("$_better_bash" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)"
        if [ "$_better_major" -ge 5 ]; then
            export MANIFEST_CLI_INSTALL_REEXEC=1
            exec "$_better_bash" "$0" "$@"
        fi
    fi
    echo "❌ Bash ${BASH_VERSION:-unknown} detected. Manifest CLI requires Bash 5.0+." >&2
    echo "   Install:  brew install bash   (then re-run: ./install-cli.sh)" >&2
    exit 1
fi

# =============================================================================
# Configuration & Constants
# =============================================================================

# Colors for rich output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Version requirements + canonical install paths
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/modules/core/manifest-requirements.sh"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/modules/system/manifest-install-paths.sh"

# Installation paths (derived from manifest-install-paths.sh)
MANIFEST_CLI_LOCAL_BIN="$(manifest_install_paths_user_bin_dir)"
MANIFEST_CLI_NAME="manifest"
MANIFEST_CLI_IDE_SUPPORT_DIR="$(manifest_install_paths_global_state_dir)/ide"

# Function to determine the best installation directory
get_install_location() {
    if [ -n "$MANIFEST_CLI_INSTALL_LOCATION" ]; then
        echo "$MANIFEST_CLI_INSTALL_LOCATION"
        return 0
    fi
    manifest_install_paths_global_state_dir
}

# Set the actual installation directory
MANIFEST_CLI_INSTALL_LOCATION="$(get_install_location)"

# =============================================================================
# Utility Functions
# =============================================================================

# Print colored status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BOLD}${CYAN}$1${NC}"
}

print_subheader() {
    echo -e "${BOLD}${PURPLE}$1${NC}"
}

# Check if command exists
# Print the right install command for the current OS/distro for a given pkg.
# Pkg names: bash, yq, git, curl, docker, coreutils. Falls back to a documentation URL.
_install_hint() {
    local pkg="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [[ "$pkg" == "docker" ]]; then
            echo "brew install --cask docker"
            return
        fi
        echo "brew install $pkg"; return
    fi
    if command -v apt-get >/dev/null 2>&1; then
        case "$pkg" in
            yq) echo "sudo snap install yq  OR  see https://github.com/mikefarah/yq#install" ;;
            docker) echo "see https://docs.docker.com/engine/install/" ;;
            coreutils) echo "sudo apt-get install coreutils" ;;
            *)  echo "sudo apt-get install $pkg" ;;
        esac
        return
    fi
    if command -v dnf >/dev/null 2>&1; then
        [[ "$pkg" == "docker" ]] && echo "see https://docs.docker.com/engine/install/" || echo "sudo dnf install $pkg"
        return
    fi
    if command -v yum >/dev/null 2>&1; then
        [[ "$pkg" == "docker" ]] && echo "see https://docs.docker.com/engine/install/" || echo "sudo yum install $pkg"
        return
    fi
    if command -v zypper >/dev/null 2>&1; then
        [[ "$pkg" == "docker" ]] && echo "see https://docs.docker.com/engine/install/" || echo "sudo zypper install $pkg"
        return
    fi
    if command -v apk >/dev/null 2>&1; then
        [[ "$pkg" == "docker" ]] && echo "see https://docs.docker.com/engine/install/" || echo "sudo apk add $pkg"
        return
    fi
    if command -v pacman >/dev/null 2>&1; then
        case "$pkg" in
            yq) echo "sudo pacman -S go-yq" ;;
            docker) echo "sudo pacman -S docker && sudo systemctl enable --now docker" ;;
            coreutils) echo "sudo pacman -S coreutils" ;;
            *)  echo "sudo pacman -S $pkg" ;;
        esac
        return
    fi
    case "$pkg" in
        yq) echo "see your distro's package manager or https://github.com/mikefarah/yq#install" ;;
        docker) echo "see https://docs.docker.com/engine/install/" ;;
        coreutils) echo "see your distro's coreutils package" ;;
        *) echo "see your distro's package manager" ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

print_docker_help() {
    print_error "   Install:  $(_install_hint docker)"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        print_error "   Start:    open -a Docker"
        print_error "   Verify:   docker info"
    elif command_exists systemctl; then
        print_error "   Start:    sudo systemctl enable --now docker"
        print_error "   Verify:   docker info"
    else
        print_error "   Start Docker, then verify with: docker info"
    fi
}

ensure_docker_installed() {
    if manifest_requirement_docker_command_exists; then
        return 0
    fi

    if [[ "$OSTYPE" == "darwin"* ]] && command_exists brew; then
        print_status "🐳 Docker is required and is not installed"
        print_status "Docker Desktop can be installed via Homebrew cask."
        echo ""
        read -p "   Install Docker Desktop now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            print_status "Installing Docker Desktop..."
            if brew install --cask docker; then
                print_success "✅ Docker Desktop installed"
                print_status "Start Docker Desktop before continuing:"
                print_status "   open -a Docker"
            else
                print_error "❌ Docker Desktop installation failed"
                return 1
            fi
        else
            print_status "Skipping Docker installation"
        fi
        echo ""
    fi
}

# Cross-platform in-place sed
# BSD sed (macOS, FreeBSD, OpenBSD, NetBSD) requires -i ''
# GNU sed (Linux, WSL2, Git Bash/MSYS2, Cygwin) requires -i without argument
sed_inplace() {
    case "$OSTYPE" in
        darwin*|freebsd*|openbsd*|netbsd*)
            sed -i '' "$@" ;;
        *)
            sed -i "$@" ;;
    esac
}

migrate_user_global_configuration() {
    local config_file
    config_file="$(manifest_install_paths_user_global_config)"
    [ -f "$config_file" ] || return 0

    # Source the YAML module for get_yaml_value / set_yaml_value
    local yaml_module
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    yaml_module="$script_dir/modules/core/manifest-yaml.sh"
    if [[ -f "$yaml_module" ]]; then
        source "$yaml_module"
    elif [[ -f "$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh" ]]; then
        source "$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh"
    else
        print_warning "⚠️  YAML module not found, skipping configuration migration"
        return 0
    fi

    print_subheader "🧭 Migrating User Configuration (Safe Merge)"

    local migrated=0

    # get_yaml_value with explicit "" default keeps the migration safe under
    # `set -e`: a missing key returns "" rc=0 rather than rc=1, which would
    # otherwise abort the installer on a fresh config file that doesn't yet
    # carry the legacy keys this function is checking for.
    local time1 time2 time3 time4 tap_repo
    time1=$(get_yaml_value "$config_file" ".time.server1" "")
    time2=$(get_yaml_value "$config_file" ".time.server2" "")
    time3=$(get_yaml_value "$config_file" ".time.server3" "")
    time4=$(get_yaml_value "$config_file" ".time.server4" "")
    tap_repo=$(get_yaml_value "$config_file" ".brew.tap_repo" "")

    # Migrate only known legacy defaults; preserve user custom values.
    if [ "$time1" = "time.apple.com" ] || [ "$time1" = "216.239.35.0" ]; then
        set_yaml_value "$config_file" ".time.server1" "https://www.cloudflare.com/cdn-cgi/trace"
        migrated=$((migrated + 1))
    fi
    if [ "$time2" = "time.google.com" ] || [ "$time2" = "216.239.35.4" ]; then
        set_yaml_value "$config_file" ".time.server2" "https://www.google.com/generate_204"
        migrated=$((migrated + 1))
    fi
    if [ "$time3" = "pool.ntp.org" ]; then
        set_yaml_value "$config_file" ".time.server3" "https://www.apple.com"
        migrated=$((migrated + 1))
    fi
    if [ "$time4" = "time.nist.gov" ]; then
        set_yaml_value "$config_file" ".time.server4" ""
        migrated=$((migrated + 1))
    fi
    if [ "$tap_repo" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        set_yaml_value "$config_file" ".brew.tap_repo" "https://github.com/fidenceio/homebrew-tap.git"
        migrated=$((migrated + 1))
    fi

    # Ensure new cache controls exist.
    local cache_ttl cache_cleanup cache_stale
    cache_ttl=$(get_yaml_value "$config_file" ".time.cache_ttl" "")
    if [ -z "$cache_ttl" ]; then
        set_yaml_value "$config_file" ".time.cache_ttl" "120"
        migrated=$((migrated + 1))
    fi
    cache_cleanup=$(get_yaml_value "$config_file" ".time.cache_cleanup_period" "")
    if [ -z "$cache_cleanup" ]; then
        set_yaml_value "$config_file" ".time.cache_cleanup_period" "3600"
        migrated=$((migrated + 1))
    fi
    cache_stale=$(get_yaml_value "$config_file" ".time.cache_stale_max_age" "")
    if [ -z "$cache_stale" ]; then
        set_yaml_value "$config_file" ".time.cache_stale_max_age" "21600"
        migrated=$((migrated + 1))
    fi

    if [ "$migrated" -gt 0 ]; then
        print_success "✅ Migrated $migrated configuration setting(s) in $config_file"
    else
        print_status "ℹ️  No user config migrations needed"
    fi
    echo ""
}

# Get system information
get_system_info() {
    print_subheader "🔍 System Information"
    local os shell_name bash_ver
    if [[ "$OSTYPE" == "darwin"* ]]; then
        os="macOS $(sw_vers -productVersion 2>/dev/null || echo "")"
    elif command_exists lsb_release; then
        os="$(lsb_release -si) $(lsb_release -sr)"
    else
        os="$OSTYPE"
    fi
    shell_name="$(basename "$SHELL")"
    # Report the running interpreter, not whatever `bash` happens to resolve to on PATH.
    bash_ver="${BASH_VERSION%%[!0-9.]*}"
    echo "   🖥️  OS: $os"
    echo "   🐚 Shell: $shell_name"
    echo "   🐍 Bash: ${bash_ver:-not installed}"
    echo ""
}

# Validate system requirements
validate_system() {
    print_subheader "🔍 System Requirements Validation"
    
    local errors=0
    
    # Check if we're in the right directory
    if [ ! -f "scripts/manifest-cli-wrapper.sh" ]; then
        print_error "❌ This script must be run from the manifest.cli project root directory"
        print_error "   Please navigate to the project root and try again"
        errors=$((errors + 1))
    fi
    
    # Bash
    if command_exists bash; then
        local bash_ver
        bash_ver=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
        if ! manifest_requirement_bash_is_supported_major "$(manifest_requirement_semver_major "$bash_ver")"; then
            print_error "❌ Bash $bash_ver detected. Manifest CLI requires Bash ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+."
            print_error "   Install:  $(_install_hint bash)"
            errors=$((errors + 1))
        else
            print_success "✅ Bash $bash_ver"
        fi
    else
        print_error "❌ Bash is not installed or not in PATH"
        errors=$((errors + 1))
    fi

    # yq
    if command_exists yq && manifest_requirement_yq_is_supported yq; then
        local yq_ver
        yq_ver=$(manifest_requirement_yq_version_text yq)
        print_success "✅ yq $yq_ver"
    else
        print_error "❌ ${MANIFEST_CLI_REQUIRED_YQ_LABEL} required for YAML config."
        print_error "   Install:  $(_install_hint yq)"
        errors=$((errors + 1))
    fi

    # Git
    if command_exists git; then
        print_success "✅ git is available"
    else
        print_error "❌ Git is required for Manifest repo operations."
        print_error "   Install:  $(_install_hint git)"
        errors=$((errors + 1))
    fi

    # coreutils
    if manifest_requirement_coreutils_timeout_command; then
        print_success "✅ ${MANIFEST_CLI_REQUIRED_COREUTILS_LABEL} is available"
    else
        print_error "❌ ${MANIFEST_CLI_REQUIRED_COREUTILS_LABEL} is required."
        print_error "   Install:  $(_install_hint coreutils)"
        errors=$((errors + 1))
    fi

    # Docker
    if ! manifest_requirement_docker_command_exists; then
        print_error "❌ ${MANIFEST_CLI_REQUIRED_DOCKER_LABEL} is required."
        print_docker_help
        errors=$((errors + 1))
    elif ! manifest_requirement_docker_engine_is_running; then
        print_error "❌ Docker is installed, but the Docker engine is not running or not reachable."
        print_docker_help
        errors=$((errors + 1))
    else
        print_success "✅ Docker is installed and running"
    fi

    # Check for useful commands
    local recommended_commands=("curl" "wget")
    for cmd in "${recommended_commands[@]}"; do
        if command_exists "$cmd"; then
            print_success "✅ $cmd is available"
        else
            print_warning "⚠️  $cmd is not available (some features may be limited)"
        fi
    done
    
    if [ $errors -gt 0 ]; then
        print_error "❌ System validation failed with $errors error(s)"
        exit 1
    fi
    
    print_success "✅ System validation passed"
    echo ""
}

# =============================================================================
# Installation Functions
# =============================================================================

# Source the uninstall module for cleanup
# Load shared utils + uninstall module from this script's modules/ tree.
# Returns 0 if both available, 1 otherwise (printing an error).
source_manifest_uninstall() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [ -f "$script_dir/modules/core/manifest-shared-utils.sh" ] \
        && source "$script_dir/modules/core/manifest-shared-utils.sh"
    if [ -f "$script_dir/modules/system/manifest-uninstall.sh" ]; then
        source "$script_dir/modules/system/manifest-uninstall.sh"
    else
        print_error "❌ Uninstall module not found: $script_dir/modules/system/manifest-uninstall.sh"
        return 1
    fi
}

# Strip MANIFEST_* exports and manifest-related source/PATH lines from shell
# profiles. Delegates to the canonical impl in manifest-install-paths.sh so
# the regex, tripwire, and backup pattern live in one place. Called once
# before installing to remove residue from previous installs.
cleanup_environment_variables() {
    print_subheader "🧹 Cleaning Up Manifest CLI Shell-Profile Entries"
    manifest_install_paths_cleanup_profile_entries 0 0
}

# Clean up legacy installation locations
cleanup_legacy_locations() {
    print_subheader "🧹 Cleaning Up Legacy Installation Locations"

    local legacy_location
    legacy_location="$(manifest_install_paths_legacy_install_dir)"

    if [ -d "$legacy_location" ]; then
        print_status "Found legacy installation at: $legacy_location"
        if ! manifest_install_paths_assert_destructive_target_safe "$legacy_location" "rm legacy-location"; then
            print_warning "⚠️  Skipped removal of $legacy_location (sandbox tripwire)"
        # Try with sudo since it's a system location
        elif sudo rm -rf "$legacy_location" 2>/dev/null; then
            print_success "✅ Removed legacy installation: $legacy_location"
        else
            print_warning "⚠️  Could not remove $legacy_location (may need manual cleanup)"
        fi
    else
        print_status "No legacy installations found"
    fi

    print_success "✅ Legacy location cleanup completed"
}

# Clean up stray legacy installation artifacts at the install root.
#
# This runs ONLY on a fresh install (mode=fresh) when stray shipped
# artifacts are detected at the top level of $HOME/.manifest-cli/ from
# a pre-§5.7 flat install. It must NEVER invoke uninstall_manifest —
# that helper's blast radius (shell profiles, env vars, user state) is
# the root cause of the partial-state-on-interrupt defect §5.7 fixes.
#
# Scope (explicit allowlist of shipped artifacts):
#   - modules/, docs/, examples/, completions/, VERSION
#
# Untouched (USER STATE — preserved across installs/upgrades):
#   - logs/, audit/, ide/, manifest.config.global.yaml, current,
#     runtime/, .install.lock, anything else
cleanup_legacy_installation() {
    print_subheader "🧹 Cleaning Up Stray Legacy Artifacts"

    # First, clean up any legacy /usr/local install location.
    cleanup_legacy_locations

    local state_dir
    state_dir="$(manifest_install_paths_global_state_dir)"
    [ -d "$state_dir" ] || { print_status "No stray artifacts found"; return 0; }

    local artifact name path
    local artifacts=(modules docs examples completions VERSION)
    local removed=0
    for name in "${artifacts[@]}"; do
        path="$state_dir/$name"
        if [ -e "$path" ]; then
            if manifest_install_paths_assert_destructive_target_safe "$path" "rm legacy-artifact"; then
                rm -rf "$path"
                print_success "✅ Removed stray $path"
                removed=$((removed + 1))
            else
                print_warning "⚠️  Skipped removal of $path (sandbox tripwire)"
            fi
        fi
    done
    if [ "$removed" -eq 0 ]; then
        print_status "No stray shipped artifacts at $state_dir"
    fi
    echo ""
}

# Create the stable state-root tree under $HOME/.manifest-cli/.
#
# This dir hierarchy is user-visible and never renamed — only the
# `current` symlink and `runtime/v<X>/` subdirs are swapped on upgrade.
# User-state subdirs (logs/, audit/, ide/) and $HOME/.local/bin/ live
# here permanently. Idempotent; safe to invoke on every run.
create_state_root() {
    print_subheader "📁 Creating State Root"

    if [ ! -d "$MANIFEST_CLI_LOCAL_BIN" ]; then
        mkdir -p "$MANIFEST_CLI_LOCAL_BIN"
        print_success "✅ Created $MANIFEST_CLI_LOCAL_BIN"
    fi

    local state_dir preserved
    state_dir="$(manifest_install_paths_global_state_dir)"
    mkdir -p "$state_dir"
    while IFS= read -r preserved; do
        [ -n "$preserved" ] || continue
        mkdir -p "$state_dir/$preserved"
    done < <(manifest_install_paths_preserved_subdirs)

    print_success "✅ State root ready at $state_dir"
    echo ""
}

# Copy shipped artifacts from the install-cli.sh source tree into a
# target staging directory. The wrapper binary (~/.local/bin/manifest)
# is written separately in main() because it lives outside the swap
# target and is version-agnostic.
#
# Arguments:
#   $1  target staging dir for shipped artifacts (modules/, docs/, …)
copy_cli_files() {
    local target="$1"

    if [ -z "$target" ]; then
        print_error "❌ copy_cli_files: target staging dir required"
        exit 1
    fi

    print_subheader "📦 Staging CLI Files → $target"

    local source_dir
    source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    mkdir -p "$target"

    if [ -d "$source_dir/modules" ]; then
        cp -r "$source_dir/modules" "$target/"
        print_success "✅ Staged modules"
    fi

    if [ -f "$source_dir/VERSION" ]; then
        cp "$source_dir/VERSION" "$target/"
        print_success "✅ Staged VERSION"
    fi

    if [ -d "$source_dir/docs" ]; then
        cp -r "$source_dir/docs" "$target/"
        print_success "✅ Staged docs"
    fi

    if [ -d "$source_dir/examples" ]; then
        cp -r "$source_dir/examples" "$target/"
        print_success "✅ Staged examples"
    fi

    if [ -d "$source_dir/completions" ]; then
        cp -r "$source_dir/completions" "$target/"
        print_success "✅ Staged completions"
    fi

    print_success "✅ Staging complete"
    echo ""
}

# True if the source wrapper script and the installed binary have the
# same sha256 content. Used by upgrade flow to skip rewriting the
# wrapper binary when nothing changed.
_wrapper_binaries_match() {
    local src="$1"
    local dst="$2"
    [ -f "$src" ] && [ -f "$dst" ] || return 1

    local hasher
    if command -v shasum >/dev/null 2>&1; then
        hasher="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then
        hasher="sha256sum"
    else
        return 1
    fi

    local h_src h_dst
    h_src="$($hasher "$src" 2>/dev/null | awk '{print $1}')"
    h_dst="$($hasher "$dst" 2>/dev/null | awk '{print $1}')"
    [ -n "$h_src" ] && [ "$h_src" = "$h_dst" ]
}

# =============================================================================
# §5.7 Atomic Upgrade Mechanism
# =============================================================================

# Hook used exclusively by Phase 3 tests to simulate failure at a specific
# phase. Returns 1 with a stderr marker if the env var matches the named
# phase. No-op in production runs.
_manifest_install_fail_at() {
    local phase="$1"
    if [ "${MANIFEST_CLI_INSTALL_FAIL_AT:-}" = "$phase" ]; then
        echo "manifest: simulated failure at $phase" >&2
        return 1
    fi
    return 0
}

# Classify the current install state. Echo one of:
#   legacy-migration  — pre-§5.7 flat layout present, `current` absent
#   upgrade           — `current` symlink OR runtime/ tree present
#   fresh             — neither
detect_install_mode() {
    local state_dir current runtime
    state_dir="$(manifest_install_paths_global_state_dir)"
    current="$(manifest_install_paths_current_symlink)"
    runtime="$(manifest_install_paths_runtime_root)"

    if [ -d "$state_dir/modules" ] && [ ! -L "$current" ] && [ ! -e "$current" ]; then
        echo "legacy-migration"
        return 0
    fi
    if [ -L "$current" ] || [ -d "$runtime" ]; then
        echo "upgrade"
        return 0
    fi
    echo "fresh"
}

# Path of the install-time lock file. Co-located with the install root so a
# stale lock from a crashed installer is visible alongside the partial
# install state it may have left behind.
_manifest_install_lock_path() {
    echo "$(manifest_install_paths_global_state_dir)/.install.lock"
}

# Race-free pid-file lock using set -C (noclobber). If a lock already
# exists, the holder pid is examined via kill -0; a stale lock is
# overwritten with a stderr warning. Lock content: "<pid>\n<iso-ts>\n".
acquire_install_lock() {
    local lock pid stale
    lock="$(_manifest_install_lock_path)"
    mkdir -p "$(dirname "$lock")"

    if [ -e "$lock" ]; then
        pid="$(head -n1 "$lock" 2>/dev/null || true)"
        stale=1
        if [ -n "$pid" ] && [ "$pid" -eq "$pid" ] 2>/dev/null; then
            if kill -0 "$pid" 2>/dev/null; then
                stale=0
            fi
        fi
        if [ "$stale" -eq 0 ]; then
            print_error "❌ Another manifest install is already in progress (pid $pid, lock $lock)."
            print_error "   If you're sure no other installer is running, remove $lock and retry."
            return 1
        fi
        echo "manifest: warning: stale install lock from pid ${pid:-?} found at $lock — overwriting" >&2
        rm -f "$lock"
    fi

    # set -C makes the redirect fail if the file appears between our check
    # and the write — closing the TOCTOU window for two concurrent installs.
    (
        set -C
        : > "$lock"
    ) || {
        print_error "❌ Failed to create install lock at $lock (race or permission)"
        return 1
    }
    {
        echo "$$"
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    } > "$lock"
    _MANIFEST_CLI_INSTALL_LOCK_HELD="$lock"
    return 0
}

# Release the lock only if it still names our pid. Defensive against a
# trap firing after a swap left the lock in a half-known state.
release_install_lock() {
    local lock pid
    lock="${_MANIFEST_CLI_INSTALL_LOCK_HELD:-$(_manifest_install_lock_path)}"
    [ -f "$lock" ] || return 0
    pid="$(head -n1 "$lock" 2>/dev/null || true)"
    if [ "$pid" = "$$" ]; then
        rm -f "$lock"
    fi
}

# Stage all shipped artifacts into runtime/v<version>.tmp/ then atomically
# rename to runtime/v<version>/. A pre-existing .tmp is a leftover from a
# prior interrupted run — remove it and retry.
stage_version_dir() {
    local version="$1"
    [ -n "$version" ] || { print_error "❌ stage_version_dir: version required"; return 1; }

    _manifest_install_fail_at "stage_version_dir" || return 1

    local final_dir staging_dir
    final_dir="$(manifest_install_paths_versioned_dir "$version")"
    staging_dir="${final_dir}.tmp"

    mkdir -p "$(dirname "$final_dir")"

    # Idempotent re-run: a leftover staging dir from a prior interrupted
    # install must be removed before we restart. Gated by the tripwire.
    if [ -d "$staging_dir" ]; then
        if manifest_install_paths_assert_destructive_target_safe "$staging_dir" "rm staging"; then
            rm -rf "$staging_dir"
        else
            return 1
        fi
    fi

    # If the final dir already exists for this version, treat as no-op.
    # (Re-running the installer for the already-installed version should
    # not blow away a live install we're presumably symlinked to.)
    if [ -d "$final_dir" ]; then
        print_status "ℹ️  Version dir already present at $final_dir — skipping stage"
        return 0
    fi

    copy_cli_files "$staging_dir"

    # Atomic same-fs rename — the single point where the new dir becomes
    # visible under its final name. After this returns, swap_current_symlink
    # is the only remaining step in the upgrade window.
    mv "$staging_dir" "$final_dir"
    print_success "✅ Staged $final_dir"
    echo ""
}

# Atomically point ~/.manifest-cli/current at runtime/v<version>/. Uses a
# write-to-sibling + rename-over-target pattern so a SIGTERM mid-call
# leaves the prior symlink intact (it's either the old target or the
# new target, never broken).
#
# The symlink target is RELATIVE so the install dir stays relocatable.
swap_current_symlink() {
    local version="$1"
    [ -n "$version" ] || { print_error "❌ swap_current_symlink: version required"; return 1; }

    _manifest_install_fail_at "swap_current_symlink" || return 1

    local state_dir vdirname new_link current_link
    state_dir="$(manifest_install_paths_global_state_dir)"
    case "$version" in
        v*) vdirname="$version" ;;
        *)  vdirname="v$version" ;;
    esac
    new_link="$state_dir/current.new"
    current_link="$state_dir/current"

    # Drop a stale .new from a prior interrupted swap.
    [ -L "$new_link" ] && rm -f "$new_link"

    # Atomic swap pattern:
    #   1. Create a fresh symlink at current.new (pointing at the new target)
    #   2. rename(2) it over current
    #
    # rename(2) of one symlink-to-X over another symlink is atomic and does
    # NOT follow either link. We invoke it via `mv -fh` on BSD (Darwin) so
    # mv treats the destination as a file even when it's a symlink-to-dir;
    # GNU mv has no -h flag but defaults to the file-replace semantics we
    # want, so we feature-detect.
    #
    # NB: BSD `mv` without -h, when the dst is a symlink-to-dir, will move
    # INTO that directory (the very bug §5.7 is supposed to avoid). The -h
    # detection guards against that.
    ln -sfn "runtime/$vdirname" "$new_link"
    if mv -h "$new_link" "$current_link" 2>/dev/null; then
        :
    else
        # GNU mv: no -h, but its default rename semantics do not follow a
        # symlink at the destination, so a plain `mv -f` is the right
        # primitive on Linux.
        mv -f "$new_link" "$current_link"
    fi
    print_success "✅ Pointed $current_link → runtime/$vdirname"
    echo ""
}

# Keep `keep_n` versions under runtime/: the one currently pointed to by
# `current`, plus (keep_n - 1) most recently modified other version dirs.
# Anything else is removed. Default keep_n=2.
prune_old_versions() {
    local keep_n="${1:-2}"

    _manifest_install_fail_at "prune_old_versions" || return 1

    local runtime current_target state_dir
    state_dir="$(manifest_install_paths_global_state_dir)"
    runtime="$(manifest_install_paths_runtime_root)"
    [ -d "$runtime" ] || return 0

    # Resolve the currently-active version directory NAME (basename, since
    # `current` stores a relative target like runtime/v<X>).
    current_target=""
    if [ -L "$state_dir/current" ]; then
        current_target="$(basename "$(readlink "$state_dir/current")")"
    fi

    # Collect candidate version dir basenames sorted by mtime, newest first.
    local -a all_versions=()
    local entry name
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        name="$(basename "$entry")"
        case "$name" in v*) all_versions+=("$name") ;; esac
    done < <(
        # `ls -td` orders by mtime (newest first); fall back to a stat sort
        # if -t is unavailable (extremely rare on POSIX hosts).
        ls -dt "$runtime"/v* 2>/dev/null || true
    )

    # Build the keep-set: always include current_target; then take from the
    # mtime-sorted list until we hit keep_n total.
    local -a keep=()
    [ -n "$current_target" ] && keep+=("$current_target")
    local v
    for v in "${all_versions[@]}"; do
        if [ "${#keep[@]}" -ge "$keep_n" ]; then break; fi
        local already=0
        local k
        for k in "${keep[@]}"; do
            [ "$k" = "$v" ] && { already=1; break; }
        done
        [ "$already" -eq 0 ] && keep+=("$v")
    done

    # rm anything not in keep[].
    for v in "${all_versions[@]}"; do
        local in_keep=0
        local k
        for k in "${keep[@]}"; do
            [ "$k" = "$v" ] && { in_keep=1; break; }
        done
        if [ "$in_keep" -eq 0 ]; then
            local victim="$runtime/$v"
            if manifest_install_paths_assert_destructive_target_safe "$victim" "rm old-version"; then
                rm -rf "$victim"
                print_success "✅ Pruned $victim"
            fi
        fi
    done
}

# Migrate a pre-§5.7 flat layout into the runtime/v<X>/ scheme.
#
# Detection (caller's responsibility — detect_install_mode returns
# "legacy-migration" when this is needed): $HOME/.manifest-cli/modules/
# exists AND $HOME/.manifest-cli/current does NOT exist.
#
# Strategy: relocate only the allowlisted shipped subdirs (modules,
# docs, examples, completions, VERSION) into runtime/v<OLD_VER>/, then
# create the `current` symlink pointing at that dir. User-state subdirs
# (logs/, audit/, ide/, manifest.config.global.yaml, anything else) are
# left untouched at the top level.
#
# Version sourced from $HOME/.manifest-cli/VERSION if present; falls
# back to "0.0.0-legacy" so the dir name is deterministic and obviously
# identifies a pre-§5.7 install.
migrate_legacy_layout() {
    _manifest_install_fail_at "migrate_legacy_layout" || return 1

    print_subheader "🧭 Migrating Legacy Flat Layout"

    local state_dir old_version target
    state_dir="$(manifest_install_paths_global_state_dir)"

    if [ -f "$state_dir/VERSION" ]; then
        old_version="$(tr -d '[:space:]' < "$state_dir/VERSION")"
    fi
    [ -n "$old_version" ] || old_version="0.0.0-legacy"

    target="$(manifest_install_paths_versioned_dir "$old_version")"
    mkdir -p "$target"

    local moved=0 artifact src
    local artifacts=(modules docs examples completions VERSION)
    for artifact in "${artifacts[@]}"; do
        src="$state_dir/$artifact"
        if [ -e "$src" ]; then
            if manifest_install_paths_assert_destructive_target_safe "$src" "mv legacy-artifact"; then
                mv "$src" "$target/"
                moved=$((moved + 1))
            else
                print_warning "⚠️  Skipped move of $src (sandbox tripwire)"
            fi
        fi
    done

    # Create the relative `current` symlink. Use the same swap helper so
    # the path goes through one canonical impl.
    swap_current_symlink "$old_version"

    echo "manifest: migrated legacy flat layout → $target (moved $moved shipped subdir(s))" >&2
    echo ""
}

manifest_completion_source_dir() {
    local source_dir
    local candidates=(
        "$MANIFEST_CLI_INSTALL_LOCATION/current/completions"
        "$MANIFEST_CLI_INSTALL_LOCATION/completions"
        "$(pwd)/completions"
    )

    for source_dir in "${candidates[@]}"; do
        if [ -f "$source_dir/manifest.bash" ] && [ -f "$source_dir/_manifest" ]; then
            echo "$source_dir"
            return 0
        fi
    done

    return 1
}

install_shell_completions() {
    print_subheader "🧩 Installing Shell and IDE Terminal Completions"

    local source_dir
    if ! source_dir="$(manifest_completion_source_dir)"; then
        print_warning "⚠️  Completion files not found; skipping shell completion setup"
        echo ""
        return 0
    fi

    # install-cli.sh owns user-writable locations only. Homebrew-managed
    # directories (e.g. $(brew --prefix)/etc/bash_completion.d) belong to the
    # formula; writing there from here clobbers brew's own symlinks and breaks
    # the next `brew upgrade`. The Homebrew install path therefore skips this
    # function entirely — see formula/manifest.rb for the brew-side install.
    local bash_target="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/manifest"
    local zsh_dir="$HOME/.zsh/completions"
    local zsh_target="$zsh_dir/_manifest"

    mkdir -p "$(dirname "$bash_target")"
    ln -sf "$source_dir/manifest.bash" "$bash_target"
    print_success "✅ Bash completion installed: $bash_target"

    mkdir -p "$zsh_dir"
    ln -sf "$source_dir/_manifest" "$zsh_target"
    print_success "✅ Zsh completion installed: $zsh_target"

    print_status "Bash picks this up automatically when bash-completion is enabled."
    print_status "For Zsh, ensure your ~/.zshrc loads the directory:"
    print_status "  fpath+=$zsh_dir"
    print_status "  autoload -Uz compinit && compinit"
    echo ""
}

install_ide_command_catalog() {
    print_subheader "🧠 Installing IDE and AI Assistant Command Catalog"

    mkdir -p "$MANIFEST_CLI_IDE_SUPPORT_DIR"

    local command_catalog_md="$MANIFEST_CLI_IDE_SUPPORT_DIR/manifest-cli-commands.md"
    local command_catalog_json="$MANIFEST_CLI_IDE_SUPPORT_DIR/manifest-cli-commands.json"
    local agents_hint="$MANIFEST_CLI_IDE_SUPPORT_DIR/AGENTS.md"
    local claude_hint="$MANIFEST_CLI_IDE_SUPPORT_DIR/CLAUDE.md"

    cat > "$command_catalog_md" <<EOF
# Manifest CLI Commands

Manifest CLI is installed as \`manifest\`.

Use these first-class commands before falling back to lower-level internals:

- \`manifest doctor\` - validate dependencies, config, and repository state
- \`manifest status [repo|fleet]\` - inspect current repo or fleet state
- \`manifest init repo [--dry-run|-y]\` - scaffold repo metadata
- \`manifest init fleet [--dry-run|-y]\` - scaffold fleet inventory
- \`manifest prep repo [--dry-run|-y]\` - prepare remotes and repo metadata
- \`manifest prep fleet [--dry-run|-y]\` - prepare fleet members
- \`manifest refresh repo [--dry-run|-y]\` - refresh generated docs and metadata
- \`manifest refresh fleet [--dry-run|-y]\` - refresh fleet inventory
- \`manifest ship repo patch|minor|major|revision [--dry-run|-y]\` - preview or cut a repo release
- \`manifest ship fleet patch|minor|major|revision [--dry-run|-y]\` - preview or cut fleet releases
- \`manifest config list|get|set|unset|doctor\` - inspect and manage YAML config
- \`manifest recipe list|show|explain\` - inspect built-in workflow contracts
- \`manifest pr create|status|checks|ready|merge|update\` - GitHub PR helpers

Behavior contract:

- Mutating commands preview by default.
- Use \`--dry-run\` for explicit preview.
- Use \`-y\` or \`--yes\` to apply.
- Use \`manifest <command> --help\` for exact flags.

Installed docs:

- $MANIFEST_CLI_INSTALL_LOCATION/docs/USER_GUIDE.md
- $MANIFEST_CLI_INSTALL_LOCATION/docs/COMMAND_REFERENCE.md
- $MANIFEST_CLI_INSTALL_LOCATION/completions/README.md
EOF

    cat > "$command_catalog_json" <<'EOF'
{
  "name": "Manifest CLI",
  "binary": "manifest",
  "safe_by_default": true,
  "preview_flags": ["--dry-run"],
  "apply_flags": ["-y", "--yes"],
  "commands": [
    "manifest doctor",
    "manifest status repo",
    "manifest status fleet",
    "manifest init repo",
    "manifest init fleet",
    "manifest prep repo",
    "manifest prep fleet",
    "manifest refresh repo",
    "manifest refresh fleet",
    "manifest ship repo patch",
    "manifest ship repo minor",
    "manifest ship repo major",
    "manifest ship repo revision",
    "manifest ship fleet patch",
    "manifest ship fleet minor",
    "manifest ship fleet major",
    "manifest ship fleet revision",
    "manifest config list",
    "manifest config get",
    "manifest config set",
    "manifest config unset",
    "manifest config doctor",
    "manifest recipe list",
    "manifest recipe show",
    "manifest recipe explain",
    "manifest pr create",
    "manifest pr status",
    "manifest pr checks",
    "manifest pr ready",
    "manifest pr merge",
    "manifest pr update"
  ]
}
EOF

    cat > "$agents_hint" <<EOF
# Manifest CLI Assistant Hints

Manifest CLI is available as \`manifest\`. Prefer first-class commands such as
\`manifest status\`, \`manifest doctor\`, \`manifest init repo\`,
\`manifest prep repo\`, \`manifest refresh repo\`, and
\`manifest ship repo patch\`.

Mutating commands preview by default. Use \`--dry-run\` for explicit preview and
\`-y\` or \`--yes\` to apply. Full command reference:
$MANIFEST_CLI_INSTALL_LOCATION/docs/COMMAND_REFERENCE.md
EOF

    cp "$agents_hint" "$claude_hint"

    print_success "✅ Command catalog installed: $command_catalog_md"
    print_success "✅ JSON command catalog installed: $command_catalog_json"
    print_success "✅ Assistant hints installed: $agents_hint and $claude_hint"
    echo ""
}

# Create configuration files
create_configuration() {
    print_subheader "⚙️  Creating Configuration Files"

    local config_dir config_file
    config_dir="$(manifest_install_paths_global_state_dir)"
    config_file="$(manifest_install_paths_user_global_config)"

    # Ensure the config directory exists
    mkdir -p "$config_dir"

    # Create user's global configuration in home directory if it doesn't exist
    if [ ! -f "$config_file" ]; then
        if [ -f "examples/manifest.config.yaml.example" ]; then
            cp "examples/manifest.config.yaml.example" "$config_file"
            print_success "✅ Global configuration created: $config_file"
        else
            print_warning "⚠️  manifest.config.yaml.example not found, creating basic configuration"
            cat > "$config_file" << 'EOF'
# Manifest CLI Global Configuration
# See: examples/manifest.config.yaml.example for all options

time:
  timezone: "UTC"
  server1: "https://www.cloudflare.com/cdn-cgi/trace"
  server2: "https://www.google.com/generate_204"
  server3: "https://www.apple.com"
  server4: ""
  timeout: 5
  retries: 3
  verify: true
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600

version:
  format: "XX.XX.XX"

git:
  tag_prefix: "v"
  default_branch: "main"

docs:
  folder: "docs"
  archive_folder: "docs/zArchive"
  generate:
    enabled: true
    changelog: true
    readme_version: true
    index: true
    archive_cleanup: true
    site: false
    site_workflow: true

config:
  schema_version: 2
EOF
            print_success "✅ Global configuration created: $config_file"
        fi
    else
        print_status "ℹ️  Global configuration already exists: $config_file (preserved)"
    fi

    # Apply safe key-level migrations on every install/upgrade run.
    migrate_user_global_configuration

    echo ""
}

# Set up environment variables
setup_environment_variables() {
    print_subheader "🌍 Setting Up Environment Variables"

    local config_file
    config_file="$(manifest_install_paths_user_global_config)"

    # Source the YAML module for load_yaml_to_env
    local yaml_module="$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh"
    if [[ -f "$yaml_module" ]]; then
        source "$yaml_module"
    fi

    # Export environment variables from the user's global YAML configuration
    if [ -f "$config_file" ]; then
        if type load_yaml_to_env &>/dev/null; then
            load_yaml_to_env "$config_file"
            print_success "✅ Environment variables loaded from $config_file"
        else
            print_warning "⚠️  YAML module not available, cannot load $config_file"
        fi
    else
        print_warning "⚠️  Configuration file not found: $config_file, using defaults"
    fi

    # Set essential installation variables
    export MANIFEST_CLI_INSTALL_DIR="$MANIFEST_CLI_INSTALL_LOCATION"
    export MANIFEST_CLI_BIN_DIR="$MANIFEST_CLI_LOCAL_BIN"
    export MANIFEST_CLI_VERSION_FILE="VERSION"
    export MANIFEST_CLI_GITIGNORE_FILE=".gitignore"

    print_success "✅ Environment variables configured"
    echo ""
}

# Configure PATH
configure_path() {
    print_subheader "🛤️  Configuring PATH"
    
    if [[ ":$PATH:" != *":$MANIFEST_CLI_LOCAL_BIN:"* ]]; then
        print_warning "⚠️  $MANIFEST_CLI_LOCAL_BIN is not in your PATH"
        
        # Add to current session
        print_status "Adding to PATH for current session..."
        export PATH="$MANIFEST_CLI_LOCAL_BIN:$PATH"
        
        # Detect shell and suggest permanent configuration
        local shell_profile=""
        if [ -n "$ZSH_VERSION" ]; then
            shell_profile="$HOME/.zshrc"
            print_status "Detected zsh shell"
        elif [ -n "$BASH_VERSION" ]; then
            if [ -f "$HOME/.bash_profile" ]; then
                shell_profile="$HOME/.bash_profile"
            else
                shell_profile="$HOME/.bashrc"
            fi
            print_status "Detected bash shell"
        fi
        
        if [ -n "$shell_profile" ]; then
            print_warning "⚠️  To make this permanent, add this line to $shell_profile:"
            echo "   export PATH=\"$MANIFEST_CLI_LOCAL_BIN:\$PATH\""

            if [ ! -t 0 ]; then
                print_status "Non-interactive shell detected; skipping automatic profile edit"
                return 0
            fi
            
            # Offer to add it automatically
            read -p "   Would you like me to add this to $shell_profile? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "export PATH=\"$MANIFEST_CLI_LOCAL_BIN:\$PATH\"" >> "$shell_profile"
                print_success "✅ Added to $shell_profile"
                print_status "Please restart your terminal or run: source $shell_profile"
            fi
        fi
    else
        print_success "✅ $MANIFEST_CLI_LOCAL_BIN is already in your PATH"
    fi
    
    echo ""
}

# Verify installation
verify_installation() {
    print_subheader "🔍 Verifying Installation"

    # §5.7 layout assertions: current must be a symlink resolving to a real
    # versioned dir under runtime/, and the canonical core module must be
    # readable through the symlink. Skipped on Homebrew installs (where
    # MANIFEST_CLI_INSTALL_LOCATION points at the brew prefix and the
    # symlink scheme is not used).
    local state_dir current_link
    state_dir="$(manifest_install_paths_global_state_dir)"
    current_link="$state_dir/current"
    if [ -e "$current_link" ] || [ -L "$current_link" ]; then
        if [ ! -L "$current_link" ]; then
            print_error "❌ $current_link exists but is not a symlink"
            return 1
        fi
        if [ ! -d "$current_link" ]; then
            print_error "❌ $current_link does not resolve to a directory"
            return 1
        fi
        if [ ! -r "$current_link/modules/core/manifest-core.sh" ]; then
            print_error "❌ $current_link/modules/core/manifest-core.sh is not readable"
            return 1
        fi
        print_success "✅ current symlink resolves and core module is readable"
    fi

    if command_exists "$MANIFEST_CLI_NAME"; then
        print_success "✅ Manifest CLI installed successfully!"

        # Get version information
        local version_info
        if version_info=$("$MANIFEST_CLI_NAME" --version 2>/dev/null); then
            print_status "📋 CLI Version: $version_info"
        else
            print_status "📋 CLI Version: Version info not available"
        fi

        # Determine project root (always use current working directory)
        PROJECT_ROOT="$PWD"

        print_status "📍 Location: $(which "$MANIFEST_CLI_NAME")"
        print_status "🏠 Project directory: $PROJECT_ROOT"

        # Test basic functionality
        print_status "🧪 Testing basic functionality..."
        if "$MANIFEST_CLI_NAME" --help >/dev/null 2>&1; then
            print_success "✅ Help command working"
        else
            print_warning "⚠️  Help command failed"
        fi

        return 0
    else
        print_error "❌ Installation failed - $MANIFEST_CLI_NAME command not found"
        print_error "Please check the installation and try again"
        return 1
    fi
}

# Display post-installation information
display_post_install_info() {
    print_subheader "🎉 Installation Complete!"
    cat <<EOF

🚀 First steps with Manifest CLI:
   $MANIFEST_CLI_NAME doctor                     # health check (deps + config + repo)
   $MANIFEST_CLI_NAME status                     # snapshot of current repo
   $MANIFEST_CLI_NAME init repo                  # scaffold a project
   $MANIFEST_CLI_NAME ship repo patch            # cut a release

🔧 Configuration:
   ~/.manifest-cli/manifest.config.global.yaml   # user-wide preferences
   ./manifest.config.yaml                        # per-project (committed)
   ./manifest.config.local.yaml                  # per-project (git-ignored)
   $MANIFEST_CLI_NAME config list                # all keys + active layer

📚 Docs:  $MANIFEST_CLI_INSTALL_LOCATION/docs/USER_GUIDE.md
🌐 Repo:  https://github.com/fidenceio/manifest.cli

🧠 IDE / AI assistant support:
   Shell completions: installed for standard bash/zsh completion paths when available
   Command catalog:   $MANIFEST_CLI_IDE_SUPPORT_DIR/manifest-cli-commands.md
   Assistant hints:   $MANIFEST_CLI_IDE_SUPPORT_DIR/AGENTS.md and CLAUDE.md
EOF
    if [ -f ".git/hooks/pre-commit" ] && grep -q "Manifest CLI Pre-Commit Hook" ".git/hooks/pre-commit" 2>/dev/null; then
        echo
        print_status "🔒 Pre-commit security hook installed (see docs/USER_GUIDE.md, Git Hooks section)"
    fi
    echo
}

# =============================================================================
# Git Hooks Installation
# =============================================================================

install_git_hooks() {
    print_subheader "🔒 Installing Git Hooks"

    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        print_warning "⚠️  Not in a Git repository, skipping git hooks installation"
        print_warning "   Run './install-git-hooks.sh' manually when in a git repository"
        return 0
    fi

    local GIT_HOOKS_SOURCE_DIR=".git-hooks"
    local GIT_HOOKS_TARGET_DIR=".git/hooks"
    local PRE_COMMIT_SOURCE="$GIT_HOOKS_SOURCE_DIR/pre-commit"
    local PRE_COMMIT_TARGET="$GIT_HOOKS_TARGET_DIR/pre-commit"

    # Check if git hooks source directory exists
    if [ ! -d "$GIT_HOOKS_SOURCE_DIR" ]; then
        print_warning "⚠️  Git hooks source directory not found: $GIT_HOOKS_SOURCE_DIR"
        print_warning "   Skipping git hooks installation"
        return 0
    fi

    # Create hooks directory if it doesn't exist
    if [ ! -d "$GIT_HOOKS_TARGET_DIR" ]; then
        mkdir -p "$GIT_HOOKS_TARGET_DIR"
        print_success "✅ Created git hooks directory"
    fi

    # Check if pre-commit hook source exists
    if [ ! -f "$PRE_COMMIT_SOURCE" ]; then
        print_warning "⚠️  Pre-commit hook source not found: $PRE_COMMIT_SOURCE"
        print_warning "   Skipping git hooks installation"
        return 0
    fi

    # Backup existing hook if it exists
    if [ -f "$PRE_COMMIT_TARGET" ]; then
        local BACKUP_FILE="$PRE_COMMIT_TARGET.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "⚠️  Existing pre-commit hook found"
        print_warning "   Creating backup: $BACKUP_FILE"
        cp "$PRE_COMMIT_TARGET" "$BACKUP_FILE"
    fi

    # Copy and install the hook
    cp "$PRE_COMMIT_SOURCE" "$PRE_COMMIT_TARGET"
    chmod +x "$PRE_COMMIT_TARGET"

    # Verify installation
    if [ -f "$PRE_COMMIT_TARGET" ] && [ -x "$PRE_COMMIT_TARGET" ]; then
        if grep -q "Manifest CLI Pre-Commit Hook" "$PRE_COMMIT_TARGET" 2>/dev/null; then
            print_success "✅ Git hooks installed successfully"
            echo
            print_success "🔒 Security features enabled:"
            print_success "   • Blocks commits with private environment files"
            print_success "   • Scans for sensitive data patterns (API keys, tokens, passwords)"
            print_success "   • Verifies .gitignore configuration"
            print_success "   • Detects large files (>10MB)"
            print_success "   • Integrates with Manifest CLI security module"
        else
            print_warning "⚠️  Git hooks installed but content verification failed"
        fi
    else
        print_warning "⚠️  Git hooks installation failed"
    fi

    echo
}

# =============================================================================
# Legacy Manual Install Cleanup
# =============================================================================

# Remove a Homebrew-managed Manifest so a source-tree install becomes the single
# channel. The mirror image of cleanup_homebrew_install (which removes the manual
# footprint before a brew install): a channel switch must clean up the channel it
# leaves, in BOTH directions, so we never strand two installs fighting over PATH.
# Only invoked on an explicit --manual switch when a brew-managed copy is present.
# Honors the destructive-brew sandbox tripwire; best-effort (warns, never aborts
# the install) — same contract as the uninstall module's brew removal.
remove_brew_managed_install() {
    manifest_install_paths_is_brew_managed || return 0

    print_subheader "🧹 Removing Homebrew-managed Manifest (switching to the source channel)"

    if ! manifest_install_paths_assert_destructive_brew_safe "brew uninstall manifest"; then
        print_warning "   brew uninstall skipped by sandbox tripwire"
        return 0
    fi

    local brew_formula
    brew_formula="$(manifest_install_paths_homebrew_formula)"
    if brew uninstall "$brew_formula" 2>/dev/null || brew uninstall manifest 2>/dev/null; then
        print_success "✅ Removed Homebrew-managed Manifest"
    else
        print_warning "   Could not remove the Homebrew copy automatically — run: brew uninstall manifest"
    fi
}

# Cleanup step used before Homebrew install
cleanup_homebrew_install() {
    local user_bin state_dir legacy_dir
    user_bin="$(manifest_install_paths_user_binary)"
    state_dir="$(manifest_install_paths_global_state_dir)"
    legacy_dir="$(manifest_install_paths_legacy_install_dir)"

    local found_legacy=false
    [ -f "$user_bin" ] && found_legacy=true
    [ -d "$state_dir" ] && found_legacy=true
    [ -d "$legacy_dir" ] && found_legacy=true

    if [ "$found_legacy" = "false" ]; then
        return 0
    fi

    print_subheader "🧹 Cleaning up previous manual installation"

    if [ -f "$user_bin" ]; then
        if manifest_install_paths_assert_destructive_target_safe "$user_bin" "rm user-bin"; then
            rm -f "$user_bin"
            print_success "✅ Removed $user_bin"
        fi
    fi
    if [ -d "$state_dir" ]; then
        if manifest_install_paths_assert_destructive_target_safe "$state_dir" "rm state-dir"; then
            rm -rf "$state_dir"
            print_success "✅ Removed $state_dir"
        fi
    fi
    if [ -d "$legacy_dir" ]; then
        if manifest_install_paths_assert_destructive_target_safe "$legacy_dir" "rm legacy-dir"; then
            sudo rm -rf "$legacy_dir" 2>/dev/null && \
                print_success "✅ Removed $legacy_dir" || \
                print_warning "⚠️  Could not remove $legacy_dir (may need manual cleanup)"
        fi
    fi

    # Strip any residual MANIFEST_* exports and installer-style PATH adds from
    # shell profiles via the centralized profile-line regex.
    cleanup_environment_variables

    echo ""
}

# =============================================================================
# Homebrew Installation
# =============================================================================

install_via_homebrew() {
    print_subheader "🍺 Installing via Homebrew"

    local brew_tap brew_formula
    brew_tap="$(manifest_install_paths_homebrew_tap)"
    brew_formula="$(manifest_install_paths_homebrew_formula)"

    if ! brew tap "$brew_tap" 2>/dev/null; then
        print_error "❌ Failed to tap $brew_tap"
        return 1
    fi
    print_success "✅ Tapped $brew_tap"

    if manifest_install_paths_is_brew_managed; then
        print_status "Manifest CLI already installed via Homebrew, upgrading..."
        brew upgrade "$brew_formula" 2>/dev/null || true
    else
        if ! brew install "$brew_formula"; then
            print_error "❌ brew install failed"
            return 1
        fi
    fi

    print_success "✅ Manifest CLI installed via Homebrew"
    echo ""
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    local install_mode="auto"
    while [ $# -gt 0 ]; do
        case "$1" in
            --manual|--no-brew)
                install_mode="manual"
                shift
                ;;
            --brew|--homebrew)
                install_mode="brew"
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage: ./install-cli.sh [--manual | --brew]

Installs the Manifest CLI.

Options:
  --manual, --no-brew   Force a source-tree install from this checkout
                        (Homebrew routing skipped); removes an existing
                        Homebrew-managed copy so source is the only channel.
                        Use this to test changes not yet shipped to the tap.
  --brew, --homebrew    Force a Homebrew install of the SHIPPED formula
                        ('brew install fidenceio/tap/manifest'), removing an
                        existing manual install so brew is the only channel.
  -h, --help            Show this help.

Default behavior (no flag): Manifest stays on the channel it is already
installed through — a Homebrew install upgrades via Homebrew, a manual
install re-installs from source. Only a machine with no existing install
prefers Homebrew (when available). This is why a bare re-run never
silently switches your install channel; pass --manual or --brew to switch
deliberately.
EOF
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_error "Run './install-cli.sh --help' for usage."
                exit 2
                ;;
        esac
    done

    # Display banner
    echo
    print_header "============================================================================="
    print_header "🚀 Manifest CLI Installation Script"
    print_header "============================================================================="
    echo
    if [ "$install_mode" = "manual" ]; then
        print_status "📦 --manual specified — installing directly from this source tree (Homebrew routing skipped)"
        echo
    elif [ "$install_mode" = "brew" ]; then
        print_status "🍺 --brew specified — installing the shipped Homebrew formula"
        echo
    fi

    print_status "Welcome to the Manifest CLI installation!"
    print_status "This script will install a powerful CLI tool for versioning,"
    print_status "AI documenting, and repository operations."
    echo

    # System validation
    get_system_info

    # --- Resolve install channel (provenance-aware) --------------------------
    # The channel is decided by how Manifest is *currently* installed, not by
    # whether brew merely exists on this machine. Conflating those is what let a
    # bare re-run silently convert a --manual source install onto the shipped
    # formula. manifest_install_paths_is_brew_managed is the single source of
    # truth, shared with uninstall, the doctor reinstall, and the post-ship
    # self-upgrade — so none of them can disagree about "are we on brew".
    #   --manual : force a source-tree install
    #   --brew   : force a Homebrew install
    #   (auto)   : stay on the channel already in use; only a machine with no
    #              existing install prefers Homebrew (when it is available).
    local already_brew=false already_manual=false
    manifest_install_paths_is_brew_managed   && already_brew=true
    manifest_install_paths_is_manual_install && already_manual=true

    local want_brew=false
    case "$install_mode" in
        manual) want_brew=false ;;
        brew)   want_brew=true  ;;
        auto)
            if [ "$already_brew" = true ]; then
                want_brew=true        # already brew-managed → upgrade via brew
            elif [ "$already_manual" = true ]; then
                want_brew=false       # already a source install → stay on source
            else
                want_brew=true        # fresh machine → prefer brew (offered below)
            fi
            ;;
    esac

    if [ "$already_brew" = true ] && [ "$already_manual" = true ]; then
        print_status "ℹ️  Found BOTH a Homebrew-managed and a manual install of Manifest; converging to a single channel."
    fi

    # On macOS, offer to install Homebrew when we intend to use it but it is
    # missing. Gated on the resolved channel (not bare brew-presence), so a user
    # already on the source channel is never nagged to adopt Homebrew.
    if [ "$want_brew" = true ] && [[ "$OSTYPE" == "darwin"* ]] && ! command_exists brew; then
        print_status "🍺 macOS detected but Homebrew is not installed"
        print_status "Homebrew is the recommended way to install, upgrade, manage, and cleanly remove Manifest CLI on macOS. Plus, it offers thousands of other packages."
        echo ""
        read -p "   Would you like to install Homebrew? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            print_status "Installing Homebrew..."
            echo ""
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Add Homebrew to PATH for this session (Apple Silicon vs Intel)
            if [ -f "/opt/homebrew/bin/brew" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -f "/usr/local/bin/brew" ]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            if command_exists brew; then
                print_success "✅ Homebrew installed successfully"
            else
                print_error "❌ Homebrew installation failed — falling back to manual install"
            fi
        else
            print_status "Skipping Homebrew — will use manual installation"
        fi
        echo ""
    fi

    # If we intended to use brew but it is still unavailable (offer declined, or
    # a non-macOS box), reconcile rather than fall through inconsistently: an
    # explicit --brew is a hard error (never a silent downgrade to source); a
    # bare/auto run quietly uses the source channel instead.
    if [ "$want_brew" = true ] && ! command_exists brew; then
        if [ "$install_mode" = "brew" ]; then
            print_error "❌ --brew requested but Homebrew is not available."
            print_error "   Install Homebrew first, or re-run without --brew for a source install."
            exit 2
        fi
        want_brew=false
    fi

    # Docker install check comes after Homebrew so macOS has one clean path:
    # Homebrew first, Docker Desktop second, validation third.
    ensure_docker_installed
    validate_system

    # Route to the resolved channel (see the provenance resolution above).
    if [ "$want_brew" = true ]; then
        print_status "🍺 Installing via Homebrew"
        echo ""

        # Converge on a single channel: remove any prior manual footprint before
        # Homebrew takes over. Only reached when already brew-managed (no-op), a
        # fresh machine (nothing to remove), or an explicit --brew switch (the
        # cleanup is the intended effect).
        cleanup_homebrew_install

        if install_via_homebrew; then
            create_configuration
            # Shell completions are owned by the Homebrew formula
            # (bash_completion.install / zsh_completion.install). Installing
            # them again here would clobber brew's symlinks and break the next
            # `brew upgrade`. Only the manual path calls install_shell_completions.
            install_ide_command_catalog
            install_git_hooks
            local brew_manifest="$(brew --prefix)/bin/manifest"
            if [ -x "$brew_manifest" ] && "$brew_manifest" --help >/dev/null 2>&1; then
                print_success "✅ Installed at $brew_manifest"
                MANIFEST_CLI_INSTALL_LOCATION="${MANIFEST_CLI_INSTALL_LOCATION:-$(brew --prefix)/share/manifest}"
                display_post_install_info
                print_status "💡 To upgrade: brew update && brew upgrade manifest"
            else
                print_error "❌ Homebrew installation verification failed"
                exit 1
            fi
        else
            print_error "❌ Homebrew installation failed"
            exit 1
        fi
    else
        # Source-tree install: --manual, an existing source install on a bare
        # run, or no Homebrew available.
        if [ "$install_mode" = "manual" ]; then
            print_status "📦 Installing from this source tree (--manual specified — Homebrew routing skipped)"
        elif [ "$already_manual" = true ]; then
            print_status "📦 Existing source install detected — re-installing from this source tree (use --brew to switch to Homebrew)"
        else
            print_status "📦 Homebrew not available — installing from this source tree"
        fi
        # Converge on a single channel: a Homebrew-managed copy would otherwise
        # shadow (or be shadowed by) this source build depending on PATH order.
        # Remove it now so the switch to source is clean — the mirror of the brew
        # branch's cleanup_homebrew_install. Reached only on an explicit --manual
        # (a bare auto run with a brew copy present routes to the brew branch).
        if [ "$already_brew" = true ]; then
            remove_brew_managed_install
        fi
        echo ""

        # §5.7 atomic-upgrade flow: stage to runtime/v<X>.tmp/, atomic
        # rename to runtime/v<X>/, swap `current` symlink. User-state
        # subdirs and shell profiles are NOT touched on upgrade.
        create_state_root
        acquire_install_lock || exit 1
        # shellcheck disable=SC2064
        trap "release_install_lock" EXIT

        local install_state
        install_state="$(detect_install_mode)"
        print_status "🧭 Install mode: $install_state"

        if [ "$install_state" = "legacy-migration" ]; then
            migrate_legacy_layout || {
                print_error "❌ Legacy layout migration failed"
                exit 1
            }
            install_state="upgrade"
        fi

        # Resolve the source-tree VERSION (the one we're installing).
        local install_source_dir version_value
        install_source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$install_source_dir/VERSION" ]; then
            version_value="$(tr -d '[:space:]' < "$install_source_dir/VERSION")"
        fi
        if [ -z "$version_value" ]; then
            print_error "❌ Cannot determine version (missing VERSION file at $install_source_dir)"
            exit 1
        fi

        # Shell-profile rewriting is the duplicate-write defect's blast
        # radius. Run ONLY on a fresh install — upgrades must leave the
        # user's shell profiles untouched.
        if [ "$install_state" = "fresh" ]; then
            cleanup_environment_variables
            cleanup_legacy_installation
        fi

        stage_version_dir "$version_value"

        # The wrapper binary lives at the user-bin location (see
        # manifest_install_paths_user_binary) and is version-agnostic.
        # On a fresh install we write it; on upgrade we
        # only refresh it if its sha256 differs from the source tree's
        # copy (cheap content-hash compare avoids spurious mv on no-op).
        local wrapper_src wrapper_dst
        wrapper_src="$install_source_dir/scripts/manifest-cli-wrapper.sh"
        wrapper_dst="$MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
        if [ "$install_state" = "fresh" ] || ! _wrapper_binaries_match "$wrapper_src" "$wrapper_dst"; then
            if [ -f "$wrapper_src" ]; then
                local wrapper_tmp
                wrapper_tmp="$(mktemp "${wrapper_dst}.XXXXXX")"
                cp "$wrapper_src" "$wrapper_tmp"
                chmod +x "$wrapper_tmp"
                mv -f "$wrapper_tmp" "$wrapper_dst"
                print_success "✅ Installed wrapper $wrapper_dst"
            else
                print_error "❌ CLI wrapper script not found at $wrapper_src"
                exit 1
            fi
        else
            print_status "ℹ️  Wrapper binary already up to date"
        fi

        swap_current_symlink "$version_value"

        if [ "$install_state" = "fresh" ]; then
            create_configuration
            setup_environment_variables
            configure_path
            install_shell_completions
        else
            # Upgrade mode: refresh only version-dependent content;
            # leave shell profiles alone.
            create_configuration
            install_shell_completions
        fi

        install_ide_command_catalog
        prune_old_versions 2

        if verify_installation; then
            if [ "$install_state" = "fresh" ]; then
                install_git_hooks
            fi
            display_post_install_info
        else
            print_error "❌ Installation verification failed"
            exit 1
        fi
    fi
}

# =============================================================================
# Script Execution
# =============================================================================

# Check if script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
else
    # Script is being sourced
    print_warning "⚠️  This script is designed to be executed, not sourced"
    print_warning "   Please run: ./install-cli.sh"
fi
