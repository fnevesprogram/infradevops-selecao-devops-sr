#!/usr/bin/env bash
# Verifica se o repositório Docker existe no Artifact Registry.
# A criação é responsabilidade do Terraform (módulo artifact_registry) — least privilege no CD.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd gcloud
require_env PROJECT_ID REGION GAR_REPOSITORY

if gcloud artifacts repositories describe "${GAR_REPOSITORY}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "Artifact Registry OK: ${GAR_REPOSITORY} (${REGION})"
  exit 0
fi

die "Repositório '${GAR_REPOSITORY}' não existe em ${REGION}.
Crie via Terraform (não pela esteira):

  cd infra/terraform/environments/dev
  terraform apply

Ou manualmente:

  gcloud artifacts repositories create ${GAR_REPOSITORY} \\
    --repository-format=docker \\
    --location=${REGION} \\
    --project=${PROJECT_ID}"
