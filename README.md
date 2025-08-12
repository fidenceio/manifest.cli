# Manifest Local - Complete Local Development System

A comprehensive local development system that combines a powerful CLI with a full-featured local service for automated Git workflows, version management, documentation generation, and continuous monitoring. Manifest Local runs entirely on your machine, providing enterprise-grade automation without external dependencies.

## 🚀 What Manifest Local Provides

### 🖥️ **Command Line Interface (CLI)**
- **Automated Version Management**: Bump versions with semantic versioning (patch, minor, major)
- **Smart Git Operations**: Auto-commit, tag, and push with conflict resolution
- **Documentation Generation**: Create release notes, changelogs, and README updates
- **Health Diagnostics**: Built-in troubleshooting and system health checks

### 🏗️ **Local Manifest Service**
- **Express.js Service**: Runs on localhost:3001 with full API endpoints
- **Database Integration**: PostgreSQL for persistent data storage
- **Caching Layer**: Redis for performance optimization
- **Container Orchestration**: Docker Compose for easy deployment

### 🔄 **Automated Workflows**
- **Heartbeat Monitoring**: Continuous repository health checking
- **Update Detection**: Automatic dependency and security update detection
- **CI/CD Integration**: Seamless integration with existing CI/CD pipelines
- **Plugin System**: Extensible architecture for custom functionality

### 📊 **Monitoring & Intelligence**
- **Real-time Health Checks**: Repository status monitoring
- **Security Scanning**: Vulnerability detection and reporting
- **Performance Metrics**: Service health and performance tracking
- **Notification System**: Webhook, email, and Slack integration

## 🎯 Quick Start

### 1. **Install the Complete System**

```bash
# Clone the repository
git clone https://github.com/fidenceio/manifest.local.git
cd manifest.local

# Install CLI and start local service
./install-local-cli.sh
docker-compose up -d
```

### 2. **Use the CLI for Development**

```bash
# Automated workflow (recommended)
manifest go major    # Complete version bump → commit → tag → push

# Generate documentation
manifest docs

# Check system health
manifest diagnose
```

### 3. **Access the Local Service**

```bash
# Service health check
curl http://localhost:3001/health

# API endpoints available at
curl http://localhost:3001/api/v1/
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Manifest Local System                    │
├─────────────────────────────────────────────────────────────┤
│  🖥️  CLI Interface     🏗️  Local Service     📊  Monitoring  │
│  • manifest go         • Express.js API     • Heartbeat     │
│  • manifest docs       • PostgreSQL DB      • Update Check  │
│  • manifest diagnose   • Redis Cache        • Health Check  │
│  • manifest revert     • Docker Containers  • Notifications │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   Your Repos    │
                    │ • Git Ops       │
                    │ • Version Mgmt  │
                    │ • Documentation │
                    └─────────────────┘
```

## 📦 Installation Options

### **Option 1: Complete System (Recommended)**

```bash
# Install CLI and start all services
./install-local-cli.sh
docker-compose up -d

# Verify installation
manifest diagnose
curl http://localhost:3001/health
```

### **Option 2: CLI Only**

```bash
# Install just the CLI
./install-local-cli.sh

# Use basic functionality without local service
manifest version patch
manifest docs
```

### **Option 3: Service Only**

```bash
# Start just the local service
docker-compose up -d manifest-cloud redis postgres

# Access via HTTP API
curl http://localhost:3001/api/v1/
```

## 🔧 Configuration

### **Environment Setup**

Create `.env` file for service configuration:

```bash
# Service Configuration
PORT=3001
NODE_ENV=production
MANIFEST_SECRET=your-secret-key-here

# Database
POSTGRES_DB=manifest_cloud
POSTGRES_USER=manifest_user
POSTGRES_PASSWORD=manifest_password

# Redis
REDIS_URL=redis://localhost:6380

# Features
ENABLE_HEARTBEAT=true
ENABLE_UPDATE_CHECKER=true
ENABLE_PLUGIN_SYSTEM=true
ENABLE_CICD_INTEGRATION=true
```

### **CLI Configuration**

Create `~/.manifest-local/.env` for CLI options:

```bash
# Optional: Manifest Cloud integration
MANIFEST_CLOUD_URL=http://localhost:3001
MANIFEST_CLOUD_API_KEY=your-api-key-here

# CLI preferences
MANIFEST_AUTO_COMMIT=true
MANIFEST_AUTO_PUSH=true
MANIFEST_NOTIFICATION_EMAIL=your@email.com
```

## 📚 Command Reference

### **Core CLI Commands**

#### `manifest go [type]` - Complete Workflow
The main command for automated development workflows.

```bash
manifest go major     # Major version bump with full automation
manifest go minor     # Minor version bump with full automation
manifest go patch     # Patch version bump with full automation
manifest go           # Auto-detect increment type
```

**What happens automatically:**
1. ✅ Checks for uncommitted changes
2. 🔍 Analyzes commits (if service configured)
3. 📈 Bumps version according to type
4. 📄 Updates VERSION file and package.json
5. 💾 Commits changes with intelligent messages
6. 🏷️ Creates Git tag
7. 🚀 Pushes to all remotes with conflict resolution

#### `manifest docs` - Documentation Generation
Generate comprehensive documentation for the current version.

**Creates:**
- `docs/RELEASE_vX.Y.Z.md` - Release notes
- `docs/CHANGELOG_vX.Y.Z.md` - Detailed changelog
- Updates `README.md` with changelog section

#### `manifest revert` - Version Reversion
Interactive version reversion with safety confirmations.

