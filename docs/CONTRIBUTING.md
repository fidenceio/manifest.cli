# 🤝 Contributing to Manifest CLI

**A powerful CLI tool for versioning, AI documenting, and repository operations.**

Thank you for your interest in contributing to Manifest CLI! This guide will help you get started with contributing to the project.

## 🎯 What We're Building

Manifest CLI is an intelligent command-line interface that automates and streamlines software release workflows. We're building a tool that combines:

- **Version Management**: Semantic versioning with automatic bumps
- **AI Documentation**: Intelligent generation of release notes and changelogs
- **Repository Operations**: Git workflow automation and synchronization
- **Timestamp Verification**: Trusted NTP-based timestamps for compliance
- **Homebrew Integration**: Automatic formula updates and maintenance

### **Current State**
The tool is production-ready with core functionality for automated releases, documentation generation, and repository management.

### **Future Vision**
We're building towards a comprehensive platform that includes:
- **Advanced AI Integration**: Machine learning for intelligent workflow optimization
- **Plugin Ecosystem**: Extensible architecture for community contributions
- **Cloud-Native Features**: Multi-cloud deployment and infrastructure automation
- **Enterprise Security**: Advanced compliance and security features
- **Team Collaboration**: Multi-user workflows and approval processes

## 🚀 Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Git** 2.20+ installed and configured
- **Node.js** 16.0+ (for package.json support)
- **Bash** 4.0+ (for advanced features)
- **Docker** (optional, for testing in different environments)
- A **GitHub account** for contributing

### Development Setup

1. **Fork the repository**
   ```bash
   # Fork on GitHub first, then clone your fork
   git clone https://github.com/YOUR_USERNAME/manifest.cli.git
   cd manifest.cli
   ```

2. **Set up upstream remote**
   ```bash
   git remote add upstream https://github.com/fidenceio/manifest.cli.git
   git fetch upstream
   ```

3. **Install development dependencies**
   ```bash
   # Install the CLI locally
   ./install-cli.sh
   
   # Verify installation
   manifest --version
   ```

4. **Create a development branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 🏗️ Project Structure

```
manifest.cli/
├── src/cli/                   # CLI source code
│   ├── manifest-cli.sh        # Main entry point
│   ├── manifest-cli-wrapper.sh # Installation wrapper
│   └── modules/               # Modular components
│       ├── manifest-core.sh   # Workflow orchestration
│       ├── manifest-git.sh    # Git operations
│       ├── manifest-ntp.sh    # NTP timestamp service
│       ├── manifest-docs.sh   # Documentation generation
│       ├── manifest-os.sh     # OS detection & optimization
│       └── manifest-test.sh   # Testing framework
├── docs/                      # Documentation
├── scripts/                   # Utility scripts
├── Formula/                   # Homebrew formula
├── install-cli.sh            # Installation script
└── package.json              # Project metadata
```

## 🔧 Development Guidelines

### Code Style

#### Bash Scripts
- Use **4 spaces** for indentation (no tabs)
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use descriptive variable names
- Add comprehensive comments for complex logic
- Include error handling for all external commands

#### Example Bash Style
```bash
#!/bin/bash

# Manifest Module: Example Module
# Handles example functionality with proper error handling

# Configuration
EXAMPLE_TIMEOUT=${EXAMPLE_TIMEOUT:-30}
EXAMPLE_RETRIES=${EXAMPLE_RETRIES:-3}

# Main function with proper error handling
example_function() {
    local input="$1"
    
    # Validate input
    if [[ -z "$input" ]]; then
        echo "❌ Input parameter required" >&2
        return 1
    fi
    
    # Process with error handling
    if ! process_input "$input"; then
        echo "❌ Failed to process input: $input" >&2
        return 1
    fi
    
    echo "✅ Input processed successfully"
    return 0
}
```

#### Documentation
- Use **Markdown** for all documentation
- Follow consistent formatting and structure
- Include code examples for all features
- Use emojis sparingly but effectively
- Keep documentation up-to-date with code changes

### Testing Requirements

