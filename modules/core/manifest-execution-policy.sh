#!/bin/bash

# =============================================================================
# Manifest Execution Policy
# =============================================================================
#
# Central contract for safe-by-default command execution:
#   default       -> preview
#   --dry-run     -> explicit preview
#   -y, --yes     -> apply
#   --local -y    -> apply local effects only
#
# Consent model: -y is full apply authorization. The apply-target gate
# (manifest_repo_scope_confirm_apply) then resolves the target with NO
# interactive confirmation prompt — the same way whether or not a TTY is
# attached:
#   * UNAMBIGUOUS  -> apply on -y alone (a named branch + an origin remote when
#                     one is required) — no extra env var, no confirmation
#   * AMBIGUOUS    -> refuse (detached HEAD, or no origin when origin is
#                     required); fix the repo or set MANIFEST_CLI_AUTO_CONFIRM=1
#
# MANIFEST_CLI_AUTO_CONFIRM does not imply apply. Its sole remaining job is to
# authorize an *ambiguous* target; apply must still be requested via -y.
# =============================================================================

if [[ -n "${_MANIFEST_EXECUTION_POLICY_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_EXECUTION_POLICY_LOADED=1

manifest_execution_parse() {
    local -n mode_ref="$1"
    local -n local_ref="$2"
    local -n remaining_ref="$3"
    shift 3

    local saw_dry_run=false
    local saw_yes=false
    local saw_local=false
    local remaining=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                saw_dry_run=true
                shift
                ;;
            -y|--yes)
                saw_yes=true
                shift
                ;;
            --local)
                saw_local=true
                shift
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    if [[ "$saw_dry_run" == "true" && "$saw_yes" == "true" ]]; then
        log_error "Cannot combine --dry-run with -y/--yes. Preview is already the default; remove --dry-run to apply."
        return 1
    fi

    local mode="preview"
    [[ "$saw_yes" == "true" ]] && mode="apply"

    mode_ref="$mode"
    local_ref="$saw_local"
    remaining_ref=("${remaining[@]}")
}

manifest_execution_preview_header() {
    local label="$1"
    echo "Preview - no changes written: $label"
}

manifest_execution_apply_header() {
    echo "Applying because -y/--yes was provided."
    # Lazy hook: modules loaded after execution-policy (e.g. manifest-config.sh)
    # can register _manifest_execution_apply_hook to perform apply-only writes
    # at the apply boundary — keeping preview commands side-effect-free without
    # coupling execution-policy.sh to those modules' internals.
    if declare -F _manifest_execution_apply_hook >/dev/null 2>&1; then
        _manifest_execution_apply_hook
    fi
}

# Build the apply replay hint for a base command: "<base> -y". Single source
# of truth so every preview footer and confirm prompt spells apply the same way.
manifest_execution_replay_hint() {
    local base="$1"
    printf '%s -y' "$base"
}

# Apply guard: in apply mode, require confirmation before mutating; no-op in
# preview mode. Centralizes the "if apply: confirm, abort on decline" block
# that ship/prep/refresh each carried, so the apply boundary stays uniform
# (and is the natural single place for the future apply-event audit log).
# Returns non-zero if apply was declined or write access failed.
# $5/$6 forward the two target-ambiguity requirements to the gate, both
# defaulting to true so existing callers are unchanged. Only an operation that
# publishes nothing may pass false — see manifest_repo_scope_target_unambiguous.
manifest_execution_require_apply() {
    local mode="$1"
    local project_root="$2"
    local replay_hint="$3"
    local plan_hash="${4:-}"
    local origin_required="${5:-true}"
    local head_required="${6:-true}"
    [[ "$mode" == "apply" ]] || return 0

    local rc git_root
    manifest_repo_scope_confirm_apply "$project_root" "$replay_hint" "$origin_required" "$head_required"
    rc=$?

    # Audit every apply attempt that reached this boundary (CLI tracker §5.8):
    # record who authorized which plan, when, and whether authorization +
    # write-access preflight succeeded ($rc). Emitted here, the single
    # apply-guard, so each -y-gated repo apply emits exactly once. Source is
    # cli by default; fleet ship exports MANIFEST_CLI_AUDIT_SOURCE=cli-fleet so
    # its per-member applies are distinguishable. Best-effort — never alters $rc.
    if declare -F manifest_audit_apply_event >/dev/null 2>&1; then
        git_root="$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null || echo "$project_root")"
        manifest_audit_apply_event \
            "${MANIFEST_CLI_AUDIT_SOURCE:-cli}" \
            "$replay_hint" \
            "$git_root" \
            "$plan_hash" \
            "$rc"
    fi

    return $rc
}

