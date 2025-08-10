const fs = require('fs').promises;
const path = require('path');
const { execSync } = require('child_process');
const { logger } = require('../utils/logger');
const { ManifestFormatManager } = require('./manifestFormatManager');

class EnhancedVersionManager {
  constructor() {
    this.manifestFormatManager = new ManifestFormatManager();
    this.versionStrategies = {
      semantic: {
        name: 'Semantic Versioning',
        pattern: /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/,
        increment: this.incrementSemanticVersion.bind(this)
      },
      date: {
        name: 'Date-based Versioning',
        pattern: /^(\d{4})\.(\d{2})\.(\d{2})\.(\d+)$/,
        increment: this.incrementDateVersion.bind(this)
      },
      commit: {
        name: 'Commit-based Versioning',
        pattern: /^([a-f0-9]{7,8})$/,
        increment: this.incrementCommitVersion.bind(this)
      },
      custom: {
        name: 'Custom Versioning',
        pattern: null,
        increment: this.incrementCustomVersion.bind(this)
      }
    };
  }

  /**
   * Detect version strategy for a repository
   */
  async detectVersionStrategy(repoPath) {
    try {
      logger.logOperation('Detecting version strategy', { repoPath });
      
      // Check for existing version files
      const versionFiles = await this.findVersionFiles(repoPath);
      
      // Check for Git repository
      const isGitRepo = await this.isGitRepository(repoPath);
      
      // Check for CI/CD configuration
      const cicdConfig = await this.detectCICDConfig(repoPath);
      
      // Determine strategy based on findings
      let strategy = 'semantic'; // Default
      let confidence = 0.5;
      
      if (versionFiles.length > 0) {
        const versionFile = versionFiles[0];
        const content = await fs.readFile(path.join(repoPath, versionFile), 'utf8');
        const version = content.trim();
        
        for (const [key, strategyConfig] of Object.entries(this.versionStrategies)) {
          if (strategyConfig.pattern && strategyConfig.pattern.test(version)) {
            strategy = key;
            confidence = 0.9;
            break;
          }
        }
      }
      
      if (isGitRepo) {
        confidence = Math.min(confidence + 0.2, 1.0);
      }
      
      if (cicdConfig) {
        confidence = Math.min(confidence + 0.1, 1.0);
      }
      
      logger.logOperation('Version strategy detected', { repoPath, strategy, confidence, versionFiles, isGitRepo, cicdConfig });
      
      return {
        strategy,
        confidence,
        versionFiles,
        isGitRepo,
        cicdConfig
      };
    } catch (error) {
      logger.logError('Detecting version strategy', error, { repoPath });
      throw error;
    }
  }

  /**
   * Find version files in repository
   */
  async findVersionFiles(repoPath) {
    const versionFiles = [];
    const commonVersionFiles = [
      'VERSION',
      'version',
      'VERSION.txt',
      'version.txt',
      '.version'
    ];
    
    for (const file of commonVersionFiles) {
      try {
        await fs.access(path.join(repoPath, file));
        versionFiles.push(file);
      } catch (error) {
        // File doesn't exist
      }
    }
    
    return versionFiles;
  }

