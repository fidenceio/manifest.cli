#!/usr/bin/env bash
# Prune boilerplate-stub release docs from docs/zArchive.
#
# Tracker item #42 — extends the 709d6a5 prune to also filter changelogs
# whose only substantive section is auto-emitted "Documentation review:"
# bullets from manifest-doc-review.sh.
#
# Detection (file is a stub if any apply):
#   1. Empty-release marker — contains "No notable user-facing changes
#      were detected since the previous release tag" (the doc-generation
#      pipeline's no-content marker).
#   2. Doc-review-only — sections are exactly "Summary" + "Documentation",
#      and every Documentation bullet starts with "Documentation review:".
#
# Each matched CHANGELOG_v<v>.md drops its paired RELEASE_v<v>.md too.
# After --apply, run `manifest docs cleanup` to regenerate INDEX.md files.
#
# Usage: scripts/prune-archive-stubs.sh [--apply] [path]
# Default path: docs/zArchive. Default mode: dry-run.

set -euo pipefail

mode="dry-run"
target="docs/zArchive"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)   mode="apply" ;;
        --dry-run) mode="dry-run" ;;
        -h|--help)
            sed -n '/^# Usage:/,/^# Default mode/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) target="$1" ;;
    esac
    shift
done

[[ -d "$target" ]] || { echo "Not a directory: $target" >&2; exit 1; }

is_stub() {
    local file="$1"

    grep -qF "No notable user-facing changes were detected since the previous release tag" "$file" && return 0

    local sections
    sections=$(grep -E '^### ' "$file" | LC_ALL=C sort)
    [[ "$sections" == $'### Documentation\n### Summary' ]] || return 1

    local doc_bullets
    doc_bullets=$(awk '/^### Documentation$/{f=1; next} /^### /{f=0} f && /^- /' "$file")
    [[ -n "$doc_bullets" ]] || return 1
    grep -vE '^- Documentation review:' <<< "$doc_bullets" | grep -q '^- ' && return 1
    return 0
}

removed=0
declare -a removed_files=()

while IFS= read -r changelog; do
    is_stub "$changelog" || continue
    version=$(basename "$changelog" .md | sed 's/^CHANGELOG_//')
    release="$(dirname "$changelog")/RELEASE_${version}.md"
    has_release=0
    [[ -f "$release" ]] && has_release=1

    if [[ "$mode" == "apply" ]]; then
        rm -f "$changelog"
        [[ "$has_release" -eq 1 ]] && rm -f "$release"
    fi

    removed=$((removed + 1))
    removed_files+=("$changelog")
    [[ "$has_release" -eq 1 ]] && removed_files+=("$release")
done < <(find "$target" -type f -name 'CHANGELOG_v*.md' | LC_ALL=C sort)

label="DRY-RUN — would remove"
[[ "$mode" == "apply" ]] && label="Removed"

if [[ "$removed" -eq 0 ]]; then
    echo "${label} 0 stub pair(s)."
    exit 0
fi

echo "${label} ${removed} stub pair(s) (${#removed_files[@]} files):"
for f in "${removed_files[@]}"; do
    echo "  $f"
done

if [[ "$mode" == "dry-run" ]]; then
    echo
    echo "Re-run with --apply to delete."
fi
