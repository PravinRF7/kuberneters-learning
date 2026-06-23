# Module 12: Monitoring — Prometheus & Grafana `[Advanced]`

## Why Monitor Kubernetes?

Without monitoring you're flying blind:
- Is my app healthy? How much CPU/memory is it using?
- Are pods crashing? How often?
- Is traffic increasing? Are requests slow?
- When will I run out of resources?

---

## The Monitoring Stack

```
┌─────────────┐     ┌────────────┐     ┌──────────┐
│ Your Apps   │────►│ Prometheus │────►│ Grafana  │
│ (metrics)   │     │ (scrape &  │     │ (dashboards│
│             │     │  store)    │     │  & alerts)│
└─────────────┘     └────────────┘     └──────────┘
     ▲                    ▲
     │                    │
┌─────────────┐     ┌────────────┐
│ Node        │     │ kube-state │
│ Exporter    │     │ -metrics   │
│ (host metrics)│   │ (K8s object│
└─────────────┘     │  state)    │
                    └────────────┘
```

| Component | Role |
|-----------|------|
| **Prometheus** | Scrapes and stores time-series metrics |
| **Grafana** | Visualizes metrics in dashboards |
| **Node Exporter** | Exposes host-level metrics (CPU, RAM, disk) |
| **kube-state-metrics** | Exposes K8s object states (pod status, replica counts) |
| **Alertmanager** | Sends alerts (Slack, email, PagerDuty) |

---

## Install with Helm (kube-prometheus-stack)

This installs everything in one shot:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123
```

### Access Grafana

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

# Open http://localhost:3000
# Login: admin / admin123
```

### Access Prometheus

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090

# Open http://localhost:9090
```

---

## How Prometheus Works

1. Your app exposes metrics at `/metrics` endpoint
2. Prometheus **scrapes** that endpoint on a schedule
3. Metrics are stored as time-series data
4. You query them with **PromQL**

### Metrics Format

```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET", path="/api/notes", status="200"} 1523
http_requests_total{method="POST", path="/api/notes", status="201"} 87
```

### Metric Types

| Type | Description | Example |
|------|-------------|---------|
| **Counter** | Only goes up | Total requests, errors |
| **Gauge** | Goes up and down | Current memory, temperature |
| **Histogram** | Distribution of values | Request duration buckets |
| **Summary** | Similar to histogram | Quantiles (p50, p99) |

---

## Instrumenting Your App

### Node.js Example

```javascript
const promClient = require('prom-client');

// Collect default metrics (CPU, memory, event loop)
promClient.collectDefaultMetrics();

// Custom counter
const httpRequests = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'path', 'status'],
});

// Custom histogram
const httpDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'path'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 5],
});

// Middleware to track requests
app.use((req, res, next) => {
  const end = httpDuration.startTimer({ method: req.method, path: req.path });
  res.on('finish', () => {
    httpRequests.inc({ method: req.method, path: req.path, status: res.statusCode });
    end();
  });
  next();
});

// Expose metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', promClient.register.contentType);
  res.end(await promClient.register.metrics());
});
```

---

## Tell Prometheus to Scrape Your App

### Via Pod Annotations

```yaml
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "3000"
        prometheus.io/path: "/metrics"
```

### Via ServiceMonitor (recommended with kube-prometheus-stack)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: notes-api
  namespace: monitoring
  labels:
    release: monitoring    # must match Prometheus selector
spec:
  namespaceSelector:
    matchNames:
    - notes-app
  selector:
    matchLabels:
      app: notes-api
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
```

---

## PromQL Basics

```promql
# Current CPU usage per pod
rate(container_cpu_usage_seconds_total{namespace="notes-app"}[5m])

# Memory usage in MB
container_memory_usage_bytes{namespace="notes-app"} / 1024 / 1024

# Request rate (requests per second)
rate(http_requests_total[5m])

# 99th percentile request duration
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Pod restart count
kube_pod_container_status_restarts_total{namespace="notes-app"}
```

---

## Alerting

### PrometheusRule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
  - name: app.rules
    rules:
    - alert: HighErrorRate
      expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High error rate detected"
    - alert: PodCrashLooping
      expr: kube_pod_container_status_restarts_total > 5
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} is crash-looping"
```

---

## Key Grafana Dashboards

The kube-prometheus-stack comes with pre-built dashboards:
- **Kubernetes / Compute Resources / Namespace** — CPU/memory per namespace
- **Kubernetes / Networking / Namespace** — network traffic
- **Node Exporter** — host-level metrics
- **CoreDNS** — DNS query performance

Import community dashboards from https://grafana.com/grafana/dashboards/ by ID.

---

## Exercises

1. Install kube-prometheus-stack with Helm. Access Grafana and explore default dashboards.
2. Add `prom-client` to the Notes API. Expose request count and duration metrics.
3. Create a ServiceMonitor to scrape the Notes API.
4. Write a PrometheusRule that alerts when pod restarts exceed 3.
5. Query request rate and error rate in Prometheus UI using PromQL.

---

[← Module 11: CI/CD](../11-cicd/README.md) | [Module 13: Service Mesh →](../13-service-mesh/README.md)