  /**
   * Check if directory is a Git repository
   */
  async isGitRepository(repoPath) {
    try {
      await fs.access(path.join(repoPath, '.git'));
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Detect CI/CD configuration
   */
  async detectCICDConfig(repoPath) {
    const cicdFiles = [
      '.github/workflows',
      '.gitlab-ci.yml',
      'Jenkinsfile',
      '.circleci/config.yml',
      '.travis.yml',
      'azure-pipelines.yml',
      'bitbucket-pipelines.yml'
    ];
    
    for (const file of cicdFiles) {
      try {
        await fs.access(path.join(repoPath, file));
        return file;
      } catch (error) {
        // File doesn't exist
      }
    }
    
    return null;
  }

  /**
   * Get current version from repository
   */
  async getCurrentVersion(repoPath) {
    try {
      logger.logOperation('Getting current version', { repoPath });
      
      // Try to get version from manifest files first
      const manifestFormats = await this.manifestFormatManager.detectManifestFormat(repoPath);
      
      if (manifestFormats.length > 0) {
        const manifestInfo = manifestFormats[0];
        const metadata = await this.manifestFormatManager.extractMetadata(repoPath, manifestInfo);
        
        if (metadata.version) {
          logger.logOperation('Version found in manifest', { repoPath, version: metadata.version });
          return {
            version: metadata.version,
            source: 'manifest',
            file: manifestInfo.filename,
            metadata
          };
        }
      }
      
      // Try to get version from version files
      const versionFiles = await this.findVersionFiles(repoPath);
      
      if (versionFiles.length > 0) {
        const versionFile = versionFiles[0];
        const content = await fs.readFile(path.join(repoPath, versionFile), 'utf8');
        const version = content.trim();
        
        logger.logOperation('Version found in version file', { repoPath, version, file: versionFile });
        return {
          version,
          source: 'version_file',
          file: versionFile
        };
      }
      
      // Try to get version from Git tags
      if (await this.isGitRepository(repoPath)) {
        try {
          const gitVersion = await this.getGitVersion(repoPath);
          if (gitVersion) {
            logger.logOperation('Version found in Git', { repoPath, version: gitVersion });
            return {
              version: gitVersion,
              source: 'git',
              file: '.git'
            };
          }
        } catch (error) {
          logger.logWarning('Failed to get Git version', { repoPath, error: error.message });
        }
      }
      
      logger.logWarning('No version found', { repoPath });
      return null;
    } catch (error) {
      logger.logError('Getting current version', error, { repoPath });
      throw error;
    }
  }

  /**
   * Get version from Git repository
   */
  async getGitVersion(repoPath) {
    try {
      const cwd = process.cwd();
      process.chdir(repoPath);
      
      // Get latest tag
      const latestTag = execSync('git describe --tags --abbrev=0 2>/dev/null || echo ""', { encoding: 'utf8' }).trim();
      
      if (latestTag) {
        // Remove 'v' prefix if present
        return latestTag.startsWith('v') ? latestTag.substring(1) : latestTag;
      }
      
      // Get commit hash if no tags
      const commitHash = execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim();
      return commitHash;
    } catch (error) {
      return null;
    } finally {
      process.chdir(cwd);
    }
  }

  /**
   * Increment version based on strategy
   */
  async incrementVersion(repoPath, incrementType = 'patch', options = {}) {
    try {
      logger.logOperation('Incrementing version', { repoPath, incrementType, options });
      
      const currentVersionInfo = await this.getCurrentVersion(repoPath);
      if (!currentVersionInfo) {
        throw new Error('No current version found');
      }
      
      const { version: currentVersion, source, file } = currentVersionInfo;
      
      // Detect version strategy
      const strategyInfo = await this.detectVersionStrategy(repoPath);
      const strategy = this.versionStrategies[strategyInfo.strategy];
      
      if (!strategy) {
        throw new Error(`Unsupported version strategy: ${strategyInfo.strategy}`);
      }
      
      // Increment version
      const newVersion = await strategy.increment(currentVersion, incrementType, options);
      
      // Update version in repository
      const updateResult = await this.updateVersionInRepository(repoPath, newVersion, source, file, options);
      
      logger.logOperation('Version incremented successfully', { 
        repoPath, 
        oldVersion: currentVersion, 
        newVersion, 
        strategy: strategyInfo.strategy,
        updateResult 
      });
      
      return {
        oldVersion: currentVersion,
        newVersion,
        strategy: strategyInfo.strategy,
        source,
        file,
        updateResult
      };
    } catch (error) {
      logger.logError('Incrementing version', error, { repoPath, incrementType, options });
      throw error;
    }
  }

  /**
   * Increment semantic version
   */
  async incrementSemanticVersion(currentVersion, incrementType, options = {}) {
    const match = currentVersion.match(this.versionStrategies.semantic.pattern);
    if (!match) {
      throw new Error(`Invalid semantic version format: ${currentVersion}`);
    }
    
    let [_, major, minor, patch, prerelease, build] = match;
    major = parseInt(major);
    minor = parseInt(minor);
    patch = parseInt(patch);
    
    switch (incrementType) {
      case 'major':
        major++;
        minor = 0;
        patch = 0;
        break;
      case 'minor':
        minor++;
        patch = 0;
        break;
      case 'patch':
      default:
        patch++;
        break;
    }
    
    let newVersion = `${major}.${minor}.${patch}`;
    
    // Handle prerelease
    if (prerelease && !options.removePrerelease) {
      newVersion += `-${prerelease}`;
    }
    
    // Handle build metadata
    if (build && !options.removeBuild) {
      newVersion += `+${build}`;
    }
    
    return newVersion;
  }

  /**
   * Increment date-based version
   */
  async incrementDateVersion(currentVersion, incrementType, options = {}) {
    const match = currentVersion.match(this.versionStrategies.date.pattern);
    if (!match) {
      throw new Error(`Invalid date version format: ${currentVersion}`);
    }
    
    let [_, year, month, day, build] = match;
    year = parseInt(year);
    month = parseInt(month);
    day = parseInt(day);
    build = parseInt(build);
    
    const now = new Date();
    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth() + 1;
    const currentDay = now.getDate();
    
    // If it's a new day, increment day and reset build
    if (currentYear > year || currentMonth > month || currentDay > day) {
      year = currentYear;
      month = currentMonth;
      day = currentDay;
      build = 1;
    } else {
      build++;
    }
    
    return `${year.toString().padStart(4, '0')}.${month.toString().padStart(2, '0')}.${day.toString().padStart(2, '0')}.${build}`;
  }

  /**
   * Increment commit-based version
   */
  async incrementCommitVersion(currentVersion, incrementType, options = {}) {
    // For commit-based versioning, we typically just use the current commit hash
    // This method is called when we want to "increment" but commit hashes don't increment
    // So we return the current version or generate a new one based on current commit
    return currentVersion;
  }

  /**
   * Increment custom version
   */
  async incrementCustomVersion(currentVersion, incrementType, options = {}) {
    // For custom versioning, we need custom logic
    if (options.customIncrement) {
      return options.customIncrement(currentVersion, incrementType);
    }
    
    // Default behavior: append timestamp
    const timestamp = Date.now();
    return `${currentVersion}.${timestamp}`;
  }

  /**
   * Update version in repository
   */
  async updateVersionInRepository(repoPath, newVersion, source, file, options = {}) {
    try {
      logger.logOperation('Updating version in repository', { repoPath, newVersion, source, file });
      
      const results = {};
      
      // Update manifest files
      if (source === 'manifest') {
        const manifestFormats = await this.manifestFormatManager.detectManifestFormat(repoPath);
        for (const manifestInfo of manifestFormats) {
          const result = await this.updateManifestVersion(repoPath, manifestInfo, newVersion, options);
          results[manifestInfo.filename] = result;
        }
      }
      
      // Update version files
      if (source === 'version_file' || source === 'git') {
        const versionFiles = await this.findVersionFiles(repoPath);
        for (const versionFile of versionFiles) {
          const result = await this.updateVersionFile(repoPath, versionFile, newVersion);
          results[versionFile] = result;
        }
      }
      
      // Create Git tag if it's a Git repository
      if (await this.isGitRepository(repoPath) && options.createGitTag !== false) {
        const gitResult = await this.createGitTag(repoPath, newVersion, options);
        results.git = gitResult;
      }
      
      // Generate changelog if requested
      if (options.generateChangelog) {
        const changelogResult = await this.generateChangelog(repoPath, newVersion, options);
        results.changelog = changelogResult;
      }
      
      // Commit changes if requested
      if (options.commitChanges !== false) {
        const commitResult = await this.commitVersionChanges(repoPath, newVersion, options);
        results.commit = commitResult;
      }
      
      logger.logOperation('Version updated in repository', { repoPath, newVersion, results });
      return results;
    } catch (error) {
      logger.logError('Updating version in repository', error, { repoPath, newVersion, source, file });
      throw error;
    }
  }

  /**
   * Update version in manifest file
   */
  async updateManifestVersion(repoPath, manifestInfo, newVersion, options = {}) {
    try {
      const { filename, format } = manifestInfo;
      const filePath = path.join(repoPath, filename);
      
      let updated = false;
      
      switch (format.type) {
        case 'json':
          updated = await this.updateJsonManifest(filePath, newVersion, format);
          break;
        case 'toml':
          updated = await this.updateTomlManifest(filePath, newVersion, format);
          break;
        case 'xml':
          updated = await this.updateXmlManifest(filePath, newVersion, format);
          break;
        case 'python':
          updated = await this.updatePythonManifest(filePath, newVersion, format);
          break;
        default:
          logger.logWarning('Unsupported manifest format for version update', { filename, format: format.type });
          return { success: false, reason: 'unsupported_format' };
      }
      
      return { success: updated, file: filename, format: format.type };
    } catch (error) {
      logger.logError('Updating manifest version', error, { repoPath, filename, newVersion });
      return { success: false, error: error.message };
    }
  }

  /**
   * Update JSON manifest file
   */
  async updateJsonManifest(filePath, newVersion, format) {
    const content = await fs.readFile(filePath, 'utf8');
    const data = JSON.parse(content);
    
    // Update version using the format's version path
    if (format.versionPath) {
      const keys = format.versionPath.split('.');
      let current = data;
      
      for (let i = 0; i < keys.length - 1; i++) {
        if (!current[keys[i]]) {
          current[keys[i]] = {};
        }
        current = current[keys[i]];
      }
      
      const lastKey = keys[keys.length - 1];
      if (current[lastKey] !== newVersion) {
        current[lastKey] = newVersion;
        await fs.writeFile(filePath, JSON.stringify(data, null, 2) + '\n', 'utf8');
        return true;
      }
    }
    
    return false;
  }

  /**
   * Update TOML manifest file
   */
  async updateTomlManifest(filePath, newVersion, format) {
    // For TOML files, we'll do a simple text replacement
    // In production, you'd want to use a proper TOML parser
    const content = await fs.readFile(filePath, 'utf8');
    
    if (format.versionPath) {
      const keys = format.versionPath.split('.');
      const lastKey = keys[keys.length - 1];
      const versionRegex = new RegExp(`(${lastKey}\\s*=\\s*["'])[^"']+(["'])`, 'g');
      
      if (versionRegex.test(content)) {
        const newContent = content.replace(versionRegex, `$1${newVersion}$2`);
        await fs.writeFile(filePath, newContent, 'utf8');
        return true;
      }
    }
    
    return false;
  }

  /**
   * Update XML manifest file
   */
  async updateXmlManifest(filePath, newVersion, format) {
    // For XML files, we'll do a simple text replacement
    // In production, you'd want to use a proper XML parser
    const content = await fs.readFile(filePath, 'utf8');
    
    if (format.versionPath) {
      const keys = format.versionPath.split('.');
      const lastKey = keys[keys.length - 1];
      const versionRegex = new RegExp(`(<${lastKey}>)[^<]+(</${lastKey}>)`, 'g');
      
      if (versionRegex.test(content)) {
        const newContent = content.replace(versionRegex, `$1${newVersion}$2`);
        await fs.writeFile(filePath, newContent, 'utf8');
        return true;
      }
    }
    
    return false;
  }

  /**
   * Update Python manifest file
   */
  async updatePythonManifest(filePath, newVersion, format) {
    const content = await fs.readFile(filePath, 'utf8');
    
    if (format.versionPath) {
      const versionRegex = new RegExp(`(${format.versionPath}\\s*=\\s*["'])[^"']+(["'])`, 'g');
      
      if (versionRegex.test(content)) {
        const newContent = content.replace(versionRegex, `$1${newVersion}$2`);
        await fs.writeFile(filePath, newContent, 'utf8');
        return true;
      }
    }
    
    return false;
  }

  /**
   * Update version file
   */
  async updateVersionFile(repoPath, filename, newVersion) {
    try {
      const filePath = path.join(repoPath, filename);
      const currentContent = await fs.readFile(filePath, 'utf8');
      
      if (currentContent.trim() !== newVersion) {
        await fs.writeFile(filePath, newVersion + '\n', 'utf8');
        return { success: true, file: filename };
      }
      
      return { success: false, reason: 'version_unchanged', file: filename };
    } catch (error) {
      logger.logError('Updating version file', error, { repoPath, filename, newVersion });
      return { success: false, error: error.message, file: filename };
    }
  }

  /**
   * Create Git tag
   */
  async createGitTag(repoPath, version, options = {}) {
    try {
      const cwd = process.cwd();
      process.chdir(repoPath);
      
      // Check if tag already exists
      const existingTag = execSync(`git tag -l "v${version}"`, { encoding: 'utf8' }).trim();
      
      if (existingTag) {
        logger.logWarning('Git tag already exists', { repoPath, version });
        return { success: false, reason: 'tag_exists' };
      }
      
      // Create tag
      const tagMessage = options.tagMessage || `Release version ${version}`;
      execSync(`git tag -a "v${version}" -m "${tagMessage}"`, { stdio: 'inherit' });
      
      // Push tag if requested
      if (options.pushTag) {
        execSync('git push --tags', { stdio: 'inherit' });
      }
      
      return { success: true, tag: `v${version}` };
    } catch (error) {
      logger.logError('Creating Git tag', error, { repoPath, version });
      return { success: false, error: error.message };
    } finally {
      process.chdir(cwd);
    }
  }

  /**
   * Generate changelog
   */
  async generateChangelog(repoPath, newVersion, options = {}) {
    try {
      const changelogFile = options.changelogFile || 'CHANGELOG.md';
      const changelogPath = path.join(repoPath, changelogFile);
      
      // Get Git commits since last tag
      const commits = await this.getCommitsSinceLastTag(repoPath);
      
      // Generate changelog entry
      const changelogEntry = this.generateChangelogEntry(newVersion, commits, options);
      
      // Read existing changelog
      let existingChangelog = '';
      try {
        existingChangelog = await fs.readFile(changelogPath, 'utf8');
      } catch (error) {
        // File doesn't exist, create new one
      }
      
      // Prepend new entry
      const newChangelog = changelogEntry + '\n\n' + existingChangelog;
      
      // Write changelog
      await fs.writeFile(changelogPath, newChangelog, 'utf8');
      
      return { success: true, file: changelogFile, commits: commits.length };
    } catch (error) {
      logger.logError('Generating changelog', error, { repoPath, newVersion });
      return { success: false, error: error.message };
    }
  }

  /**
   * Get commits since last tag
   */
  async getCommitsSinceLastTag(repoPath) {
    try {
      const cwd = process.cwd();
      process.chdir(repoPath);
      
      // Get last tag
      const lastTag = execSync('git describe --tags --abbrev=0 2>/dev/null || echo ""', { encoding: 'utf8' }).trim();
      
      let commits;
      if (lastTag) {
        commits = execSync(`git log ${lastTag}..HEAD --oneline --format="%h %s"`, { encoding: 'utf8' }).trim().split('\n');
      } else {
        commits = execSync('git log --oneline --format="%h %s"', { encoding: 'utf8' }).trim().split('\n');
      }
      
      return commits.filter(commit => commit.trim());
    } catch (error) {
      logger.logWarning('Failed to get commits since last tag', { repoPath, error: error.message });
      return [];
    } finally {
      process.chdir(process.cwd());
    }
  }

  /**
   * Generate changelog entry
   */
  generateChangelogEntry(version, commits, options = {}) {
    const date = new Date().toISOString().split('T')[0];
    const title = options.changelogTitle || `## [${version}] - ${date}`;
    
    let entry = title + '\n\n';
    
    if (commits.length > 0) {
      entry += '### Changes\n';
      for (const commit of commits) {
        entry += `- ${commit}\n`;
      }
      entry += '\n';
    }
    
    if (options.changelogFooter) {
      entry += options.changelogFooter + '\n';
    }
    
    return entry;
  }

  /**
   * Commit version changes
   */
  async commitVersionChanges(repoPath, newVersion, options = {}) {
    try {
      const cwd = process.cwd();
      process.chdir(repoPath);
      
      // Check if there are changes to commit
      const status = execSync('git status --porcelain', { encoding: 'utf8' }).trim();
      
      if (!status) {
        logger.logInfo('No changes to commit', { repoPath });
        return { success: true, reason: 'no_changes' };
      }
      
      // Add all changes
      execSync('git add .', { stdio: 'inherit' });
      
      // Commit changes
      const commitMessage = options.commitMessage || `chore: bump version to ${newVersion}`;
      execSync(`git commit -m "${commitMessage}"`, { stdio: 'inherit' });
      
      // Push changes if requested
      if (options.pushChanges) {
        execSync('git push', { stdio: 'inherit' });
      }
      
      return { success: true, commitMessage };
    } catch (error) {
      logger.logError('Committing version changes', error, { repoPath, newVersion });
      return { success: false, error: error.message };
    } finally {
      process.chdir(cwd);
    }
  }

  /**
   * Execute push.sh-like functionality
   */
  async executePushScript(repoPath, options = {}) {
    try {
      logger.logOperation('Executing push script functionality', { repoPath, options });
      
      // Detect version strategy
      const strategyInfo = await this.detectVersionStrategy(repoPath);
      
      // Get current version
      const currentVersionInfo = await this.getCurrentVersion(repoPath);
      if (!currentVersionInfo) {
        throw new Error('No current version found');
      }
      
      // Increment version
      const incrementResult = await this.incrementVersion(repoPath, options.incrementType || 'patch', options);
      
      // Execute pre-push hooks if configured
      if (options.prePushHooks) {
        await this.executePrePushHooks(repoPath, incrementResult, options);
      }
      
      // Execute post-push hooks if configured
      if (options.postPushHooks) {
        await this.executePostPushHooks(repoPath, incrementResult, options);
      }
      
      logger.logOperation('Push script functionality completed', { repoPath, incrementResult });
      
      return incrementResult;
    } catch (error) {
      logger.logError('Executing push script functionality', error, { repoPath, options });
      throw error;
    }
  }

  /**
   * Execute pre-push hooks
   */
  async executePrePushHooks(repoPath, incrementResult, options) {
    try {
      const hooks = options.prePushHooks || [];
      
      for (const hook of hooks) {
        logger.logOperation('Executing pre-push hook', { repoPath, hook });
        
        if (typeof hook === 'function') {
          await hook(repoPath, incrementResult, options);
        } else if (typeof hook === 'string') {
          // Execute shell command
          const cwd = process.cwd();
          process.chdir(repoPath);
          execSync(hook, { stdio: 'inherit' });
          process.chdir(cwd);
        }
      }
    } catch (error) {
      logger.logError('Executing pre-push hooks', error, { repoPath, incrementResult });
      throw error;
    }
  }

  /**
   * Execute post-push hooks
   */
  async executePostPushHooks(repoPath, incrementResult, options) {
    try {
      const hooks = options.postPushHooks || [];
      
      for (const hook of hooks) {
        logger.logOperation('Executing post-push hook', { repoPath, hook });
        
        if (typeof hook === 'function') {
          await hook(repoPath, incrementResult, options);
        } else if (typeof hook === 'string') {
          // Execute shell command
          const cwd = process.cwd();
          process.chdir(repoPath);
          execSync(hook, { stdio: 'inherit' });
          process.chdir(cwd);
        }
      }
    } catch (error) {
      logger.logError('Executing post-push hooks', error, { repoPath, incrementResult });
      throw error;
    }
  }
}

module.exports = { EnhancedVersionManager };
