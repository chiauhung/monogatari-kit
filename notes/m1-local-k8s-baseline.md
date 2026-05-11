# M1 — Local k8s baseline

**Goal (per [PRD §9](../docs/PRD.md#9-process--learning-plan)):** Docker Desktop k8s up; Postgres (CNPG) + Redis + MinIO running in cluster; can `kubectl exec` into each.

**Status:** 🚧 In progress (Postgres ✅ · Redis ✅ · MinIO pending)

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

## Step 5 — MinIO (pending)

To be added.

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
- **StatefulSet from scratch** — `volumeClaimTemplates`, headless services, ordinal naming (Step 4)
- **When NOT to use an operator** — raw manifests sometimes simpler (Step 4 framing)
- **Secret hygiene** — gitignore patterns, templates, never plaintext in public history (Side-quest)

## Related deep-dives in Obsidian

- `Learning/Deep Dives/Kubernetes Vocabulary - CRD, Operator, PVC, StatefulSet.md`

## FDE probe questions (to attempt at M1 wrap)

(to be filled in after MinIO is up and M1 is "done")
