# Live Demo: Kubernetes Superpowers in Action

> Run this AFTER the app is deployed (`./deploy.sh` done and pods are running).

## Setup Before Demo

```bash
# Ensure metrics-server is running (needed for HPA)
minikube addons enable metrics-server

# Verify app is running
kubectl get pods -n notes-app

# Start port-forward in background
kubectl port-forward svc/notes-api -n notes-app 8080:80 &
```

---

## Demo 1: Self-Healing (Pod Dies → K8s Brings It Back)

**Story:** "I'll kill a pod. Kubernetes detects it's gone and recreates it automatically."

```bash
# Terminal 1: Watch pods in real-time
kubectl get pods -n notes-app -w

# Terminal 2: Kill a pod
kubectl delete pod -l app=notes-api -n notes-app --wait=false | head -1

# Watch Terminal 1 — you'll see:
#   notes-api-xxx   1/1   Terminating
#   notes-api-yyy   0/1   Pending
#   notes-api-yyy   1/1   Running     ← NEW pod auto-created!
```

**Why it works:** The Deployment declares "I want 3 replicas." The controller constantly reconciles actual state with desired state.

---

## Demo 2: Traffic Failover (Pod Dies → Traffic Goes to Others)

**Story:** "I'll send continuous traffic, then kill a pod. Requests keep succeeding because the Service routes to healthy pods."

```bash
# Terminal 1: Continuous requests (shows which pod responds)
while true; do
  curl -s http://localhost:8080/healthz && echo " [$(date +%H:%M:%S)]"
  sleep 0.5
done

# Terminal 2: Kill a pod while traffic is flowing
kubectl delete pod -l app=notes-api -n notes-app --wait=false | head -1

# Watch Terminal 1 — requests keep returning {"status":"ok"}
# Zero downtime! The Service's endpoint controller removes the dead pod
# and routes only to Ready pods (readinessProbe).
```

**Why it works:** The Service + readinessProbe combo. K8s only sends traffic to pods that pass their readiness check. Dead pod is removed from endpoints instantly.

---

## Demo 3: HPA — Auto-Scale When Traffic Explodes

**Story:** "I'll flood the app with requests. Kubernetes sees CPU spike and adds more replicas automatically."

### Step 1: Create the HPA

```bash
kubectl autoscale deployment notes-api -n notes-app \
  --min=3 --max=8 --cpu-percent=50
```

### Step 2: Watch in one terminal

```bash
# Terminal 1: Watch HPA status
kubectl get hpa -n notes-app -w

# Terminal 2: Watch pod count
kubectl get pods -n notes-app -w
```

### Step 3: Generate load

```bash
# Terminal 3: Hammer the API
kubectl run load-gen -n notes-app --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://notes-api/healthz; done"
```

### Watch it scale

```bash
# After ~30-60 seconds, the HPA shows:
# NAME        REFERENCE              TARGETS    MINPODS   MAXPODS   REPLICAS
# notes-api   Deployment/notes-api   78%/50%    3         8         5  ← SCALED UP!

# You'll see new pods spinning up in Terminal 2
```

### Stop load & watch scale-down

```bash
kubectl delete pod load-gen -n notes-app

# Wait ~5 minutes (default cooldown), replicas go back to 3
kubectl get hpa -n notes-app -w
```

### Cleanup HPA (optional)

```bash
kubectl delete hpa notes-api -n notes-app
```

---

## Demo 4: Rolling Update (Zero-Downtime Deployment)

**Story:** "I'll push a new version. Kubernetes gradually replaces old pods with new ones — no downtime."

### Step 1: Make a visible change

```bash
# Rebuild with a v2 tag (add something to distinguish)
eval $(minikube docker-env)
docker build -t notes-api:v2 ./app
```

### Step 2: Watch the rollout

```bash
# Terminal 1: Watch pods
kubectl get pods -n notes-app -w

# Terminal 2: Continuous traffic to prove zero downtime
while true; do
  curl -s http://localhost:8080/healthz && echo " [$(date +%H:%M:%S)]"
  sleep 0.3
done

# Terminal 3: Trigger the update
kubectl set image deployment/notes-api notes-api=notes-api:v2 -n notes-app
```

### What you'll see in Terminal 1:

```
notes-api-OLD-aaa   1/1   Running
notes-api-OLD-bbb   1/1   Running
notes-api-OLD-ccc   1/1   Running
notes-api-NEW-xxx   0/1   Pending        ← new pod starting
notes-api-NEW-xxx   1/1   Running        ← new pod ready
notes-api-OLD-aaa   1/1   Terminating    ← old pod removed
notes-api-NEW-yyy   0/1   Pending        ← next new pod
notes-api-NEW-yyy   1/1   Running
notes-api-OLD-bbb   1/1   Terminating
...
```

Traffic in Terminal 2 never drops — requests keep succeeding!

### Step 3: Rollback (Bonus)

```bash
# Oh no, v2 has a bug! Roll back instantly:
kubectl rollout undo deployment/notes-api -n notes-app

# Check rollout history
kubectl rollout history deployment/notes-api -n notes-app
```

---

## Summary — What You Just Proved

| Concept | What Happened | Why |
|---------|---------------|-----|
| **Self-healing** | Killed pod → new one auto-created | Deployment controller reconciles desired vs actual |
| **Traffic failover** | Pod died → zero failed requests | Service + readinessProbe routes only to healthy pods |
| **HPA auto-scaling** | CPU spiked → replicas increased | HPA watches metrics, scales to meet target |
| **Rolling update** | Deployed v2 → zero downtime | New pods start before old ones terminate |

---

## One-Liner Cheat Sheet

```bash
# Self-heal
kubectl delete pod -l app=notes-api -n notes-app --wait=false | head -1

# HPA
kubectl autoscale deployment notes-api -n notes-app --min=3 --max=8 --cpu-percent=50

# Load test
kubectl run load-gen -n notes-app --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://notes-api/healthz; done"

# Rolling update
kubectl set image deployment/notes-api notes-api=notes-api:v2 -n notes-app

# Rollback
kubectl rollout undo deployment/notes-api -n notes-app
```
