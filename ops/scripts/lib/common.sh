#!/usr/bin/env bash
# Helpers compartilhados pelos scripts de CI/CD.
# shellcheck shell=bash

set -euo pipefail

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

require_env() {
  local name
  for name in "$@"; do
    if [ -z "${!name:-}" ]; then
      die "Variável obrigatória ausente: ${name}"
    fi
  done
}

# Substitui placeholders do overlay GCP em arquivos (cópia temporária).
# Usa '|' para não conflitar com '/' nas URIs do Artifact Registry.
replace_gcp_placeholders() {
  local file="$1"
  local project_id="$2"
  local secret_key="$3"
  local image_repo="$4"
  local image_tag="$5"

  sed -i.bak \
    -e "s|__GCP_PROJECT_ID__|${project_id}|g" \
    -e "s|__SECRET_REMOTE_KEY__|${secret_key}|g" \
    -e "s|__IMAGE_REPO__|${image_repo}|g" \
    -e "s|__IMAGE_TAG__|${image_tag}|g" \
    "${file}"
  rm -f "${file}.bak"
}
