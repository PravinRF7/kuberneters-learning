# Module 11: CI/CD with Kubernetes `[Advanced]`

## What is CI/CD for Kubernetes?

```
Code Push → Build Image → Push to Registry → Deploy to Cluster → Verify
```

| Stage | Tools |
|-------|-------|
| **CI** (Continuous Integration) | GitHub Actions, GitLab CI, Jenkins |
| **CD** (Continuous Delivery) | ArgoCD, Flux, Spinnaker, plain kubectl |
| **Registry** | Docker Hub, ECR, GCR, GHCR |

---

## Approach 1: Push-Based (CI tool deploys)

```
Developer → git push → CI Pipeline → kubectl apply → Cluster
```

### GitHub Actions Example

```yaml
# .github/workflows/deploy.yaml
name: Build and Deploy

on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Build Docker image
      run: docker build -t ghcr.io/${{ github.repository }}/app:${{ github.sha }} .

    - name: Login to GHCR
      run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

    - name: Push image
      run: docker push ghcr.io/${{ github.repository }}/app:${{ github.sha }}

    - name: Set up kubectl
      uses: azure/setup-kubectl@v3

    - name: Configure kubeconfig
      run: echo "${{ secrets.KUBECONFIG }}" | base64 -d > $HOME/.kube/config

    - name: Deploy
      run: |
        kubectl set image deployment/my-app \
          app=ghcr.io/${{ github.repository }}/app:${{ github.sha }} \
          -n production
        kubectl rollout status deployment/my-app -n production
```

**Pros:** Simple, familiar.
**Cons:** CI needs cluster credentials, no drift detection.

---

## Approach 2: GitOps with ArgoCD (Pull-Based)

```
Developer → git push manifests → ArgoCD watches repo → syncs to cluster
```

The cluster pulls desired state from Git. No external tool needs cluster access.

### Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Create an ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: notes-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/youruser/k8s-manifests.git
    targetRevision: main
    path: apps/notes-app
  destination:
    server: https://kubernetes.default.svc
    namespace: notes-app
  syncPolicy:
    automated:
      prune: true         # delete resources removed from git
      selfHeal: true      # revert manual cluster changes
    syncOptions:
    - CreateNamespace=true
```

Push changes to `apps/notes-app/` in your repo → ArgoCD auto-syncs to cluster.

---

## Approach 3: Kustomize for Environments

```
k8s-manifests/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── staging/
    │   └── kustomization.yaml
    └── production/
        └── kustomization.yaml
```

```yaml
# base/kustomization.yaml
resources:
- deployment.yaml
- service.yaml

# overlays/production/kustomization.yaml
resources:
- ../../base
patches:
- patch: |
    - op: replace
      path: /spec/replicas
      value: 5
  target:
    kind: Deployment
    name: my-app
images:
- name: my-app
  newTag: v2.1.0
```

```bash
kubectl apply -k overlays/production/
```

---

## Which Approach?

| Approach | Best For |
|----------|----------|
| **kubectl in CI** | Small teams, simple apps |
| **ArgoCD/Flux (GitOps)** | Production, audit trail, drift detection |
| **Helm + ArgoCD** | Complex apps with many config variations |
| **Kustomize + ArgoCD** | Overlays without templating |

---

## Exercises

1. Create a GitHub Actions workflow that builds and pushes a Docker image on every push to `main`.
2. Install ArgoCD. Create an Application pointing to a Git repo.
3. Push a manifest change and watch ArgoCD auto-sync.
4. Set up Kustomize overlays for staging vs production.

---

[← Module 10: Scheduling](../10-scheduling/README.md) | [Module 12: Monitoring →](../12-monitoring/README.md)
