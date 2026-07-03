#!/bin/bash

# Manifest CLI Env Naming Module — ENV-001 naming law (STANDARD.md §2.7)
#
# Every Fidence-owned STORED env name matches ^FIDENCE_[A-Z0-9_]+$. Framework
# names (what a third-party tool reads) are bridged at injection boundaries,
# never stored — so they are allowed where they legitimately appear, via the
# allowlist below. The built-in allowlist mirrors the fleet registry-as-data
# at docs/contracts/schemas/v1/env_framework_names.json.
#
# Enforcement is config-driven (env.naming_enforcement): `warn` (56.x default)
# surfaces violations as audit warnings; `strict` (57.0.0 default) makes them
# critical. Extra allow entries come from env.naming_allow (comma-separated;
# entries ending in `_` are prefixes, otherwise exact names).

# Guard against multiple sourcing
if [[ -n "${_MANIFEST_CLI_ENV_NAMING_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_ENV_NAMING_LOADED=1

# Mirrors env_framework_names.json `exact`
MANIFEST_CLI_ENV_NAMING_EXACT_DEFAULT=(
    DATABASE_URL NODE_ENV PORT HOST HOSTNAME TZ CI
    RUST_LOG RUST_BACKTRACE SQLX_OFFLINE
    NEXTAUTH_URL NEXTAUTH_SECRET AUTH_SECRET AUTH_TRUST_HOST
)

# Mirrors env_framework_names.json `prefixes` + `exempt_namespaces`
# (MANIFEST_CLI_ is the permanent carve-out — never renamed, aliased, bridged).
MANIFEST_CLI_ENV_NAMING_PREFIXES_DEFAULT=(
    NEXT_PUBLIC_ NEXT_ REACT_APP_ VITE_ NODE_ NPM_ PNPM_
    POSTGRES_ PG CRDB_ COCKROACH_ REDIS_ KAFKA_ MONGO_ MINIO_
    RUST_ CARGO_ SQLX_ OTEL_ DOCKER_ KUBERNETES_
    AUTHENTIK_ KONG_ GF_ VM_
    MANIFEST_CLI_
)

# Is a single stored env name legal under the law?
_manifest_env_name_allowed() {
    local name="$1"

    if [[ "$name" =~ ^FIDENCE_[A-Z0-9_]+$ ]]; then
        return 0
    fi

    local exact
    for exact in "${MANIFEST_CLI_ENV_NAMING_EXACT_DEFAULT[@]}"; do
        [[ "$name" == "$exact" ]] && return 0
    done

    local prefix
    for prefix in "${MANIFEST_CLI_ENV_NAMING_PREFIXES_DEFAULT[@]}"; do
        [[ "$name" == "$prefix"* ]] && return 0
    done

    local extra_raw="${MANIFEST_CLI_ENV_NAMING_ALLOW:-}"
    if [[ -n "$extra_raw" ]]; then
        local entry
        IFS=',' read -r -a _manifest_env_allow_entries <<< "$extra_raw"
        for entry in "${_manifest_env_allow_entries[@]}"; do
            entry="${entry#"${entry%%[![:space:]]*}"}"
            entry="${entry%"${entry##*[![:space:]]}"}"
            [[ -n "$entry" ]] || continue
            if [[ "$entry" == *_ ]]; then
                [[ "$name" == "$entry"* ]] && return 0
            else
                [[ "$name" == "$entry" ]] && return 0
            fi
        done
    fi

    return 1
}

# Extract stored env names (KEY=... assignment keys) from a dotenv-style file.
_manifest_env_names_from_dotenv() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "$file"
}

# Extract ${VAR} interpolation references (RHS of the compose bridge — the
# stored side). Compose LHS keys are framework names by design; never checked.
_manifest_env_names_from_compose() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null | sed 's/^\${//' | sort -u
}

# ENV-001 naming audit over one repo. Reports each violating name with its
# source surface. Untracked .env* value files are ADVISORY only (local dev,
# never fail the audit). Returns 0 = clean, 1 = violations found.
check_env_naming() {
    local project_root="$1"
    local violations=0
    local file name

    local in_git=false
    if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        in_git=true
    fi

    # --- Tracked env schema/template files (the stored-name surface) ---------
    local tracked_env_files=()
    if [[ "$in_git" == "true" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && tracked_env_files+=("$file")
        done < <(git -C "$project_root" ls-files '.env.example' '.env.template' '.env.*' '.env' 2>/dev/null)
    else
        for file in .env.example .env.template; do
            [[ -f "$project_root/$file" ]] && tracked_env_files+=("$file")
        done
    fi

    for file in "${tracked_env_files[@]}"; do
        while IFS= read -r name; do
            [[ -n "$name" ]] || continue
            if ! _manifest_env_name_allowed "$name"; then
                echo "      ❌ $file: $name (not FIDENCE_-prefixed or allowlisted)"
                violations=$((violations + 1))
            fi
        done < <(_manifest_env_names_from_dotenv "$project_root/$file")
    done

    # --- Spec env: block (the source of truth, D-ENV-2) ----------------------
    local spec
    for spec in service.spec.yaml app.spec.yaml; do
        [[ -f "$project_root/$spec" ]] || continue
        command -v yq >/dev/null 2>&1 || continue
        while IFS= read -r name; do
            [[ -n "$name" && "$name" != "null" ]] || continue
            if ! _manifest_env_name_allowed "$name"; then
                echo "      ❌ $spec: env[].name $name (not FIDENCE_-prefixed or allowlisted)"
                violations=$((violations + 1))
            fi
        done < <(yq e '.env[].name // ""' "$project_root/$spec" 2>/dev/null)
    done

    # --- Compose interpolation refs (stored side of the bridge) --------------
    local compose_files=()
    if [[ "$in_git" == "true" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && compose_files+=("$file")
        done < <(git -C "$project_root" ls-files 'docker-compose*.yml' 'docker-compose*.yaml' 'compose*.yml' 'compose*.yaml' 2>/dev/null)
    else
        for file in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            [[ -f "$project_root/$file" ]] && compose_files+=("$file")
        done
    fi

    for file in "${compose_files[@]}"; do
        while IFS= read -r name; do
            [[ -n "$name" ]] || continue
            if ! _manifest_env_name_allowed "$name"; then
                echo "      ❌ $file: \${$name} (compose RHS must reference a FIDENCE_ stored name)"
                violations=$((violations + 1))
            fi
        done < <(_manifest_env_names_from_compose "$project_root/$file")
    done

    # --- Untracked local value files: advisory only ---------------------------
    if [[ "$in_git" == "true" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] || continue
            local advisory_names=""
            while IFS= read -r name; do
                [[ -n "$name" ]] || continue
                _manifest_env_name_allowed "$name" || advisory_names+="$name "
            done < <(_manifest_env_names_from_dotenv "$project_root/$file")
            if [[ -n "$advisory_names" ]]; then
                echo "      ℹ️  $file (untracked, advisory): ${advisory_names% }"
            fi
        done < <(git -C "$project_root" ls-files --others --exclude-standard '.env' '.env.*' 2>/dev/null; \
                 git -C "$project_root" ls-files --others -i --exclude-standard '.env' '.env.*' 2>/dev/null)
    fi

    [ $violations -eq 0 ]
}
