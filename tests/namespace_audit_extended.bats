#!/usr/bin/env bats
#
# Extended namespace audits — covers four gaps the existing audit
# ("Manifest-owned environment variables use MANIFEST_CLI namespace" in
# install_requirements.bats) does NOT catch:
#
#   Gap A — uninstall-cli.sh is omitted from the existing audit's
#           search_paths even though it contains env-related logic.
#   Gap B — the existing audit's grep `MANIFEST_[A-Z0-9_]+` requires at
#           least one alphanumeric after the underscore, so literal
#           `MANIFEST_*` (asterisk) strings slip past. We re-grep
#           specifically for the literal-asterisk form and enforce an
#           explicit per-file allowlist.
#   Gap C — private shell globals starting with `_MANIFEST_*` (vs the
#           preferred `_MANIFEST_CLI_*`). Today's catalog is allowlisted
#           verbatim so any NEW underscored legacy-namespace global trips
#           the test.
#   Gap D — the existing audit only inspects two doc files
#           (COMMAND_REFERENCE.md, IMPROVEMENT_TRACKER.md). We extend
#           coverage to every active doc under docs/ (everything not in
#           zArchive/), with the same comment-line skipping rule.
#
# These tests use the SAME core scanning loop as the existing audit so
# results stay consistent.

load 'helpers/setup'

# Shared scanner: emit "file:line:var" for every MANIFEST_<token> hit in
# the given search_paths that is NOT MANIFEST_CLI or MANIFEST_CLI_*, while
# skipping pure-comment lines (matches existing audit semantics).
_namespace_scan_offenders() {
    local offenders="" file line text var
    while IFS=: read -r file line text; do
        [[ "$text" =~ ^[[:space:]]*# ]] && continue
        while [[ "$text" =~ (^|[^A-Za-z0-9_])(MANIFEST_[A-Z0-9_]*) ]]; do
            var="${BASH_REMATCH[2]}"
            case "$var" in
                MANIFEST_CLI|MANIFEST_CLI_*) ;;
                *) offenders+="${file}:${line}:${var}"$'\n' ;;
            esac
            text="${text#*"${BASH_REMATCH[2]}"}"
        done
    done < <(grep -R -n -E '(^|[^A-Za-z0-9_])MANIFEST_[A-Z0-9_]+' "$@" 2>/dev/null || true)
    printf '%s' "$offenders"
}

# Gap A — uninstall-cli.sh is not covered by the existing audit. Re-run
# the same scan with that file included so future regressions there fail.
@test "Gap A: uninstall-cli.sh uses MANIFEST_CLI namespace" {
    local offenders
    offenders="$(_namespace_scan_offenders "$TEST_REPO_ROOT/uninstall-cli.sh")"
    if [ -n "$offenders" ]; then
        printf '%s' "$offenders" >&2
        return 1
    fi
}

