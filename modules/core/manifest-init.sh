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
#
# NO-CLOBBER CONTRACT (scaffold writers):
#   Never overwrite an existing real file. When Manifest wants to provide a
#   default and the real file is already present, write "<name>.manifest" as a
#   merge reference instead. When both the real file and the sidecar already
#   exist, refresh the sidecar with the latest Manifest-advised content — still
#   never touch the real file. Sole exception: an empty .gitignore
#   (comments/blanks only) is treated as "no content yet" and may be filled
#   once — see ensure_gitignore_smart.
# =============================================================================

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_INIT_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_INIT_LOADED=1

# =============================================================================
# FILE CREATION AND VALIDATION FUNCTIONS
# =============================================================================

# Write scaffold content without clobbering the real file.
#
#   $1 - destination path (absolute or relative)
#   $2 - writer function name: writer <path>  (must write only to that path)
#
# Outcomes (printed to stdout, one of):
#   <basename>              — created the real file (it was missing)
#   <basename>.manifest     — real file existed; created or refreshed the
#                             sidecar with the latest Manifest defaults
#
# Never overwrites the real file. The sidecar is always kept current with the
# CLI's advised content when the real file is present. Returns 0 on success,
# 1 if the writer fails.
write_scaffold_no_clobber() {
    local dest="$1"
    local writer="$2"
    local base sidecar_dest

    if [[ -z "$dest" || -z "$writer" ]]; then
        log_error "write_scaffold_no_clobber: dest and writer are required"
        return 1
    fi
    if ! declare -F "$writer" >/dev/null 2>&1; then
        log_error "write_scaffold_no_clobber: writer '$writer' is not a function"
        return 1
    fi

    base="$(basename "$dest")"
    sidecar_dest="${dest}.manifest"

    if [[ ! -e "$dest" ]]; then
        if ! "$writer" "$dest"; then
            return 1
        fi
        printf '%s\n' "$base"
        return 0
    fi

    # Real file exists — never clobber it. Create or refresh the sidecar with
    # the latest Manifest-advised content so operators always have a current
    # merge reference.
    if ! "$writer" "$sidecar_dest"; then
        return 1
    fi
    printf '%s\n' "${base}.manifest"
    return 0
}

# Check for required files and create them if missing
ensure_required_files() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
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

    # Crawl-privacy defaults (private/safe by default for deployed surfaces)
    local privacy_result
    privacy_result=$(ensure_crawl_privacy_files "$project_root") || true
    if [[ -n "$privacy_result" ]]; then
        # shellcheck disable=SC2206
        created_files+=($privacy_result)
    fi

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

# True when a directory already has the full Manifest init scaffold set.
# Used by fleet init to pass over members that were previously initialized
# (avoids writing .manifest sidecars on every fleet re-run). Repo init still
# calls ensure_repo_scaffold for idempotent backfill of any missing pieces.
manifest_repo_scaffold_is_complete() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    [[ -n "$project_root" ]] || return 1
    [[ -f "$project_root/VERSION" ]] \
        && [[ -f "$project_root/README.md" ]] \
        && [[ -f "$project_root/CHANGELOG.md" ]] \
        && [[ -f "$project_root/.gitignore" ]] \
        && [[ -f "$project_root/robots.txt" ]] \
        && [[ -f "$project_root/ai.txt" ]] \
        && [[ -f "$project_root/scripts/run-tests.sh" ]] \
        && [[ -f "$project_root/.env.example" ]]
}

# Shared repo scaffold used by both `manifest init repo` and `manifest init fleet`.
# Composes required files (incl. crawl privacy) + release gate + env example.
# All writers honor write_scaffold_no_clobber (real file or .manifest sidecar).
ensure_repo_scaffold() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"

    if [[ -z "$project_root" || ! -d "$project_root" ]]; then
        log_error "ensure_repo_scaffold: project root missing or not a directory: ${project_root:-<empty>}"
        return 1
    fi

    if ! ensure_required_files "$project_root"; then
        return 1
    fi

    # Best-effort: a scaffold hiccup warns inside the helper but does not fail
    # the overall init (parity with historical init-repo behavior).
    ensure_release_gate_script "$project_root" || true
    ensure_env_files "$project_root" || true
    return 0
}

