#!/usr/bin/env bats
#
# examples/env-dockerfile-render.sh — the reference script an adopter copies
# to keep the Dockerfile ARG→ENV block Manifest stopped writing (TRACKER §127).
#
# Manifest does not run it; these tests keep the copy that ships honest:
#
#   takes over   the block an earlier Manifest wrote is rewritten in place,
#                under the script's own markers, mode and surroundings kept
#   never adds   a Dockerfile with no block is not written: the block is
#                printed for the adopter to place. Manifest appended it to
#                the end of the file, which in a multi-stage Dockerfile is the
#                last stage, after the build step — where it does nothing
#   --check      writes nothing; 0 when current, 1 when the spec moved on
#   refuses      input that is not an export, a name that would break the
#                Dockerfile (checked per entry, so a newline cannot split one
#                bad value into two good lines), two blocks, and a yq that
#                cannot list the variables — never an emptied block
#   in place     a symlink or a hard link is written through, not renamed
#                over; a write that fails part-way keeps the whole new file
#                and names it, and never leaves a cut-off Dockerfile as the
#                only copy
#
# The export is written as a fixture so the script is tested on its own; one
# test runs it from the tree's entrypoint end to end.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    RENDER="$TEST_REPO_ROOT/examples/env-dockerfile-render.sh"
    cd "$SCRATCH"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# export_json <public-name> <framework_name|null> [<second public name>]
export_json() {
    local fw="null"
    [ "$2" != "null" ] && fw="\"$2\""
    {
        printf '{"schema":1,"identity":"acme-web","env":['
        printf '{"name":"ACME_WEB_LOG_LEVEL","description":"","required":false,"default":"info","secret":false,"group":"app","public":false,"framework_name":null},'
        printf '{"name":"%s","description":"","required":true,"default":null,"secret":false,"group":"app","public":true,"framework_name":%s}' "$1" "$fw"
        if [ -n "${3:-}" ]; then
            printf ',{"name":"%s","description":"","required":false,"default":null,"secret":false,"group":"app","public":true,"framework_name":null}' "$3"
        fi
        printf ']}\n'
    } > "$SCRATCH/export.json"
}

FORMER_BEGIN='# --- manifest env bridge (generated — edit the spec, not this block) ---'
FORMER_END='# --- end manifest env bridge ---'
OWN_BEGIN='# --- env-dockerfile-render.sh: build-time variables (generated from the spec — edit the spec, not this block) ---'

multi_stage_with_former_block() {
    printf '%s\n' \
        'FROM node:22 AS build' \
        "$FORMER_BEGIN" \
        'ARG ACME_WEB_OLD' \
        'ENV ACME_WEB_OLD=${ACME_WEB_OLD}' \
        "$FORMER_END" \
        'RUN npm run build' \
        'FROM nginx:1.27' \
        'COPY --from=build /app/dist /usr/share/nginx/html' > "$SCRATCH/Dockerfile"
}

@test "takes over the block Manifest wrote: rewritten in place under its own markers, the rest and the mode kept" {
    export_json ACME_WEB_SITE_URL NEXT_PUBLIC_SITE_URL
    multi_stage_with_former_block
    chmod 640 "$SCRATCH/Dockerfile"

    run "$RENDER" export.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"wrote: Dockerfile"* ]]
    [ "$(sed -n 1p Dockerfile)" = "FROM node:22 AS build" ]
    [ "$(sed -n 2p Dockerfile)" = "$OWN_BEGIN" ]
    [ "$(sed -n 3p Dockerfile)" = "ARG ACME_WEB_SITE_URL" ]
    [ "$(sed -n 4p Dockerfile)" = 'ENV NEXT_PUBLIC_SITE_URL=${ACME_WEB_SITE_URL}' ]
    [ "$(sed -n 5p Dockerfile)" = "# --- end env-dockerfile-render.sh ---" ]
    # Still before the build step, in the build stage: where it was put.
    [ "$(sed -n 6p Dockerfile)" = "RUN npm run build" ]
    [ "$(tail -n 1 Dockerfile)" = "COPY --from=build /app/dist /usr/share/nginx/html" ]
    refute grep -qF "$FORMER_BEGIN" Dockerfile
    refute grep -q 'ACME_WEB_OLD' Dockerfile
    # ls -l, not stat: BusyBox stat -f is filesystem status, and succeeds.
    local perms
    perms="$(ls -l Dockerfile)"
    [ "${perms:0:10}" = "-rw-r-----" ]
}

