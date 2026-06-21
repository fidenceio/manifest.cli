#!/usr/bin/env bash

# =============================================================================
# Manifest CLI - Fleet GitHub Topics Module (tracker §9.1)
# =============================================================================
#
# Projects repo-name slugs onto GitHub topics so a fleet's naming convention
# becomes filterable in the GitHub org UI (?q=topic:...).
#
# Opt-in via ONE key in manifest.fleet.config.yaml:
#
#   topics:
#     from_name: inner    # fidence.service.accounting.avalara -> service, accounting
#
# Modes: inner (drop first and last slug) | all | all-but-first.
# Absent / empty / null = off: zero gh calls, no output. A present but
# invalid value fails loud (a typo must never silently disable the feature).
#
# Contract:
#   - Additive-only. Existing topics are read first (gh repo view) and only
#     the missing ones are pushed (gh repo edit --add-topic). Manifest never
#     removes a topic: derived slugs carry no ownership mark, and a repo may
#     belong to more than one fleet, so removal cannot be attributed safely.
#   - Members also receive a fleet-<name> membership topic when fleet.name
#     is set, making the whole fleet filterable in one query.
#   - The repo slug comes from each member's own git remote (origin), not
#     from inventory copies — the repo's git info is the source of truth.
#   - gh missing/unauthenticated, non-GitHub origins, and repos whose names
#     derive zero slugs are per-member skips with a notice, never failures
#     (same degraded-mode posture as GitHub release creation).
#
# Roster (Phase 2): with topics on, the run also lists org repos that match
# the fleet's naming family (same first dot-slug as an enrolled member) but
# are not in the local fleet — new family repos nobody has cloned yet.
# This is READ-ONLY and REPORT-ONLY by design:
#   - enumeration uses the full org list (gh repo list --json name); a
#     fleet-topic-filtered query could never find untagged new repos
#   - candidates are reported with a clone-to-enroll hint, never written to
#     the TSV (a regenerate — merge_update_tsv default mode, used by init —
#     rebuilds the TSV from the local scan, so a remote-only row would be
#     silently wiped) and never
#     topic-stamped (writes to un-enrolled repos would break the consent
#     boundary) — cloning into the fleet root IS the enrollment act
#   - a failed org listing degrades to a per-owner notice, never a failure
#   - MANIFEST_CLI_FLEET_TOPICS_ROSTER_LIMIT (default 1000) bounds the
#     listing; hitting the cap is reported, never silent
# =============================================================================

# -----------------------------------------------------------------------------
# Function: manifest_fleet_topics_mode
# -----------------------------------------------------------------------------
# Reads and validates topics.from_name from the fleet config.
# MANIFEST_CLI_FLEET_TOPICS_FROM_NAME (env) takes precedence over YAML.
#
# Echoes the mode, or "" when the feature is off (absent/empty/null).
# Returns 1 (fail loud) on a present-but-invalid value.
# -----------------------------------------------------------------------------
manifest_fleet_topics_mode() {
    local config_file="$1"
    local mode="${MANIFEST_CLI_FLEET_TOPICS_FROM_NAME:-}"

    if [[ -z "$mode" && -f "$config_file" ]]; then
        mode=$(get_yaml_value "$config_file" ".topics.from_name" "")
    fi

    case "$mode" in
        "")
            echo ""
            return 0
            ;;
        inner|all|all-but-first)
            echo "$mode"
            return 0
            ;;
        *)
            log_error "Invalid topics.from_name: '$mode' (valid: inner | all | all-but-first; remove the key to disable)"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Function: _fleet_topics_normalize_slug
# -----------------------------------------------------------------------------
# Normalizes one name slug into a GitHub-legal topic: lowercase, [a-z0-9-]
# only, must start with a letter or digit, max 50 chars. Echoes "" when
# nothing legal remains (caller drops it).
# -----------------------------------------------------------------------------
_fleet_topics_normalize_slug() {
    local slug="$1"
    slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    while [[ "$slug" == -* ]]; do slug="${slug#-}"; done
    echo "${slug:0:50}"
}

