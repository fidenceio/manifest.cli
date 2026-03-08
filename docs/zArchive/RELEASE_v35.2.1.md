# Release v35.2.1

Release date: 2026-03-08  
Release type: patch

## Scope

This release continues stabilization of the Manifest CLI release pipeline, with emphasis on generated documentation consistency and package delivery alignment.

## Operational Notes

- `prep` remains a local preparation flow.
- `ship` remains the publish flow.
- PR workflow remains explicit through `manifest pr ...`.

## Install / Upgrade

```bash
brew tap fidenceio/tap
brew install manifest
brew update && brew upgrade manifest
```

## Related

- `docs/CHANGELOG_v35.2.1.md`
- `CHANGELOG.md`