#### Before Submitting
- **Run all tests**: `manifest test all`
- **Test your changes**: Create test cases for new functionality
- **Cross-platform testing**: Test on macOS and Linux if possible
- **Integration testing**: Test with real Git repositories

#### Test Coverage
- **Unit tests**: Test individual functions
- **Integration tests**: Test module interactions
- **End-to-end tests**: Test complete workflows
- **Error handling**: Test failure scenarios

#### Example Test Structure
```bash
# In manifest-test.sh
test_new_feature() {
    echo "🧪 Testing new feature..."
    
    # Test basic functionality
    if ! manifest new-feature "test-input"; then
        echo "   ❌ Basic functionality failed"
        return 1
    fi
    
    # Test error handling
    if manifest new-feature "" 2>/dev/null; then
        echo "   ❌ Error handling failed"
        return 1
    fi
    
    echo "   ✅ New feature tests passed"
    return 0
}
```

### Git Workflow

#### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```bash
# Format: type(scope): description
feat(ntp): add support for custom NTP servers
fix(git): resolve authentication issues with SSH keys
docs(readme): update installation instructions
test(core): add comprehensive workflow tests
refactor(docs): simplify template generation logic
```

#### Branch Naming
- `feature/description`: New features
- `fix/description`: Bug fixes
- `docs/description`: Documentation updates
- `test/description`: Testing improvements
- `refactor/description`: Code refactoring

#### Pull Request Process
1. **Create feature branch** from `main`
2. **Make focused changes** with clear commits
3. **Add tests** for new functionality
4. **Update documentation** if needed
5. **Run all tests** before submitting
6. **Create descriptive PR** with clear title and description

## 🌟 Areas for Contribution

### High Priority
- **Error Handling**: Improve error messages and recovery
- **Testing**: Expand test coverage and add integration tests
- **Documentation**: Enhance user guides and examples
- **Cross-platform**: Improve Windows and BSD support

### Medium Priority
- **Performance**: Optimize slow operations
- **Configuration**: Add more customization options
- **Integration**: Support for more CI/CD platforms
- **Monitoring**: Add logging and metrics

### Low Priority
- **UI/UX**: Improve command output formatting
- **Plugins**: Plugin system for extensibility
- **API**: REST API for remote operations
- **GUI**: Web-based interface

### Specific Ideas
- **NTP Improvements**: Add more NTP servers and protocols
- **Git Enhancements**: Support for more Git workflows
- **Documentation**: AI-powered commit message generation
- **Validation**: Enhanced input validation and sanitization
- **Security**: Security audit and vulnerability scanning

## 🧪 Testing Your Changes

### Local Testing
```bash
# Run basic tests
manifest test

# Run comprehensive tests
manifest test all

# Test specific components
manifest test ntp
manifest test git
manifest test docs
```

### Integration Testing
```bash
# Test with real repository
mkdir test-repo && cd test-repo
git init
echo "1.0.0" > VERSION
git add . && git commit -m "Initial commit"

# Test workflow
manifest go --dry-run
```

### Cross-platform Testing
```bash
# Test on different OS (if available)
# macOS: Use local environment
# Linux: Use Docker or WSL
# Windows: Use WSL2 or Git Bash

