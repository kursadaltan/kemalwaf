# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-11-28

### Added

#### Core Features
- Initial release of kemal-waf - A Web Application Firewall built with Crystal and Kemal framework
- YAML-based rule configuration system with hot-reload support (5-second interval)
- Support for OWASP CRS (Core Rule Set) SQL Injection rules (942xxx series)
- Multiple rule operators: `regex`, `libinjection_sqli`, `libinjection_xss`, `contains`, `starts_with`
- Request variable support: `REQUEST_LINE`, `ARGS`, `ARGS_NAMES`, `HEADERS`, `BODY`, `COOKIE`, `COOKIE_NAMES`, `REQUEST_FILENAME`, `REQUEST_BASENAME`
- Advanced transformation pipeline: `none`, `url_decode`, `url_decode_uni`, `lowercase`, `utf8_to_unicode`, `remove_nulls`, `replace_comments`

#### Security Features
- **LibInjection Integration**: Real-time SQL injection and XSS detection using LibInjection C library
- IP whitelist/blacklist filtering with CIDR notation support
- GeoIP filtering support using MaxMind GeoLite2 database
- Rate limiting with configurable limits, windows, and block durations
- Observe mode for testing rules without blocking requests

#### Configuration & Management
- YAML configuration file (`config/waf.yml`) with comprehensive settings
- Multi-domain upstream routing support
- Dynamic upstream routing via `X-Next-Upstream` header
- Environment variable support for backward compatibility
- Hot configuration reload via SIGHUP signal
- Default rules included in Docker image

#### Performance & Scalability
- HTTP connection pooling with configurable pool sizes
- Connection pool manager with automatic cleanup
- Health checks and connection recycling
- TLS/SSL support for upstream connections

#### Observability
- Prometheus metrics endpoint (`/metrics`)
- Structured JSON logging
- Audit logging with separate log files
- Log rotation with size and retention policies
- Health check endpoint (`/health`)
- Request/response metrics tracking

#### Deployment & Developer Experience
- Docker image available on Docker Hub (`kursadaltan/kemalwaf`)
- Docker Compose support with upstream server
- Setup script (`setup.sh`) for easy rules and config preparation
- Comprehensive documentation in README
- CI/CD pipeline with GitHub Actions
- Unit and integration test suites
- Build scripts for macOS and Linux

#### Documentation
- Complete README with quick start guide
- Configuration examples (`waf.yml.example`)
- IP filtering examples (`ip_whitelist.txt.example`, `ip_blacklist.txt.example`)
- Contributing guidelines
- Architecture documentation

[Unreleased]: https://github.com/kursadaltan/kemalwaf/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kursadaltan/kemalwaf/releases/tag/v1.0.0
