#!/usr/bin/env bash
# Smoke pós-deploy (rollout já foi validado em deploy-gcp-kustomize.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd kubectl

NAMESPACE="${NAMESPACE:-comments}"

log "Recursos no namespace ${NAMESPACE}"
kubectl get pods,svc,pdb,hpa,externalsecret -n "${NAMESPACE}"
kubectl get secret comments-api-db-secret -n "${NAMESPACE}" >/dev/null

ready="$(kubectl get deploy comments-api -n "${NAMESPACE}" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
desired="$(kubectl get deploy comments-api -n "${NAMESPACE}" \
  -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)"

if [[ "${ready:-0}" -lt 1 ]] || [[ "${ready}" -lt "${desired:-0}" ]]; then
  die "Deploy inconsistente: ready=${ready:-0} desired=${desired:-0}"
fi

log "Deploy verificado (sha=${GITHUB_SHA:-local} ready=${ready}/${desired})"
