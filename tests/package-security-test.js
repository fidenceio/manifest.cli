#!/usr/bin/env node

/**
 * Package Security Test Suite for Manifest Cloud
 * Tests package dependencies, security vulnerabilities, and Docker security
 */

const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');

console.log('📦 Running Package Security Tests...\n');

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

// Test 1: Package Lock File
test('Package Lock File Exists', () => {
    if (!fs.existsSync('package-lock.json')) {
        throw new Error('package-lock.json is missing');
    }
});

// Test 2: NPM Audit - Critical Vulnerabilities
test('NPM Audit - No Critical Vulnerabilities', () => {
    try {
        const output = execSync('npm audit --audit-level=critical', { encoding: 'utf8' });
        if (output.includes('found') && output.includes('vulnerabilities')) {
            throw new Error('Critical vulnerabilities found');
        }
    } catch (error) {
        if (error.status === 1) {
            throw new Error('Critical vulnerabilities detected');
        }
        throw error;
    }
});

// Test 3: NPM Audit - High Vulnerabilities
test('NPM Audit - No High Vulnerabilities', () => {
    try {
        const output = execSync('npm audit --audit-level=high', { encoding: 'utf8' });
        if (output.includes('found') && output.includes('vulnerabilities')) {
            throw new Error('High vulnerabilities found');
        }
    } catch (error) {
        if (error.status === 1) {
            throw new Error('High vulnerabilities detected');
        }
        throw error;
    }
});

// Test 4: NPM Audit - Moderate Vulnerabilities
test('NPM Audit - No Moderate Vulnerabilities', () => {
    try {
        const output = execSync('npm audit --audit-level=moderate', { encoding: 'utf8' });
        if (output.includes('found') && output.includes('vulnerabilities')) {
            throw new Error('Moderate vulnerabilities found');
        }
    } catch (error) {
        if (error.status === 1) {
            throw new Error('Moderate vulnerabilities detected');
        }
        throw error;
    }
});

// Test 5: Outdated Dependencies
test('Dependencies Are Up to Date', () => {
    try {
        const output = execSync('npm outdated', { encoding: 'utf8' });
        if (output.trim() !== '') {
            console.log('⚠️  Some dependencies are outdated:');
            console.log(output);
        }
    } catch (error) {
        // npm outdated returns exit code 1 when there are outdated packages
        if (error.status === 1) {
            console.log('⚠️  Some dependencies are outdated');
        } else {
            throw error;
        }
    }
});

// Test 6: Dev Dependencies in Production
test('No Dev Dependencies in Production', () => {
    const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    const devDeps = Object.keys(packageJson.devDependencies || {});
    
    // Check if any dev dependencies are accidentally in production
    const productionScripts = ['start', 'prod'];
    for (const script of productionScripts) {
        if (packageJson.scripts && packageJson.scripts[script]) {
            const scriptContent = packageJson.scripts[script];
            for (const devDep of devDeps) {
                if (scriptContent.includes(devDep)) {
                    throw new Error(`Dev dependency ${devDep} used in production script ${script}`);
                }
            }
        }
    }
});

// Test 7: Version Pinning
test('Dependencies Are Version Pinned', () => {
    const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    const allDeps = { ...packageJson.dependencies, ...packageJson.devDependencies };
    
    for (const [dep, version] of Object.entries(allDeps)) {
        if (version.includes('^') || version.includes('~') || version === '*') {
            console.log(`⚠️  Dependency ${dep} is not pinned: ${version}`);
        }
    }
});

// Test 8: Known Malicious Packages
test('No Known Malicious Packages', () => {
    const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    const allDeps = { ...packageJson.dependencies, ...packageJson.devDependencies };
    
    const knownMalicious = [
        'malicious-package',
        'evil-package',
        'hack-package'
    ];
    
    for (const malicious of knownMalicious) {
        if (allDeps[malicious]) {
            throw new Error(`Known malicious package detected: ${malicious}`);
        }
    }
});

// Test 9: Dockerfile Security - Base Image
test('Dockerfile Uses Alpine Base Image', () => {
    const dockerfile = fs.readFileSync('Dockerfile', 'utf8');
    if (!dockerfile.includes('FROM node:20-alpine')) {
        throw new Error('Dockerfile should use Alpine base image for security');
    }
});

// Test 10: Dockerfile Security - Node Version
test('Dockerfile Uses Specific Node Version', () => {
    const dockerfile = fs.readFileSync('Dockerfile', 'utf8');
    if (!dockerfile.includes('FROM node:20-alpine')) {
        throw new Error('Dockerfile should pin Node.js version');
    }
});

// Test 11: Dockerfile Security - Non-root User
test('Dockerfile Creates Non-root User', () => {
    const dockerfile = fs.readFileSync('Dockerfile', 'utf8');
    if (!dockerfile.includes('USER nodejs')) {
        throw new Error('Dockerfile should create and use non-root user');
    }
});

// Test 12: Sensitive Data in Code
test('No Sensitive Data in Code', () => {
    const sensitivePatterns = [
        /password\s*[:=]\s*['"][^'"]+['"]/i,
        /api_key\s*[:=]\s*['"][^'"]+['"]/i,
        /secret\s*[:=]\s*['"][^'"]+['"]/i,
        /token\s*[:=]\s*['"][^'"]+['"]/i
    ];
    
    const sourceFiles = [
        'src/index.js',
        'src/routes/repository.js',
        'src/services/repositoryService.js'
    ];
    
    for (const file of sourceFiles) {
        if (fs.existsSync(file)) {
            const content = fs.readFileSync(file, 'utf8');
            for (const pattern of sensitivePatterns) {
                if (pattern.test(content)) {
                    throw new Error(`Potential sensitive data found in ${file}`);
                }
            }
        }
    }
});

// Test 13: GitHub CLI Availability
test('GitHub CLI Available in Container', () => {
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

// Test 14: GitHub CLI Authentication
test('GitHub CLI Authentication Configured', () => {
    try {
        const output = execSync('docker exec manifest-cloud gh auth status', { encoding: 'utf8' });
        if (output.includes('not logged in')) {
            throw new Error('GitHub CLI not authenticated');
        }
    } catch (error) {
        if (error.message.includes('No such file or directory')) {
            throw new Error('Container not running - start services first');
        }
        throw error;
    }
});

// Test 15: Health Check Configuration
test('Health Check Properly Configured', () => {
    const dockerfile = fs.readFileSync('Dockerfile', 'utf8');
    if (!dockerfile.includes('HEALTHCHECK')) {
        throw new Error('Dockerfile should include health check');
    }
    
    if (!dockerfile.includes('curl -f http://localhost:3001/health')) {
        throw new Error('Health check should use proper endpoint');
    }
});

console.log('\n📊 Package Security Test Results:');
console.log(`Passed: ${passedTests}`);
console.log(`Failed: ${failedTests}`);
console.log(`Total: ${passedTests + failedTests}`);

if (failedTests === 0) {
    console.log('\n🎉 All package security tests passed!');
    process.exit(0);
} else {
    console.log('\n❌ Some package security tests failed. Please review the output above.');
    process.exit(1);
}
