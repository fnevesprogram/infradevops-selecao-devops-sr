#!/usr/bin/env bash
# Falha cedo se secrets/vars do CD estiverem ausentes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_env PROJECT_ID WIF_PROVIDER WIF_SERVICE_ACCOUNT

log "CD config OK"
log "project=${PROJECT_ID} region=${REGION:-?} cluster=${GKE_CLUSTER:-?} env=${ENVIRONMENT:-?}"
