# Module 6: Working Demo — From Zero to Deployed

We'll build and deploy a complete application to Kubernetes, using everything from the previous modules.

## What We're Building

A simple **Note-taking API** with:
- Node.js/Express backend API
- PostgreSQL database
- Full K8s deployment with ConfigMaps, Secrets, Probes, Ingress

```
┌──────────┐     ┌─────────────┐     ┌────────────┐
│  Ingress │────►│  Notes API  │────►│ PostgreSQL │
│  /api/*  │     │  (3 replicas)│     │ (StatefulSet)│
└──────────┘     └─────────────┘     └────────────┘
```

---

## Step 1: The Application Code

### `app/server.js`

```javascript
const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// Health endpoints
app.get('/healthz', (req, res) => res.status(200).json({ status: 'ok' }));
app.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch (err) {
    res.status(503).json({ status: 'not ready', error: err.message });
  }
});

// Init DB
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS notes (
      id SERIAL PRIMARY KEY,
      title VARCHAR(255) NOT NULL,
      content TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    )
  `);
}

// CRUD endpoints
app.get('/api/notes', async (req, res) => {
  const result = await pool.query('SELECT * FROM notes ORDER BY created_at DESC');
  res.json(result.rows);
});

app.post('/api/notes', async (req, res) => {
  const { title, content } = req.body;
  const result = await pool.query(
    'INSERT INTO notes (title, content) VALUES ($1, $2) RETURNING *',
    [title, content]
  );
  res.status(201).json(result.rows[0]);
});

app.delete('/api/notes/:id', async (req, res) => {
  await pool.query('DELETE FROM notes WHERE id = $1', [req.params.id]);
  res.status(204).send();
});

const PORT = process.env.PORT || 3000;
initDB().then(() => {
  app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
});
```

### `app/package.json`

```json
{
  "name": "notes-api",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "4.18.2",
    "pg": "8.11.3"
  }
}
```

### `app/Dockerfile`

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY server.js ./
EXPOSE 3000
USER node
CMD ["npm", "start"]
```

---

## Step 2: Build & Push the Image

```bash
# Option A: Using Minikube's Docker daemon (no registry needed)
eval $(minikube docker-env)
docker build -t notes-api:v1 ./app

# Option B: Push to a registry
docker build -t your-registry/notes-api:v1 ./app
docker push your-registry/notes-api:v1
```

---

## Step 3: Kubernetes Manifests

Create all manifests in `k8s/` directory.

### `k8s/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: notes-app
```

### `k8s/postgres-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: notes-app
type: Opaque
stringData:
  POSTGRES_USER: notesadmin
  POSTGRES_PASSWORD: K8sDemo2024!
  POSTGRES_DB: notesdb
```

### `k8s/postgres.yaml`

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: notes-app
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        envFrom:
        - secretRef:
            name: postgres-credentials
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "notesadmin", "-d", "notesdb"]
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: notes-app
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
  clusterIP: None
```

### `k8s/app-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: notes-app
data:
  DB_HOST: "postgres"
  DB_PORT: "5432"
  DB_NAME: "notesdb"
  PORT: "3000"
```

### `k8s/app-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-api
  namespace: notes-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: notes-api
  template:
    metadata:
      labels:
        app: notes-api
    spec:
      containers:
      - name: notes-api
        image: notes-api:v1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
        envFrom:
        - configMapRef:
            name: app-config
        env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_PASSWORD
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: notes-api
  namespace: notes-app
spec:
  selector:
    app: notes-api
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
```

### `k8s/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: notes-ingress
  namespace: notes-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: notes.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: notes-api
            port:
              number: 80
```

---

## Step 4: Deploy Everything

```bash
# 1. Start your cluster
minikube start

# 2. Enable ingress addon
minikube addons enable ingress

# 3. Use minikube's docker (so it can find our local image)
eval $(minikube docker-env)

# 4. Build the app image
docker build -t notes-api:v1 ./app

