# COMMENTS.md — Decisões Técnicas (objetivo)

Registro objetivo das escolhas da solução **Comments API** no Google Cloud.

Segue visão big picture da arquitetura:

![Arquitetura Comments API GCP](docs/architecture/Arquitetura%20comments-api-gcp.png)

---

## 1. Por que Google Cloud (GCP) para a API Python

- Stack alinhada ao ecossistema da empresa e ao desafio (GKE, Cloud SQL, Secret Manager, Artifact Registry).
- Integração nativa entre compute, rede, banco e IAM — menos “cola” entre provedores.
- Workload Identity e OIDC com GitHub eliminam chaves JSON de longa duração.
- Ferramentas maduras de observabilidade e segurança (Cloud Logging, Binary Authorization, Checkov/CIS no IaC).

---

## 2. Solução cloud-native

A aplicação roda como **workload em containers** no Kubernetes, com:

| Princípio | Como aparece na solução |
| :--- | :--- |
| Empacotamento imutável | Imagem multi-stage, non-root (UID 10001) |
| Orquestração | GKE Autopilot + Deploy/Service/Ingress/HPA/PDB (Kustomize) |
| Config e segredos | ConfigMap + Secret Manager via External Secrets |
| Observabilidade | `/metrics`, Prometheus, Grafana, probes live/ready |
| Automação | CI/CD GitHub Actions + Terraform (IaC) |
| Elasticidade e resiliência | HPA por CPU/memória; PDB em disrupções; nós sob demanda no Autopilot |

Local e nuvem compartilham o mesmo contrato da API; o caminho dual (Compose/KinD → GCP) valida o comportamento antes do deploy.

---

## 3. Por que GKE Autopilot

- **Menos operação:** Google gerencia nós, patches e capacity — sem node pools no Terraform.
- **FinOps:** cobra-se CPU/memória **solicitadas pelos pods**, não VMs ociosas 24/7.
- **Segurança default:** Workload Identity, Dataplane V2 e restrições a privileged/hostPath.
- **Escala com a demanda:** o data plane acompanha o HPA da Comments API.
- **IaC enxuta:** o módulo `gke` declara o cluster Autopilot + rede privada; menos superfície de erro.

Trade-off aceito: menos controle fino de machine type; em troca, menor custo operacional em `dev`.

---

## 4. Por que Cloud SQL (PostgreSQL)

- Banco **gerenciado** (backup, patching, métricas) sem operar Postgres em pod.
- **Private IP** na VPC — sem exposição pública; tráfego criptografado (`ENCRYPTED_ONLY`).
- Integração natural com GKE na mesma VPC (Private Services Access).
- Adequado ao modelo de comentários (persistência relacional, índices por `content_id`).
- Em `dev`: tier pequeno (`db-f1-micro`), PITR/backups ligados; HA multirregião dispensada no teste.

---

## 5. Vantagens da infraestrutura montada

1. **Rede privada** — VPC customizada, Cloud NAT, GKE e Cloud SQL sem IP público desnecessário.
2. **Segredos fora do Git** — connection string no Secret Manager, sincronizada pelo ESO.
3. **CI/CD keyless** — GitHub Actions autentica via Workload Identity Federation (OIDC).
4. **Deploy declarativo** — manifests Kustomize (`k8s/overlays/gcp`) no Autopilot.
5. **Resiliência de pods** — HPA + PodDisruptionBudget (`minAvailable: 1`).
6. **Observabilidade** — Golden Signals (RPS, latência, erros, saturação) no Grafana.
7. **Reprodutibilidade** — `terraform apply` / `destroy` para provisionar e cortar custo.
8. **Hardening** — Checkov no pipeline; container non-root; Binary Authorization no cluster.

---

## 6. PodDisruptionBudget (PDB) — por que configuramos

Arquivo: `k8s/base/pdb.yaml` (`minAvailable: 1`, mesmo seletor do Deployment).

**Por quê**

- O HPA mantém no mínimo **2 réplicas**, mas upgrades de nó/Autopilot e `kubectl drain` podem evictar vários pods ao mesmo tempo.
- Sem PDB, uma disrupção voluntária pode derrubar todos os pods da API de uma vez e violar disponibilidade.
- Com PDB, o Kubernetes **limita evictions voluntárias** até restar pelo menos 1 pod disponível.

**Benefícios**

- Continuidade do serviço durante manutenção e rolling do data plane.
- Alinha resiliência ao SLO de disponibilidade (menos janelas de indisponibilidade).
- Complementa (não substitui) probes, HPA e RollingUpdate (`maxUnavailable: 0` no Deployment).
- Comportamento previsível em clusters gerenciados (Autopilot faz manutenções de nós sem aviso da aplicação).

> PDB não protege contra falhas involuntárias (crash, OOM, queda de zona). Para isso seguem health checks, réplicas e o próprio Autopilot.

---

## 7. Benefícios do Kustomize