manifest_execution_footer() {
    local apply_command="${1:-}"
    echo ""
    if [[ -n "$apply_command" ]]; then
        echo "No changes written. Re-run with -y to apply this plan:"
        echo "  $apply_command"
    else
        echo "No changes written. Re-run with -y to apply this plan."
    fi
}

# =============================================================================
# Shared dry-run summary
# =============================================================================
#
# Before this, every command hand-wrote its own preview body: 61 "Would ..."
# lines across 10 modules, each inventing its own verb, punctuation and
# grouping, with no size formatter anywhere. That is the duplicated-derivation
# half of TRACKER §6 — copies that agree only until they don't.
#
# The payload here is the ACTION->VERB table. A caller states what will happen
# to a thing (delete/create/update/skip/manual); the wording is decided in
# exactly one place. Adding a sixth action is a deliberate edit to that table,
# not 61 independent guesses.
#
# Callers accumulate rows, then render:
#
#   manifest_execution_summary_reset
#   manifest_execution_summary_add delete "Temporary files" "$path" "$bytes"
#   manifest_execution_summary_add manual "Retired files" "$p" "$b" "git rm $p"
#   manifest_execution_summary_note "Git worktrees" "0 stale records to prune"
#   manifest_execution_summary_render "manifest cleanup repo -y"
#
# Rows buffer in memory, never a temp file: a preview must be side-effect-free,
# and "the preview wrote something" would be the defect this contract exists to
# prevent.
#
# MIGRATION NOTE. 36 existing preview strings are pinned as contract text by
# tests (tests/uninstall_safe_by_default.bats:37 greps
# "Would remove installation directory: $HOME/.manifest-cli" verbatim, and 9
# other files do likewise). This renderer is therefore ADDITIVE: `cleanup` is
# its only caller today. The verb table is shaped so a later migration produces
# byte-identical output — `delete` + "installation directory" + path renders as
# "Would remove installation directory: <path>" — so callers can move over one
# at a time without touching a pinned test. Migrating a caller and its pinned
# strings must be its own change, never a side effect of another feature.

declare -ga _MANIFEST_CLI_SUMMARY_ROWS=()

# Field delimiter: ASCII Unit Separator (0x1f), NOT tab.
#
# Tab is an IFS *whitespace* character, so `read` collapses a run of them into a
# single delimiter and an empty middle field silently shifts every later field
# one position left. A note row (whose action field is empty by construction)
# parsed as though its group were its target, which rendered the note text as a
# section heading. 0x1f is non-whitespace, so empty fields are preserved, and it
# cannot occur in a path.
_MANIFEST_CLI_SUMMARY_FS=$'\x1f'

# Reset the buffer. Call before accumulating; a command invoked twice in one
# process (fleet fan-out) must not inherit the previous target's rows.
manifest_execution_summary_reset() {
    _MANIFEST_CLI_SUMMARY_ROWS=()
}

# The one place a verb is chosen. Returns non-zero for an unknown action so a
# typo surfaces as an error rather than a blank verb in front of a user.
#
# These strings are the SENTENCE form and are load-bearing for migration: they
# are what the existing hand-written lines already say, so a migrated caller's
# output is byte-identical. Changing one changes a pinned contract test.
_manifest_execution_summary_verb() {
    case "$1" in
        delete) printf 'Would remove' ;;
        create) printf 'Would create' ;;
        update) printf 'Would update' ;;
        skip)   printf 'Would leave alone' ;;
        manual) printf 'Needs a manual step for' ;;
        *)      return 1 ;;
    esac
}

