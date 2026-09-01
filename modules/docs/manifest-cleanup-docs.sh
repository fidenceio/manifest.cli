#!/bin/bash

# Manifest Cleanup Docs Module
# Handles moving old documentation to zArchive and general repository cleanup

# Cleanup-docs module - uses MANIFEST_CLI_PROJECT_ROOT from core module

# Get configurable documentation paths
get_zarchive_dir() {
    get_docs_archive_folder "$MANIFEST_CLI_PROJECT_ROOT"
}

# Ensure zArchive directory exists
ensure_zarchive_dir() {
    local zarchive_dir=$(get_zarchive_dir)
    if [[ ! -d "$zarchive_dir" ]]; then
        log_info "Creating zArchive directory: $zarchive_dir"
        mkdir -p "$zarchive_dir"
        log_success "zArchive directory created"
    fi
}


# ---------------------------------------------------------------------------
# Temporary-file sweep (TRACKER §3)
#
# This runs as the `archive_sweep` ship step, so it deletes files on every
# release, and until 2026-08-23 it walked the whole project root removing every
# hit for `*.tmp *.temp *.bak *.backup *~ .DS_Store Thumbs.db`. That took out a
# user's *tracked* `notes.bak` and anything matching inside `.git/` — from a
# step whose stated job is documentation cleanup, and which no preview
# mentioned. Three rules now bound it:
#
#   1. `.git` is pruned. Nothing in git's own store is a temporary file; a
#      swept `*.tmp` in there is repository damage, not tidiness.
#   2. A git-TRACKED file is never deleted. A tracked `notes.bak` is content
#      somebody committed on purpose, and the release commit's `git add .`
#      would then record the sweep's deletion as an intended change.
#   3. Patterns a person plausibly authored are scoped to where this module's
#      own generators write. Only unambiguous machine droppings sweep tree-wide.
#
# Skips are reported rather than silent: a caller learns nothing from a step
# that quietly decided not to act.
# ---------------------------------------------------------------------------

# Never user content under any name — safe to sweep anywhere in the work tree.
_MANIFEST_CLI_CLEANUP_TREEWIDE_PATTERNS=(".DS_Store" "Thumbs.db")

# Plausibly hand-authored (an editor backup, a deliberately kept `.bak`).
# Swept only under the docs tree, which is what this module generates into.
_MANIFEST_CLI_CLEANUP_SCOPED_PATTERNS=("*.tmp" "*.temp" "*.bak" "*.backup" "*~")

# Every path git tracks, keyed by repo-relative path.
declare -gA _MANIFEST_CLI_CLEANUP_TRACKED=()

# Load the tracked-file set for $1. Returns non-zero when git cannot answer,
# which the caller must treat as "refuse to delete" — reading an unavailable
# index as "nothing is tracked" is exactly the absent-input-as-a-value shape
# that TRACKER §6 exists to remove.
_manifest_cleanup_load_tracked() {
    local root="$1" path
    _MANIFEST_CLI_CLEANUP_TRACKED=()
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1

    # Prove the index is READABLE before trusting an empty answer.
    #
    # `rev-parse --is-inside-work-tree` never reads the index, so it still
    # succeeds against a corrupt .git/index. The NUL-delimited `ls-files` below
    # runs in a process substitution, whose exit status is unobservable — so a
    # failed listing produced no paths, the loop set nothing, and this function
    # returned 0 with an EMPTY tracked set. Every caller then read "git could not
    # answer" as "nothing is tracked" and treated committed content as
    # deletable: TRACKER §6's absent-input-as-a-value shape, guarding the very
    # sweep that TRACKER §3 was filed for.
    #
    # Measured on a repo with a deliberately corrupted index: the sweep deleted a
    # tracked file. This probe is a second `ls-files` purely because its status
    # is capturable; command substitution cannot be used, as `$(...)` discards
    # the NUL bytes the -z form depends on.
    git -C "$root" ls-files >/dev/null 2>&1 || return 1

    while IFS= read -r -d '' path; do
        [[ -n "$path" ]] && _MANIFEST_CLI_CLEANUP_TRACKED["$path"]=1
    done < <(git -C "$root" ls-files -z 2>/dev/null)
    return 0
}

