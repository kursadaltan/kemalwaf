# Configuration Guide

Kemal WAF is configured via the `config/waf.yml` file. See `config/waf.yml.example` for a complete example.

## Configuration File Structure

The configuration file supports:
- Multi-domain upstream routing
- WAF mode (enforce, observe, disabled)
- Rate limiting settings
- IP filtering (whitelist/blacklist)
- GeoIP blocking
- Rule directory and reload interval
- Logging configuration
- Metrics settings
- TLS/HTTPS configuration
- HTTP/HTTPS server settings

## Basic Configuration

### Minimal Configuration

```yaml
waf:
  mode: enforce  # enforce, observe, disabled
  domains:
    "example.com":
      default_upstream: "http://localhost:8080"
```

### Full Configuration Example

```yaml
waf:
  mode: enforce  # enforce, observe, disabled
  
  # Global default upstream (optional, for backward compatibility)
  upstream:
    url: http://backend:8080
    timeout: 30s
    retry: 3
    
  # Multi-domain configuration
  domains:
    "example.com":
      default_upstream: "http://localhost:8080"
      upstream_host_header: ""  # Empty means use upstream URI
      preserve_original_host: false
    "api.example.com":
      default_upstream: "http://api-backend:8080"
    "xyz.com":
      default_upstream: "https://xyz-backend:443"
      preserve_original_host: true
    
  rate_limiting:
    enabled: true
    default_limit: 100
    window: 60s
    block_duration: 300s
    
  ip_filtering:
    enabled: true
    whitelist_file: config/ip_whitelist.txt
    blacklist_file: config/ip_blacklist.txt
    
  geoip:
    enabled: false
    mmdb_file: config/Maxmind/GeoLite2-Country.mmdb
    blocked_countries: [CN, RU, KP]
    allowed_countries: []
    
  rules:
    directory: rules/
    reload_interval: 5s
    
  logging:
    level: info
    format: json
    audit_file: logs/audit.log
    log_dir: logs
    max_size_mb: 100
    retention_days: 30
    
  metrics:
    enabled: true
    port: 9090
    
  server:
    http_enabled: true
    http_port: 3030
    https_enabled: false
    https_port: 3443
    tls:
      cert_file: /path/to/cert.pem
      key_file: /path/to/key.pem
```

## Multi-Domain Configuration

Each domain can have its own upstream configuration:

```yaml
domains:
  "example.com":
    default_upstream: "http://backend1:8080"
    upstream_host_header: ""  # Optional: custom Host header
    preserve_original_host: false  # Preserve original Host header
  "api.example.com":
    default_upstream: "http://api-backend:8080"
  "xyz.com":
    default_upstream: "https://xyz-backend:443"
```

**Notes:**
- Domain matching is exact (subdomains must be defined separately)
- If domain is not found, returns 502 Bad Gateway
- If `default_upstream` is not set, returns 502 Bad Gateway

## Dynamic Upstream Routing

You can override the default upstream using the `X-Next-Upstream` header:

```bash
# Use custom upstream for this request
curl -H "X-Next-Upstream: http://31.2.1.4:80" http://localhost:3030/
```

**Priority:**
1. `X-Next-Upstream` header (if present)
2. Domain config `default_upstream`
3. Global `upstream.url` (backward compatibility)

## WAF Modes

### Enforce Mode (Default)
Blocks requests that match rules.

```yaml
waf:
  mode: enforce
```

### Observe Mode
Logs rule matches but doesn't block requests. Useful for testing rules.

```yaml
waf:
  mode: observe
```

### Disabled Mode
WAF rules are not evaluated. Only IP filtering and rate limiting apply.

```yaml
waf:
  mode: disabled
```

## Rate Limiting

```yaml
rate_limiting:
  enabled: true
  default_limit: 100      # Requests per window
  window: 60s              # Time window
  block_duration: 300s    # IP block duration when limit exceeded
```

## IP Filtering

```yaml
ip_filtering:
  enabled: true
  whitelist_file: config/ip_whitelist.txt
  blacklist_file: config/ip_blacklist.txt
```

**IP List File Format:**
```
# Comments start with #
192.168.1.100
10.0.0.0/24
# IPv6 support
2001:db8::/32
```

## GeoIP Filtering

```yaml
geoip:
  enabled: true
  mmdb_file: config/Maxmind/GeoLite2-Country.mmdb
  blocked_countries: [CN, RU, KP]  # Block these countries
  allowed_countries: []             # Whitelist (only allow these)
```

See [GeoIP Filtering Guide](geoip.md) for details.

## Rule Configuration

```yaml
rules:
  directory: rules/        # Rule files directory
  reload_interval: 5s      # Hot reload check interval
```

Rules are automatically reloaded every 5 seconds. You can add, modify, or delete rule files without restarting the WAF.

## Logging Configuration

```yaml
logging:
  level: info              # debug, info, warn, error
  format: json            # json or text
  audit_file: logs/audit.log
  log_dir: logs
  max_size_mb: 100        # Max log file size
  retention_days: 30      # Log retention period
```

## Metrics Configuration

```yaml
metrics:
  enabled: true
  port: 9090              # Prometheus metrics endpoint port
```

Access metrics at: `http://localhost:9090/metrics`

## Server Configuration

### HTTP Server

```yaml
server:
  http_enabled: true
  http_port: 3030
```

### HTTPS Server

```yaml
server:
  https_enabled: true
  https_port: 3443
  tls:
    cert_file: /path/to/cert.pem
    key_file: /path/to/key.pem
```

See [TLS/HTTPS Setup](tls-https.md) for detailed TLS configuration.

## Environment Variables

For backward compatibility, you can override configuration with environment variables:

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

See [Environment Variables](environment-variables.md) for complete list.

## Configuration Validation

The WAF validates the configuration file on startup. Invalid configurations will cause the WAF to exit with an error message.

## Hot Reload

Configuration changes require a restart. However, rule files are hot-reloaded automatically every 5 seconds.

To reload configuration:
```bash
# Send SIGHUP signal (if supported)
kill -HUP <pid>

# Or restart the container
docker restart kemal-waf
```

## Best Practices

1. **Use YAML config file** instead of environment variables for complex setups
2. **Test in observe mode** before enabling enforce mode
3. **Monitor metrics** to tune rate limiting and rule effectiveness
4. **Keep logs** for at least 30 days for security auditing
5. **Use separate configs** for development and production

