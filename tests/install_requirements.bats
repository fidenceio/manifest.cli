#!/usr/bin/env bats

load 'helpers/setup'

@test "requirements centralize Docker availability checks" {
    load_modules

    [ "$MANIFEST_CLI_REQUIRED_DOCKER_COMMAND" = "docker" ]
    [ -n "$MANIFEST_CLI_REQUIRED_DOCKER_LABEL" ]
    [ -n "$MANIFEST_CLI_REQUIRED_COREUTILS_LABEL" ]

    declare -F manifest_requirement_docker_command_exists >/dev/null
    declare -F manifest_requirement_docker_engine_is_running >/dev/null
    declare -F manifest_requirement_coreutils_timeout_command >/dev/null
}

@test "requirements expose a GNU-specific parallel check (rejects non-GNU same-named binaries)" {
    load_modules

    declare -F manifest_requirement_parallel_is_gnu >/dev/null

    # A missing binary is not GNU parallel.
    ! manifest_requirement_parallel_is_gnu /nonexistent-parallel-xyz

    # A same-named binary that isn't GNU (the moreutils collision) is rejected,
    # not accepted just because something called 'parallel' is on PATH.
    local fake="$BATS_TEST_TMPDIR/parallel-fake"
    cat >"$fake" <<'EOF'
#!/bin/sh
echo "parallel (moreutils-style) 0.0 — not GNU"
EOF
    chmod +x "$fake"
    ! manifest_requirement_parallel_is_gnu "$fake"
}

@test "test container and CI install GNU parallel for run-tests.sh --jobs" {
    # Parallelism is a required test dependency (run-tests.sh defaults to --jobs
    # auto), so every place that provisions the suite must install it. The Linux
    # CI leg runs the suite inside the disposable container (no host installs), so
    # it inherits parallel from there; the host-native macOS leg (no Docker on
    # GitHub macOS runners) installs it via brew. The host installer/formula must
    # NOT — parallel is a test-only dep, like bats, never shipped to CLI users.
    grep -F 'apk add --no-cache bash git bats parallel yq coreutils' \
        "$TEST_REPO_ROOT/scripts/run-tests-container.sh" >/dev/null
    # Linux leg runs via the containerized runner (parallel provisioned in-container)…
    grep -F './scripts/run-tests-container.sh' "$TEST_REPO_ROOT/.github/workflows/test.yml" >/dev/null
    # …and no longer installs test deps on the runner host.
    ! grep -F 'apt-get install -y bats parallel' "$TEST_REPO_ROOT/.github/workflows/test.yml"
    # macOS leg is host-native and brew-installs parallel (and gnu-sed for §5.11).
    grep -F 'brew install bats-core yq bash coreutils gnu-sed parallel' "$TEST_REPO_ROOT/.github/workflows/test.yml" >/dev/null

    ! grep -iqE 'parallel' "$TEST_REPO_ROOT/install-cli.sh"
    ! grep -iqE 'parallel' "$TEST_REPO_ROOT/formula/manifest.rb"
}

@test "requirements expose a GNU-specific sed check (rejects BSD sed of the same name) (§7.9)" {
    load_modules

    declare -F manifest_requirement_sed_command_is_gnu >/dev/null
    declare -F manifest_requirement_runtime_sed_is_gnu >/dev/null

    # A missing binary is not GNU sed.
    ! manifest_requirement_sed_command_is_gnu /nonexistent-sed-xyz

    # BSD sed (the macOS default) has no GNU banner — it must be rejected, not
    # accepted just because something called 'sed' is on PATH.
    local fake_bsd="$BATS_TEST_TMPDIR/sed-bsd-fake"
    cat >"$fake_bsd" <<'EOF'
#!/bin/sh
echo "usage: sed [-Ealn] command [file ...]" >&2
exit 1
EOF
    chmod +x "$fake_bsd"
    ! manifest_requirement_sed_command_is_gnu "$fake_bsd"

    # A GNU sed banner is accepted.
    local fake_gnu="$BATS_TEST_TMPDIR/sed-gnu-fake"
    cat >"$fake_gnu" <<'EOF'
#!/bin/sh
echo "sed (GNU sed) 4.9"
EOF
    chmod +x "$fake_gnu"
    manifest_requirement_sed_command_is_gnu "$fake_gnu"
}

