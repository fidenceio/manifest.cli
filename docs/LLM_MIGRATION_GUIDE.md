# LLM Migration Guide

## Overview

The LLM (Large Language Model) functionality has been successfully migrated from the local Manifest repository to the dedicated **Manifest Cloud** service. This migration provides better scalability, centralized management, and improved performance for LLM operations.

## What Was Migrated

### ✅ Moved to Manifest Cloud (`fidenceio.manifest.cloud`)

- **Core LLM Service**: `llmAgentService.js` - Advanced LLM agent with intelligent commit analysis
- **API Routes**: `llmAgent.js` - RESTful endpoints for LLM operations
- **Universal Client**: `universalManifestClient.js` - Full-featured client library
- **Test Examples**: `test-llm-agent.js` - Comprehensive testing suite
- **Documentation**: `LLM_AGENT_GUIDE.md` - Complete usage guide
- **Supporting Utilities**: Logger, validation, health checks, and metrics

### 🔄 Updated in Local Repository

- **Main Index**: Removed LLM routes, now points to cloud service
- **New Cloud Client**: `manifestCloudClient.js` - Proxy to cloud service
- **Test Script**: `test-manifest-cloud-client.js` - Test the cloud integration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Manifest Repository                │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              ManifestCloudClient                    │   │
│  │           (Proxy to Cloud Service)                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                │
│                           ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              HTTP/HTTPS Request                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 Manifest Cloud Service                     │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              LLM Agent Service                      │   │
│  │           (Intelligent Analysis)                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              API Endpoints                          │   │
│  │           (RESTful Interface)                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Usage

### 1. Basic Setup

The local repository now includes a `ManifestCloudClient` that seamlessly proxies to the cloud service:

```javascript
const { ManifestCloudClient } = require('./src/client/manifestCloudClient');

const client = new ManifestCloudClient({
  baseURL: 'http://localhost:3001', // or your cloud service URL
  apiKey: process.env.MANIFEST_CLOUD_API_KEY // optional
});
```

### 2. Environment Variables

Set these environment variables to configure the cloud client:

```bash
# Required: Cloud service URL
export MANIFEST_CLOUD_URL="http://localhost:3001"

# Optional: API key for authentication
export MANIFEST_CLOUD_API_KEY="your-api-key-here"
```

### 3. Available Methods

The cloud client provides the same interface as the old local service:

```javascript
// Commit analysis
const analysis = await client.analyzeCommits('/path/to/repo', { depth: 10 });

// Changelog generation
const changelog = await client.generateChangelog('/path/to/repo', { 
  format: 'markdown' 
});

// Version recommendation
const version = await client.getVersionRecommendation('/path/to/repo', {
  strategy: 'semantic'
});

// API change detection
const changes = await client.detectAPIChanges('/path/to/repo');

// Individual commit analysis
const commit = await client.analyzeCommit('/path/to/repo', 'abc123');

// Smart update detection
const updates = await client.detectSmartUpdates('/path/to/repo');

// Commit insights
const insights = await client.getCommitInsights('/path/to/repo');
```

### 4. Event Handling

The client emits events for monitoring and debugging:

```javascript
client.on('request', (data) => {
  console.log(`Request: ${data.method} ${data.url}`);
});

client.on('response', (data) => {
  console.log(`Response: ${data.status} (${data.duration}ms)`);
});

client.on('error', (error) => {
  console.error(`Error: ${error.message}`);
});
```

## Testing

### Test the Cloud Client

```bash
# Basic test
node examples/test-manifest-cloud-client.js

# With custom URL
node examples/test-manifest-cloud-client.js --url http://cloud.example.com

# With API key
node examples/test-manifest-cloud-client.js --key my-api-key

# Show help
node examples/test-manifest-cloud-client.js --help
```

### Test the Cloud Service

```bash
# Navigate to cloud repository
cd ../fidenceio.manifest.cloud

# Install dependencies
npm install

# Start the service
npm start

# Test LLM functionality
node examples/test-llm-agent.js
```

## Migration Benefits

### 🚀 **Performance**
- Dedicated cloud infrastructure
- Optimized LLM processing
- Reduced local resource usage

### 🔧 **Maintenance**
- Centralized LLM service updates
- Easier dependency management
- Consistent API across environments

### 📈 **Scalability**
- Handle multiple concurrent requests
- Better resource allocation
- Cloud-native monitoring and metrics

### 🛡️ **Reliability**
- Dedicated health monitoring
- Automatic failover capabilities
- Professional-grade infrastructure

## Troubleshooting

### Connection Issues

1. **Check Cloud Service Status**
   ```bash
   curl http://localhost:3001/health
   ```

2. **Verify Environment Variables**
   ```bash
   echo $MANIFEST_CLOUD_URL
   echo $MANIFEST_CLOUD_API_KEY
   ```

3. **Test Network Connectivity**
   ```bash
   node examples/test-manifest-cloud-client.js
   ```

### Common Errors

- **ECONNREFUSED**: Cloud service not running
- **401 Unauthorized**: Invalid or missing API key
- **404 Not Found**: Incorrect service URL
- **Timeout**: Network latency or service overload

### Getting Help

1. Check the cloud service logs
2. Verify environment configuration
3. Test with the provided test scripts
4. Review the `LLM_AGENT_GUIDE.md` in the cloud repository

## Rollback Plan

If you need to revert to the local LLM service:

1. **Restore Local Files**
   ```bash
   git checkout HEAD~1 -- src/services/llmAgentService.js
   git checkout HEAD~1 -- src/routes/llmAgent.js
   git checkout HEAD~1 -- src/client/universalManifestClient.js
   ```

2. **Update Main Index**
   ```javascript
   // Uncomment in src/index.js
   app.use('/api/v1/llm-agent', require('./routes/llmAgent'));
   ```

3. **Restart Local Service**
   ```bash
   npm start
   ```

## Next Steps

1. **Deploy Cloud Service**: Set up the Manifest Cloud service in your preferred environment
2. **Update Configuration**: Configure environment variables for production use
3. **Monitor Performance**: Use the built-in metrics and health checks
4. **Scale as Needed**: Add more cloud service instances as demand grows

## Support

For questions or issues with the LLM migration:

- **Local Repository**: Check this migration guide and test scripts
- **Cloud Service**: Refer to `LLM_AGENT_GUIDE.md` in the cloud repository
- **General Issues**: Review logs and health check endpoints

---

**Migration completed successfully!** 🎉

The LLM functionality is now running in the cloud with improved performance, scalability, and maintainability.
