# Manifest Fleet: Polyrepo Management Design Specification

**Version:** Draft 1.0
**Date:** 2026-01-28
**Status:** Proposal

---

## Table of Contents

1. [Design Principles](#design-principles)
2. [Configuration Architecture](#configuration-architecture)
3. [Fleet Configuration Schema](#fleet-configuration-schema)
4. [Single Repo vs Fleet Mode](#single-repo-vs-fleet-mode)
5. [Changelog Strategy](#changelog-strategy)
6. [Edge Cases & Error Handling](#edge-cases--error-handling)
7. [Command Reference](#command-reference)
8. [Migration Path](#migration-path)

---

## Design Principles

### 1. Backward Compatibility First
- Single repos work exactly as they do today
- No breaking changes to existing workflows
- Fleet features are additive, not replacement

### 2. Convention Over Configuration
- Smart defaults that "just work"
- Explicit configuration only when needed
- Auto-detection where possible

### 3. Fail Safe, Not Fail Silent
- Clear error messages for every failure mode
- Rollback capability for partial failures
- Dry-run support for all fleet operations

### 4. Respect Repo Autonomy
- Each repo maintains its own VERSION, CHANGELOG, config
- Fleet orchestrates, does not dictate
- Teams can opt-out of fleet operations per-repo

---

## Configuration Architecture

### Configuration Precedence (Lowest to Highest)

```
1. Built-in defaults (in code)
        ↓
2. ~/.env.manifest.global (user-level)
        ↓
3. <fleet-root>/.env.manifest.local (fleet-level)
        ↓
4. <fleet-root>/manifest.fleet.yaml (fleet definition)
        ↓
5. <repo>/.env.manifest.local (repo-level overrides)
        ↓
6. Command-line flags (highest priority)
```

### File Locations

```
# Single Repo (existing)
my-repo/
├── .env.manifest.local      # Repo-specific config (git-ignored)
├── VERSION
└── ...

# Fleet Workspace
fleet-workspace/
├── .env.manifest.local      # Fleet-level config (git-ignored)
├── manifest.fleet.yaml      # Fleet definition (committed)
├── CHANGELOG_FLEET.md       # Unified changelog (committed)
│
├── user-service/
│   ├── .env.manifest.local  # Service-specific overrides
│   ├── VERSION
│   └── CHANGELOG.md
│
└── order-service/
    ├── .env.manifest.local
    ├── VERSION
    └── CHANGELOG.md
```

---

## Fleet Configuration Schema

### manifest.fleet.yaml

```yaml
# manifest.fleet.yaml - Fleet Definition
# This file is COMMITTED to version control

# =============================================================================
# FLEET METADATA
# =============================================================================
fleet:
  name: "acme-platform"
  description: "ACME Corp Microservices Platform"

  # Optional fleet-level versioning
  # Options: "none" | "date" | "semver" | "increment"
  versioning: "date"  # Generates: 2026.01.28

  # Fleet version file (only if versioning != "none")
  version_file: "FLEET_VERSION"

# =============================================================================
# SERVICES / REPOSITORIES
# =============================================================================
services:
  # ---------------------------------------------------------------------------
  # Local path reference (repo already cloned)
  # ---------------------------------------------------------------------------
  user-service:
    path: "./user-service"              # Relative to fleet root
    description: "User authentication and profile management"

    # Optional: Override default branch for this service
    branch: "main"

    # Optional: Service-specific version file (default: VERSION)
    version_file: "VERSION"

    # Optional: Exclude from fleet operations
    # Use case: Legacy service being deprecated
    exclude_from_fleet_bump: false

    # Optional: Service type for changelog categorization
    type: "service"  # service | library | infrastructure | tool

    # Optional: Team ownership (for notifications/attribution)
    team: "auth-team"

  # ---------------------------------------------------------------------------
  # Remote URL reference (will be cloned)
  # ---------------------------------------------------------------------------
  order-service:
    url: "git@github.com:acme/order-service.git"
    path: "./order-service"             # Where to clone
    branch: "main"
    type: "service"
    team: "commerce-team"

  # ---------------------------------------------------------------------------
  # Shared library (special handling for breaking changes)
  # ---------------------------------------------------------------------------
  shared-lib:
    path: "./libs/shared"
    type: "library"
    team: "platform-team"

    # Libraries get special treatment:
    # - Breaking changes trigger warnings for all dependents
    # - Version bumps can cascade notifications

  # ---------------------------------------------------------------------------
  # Git submodule reference
  # ---------------------------------------------------------------------------
  infra-config:
    path: "./infrastructure"
    type: "infrastructure"
    submodule: true                     # Indicates this is a git submodule

    # Submodule-specific options
    submodule_update: "checkout"        # checkout | rebase | merge

# =============================================================================
# DEPENDENCIES (Optional but recommended)
# =============================================================================
dependencies:
  # Format: service-name: [list of dependencies with version constraints]

  user-service:
    - shared-lib: "^3.0.0"              # Semver constraint

  order-service:
    - shared-lib: "^3.0.0"
    - user-service: ">=2.0.0"           # Depends on user-service API

  # Dependencies are used for:
  # 1. Compatibility matrix generation
  # 2. Breaking change impact analysis
  # 3. Cascade notifications on major bumps

# =============================================================================
# CHANGELOG CONFIGURATION
# =============================================================================
changelog:
  # Unified fleet changelog
  unified:
    enabled: true
    file: "CHANGELOG_FLEET.md"

    # What to include in unified changelog
    include:
      - summary_table: true             # Version summary table
      - breaking_changes: true          # Highlighted breaking changes
      - per_service_sections: true      # Collapsed per-service details
      - compatibility_matrix: true      # Dependency compatibility
      - migration_guides: true          # For major version bumps

    # How much detail to pull from each service
    # "full" = entire changelog, "summary" = key sections only
    detail_level: "summary"

  # Per-service changelog settings
  per_service:
    enabled: true                       # Each service keeps its own changelog

    # Sync service changelogs to a central location (optional)
    sync_to_fleet: false
    sync_path: "./changelogs/"

# =============================================================================
# FLEET OPERATIONS CONFIGURATION
# =============================================================================
operations:
  # What happens on `manifest fleet go`
  default_bump: "patch"                 # Default version increment

  # Parallel vs sequential operations
  parallel: true
  max_parallel: 4

  # Commit strategy
  commit:
    # "per-service" = one commit per service
    # "atomic" = single commit in fleet repo referencing all changes
    strategy: "per-service"

    # Include fleet version in service commits
    include_fleet_version: true

  # Push strategy
  push:
    # "immediate" = push each service as it's done
    # "batched" = push all at end
    # "manual" = don't push, user will push
    strategy: "batched"

  # Tag strategy
  tags:
    per_service: true                   # Tag each service: v2.1.0
    fleet_tag: true                     # Also tag fleet: fleet-2026.01.28

# =============================================================================
# NOTIFICATIONS (Optional)
# =============================================================================
notifications:
  # Notify on breaking changes
  breaking_changes:
    enabled: true
    # Future: Slack, email, GitHub issues
    method: "console"

  # Notify dependent services when a library bumps major
  cascade_alerts:
    enabled: true
    method: "console"

# =============================================================================
# VALIDATION RULES
# =============================================================================
validation:
  # Require all services to be on same major version
  enforce_major_alignment: false

  # Require dependency constraints to be satisfied
  enforce_dependencies: true

  # Require clean git status before fleet operations
  require_clean_status: true

  # Allow fleet operations on non-default branches
  allow_non_default_branch: false
```

---

## .env.manifest.local Extensions for Fleet

Add these new variables to support fleet configuration:

```bash
# =============================================================================
# FLEET CONFIGURATION (in .env.manifest.local)
# =============================================================================

# -----------------------------------------------------------------------------
# FLEET DETECTION
# -----------------------------------------------------------------------------
# Is this repo part of a fleet?
# "auto" = detect from manifest.fleet.yaml presence
# "true" = force fleet mode
# "false" = force single-repo mode (ignore any fleet.yaml)
MANIFEST_CLI_FLEET_MODE="auto"

# Path to fleet root (if this repo is nested within a fleet)
# Leave empty for auto-detection (walks up directory tree)
MANIFEST_CLI_FLEET_ROOT=""

# -----------------------------------------------------------------------------
# FLEET IDENTITY (for services within a fleet)
# -----------------------------------------------------------------------------
# This service's name in the fleet (must match manifest.fleet.yaml)
MANIFEST_CLI_FLEET_SERVICE_NAME=""

# Override: Exclude this service from fleet bump operations
MANIFEST_CLI_FLEET_EXCLUDE_FROM_BUMP="false"

# Override: This service's team (for changelog attribution)
MANIFEST_CLI_FLEET_TEAM=""

# -----------------------------------------------------------------------------
# FLEET CHANGELOG
# -----------------------------------------------------------------------------
# Generate unified fleet changelog
MANIFEST_CLI_FLEET_CHANGELOG_UNIFIED="true"

# Detail level in unified changelog: "full" | "summary" | "minimal"
MANIFEST_CLI_FLEET_CHANGELOG_DETAIL="summary"

# Include compatibility matrix in fleet changelog
MANIFEST_CLI_FLEET_CHANGELOG_MATRIX="true"

# -----------------------------------------------------------------------------
# FLEET OPERATIONS
# -----------------------------------------------------------------------------
# Default bump type for fleet operations
MANIFEST_CLI_FLEET_DEFAULT_BUMP="patch"

# Run fleet operations in parallel
MANIFEST_CLI_FLEET_PARALLEL="true"

# Maximum parallel operations
MANIFEST_CLI_FLEET_MAX_PARALLEL="4"

# Push strategy: "immediate" | "batched" | "manual"
MANIFEST_CLI_FLEET_PUSH_STRATEGY="batched"

# -----------------------------------------------------------------------------
# FLEET SUBMODULES
# -----------------------------------------------------------------------------
# How to handle submodules in fleet: "include" | "exclude" | "separate"
MANIFEST_CLI_FLEET_SUBMODULE_HANDLING="include"

# Submodule update strategy: "checkout" | "rebase" | "merge"
MANIFEST_CLI_FLEET_SUBMODULE_UPDATE="checkout"

# -----------------------------------------------------------------------------
# FLEET VALIDATION
# -----------------------------------------------------------------------------
# Require clean git status before fleet ops
MANIFEST_CLI_FLEET_REQUIRE_CLEAN="true"

# Enforce dependency version constraints
MANIFEST_CLI_FLEET_ENFORCE_DEPS="true"

# Allow operations on non-default branches
MANIFEST_CLI_FLEET_ALLOW_BRANCH_OPS="false"

# -----------------------------------------------------------------------------
# FLEET NOTIFICATIONS
# -----------------------------------------------------------------------------
# Alert on breaking changes (major bumps in libraries)
MANIFEST_CLI_FLEET_ALERT_BREAKING="true"

# Alert method: "console" | "slack" | "github-issue"
MANIFEST_CLI_FLEET_ALERT_METHOD="console"
```

---

## Single Repo vs Fleet Mode

### Detection Logic

```
┌─────────────────────────────────────────────────────────────┐
│                    manifest go patch                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                 ┌────────────────────────┐
                 │ MANIFEST_CLI_FLEET_MODE │
                 │ in .env.manifest.local? │
                 └────────────────────────┘
                    │         │         │
            "false" │  "auto" │  "true" │
                    │         │         │
                    ▼         ▼         ▼
              ┌─────────┐ ┌─────────────────┐ ┌──────────────┐
              │ SINGLE  │ │ Check for       │ │ FLEET MODE   │
              │ REPO    │ │ manifest.fleet  │ │ (find fleet  │
              │ MODE    │ │ .yaml in cwd    │ │  root)       │
              └─────────┘ │ or parent dirs  │ └──────────────┘
                          └─────────────────┘
                              │         │
                        Found │         │ Not Found
                              ▼         ▼
                        ┌─────────┐ ┌─────────┐
                        │ FLEET   │ │ SINGLE  │
                        │ MODE    │ │ REPO    │
                        └─────────┘ └─────────┘
```

### Behavior Comparison

| Operation | Single Repo | Fleet Mode |
|-----------|-------------|------------|
| `manifest go patch` | Bump this repo | Bump all services in fleet |
| `manifest version` | Show this repo version | Show fleet + all service versions |
| `manifest docs` | Generate repo docs | Generate per-repo + unified docs |
| `manifest sync` | Sync this repo | Sync all repos in fleet |
| `manifest status` | Git status | Fleet-wide status matrix |

### Escaping Fleet Mode

When inside a fleet, you can still operate on a single service:

```bash
# Operate on fleet (default when fleet detected)
manifest go patch

# Operate on just this service (escape fleet mode)
manifest go patch --single
# or
cd user-service && MANIFEST_CLI_FLEET_MODE=false manifest go patch
```

---

## Changelog Strategy

### Per-Service Changelog (Unchanged)

Each service maintains its own changelog exactly as today:

```
user-service/
├── VERSION                      # 2.1.0
├── CHANGELOG.md                 # Latest (root-level, for GitHub)
└── docs/
    ├── CHANGELOG_v2.1.0.md      # Version-specific
    ├── CHANGELOG_v2.0.0.md
    └── zArchive/
        └── CHANGELOG_v1.x.x.md
```

**Content** (unchanged from current Manifest output):
- New Features
- Improvements
- Bug Fixes
- Documentation
- Actual Changes (from git diff)

### Unified Fleet Changelog (New)

Located at fleet root:

```
fleet-workspace/
├── CHANGELOG_FLEET.md           # Latest unified
└── docs/
    └── fleet/
        ├── CHANGELOG_FLEET_2026.01.28.md
        └── CHANGELOG_FLEET_2026.01.21.md
```

**Structure:**

```markdown
# ACME Platform Fleet Changelog

**Fleet Version:** 2026.01.28
**Release Date:** 2026-01-28 14:30:00 UTC
**Services Updated:** 3 of 5

---

## Release Summary

| Service | Previous | Current | Change | Team |
|---------|----------|---------|--------|------|
| user-service | 2.0.0 | 2.1.0 | minor | auth-team |
| order-service | 1.5.0 | 1.5.0 | - | commerce-team |
| shared-lib | 2.9.0 | 3.0.0 | **MAJOR** | platform-team |
| gateway | 4.1.0 | 4.2.0 | minor | platform-team |
| infra-config | - | - | unchanged | devops |

---

## Breaking Changes

### shared-lib `v3.0.0`

**Impact:** user-service, order-service, gateway

- Removed deprecated `authenticate()` method - use `authenticateV2()`
- Changed `User` interface: `name` property renamed to `displayName`
- Minimum Node.js version increased to 18.x

<details>
<summary>Migration Guide</summary>

```bash
# Update imports
sed -i 's/authenticate(/authenticateV2(/g' src/**/*.ts

# Update User interface usage
sed -i 's/\.name/.displayName/g' src/**/*.ts
```

</details>

---

## Service Details

<details>
<summary>user-service v2.1.0</summary>

### New Features
- Added OAuth2 support for third-party login (#142)
- New `/users/bulk` endpoint for batch operations (#156)

### Bug Fixes
- Fixed session timeout not respecting config (#148)

[Full changelog](./user-service/docs/CHANGELOG_v2.1.0.md)

</details>

<details>
<summary>gateway v4.2.0</summary>

### Improvements
- Upgraded to shared-lib v3.0.0
- Added request tracing headers

[Full changelog](./gateway/docs/CHANGELOG_v4.2.0.md)

</details>

---

## Dependency Compatibility Matrix

| Service | shared-lib | user-service | order-service |
|---------|------------|--------------|---------------|
| user-service@2.1.0 | >=3.0.0 | - | - |
| order-service@1.5.0 | >=3.0.0 | >=2.0.0 | - |
| gateway@4.2.0 | >=3.0.0 | >=2.1.0 | >=1.5.0 |

**Legend:**
- Requires version
- - No direct dependency

---

## NTP Verification

| Service | Timestamp | NTP Server | Offset |
|---------|-----------|------------|--------|
| user-service | 2026-01-28 14:30:12 UTC | time.apple.com | +0.003s |
| shared-lib | 2026-01-28 14:30:08 UTC | time.apple.com | +0.002s |
| gateway | 2026-01-28 14:30:15 UTC | time.apple.com | +0.004s |

---

*Generated by Manifest CLI Fleet v28.4.0*
```

### Changelog Generation Flow

```
┌─────────────────────────────────────────────────────────────┐
│                  manifest fleet go minor                     │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
   │ user-service│     │order-service│     │  shared-lib │
   │   VERSION++ │     │  VERSION++  │     │  VERSION++  │
   │   CHANGELOG │     │  CHANGELOG  │     │  CHANGELOG  │
   │   RELEASE   │     │   RELEASE   │     │   RELEASE   │
   └─────────────┘     └─────────────┘     └─────────────┘
          │                   │                   │
          └───────────────────┼───────────────────┘
                              │
                              ▼
                 ┌────────────────────────┐
                 │  AGGREGATE & ANALYZE   │
                 │  - Collect all changes │
                 │  - Detect breaking     │
                 │  - Build dep matrix    │
                 └────────────────────────┘
                              │
                              ▼
                 ┌────────────────────────┐
                 │  GENERATE UNIFIED      │
                 │  CHANGELOG_FLEET.md    │
                 └────────────────────────┘
                              │
                              ▼
                 ┌────────────────────────┐
                 │  COMMIT & TAG          │
                 │  - Per-service tags    │
                 │  - Fleet tag           │
                 └────────────────────────┘
```

---

## Edge Cases & Error Handling

### 1. Partial Fleet Operations

**Scenario:** 3 of 5 services fail during `manifest fleet go`

**Handling:**
```
1. Complete successful operations (don't rollback)
2. Report which services failed and why
3. Save state to .manifest-fleet-state.json
4. Allow resume: `manifest fleet go --resume`
5. Allow selective retry: `manifest fleet go --only user-service,order-service
```

**State File:**
```json
{
  "operation": "fleet-go-minor",
  "started_at": "2026-01-28T14:30:00Z",
  "status": "partial",
  "services": {
    "user-service": { "status": "completed", "version": "2.1.0" },
    "order-service": { "status": "completed", "version": "1.6.0" },
    "shared-lib": { "status": "failed", "error": "merge conflict in src/index.ts" },
    "gateway": { "status": "pending" },
    "infra-config": { "status": "pending" }
  }
}
```

### 2. Circular Dependencies

**Scenario:** service-a depends on service-b, service-b depends on service-a

**Handling:**
```
1. Detect during manifest.fleet.yaml validation
2. Error with clear message:
   "Circular dependency detected: service-a -> service-b -> service-a"
3. Suggest resolution: "Consider extracting shared code to a library"
```

### 3. Version Constraint Violations

**Scenario:** user-service requires shared-lib@^3.0.0, but shared-lib is at 2.9.0

**Handling:**
```
1. Warn during `manifest fleet status`
2. Block `manifest fleet go` unless:
   - shared-lib is also being bumped to satisfy constraint
   - User passes --ignore-constraints
3. Suggest: "Bump shared-lib to 3.0.0 first, or update constraint in user-service"
```

### 4. Mixed Hosting Platforms

**Scenario:** user-service on GitHub, order-service on GitLab

**Handling:**
```yaml
# manifest.fleet.yaml
services:
  user-service:
    url: "git@github.com:acme/user-service.git"
    platform: "github"  # Optional, auto-detected from URL

  order-service:
    url: "git@gitlab.com:acme/order-service.git"
    platform: "gitlab"
```

- Each service uses appropriate platform API for PR creation
- Unified changelog links to correct platform URLs

### 5. Submodule Within Fleet Service

**Scenario:** user-service itself contains a submodule

**Handling:**
```yaml
services:
  user-service:
    path: "./user-service"
    submodules:
      handling: "include"  # include | exclude | error
```

- `include`: Recursively init/update submodules during fleet sync
- `exclude`: Ignore service's internal submodules
- `error`: Fail if service contains submodules (strict mode)

### 6. Dirty Working Directory

**Scenario:** User has uncommitted changes in one service

**Handling:**
```
1. `manifest fleet go` checks all services first
2. If any dirty:
   - List which services have uncommitted changes
   - Offer options:
     a) Abort (default)
     b) Auto-commit with message "WIP: Pre-fleet-bump auto-commit"
     c) Stash changes, proceed, pop stash
     d) Proceed anyway (--allow-dirty)
```

### 7. Network Failure Mid-Push

**Scenario:** Pushed 3 of 5 services, network dies

**Handling:**
```
1. State file tracks push status per service
2. On resume, only push remaining services
3. Fleet tag is only created after ALL services pushed
4. If fleet tag fails, it can be retried: `manifest fleet tag --retry`
```

### 8. Service Not a Git Repository

**Scenario:** Path in manifest.fleet.yaml exists but isn't a git repo

**Handling:**
```
1. During `manifest fleet status`: Mark as "not initialized"
2. During `manifest fleet sync`:
   - If URL provided: Clone it
   - If no URL: Error "service 'x' at path 'y' is not a git repository and no URL provided"
```

### 9. Fleet Root Detection Ambiguity

**Scenario:** Nested fleet structures (fleet within fleet)

**Handling:**
```
1. Walk up from cwd, use FIRST manifest.fleet.yaml found
2. Warn if multiple found: "Multiple fleet configs detected. Using: /path/to/fleet"
3. Allow explicit override: MANIFEST_CLI_FLEET_ROOT=/specific/path
```

### 10. Version File Missing in Service

**Scenario:** Service doesn't have a VERSION file

**Handling:**
```
1. During `manifest fleet status`: Warn "service 'x' missing VERSION file"
2. During `manifest fleet go`:
   - Create VERSION file with "1.0.0" (with confirmation)
   - Or error if --strict mode
```

### 11. Branch Mismatch

**Scenario:** manifest.fleet.yaml says branch: main, but service is on develop

**Handling:**
```
1. During validation: Warn "service 'x' is on 'develop' but fleet expects 'main'"
2. Offer options:
   a) Switch to expected branch (may have uncommitted changes issue)
   b) Proceed on current branch (--allow-branch-mismatch)
   c) Update fleet.yaml to expect current branch
   d) Abort
