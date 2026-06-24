# Kubernetes Demo — Full Walkthrough & Script

> Total time: ~20-25 minutes  
> What you need: Minikube installed, Docker installed, kubectl installed  
> Open 3 terminal windows side-by-side before starting

---

## PART 0: Setup (Do This BEFORE the Demo) [5 min]

```bash
cd ~/work/learn/kubernetes/06-demo

minikube start
minikube addons enable ingress
minikube addons enable metrics-server

# Build the app
eval $(minikube docker-env)
docker build -t notes-api:v1 ./app

# Deploy everything
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/app-config.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/ingress.yaml

# Wait until all pods are Running
kubectl wait --for=condition=ready pod -l app=postgres -n notes-app --timeout=120s
kubectl wait --for=condition=ready pod -l app=notes-api -n notes-app --timeout=120s

# Verify
kubectl get pods -n notes-app
# You should see: 3 notes-api pods + 1 postgres pod, all Running

# Start port-forward
kubectl port-forward svc/notes-api -n notes-app 8080:80 &

# Quick test
curl http://localhost:8080/healthz
# Should return: {"status":"ok"}
```

✅ You're ready. Now start the demo.

---

## PART 1: Introduction [2 min]

**What to SAY:**

> "I've deployed a Notes API on Kubernetes — it's a Node.js app with 3 replicas and a PostgreSQL database. Let me show you how Kubernetes handles real-world production problems automatically."

**What to SHOW:**

```bash
# Show the architecture
kubectl get pods -n notes-app
kubectl get svc -n notes-app
```

**Explain:**
- 3 replicas of the API (like 3 copies of your server)
- 1 PostgreSQL database
- A Service that load-balances across all 3 pods

---

## PART 2: Self-Healing [3 min]

**What to SAY:**

> "What happens if a server crashes? In traditional setups, you'd get paged at 3am. In Kubernetes, it fixes itself."

**What to DO:**

```bash
# Terminal 1: Watch pods live
kubectl get pods -n notes-app -w

# Terminal 2: Kill a pod (simulate server crash)
kubectl delete pod $(kubectl get pod -n notes-app -l app=notes-api -o jsonpath='{.items[0].metadata.name}') -n notes-app
```

**What to SHOW audience in Terminal 1:**

```
NAME                         READY   STATUS        RESTARTS   AGE
notes-api-xxx-aaa            1/1     Terminating   0          5m    ← dying
notes-api-xxx-bbb            1/1     Running       0          5m
notes-api-xxx-ccc            1/1     Running       0          5m
notes-api-xxx-ddd            0/1     Pending       0          1s    ← new one!
notes-api-xxx-ddd            1/1     Running       0          3s    ← back to 3!
```

**What to SAY:**

> "I killed a pod. Within seconds, Kubernetes detected it was gone and created a new one. The Deployment says 'I want 3 replicas' and the controller makes it so. No human intervention needed."

---

## PART 3: Traffic Failover — Zero Downtime [3 min]

**What to SAY:**

> "But what about the users who were hitting that pod? Did they get errors? Let's prove they didn't."

**What to DO:**

```bash
# Terminal 1: Continuous traffic (1 request every 0.5s)
while true; do
  RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz)
  echo "$(date +%H:%M:%S) → HTTP $RESP"
  sleep 0.5
done

# Terminal 2: Watch pods
kubectl get pods -n notes-app -w

# Terminal 3: Kill a pod WHILE traffic is flowing
kubectl delete pod $(kubectl get pod -n notes-app -l app=notes-api -o jsonpath='{.items[0].metadata.name}') -n notes-app
```

**What audience sees in Terminal 1:**

```
08:15:01 → HTTP 200
08:15:01 → HTTP 200
08:15:02 → HTTP 200    ← pod killed here
08:15:02 → HTTP 200    ← still 200!
08:15:03 → HTTP 200
08:15:03 → HTTP 200    ← never dropped
```

**What to SAY:**

> "Every single request returned 200. The Service has a readiness probe — it only sends traffic to pods that are actually ready. The moment a pod starts dying, traffic routes to the remaining healthy pods. Users never notice."

**Stop the loop:** `Ctrl+C`

---

## PART 4: Auto-Scaling with HPA [5 min]

**What to SAY:**

> "What if traffic explodes? Black Friday, viral moment, whatever. Kubernetes can automatically add more replicas."

**What to DO:**

```bash
# Step 1: Create the HPA
kubectl autoscale deployment notes-api -n notes-app --min=3 --max=8 --cpu-percent=50

# Terminal 1: Watch HPA (shows current CPU% and replica count)
kubectl get hpa -n notes-app -w

# Terminal 2: Watch pods
kubectl get pods -n notes-app -w

# Step 2: Generate heavy load (simulate traffic explosion)
kubectl run load-gen -n notes-app --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://notes-api/healthz; done"
```

**Wait 30-60 seconds. What audience sees:**

