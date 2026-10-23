# Passo a passo — Subir no GCP e usar a esteira GitHub Actions (GKE Autopilot + Kustomize)

Este guia cobre: (A) provisionar a infra no GCP, (B) configurar o GitHub, (C) disparar a esteira CD que faz deploy com **Kustomize** no **GKE Autopilot**.

Workflow: [`.github/workflows/cd.yml`](../../.github/workflows/cd.yml)

---

## Visão geral do fluxo CD

```
push main / workflow_dispatch
        │
        ▼
 GitHub Actions (OIDC → GCP WIF)
        │
        ├── docker build + push → Artifact Registry
        ├── get-gke-credentials (GKE Autopilot)
        ├── deploy-gcp-kustomize.sh  (kubectl apply -k, análogo ao helm upgrade --wait)
        └── kubectl rollout status
```

> Mesmo padrão da esteira de referência (auth → build/push → credentials → deploy → verify).  
> Em vez de Helm, usa **Kustomize** embutido no `kubectl` (`ops/scripts/deploy-gcp-kustomize.sh`).

---

## Parte A — Subir a infraestrutura no GCP

### A1. Pré-requisitos na máquina

- Conta GCP com billing e um `project_id`
- Instalados: `gcloud`, Terraform `>= 1.5`, kubectl (opcional local)

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project SEU_PROJECT_ID
```

### A2. Criar o repositório no GitHub (se ainda não existir)

1. Crie (ou faça fork) o repositório no GitHub.
2. Anote o caminho `owner/repo` (ex.: `meu-user/infradevops-selecao-devops-sr`).
3. Esse valor **deve** ir no Terraform (`github_repo`) para o OIDC aceitar só este repositório.

### A3. Variáveis Terraform

```bash
cd infra/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edite `terraform.tfvars`:

```hcl
project_id  = "SEU_PROJECT_ID"
region      = "us-central1"
environment = "dev"
github_repo = "SEU_OWNER/SEU_REPO"   # mesmo owner/repo do GitHub
```

### A4. Provisionar (VPC, GKE Autopilot, Cloud SQL, Secret Manager, WIF, ESO)

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### A5. Copiar outputs para o GitHub

```bash
terraform output
```

| Output Terraform | Secret / Variable no GitHub |
| :--- | :--- |
| *(project id usado no tfvars)* | Secret `GCP_PROJECT_ID` |
| `workload_identity_provider` | Secret `GCP_WIF_PROVIDER` |
| `github_actions_sa_email` | Secret `GCP_WIF_SERVICE_ACCOUNT` |
| `gke_cluster_name` (default `dev-comments-gke`) | Variable `GKE_CLUSTER_NAME` |
| região (`us-central1`) | Variable `GCP_REGION` |

Opcional: Variable `GAR_REPOSITORY` = `comments-repo`, Variable `ENVIRONMENT` = `dev`.

### A6. Conferir cluster Autopilot (opcional)

```bash
gcloud container clusters get-credentials "$(terraform output -raw gke_cluster_name)" \
  --region=us-central1 --project=SEU_PROJECT_ID

kubectl get nodes
kubectl get pods -n external-secrets
```

---

## Parte B — Configurar a esteira no GitHub

### B1. Secrets (Settings → Secrets and variables → Actions → Secrets)

| Nome | Origem |
| :--- | :--- |
| `GCP_PROJECT_ID` | ID do projeto GCP |
| `GCP_WIF_PROVIDER` | `terraform output workload_identity_provider` |
| `GCP_WIF_SERVICE_ACCOUNT` | `terraform output github_actions_sa_email` |

### B2. Variables (Settings → Secrets and variables → Actions → Variables)

| Nome | Valor sugerido |
| :--- | :--- |
| `GCP_REGION` | `us-central1` |
| `GKE_CLUSTER_NAME` | `dev-comments-gke` |
| `GAR_REPOSITORY` | `comments-repo` |
| `ENVIRONMENT` | `dev` |

### B3. Garantir que o código da esteira está no `main`

- Arquivo obrigatório: `.github/workflows/cd.yml`
- Manifests: `k8s/base` + `k8s/overlays/gcp`
- O `github_repo` do Terraform **deve bater** com o repositório onde a Actions roda (senão OIDC falha).

