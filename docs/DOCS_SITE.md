# Docs Site Generation

Manifest can build a small documentation website for your repository and publish it
with GitHub Pages. Site generation is **on by default**. Manifest writes the site
source whenever it generates documentation, which includes every release. To turn it
off, see [Defaults](#defaults).

A few terms used below:

- **Jekyll** is the site builder that GitHub Pages runs. It turns Markdown files into
  HTML.
- **GitHub Pages** is GitHub's web hosting for a repository.
- **Managed file** means that Manifest wrote the file and may rewrite it. Manifest
  marks each managed file with a comment, so it can tell its own files from yours.

## What It Generates

Manifest writes a source directory. Its name is `docs-site/` unless you choose another.
It contains:

- `_config.yml` — Jekyll's settings
- `index.md` — the landing page
- `_layouts/default.html` — the page template
- `assets/css/manifest.css` — the stylesheet
- `.gitignore` — keeps Jekyll's build output out of git

When workflow generation is on, which is the default, Manifest also writes:

- `.github/workflows/manifest-docs-pages.yml`

That workflow asks GitHub Pages to build the site and publish the result.

Manifest never commits Jekyll's build output. It commits only the source files above.

## Defaults

| Setting | Default | Meaning |
| --- | --- | --- |
| `docs.generate.enabled` | on | Manifest's documentation generation in general (changelog, index, README version) |
| `docs.generate.site` | **on** | The website itself. **This is the switch to turn off.** |
| `docs.site.enabled` | off | A second switch for the same thing. The site is generated when either switch is on. |
| `docs.generate.site_workflow` | on | Write the Pages workflow. It takes effect only when the site is on. |
| `docs.site.enable_pages` | on | Ask GitHub to turn Pages on. It takes effect only when the site is on. |

To turn the site off, set one key and leave `docs.site.enabled` off:

```yaml
docs:
  generate:
    site: false
```

One of your config files may already set this key. Check them all, including the
global one, `~/.manifest-cli/manifest.config.global.yaml`.

## Behavior

**Turning on Pages is best-effort and never stops a release.** GitHub may refuse the
request. The most common reason is a private repository on a plan that does not include
Pages for private repositories. GitHub then returns HTTP 422. Manifest prints a notice
and carries on. The site source and the workflow are still committed, so publishing
starts by itself when Pages becomes available. Make the repository public or upgrade
the plan. Nothing else is needed.

**Manifest does not overwrite files you wrote.** Every file it manages carries a marker
comment. If `docs-site/index.md`, or any other target, already exists *without* that
marker, Manifest stops with an error and does not replace the file. During a release,
this stops the release at the documentation step. To let Manifest manage that path,
move your file aside. To keep your own file, turn the site off or set
`docs.site.source_dir` to a different folder.

**The landing page carries no version number.** A version written into the page would
go out of date whenever the page is not regenerated. The page links to the changelog,
which always states its own latest version.

## Configuration

A fuller example, if you want to set more than one switch:

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
| `docs.site.enabled` | Second switch for site generation |
| `docs.site.enable_pages` | Best-effort request to GitHub to enable Pages. A refusal is never fatal. |
| `docs.site.source_dir` | Where the managed site files go |
| `docs.site.publish_mode` | Accepted, but it has no effect. Manifest always publishes through the generated GitHub Actions workflow. |

If you leave `title` empty, Manifest derives it from the repository name. If you leave
`description` empty, Manifest uses "Documentation for" followed by the title.

## Verification

The focused regression suite runs in a container:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
```

Its site tests cover four things:

- Manifest writes the managed files and the Pages workflow.
- Manifest refuses to overwrite a file that has no marker.
- Manifest asks GitHub to enable Pages.
- A refused Pages request does not fail the run.
