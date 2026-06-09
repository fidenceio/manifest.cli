#!/usr/bin/env bash
# Manifest CLI test runner.
# Requires bats-core: brew install bats-core (or https://github.com/bats-core/bats-core)
# Requires the same Bash major version as the CLI.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"
# shellcheck disable=SC1091
source "$REPO_ROOT/modules/core/manifest-requirements.sh"

# Bash 3.2 (Apple's default /bin/bash) silently mangles 'declare -A' and array
# subscripts, producing cryptic "syntax error" lines. Surface the real cause
# upfront so contributors don't waste time chasing parser ghosts.
if ! manifest_requirement_current_bash_is_supported; then
    echo "Bash ${BASH_VERSION} is too old. Manifest CLI and its tests require Bash ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+."
    echo "On macOS: brew install bash, then ensure /opt/homebrew/bin is first in PATH."
    exit 2
fi

# bats's '#!/usr/bin/env bash' shebang resolves to whatever bash is first on
# PATH. If macOS has Homebrew's bash but command lookup still lands on
# /bin/bash 3.2, prepend the Homebrew bin so bats itself runs under the required Bash.
if [[ -x /opt/homebrew/bin/bash ]] && [[ "$(command -v bash 2>/dev/null || true)" != "/opt/homebrew/bin/bash" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
elif [[ -x /usr/local/bin/bash ]] && [[ "$(command -v bash 2>/dev/null || true)" != "/usr/local/bin/bash" ]] && manifest_requirement_bash_is_supported_major "$(manifest_requirement_bash_major_from_command /usr/local/bin/bash)"; then
    export PATH="/usr/local/bin:$PATH"
fi

if ! command -v bats >/dev/null 2>&1; then
    echo "bats is not installed."
    echo "Install: brew install bats-core"
    echo "         or: https://github.com/bats-core/bats-core#installation"
    exit 2
fi

if [ ! -d "$TESTS_DIR" ]; then
    echo "tests/ directory not found at $TESTS_DIR"
    exit 2
fi

# --tier selects a test subset by native bats tag (§5.10 layered test-cost
# reduction). Default is the full suite — the safety invariant is that nothing
# merges to main or releases without a full run, so 'full' must be the fallback.
#   smoke — safety-contract suites tagged `# bats file_tags=smoke`
#   full  — the entire suite
#
# --jobs N|auto runs bats test files in parallel (§5.10). Default is 'auto'
# (detected CPU count). bats parallelism is built on GNU parallel, which is a
# REQUIRED test dependency (provided by the test container; on a host install it
# with `brew install parallel` / `apk add parallel`). A parallel run with GNU
# parallel missing is a hard error, not a silent serial downgrade — that would
# misreport how the suite ran. `--jobs 1` is the explicit serial escape hatch and
# needs no parallel.
#
# --changed runs only the tests mapped to what changed on this branch (§5.10
# change-aware selection), always unioning the smoke tier. The changed set is
# `git diff` vs `git merge-base HEAD origin/main` (plus untracked files), or — for
# CI, which already has the PR's file list — whatever is passed in
# MANIFEST_CLI_TEST_CHANGED_PATHS (space/newline-separated; honored even when
# empty). Mapping lives in tests/coverage-map.tsv. It is FAIL-SAFE to the full
# suite: an unmapped path, any modules/core/* or tests/helpers/* change, a change
# to the map itself, or an undeterminable base all force full. A changed test file
# runs itself; a docs-only change runs smoke. The narrowed-vs-full decision is
# logged loudly to stderr so a reduced run is never silent. --changed is a
# convenience for local/CI-PR pre-checks ONLY — push-to-main and the release gate
# still run full; nothing merges or releases on a narrowed run. Cannot combine with
# explicit test-file arguments.
#
# --cache / --no-cache control the TTL'd green-run cache (§5.10). After a run
# passes, run-tests.sh records a fingerprint of the test-relevant tree (modules/
# + tests/ + this script, plus the bats version) keyed by the run's scope (tier +
# selected files). On a later run whose fingerprint matches AND falls inside the
# window, the run is SKIPPED and reported as a cache hit. The cache only ever
# skips work that already passed for byte-identical inputs; ANY doubt — no marker,
# unreadable fingerprint, an unparseable window, a scope or content mismatch — is
# a miss and runs the tests. The window comes from
# MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN (config key test.skip_unchanged_within),
# default 4h; values like 30m / 90s / 2d / off are accepted. Caching is on by
# default; --no-cache forces a run (the release gate passes --no-cache, so nothing
# ever releases on a cached result). Markers live under .test-cache/ (gitignored),
# overridable via MANIFEST_CLI_TEST_CACHE_DIR.
#
# --print-cmd prints the resolved bats invocation and exits without running it
# (operability + the testable seam: lets the suite assert the plan, not execute it).
# --print-cache-key prints the resolved cache fingerprint and exits (the cache
# analogue of that seam).
#
# --progress / --no-progress emit a lightweight "N/TOTAL (pct%)" line to stderr at
# each 10% boundary as tests complete — a cheap progress indicator for the long
# full suite. TAP on stdout is unchanged. Off by default; MANIFEST_CLI_TEST_PROGRESS=1
# defaults it on.
#
# Any remaining args pass through to bats (e.g. explicit test files to run).
TIER="full"
JOBS="auto"
PRINT_CMD=0
PRINT_CACHE_KEY=0
CHANGED=0
CACHE_ENABLED=1
# --progress prints a lightweight "N/TOTAL (pct%)" milestone line to stderr at
# each 10% boundary as tests complete — a cheap "how far along are we" indicator
# for the long full suite. Off by default (keeps CI/gate logs and the TAP stream
# on stdout untouched); set MANIFEST_CLI_TEST_PROGRESS=1 to default it on, or pass
# --progress / --no-progress per run. It only counts TAP lines — no extra compute.
PROGRESS=0
case "${MANIFEST_CLI_TEST_PROGRESS:-}" in 1|true|on|yes) PROGRESS=1 ;; esac
BATS_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tier)
            TIER="${2:-}"
            shift 2 || { echo "--tier requires an argument (smoke|full)"; exit 2; }
            ;;
        --tier=*)
            TIER="${1#--tier=}"
            shift
            ;;
        --jobs|-j)
            JOBS="${2:-}"
            shift 2 || { echo "--jobs requires an argument (a positive integer or 'auto')"; exit 2; }
            ;;
        --jobs=*)
            JOBS="${1#--jobs=}"
            shift
            ;;
        --changed)
            CHANGED=1
            shift
            ;;
        --cache)
            CACHE_ENABLED=1
            shift
            ;;
        --no-cache)
            CACHE_ENABLED=0
            shift
            ;;
        --progress)
            PROGRESS=1
            shift
            ;;
        --no-progress)
            PROGRESS=0
            shift
            ;;
        --print-cmd)
            PRINT_CMD=1
            shift
            ;;
        --print-cache-key)
            PRINT_CACHE_KEY=1
            shift
            ;;
        *)
            BATS_ARGS+=("$1")
            shift
            ;;
    esac
