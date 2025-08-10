const axios = require('axios');
const { EventEmitter } = require('events');

class EnhancedManifestClient extends EventEmitter {
  constructor(config = {}) {
    super();
    
    this.config = {
      baseURL: config.baseURL || 'http://localhost:3000',
      apiVersion: config.apiVersion || 'v1',
      timeout: config.timeout || 30000,
      retries: config.retries || 3,
      heartbeatInterval: config.heartbeatInterval || 5 * 60 * 1000, // 5 minutes
      autoHeartbeat: config.autoHeartbeat !== false,
      ...config
    };
    
    this.axios = axios.create({
      baseURL: `${this.config.baseURL}/api/${this.config.apiVersion}`,
      timeout: this.config.timeout,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Manifest-Client/1.0.0'
      }
    });
    
    this.heartbeatId = null;
    this.heartbeatInterval = null;
    this.isConnected = false;
    
    // Setup interceptors
    this.setupInterceptors();
    
    // Auto-connect if enabled
    if (this.config.autoConnect !== false) {
      this.connect();
    }
  }

  /**
   * Setup axios interceptors
   */
  setupInterceptors() {
    // Request interceptor
    this.axios.interceptors.request.use(
      (config) => {
        this.emit('request', config);
        return config;
      },
      (error) => {
        this.emit('requestError', error);
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.axios.interceptors.response.use(
      (response) => {
        this.emit('response', response);
        return response;
      },
      async (error) => {
        this.emit('responseError', error);
        
        // Retry logic
        if (error.config && error.config.retryCount < this.config.retries) {
          error.config.retryCount = error.config.retryCount || 0;
          error.config.retryCount++;
          
          // Exponential backoff
          const delay = Math.pow(2, error.config.retryCount) * 1000;
          await new Promise(resolve => setTimeout(resolve, delay));
          
          return this.axios.request(error.config);
        }
        
        return Promise.reject(error);
      }
    );
  }

  /**
   * Connect to Manifest service
   */
  async connect() {
    try {
      const response = await this.axios.get('/health');
      this.isConnected = true;
      this.emit('connected', response.data);
      
      // Start heartbeat if enabled
      if (this.config.autoHeartbeat) {
        this.startHeartbeat();
      }
      
      return response.data;
    } catch (error) {
      this.isConnected = false;
      this.emit('connectionError', error);
      throw error;
    }
  }

  /**
   * Disconnect from Manifest service
   */
  async disconnect() {
    try {
      if (this.heartbeatInterval) {
        clearInterval(this.heartbeatInterval);
        this.heartbeatInterval = null;
      }
      
      this.isConnected = false;
      this.emit('disconnected');
      
      return { success: true };
    } catch (error) {
      this.emit('disconnectionError', error);
      throw error;
    }
  }

  /**
   * Start heartbeat monitoring
   */
  startHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
    
    this.heartbeatInterval = setInterval(async () => {
      try {
        const response = await this.axios.get('/health');
        this.emit('heartbeat', response.data);
      } catch (error) {
        this.emit('heartbeatError', error);
      }
    }, this.config.heartbeatInterval);
    
    this.emit('heartbeatStarted');
  }

  /**
   * Stop heartbeat monitoring
   */
  stopHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
      this.emit('heartbeatStopped');
    }
  }

  /**
   * Analyze repository manifest
   */
  async analyzeManifest(repoPath, options = {}) {
    try {
      const response = await this.axios.get(`/manifest/${encodeURIComponent(repoPath)}/analyze`, {
        params: options
      });
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Bump version with push script integration
   */
  async bumpVersion(repoPath, incrementType = 'patch', options = {}) {
    try {
      const response = await this.axios.post(`/manifest/${encodeURIComponent(repoPath)}/version/bump`, {
        incrementType,
        options
      });
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Start heartbeat monitoring for repository
   */
  async startRepositoryHeartbeat(repoPath, options = {}) {
    try {
      const response = await this.axios.post(`/heartbeat/${encodeURIComponent(repoPath)}/start`, options);
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Stop heartbeat monitoring for repository
   */
  async stopRepositoryHeartbeat(repoPath) {
    try {
      const response = await this.axios.post(`/heartbeat/${encodeURIComponent(repoPath)}/stop`);
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Get heartbeat status for repository
   */
  async getHeartbeatStatus(repoPath) {
    try {
      const response = await this.axios.get(`/heartbeat/${encodeURIComponent(repoPath)}/status`);
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Generate installation scripts
   */
  async generateInstallScripts(repoPath, platform, containerType, options = {}) {
    try {
      const response = await this.axios.post(`/manifest/${encodeURIComponent(repoPath)}/install/generate`, {
        platform,
        containerType,
        options
      });
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Check for updates
   */
  async checkUpdates(repoPath) {
    try {
      const response = await this.axios.get(`/updates/${encodeURIComponent(repoPath)}`);
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Execute plugin
   */
  async executePlugin(pluginId, context, options = {}) {
    try {
      const response = await this.axios.post(`/plugins/${pluginId}/execute`, {
        context,
        options
      });
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * List available plugins
   */
  async listPlugins() {
    try {
      const response = await this.axios.get('/plugins/list');
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Get plugin information
   */
  async getPluginInfo(pluginId) {
    try {
      const response = await this.axios.get(`/plugins/${pluginId}/info`);
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Generate CI/CD configuration
   */
  async generateCICDConfig(repoPath, platform, options = {}) {
    try {
      const response = await this.axios.post(`/manifest/${encodeURIComponent(repoPath)}/cicd/generate`, {
        platform,
        options
      });
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Get service health status
   */
  async getHealth() {
    try {
      const response = await this.axios.get('/health');
      return response.data;
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  /**
   * Wait for service to be ready
   */
  async waitForReady(timeout = 60000, interval = 1000) {
    const startTime = Date.now();
    
    while (Date.now() - startTime < timeout) {
      try {
        await this.getHealth();
        return true;
      } catch (error) {
        await new Promise(resolve => setTimeout(resolve, interval));
      }
    }
    
    throw new Error('Service not ready within timeout');
  }

  /**
   * Get client status
   */
  getStatus() {
    return {
      isConnected: this.isConnected,
      heartbeatActive: !!this.heartbeatInterval,
      config: this.config,
      uptime: process.uptime()
    };
  }
}

module.exports = { EnhancedManifestClient };