```

### 12. Offline Mode

**Scenario:** No network connectivity

**Handling:**
```
1. Detect network status before operations requiring remote
2. Allow local-only operations:
   - Version bump: YES
   - Changelog generation: YES
   - Commit: YES
   - Push: NO (queue for later)
   - Remote sync: NO (use local state)
3. Save pending pushes to state file
4. `manifest fleet push --pending` when back online
```

---

## Command Reference

### New Fleet Commands

```bash
# -----------------------------------------------------------------------------
# FLEET MANAGEMENT
# -----------------------------------------------------------------------------

# Initialize a new fleet in current directory
manifest fleet init
# Creates manifest.fleet.yaml with interactive prompts

# Add a service to the fleet
manifest fleet add <path-or-url> [--name <name>] [--type <type>]
# Examples:
#   manifest fleet add ./user-service
#   manifest fleet add git@github.com:acme/order-service.git --name order-service

# Remove a service from fleet (doesn't delete files)
manifest fleet remove <service-name>

# -----------------------------------------------------------------------------
# FLEET OPERATIONS
# -----------------------------------------------------------------------------

# Sync all services (clone missing, pull existing)
manifest fleet sync [--parallel] [--include-submodules]

# Show fleet status (versions, git status, dep health)
manifest fleet status [--verbose]

