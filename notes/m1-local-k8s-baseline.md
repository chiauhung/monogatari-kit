# M1 — Local k8s baseline

**Goal (per [PRD §9](../docs/PRD.md#9-process--learning-plan)):** Docker Desktop k8s up; Postgres (CNPG) + Redis + MinIO running in cluster; can `kubectl exec` into each.

**Status:** ✅ All services up. Quiz pending.

---

## Step 0 — Wrong-cluster footgun (before we even started)

First `kubectl config current-context` returned `gke_data-sandbox-warehouse_...`. Had we not checked, the first `kubectl apply` would have landed CRDs on a **real GKE cluster**. No "are you sure?" prompt — k8s just goes wherever the current context points.

**Lesson:** check context before apply. Always.

**Habit adopted for this project:** every `kubectl` invocation in commits and scripts passes `--context docker-desktop` explicitly, so even if global context drifts, we land in the right place.

After enabling Docker Desktop's built-in Kubernetes via the GUI settings, a `docker-desktop` context appeared. Switched, verified: 1 control-plane node, v1.32.2, client=server (no skew).

## Step 1 — Namespace strategy

Picked **per-component namespacing** over single-namespace:

- `vn-data` — Postgres
- `vn-cache` — Redis
- `vn-storage` — MinIO
- `vn-app` — Next.js app (created now, populated in M2)
- `cnpg-system` — auto-created by CNPG operator install

**Why per-component over single:** real-prod pattern, forces cross-namespace networking practice (FQDN like `vn-postgres-rw.vn-data.svc.cluster.local`). Slightly more `-n` typing, worth it for FDE training.

## Step 2 — CloudNativePG operator install

Pinned to **v1.29.0** (latest stable at time of install). Discoverable via:

```bash
curl -s https://api.github.com/repos/cloudnative-pg/cloudnative-pg/releases/latest
```

Applied with server-side apply (CRDs are large enough that client-side apply hits annotation size limits):

```bash
kubectl --context docker-desktop apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-1.29.0.yaml
```

This creates ~25 resources: 10 CRDs (the new vocabulary — `clusters.postgresql.cnpg.io` and friends), RBAC, the operator deployment, a webhook service, and admission webhook configs.

### Surprise: webhook race condition

After `kubectl rollout status deploy/cnpg-controller-manager` said "deployment available," our first attempt to apply a `Cluster` CRD failed:

```
failed calling webhook "mcluster.cnpg.io":
  dial tcp 10.100.152.222:443: connect: connection refused
```

**What happened:** "Deployment ready" only means the pod started. CNPG's webhook server (inside the pod) takes a few more seconds to bind to its TLS port. We applied too soon, k8s couldn't reach the webhook for validation, apply rejected.

**Fixes for scripts:**
- Retry-with-backoff on the Cluster apply
- Or `kubectl wait --for=condition=Available --timeout=60s deploy/cnpg-controller-manager` followed by a 5-10s sleep
- Or check `kubectl get endpoints -n cnpg-system cnpg-webhook-service` has an address before applying

**FDE muscle:** "operator pod ready" ≠ "operator functionally ready." Webhook endpoint readiness is the real gate.

## Step 3 — Postgres Cluster CRD

The whole CRD, in 10 lines:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: vn-postgres
  namespace: vn-data
spec:
  instances: 1
  storage:
    size: 5Gi
  bootstrap:
    initdb:
      database: vn_app
      owner: vn_app
      secret:
        name: vn-postgres-app-user
```

Plus a separate `Secret` for the app user (basic-auth type, username + password).

### What the operator generated

Predicted vs actual — every prediction held:

| Resource | Predicted | Actual |
|---|---|---|
| Pod | `vn-postgres-1` | ✅ `vn-postgres-1` Running |
| PVC | 5Gi, named `vn-postgres-1` | ✅ Bound, 5Gi |
| Services | `vn-postgres-rw` (writes), `-ro` (reads), `-r` (any) | ✅ all 3 |
| StatefulSet | `vn-postgres` | ✅ |

### Why 3 services not 1

Even with `instances: 1`, CNPG creates 3 services:
- `-rw` — always routes to current primary (apps point here for writes)
- `-ro` — routes to replicas; falls back to primary if alone
- `-r` — any instance

**Rule for app config:** writes → `-rw`, reads → `-ro`. Two DSNs in env. When scale goes from 1 → 3 instances later, no app refactor needed.

### Reconciliation has phases

Watching `kubectl get all -n vn-data` immediately after applying the Cluster CRD showed:

```
7s:    services (instant) + initdb Job (running) + PVC (Pending)
79s:   Pod vn-postgres-1 Running, PVC Bound, Cluster status healthy
```

The operator creates resources in a careful order — services first (cheap, instant), then storage claim, then bootstrap Job (`initdb` on the fresh PVC), then promotes to real StatefulSet pod. If reconciliation stalls, the phase visible in `get all` tells you where to look.

### Smoke test

```bash
kubectl --context docker-desktop -n vn-data exec vn-postgres-1 -- psql -U postgres -c '\l'
```

Shows 4 databases: `postgres` (default), `template0`, `template1`, **`vn_app` owned by `vn_app`** ← what we asked for in the bootstrap block.

Roles: `postgres` (superuser), `streaming_replica` (CNPG-internal for replication), `vn_app`.

Postgres version: **18.3** on aarch64-linux (M-series Mac).

## Step 4 — Redis (StatefulSet, no operator)

Skipped using a Redis operator. Reason: for our use case (BullMQ job queue, no business data lives in Redis itself), single-replica + AOF persistence is plenty. An operator would add sentinel/cluster mode complexity we don't need.

**Rule of thumb:** use an operator when day-2 ops (failover, backup, upgrade) matter. For dev/MVP with simple workloads, raw `StatefulSet` is shorter than installing+learning an operator.

### Manifests (4 files)

- `secret.yaml` — Redis auth password
- `configmap.yaml` — `redis.conf` (AOF enabled, 256mb maxmemory, LRU eviction)
- `statefulset.yaml` — 1 replica, `redis:8.6.3-alpine`, mounts configmap + PVC
- `service.yaml` — headless service (`clusterIP: None`)

### New k8s concepts that surfaced here

Postgres had everything handled by CNPG. Going raw forced writing these by hand:

| Concept | Why it appeared |
|---|---|
| `ConfigMap` | Need to mount `redis.conf` into the pod; non-secret config blob |
| `volumeClaimTemplates` | StatefulSet's way to auto-create one PVC per pod ordinal |
| `readinessProbe` + `livenessProbe` | Wrote them ourselves (CNPG generated for Postgres) |
| Headless service (`clusterIP: None`) | Canonical pairing with StatefulSet for stable per-pod DNS |
| Wrapper command (`sh -c '...$ENV_VAR...'`) | To pass password from Secret into `--requirepass` flag at runtime, not bake into ConfigMap |

### Naming gotcha (vs CNPG)

**Plain StatefulSets number pods starting from 0**, not 1. CNPG starts from 1 (operator opinion).

- Postgres pod: `vn-postgres-1`
- Redis pod: `vn-redis-0` ← not `vn-redis`

And the auto-generated PVC follows the template name:

```
<volumeClaimTemplate.name>-<statefulset.name>-<ordinal>
        data            -    vn-redis       -    0     →  data-vn-redis-0
```

### Smoke test

```bash
kubectl --context docker-desktop -n vn-cache exec vn-redis-0 -- \
  sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping'
# → PONG
```

Auth round-trip works. SET/GET works. AOF mode confirmed (`appendonly: yes`, `/data/appendonlydir/` exists on the PVC).

## Step 5 — MinIO (raw StatefulSet + bootstrap Job)

Same skip-the-operator reasoning as Redis: single-node MinIO is fine for dev, an operator brings distributed-mode complexity we don't need yet.

Pinned to `quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z` and `quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z` for reproducibility.

### Manifests (5 files)

- `secret.yaml` — root credentials (`rootUser` / `rootPassword`)
- `statefulset.yaml` — 1 replica, multi-port (9000 S3 API + 9001 console), HTTP health probes, 5Gi PVC
- `service.yaml` — headless, exposes **both ports** with named entries (`s3-api`, `console`)
- `bucket-bootstrap-job.yaml` — one-shot `Job` that creates `vn-characters` + `vn-uploads` buckets
- `secret.example.yaml` — committed template; real `secret.yaml` gitignored (same pattern as Postgres + Redis)

### New k8s concepts that surfaced

| Concept | Where it appeared |
|---|---|
| Multi-port container + service | MinIO exposes 9000 (S3 API) + 9001 (console); both named in container `ports:` and service `ports:` |
| HTTP probes (vs exec) | `/minio/health/ready` for readiness, `/minio/health/live` for liveness — cheaper than exec; subtle semantic difference (ready can refuse traffic when cluster degraded, live just checks process) |
| `Job` resource | Run-to-completion workload. `backoffLimit: 3`, `ttlSecondsAfterFinished: 600`, `restartPolicy: OnFailure` |
| Idempotent bootstrap | `mc mb --ignore-existing` — re-running the Job won't error if buckets already exist. **Idempotency is the #1 property of good bootstrap scripts.** |
| Cross-namespace FQDN | Job in `vn-storage` connecting via `http://vn-minio.vn-storage.svc.cluster.local:9000` — full FQDN deliberately, building the muscle for when M2's app in `vn-app` talks to MinIO |
| Race-condition handling | Job's container loops `mc alias set ... || sleep 2` until MinIO responds. Same lesson as the CNPG webhook race, but defended in script |

### Reconciliation timeline

```
0s    apply all 4 manifests
0s    StatefulSet pod (vn-minio-0) starts pulling image
0s    Bootstrap Job pod starts — immediately tries to connect
0s    PVC requested, hostpath provisioner binds it
~10-20s   pod scheduled, image pulled, MinIO process starts listening
~22s   Job's retry loop succeeds, creates buckets, exits 0
10min later   Job + pod auto-cleaned by ttlSecondsAfterFinished
```

The Job log (preserved at [`logs/m1-minio-bucket-bootstrap.log`](./logs/m1-minio-bucket-bootstrap.log)) shows ~10 retry cycles before MinIO answered — exactly as designed.

### Smoke test

```bash
kubectl --context docker-desktop -n vn-storage exec vn-minio-0 -- sh -c \
  'mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null \
   && mc ls local'
# → vn-characters/ + vn-uploads/

echo "hello" | mc pipe local/vn-uploads/test.txt
mc cat local/vn-uploads/test.txt   # → hello
mc rm local/vn-uploads/test.txt
```

All round-trip ✅. Both buckets ready for M5 (character images) and general uploads.

### Browser console via port-forward

MinIO has a UI on port 9001 — the FDE pattern to see it without changing any manifest:

```bash
kubectl --context docker-desktop -n vn-storage port-forward svc/vn-minio 9001:9001
# → tunnel: localhost:9001 ↔ vn-minio-0:9001
```

Open `http://localhost:9001`, log in with root creds, see the buckets. Tunnel exists only while the command runs. Nothing exposed to the internet.

**`kubectl port-forward` is one of the most-used FDE debugging tricks:**
- Open a UI not yet behind Ingress (MinIO console, Grafana, Argo CD)
- Connect a local DB client to in-cluster Postgres
- Test an internal API without exposing it

---

## Side-quest: persistent log strategy

Watching the bootstrap Job emit beautiful logs that would vanish in 10 minutes raised the real question: **where do logs go when pods vanish?**

### The problem

Pods log to stdout/stderr. The kubelet captures into local files on the node. **When the pod dies, those files get garbage-collected within minutes.** `kubectl logs` is just reading those local files. Restart → logs gone. Pod hop to another node → unreachable. By design — k8s does compute orchestration, not observability.

### The real pattern (deferred to M5.5)

```
Pod stdout/stderr
    ↓
kubelet writes /var/log/pods/...   (per-node, ephemeral)
    ↓
Log collector DaemonSet (Vector / Fluent Bit / Promtail)
    ↓
Durable backend (Loki / Elasticsearch / ClickHouse / Cloud Logging)
```

### Decision: defer the full stack, capture meaningful logs now

Installing Loki + Grafana + collector on a single-node Docker Desktop would cost ~500MB RAM — unnecessary cost when the only live workload is bootstrap Jobs running once.

**For now:** any Job whose output matters gets saved to `notes/logs/` before TTL fires. The repo IS the log store for milestone artifacts.

**Scheduled formally:** added **M5.5 — Observability (Loki + Grafana + Vector/Promtail collector)** to [PRD §9](../docs/PRD.md#9-process--learning-plan), between current M5 and M6. Carves out the work so it's tracked, not forgotten.

---

## Side-quest: making the repo public-safe before push

Two Secret manifests had `password: dev-only-change-me`. Technically safe (cluster is laptop-local, can't be reached externally), but committing plaintext passwords builds the wrong habit.

**Pattern adopted:** commit `*.example.yaml` templates with `<REPLACE_ME>` placeholders. Real `secret.yaml` files are gitignored. README documents the `cp ... && edit` step.

`.gitignore` rules:

```gitignore
infra/k8s/**/secret.yaml
infra/k8s/**/*-secret.yaml
!infra/k8s/**/*.example.yaml
```

Verified with `git check-ignore`: real secrets hidden, examples tracked.

For prod (M7+), these get replaced by sealed-secrets or Vault — same pattern, different secret source.

---

## What this milestone built (FDE muscles)

- **Context discipline** — never apply to the wrong cluster (Step 0)
- **Operator pattern** — CRDs as new vocabulary, operator as reconciler, predicting what gets generated (Step 3)
- **Webhook race condition** — operator readiness ≠ pod readiness (Step 2)
- **StatefulSet from scratch** — `volumeClaimTemplates`, headless services, ordinal naming (Steps 4, 5)
- **When NOT to use an operator** — raw manifests sometimes simpler (Steps 4, 5)
- **Multi-port containers** — named ports, HTTP probes (Step 5)
- **`Job` for bootstrap** — idempotency, TTL, retry loops against eventually-ready services (Step 5)
- **`kubectl port-forward`** — temporary localhost ↔ in-cluster tunnel (Step 5)
- **Cross-namespace FQDN** — `svc.cluster.local` discipline before it strictly matters (Step 5)
- **Secret hygiene** — gitignore patterns, templates, never plaintext in public history (Side-quest)
- **Log persistence** — accept ephemerality at MVP; schedule real stack at M5.5 (Side-quest)

## Related deep-dives in Obsidian

- `Learning/Deep Dives/Kubernetes Vocabulary - CRD, Operator, PVC, StatefulSet.md`

## FDE probe questions (M1 quiz)

(to be filled in with quiz answers after M1 wrap)
