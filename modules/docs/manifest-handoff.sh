#!/bin/bash

# Manifest Documentation Handoff Module (TRACKER §78)
#
# Lets whoever is driving the ship — an AI agent, or a human — finish the
# release documentation before the release commit is made, and VERIFIES what
# comes back before committing it.
#
# THE SHAPE, and why it is this shape:
#
# Manifest does the mechanical parts (bump VERSION, write a CHANGELOG skeleton
# from the real commit subjects), writes a BRIEF describing exactly what is
# needed, and STOPS with a distinct exit code. Nothing is committed, tagged or
# pushed. The driver edits the documentation and re-runs the identical command;
# that re-run lands in the ship's existing `resume-in-place` state, verifies the
# edits structurally, and only then commits.
#
#   - Nothing here executes a program, ever. The alternative design — detect an
#     agent CLI and run it as a provider — is what §44 argues against in its own
#     words: it turns "the user configured a command" into "Manifest chose a
#     program to run for you". Because this module names no program, its config
#     key is ordinary policy and may live in a committed file, which is what
#     makes a team's release contract shareable at all.
#   - Detection is a DEFAULT-CHOOSER, not a gate. `auto` asks the driver
#     detector whether pausing would help. Every signal it reads is claimed
#     rather than authenticated, so it may only decide convenience, never
#     safety. `always` needs no detection at all.
#   - The pause is NOT a failure. It has its own report and its own recovery
#     mode, because the ship's failure classifier would otherwise advise
#     reverting the very files the driver is being asked to write.
#   - TRUST IS NOT THE MECHANISM — verification is. An agent asserting it
#     updated the docs is an unverified claim; the re-run checks the structure
#     it can check and says exactly which rule failed. That check is worth the
#     same whether a model, a person, or a future Cloud provider did the work.