done

FILTER=()
case "$TIER" in
    full)
        : # no tag filter — run everything
        ;;
    smoke)
        # Native tag filtering needs bats >= 1.8.0. Fail loud rather than
        # silently running the full suite, which would misreport what ran.
        if ! bats --help 2>&1 | grep -q -- '--filter-tags'; then
            echo "This bats ($(bats --version 2>&1)) lacks --filter-tags; the 'smoke' tier needs bats >= 1.8.0."
            echo "Install a newer bats-core, or run the full tier."
            exit 2
        fi
        FILTER=(--filter-tags smoke)
        ;;
    *)
        echo "Unknown --tier '$TIER'. Expected: smoke | full."
        exit 2
        ;;
esac

# Resolve --jobs into PARALLEL=(), the flags handed to bats. 'auto' resolves to
# the detected CPU count. A resolved count of 1 means serial (no parallel flags,
# no GNU-parallel dependency); a count > 1 requires GNU parallel.
PARALLEL=()
if [ "$JOBS" = "auto" ]; then
    if command -v nproc >/dev/null 2>&1; then
        JOBS="$(nproc 2>/dev/null)"
    elif command -v sysctl >/dev/null 2>&1; then
        JOBS="$(sysctl -n hw.ncpu 2>/dev/null)"
    fi
    # Single-core or undetectable → serial. Not an error: there's nothing to
    # parallelize across, so GNU parallel isn't needed.
    [ -n "$JOBS" ] && [ "$JOBS" -ge 1 ] 2>/dev/null || JOBS=1
