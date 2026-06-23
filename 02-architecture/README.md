# Module 2: Kubernetes Architecture

## The Big Picture

A Kubernetes cluster has two types of machines:

```
┌─────────────────────────────────────────────────────────────┐
│                     KUBERNETES CLUSTER                        │
│                                                              │
│  ┌──────────────────────┐    ┌────────────────────────────┐ │
│  │    CONTROL PLANE      │    │       WORKER NODES          │ │
│  │    (The Brain)        │    │       (The Muscle)          │ │
│  │                       │    │                             │ │
│  │  ┌─────────────────┐ │    │  ┌───────┐  ┌───────┐      │ │
│  │  │   API Server    │ │    │  │ Pod A │  │ Pod B │      │ │
│  │  ├─────────────────┤ │    │  └───────┘  └───────┘      │ │
│  │  │   Scheduler     │ │    │  ┌───────┐  ┌───────┐      │ │
│  │  ├─────────────────┤ │    │  │ Pod C │  │ Pod D │      │ │
│  │  │ Controller Mgr  │ │    │  └───────┘  └───────┘      │ │
│  │  ├─────────────────┤ │    │                             │ │
│  │  │     etcd        │ │    │  kubelet + kube-proxy       │ │
│  │  └─────────────────┘ │    │  (on every worker node)     │ │
│  └──────────────────────┘    └────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Control Plane Components

The control plane makes decisions about the cluster. It doesn't run your app — it manages everything.

### 1. API Server (`kube-apiserver`)

**What:** The front door to the cluster. Every command goes through it.

```bash
kubectl get pods  →  hits API Server  →  returns pod list
```

- All communication (internal and external) goes through the API server
- It validates and processes REST requests
- It's the ONLY component that talks to etcd directly

**Analogy:** The receptionist at a hospital — every request goes through them.

### 2. etcd

**What:** A distributed key-value store that holds ALL cluster state.

- Every pod, service, config — all stored here
- If etcd dies and isn't backed up, you lose your entire cluster state
- It's the single source of truth

**What's stored:**
```
/registry/pods/default/my-app-pod-xyz
/registry/services/default/my-service
/registry/deployments/default/my-deployment
```

**Analogy:** The hospital's patient records database.

### 3. Scheduler (`kube-scheduler`)

**What:** Decides WHICH node a new pod should run on.

**How it decides:**
1. Filters nodes that can't run the pod (not enough CPU/RAM, taints, etc.)
2. Ranks remaining nodes by criteria (spread, affinity, resource balance)
3. Picks the best one

```
New pod created → Scheduler picks Node-2 → Pod runs on Node-2
```

**Analogy:** Hospital admin deciding which ward has space for a new patient.

### 4. Controller Manager (`kube-controller-manager`)

**What:** Runs control loops that watch cluster state and make corrections.

Key controllers:
| Controller | What It Does |
|-----------|-------------|
| **ReplicaSet Controller** | Ensures desired number of pod replicas exist |
| **Deployment Controller** | Manages rollouts and rollbacks |
| **Node Controller** | Monitors node health, marks them unavailable |
| **Job Controller** | Manages one-off and scheduled jobs |
| **Service Account Controller** | Creates default accounts for namespaces |

**The reconciliation loop:**
```
1. Observe current state    (3 pods running? 2 pods running?)
2. Compare to desired state (spec says 3 replicas)
3. Take action             (start 1 more pod)
4. Repeat forever
```

**Analogy:** Hospital shift manager checking if enough staff are on duty.

### 5. Cloud Controller Manager (optional)

**What:** Integrates with cloud providers (AWS, GCP, Azure).

Handles:
- Creating cloud load balancers for `type: LoadBalancer` services
- Managing cloud storage volumes
- Managing node lifecycle (detects when a cloud VM is deleted)

Only exists if you're running on a cloud provider.

---

## Worker Node Components

Worker nodes run your actual application containers.

### 1. kubelet

**What:** The agent running on every worker node. It:
- Receives pod specs from the API server
- Ensures containers described in pod specs are running and healthy
- Reports node and pod status back to the control plane

```
API Server → "Run pod X on this node" → kubelet → starts containers
```

**Key point:** kubelet doesn't manage containers not created by Kubernetes.

### 2. kube-proxy

**What:** Network proxy on every node. Maintains network rules for pod communication.

- Implements the `Service` concept (virtual IPs that load-balance to pods)
- Uses iptables or IPVS rules under the hood
- Enables pod-to-pod and external-to-pod communication

```
Request to Service IP:port → kube-proxy → routes to actual pod
```

### 3. Container Runtime

**What:** The software that actually runs containers.

- **containerd** (default since K8s 1.24+)
- CRI-O (alternative)
- Docker was removed as a runtime in K8s 1.24 (but Docker images still work)

```
kubelet → talks to container runtime via CRI → container starts
```

---

## How It All Works Together

Let's trace what happens when you run `kubectl apply -f deployment.yaml`:

```
Step 1: kubectl sends YAML to API Server (via REST/HTTPS)
           │
