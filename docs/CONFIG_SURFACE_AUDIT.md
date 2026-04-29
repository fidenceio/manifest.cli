# Manifest CLI Config Surface Audit

Generated: 2026-04-26

This chart separates persisted YAML configuration from `MANIFEST_CLI_*`
environment variables used as implementation plumbing. Today the CLI loads YAML
from global, project, and local config files, maps YAML paths to env vars in
`modules/core/manifest-yaml.sh`, then runtime modules consume those env vars.

Configuration policy:

- Every user-facing configurable behavior has a YAML key.
- Internal computed/process variables may remain shell variables.

## Summary

| Area | Current state | Count | Recommendation |
| --- | --- | ---: | --- |
| YAML-backed config | Mapped in `_MANIFEST_YAML_TO_ENV` | 76 | Keep as canonical user config, but runtime can still consume normalized env vars. |
| Defaults with no YAML mapping | Defaulted in `manifest-config.sh`, not mapped | 2 | Add mapping only if these should be user-facing config. |
| YAML mapping missing from example file | Mapped in code, absent from `examples/manifest.config.yaml.example` | 8 | Add to the example schema. |
| Example-only YAML key | Present in example, no runtime mapping | 1 | Either wire it or remove it from the example. |
| Env-only migration candidates | User-facing toggles or policy choices | 13 | Add YAML keys with env override compatibility. |
| Env-only internals | Runtime state, bootstrap, constants, test harness vars | Many | Keep out of YAML unless intentionally promoted to user config. |

## YAML-Backed Config

These are already YAML-first from the user's perspective. The env var is the
internal normalized form used by shell modules.

| YAML section | YAML paths | Env vars |
| --- | ---: | ---: |
| `version` | 18 | `MANIFEST_CLI_VERSION_*`, component position, increment, reset vars |
| `release` | 1 | `MANIFEST_CLI_RELEASE_TAG_TARGET` |
| `git` | 14 | `MANIFEST_CLI_GIT_*` |
| `time` | 11 | `MANIFEST_CLI_TIME_SERVER*`, timeout, retries, cache, timezone vars |
| `docs` | 6 | `MANIFEST_CLI_DOCS_*` |
| `files` | 7 | `MANIFEST_CLI_README_FILE`, `VERSION_FILE`, path/ext vars |
| `install` | 4 | `MANIFEST_CLI_INSTALL_DIR`, `BIN_DIR`, temp vars |
| `brew` | 3 | `MANIFEST_CLI_BREW_*`, `MANIFEST_CLI_TAP_REPO` |
| `project` | 3 | `MANIFEST_CLI_PROJECT_*`, `MANIFEST_CLI_ORGANIZATION` |
| `auto_update` | 2 | `MANIFEST_CLI_AUTO_UPDATE`, `MANIFEST_CLI_UPDATE_COOLDOWN` |
| `config` | 1 | `MANIFEST_CLI_CONFIG_SCHEMA_VERSION` |
| `debug` | 4 | `MANIFEST_CLI_DEBUG`, `VERBOSE`, `LOG_LEVEL`, `INTERACTIVE` |
| `pr` | 2 | `MANIFEST_CLI_PR_PROFILE`, `MANIFEST_CLI_PR_ENFORCE_READY` |

## Schema Drift

| Issue | Instances | Fix |
| --- | --- | --- |
| Mapped but missing from example YAML | `version.regex`, `version.validation`, `debug.enabled`, `debug.verbose`, `debug.log_level`, `debug.interactive`, `pr.profile`, `pr.enforce_ready` | Add these to `examples/manifest.config.yaml.example`. |
| Example YAML key has no mapping | `project.team` | Add `project.team -> MANIFEST_CLI_PROJECT_TEAM` or remove it. |
| Defaults with no YAML mapping | `MANIFEST_CLI_CONFIG_GLOBAL`, `MANIFEST_CLI_CONFIG_LOCAL` | Usually keep as bootstrap/discovery settings; mapping inside YAML is less useful because config paths are needed before YAML is loaded. |

## Env-Only Migration Candidates

These are user-facing enough to deserve YAML support if the goal is full YAML
coverage. Keep env vars as overrides for CI and backward compatibility.

