const fs = require('fs').promises;
const path = require('path');
const marked = require('marked');
const matter = require('gray-matter');
const yaml = require('js-yaml');
const { logger } = require('../utils/logger');

class DocumentationManager {
  constructor() {
    this.docTemplates = {
      readme: {
        name: 'README.md',
        sections: [
          'title',
          'description',
          'badges',
          'features',
          'installation',
          'usage',
          'configuration',
          'api',
          'examples',
          'contributing',
          'license',
          'changelog'
        ]
      },
      changelog: {
        name: 'CHANGELOG.md',
        sections: [
          'header',
          'unreleased',
          'versions'
        ]
      },
      api: {
        name: 'API.md',
        sections: [
          'overview',
          'endpoints',
          'authentication',
          'examples',
          'errors'
        ]
      }
    };
  }

  /**
   * Update README.md with current information
   */
  async updateReadme(repoPath, metadata = {}) {
    try {
      logger.logOperation('Updating README', { repoPath, metadata });
      
      const readmePath = path.join(repoPath, 'README.md');
      let readmeContent = '';
      
      try {
        readmeContent = await fs.readFile(readmePath, 'utf8');
      } catch (error) {
        // README doesn't exist, create new one
        logger.info('README.md not found, creating new one');
      }

      const updatedContent = await this.generateReadmeContent(metadata, readmeContent);
      await fs.writeFile(readmePath, updatedContent);

      logger.logOperation('README updated successfully', { repoPath });
      return { success: true, file: 'README.md' };
    } catch (error) {
      logger.logError('Updating README', error, { repoPath, metadata });
      throw error;
    }
  }

  /**
   * Generate README content
   */
  async generateReadmeContent(metadata, existingContent = '') {
    try {
      const {
        name = 'Project Name',
        description = 'Project description',
        version = '1.0.0',
        repository = {},
        badges = [],
        features = [],
        installation = [],
        usage = [],
        configuration = {},
        api = {},
        examples = [],
        license = 'MIT',
        changelog = true
      } = metadata;

      let content = '';

      // Title
      content += `# ${name}\n\n`;
      
      // Description
      if (description) {
        content += `${description}\n\n`;
      }

      // Badges
      if (badges.length > 0) {
        content += this.generateBadges(badges, version);
        content += '\n\n';
      }

      // Features
      if (features.length > 0) {
        content += '## Features\n\n';
        features.forEach(feature => {
          content += `- ${feature}\n`;
        });
        content += '\n';
      }

      // Installation
      if (installation.length > 0) {
        content += '## Installation\n\n';
        installation.forEach(step => {
          content += `${step}\n\n`;
        });
      }

      // Usage
      if (usage.length > 0) {
        content += '## Usage\n\n';
        usage.forEach(example => {
          content += `${example}\n\n`;
        });
      }

      // Configuration
      if (Object.keys(configuration).length > 0) {
        content += '## Configuration\n\n';
        content += '| Option | Description | Default |\n';
        content += '|--------|-------------|--------|\n';
        Object.entries(configuration).forEach(([key, config]) => {
          content += `| \`${key}\` | ${config.description || ''} | \`${config.default || ''}\` |\n`;
        });
        content += '\n';
      }

      // API Reference
      if (Object.keys(api).length > 0) {
        content += '## API Reference\n\n';
        Object.entries(api).forEach(([endpoint, details]) => {
          content += `### ${endpoint}\n\n`;
          content += `**Method:** \`${details.method || 'GET'}\`\n\n`;
          if (details.description) {
            content += `${details.description}\n\n`;
          }
          if (details.parameters) {
            content += '**Parameters:**\n\n';
            content += '| Name | Type | Required | Description |\n';
            content += '|------|------|----------|-------------|\n';
            details.parameters.forEach(param => {
              content += `| \`${param.name}\` | \`${param.type}\` | ${param.required ? 'Yes' : 'No'} | ${param.description || ''} |\n`;
            });
            content += '\n';
          }
        });
      }

      // Examples
      if (examples.length > 0) {
        content += '## Examples\n\n';
        examples.forEach((example, index) => {
          content += `### Example ${index + 1}\n\n`;
          content += example.description ? `${example.description}\n\n` : '';
          if (example.code) {
            content += '```' + (example.language || '') + '\n';
            content += example.code;
            content += '\n```\n\n';
          }
        });
      }

      // Contributing
      content += '## Contributing\n\n';
      content += 'Contributions are welcome! Please feel free to submit a Pull Request.\n\n';

      // License
      content += `## License\n\n`;
      content += `This project is licensed under the ${license} License - see the [LICENSE](LICENSE) file for details.\n\n`;

      // Changelog
      if (changelog) {
        content += '## Changelog\n\n';
        content += `See [CHANGELOG.md](CHANGELOG.md) for a list of changes.\n\n`;
      }

      return content;
    } catch (error) {
      logger.logError('Generating README content', error, { metadata });
      throw error;
    }
  }

