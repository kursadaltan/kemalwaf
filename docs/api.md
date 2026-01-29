# API Reference

HTTP endpoints for health checks, metrics, and the admin API.

## Health check

### GET `/health`

Health check endpoint to verify WAF is running.

**Request:**
```bash
curl http://localhost:3030/health
```

**Response:**
```json
{
  "status": "healthy",
  "rules_loaded": 42,
  "observe_mode": false
}
```

**Response Fields:**
- `status`: Service status (`healthy` or `unhealthy`)
- `rules_loaded`: Number of active WAF rules
- `observe_mode`: Whether observe mode is enabled

**Status Codes:**
- `200 OK` - Service is healthy
- `503 Service Unavailable` - Service is unhealthy

## Metrics

### GET `/metrics`

Prometheus format metrics endpoint.

**Request:**
```bash
curl http://localhost:9090/metrics
```

**Response:**
```
# HELP waf_requests_total Total number of requests processed
# TYPE waf_requests_total counter
waf_requests_total 12345

# HELP waf_blocked_total Number of blocked requests
# TYPE waf_blocked_total counter
waf_blocked_total 123

# HELP waf_observed_total Number of requests matched in observe mode
# TYPE waf_observed_total counter
waf_observed_total 45

# HELP waf_rules_loaded Number of loaded rules
# TYPE waf_rules_loaded gauge
waf_rules_loaded 42
```

**Metrics:**
- `waf_requests_total` - Total number of requests processed
- `waf_blocked_total` - Number of blocked requests
- `waf_observed_total` - Number of requests matched in observe mode
- `waf_rules_loaded` - Number of loaded rules

## Admin Panel API

The Admin Panel provides a REST API for managing domains, rules, and configuration.

### Base URL

- Standalone: `http://localhost:8888/api/`
- Behind Nginx: `https://yourdomain.com/admin/api/`

### Authentication

All API endpoints require JWT authentication. Get a token by logging in through the Admin Panel UI.

**Request:**
```bash
curl -X POST http://localhost:8888/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "password"}'
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 3600
}
```

**Using Token:**
```bash
curl -H "Authorization: Bearer <token>" \
  http://localhost:8888/api/domains
```

### Domains API

#### GET `/api/domains`

List all configured domains.

**Response:**
```json
[
  {
    "domain": "example.com",
    "default_upstream": "http://localhost:8080",
    "letsencrypt_enabled": false
  }
]
```

#### POST `/api/domains`

Create a new domain configuration.

**Request:**
```json
{
  "domain": "example.com",
  "default_upstream": "http://localhost:8080",
  "letsencrypt_enabled": true,
  "letsencrypt_email": "admin@example.com"
}
```

#### PUT `/api/domains/:domain`

Update domain configuration.

#### DELETE `/api/domains/:domain`

Delete domain configuration.

### Rules API

#### GET `/api/rules`

List all active rules.

**Response:**
```json
[
  {
    "id": 942100,
    "name": "SQL Injection Detection",
    "msg": "SQL Injection Attack Detected",
    "category": "sqli",
    "severity": "CRITICAL",
    "action": "deny"
  }
]
```

#### POST `/api/rules`

Create a new rule.

**Request:**
```json
{
  "id": 942100,
  "name": "SQL Injection Detection",
  "msg": "SQL Injection Attack Detected",
  "operator": "libinjection_sqli",
  "variables": ["ARGS", "BODY"],
  "action": "deny"
}
```

#### PUT `/api/rules/:id`

Update a rule.

#### DELETE `/api/rules/:id`

Delete a rule.

## Test Scenarios

### 1. Normal Request (Allowed)

```bash
curl -i http://localhost:3030/api/users
```

**Expected:** `200 OK` (response from upstream)

### 2. SQL Injection Attack (Blocked)

```bash
curl -i "http://localhost:3030/api/users?id=1' OR '1'='1"
```

**Expected:** `403 Forbidden`
```json
{
  "error": "Request blocked by WAF",
  "rule_id": 942100,
  "message": "SQL Injection Attack Detected via libinjection"
}
```

### 3. XSS Attack (Blocked)

```bash
curl -i "http://localhost:3030/search?q=<script>alert('xss')</script>"
```

**Expected:** `403 Forbidden`
```json
{
  "error": "Request blocked by WAF",
  "rule_id": 941100,
  "message": "XSS Attack Detected"
}
```

### 4. SQL Injection in POST Body (Blocked)

```bash
curl -i -X POST http://localhost:3030/api/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "pass OR 1=1"}'
```

**Expected:** `403 Forbidden`

### 5. Observe Mode (Logs but Doesn't Block)

```bash
# Enable observe mode in config
# config/waf.yml: mode: observe

# Try SQL injection
curl -i "http://localhost:3030/api/users?id=1' OR '1'='1"
```

**Expected:** `200 OK` (proxied to upstream, but logged)

**Check logs:**
```bash
docker logs kemal-waf | grep "OBSERVE MODE"
```

## Error Responses

### 403 Forbidden

Request blocked by WAF rule.

```json
{
  "error": "Request blocked by WAF",
  "rule_id": 942100,
  "message": "SQL Injection Attack Detected"
}
```

### 429 Too Many Requests

Rate limit exceeded.

```json
{
  "error": "Rate limit exceeded",
  "retry_after": 60
}
```

### 502 Bad Gateway

Upstream server error or domain not configured.

```json
{
  "error": "Bad Gateway",
  "message": "Upstream server unavailable"
}
```

## Rate Limit Headers

When rate limiting is enabled, responses include rate limit headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640995200
```

## Monitoring Integration

### Prometheus

Scrape metrics from `/metrics` endpoint:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'kemal-waf'
    static_configs:
      - targets: ['localhost:9090']
```

### Grafana

Use Prometheus as data source and create dashboards for:
- Request rate
- Block rate
- Top blocked IPs
- Rule effectiveness

## WebSocket API

The Admin Panel uses WebSocket for real-time updates. Connect to:

```
ws://localhost:8888/ws
```

Authentication is required via JWT token in the connection header.

