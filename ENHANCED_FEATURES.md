# 🚀 Enhanced Manifest Features

## Overview

Manifest has been enhanced with powerful new features that make it truly universal and modular for any application type. This document outlines the new capabilities and how to use them.

## ✨ New Features

### 1. 🔌 Plugin System

The plugin system allows Manifest to be extended with custom functionality for different application types and ecosystems.

#### Plugin Types
- **manifest-format**: Custom manifest format detection and parsing
- **version-strategy**: Custom version management strategies
- **cicd-platform**: Custom CI/CD platform integration
- **install-script**: Custom installation script generation
- **update-checker**: Custom update and heartbeat checking
- **deployment**: Custom deployment automation
- **monitoring**: Custom health monitoring and metrics

#### Example Plugin
```javascript
// src/plugins/example-manifest-format.js
module.exports = {
  name: 'example-manifest-format',
  version: '1.0.0',
  description: 'Example plugin for custom manifest format detection',
  pluginType: 'manifest-format',
  
  async execute(context, options = {}) {
    // Plugin logic here
    return { success: true, format: 'custom' };
  }
};
```

#### Plugin API Endpoints
- `POST /api/v1/plugins/register` - Register a new plugin
- `POST /api/v1/plugins/:pluginId/execute` - Execute a plugin
- `GET /api/v1/plugins/list` - List all registered plugins
- `GET /api/v1/plugins/type/:pluginType` - Get plugins by type
- `DELETE /api/v1/plugins/:pluginId` - Unregister a plugin
- `POST /api/v1/plugins/load-directory` - Load plugins from directory

### 2. 💓 Heartbeat Monitoring

Continuous monitoring and health checking for any repository with automatic notifications.

#### Features
- **Automatic Health Checks**: Configurable intervals (default: 5 minutes)
- **Repository Health Monitoring**: Git, files, dependencies health
- **Critical Update Detection**: Security vulnerabilities, breaking changes
- **Notification System**: Webhook, email, Slack support
- **Retry Logic**: Automatic retry with exponential backoff
- **Status Tracking**: Real-time status monitoring

#### Heartbeat API Endpoints
- `POST /api/v1/heartbeat/:repoPath/start` - Start heartbeat monitoring
- `POST /api/v1/heartbeat/:repoPath/stop` - Stop heartbeat monitoring
- `GET /api/v1/heartbeat/:repoPath/status` - Get heartbeat status
- `GET /api/v1/heartbeat/all/status` - Get all heartbeat statuses
- `POST /api/v1/heartbeat/:repoPath/check` - Perform immediate check
- `PUT /api/v1/heartbeat/:repoPath/configure` - Configure heartbeat

#### Example Heartbeat Configuration
```json
{
  "interval": "5m",
  "notifications": [
    {
      "type": "webhook",
      "url": "https://hooks.slack.com/services/..."
    },
    {
      "type": "email",
      "email": "admin@company.com"
    }
  ],
  "enabled": true
}
```

### 3. 🐳 Enhanced Container Integration

Automatic Manifest container setup for any application environment.

#### Supported Container Types
- **Docker**: docker-compose.yml with Manifest integration
- **Kubernetes**: K8s manifests with Manifest sidecar
- **Podman**: podman-compose.yml with Manifest integration

#### Automatic Setup
```bash
# Generate Docker setup
curl -X POST http://localhost:3000/api/v1/manifest/repo-path/install/generate \
  -H "Content-Type: application/json" \
  -d '{"platform": "linux", "containerType": "docker", "options": {"appName": "my-app"}}'
```

#### Generated Files
- `docker-compose.yml` with Manifest service
- `manifest-config/` directory
- `.manifestrc` configuration file
- Health checks and monitoring

### 4. 🔧 Enhanced Client SDK

Simple client library for any application to communicate with Manifest.

#### Basic Usage
```javascript
const { EnhancedManifestClient } = require('@fidenceio/manifest-client');

const client = new EnhancedManifestClient({
  baseURL: 'http://localhost:3000',
  autoHeartbeat: true
});

// Connect to Manifest
await client.connect();

// Start heartbeat monitoring
await client.startRepositoryHeartbeat('/path/to/repo', {
  interval: '5m',
  notifications: [{ type: 'webhook', url: 'https://...' }]
});

// Check for updates
const updates = await client.checkUpdates('/path/to/repo');

// Execute plugins
const result = await client.executePlugin('plugin-id', { repoPath: '/path/to/repo' });
```

