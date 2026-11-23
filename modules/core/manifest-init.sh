#!/bin/bash

# =============================================================================
# Manifest Init Module
# =============================================================================
#
# Implements: manifest init repo|fleet
#
# PURPOSE:
#   Scaffold a single repo or fleet. First step after config in the user journey.
#   Preview setup, then connect/scaffold/verify on apply; never ship.
#
# COMMANDS:
#   manifest init repo          Prepare Git, origin, scaffold and release check
#   manifest init fleet         Two-phase fleet setup via TSV discovery
#
# DEPENDENCIES:
#   - manifest-shared-functions.sh (logging, get_docs_folder, manifest_*_repo)
#   - manifest-fleet.sh (_fleet_start, _fleet_init)
#   - manifest-yaml.sh (set_yaml_value)
#
# SCAFFOLDING HELPERS:
#   ensure_required_files, create_default_readme, create_default_changelog,
#   ensure_gitignore_smart, create_default_gitignore, manifest_gitignore_upgrade
#   — defined here and used by manifest-orchestrator.sh,
#   manifest-documentation.sh, manifest-fleet.sh. They live in this module
#   because init owns the scaffolding semantics; other callers borrow them for
#   repair/idempotency on existing repos.
#
# NO-CLOBBER CONTRACT (scaffold writers):
#   Never overwrite an existing real file. When Manifest wants to provide a
#   default and the real file is already present, leave the real file alone and
#   report what the advice would add. Nothing is written beside it — the CLI is
#   the source of the advised content and renders it on demand, so a stored copy
#   would only duplicate and drift. Sole exception: an empty .gitignore
#   (comments/blanks only) is treated as "no content yet" and may be filled
#   once — see ensure_gitignore_smart.
#
#   manifest_gitignore_upgrade is consistent with this, not an exception to it:
#   it only ever APPENDS, so no existing line is overwritten, reordered, or
#   removed, and no second file appears. It is also opt-in — ensure_gitignore_smart
#   defaults to reporting, and only explicit scaffolding (`manifest init`) asks
#   for the append. A release never mutates a .gitignore.
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
#   <basename>:preserved    — the real file existed and was left untouched
#
# Never overwrites the real file, and never writes anything beside it. Earlier
# versions dropped a "<basename>.manifest" copy of the advised content as a merge
# reference; that produced a per-repo file nothing ever read, which drifted from
# the CLI that generated it and was committed by accident in some repos. The CLI
# is the source of the advised content and can render it on demand, so storing a
# second copy in every repo was pure duplication.
#
# Returns 0 on success, 1 if the writer fails.
write_scaffold_no_clobber() {
    local dest="$1"
    local writer="$2"
    local base

    if [[ -z "$dest" || -z "$writer" ]]; then
        log_error "write_scaffold_no_clobber: dest and writer are required"
        return 1
    fi
    if ! declare -F "$writer" >/dev/null 2>&1; then
        log_error "write_scaffold_no_clobber: writer '$writer' is not a function"
        return 1
    fi

    base="$(basename "$dest")"

    if [[ ! -e "$dest" ]]; then
        if ! "$writer" "$dest"; then
            return 1
        fi
        printf '%s\n' "$base"
        return 0
    fi

    printf '%s:preserved\n' "$base"
    return 0
}

