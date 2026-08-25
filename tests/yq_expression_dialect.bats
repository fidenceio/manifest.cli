#!/usr/bin/env bats

# TRACKER §2(c) follow-on — THE yq DIALECT TRAP.
#
# THE DEFECT THIS FILE EXISTS FOR. The first cut of the §2(c) sequence-join fix
# was written in jq syntax:
#
#     if <cond> then <join> else <sentinel> end
#
# mikefarah yq v4 has no `if/then/else/end`. Two properties turned that typo
# into a repo-wide outage rather than a bug in one branch:
#
#   1. yq LEXES THE EXPRESSION BEFORE IT READS THE DOCUMENT. The program was
#      rejected on every file, not only on the sequences it was written for:
#          $ echo 'a: 1' | yq e 'if true then 1 else 2 end' -
#          Error: 1:1: lexer: invalid input text "if true then 1 e..."
#   2. Every call site swallowed the failure — `2>/dev/null`, `|| value=""`,
#      `return 1` into a fallback. Nothing printed. Nothing exited non-zero.
#
# Measured blast radius: `_load_yaml_to_env_batch` returned 1 on every config
# load, so the §8.4f one-walk fast path (~130 yq spawns -> 1) was dead; the
# per-key fallback's join failed into `|| value=""`, the empty value was
# refused by _manifest_yaml_export_mapped_value, and a configured list silently
# fell back to a module built-in; the two refusal branches downstream became
# unreachable dead code.
#
# WHY THE SUITE DID NOT NOTICE, which is the part that generalizes. Every
# assertion was written against a value the built-in default ALSO satisfied, so
# "the loader exported nothing" and "the loader exported the right thing" were
# indistinguishable. A test can only catch what its fixture can distinguish.
#
# WHAT THIS FILE GUARDS, and how it avoids repeating that mistake.
#
#   A. Every yq program in modules/ is ENUMERATED from source and handed to the
#      real yq to PARSE. Not a syntax eyeball, not a blacklist of jq keywords
#      (`if`, `try`, `reduce`, `empty`, `foreach`, ... — a blacklist only ever
#      catches the mistakes someone already made). yq itself is the oracle.
#
#   B. The parse probe is `yq -n 'select(false) | ( <expr> )'`. `select(false)`
#      yields no results, so the right-hand side of the pipe is PARSED and never
#      EVALUATED. Exit 0 therefore means exactly "this program parses", with no
#      dependence on error-message wording: an expression that would explode at
#      evaluation (`.a | join(",")` against a non-array) still passes, and only a
#      lexer/parser rejection fails. Both directions are pinned by the control
#      tests below, because a probe that says "no" to everything and a probe that
#      says "yes" to everything both read as a green suite.
#
#   C. The extractor is cross-checked against an INDEPENDENT grep, and both
#      sides are required to be non-trivial. A guard whose enumerator silently
#      goes blind finds nothing to check and prints a pass — the same failure
#      shape as the original bug. That test is the one that stops it.
#
#   D. The skip count is PINNED and printed. Skips are the guard's honest cost;
#      an unpinned skip list is how coverage evaporates one commit at a time.
#
#   E. An end-to-end positive control plants the historical jq-dialect
#      expression in a throwaway module tree and requires the whole chain
#      (extract -> substitute -> parse) to go RED on it.
#
# COVERAGE AND ITS LIMITS, stated exactly.
#
#   Covered: every `yq` invocation in modules/**/*.sh standing in command
#   position, including expressions assembled from adjacent quoted segments
#   (modules/core/manifest-yaml.sh:866 splices a shell constant into the middle
#   of a single-quoted program, and a lexer that stopped at the first closing
#   quote would check only the harmless first third of it).
#
#   Shell interpolation is handled by expanding the captured word with bash's
#   own rules, after seeding the referenced names:
#     * an ALL-CAPS $NAME that is set once the modules are loaded expands to its
#       REAL value. This is what makes the check meaningful rather than
#       decorative: _MANIFEST_YAML_SEQ_JOIN_EXPR — the constant that carried the
#       original bug — is a module-level ALL-CAPS constant, so the composed
#       program at manifest-yaml.sh:1024 is parsed with the genuine text in it.
#     * $NAME written as an array subscript, `[$NAME]`, becomes 0.
#     * every other $NAME becomes the literal `PLACEHOLDER`, which is a valid
#       yq path segment. This checks the expression's SHAPE, not the caller's
#       runtime path — and a dialect error survives placeholder substitution,
#       which is what this guard is for.
#
#   Skipped, counted, printed, and pinned: an expression word that is nothing
#   but a variable (`yq e "$yaml_path"` — parse_yaml_config takes the whole
#   program from its caller, so there is no static text to check); a word
#   containing a command substitution (never evaluated here, on purpose); and an
#   ALL-CAPS constant that the loaded module stack does not define.
#
#   NOT covered: expressions built in scripts/, install-cli.sh, or tests/;
#   whether an expression is CORRECT (only that it parses — behaviour is pinned
#   separately, below, for the one expression whose behaviour is load-bearing).

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    load_modules
    SCRATCH="$(mk_scratch)"
}

