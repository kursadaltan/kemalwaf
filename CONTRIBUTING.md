# Contributing Guide

Thank you for your interest in contributing to kemal-waf! This document explains how you can contribute to the project.

## How Can You Contribute?

### Bug Reports

1. Create a new issue on GitHub Issues
2. Add a description of the bug, steps to reproduce, and expected behavior
3. If possible, add a minimal example that reproduces the bug

### Feature Requests

1. Create a new feature request on GitHub Issues
2. Explain the purpose of the feature and usage scenario
3. If there are alternative solutions, mention them as well

### Code Contributions

1. **Fork**: Fork the project on GitHub
2. **Create branch**: Create a new feature branch (`git checkout -b feature/amazing-feature`)
3. **Make changes**: Write and test your code
4. **Commit**: Use meaningful commit messages (`git commit -m 'Add amazing feature'`)
5. **Push**: Push your branch to your fork (`git push origin feature/amazing-feature`)
6. **Open Pull Request**: Create a Pull Request on GitHub

## Development Environment Setup

### Prerequisites

- Crystal 1.12.0 or higher
- Docker (optional, for containerized testing)
- Git

### Installation

```bash
# Clone the project
git clone https://github.com/kursadaltan/kemalwaf.git
cd kemal-waf

# Install dependencies
shards install

# Build
./build.sh
```

### Running Tests

```bash
# Unit tests
make test-unit

# All tests
make test-all

# Format check
crystal tool format --check
```

## Code Standards

### Crystal Format

The project uses Crystal's standard format. To format your code:

```bash
crystal tool format
```

### Commit Messages

Your commit messages should be descriptive:

- `Add`: New feature added
- `Fix`: Bug fixed
- `Update`: Existing feature updated
- `Refactor`: Code refactored
- `Docs`: Documentation updated
- `Test`: Test added or updated

Example:
```
Add rate limiting support for IP-based filtering
Fix SQL injection rule pattern matching
Update README with Docker Hub instructions
```

### Pull Request Process

1. Your Pull Request should have a descriptive title and description
2. Reference related issues (e.g., `Fixes #123`)
3. Explain your code changes
4. Add test results
5. Ensure the CI/CD pipeline is successful

### Code Review

All Pull Requests must be reviewed by at least one maintainer. During the review process:

- Code quality is checked
- Tests are run
- Documentation is updated
- Performance impact is evaluated

## Rule Development

To add new WAF rules:

1. Create a new YAML file in the `rules/` directory
2. Follow the rule format (see examples in README.md)
3. Test the rule
4. Update documentation

## Documentation

Documentation updates are also welcome:

- README.md improvements
- Code comments
- Usage examples
- Troubleshooting guides

## Questions?

If you have any questions:

- Ask questions on GitHub Issues
- Use the Discussions section
- Contact maintainers directly

## Code of Conduct

This project expects participants to behave respectfully and professionally. To ensure a pleasant environment for everyone, please:

- Be kind and respectful
- Be open to different views
- Provide constructive feedback
- Avoid personal attacks

Thank you for your contributions!
