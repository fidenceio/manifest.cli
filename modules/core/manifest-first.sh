#!/bin/bash

# =============================================================================
# manifest first — guided onboarding front door
# =============================================================================
#
# One command to answer "I just installed Manifest — now what?". It runs a
# STRICTLY READ-ONLY inspection of the current directory, then proposes an
# opinionated setup as a plan. It honours the execution-policy contract:
# preview by default, write only on -y. Re-running on an already-configured
# repo or fleet is safe — it reports state and proposes nothing destructive.
#
# Read-only is enforced two ways: the dispatcher loads config with
# MANIFEST_CLI_CONFIG_SKIP_WRITES=1 (no incidental migration/marker writes),
# and the preview path simply renders and never calls a writer.
#
# Apply delegates the heavy lifting to the existing initializers rather than
# re-implementing their writes: manifest_init_repo for a single repo (one-shot,
# fully scaffolded), and manifest_init_fleet for a fleet. A fleet candidate runs
# only Phase 1 (write the reviewable manifest.fleet.tsv, then stop) — the curated
# apply (config + member scaffolding) belongs to `manifest init fleet -y` after
# the user reviews membership. Those initializers carry no apply-event audit of
# their own, so first records one cli audit event at its own apply boundary.
# =============================================================================

if [[ -n "${_MANIFEST_CLI_FIRST_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_FIRST_LOADED=1

_manifest_first_line() {
    printf '  %-13s %s\n' "$1" "$2"
}

# Running CLI version (the tool's own VERSION, not the project's).
_manifest_first_cli_version() {
    local cli_root="${MANIFEST_CLI_CORE_MODULES_DIR%/modules}"
    if [[ -f "$cli_root/VERSION" ]]; then
        tr -d '[:space:]' < "$cli_root/VERSION" 2>/dev/null
    fi
}

_manifest_first_fleet_config() {
    local root="$1"
    if [[ -f "$root/manifest.fleet.config.yaml" ]]; then
        echo "$root/manifest.fleet.config.yaml"
    elif [[ -f "$root/manifest.fleet.yaml" ]]; then
        echo "$root/manifest.fleet.yaml"
    fi
}

# Detect onboarding context for project root $1. Echoes exactly one of:
#   fleet | fleet-pending | fleet-candidate |
#   repo-initialized | repo-uninitialized | empty
_manifest_first_context() {
    local root="$1"
    if [[ -n "$(_manifest_first_fleet_config "$root")" ]]; then
        echo "fleet"; return 0
    fi
    if [[ -f "$root/manifest.fleet.tsv" ]]; then
        echo "fleet-pending"; return 0
    fi
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if [[ -f "$root/VERSION" ]]; then
            echo "repo-initialized"
        else
            echo "repo-uninitialized"
        fi
        return 0
    fi
    # Not a git repo itself — a directory holding child repos is a fleet root.
    local depth repos
    if depth="$(manifest_fleet_resolve_depth auto "$root" 2>/dev/null)" && [[ -n "$depth" ]]; then
        repos="$(discover_fleet_repos "$root" "$depth" 2>/dev/null)"
        if [[ -n "$repos" ]]; then
            echo "fleet-candidate"; return 0
        fi
    fi
    echo "empty"
}

_manifest_first_describe_context() {
    case "$1" in
        fleet)              echo "fleet (configured)" ;;
        fleet-pending)      echo "fleet (init phase 1 — TSV pending review)" ;;
        fleet-candidate)    echo "fleet candidate (child repos, no fleet config yet)" ;;
        repo-initialized)   echo "single repo (initialized)" ;;
        repo-uninitialized) echo "single repo (not yet initialized)" ;;
        empty)              echo "no git repo or child repos found" ;;
        *)                  echo "$1" ;;
    esac
}