# ===========================================================================
# The parse probe
# ===========================================================================

# Exit 0 <=> the expression PARSES under the installed yq. `select(false)`
# produces no results, so the piped right-hand side is never evaluated.
yq_expr_parses() {
    yq -n "select(false) | ( $1 )" >/dev/null 2>&1
}

yq_expr_error() {
    yq -n "select(false) | ( $1 )" 2>&1 | head -1 || true
}

# ===========================================================================
# Extractor: yq invocations -> verbatim shell-word source
#
# A bash source file is lexed one line at a time with a quote /
# command-substitution state machine, so the `yq` inside `log_error "yq is
# installed but ..."` is ignored while the one inside `x="$(yq e '.a' f)"` is
# not, and `manifest_requirement_yq_is_supported yq` is ignored because that
# `yq` is an argument rather than a command. The expression argument is then
# read as a whole shell WORD, so adjacent quoted segments concatenate.
#
# Results land in the parallel arrays _YQ_FILE / _YQ_LINE / _YQ_KIND / _YQ_RAW.
# _YQ_RAW is verbatim source, quotes retained, so bash can expand it later
# under its own rules instead of this file reimplementing them.
# ===========================================================================

# Resumable word reader. Returns 0 when the word is complete, 1 when an
# unterminated quote means it continues on the next line.
_yq_word_build() {
    local c
    while (( _YQ_P < _YQ_LEN )); do
        c="${_YQ_S:_YQ_P:1}"
        if [[ "$_YQ_WQ" == "'" ]]; then
            _YQ_RAWW="$_YQ_RAWW$c"; _YQ_P=$(( _YQ_P + 1 ))
            if [[ "$c" == "'" ]]; then _YQ_WQ=""; fi
            continue
        fi
        if [[ "$_YQ_WQ" == '"' ]]; then
            if [[ "$c" == '\' ]]; then
                _YQ_RAWW="$_YQ_RAWW$c${_YQ_S:_YQ_P+1:1}"; _YQ_P=$(( _YQ_P + 2 )); continue
            fi
            if [[ "$c" == '$' ]]; then _YQ_EXPAND=1; fi
            _YQ_RAWW="$_YQ_RAWW$c"; _YQ_P=$(( _YQ_P + 1 ))
            if [[ "$c" == '"' ]]; then _YQ_WQ=""; fi
            continue
        fi
        case "$c" in
            ' '|$'\t'|';'|'|'|'&'|'>'|'<'|')'|'(')
                return 0 ;;
            "'")
                _YQ_WQ="'"; _YQ_RAWW="$_YQ_RAWW$c"; _YQ_P=$(( _YQ_P + 1 )); continue ;;
            '"')
                _YQ_WQ='"'; _YQ_RAWW="$_YQ_RAWW$c"; _YQ_P=$(( _YQ_P + 1 )); continue ;;
            '\')
                _YQ_RAWW="$_YQ_RAWW$c${_YQ_S:_YQ_P+1:1}"; _YQ_P=$(( _YQ_P + 2 )); continue ;;
            '$')
                _YQ_EXPAND=1 ;;
        esac
        _YQ_RAWW="$_YQ_RAWW$c"; _YQ_P=$(( _YQ_P + 1 ))
    done
    if [[ -n "$_YQ_WQ" ]]; then _YQ_RAWW="$_YQ_RAWW"$'\n'; return 1; fi
    return 0
}

