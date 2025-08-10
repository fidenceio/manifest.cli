const fs = require('fs').promises;
const path = require('path');
const { logger } = require('../utils/logger');

class InstallScriptGenerator {
  constructor() {
    this.platforms = {
      linux: {
        name: 'Linux',
        extensions: ['.sh'],
        shebang: '#!/bin/bash',
        packageManager: 'apt-get',
        dockerInstall: 'curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh',
        dockerComposeInstall: 'curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose'
      },
      macos: {
        name: 'macOS',
        extensions: ['.sh'],
        shebang: '#!/bin/bash',
        packageManager: 'brew',
        dockerInstall: 'brew install --cask docker',
        dockerComposeInstall: 'brew install docker-compose'
      },
      windows: {
        name: 'Windows',
        extensions: ['.ps1', '.bat'],
        shebang: null,
        packageManager: 'choco',
        dockerInstall: 'choco install docker-desktop',
        dockerComposeInstall: 'choco install docker-compose'
      },
      alpine: {
        name: 'Alpine Linux',
        extensions: ['.sh'],
        shebang: '#!/bin/sh',
        packageManager: 'apk',
        dockerInstall: 'apk add docker',
        dockerComposeInstall: 'apk add docker-compose'
      },
      centos: {
        name: 'CentOS/RHEL',
        extensions: ['.sh'],
        shebang: '#!/bin/bash',
        packageManager: 'yum',
        dockerInstall: 'yum install -y docker && systemctl start docker && systemctl enable docker',
        dockerComposeInstall: 'curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose'
      },
      ubuntu: {
        name: 'Ubuntu/Debian',
        extensions: ['.sh'],
        shebang: '#!/bin/bash',
        packageManager: 'apt-get',
        dockerInstall: 'curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh',
        dockerComposeInstall: 'curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose'
      }
    };

    this.containerTypes = {
      docker: {
        name: 'Docker',
        configFile: 'docker-compose.yml',
        healthCheck: 'docker-compose ps',
        logs: 'docker-compose logs -f',
        restart: 'docker-compose restart',
        stop: 'docker-compose down',
        start: 'docker-compose up -d'
      },
      kubernetes: {
        name: 'Kubernetes',
        configFile: 'k8s-manifest.yml',
        healthCheck: 'kubectl get pods -l app=manifest',
        logs: 'kubectl logs -l app=manifest -f',
        restart: 'kubectl rollout restart deployment/manifest',
        stop: 'kubectl delete -f k8s-manifest.yml',
        start: 'kubectl apply -f k8s-manifest.yml'
      },
      podman: {
        name: 'Podman',
        configFile: 'podman-compose.yml',
        healthCheck: 'podman-compose ps',
        logs: 'podman-compose logs -f',
        restart: 'podman-compose restart',
        stop: 'podman-compose down',
        start: 'podman-compose up -d'
      }
    };
  }

  /**
   * Detect the current platform
   */
  async detectPlatform() {
    try {
      const platform = process.platform;
      const arch = process.arch;
      
      let detectedPlatform = 'linux';
      
      if (platform === 'darwin') {
        detectedPlatform = 'macos';
      } else if (platform === 'win32') {
        detectedPlatform = 'windows';
      } else if (platform === 'linux') {
        // Try to detect specific Linux distribution
        try {
          const osRelease = await fs.readFile('/etc/os-release', 'utf8');
          if (osRelease.includes('alpine')) {
            detectedPlatform = 'alpine';
          } else if (osRelease.includes('centos') || osRelease.includes('rhel')) {
            detectedPlatform = 'centos';
          } else if (osRelease.includes('ubuntu') || osRelease.includes('debian')) {
            detectedPlatform = 'ubuntu';
          }
        } catch (error) {
          // Default to generic Linux
          detectedPlatform = 'linux';
        }
      }
      
      logger.logOperation('Platform detected', { platform: detectedPlatform, arch });
      return detectedPlatform;
    } catch (error) {
      logger.logError('Detecting platform', error);
      return 'linux'; // Default fallback
    }
  }

