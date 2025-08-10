const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');
const axios = require('axios');
const { logger } = require('../utils/logger');

const execAsync = promisify(exec);

class UpdateChecker {
  constructor() {
    this.npmRegistry = 'https://registry.npmjs.org';
    this.pypiRegistry = 'https://pypi.org/pypi';
    this.dockerHub = 'https://hub.docker.com/v2';
  }

  /**
   * Check for updates in a repository
   */
  async checkRepositoryUpdates(repoPath) {
    try {
      logger.logOperation('Checking repository updates', { repoPath });
      
      const results = {
        npm: null,
        python: null,
        docker: null,
        git: null,
        security: null,
        timestamp: new Date().toISOString()
      };

      // Check npm dependencies
      try {
        results.npm = await this.checkNpmUpdates(repoPath);
      } catch (error) {
        logger.warn('Could not check npm updates', { repoPath, error: error.message });
      }

      // Check Python dependencies
      try {
        results.python = await this.checkPythonUpdates(repoPath);
      } catch (error) {
        logger.warn('Could not check Python updates', { repoPath, error: error.message });
      }

      // Check Docker images
      try {
        results.docker = await this.checkDockerUpdates(repoPath);
      } catch (error) {
        logger.warn('Could not check Docker updates', { repoPath, error: error.message });
      }

      // Check Git repository status
      try {
        results.git = await this.checkGitStatus(repoPath);
      } catch (error) {
        logger.warn('Could not check Git status', { repoPath, error: error.message });
      }

      // Check security vulnerabilities
      try {
        results.security = await this.checkSecurityUpdates(repoPath);
      } catch (error) {
        logger.warn('Could not check security updates', { repoPath, error: error.message });
      }

      logger.logOperation('Repository update check completed', { repoPath, results });
      return results;
    } catch (error) {
      logger.logError('Checking repository updates', error, { repoPath });
      throw error;
    }
  }

  /**
   * Check npm dependencies for updates
   */
  async checkNpmUpdates(repoPath) {
    try {
      const packageJsonPath = path.join(repoPath, 'package.json');
      const packageLockPath = path.join(repoPath, 'package-lock.json');
      
      // Check if package.json exists
      try {
        await fs.access(packageJsonPath);
      } catch (error) {
        return { available: false, reason: 'No package.json found' };
      }

      // Read package.json
      const packageJson = JSON.parse(await fs.readFile(packageJsonPath, 'utf8'));
      const dependencies = { ...packageJson.dependencies, ...packageJson.devDependencies };
      
      if (!dependencies || Object.keys(dependencies).length === 0) {
        return { available: false, reason: 'No dependencies found' };
      }

      // Check for outdated packages
      const { stdout } = await execAsync('npm outdated --json', { cwd: repoPath });
      const outdated = JSON.parse(stdout);

      // Get current and latest versions
      const updates = [];
      for (const [packageName, info] of Object.entries(outdated)) {
        const currentVersion = dependencies[packageName];
        const latestVersion = info.latest;
        const current = info.current;
        const wanted = info.wanted;

        updates.push({
          package: packageName,
          current: current,
          wanted: wanted,
          latest: latestVersion,
          location: info.location,
          type: this.getDependencyType(packageName, packageJson),
          updateType: this.determineUpdateType(current, latestVersion)
        });
      }

      // Check for security vulnerabilities
      let securityIssues = [];
      try {
        const { stdout: auditOutput } = await execAsync('npm audit --json', { cwd: repoPath });
        const audit = JSON.parse(auditOutput);
        securityIssues = audit.vulnerabilities ? Object.values(audit.vulnerabilities) : [];
      } catch (error) {
        // npm audit might fail if there are no vulnerabilities
        securityIssues = [];
      }

      return {
        available: true,
        dependencies: Object.keys(dependencies).length,
        outdated: Object.keys(outdated).length,
        updates: updates,
        security: {
          vulnerabilities: securityIssues.length,
          issues: securityIssues
        }
      };
    } catch (error) {
      logger.logError('Checking npm updates', error, { repoPath });
      throw error;
    }
  }