  /**
   * Generate badges for README
   */
  generateBadges(badges, version) {
    const badgeUrls = {
      version: `https://img.shields.io/badge/version-${version}-blue.svg`,
      build: 'https://img.shields.io/badge/build-passing-brightgreen.svg',
      coverage: 'https://img.shields.io/badge/coverage-90%25-brightgreen.svg',
      license: 'https://img.shields.io/badge/license-MIT-blue.svg',
      npm: 'https://img.shields.io/npm/v/package-name.svg',
      docker: 'https://img.shields.io/docker/pulls/image-name.svg',
      github: 'https://img.shields.io/github/stars/owner/repo.svg'
    };

    return badges.map(badge => {
      const url = badgeUrls[badge.type] || badge.url;
      const alt = badge.alt || badge.type;
      return `![${alt}](${url})`;
    }).join(' ');
  }

  /**
   * Update CHANGELOG.md
   */
  async updateChangelog(repoPath, version, changes = [], type = 'patch') {
    try {
      logger.logOperation('Updating CHANGELOG', { repoPath, version, changes, type });
      
      const changelogPath = path.join(repoPath, 'CHANGELOG.md');
      let changelogContent = '';
      
      try {
        changelogContent = await fs.readFile(changelogPath, 'utf8');
      } catch (error) {
        // CHANGELOG doesn't exist, create new one
        logger.info('CHANGELOG.md not found, creating new one');
      }

      const updatedContent = this.generateChangelogContent(version, changes, type, changelogContent);
      await fs.writeFile(changelogPath, updatedContent);

      logger.logOperation('CHANGELOG updated successfully', { repoPath, version });
      return { success: true, file: 'CHANGELOG.md' };
    } catch (error) {
      logger.logError('Updating CHANGELOG', error, { repoPath, version, changes });
      throw error;
    }
  }

  /**
   * Generate changelog content
   */
  generateChangelogContent(version, changes, type, existingContent = '') {
    try {
      const date = new Date().toISOString().split('T')[0];
      let content = '';

      // Header
      if (!existingContent.includes('# Changelog')) {
        content += '# Changelog\n\n';
        content += 'All notable changes to this project will be documented in this file.\n\n';
        content += 'The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),\n';
        content += 'and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).\n\n';
      } else {
        content = existingContent;
      }

      // Add new version entry
      const versionEntry = `## [${version}] - ${date}\n\n`;
      
      // Determine change type labels
      const typeLabels = {
        major: '🚨 BREAKING CHANGES',
        minor: '✨ Features',
        patch: '🐛 Bug Fixes'
      };

      const label = typeLabels[type] || typeLabels.patch;
      content += versionEntry;
      content += `### ${label}\n\n`;

      if (changes.length > 0) {
        changes.forEach(change => {
          content += `- ${change}\n`;
        });
      } else {
        content += `- Version bump to ${version}\n`;
      }

      content += '\n';

      // Add to beginning of existing content (after header)
      if (existingContent) {
        const lines = existingContent.split('\n');
        const headerEndIndex = lines.findIndex(line => line.startsWith('## ['));
        
        if (headerEndIndex !== -1) {
          lines.splice(headerEndIndex, 0, ...versionEntry.split('\n'));
          content = lines.join('\n');
        }
      }

      return content;
    } catch (error) {
      logger.logError('Generating changelog content', error, { version, changes, type });
      throw error;
    }
  }