# -----------------------------------------------------------------------------
# Function: _fleet_topics_derive
# -----------------------------------------------------------------------------
# Derives topics from a dot-separated repo name per the configured mode.
# Echoes normalized topics one per line (deduplicated, empties dropped).
# A name with too few slugs for the mode derives nothing — that is a no-op,
# not an error.
# -----------------------------------------------------------------------------
_fleet_topics_derive() {
    local repo_name="$1"
    local mode="$2"

    local -a slugs=()
    IFS='.' read -r -a slugs <<< "$repo_name"
    local count=${#slugs[@]}

    local -a picked=()
    case "$mode" in
        all)
            picked=("${slugs[@]}")
            ;;
        all-but-first)
            (( count >= 2 )) && picked=("${slugs[@]:1}")
            ;;
        inner)
            (( count >= 3 )) && picked=("${slugs[@]:1:count-2}")
            ;;
    esac

    local slug normalized seen=" "
    for slug in "${picked[@]:-}"; do
        normalized=$(_fleet_topics_normalize_slug "$slug")
        [[ -z "$normalized" ]] && continue
        [[ "$seen" == *" $normalized "* ]] && continue
        seen="$seen$normalized "
        echo "$normalized"
    done
}

# -----------------------------------------------------------------------------
# Function: _fleet_topics_current
# -----------------------------------------------------------------------------
# Reads a repo's existing topics from GitHub, one per line. Returns 1 when
# they cannot be read; the caller then treats current as unknown and pushes
# the full desired set — safe, because --add-topic is idempotent on the
# server side.
# -----------------------------------------------------------------------------
_fleet_topics_current() {
    local slug="$1"
    gh repo view "$slug" --json repositoryTopics \
        --jq '.repositoryTopics[].name' 2>/dev/null
}

# -----------------------------------------------------------------------------
# Function: _fleet_topics_org_candidates
# -----------------------------------------------------------------------------
# Pure candidate filter (no gh): given one owner, the newline list of known
# member slugs (owner/name), the newline list of family prefixes (lowercased
# first dot-slugs of enrolled members), and the newline list of the owner's
# org repo names, echoes "owner/name" for each org repo that belongs to the
# naming family but is not an enrolled member.
# -----------------------------------------------------------------------------
_fleet_topics_org_candidates() {
    local owner="$1"
    local known="$2"
    local prefixes="$3"
    local org_names="$4"

    local name first
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        printf '%s\n' "$known" | grep -qxF "$owner/$name" && continue
        first=$(printf '%s' "${name%%.*}" | tr '[:upper:]' '[:lower:]')
        [[ -z "$first" ]] && continue
        printf '%s\n' "$prefixes" | grep -qxF "$first" || continue
        echo "$owner/$name"
    done <<< "$org_names"
    return 0
}