  /**
   * Check Python dependencies for updates
   */
  async checkPythonUpdates(repoPath) {
    try {
      const requirementsPath = path.join(repoPath, 'requirements.txt');
      const pyprojectPath = path.join(repoPath, 'pyproject.toml');
      
      let dependencies = [];

      // Check requirements.txt
      try {
        const requirements = await fs.readFile(requirementsPath, 'utf8');
        dependencies = this.parseRequirementsTxt(requirements);
      } catch (error) {
        // requirements.txt doesn't exist
      }

      // Check pyproject.toml
      try {
        const pyproject = await fs.readFile(pyprojectPath, 'utf8');
        const pyprojectDeps = this.parsePyprojectToml(pyproject);
        dependencies = [...dependencies, ...pyprojectDeps];
      } catch (error) {
        // pyproject.toml doesn't exist
      }

      if (dependencies.length === 0) {
        return { available: false, reason: 'No Python dependencies found' };
      }

      // Check for updates using pip
      const updates = [];
      for (const dep of dependencies) {
        try {
          const latestVersion = await this.getPyPiLatestVersion(dep.package);
          if (latestVersion && dep.version && latestVersion !== dep.version) {
            updates.push({
              package: dep.package,
              current: dep.version,
              latest: latestVersion,
              updateType: this.determineUpdateType(dep.version, latestVersion)
            });
          }
        } catch (error) {
          logger.warn(`Could not check version for ${dep.package}`, { error: error.message });
        }
      }

      return {
        available: true,
        dependencies: dependencies.length,
        outdated: updates.length,
        updates: updates
      };
    } catch (error) {
      logger.logError('Checking Python updates', error, { repoPath });
      throw error;
    }
  }

  /**
   * Check Docker images for updates
   */
  async checkDockerUpdates(repoPath) {
    try {
      const dockerfilePath = path.join(repoPath, 'Dockerfile');
      const dockerComposePath = path.join(repoPath, 'docker-compose.yml');
      
      let images = [];

      // Check Dockerfile
      try {
        const dockerfile = await fs.readFile(dockerfilePath, 'utf8');
        const dockerfileImages = this.parseDockerfile(dockerfile);
        images = [...images, ...dockerfileImages];
      } catch (error) {
        // Dockerfile doesn't exist
      }

      // Check docker-compose.yml
      try {
        const dockerCompose = await fs.readFile(dockerComposePath, 'utf8');
        const composeImages = this.parseDockerCompose(dockerCompose);
        images = [...images, ...composeImages];
      } catch (error) {
        // docker-compose.yml doesn't exist
      }

      if (images.length === 0) {
        return { available: false, reason: 'No Docker images found' };
      }

      // Check for updates
      const updates = [];
      for (const image of images) {
        try {
          const latestTag = await this.getDockerHubLatestTag(image.name);
          if (latestTag && image.tag && latestTag !== image.tag) {
            updates.push({
              image: image.name,
              current: image.tag,
              latest: latestTag,
              updateType: this.determineUpdateType(image.tag, latestTag)
            });
          }
        } catch (error) {
          logger.warn(`Could not check version for ${image.name}`, { error: error.message });
        }
      }

      return {
        available: true,
        images: images.length,
        outdated: updates.length,
        updates: updates
      };
    } catch (error) {
      logger.logError('Checking Docker updates', error, { repoPath });
      throw error;
    }
  }

  /**
   * Check Git repository status
   */
  async checkGitStatus(repoPath) {
    try {
      const { stdout: status } = await execAsync('git status --porcelain', { cwd: repoPath });
      const { stdout: branch } = await execAsync('git branch --show-current', { cwd: repoPath });
      const { stdout: remote } = await execAsync('git remote -v', { cwd: repoPath });
      const { stdout: log } = await execAsync('git log --oneline -5', { cwd: repoPath });

      const hasChanges = status.trim().length > 0;
      const currentBranch = branch.trim();
      const remotes = remote.split('\n').filter(r => r.trim()).map(r => {
        const [name, url] = r.split('\t');
        return { name: name.trim(), url: url.trim() };
      });

      return {
        available: true,
        currentBranch,
        hasChanges,
        changes: hasChanges ? status.split('\n').filter(l => l.trim()) : [],
        remotes,
        recentCommits: log.split('\n').filter(l => l.trim()).map(commit => {
          const [hash, ...message] = commit.split(' ');
          return { hash, message: message.join(' ') };
        })
      };
    } catch (error) {
      logger.logError('Checking Git status', error, { repoPath });
      throw error;
    }
  }

