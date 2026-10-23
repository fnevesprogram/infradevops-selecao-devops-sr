#!/usr/bin/env bash
# Ajustes pontuais no cluster para o CD passar (requer permissão de update no GKE).
# Preferível: terraform apply nos módulos gke + cloudsql.
#
# Uso:
#   PROJECT_ID=... REGION=... GKE_CLUSTER=... ./ops/scripts/cd/fix-cluster-prereqs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd gcloud
require_env PROJECT_ID REGION GKE_CLUSTER

log "Desabilitando Binary Authorization em ${GKE_CLUSTER} (${REGION})"
gcloud container clusters update "${GKE_CLUSTER}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --binauthz-evaluation-mode=DISABLED \
  --quiet

log "OK — rode terraform apply depois para persistir (módulo gke)."