A aplicação é empacotada em `k8s/base` + overlays `local` e `gcp` (sem Helm na app).

| Benefício | Efeito prático |
| :--- | :--- |
| **YAML puro** | Manifests legíveis, sem template engine; `kubectl apply -k` direto |
| **Base + overlays** | Um base compartilhado; local (Postgres/Secret) vs GCP (ESO + imagem GAR) |
| **Patches e imagens** | `kustomize edit set image` na esteira CD — tag = `github.sha` |
| **Sem release state** | Rollback via `kubectl rollout undo` (histórico do Deployment) |
| **CI simples** | `kustomize build` valida overlays no GitHub Actions |
| **Menos acoplamento** | Plataforma (ESO via Terraform) separada do deploy da app |

Em resumo: Kustomize dá variação por ambiente com pouco overhead e encaixa bem no fluxo OIDC → GAR → GKE Autopilot.

---

## 8. Por que GitHub Actions

- Já vive no mesmo repositório do código — pipeline como código (`.github/workflows`).
- **OIDC nativo** com GCP (sem armazenar service account key).
- Separação clara: CI (pytest, `kubectl kustomize`, Trivy, Checkov) e CD (buildx → Artifact Registry → `kubectl apply -k` no Autopilot, sem instalar binário kustomize).
- Disparo por push em `main` ou `workflow_dispatch` (redeploy sob demanda).
- Ecossistema maduro (`google-github-actions/auth`, `get-gke-credentials`).

---

## 9. API: FastAPI async + PEP 8

**FastAPI assíncrono**

- I/O não bloqueante com `async`/`await` (SQLAlchemy async + asyncpg).
- OpenAPI automático em `/docs` — contrato claro para Postman/Insomnia e onboarding.
- Separação de probes: `/health/live` (processo) vs `/health/ready` (banco) — boa prática SRE.
- Instrumentação Prometheus nativa (`/metrics`).

**Boas práticas PEP 8 / código idiomático**

- Nomes e módulos claros (`config`, `database`, `schemas`, `routers`).
- Type hints e `Annotated` para dependências e validação.
- Settings tipadas (`pydantic-settings`), factory `create_app()`, logs com `logger.exception`.
- Código enxuto e legível (`Comment(**payload.model_dump())`, `db.scalars(stmt)`).
- Testes com Pytest/httpx cobrindo health, validação e CRUD de comentários.

---

## 10. IaC com Terraform no Google

Toda a infra GCP é provisionada por **Terraform modular** em `infra/terraform/`:

| Módulo | Responsabilidade |
| :--- | :--- |
| `vpc` | Rede, subnets, NAT, Private Services Access |
| `gke` | Cluster Autopilot privado |
| `cloudsql` | PostgreSQL 16 (Private IP) |
| `secrets` | Secret Manager (URL do banco) |
| `workload_identity_federation` | OIDC GitHub → GCP |
| `external_secrets` | ESO no cluster (plataforma) |

**Por quê Terraform**

- Estado e plano previsíveis (`plan` / `apply` / `destroy`).
- Ambiente `dev` versionado e repetível.
- Menos clique no Console; auditoria via PR + Checkov.
- Separação plataforma (ESO/WIF) vs aplicação (Kustomize/CD).

Fluxo resumido: `terraform apply` sobe a base → secrets/OIDC no GitHub → Actions faz deploy da API no Autopilot.

---

## 11. FinOps (ambiente de avaliação)

- Autopilot pay-per-pod + Cloud SQL `db-f1-micro` + Spot implícito na elasticidade da plataforma.
- Após validação: `terraform destroy` para evitar custo ocioso.

---

## 12. Transparência — uso de IA (Cursor)

Utilizamos **IA assistida via Cursor** como apoio ao desenvolvimento e à documentação do desafio:

| Área | Uso |
| :--- | :--- |
| **Documentação** | Redação e organização de README, COMMENTS, runbooks e guias de subida (local/GCP/esteira) |
| **Python (API)** | Auxílio na estrutura FastAPI, refinamentos PEP 8 / código idiomático, testes e ajustes de runtime |
| **Terraform (IaC)** | Apoio na modelagem modular (VPC, GKE Autopilot, Cloud SQL, WIF, ESO) e boas práticas de provisionamento |

A decisão arquitetural, a validação (pytest, Compose, `kustomize build`, `terraform validate`) e a responsabilidade técnica final permanecem com o candidato. A IA acelerou exploração de trade-offs, boilerplate e clareza da documentação — não substitui o domínio DevOps/SRE aplicado na solução.

- Tempo estimado: planejamento ~2h; implementação/ajustes ~5h+.
- Operação: [Runbook Globo Comments](docs/runbooks/runbook-globo-comments.md) (incidentes + rollback).
- Esteira / GCP: [github-actions-gke-deploy.md](docs/runbooks/github-actions-gke-deploy.md).