  /**
   * Generate installation script for a specific platform and container type
   */
  async generateInstallScript(platform, containerType, options = {}) {
    try {
      logger.logOperation('Generating install script', { platform, containerType, options });
      
      const platformConfig = this.platforms[platform];
      const containerConfig = this.containerTypes[containerType];
      
      if (!platformConfig) {
        throw new Error(`Unsupported platform: ${platform}`);
      }
      
      if (!containerConfig) {
        throw new Error(`Unsupported container type: ${containerType}`);
      }
      
      const script = await this.generatePlatformSpecificScript(platform, containerType, options);
      
      logger.logOperation('Install script generated', { platform, containerType });
      return script;
    } catch (error) {
      logger.logError('Generating install script', error, { platform, containerType, options });
      throw error;
    }
  }

  /**
   * Generate platform-specific installation script
   */
  async generatePlatformSpecificScript(platform, containerType, options) {
    const platformConfig = this.platforms[platform];
    const containerConfig = this.containerTypes[containerType];
    
    let script = '';
    
    // Add shebang for Unix-like systems
    if (platformConfig.shebang) {
      script += `${platformConfig.shebang}\n\n`;
    }
    
    // Add script header
    script += this.generateScriptHeader(platform, containerType, options);
    
    // Add platform-specific setup
    script += this.generatePlatformSetup(platform, options);
    
    // Add container-specific setup
    script += this.generateContainerSetup(containerType, options);
    
    // Add Manifest-specific setup
    script += this.generateManifestSetup(containerType, options);
    
    // Add verification and health checks
    script += this.generateVerificationSteps(containerType, options);
    
    // Add cleanup and completion
    script += this.generateCompletionSteps(platform, containerType, options);
    
    return script;
  }

  /**
   * Generate script header with documentation
   */
  generateScriptHeader(platform, containerType, options) {
    const platformName = this.platforms[platform].name;
    const containerName = this.containerTypes[containerType].name;
    
    return `# Manifest Installation Script
# Platform: ${platformName}
# Container Type: ${containerName}
# Generated: ${new Date().toISOString()}
# 
# This script will install and configure Manifest in your ${platformName} environment
# using ${containerName} for containerization.
#
# Prerequisites:
# - ${platformName} system with internet access
# - User with sudo/administrator privileges
# - Minimum 2GB RAM and 10GB disk space
#
# Usage: ${this.getScriptExecutionCommand(platform, containerType)}
# Options: --help, --skip-deps, --skip-verify, --config <file>

set -e  # Exit on any error

# Configuration
MANIFEST_VERSION="${options.version || 'latest'}"
MANIFEST_PORT="${options.port || '3000'}"
MANIFEST_DATA_DIR="${options.dataDir || '/opt/manifest'}"
MANIFEST_CONFIG_FILE="${options.configFile || 'manifest-config.yml'}"
SKIP_DEPENDENCIES="${options.skipDependencies || 'false'}"
SKIP_VERIFICATION="${options.skipVerification || 'false'}"

# Colors for output
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
NC='\\033[0m' # No Color

# Logging functions
log_info() { echo -e "\${BLUE}[INFO]\${NC} \$1"; }
log_success() { echo -e "\${GREEN}[SUCCESS]\${NC} \$1"; }
log_warning() { echo -e "\${YELLOW}[WARNING]\${NC} \$1"; }
log_error() { echo -e "\${RED}[ERROR]\${NC} \$1"; }

# Parse command line arguments
while [[ \$# -gt 0 ]]; do
  case \$1 in
    --help)
      echo "Usage: \$0 [options]"
      echo "Options:"
      echo "  --help              Show this help message"
      echo "  --version <ver>     Specify Manifest version (default: latest)"
      echo "  --port <port>       Specify port (default: 3000)"
      echo "  --data-dir <dir>    Specify data directory (default: /opt/manifest)"
      echo "  --config <file>     Specify config file (default: manifest-config.yml)"
      echo "  --skip-deps         Skip dependency installation"
      echo "  --skip-verify       Skip verification steps"
      exit 0
      ;;
    --version)
      MANIFEST_VERSION="\$2"
      shift 2
      ;;
    --port)
      MANIFEST_PORT="\$2"
      shift 2
      ;;
    --data-dir)
      MANIFEST_DATA_DIR="\$2"
      shift 2
      ;;
    --config)
      MANIFEST_CONFIG_FILE="\$2"
      shift 2
      ;;
    --skip-deps)
      SKIP_DEPENDENCIES="true"
      shift
      ;;
    --skip-verify)
      SKIP_VERIFICATION="true"
      shift
      ;;
    *)
      log_error "Unknown option: \$1"
      exit 1
      ;;
  esac
done

log_info "Starting Manifest installation for ${platformName} with ${containerName}"
log_info "Version: \$MANIFEST_VERSION"
log_info "Port: \$MANIFEST_PORT"
log_info "Data Directory: \$MANIFEST_DATA_DIR"

`;
  }

