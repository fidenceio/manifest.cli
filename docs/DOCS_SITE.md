# Docs Site Generation

Manifest can build a small documentation website for your repository and publish it
with GitHub Pages. This is **off by default** — you turn it on when you want it.

A few terms used below:

- **Jekyll** is the site builder GitHub Pages runs. It turns Markdown files into HTML.
- **GitHub Pages** is GitHub's free web hosting for a repository.
- **Managed file** means Manifest wrote it and may rewrite it. Manifest marks each one
  with a comment so it can tell its own files from yours.

## What It Generates

When you enable it, Manifest writes a source directory — `docs-site/` unless you
choose another name — containing:

- `_config.yml` — Jekyll's settings
- `index.md` — the landing page
- `_layouts/default.html` — the page template
- `assets/css/manifest.css` — the stylesheet
- `.gitignore` — keeps Jekyll's build output out of git

If workflow generation is also on (it is, once the site is on), Manifest writes:

- `.github/workflows/manifest-docs-pages.yml`

That workflow asks GitHub Pages to build the site and publish the result.

## Defaults

The site is off until you ask for it. Once you do, the pieces that support it are
already on, so enabling one key is normally enough.

| Setting | Default | Meaning |
| --- | --- | --- |
| `docs.generate.enabled` | **on** | Manifest's documentation generation in general (changelog, index, README version) |
| `docs.generate.site` | **off** | The website itself. **This is the switch to flip.** |
| `docs.site.enabled` | **off** | A second name for the same switch; either one turns the site on |
| `docs.generate.site_workflow` | on | Write the Pages workflow — only takes effect once the site is on |
| `docs.site.enable_pages` | on | Ask GitHub to turn Pages on — only takes effect once the site is on |

So the shortest way to get a site is one line:

```yaml
docs:
  generate:
    site: true
```

Manifest never commits Jekyll's build output. Only the source files above are
committed.

## Behavior

**Turning on Pages is best-effort and never stops a release.** If GitHub refuses —
most often a private repository on a plan that does not include Pages for private
repos, which returns HTTP 422 — Manifest prints a notice and carries on. The site
source and the workflow are still committed, so publishing starts by itself once
Pages becomes available. Make the repository public or upgrade the plan, and nothing
else is needed.

**Manifest will not overwrite files you wrote.** Every file it manages carries a
marker comment. If `docs-site/index.md` (or any other target) already exists *without*
that marker, Manifest stops rather than replacing it. Move your file aside if you want
Manifest to take over that path.

**The landing page carries no version number.** Because generation is opt-in, the page
is written once and then sits unchanged until you regenerate — a version baked into it
would slowly become wrong. It once advertised `v50.1.2` while the project was on
`59.3.0`. The changelog it links to always states its own latest version.

## Configuration

A fuller example, if you want to set more than the one switch:

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

| Key | Meaning |
| --- | ------- |
| `docs.generate.site` | Build the managed Jekyll source |
| `docs.generate.site_workflow` | Write the Pages workflow (applies only when the site is on) |
| `docs.site.enabled` | Alternate switch for site generation |
| `docs.site.enable_pages` | Best-effort request to GitHub to enable Pages; never fatal |
| `docs.site.source_dir` | Where the managed site files go |

Leaving `title` and `description` empty makes Manifest derive them from the repository
name.

## Verification

The focused regression suite runs in a container:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
```

It covers four things: that the managed files are written, that Manifest refuses to
overwrite an unmarked file, that the workflow is generated, and that the call asking
GitHub to enable Pages is made.
