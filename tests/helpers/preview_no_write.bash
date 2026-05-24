#!/usr/bin/env bash
# Snapshot-and-diff helpers for the preview no-write coverage matrix.
#
# A preview-mode command must leave the user-visible sandbox byte-identical.
# Focused tests assert specific files were not created; this helper catches
# stray writes the focused tests do not know to check.
#
# Snapshot scope intentionally excludes subprocess side effects (Homebrew
# bootsnap caches, etc.) that are unrelated to whether the CLI itself wrote
# any user data. The scope is the union of paths a preview command must not
# touch: the project root and the on-disk install footprint.

# Print a stable, sorted snapshot of every regular file under each of the
# given paths as lines of "<sha256>\t<absolute-path>". Missing paths are
# recorded as MISSING lines so deletion is also detected.
snapshot_tree() {
    local p
    for p in "$@"; do
        if [[ -e "$p" ]]; then
            if [[ -f "$p" ]]; then
                local hash
                hash="$(shasum -a 256 "$p" 2>/dev/null | awk '{print $1}')"
                printf '%s\t%s\n' "$hash" "$p"
            elif [[ -L "$p" ]]; then
                printf 'SYMLINK:%s\t%s\n' "$(readlink "$p")" "$p"
            elif [[ -d "$p" ]]; then
                (
                    cd "$p" || return 1
                    find . \( -type f -o -type l \) -print \
                        | LC_ALL=C sort \
                        | while IFS= read -r path; do
                            if [[ -L "$path" ]]; then
                                printf 'SYMLINK:%s\t%s\n' "$(readlink "$path")" "$p/${path#./}"
                            else
                                local h
                                h="$(shasum -a 256 "$path" 2>/dev/null | awk '{print $1}')"
                                printf '%s\t%s\n' "$h" "$p/${path#./}"
                            fi
                        done
                )
            fi
        else
            printf 'MISSING\t%s\n' "$p"
        fi
    done
}

# Default snapshot scope: project work directory + on-disk install footprint.
# Each test should call this rather than naming paths inline so the scope
# stays consistent across the matrix.
preview_snapshot_paths() {
    printf '%s\n' \
        "$SCRATCH/work" \
        "$HOME/.manifest-cli" \
        "$HOME/.local/bin/manifest" \
        "$HOME/.zshrc" \
        "$HOME/.bashrc" \
        "$HOME/.profile"
}

# Capture a snapshot across the standard preview scope.
preview_snapshot() {
    local paths=()
    while IFS= read -r p; do paths+=("$p"); done < <(preview_snapshot_paths)
    snapshot_tree "${paths[@]}"
}

# Fail the test if BEFORE != AFTER. Prints a unified diff to stderr so the
# offending paths are visible in bats output.
assert_no_writes() {
    local before="$1"
    local after="$2"
    if [[ "$before" != "$after" ]]; then
        {
            printf 'FAIL: filesystem changed during preview\n'
            diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
        } >&2
        return 1
    fi
}