  /**
   * Generate platform-specific setup steps
   */
  generatePlatformSetup(platform, options) {
    const platformConfig = this.platforms[platform];
    
    let setup = `
# Platform-specific setup for ${platformConfig.name}
log_info "Setting up platform dependencies for ${platformConfig.name}"

`;
    
    if (platform === 'windows') {
      setup += `
# Windows-specific setup
if [[ "\$OSTYPE" == "msys" || "\$OSTYPE" == "cygwin" ]]; then
  log_info "Detected Windows environment"
  
  # Check if running as administrator
  if ! net session >/dev/null 2>&1; then
    log_error "This script must be run as Administrator on Windows"
    exit 1
  fi
  
  # Install Chocolatey if not present
  if ! command -v choco >/dev/null 2>&1; then
    log_info "Installing Chocolatey package manager"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
  else
    log_info "Chocolatey already installed"
  fi
fi

`;
    } else {
      setup += `
# Check if running as root or with sudo
if [[ \$EUID -ne 0 ]]; then
  log_info "Requesting sudo privileges for system-wide installation"
  if ! sudo -n true 2>/dev/null; then
    log_error "This script requires sudo privileges"
    exit 1
  fi
fi

# Update package manager
log_info "Updating package manager"
`;
      
      if (platform === 'macos') {
        setup += `brew update\n`;
      } else if (platform === 'alpine') {
        setup += `sudo apk update\n`;
      } else if (platform === 'centos') {
        setup += `sudo yum update -y\n`;
      } else {
        setup += `sudo apt-get update\n`;
      }
    }
    
    return setup;
  }