@test "install + doctor surface the gnu-sed gap as a macOS WARNING, not a hard error (§7.9)" {
    # Pre-ship, not mid-ship (§7.9): the gap is reported at install-time
    # validation and in `manifest doctor`, scoped to macOS, pointing at
    # `brew install gnu-sed`. Only the maintainer formula-rewrite path needs it,
    # so it must NEVER be a hard install error.
    grep -F 'manifest_requirement_runtime_sed_is_gnu' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'manifest_requirement_runtime_sed_is_gnu' "$TEST_REPO_ROOT/modules/core/manifest-doctor.sh" >/dev/null
    grep -F 'brew install gnu-sed' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'brew install gnu-sed' "$TEST_REPO_ROOT/modules/core/manifest-doctor.sh" >/dev/null
    # Warning, not error: surfaced via print_warning / _doctor_warn only.
    grep -F 'print_warning "⚠️  GNU sed not found' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    ! grep -qF 'print_error "❌ GNU sed' "$TEST_REPO_ROOT/install-cli.sh"
    grep -F '_doctor_warn "GNU sed (optional)"' "$TEST_REPO_ROOT/modules/core/manifest-doctor.sh" >/dev/null
}

@test "requirements preserve Bash 5 and Mike Farah yq as runtime contract" {
    load_modules

    [ "$MANIFEST_CLI_REQUIRED_BASH_MAJOR" = "5" ]
    [ "$MANIFEST_CLI_REQUIRED_YQ_MAJOR" = "4" ]
    [[ "$MANIFEST_CLI_REQUIRED_YQ_VENDOR" == *"github.com/mikefarah/yq"* ]]

    grep -F '| Bash | 5.0+ |' "$TEST_REPO_ROOT/README.md" >/dev/null
    grep -F '| yq | 4.0+ (Mike Farah' "$TEST_REPO_ROOT/README.md" >/dev/null
    grep -F '| coreutils | Any |' "$TEST_REPO_ROOT/README.md" >/dev/null
    ! grep -F 'MANIFEST_CLI_REQUIRED_SCRIPT' "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh" >/dev/null
}

@test "Manifest-owned environment variables use MANIFEST_CLI namespace" {
    local search_paths=(
        "$TEST_REPO_ROOT/modules"
        "$TEST_REPO_ROOT/tests"
        "$TEST_REPO_ROOT/scripts"
        "$TEST_REPO_ROOT/install-cli.sh"
        "$TEST_REPO_ROOT/formula"
        "$TEST_REPO_ROOT/completions"
        "$TEST_REPO_ROOT/.github"
        "$TEST_REPO_ROOT/README.md"
        "$TEST_REPO_ROOT/docs/COMMAND_REFERENCE.md"
        "$TEST_REPO_ROOT/docs/IMPROVEMENT_TRACKER.md"
    )
    local offenders="" file line text var

    while IFS=: read -r file line text; do
        # Skip pure comment lines — documentation legitimately references the
        # legacy unprefixed Manifest namespace (e.g. uninstall's sweep over
        # pre-namespace exports) and shouldn't be flagged as a code offender.
        [[ "$text" =~ ^[[:space:]]*# ]] && continue
        while [[ "$text" =~ (^|[^A-Za-z0-9_])(MANIFEST_[A-Z0-9_]*) ]]; do
            var="${BASH_REMATCH[2]}"
            case "$var" in
                MANIFEST_CLI|MANIFEST_CLI_*) ;;
                *) offenders+="${file}:${line}:${var}"$'\n' ;;
            esac
            text="${text#*"${BASH_REMATCH[2]}"}"
        done
    done < <(grep -R -n -E '(^|[^A-Za-z0-9_])MANIFEST_[A-Z0-9_]+' "${search_paths[@]}" 2>/dev/null || true)

    if [ -n "$offenders" ]; then
        printf '%s' "$offenders" >&2
        return 1
    fi
}

