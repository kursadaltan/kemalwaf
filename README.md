# kemal-waf

[![CI/CD](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Crystal](https://img.shields.io/badge/Crystal-1.12.0-blue.svg)](https://crystal-lang.org/)
[![Kemal](https://img.shields.io/badge/Built%20with-Kemal-green.svg)](https://github.com/kemalcr/kemal)

A Web Application Firewall (WAF) built with [Kemal](https://github.com/kemalcr/kemal) framework that supports OWASP CRS rules.

## Features

- ✅ **OWASP CRS Support** - SQL injection, XSS, and other attack detection with LibInjection
- ✅ **Web Admin Panel** - Cloudflare-like UI for domain and rule management
- ✅ **TLS/HTTPS** - Full TLS support with Let's Encrypt integration
- ✅ **Hot Rule Reloading** - Update rules without restart
- ✅ **Prometheus Metrics** - Built-in metrics endpoint
- ✅ **Rate Limiting** - IP-based rate limiting and throttling
- ✅ **IP Filtering** - Whitelist/blacklist with CIDR support
- ✅ **GeoIP Blocking** - Country-based access control

## Quick Start

### Docker Compose (Recommended)

```bash
git clone https://github.com/kursadaltan/kemalwaf.git
cd kemalwaf
docker compose up -d
```

Access:
- **Admin Panel:** http://localhost:8888
- **WAF HTTP:** http://localhost:80
- **WAF HTTPS:** https://localhost:443

On first access, the admin panel will guide you through setup wizard to create your admin user.

### Docker Run

```bash
docker run -d \
  --name kemal-waf \
  -p 80:3030 -p 443:3443 -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  kursadaltan/kemalwaf:latest
```

### From Docker Hub

```bash
docker pull kursadaltan/kemalwaf:latest
docker run -d \
  --name kemal-waf \
  -p 80:3030 -p 443:3443 -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  kursadaltan/kemalwaf:latest
```

## Documentation

📚 **[Full Documentation](.github/docs/)**

- [Installation Guide](.github/docs/installation.md) - Detailed installation instructions
- [Configuration](.github/docs/configuration.md) - WAF configuration guide
- [Rule Format](.github/docs/rules.md) - How to write and manage rules
- [TLS/HTTPS Setup](.github/docs/tls-https.md) - SSL/TLS configuration
- [Deployment](.github/docs/deployment.md) - Production deployment guide
- [Nginx Setup](.github/docs/nginx-setup.md) - Reverse proxy configuration
- [Environment Variables](.github/docs/environment-variables.md) - All environment variables
- [GeoIP Filtering](.github/docs/geoip.md) - Country-based blocking
- [API Reference](.github/docs/api.md) - API endpoints

## Architecture

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

## Contributing

Pull requests are welcome! For major changes, please open an issue first.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Changelog

All notable changes are documented in the [CHANGELOG.md](CHANGELOG.md) file.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
