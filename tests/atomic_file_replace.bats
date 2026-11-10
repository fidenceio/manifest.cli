#!/usr/bin/env bats
# bats file_tags=smoke
#
# TRACKER §3 — the write-then-rename slice. One helper,
# manifest_replace_file_atomically, now lands content on a user-owned file for
# the three writers that used to do it three different wrong ways:
#
#   validate_file                      `echo "$content" > "$file"` — truncated a
#                                      tracked doc at redirect-open, on every ship
#   manifest_replace_managed_block     scratch-dir mktemp + unchecked `mv` — a
#                                      cross-device rename, and the temp's 0600
#                                      carried onto README.md / docs/INDEX.md
#   _manifest_docs_write_managed_file  `cp` from a 0600 mktemp — every NEW docs-site
#                                      file born 0600 (measured: eight tracked files)
#
# Pins: the target keeps its own mode; a new file is not 0600; nothing is left
# beside the target; a failed staging leaves the target byte-identical; and the
# mode defect's mechanism is shown live as the positive control, so the guard
# cannot pass on a platform where the defect could not occur.

load 'helpers/setup'

setup() {
    load_modules "docs/manifest-markdown-validation.sh" "docs/manifest-documentation.sh"
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
}

teardown() {
    cd /tmp
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    rm -rf "$SCRATCH"
}

_no_temp_beside() {
    # mktemp "${target}.XXXXXX" leaves nothing behind on success or failure.
    [ -z "$(ls "$(dirname "$1")" | grep -F "$(basename "$1")." || true)" ]
}

# --- positive control: the mechanism the helper exists for -------------------------

@test "positive control: a bare mv from a 0600 mktemp onto a 644 file leaves it 0600" {
    printf 'old\n' > target.md; chmod 644 target.md
    local tmp; tmp="$(mktemp "$SCRATCH/scratch.XXXXXX")"
    [ "$(manifest_file_mode "$tmp")" = "600" ]
    printf 'new\n' > "$tmp"
    mv -f "$tmp" target.md
    [ "$(manifest_file_mode target.md)" = "600" ]
}

# --- the helper ---------------------------------------------------------------------

@test "helper: an existing file keeps its mode, gets the new contents, and no temp is left beside it" {
    printf 'old\n' > target.md; chmod 644 target.md
    printf 'new\n' > source.txt; chmod 600 source.txt
    run manifest_replace_file_atomically "$SCRATCH/target.md" "$SCRATCH/source.txt"
    [ "$status" -eq 0 ]
    [ "$(cat target.md)" = "new" ]
    [ "$(manifest_file_mode target.md)" = "644" ]
    _no_temp_beside "$SCRATCH/target.md"
    # The source is the caller's; the helper does not consume it.
    [ -f source.txt ]

    chmod 600 target.md
    run manifest_replace_file_atomically "$SCRATCH/target.md" "$SCRATCH/source.txt"
    [ "$status" -eq 0 ]
    [ "$(manifest_file_mode target.md)" = "600" ]
}

@test "helper: a new file is created at the umask default, never 0600, and its directory is made" {
    printf 'new\n' > source.txt; chmod 600 source.txt
    run manifest_replace_file_atomically "$SCRATCH/deep/er/new.md" "$SCRATCH/source.txt"
    [ "$status" -eq 0 ]
    [ "$(cat deep/er/new.md)" = "new" ]
    [ "$(manifest_file_mode deep/er/new.md)" != "600" ]
    [ "$(manifest_file_mode deep/er/new.md)" = "$(printf '%o' "$(( 0666 & ~0$(umask) ))")" ]
}

@test "helper: reads stdin with -, and a leading -n line is content, not a flag" {
    printf 'old\n' > target.md; chmod 644 target.md
    run bash -c 'printf -- "-n first\nsecond\n" | manifest_replace_file_atomically "$1" -' _ "$SCRATCH/target.md"
    [ "$status" -eq 0 ]
    [ "$(head -n 1 target.md)" = "-n first" ]
    [ "$(manifest_file_mode target.md)" = "644" ]
}

