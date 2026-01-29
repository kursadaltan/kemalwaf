# TLS/HTTPS

kemal-waf supports HTTPS with your own certs, self-signed (dev only), per-domain (SNI), or Let's Encrypt.

## Option 1: Global certificate files

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

## Option 2: Self-signed cert (dev only)

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

## Option 3: SNI (per-domain certs)

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

## Option 4: Let's Encrypt

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

## HTTP and HTTPS Together

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

## Automatic Certificate Renewal

When using Let's Encrypt, certificates are automatically renewed 30 days before expiry. The renewal process runs in the background every 12 hours.

## HTTP/2.0 Support

HTTP/2.0 support is planned but not yet implemented. The configuration option `http2_enabled` is available in the config file for future use. Currently, the WAF uses HTTP/1.1.

## Docker Volume Setup

For persistent certificate storage:

```bash
# Create volume for certificates
docker volume create waf-certs

# Run with certificate volume
docker run -d \
  --name kemal-waf \
  -p 443:3443 \
  -v waf-certs:/app/config/certs \
  kursadaltan/kemalwaf:latest
```

## Certificate File Permissions

Ensure certificate files have correct permissions:

```bash
chmod 600 /path/to/key.pem
chmod 644 /path/to/cert.pem
```

## Testing TLS Configuration

```bash
# Test HTTPS connection
curl -k https://localhost:3443/

# Test with certificate validation
curl https://example.com/ --cacert /path/to/ca-cert.pem

# Check certificate details
openssl s_client -connect example.com:443 -servername example.com
```

## Troubleshooting

### Certificate Not Found

If you see "certificate file not found" errors:
- Check file paths are correct
- Ensure files are readable by the WAF process
- Verify certificate and key files match

### Let's Encrypt Rate Limits

If you hit Let's Encrypt rate limits:
- Use `LETSENCRYPT_STAGING=true` for testing
- Wait for rate limit reset (usually 1 week)
- Use wildcard certificates for multiple subdomains

### SNI Not Working

If SNI is not working:
- Ensure each domain has its own certificate configuration
- Check that the domain name matches exactly (case-sensitive)
- Verify certificates are valid and not expired