# Scaffold the release gate script `manifest ship` auto-detects
# (scripts/run-tests.sh). Since v56.0.0 the release gate is fail-closed: a
# releaseable repo with no test command refuses to release, and inside
# `ship fleet` that refusal aborts the whole sweep. Repos born via
# `manifest init` therefore get a gate on day one, so a fleet's FIRST
# `ship fleet` never dies on a gate-less member.
#
# No-clobber: an existing scripts/run-tests.sh is never overwritten. When one
# already exists, write scripts/run-tests.sh.manifest as a merge reference.
# Deliberately NOT called from the orchestrator's ship-time repair paths —
# materializing an executable mid-ship that the gate would then immediately
# run is a surprise; gates appear at init time only.
ensure_release_gate_script() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local gate_file="$project_root/scripts/run-tests.sh"
    local result

    if ! mkdir -p "$project_root/scripts"; then
        log_warning "Could not create scripts/ — release gate not scaffolded."
        return 1
    fi

    result="$(write_scaffold_no_clobber "$gate_file" create_default_run_tests)" || {
        log_warning "Could not write scripts/run-tests.sh — release gate not scaffolded."
        return 1
    }

    case "$result" in
        "run-tests.sh")
            chmod +x "$gate_file"
            log_success "Created scripts/run-tests.sh (release gate — 'manifest ship' runs it before releasing)"
            ;;
        "run-tests.sh.manifest")
            chmod +x "$project_root/scripts/run-tests.sh.manifest" 2>/dev/null || true
            if [[ -f "$gate_file" ]]; then
                log_success "Wrote scripts/run-tests.sh.manifest (existing gate preserved — latest Manifest default)"
            fi
            ;;
        "")
            : # unreachable under current write_scaffold_no_clobber contract
            ;;
    esac
    return 0
}

# Generate the default scripts/run-tests.sh release gate.
#
# The PROJECT CHECKS section is detected once, here at scaffold time, from the
# repo's OWN declared verification (package.json scripts, Cargo, .NET .sln/.csproj,
# go, pyproject/tox, a Makefile target, or a compose file) — the generated
# script contains plain reviewable commands run with the developer's host
# toolchain, not runtime magic and no imposed container. A Docker-only repo
# (a Dockerfile with no recognizable source manifest) is left to the loud path
# rather than force a container build by default. When the repo declares no
# build or test, the full-tier gate refuses (fail-closed) rather than reporting
# a green "verified" it never earned; the emitted message tells the owner how to
# fix it (add a check, set release_gate_command, or take the audited
# release_gate=none bypass). The cheap BASELINE floor (VERSION shape, shell
# syntax, JSON parse) always runs.
create_default_run_tests() {
    local gate_file="$1"
    local project_root
    project_root="$(dirname "$(dirname "$gate_file")")"

    # --- Detect the repo's OWN declared verification (scaffold-time) ---------
    # Wire the gate to the developer's existing toolchain, host-native. Only
    # what the project actually declares is emitted — no invented commands, no
    # imposed toolchain (containerization is opt-in via release_gate_command,
    # never baked in here).
    local checks=""

    if [[ -f "$project_root/Cargo.toml" ]]; then
        checks+='    run_check cargo test'$'\n'
    fi

    if [[ -f "$project_root/package.json" ]]; then
        local pm s
        # Corepack's declared package manager wins; otherwise infer from lockfile.
        pm="$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\([a-z]*\)@.*/\1/p' "$project_root/package.json" 2>/dev/null | head -1)"
        case "$pm" in
            npm|pnpm|yarn|bun) ;;
            *)
                if [[ -f "$project_root/pnpm-lock.yaml" ]]; then pm="pnpm"
                elif [[ -f "$project_root/yarn.lock" ]]; then pm="yarn"
                elif [[ -f "$project_root/bun.lockb" || -f "$project_root/bun.lock" ]]; then pm="bun"
                else pm="npm"; fi
                ;;
        esac
        for s in lint typecheck type-check build test; do
            grep -qE "\"$s\"[[:space:]]*:" "$project_root/package.json" || continue
            # Skip npm's scaffold placeholder ("Error: no test specified").
            if [[ "$s" == "test" ]] && grep -q 'Error: no test specified' "$project_root/package.json"; then
                continue
            fi
            # `<pm> run <script>` runs the package.json script across every
            # manager (bun's bare `bun test` would bypass it, so `run` is used).
            checks+="    run_check $pm run $s"$'\n'
        done
    fi

    # .NET: a solution or project file (often nested under src/), no manifest of
    # its own on the JS/Rust side.
    if [[ -n "$(find "$project_root" -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -print 2>/dev/null | head -1)" ]]; then
        checks+='    run_check dotnet build'$'\n'
        checks+='    run_check dotnet test'$'\n'
    fi

    if [[ -f "$project_root/go.mod" ]]; then
        checks+='    run_check go build ./...'$'\n'
        checks+='    run_check go test ./...'$'\n'
    fi

    if [[ -f "$project_root/pyproject.toml" ]] && { [[ -d "$project_root/tests" ]] || [[ -d "$project_root/test" ]]; }; then
        checks+='    run_check python3 -m pytest -q'$'\n'
    fi
    if [[ -f "$project_root/tox.ini" ]]; then
        checks+='    run_check tox'$'\n'
    fi

    # Make is a fallback: only when no more specific toolchain declared a check,
    # since a Makefile's targets usually just wrap one of the above.
    if [[ -z "$checks" ]]; then
        local mk m
        for m in Makefile makefile GNUmakefile; do
            [[ -f "$project_root/$m" ]] && { mk="$project_root/$m"; break; }
        done
        if [[ -n "${mk:-}" ]]; then
            grep -qE '^build:' "$mk" && checks+='    run_check make build'$'\n'
            grep -qE '^test:'  "$mk" && checks+='    run_check make test'$'\n'
        fi
    fi

    # Compose/config repo: a compose file and no app source above. Validating the
    # compose file is the honest check (compose is its own toolchain here).
    if [[ -z "$checks" ]]; then
        local cf
        for cf in "$project_root"/docker-compose*.yml "$project_root"/docker-compose*.yaml \
                  "$project_root"/compose*.yml "$project_root"/compose*.yaml; do
            [[ -e "$cf" ]] || continue
            checks+='    run_check docker compose config -q'$'\n'
            break
        done
    fi

    # Nothing real declared. A gate that passed here would report "verified"
    # without verifying anything, so it refuses on the release (full) tier and
    # says exactly how to fix it. release_gate=none is the audited escape hatch.
    if [[ -z "$checks" ]]; then
        checks='    bad "no build or test verification is declared by this repo — the release gate cannot certify it"'$'\n'
        checks+='    note "A passing gate here would claim \"verified\" without verifying anything. Do ONE of:"'$'\n'
        checks+='    note "  1. add your real check above:  run_check <build/test command>"'$'\n'
        checks+='    note "  2. point the gate elsewhere:   set release_gate_command (MANIFEST_CLI_RELEASE_GATE_COMMAND)"'$'\n'
        checks+='    note "  3. bypass deliberately:         set release_gate=none (audited, unverified)"'$'\n'
    fi

    # --- Static head (quoted heredoc: nothing expands) -----------------------
    cat > "$gate_file" << 'MANIFEST_CLI_GATE_HEAD'
