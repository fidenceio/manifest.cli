#!/bin/bash

# =============================================================================
# Manifest Init Module
# =============================================================================
#
# Implements: manifest init repo|fleet
#
# PURPOSE:
#   Scaffold a single repo or fleet. First step after config in the user journey.
#   Creates local files only — no remote operations.
#
# COMMANDS:
#   manifest init repo          Scaffold single repo (VERSION, CHANGELOG, etc.)
#   manifest init fleet         Two-phase fleet setup via TSV discovery
#
# DEPENDENCIES:
#   - manifest-shared-functions.sh (logging, get_docs_folder, manifest_*_repo)
#   - manifest-fleet.sh (_fleet_start, _fleet_init)
#   - manifest-yaml.sh (set_yaml_value)
#
# SCAFFOLDING HELPERS:
#   ensure_required_files, create_default_readme, create_default_changelog,
#   ensure_gitignore_smart, create_default_gitignore — defined here and used
#   by manifest-orchestrator.sh, manifest-documentation.sh, manifest-fleet.sh.
#   They live in this module because init owns the scaffolding semantics; other
#   callers borrow them for repair/idempotency on existing repos.
# =============================================================================

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_INIT_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_INIT_LOADED=1

# =============================================================================
# FILE CREATION AND VALIDATION FUNCTIONS
# =============================================================================

