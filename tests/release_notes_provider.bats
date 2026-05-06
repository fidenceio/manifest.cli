#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "docs/manifest-documentation.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    PROJECT_ROOT="$SCRATCH"
    export PROJECT_ROOT

    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit -q --allow-empty -m "initial"

    unset MANIFEST_CLI_RELEASE_NOTES_PROVIDER
    unset MANIFEST_CLI_RELEASE_NOTES_COMMAND
    unset MANIFEST_CLI_RELEASE_NOTES_REQUIRED
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_RELEASE_NOTES_PROVIDER
    unset MANIFEST_CLI_RELEASE_NOTES_COMMAND
    unset MANIFEST_CLI_RELEASE_NOTES_REQUIRED
}

# Build a changes_file that mirrors what analyze_changes leaves behind: a
# `## Highlights for vX` header followed by a single `### Changes` body.
seed_local_body() {
    local file="$1"
    local version="$2"
    cat > "$file" <<EOF
## Highlights for v${version}

### Changes

- Add fleet adoption planning
- Fix release-note generation
EOF
}

# Body of a provider stub script.  $1 is the path to write to the output
# file; the stub copies it verbatim. Use printf-friendly escapes.
make_stub() {
    local stub="$1"
    local body="$2"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'request="$1"'
        printf '%s\n' 'output="$2"'
        printf '%s\n' "cat > \"\$output\" <<'PROVIDER_EOF'"
        printf '%s\n' "$body"
        printf '%s\n' "PROVIDER_EOF"
    } > "$stub"
    chmod +x "$stub"
}

# -----------------------------------------------------------------------------
# Provider invocation paths
# -----------------------------------------------------------------------------

@test "provider=local: helper is a no-op and changes_file is preserved" {
    local changes="$SCRATCH/changes.md"
    seed_local_body "$changes" "1.0.0"
    local before
    before="$(cat "$changes")"

    run _manifest_release_notes_run_provider "1.0.0" "patch" "2026-05-06 00:00:00 UTC" "$changes"

    [ "$status" -eq 0 ]
    [ "$(cat "$changes")" = "$before" ]
}

@test "provider=command: working stub replaces the body in changes_file" {
    local changes="$SCRATCH/changes.md"
    seed_local_body "$changes" "1.0.0"

    local stub="$SCRATCH/provider"
    make_stub "$stub" '- Added fleet adoption planning across the v46 line
- Fixed release-note generation so empty ranges no longer emit filler'

    MANIFEST_CLI_RELEASE_NOTES_PROVIDER=command \
    MANIFEST_CLI_RELEASE_NOTES_COMMAND="$stub" \
        run _manifest_release_notes_run_provider "1.0.0" "minor" "2026-05-06 00:00:00 UTC" "$changes"

    [ "$status" -eq 0 ]
    grep -qx '^## Highlights for v1.0.0$' "$changes"
    grep -qx '^### Changes$' "$changes"
    grep -qx '^- Added fleet adoption planning across the v46 line$' "$changes"
    grep -qx '^- Fixed release-note generation so empty ranges no longer emit filler$' "$changes"
    # Original local bullets are gone.
    ! grep -q '^- Add fleet adoption planning$' "$changes"
}

@test "provider=command: missing command env var falls back without aborting" {
    local changes="$SCRATCH/changes.md"
    seed_local_body "$changes" "1.0.0"

    MANIFEST_CLI_RELEASE_NOTES_PROVIDER=command \
        run _manifest_release_notes_run_provider "1.0.0" "patch" "2026-05-06 00:00:00 UTC" "$changes"

    [ "$status" -eq 0 ]
    grep -q '^- Add fleet adoption planning$' "$changes"
}

@test "provider=command: non-executable script falls back without aborting" {
    local changes="$SCRATCH/changes.md"
    seed_local_body "$changes" "1.0.0"

    local stub="$SCRATCH/not-executable"
    : > "$stub"

    MANIFEST_CLI_RELEASE_NOTES_PROVIDER=command \
    MANIFEST_CLI_RELEASE_NOTES_COMMAND="$stub" \
        run _manifest_release_notes_run_provider "1.0.0" "patch" "2026-05-06 00:00:00 UTC" "$changes"

    [ "$status" -eq 0 ]
    grep -q '^- Add fleet adoption planning$' "$changes"
}

