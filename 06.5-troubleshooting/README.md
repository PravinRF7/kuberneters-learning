# Module 6.5: Troubleshooting & Debugging

You deployed your app. It's not working. Now what?

This module is your debugging survival kit. You'll learn to diagnose the most common Kubernetes failures — systematically, not by guessing.

**Prerequisites:** Complete Modules 1-6 first. We'll reference the notes-api demo throughout.

---

## The Debugging Mindset

When something breaks in K8s, follow this order:

```
1. What's the STATUS?        → kubectl get pods
2. What EVENTS happened?     → kubectl describe pod <name>
3. What do the LOGS say?     → kubectl logs <name>
4. Can I get INSIDE?         → kubectl exec -it <name> -- sh
```

Don't skip steps. 90% of issues are solved by steps 1-3.

---

## Pod Failure Decision Tree

```
Pod isn't working?
│
├─ STATUS: Pending
│  ├─ No node with enough resources? → Scale cluster or reduce requests
│  ├─ PVC stuck in Pending? → Check StorageClass, PV availability
│  └─ Node selector/affinity not matching? → Check labels on nodes
│
├─ STATUS: ImagePullBackOff / ErrImagePull
│  ├─ Image name typo? → Check image: field carefully
│  ├─ Private registry, no credentials? → Add imagePullSecrets
│  └─ Tag doesn't exist? → Verify tag in registry
│
├─ STATUS: CrashLoopBackOff
│  ├─ App crashes on startup? → kubectl logs <pod>
│  ├─ Missing env var / config? → Check ConfigMap/Secret refs
│  ├─ Wrong command/args? → Check container command field
│  └─ Database not ready? → Check dependent services
│
├─ STATUS: Running but not READY (0/1)
│  ├─ Readiness probe failing? → Check probe path/port
│  ├─ App started but dependency down? → Check upstream services
│  └─ Probe timing too aggressive? → Increase initialDelaySeconds
│
├─ STATUS: OOMKilled
│  └─ Container exceeded memory limit → Increase limits or fix memory leak
│
├─ STATUS: Evicted
│  └─ Node ran out of resources → Check node pressure, add resources
│
├─ STATUS: CreateContainerConfigError
│  ├─ Referenced ConfigMap doesn't exist? → Check name/namespace
│  └─ Referenced Secret doesn't exist? → Check name/namespace
│
├─ STATUS: Running but app misbehaving
│  ├─ Service selector doesn't match pod labels? → Check labels
│  ├─ Wrong port in Service? → Compare targetPort vs containerPort
│  └─ NetworkPolicy blocking traffic? → Check policies in namespace
│
└─ Pod never appears at all
   ├─ Deployment selector doesn't match template labels? → They MUST match
   └─ Namespace mismatch? → Check -n flag
```

---

## Top 10 Pod Failure Modes

### 1. Pending

**What it means:** Pod is accepted but can't be scheduled to a node.

**Diagnose:**
```bash
kubectl describe pod <name> -n <namespace>
# Look at Events section at the bottom
```

**Common causes:**

| Cause | Event Message | Fix |
|-------|--------------|-----|
| Not enough CPU/RAM | `Insufficient cpu` / `Insufficient memory` | Reduce resource requests or add nodes |
| PVC not bound | `persistentvolumeclaim "xxx" not found` | Create PVC or check StorageClass |
| Node selector mismatch | `0/3 nodes are available: 3 node(s) didn't match` | Fix nodeSelector labels |
| Taint with no toleration | `1 node(s) had taints that the pod didn't tolerate` | Add toleration or remove taint |

```bash
# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check PVC status
kubectl get pvc -n <namespace>
```

---

### 2. ImagePullBackOff / ErrImagePull

**What it means:** K8s can't download your container image.

**Diagnose:**
```bash
kubectl describe pod <name> | grep -A 3 "Events"
# Look for: "Failed to pull image" messages
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| Typo in image name | Double-check `image:` field |
| Tag doesn't exist | Verify with `docker pull <image>` locally |
| Private registry, no auth | Add `imagePullSecrets` to pod spec |
| Registry unreachable | Check network/DNS from node |

```bash
# Verify image exists
docker pull your-registry/app:v1

