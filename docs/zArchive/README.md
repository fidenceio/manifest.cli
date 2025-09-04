# 📚 Past Releases

This directory contains historical documentation for previous versions of Manifest CLI.

## 🎯 Purpose

When a new version is released, the previous version's documentation files are automatically moved here to keep the main `docs/` directory clean and focused on current information.

## 📁 Contents

- **RELEASE_v{version}.md** - Release notes for each version
- **CHANGELOG_v{version}.md** - Changelog for each version
- **Other version-specific files** - Any additional documentation tied to specific versions

## 🔄 Automatic Management

- **Moving**: Previous version files are automatically moved here during version updates
- **Cleanup**: Only the 20 most recent versions are kept to prevent directory bloat
- **Organization**: Files are organized by version for easy reference

## 📖 Accessing Historical Information

To view documentation for a specific version:

```bash
# View release notes for version 8.6.7
cat docs/past_releases/RELEASE_v8.6.7.md

# View changelog for version 8.6.7
cat docs/past_releases/CHANGELOG_v8.6.7.md
```

## 🧹 Manual Cleanup

If you need to manually clean up this directory:

```bash
# List all files
ls -la docs/past_releases/

# Remove specific version files
rm docs/past_releases/*_v8.6.7.*

# Remove all historical files (use with caution)
rm -rf docs/past_releases/*
```

---

*This directory is automatically managed by Manifest CLI during version updates.*
