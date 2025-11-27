# kemal-waf

[![CI/CD](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Crystal](https://img.shields.io/badge/Crystal-1.12.0-blue.svg)](https://crystal-lang.org/)
[![Kemal](https://img.shields.io/badge/Built%20with-Kemal-green.svg)](https://github.com/kemalcr/kemal)

A Web Application Firewall (WAF) Proof-of-Concept application built with [Kemal](https://github.com/kemalcr/kemal) framework that supports OWASP CRS rules.

> 🚀 **Quick Setup:** Use the `setup.sh` script to prepare rules files. See the [Running from Docker Hub](#running-from-docker-hub) section for details.

## Features

- ✅ YAML format rule loading with multiple operator support
- ✅ **LibInjection** integration - Real SQLi/XSS detection
- ✅ Request variables: `REQUEST_LINE`, `ARGS`, `ARGS_NAMES`, `HEADERS`, `BODY`, `COOKIE`, `COOKIE_NAMES`, `REQUEST_FILENAME`, `REQUEST_BASENAME`
- ✅ Advanced transformations: `none`, `url_decode`, `url_decode_uni`, `lowercase`, `utf8_to_unicode`, `remove_nulls`, `replace_comments`
- ✅ Multiple operator support: `regex`, `libinjection_sqli`, `libinjection_xss`, `contains`, `starts_with`
- ✅ OWASP CRS SQL Injection rules (942xxx series)
- ✅ Hot rule reloading (every 5 seconds)
- ✅ Observe mode - logging without blocking to test rules
- ✅ Prometheus metrics (`/metrics` endpoint)
- ✅ Upstream proxy support
- ✅ Easy deployment with Docker and docker-compose

## Quick Start

### Running from Docker Hub

#### Quick Start (Default Rules)

Default rules are already included in the Docker image, so volume mount is optional:

```bash
# Pull the image from Docker Hub
docker pull kursadaltan/kemalwaf:latest

# Minimal run (with default rules)
docker run -d \
  -p 3030:3030 \
  -v $(pwd)/config/waf.yml:/app/config/waf.yml:ro \
  kursadaltan/kemalwaf:latest
```

#### Running with Custom Rules

If you want to use your own rules files:

**1. Preparation with setup script (Recommended):**

```bash
# Run the setup script (downloads rules and config files)
curl -L https://raw.githubusercontent.com/kursadaltan/kemalwaf/main/setup.sh | bash

# Or manually:
chmod +x setup.sh
./setup.sh
```

**2. Mounting custom rules with docker run:**

```bash
docker run -d \
  -p 3030:3030 \
  -v $(pwd)/config/waf.yml:/app/config/waf.yml:ro \
  -v $(pwd)/rules:/app/rules:ro \
  kursadaltan/kemalwaf:latest
```

**Note:** If the `rules` volume is mounted, the mounted rules will be used instead of the default rules in the image.

### Running with Docker Compose

```bash
# Clone the project
git clone https://github.com/kursadaltan/kemalwaf.git
cd kemal-waf

# Start with Docker Compose
docker-compose up --build

# WAF is now running at http://localhost:3000
```

### Direct Build on macOS (Without Docker)

**Prerequisite:** Crystal must be installed
```bash
# To install Crystal
brew install crystal
```

**Build and Run:**
```bash
# Build
./build.sh

# Run
./run.sh
```

Or manually:
```bash
# Install dependencies
shards install

# Compile the application
crystal build --release --no-debug src/waf.cr -o bin/kemal-waf

# Run
UPSTREAM=http://localhost:8080 ./bin/kemal-waf
```

**Note:** To run on macOS, you need an upstream server. If you're not using Docker Compose, start the upstream server in another terminal or set the `UPSTREAM` environment variable to a real upstream URL.

## Configuration

Configuration is done via `config/waf.yml` file. See `config/waf.yml.example` for a complete example.

The configuration file supports:
- Multi-domain upstream routing
- WAF mode (enforce, observe, disabled)
- Rate limiting settings
- IP filtering (whitelist/blacklist)
- GeoIP blocking
- Rule directory and reload interval
- Logging configuration
- Metrics settings

**Environment variables** (for backward compatibility):

| Variable | Default | Description |
|----------|---------|-------------|
| `RULE_DIR` | `rules` | Directory containing YAML rule files |
| `UPSTREAM` | `http://localhost:8080` | Upstream URL for proxy target (if not in config) |
| `OBSERVE` | `false` | If `true`, rules will log but not block when matched |
| `BODY_LIMIT_BYTES` | `1048576` | Request body read limit (1MB) |
| `RELOAD_INTERVAL_SEC` | `5` | Interval for checking rule files (seconds) |

## Rule Format

### Simple Format (Backward Compatible)

```yaml
---
id: 942100
msg: "SQL Injection Attack Detected"
variables:
  - ARGS
  - BODY
  - REQUEST_LINE
pattern: "(?i)(union.*select|select.*from|insert.*into)"
action: deny
transforms:
  - url_decode
  - lowercase
```

### Advanced Format (OWASP CRS)

```yaml
---
id: 942100
name: "SQL Injection - LibInjection Detection"
msg: "SQL Injection Attack Detected via libinjection"
category: "sqli"
severity: "CRITICAL"
paranoia_level: 1
operator: "libinjection_sqli"  # or "regex", "libinjection_xss", "contains", "starts_with"
pattern: null  # null for LibInjection, pattern for regex
variables:
  - type: COOKIE
  - type: ARGS
  - type: ARGS_NAMES
  - type: HEADERS
    names: ["User-Agent", "Referer"]  # Filter for specific headers
  - type: BODY
transforms:
  - none
  - utf8_to_unicode
  - url_decode_uni
  - remove_nulls
action: "deny"
tags:
  - "OWASP_CRS"
  - "attack-sqli"
  - "paranoia-level/1"
```

### Rule Fields

- **id**: Unique rule identifier (integer, required)
- **msg**: Rule description (string, required)
- **name**: Rule name (string, optional)
- **category**: Rule category: `sqli`, `xss`, `lfi`, `rce`, etc. (string, optional)
- **severity**: Severity level: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` (string, optional)
- **paranoia_level**: Paranoia level (integer, optional, default: 1)
- **operator**: Matching operator (string, optional, default: "regex")
  - `regex`: Regex pattern matching
  - `libinjection_sqli`: LibInjection SQLi detection
  - `libinjection_xss`: LibInjection XSS detection
  - `contains`: String contains check
  - `starts_with`: String starts with check
- **pattern**: Regex pattern or string pattern (string?, optional - null for LibInjection)
- **variables**: List of variables to check (array, required)
  - Simple format: `["ARGS", "BODY"]`
  - Advanced format: `[{type: "HEADERS", names: ["User-Agent"]}]`
  - Supported variables:
    - `REQUEST_LINE`: HTTP request line (METHOD PATH PROTOCOL)
    - `REQUEST_FILENAME`: Request path
    - `REQUEST_BASENAME`: Basename of path
    - `ARGS`: Query string parameters (in key=value format)
    - `ARGS_NAMES`: Parameter names only
    - `HEADERS`: HTTP headers (in Header-Name: value format)
    - `BODY`: Request body
    - `COOKIE`: Cookie header
    - `COOKIE_NAMES`: Cookie names only
- **action**: `deny` (block) or `log` (log only) (string, required)
- **transforms**: Optional transformation list (array, optional)
  - `none`: No transform
  - `url_decode`: Apply URL decode
  - `url_decode_uni`: Unicode-aware URL decode
  - `lowercase`: Convert to lowercase
  - `utf8_to_unicode`: UTF-8 to Unicode conversion
  - `remove_nulls`: Remove null bytes
  - `replace_comments`: Remove SQL/HTML comments
- **tags**: Rule tags (array, optional)

## Adding New Rules

### Manual YAML Creation

1. Create a new `.yaml` file in the `rules/` directory (or subdirectories)
2. Define the rule using the format above
3. WAF will automatically load the new rule within 5 seconds (recursive directory scanning)

### OWASP CRS Rules

The project includes OWASP CRS SQL Injection rules (in the `rules/owasp-crs/` folder):

- **942100**: LibInjection SQLi Detection
- **942140**: Common DB Names Detection
- **942151**: SQL Function Names Detection
- **942160**: Sleep/Benchmark Detection
- **942170**: Benchmark and Sleep Injection

These rules have been manually converted from OWASP CRS to YAML format. To add new rules:

1. Reference the OWASP CRS documentation
2. Copy regex patterns from OWASP CRS
3. Map transforms correctly
4. Create a rule file in YAML format

### LibInjection Installation

The LibInjection C library must be installed on the system or built from source:

```bash
# To build LibInjection from source
git clone https://github.com/libinjection/libinjection.git
cd libinjection
make
sudo make install
```

It is linked during Crystal build with the `-linjection` flag.

## Endpoints

### `/health`
Health check endpoint

```bash
curl http://localhost:3000/health
```

Response:
```json
{
  "status": "healthy",
  "rules_loaded": 2,
  "observe_mode": false
}
```

### `/metrics`
Prometheus format metrics

```bash
curl http://localhost:3000/metrics
```

Metrics:
- `waf_requests_total`: Total number of requests processed
- `waf_blocked_total`: Number of blocked requests
- `waf_observed_total`: Number of requests matched in observe mode
- `waf_rules_loaded`: Number of loaded rules

## Test Scenarios

### 1. Normal Request (Allowed)

```bash
curl -i http://localhost:3000/api/users
```

Expected: `200 OK` (response from upstream)

### 2. SQL Injection Attack (Blocked)

```bash
curl -i "http://localhost:3000/api/users?id=1' OR '1'='1"
```

Expected: `403 Forbidden`
```json
{
  "error": "Request blocked by WAF",
  "rule_id": 942100,
  "message": "SQL Injection Attack Detected via libinjection"
}
```

### 3. XSS Attack (Blocked)

```bash
curl -i "http://localhost:3000/search?q=<script>alert('xss')</script>"
```

Expected: `403 Forbidden`
```json
{
  "error": "Request blocked by WAF",
  "rule_id": 941100,
  "message": "XSS Attack Detected"
}
```

### 4. SQL Injection in POST Body (Blocked)

```bash
curl -i -X POST http://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "pass OR 1=1"}'
```

Expected: `403 Forbidden`

### 5. Observe Mode (Logs but Doesn't Block)

```bash
# Enable observe mode
docker-compose down
OBSERVE=true docker-compose up -d

# Try SQL injection
curl -i "http://localhost:3000/api/users?id=1' OR '1'='1"
```

Expected: `200 OK` (proxied to upstream, but logged)

Check logs:
```bash
docker-compose logs waf | grep "OBSERVE MODE"
```

## Test Plan

### Unit Tests

1. **Transformation Tests**
   - URL decode: `%27OR%271%27%3D%271` → `'OR'1'='1`
   - Lowercase: `SELECT * FROM` → `select * from`
   - Combined: URL decode + lowercase

2. **Regex Matching Tests**
   - SQLi patterns: `union select`, `' or '1'='1`, `--`, `/**/`
   - XSS patterns: `<script>`, `javascript:`, `onerror=`

3. **Variable Snapshot Tests**
   - ARGS parsing: Correct parsing of query string parameters
   - HEADERS parsing: Capturing all headers
   - BODY parsing: Reading POST body content
   - COOKIE parsing: Parsing cookie header

### Integration Tests

1. **Rule Loading**
   - Loading all YAML files at startup
   - Gracefully skipping invalid YAML files
   - Catching regex compilation errors

2. **Hot Reload**
   - Adding new rule file → loaded within 5s
   - Updating existing rule file → reloaded within 5s
   - Deleting rule file → removed within 5s

3. **Proxy Functionality**
   - Forwarding GET requests to upstream
   - Forwarding POST requests with body
   - Forwarding upstream response headers to client
   - Catching upstream connection errors (502)

4. **Metric Accuracy**
   - Each request increments `waf_requests_total`
   - Blocked requests increment `waf_blocked_total`
   - Observe mode matches increment `waf_observed_total`
   - Rule reloading updates `waf_rules_loaded`

### Performance Tests

```bash
# Load test with Apache Bench
ab -n 10000 -c 100 http://localhost:3000/api/test

# Check metrics
curl http://localhost:3000/metrics
```

## Architecture

This WAF is built on top of the [Kemal](https://github.com/kemalcr/kemal) web framework for Crystal, which provides fast HTTP server capabilities and middleware support.

```
┌─────────┐      ┌──────────────┐      ┌──────────┐
│ Client  │─────▶│  kemal-waf   │─────▶│ Upstream │
└─────────┘      │              │      └──────────┘
                 │ - Rule Load  │
                 │ - Evaluate   │
                 │ - Proxy      │
                 │ - Metrics    │
                 │ - Hot Reload │
                 └──────────────┘
```

### Components

- **rule_loader.cr**: YAML rule loading, file watching, hot-reload, recursive directory scanning
- **evaluator.cr**: Request evaluation, variable snapshot, transformations, multiple operator support
- **libinjection.cr**: LibInjection C binding and wrapper functions
- **proxy_client.cr**: Upstream HTTP proxy client
- **metrics.cr**: Prometheus metric management
- **waf.cr**: Main Kemal server application with middleware and routes

## Security Notes

⚠️ **This is a PoC application.** For production use:

## Contributing

Pull requests are welcome. For major changes, please open an issue first.

For detailed information, see the [CONTRIBUTING.md](CONTRIBUTING.md) file.

## Changelog

All notable changes are documented in the [CHANGELOG.md](CHANGELOG.md) file.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
