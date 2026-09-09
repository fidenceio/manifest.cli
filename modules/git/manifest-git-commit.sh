#!/bin/bash

# Manifest Git Commit Module — how Manifest writes a commit.
#
# One executor for every commit the CLI makes (TRACKER §82). Before it, the
# CLI committed at seven sites with seven shapes: one discarded both of git's
# streams and then GUESSED at the cause ("is git user.name/user.email
# configured?"), one printed "Committed" without checking, one let a refused
# commit fall through to a push that found nothing new and reported success.
# A pre-commit hook that said no was invisible at three of them. Whatever a
# hook or git prints on failure now reaches the operator, and the one line
# that follows it says why — from what git said, not from a guess.
#
# Facts that shaped this file, all measured (2026-09-08):
#   - git on macOS AUTO-DETECTS a committer identity from the account and
#     hostname and commits happily; only `-c user.useConfigOnly=true` makes a
#     missing identity fail. So "is user.name configured?" was usually the
#     wrong diagnosis on the platform it was written on and right only on
#     Linux — and a probe for a configured identity is wrong the same way:
#     it fires for every macOS repo that never set one, whatever the actual
#     cause. Identity is therefore read from git's OWN words in the captured
#     output ("Committer identity unknown", "Please tell me who you are", …);
#     the probe is the fallback only when nothing could be captured.
#   - When both a hook and the identity are wrong, git reports whichever it
#     checks first (measured: with useConfigOnly it dies on identity and the
#     hook never runs). The classifier reads git's text, so it names what git
#     named and does not depend on that order.
#   - git redirects a hook's stdout to its own stderr (measured, git 2.55), so
#     a hook's verdict — this repo's own "COMMIT BLOCKED" included — reaches
#     the operator only if stderr does. What hid it at the fleet root was
#     discarding BOTH streams. Both are captured here, to separate files, so
#     nothing is lost whichever stream git chose, and on success each is
#     replayed to the fd it came from — a hook's text stays on stderr, where
#     the ship log's capture and a `>/dev/null` caller expect it; git's own
#     summary stays on stdout.
#
# Sign-off follows git's OWN setting, format.signOff, so there is no Manifest
# key to learn. `git commit` itself does not read it (it is format-patch's
# default for -s — the documentation says so plainly), but it is the one place
# a git user already states "I sign off what I produce", and it resolves per
# repository like every git setting. A repository cannot REQUIRE it through
# Manifest; the hint printed on a sign-off-shaped rejection is what carries
# that requirement to the operator, and it prints only then.
#
# Never `--no-verify`, anywhere. Never a retry: a commit is a local operation
# and a hook that refused will refuse again.

