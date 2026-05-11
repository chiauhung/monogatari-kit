#!/usr/bin/env bash
# Bring monogatari-kit workloads back from a cluster-down.sh state.
# Restores Postgres to 1 instance and Redis + MinIO StatefulSets to 1 replica.
set -euo pipefail

CONTEXT="docker-desktop"

echo "Scaling monogatari-kit workloads back up in context: $CONTEXT"
echo

echo "→ Postgres (un-hibernate)"
kubectl --context "$CONTEXT" annotate cluster vn-postgres -n vn-data \
  cnpg.io/hibernation=off --overwrite

echo "→ Redis (StatefulSet)"
kubectl --context "$CONTEXT" scale statefulset vn-redis -n vn-cache --replicas=1

echo "→ MinIO (StatefulSet)"
kubectl --context "$CONTEXT" scale statefulset vn-minio -n vn-storage --replicas=1

echo
echo "Waiting for pods to become Ready (timeout 3 minutes)..."
kubectl --context "$CONTEXT" wait --for=condition=Ready pod \
  -l 'cnpg.io/cluster=vn-postgres' -n vn-data --timeout=180s
kubectl --context "$CONTEXT" wait --for=condition=Ready pod \
  -l 'app=vn-redis' -n vn-cache --timeout=180s
kubectl --context "$CONTEXT" wait --for=condition=Ready pod \
  -l 'app=vn-minio' -n vn-storage --timeout=180s

echo
echo "✓ All workloads Ready. Final state:"
kubectl --context "$CONTEXT" get pods -A | grep -E 'vn-|cnpg' || true
