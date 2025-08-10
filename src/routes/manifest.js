const express = require('express');
const { ManifestFormatManager } = require('../services/manifestFormatManager');
const { CICDIntegrationService } = require('../services/cicdIntegrationService');
const { InstallScriptGenerator } = require('../services/installScriptGenerator');
const { EnhancedVersionManager } = require('../services/enhancedVersionManager');
const { logger } = require('../utils/logger');

const router = express.Router();
const manifestFormatManager = new ManifestFormatManager();
const cicdIntegrationService = new CICDIntegrationService();
const installScriptGenerator = new InstallScriptGenerator();
const enhancedVersionManager = new EnhancedVersionManager();

/**
 * @route GET /api/v1/manifest/:repoPath/analyze
 * @desc Analyze repository and detect manifest formats
 * @access Public
 */
router.get('/:repoPath(*)/analyze', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Analyzing repository manifest', { repoPath });

    const manifestInfo = await manifestFormatManager.detectManifestFormat(repoPath);
    const metadata = await manifestFormatManager.extractMetadata(repoPath, manifestInfo);
    const cicdPlatform = await cicdIntegrationService.detectCICDPlatform(repoPath);

    logger.logPerformance('Analyzing repository manifest', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      manifest: {
        format: manifestInfo,
        metadata: metadata,
        cicdPlatform: cicdPlatform
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/manifest/:repoPath/version/bump
 * @desc Enhanced version bumping with push script integration
 * @access Public
 */
router.post('/:repoPath(*)/version/bump', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { incrementType = 'patch', options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Enhanced version bumping', { repoPath, incrementType });

    const incrementResult = await enhancedVersionManager.incrementVersion(repoPath, incrementType, options);
    const updateResult = await enhancedVersionManager.updateVersionInRepository(repoPath, incrementResult.newVersion, 'enhanced', null, options);
    
    // Execute push script functionality
    const pushResult = await enhancedVersionManager.executePushScript(repoPath, options);

    logger.logPerformance('Enhanced version bumping', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      result: {
        increment: incrementResult,
        update: updateResult,
        push: pushResult
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/manifest/:repoPath/version/strategy
 * @desc Detect and configure version strategy
 * @access Public
 */
router.post('/:repoPath(*)/version/strategy', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { strategy, options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Configuring version strategy', { repoPath, strategy });

    const detectedStrategy = await enhancedVersionManager.detectVersionStrategy(repoPath);
    const versionFiles = await enhancedVersionManager.findVersionFiles(repoPath);
    const cicdConfig = await enhancedVersionManager.detectCICDConfig(repoPath);

    logger.logPerformance('Configuring version strategy', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      strategy: {
        detected: detectedStrategy,
        configured: strategy,
        versionFiles: versionFiles,
        cicdConfig: cicdConfig
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/manifest/:repoPath/cicd/generate
 * @desc Generate CI/CD configuration for detected platform
 * @access Public
 */
router.post('/:repoPath(*)/cicd/generate', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { platform, options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Generating CI/CD config', { repoPath, platform });

    const detectedPlatform = platform || await cicdIntegrationService.detectCICDPlatform(repoPath);
    const config = await cicdIntegrationService.generateCICDConfig(repoPath, detectedPlatform, options);

    logger.logPerformance('Generating CI/CD config', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      cicd: {
        platform: detectedPlatform,
        config: config
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/manifest/:repoPath/cicd/webhook
 * @desc Process CI/CD webhook events
 * @access Public
 */
router.post('/:repoPath(*)/cicd/webhook', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { platform, eventType, payload } = req.body;
    const startTime = Date.now();

    logger.logOperation('Processing CI/CD webhook', { repoPath, platform, eventType });

    const result = await cicdIntegrationService.processWebhookEvent(platform, eventType, payload);

    logger.logPerformance('Processing CI/CD webhook', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      webhook: {
        platform: platform,
        eventType: eventType,
        result: result
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/manifest/:repoPath/install/generate
 * @desc Generate installation scripts for Manifest
 * @access Public
 */
router.post('/:repoPath(*)/install/generate', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { platform, containerType, options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Generating install scripts', { repoPath, platform, containerType });

    const detectedPlatform = platform || await installScriptGenerator.detectPlatform();
    const script = await installScriptGenerator.generateInstallScript(detectedPlatform, containerType, options);

    logger.logPerformance('Generating install scripts', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      install: {
        platform: detectedPlatform,
        containerType: containerType,
        script: script
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/manifest/:repoPath/install/all
 * @desc Generate all installation scripts for all platforms
 * @access Public
 */
router.post('/:repoPath(*)/install/all', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Generating all install scripts', { repoPath });

    const detectedPlatform = await installScriptGenerator.detectPlatform();
    const allScripts = await installScriptGenerator.generateAllScripts(detectedPlatform, options);

    logger.logPerformance('Generating all install scripts', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      install: {
        platform: detectedPlatform,
        scripts: allScripts
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/manifest/:repoPath/health
 * @desc Get comprehensive health status for repository
 * @access Public
 */
router.get('/:repoPath(*)/health', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository health status', { repoPath });

    // Get manifest health
    const manifestInfo = await manifestFormatManager.detectManifestFormat(repoPath);
    const metadata = await manifestFormatManager.extractMetadata(repoPath, manifestInfo);
    
    // Get version health
    const currentVersion = await enhancedVersionManager.getCurrentVersion(repoPath);
    const versionStrategy = await enhancedVersionManager.detectVersionStrategy(repoPath);
    
    // Get CI/CD health
    const cicdPlatform = await cicdIntegrationService.detectCICDPlatform(repoPath);
    
    // Get installation health
    const platform = await installScriptGenerator.detectPlatform();

    const healthScore = this.calculateHealthScore(manifestInfo, metadata, currentVersion, versionStrategy, cicdPlatform);

    logger.logPerformance('Getting repository health status', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      health: {
        score: healthScore,
        manifest: {
          format: manifestInfo,
          metadata: metadata,
          status: manifestInfo ? 'healthy' : 'unhealthy'
        },
        version: {
          current: currentVersion,
          strategy: versionStrategy,
          status: currentVersion ? 'healthy' : 'unhealthy'
        },
        cicd: {
          platform: cicdPlatform,
          status: cicdPlatform ? 'healthy' : 'unhealthy'
        },
        install: {
          platform: platform,
          status: 'healthy'
        },
        recommendations: this.generateHealthRecommendations(manifestInfo, metadata, currentVersion, versionStrategy, cicdPlatform)
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Calculate overall health score
 */
calculateHealthScore(manifestInfo, metadata, currentVersion, versionStrategy, cicdPlatform) {
  let score = 100;
  
  if (!manifestInfo) score -= 30;
  if (!metadata) score -= 20;
  if (!currentVersion) score -= 25;
  if (!versionStrategy) score -= 15;
  if (!cicdPlatform) score -= 10;
  
  return Math.max(0, Math.min(100, score));
}

/**
 * Generate health recommendations
 */
generateHealthRecommendations(manifestInfo, metadata, currentVersion, versionStrategy, cicdPlatform) {
  const recommendations = [];
  
  if (!manifestInfo) {
    recommendations.push('No manifest file detected. Consider adding a package.json, pyproject.toml, or other manifest file.');
  }
  
  if (!metadata) {
    recommendations.push('Unable to extract metadata from manifest. Check manifest file format and content.');
  }
  
  if (!currentVersion) {
    recommendations.push('No version information found. Consider adding version to manifest or creating a VERSION file.');
  }
  
  if (!versionStrategy) {
    recommendations.push('No version strategy detected. Consider implementing semantic versioning or other versioning strategy.');
  }
  
  if (!cicdPlatform) {
    recommendations.push('No CI/CD configuration detected. Consider setting up GitHub Actions, GitLab CI, or other CI/CD platform.');
  }
  
  return recommendations;
}

module.exports = router;
