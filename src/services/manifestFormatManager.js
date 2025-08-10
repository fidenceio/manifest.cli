const fs = require('fs').promises;
const path = require('path');
const yaml = require('js-yaml');
const { logger } = require('../utils/logger');

class ManifestFormatManager {
  constructor() {
    this.manifestFormats = {
      // Node.js ecosystem
      'package.json': {
        type: 'json',
        versionPath: 'version',
        namePath: 'name',
        descriptionPath: 'description',
        dependenciesPath: 'dependencies',
        devDependenciesPath: 'devDependencies',
        scriptsPath: 'scripts'
      },
      
      // Python ecosystem
      'pyproject.toml': {
        type: 'toml',
        versionPath: 'project.version',
        namePath: 'project.name',
        descriptionPath: 'project.description',
        dependenciesPath: 'project.dependencies',
        devDependenciesPath: 'project.optional-dependencies'
      },
      'setup.py': {
        type: 'python',
        versionPath: 'version',
        namePath: 'name',
        descriptionPath: 'description',
        dependenciesPath: 'install_requires'
      },
      'requirements.txt': {
        type: 'requirements',
        versionPath: null, // No version in requirements.txt
        namePath: null,
        descriptionPath: null,
        dependenciesPath: 'all'
      },
      
      // Rust ecosystem
      'Cargo.toml': {
        type: 'toml',
        versionPath: 'package.version',
        namePath: 'package.name',
        descriptionPath: 'package.description',
        dependenciesPath: 'dependencies'
      },
      
      // Go ecosystem
      'go.mod': {
        type: 'go',
        versionPath: 'module', // Go uses module path
        namePath: 'module',
        descriptionPath: null,
        dependenciesPath: 'require'
      },
      
      // PHP ecosystem
      'composer.json': {
        type: 'json',
        versionPath: 'version',
        namePath: 'name',
        descriptionPath: 'description',
        dependenciesPath: 'require',
        devDependenciesPath: 'require-dev'
      },
      
      // Ruby ecosystem
      'Gemfile': {
        type: 'ruby',
        versionPath: null,
        namePath: null,
        descriptionPath: null,
        dependenciesPath: 'gems'
      },
      
      // Java ecosystem
      'pom.xml': {
        type: 'xml',
        versionPath: 'version',
        namePath: 'artifactId',
        descriptionPath: 'description',
        dependenciesPath: 'dependencies.dependency'
      },
      
      // .NET ecosystem
      '*.csproj': {
        type: 'xml',
        versionPath: 'PropertyGroup.Version',
        namePath: 'PropertyGroup.AssemblyName',
        descriptionPath: 'PropertyGroup.Description',
        dependenciesPath: 'ItemGroup.PackageReference'
      },
      
      // Universal format
      'VERSION': {
        type: 'plain',
        versionPath: 'content',
        namePath: null,
        descriptionPath: null,
        dependenciesPath: null
      },
      
      // Docker ecosystem
      'Dockerfile': {
        type: 'docker',
        versionPath: 'LABEL version',
        namePath: 'LABEL name',
        descriptionPath: 'LABEL description',
        dependenciesPath: 'FROM'
      }
    };
  }

  /**
   * Detect manifest format for a repository
   */
  async detectManifestFormat(repoPath) {
    try {
      logger.logOperation('Detecting manifest format', { repoPath });
      
      const detectedFormats = [];
      
      for (const [filename, format] of Object.entries(this.manifestFormats)) {
        if (filename.includes('*')) {
          // Handle wildcard patterns
          const pattern = filename.replace('*', '');
          const files = await this.findFilesByPattern(repoPath, pattern);
          if (files.length > 0) {
            detectedFormats.push({
              filename: files[0],
              format: { ...format, pattern: filename }
            });
          }
        } else {
          const filePath = path.join(repoPath, filename);
          try {
            await fs.access(filePath);
            detectedFormats.push({ filename, format });
          } catch (error) {
            // File doesn't exist
          }
        }
      }
      
      // Sort by priority (VERSION file first, then package.json, etc.)
      const priorityOrder = ['VERSION', 'package.json', 'pyproject.toml', 'setup.py'];
      detectedFormats.sort((a, b) => {
        const aPriority = priorityOrder.indexOf(a.filename);
        const bPriority = priorityOrder.indexOf(b.filename);
        return (aPriority === -1 ? 999 : aPriority) - (bPriority === -1 ? 999 : bPriority);
      });
      
      logger.logOperation('Manifest format detected', { repoPath, formats: detectedFormats });
      return detectedFormats;
    } catch (error) {
      logger.logError('Detecting manifest format', error, { repoPath });
      throw error;
    }
  }

