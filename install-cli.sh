#!/bin/bash
# Manifest CLI installer.
#
# Validates the host (centralized requirements, Git, Docker), copies the CLI tree to
# ~/.manifest-cli, configures PATH, sets up the global YAML config, and
# optionally installs a pre-commit security hook in the current repo.
#
# Run from the repo root:  ./install-cli.sh
# Or via Homebrew:          brew install fidenceio/tap/manifest

set -e

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
    bash_ver="$(bash --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
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
# profiles. Inlined here so install-cli.sh has no dependency on the (deleted)
# env-management module. Called once before installing to remove residue from
# previous installs.
cleanup_environment_variables() {
    print_subheader "🧹 Cleaning Up Manifest CLI Shell-Profile Entries"

    local removed_count=0
    local profile_regex
    profile_regex="$(manifest_install_paths_profile_line_regex)"

    local profile temp backup
    while IFS= read -r profile; do
        [ -n "$profile" ] || continue
        [ -f "$profile" ] || continue
        backup="${profile}.manifest-backup-$(date +%Y%m%d-%H%M%S)"
        cp "$profile" "$backup"
        temp=$(mktemp)
        if grep -v -E "$profile_regex" "$profile" > "$temp"; then
            if [ -s "$temp" ] && ! cmp -s "$profile" "$temp"; then
                mv "$temp" "$profile"
                print_success "✅ Cleaned: $profile (backup: $backup)"
                ((removed_count++))
            else
                rm -f "$temp" "$backup"
            fi
        else
            rm -f "$temp" "$backup"
        fi
    done < <(manifest_install_paths_shell_profiles)
    if [ $removed_count -eq 0 ]; then
        print_status "  No prior Manifest entries found in shell profiles"
    fi
}

# Clean up legacy installation locations
cleanup_legacy_locations() {
    print_subheader "🧹 Cleaning Up Legacy Installation Locations"

    local legacy_location
    legacy_location="$(manifest_install_paths_legacy_install_dir)"

    if [ -d "$legacy_location" ]; then
        print_status "Found legacy installation at: $legacy_location"
        # Try with sudo since it's a system location
        if sudo rm -rf "$legacy_location" 2>/dev/null; then
            print_success "✅ Removed legacy installation: $legacy_location"
        else
            print_warning "⚠️  Could not remove $legacy_location (may need manual cleanup)"
        fi
    else
        print_status "No legacy installations found"
    fi

    print_success "✅ Legacy location cleanup completed"
}

# Clean up old installation using the uninstall module
cleanup_old_installation() {
    print_subheader "🧹 Cleaning Up Old Installation"

    # First, clean up any legacy installation locations
    cleanup_legacy_locations

    # Source the uninstall module
    if ! source_manifest_uninstall; then
        print_error "❌ Failed to load uninstall module"
        print_error "❌ Cannot proceed with installation without cleanup capability"
        return 1
    fi

    # Use the uninstall module for comprehensive cleanup
    # Parameters: skip_confirmations=true, non_interactive=true
    uninstall_manifest "true" "true"
}

# Create directory structure
create_directories() {
    print_subheader "📁 Creating Directory Structure"
    
    # Create local bin directory
    if [ ! -d "$MANIFEST_CLI_LOCAL_BIN" ]; then
        mkdir -p "$MANIFEST_CLI_LOCAL_BIN"
        print_success "✅ Created $MANIFEST_CLI_LOCAL_BIN"
    else
        print_success "✅ $MANIFEST_CLI_LOCAL_BIN already exists"
    fi
    
    # Create project directory
    if [ ! -d "$MANIFEST_CLI_INSTALL_LOCATION" ]; then
        mkdir -p "$MANIFEST_CLI_INSTALL_LOCATION"
        print_success "✅ Created $MANIFEST_CLI_INSTALL_LOCATION"
    else
        print_success "✅ $MANIFEST_CLI_INSTALL_LOCATION already exists"
    fi
    
    # Create subdirectories
    mkdir -p "$MANIFEST_CLI_INSTALL_LOCATION/docs"
    
    print_success "✅ Directory structure created"
    echo ""
}

