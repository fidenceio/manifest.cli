const fs = require('fs').promises;
const path = require('path');
const axios = require('axios');
const { logger } = require('../utils/logger');
const { UpdateChecker } = require('./updateChecker');

class HeartbeatService {
  constructor() {
    this.updateChecker = new UpdateChecker();
    this.heartbeats = new Map();
    this.checkIntervals = new Map();
    this.defaultInterval = 5 * 60 * 1000; // 5 minutes
    this.maxRetries = 3;
  }

  /**
   * Start heartbeat monitoring for a repository
   */
  async startHeartbeat(repoPath, options = {}) {
    try {
      const heartbeatId = this.generateHeartbeatId(repoPath);
      
      if (this.heartbeats.has(heartbeatId)) {
        logger.warn('Heartbeat already running', { repoPath, heartbeatId });
        return { success: false, reason: 'Heartbeat already running' };
      }

      const interval = options.interval || this.defaultInterval;
      const config = {
        repoPath,
        interval,
        lastCheck: null,
        lastStatus: null,
        retryCount: 0,
        enabled: true,
        notifications: options.notifications || [],
        ...options
      };

      this.heartbeats.set(heartbeatId, config);
      
      // Start the heartbeat loop
      this.scheduleHeartbeat(heartbeatId, interval);
      
      logger.logOperation('Heartbeat started', { repoPath, heartbeatId, interval });
      
      return { success: true, heartbeatId, config };
    } catch (error) {
      logger.logError('Starting heartbeat', error, { repoPath, options });
      throw error;
    }
  }

  /**
   * Stop heartbeat monitoring
   */
  async stopHeartbeat(repoPath) {
    try {
      const heartbeatId = this.generateHeartbeatId(repoPath);
      
      if (!this.heartbeats.has(heartbeatId)) {
        return { success: false, reason: 'Heartbeat not running' };
      }

      // Clear the interval
      if (this.checkIntervals.has(heartbeatId)) {
        clearInterval(this.checkIntervals.get(heartbeatId));
        this.checkIntervals.delete(heartbeatId);
      }

      // Remove from heartbeats
      this.heartbeats.delete(heartbeatId);
      
      logger.logOperation('Heartbeat stopped', { repoPath, heartbeatId });
      
      return { success: true, heartbeatId };
    } catch (error) {
      logger.logError('Stopping heartbeat', error, { repoPath });
      throw error;
    }
  }

  /**
   * Schedule heartbeat checks
   */
  scheduleHeartbeat(heartbeatId, interval) {
    const config = this.heartbeats.get(heartbeatId);
    if (!config) return;

    const checkInterval = setInterval(async () => {
      if (config.enabled) {
        await this.performHeartbeatCheck(heartbeatId);
      }
    }, interval);

    this.checkIntervals.set(heartbeatId, checkInterval);
  }

  /**
   * Perform a heartbeat check
   */
  async performHeartbeatCheck(heartbeatId) {
    try {
      const config = this.heartbeats.get(heartbeatId);
      if (!config) return;

      logger.logOperation('Performing heartbeat check', { heartbeatId, repoPath: config.repoPath });

      // Update last check time
      config.lastCheck = new Date().toISOString();

      // Perform comprehensive update check
      const updateResults = await this.updateChecker.checkRepositoryUpdates(config.repoPath);
      
      // Check for critical updates
      const criticalUpdates = this.analyzeCriticalUpdates(updateResults);
      
      // Check repository health
      const healthStatus = await this.checkRepositoryHealth(config.repoPath);
      
      // Determine overall status
      const status = this.determineStatus(updateResults, criticalUpdates, healthStatus);
      
      // Update heartbeat status
      config.lastStatus = {
        timestamp: config.lastCheck,
        status,
        updates: updateResults,
        criticalUpdates,
        health: healthStatus
      };

      // Reset retry count on success
      config.retryCount = 0;

      // Send notifications if configured
      if (config.notifications.length > 0) {
        await this.sendNotifications(heartbeatId, status, updateResults, criticalUpdates);
      }

      logger.logOperation('Heartbeat check completed', { heartbeatId, status });
      
    } catch (error) {
      logger.logError('Performing heartbeat check', error, { heartbeatId });
      
      // Increment retry count
      const config = this.heartbeats.get(heartbeatId);
      if (config) {
        config.retryCount++;
        
        // Disable heartbeat if max retries exceeded
        if (config.retryCount >= this.maxRetries) {
          config.enabled = false;
          logger.error('Heartbeat disabled due to max retries', { heartbeatId, retryCount: config.retryCount });
        }
      }
    }
  }

  /**
   * Analyze critical updates
   */
  analyzeCriticalUpdates(updateResults) {
    const critical = {
      security: [],
      breaking: [],
      major: [],
      dependencies: []
    };

    // Check for security vulnerabilities
    if (updateResults.security && updateResults.security.vulnerabilities) {
      critical.security = updateResults.security.vulnerabilities.filter(v => v.severity === 'high' || v.severity === 'critical');
    }

    // Check for major version updates
    if (updateResults.npm && updateResults.npm.outdated) {
      critical.major = updateResults.npm.outdated.filter(pkg => {
        const current = pkg.current.split('.')[0];
        const latest = pkg.latest.split('.')[0];
        return current !== latest;
      });
    }

    // Check for breaking changes in dependencies
    if (updateResults.npm && updateResults.npm.outdated) {
      critical.breaking = updateResults.npm.outdated.filter(pkg => 
        pkg.breaking || pkg.major || pkg.minor
      );
    }

    return critical;
  }

