# Module 5: Configuration & Secrets

## The Problem

You don't want to bake configuration (DB URLs, API keys, feature flags) into your container image. You need a way to:
- Inject config at deployment time
- Change config without rebuilding images
- Keep secrets separate and secure

K8s gives you **ConfigMaps** (non-sensitive data) and **Secrets** (sensitive data).

---

## 1. ConfigMaps

Store non-sensitive key-value pairs or entire config files.

### Create from literal values

```bash
kubectl create configmap app-config \
  --from-literal=DATABASE_HOST=postgres \
  --from-literal=LOG_LEVEL=info \
  --from-literal=CACHE_TTL=300
```

### Create from YAML

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DATABASE_HOST: "postgres"
  LOG_LEVEL: "info"
  CACHE_TTL: "300"
```

### Create from a file

```bash
# Given a file config.properties:
# database.host=postgres
# log.level=info

kubectl create configmap app-config --from-file=config.properties
```

### Using ConfigMaps in Pods

#### As environment variables (individual keys)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: my-app
    image: my-app:v1
    env:
    - name: DATABASE_HOST
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: DATABASE_HOST
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
```

#### As environment variables (all keys at once)

```yaml
spec:
  containers:
  - name: my-app
    image: my-app:v1
    envFrom:
    - configMapRef:
        name: app-config
```

#### As mounted files (volume)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: my-app
    image: nginx
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
  volumes:
  - name: config-volume
    configMap:
      name: app-config
```

This creates files in `/etc/config/`:
```
/etc/config/DATABASE_HOST  → contains "postgres"
/etc/config/LOG_LEVEL      → contains "info"
/etc/config/CACHE_TTL      → contains "300"
```

#### Mount a specific config file

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    server {
      listen 80;
      location / {
        root /usr/share/nginx/html;
      }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: config
      mountPath: /etc/nginx/conf.d/default.conf
      subPath: nginx.conf
  volumes:
  - name: config
    configMap:
      name: nginx-config
```

---

## 2. Secrets

Like ConfigMaps but for sensitive data. Values are base64-encoded (NOT encrypted by default).

### Create from literal

```bash
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=s3cur3P@ss
```

### Create from YAML

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  username: YWRtaW4=          # base64 encoded "admin"
  password: czNjdXIzUEBzcw==  # base64 encoded "s3cur3P@ss"
```

```bash
# Encode values:
echo -n "admin" | base64        # YWRtaW4=
echo -n "s3cur3P@ss" | base64   # czNjdXIzUEBzcw==

# Or use stringData (plain text, K8s encodes it for you):
```

### Using stringData (easier)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
stringData:
  username: admin
  password: s3cur3P@ss
```

### Using Secrets in Pods

#### As environment variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: my-app
    image: my-app:v1
    env:
    - name: DB_USERNAME
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
```

#### As mounted files

```yaml
spec:
  containers:
  - name: my-app
    image: my-app:v1
    volumeMounts:
    - name: secrets
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: secrets
    secret:
      secretName: db-credentials
```

### Secret Types

| Type | Use Case |
|------|----------|
| `Opaque` | Generic key-value (default) |
| `kubernetes.io/tls` | TLS cert + key |
| `kubernetes.io/dockerconfigjson` | Docker registry credentials |
| `kubernetes.io/basic-auth` | Basic auth credentials |

### TLS Secret

```bash
kubectl create secret tls my-tls \
  --cert=tls.crt \
  --key=tls.key
```

### Docker Registry Secret

```bash
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass
```

Use it in a pod:
```yaml
spec:
  imagePullSecrets:
  - name: regcred
  containers:
  - name: app
    image: registry.example.com/my-app:v1
```

---

## 3. Important Security Notes

⚠️ Secrets are base64-encoded, NOT encrypted at rest by default.

To make secrets actually secure:
1. **Enable encryption at rest** — configure `EncryptionConfiguration` on the API server
2. **Use RBAC** — restrict who can read secrets
3. **Use external secret managers** — AWS Secrets Manager, HashiCorp Vault, etc.
4. **Don't commit secrets to git** — use sealed-secrets or external-secrets operator

---

## 4. Environment Variables

Besides ConfigMaps and Secrets, you can set env vars directly:

```yaml
spec:
  containers:
  - name: my-app
    image: my-app:v1
    env:
    # Direct value
    - name: APP_MODE
      value: "production"
    
    # From ConfigMap
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    
    # From Secret
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
    
    # From pod metadata (Downward API)
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
```

---

## 5. Resource Requests & Limits

Tell K8s how much CPU and memory your container needs.

```yaml
spec:
  containers:
  - name: my-app
    image: my-app:v1
    resources:
      requests:        # minimum guaranteed
        memory: "128Mi"
        cpu: "250m"    # 250 millicores = 0.25 CPU
      limits:          # maximum allowed
        memory: "256Mi"
        cpu: "500m"