  /**
   * Generate container-specific setup steps
   */
  generateContainerSetup(containerType, options) {
    const containerConfig = this.containerTypes[containerType];
    
    let setup = `
# Container setup for ${containerConfig.name}
log_info "Setting up ${containerConfig.name}"

`;
    
    if (containerType === 'docker') {
      setup += `
# Install Docker
if ! command -v docker >/dev/null 2>&1; then
  log_info "Installing Docker"
  ${this.platforms[process.platform === 'win32' ? 'windows' : 'linux'].dockerInstall}
  
  # Add current user to docker group (Linux/macOS)
  if [[ "\$OSTYPE" != "msys" && "\$OSTYPE" != "cygwin" ]]; then
    sudo usermod -aG docker \$USER
    log_warning "You may need to log out and back in for Docker group changes to take effect"
  fi
else
  log_info "Docker already installed"
fi

# Install Docker Compose
if ! command -v docker-compose >/dev/null 2>&1; then
  log_info "Installing Docker Compose"
  ${this.platforms[process.platform === 'win32' ? 'windows' : 'linux'].dockerComposeInstall}
else
  log_info "Docker Compose already installed"
fi

# Start Docker service
if [[ "\$OSTYPE" != "msys" && "\$OSTYPE" != "cygwin" ]]; then
  log_info "Starting Docker service"
  sudo systemctl start docker
  sudo systemctl enable docker
fi

# Verify Docker installation
log_info "Verifying Docker installation"
if ! docker --version >/dev/null 2>&1; then
  log_error "Docker installation failed"
  exit 1
fi

if ! docker-compose --version >/dev/null 2>&1; then
  log_error "Docker Compose installation failed"
  exit 1
fi

log_success "Docker and Docker Compose installed successfully"

`;
    } else if (containerType === 'kubernetes') {
      setup += `
# Install kubectl
if ! command -v kubectl >/dev/null 2>&1; then
  log_info "Installing kubectl"
  curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
else
  log_info "kubectl already installed"
fi

# Install minikube for local development (optional)
if [[ "\${INSTALL_MINIKUBE:-false}" == "true" ]]; then
  if ! command -v minikube >/dev/null 2>&1; then
    log_info "Installing minikube"
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
  fi
fi

`;
    } else if (containerType === 'podman') {
      setup += `
# Install Podman
if ! command -v podman >/dev/null 2>&1; then
  log_info "Installing Podman"
  if [[ "\$OSTYPE" == "darwin" ]]; then
    brew install podman
  else
    sudo apt-get install -y podman
  fi
else
  log_info "Podman already installed"
fi

# Install Podman Compose
if ! command -v podman-compose >/dev/null 2>&1; then
  log_info "Installing Podman Compose"
  pip3 install podman-compose
else
  log_info "Podman Compose already installed"
fi

`;
    }
    
    return setup;
  }

  /**
   * Generate Manifest container setup
   */
  generateManifestSetup(containerType, options) {
    const manifestConfig = {
      name: options.appName || 'my-app',
      version: options.appVersion || '1.0.0',
      description: options.appDescription || 'Application managed by Manifest',
      heartbeat: {
        enabled: true,
        interval: '5m',
        notifications: []
      },
      updates: {
        autoCheck: true,
        autoUpdate: false,
        channels: ['stable', 'beta']
      },
      cicd: {
        platforms: ['github', 'gitlab'],
        autoDeploy: false
      }
    };

    let setupScript = '';
    
    switch (containerType) {
      case 'docker':
        setupScript = this.generateDockerManifestSetup(manifestConfig, options);
        break;
      case 'kubernetes':
        setupScript = this.generateKubernetesManifestSetup(manifestConfig, options);
        break;
      case 'podman':
        setupScript = this.generatePodmanManifestSetup(manifestConfig, options);
        break;
      default:
        setupScript = this.generateDockerManifestSetup(manifestConfig, options);
    }

    return setupScript;
  }