# Check for required files and create them if missing
ensure_required_files() {
    local project_root="${1:-$PROJECT_ROOT}"
    local created_files=()

    log_info "Checking for required files in: $project_root"

    # Ensure VERSION file exists
    if [ ! -f "$project_root/VERSION" ]; then
        log_info "Creating VERSION file..."
        echo "1.0.0" > "$project_root/VERSION"
        created_files+=("VERSION")
        log_success "Created VERSION file with default version 1.0.0"
    fi

    # Ensure README.md exists
    if [ ! -f "$project_root/README.md" ]; then
        log_info "Creating README.md file..."
        create_default_readme "$project_root/README.md"
        created_files+=("README.md")
        log_success "Created README.md file"
    fi

    # Ensure docs directory exists
    local docs_dir=$(get_docs_folder "$project_root")
    if [ ! -d "$docs_dir" ]; then
        log_info "Creating documentation directory..."
        mkdir -p "$docs_dir"
        created_files+=("$(basename "$docs_dir")/")
        log_success "Created documentation directory: $(basename "$docs_dir")/"
    fi

    # Ensure CHANGELOG.md exists
    if [ ! -f "$project_root/CHANGELOG.md" ]; then
        log_info "Creating CHANGELOG.md file..."
        create_default_changelog "$project_root/CHANGELOG.md"
        created_files+=("CHANGELOG.md")
        log_success "Created CHANGELOG.md file"
    fi

    # Ensure .gitignore exists with best-practice entries
    local gitignore_result
    gitignore_result=$(ensure_gitignore_smart "$project_root")
    case "$gitignore_result" in
        ".gitignore:empty-overwrite")
            created_files+=(".gitignore")
            ;;
        ".gitignore"|".gitignore.manifest")
            created_files+=("$gitignore_result")
            ;;
    esac

    # Report results
    if [ ${#created_files[@]} -gt 0 ]; then
        log_success "Created ${#created_files[@]} missing file(s): ${created_files[*]}"
    else
        log_info "All required files are present"
    fi

    # Deferred warnings
    if [[ "$gitignore_result" == ".gitignore:empty-overwrite" ]]; then
        log_warning "An existing .gitignore had no entries and was overwritten with Manifest defaults."
        log_warning "If the empty .gitignore was intentional, review and adjust as needed."
    fi

    return 0
}

# Create default README.md content
create_default_readme() {
    local readme_file="$1"
    local project_root
    project_root="$(dirname "$readme_file")"
    local project_name
    project_name="$(manifest_repo_display_name "$project_root")"
    local current_version
    current_version=$(cat "$project_root/VERSION" 2>/dev/null || echo "1.0.0")
    local docs_dir_name
    docs_dir_name="$(basename "$(get_docs_folder "$project_root")")"
    local timestamp
    timestamp="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"

    if manifest_is_canonical_repo "$project_root"; then
        cat > "$readme_file" << EOF
# $project_name

A software project with automated version management and documentation.

## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | \`$current_version\` |
| **Release Date** | \`$(date -u +'%Y-%m-%d %H:%M:%S UTC')\` |
| **Git Tag** | \`v$current_version\` |
| **Branch** | \`$(git branch --show-current 2>/dev/null || echo 'main')\` |
| **Last Updated** | \`$(date -u +'%Y-%m-%d %H:%M:%S UTC')\` |

## 🚀 Getting Started

### Prerequisites

- Git (for version control)
- Basic command-line tools

### Development Workflow

This project uses automated version management and documentation generation:

\`\`\`bash
# View current version
cat VERSION

# Check project status
git status

# View changelog
cat CHANGELOG.md
\`\`\`

## 📚 Documentation

- **Version Info**: [VERSION](VERSION)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- **Project Docs**: [$(basename "$(get_docs_folder)")/]($(basename "$(get_docs_folder)")/) (if available)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

*This project uses [Manifest CLI](https://github.com/fidenceio/fidenceio.manifest.cli) for automated version management and documentation generation.*
EOF
        return 0
    fi

    cat > "$readme_file" << EOF
# $project_name

Repository documentation and release metadata.

<!-- manifest:readme-version:start -->
## Version Information

| Property | Value |
|----------|-------|
| Current Version | \`$current_version\` |
| Release Date | \`$timestamp\` |
| Git Tag | \`v$current_version\` |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |
| Last Updated | \`$timestamp\` |
<!-- manifest:readme-version:end -->

## Documentation

- [VERSION](VERSION)
- [CHANGELOG.md](CHANGELOG.md)
- [$docs_dir_name/]($docs_dir_name/)
EOF
}

# Create default CHANGELOG.md content
create_default_changelog() {
    local changelog_file="$1"
    local project_root
    project_root="$(dirname "$changelog_file")"
    local current_version
    current_version=$(cat "$project_root/VERSION" 2>/dev/null || echo "1.0.0")

    if manifest_is_canonical_repo "$project_root"; then
        cat > "$changelog_file" << EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup
- Automated version management
- Documentation generation

## [$current_version] - $(date -u +'%Y-%m-%d')

### Added
- Initial release
- Basic project structure
- Version tracking system

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A
EOF
        return 0
    fi

    local release_date
    release_date="$(date -u +'%Y-%m-%d')"

    cat > "$changelog_file" << EOF
# Changelog

All notable changes to this project will be documented in this file.

## [$current_version] - $release_date

Initial release.
EOF
}

# Smart .gitignore creation
# - No .gitignore          → create .gitignore
# - .gitignore with no entries (empty / only comments+blanks) → overwrite .gitignore
# - .gitignore with entries → create .gitignore.manifest as reference
#
# Output (stdout):
#   ".gitignore"                 — created new file
#   ".gitignore:empty-overwrite" — overwrote a .gitignore that had no real entries
#   ".gitignore.manifest"        — reference file created alongside existing .gitignore
#   (empty)                      — nothing was done
#
# Returns 0 on success, 1 on write failure.
ensure_gitignore_smart() {
    local project_root="$1"
    local gitignore_file="$project_root/.gitignore"
    local manifest_ref="$project_root/.gitignore.manifest"

    if [[ ! -f "$gitignore_file" ]]; then
        # No .gitignore at all — create one
        log_info "Creating .gitignore file..."
        if ! create_default_gitignore "$gitignore_file"; then
            log_error "Failed to create .gitignore in $project_root"
            return 1
        fi
        log_success "Created .gitignore file"
        echo ".gitignore"
        return 0
    fi

    # Count non-blank, non-comment lines (actual ignore entries)
    local entry_count
    entry_count=$(grep -cvE '^\s*$|^\s*#' "$gitignore_file" 2>/dev/null || echo "0")

    if [[ "$entry_count" -eq 0 ]]; then
        # .gitignore exists but has no real entries — overwrite
        log_info "Existing .gitignore has no entries, overwriting with defaults..."
        if ! create_default_gitignore "$gitignore_file"; then
            log_error "Failed to overwrite .gitignore in $project_root"
            return 1
        fi
        log_success "Overwrote empty .gitignore with best-practice defaults"
        echo ".gitignore:empty-overwrite"
        return 0
    fi

    # .gitignore has real entries — write a reference file instead
    if [[ ! -f "$manifest_ref" ]]; then
        log_info "Existing .gitignore has entries, creating .gitignore.manifest as reference..."
        if ! create_default_gitignore "$manifest_ref"; then
            log_error "Failed to create .gitignore.manifest in $project_root"
            return 1
        fi
        log_success "Created .gitignore.manifest (merge entries into .gitignore as needed)"
        echo ".gitignore.manifest"
        return 0
    fi

    # Both files already exist — nothing to do
    return 0
}

# Create default .gitignore content
create_default_gitignore() {
    local gitignore_file="$1"

    cat > "$gitignore_file" << 'EOF'
# =============================================================================
# Manifest CLI
# =============================================================================
.manifest-cli/
*.manifest-cli.log
.gitignore.manifest

# =============================================================================
# OS generated files
# =============================================================================
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
Desktop.ini
$RECYCLE.BIN/

# =============================================================================
# Editor and IDE files
# =============================================================================
.vscode/
.idea/
*.swp
*.swo
*~
*.sublime-project
*.sublime-workspace
.project
.classpath
.settings/
*.tmproj
*.tmproject
.tmtags
nbproject/

# =============================================================================
# Environment and secrets
# =============================================================================
.env
.env.*
!.env.example
!.env.template

# =============================================================================
# Logs and runtime data
# =============================================================================
*.log
logs/
pids/
*.pid
*.seed
*.pid.lock

# =============================================================================
# Dependencies
# =============================================================================
node_modules/
bower_components/
vendor/
.bundle/
jspm_packages/

# =============================================================================
# Package manager caches and artifacts
# =============================================================================
.npm
.yarn/
!.yarn/patches
!.yarn/plugins
!.yarn/releases
!.yarn/sdks
!.yarn/versions
.pnpm-store/
.node_repl_history
*.tgz
.yarn-integrity

# =============================================================================
# Build outputs
# =============================================================================
dist/
build/
out/
target/
*.egg-info/
*.egg
*.whl
*.class
*.jar
*.war
*.ear

# =============================================================================
# Test and coverage
# =============================================================================
coverage/
.nyc_output/
.coverage
htmlcov/
.pytest_cache/
.tox/
.nox/
nosetests.xml
coverage.xml
*.cover
*.py,cover

# =============================================================================
# Compiled and generated files
# =============================================================================
*.o
*.so
*.dylib
*.dll
*.exe
*.out
*.app
*.com
__pycache__/
*.py[cod]
*$py.class
*.class

# =============================================================================
# Temporary files
# =============================================================================
tmp/
temp/
*.tmp
*.temp
*.bak
*.orig
*.rej

# =============================================================================
# Archive directories
# =============================================================================
zArchive/
archive/

# =============================================================================
# Terraform
# =============================================================================
.terraform/
*.tfstate
*.tfstate.*
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc

# =============================================================================
# Docker
# =============================================================================
.docker/

# =============================================================================
# Miscellaneous
# =============================================================================
*.sqlite
*.db
.cache/
.parcel-cache/
.turbo/
.next/
.nuxt/
.output/
.svelte-kit/
EOF
}

# -----------------------------------------------------------------------------
# Function: manifest_init_repo
# -----------------------------------------------------------------------------
# Scaffolds a single repository with required files.
# Creates: VERSION (1.0.0), CHANGELOG.md, README.md, docs/, .gitignore entries,
# manifest.config.local.yaml.
#
# Idempotent — safe to re-run. Reports what was created/updated.
#
# ARGUMENTS:
#   --force    Re-create files even if they exist
# -----------------------------------------------------------------------------
manifest_init_repo() {
    local force=false
    local dry_run=true
    local create_repo_visibility=""
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()

    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    [[ "$execution_mode" == "apply" ]] && dry_run=false
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            --create-repo-private)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "private") || return 1
                shift ;;
            --create-repo-public)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "public") || return 1
                shift ;;
            -h|--help)
                _render_help \
                    "manifest init repo [-y|--yes] [--dry-run] [--force] [--create-repo-private|--create-repo-public]" \
                    "Scaffold a single repository: VERSION, CHANGELOG.md, README.md, docs/, .gitignore.
Idempotent — safe to re-run. Optionally creates a GitHub repo via 'gh repo create'." \
                    "Options" "  --dry-run                  Explicit preview; no writes
  -y, --yes                  Apply the scaffold plan
  -f, --force                Re-create files even if they already exist
  --create-repo-private      Create a private GitHub repo (gh repo create) and add as origin
  --create-repo-public       Create a public GitHub repo (gh repo create) and add as origin" \
                    "Examples" "  manifest init repo
  manifest init repo --dry-run
  manifest init repo -y
  manifest init repo --create-repo-private -y
  manifest init repo --force --create-repo-public -y"
                return 0
                ;;
            *)
                _render_help_error "Unknown option: $1" "manifest init repo [--force] [--dry-run] [--create-repo-private|--create-repo-public]"
                return 1
                ;;
        esac
    done

    local project_root="${PROJECT_ROOT:-$(pwd)}"

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "Dry run — manifest init repo: $project_root"
        echo ""
        if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
            echo "  would create: .git/   (git init)"
        else
            echo "  exists:       .git/"
        fi
        local f
        for f in VERSION README.md CHANGELOG.md .gitignore; do
            if [[ -f "$project_root/$f" ]]; then
                if [[ "$force" == "true" ]]; then
                    echo "  would overwrite: $f   (--force)"
                else
                    echo "  exists:          $f"
                fi
            else
                echo "  would create:    $f"
            fi
        done
        if [[ -d "$project_root/docs" ]]; then
            echo "  exists:          docs/"
        else
            echo "  would create:    docs/"
        fi
        if [[ -f "$project_root/manifest.config.local.yaml" && "$force" != "true" ]]; then
            echo "  exists:          manifest.config.local.yaml"
        else
            echo "  would create:    manifest.config.local.yaml"
        fi
        if [[ -n "$create_repo_visibility" ]]; then
            local repo_name
            repo_name="$(basename "$project_root")"
            if git -C "$project_root" remote get-url origin >/dev/null 2>&1; then
                echo "  exists:          origin remote (gh repo create skipped)"
            else
                echo "  would gh repo create: $repo_name ($create_repo_visibility) and add as origin"
            fi
        fi
        echo ""
        manifest_execution_footer "manifest init repo -y"
        echo ""
        return 0
    fi

    manifest_execution_apply_header
    echo ""
    echo "Initializing repository: $project_root"
    echo ""

    # Ensure we're in a git repo (or create one)
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "No git repository found. Initializing..."
        if git init "$project_root" >/dev/null; then
            echo "  Created: .git/"
        else
            log_error "Failed to initialize git repository"
            return 1
        fi
    fi

    # Use the shared ensure_required_files function
    # This creates VERSION, README.md, CHANGELOG.md, docs/, .gitignore
    if ! ensure_required_files "$project_root"; then
        log_error "Failed to create required files"
        return 1
    fi

    # Create manifest.config.local.yaml if it doesn't exist
    local local_config="$project_root/manifest.config.local.yaml"
    if [[ ! -f "$local_config" ]] || [[ "$force" == "true" ]]; then
        cat > "$local_config" << 'EOF'
# Manifest CLI — Local Configuration (git-ignored)
# This file overrides manifest.config.yaml for your local environment.
# See: manifest config show

# project:
#   name: "my-project"
#   description: "My project description"

# git:
#   default_branch: "main"

# debug:
#   enabled: false
#   verbose: false
EOF
        echo "  Created: manifest.config.local.yaml"
    fi

    if [[ -n "$create_repo_visibility" ]]; then
        echo ""
        if ! _manifest_gh_repo_create "$project_root" "$create_repo_visibility"; then
            log_warning "GitHub repo creation failed; local scaffold is intact."
            echo ""
            echo "  Re-attempt later with: manifest prep repo --create-repo-$create_repo_visibility"
            return 1
        fi
    fi

    echo ""
    echo "Repository initialized successfully."
    echo ""
    echo "Next steps:"
    echo "  manifest prep repo       Connect remotes, pull latest"
    echo "  manifest config          Adjust settings"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: manifest_init_fleet
# -----------------------------------------------------------------------------
# Two-phase fleet initialization:
#   Phase 1 (no TSV exists): Scan directories, create manifest.fleet.tsv
#   Phase 2 (TSV exists):    Read selections, scaffold each repo, create config
#
# Delegates to _fleet_start (phase 1) and _fleet_init (phase 2) in
# manifest-fleet.sh.
#
# ARGUMENTS:
#   --depth N|auto  Scan depth; auto adapts to repos found (default: auto)
#   --force      Overwrite existing files
#   --name NAME  Fleet name
# -----------------------------------------------------------------------------
_manifest_init_fleet_dry_run_phase1() {
    local root_dir="$1"
    local depth="$2"
    local start_file="$3"
    local force="$4"
    local create_repo_visibility="$5"
    local all_folders="${6:-false}"

    # Resolve --depth (N|auto) to a concrete scan depth; auto adapts to the
    # shallowest level with repos (§7.3). Keep the original spec ($depth) for the
    # replay hint so the default ("auto") replays as a bare command.
    local resolved_depth
    resolved_depth="$(manifest_fleet_resolve_depth "$depth" "$root_dir")" || return 1

    local discovered
    discovered=$(discover_all_directories "$root_dir" "$resolved_depth")

    local rules="" inventory="$discovered"
    if [[ "$all_folders" != "true" ]]; then
        rules=$(_fleet_default_repo_depth_rules "$discovered")
        inventory=$(filter_start_inventory_by_repo_depth "$discovered" "$rules" "false")
    fi

    local total=0 listed=0 git_count=0 plain_count=0
    while IFS=$'\t' read -r name _path _type _branch _version _url _submodule has_git _has_remote; do
        [[ -z "$name" ]] && continue
        ((total += 1))
    done <<< "$discovered"
    while IFS=$'\t' read -r name _path _type _branch _version _url _submodule has_git _has_remote; do
        [[ -z "$name" ]] && continue
        ((listed += 1))
        if [[ "$has_git" == "true" ]]; then
            ((git_count += 1))
        else
            ((plain_count += 1))
        fi
    done <<< "$inventory"

    echo ""
    echo "Dry run - manifest init fleet (Phase 1/2): $root_dir"
    echo ""
    echo "Would scan depth: $resolved_depth"
    if [[ "$all_folders" == "true" ]]; then
        echo "Inventory mode:   all scanned folders"
    else
        echo "Inventory mode:   repo-depth defaults (interactive prompts in live mode)"
    fi
    if [[ -f "$start_file" && "$force" == "true" ]]; then
        echo "Would overwrite: $start_file"
    else
        echo "Would create:    $start_file"
    fi
    echo "Would scan:      $total directories"
    echo "Would list:      $listed TSV rows ($git_count with git, $plain_count without git)"
    if [[ -n "$create_repo_visibility" ]]; then
        echo "Would defer:     GitHub repo creation flag applies in Phase 2 (--create-repo-$create_repo_visibility)"
    fi
    echo ""
    local replay_command="manifest init fleet"
    [[ "$depth" != "auto" ]] && replay_command="$replay_command --depth $depth"
    [[ "$force" == "true" ]] && replay_command="$replay_command --force"
    [[ -n "$create_repo_visibility" ]] && replay_command="$replay_command --create-repo-$create_repo_visibility"
    [[ "$all_folders" == "true" ]] && replay_command="$replay_command --all-folders"
    manifest_execution_footer "$replay_command -y"
}

_manifest_init_fleet_dry_run_phase2() {
    local root_dir="$1"
    local start_file="$2"
    local config_file="$3"
    local force="$4"
    local fleet_name="$5"
    local create_repo_visibility="$6"
    local stale="$7"

    local selected
    selected=$(parse_start_tsv "$start_file")

    local selected_count=0 existing_count=0 missing_count=0 needs_git_count=0
    while IFS=$'\t' read -r name path _type has_git _url _branch _version; do
        [[ -z "$name" ]] && continue
        ((selected_count += 1))
        local abs_path="$root_dir/${path#./}"
        if [[ -d "$abs_path" ]]; then
            ((existing_count += 1))
        else
            ((missing_count += 1))
        fi
        [[ "$has_git" != "true" ]] && ((needs_git_count += 1))
    done <<< "$selected"

    if [[ -z "$fleet_name" ]]; then
        fleet_name=$(basename "$root_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    fi

    echo ""
    echo "Dry run - manifest init fleet (Phase 2/2): $root_dir"
    echo ""
    echo "Would read:      $start_file"
    if [[ -f "$config_file" && "$force" == "true" ]]; then
        echo "Would overwrite: $config_file"
    elif [[ -f "$config_file" ]]; then
        echo "Exists:          $config_file"
    else
        echo "Would create:    $config_file"
    fi
    if [[ -f "$root_dir/manifest.config.local.yaml" ]]; then
        echo "Exists:          $root_dir/manifest.config.local.yaml"
    else
        echo "Would create:    $root_dir/manifest.config.local.yaml"
    fi
    if [[ -d "$root_dir/.git" ]] || [[ -f "$root_dir/.git" ]]; then
        echo "Exists:          fleet-root git repo ($root_dir/.git)"
    else
        echo "Would init:      fleet-root git repo (local-only, no remote)"
        if git -C "$root_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "                 note: root is nested in a parent repo; a separate coordination repo will be created here"
        fi
    fi
    if [[ -f "$root_dir/.gitignore" ]]; then
        echo "Exists:          $root_dir/.gitignore (allowlist saved as .gitignore.manifest if it has entries)"
    else
        echo "Would create:    $root_dir/.gitignore (coordination allowlist)"
    fi
    echo "Fleet name:      $fleet_name"
    echo "Selected rows:   $selected_count ($existing_count existing, $missing_count missing)"
    echo "Would git init:  $needs_git_count selected director$( [[ "$needs_git_count" == "1" ]] && echo "y" || echo "ies" ) without git"
    if [[ -n "$create_repo_visibility" ]]; then
        echo "Would create:    $create_repo_visibility GitHub repo per selected directory after local init"
    fi
    if [[ "$stale" == "true" ]]; then
        echo ""
        echo "Would stop live run: manifest.fleet.tsv still has generated default selections."
        echo "Re-run with --force to apply defaults, or edit SELECT values first."
    fi
    echo ""
    local replay_command="manifest init fleet"
    [[ "$force" == "true" ]] && replay_command="$replay_command --force"
    [[ -n "$fleet_name" ]] && replay_command="$replay_command --name $fleet_name"
    [[ -n "$create_repo_visibility" ]] && replay_command="$replay_command --create-repo-$create_repo_visibility"
    manifest_execution_footer "$replay_command -y"
}

manifest_init_fleet() {
    local depth="auto"
    local force=false
    local dry_run=true
    local fleet_name=""
    local create_repo_visibility=""
    local all_folders=false
    local fleet_args=()
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()

    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    [[ "$execution_mode" == "apply" ]] && dry_run=false
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--depth requires a numeric value"
                    return 1
                fi
                depth="$2"; shift 2 ;;
            -f|--force) force=true; shift ;;
            --all-folders) all_folders=true; shift ;;
            -n|--name)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--name requires a value"
                    return 1
                fi
                fleet_name="$2"; shift 2 ;;
            --create-repo-private)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "private") || return 1
                shift ;;
            --create-repo-public)
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "public") || return 1
                shift ;;
            -h|--help)
                _render_help \
                    "manifest init fleet [-y|--yes] [--dry-run] [--depth N|auto] [--all-folders] [--force] [--name NAME] [--create-repo-private|--create-repo-public]" \
                    "Two-phase fleet initialization." \
                    "Phases" "  Phase 1 (no TSV yet):  Scan directories, ask repo depth per
                         top-level folder when interactive, then write
                         manifest.fleet.tsv for review.
  Phase 2 (TSV exists):  Read selections, scaffold each repo, write
                         manifest.fleet.config.yaml." \
                    "Options" "  --dry-run                  Explicit preview; no writes
  -y, --yes                  Apply the current fleet init phase
  --depth N|auto             Scan depth in Phase 1; auto deepens to the
                             shallowest level with repos, capped (default: auto)
  --all-folders              Write every scanned folder to the TSV
  -f, --force                Overwrite existing files (re-runs Phase 1 + skips guard)
  -n, --name                 Fleet name (prompted if not provided)
  --create-repo-private      In Phase 2, create a private GitHub repo for each scaffolded dir
  --create-repo-public       In Phase 2, create a public GitHub repo for each scaffolded dir" \
                    "Examples" "  manifest init fleet                 # Phase 1: discover
  manifest init fleet --dry-run       # Preview current phase
  vim manifest.fleet.tsv             # edit SELECT column
  manifest init fleet -y              # Apply current phase
  manifest init fleet --create-repo-private -y   # Phase 2 + create private GitHub repos" \
                    "Exit codes (Phase 2)" "  0  All directories initialized (and gh ok if requested)
  1  One or more directories failed to init or to create their gh repo
  2  TSV references one or more directories that don't exist on disk"
                return 0
                ;;
            *)
                _render_help_error \
                    "Unknown option: $1" \
                    "manifest init fleet [--depth N|auto] [--all-folders] [--force] [--dry-run] [--name NAME] [--create-repo-private|--create-repo-public]"
                return 1
                ;;
        esac
    done

    local root_dir="$(pwd)"
    local start_file="$root_dir/manifest.fleet.tsv"
    local config_file="$root_dir/manifest.fleet.config.yaml"

    # Phase 1: No TSV exists yet — run discovery.
    # Also re-runs Phase 1 if --force is given AND no fleet config exists yet
    # (so users can regenerate the TSV before applying it).
    if [[ ! -f "$start_file" ]] || [[ "$force" == "true" && ! -f "$config_file" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _manifest_init_fleet_dry_run_phase1 "$root_dir" "$depth" "$start_file" "$force" "$create_repo_visibility" "$all_folders"
            return $?
        fi

        manifest_execution_apply_header
        echo ""
        echo "Phase 1/2: Discovering directories…"
        echo "After this completes, review manifest.fleet.tsv and adjust SELECT=true/false,"
        echo "then re-run 'manifest init fleet' to apply your selections (Phase 2)."
        if [[ -n "$create_repo_visibility" ]]; then
            echo ""
            echo "Note: --create-repo-$create_repo_visibility applies in Phase 2."
            echo "      Re-run with the same flag after editing manifest.fleet.tsv."
        fi
        echo ""

        local start_args=("--depth" "$depth")
        if [[ "$force" == "true" ]]; then
            start_args+=("--force")
        fi
        if [[ "$all_folders" == "true" ]]; then
            start_args+=("--all-folders")
        fi

        _fleet_start "${start_args[@]}"
        return $?
    fi

    # Phase 2: TSV exists — guard against accidental re-scan that would
    # discard the user's edits unless --force is explicit.
    local stale_tsv=false
    if _fleet_init_tsv_is_stale "$start_file" "$config_file"; then
        stale_tsv=true
    fi

    if [[ "$dry_run" == "true" ]]; then
        _manifest_init_fleet_dry_run_phase2 "$root_dir" "$start_file" "$config_file" "$force" "$fleet_name" "$create_repo_visibility" "$stale_tsv"
        return $?
    fi

    if [[ "$stale_tsv" == "true" ]]; then
        log_warning "manifest.fleet.tsv has not been edited since it was generated."
        echo ""
        echo "  If you meant to apply Phase 1 results without changes, that's fine —"
        echo "  re-run with --force to acknowledge:"
        echo "    manifest init fleet --force"
        echo ""
        echo "  Otherwise, edit manifest.fleet.tsv first to set SELECT=true/false,"
        echo "  then re-run 'manifest init fleet'."
        return 1
    fi

    echo ""
    manifest_execution_apply_header
    echo "Phase 2/2: Applying TSV selections…"
    echo ""

    if [[ "$force" == "true" ]]; then
        fleet_args+=("--force")
    fi

    if [[ -n "$fleet_name" ]]; then
        fleet_args+=("--name" "$fleet_name")
    fi

    if [[ -n "$create_repo_visibility" ]]; then
        fleet_args+=("--create-repo-$create_repo_visibility")
    fi

    _fleet_init "${fleet_args[@]}"
}

# -----------------------------------------------------------------------------
# Function: _fleet_init_tsv_is_stale (internal)
# -----------------------------------------------------------------------------
# Returns 0 (stale = unedited) when the TSV's SELECT column matches the
# default-selection fingerprint that _fleet_start wrote into the header,
# meaning the user ran Phase 2 without touching selections.
# Returns 1 (edited, or no fingerprint, or cannot tell) otherwise — in
# which case Phase 2 proceeds without prompting.
#
# We deliberately err on the side of *not* flagging as stale so we don't
# false-positive and block legitimate Phase 2 runs (e.g. on TSVs written
# by older versions of generate_start_tsv that lack the fingerprint).
# -----------------------------------------------------------------------------
_fleet_init_tsv_is_stale() {
    local tsv="$1"
    local config="$2"

    [[ -f "$tsv" ]] || return 1
    # If a fleet config already exists, we're past phase 2 — not stale.
    [[ -f "$config" ]] && return 1

    # Pull the embedded default-selection fingerprint. Old TSVs (pre-#15)
    # have no such header — treat as edited so we don't break them.
    local stored_hash
    stored_hash=$(awk '/^# DEFAULT-SELECT-HASH:/ {print $3; exit}' "$tsv")
    [[ -z "$stored_hash" ]] && return 1

    # Recompute the fingerprint from the current SELECT column. If the
    # user has edited even one row, the hashes diverge.
    local current_hash
    current_hash=$(awk -F'\t' '
        /^#/ {next}
        $1 == "" {next}
        {print $1}
    ' "$tsv" | _manifest_hash_short)

    [[ "$stored_hash" == "$current_hash" ]] && return 0
    return 1
}

# -----------------------------------------------------------------------------
# Function: manifest_init_dispatch
# -----------------------------------------------------------------------------
# Main entry point for 'manifest init' command routing.
#
# ARGUMENTS:
#   $1 - Scope: "repo" or "fleet"
#   $@ - Remaining arguments passed to the scope handler
# -----------------------------------------------------------------------------
manifest_init_dispatch() {
    local scope="${1:-}"
    shift || true

    case "$scope" in
        repo)
            manifest_init_repo "$@"
            ;;
        fleet)
            manifest_init_fleet "$@"
            ;;
        -h|--help|help)
            _render_help \
                "manifest init <repo|fleet> [options]" \
                "Scaffold a repository or fleet. No remote operations." \
                "Scopes" "  repo    Scaffold single repo (VERSION, CHANGELOG, docs, .gitignore)
  fleet   Two-phase fleet setup via directory scanning" \
                "More" "  manifest init repo --help    Per-repo options
  manifest init fleet --help   Phase 1 / Phase 2 details"
            ;;
        "")
            _render_help_error "init requires a scope" "manifest init <repo|fleet>"
            return 1
            ;;
        *)
            _render_help_error "Unknown scope: $scope" "manifest init <repo|fleet>"
            return 1
            ;;
    esac
}

# Export public functions
export -f manifest_init_repo
export -f manifest_init_fleet
export -f manifest_init_dispatch
# Scaffolding helpers (used by orchestrator, documentation, fleet)
export -f ensure_required_files create_default_readme create_default_changelog
export -f create_default_gitignore ensure_gitignore_smart