# Several modules source this file so their tests can load them alone.
if [[ -n "${_MANIFEST_CLI_GIT_COMMIT_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_GIT_COMMIT_LOADED=1

# manifest_git_commit REPO SUBJECT [BODY]
#
# Commits whatever is staged in REPO with SUBJECT (and BODY as a second
# paragraph when given). Returns:
#   0  committed; what git printed was replayed, each stream to its own fd
#   3  nothing staged — `git commit` never ran, nothing was printed
#   5  `git commit` exited non-zero; everything it and its hooks printed was
#      replayed to STDERR (so a `$( )` caller cannot swallow it, and so the
#      ship log's stderr capture carries it), followed by one classified line
#   1  bad arguments
manifest_git_commit() {
    local repo="${1:-}" subject="${2:-}" body="${3:-}"
    if [[ -z "$repo" || -z "$subject" ]]; then
        log_error "manifest_git_commit: a repository path and a subject are required."
        return 1
    fi

    # Nothing staged is not a failure and does not deserve git's complaint.
    if git -C "$repo" diff --cached --quiet 2>/dev/null; then
        return 3
    fi

    local signoff=false
    _manifest_git_commit_signoff_wanted "$repo" && signoff=true

    local -a args=(-m "$subject")
    [[ -n "$body" ]] && args+=(-m "$body")
    [[ "$signoff" == "true" ]] && args+=(--signoff)

    # Capture each stream to its own scratch file (a hook's refusal is usually
    # on stdout; its warnings on stderr). Same fallback as _manifest_ship_step:
    # when no scratch file can be made, let git speak live rather than lose it.
    local scratch="" out="" err="" rc=0 out_text="" err_text="" captured=false
    scratch="$(manifest_make_scratch_path git-commit 2>/dev/null || true)"
    if [[ -n "$scratch" ]]; then
        out="$(mktemp "$scratch/commit.out.XXXXXXXX" 2>/dev/null || true)"
        err="$(mktemp "$scratch/commit.err.XXXXXXXX" 2>/dev/null || true)"
    fi
    # Message language pinned to English so the classifier below can read
    # git's own words (a German git says "Identität des Autors unbekannt").
    # LANGUAGE wins over LC_ALL in GNU gettext, LC_MESSAGES covers the no-LC_ALL
    # case; LC_CTYPE is deliberately left alone so a hook still runs in the
    # operator's character locale (the §81 lesson: LC_ALL=C changes what
    # counts as printable).
    if [[ -n "$out" && -n "$err" ]]; then
        captured=true
        LANGUAGE=C LC_MESSAGES=C git -C "$repo" commit "${args[@]}" >"$out" 2>"$err" || rc=$?
        out_text="$(cat "$out" 2>/dev/null || true)"
        err_text="$(cat "$err" 2>/dev/null || true)"
    else
        LANGUAGE=C LC_MESSAGES=C git -C "$repo" commit "${args[@]}" || rc=$?
    fi
    rm -f "$out" "$err" 2>/dev/null || true

    if [[ "$rc" -eq 0 ]]; then
        # Success: each stream back to the fd it came from, as git printed it.
        if [[ -n "$out_text" ]]; then _manifest_git_commit_replay "$out_text" 1; fi
        if [[ -n "$err_text" ]]; then _manifest_git_commit_replay "$err_text" 2; fi
        return 0
    fi

    # Failure: everything to stderr, stdout's text first, then stderr's.
    if [[ -n "$out_text" ]]; then _manifest_git_commit_replay "$out_text" 2; fi
    if [[ -n "$err_text" ]]; then _manifest_git_commit_replay "$err_text" 2; fi
    _manifest_git_commit_explain_failure "$repo" "$rc" "$captured" "${out_text}"$'\n'"${err_text}" "$signoff"
    return 5
}

# Does the operator want a Signed-off-by trailer? Git's own format.signOff,
# resolved for REPO (repo-local wins over global, as with every git setting).
# `--type=bool` canonicalises every spelling git accepts (true/yes/on/1).
_manifest_git_commit_signoff_wanted() {
    local repo="$1" v
    v="$(git -C "$repo" config --type=bool --get format.signOff 2>/dev/null || true)"
    [[ "$v" == "true" ]]
}

# Replay captured git/hook output line by line to fd $2 (1 or 2), through the
# redactor when it is loaded — parity with log_error, which routes through it.
_manifest_git_commit_replay() {
    local text="$1" fd="${2:-2}" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if declare -F manifest_redact >/dev/null 2>&1; then
            line="$(manifest_redact "$line")"
        fi
        if [[ "$fd" == "1" ]]; then
            printf '%s\n' "$line"
        else
            printf '%s\n' "$line" >&2
        fi
    done <<<"$text"
}

# The directory git will read hooks from for REPO, absolute; honours
# core.hooksPath. Empty when it cannot be determined.
_manifest_git_commit_hooks_dir() {
    local repo="$1" dir
    dir="$(git -C "$repo" rev-parse --path-format=absolute --git-path hooks 2>/dev/null || true)"
    if [[ -z "$dir" ]]; then
        dir="$(git -C "$repo" rev-parse --git-path hooks 2>/dev/null || true)"
        [[ -n "$dir" && "$dir" != /* ]] && dir="$repo/$dir"
    fi
    printf '%s' "$dir"
}

# Print the hooks directory and return 0 when a hook that can refuse a commit
# is installed there; return 1 otherwise.
_manifest_git_commit_has_commit_hook() {
    local repo="$1" dir h
    dir="$(_manifest_git_commit_hooks_dir "$repo")"
    [[ -n "$dir" ]] || return 1
    for h in pre-commit prepare-commit-msg commit-msg pre-merge-commit; do
        if [[ -x "$dir/$h" ]]; then
            printf '%s' "$dir"
            return 0
        fi
    done
    return 1
}

# Did git's own output say the identity was the problem? These are git's exact
# phrasings (builtin/commit.c, ident.c); matched with bash's regex, not a
# pipe into grep -q — a producer feeding an early-exiting consumer is §9.27(b)'s
# SIGPIPE class, and under pipefail a match could read as a miss.
_manifest_git_commit_text_names_identity() {
    local text="$1"
    [[ "$text" =~ (Author|Committer)\ identity\ unknown|Please\ tell\ me\ who\ you\ are|empty\ ident\ name|no\ email\ was\ given|unable\ to\ auto-detect ]]
}

# Did a rejection mention a sign-off (DCO)? Case-insensitive via a lowered copy.
_manifest_git_commit_text_mentions_signoff() {
    local lower="${1,,}"
    [[ "$lower" =~ signed-off-by|sign-?off|(^|[^a-z])dco([^a-z]|$) ]]
}

# Say WHY a commit failed, from evidence. $1 repo, $2 git's exit code,
# $3 whether the output was captured (true|false), $4 the captured text,
# $5 whether --signoff was passed.
#
# Order: identity first, but only when git SAID so — no hook fix helps until
# that is set, and git names it unmistakably. Then a hook, named by the
# directory git actually reads so the operator knows which file said no.
# Then git itself.
_manifest_git_commit_explain_failure() {
    local repo="$1" rc="$2" captured="$3" text="$4" signoff="$5"
    local where="above"
    if [[ "$captured" != "true" ]]; then
        where="printed live above (it could not be captured)"
    elif [[ -z "${text//[[:space:]]/}" ]]; then
        where="empty: git printed nothing"
    fi

    local identity=false
    if [[ "$captured" == "true" ]]; then
        _manifest_git_commit_text_names_identity "$text" && identity=true
    elif ! git -C "$repo" -c user.useConfigOnly=true var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
        # Nothing captured to read: the probe is the best remaining evidence.
        identity=true
    fi
    if [[ "$identity" == "true" ]]; then
        log_error "Commit in $repo failed (git exited $rc): no git identity is configured. Set it once — git config --global user.name 'Your Name' && git config --global user.email 'you@example.com' — or export GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL. Its output is $where."
        return 0
    fi

    local hooks_dir
    if hooks_dir="$(_manifest_git_commit_has_commit_hook "$repo")"; then
        log_error "Commit in $repo was rejected (git exited $rc) with a hook active at $hooks_dir; the hook's output is $where."
        if [[ "$signoff" != "true" ]] && _manifest_git_commit_text_mentions_signoff "$text"; then
            log_warning "That hook appears to require a sign-off. Set once — git config --global format.signOff true — and Manifest passes --signoff on every commit it writes."
        fi
        return 0
    fi

    log_error "Commit in $repo failed (git exited $rc); its output is $where."
    return 0
}
