#!/usr/bin/env node

/**
 * Core Functionality Test Suite for Manifest Cloud
 * Tests service health, API endpoints, and container functionality
 */

const axios = require('axios');
const { execSync } = require('child_process');

const BASE_URL = process.env.MANIFEST_API_URL || 'http://localhost:3001';
const API_KEY = process.env.MANIFEST_API_KEY || 'test-api-key';

console.log('🚀 Running Core Functionality Tests...\n');

let passedTests = 0;
let failedTests = 0;

function test(name, testFn) {
    try {
        testFn();
        console.log(`✅ ${name}`);
        passedTests++;
    } catch (error) {
        console.log(`❌ ${name}: ${error.message}`);
        failedTests++;
    }
}

// Test 1: Service Health
test('Service Health Endpoint', async () => {
    const response = await axios.get(`${BASE_URL}/health`);
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
    if (!response.data.includes('OK')) {
        throw new Error('Health endpoint should return OK status');
    }
});

// Test 2: Root Endpoint
test('Root Endpoint', async () => {
    const response = await axios.get(`${BASE_URL}/`);
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
    if (!response.data.includes('Manifest Cloud')) {
        throw new Error('Root endpoint should return Manifest Cloud information');
    }
});

// Test 3: Repository API - Get Repository Info
test('Repository API - Get Repository Info', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/info`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 4: Repository API - Get Repository Stats
test('Repository API - Get Repository Stats', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/stats`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 5: Repository API - Get Repository Commits
test('Repository API - Get Repository Commits', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/commits`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 6: Repository API - Get Repository Access
test('Repository API - Get Repository Access', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/access`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 7: Repository API - Update Description
test('Repository API - Update Description', async () => {
    const testDescription = 'Test description update';
    const response = await axios.put(`${BASE_URL}/api/v1/repository/description`, 
        { description: testDescription },
        { headers: { 'Authorization': `Bearer ${API_KEY}` } }
    );
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 8: Repository API - Add Topics
test('Repository API - Add Topics', async () => {
    const testTopics = ['test-topic', 'manifest-cloud'];
    const response = await axios.post(`${BASE_URL}/api/v1/repository/topics`, 
        { topics: testTopics },
        { headers: { 'Authorization': `Bearer ${API_KEY}` } }
    );
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 9: Repository API - Get Releases
test('Repository API - Get Releases', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/releases`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 10: Repository API - Create Release
test('Repository API - Create Release', async () => {
    const testRelease = {
        tag_name: 'v1.0.0-test',
        name: 'Test Release',
        body: 'This is a test release'
    };
    const response = await axios.post(`${BASE_URL}/api/v1/repository/releases`, 
        testRelease,
        { headers: { 'Authorization': `Bearer ${API_KEY}` } }
    );
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 11: Repository API - Get Issues
test('Repository API - Get Issues', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/issues`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 12: Repository API - Get Pull Requests
test('Repository API - Get Pull Requests', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/pulls`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 13: Error Handling - Invalid Repository
test('Error Handling - Invalid Repository', async () => {
    try {
        await axios.get(`${BASE_URL}/api/v1/repository/info?repo=invalid/repo`, {
            headers: { 'Authorization': `Bearer ${API_KEY}` }
        });
        throw new Error('Should have returned an error for invalid repository');
    } catch (error) {
        if (error.response?.status === 404 || error.response?.status === 400) {
            // Expected error
        } else {
            throw new Error(`Unexpected error status: ${error.response?.status}`);
        }
    }
});

// Test 14: Error Handling - Missing Required Fields
test('Error Handling - Missing Required Fields', async () => {
    try {
        await axios.post(`${BASE_URL}/api/v1/repository/description`, 
            {},
            { headers: { 'Authorization': `Bearer ${API_KEY}` } }
        );
        throw new Error('Should have returned an error for missing fields');
    } catch (error) {
        if (error.response?.status === 400) {
            // Expected error
        } else {
            throw new Error(`Unexpected error status: ${error.response?.status}`);
        }
    }
});

// Test 15: Container Functionality - GitHub CLI
test('Container Functionality - GitHub CLI', () => {
    try {
        const output = execSync('docker exec manifest-cloud gh --version', { encoding: 'utf8' });
        if (!output.includes('gh version')) {
            throw new Error('GitHub CLI not available in container');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 16: Container Functionality - Git
test('Container Functionality - Git', () => {
    try {
        const output = execSync('docker exec manifest-cloud git --version', { encoding: 'utf8' });
        if (!output.includes('git version')) {
            throw new Error('Git not available in container');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 17: Container Functionality - SSH Access
test('Container Functionality - SSH Access', () => {
    try {
        const output = execSync('docker exec manifest-cloud ssh -V', { encoding: 'utf8' });
        if (!output.includes('OpenSSH')) {
            throw new Error('SSH not available in container');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 18: Container Functionality - Git Configuration
test('Container Functionality - Git Configuration', () => {
    try {
        const output = execSync('docker exec manifest-cloud git config --list', { encoding: 'utf8' });
        if (!output.includes('user.name') && !output.includes('user.email')) {
            console.log('⚠️  Git configuration may not be set up');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 19: Container Functionality - Node.js
test('Container Functionality - Node.js', () => {
    try {
        const output = execSync('docker exec manifest-cloud node --version', { encoding: 'utf8' });
        if (!output.includes('v20.')) {
            throw new Error('Node.js 20 not available in container');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 20: Container Functionality - NPM
test('Container Functionality - NPM', () => {
    try {
        const output = execSync('docker exec manifest-cloud npm --version', { encoding: 'utf8' });
        if (!output.match(/^\d+\.\d+\.\d+$/)) {
            throw new Error('NPM not available in container');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

console.log('\n📊 Core Functionality Test Results:');
console.log(`Passed: ${passedTests}`);
console.log(`Failed: ${failedTests}`);
console.log(`Total: ${passedTests + failedTests}`);

if (failedTests === 0) {
    console.log('\n🎉 All core functionality tests passed!');
    process.exit(0);
} else {
    console.log('\n❌ Some core functionality tests failed. Please review the output above.');
    process.exit(1);
}