fi

case "$JOBS" in
    ''|*[!0-9]*)
        echo "--jobs requires a positive integer or 'auto' (got '$JOBS')."
        exit 2
        ;;
esac
if [ "$JOBS" -lt 1 ]; then
    echo "--jobs must be >= 1 (got '$JOBS')."
    exit 2
fi

if [ "$JOBS" -gt 1 ]; then
    # GNU parallel is a required test dependency for parallel runs. Fail loud
    # rather than silently downgrade to serial, which would misreport what ran.
    # (manifest_requirement_parallel_is_gnu rejects moreutils' same-named binary.)
    if ! manifest_requirement_parallel_is_gnu; then
        echo "GNU parallel is required for parallel test runs (--jobs $JOBS) but was not found."
        echo "Install it:  brew install parallel   (macOS)"
        echo "             apk add parallel         (Alpine / the test container)"
        echo "             apt-get install parallel (Debian/Ubuntu)"
        echo "Or run serially with: $(basename "$0") --jobs 1"
        exit 2
    fi
    PARALLEL=(--jobs "$JOBS")
fi

if [ "${#BATS_ARGS[@]}" -gt 0 ]; then
    TARGET=("${BATS_ARGS[@]}")
else
    TARGET=("$TESTS_DIR")
fi

# --- §5.10 change-aware selection (--changed) ------------------------------
COVERAGE_MAP="$TESTS_DIR/coverage-map.tsv"

_changed_log() { echo "[changed] $*" >&2; }

# Smoke-tagged test files (the safety contract), always unioned into a narrowed
# run. file_tags applies the tag to every test in the file, so running the file
# is exactly the smoke tier for that file.
_smoke_files() {
    grep -l 'file_tags=smoke' "$TESTS_DIR"/*.bats 2>/dev/null | sort
}

# The changed-path set. CI already knows the PR's changed files, so an explicit
# MANIFEST_CLI_TEST_CHANGED_PATHS (set, even if empty) wins and skips git.
# Otherwise diff the working tree against the merge-base with origin/main and add
# untracked files. Exit 1 means the base is undeterminable → caller fails to full.
_changed_paths() {
    if [ -n "${MANIFEST_CLI_TEST_CHANGED_PATHS+x}" ]; then
        printf '%s\n' $MANIFEST_CLI_TEST_CHANGED_PATHS
        return 0
    fi
    local base
    base="$(git -C "$REPO_ROOT" merge-base HEAD origin/main 2>/dev/null)" || true
    [ -n "$base" ] || return 1
    {
        git -C "$REPO_ROOT" diff --name-only "$base" 2>/dev/null
        git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null
    }
}

# Echoes either the literal "FULL" (run the whole suite) or a newline-separated
# list of absolute test-file paths to run. All rationale goes to stderr.
_resolve_changed_selection() {
    local changed
    if ! changed="$(_changed_paths)"; then
        _changed_log "fail-safe -> FULL: cannot determine changed paths (no merge-base with origin/main)"
        echo "FULL"; return 0
    fi
    changed="$(printf '%s\n' "$changed" | awk 'NF' | sort -u)"
    if [ -z "$changed" ]; then
        _changed_log "no changed paths; running smoke tier only"
        _smoke_files; return 0
    fi

    local selected reason="" f glob files tf hit
    selected="$(_smoke_files)"   # smoke is always unioned
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            modules/core/*)        reason="core module changed: $f"; break ;;
            tests/helpers/*)       reason="test helper changed: $f"; break ;;
            tests/coverage-map.tsv) reason="coverage map changed: $f"; break ;;
        esac
        case "$f" in
            docs/*|*.md|README*|LICENSE*|CHANGELOG*) continue ;;  # docs-only: no tests
            tests/*.bats) selected="$selected"$'\n'"$REPO_ROOT/$f"; continue ;;  # run the edited test
        esac
        hit=0
        while IFS=$'\t' read -r glob files; do
            case "$glob" in ''|\#*) continue ;; esac
            # shellcheck disable=SC2254
            if [[ "$f" == $glob ]]; then
                hit=1
                for tf in $files; do
                    selected="$selected"$'\n'"$TESTS_DIR/$tf"
                done
            fi
        done < "$COVERAGE_MAP"
        if [ "$hit" -eq 0 ]; then
            reason="unmapped path changed: $f"; break
        fi
    done <<EOF
$changed
EOF

    if [ -n "$reason" ]; then
        _changed_log "fail-safe -> FULL: $reason"
        echo "FULL"; return 0
    fi
    printf '%s\n' "$selected" | awk 'NF' | sort -u
}

if [ "$CHANGED" -eq 1 ]; then
    if [ "${#BATS_ARGS[@]}" -gt 0 ]; then
        echo "--changed cannot combine with explicit test files."
        exit 2
    fi
    if [ ! -f "$COVERAGE_MAP" ]; then
        echo "coverage map not found at $COVERAGE_MAP (required for --changed)."
        exit 2
    fi
    SELECTION="$(_resolve_changed_selection)"
    if [ "$SELECTION" = "FULL" ]; then
        TARGET=("$TESTS_DIR")
        FILTER=()   # --changed full fallback ignores any tier filter
        _changed_log "selection: FULL suite ($(find "$TESTS_DIR" -maxdepth 1 -name '*.bats' | wc -l | tr -d ' ') files)"
    else
        TARGET=()
        while IFS= read -r line; do
            [ -n "$line" ] && TARGET+=("$line")
        done <<EOF
$SELECTION
EOF
        FILTER=()   # selection is by file; smoke is already unioned in
        _changed_log "selection: ${#TARGET[@]} of $(find "$TESTS_DIR" -maxdepth 1 -name '*.bats' | wc -l | tr -d ' ') files (smoke unioned); full would run all"
        for line in "${TARGET[@]}"; do _changed_log "  run: ${line##*/}"; done
    fi