# Which language/tool ecosystems does this project declare?
#
# Keyed on marker files, and deliberately coarse — one label per ecosystem, never
# per tool. A label says what the repo *is*; it never implies a command. Consumers
# map a label to their own content.
#
# Extracted so the .gitignore template and the release-gate script agree about the
# same repo. They did not before: the gate detected Go and wrote `go build ./...`
# while the .gitignore writer took no project argument at all, so one
# `manifest init` run produced a Go-shaped run-tests.sh beside a 184-rule
# .gitignore covering nine ecosystems. 70 of those 184 rules were ecosystem-specific
# and, for a Go repo, none of them applied.
#
# Written with `if` blocks rather than `[[ … ]] && echo` chains on purpose: the
# && form makes the last test's failure the function's exit status, which under
# errexit aborts the caller for the ordinary case of "this ecosystem is absent".
#
# ARGUMENTS:
#   $1 - project root
# Output (stdout): zero or more labels, one per line, from
#   go node rust python dotnet java ruby terraform docker
# RETURNS: 0 always, including when nothing is recognised (absence is not an error).
manifest_detect_project_ecosystems() {
    local project_root="${1:-}"
    [[ -n "$project_root" && -d "$project_root" ]] || return 0

    if [[ -f "$project_root/go.mod" ]]; then echo go; fi
    if [[ -f "$project_root/package.json" ]]; then echo node; fi
    if [[ -f "$project_root/Cargo.toml" ]]; then echo rust; fi
    if [[ -f "$project_root/Gemfile" ]]; then echo ruby; fi

    if [[ -f "$project_root/pyproject.toml" || -f "$project_root/setup.py" \
        || -f "$project_root/requirements.txt" || -f "$project_root/tox.ini" ]]; then
        echo python
    fi

    if [[ -f "$project_root/pom.xml" || -f "$project_root/build.gradle" \
        || -f "$project_root/build.gradle.kts" ]]; then
        echo java
    fi

    # .NET project files conventionally sit under src/, so this is not a root-only
    # test — it mirrors the release gate's own long-standing -maxdepth 3 search.
    if [[ -n "$(find "$project_root" -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) \
        -print 2>/dev/null | head -1)" ]]; then
        echo dotnet
    fi

    local candidate
    for candidate in "$project_root"/*.tf; do
        if [[ -e "$candidate" ]]; then
            echo terraform
            break
        fi
    done

    if [[ -f "$project_root/Dockerfile" ]]; then
        echo docker
    else
        for candidate in "$project_root"/docker-compose*.yml "$project_root"/docker-compose*.yaml \
                         "$project_root"/compose*.yml "$project_root"/compose*.yaml; do
            if [[ -e "$candidate" ]]; then
                echo docker
                break
            fi
        done
    fi

    return 0
}

# True when ecosystem $1 should contribute rules to the rendered .gitignore.
#
# ARGUMENTS:
#   $1 - ecosystem label to test
#   $2 - detected labels, newline-separated (may be empty)
#   $3 - "true" to emit the whole superset regardless of $2
_manifest_gitignore_wants() {
    [[ "$3" == "true" ]] && return 0
    [[ -n "$2" ]] || return 1
    grep -qxF -- "$1" <<<"$2"
}

# One line saying what a scaffolded file is FOR, for the init preview.
#
# `manifest init repo --dry-run` used to name six files with no explanation and
# two with one, and the two undescribed outliers were robots.txt and ai.txt —
# the same two a user reported finding in their repo without being able to say
# why they were there. A preview that lists a filename and nothing else asks the
# reader to consent to something it has not described.
#
# This is the single place that answers "what is this file", so the preview and
# the docs cannot drift into two different answers.
#
# ARGUMENTS:
#   $1 - scaffolded path, as the preview prints it
# Output (stdout): a short purpose phrase, never empty.
_manifest_scaffold_purpose() {
    case "$1" in
        VERSION)      echo "the version Manifest reads and bumps on ship" ;;
        README.md)    echo "project entry point; ship maintains a version block in it" ;;
        CHANGELOG.md) echo "release history; every ship appends an entry" ;;
        .gitignore)   echo "ignore rules, chosen for this project's ecosystem" ;;
        robots.txt)   echo "crawl privacy — disallows search and AI crawlers by default" ;;
        ai.txt)       echo "crawl privacy — declares no crawling, training, or indexing" ;;
        docs/)        echo "documentation folder Manifest generates into" ;;
        scripts/run-tests.sh) echo "release gate — 'manifest ship' runs it" ;;
        .env.example) echo "every variable the spec declares; secrets commented out" ;;
        service.spec.yaml) echo "env: — the one list of this repository's environment variables" ;;
        manifest.config.local.yaml) echo "per-repo settings; git-ignored" ;;
        *)            echo "scaffolded by manifest init" ;;
    esac
}

# Advised .gitignore rules that a real .gitignore does not already carry.
# Prints one missing rule per line (nothing when the file satisfies the advice).
# Comments and blank lines are ignored on both sides — only real rules count.
#
# The advice is rendered for the SAME project as the file being checked. That is
# load-bearing, not a refinement: render the superset here and the upgrade path
# would append every ecosystem's rules to a repo that declares one, re-creating
# the bloat that project-aware generation exists to remove — through a different
# door, on any repo that already had a .gitignore.
#
# ARGUMENTS:
#   $1 - path to the .gitignore(-style) file to check
#   $2 - project root (default: the file's own directory, which is where a real
#        .gitignore always lives; a caller rendering to a temp path must pass it)
manifest_gitignore_missing_rules() {
    local real_file="$1"
    local project_root="${2:-}"
    local advised
    [[ -f "$real_file" ]] || return 0
    [[ -n "$project_root" ]] || project_root="$(dirname "$real_file")"

    advised="$(mktemp)" || return 0
    if ! create_default_gitignore "$advised" "$project_root"; then
        rm -f "$advised"
        return 0
    fi

    # A rule counts as present on an exact line match — .gitignore semantics are
    # positional, so a fuzzy match would under-report and hide real gaps.
    grep -vE '^\s*$|^\s*#' "$advised" 2>/dev/null | while IFS= read -r rule; do
        grep -qxF -- "$rule" "$real_file" 2>/dev/null || printf '%s\n' "$rule"
    done
    rm -f "$advised"
    return 0
}

# For each advised rule (one per line in $2), the pattern in $1 that already
# decides the path the rule names — or an empty line when the file says nothing
# about it. One output line per input rule, in order.
#
# The file is evaluated by git itself, alone in a scratch repository, so the
# verdict is exactly what git would do with it: `check-ignore -v -n` prints the
# deciding pattern (a negation when the path is re-included) or `::` when no
# pattern matches. The rule's own path stands in for a concrete file: globs are
# filled with a sample component (`*.key` → `smp.key`, `.env.*` → `.env.smp`),
# a trailing slash is kept so directory rules are asked about a directory, and
# a leading slash is dropped because the sample is relative to the root.
#
# Without git the answer is "nothing decided" for every rule, which makes the
# caller fall back to appending — the pre-§1(a) behaviour, never a wider skip.
_manifest_gitignore_decisions() {
    local file="$1"
    local rules="$2"
    local -a samples=()
    local rule sample
    while IFS= read -r rule; do
        [[ -n "$rule" ]] || continue
        sample="${rule#!}"
        sample="${sample#/}"
        sample="${sample//\*\*\//smp/}"
        sample="${sample//\*/smp}"
        sample="${sample//\?/s}"
        # A bracket class stands in for its first member (`*.py[cod]` → `smp.pyc`).
        # Pure bash on purpose: this runs in the git-less fallback path too.
        while [[ "$sample" =~ ^(.*)\[([^]])[^]]*\](.*)$ ]]; do
            sample="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        done
        samples+=("$sample")
    done <<< "$rules"
    [[ ${#samples[@]} -gt 0 ]] || return 0

    # The scratch repository must answer from the copied file and nothing else.
    # `--template=` (empty) stops `init` copying the machine's template
    # directory, whose info/exclude would otherwise be consulted; an explicit
    # GIT_DIR/GIT_WORK_TREE beats one inherited from a hook or wrapper, which
    # would otherwise make `init` re-initialise THAT repository and
    # `check-ignore` answer from its excludes. Measured during review: both
    # leaks produced a "skipped — already covers" for a pattern the file does
    # not contain.
    local scratch
    if ! command -v git >/dev/null 2>&1 \
        || ! scratch="$(mktemp -d "${TMPDIR:-/tmp}/manifest-gitignore.XXXXXX" 2>/dev/null)" \
        || ! GIT_DIR="$scratch/.git" GIT_WORK_TREE="$scratch" git init -q --template= "$scratch" 2>/dev/null \
        || ! cp "$file" "$scratch/.gitignore" 2>/dev/null; then
        [[ -n "${scratch:-}" ]] && rm -rf "$scratch"
        local n
        for ((n = 0; n < ${#samples[@]}; n++)); do printf '\n'; done
        return 0
    fi
    # `-n` prints a line for every path, matched or not, so the output lines
    # align with the input rules. Exit status is 0/1 for matched/none and is
    # not an error either way. Only a verdict sourced from the copied file is
    # accepted; anything else prints an empty line, so a leak of any future
    # kind reads as "undecided" and the caller appends — the safe direction.
    printf '%s\n' "${samples[@]}" \
        | GIT_DIR="$scratch/.git" GIT_WORK_TREE="$scratch" \
          git -c core.excludesFile=/dev/null check-ignore -v -n --no-index --stdin 2>/dev/null \
        | awk -F'\t' '{ if ($1 ~ /^\.gitignore:/) { sub(/^[^:]*:[^:]*:/, "", $1); print $1 } else { print "" } }'
    rm -rf "$scratch"
    return 0
}

# Bring an existing .gitignore up to the current advised set, append-only.
#
# Counterpart to manifest_gitignore_missing_rules: that one *reports* the gap,
# this one *closes* it. Written for .gitignore files generated by an older CLI
# (or a `.gitignore` written from a retired `.gitignore.manifest` sidecar), which carry whatever the
# template held when they were written and never learn about rules added since —
# the KEY MATERIAL block being the case that motivated this. Also safe on a
# hand-maintained .gitignore, though on one that diverges from the template it
# will append a lot; the count is always announced before it is written.
#
# That last clause is load-bearing — it is the property that makes appending to
# a file Manifest does not own defensible — and it was FALSE on the fleet path
# for as long as that path existed (§73): `ensure_repo_scaffold` defaults this
# mode to `upgrade`, and fleet init called it with stdout and stderr both sent
# to /dev/null, so N members were appended to with the announcement discarded.
# Fixed by passing `report` there explicitly, not by softening this sentence:
# the sentence describes the contract, so a caller that cannot honour it must
# not use this mode. Any NEW caller of upgrade mode owes the same check —
# announce, or pass `report`.
#
# This does not violate the module's no-clobber contract. Nothing existing is
# rewritten, reordered, or removed — rules are appended under a marked header,
# and .gitignore is last-match-wins, so appended negations still re-include.
#
# Refuses to reverse a deliberate decision, judged by what the file DOES to the
# path a rule names rather than by the line's text (TRACKER §1(a)): a path the
# file already ignores is not re-included, and a path it re-includes is not
# ignored. Without that, appending `*.key` under a user's considered `!*.key`
# would silently start ignoring their file, and appending
# `!.claude/settings.json` under `.claude/*` would re-include the one file
# they chose to keep out. A consequence worth knowing: an advised re-include
# (`!.env.example`) only ever lands beside its own positive rule, because a
# file that already ignores `.env.*` has decided the path and is left alone.
#
# Idempotent — a second run finds nothing missing and writes nothing.
#
# ARGUMENTS:
#   $1 - path to the .gitignore(-style) file to upgrade (must exist)
#   $2 - line prefix for output (default "   ")
# Output (stdout): "<basename>:upgraded:<n>" or "<basename>:current"
# RETURNS: 0 on success (including nothing-to-do), 1 on bad input / write failure.
manifest_gitignore_upgrade() {
    local target="$1"
    local prefix="${2:-   }"

    if [[ -z "$target" || ! -f "$target" ]]; then
        log_error "manifest_gitignore_upgrade: '$target' is not an existing file"
        return 1
    fi

    local base
    base="$(basename "$target")"

    local missing
    missing="$(manifest_gitignore_missing_rules "$target")"
    if [[ -z "$missing" ]]; then
        printf '%s:current\n' "$base"
        return 0
    fi

    # Drop any rule the file has already decided on — by DECISION, not by line
    # (TRACKER §1(a)). The old guard skipped a rule only when its exact textual
    # inverse was present, so a repo that ignores `.claude/*` and deliberately
    # re-includes nothing but `agents/` got `!.claude/settings.json` appended:
    # the decision was written differently, and the guard reversed it. Now each
    # rule is judged by what the file already does to the path it names: a
    # path the file ignores is decided, a path the file re-includes is decided,
    # and only a path the file says nothing about is appended.
    local applicable=() rule verdict
    local -a verdicts=()
    mapfile -t verdicts < <(_manifest_gitignore_decisions "$target" "$missing")
    local i=0
    while IFS= read -r rule; do
        [[ -n "$rule" ]] || continue
        verdict="${verdicts[$i]:-}"
        i=$((i + 1))
        if [[ -n "$verdict" ]]; then
            if [[ "$rule" == '!'* && "$verdict" != '!'* ]]; then
                echo "${prefix}↩︎ skipped '$rule' — '$verdict' already decides ${rule#!} is ignored here" >&2
                continue
            fi
            if [[ "$rule" != '!'* && "$verdict" == '!'* ]]; then
                echo "${prefix}↩︎ skipped '$rule' — '$verdict' already decides $rule is kept here" >&2
                continue
            fi
            # A positive rule whose sample the file already ignores is still
            # appended. One sample proves a reversal (either branch above:
            # any single point the appended rule would flip is enough), but
            # it cannot prove coverage: `/.env` ignores the sample for `.env`
            # and says nothing about `sub/.env`, `*.pyc` covers one member of
            # `*.py[cod]`. Skipping on that evidence lost depth for security
            # rules; the cost of appending is one redundant line.
            # A negation re-included by another negation is consistent and is
            # appended too — in practice git reports a re-included directory
            # sample (`!.claude/agents/`) as undecided, which lands here anyway.
        fi
        applicable+=("$rule")
    done <<< "$missing"

    if [[ ${#applicable[@]} -eq 0 ]]; then
        printf '%s:current\n' "$base"
        return 0
    fi

    # Append atomically-ish: build the block, then one write. A partial append
    # would leave a .gitignore whose negations lost their rules.
    local block
    block="$(printf '\n# %s\n# Added by Manifest: advised rules this file did not carry.\n# Review and keep, or delete any that do not apply to this repo.\n# %s\n' \
        '=============================================================================' \
        '=============================================================================')"
    block+=$'\n'
    block+="$(printf '%s\n' "${applicable[@]}")"

    if ! printf '%s\n' "$block" >> "$target"; then
        log_error "manifest_gitignore_upgrade: failed to append to $target"
        return 1
    fi

    printf '%s:upgraded:%s\n' "$base" "${#applicable[@]}"
    return 0
}

# Check for required files and create them if missing.
#
# ARGUMENTS:
#   $1 - project root
#   $2 - .gitignore mode for an existing populated file: "report" (default) or
#        "upgrade". See ensure_gitignore_smart. Ship/refresh callers leave this
#        at the default so they never mutate a .gitignore behind the user.
ensure_required_files() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local gitignore_mode="${2:-report}"
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
    gitignore_result=$(ensure_gitignore_smart "$project_root" "$gitignore_mode")
    case "$gitignore_result" in
        ".gitignore:empty-overwrite")
            created_files+=(".gitignore")
            ;;
        ".gitignore")
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
# (avoids redundant scaffold work on every fleet re-run). Repo init still
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
# All writers honor write_scaffold_no_clobber (create when missing; preserve otherwise).
#
# An existing .gitignore is upgraded in place (append-only) rather than merely
# reported on: init is the explicit "scaffold this repo" request, and a
# .gitignore written by an older CLI would otherwise never gain rules added
# since — including the KEY MATERIAL block. Ship and refresh keep the reporting
# default, so nothing is appended during a release.
#
# ARGUMENTS:
#   $1 - project root
#   $2 - .gitignore mode ("upgrade" default here; "report" to only report)
ensure_repo_scaffold() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local gitignore_mode="${2:-upgrade}"

    if [[ -z "$project_root" || ! -d "$project_root" ]]; then
        log_error "ensure_repo_scaffold: project root missing or not a directory: ${project_root:-<empty>}"
        return 1
    fi

    if ! ensure_required_files "$project_root" "$gitignore_mode"; then
        return 1
    fi

    ensure_release_gate_script "$project_root" || return 1
    ensure_env_files "$project_root" || return 1
    return 0
}

# Scaffold the release gate script `manifest ship` auto-detects
# (scripts/run-tests.sh). Since v56.0.0 the release gate is fail-closed: a
# releaseable repo with no test command refuses to release, and inside
# `ship fleet` that refusal aborts the whole sweep. Repos born via
# `manifest init` therefore get a gate on day one, so a fleet's FIRST
# `ship fleet` never dies on a gate-less member.
#
# No-clobber: an existing scripts/run-tests.sh is never overwritten, and nothing
# is written beside it — the existing gate is reported as preserved.
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
        "run-tests.sh:preserved")
            log_success "scripts/run-tests.sh preserved (existing release gate left untouched)"
            ;;
        "")
            : # unreachable under current write_scaffold_no_clobber contract
            ;;
    esac
    return 0
}

# Generate the default scripts/run-tests.sh release gate.
#
# Detect declared verification once at scaffold time. New gates execute in a
# disposable Docker container, or directly when already inside a container.
# Existing project gates are preserved. Undeclared verification fails closed.
create_default_run_tests() {
    local gate_file="$1"
    local project_root
    project_root="$(dirname "$(dirname "$gate_file")")"

    # --- Detect the repo's OWN declared verification (scaffold-time) ---------
    # Emit only declared checks; provisioning stays inside the container.
    local checks=""
    local container_packages="bash git jq make"

    local ecosystems label
    ecosystems="$(manifest_detect_project_ecosystems "$project_root")"

    # The shared detector drives the four toolchains whose gate condition is
    # exactly "the marker file exists". The rest stay inline below, because their
    # condition is finer than a label can express: pytest additionally requires a
    # tests directory, and Make/Compose are fallbacks keyed on "nothing has been
    # emitted yet" rather than on the absence of an ecosystem. A label says what
    # the repo IS; it deliberately never says what verifies it.
    local eco_rust=false eco_node=false eco_go=false eco_dotnet=false
    while IFS= read -r label; do
        case "$label" in
            rust) eco_rust=true ;;
            node) eco_node=true ;;
            go) eco_go=true ;;
            dotnet) eco_dotnet=true ;;
        esac
    done <<< "$ecosystems"

    if [[ "$eco_rust" == "true" ]]; then
        container_packages+=" cargo rust"
        checks+='    run_check cargo test'$'\n'
    fi

    if [[ "$eco_node" == "true" ]]; then
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
        container_packages+=" nodejs npm"
        for s in lint typecheck type-check build test; do
            grep -qE "\"$s\"[[:space:]]*:" "$project_root/package.json" || continue
            # Skip npm's scaffold placeholder ("Error: no test specified").
            if [[ "$s" == "test" ]] && grep -q 'Error: no test specified' "$project_root/package.json"; then
                continue
            fi
            # `<pm> run <script>` runs the package.json script across every
            # manager (bun's bare `bun test` would bypass it, so `run` is used).
            if [[ "$checks" != *"$pm run "* ]]; then
                case "$pm" in
                    npm)
                        if [[ -f "$project_root/package-lock.json" ]]; then
                            checks+='    run_check npm ci'$'\n'
                        else
                            checks+='    run_check npm install --package-lock=false'$'\n'
                        fi ;;
                    *)
                        checks+="    run_check npm install --global $pm"$'\n'
                        checks+="    run_check $pm install"$'\n' ;;
                esac
            fi
            checks+="    run_check $pm run $s"$'\n'
        done
    fi

    # .NET: a solution or project file, often nested under src/ — which is why the
    # detector searches to -maxdepth 3 for this one and at the root for the others.
    if [[ "$eco_dotnet" == "true" ]]; then
        checks+='    run_check dotnet build'$'\n'
        checks+='    run_check dotnet test'$'\n'
    fi

    if [[ "$eco_go" == "true" ]]; then
        container_packages+=" go"
        checks+='    run_check go build ./...'$'\n'
        checks+='    run_check go test ./...'$'\n'
    fi

    if [[ -f "$project_root/pyproject.toml" ]] && { [[ -d "$project_root/tests" ]] || [[ -d "$project_root/test" ]]; }; then
        container_packages+=" python3 py3-pytest"
        checks+='    run_check python3 -m pytest -q'$'\n'
    fi
    if [[ -f "$project_root/tox.ini" ]]; then
        container_packages+=" py3-tox"
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
            container_packages+=" docker-cli docker-cli-compose"
            checks+='    run_check docker compose config -q'$'\n'
            break
        done
    fi

    # A new scaffold has no application code to build. Verify that exact,
    # bounded inventory; adding any other content requires real project checks.
    # This is a structural check, never a blanket passing placeholder.
    #
    # service.spec.yaml counts as scaffold only while it carries the header
    # init writes when it creates one; any other spec is project content.
    if [[ -z "$checks" ]]; then
        checks=$(cat <<'BOOTSTRAP_CHECK'
    bootstrap_only=true
    [ -d "$DOCS_FOLDER" ] || bootstrap_only=false
    for required in VERSION README.md CHANGELOG.md .gitignore .env.example robots.txt ai.txt; do
        [ -s "$required" ] || bootstrap_only=false
    done
    while IFS= read -r file; do
        case "$file" in
            VERSION|README.md|CHANGELOG.md|.gitignore|.env.example|robots.txt|ai.txt|scripts/run-tests.sh|manifest.config.yaml|manifest.config.local.yaml|"$DOCS_FOLDER"/*.md) ;;
            "$DOCS_SITE_FOLDER"/_config.yml|"$DOCS_SITE_FOLDER"/index.md|"$DOCS_SITE_FOLDER"/_layouts/default.html|"$DOCS_SITE_FOLDER"/assets/css/manifest.css|"$DOCS_SITE_FOLDER"/.gitignore|.github/workflows/manifest-docs-pages.yml)
                # Ship can add these exact managed documentation files. A user
                # file at the same path must not gain this exception by name.
                grep -Fq 'Managed by Manifest CLI docs site generation' "$file" || bootstrap_only=false ;;
            service.spec.yaml)
                # Only the spec init created, with its header, is scaffold
                grep -Fq 'Manifest reads one key here: env:, the list of this repository' "$file" || bootstrap_only=false ;;
            *) bootstrap_only=false ;;
        esac
    done < <(list_files '*')
    if [ "$bootstrap_only" = true ]; then
        ok "scaffold-only repository: verified required files, version, shell syntax and JSON"
    else
        bad "no build or test verification is declared by this repo — the release gate cannot certify it"
        note "Add real PROJECT CHECKS above or configure release.gate_command for your container test runner."
        note "release_gate=none is an unverified ship bypass; init cannot certify readiness with it."
    fi
BOOTSTRAP_CHECK
)
        checks+=$'\n'
    fi

    # --- Static head (quoted heredoc: nothing expands) -----------------------
    cat > "$gate_file" << 'MANIFEST_CLI_GATE_CONTAINER'
#!/usr/bin/env bash
# Release gate — scaffolded by Manifest CLI. Dependencies stay in containers, and
# by default nothing is written back to this checkout: the tree is mounted
# read-only and copied inside the container, so no cache, build output or volume
# mount point lands on the host. Existing containers execute directly.
# To let the checks write into this checkout instead, opt out explicitly:
#   release.gate_host_writes: true   (manifest.config.local.yaml; honoured when
#                                     `manifest ship` runs this gate)
#   MANIFEST_CLI_RELEASE_GATE_HOST_WRITES=true   (when running it yourself)
if [[ ! -f /.dockerenv && ! -f /run/.containerenv ]]; then
    command -v docker >/dev/null 2>&1 || { echo "Docker is required for the release check; no host dependencies are installed." >&2; exit 1; }
    root="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
MANIFEST_CLI_GATE_CONTAINER
    printf '    packages=%q\n' "$container_packages" >> "$gate_file"
    cat >> "$gate_file" << 'MANIFEST_CLI_GATE_CONTAINER'
    image="manifest-project-checks:$(printf '%s' "$packages" | cksum | awk '{print $1}')"
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        printf 'FROM alpine:3.24\nRUN apk add --no-cache %s && git config --system --add safe.directory /workspace\n' "$packages" | docker build -q -t "$image" - || exit 1
    fi
    if [[ "${MANIFEST_CLI_RELEASE_GATE_HOST_WRITES:-false}" == "true" ]]; then
        # Opted out: the checks run against this checkout read-write.
        exec docker run --rm -v "$root:/workspace" -w /workspace "$image" bash scripts/run-tests.sh "$@"
    fi
    exec docker run --rm -v "$root:/source:ro" -e MANIFEST_CLI_GATE_SOURCE=/source \
        -w /source "$image" bash scripts/run-tests.sh "$@"
fi
MANIFEST_CLI_GATE_CONTAINER
    cat >> "$gate_file" << 'MANIFEST_CLI_GATE_HEAD'
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

# Inside the container the checkout arrives read-only at $MANIFEST_CLI_GATE_SOURCE
# (the host wrapper's default). Copy it to a scratch tree the checks can write
# to, then run from there: nothing reaches the host.
if [ -n "${MANIFEST_CLI_GATE_SOURCE:-}" ]; then
    gate_source="$MANIFEST_CLI_GATE_SOURCE"
    unset MANIFEST_CLI_GATE_SOURCE
    gate_work="$(mktemp -d "${TMPDIR:-/tmp}/release-gate.XXXXXX")" \
        || { echo "release gate: could not create a scratch tree under ${TMPDIR:-/tmp}" >&2; exit 2; }
    # -o on extract: do not restore the archive's uid/gid. On a Linux host the
    # bind mount carries the host user's uid; a copy that kept it would be
    # refused by git as "dubious ownership" while this script runs as root.
    tar -C "$gate_source" --exclude=./node_modules --exclude=./target -cf - . | tar -C "$gate_work" -o -xf - \
        || { echo "release gate: could not copy the checkout from $gate_source into the container" >&2; exit 2; }
    cd "$gate_work" || { echo "release gate: could not enter $gate_work" >&2; exit 2; }
    exec bash scripts/run-tests.sh "$@"
fi

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
        git ls-files --cached --others --exclude-standard -- "$1" 2>/dev/null | sort -u
    else
        find . -type d \( -name .git -o -name node_modules -o -name target \
            -o -name dist -o -name build -o -name .next -o -name vendor \) -prune \
            -o -type f -name "$1" -print | sed 's|^\./||'
    fi
}

# ------------------------------------------------------------------ BASELINE

if [ -f VERSION ]; then
    v="$(tr -d '[:space:]' < VERSION)"
    if grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.+-]*)?$' <<<"$v"; then
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
    printf '    DOCS_FOLDER=%q\n' "${MANIFEST_CLI_DOCS_FOLDER:-docs}" >> "$gate_file"
    printf '    DOCS_SITE_FOLDER=%q\n' "${MANIFEST_CLI_DOCS_SITE_SOURCE_DIR:-docs-site}" >> "$gate_file"
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
# truth for this repo's environment schema. Empty output = no spec.
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

# ---------------------------------------------------------------------------
# The three boolean flags of a spec `env:` entry — secret, required, public —
# and the ONE reader every consumer uses (TRACKER §98).
#
#   _manifest_env_spec_flag <spec-file> <entry-index> <secret|required|public>
#
# Prints `true` or `false`. Returns 2, printing nothing, for a value that is
# neither — and a caller that gets 2 stops; it never reads that as false.
#
# Every reader used to take `yq '.<flag> // false'` and compare the PRINTED
# text with the string "true". `secret: True` is a YAML boolean that prints as
# `True`, and `secret: yes` is a string, so both read as "not a secret" and the
# entry's default went into the ConfigMap and into .env.example as a live
# assignment, exit 0. yq's JSON encoding is the probe because it reports the
# VALUE, not the spelling: true, True and TRUE all encode as `true`. Comparing
# the flag with the boolean inside yq does not work — the comparison is false
# for `True`.
#
#   true / True / TRUE, or the string "true"     → true
#   false / False / FALSE, the string "false",
#   an absent flag, or an explicit null          → false
#   anything else (yes, on, 1, y, "True", a list) → refused
#
# The quoted strings are accepted because specs in the field carry them. A
# YAML-1.1 spelling is refused rather than guessed: this parser reads `yes` as
# a string, and guessing which way the author meant a secret flag is the
# defect.
#
# The encoding is read together with the text as written, because a tag can
# force one onto the other: `secret: !!bool 1` encodes as `false`. A boolean
# counts only when the two agree.
#
# Lives here, not in manifest-env.sh, because .env.example is also rendered at
# init time, when only this module is loaded.
# ---------------------------------------------------------------------------
_manifest_env_spec_flag() {
    local spec_file="$1" index="$2" flag="$3"
    local read_as
    # <JSON encoding>|<text as written>, matched whole: a value with a newline
    # in it matches nothing below.
    read_as="$(yq e ".env[$index].$flag | @json + \"|\" + tostring" "$spec_file" 2>/dev/null)" || return 2
    case "$read_as" in
        'true|true'|'true|True'|'true|TRUE'|'"true"|true')        printf 'true' ;;
        'false|false'|'false|False'|'false|FALSE'|'"false"|false') printf 'false' ;;
        'null|null'|'null|~'|'null|')                               printf 'false' ;;
        *)                                                          return 2 ;;
    esac
}

# Every flag value _manifest_env_spec_flag refuses, one line per entry and
# flag on stdout, naming both; exit 1 when there is at least one. An entry
# with no name is skipped, as every renderer skips it.
_manifest_env_spec_flag_problems() {
    local spec_file="$1"
    local count i name flag shown problems=0
    count="$(yq e '.env | length' "$spec_file" 2>/dev/null)"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    for ((i = 0; i < count; i++)); do
        name="$(yq e ".env[$i].name // \"\"" "$spec_file" 2>/dev/null)"
        [[ -n "$name" ]] || continue
        for flag in secret required public; do
            _manifest_env_spec_flag "$spec_file" "$i" "$flag" >/dev/null && continue
            # One line whatever the value holds: the JSON encoding escapes a
            # newline, and a long value is cut. A value a tag forced into a
            # boolean or a null is shown as written, since its encoding is the
            # misleading part.
            shown="$(yq e ".env[$i].$flag | @json" "$spec_file" 2>/dev/null | head -n 1)"
            case "$shown" in
                true|false|null)
                    shown="$(yq e ".env[$i].$flag | tostring" "$spec_file" 2>/dev/null | head -n 1) (under an explicit tag)"
                    ;;
            esac
            [[ ${#shown} -gt 60 ]] && shown="${shown:0:60}…"
            echo "${name}: ${flag} is ${shown:-unreadable} — write true or false"
            problems=$((problems + 1))
        done
    done
    [[ "$problems" -eq 0 ]]
}

# The .env.example comment for a secret. It names no store, path or provider:
# where a secret is kept is the platform's business, and Manifest reads no
# setting that describes it.
_manifest_env_secret_example_comment() {
    printf '%s\n' "# secret — set from the platform's secret store; never a literal value in any .env"
}

# Render .env.example content from a spec `env:` block onto stdout.
# Secret entries are emitted commented-out and valueless — a secret value
# never belongs in any .env file.
#   $2 (the project root) is accepted and unused: callers pass it, and nothing
#   rendered here depends on where the checkout sits.
_manifest_env_render_example() {
    local spec_file="$1"

    printf '# .env.example — generated by Manifest CLI from %s `env:`.\n' "$(basename "$spec_file")"
    printf '# Framework names (DATABASE_URL, NEXT_PUBLIC_*, …) are bridged at injection\n'
    printf '# boundaries, not stored here. Edit the spec, then: manifest init repo -y\n'

    local count
    count="$(yq e '.env | length' "$spec_file" 2>/dev/null)"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0

    local i name description required default secret_flag public framework_name
    for ((i = 0; i < count; i++)); do
        name="$(yq e ".env[$i].name // \"\"" "$spec_file" 2>/dev/null)"
        [[ -n "$name" ]] || continue
        description="$(yq e ".env[$i].description // \"\"" "$spec_file" 2>/dev/null)"
        # A flag the reader refuses stops the render: the caller gets a
        # non-zero status and no file, never a secret emitted as a value.
        required="$(_manifest_env_spec_flag "$spec_file" "$i" required)" || return 1
        # Not `.default // ""`: the alternative operator also replaces a
        # boolean false, so `default: false` was written as an empty value.
        default="$(yq e "(.env[$i].default | select(tag != \"!!null\") | tostring) // \"\"" "$spec_file" 2>/dev/null)"
        secret_flag="$(_manifest_env_spec_flag "$spec_file" "$i" secret)" || return 1
        public="$(_manifest_env_spec_flag "$spec_file" "$i" public)" || return 1
        framework_name="$(yq e ".env[$i].framework_name // \"\"" "$spec_file" 2>/dev/null)"

        printf '\n'
        local traits=""
        [[ "$required" == "true" ]] && traits+="required" || traits+="optional"
        [[ "$secret_flag" == "true" ]] && traits+=", secret"
        [[ "$public" == "true" ]] && traits+=", public (build-time)"
        if [[ -n "$description" ]]; then
            printf '# %s — %s (%s)\n' "$name" "$description" "$traits"
        else
            printf '# %s (%s)\n' "$name" "$traits"
        fi
        [[ -n "$framework_name" ]] && printf '# bridged framework name: %s (materialized at injection boundaries only)\n' "$framework_name"
        if [[ "$secret_flag" == "true" ]]; then
            _manifest_env_secret_example_comment
            printf '# %s=\n' "$name"
        else
            printf '%s=%s\n' "$name" "$default"
        fi
    done
}

# The spec `init` creates when a repository has none. `app.spec.yaml` is read
# too, but one name has to be chosen for a file that does not exist yet.
MANIFEST_CLI_ENV_SPEC_CREATED_NAME="service.spec.yaml"

# Load the env engine (manifest-env.sh) when this module is used without it.
# The CLI sources both; a caller that sources only this module still gets
# the one writer of .env.example rather than a second copy of it.
_manifest_init_load_env_module() {
    [[ -n "${_MANIFEST_CLI_ENV_LOADED:-}" ]] && return 0
    local env_module="${MANIFEST_CLI_CORE_MODULES_DIR:-}/core/manifest-env.sh"
    [[ -f "$env_module" ]] || return 1
    # shellcheck disable=SC1090
    source "$env_module"
}

# What `init` does with the spec, as one word:
#   create      no spec file: create service.spec.yaml with a starter env:
#   seed        a spec with no env: key: add a starter env: block
#   ready       a spec whose env: key is set (a list, possibly empty)
#   noyq        yq is not installed: no spec can be read or written
# A spec init leaves as it is and goes on (warned; .env.example is the
# no-clobber starter, as it is for noyq and `env: []`):
#   linked      no env: key, and the file is shared — a symlink, or a hard
#               link — so seeding would write this repository's identity
#               into another's spec, or replace the link
#   readonly    no env: key, and the file cannot be written
# A spec that stops `init -y` and fails `init --check`, nothing written:
#   blocked     a spec name taken by something that is not a readable file —
#               a dangling symlink, a directory: nothing is created through it
#   unreadable  not valid YAML
#   multidoc    more than one YAML document
#   notamap     its top level is a list or a single value, not keys
#   notalist    env: is a string or a map, not a list
_manifest_env_spec_plan_state() {
    local project_root="$1"
    [[ -n "$(_manifest_env_spec_blocked_name "$project_root")" ]] && { printf 'blocked'; return 0; }
    command -v yq >/dev/null 2>&1 || { printf 'noyq'; return 0; }
    local spec_file
    spec_file="$(_manifest_env_spec_file "$project_root")"
    [[ -n "$spec_file" ]] || { printf 'create'; return 0; }
    yq e 'true' "$spec_file" >/dev/null 2>&1 || { printf 'unreadable'; return 0; }
    [[ "$(yq e 'document_index' "$spec_file" 2>/dev/null | tail -n 1)" == "0" ]] || { printf 'multidoc'; return 0; }
    case "$(yq e 'tag' "$spec_file" 2>/dev/null)" in
        '!!map'|'!!null') ;;
        *) printf 'notamap'; return 0 ;;
    esac
    local env_tag
    env_tag="$(yq e '.env | tag' "$spec_file" 2>/dev/null)" || { printf 'unreadable'; return 0; }
    case "$env_tag" in
        # Only an absent (or null) key is seeded. `env: []` is a decision —
        # "this repository declares no variables" — and is left as written.
        '!!null')
            if [[ -L "$spec_file" || -n "$(find "$spec_file" -links +1 2>/dev/null)" ]]; then
                printf 'linked'
            elif [[ ! -w "$spec_file" ]]; then
                printf 'readonly'
            else
                printf 'seed'
            fi ;;
        '!!seq') printf 'ready' ;;
        *)       printf 'notalist' ;;
    esac
}

# Why a spec in one of the states above is not used: one sentence, the same
# in the plan, under -y and under --check. Empty for the states that are used.
#   _manifest_env_spec_state_reason <state> <project-root>
_manifest_env_spec_state_reason() {
    local state="$1" project_root="$2" spec
    spec="$(basename "$(_manifest_env_spec_file "$project_root")")"
    case "$state" in
        blocked)    printf '%s is not a readable file (a dangling symlink, a directory, or unreadable)' "$(_manifest_env_spec_blocked_name "$project_root")" ;;
        unreadable) printf '%s cannot be parsed as YAML' "$spec" ;;
        multidoc)   printf '%s holds more than one YAML document; the spec is one' "$spec" ;;
        notamap)    printf '%s is not a map of keys: its top level is a list or a single value' "$spec" ;;
        notalist)   printf 'env: in %s is not a list of variables' "$spec" ;;
        linked)     printf '%s is shared (a symlink or a hard link) and has no env: key; Manifest does not seed a shared spec' "$spec" ;;
        readonly)   printf '%s is read-only and has no env: key; Manifest does not seed a read-only spec' "$spec" ;;
    esac
}

# The spec name that is blocked, if one is: the spec that would be read but
# cannot be (a file this user cannot read), or — when there is no spec to
# read — the name init would create, taken by a dangling symlink, a directory
# or anything else that is not a file. Empty output = nothing blocked.
_manifest_env_spec_blocked_name() {
    local project_root="$1" spec_file created
    spec_file="$(_manifest_env_spec_file "$project_root")"
    if [[ -n "$spec_file" ]]; then
        [[ -r "$spec_file" ]] || printf '%s' "$(basename "$spec_file")"
        return 0
    fi
    created="$project_root/$MANIFEST_CLI_ENV_SPEC_CREATED_NAME"
    if [[ -L "$created" || -e "$created" ]]; then
        printf '%s' "$MANIFEST_CLI_ENV_SPEC_CREATED_NAME"
    fi
    return 0
}

# Set the starter env: list in <file>, in place. The one place the starter's
# yq expression is written, kept literal so the yq dialect guard reads it.
#   _manifest_env_starter_into <file> <prefix> <identity>
_manifest_env_starter_into() {
    PREFIX="$2" IDENTITY="$3" yq e -i '.env = [
        {"name": strenv(PREFIX) + "LOG_LEVEL", "description": "Structured-log verbosity", "required": false, "default": "info", "secret": false},
        {"name": strenv(PREFIX) + "SERVICE_FQN", "description": "Canonical service identity for logs/metrics", "required": false, "default": strenv(IDENTITY), "secret": false}
    ]' "$1" 2>/dev/null
}

# The starter entries `init` writes into a spec: a log level, and the
# service's identity — the same identity `status repo --env` reports (the
# origin repository's name), not the checkout's folder (TRACKER §106).
#   _manifest_env_seed_spec <spec-file> <project-root> [new]
# `new` = the spec was created by the caller a moment ago and holds nothing of
# the user's: on a failed write there is no whole copy worth keeping, and the
# caller removes the file, so nothing is kept and nothing is said here.
_manifest_env_seed_spec() {
    local spec_file="$1" project_root="$2" is_new="${3:-}"
    local prefix identity
    prefix="$(_manifest_env_prefix_for_repo "$project_root")"
    # The identity reader lives in the env module: load it first, or a caller
    # that sourced only this module would silently get the folder name.
    if _manifest_init_load_env_module && declare -F _manifest_env_export_identity >/dev/null 2>&1; then
        identity="$(_manifest_env_export_identity "$project_root")"
    else
        identity="$(basename "$project_root")"
    fi
    local staged block rc=0
    staged="$(mktemp "${TMPDIR:-/tmp}/manifest-spec.XXXXXX")" || return 1
    block="$(mktemp "${TMPDIR:-/tmp}/manifest-spec-env.XXXXXX")" || { rm -f "$staged"; return 1; }
    # Appended as text, so the rest of the spec — its indentation, comments
    # and spacing — is left exactly as written. yq rewrites the whole file
    # only when it must: an `env:` key already present with no value, or a
    # spec whose shape the appended block does not parse into.
    if [[ "$(yq e 'has("env")' "$spec_file" 2>/dev/null)" != "true" ]] \
        && _manifest_env_starter_into "$block" "$prefix" "$identity"; then
        {
            cat "$spec_file"
            if [[ -s "$spec_file" && -n "$(tail -c 1 "$spec_file")" ]]; then echo; fi
            cat "$block"
        } > "$staged" 2>/dev/null || rc=1
    else
        rc=1
    fi
    if [[ "$rc" -ne 0 || "$(yq e '.env | length' "$staged" 2>/dev/null)" != "2" ]]; then
        rc=0
        cat "$spec_file" > "$staged" \
            && _manifest_env_starter_into "$staged" "$prefix" "$identity" \
            && [[ "$(yq e '.env | length' "$staged" 2>/dev/null)" == "2" ]] || rc=1
    fi
    # cat >, not mv: the spec keeps its mode, and the file stays where it is.
    # cat > truncates first: if the write then fails (a full disk), the staged
    # copy is the only whole one, so it is kept and named, not deleted.
    if [[ "$rc" -eq 0 ]] && ! cat "$staged" > "$spec_file" 2>/dev/null; then
        if [[ "$is_new" == "new" ]]; then
            rm -f "$staged" "$block"
            return 1
        fi
        echo "Could not write $(basename "$spec_file"); it may now be incomplete. The whole file, with the env: block, is at: $staged" >&2
        rm -f "$block"
        return 1
    fi
    rm -f "$staged" "$block"
    return "$rc"
}

# Create service.spec.yaml holding only a commented header and a starter env:
# block. Manifest owns no other key of a spec; a fleet's own convention may
# add them.
_manifest_env_create_spec() {
    local project_root="$1"
    local spec_file="$project_root/$MANIFEST_CLI_ENV_SPEC_CREATED_NAME"
    cat > "$spec_file" <<'MANIFEST_CLI_ENV_SPEC'
# service.spec.yaml — created by Manifest CLI.
#
# Manifest reads one key here: env:, the list of this repository's
# environment variables. Each entry takes:
#   name            the variable's name (required)
#   description     what it is for
#   required        true or false
#   default         the value .env.example carries (never shown for a secret)
#   secret          true or false: commented out and valueless in .env.example
#   public          true or false: needed at build time, not only at run time
#   group           a label of your own; "app" when unset
#   framework_name  the name a framework expects (DATABASE_URL, NEXT_PUBLIC_*)
#
# Edit the list, then run: manifest init repo -y   (rewrites .env.example)
# Read it as JSON:        manifest status repo --env --json
MANIFEST_CLI_ENV_SPEC
    _manifest_env_seed_spec "$spec_file" "$project_root" new || { rm -f "$spec_file"; return 1; }
}

# The env part of the repository scaffold:
#   1. the spec — created when there is none (service.spec.yaml), given a
#      starter env: block when it has no env: key, otherwise left as written;
#   2. .env.example — written from the spec by the one writer
#      (manifest_env_generate). A file Manifest wrote is brought up to date; a
#      hand-authored one is left untouched; one that cannot be read is an error.
# Without yq no spec can be read, so a starter .env.example is written instead
# (no-clobber), as is one for a spec that declares no variables (`env: []`).
ensure_env_files() {
    local project_root="${1:-$MANIFEST_CLI_PROJECT_ROOT}"
    local example_file="$project_root/.env.example"
    local spec_state spec_file
    spec_state="$(_manifest_env_spec_plan_state "$project_root")"
    spec_file="$(_manifest_env_spec_file "$project_root")"

    case "$spec_state" in
        create)
            if ! _manifest_env_create_spec "$project_root"; then
                log_warning "Could not create $MANIFEST_CLI_ENV_SPEC_CREATED_NAME — env scaffold skipped."
                return 1
            fi
            spec_file="$project_root/$MANIFEST_CLI_ENV_SPEC_CREATED_NAME"
            log_success "Created $MANIFEST_CLI_ENV_SPEC_CREATED_NAME (env: — the one list of this repository's environment variables)"
            ;;
        seed)
            if ! _manifest_env_seed_spec "$spec_file" "$project_root"; then
                log_warning "Could not add an env: block to $(basename "$spec_file") — env scaffold skipped."
                return 1
            fi
            log_success "Added a starter env: block to $(basename "$spec_file")"
            ;;
        blocked|unreadable|multidoc|notamap|notalist)
            log_warning "$(_manifest_env_spec_state_reason "$spec_state" "$project_root") — .env.example was not written."
            return 1
            ;;
        linked|readonly)
            # Nothing in this repository is wrong: say so, and go on to the
            # starter .env.example below. Returning here without one left the
            # scaffold incomplete for good (manifest_repo_scaffold_is_complete
            # requires the file), so `init repo -y` failed on every run.
            log_warning "$(_manifest_env_spec_state_reason "$spec_state" "$project_root"). Add an env: list to it yourself; until then .env.example is not generated from it."
            ;;
    esac

    # No yq, a spec Manifest does not seed, or a spec that declares no
    # variables: the starter, no-clobber.
    if [[ "$spec_state" == "noyq" || "$spec_state" == "linked" || "$spec_state" == "readonly" ]] \
        || [[ "$(yq e '.env | length > 0' "$spec_file" 2>/dev/null)" != "true" ]]; then
        # "Does not exist" is not enough to write: a symlink to nothing does
        # not exist either, and `>` through it creates its target wherever it
        # points. The writer of a spec's variables refuses that; so does this.
        if ! _manifest_init_load_env_module; then
            log_warning "The env module is not available — .env.example was not written."
            return 1
        fi
        if _manifest_env_target_blocked "$example_file"; then
            log_warning ".env.example is not a readable file (a dangling symlink, a directory, or unreadable) — nothing was written through it."
            return 1
        fi
        local result
        result="$(write_scaffold_no_clobber "$example_file" create_default_env_example)" || {
            log_warning "Could not write .env.example — env scaffold skipped."
            return 1
        }
        case "$result" in
            ".env.example") log_success "Created .env.example (starter — the spec declares no variables yet)" ;;
            ".env.example:preserved") log_success ".env.example preserved (existing file left untouched)" ;;
        esac
        return 0
    fi

    if ! _manifest_init_load_env_module; then
        log_warning "The env module is not available — .env.example was not written."
        return 1
    fi
    local out rc=0
    out="$(MANIFEST_CLI_PROJECT_ROOT="$project_root" manifest_env_generate -y --quiet 2>&1)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        if grep -q '^env spec — cannot generate' <<<"$out"; then
            log_warning "$(basename "$spec_file") env: has a flag that is neither true nor false — .env.example not written:"
            printf '%s\n' "$out" | sed -n '/ — write true or false$/p' | sed 's/^ */    /' >&2
        else
            log_warning ".env.example could not be written:"
            printf '%s\n' "$out" | sed '/^$/d; s/^ */    /' >&2
        fi
        return 1
    fi
    case "$out" in
        *"wrote: .env.example"*) log_success "Wrote .env.example (from $(basename "$spec_file") env:)" ;;
        *"up-to-date:"*)         log_success ".env.example up to date with $(basename "$spec_file") env:" ;;
        *"left:"*)               log_success ".env.example preserved (hand-authored, or a starter with your own lines in it)" ;;
    esac
    return 0
}

