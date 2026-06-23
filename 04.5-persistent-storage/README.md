# Module 4.5: Persistent Storage Deep Dive

Module 4 introduced PVs, PVCs, and StorageClasses. This module goes deeper — you'll understand *when* to use each option, deploy a real database with durable storage, and troubleshoot the most common storage issues.

---

## Why Storage Matters

Containers are ephemeral. When a pod restarts, its filesystem resets. For anything that needs to survive restarts — databases, uploads, logs — you need persistent storage.

```
Without PV:
  Pod dies → data gone forever ☠️

With PV:
  Pod dies → PVC keeps data → new Pod mounts same PVC → data intact ✓
```

---

## The Storage Stack

```
┌─────────────────────────────────────────────────────────┐
│                     YOUR POD                             │
│   volumeMounts:                                         │
│     - mountPath: /var/lib/postgresql/data                │
│       name: db-storage                                  │
└──────────────────────────┬──────────────────────────────┘
                           │ references
┌──────────────────────────▼──────────────────────────────┐
│              PersistentVolumeClaim (PVC)                  │
│   "I need 10Gi of ReadWriteOnce storage"                │
│   storageClassName: standard                            │
└──────────────────────────┬──────────────────────────────┘
                           │ binds to
┌──────────────────────────▼──────────────────────────────┐
│              PersistentVolume (PV)                        │
│   Capacity: 10Gi                                        │
│   Type: AWS EBS / GCP PD / local disk / NFS             │
└──────────────────────────┬──────────────────────────────┘
                           │ backed by
┌──────────────────────────▼──────────────────────────────┐
│              Actual Storage                               │
│   Physical disk, network drive, cloud volume             │
└─────────────────────────────────────────────────────────┘
```

**Think of it like renting:**
- **StorageClass** = the type of apartment (luxury, standard, budget)
- **PVC** = your lease application ("I need a 2-bedroom")
- **PV** = the actual apartment assigned to you
- **Pod** = you living in it

---

## PV vs PVC vs StorageClass

| Resource | Created By | Purpose |
|----------|-----------|---------|
| **PersistentVolume (PV)** | Admin (or dynamically by StorageClass) | The actual storage resource |
| **PersistentVolumeClaim (PVC)** | Developer | A request for storage |
| **StorageClass** | Admin | Template for dynamically creating PVs |

### Static Provisioning (manual)

Admin creates PVs ahead of time. Developer creates PVCs that bind to available PVs.

```
Admin creates:  PV-1 (10Gi), PV-2 (20Gi), PV-3 (50Gi)
Dev requests:   PVC "give me 15Gi" → binds to PV-2 (smallest fit)
```

### Dynamic Provisioning (automatic)

StorageClass creates PVs on-demand when a PVC is created. This is the modern approach.

```
Dev creates PVC with storageClassName: fast-ssd
→ StorageClass provisions a new PV automatically
→ PVC binds to new PV
→ Pod mounts PVC
```

---

## Access Modes Explained

| Mode | Short | What It Means | Use Case |
|------|-------|---------------|----------|
| **ReadWriteOnce** | RWO | One node can mount read-write | Databases, single-writer apps |
| **ReadOnlyMany** | ROX | Many nodes can mount read-only | Shared config, static assets |
| **ReadWriteMany** | RWX | Many nodes can mount read-write | Shared uploads, CMS content |
| **ReadWriteOncePod** | RWOP | Exactly one pod can mount (K8s 1.27+) | Strict single-writer guarantee |

### Which mode do you need?

```
Single database pod? → RWO (most common)
Multiple pods reading same data? → ROX
Multiple pods writing to shared filesystem? → RWX (needs NFS or similar)
```

**Important:** Cloud block storage (EBS, GCP PD) only supports RWO. For RWX you need NFS, EFS, or similar shared filesystem.

---

## Practical Example 1: Local Storage (Minikube/kind)

For learning and dev, use `hostPath` or Minikube's built-in `standard` StorageClass.

### Using Minikube's default StorageClass

```bash
# Minikube already has a StorageClass called "standard"
kubectl get storageclass
# NAME                 PROVISIONER                RECLAIMPOLICY
# standard (default)   k8s.io/minikube-hostpath   Delete
```

Just create a PVC — it gets a PV automatically:

```yaml
# pvc-demo.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-storage
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f pvc-demo.yaml
kubectl get pvc
# NAME           STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS
# demo-storage   Bound    pvc-abc123   1Gi        RWO            standard
```