@test "helper: a missing source, or a directory it cannot stage in, leaves the target byte-identical and returns 1" {
    printf 'keep me\n' > target.md; chmod 644 target.md
    run manifest_replace_file_atomically "$SCRATCH/target.md" "$SCRATCH/does-not-exist"
    [ "$status" -eq 1 ]
    [[ "$output" == *"source file is missing"* ]]
    [ "$(cat target.md)" = "keep me" ]

    [ "$(id -u)" -ne 0 ] || skip "root can stage in a read-only directory"
    mkdir ro; printf 'keep me\n' > ro/target.md; chmod 644 ro/target.md; chmod 555 ro
    printf 'new\n' > source.txt
    run manifest_replace_file_atomically "$SCRATCH/ro/target.md" "$SCRATCH/source.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not stage a temporary file beside it"* ]]
    [ "$(cat ro/target.md)" = "keep me" ]
    chmod 755 ro
    _no_temp_beside "$SCRATCH/ro/target.md"
}

@test "helper: writes THROUGH a symlink — the link stays a link and the real file gets the content at its own mode" {
    printf 'old\n' > real.md; chmod 644 real.md
    ln -s real.md link.md
    printf 'new\n' > source.txt; chmod 600 source.txt
    run manifest_replace_file_atomically "$SCRATCH/link.md" "$SCRATCH/source.txt"
    [ "$status" -eq 0 ]
    [ -L link.md ]
    [ "$(cat real.md)" = "new" ]
    [ "$(manifest_file_mode real.md)" = "644" ]
    _no_temp_beside "$SCRATCH/real.md"

    # A link to a link resolves the chain; a loop is refused, untouched.
    ln -s link.md link2.md
    printf 'newer\n' > source.txt
    run manifest_replace_file_atomically "$SCRATCH/link2.md" "$SCRATCH/source.txt"
    [ "$status" -eq 0 ]
    [ "$(cat real.md)" = "newer" ]
    ln -s loop-b.md loop-a.md; ln -s loop-a.md loop-b.md
    run manifest_replace_file_atomically "$SCRATCH/loop-a.md" "$SCRATCH/source.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"symlink chain too deep"* ]]
}

@test "helper: a directory at the target path is refused, with nothing moved into it" {
    mkdir dir.md
    printf 'new\n' > source.txt
    run manifest_replace_file_atomically "$SCRATCH/dir.md" "$SCRATCH/source.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a regular file"* ]]
    [ -d dir.md ]
    [ -z "$(ls -A dir.md)" ]
}

@test "helper: staging happens beside the target, not in a scratch dir — a dead TMPDIR changes nothing" {
    printf 'old\n' > target.md; chmod 644 target.md
    printf 'new\n' > source.txt
    TMPDIR=/nonexistent/scratch run manifest_replace_file_atomically "$SCRATCH/target.md" "$SCRATCH/source.txt"
    [ "$status" -eq 0 ]
    [ "$(cat target.md)" = "new" ]
    [ "$(manifest_file_mode target.md)" = "644" ]
}

# --- the three writers, through the helper ------------------------------------------

@test "validate_file: cleaning a tracked doc keeps its mode, leaves no temp, and the content is what clean_markdown produced" {
    printf '# Title   \n\n\n\nbody  \n' > doc.md; chmod 644 doc.md
    run validate_file "$SCRATCH/doc.md" true
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned:"* ]]
    [ "$(cat doc.md)" = "$(clean_markdown "$(printf '# Title   \n\n\n\nbody  \n')")" ]
    [ "$(manifest_file_mode doc.md)" = "644" ]
    _no_temp_beside "$SCRATCH/doc.md"
}