# Skip flags and the eval subcommand, then read the expression word (across
# lines if it is an unterminated quote) and record it.
_yq_take_arg() {
    local file="$1" startline="$2" c tok j
    while : ; do
        while (( _YQ_P < _YQ_LEN )) && [[ "${_YQ_S:_YQ_P:1}" == " " || "${_YQ_S:_YQ_P:1}" == $'\t' ]]; do
            _YQ_P=$(( _YQ_P + 1 ))
        done
        if (( _YQ_P >= _YQ_LEN )); then return 1; fi
        c="${_YQ_S:_YQ_P:1}"
        if [[ "$c" == "-" && "${_YQ_S:_YQ_P+1:1}" == [[:alnum:]-] ]]; then
            while (( _YQ_P < _YQ_LEN )) && [[ "${_YQ_S:_YQ_P:1}" != " " && "${_YQ_S:_YQ_P:1}" != $'\t' ]]; do
                _YQ_P=$(( _YQ_P + 1 ))
            done
            continue
        fi
        tok=""; j=$_YQ_P
        while (( j < _YQ_LEN )) && [[ "${_YQ_S:j:1}" != " " && "${_YQ_S:j:1}" != $'\t' ]]; do
            tok="$tok${_YQ_S:j:1}"; j=$(( j + 1 ))
        done
        case "$tok" in
            e|eval|ea|eval-all) _YQ_P=$j; continue ;;
        esac
        break
    done

    _YQ_RAWW=""; _YQ_EXPAND=0; _YQ_WQ=""
    while : ; do
        if _yq_word_build; then break; fi
        _YQ_I=$(( _YQ_I + 1 ))
        if (( _YQ_I >= ${#_YQ_SRC[@]} )); then break; fi
        _YQ_S="${_YQ_SRC[_YQ_I]}"; _YQ_LEN=${#_YQ_S}; _YQ_P=0
    done

    _YQ_FILE+=( "$file" )
    _YQ_LINE+=( "$startline" )
    if (( _YQ_EXPAND )); then _YQ_KIND+=( exp ); else _YQ_KIND+=( lit ); fi
    _YQ_RAW+=( "$_YQ_RAWW" )
    return 0
}

_yq_walk_line() {
    local file="$1" c w st cmdpos depth
    local -a stack=()
    st="NORMAL"; cmdpos=1; depth=0
    while (( _YQ_P < _YQ_LEN )); do
        c="${_YQ_S:_YQ_P:1}"
        if [[ "$st" == "SQ" ]]; then
            if [[ "$c" == "'" ]]; then depth=$(( depth - 1 )); st="${stack[depth]}"; fi
            _YQ_P=$(( _YQ_P + 1 )); continue
        fi
        if [[ "$st" == "DQ" ]]; then
            if [[ "$c" == '\' ]]; then _YQ_P=$(( _YQ_P + 2 )); continue; fi
            if [[ "$c" == '$' && "${_YQ_S:_YQ_P+1:1}" == "(" ]]; then
                stack[depth]="DQ"; depth=$(( depth + 1 )); st="NORMAL"; cmdpos=1
                _YQ_P=$(( _YQ_P + 2 )); continue
            fi
            if [[ "$c" == '"' ]]; then depth=$(( depth - 1 )); st="${stack[depth]}"; fi
            _YQ_P=$(( _YQ_P + 1 )); continue
        fi
        case "$c" in
            '\')
                _YQ_P=$(( _YQ_P + 2 )); continue ;;
            "'")
                stack[depth]="NORMAL"; depth=$(( depth + 1 )); st="SQ"
                _YQ_P=$(( _YQ_P + 1 )); continue ;;
            '"')
                stack[depth]="NORMAL"; depth=$(( depth + 1 )); st="DQ"
                _YQ_P=$(( _YQ_P + 1 )); continue ;;
            '$')
                if [[ "${_YQ_S:_YQ_P+1:1}" == "(" ]]; then
                    stack[depth]="NORMAL"; depth=$(( depth + 1 )); cmdpos=1
                    _YQ_P=$(( _YQ_P + 2 )); continue
                fi ;;
            '(')
                stack[depth]="NORMAL"; depth=$(( depth + 1 )); cmdpos=1
                _YQ_P=$(( _YQ_P + 1 )); continue ;;
            ')')
                if (( depth > 0 )); then depth=$(( depth - 1 )); st="${stack[depth]}"; fi
                cmdpos=0; _YQ_P=$(( _YQ_P + 1 )); continue ;;
            ';'|'|'|'&'|'{'|'!')
                cmdpos=1; _YQ_P=$(( _YQ_P + 1 )); continue ;;
            '#')
                if (( _YQ_P == 0 )); then return 0; fi
                if [[ "${_YQ_S:_YQ_P-1:1}" == " " || "${_YQ_S:_YQ_P-1:1}" == $'\t' ]]; then return 0; fi ;;
        esac
        if [[ "$c" == [[:alnum:]_] ]]; then
            w=""
            while (( _YQ_P < _YQ_LEN )) && [[ "${_YQ_S:_YQ_P:1}" == [[:alnum:]_./+=-] ]]; do
                w="$w${_YQ_S:_YQ_P:1}"; _YQ_P=$(( _YQ_P + 1 ))
            done
            if [[ "$w" == "yq" ]] && (( cmdpos == 1 )); then
                _yq_take_arg "$file" "$(( _YQ_I + 1 ))" || true
                cmdpos=0
                continue
            fi
            # `FOO=bar yq ...` keeps command position, and so do the keywords
            # that can precede a command (`if ! yq ...`, `while yq ...`).
            if [[ "$w" == *= ]]; then cmdpos=1; continue; fi
            case "$w" in
                'if'|'then'|'else'|'elif'|'do'|'while'|'until'|'time'|'fi'|'done'|'esac'|'in'|'case'|'for'|'function')
                    cmdpos=1; continue ;;
            esac
            cmdpos=0
            continue
        fi
        _YQ_P=$(( _YQ_P + 1 ))
    done
    return 0
}

