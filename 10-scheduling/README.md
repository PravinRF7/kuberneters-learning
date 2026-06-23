# Module 10: Taints, Tolerations & Affinity `[Intermediate]`

## Overview

These control **WHERE** pods get scheduled:

| Mechanism | Who Sets It | Effect |
|-----------|------------|--------|
| **Taints** | Node admin | Repels pods FROM a node |
| **Tolerations** | Pod spec | Allows a pod to tolerate a taint |
| **Node Affinity** | Pod spec | Attracts pods TO specific nodes |
| **Pod Affinity/Anti-Affinity** | Pod spec | Attracts/repels pods relative to OTHER pods |

---

## 1. Taints & Tolerations

### Taints — "Keep pods away from this node"

```bash
# Add a taint
kubectl taint nodes node1 gpu=true:NoSchedule

# Format: key=value:effect
```

**Effects:**

| Effect | Behavior |
|--------|----------|
| `NoSchedule` | New pods won't be scheduled (existing stay) |
| `PreferNoSchedule` | Avoid scheduling here, but allow if needed |
| `NoExecute` | Evict existing pods + don't schedule new ones |

```bash
# See taints on a node
kubectl describe node node1 | grep Taints

# Remove a taint
kubectl taint nodes node1 gpu=true:NoSchedule-
```

### Tolerations — "This pod CAN run on tainted nodes"

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-job
spec:
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  containers:
  - name: ml-training
    image: tensorflow/tensorflow:latest-gpu
```

This pod tolerates the `gpu=true:NoSchedule` taint, so it CAN be scheduled on node1.

### Real-World Uses

| Scenario | Taint | Who Tolerates |
|----------|-------|---------------|
| GPU nodes | `gpu=true:NoSchedule` | Only ML workloads |
| Master nodes | `node-role.kubernetes.io/master:NoSchedule` | System pods only |
| Dedicated team nodes | `team=data:NoSchedule` | Only data team's pods |
| Spot/preemptible nodes | `spot=true:NoSchedule` | Fault-tolerant workloads |

---

## 2. Node Affinity

### "Schedule this pod on nodes with specific labels"

First, label your nodes:

```bash
kubectl label nodes node1 disktype=ssd
kubectl label nodes node2 disktype=hdd
kubectl label nodes node1 zone=us-east-1a
```

### requiredDuringSchedulingIgnoredDuringExecution (hard rule)

Pod MUST be scheduled on matching nodes. Stays pending if none match.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ssd-app
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disktype
            operator: In
            values:
            - ssd
  containers:
  - name: app
    image: nginx
```

### preferredDuringSchedulingIgnoredDuringExecution (soft rule)

Try to schedule on matching nodes, but fallback to others if needed.

```yaml
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80
        preference:
          matchExpressions:
          - key: zone
            operator: In
            values:
            - us-east-1a
      - weight: 20
        preference:
          matchExpressions:
          - key: disktype
            operator: In
            values:
            - ssd
```

Higher weight = stronger preference.

### Operators

| Operator | Meaning |
|----------|---------|
| `In` | Label value is in the list |
| `NotIn` | Label value is NOT in the list |
| `Exists` | Label key exists (any value) |
| `DoesNotExist` | Label key doesn't exist |
| `Gt` / `Lt` | Greater/less than (numeric strings) |

---

## 3. Pod Affinity & Anti-Affinity

### Pod Affinity — "Schedule near other pods"

"Put my frontend pods on the SAME node/zone as my backend pods"

```yaml
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - backend
        topologyKey: kubernetes.io/hostname   # same node
```

### Pod Anti-Affinity — "Schedule AWAY from other pods"

"Spread my replicas across different nodes" (for high availability):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-server
  template:
    metadata:
      labels:
        app: web-server
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - web-server
            topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx
```

Each replica MUST be on a different node. If you only have 2 nodes and want 3 replicas, the 3rd pod stays `Pending`.

### Topology Keys

| Key | Spread Across |
|-----|--------------|
| `kubernetes.io/hostname` | Different nodes |
| `topology.kubernetes.io/zone` | Different availability zones |
| `topology.kubernetes.io/region` | Different regions |

---

## 4. Topology Spread Constraints

More flexible than anti-affinity for even pod distribution:

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web-server
```

This ensures pods are spread evenly across zones (max difference of 1 between any two zones).

---

## Decision Guide

```
Need to REPEL pods from a node?
  → Taint the node + add tolerations to allowed pods

Need to ATTRACT pods to specific nodes?
  → Label nodes + use nodeAffinity

Need pods CO-LOCATED (same node/zone)?
  → Use podAffinity

Need pods SPREAD OUT (different nodes/zones)?
  → Use podAntiAffinity or topologySpreadConstraints
```

---

## Useful Commands

```bash
# Labels
kubectl get nodes --show-labels
kubectl label nodes node1 disktype=ssd
kubectl label nodes node1 disktype-          # remove label

# Taints
kubectl taint nodes node1 key=value:NoSchedule
kubectl taint nodes node1 key=value:NoSchedule-  # remove

# Debug scheduling
kubectl describe pod <pending-pod>    # check Events for scheduling failures
kubectl get events --field-selector reason=FailedScheduling
```

---

## Exercises

1. Taint a node with `env=production:NoSchedule`. Deploy a pod without tolerations (should stay Pending). Add the toleration and watch it schedule.
2. Label a node with `disktype=ssd`. Create a pod with nodeAffinity requiring SSD nodes.
3. Deploy 3 replicas with pod anti-affinity across nodes. Verify each pod lands on a different node.
4. Use `preferredDuringScheduling` to prefer SSD nodes but allow fallback.

---

[← Module 9: RBAC](../09-rbac/README.md) | [Module 11: CI/CD →](../11-cicd/README.md)
