const express = require('express');
const { PluginManager } = require('../services/pluginManager');
const { logger } = require('../utils/logger');

const router = express.Router();
const pluginManager = new PluginManager();

/**
 * @route POST /api/v1/plugins/register
 * @desc Register a new plugin
 * @access Public
 */
router.post('/register', async (req, res, next) => {
  try {
    const { pluginPath, pluginType } = req.body;
    const startTime = Date.now();

    logger.logOperation('Registering plugin', { pluginPath, pluginType });

    const result = await pluginManager.registerPlugin(pluginPath, pluginType);

    logger.logPerformance('Registering plugin', Date.now() - startTime, { pluginPath, pluginType });

    res.json({
      success: true,
      result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/plugins/:pluginId/execute
 * @desc Execute a plugin
 * @access Public
 */
router.post('/:pluginId/execute', async (req, res, next) => {
  try {
    const { pluginId } = req.params;
    const { context, options = {} } = req.body;
    const startTime = Date.now();

    logger.logOperation('Executing plugin', { pluginId, context });

    const result = await pluginManager.executePlugin(pluginId, context, options);

    logger.logPerformance('Executing plugin', Date.now() - startTime, { pluginId });

    res.json({
      success: true,
      pluginId,
      result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/plugins/list
 * @desc List all registered plugins
 * @access Public
 */
router.get('/list', async (req, res, next) => {
  try {
    const startTime = Date.now();

    logger.logOperation('Listing plugins');

    const plugins = pluginManager.listPlugins();

    logger.logPerformance('Listing plugins', Date.now() - startTime);

    res.json({
      success: true,
      plugins,
      count: plugins.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/plugins/type/:pluginType
 * @desc Get plugins by type
 * @access Public
 */
router.get('/type/:pluginType', async (req, res, next) => {
  try {
    const { pluginType } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting plugins by type', { pluginType });

    const plugins = pluginManager.getPluginsByType(pluginType);

    logger.logPerformance('Getting plugins by type', Date.now() - startTime, { pluginType });

    res.json({
      success: true,
      pluginType,
      plugins,
      count: plugins.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route DELETE /api/v1/plugins/:pluginId
 * @desc Unregister a plugin
 * @access Public
 */
router.delete('/:pluginId', async (req, res, next) => {
  try {
    const { pluginId } = req.params;
    const startTime = Date.now();

    logger.logOperation('Unregistering plugin', { pluginId });

    const result = await pluginManager.unregisterPlugin(pluginId);

    logger.logPerformance('Unregistering plugin', Date.now() - startTime, { pluginId });

    res.json({
      success: true,
      pluginId,
      result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/plugins/load-directory
 * @desc Load plugins from a directory
 * @access Public
 */
router.post('/load-directory', async (req, res, next) => {
  try {
    const { pluginsDir } = req.body;
    const startTime = Date.now();

    logger.logOperation('Loading plugins from directory', { pluginsDir });

    const result = await pluginManager.loadPluginsFromDirectory(pluginsDir);

    logger.logPerformance('Loading plugins from directory', Date.now() - startTime, { pluginsDir });

    res.json({
      success: true,
      result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/plugins/types
 * @desc Get available plugin types
 * @access Public
 */
router.get('/types', async (req, res, next) => {
  try {
    const startTime = Date.now();

    logger.logOperation('Getting plugin types');

    const pluginTypes = pluginManager.pluginTypes;

    logger.logPerformance('Getting plugin types', Date.now() - startTime);

    res.json({
      success: true,
      pluginTypes,
      count: Object.keys(pluginTypes).length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/plugins/:pluginId/info
 * @desc Get plugin information
 * @access Public
 */
router.get('/:pluginId/info', async (req, res, next) => {
  try {
    const { pluginId } = req.params;
    const startTime = Date.now();

    logger.logOperation('Getting plugin info', { pluginId });

    const plugins = pluginManager.listPlugins();
    const plugin = plugins.find(p => p.id === pluginId);

    if (!plugin) {
      return res.status(404).json({
        success: false,
        error: 'Plugin not found',
        pluginId
      });
    }

    logger.logPerformance('Getting plugin info', Date.now() - startTime, { pluginId });

    res.json({
      success: true,
      plugin,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
