# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-01-XX

### Added
- Kemal-based WAF implementation supporting OWASP CRS rules
- YAML format rule loading with multiple operator support
- LibInjection integration - Real SQLi/XSS detection
- Request variable support: `REQUEST_LINE`, `ARGS`, `ARGS_NAMES`, `HEADERS`, `BODY`, `COOKIE`, `COOKIE_NAMES`, `REQUEST_FILENAME`, `REQUEST_BASENAME`
- Advanced transformations: `none`, `url_decode`, `url_decode_uni`, `lowercase`, `utf8_to_unicode`, `remove_nulls`, `replace_comments`
- Multiple operator support: `regex`, `libinjection_sqli`, `libinjection_xss`, `contains`, `starts_with`
- OWASP CRS SQL Injection rules (942xxx series)
- Hot rule reloading (every 5 seconds)
- Observe mode - logging without blocking to test rules
- Prometheus metrics (`/metrics` endpoint)
- Upstream proxy support
- Multi-domain configuration support
- IP whitelist/blacklist filtering
- GeoIP filtering support (MaxMind GeoLite2)
- Rate limiting support
- Connection pooling
- Easy deployment with Docker and docker-compose
- Structured logging and audit logging
- Log rotation support
- Health check endpoint (`/health`)
- Unit and integration tests

### Security
- Real-time SQL injection and XSS detection with LibInjection
- OWASP CRS-based security rules
- IP-based filtering
- GeoIP-based filtering
- Rate limiting protection

[Unreleased]: https://github.com/kursadaltan/kemalwaf/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kursadaltan/kemalwaf/releases/tag/v1.0.0
