# Nginx Reverse Proxy

Run the admin panel behind Nginx (e.g. at `https://yourdomain.com/admin/`).

**You need to:**  
1. Build the image with subpath support (`VITE_BASE_PATH=/admin/`)  
2. Configure Nginx to proxy to the WAF and admin ports  

## Build with subpath support

### Option 1: Using Make

```bash
make docker-build-nginx
```

### Option 2: Using Docker Compose

```bash
docker compose build --build-arg VITE_BASE_PATH=/admin/
```

### Option 3: Using Docker Build

```bash
docker build --build-arg VITE_BASE_PATH=/admin/ -t kemal-waf:latest .
```

## Nginx Configuration

### Option A: Nginx Proxy Manager (GUI)

In your Proxy Host configuration for `yourdomain.com`, add these location blocks in the **Custom Nginx Configuration** section:

```nginx
# Admin Panel UI - /admin path
location /admin/ {
    proxy_pass http://kemal-waf:8888/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

# Admin API - /admin/api path
location /admin/api/ {
    proxy_pass http://kemal-waf:8888/api/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# Main WAF - proxy to backend
location / {
    proxy_pass http://kemal-waf:3030;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

### Option B: Standard Nginx Config

```nginx
server {
    listen 443 ssl http2;
    server_name yourdomain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # Admin Panel
    location /admin/ {
        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Admin API
    location /admin/api/ {
        proxy_pass http://127.0.0.1:8888/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Main application (proxied through WAF)
    location / {
        proxy_pass http://127.0.0.1:3030;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Alternative: Subdomain Setup

If you prefer a subdomain instead of a subpath (e.g., `admin.yourdomain.com`):

1. **Build with default settings** (no `VITE_BASE_PATH` needed):
   ```bash
   make docker-build
   ```

2. **Create separate Nginx server block:**
   ```nginx
   server {
       listen 443 ssl http2;
       server_name admin.yourdomain.com;
       
       ssl_certificate /path/to/cert.pem;
       ssl_certificate_key /path/to/key.pem;
       
       location / {
           proxy_pass http://127.0.0.1:8888;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
       }
   }
   ```

## Docker Compose with Nginx

```yaml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - waf

  waf:
    image: kemal-waf:latest
    build:
      context: .
      args:
        VITE_BASE_PATH: /admin/
    expose:
      - "3030"
      - "3443"
      - "8888"
    volumes:
      - ./config/waf.yml:/app/config/waf.yml:ro
      - ./rules:/app/rules:ro
```

## Important Notes

### Trailing Slashes

- Admin Panel: `/admin/` (with trailing slash)
- Admin API: `/admin/api/` (with trailing slash)
- Proxy pass: Use trailing slash in `proxy_pass` URL

### WebSocket Support

The Admin Panel uses WebSockets for real-time updates. Ensure your Nginx config includes:

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### Headers

Always forward these headers:
- `Host` - Original host header
- `X-Real-IP` - Client IP
- `X-Forwarded-For` - Forwarded IP chain
- `X-Forwarded-Proto` - Original protocol (http/https)

## Testing

After configuration:

1. **Test Admin Panel:**
   ```bash
   curl -I https://yourdomain.com/admin/
   ```

2. **Test Admin API:**
   ```bash
   curl https://yourdomain.com/admin/api/health
   ```

3. **Test WAF:**
   ```bash
   curl https://yourdomain.com/
   ```

## Troubleshooting

### 404 Errors

- Check that `VITE_BASE_PATH` matches your Nginx location path
- Verify trailing slashes in Nginx config
- Check Nginx error logs: `tail -f /var/log/nginx/error.log`

### WebSocket Not Working

- Ensure WebSocket headers are set correctly
- Check that `proxy_http_version 1.1` is set
- Verify `Upgrade` and `Connection` headers

### API Not Found

- Verify API path matches: `/admin/api/`
- Check that `proxy_pass` URL has trailing slash
- Ensure API routes are correctly proxied

## Security Considerations

1. **Restrict Admin Access:**
   ```nginx
   location /admin/ {
       allow 192.168.1.0/24;  # Your office IP range
       deny all;
       # ... proxy settings
   }
   ```

2. **Use HTTPS:**
   - Always use SSL/TLS in production
   - Redirect HTTP to HTTPS

3. **Rate Limiting:**
   ```nginx
   limit_req_zone $binary_remote_addr zone=admin:10m rate=10r/m;
   
   location /admin/ {
       limit_req zone=admin burst=5;
       # ... proxy settings
   }
   ```

