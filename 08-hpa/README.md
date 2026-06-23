# Module 8: HorizontalPodAutoscaler (HPA) `[Intermediate]`

## What is HPA?

HPA automatically scales the number of pod replicas based on observed metrics (CPU, memory, or custom metrics).

```
Low traffic:   [Pod] [Pod]              ← 2 replicas
Peak traffic:  [Pod] [Pod] [Pod] [Pod]  ← HPA scaled to 4
After peak:    [Pod] [Pod]              ← scaled back down
```

You set a target (e.g., "keep CPU at 50%") and HPA adjusts replicas to maintain it.

---

## Prerequisites

HPA needs **metrics-server** to read CPU/memory data:

```bash
# Minikube
minikube addons enable metrics-server

# Verify it's working
kubectl top pods
kubectl top nodes
```

---

## Basic HPA — CPU-based

### Step 1: Deployment with resource requests (REQUIRED)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
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
        image: nginx
        resources:
          requests:
            cpu: "100m"    # HPA uses this as the baseline
          limits:
            cpu: "500m"
```

### Step 2: Create HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50   # scale when avg CPU > 50% of request
```

Or via CLI:

```bash
kubectl autoscale deployment my-app --min=2 --max=10 --cpu-percent=50
```

### How It Works

```
Each pod requests 100m CPU.
Target: 50% utilization = 50m per pod.

If 2 pods are using 80m each (80% utilization):
  Total usage: 160m
  Desired replicas = 160m / 50m = 3.2 → rounds up to 4

HPA scales from 2 → 4 pods.
```

---

## Memory-based HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
```

---

## Multiple Metrics

```yaml
spec:
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
```

HPA picks the metric that results in the HIGHEST replica count.

---

## Scaling Behavior (Control Speed)

```yaml
spec:
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Pods
        value: 2
        periodSeconds: 60      # add max 2 pods per minute
    scaleDown:
      stabilizationWindowSeconds: 300   # wait 5 min before scaling down
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60      # remove max 10% of pods per minute
```

This prevents thrashing (rapid scale up/down cycles).

---

## Testing HPA — Generate Load

```bash
# Watch HPA in one terminal
kubectl get hpa -w

# In another terminal, generate CPU load
kubectl run load-gen --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://my-app-service; done"

# Watch pods scale
kubectl get pods -w

# Stop the load
kubectl delete pod load-gen
# Watch pods scale back down (after stabilization window)
```

---

## Useful Commands

```bash
kubectl get hpa
kubectl describe hpa my-app-hpa
kubectl top pods
kubectl delete hpa my-app-hpa
```

---

## Key Points

| Concept | Detail |
|---------|--------|
| **Requires** | metrics-server + resource requests on pods |
| **Default cooldown** | Scale up: 0s, Scale down: 5 min |
| **Calculation** | desiredReplicas = currentReplicas × (currentMetric / targetMetric) |
| **Won't scale below** | minReplicas |
| **Won't scale above** | maxReplicas |

---

## Exercises

1. Deploy an app with CPU requests. Create an HPA targeting 50% CPU. Generate load and watch it scale.
2. Create an HPA with both CPU and memory targets.
3. Configure `behavior` to limit scale-down to 1 pod per minute.

---

[← Module 7: Helm](../07-helm/README.md) | [Module 9: RBAC →](../09-rbac/README.md)