@test "--check: 0 when current, 1 naming the file when the spec moved on, and it writes nothing" {
    export_json ACME_WEB_SITE_URL null
    multi_stage_with_former_block
    "$RENDER" export.json >/dev/null

    run "$RENDER" --check export.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"up-to-date: Dockerfile"* ]]

    export_json ACME_WEB_SITE_URL null ACME_WEB_API_URL
    local before
    before="$(cksum < Dockerfile)"
    run "$RENDER" --check export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of date: Dockerfile"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]

    # Control: without --check the same input is written, and then current.
    run "$RENDER" export.json
    [ "$status" -eq 0 ]
    grep -qx 'ARG ACME_WEB_API_URL' Dockerfile
    run "$RENDER" --check export.json
    [ "$status" -eq 0 ]
}

@test "never adds a block: with none in the Dockerfile it prints one, exits 1, and leaves the file byte-identical" {
    export_json ACME_WEB_SITE_URL NEXT_PUBLIC_SITE_URL
    printf 'FROM node:22 AS build\nRUN npm run build\nFROM nginx:1.27\n' > Dockerfile
    local before
    before="$(cksum < Dockerfile)"
    run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"nothing was written"* ]]
    [[ "$output" == *"ARG ACME_WEB_SITE_URL"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]
}

@test "--print prints the block and reads no Dockerfile" {
    export_json ACME_WEB_SITE_URL null
    run "$RENDER" --print export.json
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$OWN_BEGIN" ]
    [ "${lines[1]}" = "ARG ACME_WEB_SITE_URL" ]
    [ "${lines[2]}" = 'ENV ACME_WEB_SITE_URL=${ACME_WEB_SITE_URL}' ]
    [ ! -e Dockerfile ]
}

@test "refused before anything is written: not an export, a name that would break the Dockerfile, two blocks" {
    multi_stage_with_former_block
    local before
    before="$(cksum < Dockerfile)"

    printf '{"schema":2,"env":[]}\n' > export.json
    run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a schema-1 export"* ]]

    export_json 'ACME WEB; RUN curl evil' null
    run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a variable name"* ]]

    export_json ACME_WEB_SITE_URL 'NEXT_PUBLIC_X=1 EVIL'
    run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a variable name"* ]]

    [ "$(cksum < Dockerfile)" = "$before" ]

    export_json ACME_WEB_SITE_URL null
    printf '%s\n%s\n' "$FORMER_BEGIN" "$FORMER_END" >> Dockerfile
    before="$(cksum < Dockerfile)"
    run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"more than one block"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]
}

@test "refused per entry, not per line: a framework_name with a newline in it does not pass as two good halves" {
    multi_stage_with_former_block
    local before
    before="$(cksum < Dockerfile)"
    printf '{"schema":1,"env":[{"name":"A","public":true,"framework_name":"FOO\\nBAR"}]}\n' > export.json
    run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a variable name"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]
}

@test "a yq that cannot read the export never empties the block: env not a list, or no TSV output" {
    multi_stage_with_former_block
    local before
    before="$(cksum < Dockerfile)"
    printf '{"schema":1,"env":"x"}\n' > export.json
    run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"env is not a list"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]

    # A yq that refuses -o=tsv, as some 4.x builds may: refused, nothing written.
    local real_yq
    real_yq="$(command -v yq)"
    mkdir -p "$SCRATCH/bin"
    printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -o=tsv) echo "unknown output format" >&2; exit 1;; esac; done\nexec "%s" "$@"\n' "$real_yq" > "$SCRATCH/bin/yq"
    chmod +x "$SCRATCH/bin/yq"
    export_json ACME_WEB_SITE_URL null
    PATH="$SCRATCH/bin:$PATH" run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"nothing was written"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]
    grep -qx 'ARG ACME_WEB_OLD' Dockerfile

    # A yq that exits 0 and prints no TSV: the count catches it, not || die.
    printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -o=tsv) exit 0;; esac; done\nexec "%s" "$@"\n' "$real_yq" > "$SCRATCH/bin/yq"
    PATH="$SCRATCH/bin:$PATH" run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"different number of variables"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]

    # Control: the real yq rewrites the block.
    run "$RENDER" export.json
    [ "$status" -eq 0 ]
    grep -qx 'ARG ACME_WEB_SITE_URL' Dockerfile
}