# Copy CLI files
copy_cli_files() {
    print_subheader "📦 Copying CLI Files"
    
    # Copy main CLI script
    if [ -f "scripts/manifest-cli-wrapper.sh" ]; then
        cp "scripts/manifest-cli-wrapper.sh" "$MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
        chmod +x "$MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
        print_success "✅ Copied CLI script to $MANIFEST_CLI_LOCAL_BIN/$MANIFEST_CLI_NAME"
    else
        print_error "❌ CLI wrapper script not found"
        exit 1
    fi
    
    # Copy source modules
    if [ -d "modules" ]; then
        cp -r "modules" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied source modules"
    fi

    # Copy documentation
    if [ -d "docs" ]; then
        cp -r "docs" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied documentation"
    fi

    # Copy example configuration files
    if [ -d "examples" ]; then
        cp -r "examples" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied example configuration files"
    fi

    # Copy shell completions for IDE-integrated terminals and regular shells.
    if [ -d "completions" ]; then
        cp -r "completions" "$MANIFEST_CLI_INSTALL_LOCATION/"
        print_success "✅ Copied shell completions"
    fi

    print_success "✅ All CLI files copied successfully"
    echo ""
}

manifest_completion_source_dir() {
    local source_dir
    local candidates=(
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

    local installed=0
    local bash_target=""
    local zsh_target=""

    if command_exists brew; then
        local brew_prefix
        brew_prefix="$(brew --prefix 2>/dev/null || true)"
        if [ -n "$brew_prefix" ]; then
            bash_target="$brew_prefix/etc/bash_completion.d/manifest"
            zsh_target="$brew_prefix/share/zsh/site-functions/_manifest"
        fi
    fi

    if [ -n "$bash_target" ]; then
        mkdir -p "$(dirname "$bash_target")"
        ln -sf "$source_dir/manifest.bash" "$bash_target"
        print_success "✅ Bash completion installed: $bash_target"
        installed=$((installed + 1))
    fi

    if [ -n "$zsh_target" ]; then
        mkdir -p "$(dirname "$zsh_target")"
        ln -sf "$source_dir/_manifest" "$zsh_target"
        print_success "✅ Zsh completion installed: $zsh_target"
        installed=$((installed + 1))
    fi

    if [ "$installed" -eq 0 ]; then
        print_warning "⚠️  No standard completion directory detected"
        print_warning "   Bash: source $source_dir/manifest.bash"
        print_warning "   Zsh:  add $source_dir to fpath and run compinit"
    else
        print_status "IDE integrated terminals pick these up through their login shell."
    fi

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
        rm -f "$user_bin"
        print_success "✅ Removed $user_bin"
    fi
    if [ -d "$state_dir" ]; then
        rm -rf "$state_dir"
        print_success "✅ Removed $state_dir"
    fi
    if [ -d "$legacy_dir" ]; then
        sudo rm -rf "$legacy_dir" 2>/dev/null && \
            print_success "✅ Removed $legacy_dir" || \
            print_warning "⚠️  Could not remove $legacy_dir (may need manual cleanup)"
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

    if brew list "$brew_formula" &>/dev/null; then
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
    # Display banner
    echo
    print_header "============================================================================="
    print_header "🚀 Manifest CLI Installation Script"
    print_header "============================================================================="
    echo

    print_status "Welcome to the Manifest CLI installation!"
    print_status "This script will install a powerful CLI tool for versioning,"
    print_status "AI documenting, and repository operations."
    echo

    # System validation
    get_system_info

    # On macOS, offer to install Homebrew if not present
    if [[ "$OSTYPE" == "darwin"* ]] && ! command_exists brew; then
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

    # Docker install check comes after Homebrew so macOS has one clean path:
    # Homebrew first, Docker Desktop second, validation third.
    ensure_docker_installed
    validate_system

    # Route through Homebrew when available
    if command_exists brew; then
        print_status "🍺 Homebrew detected — installing via Homebrew"
        echo ""

        # Remove any previous manual installation before Homebrew install
        cleanup_homebrew_install

        if install_via_homebrew; then
            create_configuration
            install_shell_completions
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
        # Fallback: manual installation (Linux, CI, no Homebrew)
        print_status "Homebrew not found — using manual installation"
        echo ""

        cleanup_environment_variables
        cleanup_old_installation
        create_directories
        copy_cli_files
        create_configuration
        setup_environment_variables
        configure_path
        install_shell_completions
        install_ide_command_catalog

        if verify_installation; then
            install_git_hooks
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