  /**
   * Generate Docker Manifest setup
   */
  generateDockerManifestSetup(manifestConfig, options) {
    return `
# Manifest Container Setup for ${manifestConfig.name}
echo "Setting up Manifest container for ${manifestConfig.name}..."

# Create Manifest configuration directory
mkdir -p ./manifest-config

# Create Manifest configuration file
cat > ./manifest-config/manifest.json << 'EOF'
${JSON.stringify(manifestConfig, null, 2)}
EOF

# Create docker-compose.yml with Manifest integration
cat > ./docker-compose.yml << 'EOF'
version: '3.8'

services:
  ${manifestConfig.name}:
    build: .
    container_name: ${manifestConfig.name}
    ports:
      - "${options.appPort || '3000'}:${options.appPort || '3000'}"
    environment:
      - NODE_ENV=production
      - MANIFEST_ENABLED=true
      - MANIFEST_URL=http://manifest:3000
    volumes:
      - ./manifest-config:/app/manifest-config
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - manifest
    networks:
      - ${manifestConfig.name}-network

  manifest:
    image: fidenceio/manifest:latest
    container_name: manifest-service
    ports:
      - "3001:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - LOG_LEVEL=info
      - GITHUB_TOKEN=${options.githubToken || 'your_github_token'}
      - MANIFEST_SECRET=${options.manifestSecret || 'your_manifest_secret'}
    volumes:
      - ./manifest-config:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
      - ${options.sshPath || '~/.ssh'}:/root/.ssh:ro
      - ${options.gitConfigPath || '~/.gitconfig'}:/root/.gitconfig:ro
    networks:
      - ${manifestConfig.name}-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ${manifestConfig.name}-network:
    driver: bridge

volumes:
  manifest_data:
EOF

# Create .manifestrc file for local development
cat > ./.manifestrc << 'EOF'
{
  "versionStrategy": "semantic",
  "autoCommit": true,
  "autoTag": true,
  "changelog": true,
  "ci": {
    "platform": "github",
    "autoDeploy": false
  },
  "install": {
    "platform": "auto",
    "containerType": "docker"
  },
  "heartbeat": {
    "enabled": true,
    "interval": "5m",
    "notifications": []
  }
}
EOF

echo "Manifest configuration created successfully!"
echo "To start your application with Manifest:"
echo "  docker-compose up -d"
echo ""
echo "To access Manifest dashboard:"
echo "  http://localhost:3001"
echo ""
echo "To check Manifest health:"
echo "  curl http://localhost:3001/health"
`;
  }

  /**
   * Generate Kubernetes Manifest setup
   */
  generateKubernetesManifestSetup(manifestConfig, options) {
    return `
# Manifest Kubernetes Setup for ${manifestConfig.name}
echo "Setting up Manifest for Kubernetes deployment..."

# Create Manifest configuration directory
mkdir -p ./k8s-manifest

# Create Manifest configuration file
cat > ./k8s-manifest/manifest-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: manifest-config
  namespace: ${options.namespace || 'default'}
data:
  manifest.json: |
${JSON.stringify(manifestConfig, null, 2).split('\n').map(line => `    ${line}`).join('\n')}
EOF

# Create Kubernetes deployment with Manifest
cat > ./k8s-manifest/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${manifestConfig.name}
  namespace: ${options.namespace || 'default'}
spec:
  replicas: ${options.replicas || 1}
  selector:
    matchLabels:
      app: ${manifestConfig.name}
  template:
    metadata:
      labels:
        app: ${manifestConfig.name}
    spec:
      containers:
      - name: ${manifestConfig.name}
        image: ${manifestConfig.name}:latest
        ports:
        - containerPort: ${options.appPort || 3000}
        env:
        - name: NODE_ENV
          value: "production"
        - name: MANIFEST_ENABLED
          value: "true"
        - name: MANIFEST_URL
          value: "http://manifest-service:3000"
        volumeMounts:
        - name: manifest-config
          mountPath: /app/manifest-config
      - name: manifest
        image: fidenceio/manifest:latest
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
        - name: PORT
          value: "3000"
        - name: LOG_LEVEL
          value: "info"
        - name: GITHUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: manifest-secrets
              key: github-token
        - name: MANIFEST_SECRET
          valueFrom:
            secretKeyRef:
              name: manifest-secrets
              key: manifest-secret
        volumeMounts:
        - name: manifest-config
          mountPath: /app/data
      volumes:
      - name: manifest-config
        configMap:
          name: manifest-config
---
apiVersion: v1
kind: Service
metadata:
  name: ${manifestConfig.name}-service
  namespace: ${options.namespace || 'default'}
spec:
  selector:
    app: ${manifestConfig.name}
  ports:
  - port: ${options.appPort || 3000}
    targetPort: ${options.appPort || 3000}
    name: app
  - port: 3001
    targetPort: 3000
    name: manifest
---
apiVersion: v1
kind: Service
metadata:
  name: manifest-service
  namespace: ${options.namespace || 'default'}
spec:
  selector:
    app: ${manifestConfig.name}
  ports:
  - port: 3000
    targetPort: 3000
    name: manifest
EOF

# Create Kubernetes secrets template
cat > ./k8s-manifest/secrets.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: manifest-secrets
  namespace: ${options.namespace || 'default'}
type: Opaque
data:
  github-token: ${options.githubToken || 'eW91cl9naXRodWJfdG9rZW4='}  # base64 encoded
  manifest-secret: ${options.manifestSecret || 'eW91cl9tYW5pZmVzdF9zZWNyZXQ='}  # base64 encoded
EOF

# Create .manifestrc file for local development
cat > ./.manifestrc << 'EOF'
{
  "versionStrategy": "semantic",
  "autoCommit": true,
  "autoTag": true,
  "changelog": true,
  "ci": {
    "platform": "github",
    "autoDeploy": false
  },
  "install": {
    "platform": "auto",
    "containerType": "kubernetes"
  },
  "heartbeat": {
    "enabled": true,
    "interval": "5m",
    "notifications": []
  }
}
EOF

echo "Kubernetes Manifest configuration created successfully!"
echo "To deploy your application with Manifest:"
echo "  kubectl apply -f ./k8s-manifest/"
echo ""
echo "To check Manifest status:"
echo "  kubectl get pods -l app=${manifestConfig.name}"
echo "  kubectl logs -l app=${manifestConfig.name} -c manifest"
echo ""
echo "To access Manifest service:"
echo "  kubectl port-forward service/manifest-service 3001:3000"
`;
  }

