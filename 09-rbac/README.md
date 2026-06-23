# Module 9: RBAC — Role-Based Access Control `[Intermediate]`

## What is RBAC?

RBAC controls **who** can do **what** on **which resources** in your cluster.

```
WHO (Subject)     +  WHAT (Verbs)      +  WHICH (Resources)   = Permission
─────────────────────────────────────────────────────────────────────────
User "pravin"        get, list, watch      pods                  can view pods
ServiceAccount       create, delete        deployments           can manage deployments
Group "dev-team"     get                   secrets               can read secrets
```

---

## RBAC Building Blocks

```
┌──────────────┐         ┌──────────────┐
│    Role      │         │  ClusterRole │
│ (namespace)  │         │ (cluster-wide)│
└──────┬───────┘         └──────┬───────┘
       │ bound via               │ bound via
       ▼                         ▼
┌──────────────┐         ┌──────────────────┐
│ RoleBinding  │         │ClusterRoleBinding│
│ (namespace)  │         │ (cluster-wide)    │
└──────────────┘         └──────────────────┘
       │                         │
       ▼                         ▼
   Subject                    Subject
(User/Group/SA)           (User/Group/SA)
```

| Object | Scope | What It Does |
|--------|-------|-------------|
| **Role** | Namespace | Defines permissions within ONE namespace |
| **ClusterRole** | Cluster | Defines permissions across ALL namespaces |
| **RoleBinding** | Namespace | Grants a Role to a subject in ONE namespace |
| **ClusterRoleBinding** | Cluster | Grants a ClusterRole across ALL namespaces |

---

## Subjects — WHO gets access

| Subject Type | Description |
|-------------|-------------|
| **User** | Human user (managed externally — certs, OIDC, etc.) |
| **Group** | A group of users |
| **ServiceAccount** | Identity for pods/processes running in the cluster |

---

## Step-by-Step: Namespace-scoped Access

### 1. Create a ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dev-sa
  namespace: dev
```

### 2. Create a Role (what can be done)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
- apiGroups: [""]              # core API group
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
```

### 3. Create a RoleBinding (connect Role to Subject)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-pod-reader
  namespace: dev
subjects:
- kind: ServiceAccount
  name: dev-sa
  namespace: dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Now `dev-sa` can only read pods and services in the `dev` namespace.

---

## Cluster-wide Access

### ClusterRole

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: namespace-reader
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
```

### ClusterRoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: global-namespace-reader
subjects:
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: namespace-reader
  apiGroup: rbac.authorization.k8s.io
```

---

## Common Verbs

| Verb | Action |
|------|--------|
| `get` | Read a single resource |
| `list` | List all resources |
| `watch` | Stream changes |
| `create` | Create new resources |
| `update` | Modify existing resources |
| `patch` | Partially modify resources |
| `delete` | Delete resources |
| `deletecollection` | Delete multiple resources |

---

## Common API Groups

| Group | Resources |
|-------|-----------|
| `""` (core) | pods, services, configmaps, secrets, namespaces, nodes, pvc |
| `apps` | deployments, statefulsets, daemonsets, replicasets |
| `batch` | jobs, cronjobs |
| `networking.k8s.io` | ingresses, networkpolicies |
| `rbac.authorization.k8s.io` | roles, rolebindings, clusterroles |
| `autoscaling` | horizontalpodautoscalers |

---

## Practical Example: Dev Team Setup

```yaml
# Developer role — can manage apps but NOT secrets or RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: staging
rules:
- apiGroups: ["", "apps"]
  resources: ["pods", "deployments", "services", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
- apiGroups: [""]
  resources: ["pods/log", "pods/exec"]
  verbs: ["get", "create"]
# Note: NO access to secrets, no RBAC modification
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-team-binding
  namespace: staging
subjects:
- kind: Group
  name: dev-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

---

## Built-in ClusterRoles

K8s comes with default ClusterRoles:

| ClusterRole | Permissions |
|-------------|------------|
| `cluster-admin` | Full access to everything (god mode) |
| `admin` | Full access within a namespace |
| `edit` | Read/write most resources (no RBAC) |
| `view` | Read-only access |

```bash
# Give a user admin access to a namespace
kubectl create rolebinding pravin-admin \
  --clusterrole=admin \
  --user=pravin \
  --namespace=dev
```

---

## Testing Permissions

```bash
# Check if YOU can do something
kubectl auth can-i create deployments --namespace=dev

# Check if a ServiceAccount can do something
kubectl auth can-i get pods --as=system:serviceaccount:dev:dev-sa -n dev

# List all permissions for a user
kubectl auth can-i --list --as=pravin
```

---

## Useful Commands

```bash
kubectl get roles,rolebindings -n dev
kubectl get clusterroles,clusterrolebindings
kubectl describe role pod-reader -n dev
kubectl create serviceaccount my-sa -n dev
```

---

## Exercises

1. Create a ServiceAccount `app-deployer` that can only create/update Deployments and Services in namespace `staging`.
2. Test with `kubectl auth can-i` to verify it can't read secrets.
3. Use the built-in `view` ClusterRole to give read-only access to a user across one namespace.
4. Create a ClusterRole that can read nodes and namespaces, bind it with a ClusterRoleBinding.

---

[← Module 8: HPA](../08-hpa/README.md) | [Module 10: Taints & Affinity →](../10-scheduling/README.md)
