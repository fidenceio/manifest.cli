#!/bin/bash

# Manifest PR Module
# Pull request workflows for both solo developers and large teams.

_manifest_pr_require_gh_auth() {
    if ! command -v gh >/dev/null 2>&1; then
        show_dependency_error "GitHub CLI ('gh') is required for PR commands"
        return 1
    fi

    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI is not authenticated. Run: gh auth login"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        show_dependency_error "jq is required for PR commands"
        return 1
    fi

    return 0
}

_manifest_pr_repo_slug() {
    local repo_url
    repo_url=$(git remote get-url origin 2>/dev/null || echo "")

    # git@github.com:owner/repo.git
    if [[ "$repo_url" =~ ^git@[^:]+:([^/]+)/([^/]+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    # https://github.com/owner/repo(.git)
    if [[ "$repo_url" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

_manifest_pr_ensure_branch_pushed() {
    local branch="$1"
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        return 1
    fi

    if git rev-parse --abbrev-ref --symbolic-full-name "${branch}@{upstream}" >/dev/null 2>&1; then
        return 0
    fi

    echo "No upstream found for '$branch'; pushing to origin..."
    if ! git push -u origin "$branch"; then
        log_error "Failed to push branch '$branch' to origin"
        return 1
    fi
    return 0
}

_manifest_pr_ensure_branch_pushed_at_path() {
    local repo_path="$1"
    local branch="$2"
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        return 1
    fi

    if git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name "${branch}@{upstream}" >/dev/null 2>&1; then
        return 0
    fi

    echo "    ↗ pushing '$branch' to origin (set upstream)"
    if ! git -C "$repo_path" push -u origin "$branch" >/dev/null 2>&1; then
        echo "    ❌ failed to push branch '$branch'"
        return 1
    fi
    return 0
}

normalize_pr_selector() {
    local selector="$1"
    local extracted_number
    extracted_number=$(echo "$selector" | sed -n 's#.*\/pull\/\([0-9][0-9]*\).*#\1#p')
    if [ -n "$extracted_number" ]; then
        echo "$extracted_number"
        return 0
    fi

    echo "$selector"
}

_manifest_pr_resolve_target() {
    local explicit_selector="$1"
    local non_interactive="$2"

    local target=""
    local reason=""

    # 1) Explicit selector
    if [ -n "$explicit_selector" ]; then
        target="$(normalize_pr_selector "$explicit_selector")"
        reason="explicit --pr selector"
    fi

    # 2) Current branch PR
    if [ -z "$target" ]; then
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ -n "$current_branch" ] && [ "$current_branch" != "HEAD" ]; then
            if gh pr view "$current_branch" --json number >/dev/null 2>&1; then
                target="$current_branch"
                reason="current branch ($current_branch)"
            fi
        fi
    fi

    # 3) Single authored open PR
    if [ -z "$target" ]; then
        local authored_json
        authored_json=$(gh pr list --author "@me" --state open --limit 30 --json number,title,headRefName,url 2>/dev/null || echo "[]")
        local authored_count
        authored_count=$(echo "$authored_json" | jq 'length' 2>/dev/null || echo "0")

        if [ "$authored_count" -eq 1 ]; then
            target=$(echo "$authored_json" | jq -r '.[0].number')
            reason="single open PR authored by current user"
        elif [ "$authored_count" -gt 1 ]; then
            if [ "$non_interactive" = "true" ] || [ ! -t 0 ]; then
                log_error "Multiple open PRs authored by current user; use --pr to disambiguate"
                echo "$authored_json" | jq -r '.[] | "  - #\(.number) \(.title) [\(.headRefName)] \(.url)"'
                return 1
            fi

            echo "Multiple open PRs authored by current user:"
            local i=1
            local options_count="$authored_count"
            while [ "$i" -le "$options_count" ]; do
                local idx=$((i-1))
                local number title head_ref
                number=$(echo "$authored_json" | jq -r ".[$idx].number")
                title=$(echo "$authored_json" | jq -r ".[$idx].title")
                head_ref=$(echo "$authored_json" | jq -r ".[$idx].headRefName")
                echo "  $i) #$number $title [$head_ref]"
                i=$((i+1))
            done

            echo ""
            local selection=""
            read -r -p "Select PR (1-$options_count): " selection
            if ! validate_version_selection "$selection" "$options_count"; then
                show_validation_error "Invalid selection: $selection"
                return 1
            fi

            local selected_idx=$((selection-1))
            target=$(echo "$authored_json" | jq -r ".[$selected_idx].number")
            reason="interactive selection"
        fi
    fi

    if [ -z "$target" ]; then
        log_error "No pull request could be resolved. Use --pr <number|url|branch>."
        return 1
    fi

    echo "$target|$reason"
    return 0
}

_manifest_pr_policy_defaults() {
    local profile="${MANIFEST_CLI_PR_PROFILE:-solo}"
    case "$profile" in
        solo)
            echo "0|false|false|false|false"
            ;;
        team)
            echo "1|true|true|false|false"
            ;;
        regulated)
            echo "2|true|true|true|true"
            ;;
        *)
            echo "invalid"
            ;;
    esac
}

_manifest_pr_parse_bool() {
    local value
    value=$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')
    case "$value" in
        1|true|yes|on) echo "true" ;;
        0|false|no|off|"") echo "false" ;;
        *)
            log_error "Invalid boolean value: '$1' (use true/false)"
            return 1
            ;;
    esac
}

_manifest_pr_require_option_value() {
    local option_name="$1"
    local option_value="${2:-}"
    local usage="$3"
    if [ -z "$option_value" ] || [[ "$option_value" == --* ]]; then
        show_required_arg_error "$option_name value" "$usage"
        return 1
    fi
    return 0
}