  /**
   * Extract metadata from manifest file
   */
  async extractMetadata(repoPath, manifestInfo) {
    try {
      const { filename, format } = manifestInfo;
      const filePath = path.join(repoPath, filename);
      
      logger.logOperation('Extracting metadata', { repoPath, filename, format });
      
      let metadata = {};
      
      switch (format.type) {
        case 'json':
          metadata = await this.extractFromJson(filePath, format);
          break;
        case 'toml':
          metadata = await this.extractFromToml(filePath, format);
          break;
        case 'xml':
          metadata = await this.extractFromXml(filePath, format);
          break;
        case 'python':
          metadata = await this.extractFromPython(filePath, format);
          break;
        case 'requirements':
          metadata = await this.extractFromRequirements(filePath, format);
          break;
        case 'go':
          metadata = await this.extractFromGo(filePath, format);
          break;
        case 'ruby':
          metadata = await this.extractFromRuby(filePath, format);
          break;
        case 'docker':
          metadata = await this.extractFromDocker(filePath, format);
          break;
        case 'plain':
          metadata = await this.extractFromPlain(filePath, format);
          break;
        default:
          throw new Error(`Unsupported manifest format: ${format.type}`);
      }
      
      // Add format information
      metadata.manifestFormat = format.type;
      metadata.manifestFile = filename;
      
      logger.logOperation('Metadata extracted successfully', { repoPath, metadata });
      return metadata;
    } catch (error) {
      logger.logError('Extracting metadata', error, { repoPath, manifestInfo });
      throw error;
    }
  }

  /**
   * Extract from JSON files (package.json, composer.json)
   */
  async extractFromJson(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    const data = JSON.parse(content);
    
    return {
      version: this.getNestedValue(data, format.versionPath),
      name: this.getNestedValue(data, format.namePath),
      description: this.getNestedValue(data, format.descriptionPath),
      dependencies: this.getNestedValue(data, format.dependenciesPath),
      devDependencies: this.getNestedValue(data, format.devDependenciesPath),
      scripts: this.getNestedValue(data, format.scriptsPath)
    };
  }

  /**
   * Extract from TOML files (pyproject.toml, Cargo.toml)
   */
  async extractFromToml(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    const data = yaml.load(content);
    
    return {
      version: this.getNestedValue(data, format.versionPath),
      name: this.getNestedValue(data, format.namePath),
      description: this.getNestedValue(data, format.descriptionPath),
      dependencies: this.getNestedValue(data, format.dependenciesPath),
      devDependencies: this.getNestedValue(data, format.devDependenciesPath)
    };
  }

  /**
   * Extract from XML files (pom.xml, *.csproj)
   */
  async extractFromXml(filePath, format) {
    // For now, return basic info - XML parsing would need additional dependencies
    const content = await fs.readFile(filePath, 'utf8');
    
    return {
      version: this.extractXmlValue(content, format.versionPath),
      name: this.extractXmlValue(content, format.namePath),
      description: this.extractXmlValue(content, format.descriptionPath),
      dependencies: this.extractXmlDependencies(content, format.dependenciesPath)
    };
  }

  /**
   * Extract from Python setup.py
   */
  async extractFromPython(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    
    return {
      version: this.extractPythonValue(content, format.versionPath),
      name: this.extractPythonValue(content, format.namePath),
      description: this.extractPythonValue(content, format.descriptionPath),
      dependencies: this.extractPythonDependencies(content, format.dependenciesPath)
    };
  }

  /**
   * Extract from requirements.txt
   */
  async extractFromRequirements(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    const lines = content.split('\n').filter(line => line.trim() && !line.startsWith('#'));
    
    return {
      dependencies: lines.map(line => {
        const [package, version] = line.split('==');
        return { package: package.trim(), version: version ? version.trim() : 'latest' };
      })
    };
  }

  /**
   * Extract from Go go.mod
   */
  async extractFromGo(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    const lines = content.split('\n');
    
    let moduleName = '';
    const dependencies = [];
    
    for (const line of lines) {
      if (line.startsWith('module ')) {
        moduleName = line.replace('module ', '').trim();
      } else if (line.startsWith('require ')) {
        const parts = line.replace('require ', '').trim().split(' ');
        if (parts.length >= 2) {
          dependencies.push({
            package: parts[0],
            version: parts[1]
          });
        }
      }
    }
    
    return {
      name: moduleName,
      dependencies
    };
  }

