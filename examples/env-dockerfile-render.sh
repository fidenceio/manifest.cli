#!/usr/bin/env bash
# env-dockerfile-render.sh — keep a Dockerfile's build-time ARG→ENV block in
# step with `manifest status repo --env --json`.
#
# A REFERENCE, not a product. Manifest CLI used to write this block itself and
# no longer does: how a variable reaches a build is your build's design, not a
# release tool's. Copy this script into your own repository, change it to fit
# your build, and own it. Nothing in Manifest runs it or checks its output.
#
# What it renders: for every variable the spec marks `public: true` (a value a
# bundler bakes into the build, such as NEXT_PUBLIC_*), the two lines a Docker
# build needs to see it —
#
#   ARG <name>
#   ENV <framework_name, or name>=${<name>}
#
# — between two marker lines, so the block can be found and replaced.
#
# Where the block goes is yours to choose, because only you know your stages:
# an ARG is visible only in the stage that declares it, and only to the steps
# after it. Put the block in the stage that runs the build, BEFORE the step
# that runs it. This script therefore never adds a block on its own: when the
# Dockerfile has none, it prints the block and exits 1 without writing. Paste
# it where it belongs, then run the script again. (Manifest used to append the
# block to the end of the file — in a multi-stage Dockerfile that is the last
# stage, after the build has run, where the values never reach the bundler.)
#
# Usage:
#   manifest status repo --env --json | env-dockerfile-render.sh [options]
#   env-dockerfile-render.sh [options] export.json
#
# Options:
#   --dockerfile PATH   the file to update (default: Dockerfile)
#   --check             write nothing; exit 1 if the block is out of date
#   --print             print the block and exit 0; read no Dockerfile
#
# It takes over the block an earlier Manifest wrote (the marker
# "# --- manifest env bridge …"): the first run rewrites it under this
# script's own markers, after which Manifest stops mentioning it.
#
# Needs: bash, and yq v4 (https://github.com/mikefarah/yq), which Manifest
# itself needs. Written to run on the bash 3.2 that macOS ships, and on BSD
# awk: the block reaches awk through the environment, because BSD awk refuses
# a newline inside a -v value.

set -u

BEGIN_MARK="# --- env-dockerfile-render.sh: build-time variables (generated from the spec — edit the spec, not this block) ---"
END_MARK="# --- end env-dockerfile-render.sh ---"
# The markers of the block Manifest itself wrote, recognised so it is taken over.
FORMER_BEGIN="# --- manifest env bridge (generated — edit the spec, not this block) ---"
FORMER_END="# --- end manifest env bridge ---"

dockerfile="Dockerfile"
check_only=false
print_only=false
input=""

die() { echo "env-dockerfile-render.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dockerfile)
            [ $# -ge 2 ] || die "--dockerfile needs a path"
            dockerfile="$2"; shift ;;
        --check) check_only=true ;;
        --print) print_only=true ;;
        -h|--help) sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *)
            [ -z "$input" ] || die "one input file at most"
            input="$1" ;;
    esac
    shift
done

command -v yq >/dev/null 2>&1 || die "yq v4 is required"

tmp_dir="$(mktemp -d)" || die "could not create a temporary directory"
staged=""
# keep_new: set when an in-place write failed part-way, so the temporary
# directory then holds the only whole copy of the new Dockerfile.
keep_new=false
trap '[ "$keep_new" = "true" ] || rm -rf "$tmp_dir"; [ -z "$staged" ] || rm -f "$staged"' EXIT
export_file="$tmp_dir/export.json"
# The temporary directory can be full. Two files are written to it — this
# copy of the export, and the new Dockerfile further down — and neither is
# used until it is known to be whole: a cut-off export is not valid JSON, so
# yq refuses it below, and the new Dockerfile is compared with a second
# rendering. Everything else is held in variables, not files.
if [ -n "$input" ]; then
    [ -f "$input" ] || die "no such file: $input"
    cat "$input" > "$export_file" || die "could not write to the temporary directory $tmp_dir"
else
    [ -t 0 ] && die "no input: pipe \`manifest status repo --env --json\` into this script, or name a file"
    cat > "$export_file" || die "could not write to the temporary directory $tmp_dir"
fi
[ -s "$export_file" ] || die "the export is empty (did \`manifest status repo --env --json\` fail?)"
[ "$(yq e -p=json '.schema' "$export_file" 2>/dev/null)" = "1" ] \
    || die "not a schema-1 export from \`manifest status repo --env --json\`"

[ "$(yq e -p=json '.env | tag' "$export_file" 2>/dev/null)" = "!!seq" ] \
    || die "not a schema-1 export: env is not a list"
public_count="$(yq e -p=json '[.env[] | select(.public == true)] | length' "$export_file" 2>/dev/null)"
case "$public_count" in ''|*[!0-9]*) die "yq could not read the export" ;; esac

