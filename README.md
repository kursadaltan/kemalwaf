# kemal-waf

[![CI/CD](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Crystal](https://img.shields.io/badge/Crystal-1.12.0-blue.svg)](https://crystal-lang.org/)
[![Kemal](https://img.shields.io/badge/Built%20with-Kemal-green.svg)](https://github.com/kemalcr/kemal)

A Web Application Firewall (WAF) Proof-of-Concept application built with [Kemal](https://github.com/kemalcr/kemal) framework that supports OWASP CRS rules.

> 🚀 **Quick Setup:** Use the `setup.sh` script to prepare rules files. See the [Running from Docker Hub](#running-from-docker-hub) section for details.

## Features

### Core WAF Features
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
- ✅ **TLS/HTTPS support** with certificate files or auto-generated self-signed certificates
- ✅ **SNI (Server Name Indication)** - Per-domain TLS certificates
- ✅ **Let's Encrypt integration** - Automatic certificate generation and renewal
- ✅ **HTTP and HTTPS** can run simultaneously

### 🎉 New: Web Admin Panel
- ✅ **Cloudflare-like UI** - Modern, user-friendly interface
- ✅ **Single Docker Image** - WAF + Admin Panel integrated
- ✅ **Domain Management** - Add/edit/delete proxy hosts via GUI
- ✅ **SSL/TLS Management** - Configure Let's Encrypt or custom certificates
- ✅ **Real-time Config** - Changes apply immediately
- ✅ **Secure Authentication** - JWT-based with Argon2 password hashing
- ✅ **Setup Wizard** - Easy first-time configuration

## Quick Start

### 🆕 Running with Admin Panel (Recommended)

The easiest way to get started with both WAF and Admin Panel:

```bash
# Clone the repository
git clone https://github.com/kursadaltan/kemalwaf.git
cd kemalwaf

# Build and start (includes WAF + Admin Panel)
docker compose up -d

# Access the services:
# - Admin Panel: http://localhost:8888
# - WAF HTTP: http://localhost:80
# - WAF HTTPS: https://localhost:443
```

On first access, the admin panel will guide you through setup wizard to create your admin user.

#### 🔀 Deploy Options

**Option 1: Standalone** (Default - Admin Panel at root `/`)
```bash
# Build with default settings
make docker-build
# or
docker compose build

# Admin Panel: http://localhost:8888/
# API: http://localhost:8888/api/
```

**Option 2: Behind Nginx Reverse Proxy** (Admin Panel at subpath `/admin/`)
```bash
# Build with Nginx subpath support
make docker-build-nginx
# or
docker compose build --build-arg VITE_BASE_PATH=/admin/

# Admin Panel: https://yourdomain.com/admin/
# API: https://yourdomain.com/admin/api/
```

See [Nginx Configuration](#nginx-reverse-proxy-configuration) section below for Nginx setup details.

### 🐳 Running with Docker Run

If you prefer `docker run` over `docker compose`:

```bash
# 1. Build the image (if not using Docker Hub)
docker build -t kemal-waf:latest .

# 2. Create network and volumes
docker network create waf-network
docker volume create waf-certs
docker volume create admin-data

# 3. Run the container
docker run -d \
  --name kemal-waf \
  --network waf-network \
  -p 3030:3030 \
  -p 3443:3443 \
  -p 8888:8888 \
  -v $(pwd)/config/waf.yml:/app/config/waf.yml \
  -v $(pwd)/rules:/app/rules:ro \
  -v waf-certs:/app/config/certs \
  -v $(pwd)/logs:/app/logs \
  -v $(pwd)/config/ip_whitelist.txt:/app/config/ip_whitelist.txt:ro \
  -v $(pwd)/config/ip_blacklist.txt:/app/config/ip_blacklist.txt:ro \
  -v admin-data:/app/admin/data \
  kursadaltan/kemalwaf:latest

# 4. View logs
docker logs -f kemal-waf

# 5. Stop and remove
docker stop kemal-waf
docker rm kemal-waf
```

**Minimal Setup (without config files):**
```bash
docker run -d \
  --name kemal-waf \
  -p 80:3030 \
  -p 443:3443 \
  -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  kemal-waf:latest
```

### Running from Docker Hub

#### Quick Start with Admin Panel

```bash
# Pull the latest image
docker pull kursadaltan/kemalwaf:latest

# Create volumes
docker volume create waf-certs
docker volume create admin-data

# Run with Admin Panel
docker run -d \
  --name kemal-waf \
  -p 80:3030 \
  -p 443:3443 \
  -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  kursadaltan/kemalwaf:latest

# Access Admin Panel: http://localhost:8888
```

#### WAF Only (Legacy, without Admin Panel)

Default rules are already included in the Docker image:

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

# WAF is now running at http://localhost:3030
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
- **TLS/HTTPS configuration** (new)
- **HTTP/HTTPS server settings** (new)

**Environment variables** (for backward compatibility):

| Variable | Default | Description |
|----------|---------|-------------|
| `RULE_DIR` | `rules` | Directory containing YAML rule files |
| `UPSTREAM` | `http://localhost:8080` | Upstream URL for proxy target (if not in config) |
| `OBSERVE` | `false` | If `true`, rules will log but not block when matched |
| `BODY_LIMIT_BYTES` | `1048576` | Request body read limit (1MB) |
| `RELOAD_INTERVAL_SEC` | `5` | Interval for checking rule files (seconds) |
| `HTTP_ENABLED` | `true` | Enable HTTP server |
| `HTTPS_ENABLED` | `false` | Enable HTTPS server |
| `HTTP_PORT` | `3030` | HTTP port number |
| `HTTPS_PORT` | `3443` | HTTPS port number |
| `TLS_CERT_FILE` | - | Path to TLS certificate file |
| `TLS_KEY_FILE` | - | Path to TLS private key file |
| `TLS_AUTO_GENERATE` | `false` | Auto-generate self-signed certificate (testing only) |

## TLS/HTTPS Configuration

Kemal WAF supports TLS (HTTPS) with multiple certificate options and SNI (Server Name Indication) support for multi-domain deployments.

### Option 1: Global Certificate Files

For a single domain or wildcard certificate:

```yaml
waf:
  server:
    https_enabled: true
    https_port: 3443
    tls:
      cert_file: /path/to/cert.pem
      key_file: /path/to/key.pem
```

### Option 2: Auto-Generated Self-Signed Certificate

For testing and development:

```yaml
waf:
  server:
    https_enabled: true
    https_port: 3443
    tls:
      auto_generate: true
      auto_cert_dir: config/certs
```

**⚠️ Warning:** Self-signed certificates are for testing/development only. Do not use in production!

### Option 3: SNI - Per-Domain Certificates

For multi-domain deployments, each domain can have its own certificate:

```yaml
waf:
  server:
    https_enabled: true
    https_port: 3443
    
  domains:
    "example.com":
      default_upstream: "http://localhost:8080"
      cert_file: /etc/letsencrypt/live/example.com/fullchain.pem
      key_file: /etc/letsencrypt/live/example.com/privkey.pem
      
    "api.example.com":
      default_upstream: "http://localhost:8081"
      cert_file: /etc/letsencrypt/live/api.example.com/fullchain.pem
      key_file: /etc/letsencrypt/live/api.example.com/privkey.pem
```

### Option 4: Let's Encrypt Auto-Certificate

Kemal WAF can automatically obtain and renew Let's Encrypt certificates:

```yaml
waf:
  server:
    https_enabled: true
    http_enabled: true   # Required for HTTP-01 challenge
    http_port: 80        # Must be accessible on port 80
    https_port: 443
    
  domains:
    "example.com":
      default_upstream: "http://localhost:8080"
      letsencrypt_enabled: true
      letsencrypt_email: admin@example.com
      
    "api.example.com":
      default_upstream: "http://localhost:8081"
      letsencrypt_enabled: true
      letsencrypt_email: admin@example.com
```

**Requirements for Let's Encrypt:**
- Domain must point to your server (DNS A/AAAA record)
- Port 80 must be accessible for HTTP-01 challenge
- Certbot should be installed (`brew install certbot` or `apt-get install certbot`)
- Email address for certificate expiry notifications

**Environment Variables for Let's Encrypt:**
- `LETSENCRYPT_STAGING=true` - Use staging environment for testing (avoids rate limits)

**Certificate Priority:**
1. Custom `cert_file` / `key_file` (highest priority)
2. `letsencrypt_enabled: true`
3. Global TLS configuration (fallback)

### HTTP and HTTPS Together

You can enable both HTTP and HTTPS simultaneously:

```yaml
waf:
  server:
    http_enabled: true
    http_port: 3030
    https_enabled: true
    https_port: 3443
    tls:
      auto_generate: true
```

### Automatic Certificate Renewal

When using Let's Encrypt, certificates are automatically renewed 30 days before expiry. The renewal process runs in the background every 12 hours.

### HTTP/2.0 Support

HTTP/2.0 support is planned but not yet implemented. The configuration option `http2_enabled` is available in the config file for future use. Currently, the WAF uses HTTP/1.1.

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

## Nginx Reverse Proxy Configuration

When deploying the Admin Panel behind Nginx (e.g., at `https://yourdomain.com/admin/`), you need to:

1. **Build with subpath support:**
   ```bash
   make docker-build-nginx
   # or
   docker compose build --build-arg VITE_BASE_PATH=/admin/
   ```

2. **Configure Nginx Proxy Manager or Custom Nginx:**

### Option A: Nginx Proxy Manager (GUI)

In your Proxy Host configuration for `yourdomain.com`, add these location blocks in the **Custom Nginx Configuration** section:

```nginx
# Admin Panel UI - /admin path
location /admin/ {
    proxy_pass http://kemal-waf:8888/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

# Admin API - /admin/api path
location /admin/api/ {
    proxy_pass http://kemal-waf:8888/api/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# Main WAF - proxy to backend
location / {
    proxy_pass http://kemal-waf:3030;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

### Option B: Standard Nginx Config

```nginx
server {
    listen 443 ssl http2;
    server_name yourdomain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # Admin Panel
    location /admin/ {
        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Admin API
    location /admin/api/ {
        proxy_pass http://127.0.0.1:8888/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Main application (proxied through WAF)
    location / {
        proxy_pass http://127.0.0.1:3030;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Alternative: Subdomain Setup

If you prefer a subdomain instead of a subpath (e.g., `admin.yourdomain.com`):

1. **Build with default settings** (no `VITE_BASE_PATH` needed):
   ```bash
   make docker-build
   ```

2. **Create separate Nginx server block:**
   ```nginx
   server {
       listen 443 ssl http2;
       server_name admin.yourdomain.com;
       
       ssl_certificate /path/to/cert.pem;
       ssl_certificate_key /path/to/key.pem;
       
       location / {
           proxy_pass http://127.0.0.1:8888;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
       }
   }
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