fi
# --- end change-aware selection --------------------------------------------

if [ "$PRINT_CMD" -eq 1 ]; then
    printf 'bats'
    printf ' %s' "${PARALLEL[@]}" "${FILTER[@]}" "${TARGET[@]}"
    printf '\n'
    exit 0
fi

# --- §5.10 TTL'd green-run cache (--cache / --no-cache) --------------------
# Skip a re-run when the exact test inputs already passed within the window.
# Fail-safe to running: a missing hash tool, empty fingerprint, unparseable
# window, or any mismatch is a cache MISS. Parallelism (--jobs) is deliberately
# excluded from the scope — it changes how the suite runs, not whether it passes.
CACHE_DIR="${MANIFEST_CLI_TEST_CACHE_DIR:-$REPO_ROOT/.test-cache}"
_HASH_CMD=""
if command -v sha256sum >/dev/null 2>&1; then _HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then _HASH_CMD="shasum -a 256"; fi

# A deterministic description of WHAT will run — tier plus the sorted basenames
# of the selected files. A narrowed --changed run therefore caches under a
# different key than the full suite, so a narrowed green can never satisfy a
# later full run (and vice versa).
_run_scope() {
    local t names=""
    for t in "${TARGET[@]}"; do names="$names ${t##*/}"; done
    names="$(printf '%s\n' $names | awk 'NF' | sort | tr '\n' ',')"
    printf 'tier=%s|targets=%s' "$TIER" "$names"
}

# Content fingerprint of the test-relevant tree + bats version + run scope.
# Paths are relative (cd into the repo) so the key is stable across checkouts.
_cache_fingerprint() {
    [ -n "$_HASH_CMD" ] || return 1
    {
        ( cd "$REPO_ROOT" 2>/dev/null && \
          find modules tests scripts/run-tests.sh -type f -print0 2>/dev/null \
          | sort -z | xargs -0 $_HASH_CMD 2>/dev/null )
        bats --version 2>/dev/null
        printf 'scope=%s\n' "$1"
    } | $_HASH_CMD | awk '{print $1}'
}

