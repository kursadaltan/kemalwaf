# Build stage - Crystal backend
FROM crystallang/crystal:1.12.0-alpine AS backend-builder

WORKDIR /build

# Install dependencies
RUN apk add --no-cache \
    sqlite-dev \
    sqlite-static \
    yaml-dev \
    yaml-static \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static

# Copy shard files
COPY shard.yml ./

# Install dependencies
RUN shards install --production

# Copy source files
COPY src/ src/
COPY config/ config/

# Build binary
RUN crystal build src/admin.cr \
    -o bin/kemal-waf-admin \
    --release \
    --static \
    --no-debug \
    -Dpreview_mt

# Build stage - Frontend
FROM node:20-alpine AS frontend-builder

WORKDIR /build

# Copy package files
COPY ../admin-ui/package*.json ./

# Install dependencies
RUN npm ci

# Copy source files
COPY ../admin-ui/ ./

# Build frontend
RUN npm run build

# Runtime stage
FROM alpine:3.19

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    sqlite-libs

# Create directories
RUN mkdir -p /app/config /app/data /app/public

# Copy binary from builder
COPY --from=backend-builder /build/bin/kemal-waf-admin /app/bin/kemal-waf-admin

# Copy frontend assets
COPY --from=frontend-builder /build/../admin/public/ /app/public/

# Copy default config
COPY config/admin.yml /app/config/admin.yml

# Set permissions
RUN chmod +x /app/bin/kemal-waf-admin

# Expose port
EXPOSE 8888

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8888/api/health || exit 1

# Run
CMD ["/app/bin/kemal-waf-admin"]