Step 2: API Server validates it, stores in etcd
           │
Step 3: Deployment Controller notices new Deployment
         → Creates a ReplicaSet
           │
Step 4: ReplicaSet Controller notices ReplicaSet wants 3 pods
         → Creates 3 Pod objects (unscheduled)
           │
Step 5: Scheduler notices unscheduled pods
         → Assigns each to a node
           │
Step 6: kubelet on each assigned node notices its new pods
         → Tells container runtime to pull image & start containers
           │
Step 7: Containers start running
         → kubelet reports status back to API Server
           │
Step 8: kube-proxy updates network rules
         → Pod is now reachable via its Service
```

---

## Single Node vs. Multi-Node

### Minikube/kind (Learning)
```
┌──────────────────────────┐
│     Single Machine        │
│                           │
│  Control Plane + Worker   │
│  (everything in one)      │
└──────────────────────────┘
```

### Production
```
┌────────────┐  ┌────────────┐  ┌────────────┐
│ Master 1   │  │ Master 2   │  │ Master 3   │   ← HA control plane
└────────────┘  └────────────┘  └────────────┘
       │               │               │
┌──────┴───────────────┴───────────────┴──────┐
│                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Worker 1 │ │ Worker 2 │ │ Worker 3 │    │  ← your apps run here
│  └──────────┘ └──────────┘ └──────────┘    │
└──────────────────────────────────────────────┘
```

Production clusters typically have:
- 3 or 5 master nodes (odd number for etcd consensus)
- As many worker nodes as needed (can be hundreds)

---

## Component Communication Summary

```
┌─────────────────────────────────────────────┐
│                                             │
│  kubectl ──HTTPS──→ API Server              │
│                        │                    │
│                   ┌────┼────┐               │
│                   ▼    ▼    ▼               │
│               etcd  Sched  CtrlMgr          │
│                                             │
│  API Server ──────→ kubelet (per node)      │
│                        │                    │
│                        ▼                    │
│               Container Runtime             │
│                        │                    │
│                        ▼                    │
│                   Your Containers           │
│                                             │
└─────────────────────────────────────────────┘

All internal communication uses TLS certificates.
Components authenticate to each other via certificates or tokens.
```

---

## Key Takeaways

| Component | Runs On | Role |
|-----------|---------|------|
| API Server | Control plane | Front door, all requests go through it |
| etcd | Control plane | Stores ALL cluster data |
| Scheduler | Control plane | Decides where pods run |
| Controller Manager | Control plane | Ensures desired state matches actual state |
| kubelet | Every worker node | Starts/stops containers, reports health |
| kube-proxy | Every worker node | Network routing for services |
| Container Runtime | Every worker node | Actually runs the containers |

---

## ⚠️ Common Gotchas

### "The API server is down — is my app dead?"
**The mistake:** Thinking the control plane runs your app.
**Why it happens:** The architecture looks like everything connects to the control plane.
**How to avoid:** Remember: the control plane manages, worker nodes run. If the API server dies, existing pods keep running. You just can't deploy changes or scale until it recovers.

### "I lost my etcd data — can I recover?"
**The mistake:** Not backing up etcd.
**Why it happens:** etcd seems like an internal detail. People forget it holds ALL cluster state.
**How to avoid:** In production, always back up etcd. Managed K8s services (EKS, GKE, AKS) handle this for you. Self-managed clusters need `etcdctl snapshot save`.

### "I'll just run one master node"
**The mistake:** Single control plane node in production.
**Why it happens:** Seems simpler and cheaper.
**How to avoid:** Use 3 or 5 master nodes for high availability. etcd needs a majority (quorum) to function — 2 nodes is actually worse than 1 (no quorum if one dies).

---

## Exercises

1. Draw the architecture from memory — label each component and its role.
2. Trace what happens when a pod crashes. Which components are involved in restarting it?
3. What happens if etcd goes down? What about the scheduler?
4. Why does production use 3 or 5 master nodes (not 2 or 4)?

---

[← Module 1: Why Kubernetes](../01-why-kubernetes/README.md) | [Module 3: Core Concepts →](../03-core-concepts/README.md)
