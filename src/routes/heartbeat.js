const express = require('express');
const { HeartbeatService } = require('../services/heartbeatService');
const { logger } = require('../utils/logger');

const router = express.Router();
const heartbeatService = new HeartbeatService();

/**
 * @route POST /api/v1/heartbeat/:repoPath/start
 * @desc Start heartbeat monitoring for a repository
 * @access Public
 */
router.post('/:repoPath(*)/start', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { interval, notifications, options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Starting heartbeat monitoring', { repoPath, interval, notifications });

    const result = await heartbeatService.startHeartbeat(repoPath, {
      interval,
      notifications,
      ...options
    });

    logger.logPerformance('Starting heartbeat monitoring', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/heartbeat/:repoPath/stop
 * @desc Stop heartbeat monitoring for a repository
 * @access Public
 */
router.post('/:repoPath(*)/stop', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Stopping heartbeat monitoring', { repoPath });

    const result = await heartbeatService.stopHeartbeat(repoPath);

    logger.logPerformance('Stopping heartbeat monitoring', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/heartbeat/:repoPath/status
 * @desc Get heartbeat status for a repository
 * @access Public
 */
router.get('/:repoPath(*)/status', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting heartbeat status', { repoPath });

    const status = heartbeatService.getHeartbeatStatus(repoPath);

    logger.logPerformance('Getting heartbeat status', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      status,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/heartbeat/all/status
 * @desc Get status of all heartbeats
 * @access Public
 */
router.get('/all/status', async (req, res, next) => {
  try {
    const startTime = Date.now();

    logger.logOperation('Getting all heartbeat statuses');

    const statuses = heartbeatService.getAllHeartbeatStatuses();

    logger.logPerformance('Getting all heartbeat statuses', Date.now() - startTime);

    res.json({
      success: true,
      heartbeats: statuses,
      count: statuses.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/heartbeat/:repoPath/check
 * @desc Perform immediate heartbeat check
 * @access Public
 */
router.post('/:repoPath(*)/check', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const startTime = Date.now();

    logger.logOperation('Performing immediate heartbeat check', { repoPath });

    // Get heartbeat ID
    const status = heartbeatService.getHeartbeatStatus(repoPath);
    if (!status.running) {
      return res.status(400).json({
        success: false,
        error: 'Heartbeat not running for this repository',
        repository: repoPath
      });
    }

    // Perform check manually
    const heartbeatId = status.heartbeatId;
    await heartbeatService.performHeartbeatCheck(heartbeatId);

    // Get updated status
    const updatedStatus = heartbeatService.getHeartbeatStatus(repoPath);

    logger.logPerformance('Performing immediate heartbeat check', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      status: updatedStatus,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route PUT /api/v1/heartbeat/:repoPath/configure
 * @desc Configure heartbeat settings
 * @access Public
 */
router.put('/:repoPath(*)/configure', async (req, res, next) => {
  try {
    const { repoPath } = req.params;
    const { interval, notifications, enabled, options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Configuring heartbeat', { repoPath, interval, notifications, enabled });

    // Stop existing heartbeat if running
    const currentStatus = heartbeatService.getHeartbeatStatus(repoPath);
    if (currentStatus.running) {
      await heartbeatService.stopHeartbeat(repoPath);
    }

    // Start new heartbeat with new configuration
    const result = await heartbeatService.startHeartbeat(repoPath, {
      interval,
      notifications,
      enabled,
      ...options
    });

    logger.logPerformance('Configuring heartbeat', Date.now() - startTime, { repoPath });

    res.json({
      success: true,
      repository: repoPath,
      result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