```bash
manifest revert
# Shows available versions and prompts for selection
# Updates VERSION file, package.json, and README.md
# Commits changes and creates tag
```

#### `manifest diagnose` - System Health Check
Comprehensive health check and troubleshooting.

**Checks:**
- Git repository status
- Remote configuration
- SSH authentication
- VERSION file consistency
- Local service health
- Provides actionable solutions

### **Utility Commands**

```bash
manifest version [type]    # Simple version bumping
manifest push [type]       # Legacy version bump and push
manifest commit <message>  # Create custom commit
manifest analyze           # Analyze commits (requires service)
manifest changelog         # Generate changelog (requires service)
manifest help              # Show help information
```

## 🏗️ Local Service Features

### **API Endpoints**

#### **Health & Status**
- `GET /health` - Service health check
- `GET /api/v1/status` - Detailed service status
- `GET /api/v1/version` - Service version information

#### **Repository Management**
- `POST /api/v1/repository/:path/heartbeat/start` - Start monitoring
- `POST /api/v1/repository/:path/heartbeat/stop` - Stop monitoring
- `GET /api/v1/repository/:path/status` - Repository health status
- `POST /api/v1/repository/:path/update-check` - Check for updates

#### **Plugin System**
- `POST /api/v1/plugins/register` - Register custom plugin
- `GET /api/v1/plugins/list` - List available plugins
- `POST /api/v1/plugins/:id/execute` - Execute plugin

#### **CI/CD Integration**
- `POST /api/v1/cicd/trigger` - Trigger CI/CD pipeline
- `GET /api/v1/cicd/status` - Pipeline status
- `POST /api/v1/cicd/webhook` - Webhook endpoint

### **Service Components**

#### **Heartbeat Service**
- Continuous repository monitoring
- Configurable check intervals (default: 5 minutes)
- Automatic health status tracking
- Notification system integration

#### **Update Checker**
- Dependency update detection (npm, Python, Docker)
- Security vulnerability scanning
- Git repository status monitoring
- Automated update recommendations

#### **Plugin Manager**
- Extensible plugin architecture
- Custom manifest format detection
- Version strategy customization
- CI/CD platform integration

## 🔄 Workflow Examples

### **Standard Release Process**

```bash
# 1. Generate documentation
manifest docs

# 2. Commit documentation
manifest commit "Add documentation for v2.1.0"

# 3. Automated release with local service
manifest go minor

# Result: Version bumped, committed, tagged, pushed, and monitored
```

### **Continuous Monitoring Setup**

```bash
# Start heartbeat monitoring via API
curl -X POST http://localhost:3001/api/v1/repository/$(pwd)/heartbeat/start \
  -H "Content-Type: application/json" \
  -d '{"interval": "5m", "notifications": [{"type": "webhook", "url": "..."}]}'

# Check status
curl http://localhost:3001/api/v1/repository/$(pwd)/status
```

### **Plugin Integration**

```bash
# Register custom plugin
curl -X POST http://localhost:3001/api/v1/plugins/register \
  -H "Content-Type: application/json" \
  -d '{"name": "custom-format", "pluginType": "manifest-format", ...}'

# Execute plugin
curl -X POST http://localhost:3001/api/v1/plugins/custom-format/execute
```

## 🚨 Troubleshooting

### **Service Issues**

```bash
# Check service status
docker-compose ps

# View service logs
docker-compose logs manifest-cloud

# Restart services
docker-compose restart
```

### **CLI Issues**

```bash
# Comprehensive health check
manifest diagnose

# Check service connectivity
curl http://localhost:3001/health

# Verify installation
ls -la ~/.manifest-local/
```

### **Common Solutions**

```bash
# Service won't start
docker-compose down && docker-compose up -d

# CLI not found
export PATH="$HOME/.local/bin:$PATH"

# Database connection issues
docker-compose restart postgres
```

## 🔗 Integration Options

### **Local-Only Mode**
- CLI functionality without external services
- Basic version management and Git operations
- Documentation generation from local Git history

### **Local Service Mode**
- Full API endpoints for automation
- Heartbeat monitoring and update checking
- Plugin system and CI/CD integration

### **Hybrid Mode**
- Local service for core functionality
- Optional Manifest Cloud integration for enhanced features
- Best of both worlds: local control + cloud intelligence

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [docs/](docs/)
- **Enhanced Features**: [ENHANCED_FEATURES.md](ENHANCED_FEATURES.md)
- **Deployment Guide**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Issues**: [GitHub Issues](https://github.com/fidenceio/manifest.local/issues)
- **Discussions**: [GitHub Discussions](https://github.com/fidenceio/manifest.local/discussions)

---

**Built with ❤️ by the Fidence.io team**

## 📋 Changelog

### [v3.0.1] - 2025-08-11
- **Documentation**: Complete README rewrite to reflect full system capabilities
- **Architecture**: Clarified CLI + Local Service + Monitoring architecture
- **Installation**: Added multiple installation options (Complete, CLI-only, Service-only)
- **Features**: Documented heartbeat monitoring, update checking, and plugin system

### [v3.0.0] - 2025-08-11
- **Major Release**: Complete CLI rewrite with enhanced automation
- **New Commands**: `manifest go`, `manifest docs`, `manifest diagnose`
- **VERSION File**: Automatic VERSION file management
- **Conflict Resolution**: Automatic handling of common Git conflicts
- **Cloud Integration**: Optional Manifest Cloud service integration
- **Documentation**: Comprehensive documentation generation

See [CHANGELOG_v3.0.1.md](docs/CHANGELOG_v3.0.1.md) for full details.