_manifest_pr_effective_policy() {
    local profile="${MANIFEST_CLI_PR_PROFILE:-solo}"
    local defaults
    defaults=$(_manifest_pr_policy_defaults)

    if [ "$defaults" = "invalid" ]; then
        log_error "Invalid MANIFEST_CLI_PR_PROFILE: $profile (expected: solo|team|regulated)"
        return 1
    fi

    local def_min_reviewers def_require_checks def_require_codeowners def_require_docs def_require_security
    IFS='|' read -r def_min_reviewers def_require_checks def_require_codeowners def_require_docs def_require_security <<< "$defaults"

    local min_reviewers="${MANIFEST_CLI_PR_MIN_REVIEWERS:-$def_min_reviewers}"
    local require_checks_raw="${MANIFEST_CLI_PR_REQUIRE_CHECKS:-$def_require_checks}"
    local require_codeowners_raw="${MANIFEST_CLI_PR_REQUIRE_CODEOWNERS:-$def_require_codeowners}"
    local require_docs_raw="${MANIFEST_CLI_PR_REQUIRE_DOCS:-$def_require_docs}"
    local require_security_raw="${MANIFEST_CLI_PR_REQUIRE_SECURITY_CHECKS:-$def_require_security}"
    local enforce_ready_raw="${MANIFEST_CLI_PR_ENFORCE_READY:-true}"

    if ! [[ "$min_reviewers" =~ ^[0-9]+$ ]]; then
        log_error "MANIFEST_CLI_PR_MIN_REVIEWERS must be a non-negative integer"
        return 1
    fi

    local require_checks require_codeowners require_docs require_security enforce_ready
    require_checks=$(_manifest_pr_parse_bool "$require_checks_raw") || return 1
    require_codeowners=$(_manifest_pr_parse_bool "$require_codeowners_raw") || return 1
    require_docs=$(_manifest_pr_parse_bool "$require_docs_raw") || return 1
    require_security=$(_manifest_pr_parse_bool "$require_security_raw") || return 1
    enforce_ready=$(_manifest_pr_parse_bool "$enforce_ready_raw") || return 1

    echo "$profile|$min_reviewers|$require_checks|$require_codeowners|$require_docs|$require_security|$enforce_ready"
}

manifest_pr_policy_show() {
    local policy
    policy=$(_manifest_pr_effective_policy) || return 1
    local profile min_reviewers require_checks require_codeowners require_docs require_security enforce_ready
    IFS='|' read -r profile min_reviewers require_checks require_codeowners require_docs require_security enforce_ready <<< "$policy"

    echo "Manifest PR Policy (effective)"
    echo "=============================="
    echo "Profile:              $profile"
    echo "Min reviewers:        $min_reviewers"
    echo "Require checks:       $require_checks"
    echo "Require CODEOWNERS:   $require_codeowners"
    echo "Require docs gate:    $require_docs"
    echo "Require security gate:$require_security"
    echo "Enforce ready gate:   $enforce_ready"
}

manifest_pr_policy_validate() {
    _manifest_pr_effective_policy >/dev/null || return 1
    echo "✅ PR policy is valid"
}

manifest_pr_status() {
    local pr_selector=""
    local non_interactive=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr|-p)
                _manifest_pr_require_option_value "--pr" "${2:-}" "manifest pr status --pr <number|url|branch>" || return 1
                pr_selector="$2"
                shift 2
                ;;
            --non-interactive)
                non_interactive=true
                shift
                ;;
            --help|-h)
                echo "Usage: manifest pr status [--pr <number|url|branch>] [--non-interactive]"
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest pr status': $1"
                return 1
                ;;
        esac
    done

    _manifest_pr_require_gh_auth || return 1

    local resolved
    resolved=$(_manifest_pr_resolve_target "$pr_selector" "$non_interactive") || return 1
    local target="${resolved%%|*}"
    local reason="${resolved#*|}"

    local pr_json
    if ! pr_json=$(gh pr view "$target" --json number,title,state,isDraft,reviewDecision,mergeable,headRefName,baseRefName,url,author 2>/dev/null); then
        log_error "Failed to fetch PR details for selector: $target"
        return 1
    fi

    echo "🔎 Pull Request Status"
    echo "======================"
    echo "Resolved by: $reason"
    echo "PR:          #$(echo "$pr_json" | jq -r '.number')"
    echo "Title:       $(echo "$pr_json" | jq -r '.title')"
    echo "Author:      $(echo "$pr_json" | jq -r '.author.login // "unknown"')"
    echo "State:       $(echo "$pr_json" | jq -r '.state')"
    echo "Draft:       $(echo "$pr_json" | jq -r '.isDraft')"
    echo "Review:      $(echo "$pr_json" | jq -r '.reviewDecision // "UNSPECIFIED"')"
    echo "Mergeable:   $(echo "$pr_json" | jq -r '.mergeable // "UNKNOWN"')"
    echo "Branch:      $(echo "$pr_json" | jq -r '.headRefName') -> $(echo "$pr_json" | jq -r '.baseRefName')"
    echo "URL:         $(echo "$pr_json" | jq -r '.url')"
}