_yq_extract_file() {
    local file="$1" line trimmed n idx skip_until term j t
    local hd_re="<<-?[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)"
    local -a cand=()
    _YQ_SRC=()
    mapfile -t _YQ_SRC < "$file"
    n=${#_YQ_SRC[@]}

    # Only lines that could matter are lexed. Lexing all 33k lines of modules/
    # in bash costs ~30s per scan; grep narrows it to ~100 lines per file, and
    # the extractor/grep cross-check above is what proves the narrowing did not
    # lose anything.
    mapfile -t cand < <(grep -n -E 'yq|<<' "$file" | cut -d: -f1)

    skip_until=-1
    for idx in "${cand[@]}"; do
        _YQ_I=$(( idx - 1 ))
        if (( _YQ_I <= skip_until )); then continue; fi
        line="${_YQ_SRC[_YQ_I]}"
        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ "$trimmed" == "#"* ]]; then continue; fi
        if [[ "$line" == *yq* ]]; then
            _YQ_S="$line"; _YQ_LEN=${#line}; _YQ_P=0
            _yq_walk_line "$file"
            # a multi-line expression word consumed further lines
            if (( _YQ_I > skip_until )); then skip_until=$_YQ_I; fi
        fi
        if [[ "$line" =~ $hd_re ]]; then
            term="${BASH_REMATCH[1]}"
            j=$(( _YQ_I + 1 ))
            while (( j < n )); do
                t="${_YQ_SRC[j]}"; t="${t#"${t%%[![:space:]]*}"}"
                if [[ "$t" == "$term" ]]; then break; fi
                j=$(( j + 1 ))
            done
            if (( j > skip_until )); then skip_until=$j; fi
        fi
    done
}

_yq_extract_tree() {
    local root="$1"
    local recfile="$SCRATCH/yq-records.nul"

    # The lexer runs in a SUBSHELL with bats's DEBUG trap detached. bats
    # instruments every simple command to report failing line numbers, which
    # turns this character loop from ~1s into ~10s; the trap is restored for
    # free when the subshell exits, and nothing inside here is an assertion.
    (
        trap - DEBUG
        set +T
        local file
        _YQ_FILE=(); _YQ_LINE=(); _YQ_KIND=(); _YQ_RAW=()
        while IFS= read -r file; do
            _yq_extract_file "$file"
        done < <(find "$root" -name '*.sh' -type f | LC_ALL=C sort)
        local k
        for (( k = 0; k < ${#_YQ_FILE[@]}; k++ )); do
            printf '%s\0%s\0%s\0%s\0' \
                "${_YQ_FILE[k]}" "${_YQ_LINE[k]}" "${_YQ_KIND[k]}" "${_YQ_RAW[k]}"
        done
    ) > "$recfile"

    _YQ_FILE=(); _YQ_LINE=(); _YQ_KIND=(); _YQ_RAW=()
    local field n=0
    while IFS= read -r -d '' field; do
        case $(( n % 4 )) in
            0) _YQ_FILE+=( "$field" ) ;;
            1) _YQ_LINE+=( "$field" ) ;;
            2) _YQ_KIND+=( "$field" ) ;;
            3) _YQ_RAW+=( "$field" ) ;;
        esac
        n=$(( n + 1 ))
    done < "$recfile"
    if (( n % 4 != 0 )); then
        printf 'yq extractor emitted a truncated record stream (%s fields)\n' "$n" >&2
        return 1
    fi
    return 0
}

