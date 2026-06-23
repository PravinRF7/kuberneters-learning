# Module 11b: GitOps with ArgoCD `[Advanced]`

## ⚠️ Prerequisites

This module assumes you:
- Completed Module 11a (basic CI/CD pipeline)
- Are comfortable with Deployments, Services, and kubectl
- Have a working cluster (Minikube or cloud)

If you just want "git push → deploy", Module 11a is enough. This module is for **production-grade declarative delivery**.

---

## What is GitOps?

**Core principle:** Git is the single source of truth for your cluster state.

```
Push-based CI/CD (Module 11a):
  CI pipeline has credentials → pushes changes TO cluster

GitOps (pull-based):
  ArgoCD runs IN cluster → pulls desired state FROM git → applies it
```

### Why GitOps?

| Problem with Push-based | GitOps Solution |
|------------------------|-----------------|
| CI tool needs cluster credentials | Cluster pulls from git — no external access needed |
| Someone changes cluster manually, state drifts | ArgoCD detects drift and auto-corrects |
| No audit trail of what changed when | Git history IS the audit trail |
| Hard to know current state | Git repo = source of truth |
| Rollback = re-run pipeline | Rollback = `git revert` |

---

## The GitOps Model

```
┌──────────────┐     ┌──────────────────┐     ┌───────────────┐
│  App Repo    │     │  Manifests Repo   │     │  Kubernetes   │
│  (code)      │     │  (desired state)  │     │  Cluster      │
│              │     │                   │     │               │
│  Dockerfile  │     │  deployment.yaml  │◄────│  ArgoCD       │
│  server.js   │     │  service.yaml     │     │  (watches &   │
│              │     │  kustomization    │     │   syncs)      │
└──────┬───────┘     └──────────────────┘     └───────────────┘
       │                      ▲
       │ CI builds image,     │
       │ updates image tag    │
       └──────────────────────┘
```

**Two repos pattern:**
1. **App repo** — source code + Dockerfile (CI builds images)
2. **Manifests repo** — K8s YAML (ArgoCD syncs from this)

---

## Setting Up ArgoCD

### Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for it to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
```

### Access the UI

```bash
# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Open https://localhost:8080
# Login: admin / <password from above>
```

### Install ArgoCD CLI (optional)

```bash
# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# Login
argocd login localhost:8080 --insecure
```

---

## Kustomize: Managing Environments

Before connecting ArgoCD, let's organize manifests for multiple environments using Kustomize (built into kubectl).

### Directory structure

```
k8s-manifests/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── replicas-patch.yaml
    └── production/
        ├── kustomization.yaml
        └── replicas-patch.yaml
```

### base/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- namespace.yaml
- deployment.yaml
- service.yaml
- configmap.yaml
```

### base/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-api
  namespace: notes-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notes-api
  template:
    metadata:
      labels:
        app: notes-api
    spec:
      containers:
      - name: notes-api
        image: ghcr.io/youruser/notes-api:latest
        ports:
        - containerPort: 3000
        envFrom:
        - configMapRef:
            name: app-config
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
```

### overlays/staging/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

namespace: notes-app-staging

patches:
- path: replicas-patch.yaml

images:
- name: ghcr.io/youruser/notes-api
  newTag: staging-abc123
```

### overlays/staging/replicas-patch.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-api
spec:
  replicas: 2
```

### overlays/production/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

namespace: notes-app-production

patches:
- path: replicas-patch.yaml

images:
- name: ghcr.io/youruser/notes-api
  newTag: v1.2.0
```

### overlays/production/replicas-patch.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-api
spec:
  replicas: 5
```

### Preview what Kustomize generates

```bash
# See what staging would apply
kubectl kustomize overlays/staging/

# Apply it directly
kubectl apply -k overlays/staging/
```

---

## Creating an ArgoCD Application

### Option 1: YAML manifest

```yaml
# argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: notes-app-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/youruser/k8s-manifests.git
    targetRevision: main
    path: overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: notes-app-production
  syncPolicy:
    automated:
      prune: true       # delete resources removed from git
      selfHeal: true    # revert manual cluster changes
    syncOptions:
    - CreateNamespace=true
```

```bash
kubectl apply -f argocd-app.yaml
```

### Option 2: CLI

```bash
argocd app create notes-app-production \
  --repo https://github.com/youruser/k8s-manifests.git \
  --path overlays/production \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace notes-app-production \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

---

## The GitOps Workflow in Action

### Deploy a new version