# Gap B — broad `MANIFEST_*` literal-asterisk strings. Each match below
# is enumerated explicitly with a one-line reason. New matches anywhere
# else fail the test. Comment-line skipping does NOT apply here — the
# whole point is to catch the legacy-cleanup pattern wherever it lives.
@test "Gap B: literal MANIFEST_* strings limited to allowlisted legacy-cleanup sites" {
    local search_paths=(
        "$TEST_REPO_ROOT/modules"
        "$TEST_REPO_ROOT/tests"
        "$TEST_REPO_ROOT/scripts"
        "$TEST_REPO_ROOT/install-cli.sh"
        "$TEST_REPO_ROOT/uninstall-cli.sh"
        "$TEST_REPO_ROOT/formula"
        "$TEST_REPO_ROOT/completions"
        "$TEST_REPO_ROOT/.github"
    )

    # Per-file allowlist of `MANIFEST_*` (literal asterisk) occurrences.
    # Each "path:line" entry below is justified. If you find yourself
    # adding a new entry, you almost certainly want to use the
    # MANIFEST_CLI namespace instead — only true legacy-cleanup paths
    # (uninstall / pre-install scrub) belong here.
    local -a allowlist=(
        # install-cli.sh:400 — comment describing the cleanup_environment_variables
        #   helper that strips legacy MANIFEST_* exports from shell profiles.
        "install-cli.sh:400"
        # install-cli.sh:1050 — comment in the post-uninstall residue sweep
        #   that calls cleanup_environment_variables for stale MANIFEST_* exports.
        "install-cli.sh:1050"
        # uninstall-cli.sh:57 — usage-help text listing what the uninstaller
        #   removes from shell profiles, including legacy MANIFEST_* exports.
        "uninstall-cli.sh:57"
    )

    local offenders="" file line rel key allowed
    while IFS=: read -r file line _rest; do
        [ -n "$file" ] || continue
        rel="${file#"$TEST_REPO_ROOT/"}"
        # This audit file itself documents the literal pattern in prose;
        # excluding it keeps the test self-hosting without polluting the
        # allowlist with dozens of incidental line numbers.
        [ "$rel" = "tests/namespace_audit_extended.bats" ] && continue
        key="${rel}:${line}"
        allowed=0
        for entry in "${allowlist[@]}"; do
            if [ "$entry" = "$key" ]; then
                allowed=1
                break
            fi
        done
        if [ "$allowed" -eq 0 ]; then
            offenders+="${rel}:${line}"$'\n'
        fi
    done < <(grep -R -n -F 'MANIFEST_*' "${search_paths[@]}" 2>/dev/null || true)

    if [ -n "$offenders" ]; then
        echo "Unallowlisted literal MANIFEST_* occurrences:" >&2
        printf '%s' "$offenders" >&2
        return 1
    fi
}