# Create registry secret
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  -n <namespace>
```

---

### 3. CrashLoopBackOff

**What it means:** Container starts, crashes, K8s restarts it, it crashes again. Repeat forever with increasing backoff delay.

**Diagnose:**
```bash
# Check logs from the crashed container
kubectl logs <pod-name> -n <namespace>

# If container restarts too fast, check previous instance
kubectl logs <pod-name> --previous

# Check exit code
kubectl describe pod <pod-name> | grep -A 5 "Last State"
```

**Common causes:**

| Cause | Clue | Fix |
|-------|------|-----|
| App error on startup | Error in logs | Fix app code or config |
| Missing env var | `undefined` / `null` error in logs | Check ConfigMap/Secret references |
| Database not reachable | Connection refused/timeout in logs | Check DB service is running |
| Wrong command | `exec format error` or `not found` | Fix `command:` / `args:` in spec |
| Liveness probe too aggressive | Healthy logs then sudden restart | Increase `initialDelaySeconds` |

**Exit codes:**
| Code | Meaning |
|------|---------|
| 0 | Success (container completed — might be wrong for a long-running app) |
| 1 | Application error |
| 137 | Killed (OOMKilled or `kubectl delete`) |
| 139 | Segmentation fault |
| 143 | Graceful termination (SIGTERM) |

---

### 4. CreateContainerConfigError

**What it means:** K8s can't configure the container because a referenced resource is missing.

**Diagnose:**
```bash
kubectl describe pod <name>
# Events will say exactly which ConfigMap or Secret is missing
```

**Fix:** Create the missing ConfigMap/Secret, or fix the reference name.

```bash
# Check if ConfigMap exists
kubectl get configmap <name> -n <namespace>

# Check if Secret exists
kubectl get secret <name> -n <namespace>
```

---

### 5. OOMKilled

**What it means:** Container used more memory than its limit allows. K8s killed it.

**Diagnose:**
```bash
kubectl describe pod <name> | grep -A 3 "Last State"
# Reason: OOMKilled
```

**Fix:**
- Increase `resources.limits.memory`
- Or fix the memory leak in your app
- Check if your app needs more memory at startup (JVM heap, Node.js, etc.)

```yaml
resources:
  limits:
    memory: "512Mi"  # increase from 256Mi
```

---

### 6. Evicted

**What it means:** Node ran out of disk or memory. K8s evicts pods to protect the node.

**Diagnose:**
```bash
kubectl describe pod <name>
# Message: "The node was low on resource: memory"

# Check node conditions
kubectl describe node <node-name> | grep -A 5 "Conditions"
```

**Fix:** Add node resources, or set proper resource limits so pods don't overconsume.

---

### 7. Running But Not Ready (0/1)

**What it means:** Container is running but readiness probe is failing. No traffic is sent to this pod.

**Diagnose:**
```bash
kubectl describe pod <name>
# Events: "Readiness probe failed: HTTP probe failed with statuscode: 503"

# Test the endpoint yourself
kubectl exec -it <pod-name> -- curl -s localhost:3000/ready
```

**Common causes:**
- App is up but database connection failed
- Probe path is wrong (e.g., `/health` vs `/healthz`)
- Probe port doesn't match container port
- App needs more time to start → increase `initialDelaySeconds`

---

### 8. Service Has No Endpoints

**What it means:** Your Service exists but doesn't route to any pods.

**Diagnose:**
```bash
kubectl get endpoints <service-name> -n <namespace>
# If empty → selector doesn't match any running pods

# Compare service selector to pod labels
kubectl get svc <service-name> -o yaml | grep -A 3 selector
kubectl get pods --show-labels -n <namespace>
```

**Fix:** Make sure the Service `selector` labels exactly match pod `metadata.labels`.

---

### 9. Pod Stuck Terminating

**What it means:** Pod won't die. Usually stuck in graceful shutdown.

**Fix:**
```bash
# Force delete
kubectl delete pod <name> --grace-period=0 --force -n <namespace>
```

**Why it happens:** Finalizers, stuck pre-stop hooks, or node lost connectivity.

---

### 10. Forbidden / RBAC Errors

**What it means:** Your ServiceAccount doesn't have permission to do what the pod is trying to do.

**Diagnose:**
```bash
kubectl auth can-i get pods --as=system:serviceaccount:default:my-sa
# no

