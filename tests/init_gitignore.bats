#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the .gitignore scaffolded at init time (create_default_gitignore /
# ensure_gitignore_smart). Pins universal hygiene: local/secret/generated config
# is ignored by default, .env value files are ignored with example/template
# carve-outs kept trackable, and NO blanket *.yaml/*.yml ignore (tracked
# authoring specs — service.spec.yaml, openapi.yaml, k8s manifests — must stay
# trackable).

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    GI="$PROJ/.gitignore"
    create_default_gitignore "$GI"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "gitignore: .env value files are ignored with example/template carve-outs" {
    grep -qx '.env' "$GI"
    grep -qx '.env.*' "$GI"
    grep -qx '!.env.example' "$GI"
    grep -qx '!.env.template' "$GI"
}

@test "gitignore: local config variants are ignored" {
    grep -qx '\*.local.yaml' "$GI"
    grep -qx '\*.local.yml' "$GI"
    grep -qx '\*.local.json' "$GI"
    grep -qx '\*.local.toml' "$GI"
}

@test "gitignore: secret config variants are ignored" {
    grep -qx '\*.secret.yaml' "$GI"
    grep -qx '\*.secret.json' "$GI"
    grep -qx '\*.secret.*' "$GI"
}

@test "gitignore: example/template authoring variants stay trackable" {
    grep -qx '!\*.example.yaml' "$GI"
    grep -qx '!\*.template.yaml' "$GI"
}

@test "gitignore: AI assistant / coding-agent workspaces are ignored" {
    grep -qx '.claude/\*' "$GI"
    grep -qx '.cursor/\*' "$GI"
    grep -qx '.windsurf/\*' "$GI"
    grep -qx '.gemini/' "$GI"
    grep -qx '.aider\*' "$GI"
}

@test "gitignore: personal agent state is ignored, team-shared config stays trackable" {
    cd "$PROJ"
    git init -q .
    # Assert the scaffolded template alone — a developer's ~/.gitignore_global
    # must not be able to change this suite's verdict.
    git config core.excludesFile /dev/null
    mkdir -p .claude/commands .claude/agents .cursor/rules
    : > .claude/settings.local.json
    : > .claude/settings.json
    : > .claude/commands/ship.md
    : > .claude/agents/reviewer.md
    : > .cursor/rules/style.mdc
    : > .aider.chat.history.md

    # Personal / per-developer state — ignored.
    run git check-ignore .claude/settings.local.json .aider.chat.history.md
    [ "$status" -eq 0 ]

    # Team-shared coordination config — must remain trackable.
    run git check-ignore .claude/settings.json
    [ "$status" -ne 0 ]
    run git check-ignore .claude/commands/ship.md
    [ "$status" -ne 0 ]
    run git check-ignore .claude/agents/reviewer.md
    [ "$status" -ne 0 ]
    run git check-ignore .cursor/rules/style.mdc
    [ "$status" -ne 0 ]
}

@test "gitignore: no absolute home paths leak into the scaffolded template" {
    refute grep -qE '/(Users|home)/[a-zA-Z0-9._-]+' "$GI"
}

@test "gitignore: NO blanket *.yaml or *.yml ignore" {
    refute grep -qxE '\*\.ya?ml' "$GI"
}

@test "gitignore: an unignored authoring spec is not matched by the local/secret rules" {
    # Sanity: git honors the file — service.spec.yaml / openapi.yaml stay tracked.
    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    : > service.spec.yaml
    : > openapi.yaml
    : > config.local.yaml
    : > db.secret.yaml
    run git check-ignore service.spec.yaml openapi.yaml
    [ "$status" -ne 0 ]
    run git check-ignore config.local.yaml
    [ "$status" -eq 0 ]
    run git check-ignore db.secret.yaml
    [ "$status" -eq 0 ]
}

# --- KEY MATERIAL ------------------------------------------------------------
# These are behavioral (git check-ignore), not grep-for-the-line, because the
# block depends on rule/negation ORDER: `!*.pub` re-includes only because it sits
# after the rules. A grep test would pass on a file whose order had been broken.
# The stake is high — the release commit is a bare `git add .` and no gate scans
# for key material, so an unmatched private key ships silently.

@test "gitignore: private key material is ignored deny-by-default" {
    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    local f
    for f in server.key tls.pem token.p8 signing.pkcs8 cert.der \
             bundle.pfx store.p12 keys.jks my.keystore my.bks \
             id_rsa id_dsa id_ecdsa id_ed25519 id_ecdsa_sk id_ed25519_sk \
             deploy_rsa host_ed25519 putty.ppk \
             secring.gpg app.private.gpg app.secret.gpg; do
        : > "$f"
        run git check-ignore "$f"
        [ "$status" -eq 0 ] || {
            echo "NOT ignored (private key material would be committed): $f" >&2
            return 1
        }
    done
}

@test "gitignore: key material is ignored at any depth, not just the repo root" {
    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    mkdir -p config/certs deep/nested/dir
    : > config/certs/prod.key
    : > deep/nested/dir/id_ed25519
    run git check-ignore config/certs/prod.key
    [ "$status" -eq 0 ]
    run git check-ignore deep/nested/dir/id_ed25519
    [ "$status" -eq 0 ]
}

@test "gitignore: public halves stay trackable (exceptions survive the rules)" {
    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    local f
    for f in id_rsa.pub mykey.pub public-cert.pem publickey.key fullchain.pem chain.pem; do
        : > "$f"
        run git check-ignore "$f"
        [ "$status" -ne 0 ] || {
            echo "wrongly ignored (public half must stay trackable): $f" >&2
            return 1
        }
    done
}

@test "gitignore: *.gpg ciphertext stays trackable (git-crypt / sops / pass)" {
    # Only private keyrings are denied. A blanket *.gpg would break repos that
    # commit encrypted files on purpose.
    cd "$PROJ"
    git init -q .
    git config core.excludesFile /dev/null
    : > vault.gpg
    : > secrets.sops.gpg
    run git check-ignore vault.gpg
    [ "$status" -ne 0 ]
    run git check-ignore secrets.sops.gpg
    [ "$status" -ne 0 ]
    refute grep -qx '\*.gpg' "$GI"
}

@test "gitignore: key-material exceptions are positioned after their rules" {
    # Order is load-bearing: a negation before its rule is silently inert.
    local rule_line neg_line
    rule_line="$(grep -nx '\*.key' "$GI" | cut -d: -f1)"
    neg_line="$(grep -nx '!\*public\*.key' "$GI" | cut -d: -f1)"
    [ -n "$rule_line" ]
    [ -n "$neg_line" ]
    [ "$rule_line" -lt "$neg_line" ]
}