  /**
   * Generate Podman Manifest setup
   */
  generatePodmanManifestSetup(manifestConfig, options) {
    return `
# Manifest Podman Setup for ${manifestConfig.name}
echo "Setting up Manifest for Podman deployment..."

# Create Manifest configuration directory
mkdir -p ./podman-manifest

# Create Manifest configuration file
cat > ./podman-manifest/manifest.json << 'EOF'
${JSON.stringify(manifestConfig, null, 2)}
EOF

# Create podman-compose.yml with Manifest integration
cat > ./podman-compose.yml << 'EOF'
version: '3.8'

services:
  ${manifestConfig.name}:
    build: .
    container_name: ${manifestConfig.name}
    ports:
      - "${options.appPort || '3000'}:${options.appPort || '3000'}"
    environment:
      - NODE_ENV=production
      - MANIFEST_ENABLED=true
      - MANIFEST_URL=http://manifest:3000
    volumes:
      - ./podman-manifest:/app/manifest-config
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - manifest
    networks:
      - ${manifestConfig.name}-network

  manifest:
    image: fidenceio/manifest:latest
    container_name: manifest-service
    ports:
      - "3001:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - LOG_LEVEL=info
      - GITHUB_TOKEN=${options.githubToken || 'your_github_token'}
      - MANIFEST_SECRET=${options.manifestSecret || 'your_manifest_secret'}
    volumes:
      - ./podman-manifest:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
      - ${options.sshPath || '~/.ssh'}:/root/.ssh:ro
      - ${options.gitConfigPath || '~/.gitconfig'}:/root/.gitconfig:ro
    networks:
      - ${manifestConfig.name}-network
    restart: unless-stopped

networks:
  ${manifestConfig.name}-network:
    driver: bridge

volumes:
  manifest_data:
EOF

# Create .manifestrc file for local development
cat > ./.manifestrc << 'EOF'
{
  "versionStrategy": "semantic",
  "autoCommit": true,
  "autoTag": true,
  "changelog": true,
  "ci": {
    "platform": "github",
    "autoDeploy": false
  },
  "install": {
    "platform": "auto",
    "containerType": "podman"
  },
  "heartbeat": {
    "enabled": true,
    "interval": "5m",
    "notifications": []
  }
}
EOF

echo "Podman Manifest configuration created successfully!"
echo "To start your application with Manifest:"
echo "  podman-compose up -d"
echo ""
echo "To access Manifest dashboard:"
echo "  http://localhost:3001"
echo ""
echo "To check Manifest health:"
echo "  curl http://localhost:3001/health"
`;
  }

