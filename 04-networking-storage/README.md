# Module 4: Networking & Storage

## Part A: Networking

### Kubernetes Networking Model

K8s has a flat network with these rules:
1. Every pod gets its own unique IP address
2. All pods can communicate with all other pods without NAT
3. All nodes can communicate with all pods without NAT
4. The IP a pod sees for itself is the same IP others see for it

```
┌─────────────────────────────────────────────┐
│              Cluster Network                  │
│                                              │
│  Node 1                    Node 2            │
│  ┌──────────────┐         ┌──────────────┐  │
│  │ Pod A        │         │ Pod C        │  │
│  │ 10.244.1.5   │◄───────►│ 10.244.2.3   │  │
│  │              │         │              │  │
│  │ Pod B        │         │ Pod D        │  │
│  │ 10.244.1.6   │◄───────►│ 10.244.2.4   │  │
│  └──────────────┘         └──────────────┘  │
│                                              │
│  All pods can reach all other pods directly  │
└─────────────────────────────────────────────┘
```

### Communication Types

| From → To | How |
|-----------|-----|
| Pod → Pod (same node) | Direct via virtual bridge |
| Pod → Pod (different node) | Via CNI plugin (overlay/routing) |
| Pod → Service | Via kube-proxy (iptables/IPVS) |
| External → Pod | Via NodePort, LoadBalancer, or Ingress |

### CNI (Container Network Interface)

The CNI plugin implements the actual network. Popular choices:

| Plugin | Approach | Best For |
|--------|----------|----------|
| **Calico** | BGP routing or VXLAN | Most production clusters |
| **Flannel** | VXLAN overlay | Simple setups |
| **Cilium** | eBPF-based | Performance, observability |
| **Weave** | Mesh overlay | Easy setup |

You install one when setting up a cluster. Minikube handles this for you.

---

### DNS in Kubernetes

Every Service gets a DNS entry automatically via CoreDNS:

```
<service-name>.<namespace>.svc.cluster.local
```

Examples:
```bash
# From within the same namespace:
curl http://my-api

# From a different namespace:
curl http://my-api.staging.svc.cluster.local

# Pod DNS (less common):
# 10-244-1-5.default.pod.cluster.local
```

---

### Ingress

A Service exposes your app, but **Ingress** provides:
- HTTP/HTTPS routing
- Host-based routing (different domains → different services)
- Path-based routing (/api → service-a, /web → service-b)
- TLS termination

```
Internet → Ingress Controller → Ingress Rules → Services → Pods
```

#### Step 1: Install an Ingress Controller

```bash
# For Minikube:
minikube addons enable ingress

# For production: install nginx-ingress or traefik
```

#### Step 2: Create Ingress resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-api
            port:
              number: 8080
```

#### Multiple hosts

```yaml
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
```

#### TLS (HTTPS)

```yaml
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls-secret   # contains cert + key
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

---

### Network Policies

By default, all pods can talk to all other pods. **NetworkPolicies** restrict this.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-frontend
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

This means: `backend` pods ONLY accept traffic from `frontend` pods on port 8080.

```
frontend (app: frontend) ──TCP:8080──► backend (app: backend)  ✓
random-pod ──────────────────────────► backend                  ✗ blocked
```

---

## Part B: Storage

### The Problem

Containers have ephemeral filesystems — data is lost when a container restarts. For databases, uploads, or any persistent data, you need volumes.

### Volume Types Overview

| Type | Lifetime | Use Case |
|------|----------|----------|
| `emptyDir` | Pod lifetime | Temp scratch space, shared between containers |
| `hostPath` | Node lifetime | Dev only, maps to host filesystem |
| `PersistentVolume` | Independent of pods | Databases, file storage |
| `configMap` / `secret` | As long as the object exists | Config files mounted as volumes |

---

### emptyDir

Created when a pod starts. Deleted when the pod is deleted. Useful for sharing data between containers in the same pod.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-storage
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo hello > /data/message && sleep 3600"]
    volumeMounts:
    - name: shared
      mountPath: /data
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /data/message && sleep 3600"]
    volumeMounts:
    - name: shared
      mountPath: /data
  volumes:
  - name: shared
    emptyDir: {}
