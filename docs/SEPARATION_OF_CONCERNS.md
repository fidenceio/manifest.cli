# Separation of Concerns - Manifest Architecture

## Overview

This document outlines the proper separation of concerns between the `manifest.local` and `manifest.cloud` repositories, ensuring atomicity and clear boundaries.

## Repository Responsibilities

### 🏠 Manifest Local (`fidenceio.manifest.local`)

**Purpose**: Local development environment and Git operations

**Responsibilities**:
- ✅ **Local Git Operations**: Version bumping, commits, pushing
- ✅ **Cloud Service Integration**: Client library for cloud API calls
- ✅ **Local Development Tools**: CLI for local workflow
- ✅ **Repository Management**: Local repository state and operations

**What It Does NOT Do**:
- ❌ Manage cloud infrastructure
- ❌ Start/stop cloud services
- ❌ Handle cloud deployment

**CLI Commands**:
```bash
manifest push [patch|minor|major]  # Version bump, commit, push
manifest commit <message>           # Commit changes
manifest version [patch|minor|major] # Bump version only
manifest analyze                    # Analyze commits via cloud service
manifest changelog                  # Generate changelog via cloud service
manifest help                       # Show help
```

### ☁️ Manifest Cloud (`fidenceio.manifest.cloud`)

**Purpose**: Cloud-based LLM agent service

**Responsibilities**:
- ✅ **LLM Agent Service**: Intelligent commit analysis, version recommendations
- ✅ **Repository API**: GitHub CLI integration for repository management
- ✅ **Cloud Infrastructure**: Scalable, containerized service
- ✅ **API Endpoints**: RESTful interface for local clients

**What It Does NOT Do**:
- ❌ Manage local Git repositories
- ❌ Handle local development workflow
- ❌ Control local CLI operations

**CLI Commands** (Testing Only):
```bash
manifest-cloud test      # Run test suite
manifest-cloud start     # Start local testing environment
manifest-cloud stop      # Stop local testing environment
manifest-cloud status    # Show service status
manifest-cloud logs      # Show service logs
manifest-cloud help      # Show help
```

## Installation and Setup

### Local Development Setup
```bash
# In manifest.local repository
npm run install:cli

# This creates the manifest CLI in ~/.local/bin/
# Installs to ~/.manifest-local/
```

### Cloud Service Setup
```bash
# In manifest.cloud repository
./install-client.sh

# This creates the manifest-cloud CLI in ~/.local/bin/
# Installs to ~/.manifest-cloud/
# Only for testing purposes
```

## Communication Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Development                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              manifest CLI                            │   │
│  │           (Local Git Operations)                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                │
│                           ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              ManifestCloudClient                    │   │
│  │           (HTTP API Client)                        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 Cloud Service (manifest.cloud)             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              LLM Agent Service                      │   │
│  │           (Intelligent Analysis)                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Repository Service                     │   │
│  │           (GitHub CLI Integration)                 │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Atomic Operations

### Local Operations (manifest CLI)
- **Version Management**: Atomic version bumps with validation
- **Git Operations**: Atomic commits and pushes
- **Cloud Integration**: Atomic API calls with error handling

### Cloud Operations (manifest.cloud)
- **LLM Processing**: Atomic analysis operations
- **Repository Management**: Atomic GitHub operations
- **API Responses**: Atomic, consistent responses

## Configuration

### Local Configuration (`~/.manifest-local/.env`)
```bash
MANIFEST_CLOUD_URL=http://localhost:3001
MANIFEST_CLOUD_API_KEY=your-api-key-here
GIT_AUTO_COMMIT=true
GIT_AUTO_TAG=true
GIT_PUSH_ALL_REMOTES=true
```

### Cloud Configuration (`~/.manifest-cloud/.env`)
```bash
MANIFEST_SECRET=your-secret-key-here
NODE_ENV=production
PORT=3001
CORS_ORIGIN=*
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

## Deployment Models

### Local Development
- **manifest.local**: CLI tools and client library
- **manifest.cloud**: Local Docker containers for testing

### Production
- **manifest.local**: Client library only
- **manifest.cloud**: Cloud-hosted service (AWS, GCP, Azure)

## Benefits of This Architecture

1. **Clear Separation**: Each repository has a single, well-defined purpose
2. **Atomic Operations**: Operations are indivisible and consistent
3. **Scalability**: Cloud service can scale independently
4. **Maintainability**: Changes to one component don't affect the other
5. **Flexibility**: Different deployment models for different use cases
6. **Testing**: Local testing environment separate from production

## Migration Path

1. **Install Local CLI**: `npm run install:cli` in manifest.local
2. **Install Cloud Service**: `./install-client.sh` in manifest.cloud
3. **Configure Integration**: Set `MANIFEST_CLOUD_URL` in local config
4. **Test Integration**: Use `manifest analyze` and `manifest changelog`
5. **Deploy Cloud**: Deploy manifest.cloud to production platform

## Troubleshooting

### Local CLI Issues
- Check `~/.manifest-local/.env` configuration
- Verify `manifest` command is in PATH
- Ensure Node.js dependencies are installed

### Cloud Service Issues
- Check `~/.manifest-cloud/.env` configuration
- Verify Docker containers are running
- Check network connectivity to cloud service

### Integration Issues
- Verify `MANIFEST_CLOUD_URL` is correct
- Check API key authentication
- Ensure cloud service is accessible from local environment