  /**
   * Check for security updates
   */
  async checkSecurityUpdates(repoPath) {
    try {
      const results = {
        npm: null,
        python: null,
        docker: null,
        os: null
      };

      // Check npm security
      try {
        const { stdout } = await execAsync('npm audit --json', { cwd: repoPath });
        const audit = JSON.parse(stdout);
        results.npm = {
          vulnerabilities: audit.vulnerabilities ? Object.keys(audit.vulnerabilities).length : 0,
          details: audit.vulnerabilities || {}
        };
      } catch (error) {
        // npm audit might fail
      }

      // Check Python security (using safety if available)
      try {
        const { stdout } = await execAsync('safety check --json', { cwd: repoPath });
        const safety = JSON.parse(stdout);
        results.python = {
          vulnerabilities: safety.length || 0,
          details: safety
        };
      } catch (error) {
        // safety might not be installed
      }

      // Check Docker security
      try {
        const { stdout } = await execAsync('docker scout cves --format json', { cwd: repoPath });
        const dockerSecurity = JSON.parse(stdout);
        results.docker = {
          vulnerabilities: dockerSecurity.vulnerabilities?.length || 0,
          details: dockerSecurity
        };
      } catch (error) {
        // Docker Scout might not be available
      }

      return results;
    } catch (error) {
      logger.logError('Checking security updates', error, { repoPath });
      throw error;
    }
  }

  /**
   * Parse requirements.txt
   */
  parseRequirementsTxt(content) {
    const lines = content.split('\n');
    const dependencies = [];

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith('#')) {
        const match = trimmed.match(/^([a-zA-Z0-9_-]+)([<>=!~]+(.+))?$/);
        if (match) {
          dependencies.push({
            package: match[1],
            version: match[3] || 'latest',
            constraint: match[2] || ''
          });
        }
      }
    }

    return dependencies;
  }

  /**
   * Parse pyproject.toml
   */
  parsePyprojectToml(content) {
    const dependencies = [];
    
    // Simple regex parsing - in production you might want a proper TOML parser
    const depsMatch = content.match(/dependencies\s*=\s*\[([\s\S]*?)\]/);
    if (depsMatch) {
      const depsContent = depsMatch[1];
      const deps = depsContent.match(/"([^"]+)"\s*=\s*"([^"]+)"/g);
      if (deps) {
        deps.forEach(dep => {
          const match = dep.match(/"([^"]+)"\s*=\s*"([^"]+)"/);
          if (match) {
            dependencies.push({
              package: match[1],
              version: match[2]
            });
          }
        });
      }
    }

    return dependencies;
  }

  /**
   * Parse Dockerfile
   */
  parseDockerfile(content) {
    const images = [];
    const lines = content.split('\n');

    for (const line of lines) {
      if (line.trim().startsWith('FROM')) {
        const parts = line.trim().split(/\s+/);
        if (parts.length >= 2) {
          const image = parts[1];
          const [name, tag] = image.split(':');
          images.push({
            name: name,
            tag: tag || 'latest'
          });
        }
      }
    }

    return images;
  }

  /**
   * Parse docker-compose.yml
   */
  parseDockerCompose(content) {
    const images = [];
    
    try {
      const compose = yaml.load(content);
      if (compose.services) {
        Object.values(compose.services).forEach(service => {
          if (service.image) {
            const [name, tag] = service.image.split(':');
            images.push({
              name: name,
              tag: tag || 'latest'
            });
          }
        });
      }
    } catch (error) {
      logger.warn('Could not parse docker-compose.yml', { error: error.message });
    }

    return images;
  }

  /**
   * Get latest version from PyPI
   */
  async getPyPiLatestVersion(packageName) {
    try {
      const response = await axios.get(`${this.pypiRegistry}/${packageName}/json`);
      return response.data.info.version;
    } catch (error) {
      return null;
    }
  }

  /**
   * Get latest tag from Docker Hub
   */
  async getDockerHubLatestTag(imageName) {
    try {
      const response = await axios.get(`${this.dockerHub}/repositories/${imageName}/tags/latest/`);
      return response.data.name;
    } catch (error) {
      return null;
    }
  }

  /**
   * Get dependency type
   */
  getDependencyType(packageName, packageJson) {
    if (packageJson.dependencies && packageJson.dependencies[packageName]) {
      return 'dependencies';
    } else if (packageJson.devDependencies && packageJson.devDependencies[packageName]) {
      return 'devDependencies';
    } else if (packageJson.peerDependencies && packageJson.peerDependencies[packageName]) {
      return 'peerDependencies';
    } else if (packageJson.optionalDependencies && packageJson.optionalDependencies[packageName]) {
      return 'optionalDependencies';
    }
    return 'unknown';
  }

  /**
   * Determine update type
   */
  determineUpdateType(current, latest) {
    if (!current || !latest) return 'unknown';
    
    const currentParts = current.split('.').map(Number);
    const latestParts = latest.split('.').map(Number);
    
    if (latestParts[0] > currentParts[0]) return 'major';
    if (latestParts[1] > currentParts[1]) return 'minor';
    if (latestParts[2] > currentParts[2]) return 'patch';
    
    return 'none';
  }
}

module.exports = UpdateChecker;
