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

## What It Does Not Do By Default

Docs-site generation is disabled by default. It does not create build artifacts in the repository and it does not enable GitHub Pages unless configured.

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
    enabled: true
    enable_pages: false
    pages_required: false
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
| `docs.site.enable_pages` | Ask `gh api` to enable workflow-based Pages publishing |
| `docs.site.pages_required` | Fail if Pages enablement cannot be completed |
| `docs.site.source_dir` | Source directory for managed site files |

## Verification

The focused regression suite is containerized:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
```

The suite proves managed file generation, collision refusal, workflow generation, and the `gh api` Pages enablement call path.