```

### How They Work

| Setting | What It Does |
|---------|-------------|
| **Request** | Scheduler uses this to find a node with enough capacity |
| **Limit** | Container is killed (OOMKilled) or throttled if it exceeds this |

### CPU Units
- `1` = 1 full CPU core
- `500m` = 0.5 cores (milli-cores)
- `250m` = 0.25 cores

### Memory Units
- `128Mi` = 128 mebibytes
- `1Gi` = 1 gibibyte

### What Happens Without Limits

| Scenario | Result |
|----------|--------|
| No requests/limits | Pod can use all node resources (bad neighbor) |
| No limits, has requests | Guaranteed minimum, can burst higher |
| Has limits | Hard ceiling, killed/throttled if exceeded |

### QoS Classes

K8s assigns a Quality of Service class based on your resource config:

| QoS Class | When | Eviction Priority |
|-----------|------|-------------------|
| **Guaranteed** | requests == limits for all containers | Last to be evicted |
| **Burstable** | requests < limits (or only requests set) | Middle |
| **BestEffort** | No requests or limits set | First to be evicted |

---

## 6. Resource Quotas (per Namespace)

Limit total resource usage in a namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
    services: "10"
```

---

## 7. LimitRanges (defaults per Pod)

Set default requests/limits for pods that don't specify them:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-a
spec:
  limits:
  - default:          # default limits
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:   # default requests
      cpu: "100m"
      memory: "128Mi"
    type: Container
```

---

## 8. Probes (Health Checks)

Tell K8s how to check if your container is healthy.

### Liveness Probe — "Is this container alive?"

If it fails, K8s restarts the container.

```yaml
spec:
  containers:
  - name: my-app
    image: my-app:v1
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 5
      failureThreshold: 3
```

### Readiness Probe — "Is this container ready to receive traffic?"

If it fails, pod is removed from Service endpoints (no traffic sent to it).

```yaml
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 3
```

### Startup Probe — "Has this container finished starting?"

For slow-starting containers. Liveness/readiness probes don't run until startup probe succeeds.

```yaml
    startupProbe:
      httpGet:
        path: /healthz
        port: 8080
      failureThreshold: 30
      periodSeconds: 10    # gives up to 5 minutes to start
```

### Probe Methods

| Method | Example |
|--------|---------|
| HTTP GET | `httpGet: {path: /health, port: 8080}` |
| TCP Socket | `tcpSocket: {port: 3306}` |
| Exec command | `exec: {command: ["cat", "/tmp/healthy"]}` |

---

## Putting It All Together

A production-ready deployment with config, secrets, resources, and probes:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  CACHE_TTL: "300"
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
stringData:
  DB_PASSWORD: "super-secret-password"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:v1
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: app-config
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: DB_PASSWORD
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
```

---

## Useful Commands

```bash
# ConfigMaps
kubectl get configmaps
kubectl describe configmap app-config
kubectl get configmap app-config -o yaml

# Secrets
kubectl get secrets
kubectl describe secret db-credentials
kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d

# Resource usage
kubectl top pods          # requires metrics-server
kubectl top nodes
kubectl describe node     # see allocatable vs requested resources

# Check pod resource settings
kubectl get pod my-app -o jsonpath='{.spec.containers[0].resources}'
```

---

## ⚠️ Common Gotchas

### "I updated the ConfigMap but my app still has the old values"
**The mistake:** Expecting pods to auto-reload when a ConfigMap changes.
**Why it happens:** Pods read env vars at startup. They don't watch for ConfigMap changes.
**How to avoid:** After updating a ConfigMap, restart the deployment: `kubectl rollout restart deployment/<name>`. If you mount ConfigMaps as volumes, files update eventually (~60s) but your app still needs to re-read them.

### "My Secret isn't base64 encoded properly"
**The mistake:** Encoding the value with a trailing newline, or double-encoding.
**Why it happens:** `echo "password" | base64` adds a newline. Double-encoding happens when using `stringData` AND providing base64 values.
**How to avoid:** Use `echo -n "password" | base64` (the `-n` prevents newline). Better yet, use `stringData:` in your Secret YAML and provide plain text — K8s encodes it for you.

### "My pod got OOMKilled but I set generous limits"
**The mistake:** Not understanding the difference between requests and limits, or not accounting for JVM/runtime overhead.
**Why it happens:** The app uses more memory than `limits.memory` allows. For Java apps, the JVM heap is separate from native memory.
**How to avoid:** Set limits based on actual observed usage: `kubectl top pods`. Add ~20-30% headroom. For JVM apps, set `-Xmx` to less than the container memory limit.

### "Liveness probe keeps killing my pod during startup"
**The mistake:** Setting `initialDelaySeconds` too low for a slow-starting app.
**Why it happens:** App takes 30 seconds to start, but liveness probe starts checking after 5 seconds. Probe fails → K8s restarts → infinite restart loop.
**How to avoid:** Use a `startupProbe` for slow-starting apps (it disables liveness/readiness until the app is up). Or increase `initialDelaySeconds` on your liveness probe.

---

## Exercises

1. Create a ConfigMap with 3 keys. Use `envFrom` to inject all of them into a pod. Exec in and check with `env`.
2. Create a Secret with a password. Mount it as a file at `/etc/secrets/password`. Verify the content.
3. Deploy nginx with resource requests (64Mi RAM, 100m CPU) and limits (128Mi RAM, 200m CPU). Check its QoS class.
4. Add liveness and readiness probes to a deployment. Kill the health endpoint and watch K8s restart the pod.

---

[← Module 4: Networking & Storage](../04-networking-storage/README.md) | [Module 6: Working Demo →](../06-demo/README.md)