| Current env var | Proposed YAML path | Current role | Migration priority |
| --- | --- | --- | --- |
| `MANIFEST_CLI_CANONICAL_REPO_SLUGS` | `release.canonical_repo_slugs` or `brew.canonical_repo_slugs` | Gates canonical-only Homebrew/formula behavior | High |
| `MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS` | Deprecated alias for above | Legacy canonical gate | Do not add new YAML; migrate to canonical key |
| `MANIFEST_CLI_INTERACTIVE_MODE` | `ship.interactive` | Ship workflow prompt mode | High, because `debug.interactive` is a different-looking key |
| `MANIFEST_CLI_AUTO_CONFIRM` | `automation.auto_confirm` | Non-interactive safety-gate bypass for CI/scripts | Medium; keep env as one-shot override |
| `MANIFEST_CLI_QUIET_DEPRECATIONS` | `deprecations.quiet` | Suppresses deprecation warnings | Medium |
| `MANIFEST_CLI_OFFLINE_MODE` | `network.offline` | Documented offline mode | Medium |
| `MANIFEST_CLI_CLOUD_SKIP` | `cloud.skip` | Skips cloud behavior | Medium |
| `MANIFEST_CLI_CLOUD_API_KEY` | `cloud.api_key` or secret reference | Cloud credential | Low for committed YAML; acceptable only in local/private YAML or external secret reference |
| `MANIFEST_CLI_FLEET_MODE` | `fleet.mode` | Fleet auto/true/false mode | High if fleet remains first-class |
| `MANIFEST_CLI_FLEET_ROOT` | `fleet.root` | Explicit fleet root | High if fleet remains first-class |
| `MANIFEST_CLI_FLEET_CONFIG_FILENAME` | `fleet.config_filename` | Fleet config discovery | High if fleet remains first-class |
| `MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES` | `security.private_files` | Security scanner private-file list | Medium |
| `MANIFEST_CLI_SKIP_SECURITY_REPORT` | `security.skip_report` | Security report generation toggle | Medium |

## Env-Only Internals To Keep Out Of YAML

These are not good YAML candidates because they are computed, process-scoped, or
needed before config loading.

| Env var family | Examples | Why not YAML |
| --- | --- | --- |
| Bootstrap and re-exec | `MANIFEST_CLI_BASH_PATH`, `MANIFEST_CLI_BASH_REEXEC` | Needed before the CLI can load YAML. |
| Installer-only state | `MANIFEST_CLI_INSTALL_LOCATION`, `MANIFEST_CLI_LOCAL_BIN`, `MANIFEST_CLI_NAME`, `MANIFEST_CLI_TAP`, `MANIFEST_CLI_MIN_BASH_VERSION` | Installer runtime constants or host install choices. Some overlap with `install.*`, but these are pre-runtime installer variables. |
| Core module discovery | `MANIFEST_CLI_CORE_MODULES_DIR`, `MANIFEST_CLI_CORE_SCRIPT_DIR`, `MANIFEST_CLI_CORE_DIR`, `MANIFEST_CLI_CORE_BINARY_LOCATION` | Computed from the installed script location. |
| OS detection | `MANIFEST_CLI_OS_*` | Computed platform facts. |
| Time result state | `MANIFEST_CLI_TIME_TIMESTAMP`, `MANIFEST_CLI_TIME_SERVER`, `MANIFEST_CLI_TIME_OFFSET`, `MANIFEST_CLI_TIME_METHOD`, cache result vars | Outputs from trusted-time lookup, not config inputs. |
| Logging constants | `MANIFEST_CLI_SHARED_LOG_LEVEL_*` | Internal numeric constants. |
| Test harness | `MANIFEST_CLI_CACHE_DIR`, `MANIFEST_CLI_CORE_MODULES_DIR` in tests | Test setup only. |
| Config discovery constants | `MANIFEST_CLI_GLOBAL_CONFIG`, `MANIFEST_CLI_CONFIG_FILES`, `MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT` | Needed to find and validate YAML before mapped settings exist. |

## Recommended Next YAML Additions

`release.tag_target` is now part of the YAML surface:

```yaml
release:
  tag_target: "version_commit" # version_commit | release_head
```

Continue with canonical behavior because it directly affects release
artifacts:

```yaml
release:
  canonical_repo_slugs:
    - "fidenceio/manifest.cli"
    - "fidenceio/fidenceio.manifest.cli"
```

Then wire fleet and automation:

```yaml
ship:
  interactive: false

automation:
  auto_confirm: false

deprecations:
  quiet: false

fleet:
  mode: "auto"
  root: ""
  config_filename: "manifest.fleet.yaml"
```

For secrets, avoid normal committed project YAML. Prefer local YAML or secret
references:

```yaml
cloud:
  skip: false
  api_key_env: "MANIFEST_CLI_CLOUD_API_KEY"
```
