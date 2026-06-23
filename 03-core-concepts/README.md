# Module 3: Core Concepts

## The Object Hierarchy

```
Deployment (manages)
  └── ReplicaSet (manages)
       └── Pod (runs)
            └── Container(s)
```

Everything in Kubernetes is an **object** described by a YAML manifest. Let's learn each one.

---

## 1. Pods

The smallest deployable unit in Kubernetes. A pod = one or more containers that share:
- Network (same IP address, can talk via `localhost`)
- Storage (shared volumes)
- Lifecycle (created and destroyed together)

### Single-container pod (most common)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  containers:
  - name: my-app
    image: nginx:1.25
    ports:
    - containerPort: 80
```

```bash
# Create it
kubectl apply -f pod.yaml

# Check status
kubectl get pods

# See details
kubectl describe pod my-app

# See logs
kubectl logs my-app

# Exec into it
kubectl exec -it my-app -- /bin/sh

# Delete it
kubectl delete pod my-app
```

### Multi-container pod (sidecar pattern)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  containers:
  - name: app
    image: nginx:1.25
    ports:
    - containerPort: 80
  - name: log-collector
    image: busybox
    command: ["sh", "-c", "tail -f /var/log/nginx/access.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/nginx
  volumes:
  - name: logs
    emptyDir: {}
```

### Key Pod Facts
- Pods are **ephemeral** — they die and are never resurrected
- A pod gets a unique IP address within the cluster
- You almost NEVER create pods directly — use Deployments instead
- Pod status: `Pending` → `Running` → `Succeeded`/`Failed`

---

## 2. ReplicaSets

Ensures a specified number of pod replicas are running at all times.

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: my-app-rs
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
        image: nginx:1.25
```

**How it works:**
```
Desired: 3 replicas
Current: 2 running  → ReplicaSet creates 1 more
Current: 4 running  → ReplicaSet kills 1
Current: 3 running  → All good, do nothing
```

**You rarely create ReplicaSets directly** — Deployments create them for you.

---

## 3. Deployments

The most common way to run applications. A Deployment manages ReplicaSets, which manage Pods.

```yaml
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
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
```

### What Deployments Give You

| Feature | Description |
|---------|------------|
| **Rolling Updates** | Update pods gradually, no downtime |
| **Rollback** | Instantly revert to previous version |
| **Scaling** | Change replica count |
| **Self-healing** | Dead pods are automatically replaced |

### Key Commands

```bash
# Deploy
kubectl apply -f deployment.yaml

# Check status
kubectl get deployments
kubectl rollout status deployment/my-app

# Scale
kubectl scale deployment/my-app --replicas=5

# Update image (triggers rolling update)
kubectl set image deployment/my-app my-app=nginx:1.26

# Rollback
kubectl rollout undo deployment/my-app

# See revision history
kubectl rollout history deployment/my-app
```

### Rolling Update Strategy

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # max extra pods during update
      maxUnavailable: 0  # all old pods stay up until new ones are ready
```

```
Update from v1 → v2:
  v1 v1 v1          (start: 3 old pods)
  v1 v1 v1 v2       (surge: add 1 new)
  v1 v1 v2          (remove 1 old)
  v1 v1 v2 v2       (add 1 new)
  v1 v2 v2          (remove 1 old)
  v1 v2 v2 v2       (add 1 new)
  v2 v2 v2          (remove last old — done!)
```

---

## 4. Services

Pods are ephemeral (their IPs change). A **Service** provides a stable endpoint to reach a group of pods.

```
         ┌─────────────┐
         │   Service    │  ← stable IP + DNS name
         │ (ClusterIP)  │
         └──────┬───────┘
                │ load balances to:
       ┌────────┼────────┐
       ▼        ▼        ▼
   ┌──────┐ ┌──────┐ ┌──────┐
   │Pod 1 │ │Pod 2 │ │Pod 3 │   ← matched by labels
   └──────┘ └──────┘ └──────┘
```

### ClusterIP (default — internal only)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
spec:
  selector:
    app: my-app        # finds pods with this label
  ports:
  - port: 80          # service port
    targetPort: 80     # container port
  type: ClusterIP
```

Other pods reach it via: `http://my-app-service` or `http://my-app-service.default.svc.cluster.local`

### NodePort (exposes on each node's IP)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-nodeport
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080     # accessible on <NodeIP>:30080
  type: NodePort
```

### LoadBalancer (cloud provider creates an external LB)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-lb
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
```

### Service Types Summary

| Type | Accessible From | Use Case |
|------|----------------|----------|
| **ClusterIP** | Inside cluster only | Internal microservice communication |
| **NodePort** | Outside via `<NodeIP>:<port>` | Dev/testing, simple external access |
| **LoadBalancer** | External via cloud LB | Production external traffic |
| **ExternalName** | Maps to external DNS | Pointing to external services |

---

## 5. Namespaces

Virtual clusters within a cluster. Used for isolation and organization.