@test "validate_file: a doc the cleaner would not change is not rewritten at all" {
    printf '# Title\n\nbody\n' > doc.md; chmod 600 doc.md
    # GNU stat first, BSD second — the other way round, GNU reads `-f` as
    # --file-system, prints a filesystem block for the file and fails on '%m',
    # so both arms ran and the "mtime" carried a changing free-block count.
    local before; before="$(stat -c '%Y' doc.md 2>/dev/null || stat -f '%m' doc.md)"
    sleep 1
    run validate_file "$SCRATCH/doc.md" true
    [ "$status" -eq 0 ]
    [[ "$output" != *"Cleaned:"* ]]
    [ "$(stat -c '%Y' doc.md 2>/dev/null || stat -f '%m' doc.md)" = "$before" ]
    [ "$(manifest_file_mode doc.md)" = "600" ]
}

@test "manifest_replace_managed_block: the file keeps its mode and the block is replaced in place" {
    printf 'before\n<!-- start -->\nold\n<!-- end -->\nafter\n' > README.md; chmod 644 README.md
    printf 'new block\n' > block.txt
    run manifest_replace_managed_block "$SCRATCH/README.md" '<!-- start -->' '<!-- end -->' "$SCRATCH/block.txt"
    [ "$status" -eq 0 ]
    [ "$(cat README.md)" = "$(printf 'before\n<!-- start -->\nnew block\n<!-- end -->\nafter')" ]
    [ "$(manifest_file_mode README.md)" = "644" ]
    _no_temp_beside "$SCRATCH/README.md"
    # No marker pair → refused, untouched.
    printf 'no markers\n' > plain.md
    run manifest_replace_managed_block "$SCRATCH/plain.md" '<!-- start -->' '<!-- end -->' "$SCRATCH/block.txt"
    [ "$status" -eq 1 ]
    [ "$(cat plain.md)" = "no markers" ]
}

@test "_manifest_docs_write_managed_file: a new docs-site file is not born 0600, and a managed one keeps its mode" {
    local src; src="$(mktemp "$SCRATCH/content.XXXXXX")"
    printf '# Managed by Manifest CLI docs site generation\n' > "$src"
    [ "$(manifest_file_mode "$src")" = "600" ]   # the input every caller passes

    run _manifest_docs_write_managed_file "$SCRATCH/docs-site/_config.yml" "Managed by Manifest CLI docs site generation" "$src"
    [ "$status" -eq 0 ]
    [ "$(manifest_file_mode docs-site/_config.yml)" != "600" ]

    chmod 664 docs-site/_config.yml
    run _manifest_docs_write_managed_file "$SCRATCH/docs-site/_config.yml" "Managed by Manifest CLI docs site generation" "$src"
    [ "$status" -eq 0 ]
    [ "$(manifest_file_mode docs-site/_config.yml)" = "664" ]

    # The unmanaged-file refusal is unchanged.
    printf 'mine\n' > docs-site/index.md
    run _manifest_docs_write_managed_file "$SCRATCH/docs-site/index.md" "Managed by Manifest CLI docs site generation" "$src"
    [ "$status" -eq 1 ]
    [ "$(cat docs-site/index.md)" = "mine" ]
}

# --- the repo itself is no longer a witness -------------------------------------------

@test "no tracked file in this repo is owner-only (the eight §3 names were repaired)" {
    # The clone's umask is the baseline, not a literal 644: a checkout made
    # under umask 077 is owner-only everywhere and that is the user's choice,
    # not this repo's defect.
    local default
    default="$(printf '%o' "$(( 0666 & ~0$(umask) ))")"
    [ "$default" != "600" ] || skip "umask leaves new files owner-only; nothing to distinguish"
    local f owner_only=0 seen=0
    while IFS= read -r f; do
        seen=$((seen + 1))
        case "$(manifest_file_mode "$TEST_REPO_ROOT/$f" 2>/dev/null)" in
            600|700) owner_only=$((owner_only + 1)); echo "owner-only: $f" ;;
        esac
    done < <(git -C "$TEST_REPO_ROOT" ls-files)
    [ "$seen" -gt 100 ]   # control: the walk saw the tree
    [ "$owner_only" -eq 0 ]
}
