#!/bin/bash

# Manifest Driver Detection Module (TRACKER §78)
#
# Records WHO is driving this CLI invocation — a human at a terminal, a CI
# runner, or an AI coding agent — so that non-safety defaults can be chosen for
# them. Modelled on manifest-os.sh: a named detector with an enumerated result
# and one shared function, rather than detection logic inlined at a call site.
#
# WHAT THIS IS NOT, and the boundary is the whole design:
#
#   - It is NOT a safety control and must never gate one. Every signal below is
#     *claimed* by whatever is running — an environment variable anyone can
#     export, a process name anyone can choose — and none of it is
#     authenticated. Branching a guard on it would make a trust decision out of
#     an unverified assertion.
#   - It NEVER selects a program to run. §44 restricts config-named programs to
#     layers the operator owns precisely so that nothing else gets to choose
#     what executes during a ship; a detector that picked an agent binary off
#     PATH would turn "the user configured a command" into "Manifest chose a
#     program for you", which is the same defect wearing a different hat.
#   - An unrecognised state resolves to `none`, never to a guess. Treating an
#     absent signal as a value is TRACKER §6.
#
# Its one consumer today is docs.handoff (modules/docs/manifest-handoff.sh),
# where the verdict decides whether `auto` pauses the ship for the driver to
# finish the documentation. It also supplies a disclosure line and a `driver=`
# field for the ship log, both of which are descriptive only.
#
# LAZY BY CONSTRUCTION. detect_os() runs at module-source time, which is right
# for `uname`. This one may walk the process tree with `ps`, so it runs only
# when something asks. Do NOT add a source-time call at the foot of this file.

# The verdict. One of: none | ci | claude-code | other-agent
MANIFEST_CLI_DRIVER="${MANIFEST_CLI_DRIVER:-}"
# The agent's name even when the verdict is `ci` (an agent inside a pipeline).
MANIFEST_CLI_DRIVER_AGENT_HINT=""
# Comma-separated tokens naming the signals that fired, for disclosure. Never a
# value — only which variable or ancestor was present, so nothing secret leaks
# into a printed, logged, pasted-into-an-issue line.
MANIFEST_CLI_DRIVER_EVIDENCE=""
# true only when BOTH stdin and stdout are terminals.
MANIFEST_CLI_DRIVER_INTERACTIVE=""

# Every verdict this module can produce. A named agent is added here only
# together with a measured row in tests/fixtures/driver-census.tsv — "establish
# by running, not by reading" (§78).
_MANIFEST_CLI_DRIVER_VALUES="none ci claude-code other-agent"

# CI markers, in no particular order: the verdict is `ci` if ANY is non-empty.
# CI outranks an agent deliberately. A pipeline must never be paused for a
# driver to type something (§71), and an agent running inside CI is still a
# pipeline. The agent name survives in MANIFEST_CLI_DRIVER_AGENT_HINT.
_MANIFEST_CLI_DRIVER_CI_VARS="CI GITHUB_ACTIONS GITLAB_CI BUILDKITE CIRCLECI JENKINS_URL TF_BUILD"

# How many ancestors to examine before giving up. A ship runs a handful of
# levels below its shell; 16 is far past any real chain and bounds the loop
# against a cycle in a PID table we do not control.
#
# Overridable, and 0 disables the walk entirely. This is a TEST knob, not a
# config key, and it exists because of a measured problem: this suite is itself
# often run BY an agent, so the CLI's process really is a descendant of
# `claude`. A test asserting the scrubbed-environment verdict is `none` would
# then pass in CI and fail on a maintainer's machine — the walk would keep
# finding a true ancestor after the environment had been emptied. Tests that
# isolate the environment-signal path set this to 0; the ancestry path has its
# own test that builds a controlled chain.
_MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS="${MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS:-16}"
case "$_MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS" in
    ''|*[!0-9]*) _MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=16 ;;
esac