manifest_pr_create() {
    local title=""
    local body=""
    local base="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    local head=""
    local draft=false
    local fill=true
    local non_interactive=false
    local reviewers=()
    local labels=()
    local assignees=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)
                _manifest_pr_require_option_value "--title" "${2:-}" "manifest pr create --title <text>" || return 1
                title="$2"; shift 2 ;;
            --body)
                _manifest_pr_require_option_value "--body" "${2:-}" "manifest pr create --body <text>" || return 1
                body="$2"; shift 2 ;;
            --base)
                _manifest_pr_require_option_value "--base" "${2:-}" "manifest pr create --base <branch>" || return 1
                base="$2"; shift 2 ;;
            --head)
                _manifest_pr_require_option_value "--head" "${2:-}" "manifest pr create --head <branch>" || return 1
                head="$2"; shift 2 ;;
            --draft) draft=true; shift ;;
            --no-fill) fill=false; shift ;;
            --reviewer)
                _manifest_pr_require_option_value "--reviewer" "${2:-}" "manifest pr create --reviewer <user>" || return 1
                reviewers+=("$2"); shift 2 ;;
            --label)
                _manifest_pr_require_option_value "--label" "${2:-}" "manifest pr create --label <label>" || return 1
                labels+=("$2"); shift 2 ;;
            --assignee)
                _manifest_pr_require_option_value "--assignee" "${2:-}" "manifest pr create --assignee <user>" || return 1
                assignees+=("$2"); shift 2 ;;
            --non-interactive) non_interactive=true; shift ;;
            --help|-h)
                echo "Usage: manifest pr create [--title <t>] [--body <b>] [--base <branch>] [--head <branch>] [--draft]"
                echo "                          [--reviewer <user>] [--label <label>] [--assignee <user>] [--no-fill]"
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest pr create': $1"
                return 1
                ;;
        esac
    done

    _manifest_pr_require_gh_auth || return 1

    if [ -z "$head" ]; then
        head=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi

    if [ -z "$head" ] || [ "$head" = "HEAD" ]; then
        log_error "Could not determine current branch for PR creation"
        return 1
    fi

    if [ "$head" = "$base" ]; then
        log_error "Head branch and base branch cannot be the same ($head)"
        return 1
    fi

    _manifest_pr_ensure_branch_pushed "$head" || return 1

    # Avoid duplicate open PRs for same head branch.
    local existing_pr_json
    existing_pr_json=$(gh pr list --state open --head "$head" --limit 1 --json number,url,title 2>/dev/null || echo "[]")
    if [ "$(echo "$existing_pr_json" | jq 'length')" -gt 0 ]; then
        echo "✅ Open PR already exists for branch '$head':"
        echo "   #$(echo "$existing_pr_json" | jq -r '.[0].number') $(echo "$existing_pr_json" | jq -r '.[0].title')"
        echo "   $(echo "$existing_pr_json" | jq -r '.[0].url')"
        return 0
    fi

    local cmd=(gh pr create --base "$base" --head "$head")
    if [ "$draft" = "true" ]; then
        cmd+=(--draft)
    fi
    if [ -n "$title" ]; then
        cmd+=(--title "$title")
    fi
    if [ -n "$body" ]; then
        cmd+=(--body "$body")
    fi
    if [ "$fill" = "true" ] && [ -z "$title" ] && [ -z "$body" ]; then
        cmd+=(--fill)
    fi

    local pr_url
    if ! pr_url=$("${cmd[@]}"); then
        log_error "Failed to create pull request"
        return 1
    fi

    # Optional post-create edits
    if [ ${#reviewers[@]} -gt 0 ] || [ ${#labels[@]} -gt 0 ] || [ ${#assignees[@]} -gt 0 ]; then
        local edit_cmd=(gh pr edit "$pr_url")
        local r
        for r in "${reviewers[@]}"; do
            edit_cmd+=(--add-reviewer "$r")
        done
        local l
        for l in "${labels[@]}"; do
            edit_cmd+=(--add-label "$l")
        done
        local a
        for a in "${assignees[@]}"; do
            edit_cmd+=(--add-assignee "$a")
        done
        "${edit_cmd[@]}" >/dev/null 2>&1 || log_warning "PR created, but failed to apply some labels/reviewers/assignees"
    fi

    echo "✅ Pull request created:"
    echo "   $pr_url"

    # In non-interactive team flows, immediately show status snapshot.
    if [ "$non_interactive" = "true" ]; then
        manifest_pr_status --pr "$pr_url" --non-interactive
    fi
}

_manifest_pr_is_protected_head_branch() {
    local branch="$1"
    case "$branch" in
        main|master|release/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

manifest_pr_interactive() {
    local title=""
    local body=""
    local base="${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}"
    local head=""
    local draft=false
    local fill=true
    local reviewers=()
    local labels=()
    local assignees=()
    local run_sync="ask"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)
                _manifest_pr_require_option_value "--title" "${2:-}" "manifest pr --title <text>" || return 1
                title="$2"; shift 2 ;;
            --body)
                _manifest_pr_require_option_value "--body" "${2:-}" "manifest pr --body <text>" || return 1
                body="$2"; shift 2 ;;
            --base)
                _manifest_pr_require_option_value "--base" "${2:-}" "manifest pr --base <branch>" || return 1
                base="$2"; shift 2 ;;
            --head)
                _manifest_pr_require_option_value "--head" "${2:-}" "manifest pr --head <branch>" || return 1
                head="$2"; shift 2 ;;
            --draft) draft=true; shift ;;
            --no-fill) fill=false; shift ;;
            --reviewer)
                _manifest_pr_require_option_value "--reviewer" "${2:-}" "manifest pr --reviewer <user>" || return 1
                reviewers+=("$2"); shift 2 ;;
            --label)
                _manifest_pr_require_option_value "--label" "${2:-}" "manifest pr --label <label>" || return 1
                labels+=("$2"); shift 2 ;;
            --assignee)
                _manifest_pr_require_option_value "--assignee" "${2:-}" "manifest pr --assignee <user>" || return 1
                assignees+=("$2"); shift 2 ;;
            --sync) run_sync="true"; shift ;;
            --no-sync) run_sync="false"; shift ;;
            --help|-h)
                echo "Usage: manifest pr [interactive options]"
                echo "       manifest pr create|update|status|ready|checks|queue|policy ..."
                echo ""
                echo "Interactive options:"
                echo "  --base <branch>            Prefill target base branch (default: main)"
                echo "  --head <branch>            Prefill source branch (default: current)"
                echo "  --title <text>             Prefill PR title"
                echo "  --body <text>              Prefill PR body"
                echo "  --draft                    Start with draft PR selected"
                echo "  --no-fill                  Disable auto-fill when title/body omitted"
                echo "  --reviewer <user>          Add reviewer (repeatable)"
                echo "  --label <label>            Add label (repeatable)"
                echo "  --assignee <user>          Add assignee (repeatable)"
                echo "  --sync                     Force safe sync before PR prep (fetch only)"
                echo "  --no-sync                  Skip safe sync before PR prep"
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest pr' interactive mode: $1"
                return 1
                ;;
        esac
    done

    if [ ! -t 0 ]; then
        log_error "'manifest pr' interactive mode requires a TTY"
        echo "Use 'manifest pr create ...' in non-interactive contexts."
        return 1
    fi

    _manifest_pr_require_gh_auth || return 1

    if [ -z "$head" ]; then
        head=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi
    if [ -z "$head" ] || [ "$head" = "HEAD" ]; then
        log_error "Could not determine current branch for interactive PR creation"
        return 1
    fi

    echo "🔀 Manifest PR Wizard"
    echo "====================="
    echo "Detected source branch: $head"
    echo "Detected base branch:   $base"
    echo ""

    if [ "$run_sync" = "ask" ]; then
        local sync_reply=""
        read -r -p "Run safe sync first (fetch remotes/branches/tags)? [Y/n/q]: " sync_reply
        if [ "$sync_reply" = "q" ] || [ "$sync_reply" = "Q" ]; then
            echo "PR creation cancelled."
            return 0
        elif [ -z "$sync_reply" ] || [[ "$sync_reply" =~ ^[Yy]$ ]]; then
            run_sync="true"
        else
            run_sync="false"
        fi
    fi

    if [ "$run_sync" = "true" ]; then
        echo "🔄 Running safe sync..."
        if ! git fetch --all --prune --tags >/dev/null 2>&1; then
            log_warning "Safe sync fetch failed; continuing with local state."
        fi
    fi

    local input=""
    local local_branches=()
    local local_branch_list=""
    local remote_branches=()
    local remote_branch_list=""
    local_branch_list=$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null || true)
    if [ -n "$local_branch_list" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && local_branches+=("$line")
        done <<< "$local_branch_list"
    fi
    remote_branch_list=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null | sed 's#^origin/##' | rg -v '^HEAD$' || true)
    if [ -n "$remote_branch_list" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && remote_branches+=("$line")
        done <<< "$remote_branch_list"
    fi

    local head_options_all=("$head")
    local hb
    for hb in "${local_branches[@]}"; do
        if [ "$hb" != "$head" ]; then
            local exists=false
            local existing
            for existing in "${head_options_all[@]}"; do
                if [ "$existing" = "$hb" ]; then
                    exists=true
                    break
                fi
            done
            [ "$exists" = "false" ] && head_options_all+=("$hb")
        fi
    done
    for hb in "${remote_branches[@]}"; do
        if [ "$hb" != "$head" ]; then
            local exists=false
            local existing
            for existing in "${head_options_all[@]}"; do
                if [ "$existing" = "$hb" ]; then
                    exists=true
                    break
                fi
            done
            [ "$exists" = "false" ] && head_options_all+=("$hb")
        fi
    done

    local head_options=()
    for hb in "${head_options_all[@]}"; do
        if ! _manifest_pr_is_protected_head_branch "$hb"; then
            head_options+=("$hb")
        fi
    done
    if [ ${#head_options[@]} -eq 0 ]; then
        head_options=("${head_options_all[@]}")
    fi

    echo ""
    echo "Select source (head) branch:"
    local show_all_heads=false
    while true; do
        local active_head_options=("${head_options[@]}")
        if [ "$show_all_heads" = "true" ]; then
            active_head_options=("${head_options_all[@]}")
        fi

        local idx=1
        local max_options=15
        local total_options="${#active_head_options[@]}"
        local visible_options="$total_options"
        if [ "$visible_options" -gt "$max_options" ]; then
            visible_options="$max_options"
        fi
        while [ "$idx" -le "$visible_options" ]; do
            echo "  $idx) ${active_head_options[$((idx-1))]}"
            idx=$((idx+1))
        done
        if [ "$total_options" -gt "$max_options" ]; then
            echo "  ... plus $((total_options - max_options)) more branch(es)"
        fi
        if [ "$show_all_heads" != "true" ]; then
            echo "  a) show protected/all branches"
        fi
        echo "  c) custom branch name"
        echo "  q) cancel"
        read -r -p "Choose head [1]: " input
        if [ "$input" = "q" ] || [ "$input" = "Q" ]; then
            echo "PR creation cancelled."
            return 0
        elif [ "$input" = "a" ] || [ "$input" = "A" ]; then
            show_all_heads=true
            continue
        elif [ -z "$input" ]; then
            head="${active_head_options[0]}"
            break
        elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "$visible_options" ]; then
            head="${active_head_options[$((input-1))]}"
            break
        elif [ "$input" = "c" ] || [ "$input" = "C" ]; then
            read -r -p "Enter head branch (or q to cancel): " input
            if [ "$input" = "q" ] || [ "$input" = "Q" ]; then
                echo "PR creation cancelled."
                return 0
            fi
            if [ -n "$input" ]; then
                head="$input"
                break
            fi
        else
            # Allow direct branch name entry for power users.
            head="$input"
            break
        fi
    done

    local branch_options=("$base")
    local rb
    for rb in "${remote_branches[@]}"; do
        if [ "$rb" != "$base" ]; then
            branch_options+=("$rb")
        fi
    done

    echo ""
    echo "Select base branch:"
    local idx=1
    local max_options=15
    local total_options="${#branch_options[@]}"
    local visible_options="$total_options"
    if [ "$visible_options" -gt "$max_options" ]; then
        visible_options="$max_options"
    fi
    while [ "$idx" -le "$visible_options" ]; do
        echo "  $idx) ${branch_options[$((idx-1))]}"
        idx=$((idx+1))
    done
    if [ "$total_options" -gt "$max_options" ]; then
        echo "  ... plus $((total_options - max_options)) more branch(es)"
    fi
    echo "  c) custom branch name"
    echo "  q) cancel"
    read -r -p "Choose base [1]: " input
    if [ "$input" = "q" ] || [ "$input" = "Q" ]; then
        echo "PR creation cancelled."
        return 0
    elif [ -z "$input" ]; then
        base="${branch_options[0]}"
    elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "$visible_options" ]; then
        base="${branch_options[$((input-1))]}"
    elif [ "$input" = "c" ] || [ "$input" = "C" ]; then
        read -r -p "Enter base branch (or q to cancel): " input
        if [ "$input" = "q" ] || [ "$input" = "Q" ]; then
            echo "PR creation cancelled."
            return 0
        fi
        if [ -n "$input" ]; then
            base="$input"
        fi
    else
        # Allow direct branch name entry for power users.
        base="$input"
    fi

    local existing_pr_json
    existing_pr_json=$(gh pr list --state open --head "$head" --limit 1 --json number,url,title 2>/dev/null || echo "[]")
    if [ "$(echo "$existing_pr_json" | jq 'length')" -gt 0 ]; then
        echo "✅ Open PR already exists for '$head':"
        echo "   #$(echo "$existing_pr_json" | jq -r '.[0].number') $(echo "$existing_pr_json" | jq -r '.[0].title')"
        echo "   $(echo "$existing_pr_json" | jq -r '.[0].url')"
        return 0
    fi

    if [ "$head" = "$base" ]; then
        log_error "Head branch and base branch cannot be the same ($head)"
        return 1
    fi

    local default_title=""
    default_title=$(git log -1 --pretty=%s 2>/dev/null || echo "")
    if [ -z "$title" ] && [ -n "$default_title" ]; then
        read -r -p "PR title [$default_title]: " input
        if [ -n "$input" ]; then
            title="$input"
        else
            title="$default_title"
        fi
    fi

    if [ -z "$body" ]; then
        read -r -p "Add PR body now? [y/N]: " input
        if [[ "$input" =~ ^[Yy]$ ]]; then
            read -r -p "PR body: " body
        fi
    fi

    if [ "$draft" = "false" ]; then
        read -r -p "Create as draft? [y/N]: " input
        if [[ "$input" =~ ^[Yy]$ ]]; then
            draft=true
        fi
    fi

    local reviewers_csv=""
    local labels_csv=""
    local assignees_csv=""
    if [ ${#reviewers[@]} -eq 0 ]; then
        read -r -p "Reviewers (comma-separated, optional): " reviewers_csv
        if [ -n "$reviewers_csv" ]; then
            local item
            IFS=',' read -r -a _reviewers_split <<< "$reviewers_csv"
            for item in "${_reviewers_split[@]}"; do
                item="$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                [ -n "$item" ] && reviewers+=("$item")
            done
        fi
    fi
    if [ ${#labels[@]} -eq 0 ]; then
        read -r -p "Labels (comma-separated, optional): " labels_csv
        if [ -n "$labels_csv" ]; then
            local item
            IFS=',' read -r -a _labels_split <<< "$labels_csv"
            for item in "${_labels_split[@]}"; do
                item="$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                [ -n "$item" ] && labels+=("$item")
            done
        fi
    fi
    if [ ${#assignees[@]} -eq 0 ]; then
        read -r -p "Assignees (comma-separated, optional): " assignees_csv
        if [ -n "$assignees_csv" ]; then
            local item
            IFS=',' read -r -a _assignees_split <<< "$assignees_csv"
            for item in "${_assignees_split[@]}"; do
                item="$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                [ -n "$item" ] && assignees+=("$item")
            done
        fi
    fi

    echo ""
    echo "Plan:"
    echo "  head:  $head"
    echo "  base:  $base"
    echo "  draft: $draft"
    if [ -n "$title" ]; then
        echo "  title: $title"
    fi
    read -r -p "Proceed with these parameters? [y/N/q]: " input
    if [ "$input" = "q" ] || [ "$input" = "Q" ] || [ -z "$input" ] || [[ ! "$input" =~ ^[Yy]$ ]]; then
        echo "PR creation cancelled."
        return 0
    fi

    echo "Final confirmation required before any write actions."
    read -r -p "Type CREATE to push/create PR, or anything else to cancel: " input
    if [ "$input" != "CREATE" ]; then
        echo "PR creation cancelled."
        return 0
    fi

    local create_args=(--head "$head" --base "$base")
    [ "$draft" = "true" ] && create_args+=("--draft")
    [ "$fill" = "false" ] && create_args+=("--no-fill")
    [ -n "$title" ] && create_args+=("--title" "$title")
    [ -n "$body" ] && create_args+=("--body" "$body")

    local v
    for v in "${reviewers[@]}"; do create_args+=("--reviewer" "$v"); done
    for v in "${labels[@]}"; do create_args+=("--label" "$v"); done
    for v in "${assignees[@]}"; do create_args+=("--assignee" "$v"); done

    manifest_pr_create "${create_args[@]}"
}

manifest_pr_update() {
    local pr_selector=""
    local non_interactive=false
    local title=""
    local body=""
    local base=""
    local add_labels=()
    local remove_labels=()
    local add_reviewers=()
    local remove_reviewers=()
    local add_assignees=()
    local remove_assignees=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr|-p)
                _manifest_pr_require_option_value "--pr" "${2:-}" "manifest pr update --pr <number|url|branch>" || return 1
                pr_selector="$2"; shift 2 ;;
            --title)
                _manifest_pr_require_option_value "--title" "${2:-}" "manifest pr update --title <text>" || return 1
                title="$2"; shift 2 ;;
            --body)
                _manifest_pr_require_option_value "--body" "${2:-}" "manifest pr update --body <text>" || return 1
                body="$2"; shift 2 ;;
            --base)
                _manifest_pr_require_option_value "--base" "${2:-}" "manifest pr update --base <branch>" || return 1
                base="$2"; shift 2 ;;
            --add-label)
                _manifest_pr_require_option_value "--add-label" "${2:-}" "manifest pr update --add-label <label>" || return 1
                add_labels+=("$2"); shift 2 ;;
            --remove-label)
                _manifest_pr_require_option_value "--remove-label" "${2:-}" "manifest pr update --remove-label <label>" || return 1
                remove_labels+=("$2"); shift 2 ;;
            --add-reviewer)
                _manifest_pr_require_option_value "--add-reviewer" "${2:-}" "manifest pr update --add-reviewer <user>" || return 1
                add_reviewers+=("$2"); shift 2 ;;
            --remove-reviewer)
                _manifest_pr_require_option_value "--remove-reviewer" "${2:-}" "manifest pr update --remove-reviewer <user>" || return 1
                remove_reviewers+=("$2"); shift 2 ;;
            --add-assignee)
                _manifest_pr_require_option_value "--add-assignee" "${2:-}" "manifest pr update --add-assignee <user>" || return 1
                add_assignees+=("$2"); shift 2 ;;
            --remove-assignee)
                _manifest_pr_require_option_value "--remove-assignee" "${2:-}" "manifest pr update --remove-assignee <user>" || return 1
                remove_assignees+=("$2"); shift 2 ;;
            --non-interactive) non_interactive=true; shift ;;
            --help|-h)
                echo "Usage: manifest pr update [--pr <number|url|branch>] [edit options]"
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest pr update': $1"
                return 1
                ;;
        esac
    done

    _manifest_pr_require_gh_auth || return 1

    local resolved
    resolved=$(_manifest_pr_resolve_target "$pr_selector" "$non_interactive") || return 1
    local target="${resolved%%|*}"

    local cmd=(gh pr edit "$target")
    [ -n "$title" ] && cmd+=(--title "$title")
    [ -n "$body" ] && cmd+=(--body "$body")
    [ -n "$base" ] && cmd+=(--base "$base")

    local v
    for v in "${add_labels[@]}"; do cmd+=(--add-label "$v"); done
    for v in "${remove_labels[@]}"; do cmd+=(--remove-label "$v"); done
    for v in "${add_reviewers[@]}"; do cmd+=(--add-reviewer "$v"); done
    for v in "${remove_reviewers[@]}"; do cmd+=(--remove-reviewer "$v"); done
    for v in "${add_assignees[@]}"; do cmd+=(--add-assignee "$v"); done
    for v in "${remove_assignees[@]}"; do cmd+=(--remove-assignee "$v"); done

    "${cmd[@]}" || {
        log_error "Failed to update pull request"
        return 1
    }

    echo "✅ Pull request updated"
    manifest_pr_status --pr "$target" --non-interactive
}