# Bump versions across fleet
manifest fleet go [patch|minor|major] [options]
#   --single              # Only bump current service (escape fleet mode)
#   --only <services>     # Comma-separated list of services to bump
#   --exclude <services>  # Comma-separated list to skip
#   --dry-run             # Show what would happen
#   --resume              # Resume from partial failure
#   --no-push             # Bump and commit, but don't push
#   --no-unified-changelog # Skip unified changelog generation

# Generate documentation only (no version bump)
manifest fleet docs [--unified-only | --per-service-only]

# Push pending changes (after --no-push or network failure)
manifest fleet push [--pending]

# -----------------------------------------------------------------------------
# FLEET INSPECTION
# -----------------------------------------------------------------------------

# Show dependency graph
manifest fleet deps [--format tree|json|dot]

# Check dependency constraint satisfaction
manifest fleet check [--strict]

# Show version history across fleet
manifest fleet history [--limit 10]

# -----------------------------------------------------------------------------
# FLEET CONFIGURATION
# -----------------------------------------------------------------------------

# Validate manifest.fleet.yaml
manifest fleet validate

# Show effective configuration (merged from all sources)
manifest fleet config
```

### Modified Existing Commands

```bash
# These commands gain fleet-awareness:

manifest go patch
# In fleet: Bumps all services
# --single flag: Only bump current service