# Every name lands in a Dockerfile instruction; refuse one that would break it.
# Checked per entry, not per line, so a value with a newline in it cannot pass
# as two good halves.
NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'
bad_filter='[.env[] | select(.public == true) | select(
    ((.name | tag) != "!!str") or (.name | test(strenv(NAME_RE)) | not)
    or ((.framework_name // "" | tag) != "!!str")
    or ((.framework_name // "") != "" and ((.framework_name // "") | test(strenv(NAME_RE)) | not)))]'
bad_count="$(NAME_RE="$NAME_RE" yq e -p=json "$bad_filter | length" "$export_file" 2>/dev/null)"
if [ "$bad_count" != "0" ]; then
    bad="$(NAME_RE="$NAME_RE" yq e -p=json "$bad_filter | .[0] | (.framework_name // .name)" "$export_file" 2>/dev/null | head -n 1)"
    die "not a variable name: ${bad:-an entry yq could not read}"
fi

# The block: the markers, and two lines per public variable, in spec order.
# yq's output is captured and counted before it is used: a yq that fails, or
# cannot write TSV, must not turn into an empty block that deletes every line.
pairs="$(yq e -p=json -o=tsv '.env[] | select(.public == true) | [.name, (.framework_name // .name)]' \
    "$export_file" 2>/dev/null)" \
    || die "yq could not list the variables (yq v4 with -o=tsv is required); nothing was written"
[ "$(printf '%s\n' "$pairs" | grep -c . || true)" -eq "$public_count" ] \
    || die "yq listed a different number of variables than the export holds; nothing was written"
block="$(
    printf '%s\n' "$BEGIN_MARK"
    printf '%s\n' "$pairs" | while IFS="$(printf '\t')" read -r name injected; do
        [ -n "$name" ] || continue
        printf 'ARG %s\n' "$name"
        # An empty framework_name means none, as Manifest's writer read it.
        printf 'ENV %s=${%s}\n' "${injected:-$name}" "$name"
    done
    printf '%s\n' "$END_MARK"
)"

if [ "$print_only" = "true" ]; then
    printf '%s\n' "$block"
    exit 0
fi

[ -f "$dockerfile" ] || die "no such file: $dockerfile"
[ -r "$dockerfile" ] || die "cannot read $dockerfile"

# Which markers the Dockerfile carries: this script's, Manifest's former ones,
# or none. Exactly one block is expected.
count_mark() { grep -cxF "$1" "$dockerfile" 2>/dev/null || true; }
own="$(count_mark "$BEGIN_MARK")"
former="$(count_mark "$FORMER_BEGIN")"
if [ $((own + former)) -eq 0 ] && [ "$public_count" -eq 0 ]; then
    echo "  nothing to do: no public variables, and no block in $dockerfile"
    exit 0
fi
if [ $((own + former)) -eq 0 ]; then
    echo "No block in $dockerfile yet, so nothing was written. Paste this into the stage" >&2
    echo "that runs your build, before the step that runs it, then run this again:" >&2
    echo "" >&2
    printf '%s\n' "$block"
    exit 1
fi
[ $((own + former)) -eq 1 ] || die "$dockerfile holds more than one block; keep one"

# Replace the block where it stands; everything outside it is copied as is.
# The new Dockerfile, on stdout. Exit 3 = the block has no end marker.
render_dockerfile() {
    MANIFEST_RENDER_BLOCK="$block" awk \
        -v b1="$BEGIN_MARK" -v e1="$END_MARK" -v b2="$FORMER_BEGIN" -v e2="$FORMER_END" '
        ($0 == b1 || $0 == b2) && !done { inside = 1; print ENVIRON["MANIFEST_RENDER_BLOCK"]; next }
        inside && ($0 == e1 || $0 == e2) { inside = 0; done = 1; next }
        inside { next }
        { print }
        END { if (inside) exit 3 }
    ' "$dockerfile"
}
render_rc=0
render_dockerfile > "$tmp_dir/Dockerfile" || render_rc=$?
[ "$render_rc" -ne 3 ] || die "$dockerfile: the block has no end marker; nothing was written"
[ "$render_rc" -eq 0 ] || die "awk could not rewrite $dockerfile (exit $render_rc); nothing was written"
# awk's exit status is not proof the file is whole: BusyBox awk exits 0 when
# the write fails on a full disk, and what it leaves is a cut-off Dockerfile
# that would then replace the real one. So it is rendered a second time into
# a pipe, which cannot fill up, and the two are compared.
render_dockerfile | cmp -s - "$tmp_dir/Dockerfile" \
    || die "the new $dockerfile could not be written whole to the temporary directory $tmp_dir (is it full?); nothing was written"

if cmp -s "$tmp_dir/Dockerfile" "$dockerfile"; then
    echo "  up-to-date: $dockerfile"
    exit 0
fi
if [ "$check_only" = "true" ]; then
    echo "  out of date: $dockerfile (run without --check to rewrite the block)"
    exit 1
fi
# Staged beside the Dockerfile as a copy of it (cp -p keeps the mode), filled,
# then renamed over it: a failure part-way leaves the old file whole. Written
# through in place instead when a rename would change what the file is: a
# symlink (it stays a link), a hard link (the other names keep seeing it), or
# a file someone else owns (it keeps its owner). Running as root against a
# file a build user owns — most CI containers — takes this path.
if [ -L "$dockerfile" ] || [ ! -O "$dockerfile" ] || [ -n "$(find "$dockerfile" -links +1 2>/dev/null)" ]; then
    [ -w "$dockerfile" ] || die "cannot write $dockerfile; it was left as it was"
    # `>` empties the file before a byte is written. If the write then fails
    # (a full disk), the copy in the temporary directory is the only whole
    # one: it is kept and named, not removed with the rest on exit.
    if ! cat "$tmp_dir/Dockerfile" > "$dockerfile"; then
        keep_new=true
        rm -f "$export_file"
        die "could not write $dockerfile; it may now be incomplete. The whole new file is at: $tmp_dir/Dockerfile"
    fi
else
    staged="$dockerfile.env-dockerfile-render.$$"
    if ! { cp -p "$dockerfile" "$staged" && cat "$tmp_dir/Dockerfile" > "$staged" && mv -f "$staged" "$dockerfile"; }; then
        rm -f "$staged"
        die "could not write $dockerfile; it was left as it was"
    fi
fi
echo "  wrote: $dockerfile (build-time variable block)"
