const express = require('express');
const GitHubService = require('../services/githubService');
const { gitOperationRateLimiter } = require('../middleware/rateLimiter');
const { logger } = require('../utils/logger');

const router = express.Router();
const githubService = new GitHubService();

/**
 * @route GET /api/v1/github/auth/status
 * @desc Check GitHub authentication status
 * @access Public
 */
router.get('/auth/status', async (req, res, next) => {
  try {
    const startTime = Date.now();

    logger.logOperation('Checking GitHub auth status');

    const authStatus = await githubService.checkAuth();

    logger.logPerformance('Checking GitHub auth status', Date.now() - startTime);

    res.json({
      success: true,
      auth: authStatus,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/github/auth/login
 * @desc Authenticate with GitHub
 * @access Public
 */
router.post('/auth/login', gitOperationRateLimiter, async (req, res, next) => {
  try {
    const { token } = req.body;
    const startTime = Date.now();

    logger.logOperation('GitHub authentication');

    const result = await githubService.authenticate(token);

    logger.logPerformance('GitHub authentication', Date.now() - startTime);

    res.json({
      success: true,
      result: result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/github/repos/:owner/:repo
 * @desc Get repository information
 * @access Public
 */
router.get('/repos/:owner/:repo', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository info', { owner, repo });

    const repoInfo = await githubService.getRepositoryInfo(owner, repo);

    logger.logPerformance('Getting repository info', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: repoInfo,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/github/repos/:owner/:repo/releases
 * @desc Get repository releases
 * @access Public
 */
router.get('/repos/:owner/:repo/releases', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository releases', { owner, repo });

    const releases = await githubService.getReleases(owner, repo);

    logger.logPerformance('Getting repository releases', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      releases: releases,
      count: releases.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/github/repos/:owner/:repo/releases
 * @desc Create a new release
 * @access Public
 */
router.post('/repos/:owner/:repo/releases', gitOperationRateLimiter, async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const { tagName, name, body, draft = false, prerelease = false } = req.body;
    const startTime = Date.now();

    logger.logOperation('Creating release', { owner, repo, tagName, name });

    const release = await githubService.createRelease(owner, repo, tagName, name, body, draft, prerelease);

    logger.logPerformance('Creating release', Date.now() - startTime, { owner, repo, tagName });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      release: release,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/github/repos/:owner/:repo/tags
 * @desc Create a new tag
 * @access Public
 */
router.post('/repos/:owner/:repo/tags', gitOperationRateLimiter, async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const { tagName, message, repoPath } = req.body;
    const startTime = Date.now();

    logger.logOperation('Creating tag', { owner, repo, tagName, repoPath });

    if (!repoPath) {
      return res.status(400).json({
        success: false,
        error: 'repoPath is required for tag creation'
      });
    }

    const result = await githubService.createTag(repoPath, tagName, message);

    logger.logPerformance('Creating tag', Date.now() - startTime, { owner, repo, tagName });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      result: result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/github/repos/:owner/:repo/topics
 * @desc Get repository topics
 * @access Public
 */
router.get('/repos/:owner/:repo/topics', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository topics', { owner, repo });

    const topics = await githubService.getTopics(owner, repo);

    logger.logPerformance('Getting repository topics', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      topics: topics,
      count: topics.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route PUT /api/v1/github/repos/:owner/:repo/topics
 * @desc Update repository topics
 * @access Public
 */
router.put('/repos/:owner/:repo/topics', gitOperationRateLimiter, async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const { topics } = req.body;
    const startTime = Date.now();

    logger.logOperation('Updating repository topics', { owner, repo, topics });

    const updatedTopics = await githubService.updateTopics(owner, repo, topics);

    logger.logPerformance('Updating repository topics', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      topics: updatedTopics,
      count: updatedTopics.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/github/repos/:owner/:repo/dependencies
 * @desc Get repository dependencies
 * @access Public
 */
router.get('/repos/:owner/:repo/dependencies', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository dependencies', { owner, repo });

    const dependencies = await githubService.getDependencies(owner, repo);

    logger.logPerformance('Getting repository dependencies', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      dependencies: dependencies,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/github/repos/:owner/:repo/security
 * @desc Get repository security alerts
 * @access Public
 */
router.get('/repos/:owner/:repo/security', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository security alerts', { owner, repo });

    const securityAlerts = await githubService.getSecurityAlerts(owner, repo);

    logger.logPerformance('Getting repository security alerts', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      security: securityAlerts,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/github/repos/:owner/:repo/security/enable
 * @desc Enable security alerts
 * @access Public
 */
router.post('/repos/:owner/:repo/security/enable', gitOperationRateLimiter, async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Enabling security alerts', { owner, repo });

    const result = await githubService.enableSecurityAlerts(owner, repo);

    logger.logPerformance('Enabling security alerts', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      result: result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/github/repos/:owner/:repo/workflows
 * @desc Get repository workflows
 * @access Public
 */
router.get('/repos/:owner/:repo/workflows', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository workflows', { owner, repo });

    const workflows = await githubService.getWorkflows(owner, repo);

    logger.logPerformance('Getting repository workflows', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      workflows: workflows,
      count: workflows.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/github/repos/:owner/:repo/workflows/:workflowId/trigger
 * @desc Trigger a workflow
 * @access Public
 */
router.post('/repos/:owner/:repo/workflows/:workflowId/trigger', gitOperationRateLimiter, async (req, res, next) => {
  try {
    const { owner, repo, workflowId } = req.params;
    const { ref = 'main', inputs = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Triggering workflow', { owner, repo, workflowId, ref, inputs });

    const result = await githubService.triggerWorkflow(owner, repo, workflowId, ref, inputs);

    logger.logPerformance('Triggering workflow', Date.now() - startTime, { owner, repo, workflowId });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      workflowId: workflowId,
      result: result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/github/repos/:owner/:repo/stats
 * @desc Get repository statistics
 * @access Public
 */
router.get('/repos/:owner/:repo/stats', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting repository statistics', { owner, repo });

    const stats = await githubService.getStats(owner, repo);

    logger.logPerformance('Getting repository statistics', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      stats: stats,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/github/repos/:owner/:repo/analyze
 * @desc Comprehensive repository analysis
 * @access Public
 */
router.post('/repos/:owner/:repo/analyze', async (req, res, next) => {
  try {
    const { owner, repo } = req.params;
    const startTime = Date.now();

    logger.logOperation('Analyzing repository', { owner, repo });

    // Get comprehensive repository information
    const [
      repoInfo,
      releases,
      topics,
      dependencies,
      securityAlerts,
      workflows,
      stats
    ] = await Promise.all([
      githubService.getRepositoryInfo(owner, repo),
      githubService.getReleases(owner, repo),
      githubService.getTopics(owner, repo),
      githubService.getDependencies(owner, repo),
      githubService.getSecurityAlerts(owner, repo),
      githubService.getWorkflows(owner, repo),
      githubService.getStats(owner, repo)
    ]);

    const analysis = {
      repository: repoInfo,
      releases: {
        count: releases.length,
        latest: releases[0] || null,
        recent: releases.slice(0, 5)
      },
      topics: topics,
      dependencies: dependencies,
      security: {
        alerts: securityAlerts,
        hasVulnerabilities: securityAlerts && securityAlerts.length > 0
      },
      workflows: {
        count: workflows.length,
        active: workflows.filter(w => w.state === 'active').length
      },
      statistics: stats,
      health: {
        score: this.calculateHealthScore(repoInfo, releases, securityAlerts, workflows),
        recommendations: this.generateRecommendations(repoInfo, releases, securityAlerts, workflows)
      }
    };

    logger.logPerformance('Analyzing repository', Date.now() - startTime, { owner, repo });

    res.json({
      success: true,
      repository: `${owner}/${repo}`,
      analysis: analysis,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Calculate repository health score
 */
calculateHealthScore(repoInfo, releases, securityAlerts, workflows) {
  let score = 100;
  
  // Deduct points for missing elements
  if (!repoInfo.description) score -= 10;
  if (!repoInfo.topics || repoInfo.topics.length === 0) score -= 5;
  if (releases.length === 0) score -= 15;
  if (securityAlerts && securityAlerts.length > 0) score -= 20;
  if (workflows.length === 0) score -= 10;
  
  // Add points for good practices
  if (repoInfo.stargazers_count > 10) score += 5;
  if (repoInfo.forks_count > 5) score += 5;
  if (workflows.filter(w => w.state === 'active').length > 0) score += 10;
  
  return Math.max(0, Math.min(100, score));
}

/**
 * Generate repository recommendations
 */
generateRecommendations(repoInfo, releases, securityAlerts, workflows) {
  const recommendations = [];
  
  if (!repoInfo.description) {
    recommendations.push('Add a repository description to improve discoverability');
  }
  
  if (!repoInfo.topics || repoInfo.topics.length === 0) {
    recommendations.push('Add repository topics to improve categorization');
  }
  
  if (releases.length === 0) {
    recommendations.push('Create releases to track version history');
  }
  
  if (securityAlerts && securityAlerts.length > 0) {
    recommendations.push('Address security vulnerabilities promptly');
  }
  
  if (workflows.length === 0) {
    recommendations.push('Set up GitHub Actions workflows for CI/CD');
  }
  
  if (repoInfo.open_issues_count > 10) {
    recommendations.push('Consider addressing open issues to maintain project health');
  }
  
  return recommendations;
}

module.exports = router;