manifest status
# In fleet: Shows fleet-wide status matrix

manifest sync
# In fleet: Syncs all services

manifest docs
# In fleet: Generates per-service + unified docs

manifest config
# In fleet: Shows fleet config merged with service config
```

---

## Migration Path

### From Single Repo to Fleet

```bash
# 1. Create fleet structure
mkdir my-fleet && cd my-fleet

# 2. Initialize fleet
manifest fleet init
# Interactive prompts for fleet name, versioning strategy

# 3. Add existing repos
manifest fleet add ../user-service
manifest fleet add ../order-service
manifest fleet add git@github.com:acme/shared-lib.git

# 4. Define dependencies (edit manifest.fleet.yaml)
# Or use:
manifest fleet deps add user-service shared-lib "^3.0.0"

# 5. Validate
manifest fleet validate

# 6. First fleet operation
manifest fleet go patch --dry-run
manifest fleet go patch
```

### From Submodules to Fleet

```bash
# If you have a repo with submodules you want to convert:

# 1. In parent repo
manifest fleet init --from-submodules

# This will:
# - Read .gitmodules
# - Create manifest.fleet.yaml with each submodule as a service
# - Optionally: Convert submodules to regular clones
```

### Gradual Adoption

Teams can adopt fleet features gradually:

1. **Week 1:** Just use `manifest fleet status` for visibility
2. **Week 2:** Use `manifest fleet sync` for easier cloning
3. **Week 3:** Use `manifest fleet docs` for unified changelogs
4. **Week 4:** Use `manifest fleet go` for coordinated releases

Each step is independently valuable.

---

## Implementation Phases

### Phase 1: Foundation
- [ ] Fleet detection logic
- [ ] manifest.fleet.yaml parser
- [ ] `manifest fleet init`
- [ ] `manifest fleet status`
- [ ] `manifest fleet validate`

### Phase 2: Sync & Clone
- [ ] `manifest fleet sync`
- [ ] `manifest fleet add`
- [ ] `manifest fleet remove`
- [ ] Submodule handling

### Phase 3: Coordinated Operations
- [ ] `manifest fleet go`
- [ ] Parallel execution
- [ ] State tracking & resume
- [ ] Per-service + unified changelogs

### Phase 4: Dependencies & Analysis
- [ ] Dependency graph
- [ ] Constraint checking
- [ ] Breaking change detection
- [ ] Compatibility matrix

### Phase 5: Polish
- [ ] Offline mode
- [ ] Notifications
- [ ] Platform integrations (GitHub/GitLab PR creation)
- [ ] CI/CD examples

---

*This specification is a living document and will evolve based on implementation learnings and user feedback.*