kubectl describe clusterrolebinding | grep my-sa
```

**Fix:** Create appropriate Role/ClusterRole and binding (see Module 9).

---

## Reading Pod Events

The single most useful debugging command:

```bash
kubectl describe pod <pod-name> -n <namespace>
```

**What to look for:**

```
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  2m    default-scheduler  Successfully assigned...
  Normal   Pulling    2m    kubelet            Pulling image "notes-api:v1"
  Normal   Pulled     90s   kubelet            Successfully pulled image
  Normal   Created    90s   kubelet            Created container notes-api
  Normal   Started    89s   kubelet            Started container notes-api
```

**Trouble signs:**
```
  Warning  Failed     30s   kubelet   Error: ImagePullBackOff
  Warning  BackOff    10s   kubelet   Back-off restarting failed container
  Warning  Unhealthy  5s    kubelet   Readiness probe failed
  Warning  FailedScheduling  0s  scheduler  0/3 nodes available
```

**Get all events in a namespace (sorted by time):**
```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Watch events in real-time
kubectl get events -n <namespace> -w
```

---

## Log Reading Strategies

### Basic log reading

```bash
# Current logs
kubectl logs <pod-name> -n <namespace>

# Follow logs in real-time
kubectl logs -f <pod-name> -n <namespace>

# Last 50 lines
kubectl logs --tail=50 <pod-name>

# Logs from last 5 minutes
kubectl logs --since=5m <pod-name>

# Logs from a crashed container (previous instance)
kubectl logs <pod-name> --previous
```

### Multi-container pods

```bash
# List containers in a pod
kubectl get pod <name> -o jsonpath='{.spec.containers[*].name}'

# Logs from specific container
kubectl logs <pod-name> -c <container-name>

# Logs from init container
kubectl logs <pod-name> -c <init-container-name>
```

### Logs from multiple pods (using labels)

```bash
# All pods with a label
kubectl logs -l app=notes-api -n notes-app

# Follow all pods
kubectl logs -l app=notes-api -n notes-app -f

# With pod name prefix (to see which pod each line is from)
kubectl logs -l app=notes-api -n notes-app --prefix
```

### Pro tips

```bash
# Combine with grep for filtering
kubectl logs <pod> | grep -i error

# JSON logs? Use jq
kubectl logs <pod> | jq '.level == "error"'

# Dump logs to file for analysis
kubectl logs <pod> > /tmp/pod-logs.txt
```

---

## Common Misconfigurations

### 1. Wrong Namespace

You created a ConfigMap in `default` but your pod is in `notes-app`.

```bash
# This won't work — ConfigMap is in wrong namespace
kubectl get configmap app-config -n notes-app
# Error: not found

# Check where it actually is
kubectl get configmap app-config --all-namespaces
```

**Rule:** ConfigMaps, Secrets, and Services must be in the SAME namespace as the pod referencing them.

---

### 2. Label Selector Mismatch

Your Deployment creates pods but your Service can't find them.

```yaml
# Deployment template labels
template:
  metadata:
    labels:
      app: notes-api    # ← pod gets this label

# Service selector
spec:
  selector:
    app: note-api       # ← TYPO! "note" vs "notes"
```

**Diagnose:**
```bash
kubectl get endpoints notes-api -n notes-app
# ENDPOINTS: <none>   ← this means selector doesn't match anything
```

---

### 3. Missing Secret/ConfigMap Reference

```
Events:
  Warning  Failed  0s  kubelet  Error: configmap "app-confg" not found
```

The pod will stay in `CreateContainerConfigError`. Fix the typo or create the resource.

---

### 4. Port Mismatches

```yaml
# Container listens on port 3000
containers:
- name: app
  ports:
  - containerPort: 3000

# Service points to wrong port
spec:
  ports:
  - port: 80
    targetPort: 8080    # ← WRONG! App listens on 3000, not 8080
```

---

### 5. Image Tag Issues with Local Images

On Minikube, if you build locally but pod says `ImagePullBackOff`:

```yaml
# Fix: tell K8s not to try pulling from a registry
imagePullPolicy: IfNotPresent   # or Never
```

And make sure you ran `eval $(minikube docker-env)` before building.

---

## Interactive Debugging

### kubectl exec — Get inside a running pod

```bash
# Shell into a pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Run a specific command
kubectl exec <pod-name> -- env
kubectl exec <pod-name> -- cat /etc/config/DB_HOST
kubectl exec <pod-name> -- wget -qO- http://postgres:5432
```

### port-forward — Access pod/service from your machine

```bash
# Forward local port to a pod
kubectl port-forward pod/<pod-name> 8080:3000 -n notes-app