# Gap C — private shell globals must use the _MANIFEST_CLI_* convention
# going forward. Today's legacy `_MANIFEST_*` names are allowlisted
# verbatim (DO NOT rename them in production code under this PR); any
# new such name added in future trips the test.
@test "Gap C: private _MANIFEST_* shell globals match _MANIFEST_CLI_* or allowlist" {
    # Catalog every _MANIFEST_<token> reference in module/script source.
    # Mirrors the catalog command from the handoff doc:
    #   grep -RhoE '(^|[^A-Za-z0-9_])_MANIFEST_[A-Z0-9_]+' modules/ scripts/ \
    #     install-cli.sh uninstall-cli.sh \
    #     | grep -oE '_MANIFEST_[A-Z0-9_]+' | sort -u
    local catalog
    catalog="$(
        grep -RhoE '(^|[^A-Za-z0-9_])_MANIFEST_[A-Z0-9_]+' \
            "$TEST_REPO_ROOT/modules" \
            "$TEST_REPO_ROOT/scripts" \
            "$TEST_REPO_ROOT/install-cli.sh" \
            "$TEST_REPO_ROOT/uninstall-cli.sh" 2>/dev/null \
            | grep -oE '_MANIFEST_[A-Z0-9_]+' \
            | sort -u
    )"

    # Explicit allowlist of EXISTING legacy `_MANIFEST_*` private globals.
    # Each entry has a one-line `# why` reason. New code must use
    # _MANIFEST_CLI_* — do not add to this list without strong cause.
    local -a allow=(
        # Test/agent stub module-loaded sentinel (pre-namespace stub).
        "_MANIFEST_AGENT_STUB_LOADED"
        # Archive-regex memo used by the archive engine (pre-namespace).
        "_MANIFEST_ARCHIVABLE_REGEX"
        # Cloud-stub module-loaded sentinel (pre-namespace stub).
        "_MANIFEST_CLOUD_STUB_LOADED"
        # Config CRUD module-loaded sentinel (pre-namespace).
        "_MANIFEST_CONFIG_CRUD_LOADED"
        # Internal flag guarding one-shot env-override processing.
        "_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES"
        # Doctor module-loaded sentinel (pre-namespace).
        "_MANIFEST_DOCTOR_LOADED"
        # Helper used by yaml/env round-trip (pre-namespace).
        "_MANIFEST_ENV_TO_YAML"
        # Execution-policy module-loaded sentinel (pre-namespace).
        "_MANIFEST_EXECUTION_POLICY_LOADED"
        # GH preflight memo: timestamp of last `gh` auth/version check.
        "_MANIFEST_GH_VALIDATED_AT"
        # Init module-loaded sentinel (pre-namespace).
        "_MANIFEST_INIT_LOADED"
        # Install-paths module-loaded sentinel (pre-namespace).
        "_MANIFEST_INSTALL_PATHS_LOADED"
        # Plugin-loader module-loaded sentinel (pre-namespace).
        "_MANIFEST_PLUGIN_LOADER_LOADED"
        # Prep module-loaded sentinel (pre-namespace).
        "_MANIFEST_PREP_LOADED"
        # PR-native module-loaded sentinel (pre-namespace).
        "_MANIFEST_PR_NATIVE_LOADED"
        # PR stub module-loaded sentinel (pre-namespace).
        "_MANIFEST_PR_STUB_LOADED"
        # Recipe module-loaded sentinel (pre-namespace).
        "_MANIFEST_RECIPE_LOADED"
        # Refresh module-loaded sentinel (pre-namespace).
        "_MANIFEST_REFRESH_LOADED"
        # Repo-identity cache: current branch.
        "_MANIFEST_REPO_ID_BRANCH"
        # Repo-identity cache: detected fleet member name.
        "_MANIFEST_REPO_ID_FLEET_MEMBER"
        # Repo-identity cache: detected fleet name.
        "_MANIFEST_REPO_ID_FLEET_NAME"
        # Repo-identity cache: detected fleet root path.
        "_MANIFEST_REPO_ID_FLEET_ROOT"
        # Repo-identity cache: git root path.
        "_MANIFEST_REPO_ID_GIT_ROOT"
        # Repo-identity cache: origin remote URL.
        "_MANIFEST_REPO_ID_ORIGIN"
        # Repo-identity cache: upstream remote URL.
        "_MANIFEST_REPO_ID_UPSTREAM"
        # Repo-identity cache: identity-detection warning text.
        "_MANIFEST_REPO_ID_WARNING"
        # Ship result memo: last GitHub-release outcome.
        "_MANIFEST_SHIP_LAST_GITHUB_RELEASE_STATUS"
        # Ship result memo: last Homebrew-update outcome.
        "_MANIFEST_SHIP_LAST_HOMEBREW_STATUS"
        # Ship result memo: last local-upgrade outcome.
        "_MANIFEST_SHIP_LAST_LOCAL_UPGRADE_STATUS"
        # Ship module-loaded sentinel (pre-namespace).
        "_MANIFEST_SHIP_LOADED"
        # Status module-loaded sentinel (pre-namespace).
        "_MANIFEST_STATUS_LOADED"
        # Test stub module-loaded sentinel (pre-namespace stub).
        "_MANIFEST_TEST_STUB_LOADED"
        # YAML parser selection (pre-namespace).
        "_MANIFEST_YAML_PARSER"
        # YAML→env helper (pre-namespace).
        "_MANIFEST_YAML_TO_ENV"
    )

    local offenders="" name allowed
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$name" in
            _MANIFEST_CLI_*) continue ;;
        esac
        allowed=0
        for entry in "${allow[@]}"; do
            if [ "$entry" = "$name" ]; then
                allowed=1
                break
            fi
        done
        if [ "$allowed" -eq 0 ]; then
            offenders+="${name}"$'\n'
        fi
    done <<< "$catalog"

    if [ -n "$offenders" ]; then
        echo "Unallowlisted private _MANIFEST_* globals (use _MANIFEST_CLI_* prefix):" >&2
        printf '%s' "$offenders" >&2
        return 1
    fi
}

# Gap D — scan every active doc under docs/ (anything not in zArchive/)
# for MANIFEST_<token> names outside the MANIFEST_CLI namespace. Comment
# lines (markdown `<!--` is not a shell `#`) don't strictly apply, but we
# still skip lines whose first non-whitespace char is `#` to match the
# existing audit semantics for docs that embed shell snippets.
@test "Gap D: active CLI docs use MANIFEST_CLI namespace" {
    local -a doc_paths=()
    while IFS= read -r f; do
        doc_paths+=("$f")
    done < <(find "$TEST_REPO_ROOT/docs" \
                -type d -name 'zArchive' -prune -o \
                -type f -print 2>/dev/null)

    [ "${#doc_paths[@]}" -gt 0 ]

    local offenders
    offenders="$(_namespace_scan_offenders "${doc_paths[@]}")"
    if [ -n "$offenders" ]; then
        printf '%s' "$offenders" >&2
        return 1
    fi
}
