# Manifest Cloud - LLM Agent Service

A comprehensive cloud service for managing manifest files, LLM agents, and repository operations with advanced security and testing capabilities.

## 🚀 Features

### Core Services
- **LLM Agent Management**: Create, configure, and manage AI agents
- **Repository Management**: GitHub CLI integration for repository metadata
- **Manifest Processing**: Advanced manifest file analysis and updates
- **API Gateway**: RESTful API with authentication and rate limiting

### Security & Testing
- **Comprehensive Security Testing**: Authentication, authorization, input validation
- **Package Security**: Vulnerability scanning, outdated dependency detection
- **Core Functionality Testing**: Version management, documentation updates
- **Container-First Testing**: No host dependencies, fully containerized

### Repository Operations
- **Metadata Management**: Update descriptions, topics, homepage URLs
- **Release Management**: Create and manage GitHub releases
- **Content Access**: Commits, issues, pull requests, statistics
- **SSH Authentication**: Secure GitHub operations

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Client Tools  │    │  Manifest Cloud │    │   GitHub CLI    │
│                 │    │     Service     │    │                 │
│ • Test Runner   │◄──►│ • API Gateway   │◄──►│ • Repository    │
│ • CLI Client    │    │ • LLM Agents    │    │ • Metadata      │
│ • Installer     │    │ • Security      │    │ • Releases      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📦 Installation

### Quick Start (Recommended)

1. **Clone the repository**:
   ```bash
   git clone https://github.com/fidenceio/manifest.cloud.git
   cd manifest.cloud
   ```

2. **Install the client**:
   ```bash
   ./install-client.sh
   ```

3. **Start services**:
   ```bash
   manifest-cloud start
   ```

4. **Run tests**:
   ```bash
   manifest-cloud test
   ```

### Manual Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Configure environment**:
   ```bash
   cp env.example .env
   # Edit .env with your configuration
   ```

3. **Start with Docker**:
   ```bash
   docker-compose up -d
   ```

## 🧪 Testing Suite

### Comprehensive Testing Infrastructure

The testing suite provides three main test categories:

#### 1. Security Tests (`tests/security-test.js`)
- **Authentication**: API key validation, missing/invalid keys
- **Authorization**: Access control, permission checks
- **Input Validation**: Malformed JSON, missing fields, injection attempts
- **Security Headers**: Helmet, CORS, rate limiting
- **Container Security**: Non-root user, limited capabilities

#### 2. Package Security Tests (`tests/package-security-test.js`)
- **Vulnerability Scanning**: npm audit, critical/high vulnerabilities
- **Dependency Management**: Outdated packages, version pinning
- **Container Packages**: Alpine package updates, security patches
- **GitHub CLI**: Installation verification, functionality checks

#### 3. Core Functionality Tests (`tests/core-functionality-test.js`)
- **Service Health**: Endpoint availability, service status
- **Repository Operations**: Info, stats, commits, releases
- **Metadata Updates**: Descriptions, topics, homepage URLs
- **Error Handling**: Invalid requests, missing fields
- **Container Tools**: Git, SSH, configuration verification

### Running Tests

#### All Tests
```bash
manifest-cloud test
# or
node tests/run-all-tests.js
```

#### Individual Test Suites
```bash
# Security tests only
manifest-cloud test-security
node tests/security-test.js

# Package security tests only
manifest-cloud test-packages
node tests/package-security-test.js

# Core functionality tests only
manifest-cloud test-functionality
node tests/core-functionality-test.js
```

#### Test Results
```
🧪 Running All Test Suites

📋 Security Tests:
✅ Authentication Tests - PASSED
✅ Authorization Tests - PASSED
✅ Input Validation Tests - PASSED
✅ Security Headers Tests - PASSED

🐳 Container Security Tests:
✅ Non-Root User Test - PASSED
✅ Container Capabilities Test - PASSED
✅ Container Mounts Test - PASSED

📊 Test Report
📈 Overall Results:
   Total Tests: 15
   Passed: 15 ✅
   Failed: 0 ❌
   Success Rate: 100.0%

🎉 All tests passed! The system is secure and fully functional.
```

## 🔧 Client Tools

### Manifest Cloud CLI

The `manifest-cloud` command provides easy access to all functionality:

```bash
# Service management
manifest-cloud start          # Start services
manifest-cloud stop           # Stop services
manifest-cloud status         # Show service status
manifest-cloud logs           # View service logs

# Testing
manifest-cloud test           # Run all tests
manifest-cloud test-security  # Security tests only
manifest-cloud test-packages  # Package security tests only
manifest-cloud test-functionality # Core functionality tests only

# Help
manifest-cloud help           # Show help
manifest-cloud --help         # Show help
```

### Installation Directory

The client installs to `~/.manifest-cloud/` with the following structure:

```
~/.manifest-cloud/
├── src/                     # Source code
├── tests/                   # Test suites
├── examples/                # Example scripts
├── docker-compose.yml       # Service orchestration
├── Dockerfile               # Main service container
├── Dockerfile.test          # Test client container
├── package.json             # Dependencies
├── .env                     # Configuration
├── data/                    # Persistent data
├── logs/                    # Service logs
└── temp/                    # Temporary files
```