# ===========================================================================
# Scanner: expand each recorded word, then parse-probe it.
#
# Sets YQ_TOTAL / YQ_CHECKED / YQ_SKIPPED / YQ_FAILED / YQ_RESOLVED and the
# two human-readable reports. Returns 1 if any covered expression fails.
# ===========================================================================
yq_scan_tree() {
    local _yqroot="$1"
    _yq_extract_tree "$_yqroot"

    YQ_TOTAL=${#_YQ_FILE[@]}
    YQ_CHECKED=0; YQ_SKIPPED=0; YQ_FAILED=0; YQ_RESOLVED=0
    YQ_SKIP_REPORT=""; YQ_FAIL_REPORT=""

    local _yqn _yqraw _yqexpr _yqbare _yqids _yqid _yqwhere _yqbad _yqmissing
    for (( _yqn = 0; _yqn < YQ_TOTAL; _yqn++ )); do
        _yqraw="${_YQ_RAW[_yqn]}"
        _yqwhere="${_YQ_FILE[_yqn]#"$_yqroot"/}:${_YQ_LINE[_yqn]}"

        # Never evaluated here: a command substitution inside the expression
        # word would run module code from a test that only means to read it.
        if [[ "$_yqraw" == *'$('* || "$_yqraw" == *'`'* ]]; then
            YQ_SKIPPED=$(( YQ_SKIPPED + 1 ))
            YQ_SKIP_REPORT="${YQ_SKIP_REPORT}    ${_yqwhere}  command substitution in the expression word"$'\n'
            continue
        fi

        # The whole program comes from the caller at runtime; there is no
        # static text here to parse.
        _yqbare="${_yqraw//\"/}"; _yqbare="${_yqbare//\'/}"
        if [[ "$_yqbare" =~ ^[[:space:]]*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?[[:space:]]*$ ]]; then
            YQ_SKIPPED=$(( YQ_SKIPPED + 1 ))
            YQ_SKIP_REPORT="${YQ_SKIP_REPORT}    ${_yqwhere}  expression supplied wholly at runtime: ${_yqraw}"$'\n'
            continue
        fi

        _yqbad=""; _yqmissing=""
        if [[ "${_YQ_KIND[_yqn]}" == "exp" ]]; then
            _yqids="$(printf '%s' "$_yqraw" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' | tr -d '${}' | LC_ALL=C sort -u || true)"
            for _yqid in $_yqids; do
                # This scanner's own state must never be a substitution target.
                if [[ "$_yqid" == _YQ_* || "$_yqid" == _yq* || "$_yqid" == YQ_* ]]; then
                    _yqbad="$_yqid"; break
                fi
                if [[ "$_yqid" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
                    if [[ -n "${!_yqid:-}" ]]; then
                        YQ_RESOLVED=$(( YQ_RESOLVED + 1 ))
                        continue
                    fi
                    _yqmissing="$_yqmissing $_yqid"
                    continue
                fi
                if [[ "$_yqraw" == *"[\$$_yqid]"* || "$_yqraw" == *"[\${$_yqid}"* ]]; then
                    printf -v "$_yqid" '%s' 0 || _yqbad="$_yqid"
                else
                    printf -v "$_yqid" '%s' PLACEHOLDER || _yqbad="$_yqid"
                fi
            done
        fi
        if [[ -n "$_yqbad" ]]; then
            YQ_SKIPPED=$(( YQ_SKIPPED + 1 ))
            YQ_SKIP_REPORT="${YQ_SKIP_REPORT}    ${_yqwhere}  cannot seed \$${_yqbad}"$'\n'
            continue
        fi
        if [[ -n "$_yqmissing" ]]; then
            YQ_SKIPPED=$(( YQ_SKIPPED + 1 ))
            YQ_SKIP_REPORT="${YQ_SKIP_REPORT}    ${_yqwhere}  module constant not defined by the loaded stack:${_yqmissing}"$'\n'
            continue
        fi

        _yqexpr=""
        eval "_yqexpr=$_yqraw" 2>/dev/null || _yqexpr=""
        if [[ -z "$_yqexpr" ]]; then
            # A loud failure, never a silent skip: an expression word that will
            # not expand is an extractor defect, and an extractor defect is
            # exactly the thing that makes this guard read green while blind.
            YQ_CHECKED=$(( YQ_CHECKED + 1 ))
            YQ_FAILED=$(( YQ_FAILED + 1 ))
            YQ_FAIL_REPORT="${YQ_FAIL_REPORT}    ${_yqwhere}  expression word did not expand: ${_yqraw}"$'\n'
            continue
        fi

        YQ_CHECKED=$(( YQ_CHECKED + 1 ))
        if yq_expr_parses "$_yqexpr"; then continue; fi
        YQ_FAILED=$(( YQ_FAILED + 1 ))
        YQ_FAIL_REPORT="${YQ_FAIL_REPORT}    ${_yqwhere}"$'\n'"        expr: $(printf '%s' "$_yqexpr" | tr '\n' ' ')"$'\n'"        yq:   $(yq_expr_error "$_yqexpr")"$'\n'
    done

    if (( YQ_FAILED > 0 )); then return 1; fi
    return 0
}

# ===========================================================================
# A. the enumerator must not go blind
# ===========================================================================

@test "yq expression extractor sees every yq invocation an independent grep sees" {
    _yq_extract_tree "$TEST_REPO_ROOT/modules"

    local mine="$SCRATCH/from-extractor.txt" theirs="$SCRATCH/from-grep.txt"
    local n
    for (( n = 0; n < ${#_YQ_FILE[@]}; n++ )); do
        printf '%s:%s\n' "${_YQ_FILE[n]}" "${_YQ_LINE[n]}"
    done | LC_ALL=C sort -u > "$mine"

    # `grep -r --include` is a GNU extension the Alpine test image's BusyBox
    # grep does not have; find + xargs is the portable spelling.
    find "$TEST_REPO_ROOT/modules" -name '*.sh' -type f -print0 \
        | xargs -0 grep -Hn -E '(^|[^A-Za-z0-9_./-])yq[[:blank:]]+(e|ea|eval|eval-all|-)' \
        | grep -v -E ':[0-9]+:[[:blank:]]*#' \
        | cut -d: -f1,2 | LC_ALL=C sort -u > "$theirs"

    local mine_n theirs_n
    mine_n="$(wc -l < "$mine" | tr -d ' ')"
    theirs_n="$(wc -l < "$theirs" | tr -d ' ')"

    # Both sides non-trivial: two blind enumerators agree perfectly, and that
    # agreement would otherwise read as a pass.
    if (( mine_n < 40 )); then
        printf 'extractor found only %s yq invocations in modules/ — it has gone blind\n' "$mine_n" >&2
        return 1
    fi
    if (( theirs_n < 40 )); then
        printf 'grep found only %s yq invocation lines in modules/ — the cross-check has gone blind\n' "$theirs_n" >&2
        return 1
    fi

    if diff -u "$theirs" "$mine" > "$SCRATCH/diff.txt"; then return 0; fi
    printf 'extractor and grep disagree about which lines invoke yq:\n' >&2
    cat "$SCRATCH/diff.txt" >&2
    return 1
}

# ===========================================================================
# B. the guard itself
# ===========================================================================

@test "every yq expression in modules/ parses under the installed yq" {
    if yq_scan_tree "$TEST_REPO_ROOT/modules"; then
        echo "# yq expressions in modules/: total=$YQ_TOTAL parsed=$YQ_CHECKED skipped=$YQ_SKIPPED (module constants resolved: $YQ_RESOLVED)" >&3
        return 0
    fi
    printf 'yq expressions that do NOT parse under yq %s:\n%s\n' \
        "$(yq --version)" "$YQ_FAIL_REPORT" >&2
    printf 'checked=%s skipped=%s failed=%s of total=%s\n' \
        "$YQ_CHECKED" "$YQ_SKIPPED" "$YQ_FAILED" "$YQ_TOTAL" >&2
    return 1
}

@test "the guard's skip list is exactly the one known dynamic expression" {
    yq_scan_tree "$TEST_REPO_ROOT/modules" || true

    echo "# yq guard skips: $YQ_SKIPPED of $YQ_TOTAL" >&3

    # Pinned deliberately. A guard that quietly stops checking things reads
    # identical to a guard that checks everything, so a new skip must be looked
    # at by a person rather than absorbed into the number.
    if (( YQ_SKIPPED != 1 )); then
        printf 'expected exactly 1 skipped yq expression, got %s:\n%s' "$YQ_SKIPPED" "$YQ_SKIP_REPORT" >&2
        printf 'If the new skip is legitimate, add it here with its reason.\n' >&2
        return 1
    fi
    if [[ "$YQ_SKIP_REPORT" != *"manifest-yaml.sh"*"supplied wholly at runtime"* ]]; then
        printf 'the one permitted skip changed identity:\n%s' "$YQ_SKIP_REPORT" >&2
        return 1
    fi
    # parse_yaml_config takes the whole program from its caller. Its callers'
    # programs are ordinary path expressions built at run time.
    [ "$YQ_CHECKED" -ge 50 ]
}

# ===========================================================================
# C. controls — a probe that always says yes and a probe that always says no
#    are both indistinguishable from a passing guard
# ===========================================================================

@test "positive control: the parse probe REJECTS the jq-dialect ternary" {
    # The exact shape of the shipped defect.
    local jq_dialect
    jq_dialect='if ([.[] | select(tag == "!!map" or tag == "!!seq")] | length) == 0'
    jq_dialect="$jq_dialect then join(\",\") else \"${_MANIFEST_YAML_SEQ_UNREPRESENTABLE}\" end"

    refute yq_expr_parses "$jq_dialect"

    # ... and for the documented reason, not some incidental one.
    run yq -n "$jq_dialect"
    [ "$status" -ne 0 ]
    [[ "$output" == *"lexer"* ]] || {
        printf 'expected a lexer rejection, got: %s\n' "$output" >&2
        return 1
    }
}

@test "positive control: other jq-only spellings are rejected too" {
    local bad
    for bad in 'try .a catch 1' 'reduce .[] as $x (0; . + $x)' '.a // empty' \
               'foreach .[] as $x (0; . + $x)' 'if . then 1 end'; do
        refute yq_expr_parses "$bad"
    done
}

@test "negative control: the parse probe ACCEPTS an expression that parses but cannot evaluate" {
    # `join` on a non-array is a runtime error, not a syntax error. If the probe
    # rejected this it would be measuring evaluation, and every guard result
    # above would be meaningless.
    run yq -n '.a | join(",")'
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot join"* ]]

    yq_expr_parses '.a | join(",")'
}

@test "positive control: the whole guard goes RED on a module carrying a jq-dialect expression" {
    local badtree="$SCRATCH/badmodules/core"
    mkdir -p "$badtree"
    {
        printf '#!/usr/bin/env bash\n'
        printf '_fake_reader() {\n'
        printf '    local f="$1"\n'
        printf '    yq e -r ".k | if ([.[] | select(tag == \\"!!map\\")] | length) == 0'
        printf ' then join(\\",\\") else \\"SENTINEL\\" end" "$f" 2>/dev/null\n'
        printf '}\n'
    } > "$badtree/manifest-fake.sh"

    refute yq_scan_tree "$SCRATCH/badmodules"

    # The chain must have gone red for the right reason: the expression was
    # found, expanded, and rejected — not skipped, and not missed.
    [ "$YQ_TOTAL" -eq 1 ]
    [ "$YQ_CHECKED" -eq 1 ]
    [ "$YQ_SKIPPED" -eq 0 ]
    [ "$YQ_FAILED" -eq 1 ]
    [[ "$YQ_FAIL_REPORT" == *"manifest-fake.sh"* ]]
    [[ "$YQ_FAIL_REPORT" == *"lexer"* ]]
}

@test "positive control: a scan of a clean throwaway module tree passes" {
    # The complement of the test above — proves the red run came from the
    # expression, not from anything about scanning a scratch tree.
    local goodtree="$SCRATCH/goodmodules/core"
    mkdir -p "$goodtree"
    {
        printf '#!/usr/bin/env bash\n'
        printf '_fake_reader() {\n'
        printf '    yq e -r ".k | join(\\",\\")" "$1" 2>/dev/null\n'
        printf '}\n'
    } > "$goodtree/manifest-fake.sh"

    yq_scan_tree "$SCRATCH/goodmodules"
    [ "$YQ_TOTAL" -eq 1 ]
    [ "$YQ_CHECKED" -eq 1 ]
    [ "$YQ_FAILED" -eq 0 ]
}

# ===========================================================================
# D. _MANIFEST_YAML_SEQ_JOIN_EXPR — behaviour, not only syntax
#
# This is the expression that carried the original defect. A parse check alone
# would have caught the shipped bug, but it would not catch a rewrite that
# parses and means something else, so every branch is pinned by observation.
# ===========================================================================

# Runs the join expression against a one-key document, exactly as
# load_yaml_to_env's per-key path does (manifest-yaml.sh:1024).
seq_join() {
    printf '%s' "$1" > "$SCRATCH/seq.yaml"
    yq e -r ".k | ${_MANIFEST_YAML_SEQ_JOIN_EXPR}" "$SCRATCH/seq.yaml"
}

@test "_MANIFEST_YAML_SEQ_JOIN_EXPR is defined and parses under the real yq" {
    [ -n "$_MANIFEST_YAML_SEQ_JOIN_EXPR" ]
    [ -n "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]
    yq_expr_parses "$_MANIFEST_YAML_SEQ_JOIN_EXPR"
    # It is a yq ternary built from select + the alternative operator, which is
    # the whole point: there is no if/then/else to reach for.
    [[ "$_MANIFEST_YAML_SEQ_JOIN_EXPR" == *"select("* ]]
    [[ "$_MANIFEST_YAML_SEQ_JOIN_EXPR" == *"//"* ]]
    refute grep -q "then" <<<"$_MANIFEST_YAML_SEQ_JOIN_EXPR"
}

@test "_MANIFEST_YAML_SEQ_JOIN_EXPR joins a flat scalar list to the comma form" {
    run seq_join $'k:\n  - .env\n  - mysecret.txt\n  - third\n'
    [ "$status" -eq 0 ]
    [ "$output" = ".env,mysecret.txt,third" ]

    # flow spelling means the same thing
    run seq_join $'k: [.env, mysecret.txt, third]\n'
    [ "$status" -eq 0 ]
    [ "$output" = ".env,mysecret.txt,third" ]

    # a one-element list is the element
    run seq_join $'k:\n  - only\n'
    [ "$status" -eq 0 ]
    [ "$output" = "only" ]
}

@test "_MANIFEST_YAML_SEQ_JOIN_EXPR yields the sentinel for a list containing a map" {
    run seq_join $'k:\n  - .env\n  - name: nested\n'
    [ "$status" -eq 0 ]
    [ "$output" = "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]

    run seq_join $'k:\n  - a: 1\n  - b: 2\n'
    [ "$status" -eq 0 ]
    [ "$output" = "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]
}

@test "_MANIFEST_YAML_SEQ_JOIN_EXPR yields the sentinel for a list containing a nested list" {
    run seq_join $'k:\n  - .env\n  - - nested_a\n    - nested_b\n'
    [ "$status" -eq 0 ]
    [ "$output" = "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]

    run seq_join $'k: [a, [b, c]]\n'
    [ "$status" -eq 0 ]
    [ "$output" = "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]
}

@test "_MANIFEST_YAML_SEQ_JOIN_EXPR yields empty — NOT the sentinel — for an empty list" {
    # The edge case the alternative operator is chosen for. An empty list HAS a
    # comma encoding (the empty string), so it must join to "" and be treated as
    # absent by _manifest_yaml_export_mapped_value, not refused as malformed.
    run seq_join $'k: []\n'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$output" != "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]
}

@test "yq's alternative operator treats empty string as a value, which the empty-list case rests on" {
    # `select(cond)` yields nothing when cond is false and `//` supplies the
    # sentinel then; an empty list makes the select SUCCEED and join to "", and
    # `// sentinel` must not fire on that "". If a future yq made "" falsy to
    # `//`, the empty-list case above would silently become a loud refusal.
    run yq -n '"" // "fallback"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run yq -n 'null // "fallback"'
    [ "$status" -eq 0 ]
    [ "$output" = "fallback" ]
}

@test "the sentinel cannot be produced by the join branch of a scalar list" {
    # The sentinel is only ever compared against this expression's output, so
    # the sole collision is a one-element list holding the sentinel text itself,
    # whose consequence is a loud refusal rather than a silent narrowing.
    run seq_join $'k:\n  - a\n  - b\n'
    [ "$status" -eq 0 ]
    [ "$output" != "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]

    # The sentinel has to be QUOTED to be a value at all: unquoted, `!!...` is
    # YAML tag syntax, so the only way a user can even write the colliding
    # document is the quoted form.
    printf 'k:\n  - "%s"\n' "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" > "$SCRATCH/collide.yaml"
    run yq e -r '.k[0] | tag' "$SCRATCH/collide.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "!!str" ]

    run yq e -r ".k | ${_MANIFEST_YAML_SEQ_JOIN_EXPR}" "$SCRATCH/collide.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "$_MANIFEST_YAML_SEQ_UNREPRESENTABLE" ]
}