# Totals-block label. Kept separate from the sentence verb because the two have
# different jobs: the sentence reads as prose before a noun ("Needs a manual
# step for installation directory: /p"), while the totals column is a fixed-width
# heading over a count. Collapsing them made the totals read
# "Needs a manual step for 2 item(s)".
_manifest_execution_summary_label() {
    case "$1" in
        delete) printf 'Would remove' ;;
        create) printf 'Would create' ;;
        update) printf 'Would update' ;;
        skip)   printf 'Left alone' ;;
        manual) printf 'Needs manual step' ;;
        *)      return 1 ;;
    esac
}

# Add one countable row.
#   $1 action  delete|create|update|skip|manual
#   $2 group   section heading, also the noun in the rendered sentence
#   $3 target  path or identifier
#   $4 bytes   optional; totalled and humanized when present
#   $5 note    optional; for `manual`, the command the user must run
manifest_execution_summary_add() {
    local action="$1" group="$2" target="$3" bytes="${4:-}" note="${5:-}"

    if ! _manifest_execution_summary_verb "$action" >/dev/null; then
        log_error "manifest_execution_summary_add: unknown action '$action'"
        return 1
    fi
    [[ -n "$group" && -n "$target" ]] || {
        log_error "manifest_execution_summary_add: group and target are required"
        return 1
    }
    [[ "$bytes" =~ ^[0-9]*$ ]] || bytes=""

    local fs="$_MANIFEST_CLI_SUMMARY_FS"
    _MANIFEST_CLI_SUMMARY_ROWS+=("row${fs}${action}${fs}${group}${fs}${target}${fs}${bytes}${fs}${note}")
}

# Add a narrative line to a group — a statement with no enumerable target, so it
# is printed under that group's heading but never counted or totalled.
manifest_execution_summary_note() {
    local group="$1" text="$2"
    [[ -n "$group" && -n "$text" ]] || return 1
    local fs="$_MANIFEST_CLI_SUMMARY_FS"
    _MANIFEST_CLI_SUMMARY_ROWS+=("note${fs}${fs}${group}${fs}${text}${fs}${fs}")
}

# True when nothing has been accumulated, so a caller can print its own
# "nothing to do" line and exit 0 without rendering an empty frame.
manifest_execution_summary_is_empty() {
    [ "${#_MANIFEST_CLI_SUMMARY_ROWS[@]}" -eq 0 ]
}

# Render grouped rows, then a totals block, then the standard footer.
# Groups print in first-seen order; a group with no rows is never printed
# because a group only exists by virtue of having one.
manifest_execution_summary_render() {
    local apply_command="${1:-}"
    local fs="$_MANIFEST_CLI_SUMMARY_FS"
    local -a groups=()
    local row kind action group target bytes note g seen

    # First pass: group order.
    for row in "${_MANIFEST_CLI_SUMMARY_ROWS[@]}"; do
        IFS="$fs" read -r kind action group target bytes note <<< "$row"
        seen=false
        for g in "${groups[@]}"; do
            [[ "$g" == "$group" ]] && { seen=true; break; }
        done
        [[ "$seen" == "false" ]] && groups+=("$group")
    done

    local -A action_count=() action_bytes=()
    local -a manual_cmds=()

    for g in "${groups[@]}"; do
        echo ""
        echo "  ${g}"
        for row in "${_MANIFEST_CLI_SUMMARY_ROWS[@]}"; do
            IFS="$fs" read -r kind action group target bytes note <<< "$row"
            [[ "$group" == "$g" ]] || continue

            if [[ "$kind" == "note" ]]; then
                echo "    ${target}"
                continue
            fi

            local size_col=""
            [[ -n "$bytes" ]] && size_col="  $(manifest_format_bytes "$bytes")"
            local tail=""
            [[ "$action" == "manual" ]] && tail="  (manual)"
            echo "    ${target}${size_col}${tail}"

            action_count["$action"]=$(( ${action_count["$action"]:-0} + 1 ))
            [[ -n "$bytes" ]] && action_bytes["$action"]=$(( ${action_bytes["$action"]:-0} + bytes ))
            if [[ "$action" == "manual" && -n "$note" ]]; then
                manual_cmds+=("$note")
            fi
        done
    done

    echo ""
    echo "  Summary"
    local a label
    for a in delete create update skip manual; do
        [[ -n "${action_count[$a]:-}" ]] || continue
        label="$(_manifest_execution_summary_label "$a")"
        printf '    %-18s %s item(s)' "$label" "${action_count[$a]}"
        [[ -n "${action_bytes[$a]:-}" ]] && printf '   %s' "$(manifest_format_bytes "${action_bytes[$a]}")"
        printf '\n'
    done

    # Manual remedies once, deduplicated — a per-file repeat of the same command
    # is noise, and the user only needs something copy-pasteable.
    if [ "${#manual_cmds[@]}" -gt 0 ]; then
        echo ""
        echo "  To resolve the manual items, run:"
        printf '%s\n' "${manual_cmds[@]}" | sort -u | while IFS= read -r cmd; do
            echo "    $cmd"
        done
    fi

    manifest_execution_footer "$apply_command"
}

