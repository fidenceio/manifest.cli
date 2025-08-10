# Manifest Deployment Guide

This guide covers deploying the enhanced Manifest system across different environments and platforms.

## 🚀 Quick Deployment

### Local Development

1. **Clone and setup**
   ```bash
   git clone <repository-url>
   cd fidenceio.manifest
   npm install
   ```

2. **Environment configuration**
   ```bash
   cp env.example .env
   # Edit .env with your configuration
   ```

3. **Start services**
   ```bash
   # Start dependencies
   docker-compose up -d db redis
   
   # Start Manifest
   npm run dev
   ```

### Docker Deployment

1. **Build image**
   ```bash
   docker build -t manifest:latest .
   ```

2. **Run container**
   ```bash
   docker run -d \
     --name manifest \
     -p 3000:3000 \
     -e NODE_ENV=production \
     -e DATABASE_URL=postgresql://user:pass@host:5432/manifest \
     -e REDIS_URL=redis://host:6379 \
     manifest:latest
   ```

## 🐳 Docker Compose Deployment

### Basic Setup

```yaml
# docker-compose.yml
version: '3.8'
services:
  manifest:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://manifest:password@db:5432/manifest
      - REDIS_URL=redis://redis:6379
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - JWT_SECRET=${JWT_SECRET}
    depends_on:
      - db
      - redis
    restart: unless-stopped
    volumes:
      - ./logs:/app/logs
      - ./config:/app/config
  
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=manifest
      - POSTGRES_USER=manifest
      - POSTGRES_PASSWORD=password
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql
    restart: unless-stopped
  
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped
  
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - manifest
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
```

### Production Configuration

```yaml
# docker-compose.prod.yml
version: '3.8'
services:
  manifest:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_URL=${REDIS_URL}
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - JWT_SECRET=${JWT_SECRET}
      - RATE_LIMIT_WINDOW=${RATE_LIMIT_WINDOW:-900000}
      - RATE_LIMIT_MAX=${RATE_LIMIT_MAX:-100}
    depends_on:
      - db
      - redis
    restart: unless-stopped
    volumes:
      - ./logs:/app/logs
      - ./config:/app/config
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 512M
          cpus: '0.25'
  
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups:/backups
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
  
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.25'
  
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - manifest
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.1'

volumes:
  postgres_data:
  redis_data:
```

## ☸️ Kubernetes Deployment

### Namespace and ConfigMap

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: manifest
  labels:
    name: manifest
```

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: manifest-config
  namespace: manifest
data:
  NODE_ENV: "production"
  RATE_LIMIT_WINDOW: "900000"
  RATE_LIMIT_MAX: "100"
  LOG_LEVEL: "info"
```

### Secrets

```yaml
# secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: manifest-secrets
  namespace: manifest
type: Opaque
data:
  database-url: <base64-encoded-database-url>
  redis-url: <base64-encoded-redis-url>
  github-token: <base64-encoded-github-token>
  jwt-secret: <base64-encoded-jwt-secret>
```

### Deployment

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: manifest
  namespace: manifest
  labels:
    app: manifest
spec:
  replicas: 3
  selector:
    matchLabels:
      app: manifest
  template:
    metadata:
      labels:
        app: manifest
    spec:
      containers:
      - name: manifest
        image: manifest:latest
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          valueFrom:
            configMapKeyRef:
              name: manifest-config
              key: NODE_ENV
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: manifest-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: manifest-secrets
              key: redis-url
        - name: GITHUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: manifest-secrets
              key: github-token
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: manifest-secrets
              key: jwt-secret
        resources:
          limits:
            memory: "1Gi"
            cpu: "500m"
          requests:
            memory: "512Mi"
            cpu: "250m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: logs
          mountPath: /app/logs
        - name: config
          mountPath: /app/config
      volumes:
      - name: logs
        emptyDir: {}
      - name: config
        configMap:
          name: manifest-config
```

### Service

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: manifest-service
  namespace: manifest
spec:
  selector:
    app: manifest
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
  type: ClusterIP
```

### Ingress

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: manifest-ingress
  namespace: manifest
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - manifest.example.com
    secretName: manifest-tls
  rules:
  - host: manifest.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: manifest-service
            port:
              number: 80
```

## 🔧 Environment Configuration

### Required Environment Variables

```bash
# Server Configuration
PORT=3000
NODE_ENV=production

# Database Configuration
DATABASE_URL=postgresql://user:password@host:5432/manifest
REDIS_URL=redis://host:6379

# GitHub Configuration
GITHUB_TOKEN=your_github_token
GITHUB_WEBHOOK_SECRET=your_webhook_secret

# Security
JWT_SECRET=your_jwt_secret
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX=100

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
LOG_OUTPUT=stdout

# Monitoring
HEALTH_CHECK_INTERVAL=30000
METRICS_ENABLED=true
```

### Optional Environment Variables

```bash
# Slack Notifications
SLACK_WEBHOOK_URL=your_slack_webhook
SLACK_CHANNEL=#releases

# Email Notifications
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user@example.com
SMTP_PASS=password
SMTP_FROM=manifest@example.com