# Where pause state lives. Under .git/, never in the working tree: the release
# commit ends in a bare `git add .`, so a brief written beside the source would
# be committed into the release it describes. Mirrors
# _manifest_doc_review_state_dir's reasoning.
manifest_handoff_state_dir() {
    local project_root="${1:-${MANIFEST_CLI_PROJECT_ROOT:-$PWD}}"
    local git_dir
    git_dir="$(git -C "$project_root" rev-parse --git-dir 2>/dev/null)" || return 1
    [[ "$git_dir" != /* ]] && git_dir="$project_root/$git_dir"
    printf '%s' "$git_dir/manifest-ship/handoff"
}

# One placeholder pattern, defined once. §85(b)'s declarative placeholder
# substitution will consume the same definition, so a token that substitution
# understands is a token this scan can find left behind.
#
# `X.Y.Z` WAS in this pattern and was removed before shipping, because it is a
# description of a version FORMAT and not a placeholder anybody substitutes.
# It matched five lines of this repository's own documentation — including the
# handoff's own USER_GUIDE section, which spells out the `## [X.Y.Z] - <date>`
# heading — so `docs.handoff: always` here produced a release that could never
# complete: every re-run failed R3 on prose that was never wrong, and the only
# exits were to corrupt correct documentation or abandon the release. Found by
# the pre-commit steward review, reproduced in this repo before the change.
#
# The remaining two tokens are deliberate markers a person types INTENDING them
# to be replaced. Matching is done against text with code spans removed (see
# _manifest_handoff_strip_code), because documentation that *discusses* a
# placeholder writes it in backticks, while one awaiting substitution does not.
MANIFEST_CLI_VERSION_PLACEHOLDER_REGEX='vNEXT|\{\{ *next_version *\}\}'

# Echo $1 with fenced blocks and inline code spans blanked out, so a scan can
# tell a placeholder in the prose from a placeholder being talked ABOUT. Lines
# are preserved (blanked, not deleted) so reported line numbers stay true.
_manifest_handoff_strip_code() {
    awk '
        /^[[:space:]]*```/ { fenced = !fenced; print ""; next }
        fenced { print ""; next }
        { gsub(/`[^`]*`/, ""); print }
    ' "$1"
}

# ---------------------------------------------------------------------------
# Policy
# ---------------------------------------------------------------------------

# Echo the normalized handoff policy. Defaults to `off` so upgrading changes
# nothing: pausing a ship that used to complete is a behaviour change, and it
# must be asked for. Rejects unknown values (return 2) exactly as
# manifest_release_gate_policy does, so a typo cannot silently disable it.
manifest_handoff_policy() {
    local norm
    if declare -F normalize_enum_value >/dev/null 2>&1; then
        norm="$(normalize_enum_value "${MANIFEST_CLI_DOCS_HANDOFF:-off}")"
    else
        norm="$(printf '%s' "${MANIFEST_CLI_DOCS_HANDOFF:-off}" | tr '[:upper:]' '[:lower:]')"
    fi
    case "$norm" in
        off|auto|always) printf '%s' "$norm" ;;
        *)
            log_error "Invalid docs_handoff '${MANIFEST_CLI_DOCS_HANDOFF}'. Expected: off, auto, always."
            return 2
            ;;
    esac
}

# True when this apply should pause for the driver.
#
# A fleet member NEVER pauses, whatever the policy says. Members run in a
# subshell whose non-zero status breaks the fleet loop into its recovery
# report, so a paused member would read as a failed one and stop the fleet. The
# fleet-level design for this is deferred (§78 fleet follow-up).
manifest_handoff_should_pause() {
    local policy rc=0
    policy="$(manifest_handoff_policy)" || rc=$?
    # An unreadable policy is NOT "off". The comment on manifest_handoff_policy
    # claims a typo cannot silently disable the handoff; before this it could —
    # the rejection was printed and then the ship proceeded and committed.
    # Return 2 so the caller can refuse rather than quietly carry on.
    [[ "$rc" -eq 0 ]] || return 2
    [[ "$policy" == "off" ]] && return 1
    [[ "${_MANIFEST_CLI_DELEGATED_APPLY_CONSENT:-}" == "1" ]] && return 1
    [[ "$policy" == "always" ]] && return 0
    # auto
    declare -F manifest_driver_is_agent >/dev/null 2>&1 || return 1
    manifest_driver_is_agent
}

# The disclosure block. ONE renderer for preview and apply so the two cannot
# disagree about what the run will do (§6). Silent when the policy is off.
manifest_handoff_disclose() {
    local replay="${1:-}"
    local policy
    policy="$(manifest_handoff_policy 2>/dev/null)" || return 0
    [[ "$policy" == "off" ]] && return 0

    local layer="" driver=""
    if declare -F manifest_config_execution_key_layer >/dev/null 2>&1; then
        layer="$(manifest_config_execution_key_layer MANIFEST_CLI_DOCS_HANDOFF)"
    fi
    if declare -F manifest_driver_describe >/dev/null 2>&1; then
        driver="$(manifest_driver_describe)"
    fi

    # A pending brief changes what this run does, so it changes what the
    # disclosure says. Saying "this run pauses" on the run that is actually
    # verifying and committing would describe the opposite of what happens.
    local pending=""
    pending="$(manifest_handoff_pending "${MANIFEST_CLI_PROJECT_ROOT:-$PWD}")"

    echo ""
    if [[ -n "$pending" ]]; then
        local pending_version="${pending%%$'\t'*}"
        echo "Documentation handoff: this run VERIFIES the edits for $pending_version, then commits"
    elif manifest_handoff_should_pause; then
        echo "Documentation handoff: this run PAUSES before the release commit"
    elif [[ "${_MANIFEST_CLI_DELEGATED_APPLY_CONSENT:-}" == "1" ]]; then
        echo "Documentation handoff: off for this run (fleet member; handoff is a per-repo ship feature)"
    else
        echo "Documentation handoff: off for this run (docs.handoff: $policy does not apply to this driver)"
    fi
    printf '   docs.handoff: %s' "$policy"
    [[ -n "$layer" ]] && printf ' (%s layer)' "$layer"
    printf '\n'
    [[ -n "$driver" ]] && echo "   driver: $driver"
    if [[ -n "$pending" ]]; then
        echo "   brief: $(printf '%s' "$pending" | cut -f4)"
        echo "   CHANGELOG.md is NOT regenerated on this run; your edits are what gets committed."
    elif manifest_handoff_should_pause; then
        echo "   Manifest writes VERSION and a CHANGELOG skeleton, then stops with exit ${MANIFEST_CLI_SHIP_HANDOFF_PAUSED_EXIT_CODE:-4}."
        echo "   Whoever is driving edits the documentation and re-runs the same command to verify and continue."
        [[ -n "$replay" ]] && echo "   Continue with: $replay"
        echo "   No program is chosen or run on your behalf; detection only decides this default."
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Pending state
# ---------------------------------------------------------------------------

# Echo `version<TAB>increment<TAB>date<TAB>brief_path` for a pending handoff, or
# nothing. A pending brief is the record that a previous run stopped here.
manifest_handoff_pending() {
    local project_root="${1:-${MANIFEST_CLI_PROJECT_ROOT:-$PWD}}"
    local dir state
    dir="$(manifest_handoff_state_dir "$project_root")" || return 0
    state="$dir/state"
    [[ -f "$state" ]] || return 0
    local version increment rel_date brief
    version="$(_manifest_handoff_state_get "$state" version)"
    increment="$(_manifest_handoff_state_get "$state" increment_type)"
    rel_date="$(_manifest_handoff_state_get "$state" date)"
    brief="$(_manifest_handoff_state_get "$state" brief)"
    [[ -n "$version" ]] || return 0
    printf '%s\t%s\t%s\t%s' "$version" "$increment" "$rel_date" "$brief"
}

_manifest_handoff_state_get() {
    local file="$1" key="$2" line
    [[ -f "$file" ]] || return 0
    while IFS= read -r line; do
        case "$line" in
            "$key="*) printf '%s' "${line#*=}"; return 0 ;;
        esac
    done < "$file"
    return 0
}

# Remove the pause state once the release commit has landed.
manifest_handoff_clear() {
    local project_root="${1:-${MANIFEST_CLI_PROJECT_ROOT:-$PWD}}"
    local dir
    dir="$(manifest_handoff_state_dir "$project_root")" || return 0
    [[ -n "$dir" ]] || return 0
    rm -rf "$dir" 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# The stale scan
# ---------------------------------------------------------------------------

# Lines in tracked markdown that look stale: still naming the PREVIOUS version,
# or carrying an unsubstituted placeholder. Echoes `path:line:text` rows.
#
# CHANGELOG.md is excluded because naming old versions is its job, and the
# archive folder because it is a deliberate record of superseded documents
# (a sweep that reaches into it is TRACKER's ignore-zArchive rule).
manifest_handoff_stale_scan() {
    local project_root="${1:-${MANIFEST_CLI_PROJECT_ROOT:-$PWD}}"
    local previous_version="$2"
    local archive="${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER:-docs/zArchive}"
    local file

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        [[ "$file" == "CHANGELOG.md" ]] && continue
        case "$file" in
            "$archive"/*|*/"$archive"/*) continue ;;
        esac
        [[ -f "$project_root/$file" ]] || continue
        # -F for the version (a literal with dots; a BRE would match any char
        # there and over-report), -E for the placeholder alternation.
        if [[ -n "$previous_version" ]]; then
            grep -nF -- "$previous_version" "$project_root/$file" 2>/dev/null |
                while IFS= read -r hit; do printf '%s:%s\n' "$file" "$hit"; done
        fi
        # Code-stripped, so documentation ABOUT a placeholder is not reported
        # as one. Line numbers survive because the stripper blanks lines
        # rather than dropping them.
        _manifest_handoff_strip_code "$project_root/$file" \
            | grep -nE -- "$MANIFEST_CLI_VERSION_PLACEHOLDER_REGEX" 2>/dev/null \
            | while IFS= read -r hit; do printf '%s:%s\n' "$file" "$hit"; done
    done < <(git -C "$project_root" ls-files -- '*.md' 2>/dev/null)
    return 0
}

# ---------------------------------------------------------------------------
# The brief
# ---------------------------------------------------------------------------

# Write the pause state and BRIEF.md, then print the operator-facing summary.
#   $1 version  $2 previous_version  $3 timestamp  $4 increment  $5 local_only
manifest_handoff_pause() {
    local version="$1" previous_version="$2" timestamp="$3"
    local increment="$4" local_only="$5"
    local project_root="${MANIFEST_CLI_PROJECT_ROOT:-$PWD}"
    local dir brief state release_date range tag driver=""

    dir="$(manifest_handoff_state_dir "$project_root")" || {
        log_error "Documentation handoff: cannot resolve the state directory."
        return 1
    }
    mkdir -p "$dir" || return 1
    brief="$dir/BRIEF.md"
    state="$dir/state"
    release_date="${timestamp%% *}"
    [[ -n "$release_date" ]] || release_date="$(date -u '+%Y-%m-%d')"

    if declare -F manifest_release_tag_name >/dev/null 2>&1; then
        tag="$(manifest_release_tag_name "$version")"
    else
        tag="v${version#v}"
    fi
    if declare -F manifest_driver_describe >/dev/null 2>&1; then
        driver="$(manifest_driver_describe)"
    fi
    range="$(git -C "$project_root" describe --tags --abbrev=0 HEAD 2>/dev/null || true)"
    if [[ -n "$range" ]]; then
        range="${range}..HEAD"
    else
        range="(no previous tag)"
    fi

    {
        printf 'version=%s\n' "$version"
        printf 'previous_version=%s\n' "$previous_version"
        printf 'date=%s\n' "$release_date"
        printf 'timestamp=%s\n' "$timestamp"
        printf 'increment_type=%s\n' "$increment"
        printf 'local_only=%s\n' "$local_only"
        printf 'head_sha=%s\n' "$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo unknown)"
        printf 'range=%s\n' "$range"
        printf 'driver=%s\n' "$driver"
        printf 'created_at=%s\n' "$timestamp"
        printf 'brief=%s\n' "$brief"
    } > "$state" || return 1

    local replay="manifest ship repo $increment"
    [[ "$local_only" == "true" ]] && replay="$replay --local"
    replay="$replay -y"

    local stale
    stale="$(manifest_handoff_stale_scan "$project_root" "$previous_version")"
    local stale_count=0
    [[ -n "$stale" ]] && stale_count="$(printf '%s\n' "$stale" | grep -c . || true)"

    {
        printf '# Documentation handoff for %s\n\n' "$version"
        printf 'Manifest paused this release so the documentation can be finished before the\n'
        printf 'release commit is made. Nothing has been committed, tagged or pushed.\n\n'
        printf '## Release facts\n\n'
        printf -- '- Version: **%s** (previous: %s)\n' "$version" "${previous_version:-unknown}"
        printf -- '- Release date: **%s** (from the trusted timestamp %s)\n' "$release_date" "$timestamp"
        printf -- '- Tag that will be created: `%s`\n' "$tag"
        printf -- '- Increment: %s\n' "$increment"
        if [[ "$local_only" == "true" ]]; then
            printf -- '- Scope: local only — no push, no GitHub release\n'
        else
            printf -- '- Scope: publishing — the tag and commit will be pushed\n'
        fi
        printf -- '- Commit range: `%s`\n\n' "$range"

        printf '## Commits in this release\n\n'
        local subject
        while IFS= read -r subject; do
            [[ -n "$subject" ]] || continue
            printf -- '- %s\n' "$subject"
        done < <(git -C "$project_root" log --format='%s' "$(git -C "$project_root" describe --tags --abbrev=0 HEAD 2>/dev/null || echo HEAD)..HEAD" 2>/dev/null | head -n 50)
        printf '\n'

        printf '## Files changed\n\n'
        local changed
        changed="$(git -C "$project_root" diff --name-only HEAD 2>/dev/null | head -n 60)"
        if [[ -n "$changed" ]]; then
            printf '```\n%s\n```\n\n' "$changed"
        else
            printf '(none uncommitted)\n\n'
        fi

        printf '## What Manifest already wrote — keep it\n\n'
        printf -- '- `VERSION` is already `%s`. Do not edit it.\n' "$version"
        printf -- '- `CHANGELOG.md` has a section headed exactly:\n\n'
        printf '      ## [%s] - %s\n\n' "$version" "$release_date"
        printf -- '  Keep that heading verbatim, including the date. Rewrite the bullets under\n'
        printf -- '  it to say what actually changed and why it matters to a reader.\n\n'

        printf '## Possibly stale documentation\n\n'
        if [[ -n "$stale" ]]; then
            printf 'Lines in tracked markdown still naming `%s`, or carrying a version\n' "${previous_version:-the previous version}"
            printf 'placeholder. A mention of an older version in prose is often correct — judge\n'
            printf 'each one. Placeholders are never correct at this point.\n\n```\n'
            printf '%s\n' "$stale" | head -n 200
            printf '```\n\n'
        else
            printf 'None found.\n\n'
        fi

        printf '## What the re-run verifies\n\n'
        printf -- '- **R1** `CHANGELOG.md` has exactly one heading `## [%s] - %s`.\n' "$version" "$release_date"
        printf -- '- **R2** That section has at least one `- ` bullet.\n'
        printf -- '- **R3** No version placeholder remains in tracked markdown.\n'
        printf -- '- **R4** That section contains no assistant preamble ("As an AI", "Sure, here", ...).\n\n'
        printf 'Manifest-managed blocks in README.md / docs/INDEX.md are regenerated for you;\n'
        printf 'do not edit inside them.\n\n' 

        printf '## What Manifest will NOT do\n\n'
        printf -- '- It will not run any program on your behalf.\n'
        printf -- '- It will **not** regenerate `CHANGELOG.md` on the re-run — your edits stand.\n'
        printf -- '- The release gate runs again on the re-run.\n\n'

        printf '## Continue\n\n'
        printf '    %s\n\n' "$replay"
        printf '## Abandon instead\n\n'
        printf '    git checkout HEAD -- VERSION CHANGELOG.md\n'
        printf '    rm -rf %s\n\n' "$dir"
        printf 'Your own edits since the pause are yours to keep or revert.\n'
    } > "$brief" || return 1

    echo ""
    echo "📝 Documentation handoff for $version"
    echo "   brief:      $brief"
    echo "   changelog:  ## [$version] - $release_date  (heading is fixed; rewrite the bullets)"
    if [[ "$stale_count" -gt 0 ]]; then
        echo "   stale scan: $stale_count line(s) in tracked markdown to review"
    else
        echo "   stale scan: no stale version references found"
    fi
    [[ -n "$driver" ]] && echo "   driver:     $driver"
    return 0
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

# Verify the driver's documentation edits. Collects EVERY failure before
# returning, so one re-run reports everything rather than one rule per attempt.
manifest_handoff_verify() {
    local version="$1"
    local project_root="${MANIFEST_CLI_PROJECT_ROOT:-$PWD}"
    local dir state release_date changelog section
    local -a failures=()

    dir="$(manifest_handoff_state_dir "$project_root")" || return 1
    state="$dir/state"
    release_date="$(_manifest_handoff_state_get "$state" date)"
    changelog="$project_root/CHANGELOG.md"

    # R1 — exactly one heading, carrying the date recorded at the pause. The
    # re-run gets a NEW trusted timestamp, so "today" is the wrong thing to
    # compare against: the release is dated when it was prepared.
    local heading="## [$version] - $release_date"
    local heading_count=0
    if [[ -f "$changelog" ]]; then
        heading_count="$(grep -cxF -- "$heading" "$changelog" 2>/dev/null || true)"
        [[ -n "$heading_count" ]] || heading_count=0
    fi
    if [[ "$heading_count" != "1" ]]; then
        failures+=("R1 CHANGELOG.md: expected exactly one heading \"$heading\"; found $heading_count. The date is the release date recorded when the handoff was written, not today's.")
    fi

    # R2 — the section says something.
    if [[ "$heading_count" == "1" ]]; then
        section="$(awk -v h="$heading" '
            $0 == h { inside = 1; next }
            inside && /^## \[/ { exit }
            inside { print }
        ' "$changelog" 2>/dev/null)"
        # Bullets inside a fenced block are an example, not release content —
        # the skeleton's own brief shows one, and copying it in would otherwise
        # satisfy R2 with nothing said.
        local section_prose
        section_prose="$(printf '%s\n' "$section" | awk '
            /^[[:space:]]*```/ { fenced = !fenced; next }
            fenced { next }
            { print }
        ')"
        if ! printf '%s\n' "$section_prose" | grep -q '^- '; then
            failures+=("R2 CHANGELOG.md: the [$version] section has no bullets.")
        fi

        # R4 — assistant preamble. One phrase list, shared with the
        # release-notes provider validator, so the two can never disagree.
        local banned
        banned="$(_manifest_handoff_banned_phrase "$section_prose")"
        if [[ -n "$banned" ]]; then
            failures+=("R4 CHANGELOG.md: the [$version] section contains assistant preamble (\"$banned\").")
        fi
    fi

    # R3 — no placeholder left anywhere in tracked markdown.
    local archive="${MANIFEST_CLI_DOCS_ARCHIVE_FOLDER:-docs/zArchive}"
    local file hit
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        case "$file" in
            "$archive"/*|*/"$archive"/*) continue ;;
        esac
        [[ -f "$project_root/$file" ]] || continue
        hit="$(_manifest_handoff_strip_code "$project_root/$file" \
                | grep -nE -m1 -- "$MANIFEST_CLI_VERSION_PLACEHOLDER_REGEX" 2>/dev/null || true)"
        if [[ -n "$hit" ]]; then
            failures+=("R3 $file:${hit%%:*} still carries a version placeholder.")
        fi
    done < <(git -C "$project_root" ls-files -- '*.md' 2>/dev/null)

    # R5 — a managed version block, where a repo has one, still names this
    # version. Repos without the markers skip this: nothing to check.
    # R5 WAS HERE and was deleted before shipping, deliberately. It checked
    # that a Manifest-managed version block still named the new version. Two
    # things make that the wrong rule:
    #
    #   1. Those blocks are MANIFEST's output, not the driver's work. The brief
    #      tells the driver not to edit inside them, and the resume now
    #      regenerates them (only the CHANGELOG is held back), so the rule was
    #      checking the tool against itself.
    #   2. Getting it right means knowing WHICH managed block carries a version
    #      — `manifest:readme-version` does, `manifest:index-metadata` does,
    #      `manifest:index-current-release` does not — which is a second
    #      derivation of doc-generation's internals living over here, exactly
    #      the §36 shape this codebase keeps paying for. The first cut read the
    #      whole file (so a version in a badge passed a stale block); the
    #      second read the wrong block and failed every paused release in a
    #      repo that has an INDEX.
    #
    # A rule that cannot pass is worse than no rule — that is what the removed
    # `X.Y.Z` placeholder taught two hours earlier in the same change.

    if [[ ${#failures[@]} -gt 0 ]]; then
        local f
        log_error "Documentation handoff not complete for $version (${#failures[@]} rule(s) failed)."
        for f in "${failures[@]}"; do
            echo "   $f"
        done
        return 1
    fi

    echo "✅ Documentation handoff verified for $version (${heading_count} changelog section, placeholders clear)"
    return 0
}

# Echo the first banned assistant-preamble phrase found in $1, or nothing.
# THE one list: _manifest_release_notes_validate_output calls this too, so a
# phrase added here is rejected on both paths.
_manifest_handoff_banned_phrase() {
    local text="$1" phrase
    for phrase in "As an AI" "As a language model" "Sure, here" "Here are the" "I'll generate" "I'd be happy"; do
        case "$text" in
            *"$phrase"*) printf '%s' "$phrase"; return 0 ;;
        esac
    done
    return 0
}

export -f manifest_handoff_state_dir manifest_handoff_policy \
    manifest_handoff_should_pause manifest_handoff_disclose \
    manifest_handoff_pending manifest_handoff_clear \
    manifest_handoff_stale_scan manifest_handoff_pause \
    manifest_handoff_verify _manifest_handoff_banned_phrase \
    _manifest_handoff_state_get