Terminal 1 (HPA):
```
NAME        REFERENCE              TARGETS     MINPODS   MAXPODS   REPLICAS
notes-api   Deployment/notes-api   12%/50%     3         8         3
notes-api   Deployment/notes-api   68%/50%     3         8         3         ← CPU spiking
notes-api   Deployment/notes-api   68%/50%     3         8         5         ← SCALED UP!
notes-api   Deployment/notes-api   45%/50%     3         8         5         ← stabilized
```

Terminal 2 (Pods):
```
notes-api-xxx-aaa   1/1   Running   0   10m
notes-api-xxx-bbb   1/1   Running   0   10m
notes-api-xxx-ccc   1/1   Running   0   10m
notes-api-xxx-ddd   0/1   Pending   0   1s    ← NEW!
notes-api-xxx-eee   0/1   Pending   0   1s    ← NEW!
notes-api-xxx-ddd   1/1   Running   0   3s
notes-api-xxx-eee   1/1   Running   0   3s
```

**What to SAY:**

> "I set a rule: keep CPU below 50%. When load pushed it to 68%, Kubernetes automatically added 2 more pods. No alarm, no manual scaling, no waking up at night."

**Stop load and show scale-down:**

```bash
kubectl delete pod load-gen -n notes-app

# SAY: "Now I'll stop the load. After a cooldown period (~5 min), it scales back down to save resources."
# (You can skip waiting and just mention it)
```

**Cleanup:**

```bash
kubectl delete hpa notes-api -n notes-app
# Scale back to 3 manually for next demo
kubectl scale deployment notes-api -n notes-app --replicas=3
```

---

## PART 5: Rolling Update — Zero-Downtime Deployments [4 min]

**What to SAY:**

> "How do you deploy a new version without downtime? Kubernetes replaces pods one by one — new pod starts, passes health check, THEN old pod is removed."

**What to DO:**

```bash
# Step 1: Build a "v2" image
eval $(minikube docker-env)
docker build -t notes-api:v2 ./app

# Terminal 1: Watch pods
kubectl get pods -n notes-app -w

# Terminal 2: Continuous traffic
while true; do
  RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz)
  echo "$(date +%H:%M:%S) → HTTP $RESP"
  sleep 0.3
done

# Terminal 3: Trigger the update
kubectl set image deployment/notes-api notes-api=notes-api:v2 -n notes-app
```

**What audience sees in Terminal 1:**

```
notes-api-OLD-aaa   1/1   Running       0   15m
notes-api-OLD-bbb   1/1   Running       0   15m
notes-api-OLD-ccc   1/1   Running       0   15m
notes-api-NEW-xxx   0/1   Pending       0   0s     ← v2 starting
notes-api-NEW-xxx   1/1   Running       0   3s     ← v2 ready!
notes-api-OLD-aaa   1/1   Terminating   0   15m    ← v1 removed
notes-api-NEW-yyy   0/1   Pending       0   0s     ← next v2
notes-api-NEW-yyy   1/1   Running       0   3s
notes-api-OLD-bbb   1/1   Terminating   0   15m
notes-api-NEW-zzz   0/1   Pending       0   0s
notes-api-NEW-zzz   1/1   Running       0   3s
notes-api-OLD-ccc   1/1   Terminating   0   15m    ← all replaced!
```

**Terminal 2 shows HTTP 200 the entire time!**

**What to SAY:**

> "Notice — new pod starts FIRST, passes its health check, then the old one is terminated. At no point do we have fewer healthy pods than needed. Traffic never drops."

---

## PART 6: Rollback [1 min]

**What to SAY:**

> "Deployed a bad version? One command to roll back."

```bash
kubectl rollout undo deployment/notes-api -n notes-app

# Show history
kubectl rollout history deployment/notes-api -n notes-app
```

**What to SAY:**

> "Instant rollback. Kubernetes keeps the previous ReplicaSet around, so rolling back is just pointing back to it."

---

## PART 7: Wrap-Up [1 min]

**What to SAY:**

> "So to summarize — with Kubernetes you get:
> 1. **Self-healing** — crashed pods are auto-replaced
> 2. **Traffic failover** — users never see errors
> 3. **Auto-scaling** — handles traffic spikes without manual intervention
> 4. **Zero-downtime deploys** — new versions roll out seamlessly
> 5. **Instant rollback** — one command to undo a bad deploy
> 
> All of this is declarative — you tell Kubernetes WHAT you want, and it figures out HOW."

---

## Cleanup After Demo

```bash
kubectl delete namespace notes-app
minikube stop
```

---

## If Things Go Wrong

| Problem | Fix |
|---------|-----|
| `metrics-server` not ready (HPA shows `<unknown>`) | Wait 1-2 min after enabling, or run `kubectl top pods -n notes-app` to check |
| Port-forward dies | `kubectl port-forward svc/notes-api -n notes-app 8080:80 &` |
| Pods stuck in `Pending` | `kubectl describe pod <name> -n notes-app` — usually resource limits |
| HPA not scaling | Needs `resources.requests.cpu` set on deployment (it's already there) |
| Image not found | Make sure you ran `eval $(minikube docker-env)` before `docker build` |