# Custom Configuration
MANIFEST_CONFIG_PATH=/app/config/.manifestrc
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
```

## 📊 Monitoring and Health Checks

### Health Check Endpoint

```bash
# Check service health
curl http://localhost:3000/health

# Check repository health
curl http://localhost:3000/api/v1/manifest/{repoPath}/health
```

### Prometheus Metrics

```yaml
# prometheus-config.yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'manifest'
    static_configs:
      - targets: ['manifest-service:3000']
    metrics_path: /metrics
    scrape_interval: 5s
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Manifest Dashboard",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{route}}"
          }
        ]
      },
      {
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      }
    ]
  }
}
```

## 🔒 Security Configuration

### SSL/TLS Setup

```nginx
# nginx.conf
server {
    listen 80;
    server_name manifest.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name manifest.example.com;
    
    ssl_certificate /etc/nginx/ssl/manifest.crt;
    ssl_certificate_key /etc/nginx/ssl/manifest.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    
    location / {
        proxy_pass http://manifest:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Authentication Setup

```javascript
// middleware/auth.js
const jwt = require('jsonwebtoken');

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }
  
  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid token' });
    }
    req.user = user;
    next();
  });
};

module.exports = { authenticateToken };
```

## 🚀 Deployment Scripts

### Automated Deployment

```bash
#!/bin/bash
# deploy.sh

set -e

echo "🚀 Starting Manifest deployment..."

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Build and deploy
echo "📦 Building Manifest image..."
docker-compose build

echo "🔄 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 30

echo "🔍 Checking service health..."
curl -f http://localhost:3000/health || { echo "Service health check failed. Aborting." >&2; exit 1; }

echo "✅ Manifest deployment completed successfully!"
echo "🌐 Service available at: http://localhost:3000"
echo "📊 Health check: http://localhost:3000/health"
```

### Production Deployment

```bash
#!/bin/bash
# deploy-prod.sh

set -e

echo "🚀 Starting production deployment..."

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "Helm is required but not installed. Aborting." >&2; exit 1; }

# Load environment variables
if [ -f .env.prod ]; then
    export $(cat .env.prod | grep -v '^#' | xargs)
fi

# Create namespace
echo "📁 Creating namespace..."
kubectl apply -f k8s/namespace.yaml

# Apply secrets
echo "🔐 Applying secrets..."
kubectl apply -f k8s/secrets.yaml

# Apply config
echo "⚙️ Applying configuration..."
kubectl apply -f k8s/configmap.yaml

# Deploy application
echo "🚀 Deploying application..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# Wait for deployment
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/manifest -n manifest

echo "✅ Production deployment completed successfully!"
echo "🌐 Service available at: https://manifest.example.com"
```

## 📝 Post-Deployment Checklist

- [ ] **Service Health**: Verify `/health` endpoint returns 200
- [ ] **Database Connection**: Check database connectivity
- [ ] **Redis Connection**: Verify Redis connectivity
- [ ] **GitHub Integration**: Test GitHub API connectivity
- [ ] **Logs**: Verify logging is working correctly
- [ ] **Metrics**: Check Prometheus metrics endpoint
- [ ] **SSL/TLS**: Verify HTTPS is working
- [ ] **Authentication**: Test JWT authentication
- [ ] **Rate Limiting**: Verify rate limiting is active
- **Backup**: Test database backup functionality
- [ ] **Monitoring**: Verify Grafana dashboard is accessible
- [ ] **Alerts**: Test alerting system

## 🆘 Troubleshooting

### Common Issues

1. **Database Connection Failed**
   ```bash
   # Check database status
   docker-compose logs db
   
   # Test connection
   docker-compose exec db psql -U manifest -d manifest
   ```

2. **Redis Connection Failed**
   ```bash
   # Check Redis status
   docker-compose logs redis
   
   # Test connection
   docker-compose exec redis redis-cli ping
   ```

3. **Service Not Starting**
   ```bash
   # Check service logs
   docker-compose logs manifest
   
   # Check environment variables
   docker-compose exec manifest env | grep -E "(DATABASE|REDIS|GITHUB)"
   ```

4. **Health Check Failing**
   ```bash
   # Check service status
   curl -v http://localhost:3000/health
   
   # Check dependencies
   docker-compose ps
   ```

### Log Analysis

```bash
# View real-time logs
docker-compose logs -f manifest

# Search for errors
docker-compose logs manifest | grep -i error

# Check specific time range
docker-compose logs manifest --since="2024-01-01T00:00:00"
```

## 🔄 Updates and Maintenance

### Rolling Updates

```bash
# Update image
docker-compose pull manifest

# Rolling restart
docker-compose up -d --no-deps manifest

# Verify update
docker-compose ps manifest
```

### Database Migrations

```bash
# Backup before migration
docker-compose exec db pg_dump -U manifest manifest > backup.sql

# Run migrations
docker-compose exec manifest npm run migrate

# Verify migration
docker-compose exec manifest npm run migrate:status
```

### Monitoring Updates

```bash
# Update monitoring stack
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring-values.yaml

# Verify update
kubectl get pods -n monitoring
```

---

For additional support, refer to the [README.md](README.md) or create an issue in the repository.
