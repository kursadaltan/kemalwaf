# Installation Guide

Get kemal-waf running in a few minutes. **Easiest option: pull from Docker Hub and run. No git clone needed.**

---

## Quick Install (Docker Hub)

You only need Docker installed.

### One command

```bash
docker run -d \
  --name kemal-waf \
  -p 80:3030 \
  -p 443:3443 \
  -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  kursadaltan/kemalwaf:latest
```

Then open:

- **Admin Panel:** http://localhost:8888  
- **WAF (HTTP):** http://localhost:80  
- **WAF (HTTPS):** https://localhost:443  

The first time you open the admin panel, a setup wizard will ask you to create an admin user.

### Step-by-step (pull first, then run)

```bash
# Pull the image
docker pull kursadaltan/kemalwaf:latest

# Create volumes (first time only)
docker volume create waf-certs
docker volume create admin-data

# Run
docker run -d \
  --name kemal-waf \
  -p 80:3030 -p 443:3443 -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  kursadaltan/kemalwaf:latest
```

### Stop, start, and logs

```bash
docker stop kemal-waf    # stop
docker start kemal-waf   # start again
docker logs -f kemal-waf # watch logs
```

---

## Custom config or rules

Need your own `waf.yml` or a `rules` folder? Mount them when you run the container. You still don’t need to clone the repo—just have the files on your machine.

### Use your own config and rules

If you already have a `waf-config` and `waf-rules` folder:

```bash
docker run -d \
  --name kemal-waf \
  -p 80:3030 -p 443:3443 -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  -v $(pwd)/waf-config/waf.yml:/app/config/waf.yml:ro \
  -v $(pwd)/waf-rules:/app/rules:ro \
  kursadaltan/kemalwaf:latest
```

### Get config from GitHub (no clone)

```bash
mkdir -p waf-config waf-rules

# Example config from the repo
curl -o waf-config/waf.yml https://raw.githubusercontent.com/kursadaltan/kemalwaf/main/config/waf.yml.example

# Run with your config and rules
docker run -d \
  --name kemal-waf \
  -p 80:3030 -p 443:3443 -p 8888:8888 \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  -v $(pwd)/waf-config/waf.yml:/app/config/waf.yml:ro \
  -v $(pwd)/waf-rules:/app/rules:ro \
  kursadaltan/kemalwaf:latest
```

---

## Docker Compose (optional)

Use this if you’re developing or want to run the project’s Compose setup:

```bash
git clone https://github.com/kursadaltan/kemalwaf.git
cd kemalwaf
docker compose up -d
```

This is the only method that requires cloning the repo.

---

## What you need

- **Quick install:** [Docker](https://docs.docker.com/get-docker/) only.
- **Custom config/rules:** Local `waf.yml` and/or `rules` folder (optional).
- **Build from source:** Crystal 1.12+ (only if you build the image yourself).

---

## Next steps

- [Configuration](configuration.md) — WAF config file
- [TLS/HTTPS](tls-https.md) — SSL and certificates
- [Rules](rules.md) — Writing and managing rules
- [Deployment](deployment.md) — Production setup