#### Client Features
- **Auto-reconnection**: Automatic retry with exponential backoff
- **Event-driven**: Event emitter for real-time updates
- **Heartbeat Integration**: Built-in heartbeat monitoring
- **Plugin Support**: Execute custom plugins
- **Error Handling**: Comprehensive error handling and logging

### 5. 🤖 LLM Agent Capabilities

Intelligent analysis and automation powered by LLM agents for understanding Git commits, detecting API changes, and generating intelligent documentation.

#### Core Features
- **Intelligent Commit Analysis**: Understand functional impact of Git commits
- **API Change Detection**: Automatically detect breaking and non-breaking API changes
- **Smart Version Recommendations**: AI-powered version bump suggestions
- **Intelligent Changelog Generation**: Context-aware changelog creation
- **Commit Intent Analysis**: Understand commit purpose and impact
- **Functional Change Detection**: Identify what actually changed functionally

#### LLM Agent API Endpoints
- `POST /api/v1/llm-agent/:repoPath/analyze` - Analyze commits intelligently
- `POST /api/v1/llm-agent/:repoPath/changelog` - Generate intelligent changelog
- `POST /api/v1/llm-agent/:repoPath/version-recommendation` - Get version recommendations
- `POST /api/v1/llm-agent/:repoPath/api-changes` - Detect API changes
- `POST /api/v1/llm-agent/:repoPath/commit-analysis` - Analyze individual commit
- `POST /api/v1/llm-agent/:repoPath/smart-update` - Perform comprehensive update analysis
- `GET /api/v1/llm-agent/:repoPath/insights` - Get commit insights and trends

#### Example Usage
```javascript
// Analyze commits with LLM intelligence
const analysis = await client.analyzeCommits('/path/to/repo', {
  from: '2024-01-01',
  to: '2024-01-31',
  limit: 100
});

// Get intelligent version recommendation
const versionRec = await client.getVersionRecommendation('/path/to/repo');

// Generate intelligent changelog
const changelog = await client.generateChangelog('/path/to/repo', '2.0.0');

// Detect API changes
const apiChanges = await client.detectAPIChanges('/path/to/repo');

// Get commit insights
const insights = await client.getCommitInsights('/path/to/repo', 30, 100);
```

#### Intelligent Analysis Features
- **Commit Intent Classification**: feat, fix, perf, docs, breaking changes
- **Impact Assessment**: Critical, high, medium, low impact changes
- **File Change Analysis**: Understanding of what files changed and why
- **API Endpoint Detection**: Automatic detection of API-related changes
- **Breaking Change Detection**: Identify changes that break compatibility
- **Functional Impact Analysis**: Understand what actually changed functionally

#### Smart Update Recommendations
- **Version Bump Suggestions**: Major, minor, or patch based on changes
- **API Compatibility Warnings**: Alert about breaking API changes
- **Testing Recommendations**: Suggest testing for critical file changes
- **Documentation Updates**: Recommend documentation updates for new features
- **Migration Guidance**: Provide guidance for breaking changes

### 6. 🌐 Universal Manifest Client

Lightweight, embeddable client library that can be integrated into any application to communicate with Manifest and leverage its LLM capabilities.

#### Key Features
- **Universal Compatibility**: Works with any Node.js application
- **LLM Integration**: Built-in access to all LLM agent capabilities
- **Auto-connection**: Automatic connection and reconnection
- **Event-driven Architecture**: Real-time updates and notifications
- **Built-in Heartbeat**: Automatic health monitoring
- **Update History**: Track update history and patterns
- **Configuration Management**: Dynamic configuration updates