# Resolve the cache window to whole seconds. 0 = off; -1 = unparseable (caller
# warns and treats as off). Accepts <N>{s,m,h,d} or a bare integer (seconds).
_cache_window_seconds() {
    local raw n unit
    raw="$(printf '%s' "${MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN:-4h}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$raw" in ''|off|none|disabled|false) echo 0; return 0 ;; esac
    case "$raw" in
        *[0-9])        n="$raw";      unit="s" ;;   # bare integer → seconds
        *[0-9][smhd])  n="${raw%?}";  unit="${raw: -1}" ;;
        *)             echo -1; return 0 ;;
    esac
    case "$n" in ''|*[!0-9]*) echo -1; return 0 ;; esac
    case "$unit" in
        s) echo "$n" ;;
        m) echo $(( n * 60 )) ;;
        h) echo $(( n * 3600 )) ;;
        d) echo $(( n * 86400 )) ;;
        *) echo -1 ;;
    esac
}

if [ "$PRINT_CACHE_KEY" -eq 1 ]; then
    _cache_fingerprint "$(_run_scope)" || { echo "no hash tool (sha256sum/shasum) available for --print-cache-key" >&2; exit 2; }
    exit 0
fi

CACHE_WINDOW="$(_cache_window_seconds)"
CACHE_FP=""
if [ "$CACHE_ENABLED" -eq 1 ]; then
    if [ "$CACHE_WINDOW" -lt 0 ]; then
        echo "[cache] ignoring unrecognized test.skip_unchanged_within='${MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN:-}' — running (cache off). Use e.g. 4h, 30m, 90s, or off." >&2
        CACHE_WINDOW=0
    fi
    if [ "$CACHE_WINDOW" -gt 0 ]; then
        CACHE_FP="$(_cache_fingerprint "$(_run_scope)")" || CACHE_FP=""
        if [ -n "$CACHE_FP" ] && [ -f "$CACHE_DIR/$CACHE_FP" ]; then
            _stamp="$(cat "$CACHE_DIR/$CACHE_FP" 2>/dev/null)"
            case "$_stamp" in ''|*[!0-9]*) _stamp="" ;; esac
            if [ -n "$_stamp" ]; then
                _now="$(date +%s)"
                _age=$(( _now - _stamp ))
                if [ "$_age" -ge 0 ] && [ "$_age" -le "$CACHE_WINDOW" ]; then
                    echo "[cache] hit — green run $(( _age / 60 ))m ago is within the ${CACHE_WINDOW}s window; skipping (scope: $(_run_scope)). Use --no-cache to force a run." >&2
                    exit 0
                fi
                echo "[cache] stale — last green $(( _age / 60 ))m ago exceeds the ${CACHE_WINDOW}s window; running." >&2
            fi
        fi
    fi
fi

# Lightweight progress: pass every TAP line straight through to stdout (so the
# results stream and any consumer are untouched) while emitting a "N/TOTAL
# (pct%)" line to stderr at each 10% boundary. Pure line-counting in awk — no
# extra processes per test, no cursor control (renders the same piped or in a
# terminal). Total comes from TAP's `1..N` plan line; works with parallel runs
# since it counts completed `ok`/`not ok` lines regardless of order.
_progress_filter() {
    awk '
        BEGIN { next_ms = 10 }
        /^1\.\.[0-9]+$/ { total = substr($0, 4) + 0 }
        { print; fflush() }
        (/^ok / || /^not ok /) && total > 0 {
            completed++
            pct = int(completed * 100 / total)
            if (pct >= next_ms && next_ms < 100) {
                printf "  …running tests: %d/%d (%d%%)\n", completed, total, pct > "/dev/stderr"
                fflush("/dev/stderr")
                while (next_ms <= pct) next_ms += 10
            }
        }
        END { if (total > 0) printf "  …tests complete: %d/%d\n", completed, total > "/dev/stderr" }
    '
}

if [ "$PROGRESS" -eq 1 ]; then
    bats "${PARALLEL[@]}" "${FILTER[@]}" "${TARGET[@]}" | _progress_filter
    status=${PIPESTATUS[0]}
else
    bats "${PARALLEL[@]}" "${FILTER[@]}" "${TARGET[@]}"
    status=$?
fi
if [ "$status" -eq 0 ] && [ "$CACHE_ENABLED" -eq 1 ] && [ "$CACHE_WINDOW" -gt 0 ] && [ -n "$CACHE_FP" ]; then
    if mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s\n' "$(date +%s)" > "$CACHE_DIR/$CACHE_FP" 2>/dev/null; then
        echo "[cache] recorded green run (scope: $(_run_scope))." >&2
    fi
fi
exit "$status"
