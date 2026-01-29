# Deployment

How to run kemal-waf in production: Docker, Compose, Nginx, and Kubernetes.

## Before you go live

Before deploying to production:

- [ ] Configure TLS/HTTPS certificates
- [ ] Set up proper logging and monitoring
- [ ] Configure rate limiting
- [ ] Set up IP whitelist/blacklist
- [ ] Test rules in observe mode
- [ ] Set up backup and recovery
- [ ] Configure health checks
- [ ] Set up alerting

## Docker Deployment

### Basic Production Setup

```bash
# Create volumes
docker volume create waf-certs
docker volume create admin-data
docker volume create waf-logs

# Run with production config
docker run -d \
  --name kemal-waf \
  --restart unless-stopped \
  -p 80:3030 \
  -p 443:3443 \
  -p 8888:8888 \
  -v $(pwd)/config/waf.yml:/app/config/waf.yml:ro \
  -v $(pwd)/rules:/app/rules:ro \
  -v waf-certs:/app/config/certs \
  -v admin-data:/app/admin/data \
  -v waf-logs:/app/logs \
  kursadaltan/kemalwaf:latest
```

### Docker Compose Production

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  waf:
    image: kursadaltan/kemalwaf:latest
    container_name: kemal-waf
    restart: unless-stopped
    ports:
      - "80:3030"
      - "443:3443"
      - "8888:8888"
    volumes:
      - ./config/waf.yml:/app/config/waf.yml:ro
      - ./rules:/app/rules:ro
      - waf-certs:/app/config/certs
      - admin-data:/app/admin/data
      - waf-logs:/app/logs
    environment:
      - LOG_LEVEL=info
      - LOG_RETENTION_DAYS=90
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3030/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  waf-certs:
  admin-data:
  waf-logs:
```

Deploy:
```bash
docker compose -f docker-compose.prod.yml up -d
```

## Behind Reverse Proxy

### Nginx Configuration

See [Nginx Setup Guide](nginx-setup.md) for detailed Nginx configuration.

### Traefik Configuration

```yaml
# docker-compose.yml
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  waf:
    image: kursadaltan/kemalwaf:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.waf.rule=Host(`example.com`)"
      - "traefik.http.routers.waf.entrypoints=websecure"
      - "traefik.http.routers.waf.tls.certresolver=letsencrypt"
      - "traefik.http.services.waf.loadbalancer.server.port=3030"
```

## Kubernetes Deployment

### Basic Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kemal-waf
spec:
  replicas: 3
  selector:
    matchLabels:
      app: kemal-waf
  template:
    metadata:
      labels:
        app: kemal-waf
    spec:
      containers:
      - name: waf
        image: kursadaltan/kemalwaf:latest
        ports:
        - containerPort: 3030
          name: http
        - containerPort: 3443
          name: https
        - containerPort: 8888
          name: admin
        volumeMounts:
        - name: config
          mountPath: /app/config/waf.yml
          subPath: waf.yml
        - name: rules
          mountPath: /app/rules
        - name: certs
          mountPath: /app/config/certs
        - name: admin-data
          mountPath: /app/admin/data
        livenessProbe:
          httpGet:
            path: /health
            port: 3030
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 3030
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 2000m
            memory: 2Gi
      volumes:
      - name: config
        configMap:
          name: waf-config
      - name: rules
        configMap:
          name: waf-rules
      - name: certs
        secret:
          secretName: waf-certs
      - name: admin-data
        persistentVolumeClaim:
          claimName: waf-admin-data
---
apiVersion: v1
kind: Service
metadata:
  name: kemal-waf
spec:
  type: LoadBalancer
  selector:
    app: kemal-waf
  ports:
  - port: 80
    targetPort: 3030
    protocol: TCP
    name: http
  - port: 443
    targetPort: 3443
    protocol: TCP
    name: https
  - port: 8888
    targetPort: 8888
    protocol: TCP
    name: admin
```