@test "OS detection never installs host dependencies during runtime setup" {
    ! grep -F 'brew install coreutils' "$TEST_REPO_ROOT/modules/system/manifest-os.sh" >/dev/null
    grep -F 'using fallback timeout method' "$TEST_REPO_ROOT/modules/system/manifest-os.sh" >/dev/null
    grep -F 'Install coreutils for the supported macOS timeout command' "$TEST_REPO_ROOT/modules/system/manifest-os.sh" >/dev/null
}

@test "CI and git retry use the supported coreutils timeout command" {
    grep -F 'brew install bats-core yq bash coreutils' "$TEST_REPO_ROOT/.github/workflows/test.yml" >/dev/null
    grep -F 'manifest_git_timeout_command' "$TEST_REPO_ROOT/modules/git/manifest-git.sh" >/dev/null
    grep -F 'gtimeout' "$TEST_REPO_ROOT/modules/git/manifest-git.sh" >/dev/null
    ! grep -F 'if timeout "$timeout"' "$TEST_REPO_ROOT/modules/git/manifest-git.sh" >/dev/null
}

@test "installer handles Homebrew before Docker before final validation" {
    local homebrew_line docker_line validate_line

    run grep -n "# On macOS, offer to install Homebrew" "$TEST_REPO_ROOT/install-cli.sh"
    [ "$status" -eq 0 ]
    homebrew_line="${output%%:*}"

    run grep -n "^[[:space:]]*ensure_docker_installed$" "$TEST_REPO_ROOT/install-cli.sh"
    [ "$status" -eq 0 ]
    docker_line="${output%%:*}"

    run grep -n "^[[:space:]]*validate_system$" "$TEST_REPO_ROOT/install-cli.sh"
    [ "$status" -eq 0 ]
    validate_line="${output%%:*}"

    [ "$homebrew_line" -lt "$docker_line" ]
    [ "$docker_line" -lt "$validate_line" ]
}

@test "installer offers Docker Desktop through Homebrew cask on macOS" {
    grep -F 'brew install --cask docker' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'Install Docker Desktop now?' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'open -a Docker' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
}

@test "installer sets up shell completions for IDE integrated terminals" {
    # §5.7: copy_cli_files stages completions/ into runtime/v<X>/ rather
    # than the live install dir; the "Staged completions" print is the
    # post-rename equivalent of the old "Copy shell completions" comment.
    grep -F 'Staged completions' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'install_shell_completions' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    # Manual installs write to user-owned completion dirs, never brew's. The
    # paths are centralized in the install-paths module (single source of truth,
    # shared with the uninstaller's completion sweep) and read back by the
    # installer, so assert them there.
    grep -F 'bash-completion/completions/manifest' "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh" >/dev/null
    grep -F '.zsh/completions' "$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh" >/dev/null
}

@test "installer never writes shell completions into Homebrew-managed dirs" {
    # Regression: install-cli.sh used to symlink into $(brew --prefix)/etc and
    # /share, clobbering the formula's own completions and breaking the next
    # `brew upgrade`. The installer must only ever touch user-owned paths.
    ! grep -F 'etc/bash_completion.d/manifest' "$TEST_REPO_ROOT/install-cli.sh"
    ! grep -F 'share/zsh/site-functions/_manifest' "$TEST_REPO_ROOT/install-cli.sh"
    # The Homebrew install path must not call install_shell_completions at all;
    # the formula owns completions there. Exactly the two manual-path callers remain.
    run grep -c 'install_shell_completions$' "$TEST_REPO_ROOT/install-cli.sh"
    [ "$output" -eq 2 ]
}

@test "installer writes IDE and AI assistant command catalogs" {
    grep -F 'install_ide_command_catalog' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'manifest-cli-commands.md' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'manifest-cli-commands.json' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'AGENTS.md' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'CLAUDE.md' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
    grep -F 'Mutating commands preview by default.' "$TEST_REPO_ROOT/install-cli.sh" >/dev/null
}