# What `init repo`'s plan says about the env scaffold. Read-only.
_manifest_init_env_plan() {
    local project_root="$1"
    local spec_state spec_file
    spec_state="$(_manifest_env_spec_plan_state "$project_root")"
    spec_file="$(_manifest_env_spec_file "$project_root")"
    case "$spec_state" in
        create)     echo "  would create:    $MANIFEST_CLI_ENV_SPEC_CREATED_NAME   ($(_manifest_scaffold_purpose "$MANIFEST_CLI_ENV_SPEC_CREATED_NAME"))" ;;
        seed)       echo "  would add:       env: block to $(basename "$spec_file")   (two starter variables)" ;;
        ready)      echo "  exists:          $(basename "$spec_file")   (its env: block is read, not changed)" ;;
        noyq)       echo "  cannot read:     the spec   (yq is not installed — a starter .env.example instead)" ;;
        blocked|unreadable|multidoc|notamap|notalist)
            echo "  cannot use:      $(_manifest_env_spec_state_reason "$spec_state" "$project_root")   (-y stops here)"
            return 0 ;;
        linked|readonly)
            # No return: the .env.example line below is part of this plan too.
            echo "  left:            $(_manifest_env_spec_state_reason "$spec_state" "$project_root")   (add an env: list to it yourself)" ;;
    esac

    if [[ "$spec_state" == "ready" ]] && [[ "$(yq e '.env | length > 0' "$spec_file" 2>/dev/null)" == "true" ]] \
        && _manifest_init_load_env_module; then
        # The writer's own plan line, so the plan and -y cannot disagree.
        local line
        line="$(MANIFEST_CLI_PROJECT_ROOT="$project_root" manifest_env_generate --quiet 2>&1)" || true
        if grep -q '^env spec — cannot generate' <<<"$line"; then
            echo "  cannot generate: .env.example   (a spec flag is neither true nor false — -y stops here)"
        else
            case "$line" in
                *"up-to-date:"*)   echo "  exists:          .env.example   (up to date with the spec)" ;;
                *"would create:"*) echo "  would create:    .env.example   ($(_manifest_scaffold_purpose ".env.example"))" ;;
                *"would update:"*) echo "  would update:    .env.example   (rewritten from the spec)" ;;
                *"cannot read:"*)  echo "  cannot read:     .env.example   (not a readable file — -y stops here)" ;;
                *)                 echo "  exists:          .env.example   (hand-authored — preserved)" ;;
            esac
        fi
    elif _manifest_init_load_env_module && _manifest_env_target_blocked "$project_root/.env.example"; then
        echo "  cannot read:     .env.example   (not a readable file — -y stops here)"
    elif [[ -f "$project_root/.env.example" ]]; then
        if [[ "$spec_state" == "create" || "$spec_state" == "seed" ]]; then
            echo "  would update:    .env.example   (rewritten from the new env: block, unless hand-authored)"
        else
            echo "  exists:          .env.example   (preserved)"
        fi
    elif [[ "$spec_state" == "linked" || "$spec_state" == "readonly" ]]; then
        echo "  would create:    .env.example   (the starter — the spec has no env: list to generate it from)"
    else
        echo "  would create:    .env.example   ($(_manifest_scaffold_purpose ".env.example"))"
    fi
}

