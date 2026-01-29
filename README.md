# kemal-waf

[![CI/CD](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/kursadaltan/kemalwaf/actions/workflows/ci-cd.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Crystal](https://img.shields.io/badge/Crystal-1.12.0-blue.svg)](https://crystal-lang.org/)
[![Kemal](https://img.shields.io/badge/Built%20with-Kemal-green.svg)](https://github.com/kemalcr/kemal)

A Web Application Firewall (WAF) built with [Kemal](https://github.com/kemalcr/kemal). Supports OWASP CRS rules, a web admin panel, and runs from a single Docker image.

## Features

- **OWASP CRS** — SQLi, XSS, and other attacks (LibInjection)
- **Web Admin Panel** — Manage domains and rules in the browser
- **TLS/HTTPS** — Let's Encrypt and custom certs
- **Hot reload** — Change rules without restarting
- **Prometheus metrics** — Built-in `/metrics` endpoint
- **Rate limiting** — Per-IP throttling
- **IP filtering** — Whitelist/blacklist (CIDR)
- **GeoIP** — Block or allow by country

## Quick Start

No git clone. Pull and run:

```bash
docker run -d \
  --name kemal-waf \
  -p 80:3030 -p 443:3443 -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  kursadaltan/kemalwaf:latest
```

**Then open:**

- **Admin Panel:** http://localhost:8888  
- **WAF (HTTP):** http://localhost:80  
- **WAF (HTTPS):** https://localhost:443  

First time: the admin panel runs a setup wizard to create your admin user.

**More options (custom config, rules, Compose):** [Installation Guide](docs/installation.md)

## Documentation

- **[Installation](docs/installation.md)** — Get up and running
- **[Configuration](docs/configuration.md)** — WAF config
- **[Rules](docs/rules.md)** — Write and manage rules
- **[TLS/HTTPS](docs/tls-https.md)** — SSL setup
- **[Deployment](docs/deployment.md)** — Production
- **[Nginx](docs/nginx-setup.md)** — Reverse proxy
- **[Environment variables](docs/environment-variables.md)** — All env vars
- **[GeoIP](docs/GEOIP.md)** — Country blocking
- **[API](docs/api.md)** — Endpoints

Also: [GitHub Pages](https://kursadaltan.github.io/kemalwaf/) · [Wiki](https://github.com/kursadaltan/kemalwaf/wiki)

## Architecture

```
Client → kemal-waf (rules, proxy, metrics) → Upstream
```

## Contributing

Pull requests welcome. For big changes, open an issue first. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache 2.0. See [LICENSE](LICENSE).