## 🐳 Docker Services

### Service Architecture

```yaml
services:
  manifest-cloud:           # Main service (port 3001)
  manifest-cloud-redis:     # Redis cache (port 6380)
  manifest-cloud-postgres:  # PostgreSQL database (port 5433)
  test-client:              # Testing container
```

### Container Features

- **Base Image**: `node:20-alpine` for security and size
- **Non-Root User**: Security best practices
- **Health Checks**: Automatic health monitoring
- **Volume Mounts**: SSH keys, git config, persistent data
- **Network Isolation**: Dedicated bridge network

## 🔐 Security Features

### Authentication & Authorization
- **API Key Authentication**: Bearer token validation
- **Rate Limiting**: Configurable request limits
- **CORS Protection**: Configurable cross-origin policies
- **Input Validation**: Comprehensive request validation

### Container Security
- **Non-Root Execution**: Limited user privileges
- **Minimal Base Image**: Alpine Linux with essential packages only
- **Health Monitoring**: Automatic health checks and restarts
- **Network Isolation**: Dedicated Docker networks

### Package Security
- **Vulnerability Scanning**: Regular npm audit checks
- **Dependency Pinning**: Specific version requirements
- **Security Updates**: Automated Alpine package updates
- **Malicious Package Detection**: Known bad package filtering

## 📚 API Reference

### Repository Management

#### Get Repository Information
```http
GET /api/v1/repository/{owner}/{repo}
Authorization: Bearer {api-key}
```

#### Update Repository Description
```http
PUT /api/v1/repository/{owner}/{repo}/description
Authorization: Bearer {api-key}
Content-Type: application/json

{
  "description": "Updated repository description"
}
```

#### Add Repository Topics
```http
POST /api/v1/repository/{owner}/{repo}/topics
Authorization: Bearer {api-key}
Content-Type: application/json

{
  "topics": ["automation", "ci-cd", "devops"]
}
```

#### Create Release
```http
POST /api/v1/repository/{owner}/{repo}/releases
Authorization: Bearer {api-key}
Content-Type: application/json

{
  "tagName": "v1.0.0",
  "title": "Release v1.0.0",
  "body": "Release notes here",
  "draft": false,
  "prerelease": false
}
```

### Health & Status

#### Service Health
```http
GET /health
```

#### Service Information
```http
GET /
```

## 🚀 Getting Started

### 1. Prerequisites
- Docker and Docker Compose
- Node.js 18+ and npm
- Git
- SSH keys configured for GitHub

### 2. Quick Test
```bash
# Install client
./install-client.sh

# Start services
manifest-cloud start

# Run comprehensive tests
manifest-cloud test

# Check status
manifest-cloud status
```

### 3. Configuration
Edit `~/.manifest-cloud/.env`:
```bash
# API Configuration
MANIFEST_SECRET=your-secret-key-here
MANIFEST_API_KEY=your-api-key-here

# Service Configuration
PORT=3001
LOG_LEVEL=info

# Feature Flags
ENABLE_COMMIT_ANALYSIS=true
ENABLE_API_CHANGE_DETECTION=true
ENABLE_VERSION_RECOMMENDATIONS=true
```

## 🔍 Troubleshooting

### Common Issues

#### Services Won't Start
```bash
# Check Docker status
docker ps -a

# View logs
manifest-cloud logs

# Check configuration
cat ~/.manifest-cloud/.env
```

#### Tests Fail
```bash
# Check service health
curl http://localhost:3001/health

# Run individual test suites
manifest-cloud test-security
manifest-cloud test-packages
manifest-cloud test-functionality
```

#### GitHub CLI Issues
```bash
# Check SSH keys
docker exec manifest-cloud-service ls -la /root/.ssh

# Test GitHub connection
docker exec manifest-cloud-service gh auth status
```

### Logs and Debugging
```bash
# Service logs
manifest-cloud logs

# Container logs
docker logs manifest-cloud-service

# Test output
manifest-cloud test 2>&1 | tee test-output.log
```

## 📈 Monitoring

### Health Checks
- **Service Health**: `/health` endpoint
- **Container Health**: Docker health checks
- **Database Health**: PostgreSQL connection monitoring
- **Cache Health**: Redis connection monitoring

### Metrics
- **Request Counts**: API endpoint usage
- **Response Times**: Performance monitoring
- **Error Rates**: Failure tracking
- **Resource Usage**: Container resource monitoring

## 🔮 Future Enhancements

### Planned Features
- **Advanced Analytics**: Commit analysis and trend detection
- **Automated Updates**: Smart dependency updates
- **CI/CD Integration**: GitHub Actions and GitLab CI
- **Multi-Repository Support**: Batch operations across repos
- **Web Dashboard**: Visual management interface

### Contributing
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/fidenceio/manifest.cloud/issues)
- **Discussions**: [GitHub Discussions](https://github.com/fidenceio/manifest.cloud/discussions)

---

**Built with ❤️ by the Fidence.io team**

## Changelog

### [v2.0.0] - 2025-08-11


See [CHANGELOG_v2.0.0.md](docs/CHANGELOG_v2.0.0.md) for full details.