manifest_pr_ready() {
    local pr_selector=""
    local non_interactive=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr|-p)
                _manifest_pr_require_option_value "--pr" "${2:-}" "manifest pr ready --pr <number|url|branch>" || return 1
                pr_selector="$2"; shift 2 ;;
            --non-interactive) non_interactive=true; shift ;;
            --help|-h)
                echo "Usage: manifest pr ready [--pr <number|url|branch>] [--non-interactive]"
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest pr ready': $1"
                return 1
                ;;
        esac
    done

    _manifest_pr_require_gh_auth || return 1

    local policy
    policy=$(_manifest_pr_effective_policy) || return 1
    local _policy_profile min_reviewers require_checks require_codeowners require_docs require_security enforce_ready
    IFS='|' read -r _policy_profile min_reviewers require_checks require_codeowners require_docs require_security enforce_ready <<< "$policy"

    local resolved
    resolved=$(_manifest_pr_resolve_target "$pr_selector" "$non_interactive") || return 1
    local target="${resolved%%|*}"
    local reason="${resolved#*|}"

    local pr_json
    if ! pr_json=$(gh pr view "$target" --json number,title,state,isDraft,reviewDecision,mergeStateStatus,latestReviews,url 2>/dev/null); then
        log_error "Failed to fetch PR details for readiness"
        return 1
    fi

    local number state is_draft review_decision merge_state url
    number=$(echo "$pr_json" | jq -r '.number')
    state=$(echo "$pr_json" | jq -r '.state')
    is_draft=$(echo "$pr_json" | jq -r '.isDraft')
    review_decision=$(echo "$pr_json" | jq -r '.reviewDecision // "REVIEW_REQUIRED"')
    merge_state=$(echo "$pr_json" | jq -r '.mergeStateStatus // "UNKNOWN"')
    url=$(echo "$pr_json" | jq -r '.url')

    local approved_count
    approved_count=$(echo "$pr_json" | jq '[.latestReviews[]? | select(.state=="APPROVED")] | length' 2>/dev/null || echo "0")

    local checks_status="unknown"
    if [ "$require_checks" = "true" ]; then
        # gh pr checks exit code:
        # 0 success, 1 pending, 2 failing/no checks
        if gh pr checks "$number" >/dev/null 2>&1; then
            checks_status="pass"
        else
            local checks_exit=$?
            if [ "$checks_exit" -eq 1 ]; then
                checks_status="pending"
            else
                checks_status="fail"
            fi
        fi
    else
        checks_status="not-required"
    fi

    local codeowners_status="not-required"
    local docs_gate_status="not-required"
    local security_gate_status="not-required"

    if [ "$require_codeowners" = "true" ]; then
        if [ -f ".github/CODEOWNERS" ] || [ -f "CODEOWNERS" ] || [ -f "docs/CODEOWNERS" ]; then
            codeowners_status="configured"
        else
            codeowners_status="missing"
        fi
    fi

    if [ "$require_docs" = "true" ]; then
        if command -v git >/dev/null 2>&1 && git diff --name-only "origin/${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}...HEAD" 2>/dev/null | rg -q '^docs/|README\.md|CHANGELOG'; then
            docs_gate_status="changed"
        else
            docs_gate_status="missing-doc-changes"
        fi
    fi

    if [ "$require_security" = "true" ]; then
        # lightweight gate: require security command availability.
        if declare -F manifest_security >/dev/null 2>&1; then
            security_gate_status="configured"
        else
            security_gate_status="missing"
        fi
    fi

    local readiness_state="needs-review"
    local blockers=()

    [ "$state" != "OPEN" ] && blockers+=("PR is not open (state=$state)")
    [ "$is_draft" = "true" ] && blockers+=("PR is draft")
    [ "$approved_count" -lt "$min_reviewers" ] && blockers+=("Approvals $approved_count/$min_reviewers")
    [ "$review_decision" = "CHANGES_REQUESTED" ] && blockers+=("Changes requested by reviewers")
    [ "$checks_status" = "fail" ] && blockers+=("Required checks failing")
    [ "$codeowners_status" = "missing" ] && blockers+=("CODEOWNERS required but not found")
    [ "$docs_gate_status" = "missing-doc-changes" ] && blockers+=("Docs gate enabled but no docs/README/CHANGELOG changes")
    [ "$security_gate_status" = "missing" ] && blockers+=("Security gate enabled but security module unavailable")

    if [ ${#blockers[@]} -gt 0 ]; then
        readiness_state="blocked"
    else
        if [ "$checks_status" = "pending" ] || [ "$merge_state" = "UNKNOWN" ]; then
            readiness_state="merge-queued"
        elif [ "$review_decision" = "REVIEW_REQUIRED" ]; then
            readiness_state="needs-review"
        else
            readiness_state="ready-to-merge"
        fi
    fi

    echo "🧭 PR Readiness"
    echo "==============="
    echo "Resolved by:        $reason"
    echo "PR:                 #$number"
    echo "Readiness:          $readiness_state"
    echo "Review decision:    $review_decision"
    echo "Approvals:          $approved_count/$min_reviewers"
    echo "Checks:             $checks_status"
    echo "CODEOWNERS gate:    $codeowners_status"
    echo "Docs gate:          $docs_gate_status"
    echo "Security gate:      $security_gate_status"
    echo "Merge state:        $merge_state"
    echo "URL:                $url"

    if [ ${#blockers[@]} -gt 0 ]; then
        echo ""
        echo "Blockers:"
        local b
        for b in "${blockers[@]}"; do
            echo "  - $b"
        done
        return 1
    fi

    return 0
}

manifest_pr_checks() {
    local pr_selector=""
    local watch=false
    local interval="${MANIFEST_CLI_PR_CHECKS_INTERVAL:-10}"
    local non_interactive=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr|-p)
                _manifest_pr_require_option_value "--pr" "${2:-}" "manifest pr checks --pr <number|url|branch>" || return 1
                pr_selector="$2"; shift 2 ;;
            --watch) watch=true; shift ;;
            --interval)
                _manifest_pr_require_option_value "--interval" "${2:-}" "manifest pr checks --interval <sec>" || return 1
                interval="$2"; shift 2 ;;
            --non-interactive) non_interactive=true; shift ;;
            --help|-h)
                echo "Usage: manifest pr checks [--pr <number|url|branch>] [--watch] [--interval <sec>]"
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest pr checks': $1"
                return 1
                ;;
        esac
    done

    _manifest_pr_require_gh_auth || return 1
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        show_validation_error "--interval must be a non-negative integer"
        return 1
    fi
    local resolved
    resolved=$(_manifest_pr_resolve_target "$pr_selector" "$non_interactive") || return 1
    local target="${resolved%%|*}"

    if [ "$watch" = "true" ]; then
        echo "Watching checks for PR '$target' (interval=${interval}s, Ctrl+C to stop)..."
        while true; do
            echo ""
            date "+%Y-%m-%d %H:%M:%S"
            if gh pr checks "$target"; then
                echo "✅ All checks passing"
            else
                local checks_exit=$?
                if [ "$checks_exit" -eq 1 ]; then
                    echo "⏳ Checks pending"
                else
                    echo "❌ Some checks failing (or unavailable)"
                fi
            fi
            sleep "$interval"
        done
    else
        if gh pr checks "$target"; then
            echo "✅ All checks passing"
        else
            local checks_exit=$?
            if [ "$checks_exit" -eq 1 ]; then
                echo "⏳ Checks pending"
            else
                echo "❌ Some checks failing (or unavailable)"
            fi
            return "$checks_exit"
        fi
    fi
}