#!/usr/bin/env bash
# Release gate — scaffolded by Manifest CLI (manifest init).
#
# `manifest ship` refuses to release a repo without a verification gate
# (release_gate=local-tests, fail-closed) and auto-detects this script:
#   ./scripts/run-tests.sh --tier <smoke|full> --jobs N --no-cache
#
#   --tier smoke        baseline checks only (fast preflight)
#   --tier full         baseline + project checks (the release default)
#   --jobs, --no-cache  accepted for the ship contract; unused here
#
# The BASELINE section proves structural sanity (VERSION shape, shell syntax,
# JSON parse). It is NOT a substitute for real tests — extend the PROJECT
# CHECKS section with this repo's actual suite as it grows.

set -uo pipefail

TIER="full"
while [ $# -gt 0 ]; do
    case "$1" in
        --tier)   shift; TIER="${1:-full}" ;;
        --tier=*) TIER="${1#--tier=}" ;;
        --jobs)   shift ;;
    esac
    [ $# -gt 0 ] && shift
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

FAILED=0
note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok    %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; FAILED=1; }
run_check() {
    printf 'run   %s\n' "$*"
    if "$@"; then ok "$*"; else bad "$*"; fi
}

# Tracked files by pattern — git's view when available, pruned find otherwise.
list_files() {
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git ls-files -- "$1" 2>/dev/null
    else
        find . -type d \( -name .git -o -name node_modules -o -name target \
            -o -name dist -o -name build -o -name .next -o -name vendor \) -prune \
            -o -type f -name "$1" -print | sed 's|^\./||'
    fi
}

# ------------------------------------------------------------------ BASELINE

if [ -f VERSION ]; then
    v="$(tr -d '[:space:]' < VERSION)"
    if printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.+-]*)?$'; then
        ok "VERSION ($v)"
    else
        bad "VERSION is not semver-shaped: '$v'"
    fi
else
    bad "VERSION file missing"
fi

sh_total=0 sh_bad=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    sh_total=$((sh_total+1))
    bash -n "$f" 2>/dev/null || { bad "shell syntax: $f"; sh_bad=$((sh_bad+1)); }
done < <(list_files '*.sh')
[ "$sh_bad" -eq 0 ] && ok "shell syntax ($sh_total file(s) checked)"

