# Manifest - Universal App Store Service

Manifest is a containerized, modular service that acts as a universal "App Store" for any application. It provides comprehensive version management, CI/CD integration, manifest format support, and installation automation across all codebases and application types.

## 🚀 Features

### Universal Manifest Format Support
- **Multi-ecosystem support**: Node.js, Python, Rust, Go, PHP, Ruby, Java, .NET, Docker
- **Automatic detection**: Detects manifest files and extracts metadata
- **Format conversion**: Converts between different manifest formats
- **Universal manifest**: Generates standardized manifest for any application

### Enhanced Version Management
- **Multiple strategies**: Semantic, date-based, commit-based, custom versioning
- **Automated bumping**: Intelligent version incrementing with changelog generation
- **Git integration**: Automatic tagging, committing, and pushing
- **Push script replacement**: Full integration with existing deployment workflows

### CI/CD Pipeline Integration
- **Platform detection**: GitHub Actions, GitLab CI, Jenkins, CircleCI, Travis CI, Azure DevOps, Bitbucket
- **Configuration generation**: Auto-generates platform-specific CI/CD configs
- **Webhook processing**: Handles CI/CD events and triggers
- **Workflow automation**: Streamlines deployment and testing processes

### Universal Installation System
- **Multi-platform**: Linux, macOS, Windows, Alpine, CentOS, Ubuntu
- **Container support**: Docker, Kubernetes, Podman
- **Auto-detection**: Detects platform and generates appropriate scripts
- **One-command install**: Simple installation across any environment

### 🤖 LLM Agent Capabilities
- **Intelligent Commit Analysis**: Understand functional impact of Git commits
- **API Change Detection**: Automatically detect breaking and non-breaking API changes
- **Smart Version Recommendations**: AI-powered version bump suggestions
- **Intelligent Changelog Generation**: Context-aware changelog creation
- **Functional Impact Assessment**: Determine critical, high, medium, or low impact changes
- **Universal Client Library**: Lightweight, embeddable client for any application

## 🏗️ Architecture

```
src/
├── services/
│   ├── manifestFormatManager.js    # Universal manifest format support
│   ├── enhancedVersionManager.js   # Enhanced version management
│   ├── cicdIntegrationService.js   # CI/CD pipeline integration
│   ├── installScriptGenerator.js   # Installation script generation
│   ├── versionManager.js          # Legacy version management
│   ├── documentationManager.js    # Documentation management
│   ├── githubService.js          # GitHub integration
│   ├── heartbeatService.js        # Heartbeat monitoring service
│   ├── pluginManager.js           # Plugin system management
│   └── [LLM functionality moved to Manifest Cloud service]
├── routes/
│   ├── manifest.js               # Enhanced manifest routes
│   ├── version.js                # Version management routes
│   ├── documentation.js          # Documentation routes
│   ├── github.js                 # GitHub integration routes
│   ├── git.js                    # Git operations routes
│   ├── updates.js                # Update management routes
│   ├── repositories.js           # Repository management routes
│   ├── heartbeat.js              # Heartbeat monitoring routes
│   ├── plugins.js                # Plugin system routes
│   └── [LLM functionality moved to Manifest Cloud service]
├── middleware/
│   ├── errorHandler.js           # Error handling middleware
│   └── rateLimiter.js            # Rate limiting middleware
├── utils/
│   └── logger.js                 # Logging utility
├── client/
│   ├── enhancedManifestClient.js # Enhanced client with plugin support
│   ├── manifestCloudClient.js     # Cloud service proxy client
│   └── [LLM functionality moved to Manifest Cloud service]
└── index.js                      # Main application entry point
```

## 🚀 Quick Start

### Prerequisites
- Node.js 18+
- Docker (optional)
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd fidenceio.manifest
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Environment setup**
   ```bash
   cp env.example .env
   # Edit .env with your configuration
   ```

4. **Start the service**
   ```bash
   npm start
   # or for development
   npm run dev
   ```