# find(1) with `.git` pruned, NUL-delimited so a newline in a filename cannot
# split one path into two.
_manifest_cleanup_find() {
    local base="$1" pattern="$2"
    [[ -d "$base" ]] || return 0
    find "$base" -name .git -type d -prune -o -type f -name "$pattern" -print0 2>/dev/null
}

# Physical path of an existing directory (symlinks resolved), or non-zero.
# `cd`+`pwd -P` rather than realpath(1), which is absent on older macOS.
_manifest_cleanup_realdir() {
    ( cd "$1" 2>/dev/null && pwd -P ) || return 1
}

# True when $2 is $1 itself or lives underneath it. Both must already be
# physical paths, or a symlink makes the string compare lie.
_manifest_cleanup_is_inside() {
    local base="$1" candidate="$2"
    [[ "$candidate" == "$base" || "$candidate" == "$base"/* ]]
}

# Physical paths of LINKED worktrees (the main work tree excluded), one per
# line. Empty when git cannot answer, which is the safe direction: the callers
# use this only to EXCLUDE paths from a sweep.
#
# Why the sweeps need this. A linked worktree is a separate checkout whose files
# are gitignored in the parent, so the parent's index — the authority every
# guard here relies on — reports them as untracked. A `.DS_Store` sitting in
# somebody's active worktree was therefore a deletion candidate on every ship:
# the §3 defect displaced by one repository, where the index consulted belongs
# to the wrong checkout. Measured before this fix: the sweep listed
# `.claude/worktrees/agent-*/. DS_Store` as removable.
#
# A linked worktree also has a `.git` FILE rather than a directory, so the
# existing `-name .git -type d -prune` never excluded it.
_manifest_cleanup_worktree_roots() {
    local root="$1" main_root line wt
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    main_root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || return 0
    while IFS= read -r line; do
        case "$line" in
            worktree\ *) wt="${line#worktree }" ;;
            *) continue ;;
        esac
        [[ -n "$wt" ]] || continue
        [[ "$wt" == "$main_root" ]] && continue
        [[ -d "$wt" ]] || continue
        _manifest_cleanup_realdir "$wt" || true
    done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
    return 0
}

# Sweep temporary files. $1 = "apply" (default, deletes), "preview" (lists
# only), or "summary" (adds rows to the shared dry-run summary instead of
# echoing). Preview is what the mutating verbs' plan output calls; summary is
# what `manifest cleanup` calls.
#
# "summary" is a third MODE rather than a second candidate-selection routine on
# purpose. Every rule that makes this sweep safe — .git pruned, docs-scoped
# patterns proven contained, tracked files never deleted — lives in the code
# below, and a parallel implementation for the new command would be TRACKER §6's
# duplicated derivation: two copies agreeing right up until one is fixed.
#
# shellcheck disable=SC2120  # "preview" is passed by callers in other files
# (manifest-core.sh's `cleanup`/`docs cleanup` preview arms and
# manifest-refresh.sh's plan output); shellcheck only sees this file.
cleanup_temp_files() {
    local mode="${1:-apply}"
    local root="${MANIFEST_CLI_PROJECT_ROOT:-$PWD}"
    # Resolve the root physically, and use that same value for both the find
    # bases and the "${file#$root/}" strip below, so the two can never disagree
    # about where the project starts.
    root="$(_manifest_cleanup_realdir "$root")" || {
        log_warning "Skipping the temporary-file sweep — project root is not a readable directory."
        return 0
    }

    # `docs.folder` is user-settable and gets no path validation at load, so it
    # can point outside the repo ("../elsewhere"). Scoping the sweep to the docs
    # tree therefore has to prove containment first — otherwise a config value
    # steers `rm -f` at a directory the caller never named. Measured: without
    # this, `docs.folder: ../outside` deleted a file outside the project root.
    local docs_dir docs_real=""
    docs_dir="$(get_docs_folder "$root")"
    if [[ -d "$docs_dir" ]]; then
        docs_real="$(_manifest_cleanup_realdir "$docs_dir")" || docs_real=""
        if [[ -n "$docs_real" ]] && ! _manifest_cleanup_is_inside "$root" "$docs_real"; then
            log_warning "Not sweeping the docs folder — it resolves outside the project root:"
            log_warning "  docs.folder → $docs_real"
            docs_real=""
        fi
    fi

    if ! _manifest_cleanup_load_tracked "$root"; then
        log_warning "Skipping the temporary-file sweep — cannot read the git index."
        log_warning "  Without the tracked-file list this step cannot tell a throwaway from committed content."
        return 0
    fi

    local -a candidates=()
    local pattern file
    for pattern in "${_MANIFEST_CLI_CLEANUP_TREEWIDE_PATTERNS[@]}"; do
        while IFS= read -r -d '' file; do
            candidates+=("$file")
        done < <(_manifest_cleanup_find "$root" "$pattern")
    done
    if [[ -n "$docs_real" ]]; then
        for pattern in "${_MANIFEST_CLI_CLEANUP_SCOPED_PATTERNS[@]}"; do
            while IFS= read -r -d '' file; do
                candidates+=("$file")
            done < <(_manifest_cleanup_find "$docs_real" "$pattern")
        done
    fi

    # Linked worktrees are excluded outright: their files belong to a different
    # checkout whose index this sweep never consulted.
    local -a wt_roots=()
    mapfile -t wt_roots < <(_manifest_cleanup_worktree_roots "$root")

    local swept=0 rel wt
    local -a kept=()
    for file in "${candidates[@]}"; do
        [[ -f "$file" ]] || continue

        local in_worktree=false
        for wt in "${wt_roots[@]}"; do
            [[ -n "$wt" ]] || continue
            if _manifest_cleanup_is_inside "$wt" "$file"; then
                in_worktree=true
                break
            fi
        done
        [[ "$in_worktree" == "true" ]] && continue

        rel="${file#"$root"/}"
        # If the path did not reduce to a repo-relative one, the tracked-file
        # lookup cannot be trusted, so refuse rather than delete on a miss.
        if [[ "$rel" == /* ]]; then
            log_warning "Not sweeping $file — cannot place it inside the project root."
            continue
        fi
        if [[ -n "${_MANIFEST_CLI_CLEANUP_TRACKED[$rel]+set}" ]]; then
            kept+=("$rel")
            continue
        fi
        if [[ "$mode" == "preview" ]]; then
            echo "  • $rel"
            swept=$((swept + 1))
            continue
        fi
        if [[ "$mode" == "summary" ]]; then
            local tf_bytes
            tf_bytes="$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')"
            [[ "$tf_bytes" =~ ^[0-9]+$ ]] || tf_bytes=""
            manifest_execution_summary_add delete "Temporary files" "$rel" "$tf_bytes"
            swept=$((swept + 1))
            continue
        fi
        if rm -f "$file"; then
            swept=$((swept + 1))
        else
            log_warning "Could not remove $rel"
        fi
    done

    if [[ "$mode" == "preview" ]]; then
        [[ $swept -eq 0 ]] && echo "  • (none)"
    elif [[ "$mode" == "summary" ]]; then
        # Tracked hits are surfaced as `skip` rows so the summary shows the
        # boundary rather than silently omitting them.
        for rel in "${kept[@]}"; do
            manifest_execution_summary_add skip "Temporary files" "$rel (tracked — committed content)"
        done
        return 0
    elif [[ $swept -gt 0 ]]; then
        log_success "Cleaned up $swept temporary files"
    else
        log_info "No temporary files found"
    fi

    if [[ ${#kept[@]} -gt 0 ]]; then
        # Tense-neutral: this line prints in both preview and apply, and "left"
        # would read as past tense in a plan that has not run yet.
        log_info "Keeping ${#kept[@]} tracked file(s) (committed content, not temporary):"
        for rel in "${kept[@]}"; do
            log_info "  $rel"
        done
    fi
}

# ---------------------------------------------------------------------------
# Retired scaffold artifacts
#
# Commit 3b94fed (v58.0.0, 2026-08-04) removed the `<basename>.manifest` sidecar
# mechanism from write_scaffold_no_clobber. Its message records why, and the
# scale: "Nothing ever read those files ... they drifted from the CLI that
# generated them, and they were committed by accident in 25 of 365 fleet repos.
# Fleet-wide that was 1,535 files (~3.2 MB) rewritten on every run."
#
# The WRITER was removed. The FILES were not. Every repo scaffolded by a CLI
# older than v58.0.0 still carries them, and until now nothing detected them.
# This repo carries three, all git-tracked, with .gitignore.manifest 318 bytes
# and nine days divergent from the live .gitignore it was supposed to advise.
#
# Retiring a writer silently repeats the defect it was retired for — the same
# reasoning as _MANIFEST_CLI_CONFIG_RETIRED_KEYS in manifest-config.sh, which
# keeps retired config keys DETECTABLE so `config doctor` can name them instead
# of letting a dead setting look accepted forever.
#
# The list is derived from the call sites of write_scaffold_no_clobber AS THEY
# STOOD AT 3b94fed^ — the mechanism lived inside that function, so every caller
# could produce a sidecar. It is deliberately NOT derived from this checkout:
# `git log --all` shows only the first three ever existed here (this repo has no
# .env.example, and its run-tests.sh predates the mechanism), but the product
# runs on repos that have both. A list derived from the canonical checkout would
# be correct here and incomplete everywhere else.
#
# Exact relative paths, never a glob. `*.manifest` would match a file the user
# authored.
# ---------------------------------------------------------------------------
declare -ga _MANIFEST_CLI_RETIRED_ARTIFACTS=(
    ".gitignore.manifest"            # ensure_gitignore_smart
    "robots.txt.manifest"            # ensure_crawl_privacy_files
    "ai.txt.manifest"                # ensure_crawl_privacy_files
    "scripts/run-tests.sh.manifest"  # release gate — the old writer chmod +x'd it
    ".env.example.manifest"          # env scaffold
)

# Record separator for scan output: ASCII Unit Separator, not '|' or tab. A path
# can contain '|', and tab is IFS whitespace so empty fields collapse.
_MANIFEST_CLI_RETIRED_FS=$'\x1f'

# Scan $1 for retired artifacts. Echoes one record per hit:
#   <rel><FS><bytes><FS>tracked|untracked
#
# Returns non-zero WITHOUT emitting anything when the git index cannot be read.
# The caller must treat that as "refuse", never as "nothing is tracked": the
# tracked/untracked verdict is the only thing standing between this scan and
# TRACKER §3, where a sweep deleted three tracked files and parts of .git.
manifest_cleanup_scan_retired() {
    local root="${1:-${MANIFEST_CLI_PROJECT_ROOT:-$PWD}}"
    local fs="$_MANIFEST_CLI_RETIRED_FS"

    root="$(_manifest_cleanup_realdir "$root")" || return 1
    _manifest_cleanup_load_tracked "$root" || return 1

    local rel abs bytes state
    for rel in "${_MANIFEST_CLI_RETIRED_ARTIFACTS[@]}"; do
        abs="$root/$rel"
        [[ -f "$abs" ]] || continue
        # `wc -c` rather than stat(1): `stat -f%z` (BSD/macOS) and `stat -c%s`
        # (GNU) disagree, and this module already ships on both.
        bytes="$(wc -c < "$abs" 2>/dev/null | tr -d '[:space:]')"
        [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=""
        if [[ -n "${_MANIFEST_CLI_CLEANUP_TRACKED[$rel]+set}" ]]; then
            state="tracked"
        else
            state="untracked"
        fi
        printf '%s%s%s%s%s\n' "$rel" "$fs" "$bytes" "$fs" "$state"
    done
    return 0
}

# Feed the scan into the shared dry-run summary. Untracked hits are `delete`;
# tracked hits are `manual` and carry ONE `git rm` command covering all of them.
#
# A tracked artifact is never deleted by this CLI. It is committed content: the
# next ship's `git add .` would turn a silent deletion into a published change
# in someone else's release, which is TRACKER §3 verbatim. Naming it plus the
# exact remedy is the whole contract.
manifest_cleanup_retired_to_summary() {
    local root="${1:-${MANIFEST_CLI_PROJECT_ROOT:-$PWD}}"
    local fs="$_MANIFEST_CLI_RETIRED_FS"
    local group="Retired scaffold files (left by Manifest older than v58.0.0)"
    local -a scan=() tracked_rels=()
    local line rel bytes state scan_out

    # Command substitution, not a process-substitution pipe into mapfile:
    # mapfile's status reflects mapfile, so a refusing scan would read as an
    # empty-but-successful one — the absent-input-as-a-value shape again.
    scan_out="$(manifest_cleanup_scan_retired "$root")" || return 1
    mapfile -t scan <<< "$scan_out"

    for line in "${scan[@]}"; do
        [[ -n "$line" ]] || continue
        IFS="$fs" read -r rel bytes state <<< "$line"
        [[ "$state" == "tracked" ]] && tracked_rels+=("$rel")
    done

    local rm_cmd=""
    if [[ ${#tracked_rels[@]} -gt 0 ]]; then
        rm_cmd="git rm ${tracked_rels[*]}"
    fi

    for line in "${scan[@]}"; do
        [[ -n "$line" ]] || continue
        IFS="$fs" read -r rel bytes state <<< "$line"
        if [[ "$state" == "tracked" ]]; then
            manifest_execution_summary_add manual "$group" "$rel (tracked)" "$bytes" "$rm_cmd"
        else
            manifest_execution_summary_add delete "$group" "$rel" "$bytes"
        fi
        # An executable stale gate script is a CI hazard, not just dead weight:
        # a glob over scripts/ could pick it up.
        if [[ "$rel" == "scripts/run-tests.sh.manifest" && -x "$root/$rel" ]]; then
            manifest_execution_summary_note "$group" \
                "note: $rel is executable — a scripts/ glob in CI could run it"
        fi
    done
    return 0
}

# Delete the UNTRACKED retired artifacts. Tracked ones are reported by the
# summary and left alone; there is deliberately no flag to override that.
# Echoes nothing; returns the number of deletions via
# MANIFEST_CLI_RETIRED_REMOVED.
manifest_cleanup_retired_apply() {
    local root="${1:-${MANIFEST_CLI_PROJECT_ROOT:-$PWD}}"
    local fs="$_MANIFEST_CLI_RETIRED_FS"
    MANIFEST_CLI_RETIRED_REMOVED=0

    local resolved
    resolved="$(_manifest_cleanup_realdir "$root")" || {
        log_warning "Skipping the retired-artifact sweep — project root is not a readable directory."
        return 0
    }

    local -a scan=()
    local scan_out
    # See manifest_cleanup_retired_to_summary for why this is a command
    # substitution rather than a pipe into mapfile.
    if ! scan_out="$(manifest_cleanup_scan_retired "$resolved")"; then
        log_warning "Skipping the retired-artifact sweep — cannot read the git index."
        log_warning "  Without the tracked-file list this step cannot tell committed content from a stale sidecar."
        return 0
    fi
    mapfile -t scan <<< "$scan_out"

    local line rel bytes state
    local -a kept=()
    for line in "${scan[@]}"; do
        [[ -n "$line" ]] || continue
        IFS="$fs" read -r rel bytes state <<< "$line"
        if [[ "$state" == "tracked" ]]; then
            kept+=("$rel")
            continue
        fi
        if rm -f "$resolved/$rel"; then
            MANIFEST_CLI_RETIRED_REMOVED=$((MANIFEST_CLI_RETIRED_REMOVED + 1))
        else
            log_warning "Could not remove $rel"
        fi
    done

    if [[ $MANIFEST_CLI_RETIRED_REMOVED -gt 0 ]]; then
        log_success "Removed $MANIFEST_CLI_RETIRED_REMOVED retired scaffold file(s)"
    fi
    if [[ ${#kept[@]} -gt 0 ]]; then
        log_info "Keeping ${#kept[@]} tracked retired file(s) — remove them with a reviewable commit:"
        log_info "  git rm ${kept[*]}"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# `manifest cleanup` dispatch
# ---------------------------------------------------------------------------

# Gather every repo-scope finding into the shared summary. Returns non-zero only
# when the retired-artifact scan had to refuse (unreadable index / unreadable
# root); the temp sweep and worktree report warn and continue on their own.
_manifest_cleanup_collect_repo() {
    local root="$1"
    local rc=0
    manifest_cleanup_retired_to_summary "$root" || rc=1
    ( MANIFEST_CLI_PROJECT_ROOT="$root"; cleanup_temp_files summary ) || true
    if declare -F manifest_worktree_report >/dev/null 2>&1; then
        manifest_worktree_report "$root" || true
    fi
    return $rc
}

# Apply every repo-scope action.
_manifest_cleanup_apply_repo() {
    local root="$1"
    manifest_cleanup_retired_apply "$root"
    ( MANIFEST_CLI_PROJECT_ROOT="$root"; cleanup_temp_files apply ) || true
    if declare -F manifest_worktree_prune >/dev/null 2>&1; then
        manifest_worktree_prune "$root"
    fi
    return 0
}

# Fan out across fleet members, modelled on fleet_prep's loop: iterate
# MANIFEST_CLI_FLEET_SERVICES, resolve each path, skip what is not a git repo.
# One member's failure never aborts the run — a fleet is 365 repos in the
# product case, and stopping at the first bad one would make the command
# useless exactly where it is most needed.
_manifest_cleanup_fleet_each() {
    local action="$1"   # collect | apply
    local service path n=0 skipped=0

    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        path="$(get_fleet_service_property "$service" "path")"
        if [ -z "$path" ] || [ ! -d "$path" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        if [ ! -d "$path/.git" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        n=$((n + 1))
        if [ "$action" = "collect" ]; then
            manifest_cleanup_retired_to_summary "$path" || true
            ( MANIFEST_CLI_PROJECT_ROOT="$path"; cleanup_temp_files summary ) || true
        else
            _manifest_cleanup_apply_repo "$path" || true
        fi
    done

    if [ "$action" = "collect" ]; then
        manifest_execution_summary_note "Fleet" "$n member(s) scanned, $skipped skipped (missing path or not a git repo)"
    else
        log_info "Cleaned $n fleet member(s); skipped $skipped"
    fi
    return 0
}

# Entry point for the `cleanup` dispatch arm.
#   $1 = execution mode ("preview" | "apply"), already parsed
#   $2 = scope (repo | fleet | state), defaulting to repo
manifest_cleanup_dispatch() {
    local mode="$1"; shift
    local scope="${1:-repo}"

    case "$scope" in
        repo|fleet|state) ;;
        "") scope="repo" ;;
        *)
            log_error "Unknown cleanup scope: '$scope'"
            log_error "Use one of: repo (default), fleet, state"
            return 1
            ;;
    esac

    local root="${MANIFEST_CLI_PROJECT_ROOT:-$PWD}"
    local replay="manifest cleanup $scope -y"

    manifest_execution_summary_reset

    if [[ "$mode" == "preview" ]]; then
        manifest_execution_preview_header "manifest cleanup $scope"
        case "$scope" in
            repo)  _manifest_cleanup_collect_repo "$root" || true ;;
            fleet)
                if ! _fleet_require_initialized "cleanup"; then
                    return 1
                fi
                _manifest_cleanup_fleet_each collect
                ;;
            state) manifest_runtime_state_report ;;
        esac

        if manifest_execution_summary_is_empty; then
            echo ""
            echo "  Nothing to clean."
            echo ""
            return 0
        fi
        manifest_execution_summary_render "$replay"
        return 0
    fi

    # Apply. `state` is host-level and must NOT go through the repo apply gate:
    # that gate calls manifest_repo_scope_require_git, so running
    # `manifest cleanup state` from a non-git directory would be refused for a
    # command that has nothing to do with any repository.
    if [[ "$scope" != "state" ]]; then
        # origin_required=false, head_required=false — see the dispatch arm in
        # manifest-core.sh. Cleanup publishes nothing, so neither a missing
        # origin nor a detached HEAD makes its target ambiguous.
        if ! manifest_execution_require_apply "$mode" "$root" "$replay" "" "false" "false"; then
            return 1
        fi
    fi

    manifest_execution_apply_header
    case "$scope" in
        repo)  _manifest_cleanup_apply_repo "$root" ;;
        fleet)
            if ! _fleet_require_initialized "cleanup"; then
                return 1
            fi
            _manifest_cleanup_fleet_each apply
            ;;
        state) manifest_runtime_state_apply ;;
    esac
    return 0
}

# Clean up empty directories. `.git` is pruned for the same reason as the file
# sweep above: the old exact-match guard skipped `$root/.git` itself while
# happily removing `.git/refs/tags` and its siblings.
cleanup_empty_dirs() {
    log_info "Cleaning up empty directories..."

    local root="${MANIFEST_CLI_PROJECT_ROOT:-$PWD}"
    local cleaned_count=0 dir

    while IFS= read -r -d '' dir; do
        [[ -d "$dir" ]] || continue
        [[ "$dir" == "$root" ]] && continue
        [[ -z "$(ls -A "$dir" 2>/dev/null)" ]] || continue
        rmdir "$dir" 2>/dev/null && cleaned_count=$((cleaned_count + 1))
    done < <(find "$root" -name .git -type d -prune -o -type d -empty -print0 2>/dev/null)

    if [[ $cleaned_count -gt 0 ]]; then
        log_success "Removed $cleaned_count empty directories"
    else
        log_info "No empty directories found"
    fi
}

# Validate repository state
validate_repository() {
    log_info "Validating repository state..."
    
    local issues=0
    
    # Check for uncommitted changes
    if ! git diff --quiet 2>/dev/null; then
        log_warning "Repository has uncommitted changes"
        issues=$((issues + 1))
    fi
    
    # Check for untracked files
    if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        log_warning "Repository has untracked files"
        issues=$((issues + 1))
    fi
    
    # Check zArchive directory
    local zarchive_dir=$(get_zarchive_dir)
    if [[ ! -d "$zarchive_dir" ]]; then
        log_warning "zArchive directory does not exist: $zarchive_dir"
        issues=$((issues + 1))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Repository state is valid"
        return 0
    else
        log_warning "Repository has $issues issues"
        return 1
    fi
}

# Strict regex for archivable filenames. Anchored to start and end of the
# basename so similar-prefixed hand-authored docs are not swept up.
# Per-version RELEASE/CHANGELOG files are no longer generated — root
# CHANGELOG.md is the single archival surface — so only point-in-time
# audit artifacts (SECURITY_ANALYSIS_REPORT_v*) are archived now.
# The version segment comes from _MANIFEST_CLI_VERSION_ERE (manifest-shared-utils.sh,
# always sourced first) so a report stamped with a revision version — the
# generator interpolates the live VERSION verbatim — is still archivable.
_MANIFEST_ARCHIVABLE_REGEX='^SECURITY_ANALYSIS_REPORT_v'"${_MANIFEST_CLI_VERSION_ERE}"'(_[0-9]+T[0-9]+Z)?\.md$'

# Note: docs/zArchive/ is a read-only "memory" — files enter by move only,
# and nothing is ever created or modified inside it. There is deliberately no
# INDEX.md regeneration and no per-major v<major>/ routing here: a sweep moves
# a file flat into docs/zArchive/ and stops. Legacy v<major>/ folders from
# before this rule stay where they are; new moves go flat.

# Append a sweep entry to docs/zArchive/.archive-log.md so each archive
# action is auditable. Args:
#   $1 = version that triggered the sweep
#   $2 = full UTC timestamp string ("YYYY-MM-DD HH:MM:SS UTC")
#   $@ = "src|dest" move pairs (project-root-relative)
_manifest_archive_append_log_entry() {
    local version="$1"
    local timestamp="$2"
    shift 2
    local -a moves=("$@")

    [[ ${#moves[@]} -gt 0 ]] || return 0

    local archive_dir log_file
    archive_dir="$(get_zarchive_dir)"
    [[ -d "$archive_dir" ]] || return 0
    log_file="${archive_dir}/.archive-log.md"

    if [[ ! -f "$log_file" ]]; then
        cat > "$log_file" <<'EOF'
# Manifest CLI Archive Move Log

Append-only record of archive activity by `manifest ship` and
`manifest docs cleanup`. Each section below records one sweep, newest
at the bottom.

EOF
    fi

    {
        printf '## %s — v%s sweep\n\n' "${timestamp%% *}" "$version"
        printf 'Timestamp: %s\n' "$timestamp"

        local plural=""
        [[ ${#moves[@]} -ne 1 ]] && plural="s"
        printf 'Moved %d file%s:\n' "${#moves[@]}" "$plural"
        local pair src dest
        for pair in "${moves[@]}"; do
            src="${pair%%|*}"
            dest="${pair##*|}"
            printf -- '- %s → %s\n' "$src" "$dest"
        done

        printf '\n'
    } >> "$log_file"
}

# Main cleanup. Sweeps point-in-time audit artifacts (currently
# SECURITY_ANALYSIS_REPORT_v*) out of active docs/ into
# zArchive/v<major>/. Per-version RELEASE/CHANGELOG files are no longer
# generated, so the sweep is usually a no-op for the CLI repo itself.
# Honors MANIFEST_CLI_DOCS_ARCHIVE_FORCE to bypass the uncommitted-edit
# safety check (CI use).
main_cleanup() {
    local version="${1:-}"
    local timestamp="${2:-}"

    if [ -z "$timestamp" ]; then
        get_time_timestamp >/dev/null
        timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    fi

    log_info "Starting repository cleanup..."
    log_info "Version: $version"
    log_info "Timestamp: $timestamp"

    cd "$MANIFEST_CLI_PROJECT_ROOT"

    local zarchive_dir
    zarchive_dir="$(get_zarchive_dir)"

    local moved_count=0 skipped_count=0
    local -a move_entries=()
    if [[ -n "$version" ]]; then
        log_info "Archiving previous version documentation..."
        ensure_zarchive_dir

        local f filename
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            filename="$(basename "$f")"
            [[ "$filename" =~ $_MANIFEST_ARCHIVABLE_REGEX ]] || continue

            # Skip the current version's own files.
            if [[ "$filename" == *"v$version"* ]]; then
                skipped_count=$((skipped_count + 1))
                continue
            fi

            # Files land flat in docs/zArchive/ — no per-major v<major>/
            # routing — so the sweep only ever moves, never creates.
            local dest="${zarchive_dir}/${filename}"

            if ! is_truthy "${MANIFEST_CLI_DOCS_ARCHIVE_FORCE:-}"; then
                local porcelain
                porcelain="$(git status --porcelain -- "$f" 2>/dev/null || true)"
                if [[ -n "$porcelain" ]]; then
                    log_error "Refusing to archive ${filename} — file has uncommitted changes:"
                    log_error "  ${porcelain}"
                    log_error "Commit, stash, or set MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1 to bypass."
                    return 1
                fi
            fi

            if mv "$f" "$dest" 2>/dev/null; then
                log_success "Moved: ${filename} → zArchive/"
                moved_count=$((moved_count + 1))
                move_entries+=("${f#"$MANIFEST_CLI_PROJECT_ROOT"/}|${dest#"$MANIFEST_CLI_PROJECT_ROOT"/}")
            else
                log_warning "Failed to move: $filename"
            fi
        done < <(find "$(get_docs_folder "$MANIFEST_CLI_PROJECT_ROOT")" -maxdepth 1 -type f -name "*.md")

        log_success "Archived $moved_count files, skipped $skipped_count files"
    fi

    if [[ "$moved_count" -gt 0 ]]; then
        _manifest_archive_append_log_entry "$version" "$timestamp" "${move_entries[@]}"
    fi

    cleanup_temp_files
    cleanup_empty_dirs

    log_success "Repository cleanup completed"
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "archive")
            main_cleanup "${2:-}" "${3:-}"
            ;;
        "clean")
            # For clean command, archive all old documentation files
            local latest_version=""
            if [ -f "$MANIFEST_CLI_PROJECT_ROOT/VERSION" ]; then
                latest_version=$(cat "$MANIFEST_CLI_PROJECT_ROOT/VERSION" 2>/dev/null || echo "")
            fi
            # Get trusted timestamp for cleanup
            get_time_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            main_cleanup "$latest_version" "$timestamp"
            ;;
        "validate")
            validate_repository
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Cleanup Docs Module"
            echo "======================"
            echo ""
            echo "Usage: $0 [command] [version] [timestamp]"
            echo ""
            echo "Commands:"
            echo "  archive [version] [timestamp]  - Archive old documentation and cleanup"
            echo "  clean                          - General cleanup (no archiving)"
            echo "  validate                       - Validate repository state"
            echo "  help                           - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 archive 15.28.0             # Archive docs for version 15.28.0"
            echo "  $0 clean                       # General cleanup"
            echo "  $0 validate                    # Check repository state"
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