@test "no public variables and no block: nothing to do, exit 0 — also under --check" {
    printf 'FROM node:22\n' > Dockerfile
    printf '{"schema":1,"identity":"x","env":[]}\n' > export.json
    run "$RENDER" --check export.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to do"* ]]
    [ "$(cat Dockerfile)" = "FROM node:22" ]
}

@test "an empty framework_name means none: ENV takes the variable's own name, never ENV =" {
    multi_stage_with_former_block
    printf '{"schema":1,"env":[{"name":"ACME_WEB_B","public":true,"framework_name":""}]}\n' > export.json
    run "$RENDER" export.json
    [ "$status" -eq 0 ]
    grep -qx 'ENV ACME_WEB_B=${ACME_WEB_B}' Dockerfile
    refute grep -q '^ENV =' Dockerfile
}

@test "a Dockerfile that cannot be read is refused, not reported as having no block" {
    [ "$(id -u)" -ne 0 ] || skip "root reads any file"
    multi_stage_with_former_block
    chmod 000 Dockerfile
    printf '{"schema":1,"identity":"x","env":[]}\n' > export.json
    run "$RENDER" --check export.json
    chmod 644 Dockerfile
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot read Dockerfile"* ]]
    [[ "$output" != *"nothing to do"* ]]
}

@test "a Dockerfile that is a symlink or a hard link is written through: the link stays a link, the other name sees the new block" {
    export_json ACME_WEB_SITE_URL null
    mkdir -p "$SCRATCH/real"
    multi_stage_with_former_block
    mv Dockerfile "$SCRATCH/real/Dockerfile"
    ln -s real/Dockerfile Dockerfile
    run "$RENDER" export.json
    [ "$status" -eq 0 ]
    [ -L Dockerfile ]
    grep -qx 'ARG ACME_WEB_SITE_URL' "$SCRATCH/real/Dockerfile"
    grep -qx 'RUN npm run build' "$SCRATCH/real/Dockerfile"

    rm -f Dockerfile
    multi_stage_with_former_block
    ln Dockerfile "$SCRATCH/real/other-name"
    local inode
    inode="$(ls -i Dockerfile | awk '{print $1}')"
    run "$RENDER" export.json
    [ "$status" -eq 0 ]
    # Same inode: a rename would have left other-name holding the old block.
    [ "$(ls -i Dockerfile | awk '{print $1}')" = "$inode" ]
    grep -qx 'ARG ACME_WEB_SITE_URL' "$SCRATCH/real/other-name"
    refute grep -q 'ACME_WEB_OLD' "$SCRATCH/real/other-name"
}

@test "a write that fails part-way never loses the Dockerfile: in place, the whole new file is kept and named; renamed, the old one is untouched" {
    export_json ACME_WEB_SITE_URL null
    # A cat that writes four bytes of the new Dockerfile and fails, as a full
    # disk does. Every other cat the script runs is the real one.
    local real_cat
    real_cat="$(command -v cat)"
    mkdir -p "$SCRATCH/bin" "$SCRATCH/real"
    printf '#!/bin/sh\ncase "$1" in */Dockerfile) printf FROM; exit 1;; esac\nexec "%s" "$@"\n' "$real_cat" > "$SCRATCH/bin/cat"
    chmod +x "$SCRATCH/bin/cat"

    # In place (a hard link): the file is emptied before the write fails, so
    # the copy the script holds is the only whole one.
    multi_stage_with_former_block
    ln Dockerfile "$SCRATCH/real/other-name"
    PATH="$SCRATCH/bin:$PATH" run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not write Dockerfile; it may now be incomplete. The whole new file is at: "* ]]
    refute grep -q 'RUN npm run build' Dockerfile
    local kept="${output##*The whole new file is at: }"
    kept="${kept%%$'\n'*}"
    [ "${kept%/Dockerfile}" != "$kept" ]
    [ -f "$kept" ]
    grep -qx 'ARG ACME_WEB_SITE_URL' "$kept"
    grep -qx 'RUN npm run build' "$kept"
    grep -qx 'COPY --from=build /app/dist /usr/share/nginx/html' "$kept"
    # Only the Dockerfile is kept: the export and the working files are gone.
    [ "$(ls "${kept%/Dockerfile}")" = "Dockerfile" ]
    rm -rf "${kept%/Dockerfile}"

    # Renamed (an ordinary file): the failure is in the staged copy, and the
    # Dockerfile is byte-identical, with no staged file left beside it.
    rm -f Dockerfile "$SCRATCH/real/other-name"
    multi_stage_with_former_block
    local before
    before="$(cksum < Dockerfile)"
    PATH="$SCRATCH/bin:$PATH" run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"it was left as it was"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]
    [ -z "$(ls | grep 'env-dockerfile-render' || true)" ]

    # In place, and not writable: refused before the file is emptied. Root
    # can write any file, so there this is not tested.
    [ "$(id -u)" -ne 0 ] || return 0
    mv Dockerfile "$SCRATCH/real/Dockerfile"
    chmod 444 "$SCRATCH/real/Dockerfile"
    ln -s real/Dockerfile Dockerfile
    run "$RENDER" export.json
    chmod 644 "$SCRATCH/real/Dockerfile"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot write Dockerfile; it was left as it was"* ]]
    [ "$(cksum < "$SCRATCH/real/Dockerfile")" = "$before" ]
}