# Forward to a service
kubectl port-forward svc/notes-api 8080:80 -n notes-app

# Now test locally
curl http://localhost:8080/healthz
```

### Debug containers (ephemeral containers)

When a pod has no shell (distroless/scratch images):

```bash
# Attach a debug container with tools
kubectl debug -it <pod-name> --image=busybox --target=<container-name>

# Or create a copy of the pod with a debug container
kubectl debug <pod-name> -it --copy-to=debug-pod --container=debug --image=ubuntu
```

### Run a temporary debug pod

```bash
# Spin up a one-off pod for testing network/DNS
kubectl run debug --rm -it --image=busybox -- sh

# Inside:
nslookup postgres.notes-app.svc.cluster.local
wget -qO- http://notes-api.notes-app.svc.cluster.local/healthz
```

---

## Worked Example 1: Wrong Database Password

**Scenario:** You deployed the notes-api from Module 6, but pods are in CrashLoopBackOff.

### Step 1: Check status

```bash
$ kubectl get pods -n notes-app
NAME                         READY   STATUS             RESTARTS   AGE
notes-api-7d4b8c9f5-abc12   0/1     CrashLoopBackOff   4          3m
notes-api-7d4b8c9f5-def34   0/1     CrashLoopBackOff   4          3m
notes-api-7d4b8c9f5-ghi56   0/1     CrashLoopBackOff   4          3m
postgres-0                   1/1     Running            0          5m
```

### Step 2: Check logs

```bash
$ kubectl logs notes-api-7d4b8c9f5-abc12 -n notes-app
Server running on port 3000
error: password authentication failed for user "notesadmin"
    at /app/node_modules/pg/lib/client.js:132:19
```

### Step 3: Identify the problem

The app is connecting to PostgreSQL but with the wrong password. Let's verify what each side expects:

```bash
# What password does PostgreSQL have?
$ kubectl get secret postgres-credentials -n notes-app -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
K8sDemo2024!

# What password does the app have?
$ kubectl exec notes-api-7d4b8c9f5-abc12 -n notes-app -- env | grep DB_PASSWORD
DB_PASSWORD=WrongPassword123
```

### Step 4: Fix the secret

```bash
# The app's secret reference is pointing to wrong key or a different secret
# Check the deployment
$ kubectl get deployment notes-api -n notes-app -o yaml | grep -A 5 DB_PASSWORD
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_PASSWORD

# The secret is correct, so let's check if someone edited the secret
$ kubectl edit secret postgres-credentials -n notes-app
# Fix the password value, or delete and recreate:

$ kubectl delete secret postgres-credentials -n notes-app
$ kubectl apply -f k8s/postgres-secret.yaml

# Restart the deployment to pick up new secret
$ kubectl rollout restart deployment/notes-api -n notes-app
```

### Step 5: Verify

```bash
$ kubectl get pods -n notes-app
NAME                         READY   STATUS    RESTARTS   AGE
notes-api-8e5c9d0f6-xyz78   1/1     Running   0          30s
notes-api-8e5c9d0f6-uvw90   1/1     Running   0          28s
notes-api-8e5c9d0f6-rst12   1/1     Running   0          25s
postgres-0                   1/1     Running   0          8m
```

---

## Worked Example 2: Missing ConfigMap

**Scenario:** Pods are stuck in `CreateContainerConfigError`.

### Step 1: Check status

```bash
$ kubectl get pods -n notes-app
NAME                         READY   STATUS                       RESTARTS   AGE
notes-api-7d4b8c9f5-abc12   0/1     CreateContainerConfigError   0          1m
```

### Step 2: Describe the pod

```bash
$ kubectl describe pod notes-api-7d4b8c9f5-abc12 -n notes-app
Events:
  Type     Reason     Age   From     Message
  ----     ------     ----  ----     -------
  Warning  Failed     30s   kubelet  Error: configmap "app-confg" not found
```

### Step 3: Fix it

Typo! `app-confg` instead of `app-config`.

```bash
# Option A: Fix the deployment to use correct name
kubectl edit deployment notes-api -n notes-app
# Change "app-confg" → "app-config"

