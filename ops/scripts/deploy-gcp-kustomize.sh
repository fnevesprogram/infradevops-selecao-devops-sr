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
# Autopilot: provisionamento de nó + sync ESO + TLS/DB podem passar de 5m
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-10m}"
ESO_TIMEOUT="${ESO_TIMEOUT:-180s}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

dump_rollout_diagnostics() {
  log "Diagnóstico do rollout (falha)"
  kubectl get pods,deploy,hpa,pdb,externalsecret -n "${NAMESPACE}" || true
  kubectl describe externalsecret comments-api-db-secret -n "${NAMESPACE}" 2>/dev/null | tail -40 || true
  kubectl describe clustersecretstore gcp-secret-store 2>/dev/null | tail -30 || true
  kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' 2>/dev/null | tail -30 || true
  kubectl describe pods -l app.kubernetes.io/name=comments-api -n "${NAMESPACE}" 2>/dev/null | tail -80 || true
  kubectl logs -l app.kubernetes.io/name=comments-api -n "${NAMESPACE}" --tail=80 2>/dev/null || true
}

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
grep -q 'DATABASE_SSL: "true"' "${WORKDIR}/rendered.yaml" \
  || die "Overlay gcp sem DATABASE_SSL=true (necessário para Cloud SQL ENCRYPTED_ONLY)"

log "Aguardando CRDs do External Secrets Operator"
if ! kubectl get crd clustersecretstores.external-secrets.io >/dev/null 2>&1; then
  die "CRD ClusterSecretStore ausente. Rode terraform apply (módulo external_secrets) antes do CD."
fi
kubectl wait --for=condition=Established \
  crd/clustersecretstores.external-secrets.io \
  crd/externalsecrets.external-secrets.io \
  --timeout=120s

log "Apply ClusterSecretStore"
kubectl apply -f "${OVERLAY}/clustersecretstore.yaml"

log "Apply overlay (kubectl apply -k)"
kubectl apply -k "${OVERLAY}"

log "Aguardando ExternalSecret sincronizar a Secret do banco"
deadline=$((SECONDS + ${ESO_TIMEOUT%s}))
until kubectl get secret comments-api-db-secret -n "${NAMESPACE}" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    dump_rollout_diagnostics
    die "Secret comments-api-db-secret não criada a tempo. Verifique ESO / ClusterSecretStore / Secret Manager."
  fi
  sleep 5
done
# Status Ready do ExternalSecret (quando disponível)
if kubectl get externalsecret comments-api-db-secret -n "${NAMESPACE}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
  log "ExternalSecret Ready=True"
else
  log "Secret presente (aguardando condição Ready opcional)"
fi

log "Rollout ${NAMESPACE}/comments-api (timeout=${ROLLOUT_TIMEOUT})"
if ! kubectl rollout status "deployment/comments-api" -n "${NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"; then
  dump_rollout_diagnostics
  die "Rollout timed out. Causas comuns: ImagePullBackOff, CreateContainerConfigError, /health/ready (Cloud SQL/SSL)."
fi

log "Deploy OK (${IMAGE_URI}:${IMAGE_TAG})"
