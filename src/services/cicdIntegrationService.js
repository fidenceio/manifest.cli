const fs = require('fs').promises;
const path = require('path');
const { logger } = require('../utils/logger');

class CICDIntegrationService {
  constructor() {
    this.platforms = {
      github: {
        name: 'GitHub Actions',
        configFiles: ['.github/workflows/*.yml', '.github/workflows/*.yaml'],
        webhookPath: '/webhooks/github',
        eventTypes: ['push', 'pull_request', 'release', 'workflow_run']
      },
      gitlab: {
        name: 'GitLab CI',
        configFiles: ['.gitlab-ci.yml'],
        webhookPath: '/webhooks/gitlab',
        eventTypes: ['push', 'merge_request', 'tag_push', 'pipeline']
      },
      jenkins: {
        name: 'Jenkins',
        configFiles: ['Jenkinsfile', 'Jenkinsfile.*'],
        webhookPath: '/webhooks/jenkins',
        eventTypes: ['build', 'deploy', 'test']
      },
      circleci: {
        name: 'CircleCI',
        configFiles: ['.circleci/config.yml'],
        webhookPath: '/webhooks/circleci',
        eventTypes: ['workflow', 'job', 'build']
      },
      travis: {
        name: 'Travis CI',
        configFiles: ['.travis.yml'],
        webhookPath: '/webhooks/travis',
        eventTypes: ['build', 'deploy']
      },
      azure: {
        name: 'Azure DevOps',
        configFiles: ['azure-pipelines.yml', 'azure-pipelines.yaml'],
        webhookPath: '/webhooks/azure',
        eventTypes: ['build', 'release', 'pull_request']
      },
      bitbucket: {
        name: 'Bitbucket Pipelines',
        configFiles: ['bitbucket-pipelines.yml'],
        webhookPath: '/webhooks/bitbucket',
        eventTypes: ['push', 'pull_request', 'tag']
      }
    };
  }

  /**
   * Detect CI/CD platform in repository
   */
  async detectCICDPlatform(repoPath) {
    try {
      logger.logOperation('Detecting CI/CD platform', { repoPath });
      
      const detectedPlatforms = [];
      
      for (const [platformKey, platform] of Object.entries(this.platforms)) {
        const hasConfig = await this.hasPlatformConfig(repoPath, platform);
        if (hasConfig) {
          detectedPlatforms.push({
            platform: platformKey,
            name: platform.name,
            configFiles: await this.findConfigFiles(repoPath, platform.configFiles)
          });
        }
      }
      
      logger.logOperation('CI/CD platforms detected', { repoPath, platforms: detectedPlatforms });
      return detectedPlatforms;
    } catch (error) {
      logger.logError('Detecting CI/CD platform', error, { repoPath });
      throw error;
    }
  }

  /**
   * Check if repository has platform-specific configuration
   */
  async hasPlatformConfig(repoPath, platform) {
    for (const pattern of platform.configFiles) {
      const files = await this.findConfigFiles(repoPath, [pattern]);
      if (files.length > 0) {
        return true;
      }
    }
    return false;
  }

  /**
   * Find configuration files matching patterns
   */
  async findConfigFiles(repoPath, patterns) {
    const foundFiles = [];
    
    for (const pattern of patterns) {
      if (pattern.includes('*')) {
        // Handle wildcard patterns
        const [dir, filePattern] = pattern.split('*');
        const fullDir = path.join(repoPath, dir);
        
        try {
          const items = await fs.readdir(fullDir);
          for (const item of items) {
            if (item.endsWith(filePattern)) {
              foundFiles.push(path.join(dir, item));
            }
          }
        } catch (error) {
          // Directory doesn't exist
        }
      } else {
        // Exact file path
        const filePath = path.join(repoPath, pattern);
        try {
          await fs.access(filePath);
          foundFiles.push(pattern);
        } catch (error) {
          // File doesn't exist
        }
      }
    }
    
    return foundFiles;
  }

