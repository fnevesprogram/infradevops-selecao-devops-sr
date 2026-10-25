# FinOps — Custo atual da stack GCP (Comments API)

Documento de **FinOps** da solução **atual** (ambiente `dev`): o que gera custo no GCP, por que o **GKE Autopilot** foi escolhido e onde está a **economia** frente a um cluster Standard / sizing maior.

| Campo | Valor |
| :--- | :--- |
| Projeto | `globo-comments` (exemplo tfvars) |
| Região | `us-central1` |
| Ambiente | `dev` |
| Moeda / base | USD · preços de lista aproximados (ordem de grandeza) |
| Aviso | Valores **estimados** — confirme no [Billing](https://console.cloud.google.com/billing) e no [Pricing Calculator](https://cloud.google.com/products/calculator). Preços mudam por região, descontos e uso real. |

---

## 1. Resumo executivo — a economia em uma frase

> Com **Autopilot + Cloud SQL `db-f1-micro` + HPA mínimo 1 + pods pequenos**, o `dev` paga sobretudo pelo **que está rodando** (CPU/memória solicitada dos pods + SQL shared-core), em vez de manter **nós ociosos 24×7** como num GKE Standard.

| Comparativo | Modelo de cobrança | Perfil de custo em `dev` |
| :--- | :--- | :--- |
| **GKE Standard** | Nós (VMs) ligados o tempo todo + management | Alto piso fixo mesmo sem tráfego |
| **GKE Autopilot (escolhido)** | vCPU / memória / ephemeral **solicitados pelos pods** | Piso baixo; sobe só com escala do HPA |

**Ordem de grandeza do `dev` atual (idle / pouca carga):** tipicamente **dezenas de USD/mês** (SQL + Autopilot mínimo + NAT/rede + registry), não centenas — desde que o HPA não fique no máximo e não haja vazamento de recursos.

---

## 2. Inventário da stack que gera custo

O que o Terraform / Kustomize provisiona hoje e **como** o GCP cobra:

| Componente | Recurso atual | Driver de custo | Impacto no `dev` |
| :--- | :--- | :--- | :---: |
| **GKE Autopilot** | Cluster `dev-comments-gke`, nós privados | CPU/RAM/ephemeral dos pods + taxa de cluster (se aplicável) | **Alto** (principal variável) |
| **Cloud SQL** | Postgres 16 · `db-f1-micro` · **ZONAL** · disco 10 GB SSD · IP **privado** | Instância (vCPU/RAM do tier) + disco + backup | **Alto** (piso fixo) |
| **Cloud NAT + Router** | NAT para saída dos nós privados | Gateway-hora + processamento de dados | Médio |
| **VPC / IPs / Peering** | VPC, subnet, Private Service Connect (SQL) | Baixo (rede); tráfego egress conta à parte | Baixo |
| **Artifact Registry** | Repo Docker `comments-repo` | Storage (GB/mês) + egress de pull | Baixo |
| **Secret Manager** | `dev-comments-db-url` | Versões ativas + operações de acesso | Muito baixo |
| **IAM / WIF** | SA GitHub Actions + ESO | Sem custo de “produto”; só uso indireto | — |
| **External Secrets (Helm)** | Pods no Autopilot | Entram na conta **Autopilot** (requests do ESO) | Baixo–médio |
| **Comments API** | Deployment + HPA `minReplicas: 1` · requests `100m` CPU / `128Mi` | Autopilot (pod da app) | Médio |
| **Ingress nginx (manifest)** | Sem LB GCP dedicado garantido | Sem custo de LB se não provisionado | — / sob demanda |
| **Observabilidade** | Prometheus/Grafana no **Compose local** | **R$0 no GCP** (não está no cluster) | Zero |

Não há hoje (no escopo atual): Memorystore, Pub/Sub, API Gateway/Apigee, Cloud Armor, GKE Standard node pools, Cloud SQL HA regional, BigQuery, etc.

---

## 3. Detalhamento por serviço

### 3.1 GKE Autopilot — escolha e economia

**Por que Autopilot**

| Critério | Efeito em FinOps / operação |
| :--- | :--- |
| Cobrança por **pod request** | Não paga VM ociosa “só para ter cluster” |
| Sem node pool para gerir | Menos engenharia (patch, bin-packing, autoscaler de nó) |
| Right-sizing automático do nó | Google empacota pods; você dimensiona **requests** |
| Workload Identity nativo | Sem custo extra de “segurança”; reduz risco de chaves |
| Escala com HPA | Custo sobe **com demanda**, não com medo de capacidade |

**Configuração atual que segura o custo**

| Parâmetro | Valor | Efeito FinOps |
| :--- | :--- | :--- |
| Mode | `enable_autopilot = true` | Pay-per-pod |
| HPA | `minReplicas: 1` · `maxReplicas: 5` | Piso = 1 pod; teto controlado |
| Requests | `cpu: 100m` · `memory: 128Mi` | Unidade de cobrança pequena por réplica |
| Limits | `cpu: 500m` · `memory: 512Mi` | Limita burst (Autopilot fatura sobretudo requests) |
| Nós | Private + NAT | Sem IP público por nó; egress via NAT |

**Economia vs GKE Standard (exemplo ilustrativo)**

Cenário `dev` com baixa carga (~1–2 pods pequenos):

| Modelo | O que você paga em idle | Ordem de grandeza* |
| :--- | :--- | :--- |
| Standard (ex.: 3× `e2-medium` sempre on) | 3 VMs 24×7 + disco + management | **~$70–120+/mês** só de compute de nós |
| Autopilot (1 pod ~0,1 vCPU + 128Mi + ESO) | Só resources solicitados (+ cluster fee se houver) | **~$15–40/mês** de Kubernetes* |

\*Ilustrativo; Autopilot tem preço por vCPU-hora e GiB-hora (e ephemeral). O ponto FinOps: **o piso do Standard é alto; o do Autopilot acompanha o footprint real.**

**Quando Autopilot NÃO é mais barato**

- Carga **alta e constante** 24×7 com requests grandes → Standard com CUD/SUD e nós densos pode ganhar.
- Muitos DaemonSets / system pods ou over-request crônico → conta Autopilot sobe rápido.

Para este desafio/`dev`, Autopilot é a escolha de **menor custo fixo + menos overhead operacional**.

### 3.2 Cloud SQL — piso fixo consciente

| Item | Valor atual | Nota FinOps |
| :--- | :--- | :--- |
| Tier | `db-f1-micro` | Shared-core · **menor tier** de testes |
| HA | `ZONAL` (não REGIONAL) | Evita ~2× custo de standby |
| Disco | 10 GB PD-SSD | Pequeno; cresce com dados |
| Rede | Private IP only | Sem IP público (menos superfície; sem “público” ocioso) |
| Backup / PITR | Habilitados | Custo de backup storage — necessário para RPO |

**Economia vs alternativas**

| Alternativa | Custo relativo | Por que não no `dev` |
| :--- | :--- | :--- |
| `db-custom` / `db-n1` maior | Muito maior | Overkill sem carga |
| HA REGIONAL | ~2× instância | Reservar para `prod` |
| Cloud SQL + Proxy em todo lugar | + pods Autopilot | Aqui: IP privado na VPC |

Ordem de grandeza `db-f1-micro` zonal em `us-central1`: tipicamente **~$7–15/mês** (instância + disco pequeno), antes de backup/egress.

### 3.3 Rede (VPC, NAT, peering)

| Item | Custo | Saving / decisão |
| :--- | :--- | :--- |
| Cloud NAT | Gateway + GB processados | Necessário com **private nodes**; sem NAT os pods não saem à internet/GAR com facilidade |
| Private Google Access | Sem “produto” extra | Pull de imagens Google via PGA (já no subnet) |
| Cloud SQL private IP | Peering Service Networking | Evita exposição pública (risco + às vezes IP público) |

**Saving:** não expor SQL na internet reduz risco e evita padrões caros de mitigação depois. NAT é o trade-off aceito do Autopilot privado.

### 3.4 Artifact Registry + Secret Manager

| Serviço | Como economiza |
| :--- | :--- |
| **Artifact Registry** | Um repo; tags por SHA; limpeza de imagens antigas reduz GB |
| **Secret Manager** | Um secret de connection string; WIF/ESO sem chaves longas (menos incidente = menos custo oculto) |

Custo típico no `dev`: **&lt; $1–3/mês** se o registry não acumular dezenas de GB.

### 3.5 O que está fora da conta GCP (saving implícito)

| Item | Onde roda | Efeito |
| :--- | :--- | :--- |
| Prometheus + Grafana | Docker Compose **local** | **$0** de observability no GCP no estado atual |
| Pytest / CI | GitHub Actions minutes | Fora do billing GCP (custo GitHub) |

---

## 4. Modelo de custo mensal (estimativa `dev`)

Hipótese: 1 réplica da API na maior parte do tempo, ESO leve, pouco egress, registry &lt; 5 GB, SQL `f1-micro` zonal.

| Linha | Estimativa USD/mês | % do piso |
| :--- | ---: | ---: |
| Cloud SQL (`db-f1-micro` + disco/backup) | 8 – 15 | ~30–40% |
| GKE Autopilot (API + ESO + system) | 15 – 40 | ~40–50% |
| Cloud NAT / rede / IPs | 5 – 15 | ~15–20% |
| Artifact Registry + Secret Manager | 1 – 3 | ~5% |
| **Total estimado `dev`** | **~30 – 70** | 100% |

Sob carga (HPA → 5 réplicas, mais NAT egress, mais I/O SQL): o total sobe, **dominado pelo Autopilot (réplicas) e eventualmente pelo SQL** se o tier ficar pequeno demais (aí sobe o tier — custo consciente, não surpresa de nó ocioso).

---

## 5. Pontos de atenção FinOps (clarificados)

1. **Requests inchados** no Deployment → Autopilot cobra mais **mesmo idle**. Manter `100m/128Mi` (ou o mínimo saudável) é alavanca nº 1.
2. **`minReplicas` alto** → piso permanente. Hoje `1` no overlay GCP = saving deliberado.
3. **`db-f1-micro`** é barato, mas **não** é para milhões de RPS; escala de banco = decisão de custo explícita (tier/HA/réplicas).
4. **Imagens no GAR sem retenção** → storage sobe em silêncio; política de limpeza = saving fácil.
5. **NAT egress** (pull frequente, chamadas externas) → monitorar; cache de imagem / menos pulls ajuda.
6. **Cluster Autopilot ligado 24×7** ainda tem piso (control plane / system). Para lab intermitente: desligar SQL + cluster fora do horário é o maior saving radical (com downtime).
7. Observabilidade no GCP (Managed Prometheus / Cloud Monitoring avançado) **não** está na conta atual — incluir no roadmap = novo line item.

---

## 6. Alavancas de saving (agora e depois)

| Prioridade | Ação | Economia esperada |
| :---: | :--- | :--- |
| P0 | Manter Autopilot + requests enxutos + HPA min 1 no `dev` | Evita piso de Standard |
| P0 | Manter SQL `f1-micro` + ZONAL no `dev` | Evita 2× HA e tiers médios |
| P1 | Lifecycle no Artifact Registry (apagar tags antigas) | Storage |
| P1 | Budgets + alertas no Cloud Billing | Evita surpresa |
| P2 | Desligar `dev` fora do horário (script/scheduler) | Grande (lab) |
| P2 | Committed Use / CUDs só quando `prod` estabilizar | 20–55% em compute elegível |
| P3 | Roadmap async (Pub/Sub) — right-size SQL writer vs readers | Evita oversize do primary cedo |

---

## 7. Por que a economia do Autopilot fica “clara”

```text
GKE Standard (dev típico)
  └── 3 nós × 24h × 30d  →  custo FIXO alto
       └── pods usam 10–20%  →  80% do dinheiro “parado”

GKE Autopilot (esta solução)
  └── pods (requests) × horas  →  custo VARIÁVEL alinhado ao uso
       └── HPA min=1, requests pequenos  →  piso BAIXO
       └── pico → sobe; idle → desce (sem VM fantasma)
```

**Conclusão FinOps da stack atual:** a combinação **Autopilot + SQL micro zonal + footprint mínimo de pods** privilegia **economia de piso** e **custo proporcional à demanda**, adequada a `dev`/desafio, com caminho claro para pagar mais só quando a escala (HPA, tier SQL, HA) for uma decisão explícita — não um desperdício estrutural de nós ociosos.

---

## 8. Como validar o custo real (rotina)

```bash
# Console
# Billing → Reports → filtrar projeto globo-comments (últimos 30 dias)
# Agrupar por: Serviço (GKE, Cloud SQL, Networking, Artifact Registry)

# CLI (requer gcloud billing + permissões)
gcloud billing accounts list
# Relatórios detalhados: BigQuery export do Billing ou Console Reports
```

Checklist mensal:

- [ ] Top 3 serviços por custo  
- [ ] Autopilot: custo vs número médio de réplicas  
- [ ] Cloud SQL: % do bill (se crescer, revisar tier/HA)  
- [ ] GAR: GB armazenados  
- [ ] Budget alert &lt; limite do sandbox  

---

## 9. Referências da solução

- GKE Autopilot: `infra/terraform/modules/gke/`
- Cloud SQL `db-f1-micro`: `infra/terraform/environments/dev/main.tf`
- HPA / requests: `k8s/overlays/gcp/hpa-patch.yaml`, `k8s/base/deployment.yaml`
- Evolução (mais serviços = mais line items): `docs/runbooks/runbook_arch_evolucao.md`