  /**
   * Update API documentation
   */
  async updateApiDocs(repoPath, apiSpec) {
    try {
      logger.logOperation('Updating API documentation', { repoPath, apiSpec });
      
      const apiPath = path.join(repoPath, 'API.md');
      const content = this.generateApiContent(apiSpec);
      await fs.writeFile(apiPath, content);

      logger.logOperation('API documentation updated successfully', { repoPath });
      return { success: true, file: 'API.md' };
    } catch (error) {
      logger.logError('Updating API documentation', error, { repoPath, apiSpec });
      throw error;
    }
  }

  /**
   * Generate API documentation content
   */
  generateApiContent(apiSpec) {
    try {
      let content = '# API Documentation\n\n';
      
      if (apiSpec.overview) {
        content += `## Overview\n\n${apiSpec.overview}\n\n`;
      }

      if (apiSpec.authentication) {
        content += '## Authentication\n\n';
        content += `${apiSpec.authentication}\n\n`;
      }

      if (apiSpec.endpoints && apiSpec.endpoints.length > 0) {
        content += '## Endpoints\n\n';
        
        apiSpec.endpoints.forEach(endpoint => {
          content += `### ${endpoint.name}\n\n`;
          content += `**URL:** \`${endpoint.url}\`\n\n`;
          content += `**Method:** \`${endpoint.method}\`\n\n`;
          
          if (endpoint.description) {
            content += `${endpoint.description}\n\n`;
          }

          if (endpoint.parameters && endpoint.parameters.length > 0) {
            content += '**Parameters:**\n\n';
            content += '| Name | Type | Required | Description |\n';
            content += '|------|------|----------|-------------|\n';
            endpoint.parameters.forEach(param => {
              content += `| \`${param.name}\` | \`${param.type}\` | ${param.required ? 'Yes' : 'No'} | ${param.description || ''} |\n`;
            });
            content += '\n';
          }

          if (endpoint.responses && endpoint.responses.length > 0) {
            content += '**Responses:**\n\n';
            endpoint.responses.forEach(response => {
              content += `**${response.code} ${response.status}**\n\n`;
              if (response.description) {
                content += `${response.description}\n\n`;
              }
              if (response.example) {
                content += '```json\n';
                content += JSON.stringify(response.example, null, 2);
                content += '\n```\n\n';
              }
            });
          }

          content += '---\n\n';
        });
      }

      if (apiSpec.examples && apiSpec.examples.length > 0) {
        content += '## Examples\n\n';
        apiSpec.examples.forEach((example, index) => {
          content += `### Example ${index + 1}: ${example.title}\n\n`;
          content += `${example.description}\n\n`;
          content += '**Request:**\n\n';
          content += '```bash\n';
          content += example.request;
          content += '\n```\n\n';
          
          if (example.response) {
            content += '**Response:**\n\n';
            content += '```json\n';
            content += JSON.stringify(example.response, null, 2);
            content += '\n```\n\n';
          }
        });
      }

      if (apiSpec.errors && apiSpec.errors.length > 0) {
        content += '## Error Codes\n\n';
        content += '| Code | Status | Description |\n';
        content += '|------|--------|-------------|\n';
        apiSpec.errors.forEach(error => {
          content += `| ${error.code} | ${error.status} | ${error.description} |\n`;
        });
        content += '\n';
      }

      return content;
    } catch (error) {
      logger.logError('Generating API content', error, { apiSpec });
      throw error;
    }
  }

  /**
   * Update all documentation files
   */
  async updateAllDocumentation(repoPath, metadata) {
    try {
      logger.logOperation('Updating all documentation', { repoPath, metadata });
      
      const results = [];
      
      // Update README
      if (metadata.readme !== false) {
        const readmeResult = await this.updateReadme(repoPath, metadata);
        results.push(readmeResult);
      }

      // Update CHANGELOG
      if (metadata.changelog !== false && metadata.version) {
        const changelogResult = await this.updateChangelog(
          repoPath, 
          metadata.version, 
          metadata.changes || [], 
          metadata.versionType || 'patch'
        );
        results.push(changelogResult);
      }

      // Update API docs
      if (metadata.api && Object.keys(metadata.api).length > 0) {
        const apiResult = await this.updateApiDocs(repoPath, metadata.api);
        results.push(apiResult);
      }

      logger.logOperation('All documentation updated successfully', { repoPath, results });
      return { success: true, results };
    } catch (error) {
      logger.logError('Updating all documentation', error, { repoPath, metadata });
      throw error;
    }
  }
}

module.exports = DocumentationManager;