# The legacy sentence form: "<Verb> <group>: <target>".
#
# This is what the 61 hand-written lines already say, and it is why the verb
# table above is worded the way it is. A caller migrating to this module renders
# with THIS function and its output does not change by one byte, so its pinned
# contract test keeps passing:
#
#   summary_add delete "installation directory" "$HOME/.manifest-cli"
#   manifest_execution_summary_render_sentences "  "
#   ->  "  Would remove installation directory: $HOME/.manifest-cli"
#
# The grouped renderer above is the concise summary for new commands; this is
# the compatibility surface. Keep both — collapsing them would force every
# migration to also rewrite a pinned string, which is exactly what makes the
# migration expensive enough never to happen.
manifest_execution_summary_render_sentences() {
    local indent="${1:-  }"
    local fs="$_MANIFEST_CLI_SUMMARY_FS"
    local row kind action group target bytes note verb

    for row in "${_MANIFEST_CLI_SUMMARY_ROWS[@]}"; do
        IFS="$fs" read -r kind action group target bytes note <<< "$row"
        if [[ "$kind" == "note" ]]; then
            echo "${indent}${target}"
            continue
        fi
        verb="$(_manifest_execution_summary_verb "$action")" || continue
        echo "${indent}${verb} ${group}: ${target}"
    done
}

export -f manifest_execution_parse
export -f manifest_execution_preview_header
export -f manifest_execution_apply_header
export -f manifest_execution_footer
export -f manifest_execution_summary_render_sentences
export -f manifest_execution_summary_reset
export -f manifest_execution_summary_add
export -f manifest_execution_summary_note
export -f manifest_execution_summary_is_empty
export -f manifest_execution_summary_render
export -f _manifest_execution_summary_verb
export -f manifest_execution_replay_hint
# manifest_execution_require_apply is deliberately NOT exported (TRACKER §59).
# It hard-calls manifest_repo_scope_confirm_apply at :112 and returns that call's
# status as its own verdict, so exporting it without the gate hands an exec'd
# child a `command not found` 127 dressed up as "apply declined" -- and
# exporting it WITH the gate reopens §46 (see the export list in
# manifest-shared-utils.sh for why the gate's closure cannot leave this process).
# Nothing execs a child that CALLS it. There are two `bash -c` sites in modules/:
# the release gate (manifest-orchestrator.sh, _manifest_release_gate_exec) runs
# under `env -i`, which strips BASH_FUNC_* along with everything else; and the
# Homebrew bootstrap (manifest-core.sh) is NOT under env -i and so does inherit
# exported functions, but it runs a third-party installer that calls none of
# ours. Stated as two rather than one on purpose -- the earlier wording said
# "the only bash -c" and was wrong, even though the conclusion held.