#### Basic Integration
```javascript
const { UniversalManifestClient } = require('@fidenceio/manifest-client');

const client = new UniversalManifestClient({
  manifestUrl: 'http://localhost:3000',
  autoCheckUpdates: true,
  heartbeatEnabled: true
});

// Connect and start monitoring
await client.connect();

// Check for updates intelligently
const updates = await client.checkForUpdates('/path/to/repo');

// Get version recommendations
const versionRec = await client.getVersionRecommendation('/path/to/repo');

// Generate changelog
const changelog = await client.generateChangelog('/path/to/repo', 'next');
```

#### Advanced Features
- **Smart Update Checking**: Intelligent update detection with recommendations
- **Automatic Retry Logic**: Exponential backoff for failed requests
- **Update History Tracking**: Maintain history of all update checks
- **Configuration Export/Import**: Save and restore client configuration
- **Event Handling**: Listen to connection, update, and error events
- **Quick Functions**: One-off update checks and version recommendations

## 🚀 Getting Started

### 1. Install Dependencies
```bash
npm install
```

### 2. Start Manifest Service
```bash
npm start
```

### 3. Load Example Plugin
```bash
curl -X POST http://localhost:3000/api/v1/plugins/load-directory \
  -H "Content-Type: application/json" \
  -d '{"pluginsDir": "./src/plugins"}'
```

### 4. Start Heartbeat Monitoring
```bash
curl -X POST http://localhost:3000/api/v1/heartbeat/repo-path/start \
  -H "Content-Type: application/json" \
  -d '{"interval": "5m", "notifications": []}'
```

### 5. Generate Installation Scripts
```bash
curl -X POST http://localhost:3000/api/v1/manifest/repo-path/install/generate \
  -H "Content-Type: application/json" \
  -d '{"platform": "linux", "containerType": "docker"}'
```

### 6. Test LLM Agent Capabilities
```bash
# Analyze commits intelligently
curl -X POST http://localhost:3000/api/v1/llm-agent/repo-path/analyze \
  -H "Content-Type: application/json" \
  -d '{"limit": 50, "options": {"includeFileChanges": true}}'

# Get version recommendation
curl -X POST http://localhost:3000/api/v1/llm-agent/repo-path/version-recommendation \
  -H "Content-Type: application/json" \
  -d '{"limit": 100}'

# Generate intelligent changelog
curl -X POST http://localhost:3000/api/v1/llm-agent/repo-path/changelog \
  -H "Content-Type: application/json" \
  -d '{"version": "2.0.0", "format": "markdown", "includeDetails": true}'

# Perform smart update analysis
curl -X POST http://localhost:3000/api/v1/llm-agent/repo-path/smart-update \
  -H "Content-Type: application/json" \
  -d '{"autoVersion": true, "generateChangelog": true, "detectAPIChanges": true}'
```

### 7. Integrate Universal Client
```javascript
// In your application
const { UniversalManifestClient } = require('@fidenceio/manifest-client');

const client = new UniversalManifestClient({
  manifestUrl: 'http://localhost:3000',
  autoCheckUpdates: true
});

await client.connect();
const updates = await client.checkForUpdates('/path/to/repo');
```

## 🔌 Plugin Development

### Plugin Structure
```javascript
module.exports = {
  name: 'plugin-name',
  version: '1.0.0',
  description: 'Plugin description',
  pluginType: 'plugin-type',
  author: 'Author Name',
  
  async execute(context, options = {}) {
    // Plugin logic
    return { success: true, data: 'result' };
  },
  
  configSchema: {
    // Configuration schema
  },
  
  metadata: {
    // Plugin metadata
  }
};
```

### Plugin Context
The `context` object contains:
- `repoPath`: Repository path
- `manifestInfo`: Manifest information
- `options`: Plugin options
- `config`: Plugin configuration

### Plugin Types
- **manifest-format**: Detect and parse custom manifest formats
- **version-strategy**: Implement custom versioning strategies
- **cicd-platform**: Integrate with custom CI/CD platforms
- **install-script**: Generate custom installation scripts
- **update-checker**: Custom update checking logic
- **deployment**: Custom deployment automation
- **monitoring**: Custom health monitoring

## 💓 Heartbeat Configuration

### Notification Types
- **Webhook**: HTTP POST to specified URL
- **Email**: Email notifications (placeholder)
- **Slack**: Slack webhook integration (placeholder)