manifest_pr_queue() {
    local pr_selector=""
    local method="squash"
    local non_interactive=false
    local delete_branch=true
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr|-p)
                _manifest_pr_require_option_value "--pr" "${2:-}" "manifest pr queue --pr <number|url|branch>" || return 1
                pr_selector="$2"; shift 2 ;;
            --method)
                _manifest_pr_require_option_value "--method" "${2:-}" "manifest pr queue --method <merge|squash|rebase>" || return 1
                method="$2"; shift 2 ;;
            --no-delete-branch) delete_branch=false; shift ;;
            --force) force=true; shift ;;
            --non-interactive) non_interactive=true; shift ;;
            --help|-h)
                echo "Usage: manifest pr queue [--pr <number|url|branch>] [--method <merge|squash|rebase>] [--force]"
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest pr queue': $1"
                return 1
                ;;
        esac
    done

    if [[ ! "$method" =~ ^(merge|squash|rebase)$ ]]; then
        show_validation_error "Invalid --method value: '$method' (expected merge|squash|rebase)"
        return 1
    fi

    _manifest_pr_require_gh_auth || return 1
    manifest_pr_policy_validate || return 1

    local resolved
    resolved=$(_manifest_pr_resolve_target "$pr_selector" "$non_interactive") || return 1
    local target="${resolved%%|*}"

    # Enforce readiness before queueing auto-merge unless force override is used.
    if [ "$force" != "true" ]; then
        if ! manifest_pr_ready --pr "$target" --non-interactive; then
            log_error "PR is not ready; refusing to queue auto-merge."
            log_error "Use --force to bypass readiness gate."
            return 1
        fi
    else
        if [ "$non_interactive" != "true" ] && [ -t 0 ]; then
            local force_confirmation=""
            echo "⚠️  --force bypasses readiness/policy guardrails for PR '$target'."
            read -r -p "Type FORCE to continue: " force_confirmation
            if [ "$force_confirmation" != "FORCE" ]; then
                log_error "Force queue cancelled."
                return 1
            fi
        fi
        log_warning "Bypassing readiness gate with --force"
    fi

    local cmd=(gh pr merge "$target" --auto)
    case "$method" in
        merge) cmd+=(--merge) ;;
        squash) cmd+=(--squash) ;;
        rebase) cmd+=(--rebase) ;;
    esac
    [ "$delete_branch" = "true" ] && cmd+=(--delete-branch)

    "${cmd[@]}" || {
        log_error "Failed to queue PR for auto-merge"
        return 1
    }

    echo "✅ PR queued for auto-merge"
}

