# infra/k8s — Local k8s baseline (M1)

Manifests for running Postgres / Redis / MinIO inside Docker Desktop's built-in Kubernetes.

## Pinned versions

| Component | Version | Source |
|---|---|---|
| CloudNativePG operator | v1.29.0 | https://github.com/cloudnative-pg/cloudnative-pg/releases/tag/v1.29.0 |
| Redis | TBD | TBD |
| MinIO | TBD | TBD |

## Namespaces

- `vn-data` — Postgres (CNPG-managed)
- `vn-cache` — Redis
- `vn-storage` — MinIO
- `vn-app` — Next.js app (added in M2)
- `cnpg-system` — CNPG operator itself (created by the operator install)

## Apply order

```bash
# 1. CNPG operator (cluster-wide, one-time)
kubectl --context docker-desktop apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-1.29.0.yaml

# 2. Wait for operator
kubectl --context docker-desktop -n cnpg-system rollout status deploy/cnpg-controller-manager

# 3. Postgres cluster
kubectl --context docker-desktop apply -f postgres/cluster.yaml

# 4. (later) Redis
# 5. (later) MinIO
```

## Safety convention

Every `kubectl` invocation in this repo passes `--context docker-desktop` explicitly so we never apply to the wrong cluster.

## Secrets workflow

Real Secret manifests are **gitignored**. Only `*.example.yaml` templates are committed.

After cloning, copy each template and fill in a real password:

```bash
cp infra/k8s/postgres/app-user-secret.example.yaml infra/k8s/postgres/app-user-secret.yaml
cp infra/k8s/redis/secret.example.yaml infra/k8s/redis/secret.yaml
# edit each file, replace <REPLACE_ME> with a real password
```

For local dev, any non-empty password works (the cluster is only reachable from your laptop). For prod (M7+), these get replaced by sealed-secrets / Vault.

## Pause/resume during breaks

Quick scale-down (workloads off, control plane still running, PVCs preserved):

```bash
./scripts/cluster-down.sh    # scale Postgres + Redis + MinIO to 0
./scripts/cluster-up.sh      # restore them
```

For a longer break (frees the k8s control plane ~600MB extra RAM), use Docker Desktop's Settings → Kubernetes → uncheck "Enable Kubernetes" instead. Re-enable when you come back.
