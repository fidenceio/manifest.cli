/**
 * Example Manifest Format Plugin
 * Demonstrates how to create a custom manifest format plugin
 */

module.exports = {
  name: 'example-manifest-format',
  version: '1.0.0',
  description: 'Example plugin for custom manifest format detection',
  pluginType: 'manifest-format',
  author: 'Kanizsa Team',
  
  /**
   * Execute the plugin
   * @param {Object} context - The context object containing repository information
   * @param {Object} options - Plugin options
   * @returns {Object} Plugin execution result
   */
  async execute(context, options = {}) {
    try {
      const { repoPath, manifestInfo } = context;
      
      // Example: Detect custom manifest format
      const customManifestFiles = [
        'custom-manifest.yml',
        'app-config.yaml',
        'deployment.yml'
      ];
      
      const detectedFiles = [];
      for (const file of customManifestFiles) {
        try {
          const fs = require('fs').promises;
          await fs.access(`${repoPath}/${file}`);
          detectedFiles.push(file);
        } catch (error) {
          // File doesn't exist
        }
      }
      
      if (detectedFiles.length > 0) {
        return {
          success: true,
          format: 'custom',
          detectedFiles,
          metadata: {
            type: 'custom-manifest',
            version: '1.0.0',
            description: 'Custom manifest format detected by plugin',
            files: detectedFiles
          },
          confidence: 0.8
        };
      }
      
      return {
        success: false,
        format: null,
        reason: 'No custom manifest files detected'
      };
      
    } catch (error) {
      return {
        success: false,
        error: error.message,
        format: null
      };
    }
  },
  
  /**
   * Plugin configuration schema
   */
  configSchema: {
    customManifestFiles: {
      type: 'array',
      items: { type: 'string' },
      default: ['custom-manifest.yml', 'app-config.yaml', 'deployment.yml'],
      description: 'List of custom manifest files to detect'
    },
    confidenceThreshold: {
      type: 'number',
      minimum: 0,
      maximum: 1,
      default: 0.7,
      description: 'Minimum confidence threshold for detection'
    }
  },
  
  /**
   * Plugin metadata
   */
  metadata: {
    supportedFormats: ['custom'],
    dependencies: [],
    tags: ['example', 'custom', 'manifest-format']
  }
};
