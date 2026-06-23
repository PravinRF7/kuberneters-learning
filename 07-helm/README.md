# Module 7: Helm — Package Manager for Kubernetes `[Intermediate]`

## What is Helm?

Helm is the **package manager for Kubernetes** — think `apt` for Ubuntu or `npm` for Node.js, but for K8s manifests.

Instead of managing 10+ YAML files per app, you package them into a **Chart** with configurable values.

```
Without Helm:                    With Helm:
├── deployment.yaml              helm install my-app ./chart \
├── service.yaml                   --set replicas=3 \
├── configmap.yaml                 --set image.tag=v2
├── secret.yaml
├── ingress.yaml
├── hpa.yaml
└── ... (copy-paste for each env)
```

---

## Key Concepts

| Term | What It Is |
|------|-----------|
| **Chart** | A package of K8s manifests (templates + values) |
| **Release** | A deployed instance of a chart |
| **Repository** | A place to store and share charts |
| **Values** | Configuration that customizes a chart |

---

## Installing Helm

```bash
# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

---

## Using Existing Charts

### Add a repository

```bash
# Add popular repos
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Search for charts
helm search repo nginx
helm search repo postgresql
```

### Install a chart

```bash
# Install nginx
helm install my-nginx bitnami/nginx

# Install with custom values
helm install my-db bitnami/postgresql \
  --set auth.postgresPassword=mypassword \
  --set primary.persistence.size=5Gi \
  --namespace databases --create-namespace

# Install from a values file
helm install my-db bitnami/postgresql -f my-values.yaml
```

### Manage releases

```bash
# List installed releases
helm list
helm list -A              # all namespaces

# Check status
helm status my-nginx

# Upgrade (change values or chart version)
helm upgrade my-nginx bitnami/nginx --set replicaCount=3

# Rollback
helm rollback my-nginx 1   # revision number

# Uninstall
helm uninstall my-nginx
```

---

## Creating Your Own Chart

```bash
helm create my-app
```

This generates:

```
my-app/
├── Chart.yaml          # Chart metadata (name, version, description)
├── values.yaml         # Default configuration values
├── templates/          # K8s manifest templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   ├── _helpers.tpl    # Template helper functions
│   └── NOTES.txt       # Post-install instructions
└── charts/             # Dependencies (sub-charts)
```

### `Chart.yaml`

```yaml
apiVersion: v2
name: my-app
description: A notes API application
type: application
version: 0.1.0        # chart version
appVersion: "1.0.0"   # app version
```

### `values.yaml` — Default values

```yaml
replicaCount: 3

image:
  repository: notes-api
  tag: "v1"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  host: notes.local

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi

postgresql:
  enabled: true
  auth:
    username: notesadmin
    password: ""    # set at install time
    database: notesdb
```

### `templates/deployment.yaml` — Templated manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 3000
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
```

### Template Syntax Basics

```yaml
{{ .Values.replicaCount }}           # access values.yaml
{{ .Release.Name }}                   # release name
{{ .Chart.Name }}                     # chart name
{{ include "my-app.fullname" . }}     # named template

# Conditionals
{{- if .Values.ingress.enabled }}
  # ingress manifest here
{{- end }}

# Loops
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}
```

---

## Deploy Your Chart

```bash
# Dry run (see what would be generated)
helm template my-release ./my-app

# Install
helm install my-release ./my-app \
  --set postgresql.auth.password=secretpass

# Override for different environments
helm install staging ./my-app -f values-staging.yaml
helm install production ./my-app -f values-production.yaml
```

### Environment-specific values files

```yaml
# values-staging.yaml
replicaCount: 1
image:
  tag: "latest"
resources:
  requests:
    cpu: 50m
    memory: 64Mi

# values-production.yaml
replicaCount: 5
image:
  tag: "v2.1.0"
resources:
  requests:
    cpu: 500m
    memory: 256Mi
```

---

## Useful Commands

```bash
helm template my-release ./chart       # render templates locally
helm lint ./chart                       # validate chart
helm package ./chart                    # package into .tgz
helm show values bitnami/postgresql     # see a chart's default values
helm get values my-release              # see values used in a release
helm history my-release                 # see revision history
```

---

## Exercises

1. Install `bitnami/nginx` with 3 replicas using `--set`.
2. Create a Helm chart for the Notes API from Module 6. Templatize the replica count, image tag, and resource limits.
3. Create two values files (staging + production) and install the same chart twice with different configs.
4. Upgrade a release to a new image tag and then rollback.

---

[← Module 6: Working Demo](../06-demo/README.md) | [Module 8: HPA →](../08-hpa/README.md)
