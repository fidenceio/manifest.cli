const axios = require('axios');

class ManifestClient {
  constructor(baseURL = 'http://localhost:3000', options = {}) {
    this.baseURL = baseURL;
    this.apiVersion = 'v1';
    this.client = axios.create({
      baseURL: `${baseURL}/api/${this.apiVersion}`,
      timeout: options.timeout || 30000,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Manifest-Client/1.0.0',
        ...options.headers
      }
    });

    // Add request/response interceptors
    this.client.interceptors.request.use(
      (config) => {
        if (options.logger) {
          options.logger.info(`Making request to ${config.url}`);
        }
        return config;
      },
      (error) => {
        if (options.logger) {
          options.logger.error('Request error:', error);
        }
        return Promise.reject(error);
      }
    );

    this.client.interceptors.response.use(
      (response) => {
        if (options.logger) {
          options.logger.info(`Response from ${response.config.url}: ${response.status}`);
        }
        return response;
      },
      (error) => {
        if (options.logger) {
          options.logger.error('Response error:', error.response?.data || error.message);
        }
        return Promise.reject(error);
      }
    );
  }

  /**
   * Analyze repository manifest
   */
  async analyze(repoPath) {
    try {
      const response = await this.client.get(`/manifest/${encodeURIComponent(repoPath)}/analyze`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to analyze repository manifest');
    }
  }

  /**
   * Enhanced version bumping
   */
  async versionBump(repoPath, incrementType = 'patch', options = {}) {
    try {
      const response = await this.client.post(`/manifest/${encodeURIComponent(repoPath)}/version/bump`, {
        incrementType,
        options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to bump version');
    }
  }

  /**
   * Configure version strategy
   */
  async versionStrategy(repoPath, strategy, options = {}) {
    try {
      const response = await this.client.post(`/manifest/${encodeURIComponent(repoPath)}/version/strategy`, {
        strategy,
        options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to configure version strategy');
    }
  }

  /**
   * Generate CI/CD configuration
   */
  async cicdGenerate(repoPath, platform, options = {}) {
    try {
      const response = await this.client.post(`/manifest/${encodeURIComponent(repoPath)}/cicd/generate`, {
        platform,
        options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to generate CI/CD configuration');
    }
  }

  /**
   * Process CI/CD webhook
   */
  async cicdWebhook(repoPath, platform, eventType, payload) {
    try {
      const response = await this.client.post(`/manifest/${encodeURIComponent(repoPath)}/cicd/webhook`, {
        platform,
        eventType,
        payload
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to process CI/CD webhook');
    }
  }

  /**
   * Generate installation script
   */
  async installGenerate(repoPath, platform, containerType, options = {}) {
    try {
      const response = await this.client.post(`/manifest/${encodeURIComponent(repoPath)}/install/generate`, {
        platform,
        containerType,
        options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to generate installation script');
    }
  }

  /**
   * Generate all installation scripts
   */
  async installAll(repoPath, options = {}) {
    try {
      const response = await this.client.post(`/manifest/${encodeURIComponent(repoPath)}/install/all`, {
        options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to generate all installation scripts');
    }
  }

  /**
   * Get repository health status
   */
  async health(repoPath) {
    try {
      const response = await this.client.get(`/manifest/${encodeURIComponent(repoPath)}/health`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get repository health status');
    }
  }

  /**
   * Legacy version management methods
   */
  async getVersion(repoPath) {
    try {
      const response = await this.client.get(`/version/${encodeURIComponent(repoPath)}`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get version');
    }
  }

  async bumpVersion(repoPath, type = 'patch', changes = [], metadata = {}) {
    try {
      const response = await this.client.post(`/version/${encodeURIComponent(repoPath)}/bump`, {
        type,
        changes,
        metadata
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to bump version');
    }
  }

  async updateVersion(repoPath, version, type = 'patch', updateType = 'auto') {
    try {
      const response = await this.client.post(`/version/${encodeURIComponent(repoPath)}/update`, {
        version,
        type,
        updateType
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to update version');
    }
  }

  /**
   * Documentation management methods
   */
  async getDocumentation(repoPath) {
    try {
      const response = await this.client.get(`/documentation/${encodeURIComponent(repoPath)}`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get documentation');
    }
  }

  async updateDocumentation(repoPath, metadata, options = {}) {
    try {
      const response = await this.client.post(`/documentation/${encodeURIComponent(repoPath)}/update`, {
        metadata,
        options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to update documentation');
    }
  }

  /**
   * GitHub integration methods
   */
  async getGitHubRepo(owner, repo) {
    try {
      const response = await this.client.get(`/github/repos/${owner}/${repo}`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get GitHub repository');
    }
  }

  async createGitHubRelease(owner, repo, tagName, name, body, draft = false, prerelease = false) {
    try {
      const response = await this.client.post(`/github/repos/${owner}/${repo}/releases`, {
        tagName,
        name,
        body,
        draft,
        prerelease
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to create GitHub release');
    }
  }

  /**
   * Git operations methods
   */
  async getGitStatus(repoPath) {
    try {
      const response = await this.client.get(`/git/${encodeURIComponent(repoPath)}/status`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get git status');
    }
  }

  async getGitTags(repoPath) {
    try {
      const response = await this.client.get(`/git/${encodeURIComponent(repoPath)}/tags`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get git tags');
    }
  }

  /**
   * Update management methods
   */
  async checkUpdates(repoPath) {
    try {
      const response = await this.client.get(`/updates/${encodeURIComponent(repoPath)}/check`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to check for updates');
    }
  }

  async applyUpdates(repoPath, updateType = 'auto', options = {}) {
    try {
      const response = await this.client.post(`/updates/${encodeURIComponent(repoPath)}/apply`, {
        updateType,
        options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to apply updates');
    }
  }

  /**
   * Repository management methods
   */
  async getRepositories() {
    try {
      const response = await this.client.get('/repositories');
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get repositories');
    }
  }

  async getRepository(repoPath) {
    try {
      const response = await this.client.get(`/repositories/${encodeURIComponent(repoPath)}`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to get repository');
    }
  }

  /**
   * Utility methods
   */
  async ping() {
    try {
      const response = await axios.get(`${this.baseURL}/health`);
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'Failed to ping Manifest service');
    }
  }

  /**
   * Error handling
   */
  handleError(error, defaultMessage) {
    if (error.response) {
      const { status, data } = error.response;
      const message = data?.error || data?.message || defaultMessage;
      return new Error(`HTTP ${status}: ${message}`);
    } else if (error.request) {
      return new Error(`Network error: ${defaultMessage}`);
    } else {
      return new Error(`${defaultMessage}: ${error.message}`);
    }
  }

  /**
   * Set authentication token
   */
  setAuthToken(token) {
    this.client.defaults.headers.common['Authorization'] = `Bearer ${token}`;
  }

  /**
   * Clear authentication token
   */
  clearAuthToken() {
    delete this.client.defaults.headers.common['Authorization'];
  }
}

module.exports = { ManifestClient };
