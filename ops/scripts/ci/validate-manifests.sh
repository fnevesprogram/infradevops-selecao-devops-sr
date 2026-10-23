#!/usr/bin/env bash
# Valida overlays Kustomize com kubectl (sem binário kustomize).
# Uso: ./ops/scripts/ci/validate-manifests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
require_cmd kubectl

OUT_DIR="$(mktemp -d)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${OUT_DIR}" "${WORKDIR}"' EXIT

log "Build base"
kubectl kustomize "${ROOT_DIR}/k8s/base" > "${OUT_DIR}/base.yaml"

log "Build overlay local"
kubectl kustomize "${ROOT_DIR}/k8s/overlays/local" > "${OUT_DIR}/local.yaml"

log "Build overlay gcp (placeholders de CI)"
cp -R "${ROOT_DIR}/k8s" "${WORKDIR}/k8s"
OVERLAY="${WORKDIR}/k8s/overlays/gcp"

for f in kustomization.yaml clustersecretstore.yaml externalsecret.yaml; do
  replace_gcp_placeholders \
    "${OVERLAY}/${f}" \
    "ci-validation-project" \
    "dev-comments-db-url" \
    "example.com/comments-api" \
    "ci" \
    "us-central1" \
    "dev-comments-gke"
done

kubectl kustomize "${OVERLAY}" > "${OUT_DIR}/gcp.yaml"

log "Checagens mínimas"
for f in base.yaml local.yaml gcp.yaml; do
  test -s "${OUT_DIR}/${f}" || die "Arquivo vazio: ${f}"
done

for kind in Deployment PodDisruptionBudget ExternalSecret HorizontalPodAutoscaler; do
  grep -q "kind: ${kind}" "${OUT_DIR}/gcp.yaml" || die "Overlay gcp sem ${kind}"
done
grep -q 'DATABASE_SSL: "true"' "${OUT_DIR}/gcp.yaml" || die "Overlay gcp sem DATABASE_SSL"

log "Manifests OK (base, local, gcp)"
