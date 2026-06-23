# Kubernetes - Complete Learning Path

A structured, ground-up learning guide to Kubernetes — from "why does it exist?" to deploying a real application and beyond.

## Learning Modules

### Core (Start Here)

| # | Module | What You'll Learn |
|---|--------|-------------------|
| 1 | [Why Kubernetes](./01-why-kubernetes/README.md) | The problem it solves, use cases, when to use (and NOT use) it |
| 2 | [Architecture](./02-architecture/README.md) | Control plane, worker nodes, how all pieces fit together |
| 3 | [Core Concepts](./03-core-concepts/README.md) | Pods, Services, Deployments, ReplicaSets, Namespaces |
| 4 | [Networking & Storage](./04-networking-storage/README.md) | Cluster networking, Ingress, PVs, PVCs, StorageClasses |
| 5 | [Configuration & Secrets](./05-configuration/README.md) | ConfigMaps, Secrets, Environment variables, Resource limits |
| 6 | [Working Demo](./06-demo/README.md) | Build & deploy a real app from scratch to cluster |

### Intermediate

| # | Module | What You'll Learn |
|---|--------|-------------------|
| 7 | [Helm](./07-helm/README.md) | Package manager for K8s — charts, templates, repos |
| 8 | [HorizontalPodAutoscaler](./08-hpa/README.md) | Auto-scaling based on CPU, memory, custom metrics |
| 9 | [RBAC](./09-rbac/README.md) | Roles, ClusterRoles, bindings, ServiceAccounts |
| 10 | [Taints, Tolerations & Affinity](./10-scheduling/README.md) | Advanced pod scheduling and placement |

### Advanced

| # | Module | What You'll Learn |
|---|--------|-------------------|
| 11 | [CI/CD with Kubernetes](./11-cicd/README.md) | GitOps, ArgoCD, GitHub Actions, Kustomize |
| 12 | [Monitoring](./12-monitoring/README.md) | Prometheus, Grafana, alerting, PromQL |
| 13 | [Service Mesh](./13-service-mesh/README.md) | Istio/Linkerd, mTLS, traffic management, canary deploys |
| 14 | [Custom Resource Definitions](./14-crds/README.md) | Extending Kubernetes, Operators, Controllers |

## Prerequisites

- Basic understanding of Docker/containers
- A terminal with `kubectl` installed
- One of: Minikube, kind, Docker Desktop (with K8s enabled), or a cloud cluster

## How to Use This Repo

1. Read modules 1-6 in order (Core) — these are essential
2. Try the YAML examples and complete the exercises
3. Module 6 ties everything together into a real deployment
4. Modules 7-10 (Intermediate) — learn as you need them on real projects
5. Modules 11-14 (Advanced) — for production-grade setups

## Quick Setup (Minikube)

```bash
# Install minikube (Linux)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start cluster
minikube start

# Verify
kubectl get nodes
```
