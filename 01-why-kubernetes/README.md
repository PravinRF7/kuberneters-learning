# Module 1: Why Kubernetes?

## The Problem Before Kubernetes

Imagine you have a web app running in Docker containers. Things work fine... until:

1. **Your app crashes** → Who restarts it? You, at 3 AM?
2. **Traffic spikes** → You need 10 copies, not 1. Who spins them up?
3. **A server dies** → Your containers die with it. Now what?
4. **You need to deploy a new version** → How do you do it without downtime?
5. **You have 50 microservices** → How do they find and talk to each other?

### Without Kubernetes, you'd manually:
- SSH into servers
- Run `docker run` commands
- Set up load balancers by hand
- Write custom scripts for health checks
- Pray nothing breaks at night

**This doesn't scale.** This is exactly what Kubernetes solves.

---

## What Kubernetes Actually Does

Kubernetes (K8s) is a **container orchestration platform**. It:

| Problem | K8s Solution |
|---------|-------------|
| Container crashes | Auto-restarts it (self-healing) |
| Need more copies | Auto-scales based on load |
| Server dies | Moves containers to healthy nodes |
| New version deploy | Rolling updates with zero downtime |
| Service discovery | Built-in DNS and load balancing |
| Config management | ConfigMaps and Secrets |

**In one sentence:** You tell Kubernetes the *desired state* ("I want 3 copies of my app running"), and it makes it happen and keeps it that way.

---

## The Declarative Model

This is the KEY mental model:

```
Traditional: "Run this container on server-2" (imperative — you say HOW)
Kubernetes:  "I want 3 replicas of my app"     (declarative — you say WHAT)
```

You write YAML files describing what you want. Kubernetes figures out how to make it happen.

```yaml
# You declare this:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3  # "I want 3 copies"
```

Kubernetes then:
1. Schedules 3 pods across available nodes
2. Monitors them continuously
3. If one dies → spins up a replacement automatically

---

## Real-World Use Cases

### When Kubernetes Makes Sense

| Use Case | Why K8s Helps |
|----------|---------------|
| **Microservices** | Manage dozens of services, their networking, scaling independently |
| **CI/CD Pipelines** | Consistent deploy target, easy rollbacks |
| **Auto-scaling workloads** | Handle traffic spikes without over-provisioning |
| **Multi-cloud/Hybrid** | Same API works on AWS, GCP, Azure, on-prem |
| **Batch processing** | Jobs, CronJobs for scheduled workloads |
| **Dev/staging environments** | Namespaces isolate teams/environments on same cluster |

### Real Examples
- **Netflix** → Manages thousands of microservices
- **Spotify** → Runs ML pipelines and backend services
- **Airbnb** → Moved from monolith to microservices on K8s
- **Banks** → Run trading platforms needing high availability

---

## When NOT to Use Kubernetes

Be honest with yourself — K8s adds complexity. Skip it if:

| Scenario | Better Alternative |
|----------|-------------------|
| Single simple app | Docker Compose, or just a VM |
| Small team (1-3 devs) | Managed PaaS (Heroku, Railway, Fly.io) |
| No containerization yet | Containerize first, then consider K8s |
| Low traffic, no scaling needs | A single server is fine |
| You want serverless | AWS Lambda, Cloud Functions |

**Rule of thumb:** If you have <5 services and predictable traffic, Kubernetes is probably overkill.

---

## Kubernetes vs. Alternatives

| Tool | What It Is | When to Use |
|------|-----------|-------------|
| **Docker Compose** | Multi-container on ONE machine | Local dev, simple apps |
| **Docker Swarm** | Simple orchestration | Small clusters, simpler needs |
| **Kubernetes** | Full orchestration platform | Production microservices at scale |
| **Nomad (HashiCorp)** | Lighter orchestrator | When K8s is too heavy |
| **ECS/Fargate (AWS)** | Managed containers | AWS-only, don't want to manage K8s |

---

## Key Terminology (First Pass)

| Term | Plain English |
|------|--------------|
| **Cluster** | A set of machines (nodes) that K8s manages |
| **Node** | A single machine (physical or VM) in the cluster |
| **Pod** | The smallest deployable unit — one or more containers |
| **kubectl** | The CLI tool you use to talk to Kubernetes |
| **Manifest** | A YAML file describing what you want deployed |

---

## Summary

```
Before K8s: You manage containers manually on servers
With K8s:   You declare desired state → K8s maintains it automatically

K8s gives you: self-healing, auto-scaling, rolling deploys,
               service discovery, and a consistent platform everywhere.
```

---

## ⚠️ Common Gotchas

### "I'll just use Kubernetes for everything"
**The mistake:** Reaching for K8s when a simple Docker Compose or PaaS would do.
**Why it happens:** K8s is popular, so it feels like the "right" choice.
**How to avoid:** If you have 1-3 services with predictable traffic, start simpler. You can always migrate later. Kubernetes adds operational overhead that only pays off at scale.

### "Kubernetes will fix my bad architecture"
**The mistake:** Hoping K8s will solve problems caused by tightly coupled services, no health checks, or apps that can't handle restarts.
**Why it happens:** K8s promises self-healing and scaling, so people assume it handles everything.
**How to avoid:** Your app must be container-friendly first — stateless where possible, handles SIGTERM gracefully, uses environment variables for config. K8s orchestrates containers; it doesn't fix what's inside them.

### "I need to learn everything before starting"
**The mistake:** Spending weeks studying before touching a cluster.
**Why it happens:** The ecosystem is huge (Helm, Istio, ArgoCD, Operators...).
**How to avoid:** Start with Modules 1-6. That's enough to deploy real apps. Learn the rest as you need it on real projects.

---

## Exercise

Answer these to check your understanding:

1. What's the difference between imperative and declarative management?
2. Name 3 problems Kubernetes solves that Docker alone doesn't.
3. Give 2 scenarios where Kubernetes would be overkill.
4. What does "desired state" mean in the context of K8s?

---

[Next: Module 2 — Architecture →](../02-architecture/README.md)