manifest_driver_is_valid_value() {
    case " $_MANIFEST_CLI_DRIVER_VALUES " in
        *" ${1:-} "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Append one evidence token, comma-separated.
_manifest_driver_add_evidence() {
    local token="$1"
    [ -n "$token" ] || return 0
    if [ -z "$MANIFEST_CLI_DRIVER_EVIDENCE" ]; then
        MANIFEST_CLI_DRIVER_EVIDENCE="$token"
    else
        MANIFEST_CLI_DRIVER_EVIDENCE="${MANIFEST_CLI_DRIVER_EVIDENCE},$token"
    fi
}

# The parent PID of $1, or empty. /proc first: BusyBox `ps` (Alpine, and the
# containerized test runner) has no `-p` and no `-o`, so a `ps`-only reader
# returns nothing there and every ancestry check would silently pass as "no
# agent" — a vacuous zero of exactly the kind TRACKER warns about.
_manifest_driver_parent_pid() {
    local pid="$1" ppid=""
    if [ -r "/proc/$pid/stat" ]; then
        # Field 4 is ppid, but field 2 (comm) is parenthesised and may contain
        # spaces, so count from the LAST ')' rather than splitting the whole
        # line: "1234 (Code Helper (Plugin)) S 987 ..." breaks a naive $4.
        local stat rest
        stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
        rest="${stat##*) }"
        ppid="${rest#* }"
        ppid="${ppid%% *}"
    else
        ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
    fi
    case "$ppid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s' "$ppid"
}

# The command name of $1, basename only, or empty.
_manifest_driver_command_name() {
    local pid="$1" comm=""
    if [ -r "/proc/$pid/comm" ]; then
        comm="$(cat "/proc/$pid/comm" 2>/dev/null)" || return 1
    else
        comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
    fi
    comm="${comm##*/}"
    comm="${comm#-}"        # a login shell reports itself as "-zsh"
    [ -n "$comm" ] || return 1
    printf '%s' "$comm"
}

# Walk the ancestry looking for a known agent process. Echoes the verdict, or
# nothing. Any unreadable step ends the walk quietly: a partial answer is
# correct here (we learn nothing), an error is not.
_manifest_driver_from_ancestry() {
    local pid="${BASHPID:-$$}" hops=0 comm
    local max="${MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS:-$_MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS}"
    case "$max" in
        ''|*[!0-9]*) max="$_MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS" ;;
    esac
    while [ "$hops" -lt "$max" ]; do
        pid="$(_manifest_driver_parent_pid "$pid")" || return 0
        [ "$pid" -gt 1 ] 2>/dev/null || return 0
        comm="$(_manifest_driver_command_name "$pid")" || return 0
        case "$comm" in
            claude)
                printf '%s' "claude-code"
                return 0
                ;;
        esac
        hops=$((hops + 1))
    done
    return 0
}