5. **Test the service**
   ```bash
   # Health check
   curl http://localhost:3000/health
   
   # Test manifest analysis
   curl -X POST http://localhost:3000/api/v1/manifest/$(pwd)/analyze \
     -H "Content-Type: application/json"
   ```

### Docker Deployment

```bash
# Build the image
docker build -t manifest .

# Run with Docker Compose
docker-compose up -d

# Or run standalone
docker run -p 3000:3000 manifest
```

### Universal Client Integration

Integrate Manifest into any application with the Universal Client Library:

```javascript
const { EnhancedManifestClient } = require('./src/client/enhancedManifestClient');

const client = new EnhancedManifestClient({
  manifestUrl: 'http://localhost:3000',
  autoCheckUpdates: true
});

await client.connect();
const updates = await client.checkForUpdates('/path/to/repo');
```

### 🤖 LLM Agent Integration (Cloud Service)

LLM functionality has been moved to the dedicated **Manifest Cloud** service for improved performance and scalability:

```javascript
const { ManifestCloudClient } = require('./src/client/manifestCloudClient');

const client = new ManifestCloudClient({
  baseURL: process.env.MANIFEST_CLOUD_URL || 'http://localhost:3001',
  apiKey: process.env.MANIFEST_CLOUD_API_KEY
});

// Use the same interface as before
const analysis = await client.analyzeCommits('/path/to/repo');
const changelog = await client.generateChangelog('/path/to/repo');
```

See [LLM Migration Guide](docs/LLM_MIGRATION_GUIDE.md) for details and [LLM Agent Guide](../fidenceio.manifest.cloud/docs/LLM_AGENT_GUIDE.md) in the cloud repository.

## 📚 API Reference

### Core Endpoints

#### Manifest Analysis
```http
GET /api/v1/manifest/{repoPath}/analyze
```
Analyzes repository and detects manifest formats, metadata, and CI/CD platforms.

#### Enhanced Version Management
```http
POST /api/v1/manifest/{repoPath}/version/bump
```
Enhanced version bumping with push script integration.

```http
POST /api/v1/manifest/{repoPath}/version/strategy
```
Detect and configure version strategy.

#### CI/CD Integration
```http
POST /api/v1/manifest/{repoPath}/cicd/generate
```
Generate CI/CD configuration for detected platform.

```http
POST /api/v1/manifest/{repoPath}/cicd/webhook
```
Process CI/CD webhook events.

#### Installation Scripts
```http
POST /api/v1/manifest/{repoPath}/install/generate
```
Generate installation scripts for Manifest.

```http
POST /api/v1/manifest/{repoPath}/install/all
```
Generate all installation scripts for all platforms.

#### Health Check
```http
GET /api/v1/manifest/{repoPath}/health
```
Get comprehensive health status for repository.

#### LLM Agent Capabilities
```http
POST /api/v1/llm-agent/{repoPath}/analyze
```
Intelligent commit analysis and functional impact assessment.

```http
POST /api/v1/llm-agent/{repoPath}/version-recommendation
```
AI-powered version bump recommendations.

```http
POST /api/v1/llm-agent/{repoPath}/changelog
```
Generate intelligent, context-aware changelogs.

```http
POST /api/v1/llm-agent/{repoPath}/smart-update
```
Comprehensive update analysis with recommendations.

### Legacy Endpoints

#### Version Management
```http
GET /api/v1/version/{repoPath}
POST /api/v1/version/{repoPath}/bump
POST /api/v1/version/{repoPath}/update
```

#### Documentation
```http
GET /api/v1/documentation/{repoPath}
POST /api/v1/documentation/{repoPath}/update
```

#### GitHub Integration
```http
GET /api/v1/github/repos/{owner}/{repo}
POST /api/v1/github/repos/{owner}/{repo}/releases
```

## 🔧 Configuration

### Environment Variables

