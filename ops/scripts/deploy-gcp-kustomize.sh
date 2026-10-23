#!/usr/bin/env bash
# Deploy no GKE Autopilot com kubectl apply -k (Kustomize embutido).
#
# Uso:
#   PROJECT_ID=... IMAGE_URI=... IMAGE_TAG=... ./ops/scripts/deploy-gcp-kustomize.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

require_cmd kubectl
require_env PROJECT_ID IMAGE_URI IMAGE_TAG

ENVIRONMENT="${ENVIRONMENT:-dev}"
SECRET_REMOTE_KEY="${SECRET_REMOTE_KEY:-${ENVIRONMENT}-comments-db-url}"
NAMESPACE="${NAMESPACE:-comments}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

OVERLAY="${WORKDIR}/k8s/overlays/gcp"
cp -R "${ROOT_DIR}/k8s" "${WORKDIR}/k8s"

log "Preparando overlay gcp"
for f in kustomization.yaml clustersecretstore.yaml externalsecret.yaml; do
  replace_gcp_placeholders \
    "${OVERLAY}/${f}" \
    "${PROJECT_ID}" \
    "${SECRET_REMOTE_KEY}" \
    "${IMAGE_URI}" \
    "${IMAGE_TAG}"
done

log "Render kubectl kustomize"
kubectl kustomize "${OVERLAY}" > "${WORKDIR}/rendered.yaml"
grep -q "kind: Deployment" "${WORKDIR}/rendered.yaml" || die "Render sem Deployment"
grep -q "kind: PodDisruptionBudget" "${WORKDIR}/rendered.yaml" || die "Render sem PDB"

log "Apply ClusterSecretStore"
kubectl apply -f "${OVERLAY}/clustersecretstore.yaml"

log "Apply overlay (kubectl apply -k)"
kubectl apply -k "${OVERLAY}"

log "Rollout ${NAMESPACE}/comments-api"
kubectl rollout status "deployment/comments-api" -n "${NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"

log "Deploy OK (${IMAGE_URI}:${IMAGE_TAG})"
