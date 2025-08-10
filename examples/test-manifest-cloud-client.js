#!/usr/bin/env node

const { ManifestCloudClient, createCloudClient, testCloudConnection } = require('../src/client/manifestCloudClient');

/**
 * Test script for Manifest Cloud Client
 * This demonstrates how to use the local client to interact with the cloud LLM service
 */

async function testManifestCloudClient() {
  console.log('🚀 Testing Manifest Cloud Client...\n');

  // Test 1: Connection test
  console.log('1️⃣ Testing connection to Manifest Cloud service...');
  try {
    const connection = await testCloudConnection();
    if (connection.connected) {
      console.log('✅ Connected successfully!');
      console.log(`   Status: ${connection.status}`);
      console.log(`   Timestamp: ${connection.timestamp}`);
      console.log(`   Service: ${connection.service}\n`);
    } else {
      console.log('❌ Connection failed!');
      console.log(`   Error: ${connection.error}\n`);
      console.log('💡 Make sure the Manifest Cloud service is running on port 3001');
      console.log('   Or set MANIFEST_CLOUD_URL environment variable\n');
      return;
    }
  } catch (error) {
    console.log('❌ Connection test failed:', error.message, '\n');
    return;
  }

  // Test 2: Create client instance
  console.log('2️⃣ Creating Manifest Cloud Client instance...');
  const client = createCloudClient({
    baseURL: process.env.MANIFEST_CLOUD_URL || 'http://localhost:3001',
    apiKey: process.env.MANIFEST_CLOUD_API_KEY,
    timeout: 30000
  });

  // Test 3: Health check
  console.log('3️⃣ Testing health check...');
  try {
    const health = await client.checkHealth();
    console.log('✅ Health check successful!');
    console.log(`   Status: ${health.status}`);
    console.log(`   Uptime: ${health.uptime}s`);
    console.log(`   Version: ${health.version || 'N/A'}\n`);
  } catch (error) {
    console.log('❌ Health check failed:', error.message, '\n');
  }

  // Test 4: Metrics (if available)
  console.log('4️⃣ Testing metrics endpoint...');
  try {
    const metrics = await client.getMetrics();
    console.log('✅ Metrics retrieved successfully!');
    console.log(`   Metrics length: ${metrics.length} characters\n`);
  } catch (error) {
    console.log('❌ Metrics retrieval failed:', error.message, '\n');
  }

  // Test 5: Event handling
  console.log('5️⃣ Testing event handling...');
  client.on('request', (data) => {
    console.log(`   📤 Request: ${data.method} ${data.url}`);
  });

  client.on('response', (data) => {
    console.log(`   📥 Response: ${data.status} (${data.duration || 'N/A'}ms)`);
  });

  client.on('error', (error) => {
    console.log(`   ❌ Error: ${error.message}`);
  });

  // Test 6: Sample API calls (with mock data)
  console.log('6️⃣ Testing sample API calls...');
  
  const mockRepoPath = '/path/to/repository';
  
  try {
    // Test commit analysis (will likely fail without real repo, but shows the interface)
    console.log('   Testing commit analysis...');
    await client.analyzeCommits(mockRepoPath, { depth: 5 });
    console.log('   ✅ Commit analysis call successful');
  } catch (error) {
    console.log('   ⚠️  Commit analysis call failed (expected without real repo):', error.message);
  }

  try {
    // Test changelog generation
    console.log('   Testing changelog generation...');
    await client.generateChangelog(mockRepoPath, { format: 'markdown' });
    console.log('   ✅ Changelog generation call successful');
  } catch (error) {
    console.log('   ⚠️  Changelog generation call failed (expected without real repo):', error.message);
  }

  try {
    // Test version recommendation
    console.log('   Testing version recommendation...');
    await client.getVersionRecommendation(mockRepoPath, { strategy: 'semantic' });
    console.log('   ✅ Version recommendation call successful');
  } catch (error) {
    console.log('   ⚠️  Version recommendation call failed (expected without real repo):', error.message);
  }

  console.log('\n🎉 Manifest Cloud Client test completed!');
  console.log('\n💡 To test with real repositories:');
  console.log('   1. Set MANIFEST_CLOUD_URL to your cloud service URL');
  console.log('   2. Set MANIFEST_CLOUD_API_KEY if authentication is required');
  console.log('   3. Use real repository paths instead of mock paths');
  console.log('   4. Run: node examples/test-manifest-cloud-client.js');
}

// Command line interface
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--help') || args.includes('-h')) {
    console.log('Manifest Cloud Client Test Script');
    console.log('');
    console.log('Usage:');
    console.log('  node examples/test-manifest-cloud-client.js [options]');
    console.log('');
    console.log('Options:');
    console.log('  --help, -h     Show this help message');
    console.log('  --url <url>    Set Manifest Cloud service URL');
    console.log('  --key <key>    Set API key for authentication');
    console.log('');
    console.log('Environment Variables:');
    console.log('  MANIFEST_CLOUD_URL      Manifest Cloud service URL');
    console.log('  MANIFEST_CLOUD_API_KEY  API key for authentication');
    console.log('');
    console.log('Examples:');
    console.log('  node examples/test-manifest-cloud-client.js');
    console.log('  MANIFEST_CLOUD_URL=http://cloud.example.com node examples/test-manifest-cloud-client.js');
    console.log('  node examples/test-manifest-cloud-client.js --url http://cloud.example.com --key my-api-key');
    return;
  }

  // Parse command line arguments
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--url' && args[i + 1]) {
      process.env.MANIFEST_CLOUD_URL = args[i + 1];
      i++;
    } else if (args[i] === '--key' && args[i + 1]) {
      process.env.MANIFEST_CLOUD_API_KEY = args[i + 1];
      i++;
    }
  }

  testManifestCloudClient().catch(console.error);
}

module.exports = { testManifestCloudClient };