  /**
   * Generate verification and health check steps
   */
  generateVerificationSteps(containerType, options) {
    const containerConfig = this.containerTypes[containerType];
    
    let verification = `
# Verification and health checks
log_info "Performing verification checks"

`;
    
    if (containerType === 'docker') {
      verification += `
# Check container status
log_info "Checking container status"
if docker-compose ps | grep -q "Up"; then
  log_success "All containers are running"
else
  log_error "Some containers failed to start"
  docker-compose logs
  exit 1
fi

# Check Manifest API health
log_info "Checking Manifest API health"
HEALTH_CHECK_ATTEMPTS=0
MAX_ATTEMPTS=30

while [[ \$HEALTH_CHECK_ATTEMPTS -lt \$MAX_ATTEMPTS ]]; do
  if curl -f "http://localhost:\$MANIFEST_PORT/health" >/dev/null 2>&1; then
    log_success "Manifest API is healthy"
    break
  fi
  
  HEALTH_CHECK_ATTEMPTS=\$((HEALTH_CHECK_ATTEMPTS + 1))
  log_info "Health check attempt \$HEALTH_CHECK_ATTEMPTS/\$MAX_ATTEMPTS"
  sleep 10
done

if [[ \$HEALTH_CHECK_ATTEMPTS -eq \$MAX_ATTEMPTS ]]; then
  log_error "Manifest API health check failed after \$MAX_ATTEMPTS attempts"
  docker-compose logs
  exit 1
fi

`;
    } else if (containerType === 'kubernetes') {
      verification += `
# Check pod status
log_info "Checking pod status"
if kubectl get pods -n manifest | grep -q "Running"; then
  log_success "All pods are running"
else
  log_error "Some pods failed to start"
  kubectl describe pods -n manifest
  kubectl logs -n manifest -l app=manifest
  exit 1
fi

# Check Manifest API health
log_info "Checking Manifest API health"
HEALTH_CHECK_ATTEMPTS=0
MAX_ATTEMPTS=30

while [[ \$HEALTH_CHECK_ATTEMPTS -lt \$MAX_ATTEMPTS ]]; do
  if kubectl exec -n manifest deployment/manifest -- curl -f "http://localhost:\$MANIFEST_PORT/health" >/dev/null 2>&1; then
    log_success "Manifest API is healthy"
    break
  fi
  
  HEALTH_CHECK_ATTEMPTS=\$((HEALTH_CHECK_ATTEMPTS + 1))
  log_info "Health check attempt \$HEALTH_CHECK_ATTEMPTS/\$MAX_ATTEMPTS"
  sleep 10
done

if [[ \$HEALTH_CHECK_ATTEMPTS -eq \$MAX_ATTEMPTS ]]; then
  log_error "Manifest API health check failed after \$MAX_ATTEMPTS attempts"
  kubectl logs -n manifest -l app=manifest
  exit 1
fi

`;
    }
    
    return verification;
  }

