const express = require('express');
const DocumentationManager = require('../services/documentationManager');
const { logger } = require('../utils/logger');

const router = express.Router();
const documentationManager = new DocumentationManager();

/**
 * @route GET /api/v1/documentation/:repoPath
 * @desc Get documentation for a repository
 * @access Public
 */
router.get('/:repoPath(*)', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting documentation', { repoPath });

    const documentation = await documentationManager.getAllDocumentation(repoPath);

    logger.logPerformance('Getting documentation', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      documentation: documentation,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/documentation/:repoPath/update
 * @desc Update documentation for a repository
 * @access Public
 */
router.post('/:repoPath(*)/update', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { metadata, options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Updating documentation', { repoPath, metadata });

    const result = await documentationManager.updateAllDocumentation(repoPath, metadata, options);

    logger.logPerformance('Updating documentation', Date.now() - startTime, { repoPath });

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
 * @route GET /api/v1/documentation/:repoPath/status
 * @desc Get documentation status for a repository
 * @access Public
 */
router.get('/:repoPath(*)/status', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting documentation status', { repoPath });

    const status = await documentationManager.getDocumentationStatus(repoPath);

    logger.logPerformance('Getting documentation status', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      status: status,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