# -----------------------------------------------------------------------------
# Function: _fleet_topics_roster_report
# -----------------------------------------------------------------------------
# Lists unenrolled family repos per owner (read-only, report-only — see the
# module header). Always returns 0: a failed org listing is a notice.
#
# ARGUMENTS:
#   $1   - newline list of known member slugs (owner/name)
#   $2   - newline list of family prefixes (lowercased first slugs)
#   $3.. - distinct owners to query
# -----------------------------------------------------------------------------
_fleet_topics_roster_report() {
    local known="$1"
    local prefixes="$2"
    shift 2
    [[ $# -eq 0 ]] && return 0

    local limit="${MANIFEST_CLI_FLEET_TOPICS_ROSTER_LIMIT:-1000}"
    local owner names count candidates=""

    for owner in "$@"; do
        [[ -z "$owner" ]] && continue
        if ! names=$(gh repo list "$owner" --no-archived --limit "$limit" \
            --json name --jq '.[].name' 2>/dev/null); then
            echo "  ⚠ Roster check skipped for $owner (gh repo list failed)"
            continue
        fi
        count=$(printf '%s\n' "$names" | grep -c . || true)
        if [[ "$count" -ge "$limit" ]]; then
            echo "  ℹ Roster check covered only the first $limit repos of $owner"
        fi
        local found
        found=$(_fleet_topics_org_candidates "$owner" "$known" "$prefixes" "$names")
        [[ -n "$found" ]] && candidates+="$found"$'\n'
    done

    candidates=$(printf '%s' "$candidates" | awk 'NF && !seen[$0]++')
    if [[ -z "$candidates" ]]; then
        echo "  Roster: no unenrolled family repos found on GitHub"
        return 0
    fi

    local n
    n=$(printf '%s\n' "$candidates" | grep -c .)
    echo "  Roster: $n family repo(s) exist on GitHub but are not in this fleet:"
    local c
    while IFS= read -r c; do
        echo "    - $c"
    done <<< "$candidates"
    echo "  Clone into the fleet root, then run 'manifest update fleet' to enroll."
    return 0
}

# -----------------------------------------------------------------------------
# Function: manifest_fleet_topics_run
# -----------------------------------------------------------------------------
# The single hook called at the end of `manifest update fleet`, by the
# `manifest topics fleet` command, and (quietly) at the end of a fleet ship.
# Preview mode lists the per-member topic delta; apply mode pushes it. Off
# (no mode) is a silent no-op with zero gh calls.
#
# Quiet mode is for the ship path: no header, no per-member lines, no roster —
# one summary line only when something was pushed or failed, and degraded-mode
# skips (gh missing/unauthenticated) stay fully silent. Topics are post-release
# metadata grooming; they must never add noise to a clean ship.
#
# ARGUMENTS:
#   $1 - Fleet root directory
#   $2 - Fleet config file path
#   $3 - dry_run ("true" = preview, anything else = apply)
#   $4 - quiet ("true" = ship mode as above; default "false")
#   $5 - apply hint shown after a preview with changes
#        (default "manifest update fleet -y")
#
# RETURNS:
#   0 on success or any skip; 1 only on an invalid topics.from_name value.
# -----------------------------------------------------------------------------
manifest_fleet_topics_run() {
    local root_dir="$1"
    local config_file="$2"
    local dry_run="${3:-true}"
    local quiet="${4:-false}"
    local apply_hint="${5:-manifest update fleet -y}"

    local mode
    mode=$(manifest_fleet_topics_mode "$config_file") || return 1
    [[ -z "$mode" ]] && return 0

    local tsv_file="$root_dir/manifest.fleet.tsv"
    [[ -f "$tsv_file" ]] || return 0

    if [[ "$quiet" != "true" ]]; then
        echo ""
        echo "Topics (topics.from_name: $mode):"
    fi

    if ! command -v gh >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && echo "  ⚠ skipped — 'gh' (GitHub CLI) is not installed"
        return 0
    fi
    if ! gh auth status >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && echo "  ⚠ skipped — 'gh' is not authenticated (run: gh auth login)"
        return 0
    fi

    # Optional fleet membership topic from fleet.name.
    local fleet_topic=""
    local fleet_name
    fleet_name=$(get_yaml_value "$config_file" ".fleet.name" "")
    if [[ -n "$fleet_name" && "$fleet_name" != "unnamed-fleet" ]]; then
        fleet_topic=$(_fleet_topics_normalize_slug "fleet-$(printf '%s' "$fleet_name" | tr '.' '-')")
    fi

    local pushed=0 unchanged=0 skipped=0 failed=0
    local roster_known="" roster_prefixes=""
    local -a roster_owners=()
    local member_rows
    member_rows=$(parse_start_tsv "$tsv_file")

    local name path has_git _url _branch
    while IFS=$'\t' read -r name path has_git _url _branch; do
        [[ -z "$name" ]] && continue
        [[ "$has_git" != "true" ]] && continue

        local abs_path="$path"
        [[ "$abs_path" != /* ]] && abs_path="$root_dir/${path#./}"

        # The member's own git remote is the source of truth for its slug.
        local remote_url
        remote_url=$(git -C "$abs_path" remote get-url origin 2>/dev/null || echo "")
        if [[ "$remote_url" != *github.com* ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        local slug
        slug=$(manifest_origin_repo_slug "$abs_path" 2>/dev/null) || slug=""
        if [[ -z "$slug" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        local repo_name="${slug##*/}"

        # Roster bookkeeping: enrolled slugs, family prefixes, distinct owners.
        local owner="${slug%%/*}" first_slug
        roster_known+="$slug"$'\n'
        first_slug=$(printf '%s' "${repo_name%%.*}" | tr '[:upper:]' '[:lower:]')
        [[ -n "$first_slug" ]] && roster_prefixes+="$first_slug"$'\n'
        case " ${roster_owners[*]:-} " in
            *" $owner "*) ;;
            *) roster_owners+=("$owner") ;;
        esac

        local desired
        desired=$(_fleet_topics_derive "$repo_name" "$mode")
        if [[ -n "$fleet_topic" ]]; then
            desired=$(printf '%s\n%s\n' "$desired" "$fleet_topic" | awk 'NF && !seen[$0]++')
        fi
        if [[ -z "$desired" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        # Read existing topics first; push only what is missing.
        local current current_known=true
        if ! current=$(_fleet_topics_current "$slug"); then
            current=""
            current_known=false
        fi

        local -a delta=()
        local topic
        while IFS= read -r topic; do
            [[ -z "$topic" ]] && continue
            if [[ "$current_known" == "true" ]] \
                && printf '%s\n' "$current" | grep -qxF "$topic"; then
                continue
            fi
            delta+=("$topic")
        done <<< "$desired"

        if [[ ${#delta[@]} -eq 0 ]]; then
            unchanged=$((unchanged + 1))
            continue
        fi

        local delta_label=""
        for topic in "${delta[@]}"; do delta_label+=" +$topic"; done

        if [[ "$dry_run" == "true" ]]; then
            [[ "$quiet" != "true" ]] && printf "  + %-25s%s\n" "$repo_name" "$delta_label"
            pushed=$((pushed + 1))
        else
            local -a edit_args=("repo" "edit" "$slug")
            for topic in "${delta[@]}"; do edit_args+=("--add-topic" "$topic"); done
            if gh "${edit_args[@]}" >/dev/null 2>&1; then
                [[ "$quiet" != "true" ]] && printf "  ✓ %-25s%s\n" "$repo_name" "$delta_label"
                pushed=$((pushed + 1))
            else
                [[ "$quiet" != "true" ]] && printf "  ⚠ %-25s failed to update topics (continuing)\n" "$repo_name"
                failed=$((failed + 1))
            fi
        fi
    done <<< "$member_rows"

    if [[ "$quiet" == "true" ]]; then
        # One line, and only when there is something to say: changes made, or
        # failures that must not go silent.
        if [[ "$failed" -gt 0 ]]; then
            echo "🏷️  GitHub topics: $pushed updated, $failed failed (re-run: manifest topics fleet -y)"
        elif [[ "$pushed" -gt 0 ]]; then
            echo "🏷️  GitHub topics: $pushed repo(s) updated"
        fi
        return 0
    fi

    local verb="updated"
    [[ "$dry_run" == "true" ]] && verb="to update"
    echo "  Topics summary: $pushed $verb, $unchanged up to date, $skipped skipped, $failed failed"
    if [[ "$dry_run" == "true" && "$pushed" -gt 0 ]]; then
        echo "  To apply, run: $apply_hint"
    fi

    # Phase 2 roster: read-only, report-only (see module header). No GitHub
    # members enrolled means there is no family to roster against.
    if [[ ${#roster_owners[@]} -gt 0 ]]; then
        _fleet_topics_roster_report "$roster_known" "$roster_prefixes" "${roster_owners[@]}"
    fi

    return 0
}
