# Module 11a: CI/CD with Kubernetes — The Basics

## What You'll Build

A simple pipeline: **push code → build Docker image → deploy to cluster**. That's it. No fancy tools, no GitOps controllers — just GitHub Actions, Docker, and kubectl.

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
│ git push │────►│ GitHub Action │────►│ Docker Build │────►│ kubectl     │
│ to main  │     │ triggered    │     │ + Push       │     │ apply/set   │
└──────────┘     └──────────────┘     └──────────────┘     └─────────────┘
```

**Prerequisites:** You should have completed Module 6 (Working Demo) and be comfortable with Deployments, Services, and kubectl.

---

## Why Automate Deployments?

Manual deployments:
```
1. Change code
2. docker build ...
3. docker push ...
4. SSH to cluster / kubectl set image ...
5. Hope you didn't typo the tag
6. Forget which version is deployed
```

Automated CI/CD:
```
1. Change code
2. git push
3. ☕ (pipeline handles the rest)
```

Every push produces a traceable artifact. You always know what's deployed because the pipeline did it.

---

## The Simplest Pipeline

We'll deploy the Module 6 notes-api app on every push to `main`.

### What you need

1. A GitHub repo with your app code + Dockerfile
2. A container registry (we'll use GitHub Container Registry — free)
3. A Kubernetes cluster with kubectl access
4. A kubeconfig stored as a GitHub secret

### Repo structure

```
my-notes-app/
├── app/
│   ├── server.js
│   ├── package.json
│   └── Dockerfile
├── k8s/
│   ├── namespace.yaml
│   ├── postgres-secret.yaml
│   ├── postgres.yaml
│   ├── app-config.yaml
│   ├── app-deployment.yaml
│   └── ingress.yaml
└── .github/
    └── workflows/
        └── deploy.yaml
```

---

## Step 1: The GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yaml
name: Build and Deploy

on:
  push:
    branches: [main]

env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}/notes-api
  NAMESPACE: notes-app

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Log in to GitHub Container Registry
      run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

    - name: Build Docker image
      run: docker build -t ${{ env.IMAGE_NAME }}:${{ github.sha }} -t ${{ env.IMAGE_NAME }}:latest ./app

    - name: Push image
      run: |
        docker push ${{ env.IMAGE_NAME }}:${{ github.sha }}
        docker push ${{ env.IMAGE_NAME }}:latest

  deploy:
    needs: build
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up kubectl
      uses: azure/setup-kubectl@v3

    - name: Configure kubeconfig
      run: |
        mkdir -p $HOME/.kube
        echo "${{ secrets.KUBECONFIG }}" | base64 -d > $HOME/.kube/config

    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/notes-api \
          notes-api=${{ env.IMAGE_NAME }}:${{ github.sha }} \
          -n ${{ env.NAMESPACE }}

    - name: Wait for rollout
      run: kubectl rollout status deployment/notes-api -n ${{ env.NAMESPACE }} --timeout=120s

    - name: Verify deployment
      run: |
        kubectl get pods -n ${{ env.NAMESPACE }}
        echo "Deployed ${{ env.IMAGE_NAME }}:${{ github.sha }}"
```

---

## Step 2: Set Up GitHub Secrets

You need one secret: `KUBECONFIG` — your cluster's kubeconfig file, base64-encoded.

```bash
# Encode your kubeconfig
cat ~/.kube/config | base64 -w 0

# Go to GitHub → Repo → Settings → Secrets and variables → Actions
# Add secret: KUBECONFIG = <paste the base64 output>
```

⚠️ **Security note:** This gives your pipeline full cluster access. In production, create a ServiceAccount with limited RBAC (see Module 9) and use its token instead.

---

## Step 3: Initial Deployment (One-time)

The pipeline updates an existing deployment. You need the initial resources deployed first:

```bash
# First-time setup (run manually once)
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/app-config.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/ingress.yaml
```