### Manual PV with hostPath (for understanding)

```yaml
# pv-local.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/data
    type: DirectoryOrCreate
---
# pvc-local.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-pvc
spec:
  storageClassName: manual
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 3Gi
```

```bash
kubectl apply -f pv-local.yaml
kubectl apply -f pvc-local.yaml
kubectl get pv,pvc
```

⚠️ `hostPath` is for dev only — data is tied to a specific node and lost if the node dies.

---

## Practical Example 2: AWS EBS

For production on AWS EKS:

```yaml
# storageclass-ebs.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```yaml
# pvc-ebs.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-storage
spec:
  storageClassName: fast-ssd
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

**Key settings:**
- `WaitForFirstConsumer` — don't create the volume until a pod needs it (ensures volume is in the right AZ)
- `allowVolumeExpansion: true` — lets you resize PVCs later
- `encrypted: "true"` — encrypts the EBS volume

---

## Practical Example 3: NFS (ReadWriteMany)

When multiple pods need to write to shared storage:

```yaml
# storageclass-nfs.yaml (requires NFS CSI driver installed)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-shared
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs-server.example.com
  share: /exported/path
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
- nfsvers=4.1
```

```yaml
# pvc-nfs.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-uploads
spec:
  storageClassName: nfs-shared
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
```

Now multiple pods can mount `shared-uploads` and all read/write the same files.

---

## Storage Comparison Table

| Storage Type | Access Modes | Performance | Best For | Provider Examples |
|-------------|-------------|-------------|----------|-------------------|
| **Block (SSD)** | RWO | High IOPS | Databases | AWS EBS, GCP PD, Azure Disk |
| **File (NFS)** | RWX | Moderate | Shared files, CMS | AWS EFS, GCP Filestore, NFS |
| **Object** | N/A (use SDK) | Varies | Media, backups | S3, GCS, MinIO |
| **Local** | RWO | Fastest | Caches, temp storage | hostPath, local PV |

---

## Hands-on Lab: PostgreSQL with Persistent Storage

Let's deploy PostgreSQL properly — data survives pod restarts and deletions.

### Step 1: Create the namespace and secret

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: storage-lab
---
# postgres-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-creds
  namespace: storage-lab
type: Opaque
stringData:
  POSTGRES_USER: labuser
  POSTGRES_PASSWORD: LabPass2024!
  POSTGRES_DB: storagelab
```

### Step 2: Deploy PostgreSQL as a StatefulSet

```yaml
# postgres-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: storage-lab
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        envFrom:
        - secretRef:
            name: postgres-creds
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
          subPath: pgdata
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "labuser", "-d", "storagelab"]
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: storage-lab
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
  clusterIP: None
```

**Why `subPath: pgdata`?** PostgreSQL requires its data directory to be empty on init. The `subPath` creates a subdirectory inside the volume, avoiding issues with lost+found or other filesystem artifacts.

### Step 3: Deploy and write data

```bash
# Apply everything
kubectl apply -f namespace.yaml
kubectl apply -f postgres-secret.yaml
kubectl apply -f postgres-statefulset.yaml

# Wait for postgres to be ready
kubectl wait --for=condition=ready pod/postgres-0 -n storage-lab --timeout=60s

# Connect and create data
kubectl exec -it postgres-0 -n storage-lab -- psql -U labuser -d storagelab -c "
  CREATE TABLE experiments (id SERIAL PRIMARY KEY, name TEXT, created_at TIMESTAMP DEFAULT NOW());
  INSERT INTO experiments (name) VALUES ('persistence test 1');
  INSERT INTO experiments (name) VALUES ('persistence test 2');
  SELECT * FROM experiments;
"
```

### Step 4: Prove data survives pod deletion

```bash
# Delete the pod (StatefulSet will recreate it)
kubectl delete pod postgres-0 -n storage-lab

# Wait for new pod
kubectl wait --for=condition=ready pod/postgres-0 -n storage-lab --timeout=60s

# Check data is still there!
kubectl exec -it postgres-0 -n storage-lab -- psql -U labuser -d storagelab -c "SELECT * FROM experiments;"
#  id |        name         |         created_at
# ----+---------------------+----------------------------
#   1 | persistence test 1  | 2024-01-15 10:30:00.000000
#   2 | persistence test 2  | 2024-01-15 10:30:00.000000
```

**Data survived!** The PVC kept the data even though the pod was deleted and recreated.

### Step 5: Verify PVC status

```bash
kubectl get pvc -n storage-lab
# NAME                     STATUS   VOLUME         CAPACITY   ACCESS MODES
# postgres-data-postgres-0 Bound    pvc-abc123     2Gi        RWO