if command -v jq >/dev/null 2>&1; then
    json_total=0 json_bad=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        json_total=$((json_total+1))
        jq -e . "$f" >/dev/null 2>&1 || { bad "invalid JSON: $f"; json_bad=$((json_bad+1)); }
    done < <(list_files '*.json')
    [ "$json_bad" -eq 0 ] && ok "JSON parse ($json_total file(s) checked)"
else
    note "jq not installed - skipping JSON parse check"
fi

# ------------------------------------------------------------- PROJECT CHECKS
# Detected at scaffold time from the repo layout. This section is yours:
# replace or extend it with the repo's real test suite.

if [ "$TIER" = "full" ]; then
MANIFEST_CLI_GATE_HEAD

    # --- Detected project checks (expanded now, on purpose) ------------------
    printf '%s' "$checks" >> "$gate_file"

    # --- Static tail ----------------------------------------------------------
    cat >> "$gate_file" << 'MANIFEST_CLI_GATE_TAIL'
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
    echo "run-tests: FAIL (tier: $TIER)"
    exit 1
fi
echo "run-tests: PASS (tier: $TIER)"
MANIFEST_CLI_GATE_TAIL
}

# Derive this repo's owned-var env prefix under the env.prefix policy.
#   env.prefix: off|none       → empty (policy disabled; starter vars carry none)
#   env.prefix: <value>        → that value, namespaced by the repo dir body
#                                without repeating a matching leading segment
#                                (`ACME_` + `acme.web` → `ACME_WEB_`)
#   env.prefix unset (default) → DERIVED from the full project name, vendor-neutral
#                                (`fidence.app.kanizsa` → `FIDENCE_APP_KANIZSA_`,
#                                 `my-tool` → `MY_TOOL_`)
_manifest_env_prefix_for_repo() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local raw="${MANIFEST_CLI_ENV_PREFIX:-}"
    local lowered
    lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
    case "$lowered" in
        off|none|disabled|false|0) printf ''; return 0 ;;
    esac

    local body
    if [[ -n "$raw" ]]; then
        local first core
        body="$(basename "$project_root")"
        first="${body%%.*}"
        core="${raw%_}"
        if [[ "$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9')" == "$core" ]]; then
            body="${body#*.}"
        fi
        body="$(printf '%s' "$body" | tr '.-' '__' | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9_')"
        printf '%s%s_' "$raw" "$body"
        return 0
    fi

    body="$(basename "$project_root" | tr '.-' '__' | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9_')"
    [[ -n "$body" ]] && printf '%s_' "$body"
}

# Locate the component spec file whose `env:` block is the single source of
# truth for this repo's environment schema (D-ENV-2). Empty output = no spec.
_manifest_env_spec_file() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local candidate
    for candidate in service.spec.yaml app.spec.yaml; do
        if [[ -f "$project_root/$candidate" ]]; then
            printf '%s' "$project_root/$candidate"
            return 0
        fi
    done
    return 0
}

# Render .env.example content from a spec `env:` block onto stdout.
# Secret entries are emitted commented-out with their OpenBao path — a secret
# value never belongs in any .env file (D-ENV-3).
_manifest_env_render_example() {
    local spec_file="$1"
    local project_root="$2"
    local repo_dir
    repo_dir="$(basename "$project_root")"

    printf '# .env.example — generated by Manifest CLI from %s `env:`.\n' "$(basename "$spec_file")"
    printf '# Framework names (DATABASE_URL, NEXT_PUBLIC_*, …) are bridged at injection\n'
    printf '# boundaries, not stored here. Edit the spec, then: manifest env generate -y\n'

    local count
    count="$(yq e '.env | length' "$spec_file" 2>/dev/null)"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0

    local i name description required default secret public framework_name group
    for ((i = 0; i < count; i++)); do
        name="$(yq e ".env[$i].name // \"\"" "$spec_file" 2>/dev/null)"
        [[ -n "$name" ]] || continue
        description="$(yq e ".env[$i].description // \"\"" "$spec_file" 2>/dev/null)"
        required="$(yq e ".env[$i].required // false" "$spec_file" 2>/dev/null)"
        default="$(yq e ".env[$i].default // \"\"" "$spec_file" 2>/dev/null)"
        secret="$(yq e ".env[$i].secret // false" "$spec_file" 2>/dev/null)"
        public="$(yq e ".env[$i].public // false" "$spec_file" 2>/dev/null)"
        framework_name="$(yq e ".env[$i].framework_name // \"\"" "$spec_file" 2>/dev/null)"
        group="$(yq e ".env[$i].group // \"app\"" "$spec_file" 2>/dev/null)"

        printf '\n'
        local traits=""
        [[ "$required" == "true" ]] && traits+="required" || traits+="optional"
        [[ "$secret" == "true" ]] && traits+=", secret"
        [[ "$public" == "true" ]] && traits+=", public (build-time)"
        if [[ -n "$description" ]]; then
            printf '# %s — %s (%s)\n' "$name" "$description" "$traits"
        else
            printf '# %s (%s)\n' "$name" "$traits"
        fi
        [[ -n "$framework_name" ]] && printf '# bridged framework name: %s (materialized at injection boundaries only)\n' "$framework_name"
        if [[ "$secret" == "true" ]]; then
            printf '# secret → OpenBao via ESO: secret/{env}/%s/%s — never a literal value in any .env\n' "$repo_dir" "$group"
            printf '# %s=\n' "$name"
        else
            printf '%s=%s\n' "$name" "$default"
        fi
    done
}

