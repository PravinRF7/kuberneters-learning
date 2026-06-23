# Module 14: Custom Resource Definitions (CRDs) `[Advanced]`

## What are CRDs?

CRDs let you **extend Kubernetes with your own resource types**. Instead of only working with built-in resources (Pods, Services, Deployments), you can create custom ones.

```bash
# Built-in resources:
kubectl get pods
kubectl get services

# Custom resources (after CRD is installed):
kubectl get certificates        # cert-manager CRD
kubectl get virtualservices     # Istio CRD
kubectl get applications        # ArgoCD CRD
```

Many tools (Istio, ArgoCD, cert-manager, Prometheus Operator) work by installing CRDs.

---

## How It Works

```
1. You define a CRD (schema for your custom resource)
2. Kubernetes now accepts objects of that kind
3. A Controller/Operator watches for those objects and acts on them
```

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  You create  │────►│ K8s API now  │────►│  Controller  │
│  a CRD       │     │ knows about  │     │  watches &   │
│              │     │ "MyApp" kind │     │  reconciles  │
└──────────────┘     └──────────────┘     └──────────────┘
```

---

## Creating a CRD

Let's create a custom `Website` resource:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: websites.mycompany.io
spec:
  group: mycompany.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["image", "replicas"]
            properties:
              image:
                type: string
              replicas:
                type: integer
                minimum: 1
                maximum: 10
              hostname:
                type: string
          status:
            type: object
            properties:
              ready:
                type: boolean
              url:
                type: string
    subresources:
      status: {}
    additionalPrinterColumns:
    - name: Replicas
      type: integer
      jsonPath: .spec.replicas
    - name: Ready
      type: boolean
      jsonPath: .status.ready
  scope: Namespaced
  names:
    plural: websites
    singular: website
    kind: Website
    shortNames:
    - ws
```

```bash
kubectl apply -f website-crd.yaml

# Now K8s knows about "Website" resources
kubectl get crd websites.mycompany.io
```

---

## Using Your Custom Resource

```yaml
apiVersion: mycompany.io/v1
kind: Website
metadata:
  name: my-blog
  namespace: default
spec:
  image: nginx:1.25
  replicas: 3
  hostname: blog.example.com
```

```bash
kubectl apply -f my-blog.yaml
kubectl get websites           # or: kubectl get ws
kubectl describe website my-blog
kubectl delete website my-blog
```

---

## The Controller Pattern

A CRD alone just stores data. You need a **controller** (operator) to act on it.

The controller loop:

```
1. Watch for Website objects (create/update/delete)
2. For each Website, create:
   - A Deployment (with spec.image and spec.replicas)
   - A Service
   - An Ingress (with spec.hostname)
3. Update the Website's status field
4. Repeat forever
```

### Simple Controller (conceptual)

```python
# Pseudo-code for a Website controller
while True:
    websites = k8s.list("Website")
    for site in websites:
        # Desired state
        desired_deployment = make_deployment(site.spec.image, site.spec.replicas)
        desired_service = make_service(site.metadata.name)
        desired_ingress = make_ingress(site.spec.hostname)
        
        # Reconcile (create or update)
        k8s.apply(desired_deployment)
        k8s.apply(desired_service)
        k8s.apply(desired_ingress)
        
        # Update status
        site.status.ready = all_pods_ready(site)
        site.status.url = f"https://{site.spec.hostname}"
        k8s.update_status(site)
    
    sleep(30)
```

---

## Building Operators (Real Tools)

| Framework | Language | Complexity |
|-----------|----------|-----------|
| **Kubebuilder** | Go | Production-grade, official |
| **Operator SDK** | Go, Ansible, Helm | Red Hat backed |
| **Kopf** | Python | Simple, quick prototyping |
| **Metacontroller** | Any (webhooks) | Lowest barrier |

### Quick Example with Kopf (Python)

```python
import kopf
import kubernetes

@kopf.on.create('mycompany.io', 'v1', 'websites')
def create_website(spec, name, namespace, **kwargs):
    api = kubernetes.client.AppsV1Api()
    
    # Create Deployment
    deployment = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": name},
        "spec": {
            "replicas": spec["replicas"],
            "selector": {"matchLabels": {"app": name}},
            "template": {
                "metadata": {"labels": {"app": name}},
                "spec": {
                    "containers": [{
                        "name": "web",
                        "image": spec["image"],
                        "ports": [{"containerPort": 80}]
                    }]
                }
            }
        }
    }
    api.create_namespaced_deployment(namespace, deployment)
    return {"ready": True, "url": f"https://{spec.get('hostname', name)}"}

@kopf.on.delete('mycompany.io', 'v1', 'websites')
def delete_website(name, namespace, **kwargs):
    api = kubernetes.client.AppsV1Api()
    api.delete_namespaced_deployment(name, namespace)
```

---

## Real-World CRDs You've Already Used

| Tool | CRDs It Installs |
|------|-----------------|
| **cert-manager** | Certificate, Issuer, ClusterIssuer |
| **ArgoCD** | Application, AppProject |
| **Istio** | VirtualService, DestinationRule, Gateway |
| **Prometheus** | ServiceMonitor, PrometheusRule, AlertmanagerConfig |
| **External Secrets** | ExternalSecret, SecretStore |

```bash
# See all CRDs in your cluster
kubectl get crd

# See CRDs from a specific group
kubectl get crd | grep istio
```

---

## Validation & Versioning

### Schema Validation

```yaml
schema:
  openAPIV3Schema:
    type: object
    properties:
      spec:
        type: object
        required: ["image"]
        properties:
          image:
            type: string
            pattern: "^[a-z0-9/:.+-]+$"
          replicas:
            type: integer
            minimum: 1
            maximum: 100
```

Kubernetes rejects invalid resources at admission time.

### Multiple Versions

```yaml
versions:
- name: v1
  served: true
  storage: true
- name: v2
  served: true
  storage: false
```

---

## Exercises

1. Create a CRD called `Backup` with fields: `database` (string), `schedule` (string), `retention` (integer).
2. Create a few `Backup` custom resources. List them with `kubectl get backups`.
3. Add a custom printer column to show the schedule.
4. (Stretch) Write a simple Python controller with Kopf that logs when a Backup is created.

---

[← Module 13: Service Mesh](../13-service-mesh/README.md) | [Back to Start →](../README.md)
