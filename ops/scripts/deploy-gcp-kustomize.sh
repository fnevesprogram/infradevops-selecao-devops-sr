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
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-8m}"
ESO_TIMEOUT_SEC="${ESO_TIMEOUT_SEC:-60}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-${REGION:-us-central1}}"
CLUSTER_NAME="${CLUSTER_NAME:-${GKE_CLUSTER:-${ENVIRONMENT}-comments-gke}}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

dump_rollout_diagnostics() {
  log "Diagnóstico do rollout (falha)"
  echo "::group::pods"
  kubectl get pods -n "${NAMESPACE}" -o wide || true
  kubectl get pods -n "${NAMESPACE}" \
    -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,REASON:.status.containerStatuses[0].state.waiting.reason,MESSAGE:.status.containerStatuses[0].state.waiting.message' \
    2>/dev/null || true
  echo "::endgroup::"

  echo "::group::events"
  kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' 2>/dev/null | tail -40 || true
  echo "::endgroup::"

  echo "::group::externalsecret"
  kubectl get externalsecret,secret -n "${NAMESPACE}" || true
  kubectl describe externalsecret comments-api-db-secret -n "${NAMESPACE}" 2>/dev/null | tail -50 || true
  kubectl describe clustersecretstore gcp-secret-store 2>/dev/null | tail -40 || true
  echo "::endgroup::"

  echo "::group::pod-describe-logs"
  kubectl describe pods -l app.kubernetes.io/name=comments-api -n "${NAMESPACE}" 2>/dev/null | tail -100 || true
  kubectl logs -l app.kubernetes.io/name=comments-api -n "${NAMESPACE}" --tail=80 --all-containers=true 2>/dev/null || true
  echo "::endgroup::"

  # Dicas rápidas a partir de eventos/status
  if kubectl get events -n "${NAMESPACE}" 2>/dev/null | grep -qiE 'BinaryAuthorization|ImagePolicyWebhook|denied by'; then
    echo "::error::Binary Authorization pode estar bloqueando a imagem. Desabilite no cluster (terraform apply no módulo gke) ou: gcloud container clusters update ${CLUSTER_NAME} --location=${CLUSTER_LOCATION} --binauthz-evaluation-mode=DISABLED --project=${PROJECT_ID}"
  fi
  if kubectl get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' 2>/dev/null | grep -q ImagePullBackOff; then
    echo "::error::ImagePullBackOff — verifique Artifact Registry, tag da imagem e permissões de pull no Autopilot."
  fi
  if kubectl get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' 2>/dev/null | grep -q CreateContainerConfigError; then
    echo "::error::CreateContainerConfigError — Secret comments-api-db-secret / ESO provavelmente falhou."
  fi
}

OVERLAY="${WORKDIR}/k8s/overlays/gcp"
cp -R "${ROOT_DIR}/k8s" "${WORKDIR}/k8s"

log "Preparando overlay gcp (cluster=${CLUSTER_NAME} loc=${CLUSTER_LOCATION})"
for f in kustomization.yaml clustersecretstore.yaml externalsecret.yaml; do
  replace_gcp_placeholders \
    "${OVERLAY}/${f}" \
    "${PROJECT_ID}" \
    "${SECRET_REMOTE_KEY}" \
    "${IMAGE_URI}" \
    "${IMAGE_TAG}" \
    "${CLUSTER_LOCATION}" \
    "${CLUSTER_NAME}"
done

log "Render kubectl kustomize"
kubectl kustomize "${OVERLAY}" > "${WORKDIR}/rendered.yaml"
grep -q "kind: Deployment" "${WORKDIR}/rendered.yaml" || die "Render sem Deployment"
grep -q "kind: PodDisruptionBudget" "${WORKDIR}/rendered.yaml" || die "Render sem PDB"
grep -q 'DATABASE_SSL: "true"' "${WORKDIR}/rendered.yaml" \
  || die "Overlay gcp sem DATABASE_SSL=true"
grep -q "${CLUSTER_NAME}" "${OVERLAY}/clustersecretstore.yaml" \
  || die "ClusterSecretStore sem clusterName substituído"

if ! kubectl get crd clustersecretstores.external-secrets.io >/dev/null 2>&1; then
  die "CRD ClusterSecretStore ausente. Rode terraform apply (módulo external_secrets) antes do CD."
fi

log "Apply ClusterSecretStore + overlay"
kubectl apply -f "${OVERLAY}/clustersecretstore.yaml"
kubectl apply -k "${OVERLAY}"

if ! kubectl get secret comments-api-db-secret -n "${NAMESPACE}" >/dev/null 2>&1; then
  log "Aguardando ExternalSecret criar a Secret (${ESO_TIMEOUT_SEC}s)"
  deadline=$((SECONDS + ESO_TIMEOUT_SEC))
  until kubectl get secret comments-api-db-secret -n "${NAMESPACE}" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      dump_rollout_diagnostics
      die "Secret comments-api-db-secret não criada a tempo. Verifique ESO / Secret Manager."
    fi
    sleep 2
  done
else
  log "Secret do banco já existe — skip wait ESO"
fi

log "Rollout ${NAMESPACE}/comments-api (timeout=${ROLLOUT_TIMEOUT})"
if ! kubectl rollout status "deployment/comments-api" -n "${NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"; then
  dump_rollout_diagnostics
  die "Rollout timed out. Veja os grupos de log acima (pods/events/externalsecret)."
fi

log "Deploy OK (${IMAGE_URI}:${IMAGE_TAG})"