### ConfigMap for Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: waf-config
data:
  waf.yml: |
    waf:
      mode: enforce
      domains:
        "example.com":
          default_upstream: "http://backend:8080"
```

## Health Checks

### HTTP Health Check

```bash
curl http://localhost:3030/health
```

Response:
```json
{
  "status": "healthy",
  "rules_loaded": 42,
  "observe_mode": false
}
```

### Docker Health Check

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3030/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

## Monitoring

### Prometheus Metrics

Access metrics at: `http://localhost:9090/metrics`

Key metrics:
- `waf_requests_total` - Total requests processed
- `waf_blocked_total` - Blocked requests
- `waf_observed_total` - Observed matches (observe mode)
- `waf_rules_loaded` - Number of loaded rules

### Grafana Dashboard

See [Monitoring Guide](monitoring.md) for Grafana dashboard setup.

## Logging

### Log Rotation

Configure log rotation in `config/waf.yml`:

```yaml
logging:
  log_dir: logs
  max_size_mb: 100
  retention_days: 30
  audit_file: logs/audit.log
```

### Log Aggregation

For production, consider:
- ELK Stack (Elasticsearch, Logstash, Kibana)
- Splunk
- CloudWatch (AWS)
- Google Cloud Logging

## Backup and Recovery

### Backup Configuration

```bash
# Backup config and rules
tar -czf waf-backup-$(date +%Y%m%d).tar.gz \
  config/waf.yml \
  rules/ \
  config/ip_whitelist.txt \
  config/ip_blacklist.txt

# Backup admin data (if using SQLite)
docker exec kemal-waf sqlite3 /app/admin/data/admin.db .dump > admin-backup.sql
```

### Restore

```bash
# Restore files
tar -xzf waf-backup-YYYYMMDD.tar.gz

# Restart container
docker restart kemal-waf
```

## Security Best Practices

1. **Use HTTPS** - Always enable TLS in production
2. **Restrict Admin Panel** - Use IP whitelist for admin access
3. **Regular Updates** - Keep WAF and rules updated
4. **Monitor Logs** - Review audit logs regularly
5. **Rate Limiting** - Configure appropriate rate limits
6. **IP Filtering** - Use whitelist/blacklist for known IPs
7. **GeoIP Blocking** - Block high-risk countries if needed
8. **Strong Passwords** - Use strong passwords for admin panel

## Performance Tuning

### Connection Pooling

Configure connection pool size in `config/waf.yml`:

```yaml
waf:
  upstream:
    pool_size: 100
    timeout: 30s
```

### Rate Limiting

Tune rate limits based on your traffic:

```yaml
rate_limiting:
  enabled: true
  default_limit: 200  # Adjust based on expected traffic
  window: 60s
  block_duration: 300s
```

### Resource Limits

For Docker:
```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
    reservations:
      cpus: '0.5'
      memory: 512M
```

## Troubleshooting

### High Memory Usage

- Reduce connection pool size
- Lower log retention days
- Check for memory leaks in rules

### High CPU Usage

- Optimize regex patterns in rules
- Reduce rule reload interval
- Use LibInjection instead of regex where possible

### Connection Errors

- Check upstream server availability
- Verify network connectivity
- Review connection pool settings

## Scaling

### Horizontal Scaling

Run multiple WAF instances behind a load balancer:

```yaml
# docker-compose.yml
services:
  waf1:
    image: kursadaltan/kemalwaf:latest
    # ...
  waf2:
    image: kursadaltan/kemalwaf:latest
    # ...
  waf3:
    image: kursadaltan/kemalwaf:latest
    # ...
```

### Load Balancer Configuration

Use sticky sessions if needed, or ensure stateless operation.

## Disaster Recovery

1. **Regular Backups** - Daily backups of config and rules
2. **Documentation** - Document all custom configurations
3. **Testing** - Regularly test restore procedures
4. **Monitoring** - Set up alerts for critical failures