@test "provider=command: failing script with required=false falls back" {
    local changes="$SCRATCH/changes.md"
    seed_local_body "$changes" "1.0.0"

    local stub="$SCRATCH/fail-provider"
    {
        echo '#!/usr/bin/env bash'
        echo 'exit 9'
    } > "$stub"
    chmod +x "$stub"

    MANIFEST_CLI_RELEASE_NOTES_PROVIDER=command \
    MANIFEST_CLI_RELEASE_NOTES_COMMAND="$stub" \
    MANIFEST_CLI_RELEASE_NOTES_REQUIRED=false \
        run _manifest_release_notes_run_provider "1.0.0" "patch" "2026-05-06 00:00:00 UTC" "$changes"

    [ "$status" -eq 0 ]
    grep -q '^- Add fleet adoption planning$' "$changes"
}

@test "provider=command: failing script with required=true returns non-zero" {
    local changes="$SCRATCH/changes.md"
    seed_local_body "$changes" "1.0.0"

    local stub="$SCRATCH/fail-provider"
    {
        echo '#!/usr/bin/env bash'
        echo 'exit 9'
    } > "$stub"
    chmod +x "$stub"

    MANIFEST_CLI_RELEASE_NOTES_PROVIDER=command \
    MANIFEST_CLI_RELEASE_NOTES_COMMAND="$stub" \
    MANIFEST_CLI_RELEASE_NOTES_REQUIRED=true \
        run _manifest_release_notes_run_provider "1.0.0" "patch" "2026-05-06 00:00:00 UTC" "$changes"

    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Output validation
# -----------------------------------------------------------------------------

@test "validation: leading prose before the first bullet is stripped" {
    local raw="$SCRATCH/raw.md"
    cat > "$raw" <<'EOF'
Sure, here are the release notes you asked for:

- Added a real change
EOF

    run _manifest_release_notes_validate_output "$raw"

    # The raw output starts with "Sure, here are" — that triggers the banned
    # preamble check on the cleaned content. Since the cleaned content (post
    # awk strip) starts with "- Added a real change", the banned-phrase check
    # should NOT fire here. The "Sure, here" prose lives BEFORE the first
    # bullet and is dropped by the preamble strip.
    [ "$status" -eq 0 ]
    [ "$output" = "- Added a real change" ]
}

@test "validation: output with no bullets is rejected" {
    local raw="$SCRATCH/raw.md"
    cat > "$raw" <<'EOF'
This is a paragraph but no bullets at all.
Another sentence.
EOF

    run _manifest_release_notes_validate_output "$raw"

    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "validation: more than 15 bullets is truncated" {
    local raw="$SCRATCH/raw.md"
    : > "$raw"
    for i in $(seq 1 25); do
        printf -- '- Bullet number %d\n' "$i" >> "$raw"
    done

    run _manifest_release_notes_validate_output "$raw"

    [ "$status" -eq 0 ]
    [ "$(echo "$output" | grep -c '^- ')" -eq 15 ]
    echo "$output" | grep -q '^- Bullet number 15$'
    ! echo "$output" | grep -q '^- Bullet number 16$'
}

@test "validation: bullets containing banned LLM-preamble phrases are rejected" {
    local raw="$SCRATCH/raw.md"
    cat > "$raw" <<'EOF'
- As an AI language model, I can't actually generate these but here goes
- Added a thing
EOF

    run _manifest_release_notes_validate_output "$raw"

    [ "$status" -ne 0 ]
}

@test "validation: trailing prose after the last bullet is dropped" {
    local raw="$SCRATCH/raw.md"
    cat > "$raw" <<'EOF'
- Added a real change
- Fixed something else

Hope that helps! Let me know if you need anything else.
EOF

    run _manifest_release_notes_validate_output "$raw"

    [ "$status" -eq 0 ]
    [ "$(echo "$output" | grep -c '^- ')" -eq 2 ]
    ! echo "$output" | grep -q "Hope that helps"
    ! echo "$output" | grep -q "Let me know"
}
