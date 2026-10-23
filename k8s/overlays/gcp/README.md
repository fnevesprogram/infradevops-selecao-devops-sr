# Overlay GCP (GKE Autopilot)

Deploy via **kubectl** (Kustomize embutido) — sem instalar o binário `kustomize`.

## Placeholders

| Token | Exemplo |
| :--- | :--- |
| `__GCP_PROJECT_ID__` | ID do projeto GCP |
| `__SECRET_REMOTE_KEY__` | `dev-comments-db-url` |
| `__IMAGE_REPO__` | `us-central1-docker.pkg.dev/PROJECT/comments-repo/comments-api` |
| `__IMAGE_TAG__` | SHA do commit |

## Aplicar

```bash
export PROJECT_ID=seu-projeto
export IMAGE_URI=us-central1-docker.pkg.dev/${PROJECT_ID}/comments-repo/comments-api
export IMAGE_TAG=$(git rev-parse HEAD)
export ENVIRONMENT=dev

./ops/scripts/deploy-gcp-kustomize.sh
```

O script usa `kubectl kustomize` + `kubectl apply -k`.