  /**
   * Generate CI/CD integration configuration
   */
  async generateCICDConfig(repoPath, platform, manifestData) {
    try {
      logger.logOperation('Generating CI/CD config', { repoPath, platform, manifestData });
      
      const config = await this.generatePlatformSpecificConfig(platform, manifestData);
      
      logger.logOperation('CI/CD config generated', { repoPath, platform, config });
      return config;
    } catch (error) {
      logger.logError('Generating CI/CD config', error, { repoPath, platform, manifestData });
      throw error;
    }
  }

  /**
   * Generate platform-specific CI/CD configuration
   */
  async generatePlatformSpecificConfig(platform, manifestData) {
    switch (platform) {
      case 'github':
        return this.generateGitHubActionsConfig(manifestData);
      case 'gitlab':
        return this.generateGitLabCIConfig(manifestData);
      case 'jenkins':
        return this.generateJenkinsConfig(manifestData);
      case 'circleci':
        return this.generateCircleCIConfig(manifestData);
      case 'travis':
        return this.generateTravisConfig(manifestData);
      case 'azure':
        return this.generateAzureConfig(manifestData);
      case 'bitbucket':
        return this.generateBitbucketConfig(manifestData);
      default:
        throw new Error(`Unsupported CI/CD platform: ${platform}`);
    }
  }

  /**
   * Generate GitHub Actions workflow
   */
  generateGitHubActionsConfig(manifestData) {
    return {
      name: 'Manifest Integration',
      on: {
        push: { branches: ['main', 'master'] },
        pull_request: { branches: ['main', 'master'] },
        release: { types: ['published'] }
      },
      jobs: {
        'manifest-sync': {
          'runs-on': 'ubuntu-latest',
          steps: [
            {
              name: 'Checkout code',
              uses: 'actions/checkout@v4'
            },
            {
              name: 'Setup Node.js',
              uses: 'actions/setup-node@v4',
              with: {
                'node-version': '18'
              }
            },
            {
              name: 'Install dependencies',
              run: 'npm ci'
            },
            {
              name: 'Sync with Manifest',
              run: 'npm run manifest:sync',
              env: {
                MANIFEST_URL: '${{ secrets.MANIFEST_URL }}',
                MANIFEST_TOKEN: '${{ secrets.MANIFEST_TOKEN }}',
                REPO_NAME: '${{ github.repository }}',
                BRANCH: '${{ github.ref_name }}'
              }
            }
          ]
        }
      }
    };
  }

