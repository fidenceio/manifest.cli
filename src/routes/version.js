const express = require('express');
const VersionManager = require('../services/versionManager');
const { versionUpdateRateLimiter } = require('../middleware/rateLimiter');
const { logger } = require('../utils/logger');
const path = require('path');

const router = express.Router();
const versionManager = new VersionManager();

/**
 * @route GET /api/v1/version/:repoPath
 * @desc Get current version of a repository
 * @access Public
 */
router.get('/:repoPath(*)', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting version', { repoPath });

    const version = await versionManager.getCurrentVersion(repoPath);
    const versionInfo = versionManager.getVersionInfo(version);

    logger.logPerformance('Getting version', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      version: version,
      versionInfo: versionInfo,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/version/:repoPath/calculate
 * @desc Calculate next version based on type
 * @access Public
 */
router.post('/:repoPath(*)/calculate', versionUpdateRateLimiter, async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { type = 'patch' } = req.body;
    const startTime = Date.now();

    logger.logOperation('Calculating next version', { repoPath, type });

    const currentVersion = await versionManager.getCurrentVersion(repoPath);
    const nextVersion = versionManager.calculateNextVersion(currentVersion, type);

    logger.logPerformance('Calculating next version', Date.now() - startTime, { repoPath, type });

    res.json({
      success: true,
      repository: repoPath,
      currentVersion: currentVersion,
      nextVersion: nextVersion,
      type: type,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/version/:repoPath/update
 * @desc Update version in repository
 * @access Public
 */
router.post('/:repoPath(*)/update', versionUpdateRateLimiter, async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { version, type = 'patch', updateType = 'auto' } = req.body;
    const startTime = Date.now();

    logger.logOperation('Updating version', { repoPath, version, type, updateType });

    let newVersion = version;
    
    if (!newVersion) {
      const currentVersion = await versionManager.getCurrentVersion(repoPath);
      newVersion = versionManager.calculateNextVersion(currentVersion, type);
    }

    const result = await versionManager.updateVersion(repoPath, newVersion, updateType);

    logger.logPerformance('Updating version', Date.now() - startTime, { repoPath, newVersion });

    res.json({
      success: true,
      repository: repoPath,
      result: result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/version/:repoPath/bump
 * @desc Bump version automatically
 * @access Public
 */
router.post('/:repoPath(*)/bump', versionUpdateRateLimiter, async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { type = 'patch', changes = [], metadata = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Bumping version', { repoPath, type, changes });

    const currentVersion = await versionManager.getCurrentVersion(repoPath);
    const nextVersion = versionManager.calculateNextVersion(currentVersion, type);
    
    const updateResult = await versionManager.updateVersion(repoPath, nextVersion, type);
    
    // Update documentation if metadata is provided
    let docResult = null;
    if (Object.keys(metadata).length > 0) {
      const DocumentationManager = require('../services/documentationManager');
      const docManager = new DocumentationManager();
      docResult = await docManager.updateAllDocumentation(repoPath, {
        ...metadata,
        version: nextVersion,
        versionType: type,
        changes: changes
      });
    }

    logger.logPerformance('Bumping version', Date.now() - startTime, { repoPath, type });

    res.json({
      success: true,
      repository: repoPath,
      previousVersion: currentVersion,
      newVersion: nextVersion,
      type: type,
      updateResult: updateResult,
      documentationResult: docResult,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/version/:repoPath/check-bump
 * @desc Check if version bump is needed
 * @access Public
 */
router.post('/:repoPath(*)/check-bump', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { dependencyUpdates = [] } = req.body;
    const startTime = Date.now();

    logger.logOperation('Checking version bump', { repoPath, dependencyUpdates });

    const result = await versionManager.checkVersionBumpNeeded(repoPath, dependencyUpdates);

    logger.logPerformance('Checking version bump', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      result: result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/version/:repoPath/validate
 * @desc Validate version format
 * @access Public
 */
router.post('/:repoPath(*)/validate', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { version } = req.body;
    const startTime = Date.now();

    logger.logOperation('Validating version', { repoPath, version });

    const isValid = versionManager.validateVersion(version);
    const versionInfo = isValid ? versionManager.getVersionInfo(version) : null;

    logger.logPerformance('Validating version', Date.now() - startTime, { repoPath, version });

    res.json({
      success: true,
      repository: repoPath,
      version: version,
      isValid: isValid,
      versionInfo: versionInfo,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/version/:repoPath/compare
 * @desc Compare two versions
 * @access Public
 */
router.post('/:repoPath(*)/compare', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { version1, version2 } = req.body;
    const startTime = Date.now();

    logger.logOperation('Comparing versions', { repoPath, version1, version2 });

    const comparison = versionManager.compareVersions(version1, version2);
    const version1Info = versionManager.getVersionInfo(version1);
    const version2Info = versionManager.getVersionInfo(version2);

    logger.logPerformance('Comparing versions', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      version1: {
        version: version1,
        info: version1Info
      },
      version2: {
        version: version2,
        info: version2Info
      },
      comparison: comparison,
      result: comparison > 0 ? 'version1 is greater' : 
              comparison < 0 ? 'version2 is greater' : 'versions are equal',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/version/:repoPath/info
 * @desc Get detailed version information
 * @access Public
 */
router.get('/:repoPath(*)/info', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting version info', { repoPath });

    const currentVersion = await versionManager.getCurrentVersion(repoPath);
    const versionInfo = versionManager.getVersionInfo(currentVersion);
    
    // Get available version files
    const versionFiles = [];
    for (const file of versionManager.versionFiles) {
      try {
        await require('fs').promises.access(path.join(repoPath, file));
        versionFiles.push(file);
      } catch (error) {
        // File doesn't exist
      }
    }

    logger.logPerformance('Getting version info', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      currentVersion: currentVersion,
      versionInfo: versionInfo,
      versionFiles: versionFiles,
      supportedFiles: versionManager.versionFiles,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
