#!/usr/bin/env bash
# Scan de imagem com Trivy via Docker (evita falha do setup-trivy no GitHub Actions).
# Uso: ./ops/scripts/ci/trivy-scan-image.sh [image-ref]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

IMAGE_REF="${1:-comments-api:scan}"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.58.2}"

require_cmd docker

log "Pull Trivy ${TRIVY_IMAGE}"
docker pull "${TRIVY_IMAGE}"

log "Scan ${IMAGE_REF}"
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${TRIVY_IMAGE}" image \
  --severity CRITICAL,HIGH \
  --ignore-unfixed \
  --scanners vuln \
  --exit-code 0 \
  --format table \
  "${IMAGE_REF}"

log "Trivy scan OK"