@test "a temporary directory that cannot hold the new Dockerfile never reaches the real one: an awk that exits 0 on a cut-off write is caught" {
    export_json ACME_WEB_SITE_URL null
    multi_stage_with_former_block
    local before real_awk
    before="$(cksum < Dockerfile)"
    real_awk="$(command -v awk)"
    mkdir -p "$SCRATCH/bin"
    # BusyBox awk on a full disk: the file is cut off and the exit status is
    # 0 (measured on alpine:3.24 by the §127 round-4 review). Stood in for
    # here by an awk that writes two lines and exits 0 when its output is a
    # file, and is the real awk when its output is a pipe.
    printf '#!/bin/sh\nif [ -p /dev/stdout ]; then exec "%s" "$@"; fi\n"%s" "$@" | sed -n 1,2p\nexit 0\n' "$real_awk" "$real_awk" > "$SCRATCH/bin/awk"
    chmod +x "$SCRATCH/bin/awk"

    PATH="$SCRATCH/bin:$PATH" run "$RENDER" export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not be written whole to the temporary directory"*"nothing was written"* ]]
    [ "$(cksum < Dockerfile)" = "$before" ]

    # --check must not call the cut-off copy "out of date" either.
    PATH="$SCRATCH/bin:$PATH" run "$RENDER" --check export.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not be written whole"* ]]
    [[ "$output" != *"out of date"* ]]

    # Control: with the real awk the same input is rewritten.
    run "$RENDER" export.json
    [ "$status" -eq 0 ]
    grep -qx 'ARG ACME_WEB_SITE_URL' Dockerfile
    grep -qx 'COPY --from=build /app/dist /usr/share/nginx/html' Dockerfile
}

@test "end to end: init's notice stops once the script has taken the block over" {
    local proj="$SCRATCH/acme.web"
    mkdir -p "$proj"
    git -C "$proj" init -q -b main
    cat > "$proj/app.spec.yaml" <<'YAML'
env:
  - name: ACME_WEB_SITE_URL
    public: true
    framework_name: NEXT_PUBLIC_SITE_URL
YAML
    ( cd "$proj" && multi_stage_with_former_block && mv "$SCRATCH/Dockerfile" "$proj/Dockerfile" )
    local cli="$TEST_REPO_ROOT/scripts/manifest-cli.sh" err="$SCRATCH/err"

    ( cd "$proj" && HOME="$SCRATCH" "$cli" init repo --check ) >/dev/null 2>"$err" || true
    grep -qF 'ARG→ENV block in your Dockerfile' "$err"

    ( cd "$proj" && HOME="$SCRATCH" "$cli" status repo --env --json 2>/dev/null | "$RENDER" )
    grep -qx 'ENV NEXT_PUBLIC_SITE_URL=${ACME_WEB_SITE_URL}' "$proj/Dockerfile"

    ( cd "$proj" && HOME="$SCRATCH" "$cli" init repo --check ) >/dev/null 2>"$err" || true
    refute grep -qF 'ARG→ENV block in your Dockerfile' "$err"
}
