#!/usr/bin/env bats
# bats file_tags=smoke
#
# TRACKER §59 — the consent gate's closure must not leave this process.
#
# WHAT THIS PINS, and why the obvious fix is the wrong one.
#
# `manifest_repo_scope_confirm_apply` hard-calls
# `_manifest_repo_scope_auto_confirm_authorized`. For a while the gate was
# exported and the predicate was not, which reads like a bug with an obvious
# fix: export the predicate too. **That fix reopens §46.** In an exec'd child:
#
#   1. the predicate's `declare -F _manifest_config_auto_confirm_authorized`
#      probe misses -- manifest-config.sh exports no such function;
#   2. `_MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV`, the snapshot that records whether
#      consent came from the process environment, is `declare -g` and not -gx,
#      so the child does not inherit it;
#   3. the predicate therefore falls through to a live read of
#      `MANIFEST_CLI_AUTO_CONFIRM` -- which `manifest-yaml.sh:857` exports from
#      a repo's COMMITTED `manifest.config.yaml`.
#
# So a cloned repo's config would authorize an ambiguous apply in the child.
# That is §46 verbatim, which is why the fix is to stop exporting the gate
# rather than to start exporting the predicate.
#
# The gate's degradation while the closure was broken was fail-CLOSED, not
# fail-open: a missing function in an `if` condition exits 127, which is falsy,
# so control fell to the unambiguous-target branch and an ambiguous target was
# refused. §59's entry claimed the opposite ("falls through to reading
# MANIFEST_CLI_AUTO_CONFIRM live, i.e. exactly the §46 defect"). Recorded here
# because the wrong consequence is what made the wrong fix look urgent.

load 'helpers/setup'

CONSENT_FNS='manifest_repo_scope_confirm_apply _manifest_repo_scope_auto_confirm_authorized manifest_execution_require_apply'

# Two stages on purpose. `git grep -E '\bfn\b'` matches NOTHING -- git grep's
# ERE has no `\b` -- and a pattern that matches nothing is indistinguishable
# from "the function is not exported". The first cut of this file used `\b`,
# passed, and was caught only by the positive control below. Stage one selects
# `export -f` lines; stage two does the word match with `grep -w`, where the
# boundary is real and underscores count as word characters (so
# `_manifest_x` does not match inside `_manifest_x_y`).
exported_fn_lines() {
    git -C "$TEST_REPO_ROOT" grep -h -E '^[[:space:]]*export -f[[:space:]]' -- modules
}

is_exported() { exported_fn_lines | grep -wq -- "$1"; }

@test "consent: no function in the gate's closure is exported" {
    local fn
    for fn in $CONSENT_FNS; do
        if is_exported "$fn"; then
            printf 'exported, which reopens TRACKER §46 in an exec'"'"'d child: %s\n' "$fn" >&2
            exported_fn_lines | grep -w -- "$fn" >&2
        fi
        refute is_exported "$fn"
    done
}

@test "positive control: the export scan DOES find functions that are exported" {
    # Without this, a pattern that matches nothing makes the test above pass for
    # every name, including exported ones. That is not hypothetical: it is what
    # this file did until the `\b` was removed.
    local fn
    for fn in manifest_repo_scope_target_unambiguous manifest_execution_replay_hint \
              manifest_git_preflight_write_access; do
        is_exported "$fn"
    done

    # And the scan must be reading real lines, not an empty stream.
    local n
    n="$(exported_fn_lines | grep -c . || true)"
    [ "$n" -gt 20 ]
}

@test "negative control: a fabricated function name is not found exported" {
    refute is_exported 'manifest_repo_scope_confirm_apply_xyz'
    refute is_exported 'manifest_execution_require_apply_xyz'
}

@test "consent: the provenance snapshot stays process-local (declare -g, not -gx)" {
    # If this becomes -gx, a child inherits the snapshot and step 2 of the
    # header's chain changes -- at which point the reasoning above must be
    # re-derived rather than assumed.
    run grep -nE '^[[:space:]]*declare -g[[:space:]]+_MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV=' \
        "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    [ "$status" -eq 0 ]

    refute grep -qE 'declare -gx[[:space:]]+_MANIFEST_CLI_AUTO_CONFIRM_FROM_ENV' \
        "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
}

@test "consent: a broken closure fails CLOSED, not open" {
    # The behavioural claim, run rather than asserted. Mirrors the real shape:
    # gate exported, predicate not, MANIFEST_CLI_AUTO_CONFIRM=1 in the
    # environment exactly as manifest-yaml.sh:857 would leave it.
    run env MANIFEST_CLI_AUTO_CONFIRM=1 bash -c '
        pred() { [[ "${MANIFEST_CLI_AUTO_CONFIRM:-0}" == "1" ]]; }
        gate() { if pred; then echo "AUTHORIZED"; return 0; fi; echo "REFUSED"; return 1; }
        export -f gate
        bash -c "gate" 2>/dev/null
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"REFUSED"* ]]

    # Negative control: with the predicate exported too, the SAME child
    # authorizes from the environment variable. This is the outcome the
    # rejected fix would have shipped.
    run env MANIFEST_CLI_AUTO_CONFIRM=1 bash -c '
        pred() { [[ "${MANIFEST_CLI_AUTO_CONFIRM:-0}" == "1" ]]; }
        gate() { if pred; then echo "AUTHORIZED"; return 0; fi; echo "REFUSED"; return 1; }
        export -f gate pred
        bash -c "gate" 2>/dev/null
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTHORIZED"* ]]
}
