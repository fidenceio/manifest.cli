#!/usr/bin/env node

/**
 * Comprehensive Test Runner
 * 
 * Runs all test suites: security, package security, and core functionality
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Test suites
const testSuites = [
    {
        name: 'Security Tests',
        file: 'security-test.js',
        description: 'Authentication, authorization, input validation, and security headers'
    },
    {
        name: 'Package Security Tests',
        file: 'package-security-test.js',
        description: 'Package vulnerabilities, outdated dependencies, and security best practices'
    },
    {
        name: 'Core Functionality Tests',
        file: 'core-functionality-test.js',
        description: 'Version management, documentation updates, and repository operations'
    }
];

// Test results tracking
let overallResults = {
    total: 0,
    passed: 0,
    failed: 0,
    suites: []
};

// Colors for console output
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m'
};

// Helper functions
function log(message, color = 'reset') {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

function logHeader(message) {
    log('\n' + '='.repeat(60), 'bright');
    log(message, 'cyan');
    log('='.repeat(60), 'bright');
}

function logSubHeader(message) {
    log('\n' + '-'.repeat(40), 'yellow');
    log(message, 'yellow');
    log('-'.repeat(40), 'yellow');
}

// Check prerequisites
function checkPrerequisites() {
    logHeader('🔍 Checking Prerequisites');
    
    const checks = [
        {
            name: 'Docker',
            command: 'docker --version',
            required: true
        },
        {
            name: 'Docker Compose',
            command: 'docker-compose --version',
            required: true
        },
        {
            name: 'Node.js',
            command: 'node --version',
            required: true
        },
        {
            name: 'npm',
            command: 'npm --version',
            required: true
        }
    ];
    
    let allChecksPassed = true;
    
    for (const check of checks) {
        try {
            const result = execSync(check.command, { encoding: 'utf8' });
            log(`✅ ${check.name}: ${result.trim()}`, 'green');
        } catch (error) {
            if (check.required) {
                log(`❌ ${check.name}: Not found`, 'red');
                allChecksPassed = false;
            } else {
                log(`⚠️  ${check.name}: Not found (optional)`, 'yellow');
            }
        }
    }
    
    if (!allChecksPassed) {
        log('\n❌ Required prerequisites not met. Please install missing tools.', 'red');
        process.exit(1);
    }
    
    log('\n✅ All prerequisites met!', 'green');
}

// Start services
async function startServices() {
    logHeader('🚀 Starting Services');
    
    try {
        // Check if services are already running
        const containers = execSync('docker ps --format "{{.Names}}"', { encoding: 'utf8' });
        
        if (containers.includes('manifest-cloud-service')) {
            log('✅ Services already running', 'green');
            return;
        }
        
        log('📦 Building and starting services...', 'blue');
        execSync('docker-compose up -d --build', { stdio: 'inherit' });
        
        // Wait for services to be ready
        log('⏳ Waiting for services to be ready...', 'yellow');
        let attempts = 0;
        const maxAttempts = 30;
        
        while (attempts < maxAttempts) {
            try {
                const response = execSync('curl -s http://localhost:3001/health', { encoding: 'utf8' });
                if (response.includes('healthy')) {
                    log('✅ Services are ready!', 'green');
                    break;
                }
            } catch (error) {
                // Service not ready yet
            }
            
            attempts++;
            process.stdout.write('.');
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
        
        if (attempts >= maxAttempts) {
            throw new Error('Services failed to start within timeout');
        }
        
    } catch (error) {
        log(`❌ Failed to start services: ${error.message}`, 'red');
        process.exit(1);
    }
}

// Run a single test suite
async function runTestSuite(suite) {
    logSubHeader(`🧪 Running ${suite.name}`);
    log(`📝 ${suite.description}`, 'blue');
    
    const testFile = path.join(__dirname, suite.file);
    
    if (!fs.existsSync(testFile)) {
        log(`❌ Test file not found: ${suite.file}`, 'red');
        return { success: false, error: 'Test file not found' };
    }
    
    try {
        // Run the test suite
        const result = execSync(`node ${testFile}`, { 
            encoding: 'utf8',
            stdio: 'pipe'
        });
        
        // Parse results (this is a simplified approach)
        const passed = (result.match(/✅/g) || []).length;
        const failed = (result.match(/❌/g) || []).length;
        const total = passed + failed;
        
        const suiteResult = {
            name: suite.name,
            success: failed === 0,
            total,
            passed,
            failed,
            output: result
        };
        
        overallResults.suites.push(suiteResult);
        overallResults.total += total;
        overallResults.passed += passed;
        overallResults.failed += failed;
        
        if (suiteResult.success) {
            log(`✅ ${suite.name} completed successfully`, 'green');
        } else {
            log(`❌ ${suite.name} had ${failed} failures`, 'red');
        }
        
        return suiteResult;
        
    } catch (error) {
        const suiteResult = {
            name: suite.name,
            success: false,
            total: 0,
            passed: 0,
            failed: 1,
            error: error.message,
            output: error.stdout || error.message
        };
        
        overallResults.suites.push(suiteResult);
        overallResults.total += 1;
        overallResults.failed += 1;
        
        log(`❌ ${suite.name} failed to run: ${error.message}`, 'red');
        return suiteResult;
    }
}

// Run all test suites
async function runAllTests() {
    logHeader('🧪 Running All Test Suites');
    
    for (const suite of testSuites) {
        await runTestSuite(suite);
    }
}

// Generate test report
function generateReport() {
    logHeader('📊 Test Report');
    
    // Overall results
    log(`\n📈 Overall Results:`, 'bright');
    log(`   Total Tests: ${overallResults.total}`, 'blue');
    log(`   Passed: ${overallResults.passed}`, 'green');
    log(`   Failed: ${overallResults.failed}`, overallResults.failed > 0 ? 'red' : 'green');
    log(`   Success Rate: ${overallResults.total > 0 ? ((overallResults.passed / overallResults.total) * 100).toFixed(1) : 0}%`, 
        overallResults.failed > 0 ? 'yellow' : 'green');
    
    // Suite results
    log(`\n📋 Suite Results:`, 'bright');
    for (const suite of overallResults.suites) {
        const status = suite.success ? '✅' : '❌';
        const color = suite.success ? 'green' : 'red';
        log(`   ${status} ${suite.name}: ${suite.passed}/${suite.total} passed`, color);
        
        if (!suite.success && suite.error) {
            log(`      Error: ${suite.error}`, 'red');
        }
    }
    
    // Recommendations
    if (overallResults.failed > 0) {
        log(`\n⚠️  Recommendations:`, 'yellow');
        log(`   - Review failed tests above`, 'yellow');
        log(`   - Check service logs: docker-compose logs manifest-cloud`, 'yellow');
        log(`   - Verify configuration and environment variables`, 'yellow');
        log(`   - Ensure all prerequisites are met`, 'yellow');
    } else {
        log(`\n🎉 All tests passed! The system is secure and fully functional.`, 'green');
    }
}

// Cleanup function
function cleanup() {
    logHeader('🧹 Cleanup');
    
    try {
        log('🛑 Stopping services...', 'yellow');
        execSync('docker-compose down', { stdio: 'inherit' });
        log('✅ Services stopped', 'green');
    } catch (error) {
        log(`⚠️  Cleanup warning: ${error.message}`, 'yellow');
    }
}

// Main execution
async function main() {
    try {
        logHeader('🚀 Manifest Cloud Comprehensive Testing Suite');
        log('Testing security, package updates, and core functionality', 'blue');
        
        // Check prerequisites
        checkPrerequisites();
        
        // Start services
        await startServices();
        
        // Run all tests
        await runAllTests();
        
        // Generate report
        generateReport();
        
        // Exit with appropriate code
        if (overallResults.failed === 0) {
            log('\n🎉 All tests completed successfully!', 'green');
            process.exit(0);
        } else {
            log('\n❌ Some tests failed. Please review the report above.', 'red');
            process.exit(1);
        }
        
    } catch (error) {
        log(`\n💥 Test suite execution failed: ${error.message}`, 'red');
        process.exit(1);
    }
}

// Handle cleanup on exit
process.on('SIGINT', () => {
    log('\n\n⚠️  Test execution interrupted by user', 'yellow');
    cleanup();
    process.exit(1);
});

process.on('SIGTERM', () => {
    log('\n\n⚠️  Test execution terminated', 'yellow');
    cleanup();
    process.exit(1);
});

// Run if this file is executed directly
if (require.main === module) {
    main();
}

module.exports = {
    runAllTests,
    runTestSuite,
    generateReport,
    cleanup
};
