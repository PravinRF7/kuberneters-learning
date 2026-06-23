# Module 13: Service Mesh `[Advanced]`

## What is a Service Mesh?

A service mesh is an infrastructure layer that handles **service-to-service communication** transparently. It adds:

- **mTLS** — encrypted communication between all services (zero-trust)
- **Traffic management** — canary deploys, retries, circuit breaking
- **Observability** — request traces, latency metrics, success rates
- **Access control** — which service can talk to which

```
Without mesh:                      With mesh:
┌─────┐  HTTP  ┌─────┐           ┌─────┐ mTLS ┌─────┐
│Svc A│───────►│Svc B│           │Svc A│──────►│Svc B│
└─────┘        └─────┘           └──┬──┘       └──┬──┘
                                    │              │
                                 ┌──▼──┐        ┌──▼──┐
                                 │Proxy│        │Proxy│  ← sidecar proxies
                                 └─────┘        └─────┘
```

The mesh injects a **sidecar proxy** (Envoy) into every pod. All traffic flows through it.

---

## Popular Service Meshes

| Mesh | Key Trait |
|------|-----------|
| **Istio** | Most feature-rich, complex, widely adopted |
| **Linkerd** | Lightweight, simple, Rust-based proxy |
| **Consul Connect** | HashiCorp ecosystem, multi-platform |

---

## Istio — Quick Setup

```bash
# Install istioctl
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-*/bin:$PATH

# Install Istio to cluster
istioctl install --set profile=demo -y

# Enable auto sidecar injection for a namespace
kubectl label namespace notes-app istio-injection=enabled

# Restart pods to get sidecars injected
kubectl rollout restart deployment -n notes-app
```

After injection, every pod gets an Envoy sidecar:

```bash
kubectl get pods -n notes-app
# NAME                         READY   STATUS
# notes-api-xxxxx              2/2     Running   ← 2 containers (app + envoy)
```

---

## Traffic Management

### Canary Deployment (90/10 split)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: notes-api
  namespace: notes-app
spec:
  hosts:
  - notes-api
  http:
  - route:
    - destination:
        host: notes-api
        subset: v1
      weight: 90
    - destination:
        host: notes-api
        subset: v2
      weight: 10
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: notes-api
  namespace: notes-app
spec:
  host: notes-api
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

90% of traffic goes to v1, 10% to v2. Gradually shift if v2 is healthy.

### Retries & Timeouts

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: notes-api
spec:
  hosts:
  - notes-api
  http:
  - route:
    - destination:
        host: notes-api
    timeout: 5s
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: 5xx,connect-failure
```

### Circuit Breaking

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: notes-api
spec:
  host: notes-api
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: DEFAULT
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 30s
      baseEjectionTime: 60s     # remove unhealthy pod for 60s
```

---

## Mutual TLS (mTLS)

Istio encrypts all service-to-service traffic by default (PERMISSIVE mode). To enforce strict mTLS:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: notes-app
spec:
  mtls:
    mode: STRICT    # reject non-mTLS traffic
```

---

## Authorization Policies

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: notes-api-policy
  namespace: notes-app
spec:
  selector:
    matchLabels:
      app: notes-api
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/notes-app/sa/frontend"]
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
```

Only the `frontend` service account can call the notes-api.

---

## Observability

Istio provides built-in observability tools:

```bash
# Install addons
kubectl apply -f istio-*/samples/addons/

# Kiali — service mesh visualization
kubectl port-forward svc/kiali -n istio-system 20001:20001

# Jaeger — distributed tracing
kubectl port-forward svc/tracing -n istio-system 16686:80
```

With Kiali you can see:
- Service topology graph
- Traffic flow between services
- Error rates per service
- Response time distribution

---

## Linkerd (Simpler Alternative)

```bash
# Install
curl --proto '=https' -sSfL https://run.linkerd.io/install | sh
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Inject into namespace
kubectl get deploy -n notes-app -o yaml | linkerd inject - | kubectl apply -f -

# Dashboard
linkerd viz install | kubectl apply -f -
linkerd viz dashboard
```

Linkerd is lighter than Istio — fewer CRDs, smaller footprint, simpler config.

---

## When Do You Need a Service Mesh?

| Scenario | Need Mesh? |
|----------|-----------|
| 2-3 services, single team | No — overkill |
| 10+ microservices | Maybe — depends on requirements |
| Need mTLS between services | Yes |
| Canary/progressive deployments | Yes |
| Compliance requires encryption | Yes |
| Need per-service traffic metrics | Yes |

---

## Exercises

1. Install Istio (demo profile). Enable injection on your namespace. Verify sidecars appear.
2. Deploy two versions of an app. Create a VirtualService with 80/20 traffic split.
3. Enable strict mTLS. Verify non-mesh traffic is rejected.
4. Open Kiali and observe the service topology graph.

---

[← Module 12: Monitoring](../12-monitoring/README.md) | [Module 14: CRDs →](../14-crds/README.md)