# Writer for write_scaffold_no_clobber — the starter .env.example at $1, for a
# repository whose spec declares no variables or cannot be read (no yq). A
# spec with variables is never rendered here: manifest_env_generate is the one
# writer of that file (ensure_env_files).
create_default_env_example() {
    local example_file="$1"
    local project_root
    project_root="$(dirname "$example_file")"
    local prefix
    prefix="$(_manifest_env_prefix_for_repo "$project_root")"

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
#   manifest init repo -y
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

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

*This project uses [Manifest CLI](https://github.com/fidenceio/manifest.cli) for automated version management and documentation generation.*
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
# - .gitignore with entries → leave it alone; report any advised rules it lacks
#
# ARGUMENTS:
#   $1 - project root
#   $2 - mode for the "already has entries" case:
#          "report"  (default) — report the missing advised rules, write nothing
#          "upgrade"           — append them via manifest_gitignore_upgrade
#        Default stays "report" so the ship and fleet callers, which run this for
#        idempotency on repos the user did not ask to modify, keep writing nothing.
#        Only explicit scaffolding (`manifest init repo`) opts into "upgrade".
#
# Output (stdout):
#   ".gitignore"                 — created new file
#   ".gitignore:empty-overwrite" — overwrote a .gitignore that had no real entries
#   ".gitignore:preserved"       — existing .gitignore left untouched
#   ".gitignore:upgraded:<n>"    — existing .gitignore gained <n> appended rules
#
# Returns 0 on success, 1 on write failure.
ensure_gitignore_smart() {
    local project_root="$1"
    local mode="${2:-report}"
    local gitignore_file="$project_root/.gitignore"

    if [[ ! -f "$gitignore_file" ]]; then
        # No .gitignore at all — create one
        log_info "Creating .gitignore file..."
        if ! create_default_gitignore "$gitignore_file" "$project_root"; then
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
        if ! create_default_gitignore "$gitignore_file" "$project_root"; then
            log_error "Failed to overwrite .gitignore in $project_root"
            return 1
        fi
        log_success "Overwrote empty .gitignore with best-practice defaults"
        echo ".gitignore:empty-overwrite"
        return 0
    fi

    # Real .gitignore has entries — never clobber it, and never write beside it.
    if [[ "$mode" == "upgrade" ]]; then
        local upgrade_result
        upgrade_result="$(manifest_gitignore_upgrade "$gitignore_file")" || return 1
        case "$upgrade_result" in
            *:upgraded:*)
                log_success ".gitignore upgraded — appended ${upgrade_result##*:} advised rule(s)"
                echo ".gitignore:upgraded:${upgrade_result##*:}"
                ;;
            *)
                log_success ".gitignore preserved — already carries or decides every advised rule"
                echo ".gitignore:preserved"
                ;;
        esac
        return 0
    fi

    # Report what the advice would add so the operator can act without a second
    # file appearing in the repo.
    # Report the gap, but keep it scannable. A minimal .gitignore is missing
    # nearly the whole advised set; printing ~200 lines on every run is just a
    # different kind of noise, so the list is capped and the rest summarized.
    local missing missing_count preview_max=8
    missing="$(manifest_gitignore_missing_rules "$gitignore_file")"
    if [[ -n "$missing" ]]; then
        missing_count="$(printf '%s\n' "$missing" | grep -c . || true)"
        log_success ".gitignore preserved — $missing_count advised rule(s) not present:"
        printf '%s\n' "$missing" | head -n "$preview_max" | sed 's/^/    /' >&2
        if [[ "$missing_count" -gt "$preview_max" ]]; then
            printf '    … and %s more\n' "$((missing_count - preview_max))" >&2
        fi
    else
        log_success ".gitignore preserved — already carries every advised rule"
    fi
    echo ".gitignore:preserved"
    return 0
}

