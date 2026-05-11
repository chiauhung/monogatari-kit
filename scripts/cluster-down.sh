#!/usr/bin/env bash
# Scale all monogatari-kit workloads down to 0 replicas without disabling
# Kubernetes. PVCs, manifests, and CRDs are preserved. Use this to free up
# laptop RAM during longer breaks while keeping Docker Desktop's k8s feature
# enabled for other work.
#
# Companion: scripts/cluster-up.sh restores everything.
#
# Note: this only scales the workloads. The k8s control plane (etcd, API
# server, kubelet) still runs (~600MB RAM). If you want full RAM back, use
# Docker Desktop's Settings → Kubernetes → uncheck "Enable Kubernetes".
set -euo pipefail

CONTEXT="docker-desktop"

echo "Scaling monogatari-kit workloads to 0 in context: $CONTEXT"
echo

echo "→ Postgres (CNPG Cluster CRD)"
kubectl --context "$CONTEXT" patch cluster vn-postgres -n vn-data \
  --type=merge -p '{"spec":{"instances":0}}'

echo "→ Redis (StatefulSet)"
kubectl --context "$CONTEXT" scale statefulset vn-redis -n vn-cache --replicas=0

echo "→ MinIO (StatefulSet)"
kubectl --context "$CONTEXT" scale statefulset vn-minio -n vn-storage --replicas=0

echo
echo "Waiting for pods to terminate..."
kubectl --context "$CONTEXT" wait --for=delete pod \
  -l 'cnpg.io/cluster=vn-postgres' -n vn-data --timeout=60s 2>/dev/null || true
kubectl --context "$CONTEXT" wait --for=delete pod \
  -l 'app=vn-redis' -n vn-cache --timeout=60s 2>/dev/null || true
kubectl --context "$CONTEXT" wait --for=delete pod \
  -l 'app=vn-minio' -n vn-storage --timeout=60s 2>/dev/null || true

echo
echo "✓ All workload pods terminated. CNPG operator still running."
echo "  PVCs, CRDs, secrets all preserved. Run cluster-up.sh to restore."