manifest_ship() {
    local increment_type=""
    local interactive_prep=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major|revision)
                increment_type="$1"
                shift
                ;;
            -p) increment_type="patch"; shift ;;
            -m) increment_type="minor"; shift ;;
            -M) increment_type="major"; shift ;;
            -r) increment_type="revision"; shift ;;
            -i|--interactive)
                interactive_prep=true
                shift
                ;;
            -h|--help)
                echo "Usage: manifest ship <patch|minor|major|revision> [-i|--interactive]"
                echo ""
                echo "Options:"
                echo "  <patch|minor|major|revision>   Required release type subcommand"
                echo "  -p|-m|-M|-r                    Short form release type"
                echo "  -i|--interactive               Enable interactive prep prompts"
                echo ""
                echo "Flow:"
                echo "  ship -> prep workflow (sync, docs, version, commit, push)"
                echo "  PR operations are intentionally not part of ship."
                return 0
                ;;
            *)
                show_validation_error "Unknown option for 'manifest ship': $1"
                echo "Usage: manifest ship <patch|minor|major|revision> [-i|--interactive]"
                return 1
                ;;
        esac
    done

    if [ -z "$increment_type" ]; then
        log_error "ship requires a release type subcommand"
        echo "Usage: manifest ship <patch|minor|major|revision> [-i|--interactive]"
        echo "Release type options: patch, minor, major, revision"
        return 1
    fi

    echo "🚢 Starting ship workflow ($increment_type)..."

    if ! manifest_prep "$increment_type" "$interactive_prep"; then
        log_error "Prep step failed; aborting ship workflow."
        return 1
    fi

    echo "✅ Ship workflow complete (no PR actions)."
}