# --- Read-only state report --------------------------------------------------
_manifest_first_report() {
    local root="$1" context="$2" resolved_depth="$3" repo_count="$4"

    echo ""
    echo "manifest first"
    echo "=============="
    _manifest_first_line "Path:" "$root"
    _manifest_first_line "Context:" "$(_manifest_first_describe_context "$context")"

    if [[ -f "$root/VERSION" ]]; then
        _manifest_first_line "Version:" "$(tr -d '[:space:]' < "$root/VERSION" 2>/dev/null)"
    fi

    # Config layers (existence only — read-only).
    local g ps pl
    g="${MANIFEST_CLI_GLOBAL_CONFIG:-$HOME/.manifest-cli/manifest.config.global.yaml}"
    ps="$root/manifest.config.yaml"
    pl="$root/manifest.config.local.yaml"
    _manifest_first_line "Config:" "$([ -f "$g" ]  && echo "✓" || echo "·") global   $g"
    _manifest_first_line ""        "$([ -f "$ps" ] && echo "✓" || echo "·") project  $ps"
    _manifest_first_line ""        "$([ -f "$pl" ] && echo "✓" || echo "·") local    $pl"

    # Fleet config + selection file.
    local fc="$(_manifest_first_fleet_config "$root")"
    local tsv="$root/manifest.fleet.tsv"
    _manifest_first_line "Fleet:" "$([ -n "$fc" ] && echo "✓" || echo "·") config   ${fc:-$root/manifest.fleet.config.yaml}"
    _manifest_first_line ""        "$([ -f "$tsv" ] && echo "✓" || echo "·") tsv      $tsv"
    if [[ -n "$resolved_depth" ]]; then
        _manifest_first_line "Fleet scan:" "depth $resolved_depth → $repo_count git repo(s)"
    fi

    # Install state: completions, Manifest git hook, CLI version.
    local comp="·" comp_path="" t
    while IFS= read -r t; do
        [[ -n "$t" && -f "$t" ]] && { comp="✓"; comp_path="$t"; break; }
    done < <(manifest_install_paths_user_completion_targets 2>/dev/null)
    local hook="·" hook_file="$root/.git/hooks/pre-commit"
    if [[ -f "$hook_file" ]] && grep -q "Manifest CLI Pre-Commit Hook" "$hook_file" 2>/dev/null; then
        hook="✓"
    fi
    local cliver
    cliver="$(_manifest_first_cli_version)"; cliver="${cliver:-unknown}"
    _manifest_first_line "Completions:" "$comp ${comp_path:-not installed}"
    _manifest_first_line "Git hook:" "$hook $([ "$hook" = "✓" ] && echo "$hook_file (Manifest)" || echo "no Manifest pre-commit hook")"
    _manifest_first_line "CLI:" "v$cliver"
}