  /**
   * Check repository health
   */
  async checkRepositoryHealth(repoPath) {
    try {
      const health = {
        git: null,
        files: null,
        dependencies: null,
        overall: 'healthy'
      };

      // Check Git repository health
      try {
        const gitPath = path.join(repoPath, '.git');
        await fs.access(gitPath);
        health.git = 'healthy';
      } catch (error) {
        health.git = 'unhealthy';
      }

      // Check critical files
      try {
        const criticalFiles = ['package.json', 'README.md', '.gitignore'];
        const missingFiles = [];
        
        for (const file of criticalFiles) {
          try {
            await fs.access(path.join(repoPath, file));
          } catch (error) {
            missingFiles.push(file);
          }
        }
        
        health.files = missingFiles.length === 0 ? 'healthy' : `missing: ${missingFiles.join(', ')}`;
      } catch (error) {
        health.files = 'error';
      }

      // Check dependencies
      try {
        const packageJsonPath = path.join(repoPath, 'package.json');
        await fs.access(packageJsonPath);
        health.dependencies = 'healthy';
      } catch (error) {
        health.dependencies = 'unhealthy';
      }

      // Determine overall health
      const healthValues = Object.values(health).filter(v => v !== null);
      const unhealthyCount = healthValues.filter(v => v !== 'healthy').length;
      
      if (unhealthyCount === 0) {
        health.overall = 'healthy';
      } else if (unhealthyCount <= 1) {
        health.overall = 'warning';
      } else {
        health.overall = 'unhealthy';
      }

      return health;
    } catch (error) {
      logger.logError('Checking repository health', error, { repoPath });
      return { overall: 'error', error: error.message };
    }
  }

  /**
   * Determine overall status
   */
  determineStatus(updateResults, criticalUpdates, healthStatus) {
    if (healthStatus.overall === 'unhealthy') {
      return 'critical';
    }

    if (criticalUpdates.security.length > 0) {
      return 'security_alert';
    }

    if (criticalUpdates.breaking.length > 0) {
      return 'breaking_changes';
    }

    if (criticalUpdates.major.length > 0) {
      return 'major_updates';
    }

    if (healthStatus.overall === 'warning') {
      return 'warning';
    }

    return 'healthy';
  }

  /**
   * Send notifications
   */
  async sendNotifications(heartbeatId, status, updateResults, criticalUpdates) {
    const config = this.heartbeats.get(heartbeatId);
    if (!config || !config.notifications) return;

    for (const notification of config.notifications) {
      try {
        await this.sendNotification(notification, {
          heartbeatId,
          repoPath: config.repoPath,
          status,
          updateResults,
          criticalUpdates,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        logger.logError('Sending notification', error, { heartbeatId, notification });
      }
    }
  }

  /**
   * Send individual notification
   */
  async sendNotification(notification, data) {
    switch (notification.type) {
      case 'webhook':
        await this.sendWebhookNotification(notification.url, data);
        break;
      case 'email':
        await this.sendEmailNotification(notification.email, data);
        break;
      case 'slack':
        await this.sendSlackNotification(notification.webhook, data);
        break;
      default:
        logger.warn('Unknown notification type', { type: notification.type });
    }
  }

  /**
   * Send webhook notification
   */
  async sendWebhookNotification(url, data) {
    try {
      await axios.post(url, data, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 10000
      });
      logger.logOperation('Webhook notification sent', { url });
    } catch (error) {
      logger.logError('Sending webhook notification', error, { url });
      throw error;
    }
  }

  /**
   * Send email notification (placeholder)
   */
  async sendEmailNotification(email, data) {
    // TODO: Implement email notification
    logger.logOperation('Email notification placeholder', { email });
  }

  /**
   * Send Slack notification (placeholder)
   */
  async sendSlackNotification(webhook, data) {
    // TODO: Implement Slack notification
    logger.logOperation('Slack notification placeholder', { webhook });
  }

  /**
   * Get heartbeat status
   */
  getHeartbeatStatus(repoPath) {
    const heartbeatId = this.generateHeartbeatId(repoPath);
    const config = this.heartbeats.get(heartbeatId);
    
    if (!config) {
      return { running: false };
    }

    return {
      running: true,
      heartbeatId,
      config: {
        repoPath: config.repoPath,
        interval: config.interval,
        lastCheck: config.lastCheck,
        lastStatus: config.lastStatus,
        retryCount: config.retryCount,
        enabled: config.enabled
      }
    };
  }

  /**
   * Get all heartbeat statuses
   */
  getAllHeartbeatStatuses() {
    const statuses = [];
    for (const [heartbeatId, config] of this.heartbeats) {
      statuses.push({
        heartbeatId,
        repoPath: config.repoPath,
        interval: config.interval,
        lastCheck: config.lastCheck,
        lastStatus: config.lastStatus,
        retryCount: config.retryCount,
        enabled: config.enabled
      });
    }
    return statuses;
  }

  /**
   * Generate unique heartbeat ID
   */
  generateHeartbeatId(repoPath) {
    return `heartbeat_${Buffer.from(repoPath).toString('base64').replace(/[^a-zA-Z0-9]/g, '')}`;
  }
}

module.exports = { HeartbeatService };