# Resolve who is driving. Idempotent: a second call is a no-op, matching
# detect_os's guard, so a ship that consults the policy repeatedly forks `ps`
# at most once.
detect_driver() {
    if [ -n "${MANIFEST_CLI_DRIVER_DETECTED:-}" ]; then
        return 0
    fi

    local verdict="" hint="" override="${MANIFEST_CLI_DRIVER:-}"
    MANIFEST_CLI_DRIVER_EVIDENCE=""
    MANIFEST_CLI_DRIVER_AGENT_HINT=""

    if [ -t 0 ] && [ -t 1 ]; then
        MANIFEST_CLI_DRIVER_INTERACTIVE="true"
    else
        MANIFEST_CLI_DRIVER_INTERACTIVE="false"
    fi

    # (1) Operator override, from the process environment only. Deliberately
    # NOT a config key: a committed file travels with a clone, and a repository
    # must not get to assert who is driving the machine that cloned it.
    if [ -n "$override" ]; then
        if manifest_driver_is_valid_value "$override"; then
            MANIFEST_CLI_DRIVER="$override"
            _manifest_driver_add_evidence "override"
            MANIFEST_CLI_DRIVER_DETECTED=1
            return 0
        fi
        # Not coerced into a verdict (§6): say so and fall through to detection.
        if declare -F log_warning >/dev/null 2>&1; then
            log_warning "Ignoring MANIFEST_CLI_DRIVER='$override': expected one of $_MANIFEST_CLI_DRIVER_VALUES."
        fi
        MANIFEST_CLI_DRIVER=""
    fi

    # (2) Agent evidence is gathered BEFORE the CI verdict is applied, so that
    # an agent inside a pipeline is still named in the hint.
    if [ -n "${CLAUDECODE:-}" ]; then
        hint="claude-code"
        _manifest_driver_add_evidence "env:CLAUDECODE"
    elif [ -n "${AI_AGENT:-}" ]; then
        # A generic marker some agents export. The value names the agent, but it
        # is free text from the environment, so it never becomes a verdict of
        # its own — `other-agent` is the honest enumeration.
        hint="other-agent"
        _manifest_driver_add_evidence "env:AI_AGENT"
    fi

    # (3) CI wins the verdict outright.
    local ci_var
    for ci_var in $_MANIFEST_CLI_DRIVER_CI_VARS; do
        if [ -n "${!ci_var:-}" ]; then
            _manifest_driver_add_evidence "env:$ci_var"
            verdict="ci"
            break
        fi
    done

    # (4) No CI: the agent evidence above decides, else walk the process tree.
    if [ -z "$verdict" ]; then
        if [ -n "$hint" ]; then
            verdict="$hint"
        else
            verdict="$(_manifest_driver_from_ancestry)"
            if [ -n "$verdict" ]; then
                _manifest_driver_add_evidence "ancestry:claude"
                hint="$verdict"
            fi
        fi
    fi

    [ -n "$verdict" ] || verdict="none"

    # MANIFEST_CLI_DRIVER is BOTH the operator's override input (read at the
    # top of this function) and the computed verdict written here. That is
    # deliberate — one name for "who is driving", whoever decided it — and it
    # is safe only for as long as nothing EXPORTS it: a child would then read a
    # parent's computed verdict as an explicit override and stop detecting for
    # itself, which in a fleet means every member inheriting the root's answer.
    # Measured 2026-09-10: `git grep -n "export MANIFEST_CLI_DRIVER"` matches
    # test fixtures only, so nothing exports it today. Do not start; if a child
    # ever needs the parent's verdict, pass it under a separate name.
    MANIFEST_CLI_DRIVER="$verdict"
    # The hint is only interesting when it says something the verdict does not.
    if [ -n "$hint" ] && [ "$hint" != "$verdict" ]; then
        MANIFEST_CLI_DRIVER_AGENT_HINT="$hint"
    fi
    MANIFEST_CLI_DRIVER_DETECTED=1
    return 0
}

# True when the driver is an AI agent that could act on a handoff brief.
manifest_driver_is_agent() {
    detect_driver
    case "$MANIFEST_CLI_DRIVER" in
        claude-code|other-agent) return 0 ;;
        *) return 1 ;;
    esac
}

# One human-readable line naming the driver and how it was decided. Used by the
# handoff disclosure and the ship log; never parsed.
manifest_driver_describe() {
    detect_driver
    local out="$MANIFEST_CLI_DRIVER"
    [ -n "$MANIFEST_CLI_DRIVER_AGENT_HINT" ] && out="$out (agent: $MANIFEST_CLI_DRIVER_AGENT_HINT)"
    [ -n "$MANIFEST_CLI_DRIVER_EVIDENCE" ] && out="$out via $MANIFEST_CLI_DRIVER_EVIDENCE"
    [ "$MANIFEST_CLI_DRIVER_INTERACTIVE" = "true" ] && out="$out; terminal attached"
    printf '%s' "$out"
}

export -f detect_driver manifest_driver_is_agent manifest_driver_describe \
    manifest_driver_is_valid_value
