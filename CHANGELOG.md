# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2025-12-05

### Added

#### Performance Architecture
- **Zero GC Hotpath**: Request evaluation now uses preallocated buffer pools
  - `VariableSnapshot` class for stack-based variable storage
  - `VariableSnapshotPool` with 256 preallocated buffers
  - Zero-allocation cookie parsing using index-based iteration
  - Eliminates heap allocations in request hotpath

- **Branchless Evaluation**: Jump-table based operator dispatch
  - `OperatorDispatch` module with compile-time operator mapping
  - `@[AlwaysInline]` optimizations for matching functions
  - New operators: `ends_with`, `equals`
  - Reduced CPU branch mispredictions

#### Memory Management
- **Memory Bounds System**: Module-level memory limits with graceful degradation
  - Rate limiter: 50 MB limit
  - Challenge cache: 20 MB limit
  - Rule engine: 5 MB limit
  - Connection pool: 10 MB limit
  - GeoIP/MMDB: 80 MB limit
  - `BoundedCache` with LRU eviction
  - `BoundedMap` with memory tracking
  - Automatic eviction when limits exceeded

#### Rule Engine
- **Immutable Rule Snapshots**: Thread-safe rule management
  - `RuleSnapshot` immutable class for rule storage
  - `AtomicSnapshotHolder` for atomic pointer swap
  - Version tracking for snapshot identification
  - Dry-run validation before activation
  - Zero-downtime configuration updates

#### Observability
- **Request Tracing**: Granular latency breakdown
  - 12 trace points (Start, DNS, LB, WAF, Backend, Response, GC, End)
  - `RequestTracePool` for zero-allocation tracing
  - Nanosecond precision timestamps
  - JSON and log format output
  - Configurable sample rate

- **Extended Prometheus Metrics**: 25 fixed metrics
  - Request metrics: `duration_seconds` histogram, `size_bytes`
  - Backend metrics: `latency_seconds` histogram, `errors_total`, `retries_total`
  - Rate limit metrics: `active_counters`, `blocked_ips`
  - Connection pool metrics: `size`, `available`, `acquired`, `timeouts`
  - Memory metrics: `usage_bytes`, `gc_runs`, `gc_duration_seconds`
  - Rule engine metrics: `evaluation_duration_seconds`, `snapshot_version`
  - System metrics: `uptime_seconds`, `fiber_crashes`, `config_reloads`

#### Reliability
- **Panic Isolation**: Fiber crash recovery mechanism
  - `PanicIsolator` class for isolated fiber execution
  - Automatic restart on crash with configurable delay
  - Exponential backoff retry support
  - Crash statistics and monitoring
  - `Isolated.spawn` helper for easy usage

### Changed

#### Rate Limiter
- **Sharded State Map**: Reduced lock contention
  - 64 shards for concurrent access
  - Per-shard mutex instead of global lock
  - O(1) shard lookup using hash-based distribution
  - Eviction with 2ms time budget

#### IP Filter
- **Radix Tree Index**: O(1) CIDR lookup for IPv4
  - `IPv4RadixTree` with 32-level binary tree
  - O(32) = O(1) constant time lookup
  - Set-based exact IP matching O(1)
  - IPv6 fallback with linear scan

### New Files
- `src/memory_bounds.cr` - Memory limits and bounded containers
- `src/request_tracer.cr` - Request tracing with latency breakdown
- `src/panic_isolator.cr` - Fiber crash recovery and isolation

### Improved
- Evaluator refactored for zero-allocation evaluation
- Rate limiter simplified with sharded sliding window
- Rule loader now uses atomic snapshot swapping
- Metrics expanded from 5 to 25 Prometheus metrics
- IP filter CIDR lookup improved from O(n) to O(1)

### Technical Details

#### Memory Allocation Reduction
- Request evaluation: ~0 allocations per request (steady state)
- Cookie parsing: Zero-allocation using slice operations
- Variable snapshot: Reused from preallocated pool

#### Lock Contention Reduction
- Rate limiter: 64x reduction via sharding
- Rule engine: Lock-free reads via atomic snapshot
- IP filter: O(1) lookup eliminates iteration