```

---

### Persistent Volumes (PV) & Persistent Volume Claims (PVC)

This is the main storage system in K8s:

```
┌────────────┐        ┌──────────────┐        ┌─────────────────┐
│    Pod     │ mounts │     PVC      │ binds  │       PV        │
│            │───────►│ (request)    │───────►│ (actual disk)   │
│            │        │ "I need 10Gi"│        │ AWS EBS / NFS / │
└────────────┘        └──────────────┘        │ local disk      │
                                              └─────────────────┘
```

**PV** = The actual storage resource (created by admin or dynamically)
**PVC** = A request for storage (created by developer)

#### Create a PersistentVolume

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:                    # for local dev only
    path: /mnt/data
```

#### Create a PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

#### Use PVC in a Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-storage
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: storage
      mountPath: /usr/share/nginx/html
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: my-pvc
```

### Access Modes

| Mode | Abbreviation | Description |
|------|-------------|-------------|
| ReadWriteOnce | RWO | One node can mount read-write |
| ReadOnlyMany | ROX | Many nodes can mount read-only |
| ReadWriteMany | RWX | Many nodes can mount read-write |

---

### StorageClasses (Dynamic Provisioning)

Instead of pre-creating PVs, use a StorageClass to automatically provision storage when a PVC is created.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs    # or pd.csi.storage.gke.io, etc.
parameters:
  type: gp3
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

#### PVC using StorageClass

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-storage
spec:
  storageClassName: fast-ssd
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

Now when this PVC is created, the StorageClass automatically provisions a 20Gi SSD volume. No manual PV creation needed.

### Reclaim Policies

| Policy | What Happens When PVC is Deleted |
|--------|--------------------------------|
| **Retain** | PV and data kept (manual cleanup) |
| **Delete** | PV and underlying storage deleted |
| **Recycle** | Data wiped, PV made available again (deprecated) |

---

### Practical Example: Database with Persistent Storage

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
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
        image: postgres:16
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          value: "mysecretpassword"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
  clusterIP: None    # headless service for StatefulSet
```

---

## Useful Commands

```bash
# Networking
kubectl get services
kubectl get ingress
kubectl get endpoints
kubectl get networkpolicies

# Storage
kubectl get pv
kubectl get pvc
kubectl get storageclass
kubectl describe pvc my-pvc    # see if it's bound

# Debugging networking
kubectl exec -it <pod> -- nslookup <service-name>
kubectl exec -it <pod> -- curl <service-name>:<port>
kubectl port-forward service/my-service 8080:80   # access locally
```

---

## ⚠️ Common Gotchas

### "My Service works inside the cluster but I can't reach it from outside"
**The mistake:** Using ClusterIP and expecting external access.
**Why it happens:** ClusterIP is the default service type, and it only works inside the cluster.
**How to avoid:** For external access use NodePort (dev), LoadBalancer (cloud), or Ingress (production HTTP routing). For quick local testing: `kubectl port-forward svc/<name> 8080:80`.

### "I created an Ingress but nothing happens"
**The mistake:** No Ingress Controller installed.
**Why it happens:** Ingress is just a routing rule — it needs a controller to actually do the routing.
**How to avoid:** Install an Ingress Controller first: `minikube addons enable ingress` or install nginx-ingress. Then create your Ingress resource.

### "My PVC is stuck in Pending forever"
**The mistake:** PVC can't find a matching PV.
**Why it happens:** StorageClass name is wrong, no storage provisioner exists, or the PV is in a different zone.
**How to avoid:** Check `kubectl describe pvc <name>` for events. Verify the StorageClass exists with `kubectl get sc`. On Minikube, the default `standard` class works automatically.

### "DNS resolution doesn't work between pods"
**The mistake:** Using the full service name wrong or not waiting for CoreDNS.
**Why it happens:** New users try to curl the pod IP instead of the service name, or use wrong format.
**How to avoid:** Service DNS format: `<service-name>` (same namespace) or `<service-name>.<namespace>.svc.cluster.local` (cross-namespace). Test with: `kubectl exec -it <pod> -- nslookup <service-name>`.

---

## Exercises

1. Create a Deployment + ClusterIP Service. Exec into a separate pod and curl the service by DNS name.
2. Create an Ingress that routes `/app` to one service and `/api` to another.
3. Create a PVC, mount it in a pod, write a file. Delete the pod. Create a new pod with the same PVC — verify the file persists.
4. Create a NetworkPolicy that only allows traffic from pods with label `role: frontend` to reach your backend pod.

---

[← Module 3: Core Concepts](../03-core-concepts/README.md) | [Module 5: Configuration & Secrets →](../05-configuration/README.md)
