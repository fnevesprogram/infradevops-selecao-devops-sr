#!/usr/bin/env bash
# Verifica rollout e recursos principais pós-deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd kubectl

NAMESPACE="${NAMESPACE:-comments}"
TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

log "Aguardando rollout"
kubectl rollout status "deployment/comments-api" -n "${NAMESPACE}" --timeout="${TIMEOUT}"

log "Recursos no namespace ${NAMESPACE}"
kubectl get pods,svc,pdb,externalsecret -n "${NAMESPACE}"
kubectl get secret comments-api-db-secret -n "${NAMESPACE}"

log "Deploy verificado (sha=${GITHUB_SHA:-local})"