kubectl describe pvc postgres-data-postgres-0 -n storage-lab
```

---

## Volume Expansion (Resizing)

If your StorageClass has `allowVolumeExpansion: true`:

```bash
# Edit the PVC to request more space
kubectl patch pvc postgres-data-postgres-0 -n storage-lab \
  -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'

# Check status — may need pod restart for filesystem resize
kubectl get pvc postgres-data-postgres-0 -n storage-lab
```

⚠️ You can only increase size, never decrease.

---

## Reclaim Policies in Practice

| Policy | When PVC Deleted | Use Case |
|--------|-----------------|----------|
| **Delete** | PV and data destroyed | Dev/test (default for dynamic provisioning) |
| **Retain** | PV kept, data preserved, manual cleanup needed | Production databases |

For production databases, always use `Retain`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: production-db
provisioner: ebs.csi.aws.com
reclaimPolicy: Retain     # ← data survives PVC deletion
parameters:
  type: gp3
```

---

## Troubleshooting Storage Issues

### PVC Stuck in Pending

```bash
$ kubectl get pvc -n storage-lab
NAME        STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
my-pvc      Pending                                      fast-ssd

$ kubectl describe pvc my-pvc -n storage-lab
Events:
  Warning  ProvisioningFailed  waiting for first consumer to be created
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| StorageClass doesn't exist | `kubectl get sc` — check name matches |
| `WaitForFirstConsumer` | PVC won't bind until a pod uses it — this is normal |
| No available PVs (static provisioning) | Create a PV that matches the PVC |
| Wrong access mode | EBS only supports RWO — can't request RWX |
| Capacity mismatch | PV must be >= PVC request |
| Zone mismatch | PV in us-east-1a, pod scheduled in us-east-1b |

### Pod Can't Mount Volume

```bash
Events:
  Warning  FailedAttachVolume  Multi-Attach error for volume "pvc-xxx"
```

**Cause:** RWO volume is already attached to another node (e.g., old pod on different node hasn't released it yet).

**Fix:** Wait for old pod to terminate, or delete the stuck pod forcing volume release.

### Data Permission Issues

```bash
# Pod logs show: "Permission denied" writing to mounted volume
```

**Fix:** Use `securityContext` to set the right user/group:

```yaml
spec:
  securityContext:
    fsGroup: 999       # PostgreSQL GID
  containers:
  - name: postgres
    image: postgres:16
    securityContext:
      runAsUser: 999
```

---

## Cleanup

```bash
kubectl delete namespace storage-lab
# ⚠️ This deletes the PVCs. With reclaimPolicy: Delete, PVs are also destroyed.
# With Retain, PVs remain and need manual cleanup:
kubectl get pv
kubectl delete pv <pv-name>
```

---

## Key Takeaways

| Situation | Use |
|-----------|-----|
| Temporary cache/scratch space | `emptyDir` |
| Single database, survives restarts | StatefulSet + PVC (RWO) |
| Multiple pods reading shared data | PVC with ROX |
| Multiple pods writing shared data | NFS/EFS + PVC with RWX |
| Local dev/learning | Minikube default StorageClass |
| Production cloud | Cloud CSI driver + StorageClass |

---

## Exercises

1. **Basic persistence:** Create a PVC, mount it in a pod, write a file. Delete the pod. Mount the same PVC in a new pod — verify the file is there.

2. **StatefulSet storage:** Deploy a 3-replica StatefulSet with `volumeClaimTemplates`. Verify each pod gets its OWN PVC (check with `kubectl get pvc`).

3. **Reclaim policies:** Create a PV with `Retain` policy. Bind it with a PVC. Delete the PVC. Observe that the PV stays in `Released` state.

4. **Break and fix:** Create a PVC requesting 5Gi with `storageClassName: nonexistent`. Watch it stay Pending. Fix it by changing to a valid StorageClass.

5. **Challenge:** Deploy the Module 6 notes-api with PostgreSQL on persistent storage. Insert data, delete the postgres pod, verify data survives.

---

[← Module 4: Networking & Storage](../04-networking-storage/README.md) | [Module 5: Configuration & Secrets →](../05-configuration/README.md)