### B4. Permissões do workflow

O YAML já declara:

```yaml
permissions:
  contents: read
  id-token: write
```

Não desative `id-token: write` — é necessário para OIDC.

---

## Parte C — Usar a esteira (disparar o deploy)

### C1. Opção automática — push na `main`

```bash
git checkout main
git add .
git commit -m "ci: enable kustomize deploy to gke autopilot"
git push origin main
```

1. Abra o GitHub → aba **Actions**
2. Selecione o workflow **CD — Deploy Comments API (GKE Autopilot + Kustomize)**
3. Acompanhe os jobs: auth → build/push → kubectl apply -k → rollout

### C2. Opção manual — workflow_dispatch

1. GitHub → **Actions**
2. Workflow **CD — Deploy Comments API (GKE Autopilot + Kustomize)**
3. Botão **Run workflow** → branch `main` → **Run workflow**

Útil para redeploy sem novo commit.

### C3. O que a esteira executa (checklist interno)

1. Valida secrets (`GCP_PROJECT_ID`, WIF)
2. Autentica no GCP via OIDC (sem JSON key)
3. Garante repositório no Artifact Registry
4. `docker build` da pasta `./app` e tag com `github.sha`
5. Push da imagem
6. Credenciais do cluster **GKE Autopilot**
7. Substitui placeholders do overlay `gcp` (projeto, secret, imagem)
8. `kubectl kustomize` + `kubectl apply -k` (sem binário kustomize)
9. `kubectl rollout status deployment/comments-api -n comments`

### C4. Validar pós-deploy

No GitHub Actions, o último step lista pods/secrets. Localmente:

```bash
gcloud container clusters get-credentials dev-comments-gke \
  --region=us-central1 --project=SEU_PROJECT_ID

kubectl get pods,svc,externalsecret -n comments
kubectl port-forward -n comments svc/comments-api 8080:80

curl -s http://localhost:8080/health/live
curl -s http://localhost:8080/health/ready
```

### C5. Rollback via esteira / cluster

- Reverter commit e push em `main` (nova imagem + apply), **ou**
- Manual: `kubectl rollout undo deployment/comments-api -n comments`  
  (ver [Runbook Globo Comments](./runbook-globo-comments.md))

---

## Troubleshooting da esteira

| Sintoma | Causa | Ação |
| :--- | :--- | :--- |
| `Missing required secret` | Secrets não configurados | Parte B1 |
| `Unable to exchange token` / OIDC denied | `github_repo` no Terraform ≠ repo atual | Ajustar `terraform.tfvars` e `terraform apply` |
| `Permission denied` Artifact Registry | SA sem roles | Reaplicar módulo WIF (writer + repoAdmin) |
| `ExternalSecret` / CRD not found | ESO não instalado | `terraform apply` (módulo `external_secrets`) |
| `no matches for kind ClusterSecretStore in version external-secrets.io/v1` | Manifests em `v1` com ESO &lt; 0.16 | Usar `external-secrets.io/v1beta1` (chart 0.14.x) ou upgrade do chart para ≥ 0.16 |
| Rollout timeout + `BinaryAuthorization` / `ImagePolicyWebhook` | BinAuth ENFORCE sem attestors | `terraform apply` (gke) ou `./ops/scripts/cd/fix-cluster-prereqs.sh` |
| Rollout timeout + logs `Database health check failed` / SSL | Cloud SQL `ENCRYPTED_ONLY` | `terraform apply` (cloudsql → `ALLOW_UNENCRYPTED_AND_ENCRYPTED`) + `DATABASE_SSL` no overlay |
| Pods não ficam Ready | Secret DB / SQL | `kubectl describe externalsecret -n comments`; checar Cloud SQL |
| Workflow não aparece | YAML fora de `.github/workflows` ou branch errada | Confirmar arquivo no `main` |

---

## Parte D — Teardown (parar custos)

```bash
cd infra/terraform/environments/dev
terraform destroy
```

---

## Ordem resumida

1. `terraform apply` (Autopilot + SQL + WIF + ESO)  
2. Configurar Secrets/Variables no GitHub  
3. Push em `main` **ou** Run workflow  
4. Conferir Actions + `kubectl get pods -n comments`  
5. `terraform destroy` ao finalizar o teste  
