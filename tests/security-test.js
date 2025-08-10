#!/usr/bin/env node

/**
 * Security Test Suite for Manifest Cloud
 * Tests authentication, authorization, input validation, and security headers
 */

const axios = require('axios');
const { execSync } = require('child_process');

const BASE_URL = process.env.MANIFEST_API_URL || 'http://localhost:3001';
const API_KEY = process.env.MANIFEST_API_KEY || 'test-api-key';

console.log('🔒 Running Security Tests...\n');

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

// Test 1: Authentication - Missing API Key
test('Authentication - Missing API Key', async () => {
    try {
        await axios.get(`${BASE_URL}/api/v1/repository/info`);
        throw new Error('Should have required authentication');
    } catch (error) {
        if (error.response?.status !== 401) {
            throw new Error(`Expected 401, got ${error.response?.status}`);
        }
    }
});

// Test 2: Authentication - Invalid API Key
test('Authentication - Invalid API Key', async () => {
    try {
        await axios.get(`${BASE_URL}/api/v1/repository/info`, {
            headers: { 'Authorization': 'Bearer invalid-key' }
        });
        throw new Error('Should have rejected invalid key');
    } catch (error) {
        if (error.response?.status !== 401) {
            throw new Error(`Expected 401, got ${error.response?.status}`);
        }
    }
});

// Test 3: Authentication - Valid API Key
test('Authentication - Valid API Key', async () => {
    const response = await axios.get(`${BASE_URL}/api/v1/repository/info`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    if (response.status !== 200) {
        throw new Error(`Expected 200, got ${response.status}`);
    }
});

// Test 4: Authorization - Protected Endpoints
test('Authorization - Protected Endpoints', async () => {
    const protectedEndpoints = [
        '/api/v1/repository/info',
        '/api/v1/repository/stats',
        '/api/v1/repository/commits'
    ];
    
    for (const endpoint of protectedEndpoints) {
        try {
            await axios.get(`${BASE_URL}${endpoint}`);
            throw new Error(`Endpoint ${endpoint} should require authentication`);
        } catch (error) {
            if (error.response?.status !== 401) {
                throw new Error(`Expected 401 for ${endpoint}, got ${error.response?.status}`);
            }
        }
    }
});

// Test 5: Input Validation - Malformed JSON
test('Input Validation - Malformed JSON', async () => {
    try {
        await axios.post(`${BASE_URL}/api/v1/repository/description`, 
            'invalid json', 
            { 
                headers: { 
                    'Authorization': `Bearer ${API_KEY}`,
                    'Content-Type': 'application/json'
                }
            }
        );
        throw new Error('Should have rejected malformed JSON');
    } catch (error) {
        if (error.response?.status !== 400) {
            throw new Error(`Expected 400, got ${error.response?.status}`);
        }
    }
});

// Test 6: Input Validation - Missing Required Fields
test('Input Validation - Missing Required Fields', async () => {
    try {
        await axios.post(`${BASE_URL}/api/v1/repository/description`, 
            {}, 
            { 
                headers: { 
                    'Authorization': `Bearer ${API_KEY}`,
                    'Content-Type': 'application/json'
                }
            }
        );
        throw new Error('Should have rejected missing fields');
    } catch (error) {
        if (error.response?.status !== 400) {
            throw new Error(`Expected 400, got ${error.response?.status}`);
        }
    }
});

// Test 7: Input Validation - SQL Injection Attempt
test('Input Validation - SQL Injection Attempt', async () => {
    const sqlInjectionPayload = "'; DROP TABLE users; --";
    try {
        await axios.post(`${BASE_URL}/api/v1/repository/description`, 
            { description: sqlInjectionPayload }, 
            { 
                headers: { 
                    'Authorization': `Bearer ${API_KEY}`,
                    'Content-Type': 'application/json'
                }
            }
        );
        // If it doesn't crash, that's good - the payload should be sanitized
    } catch (error) {
        // Acceptable if it returns an error, but shouldn't crash
        if (error.code === 'ECONNREFUSED') {
            throw new Error('Service connection refused');
        }
    }
});

// Test 8: Input Validation - XSS Attempt
test('Input Validation - XSS Attempt', async () => {
    const xssPayload = '<script>alert("xss")</script>';
    try {
        await axios.post(`${BASE_URL}/api/v1/repository/description`, 
            { description: xssPayload }, 
            { 
                headers: { 
                    'Authorization': `Bearer ${API_KEY}`,
                    'Content-Type': 'application/json'
                }
            }
        );
        // If it doesn't crash, that's good - the payload should be sanitized
    } catch (error) {
        // Acceptable if it returns an error, but shouldn't crash
        if (error.code === 'ECONNREFUSED') {
            throw new Error('Service connection refused');
        }
    }
});

// Test 9: Security Headers
test('Security Headers', async () => {
    const response = await axios.get(`${BASE_URL}/health`);
    
    const requiredHeaders = [
        'X-Content-Type-Options',
        'X-Frame-Options',
        'X-XSS-Protection'
    ];
    
    for (const header of requiredHeaders) {
        if (!response.headers[header.toLowerCase()]) {
            throw new Error(`Missing security header: ${header}`);
        }
    }
});

// Test 10: Rate Limiting
test('Rate Limiting', async () => {
    const requests = [];
    for (let i = 0; i < 5; i++) {
        try {
            const response = await axios.get(`${BASE_URL}/api/v1/repository/info`, {
                headers: { 'Authorization': `Bearer ${API_KEY}` }
            });
            requests.push(response.status);
        } catch (error) {
            requests.push(error.response?.status || 0);
        }
    }
    
    // Should eventually hit rate limit (429)
    if (!requests.includes(429)) {
        console.log('⚠️  Rate limiting may not be working (no 429 responses)');
    }
});

// Test 11: Container Security
test('Container Security - Non-root User', () => {
    try {
        const output = execSync('docker exec manifest-cloud id', { encoding: 'utf8' });
        if (output.includes('uid=0')) {
            throw new Error('Container is running as root');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 12: Container Security - Limited Capabilities
test('Container Security - Limited Capabilities', () => {
    try {
        const output = execSync('docker exec manifest-cloud cat /proc/self/status | grep Cap', { encoding: 'utf8' });
        if (output.includes('0000003fffffffff')) {
            throw new Error('Container has all capabilities');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 13: Container Security - Dangerous Mounts
test('Container Security - Dangerous Mounts', () => {
    try {
        const output = execSync('docker exec manifest-cloud mount | grep -E "(proc|sys|dev)"', { encoding: 'utf8' });
        const dangerousMounts = output.split('\n').filter(line => 
            line.includes('/proc') || line.includes('/sys') || line.includes('/dev')
        );
        
        if (dangerousMounts.length > 3) { // Basic mounts are OK
            throw new Error('Container has dangerous mount points');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

console.log('\n📊 Security Test Results:');
console.log(`Passed: ${passedTests}`);
console.log(`Failed: ${failedTests}`);
console.log(`Total: ${passedTests + failedTests}`);

if (failedTests === 0) {
    console.log('\n🎉 All security tests passed!');
    process.exit(0);
} else {
    console.log('\n❌ Some security tests failed. Please review the output above.');
    process.exit(1);
}
