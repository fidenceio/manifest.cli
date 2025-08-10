const { exec } = require('child_process');
const { promisify } = require('util');
const axios = require('axios');
const { logger } = require('../utils/logger');

const execAsync = promisify(exec);

class GitHubService {
  constructor() {
    this.token = process.env.GITHUB_TOKEN;
    this.apiUrl = process.env.GITHUB_API_URL || 'https://api.github.com';
    this.headers = {
      'Authorization': `token ${this.token}`,
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'Manifest-Service'
    };
  }

  /**
   * Check if GitHub CLI is authenticated
   */
  async checkAuth() {
    try {
      const { stdout } = await execAsync('gh auth status');
      return {
        authenticated: true,
        username: stdout.match(/Logged in to github\.com as (.+)/)?.[1],
        token: stdout.match(/Token: (.+)/)?.[1] ? 'Valid' : 'Invalid'
      };
    } catch (error) {
      return {
        authenticated: false,
        error: error.message
      };
    }
  }

  /**
   * Authenticate with GitHub CLI
   */
  async authenticate(token = null) {
    try {
      const authToken = token || this.token;
      if (!authToken) {
        throw new Error('GitHub token is required');
      }

      // Set the token for gh CLI
      await execAsync(`gh auth login --with-token <<< "${authToken}"`);
      
      logger.logOperation('GitHub authentication successful');
      return { success: true, message: 'Authentication successful' };
    } catch (error) {
      logger.logError('GitHub authentication', error);
      throw error;
    }
  }

  /**
   * Get repository information
   */
  async getRepositoryInfo(owner, repo) {
    try {
      const response = await axios.get(`${this.apiUrl}/repos/${owner}/${repo}`, {
        headers: this.headers
      });

      return {
        id: response.data.id,
        name: response.data.name,
        full_name: response.data.full_name,
        description: response.data.description,
        private: response.data.private,
        fork: response.data.fork,
        language: response.data.language,
        default_branch: response.data.default_branch,
        stargazers_count: response.data.stargazers_count,
        watchers_count: response.data.watchers_count,
        forks_count: response.data.forks_count,
        open_issues_count: response.data.open_issues_count,
        created_at: response.data.created_at,
        updated_at: response.data.updated_at,
        pushed_at: response.data.pushed_at,
        size: response.data.size,
        topics: response.data.topics || []
      };
    } catch (error) {
      logger.logError('Getting repository info', error, { owner, repo });
      throw error;
    }
  }

  /**
   * Get repository releases
   */
  async getReleases(owner, repo) {
    try {
      const response = await axios.get(`${this.apiUrl}/repos/${owner}/${repo}/releases`, {
        headers: this.headers
      });

      return response.data.map(release => ({
        id: release.id,
        tag_name: release.tag_name,
        name: release.name,
        body: release.body,
        draft: release.draft,
        prerelease: release.prerelease,
        created_at: release.created_at,
        published_at: release.published_at,
        assets: release.assets.map(asset => ({
          id: asset.id,
          name: asset.name,
          size: asset.size,
          download_count: asset.download_count,
          browser_download_url: asset.browser_download_url
        }))
      }));
    } catch (error) {
      logger.logError('Getting releases', error, { owner, repo });
      throw error;
    }
  }

  /**
   * Create a new release
   */
  async createRelease(owner, repo, tagName, releaseName, body, draft = false, prerelease = false) {
    try {
      const response = await axios.post(`${this.apiUrl}/repos/${owner}/${repo}/releases`, {
        tag_name: tagName,
        name: releaseName,
        body: body,
        draft: draft,
        prerelease: prerelease
      }, {
        headers: this.headers
      });

      logger.logOperation('Release created', {
        owner,
        repo,
        tagName,
        releaseName
      });

      return {
        id: response.data.id,
        tag_name: response.data.tag_name,
        name: response.data.name,
        body: response.data.body,
        draft: response.data.draft,
        prerelease: response.data.prerelease,
        created_at: response.data.created_at,
        published_at: response.data.published_at
      };
    } catch (error) {
      logger.logError('Creating release', error, {
        owner,
        repo,
        tagName,
        releaseName
      });
      throw error;
    }
  }

