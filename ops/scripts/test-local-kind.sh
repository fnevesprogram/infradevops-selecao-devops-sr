#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="comments-cluster"
IMAGE_NAME="comments-api:latest"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=========================================================="
echo "🚀 Bootstrapping Local KinD Cluster for Comments API"
echo "=========================================================="

for cmd in kind kubectl kustomize docker; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Erro: Ferramenta '$cmd' não encontrada no PATH. Por favor, instale-a."
    echo "   (kubectl >= 1.27 inclui 'kubectl kustomize' — neste caso use: kubectl)"
    # Aceita kubectl embutido se kustomize CLI ausente
    if [[ "$cmd" == "kustomize" ]] && command -v kubectl &> /dev/null; then
      echo "ℹ️  Usando 'kubectl apply -k' / 'kubectl kustomize' como fallback."
      continue
    fi
    exit 1
  fi
done

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "ℹ️ Cluster KinD '${CLUSTER_NAME}' já existe. Pulando criação."
else
  echo "📦 Criando cluster KinD '${CLUSTER_NAME}' com suporte a Ingress (portas 80/443)..."
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo "🌐 Instalando Ingress-NGINX Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "⏳ Aguardando Ingress-NGINX Controller ficar Ready (até 90s)..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

echo "🐳 Construindo imagem '${IMAGE_NAME}'..."
docker build -t "${IMAGE_NAME}" "${ROOT_DIR}/app"

echo "📥 Carregando imagem no cluster KinD..."
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

echo "📦 Aplicando manifests Kustomize (overlay local)..."
kubectl apply -k "${ROOT_DIR}/k8s/overlays/local"

echo "⏳ Aguardando Postgres e Comments API..."
kubectl rollout status deployment/comments-postgres -n comments --timeout=120s
kubectl rollout status deployment/comments-api -n comments --timeout=120s

echo ""
echo "=========================================================="
echo "✅ Deploy concluído com sucesso no cluster KinD!"
echo "=========================================================="
echo "Endpoints disponíveis:"
echo "👉 Health:  http://localhost/health"
echo "👉 Metrics: http://localhost/metrics"
echo "👉 Swagger: http://localhost/docs"
echo ""
echo "Para limpar o cluster local:"
echo "kind delete cluster --name ${CLUSTER_NAME}"
