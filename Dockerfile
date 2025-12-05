# Multi-stage Dockerfile for kemal-waf
# Stage 1: Build
FROM crystallang/crystal:1.12.0-alpine AS builder

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
# Note: shard.lock is optional, will be generated if missing
RUN shards install

# Copy source code
COPY src/ ./src/

# Create bin directory
RUN mkdir -p bin

# Build the application with LibInjection
RUN crystal build --release --no-debug \
    --link-flags "-L/app/lib/libinjection -linjection" \
    -o bin/kemal-waf src/waf.cr

# Stage 2: Runtime
FROM alpine:3.19

WORKDIR /app

# Install runtime dependencies (shared libraries) + Certbot for Let's Encrypt
# Note: libgcc_s is provided by gcc package (we only need the libs)
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
    py3-pip

# Copy binary from builder
COPY --from=builder /app/bin/kemal-waf /app/kemal-waf

# Copy rules directory
COPY rules/ /app/rules/

# Create non-root user
RUN addgroup -g 1000 waf && \
    adduser -D -u 1000 -G waf waf && \
    chown -R waf:waf /app

# Create config/certs directory with proper permissions for Let's Encrypt
RUN mkdir -p /app/config/certs/letsencrypt/webroot/.well-known/acme-challenge && \
    mkdir -p /app/logs && \
    chown -R waf:waf /app/config/certs /app/logs

# Certbot needs to write to /etc/letsencrypt
RUN mkdir -p /etc/letsencrypt && \
    chown -R waf:waf /etc/letsencrypt

USER waf

# Environment defaults
ENV RULE_DIR=/app/rules
ENV UPSTREAM=http://upstream:8080
ENV OBSERVE=false
ENV BODY_LIMIT_BYTES=1048576
ENV RELOAD_INTERVAL_SEC=5

# Expose HTTP and HTTPS ports
EXPOSE 3030 3443

CMD ["/app/kemal-waf"]