```bash
# 1. CI builds new image: ghcr.io/youruser/notes-api:v1.3.0

# 2. Update manifests repo (this triggers ArgoCD)
cd k8s-manifests
sed -i 's/newTag: v1.2.0/newTag: v1.3.0/' overlays/production/kustomization.yaml
git add -A && git commit -m "deploy: notes-api v1.3.0" && git push

# 3. ArgoCD detects the change within ~3 minutes (default poll interval)
#    → syncs the new manifests → rolling update happens
```

### Check sync status

```bash
argocd app get notes-app-production

# Or in kubectl
kubectl get applications -n argocd
```

### Drift detection (self-heal)

```bash
# Someone manually scales the deployment
kubectl scale deployment/notes-api --replicas=1 -n notes-app-production

# ArgoCD notices within minutes: "Hey, git says 5 replicas!"
# selfHeal: true → ArgoCD reverts it back to 5
```

### Rollback

```bash
# Option 1: Git revert (preferred — audit trail)
git revert HEAD
git push

# Option 2: ArgoCD rollback (to previous sync)
argocd app rollback notes-app-production
```

---

## Full CI + GitOps Pipeline

Combine Module 11a's CI with ArgoCD's CD:

```yaml
# In your APP repo: .github/workflows/ci.yaml
name: CI - Build and Update Manifests

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
    - uses: actions/checkout@v4

    - name: Login to GHCR
      run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

    - name: Build and push
      run: |
        docker build -t ghcr.io/${{ github.repository }}/notes-api:${{ github.sha }} ./app
        docker push ghcr.io/${{ github.repository }}/notes-api:${{ github.sha }}

  update-manifests:
    needs: build
    runs-on: ubuntu-latest
    steps:
    - name: Checkout manifests repo
      uses: actions/checkout@v4
      with:
        repository: youruser/k8s-manifests
        token: ${{ secrets.MANIFESTS_PAT }}

    - name: Update image tag
      run: |
        cd overlays/staging
        kustomize edit set image ghcr.io/youruser/notes-api=ghcr.io/${{ github.repository }}/notes-api:${{ github.sha }}

    - name: Commit and push
      run: |
        git config user.name "github-actions"
        git config user.email "actions@github.com"
        git add -A
        git commit -m "chore: update notes-api to ${{ github.sha }}"
        git push
```

Now the flow is:
```
App code push → CI builds image → CI updates manifests repo → ArgoCD syncs to cluster
```

No cluster credentials in CI. ArgoCD handles the deployment.

---

## ArgoCD Application Sets (Multi-environment)

Deploy to staging AND production from one config:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: notes-app
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - environment: staging
        namespace: notes-app-staging
      - environment: production
        namespace: notes-app-production
  template:
    metadata:
      name: 'notes-app-{{environment}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/youruser/k8s-manifests.git
        targetRevision: main
        path: 'overlays/{{environment}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

---

## GitOps Best Practices

| Practice | Why |
|----------|-----|
| Separate app repo from manifests repo | Decouple build from deploy |
| Use image digests, not `latest` | Immutable, auditable deploys |
| Enable `selfHeal` | Prevent drift from manual changes |
| Enable `prune` | Ensure deleted resources are cleaned up |
| Use branch protection on manifests repo | Prevent unauthorized deploys |
| Review manifest changes via PRs | Peer review before production changes |

---

## Push-based vs GitOps: Decision Guide

| Criteria | Push-based (11a) | GitOps (11b) |
|----------|-----------------|--------------|
| **Complexity** | Low — just CI + kubectl | Higher — ArgoCD + manifests repo |
| **Team size** | 1-5 devs | 5+ devs, multiple services |
| **Audit trail** | CI logs only | Full git history |
| **Drift detection** | None | Automatic |
| **Security** | CI needs cluster creds | No external creds needed |
| **Rollback** | `kubectl rollout undo` | `git revert` |
| **Setup time** | 30 minutes | 2-4 hours |

**Start with 11a.** Move to GitOps when you need audit trails, drift detection, or manage multiple environments/teams.

---

## Exercises

1. **Install ArgoCD:** Deploy ArgoCD on Minikube. Access the UI. Create an Application pointing to a public git repo with K8s manifests.

2. **GitOps deploy:** Push a manifest change (update replica count) to your git repo. Watch ArgoCD sync automatically.

3. **Drift detection:** Manually change something in the cluster (`kubectl scale`). Observe ArgoCD detect and revert the drift.

4. **Kustomize overlays:** Create base + staging + production overlays. Deploy both via ArgoCD ApplicationSet.

5. **Full pipeline:** Set up the CI + GitOps pipeline — code push triggers image build, which updates manifests repo, which ArgoCD syncs to cluster.

---

[← Module 11a: Basic CI/CD](../11a-cicd-basic/README.md) | [Module 12: Monitoring →](../12-monitoring/README.md)