### Health Checks
- **Git Repository**: .git directory health
- **Critical Files**: package.json, README.md, .gitignore
- **Dependencies**: Package manager health
- **Overall Status**: Aggregated health score

### Status Levels
- **healthy**: All systems operational
- **warning**: Minor issues detected
- **critical**: Critical issues detected
- **security_alert**: Security vulnerabilities
- **breaking_changes**: Breaking changes detected

## 🐳 Container Integration

### Docker Setup
```yaml
version: '3.8'
services:
  my-app:
    build: .
    environment:
      - MANIFEST_ENABLED=true
      - MANIFEST_URL=http://manifest:3000
    depends_on:
      - manifest
  
  manifest:
    image: fidenceio/manifest:latest
    ports:
      - "3001:3000"
    volumes:
      - ./manifest-config:/app/data
```

### Kubernetes Setup
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        env:
        - name: MANIFEST_ENABLED
          value: "true"
      - name: manifest
        image: fidenceio/manifest:latest
```

## 🔧 API Reference

### Authentication
Currently, all endpoints are public. Future versions will include authentication.

### Rate Limiting
Default rate limit: 100 requests per minute per IP.

### Error Handling
All errors return consistent JSON format:
```json
{
  "success": false,
  "error": "Error message",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

### Response Format
Successful responses follow this format:
```json
{
  "success": true,
  "data": "Response data",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## 🚀 Deployment

### Docker
```bash
docker build -t fidenceio/manifest .
docker run -p 3000:3000 fidenceio/manifest
```

### Kubernetes
```bash
kubectl apply -f k8s-manifest/
```

### Environment Variables
- `PORT`: Service port (default: 3000)
- `NODE_ENV`: Environment (default: production)
- `LOG_LEVEL`: Logging level (default: info)
- `GITHUB_TOKEN`: GitHub API token
- `MANIFEST_SECRET`: Secret for internal communication

## 🔍 Monitoring

### Health Endpoint
```bash
curl http://localhost:3000/health
```

### Metrics
- Request count and response times
- Plugin execution metrics
- Heartbeat status metrics
- Error rates and types

### Logging
Structured logging with Winston:
- Operation logging
- Performance metrics
- Error tracking
- Debug information

## 🤝 Contributing

### Plugin Development
1. Create plugin in `src/plugins/`
2. Follow plugin structure
3. Add tests
4. Submit pull request

### Feature Requests
1. Create issue with detailed description
2. Discuss implementation approach
3. Submit pull request with tests

### Bug Reports
1. Create issue with reproduction steps
2. Include logs and environment details
3. Test with latest version

## 📚 Examples

### Custom Manifest Format Plugin
See `src/plugins/example-manifest-format.js` for a complete example.

### Heartbeat Integration
```javascript
// Start heartbeat with webhook notifications
await client.startRepositoryHeartbeat('/path/to/repo', {
  interval: '5m',
  notifications: [
    {
      type: 'webhook',
      url: 'https://hooks.slack.com/services/...'
    }
  ]
});
```

### Plugin Execution
```javascript
// Execute custom plugin
const result = await client.executePlugin('custom-plugin', {
  repoPath: '/path/to/repo',
  options: { customOption: 'value' }
});
```

## 🔮 Future Enhancements

- **Authentication & Authorization**: JWT-based authentication
- **Plugin Marketplace**: Centralized plugin repository
- **Advanced Notifications**: More notification channels
- **Multi-tenant Support**: Organization and team management
- **Advanced Metrics**: Prometheus integration
- **Web UI**: Dashboard for monitoring and management
- **Advanced LLM Models**: Integration with more sophisticated LLM providers
- **Custom LLM Prompts**: Configurable prompts for different analysis types
- **Batch Analysis**: Process multiple repositories simultaneously
- **Historical Analysis**: Long-term trend analysis and predictions

## 📞 Support

- **Documentation**: This file and inline code comments
- **Issues**: GitHub issues for bugs and feature requests
- **Discussions**: GitHub discussions for questions
- **Email**: team@kanizsa.com for direct support

---

*Manifest - Universal App Store Service for Any Application* 🚀
