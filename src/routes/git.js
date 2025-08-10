const express = require('express');
const { execSync } = require('child_process');
const { logger } = require('../utils/logger');

const router = express.Router();

/**
 * @route GET /api/v1/git/:repoPath/status
 * @desc Get git status for a repository
 * @access Public
 */
router.get('/:repoPath(*)/status', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting git status', { repoPath });

    const status = execSync('git status --porcelain', { cwd: repoPath, encoding: 'utf8' });
    const branch = execSync('git branch --show-current', { cwd: repoPath, encoding: 'utf8' }).trim();
    const lastCommit = execSync('git log -1 --oneline', { cwd: repoPath, encoding: 'utf8' }).trim();

    logger.logPerformance('Getting git status', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      status: {
        branch: branch,
        lastCommit: lastCommit,
        changes: status ? status.split('\n').filter(line => line.trim()) : []
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/git/:repoPath/tags
 * @desc Get git tags for a repository
 * @access Public
 */
router.get('/:repoPath(*)/tags', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting git tags', { repoPath });

    const tags = execSync('git tag --sort=-version:refname', { cwd: repoPath, encoding: 'utf8' })
      .split('\n')
      .filter(tag => tag.trim());

    logger.logPerformance('Getting git tags', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      tags: tags,
      count: tags.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
