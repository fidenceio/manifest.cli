#!/usr/bin/env node

const { Command } = require('commander');
const { ManifestClient } = require('../client/manifestClient');
const chalk = require('chalk');
const ora = require('ora');
const inquirer = require('inquirer');
const path = require('path');
const fs = require('fs');

const program = new Command();

// Global options
program
  .name('manifest')
  .description('Universal App Store Service CLI')
  .version('1.0.0')
  .option('-u, --url <url>', 'Manifest service URL', 'http://localhost:3000')
  .option('-t, --token <token>', 'Authentication token')
  .option('-v, --verbose', 'Enable verbose logging')
  .option('-q, --quiet', 'Suppress output');

// Create client instance
let client;

function createClient() {
  const options = program.opts();
  client = new ManifestClient(options.url, {
    timeout: 30000,
    logger: options.verbose ? console : null
  });
  
  if (options.token) {
    client.setAuthToken(options.token);
  }
}

// Health check command
program
  .command('health')
  .description('Check Manifest service health')
  .action(async () => {
    createClient();
    const spinner = ora('Checking service health...').start();
    
    try {
      const health = await client.ping();
      spinner.succeed('Service is healthy');
      
      if (!program.opts().quiet) {
        console.log(chalk.green('\nService Status:'));
        console.log(`  Status: ${health.status}`);
        console.log(`  Uptime: ${Math.floor(health.uptime / 60)} minutes`);
        console.log(`  Version: ${health.version}`);
        console.log(`  Timestamp: ${health.timestamp}`);
      }
    } catch (error) {
      spinner.fail('Service health check failed');
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

// Analyze command
program
  .command('analyze <repoPath>')
  .description('Analyze repository manifest')
  .action(async (repoPath) => {
    createClient();
    const spinner = ora('Analyzing repository...').start();
    
    try {
      const analysis = await client.analyze(repoPath);
      spinner.succeed('Repository analysis complete');
      
      if (!program.opts().quiet) {
        console.log(chalk.blue('\nRepository Analysis:'));
        console.log(`  Repository: ${analysis.repository}`);
        console.log(`  Manifest Format: ${analysis.manifest.format ? 'Detected' : 'Not detected'}`);
        console.log(`  CI/CD Platform: ${analysis.manifest.cicdPlatform || 'Not detected'}`);
        
        if (analysis.manifest.metadata) {
          console.log(chalk.green('\nMetadata:'));
          Object.entries(analysis.manifest.metadata).forEach(([key, value]) => {
            console.log(`  ${key}: ${value}`);
          });
        }
      }
    } catch (error) {
      spinner.fail('Repository analysis failed');
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

// Version bump command
program
  .command('bump <repoPath>')
  .description('Bump repository version')
  .option('-t, --type <type>', 'Version increment type (patch, minor, major)', 'patch')
  .option('-a, --auto', 'Auto-detect version strategy')
  .action(async (repoPath, options) => {
    createClient();
    const spinner = ora('Bumping version...').start();
    
    try {
      const result = await client.versionBump(repoPath, options.type, { auto: options.auto });
      spinner.succeed('Version bump complete');
      
      if (!program.opts().quiet) {
        console.log(chalk.green('\nVersion Bump Result:'));
        console.log(`  Repository: ${result.repository}`);
        console.log(`  Previous Version: ${result.result.increment.previousVersion}`);
        console.log(`  New Version: ${result.result.increment.newVersion}`);
        console.log(`  Increment Type: ${result.result.increment.type}`);
        
        if (result.result.push) {
          console.log(chalk.blue('\nPush Result:'));
          console.log(`  Status: ${result.result.push.success ? 'Success' : 'Failed'}`);
          if (result.result.push.message) {
            console.log(`  Message: ${result.result.push.message}`);
          }
        }
      }
    } catch (error) {
      spinner.fail('Version bump failed');
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

// CI/CD generate command
program
  .command('cicd <repoPath>')
  .description('Generate CI/CD configuration')
  .option('-p, --platform <platform>', 'CI/CD platform (github, gitlab, jenkins, etc.)')
  .option('-o, --output <file>', 'Output file path')
  .action(async (repoPath, options) => {
    createClient();
    const spinner = ora('Generating CI/CD configuration...').start();
    
    try {
      const result = await client.cicdGenerate(repoPath, options.platform, {});
      spinner.succeed('CI/CD configuration generated');
      
      if (!program.opts().quiet) {
        console.log(chalk.blue('\nCI/CD Configuration:'));
        console.log(`  Repository: ${result.repository}`);
        console.log(`  Platform: ${result.cicd.platform}`);
        
        if (options.output) {
          fs.writeFileSync(options.output, JSON.stringify(result.cicd.config, null, 2));
          console.log(chalk.green(`\nConfiguration saved to: ${options.output}`));
        } else {
          console.log(chalk.yellow('\nConfiguration:'));
          console.log(JSON.stringify(result.cicd.config, null, 2));
        }
      }
    } catch (error) {
      spinner.fail('CI/CD configuration generation failed');
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

// Install generate command
program
  .command('install <repoPath>')
  .description('Generate installation scripts')
  .option('-p, --platform <platform>', 'Target platform (linux, macos, windows, etc.)')
  .option('-c, --container <type>', 'Container type (docker, kubernetes, podman)')
  .option('-o, --output <dir>', 'Output directory for scripts')
  .action(async (repoPath, options) => {
    createClient();
    const spinner = ora('Generating installation scripts...').start();
    
    try {
      const result = await client.installGenerate(repoPath, options.platform, options.container, {});
      spinner.succeed('Installation scripts generated');
      
      if (!program.opts().quiet) {
        console.log(chalk.blue('\nInstallation Scripts:'));
        console.log(`  Repository: ${result.repository}`);
        console.log(`  Platform: ${result.install.platform}`);
        console.log(`  Container Type: ${result.install.containerType}`);
        
        if (options.output) {
          const outputDir = path.resolve(options.output);
          if (!fs.existsSync(outputDir)) {
            fs.mkdirSync(outputDir, { recursive: true });
          }
          
          const scriptPath = path.join(outputDir, `install-${result.install.platform}.sh`);
          fs.writeFileSync(scriptPath, result.install.script);
          console.log(chalk.green(`\nScript saved to: ${scriptPath}`));
        } else {
          console.log(chalk.yellow('\nScript:'));
          console.log(result.install.script);
        }
      }
    } catch (error) {
      spinner.fail('Installation script generation failed');
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

// Health check command for repository
program
  .command('health <repoPath>')
  .description('Get repository health status')
  .action(async (repoPath) => {
    createClient();
    const spinner = ora('Checking repository health...').start();
    
    try {
      const health = await client.health(repoPath);
      spinner.succeed('Health check complete');
      
      if (!program.opts().quiet) {
        console.log(chalk.blue('\nRepository Health:'));
        console.log(`  Repository: ${health.repository}`);
        console.log(`  Overall Score: ${health.health.score}/100`);
        
        console.log(chalk.green('\nComponent Status:'));
        console.log(`  Manifest: ${health.health.manifest.status} (${health.health.manifest.format ? 'Detected' : 'Not detected'})`);
        console.log(`  Version: ${health.health.version.status} (${health.health.version.current || 'Not found'})`);
        console.log(`  CI/CD: ${health.health.cicd.status} (${health.health.cicd.platform || 'Not detected'})`);
        console.log(`  Install: ${health.health.install.status} (${health.health.install.platform})`);
        
        if (health.health.recommendations.length > 0) {
          console.log(chalk.yellow('\nRecommendations:'));
          health.health.recommendations.forEach((rec, index) => {
            console.log(`  ${index + 1}. ${rec}`);
          });
        }
      }
    } catch (error) {
      spinner.fail('Health check failed');
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

// Interactive mode
program
  .command('interactive')
  .description('Start interactive mode')
  .action(async () => {
    createClient();
    console.log(chalk.blue('🚀 Welcome to Manifest Interactive Mode\n'));
    
    try {
      const { action } = await inquirer.prompt([
        {
          type: 'list',
          name: 'action',
          message: 'What would you like to do?',
          choices: [
            'Analyze repository',
            'Bump version',
            'Generate CI/CD config',
            'Generate install scripts',
            'Check health',
            'Exit'
          ]
        }
      ]);
      
      if (action === 'Exit') {
        console.log(chalk.green('Goodbye! 👋'));
        process.exit(0);
      }
      
      const { repoPath } = await inquirer.prompt([
        {
          type: 'input',
          name: 'repoPath',
          message: 'Enter repository path:',
          default: process.cwd()
        }
      ]);
      
      switch (action) {
        case 'Analyze repository':
          await handleInteractiveAction('analyzing repository', () => client.analyze(repoPath));
          break;
        case 'Bump version':
          const { incrementType } = await inquirer.prompt([
            {
              type: 'list',
              name: 'incrementType',
              message: 'Select increment type:',
              choices: ['patch', 'minor', 'major']
            }
          ]);
          await handleInteractiveAction('bumping version', () => client.versionBump(repoPath, incrementType));
          break;
        case 'Generate CI/CD config':
          await handleInteractiveAction('generating CI/CD config', () => client.cicdGenerate(repoPath));
          break;
        case 'Generate install scripts':
          await handleInteractiveAction('generating install scripts', () => client.installGenerate(repoPath));
          break;
        case 'Check health':
          await handleInteractiveAction('checking health', () => client.health(repoPath));
          break;
      }
    } catch (error) {
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

async function handleInteractiveAction(action, operation) {
  const spinner = ora(`${action}...`).start();
  
  try {
    const result = await operation();
    spinner.succeed(`${action} complete`);
    
    console.log(chalk.green('\nResult:'));
    console.log(JSON.stringify(result, null, 2));
    
    const { continueAction } = await inquirer.prompt([
      {
        type: 'confirm',
        name: 'continueAction',
        message: 'Would you like to perform another action?',
        default: true
      }
    ]);
    
    if (continueAction) {
      // Restart interactive mode
      program.parse(['node', 'manifest-cli.js', 'interactive']);
    } else {
      console.log(chalk.green('Goodbye! 👋'));
      process.exit(0);
    }
  } catch (error) {
    spinner.fail(`${action} failed`);
    console.error(chalk.red(`Error: ${error.message}`));
    
    const { retry } = await inquirer.prompt([
      {
        type: 'confirm',
        name: 'retry',
        message: 'Would you like to retry?',
        default: false
      }
    ]);
    
    if (retry) {
      await handleInteractiveAction(action, operation);
    } else {
      process.exit(1);
    }
  }
}

// Error handling
program.exitOverride();

try {
  program.parse();
} catch (err) {
  if (err.code === 'commander.help') {
    process.exit(0);
  } else {
    console.error(chalk.red(`Error: ${err.message}`));
    process.exit(1);
  }
}
