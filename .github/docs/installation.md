# Installation Guide

This guide covers different installation methods for kemal-waf.

## Prerequisites

- Docker and Docker Compose (recommended)
- Or Crystal 1.12.0+ for manual installation

## Quick Start with Docker Compose

The easiest way to get started:

```bash
# Clone the repository
git clone https://github.com/kursadaltan/kemalwaf.git
cd kemalwaf

# Start with Docker Compose
docker compose up -d

# Access the services:
# - Admin Panel: http://localhost:8888
# - WAF HTTP: http://localhost:80
# - WAF HTTPS: https://localhost:443
```

On first access, the admin panel will guide you through setup wizard to create your admin user.

## Docker Run

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

## Running from Docker Hub

### Quick Start with Admin Panel

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

### WAF Only (Legacy, without Admin Panel)

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

### Running with Custom Rules

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

## Direct Build on macOS (Without Docker)

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

## Deploy Options

### Option 1: Standalone (Default - Admin Panel at root `/`)

```bash
# Build with default settings
make docker-build
# or
docker compose build

# Admin Panel: http://localhost:8888/
# API: http://localhost:8888/api/
```

### Option 2: Behind Nginx Reverse Proxy (Admin Panel at subpath `/admin/`)

```bash
# Build with Nginx subpath support
make docker-build-nginx
# or
docker compose build --build-arg VITE_BASE_PATH=/admin/

# Admin Panel: https://yourdomain.com/admin/
# API: https://yourdomain.com/admin/api/
```

See [Nginx Setup Guide](nginx-setup.md) for Nginx configuration details.

## Next Steps

After installation:

1. **Configure WAF:** See [Configuration Guide](configuration.md)
2. **Set up TLS/HTTPS:** See [TLS/HTTPS Setup](tls-https.md)
3. **Create Rules:** See [Rule Format](rules.md)
4. **Deploy to Production:** See [Deployment Guide](deployment.md)

