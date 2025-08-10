const semver = require('semver');
const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');
const { logger } = require('../utils/logger');

const execAsync = promisify(exec);

class VersionManager {
  constructor() {
    this.versionFiles = [
      'VERSION',
      'package.json',
      'pyproject.toml',
      'setup.py',
      'requirements.txt',
      'Cargo.toml',
      'go.mod',
      'composer.json',
      'Gemfile',
      'pom.xml'
    ];
  }

  /**
   * Get current version from repository
   */
  async getCurrentVersion(repoPath) {
    try {
      logger.logOperation('Getting current version', { repoPath });
      
      // Check for VERSION file first
      const versionFilePath = path.join(repoPath, 'VERSION');
      try {
        const versionContent = await fs.readFile(versionFilePath, 'utf8');
        const version = versionContent.trim();
        if (semver.valid(version)) {
          return version;
        }
      } catch (error) {
        // VERSION file doesn't exist or can't be read
      }

      // Check package.json
      const packageJsonPath = path.join(repoPath, 'package.json');
      try {
        const packageJson = await fs.readFile(packageJsonPath, 'utf8');
        const packageData = JSON.parse(packageJson);
        if (packageData.version && semver.valid(packageData.version)) {
          return packageData.version;
        }
      } catch (error) {
        // package.json doesn't exist or can't be parsed
      }

      // Check pyproject.toml
      const pyprojectPath = path.join(repoPath, 'pyproject.toml');
      try {
        const pyprojectContent = await fs.readFile(pyprojectPath, 'utf8');
        const versionMatch = pyprojectContent.match(/version\s*=\s*["']([^"']+)["']/);
        if (versionMatch && semver.valid(versionMatch[1])) {
          return versionMatch[1];
        }
      } catch (error) {
        // pyproject.toml doesn't exist or can't be read
      }

      // Check setup.py
      const setupPyPath = path.join(repoPath, 'setup.py');
      try {
        const setupPyContent = await fs.readFile(setupPyPath, 'utf8');
        const versionMatch = setupPyContent.match(/version\s*=\s*["']([^"']+)["']/);
        if (versionMatch && semver.valid(versionMatch[1])) {
          return versionMatch[1];
        }
      } catch (error) {
        // setup.py doesn't exist or can't be read
      }

      throw new Error('No valid version found in repository');
    } catch (error) {
      logger.logError('Getting current version', error, { repoPath });
      throw error;
    }
  }

  /**
   * Calculate next version based on type
   */
  calculateNextVersion(currentVersion, type) {
    try {
      if (!semver.valid(currentVersion)) {
        throw new Error(`Invalid current version: ${currentVersion}`);
      }

      let nextVersion;
      switch (type) {
        case 'major':
          nextVersion = semver.inc(currentVersion, 'major');
          break;
        case 'minor':
          nextVersion = semver.inc(currentVersion, 'minor');
          break;
        case 'patch':
        case 'revision':
          nextVersion = semver.inc(currentVersion, 'patch');
          break;
        case 'premajor':
          nextVersion = semver.inc(currentVersion, 'premajor');
          break;
        case 'preminor':
          nextVersion = semver.inc(currentVersion, 'preminor');
          break;
        case 'prepatch':
          nextVersion = semver.inc(currentVersion, 'prepatch');
          break;
        case 'prerelease':
          nextVersion = semver.inc(currentVersion, 'prerelease');
          break;
        default:
          throw new Error(`Invalid version type: ${type}`);
      }

      logger.logOperation('Calculated next version', {
        currentVersion,
        type,
        nextVersion
      });

      return nextVersion;
    } catch (error) {
      logger.logError('Calculating next version', error, {
        currentVersion,
        type
      });
      throw error;
    }
  }