# Scaffold .env.example. Three paths:
#   spec with `env:`      generate .env.example from it
#   spec without `env:`   seed a starter `env:` block first, then generate
#   no spec               starter .env.example (honoring the configured prefix)
# No-clobber: an existing .env.example is never overwritten. When one already
# exists, write .env.example.manifest as a merge reference. Explicit
# regeneration of the live example is `manifest env generate -y`.
ensure_env_files() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local example_file="$project_root/.env.example"
    local result

    # Spec seeding only on first materialization of the live example — never
    # mutate a service/app spec just to write a sidecar reference.
    if [[ ! -f "$example_file" ]]; then
        local prefix spec_file
        prefix="$(_manifest_env_prefix_for_repo "$project_root")"
        spec_file="$(_manifest_env_spec_file "$project_root")"

        if [[ -n "$spec_file" ]] && command -v yq >/dev/null 2>&1; then
            local has_env
            has_env="$(yq e '.env | length > 0' "$spec_file" 2>/dev/null)"
            if [[ "$has_env" != "true" ]]; then
                log_info "Seeding starter env: block in $(basename "$spec_file")..."
                local repo_dir
                repo_dir="$(basename "$project_root")"
                PREFIX="$prefix" REPO_DIR="$repo_dir" yq e -i '.env = [
                    {"name": strenv(PREFIX) + "LOG_LEVEL", "description": "Structured-log verbosity", "required": false, "default": "info", "secret": false},
                    {"name": strenv(PREFIX) + "SERVICE_FQN", "description": "Canonical service identity for logs/metrics", "required": false, "default": strenv(REPO_DIR), "secret": false}
                ]' "$spec_file" 2>/dev/null || {
                    log_warning "Could not seed env: block in $(basename "$spec_file") — writing starter .env.example instead."
                }
            fi
        fi
    fi

    result="$(write_scaffold_no_clobber "$example_file" create_default_env_example)" || {
        log_warning "Could not write .env.example — env scaffold skipped."
        return 1
    }

    case "$result" in
        ".env.example")
            log_success "Created .env.example (env schema template — 'manifest env' manages it)"
            ;;
        ".env.example.manifest")
            log_success "Wrote .env.example.manifest (existing .env.example preserved — latest Manifest default)"
            ;;
    esac
    return 0
}

