#!/usr/bin/env bash
# Garante que o repositório Docker existe no Artifact Registry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd gcloud
require_env PROJECT_ID REGION GAR_REPOSITORY

if gcloud artifacts repositories describe "${GAR_REPOSITORY}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "Artifact Registry já existe: ${GAR_REPOSITORY}"
  exit 0
fi

log "Criando Artifact Registry: ${GAR_REPOSITORY}"
gcloud artifacts repositories create "${GAR_REPOSITORY}" \
  --repository-format=docker \
  --location="${REGION}" \
  --description="Comments API container images" \
  --project="${PROJECT_ID}"