manifest_pr_help() {
    cat << 'EOF'
Manifest PR Commands
====================

  manifest pr [options]
    Launch interactive PR wizard (default). Detects branch info and can run safe sync.
    Options:
      --head <branch>
      --base <branch>
      --title <text>
      --body <text>
      --draft
      --no-fill
      --reviewer <user>          (repeatable)
      --label <label>            (repeatable)
      --assignee <user>          (repeatable)
      --sync | --no-sync         (--sync fetches remotes/branches/tags before prompts)

  manifest pr create [options]
    Create PR from current branch (or --head) to --base.
    Options:
      --title <text>
      --body <text>
      --base <branch>            (default: main)
      --head <branch>            (default: current branch)
      --draft
      --no-fill                  (default uses --fill when title/body omitted)
      --reviewer <user>          (repeatable)
      --label <label>            (repeatable)
      --assignee <user>          (repeatable)

  manifest pr update [options]
    Update an existing PR resolved by selector strategy.
    Options:
      --pr <number|url|branch>
      --title <text>
      --body <text>
      --base <branch>
      --add-label <label>        (repeatable)
      --remove-label <label>     (repeatable)
      --add-reviewer <user>      (repeatable)
      --remove-reviewer <user>   (repeatable)
      --add-assignee <user>      (repeatable)
      --remove-assignee <user>   (repeatable)

  manifest pr status [options]
    Show PR status.
    Options:
      --pr <number|url|branch>
      --non-interactive

  manifest pr ready [options]
    Evaluate readiness to merge based on policy profile + checks.
    Options:
      --pr <number|url|branch>
      --non-interactive

  manifest pr checks [options]
    Show CI checks for resolved PR.
    Options:
      --pr <number|url|branch>
      --watch
      --interval <sec>

  manifest pr queue [options]
    Preferred path: queue PR for policy-aware auto-merge after gates pass.
    Options:
      --pr <number|url|branch>
      --method <merge|squash|rebase>
      --force
      --no-delete-branch

  manifest pr policy show
  manifest pr policy validate
    Show/validate effective PR policy profile:
      MANIFEST_CLI_PR_PROFILE=solo|team|regulated
      MANIFEST_CLI_PR_ENFORCE_READY=true|false
EOF
}

# Fleet PR commands: coordinate create/status/merge across fleet services.
manifest_fleet_pr_dispatch() {
    local subcommand="$1"
    shift || true

    # Requires fleet mode and loaded config
    if ! _fleet_require_initialized "fleet pr $subcommand"; then
        return 1
    fi

    local method="squash"
    local any_failures=0

    case "$subcommand" in
        "help"|"-h"|"--help")
            cat << 'EOF'
Fleet PR Commands
=================

  manifest fleet pr [options]
    Preferred shorthand for: manifest fleet pr queue [options]
    Options:
      --method <merge|squash|rebase>
      --force
      --no-delete-branch

  manifest fleet pr create
  manifest fleet pr status
  manifest fleet pr checks
  manifest fleet pr ready
  manifest fleet pr queue [--method <merge|squash|rebase>] [--no-delete-branch] [--force]   # Preferred
