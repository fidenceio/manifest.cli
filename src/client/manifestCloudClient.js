const axios = require('axios');
const { EventEmitter } = require('events');

/**
 * Manifest Cloud Client - Proxy to Manifest Cloud LLM Agent Service
 * This client provides seamless access to LLM functionality hosted in the cloud
 */
class ManifestCloudClient extends EventEmitter {
  constructor(config = {}) {
    super();
    
    this.baseURL = config.baseURL || process.env.MANIFEST_CLOUD_URL || 'http://localhost:3001';
    this.apiKey = config.apiKey || process.env.MANIFEST_CLOUD_API_KEY;
    this.timeout = config.timeout || 30000;
    this.retries = config.retries || 3;
    
    // Initialize axios instance
    this.client = axios.create({
      baseURL: this.baseURL,
      timeout: this.timeout,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Manifest-Local-Client/1.0.0'
      }
    });
    
    // Add auth header if API key is provided
    if (this.apiKey) {
      this.client.defaults.headers.common['Authorization'] = `Bearer ${this.apiKey}`;
    }
    
    // Add request interceptor for logging
    this.client.interceptors.request.use(
      (config) => {
        this.emit('request', { url: config.url, method: config.method });
        return config;
      },
      (error) => {
        this.emit('error', error);
        return Promise.reject(error);
      }
    );
    
    // Add response interceptor for logging
    this.client.interceptors.response.use(
      (response) => {
        this.emit('response', { 
          url: response.config.url, 
          status: response.status, 
          duration: response.headers['x-response-time'] 
        });
        return response;
      },
      (error) => {
        this.emit('error', error);
        return Promise.reject(error);
      }
    );
  }

  /**
   * Analyze commits and provide intelligent insights
   */
  async analyzeCommits(repoPath, options = {}) {
    try {
      const response = await this.client.post('/api/v1/llm-agent/analyze', {
        repoPath,
        ...options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'analyzeCommits');
    }
  }

  /**
   * Generate changelog from commits
   */
  async generateChangelog(repoPath, options = {}) {
    try {
      const response = await this.client.post('/api/v1/llm-agent/changelog', {
        repoPath,
        ...options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'generateChangelog');
    }
  }

  /**
   * Get version recommendation
   */
  async getVersionRecommendation(repoPath, options = {}) {
    try {
      const response = await this.client.post('/api/v1/llm-agent/version', {
        repoPath,
        ...options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'getVersionRecommendation');
    }
  }

  /**
   * Detect API changes
   */
  async detectAPIChanges(repoPath, options = {}) {
    try {
      const response = await this.client.post('/api/v1/llm-agent/api-changes', {
        repoPath,
        ...options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'detectAPIChanges');
    }
  }

  /**
   * Analyze individual commit
   */
  async analyzeCommit(repoPath, commitHash, options = {}) {
    try {
      const response = await this.client.post('/api/v1/llm-agent/commit', {
        repoPath,
        commitHash,
        ...options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'analyzeCommit');
    }
  }

  /**
   * Smart update detection
   */
  async detectSmartUpdates(repoPath, options = {}) {
    try {
      const response = await this.client.post('/api/v1/llm-agent/smart-update', {
        repoPath,
        ...options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'detectSmartUpdates');
    }
  }

  /**
   * Get commit insights
   */
  async getCommitInsights(repoPath, options = {}) {
    try {
      const response = await this.client.post('/api/v1/llm-agent/insights', {
        repoPath,
        ...options
      });
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'getCommitInsights');
    }
  }

  /**
   * Check cloud service health
   */
  async checkHealth() {
    try {
      const response = await this.client.get('/health');
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'checkHealth');
    }
  }

  /**
   * Get cloud service metrics
   */
  async getMetrics() {
    try {
      const response = await this.client.get('/metrics');
      return response.data;
    } catch (error) {
      throw this.handleError(error, 'getMetrics');
    }
  }

  /**
   * Handle errors with context
   */
  handleError(error, operation) {
    const enhancedError = new Error(`Manifest Cloud ${operation} failed: ${error.message}`);
    enhancedError.originalError = error;
    enhancedError.operation = operation;
    enhancedError.statusCode = error.response?.status;
    enhancedError.responseData = error.response?.data;
    
    this.emit('error', enhancedError);
    return enhancedError;
  }

  /**
   * Test connectivity to cloud service
   */
  async testConnection() {
    try {
      const health = await this.checkHealth();
      return {
        connected: true,
        status: health.status,
        timestamp: health.timestamp,
        service: 'Manifest Cloud LLM Agent'
      };
    } catch (error) {
      return {
        connected: false,
        error: error.message,
        service: 'Manifest Cloud LLM Agent'
      };
    }
  }
}

// Quick functions for common operations
const createCloudClient = (config) => new ManifestCloudClient(config);
const testCloudConnection = async (config) => {
  const client = new ManifestCloudClient(config);
  return await client.testConnection();
};

module.exports = {
  ManifestCloudClient,
  createCloudClient,
  testCloudConnection
};
