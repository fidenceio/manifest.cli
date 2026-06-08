#!/bin/bash

# Documentation Review Module
# Performs a local documentation-impact review before creating commits.
# External MCP/API-backed engines can be wired through the provider command
# without changing the commit path.

if [[ -n "${_MANIFEST_CLI_DOC_REVIEW_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_DOC_REVIEW_LOADED=1

_manifest_doc_review_is_disabled() {
    case "$(printf '%s' "${MANIFEST_CLI_DOC_REVIEW:-true}" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || printf '%s' "${MANIFEST_CLI_DOC_REVIEW:-true}")" in
        0|false|no|off|disabled) return 0 ;;
        *) return 1 ;;
    esac
}

_manifest_doc_review_output_enabled() {
    local wanted="$1"
    local outputs="${MANIFEST_CLI_DOC_REVIEW_OUTPUTS:-commit_body,report,release_notes}"
    outputs="$(printf '%s' "$outputs" | tr '[:upper:]' '[:lower:]' | tr ' ' ',' | tr -s ',')"
    case ",$outputs," in
        *",all,"*|*",${wanted},"*) return 0 ;;
        *) return 1 ;;
    esac
}

_manifest_doc_review_state_dir() {
    local project_root="${1:-$PROJECT_ROOT}"
    local git_dir
    git_dir="$(git -C "$project_root" rev-parse --git-dir 2>/dev/null)" || return 1
    [[ "$git_dir" != /* ]] && git_dir="$project_root/$git_dir"
    mkdir -p "$git_dir/manifest-doc-review" || return 1
    printf '%s\n' "$git_dir/manifest-doc-review"
}

_manifest_doc_review_report_path() {
    local project_root="${1:-$PROJECT_ROOT}"
    local stamp="${2:-$(date -u +"%Y%m%dT%H%M%SZ")}"
    local report_dir="${MANIFEST_CLI_DOC_REVIEW_REPORT_DIR:-}"

    # Default (empty): write to the git state dir so reports never land in
    # the working tree. Set MANIFEST_CLI_DOC_REVIEW_REPORT_DIR (or
    # docs.review.report_dir in YAML) to a working-tree path to opt in to
    # committed reports.
    if [[ -z "$report_dir" ]]; then
        local state_dir
        state_dir="$(_manifest_doc_review_state_dir "$project_root")" || return 1
        printf '%s\n' "$state_dir/DOC_REVIEW_${stamp}.md"
        return 0
    fi

    mkdir -p "$project_root/$report_dir" || return 1
    printf '%s\n' "$project_root/$report_dir/DOC_REVIEW_${stamp}.md"
}

_manifest_doc_review_changed_files() {
    local project_root="${1:-$PROJECT_ROOT}"
    {
        git -C "$project_root" diff --name-only 2>/dev/null || true
        git -C "$project_root" diff --cached --name-only 2>/dev/null || true
        git -C "$project_root" ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
}

_manifest_doc_review_classify_file() {
    local file="$1"
    case "$file" in
        README.md|CHANGELOG.md|docs/*|completions/README.md|examples/*.md)
            printf '%s\n' "docs" ;;
        modules/core/manifest-core.sh|modules/core/manifest-ship.sh|modules/core/manifest-init.sh|modules/core/manifest-prep.sh|modules/core/manifest-refresh.sh)
            printf '%s\n' "command_surface" ;;
        modules/fleet/*|modules/pr/*|modules/docs/*|modules/git/*|modules/system/*|modules/cloud/*)
            printf '%s\n' "runtime" ;;
        completions/*)
            printf '%s\n' "completion" ;;
        modules/catalog/*)
            printf '%s\n' "configuration" ;;
        examples/*.yaml|examples/*.yml|modules/core/manifest-yaml.sh|modules/core/manifest-config.sh)
            printf '%s\n' "configuration" ;;
        modules/core/*.sh)
            printf '%s\n' "runtime" ;;
        tests/*)
            printf '%s\n' "tests" ;;
        *)
            printf '%s\n' "other" ;;
    esac
}

_manifest_doc_review_run_provider() {
    local report_file="$1"
    local project_root="$2"
    local provider="${MANIFEST_CLI_DOC_REVIEW_PROVIDER:-local}"
    local state_dir
    state_dir="$(_manifest_doc_review_state_dir "$project_root")" || return 1

    export MANIFEST_CLI_DOC_REVIEW_REPORT_FILE="$report_file"
    export MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT_FILE="$state_dir/provider-commit-subject"
    export MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY_FILE="$state_dir/provider-commit-body"
    export MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE_FILE="$state_dir/provider-release-note"
    rm -f "$MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT_FILE" "$MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY_FILE" "$MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE_FILE"

    case "$provider" in
        ""|local)
            return 0 ;;
        command)
            if [[ -z "${MANIFEST_CLI_DOC_REVIEW_COMMAND:-}" ]]; then
                echo "   ⚠️  Documentation review provider 'command' has no MANIFEST_CLI_DOC_REVIEW_COMMAND"
                return 1
            fi
            "$MANIFEST_CLI_DOC_REVIEW_COMMAND" "$report_file" "$project_root"
            return $? ;;
        *)
            echo "   ⚠️  Unknown documentation review provider: $provider"
            return 1 ;;
    esac
}

manifest_smart_documentation_review() {
    local commit_message="${1:-}"
    local project_root="${PROJECT_ROOT:-$(pwd)}"

    MANIFEST_CLI_DOC_REVIEW_REPORT_FILE=""
    MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY=""
    MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT=""
    MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE=""

    _manifest_doc_review_is_disabled && return 0
    git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    local changed_files
    changed_files="$(_manifest_doc_review_changed_files "$project_root")"
    [[ -n "$changed_files" ]] || return 0

    local changed_count docs_count command_count runtime_count completion_count config_count test_count other_count
    changed_count=0
    docs_count=0
    command_count=0
    runtime_count=0
    completion_count=0
    config_count=0
    test_count=0
    other_count=0

    local file class
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        changed_count=$((changed_count + 1))
        class="$(_manifest_doc_review_classify_file "$file")"
        case "$class" in
            docs) docs_count=$((docs_count + 1)) ;;
            command_surface) command_count=$((command_count + 1)) ;;
            runtime) runtime_count=$((runtime_count + 1)) ;;
            completion) completion_count=$((completion_count + 1)) ;;
            configuration) config_count=$((config_count + 1)) ;;
            tests) test_count=$((test_count + 1)) ;;
            *) other_count=$((other_count + 1)) ;;
        esac
    done <<< "$changed_files"

    local docs_needed=false
    if [[ "$command_count" -gt 0 || "$runtime_count" -gt 0 || "$completion_count" -gt 0 || "$config_count" -gt 0 ]]; then
        docs_needed=true
    fi

    local recommendation="Documentation impact appears low."
    if [[ "$docs_needed" == "true" && "$docs_count" -gt 0 ]]; then
        recommendation="Documentation impact detected; documentation changes are present."
    elif [[ "$docs_needed" == "true" ]]; then
        recommendation="Documentation impact detected; review docs before committing."
    fi

    local report_file state_dir latest_file generated_at filename_stamp release_note commit_body
    local commit_report_enabled=false commit_body_enabled=false
    _manifest_doc_review_output_enabled "report" && commit_report_enabled=true
    _manifest_doc_review_output_enabled "commit_body" && commit_body_enabled=true
    filename_stamp="$(date -u +"%Y%m%dT%H%M%SZ")"
    state_dir="$(_manifest_doc_review_state_dir "$project_root")" || return 0
    if [[ "$commit_report_enabled" == "true" ]]; then
        report_file="$(_manifest_doc_review_report_path "$project_root" "$filename_stamp")" || return 0
    else
        report_file="$state_dir/latest.md"
    fi
    latest_file="$state_dir/latest.md"
    generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    release_note="- Documentation review: $recommendation ($changed_count changed files, $docs_count documentation files; report: ${report_file#"$project_root"/})"
    commit_body="Documentation review:

- Recommendation: $recommendation
- Changed files: $changed_count
- Documentation files changed: $docs_count
- Review report: ${report_file#"$project_root"/}"

    {
        echo "# Documentation Review"
        echo ""
        echo "- generated_at: $generated_at"
        echo "- provider: ${MANIFEST_CLI_DOC_REVIEW_PROVIDER:-local}"
        echo "- commit_message: $commit_message"
        echo "- changed_files: $changed_count"
        echo "- docs_changed: $docs_count"
        echo "- command_surface_changed: $command_count"
        echo "- runtime_changed: $runtime_count"
        echo "- completions_changed: $completion_count"
        echo "- configuration_changed: $config_count"
        echo "- tests_changed: $test_count"
        echo ""
        echo "## Recommendation"
        echo ""
        echo "$recommendation"
        echo ""
        echo "## Commit Body Attachment"
        echo ""
        echo "$commit_body"
        echo ""
        echo "## Release Note Attachment"
        echo ""
        echo "$release_note"
        echo ""
        echo "## Changed Files"
        echo ""
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            echo "- $file"
        done <<< "$changed_files"
    } > "$report_file"
    [[ "$report_file" != "$latest_file" ]] && cp "$report_file" "$latest_file" 2>/dev/null || true

    echo "📚 Smart documentation review..."
    echo "   Provider: ${MANIFEST_CLI_DOC_REVIEW_PROVIDER:-local}"
    echo "   Changed files: $changed_count"
    echo "   Docs changed: $docs_count"
    echo "   Recommendation: $recommendation"
    echo "   Report: $report_file"

    if ! _manifest_doc_review_run_provider "$report_file" "$project_root"; then
        if [[ "${MANIFEST_CLI_DOC_REVIEW_REQUIRED:-false}" =~ ^(1|true|yes|on)$ ]]; then
            echo "   ❌ Documentation review provider failed"
            return 1
        fi
        echo "   ⚠️  Documentation review provider failed; continuing"
    fi

    if [[ -s "${MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT_FILE:-}" ]]; then
        MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT="$(head -1 "$MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT_FILE")"
        echo "   Provider subject: $MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT"
    fi
    if [[ -s "${MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY_FILE:-}" ]]; then
        commit_body="$(cat "$MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY_FILE")"
        echo "" >> "$report_file"
        echo "## External Provider Commit Body" >> "$report_file"
        echo "" >> "$report_file"
        cat "$MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY_FILE" >> "$report_file"
    fi
    if [[ -s "${MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE_FILE:-}" ]]; then
        release_note="$(cat "$MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE_FILE")"
        echo "" >> "$report_file"
        echo "## External Provider Release Note" >> "$report_file"
        echo "" >> "$report_file"
        cat "$MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE_FILE" >> "$report_file"
    fi

    MANIFEST_CLI_DOC_REVIEW_REPORT_FILE="$report_file"
    if [[ "$commit_body_enabled" == "true" ]]; then
        MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY="$commit_body"
    fi
    MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE="$release_note"
    [[ "$report_file" != "$latest_file" ]] && cp "$report_file" "$latest_file" 2>/dev/null || true

    return 0
}

manifest_doc_review_release_notes_since() {
    local range="${1:-}"
    local project_root="${PROJECT_ROOT:-$(pwd)}"
    local report_paths path note

    _manifest_doc_review_output_enabled "release_notes" || return 0

    report_paths="$(git -C "$project_root" log --format= --name-only ${range:+"$range"} -- 'docs/documentation-reviews/*.md' 'docs/commit-reviews/*.md' 2>/dev/null | sort -u)"
    [[ -n "$report_paths" ]] || return 0

    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ -f "$project_root/$path" ]]; then
            note="$(awk '
                /^## External Provider Release Note$/ {capture=1; next}
                /^## / && capture {exit}
                capture && NF {print}
            ' "$project_root/$path")"
            if [[ -z "$note" ]]; then
                note="$(awk '
                /^## Release Note Attachment$/ {capture=1; next}
                /^## / && capture {exit}
                capture && NF {print}
                ' "$project_root/$path")"
            fi
            [[ -n "$note" ]] && printf '%s\n' "$note"
        fi
    done <<< "$report_paths"
}

export -f manifest_smart_documentation_review
export -f manifest_doc_review_release_notes_since
