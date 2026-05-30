# Docs Site Generation

Manifest can generate a managed Jekyll source tree and, optionally, a GitHub Pages workflow. This is separate from the product marketing site.

## What It Generates

When enabled, Manifest writes a managed source directory, defaulting to `docs-site/`, with:

- `_config.yml`
- `index.md`
- `_layouts/default.html`
- `assets/css/manifest.css`
- `.gitignore`

If workflow generation is enabled, it also writes:

- `.github/workflows/manifest-docs-pages.yml`

The workflow builds the Jekyll source through GitHub Pages Actions and deploys the uploaded artifact.

## Defaults and Behavior

Docs-site generation, the Pages workflow, and GitHub Pages enablement are all on by default — Manifest generates the full docs experience without extra configuration. It never commits build artifacts to the repository.

Pages enablement is best-effort and never interrupts a run. If Pages cannot be enabled — most commonly a private repository on a GitHub plan that does not include Pages for private repos (HTTP 422) — Manifest emits a clear notice and continues. The managed site and the Pages workflow are still committed, so Pages publishes automatically the moment it becomes available (upgrade the plan or make the repo public).

The generator refuses unmanaged collisions. If `docs-site/index.md` or another target exists without the Manifest managed marker, Manifest stops instead of overwriting user-owned site files.

## Configuration

Project config example:

```yaml
docs:
  generate:
    enabled: true
    site: true
    site_workflow: true
  site:
    enable_pages: true
    source_dir: "docs-site"
    publish_mode: "actions"
    title: ""
    description: ""
```

Important keys:

| Key | Meaning |
| --- | ------- |
| `docs.generate.site` | Generate managed Jekyll source |
| `docs.generate.site_workflow` | Generate the Pages workflow when site generation is enabled |
| `docs.site.enabled` | Alternate switch for site generation |
| `docs.site.enable_pages` | Best-effort `gh api` enablement of workflow-based Pages publishing (never fatal) |
| `docs.site.source_dir` | Source directory for managed site files |

## Verification

The focused regression suite is containerized:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
```

The suite proves managed file generation, collision refusal, workflow generation, and the `gh api` Pages enablement call path.
