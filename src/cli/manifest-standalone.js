#!/usr/bin/env node

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

// Determine the installation directory
function getInstallDir() {
  // If running from Homebrew installation
  if (__dirname.includes('/Cellar/') || __dirname.includes('/opt/homebrew/')) {
    return path.dirname(__dirname);
  }
  
  // If running from development environment
  if (__dirname.includes('src/cli')) {
    return path.join(__dirname, '../..');
  }
  
  // Fallback to current working directory
  return process.cwd();
}

// Check if we're in a git repository
function isGitRepo() {
  try {
    execSync('git rev-parse --git-dir', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

// Main CLI logic
async function main() {
  const installDir = getInstallDir();
  const cliPath = path.join(installDir, 'src/cli/manifest-cli.js');
  
  // Check if the CLI file exists
  if (!fs.existsSync(cliPath)) {
    console.error('❌ Error: Manifest CLI not found');
    console.error(`   Expected at: ${cliPath}`);
    console.error('');
    console.error('💡 This usually means:');
    console.error('   1. The CLI wasn\'t installed correctly');
    console.error('   2. You\'re running from the wrong directory');
    console.error('   3. The installation is corrupted');
    console.error('');
    console.error('🔧 Solutions:');
    console.error('   • Reinstall: brew uninstall manifest && brew install manifest');
    console.error('   • Check installation: brew list manifest');
    console.error('   • Report issue: https://github.com/fidenceio/manifest.local/issues');
    process.exit(1);
  }
  
  // Check if we're in a git repository
  if (!isGitRepo()) {
    console.error('❌ Error: Not in a git repository');
    console.error('');
    console.error('💡 Manifest CLI requires a git repository to work.');
    console.error('   Please run this command from within a git repository.');
    console.error('');
    console.error('🔧 Solutions:');
    console.error('   • Initialize git: git init');
    console.error('   • Navigate to existing repo: cd /path/to/your/repo');
    console.error('   • Clone a repo: git clone <repository-url>');
    process.exit(1);
  }
  
  try {
    // Change to the installation directory and run the CLI
    process.chdir(installDir);
    
    // Load and run the CLI
    const { spawn } = require('child_process');
    const child = spawn('node', [cliPath, ...process.argv.slice(2)], {
      stdio: 'inherit',
      cwd: process.cwd()
    });
    
    child.on('exit', (code) => {
      process.exit(code);
    });
    
    child.on('error', (error) => {
      console.error('❌ Error running Manifest CLI:', error.message);
      process.exit(1);
    });
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error('');
    console.error('💡 This might be a configuration issue.');
    console.error('   Check your ~/.manifest-local/.env file and try again.');
    process.exit(1);
  }
}

// Handle uncaught errors
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error.message);
  console.error(error.stack);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

// Run the CLI
if (require.main === module) {
  main().catch((error) => {
    console.error('❌ Fatal Error:', error.message);
    process.exit(1);
  });
}

module.exports = { main, getInstallDir, isGitRepo };