  /**
   * Create a tag using gh CLI
   */
  async createTag(repoPath, tagName, message = null) {
    try {
      const tagMessage = message || `Release ${tagName}`;
      
      // Create and push the tag
      await execAsync(`cd ${repoPath} && git tag -a "${tagName}" -m "${tagMessage}"`);
      await execAsync(`cd ${repoPath} && git push origin "${tagName}"`);
      
      logger.logOperation('Tag created and pushed', {
        repoPath,
        tagName,
        message: tagMessage
      });

      return {
        success: true,
        tagName,
        message: tagMessage,
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      logger.logError('Creating tag', error, {
        repoPath,
        tagName,
        message
      });
      throw error;
    }
  }

  /**
   * Get repository topics
   */
  async getTopics(owner, repo) {
    try {
      const response = await axios.get(`${this.apiUrl}/repos/${owner}/${repo}/topics`, {
        headers: {
          ...this.headers,
          'Accept': 'application/vnd.github.mercy-preview+json'
        }
      });

      return response.data.names || [];
    } catch (error) {
      logger.logError('Getting topics', error, { owner, repo });
      throw error;
    }
  }

  /**
   * Update repository topics
   */
  async updateTopics(owner, repo, topics) {
    try {
      const response = await axios.put(`${this.apiUrl}/repos/${owner}/${repo}/topics`, {
        names: topics
      }, {
        headers: {
          ...this.headers,
          'Accept': 'application/vnd.github.mercy-preview+json'
        }
      });

      logger.logOperation('Topics updated', {
        owner,
        repo,
        topics
      });

      return response.data.names || [];
    } catch (error) {
      logger.logError('Updating topics', error, {
        owner,
        repo,
        topics
      });
      throw error;
    }
  }

  /**
   * Get repository dependencies
   */
  async getDependencies(owner, repo) {
    try {
      const response = await axios.get(`${this.apiUrl}/repos/${owner}/${repo}/dependency-graph/sbom`, {
        headers: {
          ...this.headers,
          'Accept': 'application/vnd.github.v4+json'
        }
      });

      return response.data;
    } catch (error) {
      // Dependencies endpoint might not be available for all repositories
      logger.warn('Could not get dependencies', { owner, repo, error: error.message });
      return null;
    }
  }

  /**
   * Get repository security alerts
   */
  async getSecurityAlerts(owner, repo) {
    try {
      const response = await axios.get(`${this.apiUrl}/repos/${owner}/${repo}/vulnerability-alerts`, {
        headers: {
          ...this.headers,
          'Accept': 'application/vnd.github.vixen-preview+json'
        }
      });

      return response.data;
    } catch (error) {
      // Security alerts endpoint might not be available for all repositories
      logger.warn('Could not get security alerts', { owner, repo, error: error.message });
      return null;
    }
  }

  /**
   * Enable security alerts
   */
  async enableSecurityAlerts(owner, repo) {
    try {
      await axios.put(`${this.apiUrl}/repos/${owner}/${repo}/vulnerability-alerts`, {}, {
        headers: {
          ...this.headers,
          'Accept': 'application/vnd.github.vixen-preview+json'
        }
      });

      logger.logOperation('Security alerts enabled', { owner, repo });
      return { success: true };
    } catch (error) {
      logger.logError('Enabling security alerts', error, { owner, repo });
      throw error;
    }
  }

  /**
   * Get repository workflows
   */
  async getWorkflows(owner, repo) {
    try {
      const response = await axios.get(`${this.apiUrl}/repos/${owner}/${repo}/actions/workflows`, {
        headers: this.headers
      });

      return response.data.workflows.map(workflow => ({
        id: workflow.id,
        name: workflow.name,
        path: workflow.path,
        state: workflow.state,
        created_at: workflow.created_at,
        updated_at: workflow.updated_at
      }));
    } catch (error) {
      logger.logError('Getting workflows', error, { owner, repo });
      throw error;
    }
  }

  /**
   * Trigger a workflow
   */
  async triggerWorkflow(owner, repo, workflowId, ref = 'main', inputs = {}) {
    try {
      const response = await axios.post(`${this.apiUrl}/repos/${owner}/${repo}/actions/workflows/${workflowId}/dispatches`, {
        ref: ref,
        inputs: inputs
      }, {
        headers: this.headers
      });

      logger.logOperation('Workflow triggered', {
        owner,
        repo,
        workflowId,
        ref,
        inputs
      });

      return { success: true, status: response.status };
    } catch (error) {
      logger.logError('Triggering workflow', error, {
        owner,
        repo,
        workflowId,
        ref,
        inputs
      });
      throw error;
    }
  }

  /**
   * Get repository statistics
   */
  async getStats(owner, repo) {
    try {
      const [contributors, commits, codeFrequency] = await Promise.all([
        axios.get(`${this.apiUrl}/repos/${owner}/${repo}/stats/contributors`, { headers: this.headers }),
        axios.get(`${this.apiUrl}/repos/${owner}/${repo}/stats/commit_activity`, { headers: this.headers }),
        axios.get(`${this.apiUrl}/repos/${owner}/${repo}/stats/code_frequency`, { headers: this.headers })
      ]);

      return {
        contributors: contributors.data || [],
        commit_activity: commits.data || [],
        code_frequency: codeFrequency.data || []
      };
    } catch (error) {
      logger.logError('Getting repository stats', error, { owner, repo });
      throw error;
    }
  }
}

module.exports = GitHubService;