  /**
   * Generate GitLab CI configuration
   */
  generateGitLabCIConfig(manifestData) {
    return {
      stages: ['build', 'test', 'manifest-sync'],
      variables:
        MANIFEST_URL: '$MANIFEST_URL',
        MANIFEST_TOKEN: '$MANIFEST_TOKEN'
      },
      'manifest-sync':
        stage: 'manifest-sync',
        image: 'node:18-alpine',
        script:
          - 'npm ci'
          - 'npm run manifest:sync'
        only:
          - main
          - master
          - tags
        environment:
          name: 'manifest-sync'
        variables:
          REPO_NAME: '$CI_PROJECT_PATH'
          BRANCH: '$CI_COMMIT_REF_NAME'
    };
  }

  /**
   * Generate Jenkins pipeline
   */
  generateJenkinsConfig(manifestData) {
    return {
      pipeline: {
        agent: 'any',
        stages: [
          {
            stage: 'Build',
            steps: [
              'sh "npm ci"',
              'sh "npm run build"'
            ]
          },
          {
            stage: 'Test',
            steps: [
              'sh "npm test"'
            ]
          },
          {
            stage: 'Manifest Sync',
            steps: [
              'sh "npm run manifest:sync"',
              'sh "curl -X POST $MANIFEST_URL/api/v1/sync -H \\"Authorization: Bearer $MANIFEST_TOKEN\\" -d \\"repo=$REPO_NAME&branch=$BRANCH\\""'
            ]
          }
        ],
        post: {
          always: [
            'cleanWs()'
          ]
        }
      }
    };
  }

  /**
   * Generate CircleCI configuration
   */
  generateCircleCIConfig(manifestData) {
    return {
      version: '2.1',
      orbs: {
        node: 'circleci/node@5.1.0'
      },
      jobs: {
        'manifest-sync': {
          docker: [
            {
              image: 'cimg/node:18.17'
            }
          ],
          steps: [
            'checkout',
            'node/install-packages',
            {
              run: 'npm run manifest:sync'
            }
          ]
        }
      },
      workflows: {
        version: 2,
        'manifest-workflow': {
          jobs: [
            'manifest-sync'
          ]
        }
      }
    };
  }

  /**
   * Generate Travis CI configuration
   */
  generateTravisConfig(manifestData) {
    return {
      language: 'node_js',
      node_js: ['18'],
      branches: {
        only: ['main', 'master']
      },
      script: [
        'npm ci',
        'npm test',
        'npm run manifest:sync'
      ],
      after_success: [
        'curl -X POST $MANIFEST_URL/api/v1/sync -H "Authorization: Bearer $MANIFEST_TOKEN" -d "repo=$TRAVIS_REPO_SLUG&branch=$TRAVIS_BRANCH"'
      ],
      env: {
        global: [
          'MANIFEST_URL=$MANIFEST_URL',
          'MANIFEST_TOKEN=$MANIFEST_TOKEN'
        ]
      }
    };
  }

  /**
   * Generate Azure DevOps configuration
   */
  generateAzureConfig(manifestData) {
    return {
      trigger:
        - main
        - master
      variables:
        - name: MANIFEST_URL
          value: '$(MANIFEST_URL)'
        - name: MANIFEST_TOKEN
          value: '$(MANIFEST_TOKEN)'
      stages:
        - stage: Build
          displayName: 'Build and Test'
          jobs:
            - job: Build
              pool:
                vmImage: 'ubuntu-latest'
              steps:
                - task: NodeTool@0
                  inputs:
                    versionSpec: '18.x'
                - script: 'npm ci'
                - script: 'npm test'
                - script: 'npm run manifest:sync'
                  env:
                    MANIFEST_URL: $(MANIFEST_URL)
                    MANIFEST_TOKEN: $(MANIFEST_TOKEN)
    };
  }

  /**
   * Generate Bitbucket Pipelines configuration
   */
  generateBitbucketConfig(manifestData) {
    return {
      image: 'node:18',
      pipelines:
        branches:
          main:
            - step:
                name: 'Build and Test'
                caches:
                  - node
                script:
                  - 'npm ci'
                  - 'npm test'
                  - 'npm run manifest:sync'
                artifacts:
                  - dist/**
          master:
            - step:
                name: 'Build and Test'
                caches:
                  - node
                script:
                  - 'npm ci'
                  - 'npm test'
                  - 'npm run manifest:sync'
                artifacts:
                  - dist/**
        tags:
          '*':
            - step:
                name: 'Release'
                caches:
                  - node
                script:
                  - 'npm ci'
                  - 'npm run manifest:sync'
                  - 'npm run release'
      definitions:
        caches:
          node: 'node_modules'
    };
  }

  /**
   * Create webhook endpoint for CI/CD platforms
   */
  createWebhookEndpoint(platform, eventType, payload) {
    try {
      logger.logOperation('Processing webhook', { platform, eventType, payload });
      
      // Process webhook based on platform and event type
      const result = this.processWebhookEvent(platform, eventType, payload);
      
      logger.logOperation('Webhook processed', { platform, eventType, result });
      return result;
    } catch (error) {
      logger.logError('Processing webhook', error, { platform, eventType, payload });
      throw error;
    }
  }

  /**
   * Process webhook events from different platforms
   */
  processWebhookEvent(platform, eventType, payload) {
    switch (platform) {
      case 'github':
        return this.processGitHubWebhook(eventType, payload);
      case 'gitlab':
        return this.processGitLabWebhook(eventType, payload);
      case 'jenkins':
        return this.processJenkinsWebhook(eventType, payload);
      case 'circleci':
        return this.processCircleCIWebhook(eventType, payload);
      case 'travis':
        return this.processTravisWebhook(eventType, payload);
      case 'azure':
        return this.processAzureWebhook(eventType, payload);
      case 'bitbucket':
        return this.processBitbucketWebhook(eventType, payload);
      default:
        throw new Error(`Unsupported platform: ${platform}`);
    }
  }

  /**
   * Process GitHub webhook events
   */
  processGitHubWebhook(eventType, payload) {
    switch (eventType) {
      case 'push':
        return {
          action: 'sync_repository',
          repository: payload.repository.full_name,
          branch: payload.ref.replace('refs/heads/', ''),
          commit: payload.head_commit.id,
          timestamp: payload.head_commit.timestamp
        };
      case 'pull_request':
        return {
          action: 'review_pull_request',
          repository: payload.repository.full_name,
          pr_number: payload.pull_request.number,
          title: payload.pull_request.title,
          state: payload.pull_request.state
        };
      case 'release':
        return {
          action: 'process_release',
          repository: payload.repository.full_name,
          version: payload.release.tag_name,
          title: payload.release.name,
          body: payload.release.body
        };
      default:
        return { action: 'unknown_event', eventType, payload };
    }
  }

  /**
   * Process GitLab webhook events
   */
  processGitLabWebhook(eventType, payload) {
    switch (eventType) {
      case 'push':
        return {
          action: 'sync_repository',
          repository: payload.project.path_with_namespace,
          branch: payload.ref.replace('refs/heads/', ''),
          commit: payload.after,
          timestamp: new Date().toISOString()
        };
      case 'merge_request':
        return {
          action: 'review_merge_request',
          repository: payload.project.path_with_namespace,
          mr_id: payload.object_attributes.iid,
          title: payload.object_attributes.title,
          state: payload.object_attributes.state
        };
      case 'tag_push':
        return {
          action: 'process_tag',
          repository: payload.project.path_with_namespace,
          tag: payload.ref.replace('refs/tags/', ''),
          commit: payload.after
        };
      default:
        return { action: 'unknown_event', eventType, payload };
    }
  }

  /**
   * Process Jenkins webhook events
   */
  processJenkinsWebhook(eventType, payload) {
    switch (eventType) {
      case 'build':
        return {
          action: 'build_completed',
          job_name: payload.name,
          build_number: payload.number,
          status: payload.status,
          timestamp: new Date().toISOString()
        };
      case 'deploy':
        return {
          action: 'deployment_completed',
          job_name: payload.name,
          environment: payload.environment,
          status: payload.status,
          timestamp: new Date().toISOString()
        };
      default:
        return { action: 'unknown_event', eventType, payload };
    }
  }

  /**
   * Process CircleCI webhook events
   */
  processCircleCIWebhook(eventType, payload) {
    switch (eventType) {
      case 'workflow':
        return {
          action: 'workflow_completed',
          workflow_name: payload.workflow.name,
          status: payload.workflow.status,
          repository: payload.project.name,
          branch: payload.workflow.branch
        };
      case 'job':
        return {
          action: 'job_completed',
          job_name: payload.job.name,
          status: payload.job.status,
          workflow: payload.workflow.name
        };
      default:
        return { action: 'unknown_event', eventType, payload };
    }
  }

  /**
   * Process Travis CI webhook events
   */
  processTravisWebhook(eventType, payload) {
    switch (eventType) {
      case 'build':
        return {
          action: 'build_completed',
          build_id: payload.build.id,
          status: payload.build.state,
          repository: payload.repository.slug,
          branch: payload.build.branch
        };
      case 'deploy':
        return {
          action: 'deployment_completed',
          deployment_id: payload.deployment.id,
          status: payload.deployment.state,
          environment: payload.deployment.environment
        };
      default:
        return { action: 'unknown_event', eventType, payload };
    }
  }

  /**
   * Process Azure DevOps webhook events
   */
  processAzureWebhook(eventType, payload) {
    switch (eventType) {
      case 'build':
        return {
          action: 'build_completed',
          build_id: payload.id,
          status: payload.status,
          definition_name: payload.definition.name,
          repository: payload.repository.name
        };
      case 'release':
        return {
          action: 'release_completed',
          release_id: payload.id,
          status: payload.status,
          definition_name: payload.releaseDefinition.name,
          environment: payload.environment.name
        };
      case 'pull_request':
        return {
          action: 'pull_request_updated',
          pr_id: payload.id,
          status: payload.status,
          title: payload.title,
          repository: payload.repository.name
        };
      default:
        return { action: 'unknown_event', eventType, payload };
    }
  }

  /**
   * Process Bitbucket webhook events
   */
  processBitbucketWebhook(eventType, payload) {
    switch (eventType) {
      case 'push':
        return {
          action: 'sync_repository',
          repository: payload.repository.name,
          branch: payload.push.changes[0].new.name,
          commit: payload.push.changes[0].new.target.hash,
          timestamp: new Date().toISOString()
        };
      case 'pull_request':
        return {
          action: 'review_pull_request',
          repository: payload.repository.name,
          pr_id: payload.pullrequest.id,
          title: payload.pullrequest.title,
          state: payload.pullrequest.state
        };
      case 'tag':
        return {
          action: 'process_tag',
          repository: payload.repository.name,
          tag: payload.push.changes[0].new.name,
          commit: payload.push.changes[0].new.target.hash
        };
      default:
        return { action: 'unknown_event', eventType, payload };
    }
  }

  /**
   * Generate webhook configuration for a platform
   */
  generateWebhookConfig(platform, baseUrl) {
    const platformConfig = this.platforms[platform];
    if (!platformConfig) {
      throw new Error(`Unsupported platform: ${platform}`);
    }

    return {
      platform,
      name: platformConfig.name,
      webhookUrl: `${baseUrl}${platformConfig.webhookPath}`,
      eventTypes: platformConfig.eventTypes,
      headers: this.getWebhookHeaders(platform),
      samplePayload: this.getSamplePayload(platform)
    };
  }

  /**
   * Get webhook headers for a platform
   */
  getWebhookHeaders(platform) {
    const headers = {
      'Content-Type': 'application/json'
    };

    switch (platform) {
      case 'github':
        headers['X-GitHub-Event'] = '{{event_type}}';
        headers['X-Hub-Signature-256'] = 'sha256={{signature}}';
        break;
      case 'gitlab':
        headers['X-Gitlab-Event'] = '{{event_type}}';
        headers['X-Gitlab-Token'] = '{{token}}';
        break;
      case 'jenkins':
        headers['X-Jenkins-Event'] = '{{event_type}}';
        break;
      case 'circleci':
        headers['X-Circle-Event'] = '{{event_type}}';
        break;
      case 'travis':
        headers['X-Travis-Event'] = '{{event_type}}';
        break;
      case 'azure':
        headers['X-Azure-Event'] = '{{event_type}}';
        break;
      case 'bitbucket':
        headers['X-Event-Key'] = '{{event_type}}';
        break;
    }

    return headers;
  }

  /**
   * Get sample payload for a platform
   */
  getSamplePayload(platform) {
    // Return sample payload structure for testing
    return {
      platform,
      event_type: 'push',
      timestamp: new Date().toISOString(),
      repository: 'example/repo',
      branch: 'main',
      commit: 'abc123...'
    };
  }
}

module.exports = { CICDIntegrationService };