# 5. Apply manifests in order
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/app-config.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/ingress.yaml

# 6. Watch everything come up
kubectl get all -n notes-app -w
```

---

## Step 5: Verify It Works

```bash
# Check all pods are running
kubectl get pods -n notes-app
# Expected:
# NAME                         READY   STATUS    RESTARTS
# notes-api-xxxxx-yyyyy        1/1     Running   0
# notes-api-xxxxx-zzzzz        1/1     Running   0
# notes-api-xxxxx-aaaaa        1/1     Running   0
# postgres-0                   1/1     Running   0

# Check services
kubectl get svc -n notes-app

# Port-forward to test locally
kubectl port-forward svc/notes-api -n notes-app 8080:80 &

# Test the API
curl http://localhost:8080/healthz
# {"status":"ok"}

curl http://localhost:8080/ready
# {"status":"ready"}

# Create a note
curl -X POST http://localhost:8080/api/notes \
  -H "Content-Type: application/json" \
  -d '{"title": "First Note", "content": "Deployed on Kubernetes!"}'

# List notes
curl http://localhost:8080/api/notes

# Delete a note
curl -X DELETE http://localhost:8080/api/notes/1
```

### Testing via Ingress

```bash
# Get minikube IP
minikube ip

# Add to /etc/hosts
echo "$(minikube ip) notes.local" | sudo tee -a /etc/hosts

# Now access via domain
curl http://notes.local/api/notes
```

---

## Step 6: Day-2 Operations

### Scale up

```bash
kubectl scale deployment notes-api -n notes-app --replicas=5
kubectl get pods -n notes-app -w
```

### Rolling update

```bash
# Make a change to your app, rebuild
docker build -t notes-api:v2 ./app

# Update the deployment
kubectl set image deployment/notes-api notes-api=notes-api:v2 -n notes-app

# Watch the rollout
kubectl rollout status deployment/notes-api -n notes-app
```

### Rollback

```bash
kubectl rollout undo deployment/notes-api -n notes-app
```

### Check logs

```bash
# Single pod
kubectl logs -f deployment/notes-api -n notes-app

# All pods
kubectl logs -l app=notes-api -n notes-app
```

### Debug a failing pod

```bash
# Describe shows events and error details
kubectl describe pod <pod-name> -n notes-app

# Get events
kubectl get events -n notes-app --sort-by='.lastTimestamp'

# Exec into a running pod
kubectl exec -it <pod-name> -n notes-app -- /bin/sh
```

---

## Step 7: Cleanup

```bash
# Delete everything in the namespace
kubectl delete namespace notes-app

# Or delete individual resources
kubectl delete -f k8s/ 

# Stop minikube
minikube stop
```

---

## What You Just Used (Module Recap)

| Concept | Where We Used It |
|---------|-----------------|
| **Pods** | Every container runs in a pod |
| **Deployments** | notes-api with 3 replicas, rolling updates |
| **StatefulSets** | PostgreSQL with persistent storage |
| **Services** | ClusterIP for internal access |
| **Ingress** | External HTTP routing |
| **ConfigMaps** | DB host, port, app configuration |
| **Secrets** | Database credentials |
| **PVCs** | PostgreSQL data persistence |
| **Probes** | Liveness + readiness on the API |
| **Resources** | CPU/memory requests and limits |
| **Namespaces** | Isolated `notes-app` namespace |

---

## Next Steps After This Demo

1. **HorizontalPodAutoscaler** — auto-scale based on CPU/memory
2. **Helm** — package your K8s manifests into reusable charts
3. **CI/CD** — auto-deploy on git push (GitHub Actions + kubectl/ArgoCD)
4. **Monitoring** — Prometheus + Grafana stack
5. **Service Mesh** — Istio/Linkerd for advanced traffic management
6. **RBAC** — role-based access control for multi-team clusters

---

[← Module 5: Configuration & Secrets](../05-configuration/README.md) | [Back to Start →](../README.md)
