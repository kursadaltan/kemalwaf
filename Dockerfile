# Multi-stage Dockerfile for kemal-waf with Admin Panel
# Stage 1: Build WAF
FROM crystallang/crystal:1.12.0-alpine AS waf-builder

WORKDIR /app

# Install build dependencies + LibInjection build dependencies
RUN apk add --no-cache \
    openssl-dev libevent-dev pcre2-dev yaml-dev zlib-dev \
    git make gcc musl-dev

# Build LibInjection static library
RUN git clone https://github.com/libinjection/libinjection.git /tmp/libinjection && \
    cd /tmp/libinjection/src && \
    gcc -c -O2 -fPIC -DLIBINJECTION_VERSION=\"5.0.0\" \
        libinjection_sqli.c libinjection_xss.c libinjection_html5.c reader.c \
        -I. && \
    ar rcs /tmp/libinjection.a *.o && \
    mkdir -p /app/lib/libinjection && \
    cp /tmp/libinjection.a /app/lib/libinjection/ && \
    cp libinjection.h libinjection_sqli.h libinjection_xss.h libinjection_html5.h libinjection_error.h /app/lib/libinjection/ && \
    rm -rf /tmp/libinjection /tmp/libinjection.a *.o

# Copy shard files
COPY shard.yml ./

# Install dependencies
RUN shards install

# Copy source code
COPY src/ ./src/

# Create bin directory
RUN mkdir -p bin

# Build the application with LibInjection
RUN crystal build --release --no-debug \
    --link-flags "-L/app/lib/libinjection -linjection" \
    -o bin/kemal-waf src/waf.cr

# Stage 2: Build Admin Frontend
FROM node:20-alpine AS admin-frontend-builder

# Build argument for base path (can be overridden during build)
ARG VITE_BASE_PATH=/

WORKDIR /app

# Copy admin-ui files
COPY admin-ui/ ./admin-ui/

# Create admin directory for build output
RUN mkdir -p ./admin/public

# Install dependencies
WORKDIR /app/admin-ui
RUN npm ci

# Build frontend with dynamic base path
# Default: "/" (standalone)
# With --build-arg VITE_BASE_PATH=/admin/ for Nginx subpath
ENV VITE_BASE_PATH=${VITE_BASE_PATH}
RUN npm run build

# Stage 3: Build Admin Backend
FROM crystallang/crystal:1.12.0-alpine AS admin-backend-builder

WORKDIR /app/admin

# Install build dependencies
RUN apk add --no-cache \
    openssl-dev libevent-dev pcre2-dev yaml-dev zlib-dev \
    git make gcc musl-dev sqlite-dev

# Copy admin shard files
COPY admin/shard.yml ./

# Install dependencies
RUN shards install

# Copy admin source code
COPY admin/src/ ./src/

# Create bin directory
RUN mkdir -p bin

# Build admin backend
RUN crystal build --release --no-debug \
    -o bin/kemal-waf-admin src/admin.cr

# Stage 4: Runtime
FROM alpine:3.19

WORKDIR /app

# Install runtime dependencies (shared libraries) + Certbot for Let's Encrypt + SQLite for admin
RUN apk add --no-cache \
    ca-certificates \
    openssl \
    libevent \
    yaml \
    pcre2 \
    gc \
    gcc \
    certbot \
    python3 \
    py3-pip \
    sqlite-libs \
    bash

# Copy WAF binary from waf-builder
COPY --from=waf-builder /app/bin/kemal-waf /app/kemal-waf

# Copy Admin backend binary from admin-backend-builder
COPY --from=admin-backend-builder /app/admin/bin/kemal-waf-admin /app/admin/kemal-waf-admin

# Copy Admin frontend build from admin-frontend-builder
COPY --from=admin-frontend-builder /app/admin/public /app/admin/public

# Copy rules directory
COPY rules/ /app/rules/

# Copy admin config
COPY admin/config/admin.yml /app/admin/config/admin.yml

# Create non-root user
RUN addgroup -g 1000 waf && \
    adduser -D -u 1000 -G waf waf && \
    chown -R waf:waf /app

# Create necessary directories with proper permissions
RUN mkdir -p /app/config/certs/letsencrypt/webroot/.well-known/acme-challenge && \
    mkdir -p /app/logs && \
    mkdir -p /app/admin/data && \
    chown -R waf:waf /app/config/certs /app/logs /app/admin/data

# Certbot needs to write to /etc/letsencrypt
RUN mkdir -p /etc/letsencrypt && \
    chown -R waf:waf /etc/letsencrypt

# Create startup script to run both WAF and Admin
RUN echo '#!/bin/bash' > /app/start.sh && \
    echo 'set -e' >> /app/start.sh && \
    echo 'echo "🚀 Starting Kemal WAF..."' >> /app/start.sh && \
    echo '/app/kemal-waf &' >> /app/start.sh && \
    echo 'WAF_PID=$!' >> /app/start.sh && \
    echo 'echo "🔧 Starting Admin Panel..."' >> /app/start.sh && \
    echo 'cd /app/admin && ./kemal-waf-admin &' >> /app/start.sh && \
    echo 'ADMIN_PID=$!' >> /app/start.sh && \
    echo 'echo "✅ Services started - WAF: $WAF_PID, Admin: $ADMIN_PID"' >> /app/start.sh && \
    echo 'wait -n' >> /app/start.sh && \
    echo 'exit $?' >> /app/start.sh && \
    chmod +x /app/start.sh && \
    chown waf:waf /app/start.sh

USER waf

# Environment defaults
ENV RULE_DIR=/app/rules
ENV UPSTREAM=http://upstream:8080
ENV OBSERVE=false
ENV BODY_LIMIT_BYTES=1048576
ENV RELOAD_INTERVAL_SEC=5

# Expose HTTP, HTTPS and Admin ports
EXPOSE 3030 3443 8888

CMD ["/app/start.sh"]