# Writer for write_scaffold_no_clobber — emits .env.example content at $1.
create_default_env_example() {
    local example_file="$1"
    local project_root
    project_root="$(dirname "$example_file")"
    local prefix spec_file
    prefix="$(_manifest_env_prefix_for_repo "$project_root")"
    spec_file="$(_manifest_env_spec_file "$project_root")"

    if [[ -n "$spec_file" ]] && command -v yq >/dev/null 2>&1; then
        local has_env
        has_env="$(yq e '.env | length > 0' "$spec_file" 2>/dev/null)"
        if [[ "$has_env" == "true" ]]; then
            if ! _manifest_env_render_example "$spec_file" "$project_root" > "$example_file"; then
                rm -f "$example_file"
                return 1
            fi
            return 0
        fi
    fi

    local prefix_note
    if [[ -n "$prefix" ]]; then
        prefix_note="# Env prefix policy is on: owned vars start with ${prefix} (framework names are exempt)."
    else
        prefix_note="# Env prefix policy is off (default). Set env.prefix to require an owned-var prefix."
    fi
    cat > "$example_file" << MANIFEST_CLI_ENV_STARTER
# .env.example — scaffolded by Manifest CLI.
${prefix_note}
# Framework names (DATABASE_URL, NEXT_PUBLIC_*, …) are bridged at injection
# boundaries, not stored here.
# Declare vars in service.spec.yaml/app.spec.yaml \`env:\`, then:
#   manifest env generate -y
#
# ${prefix}LOG_LEVEL=info
MANIFEST_CLI_ENV_STARTER
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
# - .gitignore with entries → create/refresh .gitignore.manifest (never touch real)
#
# Output (stdout):
#   ".gitignore"                 — created new file
#   ".gitignore:empty-overwrite" — overwrote a .gitignore that had no real entries
#   ".gitignore.manifest"        — created or refreshed the sidecar reference
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

    # Count non-blank, non-comment lines (actual ignore entries).
    # grep -c prints "0" and exits 1 when there are no matches — do NOT append
    # another "0" via `|| echo 0` (that yields "0\n0" and breaks the arithmetic test).
    local entry_count
    entry_count=$(grep -cvE '^\s*$|^\s*#' "$gitignore_file" 2>/dev/null || true)
    entry_count="${entry_count:-0}"
    # Strip any accidental whitespace/newlines
    entry_count="${entry_count//$'\n'/}"
    entry_count="${entry_count//[[:space:]]/}"
    [[ "$entry_count" =~ ^[0-9]+$ ]] || entry_count=0

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

    # Real .gitignore has entries — never clobber it. Create or refresh the
    # sidecar with the latest Manifest-advised defaults.
    if [[ -f "$manifest_ref" ]]; then
        log_info "Refreshing .gitignore.manifest with latest Manifest defaults..."
    else
        log_info "Existing .gitignore has entries, creating .gitignore.manifest as reference..."
    fi
    if ! create_default_gitignore "$manifest_ref"; then
        log_error "Failed to write .gitignore.manifest in $project_root"
        return 1
    fi
    log_success "Wrote .gitignore.manifest (existing .gitignore preserved — merge as needed)"
    echo ".gitignore.manifest"
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
robots.txt.manifest
ai.txt.manifest
.env.example.manifest
scripts/run-tests.sh.manifest

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
# Environment, secrets, and local/generated config
# =============================================================================
.env
.env.*
*.local.yaml
*.local.yml
*.local.json
*.local.toml
*.secret.yaml
*.secret.yml
*.secret.json
*.secret.*
# Keep authoring templates trackable — example/template variants stay in git.
!.env.example
!.env.template
!*.example.yaml
!*.example.yml
!*.example.json
!*.example.toml
!*.template.yaml
!*.template.yml
!*.template.json
!*.template.toml

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

# Crawl-privacy defaults — private/safe by default for anything that might be
# deployed as a web surface. Uses write_scaffold_no_clobber: create the real
# file when missing; write a .manifest sidecar when the real file already
# exists; never overwrite either.
#
# Prints space-separated basenames of created files (may be empty).
ensure_crawl_privacy_files() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local created=()
    local result

    result="$(write_scaffold_no_clobber "$project_root/robots.txt" create_default_robots_txt)" || return 1
    [[ -n "$result" ]] && created+=("$result")

    result="$(write_scaffold_no_clobber "$project_root/ai.txt" create_default_ai_txt)" || return 1
    [[ -n "$result" ]] && created+=("$result")

    if [[ ${#created[@]} -gt 0 ]]; then
        log_success "Crawl privacy: ${created[*]} (Disallow all — private/safe by default)"
        printf '%s\n' "${created[*]}"
    fi
    return 0
}

create_default_robots_txt() {
    local dest="$1"
    cat > "$dest" << 'EOF'
# Manifest CLI — private/safe by default.
# Search engines and AI crawlers are disallowed until you deliberately open
# this surface. Merge from robots.txt.manifest if this file already existed
# at init time and you want Manifest's defaults.
#
# To go public later: replace Disallow rules with your allowlist, or delete
# this file and serve framework-native robots.

User-agent: *
Disallow: /

# AI / training crawlers (explicit; some ignore the wildcard Disallow)
User-agent: GPTBot
Disallow: /

User-agent: ChatGPT-User
Disallow: /

User-agent: Google-Extended
Disallow: /

User-agent: ClaudeBot
Disallow: /

User-agent: anthropic-ai
Disallow: /

User-agent: Bytespider
Disallow: /

User-agent: CCBot
Disallow: /

User-agent: Diffbot
Disallow: /

User-agent: FacebookBot
Disallow: /

User-agent: GoogleOther
Disallow: /

User-agent: ImagesiftBot
Disallow: /

User-agent: Omgilibot
Disallow: /

User-agent: PerplexityBot
Disallow: /
EOF
}

create_default_ai_txt() {
    local dest="$1"
    cat > "$dest" << 'EOF'
# Manifest CLI — private/safe by default.
# Machine-readable policy for AI agents and crawlers. This surface is not
# available for crawling, indexing, training, or quoting unless an operator
# deliberately replaces this file.
#
# contact: (set by the repo owner)
# If ai.txt already existed at init, see ai.txt.manifest for Manifest defaults.

User-Agent: *
Allow: none
Disallow: /
Crawl: no
Train: no
Index: no
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
                    "Scaffold a single repository: VERSION, CHANGELOG.md, README.md, docs/, .gitignore,
scripts/run-tests.sh (the release gate 'manifest ship' auto-detects — fail-closed since v56).
Idempotent — safe to re-run. Optionally creates a GitHub repo via 'gh repo create'." \
                    "Options" "  --dry-run                  Explicit preview; no writes
  -y, --yes                  Apply the scaffold plan
  -f, --force                Recreate manifest.config.local.yaml if present
                             (scaffold content files stay no-clobber; existing
                             content gets a .manifest sidecar merge reference)
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

    local project_root="${MANIFEST_CLI_PROJECT_ROOT:-$(pwd)}"
    if [[ -n "$create_repo_visibility" ]]; then
        _manifest_github_repo_target "$project_root" >/dev/null || return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "Dry run — manifest init repo: $project_root"
        echo ""
        if ! _manifest_dir_is_own_git_repository "$project_root"; then
            echo "  would create: .git/   (git init)"
        else
            echo "  exists:       .git/"
        fi
        local f
        for f in VERSION README.md CHANGELOG.md .gitignore robots.txt ai.txt; do
            if [[ -f "$project_root/$f" ]]; then
                # Scaffold files are never overwritten — even with --force.
                # --force only recreates manifest.config.local.yaml (below).
                # When a content file already exists, apply writes "<name>.manifest"
                # as a merge reference (see write_scaffold_no_clobber).
                if [[ "$f" == "robots.txt" || "$f" == "ai.txt" || "$f" == ".gitignore" ]]; then
                    if [[ -f "$project_root/${f}.manifest" ]]; then
                        echo "  exists:          $f   (would refresh ${f}.manifest)"
                    else
                        echo "  exists:          $f   (would write ${f}.manifest as merge reference)"
                    fi
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
        if [[ -f "$project_root/scripts/run-tests.sh" ]]; then
            if [[ -f "$project_root/scripts/run-tests.sh.manifest" ]]; then
                echo "  exists:          scripts/run-tests.sh   (would refresh scripts/run-tests.sh.manifest)"
            else
                echo "  exists:          scripts/run-tests.sh   (would write scripts/run-tests.sh.manifest)"
            fi
        else
            echo "  would create:    scripts/run-tests.sh   (release gate — 'manifest ship' runs it)"
        fi
        if [[ -f "$project_root/.env.example" ]]; then
            if [[ -f "$project_root/.env.example.manifest" ]]; then
                echo "  exists:          .env.example   (would refresh .env.example.manifest)"
            else
                echo "  exists:          .env.example   (would write .env.example.manifest)"
            fi
        else
            echo "  would create:    .env.example   (env schema template)"
        fi
        if [[ -f "$project_root/manifest.config.local.yaml" && "$force" != "true" ]]; then
            echo "  exists:          manifest.config.local.yaml"
        else
            if [[ -f "$project_root/manifest.config.local.yaml" && "$force" == "true" ]]; then
                echo "  would recreate:  manifest.config.local.yaml   (--force)"
            else
                echo "  would create:    manifest.config.local.yaml"
            fi
        fi
        if [[ -n "$create_repo_visibility" ]]; then
            local repo_target
            repo_target="$(_manifest_github_repo_display_target "$project_root")" || return 1
            if _manifest_dir_is_own_git_repository "$project_root" \
                && git -C "$project_root" remote get-url origin >/dev/null 2>&1; then
                echo "  exists:          origin remote (gh repo create skipped)"
            else
                echo "  would gh repo create: $repo_target ($create_repo_visibility) and add as origin"
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
    if ! _manifest_dir_is_own_git_repository "$project_root"; then
        echo "No git repository found. Initializing..."
        if git init "$project_root" >/dev/null; then
            echo "  Created: .git/"
        else
            log_error "Failed to initialize git repository"
            return 1
        fi
    fi

    # Shared scaffold (same path as fleet member init): VERSION/README/CHANGELOG/
    # docs/.gitignore/robots.txt/ai.txt + release gate + .env.example.
    if ! ensure_repo_scaffold "$project_root"; then
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

    # Resolve --depth (N|auto) to a concrete scan depth; auto resolves to the
    # deepest level with repos via one pruned scan (§7.3, per-branch adaptive).
    # Keep the original spec ($depth) for the replay hint so the default
    # ("auto") replays as a bare command.
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
    while IFS=$'\t' read -r name _path _branch _version _url _submodule has_git _has_remote; do
        [[ -z "$name" ]] && continue
        ((total += 1))
    done <<< "$discovered"
    while IFS=$'\t' read -r name _path _branch _version _url _submodule has_git _has_remote; do
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
    local scaffold_count=0 already_complete_count=0
    local create_targets=()
    while IFS=$'\t' read -r name path has_git _url _branch _version; do
        [[ -z "$name" ]] && continue
        ((selected_count += 1))
        local abs_path="$root_dir/${path#./}"
        if [[ -d "$abs_path" ]]; then
            ((existing_count += 1))
            local owns_git=false
            if _manifest_dir_is_own_git_repository "$abs_path"; then
                owns_git=true
            else
                ((needs_git_count += 1))
            fi

            if declare -F manifest_repo_scaffold_is_complete >/dev/null 2>&1 \
                && manifest_repo_scaffold_is_complete "$abs_path"; then
                ((already_complete_count += 1))
            else
                ((scaffold_count += 1))
            fi

            if [[ -n "$create_repo_visibility" ]]; then
                if [[ "$owns_git" != "true" ]] \
                    || ! git -C "$abs_path" remote get-url origin >/dev/null 2>&1; then
                    local display_target
                    display_target="$(_manifest_github_repo_display_target "$abs_path")" || return 1
                    create_targets+=("$display_target")
                fi
            fi
        else
            ((missing_count += 1))
        fi
    done <<< "$selected"

    if [[ -z "$fleet_name" ]]; then
        fleet_name=$(basename "$root_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    fi

    echo ""
    echo "Dry run - manifest init fleet (Phase 2/2): $root_dir"
    echo ""
    echo "Would read:      $start_file"
    if [[ -f "$config_file" && "$force" != "true" ]]; then
        # Backfill mode: the TSV is a curated membership list — preserved, not
        # rescanned (mirrors the apply path in _fleet_init).
        echo "Would preserve:  $start_file (curated membership — not rescanned; 'manifest update fleet' rescans)"
    else
        echo "Would refresh:   $start_file (rescan at its recorded depth to capture git metadata)"
    fi
    if [[ -f "$config_file" && "$force" == "true" ]]; then
        echo "Would overwrite: $config_file"
    elif [[ -f "$config_file" ]]; then
        echo "Would preserve:  $config_file (already initialized; --force regenerates from scratch)"
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
    echo "Would scaffold:  ensure_repo_scaffold (VERSION/README/CHANGELOG/docs/.gitignore/robots.txt/ai.txt/scripts/run-tests.sh/.env.example) in $scaffold_count incomplete member(s); skip $already_complete_count already-initialized"
    if [[ -n "$create_repo_visibility" ]]; then
        echo "Would create:    ${#create_targets[@]} $create_repo_visibility GitHub repo(s) after local init"
        local target
        for target in "${create_targets[@]}"; do
            echo "  would gh repo create: $target ($create_repo_visibility)"
        done
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
  Phase 2 (TSV exists):  Read selections, write manifest.fleet.config.yaml, and
                         scaffold each selected member with the Manifest-required
                         files (VERSION/README/CHANGELOG/docs/.gitignore) — no-clobber.
                         Re-running on an already-initialized fleet is safe and
                         idempotent: it preserves the existing config and only
                         backfills members still missing files (--force regenerates
                         the config from scratch)." \
                    "Options" "  --dry-run                  Explicit preview; no writes
  -y, --yes                  Apply the current fleet init phase
  --depth N|auto             Scan depth in Phase 1; auto deepens to the
                             shallowest level with repos, capped (default: auto)
  --all-folders              Write every scanned folder to the TSV
  -f, --force                Overwrite fleet-root/config files (re-runs Phase 1 +
                             skips guard); does NOT overwrite member content —
                             VERSION/README/etc. stay no-clobber
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
    if [[ -n "$create_repo_visibility" ]]; then
        _manifest_github_repo_target "$root_dir/manifest-owner-probe" >/dev/null || return 1
    fi
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
export -f ensure_release_gate_script create_default_run_tests
export -f ensure_env_files create_default_env_example _manifest_env_prefix_for_repo _manifest_env_spec_file _manifest_env_render_example
export -f write_scaffold_no_clobber ensure_crawl_privacy_files create_default_robots_txt create_default_ai_txt
export -f ensure_repo_scaffold manifest_repo_scaffold_is_complete