  /**
   * Update version in all relevant files
   */
  async updateVersion(repoPath, newVersion, updateType) {
    try {
      logger.logOperation('Updating version', {
        repoPath,
        newVersion,
        updateType
      });

      const updates = [];

      // Update VERSION file
      const versionFilePath = path.join(repoPath, 'VERSION');
      try {
        await fs.writeFile(versionFilePath, newVersion + '\n');
        updates.push('VERSION');
      } catch (error) {
        logger.warn('Could not update VERSION file', { error: error.message });
      }

      // Update package.json
      const packageJsonPath = path.join(repoPath, 'package.json');
      try {
        const packageJson = await fs.readFile(packageJsonPath, 'utf8');
        const packageData = JSON.parse(packageJson);
        if (packageData.version) {
          packageData.version = newVersion;
          await fs.writeFile(packageJsonPath, JSON.stringify(packageData, null, 2) + '\n');
          updates.push('package.json');
        }
      } catch (error) {
        logger.warn('Could not update package.json', { error: error.message });
      }

      // Update pyproject.toml
      const pyprojectPath = path.join(repoPath, 'pyproject.toml');
      try {
        const pyprojectContent = await fs.readFile(pyprojectPath, 'utf8');
        const updatedContent = pyprojectContent.replace(
          /version\s*=\s*["'][^"']+["']/,
          `version = "${newVersion}"`
        );
        await fs.writeFile(pyprojectPath, updatedContent);
        updates.push('pyproject.toml');
      } catch (error) {
        logger.warn('Could not update pyproject.toml', { error: error.message });
      }

      // Update setup.py
      const setupPyPath = path.join(repoPath, 'setup.py');
      try {
        const setupPyContent = await fs.readFile(setupPyPath, 'utf8');
        const updatedContent = setupPyContent.replace(
          /version\s*=\s*["'][^"']+["']/,
          `version = "${newVersion}"`
        );
        await fs.writeFile(setupPyPath, updatedContent);
        updates.push('setup.py');
      } catch (error) {
        logger.warn('Could not update setup.py', { error: error.message });
      }

      // Update requirements.txt if it contains version references
      const requirementsPath = path.join(repoPath, 'requirements.txt');
      try {
        const requirementsContent = await fs.readFile(requirementsPath, 'utf8');
        // This is a simplified approach - in practice you might want more sophisticated parsing
        if (requirementsContent.includes('==')) {
          logger.info('requirements.txt contains version pins - manual review recommended');
        }
      } catch (error) {
        // requirements.txt doesn't exist
      }

      logger.logOperation('Version update completed', {
        repoPath,
        newVersion,
        updatedFiles: updates
      });

      return {
        success: true,
        newVersion,
        updatedFiles: updates,
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      logger.logError('Updating version', error, {
        repoPath,
        newVersion,
        updateType
      });
      throw error;
    }
  }

  /**
   * Validate version format
   */
  validateVersion(version) {
    return semver.valid(version) !== null;
  }

  /**
   * Compare two versions
   */
  compareVersions(version1, version2) {
    try {
      return semver.compare(version1, version2);
    } catch (error) {
      logger.logError('Comparing versions', error, { version1, version2 });
      throw error;
    }
  }

  /**
   * Get version information
   */
  getVersionInfo(version) {
    try {
      if (!semver.valid(version)) {
        throw new Error(`Invalid version: ${version}`);
      }

      const parsed = semver.parse(version);
      return {
        major: parsed.major,
        minor: parsed.minor,
        patch: parsed.patch,
        prerelease: parsed.prerelease,
        build: parsed.build,
        format: parsed.format(),
        isPrerelease: parsed.prerelease.length > 0,
        isStable: parsed.prerelease.length === 0
      };
    } catch (error) {
      logger.logError('Getting version info', error, { version });
      throw error;
    }
  }

  /**
   * Check if version bump is needed
   */
  async checkVersionBumpNeeded(repoPath, dependencyUpdates = []) {
    try {
      const currentVersion = await this.getCurrentVersion(repoPath);
      const versionInfo = this.getVersionInfo(currentVersion);

      // Check if there are breaking changes
      const hasBreakingChanges = dependencyUpdates.some(update => 
        update.type === 'major' || update.breaking
      );

      // Check if there are new features
      const hasNewFeatures = dependencyUpdates.some(update => 
        update.type === 'minor' || update.feature
      );

      let recommendedBump = 'patch';
      if (hasBreakingChanges) {
        recommendedBump = 'major';
      } else if (hasNewFeatures) {
        recommendedBump = 'minor';
      }

      return {
        currentVersion,
        recommendedBump,
        hasBreakingChanges,
        hasNewFeatures,
        dependencyUpdates,
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      logger.logError('Checking version bump', error, { repoPath });
      throw error;
    }
  }
}

module.exports = VersionManager;