  /**
   * Generate completion and cleanup steps
   */
  generateCompletionSteps(platform, containerType, options) {
    const containerConfig = this.containerTypes[containerType];
    
    return `
# Installation completion
log_success "Manifest installation completed successfully!"

# Display service information
log_info "Service Information:"
log_info "  - URL: http://localhost:\$MANIFEST_PORT"
log_info "  - Health Check: http://localhost:\$MANIFEST_PORT/health"
log_info "  - Data Directory: \$MANIFEST_DATA_DIR"
log_info "  - Configuration: \$MANIFEST_CONFIG_DIR"

# Display management commands
log_info "Management Commands:"
log_info "  - View logs: ${containerConfig.logs}"
log_info "  - Check status: ${containerConfig.healthCheck}"
log_info "  - Restart: ${containerConfig.restart}"
log_info "  - Stop: ${containerConfig.stop}"
log_info "  - Start: ${containerConfig.start}"

# Create management script
MANAGEMENT_SCRIPT="\$MANIFEST_DATA_DIR/manifest-manage.sh"
log_info "Creating management script: \$MANAGEMENT_SCRIPT"

cat > "\$MANAGEMENT_SCRIPT" << 'EOF'
#!/bin/bash
# Manifest Management Script
# Usage: \$0 [start|stop|restart|status|logs|update]

MANIFEST_CONFIG_DIR="\$MANIFEST_DATA_DIR/config"
cd "\$MANIFEST_CONFIG_DIR"

case "\$1" in
  start)
    echo "Starting Manifest..."
    ${containerConfig.start}
    ;;
  stop)
    echo "Stopping Manifest..."
    ${containerConfig.stop}
    ;;
  restart)
    echo "Restarting Manifest..."
    ${containerConfig.restart}
    ;;
  status)
    echo "Manifest Status:"
    ${containerConfig.healthCheck}
    ;;
  logs)
    echo "Manifest Logs:"
    ${containerConfig.logs}
    ;;
  update)
    echo "Updating Manifest..."
    git pull origin main
    ${containerConfig.restart}
    ;;
  *)
    echo "Usage: \$0 [start|stop|restart|status|logs|update]"
    exit 1
    ;;
esac
EOF

chmod +x "\$MANAGEMENT_SCRIPT"

# Create systemd service (Linux only)
if [[ "\$OSTYPE" != "darwin" && "\$OSTYPE" != "msys" && "\$OSTYPE" != "cygwin" ]]; then
  log_info "Creating systemd service for auto-startup"
  
  sudo tee /etc/systemd/system/manifest.service > /dev/null << EOF
[Unit]
Description=Manifest Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=\$MANIFEST_CONFIG_DIR
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable manifest.service
  log_info "Systemd service created and enabled"
fi

# Final instructions
echo ""
log_success "🎉 Manifest is now installed and running!"
echo ""
log_info "Next steps:"
log_info "1. Open http://localhost:\$MANIFEST_PORT in your browser"
log_info "2. Configure your applications to connect to Manifest"
log_info "3. Set up webhooks for your CI/CD pipelines"
log_info "4. Use the management script: \$MANAGEMENT_SCRIPT"
echo ""
log_info "For support and documentation, visit:"
log_info "  https://github.com/kanizsa/manifest"
echo ""

`;
  }

  /**
   * Get script execution command for the platform
   */
  getScriptExecutionCommand(platform, containerType) {
    if (platform === 'windows') {
      return 'powershell -ExecutionPolicy Bypass -File install-manifest.ps1';
    } else {
      return 'bash install-manifest.sh';
    }
  }

  /**
   * Generate all installation scripts for a platform
   */
  async generateAllScripts(platform, options = {}) {
    try {
      const scripts = {};
      
      for (const [containerType, containerConfig] of Object.entries(this.containerTypes)) {
        const script = await this.generateInstallScript(platform, containerType, options);
        const extension = this.platforms[platform].extensions[0];
        const filename = `install-manifest-${containerType}${extension}`;
        
        scripts[filename] = {
          content: script,
          platform,
          containerType,
          extension
        };
      }
      
      return scripts;
    } catch (error) {
      logger.logError('Generating all scripts', error, { platform, options });
      throw error;
    }
  }

  /**
   * Save installation script to file
   */
  async saveScript(scriptContent, filename, targetPath) {
    try {
      const fullPath = path.join(targetPath, filename);
      await fs.writeFile(fullPath, scriptContent, 'utf8');
      
      // Make executable on Unix-like systems
      if (process.platform !== 'win32') {
        await fs.chmod(fullPath, 0o755);
      }
      
      logger.logOperation('Script saved', { filename, path: fullPath });
      return fullPath;
    } catch (error) {
      logger.logError('Saving script', error, { filename, targetPath });
      throw error;
    }
  }
}

module.exports = { InstallScriptGenerator };