# Docker example for Linux testing
docker run -it --rm -v $(pwd):/app ubuntu:20.04 bash
cd /app && ./install-cli.sh
```

## 📝 Documentation Updates

### When to Update Documentation
- **New features**: Add usage examples and API reference
- **Breaking changes**: Update migration guides
- **Bug fixes**: Update troubleshooting sections
- **Configuration changes**: Update configuration guides

### Documentation Standards
- **Clear examples**: Include copy-paste examples
- **Screenshots**: Add visual aids for complex workflows
- **Cross-references**: Link related documentation
- **Version notes**: Document version-specific changes

## 🔍 Code Review Process

### Review Checklist
- [ ] **Code quality**: Follows style guidelines
- [ ] **Functionality**: Implements requirements correctly
- [ ] **Testing**: Includes appropriate tests
- [ ] **Documentation**: Updates relevant documentation
- [ ] **Error handling**: Proper error handling and validation
- [ ] **Performance**: No obvious performance issues
- [ ] **Security**: No security vulnerabilities
- [ ] **Compatibility**: Works across supported platforms

### Review Guidelines
- **Be constructive**: Provide helpful feedback
- **Ask questions**: Clarify unclear code
- **Suggest alternatives**: Offer better approaches
- **Test thoroughly**: Verify the changes work
- **Respect contributors**: Be kind and professional

## 🚀 Release Process

### Version Bumping
- **Patch**: Bug fixes and minor improvements
- **Minor**: New features (backward compatible)
- **Major**: Breaking changes

### Release Checklist
- [ ] **Update version** in VERSION and package.json
- [ ] **Generate changelog** with `manifest docs`
- [ ] **Run all tests** to ensure stability
- [ ] **Update documentation** for new features
- [ ] **Create release notes** on GitHub
- [ ] **Update Homebrew formula** if needed

## 🐛 Bug Reports

### Before Reporting
1. **Check existing issues** for duplicates
2. **Try latest version** from main branch
3. **Reproduce the issue** with minimal steps
4. **Check documentation** for solutions

### Bug Report Template
```markdown
## Bug Description
Brief description of the issue

## Steps to Reproduce
1. Step 1
2. Step 2
3. Step 3

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Environment
- OS: [e.g., macOS 12.0]
- CLI Version: [e.g., 8.6.7]
- Git Version: [e.g., 2.35.0]
- Node Version: [e.g., 18.0.0]

## Additional Information
Any other relevant details
```

## 💡 Feature Requests

### Feature Request Guidelines
- **Clear description** of the feature
- **Use case** and problem it solves
- **Implementation ideas** if you have them
- **Priority level** (low/medium/high)
- **Related issues** or existing features

### Feature Request Template
```markdown
## Feature Description
Brief description of the requested feature

## Problem Statement
What problem does this feature solve?

## Proposed Solution
How should this feature work?

## Use Cases
When would this feature be useful?

## Alternatives Considered
What other approaches were considered?

## Additional Context
Any other relevant information
```

## 🤝 Community Guidelines

### Code of Conduct
- **Be respectful** to all contributors
- **Welcome newcomers** and help them get started
- **Provide constructive feedback** on contributions
- **Respect different perspectives** and approaches
- **Follow project conventions** and guidelines

### Communication Channels
- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and general discussion
- **Pull Requests**: Code contributions and reviews
- **GitHub Actions**: CI/CD and automated testing

## 📚 Learning Resources

### Bash Scripting
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [Advanced Bash-Scripting Guide](https://tldp.org/LDP/abs/html/)

### Git
- [Git Documentation](https://git-scm.com/doc)
- [GitHub Guides](https://guides.github.com/)
- [Conventional Commits](https://www.conventionalcommits.org/)

### Testing
- [Shell Script Testing](https://github.com/kward/shunit2)
- [BATS Core](https://github.com/bats-core/bats-core)
- [Test-Driven Development](https://en.wikipedia.org/wiki/Test-driven_development)

## 🎉 Recognition

### Contributors
- **Code contributors** are listed in [CONTRIBUTORS.md](CONTRIBUTORS.md)
- **Documentation contributors** are acknowledged in docs
- **Bug reporters** are thanked in issue responses
- **Reviewers** are recognized for their feedback

### Contribution Levels
- **Bronze**: 1-5 contributions
- **Silver**: 6-20 contributions
- **Gold**: 21+ contributions
- **Platinum**: Major features or long-term contributors

## 📞 Getting Help

### Questions and Support
- **GitHub Discussions**: General questions and help
- **GitHub Issues**: Specific problems or bugs
- **Documentation**: Check existing guides first
- **Community**: Ask in discussions for guidance

### Mentorship
- **New contributors**: We're happy to mentor newcomers
- **Code reviews**: Detailed feedback on your contributions
- **Pair programming**: Collaborate on complex features
- **Documentation**: Help improve guides and examples

---

**Thank you for contributing to Manifest CLI! 🚀**

*Together, we're building the future of automated software releases.*