manifest_first() {
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()
    local depth_spec="auto"
    local fleet_name=""
    local force=false

    if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
        return 1
    fi
    set -- "${remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                _render_help \
                    "manifest first [-y|--yes] [--dry-run] [--depth N|auto] [--name NAME] [-f|--force]" \
                    "Guided onboarding: inspect this directory and set up Manifest." \
                    "Options" "  --dry-run        Explicit preview; no writes (default)
  -y, --yes        Apply the proposed setup (audited)
  --depth N|auto   Fleet discovery depth (default: auto)
  --name NAME      Fleet name (fleet onboarding)
  -f, --force      Overwrite existing generated files" \
                    "Examples" "  manifest first                     # inspect + preview
  manifest first -y                  # single repo → fully initialized
  manifest first -y                  # fleet → writes manifest.fleet.tsv, then stops
  vim manifest.fleet.tsv             # fleet → review membership (SELECT column)
  manifest init fleet -y             # fleet → apply: config + scaffold members"
                return 0
                ;;
            --depth)
                if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                    log_error "--depth requires a value (N or auto)"; return 1
                fi
                depth_spec="$2"; shift 2 ;;
            -n|--name)
                if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                    log_error "--name requires a value"; return 1
                fi
                fleet_name="$2"; shift 2 ;;
            -f|--force) force=true; shift ;;
            *)
                _render_help_error "Unknown option: $1" \
                    "manifest first [-y|--yes] [--dry-run] [--depth N|auto] [--name NAME] [-f|--force]"
                return 1
                ;;
        esac
    done

    local root="${PROJECT_ROOT:-$(pwd)}"
    local context
    context="$(_manifest_first_context "$root")"

    # Resolve fleet discovery depth + count for fleet-shaped contexts.
    local resolved_depth="" repo_count=0
    case "$context" in
        fleet|fleet-pending|fleet-candidate)
            if resolved_depth="$(manifest_fleet_resolve_depth "$depth_spec" "$root" 2>/dev/null)" \
                && [[ -n "$resolved_depth" ]]; then
                local _r
                while IFS= read -r _r; do
                    # `repo_count=$((...))` (not `((repo_count++))`) — the
                    # post-increment form returns exit 1 when the count is 0,
                    # which aborts under the CLI's set -e.
                    [[ -n "$_r" ]] && repo_count=$((repo_count + 1))
                done < <(discover_fleet_repos "$root" "$resolved_depth" 2>/dev/null)
            else
                resolved_depth=""
            fi
            ;;
    esac

    _manifest_first_report "$root" "$context" "$resolved_depth" "$repo_count"

    # --- Resolve config answers: flag > interactive (TTY preview) > default ---
    local is_fleet_setup=false
    [[ "$context" == "fleet-candidate" || "$context" == "fleet-pending" ]] && is_fleet_setup=true

    if [[ "$is_fleet_setup" == "true" && -z "$fleet_name" ]]; then
        local default_name
        default_name="$(basename "$root" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
        if [[ "$execution_mode" != "apply" && -t 0 ]] && declare -F _manifest_config_prompt_value >/dev/null 2>&1; then
            fleet_name="$(_manifest_config_prompt_value "Fleet name" "$default_name")"
        else
            fleet_name="$default_name"
        fi
    fi

    # --- Apply -----------------------------------------------------------------
    if [[ "$execution_mode" == "apply" ]]; then
        local rc=0 applied=false
        case "$context" in
            repo-uninitialized)
                # Route the single-repo apply through the shared apply gate
                # (consent model C) before any write. origin_required=false:
                # onboarding repos often have no remote yet, and a named branch
                # alone makes the target unambiguous. On refusal, capture the rc
                # and skip the init — write nothing — but still audit below.
                if manifest_repo_scope_confirm_apply \
                        "$root" \
                        "$(manifest_execution_replay_hint "manifest first")" \
                        "false"; then
                    local _init_args=(-y)
                    [[ "$force" == "true" ]] && _init_args+=(--force)
                    # `|| rc=$?` so a delegate failure is captured (and audited)
                    # rather than aborting under set -e before we record it.
                    manifest_init_repo "${_init_args[@]}" || rc=$?
                else
                    rc=$?
                fi
                applied=true
                ;;
            fleet-candidate)
                # Phase 1 only: delegate to the canonical fleet-init engine to
                # write the reviewable membership list (manifest.fleet.tsv), then
                # stop. With no TSV present, manifest_init_fleet -y runs Phase 1
                # and returns (it prints its own "review … then run
                # 'manifest init fleet -y'" footer). `first` never runs Phase 2
                # itself — the curated apply belongs to `manifest init fleet`.
                # ( cd "$root" … ) because the engine resolves its target via $(pwd).
                local _fl_args=(-y)
                [[ "$depth_spec" != "auto" ]] && _fl_args+=(--depth "$depth_spec")
                [[ -n "$fleet_name" ]] && _fl_args+=(--name "$fleet_name")
                [[ "$force" == "true" ]] && _fl_args+=(--force)
                ( cd "$root" && manifest_init_fleet "${_fl_args[@]}" ) || rc=$?
                applied=true
                ;;
            fleet-pending)
                # TSV already exists (Phase 1 ran, or the user re-ran `first`).
                # `first` does not run Phase 2 — hand off to the curated apply so
                # membership is reviewed first. Pure report: nothing applied.
                echo ""
                echo "Membership list manifest.fleet.tsv is ready for review."
                echo "Edit the SELECT column as needed, then run:  manifest init fleet -y"
                ;;
            repo-initialized|fleet)
                echo ""
                echo "Already set up — no structural changes to apply."
                ;;
            empty)
                echo ""
                log_error "Nothing to initialize here. Run inside a git repo, or a directory that contains your repos."
                return 1
                ;;
        esac

        # The delegated writers (manifest_init_repo / _fleet_init) carry no
        # apply-event audit of their own, so record one here at first's apply
        # boundary — exactly once, only when something was actually applied.
        if [[ "$applied" == "true" ]] && declare -F manifest_audit_apply_event >/dev/null 2>&1; then
            # plan_hash is intentionally empty: onboarding has no release-plan
            # fingerprint to record (it scaffolds files, it does not compute a
            # version bump). The empty field here is deliberate, not a bug.
            manifest_audit_apply_event \
                "${MANIFEST_CLI_AUDIT_SOURCE:-cli}" \
                "$(manifest_execution_replay_hint "manifest first")" \
                "$root" "" "$rc"
        fi
        return $rc
    fi

    # --- Preview ---------------------------------------------------------------
    echo ""
    echo "Proposed setup"
    echo "=============="
    case "$context" in
        repo-uninitialized)
            echo "Initialize this repository:"
            echo "  would create:    VERSION, README.md, CHANGELOG.md, docs/, .gitignore"
            echo "  would create:    manifest.config.local.yaml"
            ;;
        fleet-candidate)
            echo "Set up a fleet across $repo_count discovered repo(s) — two steps:"
            echo "  Step 1  'manifest first -y'"
            echo "          writes manifest.fleet.tsv — an editable membership list"
            echo "          (one row per repo; the SELECT column controls membership)"
            echo "  Step 2  edit SELECT, then 'manifest init fleet -y'"
            echo "          writes config + scaffolds each selected member"
            echo "          (VERSION, README.md, CHANGELOG.md, docs/)"
            manifest_plan_render_field "Fleet name" "$fleet_name"
            [[ -n "$resolved_depth" ]] && manifest_plan_render_field "Scan depth" "$resolved_depth"
            ;;
        fleet-pending)
            echo "Membership list manifest.fleet.tsv already exists — review, then apply:"
            echo "  edit the SELECT column to choose members, then run:"
            echo "    manifest init fleet -y   (writes config + scaffolds each member)"
            ;;
        repo-initialized)
            echo "This repository is already initialized — nothing structural to create."
            echo "Next: 'manifest ship repo patch' to cut a release, or 'manifest config' to tune settings."
            ;;
        fleet)
            echo "This directory is already a fleet — nothing structural to create."
            echo "Next: 'manifest status fleet' to review, or 'manifest ship fleet <bump> -y' to release."
            ;;
        empty)
            echo "No git repository or child repos found here."
            echo "Run 'manifest first' inside a git repo, or in a directory that contains your repos."
            ;;
    esac

    # fleet-pending's next command is `manifest init fleet -y` (named in its
    # body above), not `manifest first -y`, so skip the standard replay footer.
    if [[ "$context" != "empty" && "$context" != "fleet-pending" ]]; then
        local replay="manifest first -y"
        [[ -n "$fleet_name" ]] && replay+=" --name \"$fleet_name\""
        manifest_execution_footer "$replay"
    fi
    return 0
}

export -f manifest_first