```bash
# Server Configuration
PORT=3000
NODE_ENV=production

# Database Configuration
DATABASE_URL=postgresql://user:password@localhost:5432/manifest
REDIS_URL=redis://localhost:6379

# GitHub Configuration
GITHUB_TOKEN=your_github_token
GITHUB_WEBHOOK_SECRET=your_webhook_secret

# Security
JWT_SECRET=your_jwt_secret
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX=100
```

### Manifest Configuration

Create a `.manifestrc` file in your project root:

```json
{
  "versionStrategy": "semantic",
  "autoCommit": true,
  "autoTag": true,
  "changelog": true,
  "ci": {
    "platform": "github",
    "autoDeploy": true
  },
  "install": {
    "platform": "auto",
    "containerType": "docker"
  }
}
```

## 🎯 Use Cases

### For Application Developers
- **Universal manifest management** across any programming language
- **Automated version bumping** with changelog generation
- **CI/CD integration** for any platform
- **One-command installation** scripts

### For DevOps Engineers
- **Standardized deployment** across all applications
- **Automated CI/CD** configuration generation
- **Multi-platform support** for any environment
- **Health monitoring** and recommendations

### For System Administrators
- **Containerized deployment** with Docker/Kubernetes
- **Multi-platform installation** scripts
- **Centralized management** of all applications
- **Automated updates** and version control

## 🔌 Integration Examples

### Node.js Application
```javascript
const manifest = require('@manifest/client');

// Analyze manifest
const analysis = await manifest.analyze('./my-app');

// Bump version
const result = await manifest.version.bump('./my-app', 'patch');

// Generate CI/CD config
const cicd = await manifest.cicd.generate('./my-app', 'github');
```

### Python Application
```python
import manifest

# Analyze manifest
analysis = manifest.analyze('./my-app')

# Bump version
result = manifest.version.bump('./my-app', 'minor')

# Generate install script
script = manifest.install.generate('./my-app', 'linux', 'docker')
```

### CI/CD Pipeline Integration
```yaml
# GitHub Actions
name: Manifest Integration
on: [push, pull_request]
jobs:
  manifest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Manifest Analysis
        run: |
          curl -X POST ${{ secrets.MANIFEST_URL }}/api/v1/manifest/${{ github.workspace }}/analyze
      - name: Version Bump
        run: |
          curl -X POST ${{ secrets.MANIFEST_URL }}/api/v1/manifest/${{ github.workspace }}/version/bump
```

## 🧪 Testing

```bash
# Run tests
npm test

# Run tests with coverage
npm run test:coverage

# Run linting
npm run lint

# Run specific test suites
npm test -- --grep "version"
```

## 📦 Deployment

### Docker Compose
```yaml
version: '3.8'
services:
  manifest:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://user:password@db:5432/manifest
      - REDIS_URL=redis://redis:6379
    depends_on:
      - db
      - redis
  
  db:
    image: postgres:15
    environment:
      - POSTGRES_DB=manifest
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password
    volumes:
      - postgres_data:/var/lib/postgresql/data
  
  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

### Kubernetes
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: manifest
spec:
  replicas: 3
  selector:
    matchLabels:
      app: manifest
  template:
    metadata:
      labels:
        app: manifest
    spec:
      containers:
      - name: manifest
        image: manifest:latest
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: manifest-secrets
              key: database-url
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [docs.manifest.dev](https://docs.manifest.dev)
- **Issues**: [GitHub Issues](https://github.com/kanizsa/manifest/issues)
- **Discussions**: [GitHub Discussions](https://github.com/kanizsa/manifest/discussions)
- **Email**: support@manifest.dev

## 🔮 Roadmap

- [ ] **Plugin System**: Extensible architecture for custom manifest formats
- [ ] **Multi-tenant Support**: Isolated environments for different organizations
- [ ] **Advanced Analytics**: Usage metrics and performance insights
- [ ] **Mobile SDK**: Native mobile application support
- [ ] **Enterprise Features**: SSO, RBAC, audit logging
- [ ] **AI-powered Recommendations**: Intelligent suggestions for manifest optimization

---

**Manifest** - Empowering universal application management across all ecosystems. 🚀