  /**
   * Extract from Ruby Gemfile
   */
  async extractFromRuby(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    const lines = content.split('\n').filter(line => line.trim() && !line.startsWith('#'));
    
    const dependencies = lines.map(line => {
      if (line.includes('gem ')) {
        const match = line.match(/gem\s+['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]+)['"])?/);
        if (match) {
          return {
            package: match[1],
            version: match[2] || 'latest'
          };
        }
      }
      return null;
    }).filter(Boolean);
    
    return { dependencies };
  }

  /**
   * Extract from Dockerfile
   */
  async extractFromDocker(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    const lines = content.split('\n');
    
    let version = '';
    let name = '';
    let description = '';
    const dependencies = [];
    
    for (const line of lines) {
      if (line.startsWith('LABEL ')) {
        const labelMatch = line.match(/LABEL\s+([^=]+)=["']([^'"]+)["']/);
        if (labelMatch) {
          const [_, key, value] = labelMatch;
          switch (key.toLowerCase()) {
            case 'version':
              version = value;
              break;
            case 'name':
              name = value;
              break;
            case 'description':
              description = value;
              break;
          }
        }
      } else if (line.startsWith('FROM ')) {
        const fromMatch = line.match(/FROM\s+([^\s]+)/);
        if (fromMatch) {
          dependencies.push({
            package: 'base-image',
            version: fromMatch[1]
          });
        }
      }
    }
    
    return { version, name, description, dependencies };
  }

  /**
   * Extract from plain text files (VERSION)
   */
  async extractFromPlain(filePath, format) {
    const content = await fs.readFile(filePath, 'utf8');
    
    return {
      version: content.trim()
    };
  }

  /**
   * Helper: Get nested value from object
   */
  getNestedValue(obj, path) {
    if (!path) return null;
    
    const keys = path.split('.');
    let value = obj;
    
    for (const key of keys) {
      if (value && typeof value === 'object' && key in value) {
        value = value[key];
      } else {
        return null;
      }
    }
    
    return value;
  }

  /**
   * Helper: Extract value from XML content
   */
  extractXmlValue(content, path) {
    if (!path) return null;
    
    const keys = path.split('.');
    let pattern = content;
    
    for (const key of keys) {
      const regex = new RegExp(`<${key}[^>]*>(.*?)</${key}>`, 's');
      const match = pattern.match(regex);
      if (match) {
        pattern = match[1];
      } else {
        return null;
      }
    }
    
    return pattern.trim();
  }

  /**
   * Helper: Extract dependencies from XML
   */
  extractXmlDependencies(content, path) {
    if (!path) return null;
    
    const dependencies = [];
    const regex = /<dependency>.*?<groupId>(.*?)<\/groupId>.*?<artifactId>(.*?)<\/artifactId>.*?<version>(.*?)<\/version>.*?<\/dependency>/gs;
    
    let match;
    while ((match = regex.exec(content)) !== null) {
      dependencies.push({
        groupId: match[1],
        artifactId: match[2],
        version: match[3]
      });
    }
    
    return dependencies;
  }

  /**
   * Helper: Extract value from Python content
   */
  extractPythonValue(content, path) {
    if (!path) return null;
    
    const regex = new RegExp(`${path}\\s*=\\s*["']([^"']+)["']`, 's');
    const match = content.match(regex);
    return match ? match[1] : null;
  }

  /**
   * Helper: Extract dependencies from Python content
   */
  extractPythonDependencies(content, path) {
    if (!path) return null;
    
    const dependencies = [];
    const regex = /install_requires\s*=\s*\[(.*?)\]/s;
    const match = content.match(regex);
    
    if (match) {
      const depsString = match[1];
      const deps = depsString.split(',').map(dep => dep.trim().replace(/["']/g, ''));
      dependencies.push(...deps);
    }
    
    return dependencies;
  }

  /**
   * Helper: Find files by pattern
   */
  async findFilesByPattern(repoPath, pattern) {
    // This is a simplified version - in production you'd want to use glob patterns
    const files = [];
    try {
      const items = await fs.readdir(repoPath);
      for (const item of items) {
        if (item.endsWith(pattern)) {
          files.push(item);
        }
      }
    } catch (error) {
      // Directory doesn't exist or can't be read
    }
    return files;
  }

  /**
   * Generate universal manifest format
   */
  generateUniversalManifest(metadata, format) {
    return {
      name: metadata.name || 'unknown',
      version: metadata.version || '0.0.0',
      description: metadata.description || '',
      manifestFormat: format.type,
      manifestFile: format.filename,
      dependencies: metadata.dependencies || [],
      devDependencies: metadata.devDependencies || [],
      scripts: metadata.scripts || {},
      metadata: metadata,
      timestamp: new Date().toISOString(),
      manifestVersion: '1.0.0'
    };
  }
}

module.exports = { ManifestFormatManager };