```bash
# See namespaces
kubectl get namespaces

# Default namespaces:
# - default         → where your stuff goes if you don't specify
# - kube-system     → K8s internal components
# - kube-public     → publicly accessible data
# - kube-node-lease → node heartbeats
```

### Creating and using namespaces

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging
```

```bash
# Create
kubectl create namespace staging

# Deploy to a namespace
kubectl apply -f deployment.yaml -n staging

# List pods in a namespace
kubectl get pods -n staging

# List pods in ALL namespaces
kubectl get pods -A

# Set default namespace for your context
kubectl config set-context --current --namespace=staging
```

### When to use namespaces
- Separate environments: `dev`, `staging`, `production`
- Separate teams: `team-a`, `team-b`
- Apply resource quotas per namespace
- Apply network policies per namespace

---

## 6. Labels & Selectors

Labels are key-value pairs attached to objects. Selectors find objects by their labels.

```yaml
metadata:
  labels:
    app: my-app
    environment: production
    version: v2
```

This is HOW Services find Pods, HOW Deployments manage Pods, and HOW you query objects:

```bash
# Find all production pods
kubectl get pods -l environment=production

# Find pods that are v2 AND production
kubectl get pods -l environment=production,version=v2

# Find pods that are NOT in production
kubectl get pods -l 'environment notin (production)'
```

---

## 7. Jobs & CronJobs

### Job — Run to completion

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-migration
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: my-migration:v1
        command: ["python", "migrate.py"]
      restartPolicy: Never
  backoffLimit: 3
```

### CronJob — Scheduled jobs

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"    # 2 AM every day
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: my-backup:v1
            command: ["./backup.sh"]
          restartPolicy: Never
```

---

## 8. DaemonSets

Ensures a pod runs on EVERY node (or a subset). Used for:
- Log collection (fluentd)
- Monitoring agents (node-exporter)
- Network plugins

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
      - name: fluentd
        image: fluentd:v1.16
```

---

## 9. StatefulSets

Like Deployments, but for **stateful** applications (databases, message queues):
- Stable, unique network identity (pod-0, pod-1, pod-2)
- Stable persistent storage
- Ordered deployment and scaling

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 3
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
        image: postgres:16
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

---

## Object Comparison

| Object | Use Case | Scaling | Persistent Identity |
|--------|----------|---------|-------------------|
| **Deployment** | Stateless apps (web servers, APIs) | Yes | No (pods are interchangeable) |
| **StatefulSet** | Stateful apps (DBs, queues) | Yes | Yes (stable names, storage) |
| **DaemonSet** | Per-node agents (logging, monitoring) | Auto (one per node) | No |
| **Job** | One-off tasks | Parallelism | No |
| **CronJob** | Scheduled tasks | Per schedule | No |

---

## ⚠️ Common Gotchas

### "I deleted the pod but it came back!"
**The mistake:** Trying to stop an app by deleting pods directly.
**Why it happens:** It's intuitive — you don't want the pod, so you delete it.
**How to avoid:** If the pod is managed by a Deployment/ReplicaSet, deleting the pod just makes the controller create a new one (that's self-healing!). To actually remove it, delete the Deployment: `kubectl delete deployment <name>`.

### "My selector doesn't match and I can't figure out why"
**The mistake:** Deployment's `spec.selector.matchLabels` doesn't match `spec.template.metadata.labels`.
**Why it happens:** Copy-paste errors, or not understanding that these MUST be identical.
**How to avoid:** The selector tells the Deployment which pods belong to it. If they don't match, you get an error on apply. Always make `selector.matchLabels` exactly match `template.metadata.labels`.

### "I set replicas to 5 but I only see 3 pods"
**The mistake:** Not checking if the cluster has enough resources.
**Why it happens:** You assume scaling always works.
**How to avoid:** Check `kubectl describe pod <pending-pod>` — Events will tell you if there's insufficient CPU/memory. Either reduce resource requests or add nodes.

### "I updated my Deployment YAML but nothing changed"
**The mistake:** Changing something that doesn't trigger a rollout (like adding an annotation).
**Why it happens:** Rollouts only trigger when `spec.template` changes (container image, env vars, resources, etc.).
**How to avoid:** If you changed a ConfigMap, pods won't auto-restart. Use `kubectl rollout restart deployment/<name>` to force a refresh.

---

## Exercises

1. Create a Deployment with 3 replicas of `nginx:1.25`. Scale it to 5. Then update to `nginx:1.26` and watch the rolling update.
2. Create a ClusterIP Service for the above Deployment. Exec into another pod and `curl` the service name.
3. Create a namespace called `test`. Deploy something in it. Delete the entire namespace.
4. Create a Job that runs `echo "hello kubernetes"` and completes.

### Try These Commands

```bash
# Watch pods in real-time
kubectl get pods -w

# See all resources in default namespace
kubectl get all

# Get YAML output of existing resource
kubectl get deployment my-app -o yaml

# Dry-run to generate YAML
kubectl create deployment test --image=nginx --dry-run=client -o yaml
```

---

[← Module 2: Architecture](../02-architecture/README.md) | [Module 4: Networking & Storage →](../04-networking-storage/README.md)
