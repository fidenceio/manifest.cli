const fs = require('fs').promises;
const path = require('path');
const { logger } = require('../utils/logger');

class PluginManager {
  constructor() {
    this.plugins = new Map();
    this.pluginTypes = {
      'manifest-format': 'Manifest format detection and parsing',
      'version-strategy': 'Version management strategies',
      'cicd-platform': 'CI/CD platform integration',
      'install-script': 'Installation script generation',
      'update-checker': 'Update and heartbeat checking',
      'deployment': 'Deployment automation',
      'monitoring': 'Health monitoring and metrics'
    };
  }

  /**
   * Register a plugin
   */
  async registerPlugin(pluginPath, pluginType) {
    try {
      logger.logOperation('Registering plugin', { pluginPath, pluginType });
      
      if (!this.pluginTypes[pluginType]) {
        throw new Error(`Unknown plugin type: ${pluginType}`);
      }

      const plugin = require(pluginPath);
      
      if (!plugin.name || !plugin.version || !plugin.execute) {
        throw new Error('Invalid plugin structure. Must have name, version, and execute method.');
      }

      const pluginId = `${plugin.name}@${plugin.version}`;
      this.plugins.set(pluginId, {
        ...plugin,
        type: pluginType,
        path: pluginPath,
        registeredAt: new Date().toISOString()
      });

      logger.logOperation('Plugin registered successfully', { pluginId, pluginType });
      return { success: true, pluginId };
    } catch (error) {
      logger.logError('Registering plugin', error, { pluginPath, pluginType });
      throw error;
    }
  }

  /**
   * Execute a plugin
   */
  async executePlugin(pluginId, context, options = {}) {
    try {
      const plugin = this.plugins.get(pluginId);
      if (!plugin) {
        throw new Error(`Plugin not found: ${pluginId}`);
      }

      logger.logOperation('Executing plugin', { pluginId, context });
      
      const result = await plugin.execute(context, options);
      
      logger.logOperation('Plugin executed successfully', { pluginId, result });
      return result;
    } catch (error) {
      logger.logError('Executing plugin', error, { pluginId, context });
      throw error;
    }
  }

  /**
   * Get plugins by type
   */
  getPluginsByType(pluginType) {
    const plugins = [];
    for (const [id, plugin] of this.plugins) {
      if (plugin.type === pluginType) {
        plugins.push({ id, ...plugin });
      }
    }
    return plugins;
  }

  /**
   * List all registered plugins
   */
  listPlugins() {
    const plugins = [];
    for (const [id, plugin] of this.plugins) {
      plugins.push({
        id,
        name: plugin.name,
        version: plugin.version,
        type: plugin.type,
        description: plugin.description,
        registeredAt: plugin.registeredAt
      });
    }
    return plugins;
  }

  /**
   * Unregister a plugin
   */
  async unregisterPlugin(pluginId) {
    try {
      const plugin = this.plugins.get(pluginId);
      if (!plugin) {
        throw new Error(`Plugin not found: ${pluginId}`);
      }

      this.plugins.delete(pluginId);
      logger.logOperation('Plugin unregistered', { pluginId });
      return { success: true, pluginId };
    } catch (error) {
      logger.logError('Unregistering plugin', error, { pluginId });
      throw error;
    }
  }

  /**
   * Load plugins from directory
   */
  async loadPluginsFromDirectory(pluginsDir) {
    try {
      logger.logOperation('Loading plugins from directory', { pluginsDir });
      
      const files = await fs.readdir(pluginsDir);
      const pluginFiles = files.filter(file => file.endsWith('.js') || file.endsWith('.mjs'));
      
      let loadedCount = 0;
      for (const file of pluginFiles) {
        try {
          const pluginPath = path.join(pluginsDir, file);
          const plugin = require(pluginPath);
          
          if (plugin.pluginType && plugin.name) {
            await this.registerPlugin(pluginPath, plugin.pluginType);
            loadedCount++;
          }
        } catch (error) {
          logger.warn('Failed to load plugin', { file, error: error.message });
        }
      }

      logger.logOperation('Plugins loaded from directory', { pluginsDir, loadedCount });
      return { success: true, loadedCount };
    } catch (error) {
      logger.logError('Loading plugins from directory', error, { pluginsDir });
      throw error;
    }
  }
}

module.exports = { PluginManager };