After this, every push to `main` will:
1. Build a new image tagged with the commit SHA
2. Update the deployment to use that image
3. Kubernetes does a rolling update (zero downtime)

---

## Step 4: Test It

```bash
# Make a code change
echo "// version 2" >> app/server.js

# Push
git add -A && git commit -m "deploy v2" && git push origin main

# Watch the GitHub Actions tab — build and deploy jobs run
# Then verify:
kubectl get pods -n notes-app
kubectl describe deployment notes-api -n notes-app | grep Image
# Image: ghcr.io/youruser/my-notes-app/notes-api:abc123def
```

---

## Adding Tests to the Pipeline

A real pipeline runs tests before deploying:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: '20'
    - run: cd app && npm install && npm test

  build:
    needs: test    # only build if tests pass
    # ... same as before

  deploy:
    needs: build
    # ... same as before
```

---

## Rollback

If a deployment goes wrong:

```bash
# Immediate rollback to previous version
kubectl rollout undo deployment/notes-api -n notes-app

# Rollback to specific revision
kubectl rollout history deployment/notes-api -n notes-app
kubectl rollout undo deployment/notes-api --to-revision=3 -n notes-app
```

Or revert the commit and push — the pipeline will deploy the old code again.

---

## Image Tagging Strategy

| Strategy | Tag Example | Pros | Cons |
|----------|-------------|------|------|
| **Git SHA** | `abc123def` | Unique, traceable to commit | Not human-readable |
| **Semantic** | `v1.2.3` | Clear versioning | Requires manual bumps |
| **Branch + SHA** | `main-abc123` | Clear source | Verbose |
| **latest** | `latest` | Simple | Can't tell what's deployed |

**Recommendation:** Use git SHA for deployments (traceable), push `latest` too for convenience.

---

## Full-Stack Pipeline (Apply All Manifests)

If you also want manifest changes deployed automatically:

```yaml
    - name: Deploy all manifests
      run: |
        kubectl apply -f k8s/namespace.yaml
        kubectl apply -f k8s/postgres-secret.yaml
        kubectl apply -f k8s/postgres.yaml
        kubectl apply -f k8s/app-config.yaml
        kubectl apply -f k8s/app-deployment.yaml
        kubectl apply -f k8s/ingress.yaml
        
        # Update image to current build
        kubectl set image deployment/notes-api \
          notes-api=${{ env.IMAGE_NAME }}:${{ github.sha }} \
          -n notes-app
        
        kubectl rollout status deployment/notes-api -n notes-app --timeout=120s
```

---

## Pipeline Diagram

```
Push to main
     │
     ▼
┌──────────┐   fail
│   Test   │──────────► ✗ Pipeline stops, you get notified
│          │
└────┬─────┘
     │ pass
     ▼
┌──────────┐
│  Build   │──► docker build → docker push (ghcr.io/...)
│  Image   │
└────┬─────┘
     │
     ▼
┌──────────┐
│  Deploy  │──► kubectl set image → rollout status
│          │
└────┬─────┘
     │
     ▼
  ✓ Deployed!
```

---

## Exercises

1. **Set up the pipeline:** Fork a repo with a Dockerfile. Add the GitHub Actions workflow. Push a change and watch it deploy.

2. **Add tests:** Add a test step that runs before build. Make a test fail and verify the pipeline stops (no deploy).

3. **Rollback drill:** Deploy a broken version intentionally (wrong DB password). Use `kubectl rollout undo` to revert. Observe zero-downtime rollback.

4. **Multiple environments:** Modify the pipeline to deploy to `staging` namespace on pushes to `develop` branch, and `production` namespace on pushes to `main`.

---

**Ready for production-grade GitOps?** → [Module 11b: GitOps with ArgoCD →](../11b-gitops/README.md)

---

[← Module 10: Scheduling](../10-scheduling/README.md) | [Module 11b: GitOps →](../11b-gitops/README.md)
