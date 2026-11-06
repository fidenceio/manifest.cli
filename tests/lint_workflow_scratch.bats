#!/usr/bin/env bats
# bats file_tags=smoke

# The lint workflow's containers must never write into the bind-mounted repo.
# Scope: shell redirects (`>`, `>>`, any `N>`) and `tee` targets. A `cp` or
# `install` into /work would pass this guard — a lint step copying sources is
# not a scratch-file shape, and none of the three steps does it.
#
# Every ShellCheck step in .github/workflows/lint.yml runs inside a container
# with `-v "$PWD:/work" -w /work` — the repo itself is the working directory.
# Until TRACKER §88 all three steps built their file list with
# `find … -print0 > files.zero`, a redirect into that mount. On a GitHub runner
# the checkout is discarded, so nothing was ever noticed there; the exposure was
# a maintainer reproducing a lint failure locally by pasting the step's own
# `docker run` line, which left `files.zero` in the tree — where the release
# commit's bare `git add .` would stage it (§4). `.gitignore` was the backstop;
# this guard is the fix's keeper: the lists now live under /tmp, and a redirect
# into the working directory inside those containers is exactly greppable.
#
# Scope is the container scripts only — the text between `sh -lc '` and the
# closing quote — not the runner-side `run:` wrapper, where a redirect into
# `$GITHUB_OUTPUT` would be legitimate.

load 'helpers/setup'

LINT_YML() { printf '%s\n' "$TEST_REPO_ROOT/.github/workflows/lint.yml"; }

# The bodies of every `sh -lc '…'` container script in a workflow file, with a
# `--- container N ---` separator before each so a test can count them. Text
# after the opening quote on the marker line is part of the body — a one-line
# container (`sh -lc 'find … > files.zero; …'`) must not escape the check by
# never having a body line. Shell comment lines are dropped: a `>` in prose
# (the hard gate's "ShellCheck (>= 0.7)") is not a redirect. The quote is
# passed in with -v: a bash single-quoted awk program cannot contain one.
container_scripts() {
    awk -v q="'" '
        { m = index($0, "sh -lc " q) }
        m { n++; print "--- container " n " ---"
            rest = substr($0, m + 8)
            if (rest ~ q "[[:space:]]*$") { sub(q "[[:space:]]*$", "", rest); print rest; next }
            if (rest != "") print rest
            s = 1; next }
        s && $0 ~ "^[[:space:]]*" q "[[:space:]]*$" { s = 0; next }
        s && $0 ~ "^[[:space:]]*#" { next }
        s { print }
    ' "$1"
}

# Every target of a `>`/`>>` redirect or a `tee [-a]` in those scripts, one per
# line. `2>&1`-style descriptor duplication has no target and is not matched.
redirect_targets() {
    container_scripts "$1" \
        | grep -oE '(>>?\|?|(^|[|[:space:]])tee( -a)?)[[:space:]]*[^[:space:]&;|)]+' \
        | sed -E 's/^(>+\|?|[|[:space:]]?tee( -a)?)[[:space:]]*//'
}

# Targets that land on the mount: anything not rooted at /tmp or /dev. A bare
# relative name and an explicit /work/… are both refused.
offending_targets() {
    redirect_targets "$1" | grep -vE '^/(tmp|dev)/' || true
}

@test "lint workflow: no container step redirects into the bind-mounted repo" {
    local offenders
    offenders="$(offending_targets "$(LINT_YML)")"
    if [ -n "$offenders" ]; then
        printf 'redirects into the /work mount (write under /tmp instead):\n%s\n' "$offenders" >&2
        return 1
    fi
}

@test "control: the extractor sees all three container scripts and their redirects" {
    # A parser matching nothing would pass the test above vacuously. The
    # workflow has exactly three ShellCheck containers, and each builds a file
    # list by redirect, so both counts are non-zero on the real file.
    local scripts targets
    scripts="$(container_scripts "$(LINT_YML)" | grep -c '^--- container ')"
    [ "$scripts" -eq 3 ]
    targets="$(redirect_targets "$(LINT_YML)" | wc -l | tr -d ' ')"
    [ "$targets" -ge 3 ]
    # Every live target is the /tmp list the fix introduced.
    refute grep -vE '^/tmp/(test)?files\.zero$' <<<"$(redirect_targets "$(LINT_YML)")"
}

@test "mutation control: a relative redirect in one container is refused" {
    local mutant
    mutant="$BATS_TEST_TMPDIR/lint.yml"
    # Plant the pre-§88 shape: the list writes lose their /tmp/ prefix.
    sed -E 's#> /tmp/files\.zero#> files.zero#' "$(LINT_YML)" > "$mutant"
    grep -q '> files.zero' "$mutant"
    run offending_targets "$mutant"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    refute grep -vqx 'files.zero' <<<"$output"
}

@test "mutation control: an absolute redirect under /work is refused too" {
    local mutant
    mutant="$BATS_TEST_TMPDIR/lint.yml"
    sed -E 's#>> /tmp/testfiles\.zero#>> /work/testfiles.zero#' "$(LINT_YML)" > "$mutant"
    grep -q '/work/testfiles.zero' "$mutant"
    run offending_targets "$mutant"
    [ "$status" -eq 0 ]
    [ "$output" = "/work/testfiles.zero" ]
}

@test "mutation control: a one-line container with a relative redirect is refused" {
    # Found by review: the first extractor discarded the marker line's tail, so
    # a container with no body lines was counted (three containers, still) and
    # never read. Collapse the third step to one line carrying the pre-fix shape.
    local mutant
    mutant="$BATS_TEST_TMPDIR/lint.yml"
    awk -v q="'" '
        index($0, "sh -lc " q) { n++ }
        n == 3 && index($0, "sh -lc " q) {
            sub(q "$", q "find modules -name \"*.sh\" -print0 > files.zero; xargs -0 shellcheck < files.zero" q)
            print; skip = 1; next }
        skip && $0 ~ "^[[:space:]]*" q "[[:space:]]*$" { skip = 0; next }
        skip { next }
        { print }
    ' "$(LINT_YML)" > "$mutant"
    grep -q "print0 > files.zero; xargs" "$mutant"
    [ "$(container_scripts "$mutant" | grep -c '^--- container ')" -eq 3 ]
    run offending_targets "$mutant"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    refute grep -vqx 'files.zero' <<<"$output"
}

@test "mutation control: a tee into the working directory is refused" {
    # `… | tee warnings.txt` is the natural "show and keep" idiom for the
    # advisory step, and it is not a redirect.
    local mutant
    mutant="$BATS_TEST_TMPDIR/lint.yml"
    sed -E 's#(--severity=warning < /tmp/files\.zero)$#\1 | tee -a warnings.txt#' "$(LINT_YML)" > "$mutant"
    grep -q 'tee -a warnings.txt' "$mutant"
    run offending_targets "$mutant"
    [ "$status" -eq 0 ]
    [ "$output" = "warnings.txt" ]
}

@test "mutation control: a redirect in the runner-side wrapper is out of scope" {
    # The guard polices the container, not the step's `run:` shell on the
    # runner. A `$GITHUB_OUTPUT` append outside the quotes must not trip it.
    local mutant
    mutant="$BATS_TEST_TMPDIR/lint.yml"
    awk '{ print } /^          set -euo pipefail$/ { print "          echo ok >> \"$GITHUB_OUTPUT\"" }' \
        "$(LINT_YML)" > "$mutant"
    grep -q 'GITHUB_OUTPUT' "$mutant"
    run offending_targets "$mutant"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