# Option B: Or create a ConfigMap with the typo name (not ideal)
```

### Step 4: Verify

```bash
$ kubectl get pods -n notes-app
# Pods should move to Running once the ConfigMap reference is fixed
```

---

## Worked Example 3: Service Not Routing Traffic

**Scenario:** `curl http://localhost:8080/api/notes` returns connection refused after port-forward.

### Step 1: Check Service endpoints

```bash
$ kubectl get endpoints notes-api -n notes-app
NAME        ENDPOINTS   AGE
notes-api   <none>      5m
```

No endpoints! The Service isn't finding any pods.

### Step 2: Compare labels

```bash
# Service selector
$ kubectl get svc notes-api -n notes-app -o yaml | grep -A 2 selector
  selector:
    app: notes-api

# Pod labels
$ kubectl get pods -n notes-app --show-labels
NAME                         READY   STATUS    LABELS
notes-api-7d4b8c9f5-abc12   1/1     Running   app=note-api,pod-template-hash=7d4b8c9f5
```

### Step 3: Found it!

Pod label is `app=note-api` (missing 's'), Service selector is `app=notes-api`.

### Step 4: Fix the Deployment template labels

```bash
kubectl edit deployment notes-api -n notes-app
# Fix: template.metadata.labels.app: notes-api
```

After the fix, new pods come up with correct labels and the Service finds them.

---

## Worked Example 4: Pod Stuck in Pending

**Scenario:** After scaling to 10 replicas, some pods are Pending.

```bash
$ kubectl get pods -n notes-app
notes-api-xxx-1   1/1     Running   0   5m
notes-api-xxx-2   1/1     Running   0   5m
notes-api-xxx-3   1/1     Running   0   5m
notes-api-xxx-4   0/1     Pending   0   2m
notes-api-xxx-5   0/1     Pending   0   2m

$ kubectl describe pod notes-api-xxx-4 -n notes-app
Events:
  Warning  FailedScheduling  30s  default-scheduler
    0/1 nodes are available: 1 Insufficient cpu.
```

**Fix:** Either reduce CPU requests in the pod spec, or add more nodes to the cluster.

```bash
# Check how much is allocated vs available
kubectl describe node | grep -A 8 "Allocated resources"
```

---

## Quick Debug Checklist

When something doesn't work, run through these in order:

```bash
# 1. Are pods running?
kubectl get pods -n <namespace>

# 2. Why isn't this pod running?
kubectl describe pod <name> -n <namespace>

# 3. What does the app say?
kubectl logs <name> -n <namespace>
kubectl logs <name> --previous    # if crashed

# 4. Is the Service connected to pods?
kubectl get endpoints <service> -n <namespace>

# 5. Can pods reach each other?
kubectl exec -it <pod> -- nslookup <service-name>
kubectl exec -it <pod> -- curl <service-name>:<port>

# 6. What's happening cluster-wide?
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl top pods -n <namespace>
kubectl top nodes
```

---

## Exercises

1. **Break and fix:** Deploy the Module 6 notes-api but change the DB_HOST in the ConfigMap to `wrong-host`. Watch the CrashLoopBackOff, read the logs, identify the issue, and fix it.

2. **Label mismatch:** Deploy a Deployment and Service where the Service selector has a typo. Verify with `kubectl get endpoints`. Fix it and confirm traffic flows.

3. **Resource exhaustion:** Set a pod's memory limit to `10Mi` and watch it get OOMKilled. Check with `kubectl describe pod`. Fix it.

4. **Debug container:** Deploy a pod using a minimal image (like `gcr.io/distroless/static`). Try to exec in (it will fail — no shell). Use `kubectl debug` to attach a debug container.

5. **Full investigation:** Someone deployed this broken YAML. Find all the issues:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: broken-app
     namespace: test
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: my-app
     template:
       metadata:
         labels:
           app: broken-app    # ← Issue 1: doesn't match selector
       spec:
         containers:
         - name: app
           image: ngnix:latest  # ← Issue 2: typo in image name
           ports:
           - containerPort: 80
           envFrom:
           - configMapRef:
               name: app-cfg    # ← Issue 3: ConfigMap might not exist
           resources:
             limits:
               memory: "8Mi"   # ← Issue 4: way too low for nginx
   ```

---

[← Module 6: Working Demo](../06-demo/README.md) | [Module 7: Helm →](../07-helm/README.md)