# Create default .gitignore content
create_default_gitignore() {
    local gitignore_file="$1"
    local project_root="${2:-}"

    local detected=""
    if [[ -n "$project_root" ]]; then
        detected="$(manifest_detect_project_ecosystems "$project_root")"
    fi

    # No project root given, or none of its ecosystems recognised: emit every
    # block. This is what keeps every existing single-argument caller byte-identical
    # to the historical template, and it is the safe direction — an unrecognised
    # stack gets more advice than it needs, never less than it needs.
    #
    # "Every block" HAS TWO DELIBERATE EXCEPTIONS — see the .NET block below.
    # `TestResults/` and `*.user` are withheld from the fallback, and `bin/`/`obj/`
    # are never emitted bare at all. "More advice is safe" holds only while the
    # advice cannot match a path an unrelated repo is committing on purpose; a
    # plain directory name breaks that, and the upgrade path APPENDS advice to a
    # file Manifest does not own. If you are adding the tenth ecosystem block,
    # this is the invariant to check your new rules against — not to restore.
    local emit_all=false
    [[ -z "$detected" ]] && emit_all=true

    cat > "$gitignore_file" << 'EOF'
# .gitignore — scaffolded by Manifest CLI (`manifest init`).
#
# The blocks above the ECOSYSTEM divider apply to every repository. The blocks
# below it are chosen from the marker files at this repo's root (go.mod,
# package.json, Cargo.toml, …), so this file describes THIS project rather than
# every project. Delete anything that does not apply — `manifest init` never
# rewrites an existing .gitignore, it only reports or appends.

# =============================================================================
# Manifest CLI
# =============================================================================
# Release-gate scratch and logs. Manifest's release commit stages with a bare
# `git add .`, so anything the CLI writes mid-run has to be ignored here.
.manifest-cli/
*.manifest-cli.log

# =============================================================================
# Your machine — OS, editors, and IDEs
# =============================================================================
# Per-developer noise. None of it describes the project, so none of it belongs
# in shared history.
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
Desktop.ini
$RECYCLE.BIN/
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
# AI assistants and coding agents
# =============================================================================
# Per-developer agent workspaces: sessions, transcripts, caches, local settings.
# Tools whose dir holds BOTH team-shared and personal config are ignored by
# CONTENT (dir/*) so the shared subset can be re-included — git cannot re-include
# a path inside an excluded directory.
.aider*
.amazonq/
.augment/
.claude/*
!.claude/agents/
!.claude/commands/
!.claude/skills/
!.claude/settings.json
.cline/
.codeium/
.continue/
.crush/
.cursor/*
!.cursor/rules/
.gemini/
.goose/
.junie/
.kiro/
.opencode/
.qodo/
.roo/
.specstory/
.tabnine/
.trae/
.windsurf/*
!.windsurf/rules/
!.windsurf/workflows/

# =============================================================================
# Environment, secrets, and local/generated config
# =============================================================================
# Deny the value files, re-include the authoring templates. Order matters:
# .gitignore is last-match-wins, so every negation has to follow its rule.
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

# ============================================================================
#  KEY MATERIAL
# ============================================================================
# Deny-by-default. Manifest's release commit is a bare `git add .` and its
# security gate does not scan for key material, so an unmatched private key
# gets pushed to the remote permanently, on the next ship, silently.
#
# Escape hatch for a legitimately-public file caught below:
#     git add -f path/to/public-thing.pem

# --- PEM-family containers: the extension does not tell you what's inside ---
*.key
*.pem
*.p8
*.pkcs8
*.der

# --- Binary bundles: these always carry the private half ---
*.pfx
*.p12
*.jks
*.keystore
*.bks

# --- SSH private keys ---
id_rsa
id_dsa
id_ecdsa
id_ed25519
id_ecdsa_sk
id_ed25519_sk
*_rsa
*_ed25519
*.ppk

# --- GPG private keyrings only. NOT *.gpg — that is ciphertext and is often
#     committed deliberately (git-crypt, sops, pass). ---
secring.*
*.private.gpg
*.secret.gpg

# ----------------------------------------------------------------------------
#  EXCEPTIONS — public halves, re-included. Must stay AFTER the rules above.
# ----------------------------------------------------------------------------
!*.pub
!*public*.pem
!*public*.key
!fullchain.pem
!chain.pem

# =============================================================================
# Logs, temporary files, and archives
# =============================================================================
# Runtime output and scratch: regenerated on demand, never reviewed in a diff.
*.log
logs/
pids/
*.pid
*.seed
*.pid.lock
tmp/
temp/
*.tmp
*.temp
*.bak
*.orig
*.rej
zArchive/
archive/

# =============================================================================
# Build output and native artifacts
# =============================================================================
# Generic across toolchains. Language-specific build directories are added in
# the ECOSYSTEM section below, only for what this repo actually declares.
dist/
build/
out/
*.o
*.so
*.dylib
*.dll
*.exe
*.out
*.app
*.com

# =============================================================================
# Local data and caches
# =============================================================================
*.sqlite
*.db
.cache/
coverage/
EOF

    # -------------------------------------------------------------------------
    # ECOSYSTEM blocks — emitted per detected marker file, or all of them when
    # the project could not be classified. Appended, so the universal rules above
    # (and the KEY MATERIAL negations in particular) keep their position.
    # -------------------------------------------------------------------------
    printf '\n# %s\n# ECOSYSTEM — chosen for this repository\n# %s\n' \
        '=============================================================================' \
        '=============================================================================' \
        >> "$gitignore_file" || return 1

    if _manifest_gitignore_wants go "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- Go (go.mod) ---
*.test
go.work
go.work.sum
EOF
    fi

    if _manifest_gitignore_wants node "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- Node / JavaScript (package.json) ---
node_modules/
bower_components/
jspm_packages/
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
.nyc_output/
.parcel-cache/
.turbo/
.next/
.nuxt/
.output/
.svelte-kit/
EOF
    fi

    if _manifest_gitignore_wants python "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- Python (pyproject.toml / setup.py / requirements.txt / tox.ini) ---
__pycache__/
*.py[cod]
*$py.class
*.egg-info/
*.egg
*.whl
.coverage
htmlcov/
.pytest_cache/
.tox/
.nox/
nosetests.xml
coverage.xml
*.cover
*.py,cover
EOF
    fi

    # `target/` is Cargo's build dir and also Maven's, so it is emitted once for
    # either rather than duplicated in both blocks.
    if _manifest_gitignore_wants rust "$detected" "$emit_all" \
        || _manifest_gitignore_wants java "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- Rust / JVM build directory (Cargo.toml / pom.xml / build.gradle) ---
target/
EOF
    fi

    if _manifest_gitignore_wants java "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- JVM (pom.xml / build.gradle) ---
*.class
*.jar
*.war
*.ear
EOF
    fi

    # .NET was a detector label with NO renderer block until 2026-08-29, so
    # detecting a .NET repo changed its .gitignore by exactly nothing: measured
    # at 129 rules, the universal core alone. See TRACKER §69(a).
    # Only the rules that cannot mean anything but .NET go in the superset.
    if _manifest_gitignore_wants dotnet "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- .NET (*.sln / *.csproj) ---
*.suo
*.userprefs
*.nupkg
*.snupkg
.vs/
project.lock.json
EOF
    fi

    # The rest is gated on ACTUAL detection — note the literal `false` passed as
    # emit_all, which is the whole point of this second call.
    #
    # Every other block is safe in the unclassified superset because more advice
    # than needed costs nothing. These are not. `manifest_gitignore_upgrade`
    # APPENDS advised rules to a user's existing file, and a repo Manifest cannot
    # classify receives the superset — so a bash, C or PHP repo would be told to
    # ignore paths it may be committing on purpose. Already-tracked files survive
    # a new ignore rule, so the loss is NEW files only, which is what makes it
    # quiet rather than loud. `TestResults/` is a plain directory name and
    # `*.user` a bare glob; neither is self-evidently .NET.
    if _manifest_gitignore_wants dotnet "$detected" false; then
        cat >> "$gitignore_file" << 'EOF'
*.user
TestResults/
EOF

        # `bin/` and `obj/` are anchored to the directory holding each project
        # file rather than emitted bare, and detection alone is NOT enough to
        # justify the bare form.
        #
        # .NET is the only label found below the root (-maxdepth 3; every other
        # is a root -f test or root glob), so it is the easiest label to acquire
        # by accident: one `tools/helper/x.csproj` in an otherwise-bash repo
        # classifies the whole repo as dotnet. A bare `bin/` would then ignore
        # that repo's committed `bin/` of scripts — the same quiet loss the
        # superset gating above prevents, arriving through classification
        # instead. Anchoring also matches .NET's own layout: bin/ and obj/ are
        # build output adjacent to the project file, never repo-wide.
        # NOTE: `dirname` yields an ABSOLUTE path, so stripping $project_root
        # leaves the EMPTY string for a project file at the repo root. Empty is
        # therefore a real value meaning "root" and must not be skipped — doing
        # so silently gave a root-level .csproj no bin/obj rules at all.
        local proj_dir proj_dirs=()
        while IFS= read -r proj_dir; do
            proj_dir="${proj_dir#"$project_root"}"
            proj_dir="${proj_dir#/}"
            proj_dirs+=("$proj_dir")
        done < <(find "$project_root" -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) \
                     -print 2>/dev/null \
                 | while IFS= read -r proj_file; do dirname "$proj_file"; done \
                 | sort -u)

        if [[ ${#proj_dirs[@]} -gt 0 ]]; then
            for proj_dir in "${proj_dirs[@]}"; do
                # A leading slash anchors to the .gitignore's own directory,
                # which is the repo root — without it `/src/bin/` would also
                # match `vendor/src/bin/`.
                if [[ -z "$proj_dir" ]]; then
                    printf '/bin/\n/obj/\n' >> "$gitignore_file" || return 1
                else
                    printf '/%s/bin/\n/%s/obj/\n' "$proj_dir" "$proj_dir" \
                        >> "$gitignore_file" || return 1
                fi
            done
        fi
    fi

    if _manifest_gitignore_wants ruby "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- Ruby (Gemfile) ---
vendor/
.bundle/
EOF
    fi

    if _manifest_gitignore_wants terraform "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- Terraform (*.tf) ---
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
EOF
    fi

    if _manifest_gitignore_wants docker "$detected" "$emit_all"; then
        cat >> "$gitignore_file" << 'EOF'

# --- Docker (Dockerfile / compose file) ---
.docker/
EOF
    fi

    return 0
}

# Crawl-privacy defaults — private/safe by default for anything that might be
# deployed as a web surface. Uses write_scaffold_no_clobber: create the real
# file when missing; preserve the real file when it already
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
# this surface.
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

User-Agent: *
Allow: none
Disallow: /
Crawl: no
Train: no
Index: no
EOF
}

# Check the same local prerequisites as ship without invoking its workflow.
# The gate may build/test project code; only an applied init runs it.
_manifest_init_repo_ready() (
    local root="$1" blocked=0 policy tier version
    cd "$root" || return 1
    export MANIFEST_CLI_PROJECT_ROOT="$root"
    # A connect may have checked out committed configuration. Resolve it now,
    # with the same precedence as the next CLI invocation, without migrations.
    if declare -F load_configuration >/dev/null 2>&1; then
        MANIFEST_CLI_CONFIG_SKIP_WRITES=1 load_configuration "$root" true || return 1
    fi
    echo "Checking ship readiness..."
    manifest_assert_release_branch "$root" || blocked=1
    manifest_ship_ci_verdict_preflight || blocked=1
    if ! git var GIT_AUTHOR_IDENT >/dev/null 2>&1 || ! git var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
        log_error "Git author/committer identity is missing. Configure user.name and user.email, then re-run init."
        blocked=1
    fi
    version="$(tr -d '[:space:]' < "$root/VERSION")" || return 1
    if ! manifest_version_next "$version" patch >/dev/null 2>&1; then
        log_error "VERSION is invalid: $version"
        blocked=1
    fi
    policy="$(manifest_release_gate_policy)" || return 1
    case "$policy" in
        local-tests|all)
            tier="$(manifest_release_gate_tier)" || return 1
            if ! _manifest_release_gate_test_command "$tier"; then
                log_error "No executable release check. Add scripts/run-tests.sh or configure release.gate_command."
                blocked=1
            else
                printf 'Release check: %s\n' "${MANIFEST_CLI_RELEASE_GATE_ARGV[*]}"
                if ! "${MANIFEST_CLI_RELEASE_GATE_ARGV[@]}"; then
                    log_error "Release check failed. Fix its reported errors; init preserves existing checks and never bypasses them."
                    blocked=1
                fi
            fi
            ;;
        none)
            log_warning "release.gate=none is configured; setup cannot certify test readiness."
            blocked=1 ;;
    esac
    if [[ "$policy" == "remote-ci" || "$policy" == "all" ]]; then
        log_error "Remote CI cannot be verified before publishing the first commit. Init does not publish; configure a passing local release check to verify readiness."
        blocked=1
    fi
    if ! manifest_repo_scaffold_is_complete "$root" || [[ ! -d "$(get_docs_folder "$root")" ]]; then
        log_error "Required scaffold files are missing or are not regular files. Resolve path conflicts and re-run init."
        blocked=1
    fi
    [[ "$blocked" -eq 0 ]]
)

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
    local check_only=false
    local create_repo_visibility=""
    local connect=true
    local connect_explicit=false
    local remote_url=""
    local create_explicit=false
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
            --force) force=true; shift ;;
            --check) check_only=true; shift ;;
            --connect) connect=true; connect_explicit=true; shift ;;
            --no-connect) connect=false; shift ;;
            --remote)
                [[ -n "${2:-}" && "$2" != -* ]] || { log_error "--remote requires a URL or path"; return 1; }
                remote_url="$2"; shift 2 ;;
            --create-repo-private)
                create_explicit=true
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "private") || return 1
                shift ;;
            --create-repo-public)
                create_explicit=true
                create_repo_visibility=$(_manifest_parse_create_repo_flag "$create_repo_visibility" "public") || return 1
                shift ;;
            --help)
                _render_help \
                    "manifest init repo [-y|--yes] [--dry-run] [--check] [--force] [--remote URL] [--no-connect] [--create-repo-private|--create-repo-public]" \
                    "Prepare a repository for ship: initialize Git, connect origin, preserve or
create project files, then run the release check. Preview by default.
No version bump, release commit, tag, or push is made.

Without an origin, the plan creates a PRIVATE GitHub repository by default.
Use --remote URL to connect an existing repository instead." \
                    "Options" "  --dry-run                  Preview all actions; no writes or network calls
  -y, --yes                  Apply setup and run readiness checks
  --check                    Read-only, for CI: exit 1 if .env.example is out of
                             date with the spec, a variable name breaks the
                             prefix policy, or a .env value file is not ignored
  --force                    Recreate local config; preserve project content
  --remote URL              Add origin using this existing remote URL or path
  --create-repo-private     Explicit private GitHub creation (default if missing)
  --create-repo-public      Create a PUBLIC GitHub repository
  --connect                 Explicitly enable connection (already the default)
  --no-connect              Local scaffold only; readiness is not certified" \
                    "Environment variables" "  The spec's env: block (service.spec.yaml or app.spec.yaml) is the one list of
  this repository's variables. init creates service.spec.yaml with a starter
  list when there is no spec, and writes .env.example from the list: non-secret
  variables carry their default, secrets are commented out and left blank. A
  .env.example whose first line is not Manifest's header, or a starter you have
  added lines to, is yours and is left alone. Edit the list, then run init again.
  init and --check read the folder they run in, not the repository root.
  Manifest writes no deployment file and edits no Dockerfile. To render them
  from the same list: manifest status repo --env --json" \
                    "Examples" "  manifest init repo
  manifest init repo -y
  manifest init repo --check
  manifest init repo --remote git@github.com:owner/project.git
  manifest init repo --create-repo-public
  manifest init repo --no-connect -y"
                return 0
                ;;
            *)
                _render_help_error "Unknown option: $1" "manifest init repo [--force] [--dry-run] [--connect] [--create-repo-private|--create-repo-public]"
                return 1
                ;;
        esac
    done

    local project_root="${MANIFEST_CLI_PROJECT_ROOT:-$(pwd)}"

    # --check reads and reports; it is never a plan for something else. Taken
    # before the connect defaults, so it makes no network call and creates
    # nothing, whatever the repository's origin.
    if [[ "$check_only" == "true" ]]; then
        if [[ "$execution_mode" == "apply" || "$force" == "true" || "$connect_explicit" == "true" \
            || -n "$remote_url" || -n "$create_repo_visibility" ]]; then
            log_error "--check is read-only: it cannot be combined with -y, --force, --connect, --remote or --create-repo-*."
            return 1
        fi
        if ! _manifest_init_load_env_module; then
            log_error "The env module is not available — nothing was checked."
            return 1
        fi
        MANIFEST_CLI_PROJECT_ROOT="$project_root" manifest_env_validate
        return $?
    fi

    # Creating a GitHub repo IS the connect phase — it is the call that reaches
    # the network and configures origin. Asking for it without --connect is not
    # a contradiction to refuse, it is an implication to honour.
    if [[ "$connect" == "false" && ( -n "$create_repo_visibility" || -n "$remote_url" ) ]]; then
        log_error "--no-connect cannot be combined with --remote or --create-repo-*."
        return 1
    fi
    if [[ -n "$remote_url" && -n "$create_repo_visibility" ]]; then
        log_error "--remote and --create-repo-* are mutually exclusive."
        return 1
    fi
    if [[ "$connect" == "true" && -z "$remote_url" && -z "$create_repo_visibility" ]] \
        && { ! _manifest_dir_is_own_git_repository "$project_root" \
            || ! git -C "$project_root" remote get-url origin >/dev/null 2>&1; }; then
        create_repo_visibility=private
    fi
    if [[ -n "$create_repo_visibility" ]]; then
        _manifest_github_repo_target "$project_root" >/dev/null || return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        # On stderr, and only to a repo holding something an earlier Manifest
        # rendered (k8s/env files, env.secrets, the Dockerfile block).
        _manifest_init_load_env_module && _manifest_env_rendering_moved_notice "$project_root"
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
                # Scaffold files are never overwritten — even with --force, which
                # only recreates manifest.config.local.yaml (below). An existing
                # file is preserved and nothing is written beside it.
                if [[ "$f" == ".gitignore" ]]; then
                    local missing_n
                    missing_n="$(manifest_gitignore_missing_rules "$project_root/$f" | grep -c . || true)"
                    if [[ "${missing_n:-0}" -gt 0 ]]; then
                        echo "  exists:          $f   (preserved — $missing_n advised rule(s) not present)"
                    else
                        echo "  exists:          $f   (preserved — carries every advised rule)"
                    fi
                else
                    echo "  exists:          $f   (preserved)"
                fi
            else
                echo "  would create:    $f   ($(_manifest_scaffold_purpose "$f"))"
            fi
        done
        if [[ -d "$project_root/docs" ]]; then
            echo "  exists:          docs/"
        else
            echo "  would create:    docs/   ($(_manifest_scaffold_purpose "docs/"))"
        fi
        if [[ -f "$project_root/scripts/run-tests.sh" ]]; then
            echo "  exists:          scripts/run-tests.sh   (preserved)"
        else
            echo "  would create:    scripts/run-tests.sh   ($(_manifest_scaffold_purpose "scripts/run-tests.sh"))"
        fi
        _manifest_init_env_plan "$project_root"
        if [[ -f "$project_root/manifest.config.local.yaml" && "$force" != "true" ]]; then
            echo "  exists:          manifest.config.local.yaml"
        else
            if [[ -f "$project_root/manifest.config.local.yaml" && "$force" == "true" ]]; then
                echo "  would recreate:  manifest.config.local.yaml   (--force)"
            else
                echo "  would create:    manifest.config.local.yaml   ($(_manifest_scaffold_purpose "manifest.config.local.yaml"))"
            fi
        fi
        if [[ -n "$remote_url" ]]; then
            printf '  would connect origin: %s\n' "$(manifest_redact "$remote_url")"
        elif [[ -n "$create_repo_visibility" ]]; then
            local repo_target
            repo_target="$(_manifest_github_repo_display_target "$project_root")" || return 1
            if _manifest_dir_is_own_git_repository "$project_root" \
                && git -C "$project_root" remote get-url origin >/dev/null 2>&1; then
                echo "  exists:          origin remote (gh repo create skipped)"
            else
                echo "  would gh repo create: $repo_target ($create_repo_visibility) and add as origin"
            fi
        fi
        # Name the connect phase in the plan. The preview is the consent surface,
        # so the one phase that reaches the network has to appear in it — and its
        # absence has to be just as visible, or "no network line" is
        # indistinguishable from "did not look".
        echo ""
        if [[ "$connect" == "true" ]]; then
            echo "  connect phase:   ON — verify origin; fast-forward existing history (skip pull for an empty remote)"
            echo "  readiness:       check release branch, Git identity, VERSION, available origin CI and run the configured release check"
            echo "  verification:    new checks run in Docker; images and dependencies may be downloaded inside containers"
            echo "  no release:      no commit, version bump, tag, release, or push"
        else
            echo "  connect phase:   off — no network calls (add --connect to enable)"
        fi
        echo ""
        local init_replay="manifest init repo"
        [[ "$connect" == "false" ]] && init_replay+=" --no-connect"
        [[ "$create_explicit" == "true" ]] && init_replay+=" --create-repo-$create_repo_visibility"
        if [[ -n "$remote_url" ]]; then
            local quoted_remote
            printf -v quoted_remote '%q' "$(manifest_redact "$remote_url")"
            init_replay+=" --remote $quoted_remote"
        fi
        manifest_execution_footer "$init_replay -y"
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
        local initial_branch="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
        git check-ref-format --branch "$initial_branch" >/dev/null || return 1
        if git -c "init.defaultBranch=$initial_branch" init "$project_root" >/dev/null; then
            echo "  Created: .git/"
        else
            log_error "Failed to initialize git repository"
            return 1
        fi
    fi

    # Read/fast-forward remote content BEFORE scaffolding, so an unborn local
    # repository can adopt existing remote files without untracked collisions.
    if [[ "$connect" == "true" ]]; then
        manifest_assert_release_branch "$project_root" || return 1
        local connect_args=(-y)
        [[ -n "$create_repo_visibility" ]] && connect_args+=("--create-repo-$create_repo_visibility")
        [[ -n "$remote_url" ]] && connect_args+=(--remote "$remote_url")
        if ! _MANIFEST_CLI_INIT_CONNECT_NESTED=1 manifest_init_connect_repo "${connect_args[@]}"; then
            log_error "Setup incomplete: origin connection failed. No release was made. Re-run the same init command after fixing the reported blocker."
            return 1
        fi
        if declare -F load_configuration >/dev/null 2>&1; then
            MANIFEST_CLI_CONFIG_SKIP_WRITES=1 load_configuration "$project_root" true || return 1
        fi
    fi

    # Shared scaffold (same path as fleet member init): VERSION/README/CHANGELOG/
    # docs/.gitignore/robots.txt/ai.txt + release gate + .env.example.
    if ! ensure_repo_scaffold "$project_root"; then
        log_error "Failed to create required files"
        return 1
    fi
    _manifest_init_load_env_module && _manifest_env_rendering_moved_notice "$project_root"

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

    echo ""
    if [[ "$connect" == "false" ]]; then
        echo "Local scaffold prepared (--no-connect). Ship readiness has not been verified."
        echo "Next: manifest init repo   # preview connection and readiness checks"
        return 0
    fi
    if ! _manifest_init_repo_ready "$project_root"; then
        log_error "Setup incomplete: fix the reported blockers and re-run init. No release was made."
        return 1
    fi
    echo "Repository prepared for ship. No release, tag, commit, or push was made."
    echo "Next: manifest ship repo patch   # preview the first release"

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
    # parse_start_tsv emits NAME PATH HAS_GIT BRANCH — no remote URL since §45.
    while IFS=$'\t' read -r name path has_git _branch; do
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
        echo "Exists:          $root_dir/.gitignore (preserved — coordination allowlist not applied)"
    else
        echo "Would create:    $root_dir/.gitignore (coordination allowlist)"
    fi
    echo "Fleet name:      $fleet_name"
    echo "Selected rows:   $selected_count ($existing_count existing, $missing_count missing)"
    echo "Would git init:  $needs_git_count selected director$( [[ "$needs_git_count" == "1" ]] && echo "y" || echo "ies" ) without git"
    echo "Would scaffold:  ensure_repo_scaffold (VERSION/README/CHANGELOG/docs/.gitignore/robots.txt/ai.txt/scripts/run-tests.sh/service.spec.yaml when there is no spec, or a starter env: block when it has no env: key/.env.example rewritten from the spec unless hand-authored) in $scaffold_count incomplete member(s); skip $already_complete_count already-initialized"
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
    local connect=false
    local connect_args=()
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
            --force) force=true; shift ;;
            --all-folders) all_folders=true; shift ;;
            --connect) connect=true; shift ;;
            --no-connect) connect=false; shift ;;
            # Connect-phase flags. Accepting them here is what lets
            # `manifest init fleet --connect --parallel` replace
            # `manifest prep fleet --parallel` without losing a knob.
            --parallel)   connect=true; connect_args+=("--parallel");   shift ;;
            --clone-only)    connect=true; connect_args+=("--clone-only"); shift ;;
            --pull-only)     connect=true; connect_args+=("--pull-only");  shift ;;
            --name)
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
            --help)
                _render_help \
                    "manifest init fleet [-y|--yes] [--dry-run] [--depth N|auto] [--all-folders] [--force] [--name NAME] [--connect] [--create-repo-private|--create-repo-public]" \
                    "Two-phase fleet initialization, plus an opt-in connect phase." \
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
  --force                    Overwrite fleet-root/config files (re-runs Phase 1 +
                             skips guard); does NOT overwrite member content —
                             VERSION/README/etc. stay no-clobber
  --name                     Fleet name (prompted if not provided)
  --connect                  After Phase 2, run the connect phase: clone missing
                             members, pull existing ones. OFF by default — without
                             it (and without --create-repo-*) this command makes no
                             network call at all.
  --no-connect               Explicitly skip the connect phase (the default)
  --parallel                 Connect phase: clone/pull in parallel (implies --connect)
  --clone-only               Connect phase: only clone missing members (implies --connect)
  --pull-only                Connect phase: only pull existing members (implies --connect)
  --create-repo-private      In Phase 2, create a private GitHub repo for each scaffolded dir
  --create-repo-public       In Phase 2, create a PUBLIC GitHub repo for each scaffolded dir" \
                    "Examples" "  manifest init fleet                 # Phase 1: discover
  manifest init fleet --dry-run       # Preview current phase
  vim manifest.fleet.tsv             # edit SELECT column
  manifest init fleet -y              # Apply current phase, no network
  manifest init fleet --connect -y    # Apply, then clone/pull members
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
        _manifest_init_fleet_dry_run_phase2 "$root_dir" "$start_file" "$config_file" "$force" "$fleet_name" "$create_repo_visibility" "$stale_tsv" || return $?
        if [[ "$connect" == "true" ]]; then
            if [[ -f "$config_file" && "$force" != "true" ]]; then
                # Existing membership is preserved, so the shared connect
                # preview can describe the same members apply will use.
                manifest_init_connect_fleet --dry-run ${connect_args[@]+"${connect_args[@]}"} || return $?
            else
                echo "Connect phase: after scaffolding, would clone missing members and pull existing members."
                echo "Re-run with --connect -y after reviewing the scaffold plan."
            fi
        fi
        return 0
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

    _fleet_init "${fleet_args[@]}" || return $?

    # --- Connect phase ---------------------------------------------------------
    # Phase 2 has written the config and scaffolded the selected members; only
    # now is there a membership list to clone or pull against. Opt-in, so a
    # fleet init that was network-free before the fold stays network-free.
    if [[ "$connect" == "true" ]]; then
        echo ""
        # ${a[@]+"${a[@]}"} — an empty array under `set -u` unbinds on older
        # bash; scripts/run-tests.sh runs with -u.
        _MANIFEST_CLI_INIT_CONNECT_NESTED=1 manifest_init_connect_fleet -y ${connect_args[@]+"${connect_args[@]}"}
    fi
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
        --help|help)
            _render_help \
                "manifest init [repo|fleet] [options]" \
                "Prepare a repository for ship, or review fleet membership.
With no scope, an empty directory or a Git repo uses repository setup;
a directory containing repositories uses two-phase fleet setup.

Repository setup connects origin, scaffolds missing files and runs the release
check. Missing origin defaults to private GitHub creation. No release is made.
Fleet membership is reviewed before member scaffolding; fleet connection uses
--connect. All setup is dry-run by default; -y applies." \
                "Scopes" "  repo    Prepare one repository for ship
  fleet   Two-phase fleet setup via directory scanning" \
                "Options" "  --dry-run    Explicit preview; no writes
  -y, --yes    Apply the setup plan
  --depth N|auto, --name NAME, --force
               Guided fleet setup options; use scope help for all options" \
                "More" "  manifest init repo --help    Per-repo options
  manifest init fleet --help   Phase 1 / Phase 2 details"
            ;;
        "")
            _manifest_init_guided "$@"
            ;;
        -y|--yes|--dry-run|--depth|--name|--force|--connect|--no-connect|--remote|--create-repo-private|--create-repo-public)
            _manifest_init_guided "$scope" "$@"
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
export -f create_default_gitignore ensure_gitignore_smart manifest_gitignore_missing_rules
export -f manifest_detect_project_ecosystems _manifest_gitignore_wants _manifest_gitignore_decisions _manifest_scaffold_purpose
export -f manifest_gitignore_upgrade
export -f ensure_release_gate_script create_default_run_tests
export -f ensure_env_files create_default_env_example _manifest_env_prefix_for_repo _manifest_env_spec_file _manifest_env_spec_flag _manifest_env_spec_flag_problems _manifest_env_render_example
export -f _manifest_init_load_env_module _manifest_env_spec_plan_state _manifest_env_spec_state_reason _manifest_env_spec_blocked_name _manifest_env_starter_into _manifest_env_seed_spec _manifest_env_create_spec _manifest_init_env_plan
export -f _manifest_env_secret_example_comment
export -f write_scaffold_no_clobber ensure_crawl_privacy_files create_default_robots_txt create_default_ai_txt
export -f ensure_repo_scaffold manifest_repo_scaffold_is_complete