#### Latency Improvements
- WAF evaluation: Predictable sub-microsecond latency
- Rate limiting: Consistent O(1) check time
- CIDR matching: 32-bit comparison instead of N comparisons

## [1.1.0] - 2025-12-04

### Added

#### TLS/HTTPS Support
- **TLS/HTTPS Server**: WAF can now serve traffic over HTTPS
  - HTTP and HTTPS can run simultaneously on different ports
  - Configurable HTTP/HTTPS ports
  - OpenSSL-based secure connection support

#### SNI (Server Name Indication) Support
- **Per-domain certificate management**: Each domain can use its own TLS certificate
  - `SNIManager` class for domain-based certificate management
  - Wildcard certificate support (`*.example.com`)
  - Added `cert_file` and `key_file` fields to domain configuration
  - Fallback certificate mechanism for unmatched domains

#### Let's Encrypt Integration
- **Automatic certificate provisioning**: Free SSL certificates via Let's Encrypt
  - `LetsEncryptManager` class with ACME protocol support
  - HTTP-01 challenge support (`/.well-known/acme-challenge/` endpoint)
  - Certbot integration (used when available)
  - Added `letsencrypt_enabled` and `letsencrypt_email` to domain configuration
  - Staging mode support (`LETSENCRYPT_STAGING=true`)

#### Automatic Certificate Renewal
- **Background certificate renewal**: Certificates are automatically renewed
  - Certificate check every 12 hours
  - Automatic renewal 30 days before expiration
  - Hot-reload: Renewed certificates are loaded without restart

#### Self-Signed Certificates
- **Auto-generated certificates for test/development**: Self-signed certificate generation
  - Secure generation using OpenSSL command-line tool
  - `auto_generate: true` configuration option
  - 365-day validity period
  - SAN (Subject Alternative Name) support

### New Files
- `src/tls_manager.cr` - TLS certificate management and SNI support
- `src/letsencrypt_manager.cr` - Let's Encrypt ACME integration

### Changed
- `src/config_loader.cr` - Added TLS fields to `DomainConfig` and `ServerConfig` structs
- `src/waf.cr` - TLS, SNI, and Let's Encrypt integration
- `config/waf.yml.example` - TLS and per-domain certificate examples
- `README.md` - TLS, SNI, and Let's Encrypt documentation

### Configuration

#### New Configuration Options

```yaml
waf:
  server:
    http_enabled: true      # Enable HTTP server (default: true)
    https_enabled: true     # Enable HTTPS server (default: false)
    http_port: 3030         # HTTP port
    https_port: 3443        # HTTPS port
    tls:
      cert_file: /path/to/cert.pem    # Global certificate
      key_file: /path/to/key.pem      # Global private key
      auto_generate: false            # Auto-generate self-signed cert
      auto_cert_dir: config/certs     # Certificate directory
      
  domains:
    "example.com":
      cert_file: /path/to/example.com/cert.pem   # Domain certificate (SNI)
      key_file: /path/to/example.com/key.pem
      letsencrypt_enabled: true                   # Auto Let's Encrypt
      letsencrypt_email: admin@example.com
```

#### New Environment Variables
- `HTTP_ENABLED` - Enable HTTP server (default: true)
- `HTTPS_ENABLED` - Enable HTTPS server (default: false)
- `HTTP_PORT` - HTTP port (default: 3030)
- `HTTPS_PORT` - HTTPS port (default: 3443)
- `TLS_CERT_FILE` - TLS certificate file path
- `TLS_KEY_FILE` - TLS private key file path
- `TLS_AUTO_GENERATE` - Auto-generate self-signed certificate
- `LETSENCRYPT_STAGING` - Let's Encrypt staging mode

### Improved
- Configuration change detection logic improved
- Connection pool manager constants reorganized
- LibInjection availability check enhanced
- Rule loading error handling improved with warnings and debug logs
- More descriptive log messages

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

[Unreleased]: https://github.com/kursadaltan/kemalwaf/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/kursadaltan/kemalwaf/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/kursadaltan/kemalwaf/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kursadaltan/kemalwaf/releases/tag/v1.0.0