EOF
            ;;
        "create")
            _manifest_pr_require_gh_auth || return 1
            local create_draft=false
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --draft) create_draft=true; shift ;;
                    *) shift ;;
                esac
            done
            echo "🚢 Fleet PR create"
            for service in $MANIFEST_FLEET_SERVICES; do
                local path
                path=$(get_fleet_service_property "$service" "path")
                if [ ! -d "$path/.git" ]; then
                    echo "  - $service: skipped (not a git repo)"
                    continue
                fi
                local branch
                branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
                    echo "  - $service: skipped (detached HEAD)"
                    continue
                fi
                local repo_slug
                repo_slug=$(_manifest_pr_repo_slug_from_path "$path")
                if [ -z "$repo_slug" ]; then
                    echo "  - $service: skipped (unable to parse origin repo slug)"
                    continue
                fi

                if ! _manifest_pr_ensure_branch_pushed_at_path "$path" "$branch"; then
                    any_failures=1
                    continue
                fi

                echo "  - $service: creating PR for branch '$branch'"
                local existing_json
                existing_json=$(gh -R "$repo_slug" pr list --state open --head "$branch" --limit 1 --json number,title,url 2>/dev/null || echo "[]")
                if [ "$(echo "$existing_json" | jq 'length')" -gt 0 ]; then
                    echo "    ✅ existing #$(echo "$existing_json" | jq -r '.[0].number') $(echo "$existing_json" | jq -r '.[0].url')"
                    continue
                fi

                local create_cmd=(gh -R "$repo_slug" pr create --head "$branch" --base "${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}" --fill)
                [ "$create_draft" = "true" ] && create_cmd+=(--draft)
                if ! "${create_cmd[@]}" >/dev/null 2>&1; then
                    echo "    ❌ create failed"
                    any_failures=1
                else
                    local created_json
                    created_json=$(gh -R "$repo_slug" pr list --state open --head "$branch" --limit 1 --json number,url 2>/dev/null || echo "[]")
                    if [ "$(echo "$created_json" | jq 'length')" -gt 0 ]; then
                        echo "    ✅ created #$(echo "$created_json" | jq -r '.[0].number') $(echo "$created_json" | jq -r '.[0].url')"
                    else
                        echo "    ✅ created"
                    fi
                fi
            done
            ;;
        "status")
            _manifest_pr_require_gh_auth || return 1
            echo "🚢 Fleet PR status"
            for service in $MANIFEST_FLEET_SERVICES; do
                local path
                path=$(get_fleet_service_property "$service" "path")
                if [ ! -d "$path/.git" ]; then
                    echo "  - $service: skipped (not a git repo)"
                    continue
                fi
                local branch
                branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                local repo_slug
                repo_slug=$(_manifest_pr_repo_slug_from_path "$path")
                if [ -z "$repo_slug" ]; then
                    echo "  - $service: skipped (unable to parse origin repo slug)"
                    continue
                fi

                local pr_json
                pr_json=$(gh -R "$repo_slug" pr list --state open --head "$branch" --limit 1 --json number,title,url 2>/dev/null || echo "[]")
                local pr_line
                pr_line=$(echo "$pr_json" | jq -r 'if length==0 then "none" else "#\(. [0].number) \(. [0].title) \(. [0].url)" end')
                echo "  - $service: $pr_line"
            done
            ;;
        "checks")
            _manifest_pr_require_gh_auth || return 1
            echo "🚢 Fleet PR checks"
            for service in $MANIFEST_FLEET_SERVICES; do
                local path
                path=$(get_fleet_service_property "$service" "path")
                if [ ! -d "$path/.git" ]; then
                    echo "  - $service: skipped (not a git repo)"
                    continue
                fi
                local branch
                branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                local repo_slug
                repo_slug=$(_manifest_pr_repo_slug_from_path "$path")
                if [ -z "$repo_slug" ]; then
                    echo "  - $service: skipped (unable to parse origin repo slug)"
                    continue
                fi
                local pr_json
                pr_json=$(gh -R "$repo_slug" pr list --state open --head "$branch" --limit 1 --json number 2>/dev/null || echo "[]")
                local pr_number
                pr_number=$(echo "$pr_json" | jq -r 'if length==0 then "" else .[0].number end')
                if [ -z "$pr_number" ]; then
                    echo "  - $service: no open PR"
                    continue
                fi
                if gh -R "$repo_slug" pr checks "$pr_number" >/dev/null 2>&1; then
                    echo "  - $service: ✅ checks passing (#$pr_number)"
                else
                    local checks_exit=$?
                    if [ "$checks_exit" -eq 1 ]; then
                        echo "  - $service: ⏳ checks pending (#$pr_number)"
                    else
                        echo "  - $service: ❌ checks failing/unavailable (#$pr_number)"
                        any_failures=1
                    fi
                fi
            done
            ;;
        "ready")
            _manifest_pr_require_gh_auth || return 1
            echo "🚢 Fleet PR ready"
            for service in $MANIFEST_FLEET_SERVICES; do
                local path
                path=$(get_fleet_service_property "$service" "path")
                if [ ! -d "$path/.git" ]; then
                    echo "  - $service: skipped (not a git repo)"
                    continue
                fi
                (
                    cd "$path" || exit 1
                    if manifest_pr_ready --non-interactive >/dev/null 2>&1; then
                        echo "  - $service: ✅ ready"
                    else
                        echo "  - $service: ❌ not ready"
                        exit 1
                    fi
                ) || any_failures=1
            done
            ;;
        "queue")
            _manifest_pr_require_gh_auth || return 1
            # optional flags
            local queue_no_delete=false
            local queue_force=false
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --method)
                        _manifest_pr_require_option_value "--method" "${2:-}" "manifest fleet pr queue --method <merge|squash|rebase>" || return 1
                        method="$2"; shift 2 ;;
                    --no-delete-branch) queue_no_delete=true; shift ;;
                    --force) queue_force=true; shift ;;
                    *) shift ;;
                esac
            done

            if [[ ! "$method" =~ ^(merge|squash|rebase)$ ]]; then
                log_error "Invalid --method value for fleet pr queue: '$method' (expected merge|squash|rebase)"
                return 1
            fi

            echo "🚢 Fleet PR queue"
            for service in $MANIFEST_FLEET_SERVICES; do
                local path
                path=$(get_fleet_service_property "$service" "path")
                if [ ! -d "$path/.git" ]; then
                    echo "  - $service: skipped (not a git repo)"
                    continue
                fi
                (
                    cd "$path" || exit 1
                    local queue_args=(--method "$method" --non-interactive)
                    [ "$queue_no_delete" = "true" ] && queue_args+=("--no-delete-branch")
                    [ "$queue_force" = "true" ] && queue_args+=("--force")
                    if manifest_pr_queue "${queue_args[@]}" >/dev/null 2>&1; then
                        echo "  - $service: ✅ queued"
                    else
                        echo "  - $service: ❌ queue failed"
                        exit 1
                    fi
                ) || any_failures=1
            done
            ;;
        *)
            log_error "Unknown fleet pr subcommand: $subcommand"
            return 1
            ;;
    esac

    if [ "$any_failures" -eq 1 ]; then
        return 1
    fi
    return 0
}

_manifest_pr_repo_slug_from_path() {
    local repo_path="$1"
    local repo_url
    repo_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || echo "")

    if [[ "$repo_url" =~ ^git@[^:]+:([^/]+)/([^/]+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "$repo_url" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    echo ""
    return 1
}

