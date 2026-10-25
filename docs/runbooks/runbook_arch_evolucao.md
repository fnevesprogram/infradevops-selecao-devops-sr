# Runbook — Evolução da Arquitetura (Comments API)

Roadmap de **próximos passos** e melhorias sobre a arquitetura atual (FastAPI sync no request path + Cloud SQL + GKE Autopilot + Kustomize/CD).

| Campo | Valor |
| :--- | :--- |
| Estado atual | API síncrona → Cloud SQL (única instância) · Autopilot · um repositório monólito |
| Estado alvo | API assíncrona (Pub/Sub) · CQRS leve (RW split) · cache na leitura · GitOps · API Gateway · Autopilot em escala |
| Objetivo de escala | Aceitar **milhões de requisições** (ingresso) e processar **milhares de RPS** por workload com resiliência |

---

## 1. Motivação

A arquitetura atual acopla **aceitação HTTP** e **persistência** no mesmo caminho crítico:

```text
Cliente → API → INSERT Cloud SQL → 201
```

Limitações sob pico:

- Latência e erros 5xx sobem juntos (banco satura o request path).
- Retry do cliente multiplica carga no Postgres.
- Um único writer/reader no Cloud SQL não separa carga analítica/listagem da escrita.
- Um único repositório mistura app e infra, dificultando GitOps e ownership.

A evolução desacopla **ingresso** de **persistência** e separa **leitura** de **escrita**.

---

## 2. Arquitetura alvo (visão)

```text
                    ┌─────────────────┐
  Clientes ───────► │  API Gateway    │  (rate limit, auth, WAF, routing)
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
     ┌────────────────┐            ┌────────────────┐
     │ Producer API   │            │ Read API       │
     │ (ingressão)    │            │ (consulta)     │
     │ POST → Pub/Sub │            │ GET + Cache    │
     └────────┬───────┘            └────────▲───────┘
              │ publish                     │
              ▼                             │
     ┌────────────────┐                     │
     │  GCP Pub/Sub   │                     │
     │  + DLQ         │                     │
     └────────┬───────┘                     │
              │ pull/push                   │
              ▼                             │
     ┌────────────────┐            ┌───────┴────────┐
     │ Consumer       │  WRITE     │ Cache (Memorystore│
     │ Worker         │ ─────────► │  / Redis)       │
     │ (grava + retry)│            └───────▲────────┘
     └────────┬───────┘                    │ invalidate /
              │                            │ populate
              ▼                            │
     ┌────────────────┐            ┌───────┴────────┐
     │ Cloud SQL      │            │ Cloud SQL      │
     │ PRIMARY        │ ─replicate─│ READ REPLICA(s)│
     │ (escrita)      │            │ (leitura)      │
     └────────────────┘            └────────────────┘

  GitOps: repo app (imagem)  +  repo infra (Terraform/Kustomize) ← Flux/Argo CD
```

---

## 3. API assíncrona com Pub/Sub (produtor × consumidor)

### 3.1 Produtor (Comments Ingress API)

Responsabilidade: validar payload, publicar evento, responder rápido.

| Aspecto | Definição |
| :--- | :--- |
| Endpoint | `POST /api/comment/new` |
| Resposta | `202 Accepted` + `event_id` / `message_id` (idempotency key) |
| Persistência no request | **Não** grava no banco |
| Broker | Tópico Pub/Sub `comments.created` (ou `comments.commands`) |
| Payload | JSON envelope: `event_id`, `email`, `comment`, `content_id`, `produced_at`, `trace_id` |
| Idempotência | Header `Idempotency-Key` → atributo da mensagem / dedup window |

Fluxo:

```text
POST /api/comment/new
  → valida schema
  → publica no Pub/Sub (ordering key opcional: content_id)
  → 202 Accepted
```

### 3.2 Consumidor (Comments Persist Worker)

Responsabilidade: consumir, gravar no **PRIMARY**, tratar falha com reprocessamento.

| Aspecto | Definição |
| :--- | :--- |
| Trigger | Push subscription (GKE) ou Pull com concorrência controlada |
| Ação de sucesso | `INSERT` no Cloud SQL primary + ack da mensagem |
| Falha transitória | Nack / retry com backoff (Pub/Sub redelivery) |
| Falha permanente / esgotou retries | Encaminha para **DLQ** (`comments.created.dlq`) |
| Observabilidade | métricas `messages_consumed`, `db_write_errors`, `dlq_depth` |

Política de reprocessamento:

1. Retry automático do Pub/Sub (`minimum_backoff` / `maximum_backoff`, `max_delivery_attempts`).
2. Após N tentativas → DLQ.
3. Replay da DLQ via job/runbook (dead-letter redrive) após correção (schema, permissão, outage de banco).
4. Deduplicação no consumidor: unique `(event_id)` ou `(idempotency_key)` na tabela / índice único.

### 3.3 Separação de serviços no cluster

| Workload | Tipo | Escala por |
| :--- | :--- | :--- |
| `comments-producer` | Deployment + HPA (RPS / CPU) | Ingress HTTP |
| `comments-consumer` | Deployment + HPA (unacked messages / CPU) | Lag Pub/Sub |
| `comments-read-api` | Deployment + HPA | RPS de leitura |

Benefício: pico de escrita satura o consumer/banco, **não** derruba a aceitação HTTP (produtor continua 202).

---

## 4. Segregação do banco (partição escrita × leitura)

Modelo **CQRS leve** com Cloud SQL:

| Partição | Papel | Usuários |
| :--- | :--- | :--- |
| **PRIMARY (write)** | Única fonte de verdade para `INSERT/UPDATE` | Apenas o **consumer** |
| **READ REPLICA(s)** | Réplicas assíncronas para `SELECT` | **Read API** (+ jobs analíticos) |
| **Cache (leitura)** | Memorystore Redis na frente da Read API | Listagens quentes (`/api/comment/list/{id}`) |

Regras:

- Producer **nunca** abre conexão de escrita no banco.
- Consumer **nunca** serve HTTP de listagem.
- Read API **nunca** escreve no primary (connection string só da réplica).
- Após write bem-sucedido, consumer pode: invalidar chave de cache `comments:{content_id}` ou publicar evento `comments.persisted` para refresh.

Consistência:

- Leitura após escrita pode ser **eventualmente consistente** (lag de réplica + cache TTL).
- Se o produto exigir “read-your-writes”, expor `GET` por `event_id` no produtor (status: `accepted` → `persisted`) consultando primary ou uma tabela de status enxuta.

Terraform (próximos módulos):

- `google_sql_database_instance` primary (já existe) + `replica_configuration` / read replicas.
- Memorystore Redis (VPC same as GKE).
- IAM: SAs distintas `consumer-sa` (writer) e `read-api-sa` (reader).

---

## 5. Cache na partição de leitura

| Item | Proposta |
| :--- | :--- |
| Tecnologia | Memorystore for Redis |
| Chaves | `comments:list:{content_id}` · TTL 30–120s (ajustável) |
| Hit | Read API responde sem ir à réplica |
| Miss | Read API → réplica → popula cache |
| Invalidação | Consumer após commit (delete key) ou TTL-only (mais simples) |

Não colocar cache no caminho do **producer** (ingresso deve permanecer sem estado de banco/cache).

---

## 6. Segregação de repositórios + GitOps

### 6.1 Repositórios

| Repositório | Conteúdo | CI/CD |
| :--- | :--- | :--- |
| **`comments-api` (app)** | Código FastAPI (producer / consumer / read), Dockerfile, testes | Build → Artifact Registry → tag/imagem |
| **`comments-infra` (novo)** | Terraform, Kustomize/Helm, políticas, App-of-Apps | GitOps reconcilia cluster + cloud |

O repositório atual deixa de misturar app+infra: **app-only** no repo de aplicação; infra migra para o repo dedicado.

### 6.2 Práticas GitOps

| Prática | Como aplicar |
| :--- | :--- |
| Source of truth | Manifests no repo `comments-infra` (`envs/dev`, `envs/prod`) |
| Reconciler | **Flux CD** ou **Argo CD** no Autopilot |
| Imagem | App CI publica digest; infra atualiza tag via ImagePolicy / Automation (Flux) ou PR bot |
| Promoções | PR `dev` → `staging` → `prod` (sem `kubectl apply` manual no CD app) |
| Secrets | External Secrets + Secret Manager (já iniciado) permanece na infra |
| Terraform | Pipeline no repo infra (`plan` em PR, `apply` em main com approval) |

Fluxo alvo:

```text
git push (app) → CI build/push imagem
                     ↓
              ImageUpdate (GitOps) altera tag no repo infra
                     ↓
              Flux/Argo aplica no GKE Autopilot
```

---

## 7. Autopilot em escala (milhares de RPS por camada)

| Melhoria | Detalhe |
| :--- | :--- |
| HPA por workload | Producer (RPS/CPU), Consumer (Pub/Sub undelivered / CPU), Read (RPS/CPU) |
| Resource requests | Right-size Autopilot (evitar fome de CPU e OOM sob fan-out) |
| PDB | Manter `minAvailable` adequado por Deployment |
| Concorrência | Uvicorn/Gunicorn workers no producer; consumer com `max_outstanding_messages` |
| Conexões DB | PgBouncer / pool por pod; limite de conexões no primary |
| Quotas GCP | CPU/memória Autopilot, Pub/Sub, Cloud SQL tier e IOPS dimensionados para o pico |
| Regional | Autopilot regional + read replicas multi-zona |
| Network | Private nodes, Private Google Access (já), VPC-native |
| Observabilidade | Golden Signals por serviço + lag Pub/Sub + DLQ depth + replica lag |

Meta operacional (exemplo):

- Producer: p95 &lt; 50 ms (só Pub/Sub publish).
- Consumer: throughput sustentável alinhado ao tier do Cloud SQL.
- Read API: p95 &lt; 100 ms com cache hit alto (&gt; 80% em listagens quentes).

---

## 8. API Gateway

Colocar um gateway na frente dos serviços de ingresso/leitura:

| Opção GCP | Uso |
| :--- | :--- |
| **API Gateway** / **Apigee** | Produto API (keys, quotas, analytics) |
| **Cloud Load Balancing + Cloud Armor** | L7, WAF, SSL, backend GKE/NEG |
| **Kong / Envoy Gateway (GKE)** | Gateway in-cluster se preferir CNCF |

Capacidades mínimas:

- Terminação TLS e certificados.
- Rate limiting / quota por cliente.
- Roteamento: `/api/comment/new` → producer · `/api/comment/list/*` → read-api.
- AuthN (API key / JWT / IAP) na borda.
- Correlação `X-Request-Id` / `traceparent` propagado até Pub/Sub attributes.

---

## 9. Roadmap de implementação (próximos passos)

### Fase 0 — Preparação (1 sprint)

- [ ] Congelar contratos OpenAPI atuais (`POST` sync → documentar breaking change `202`).
- [ ] Criar repo `comments-infra` e mover Terraform/Kustomize.
- [ ] Instalar Flux ou Argo CD no Autopilot (bootstrap GitOps).
- [ ] Dimensionar cotas (Pub/Sub, Cloud SQL, Autopilot).

### Fase 1 — Pub/Sub + split producer/consumer

- [ ] Terraform: tópico, subscription, DLQ, IAM (publisher/subscriber SAs).
- [ ] Extrair `comments-producer` (publish + 202).
- [ ] Extrair `comments-consumer` (write primary + retry/DLQ).
- [ ] Feature flag / dual-run: sync legado vs async (canary %).
- [ ] Dashboards: publish latency, ack deadline, DLQ, consumer lag.

### Fase 2 — Read path (réplica + cache)

- [ ] Cloud SQL read replica(s).
- [ ] `comments-read-api` apontando só para réplica.
- [ ] Memorystore + cache de listagem + invalidação.
- [ ] Remover leitura do primary na API de ingresso.

### Fase 3 — Gateway + escala Autopilot

- [ ] Provisionar API Gateway / LB + Armor.
- [ ] Rotas e rate limits por endpoint.
- [ ] HPA/PDB/load tests (k6/Locust) em milhões de eventos/dia e milhares de RPS sustentados.
- [ ] Chaos: matar consumer, encher DLQ, failover de réplica.

### Fase 4 — Hardening GitOps e multi-env

- [ ] Ambientes `dev` / `staging` / `prod` só via PR no repo infra.
- [ ] Image automation (digest imutável).
- [ ] Policy-as-code (OPA/Kyverno) no cluster.
- [ ] Runbooks de redrive DLQ e rebuild de cache.

---

## 10. Critérios de sucesso

| Critério | Meta |
| :--- | :--- |
| Desacoplamento | Pico de escrita não eleva 5xx do producer acima do SLO de ingresso |
| Resiliência | Mensagens reprocessadas via Pub/Sub; DLQ com redrive documentado |
| Escala leitura | Listagens servidas por cache/réplica; primary só write |
| GitOps | Zero `kubectl apply` manual em prod; drift reconciliado |
| Gateway | Auth/rate-limit na borda; backends internos privados |
| Observabilidade | Lag, DLQ, replica lag e golden signals por serviço |

---

## 11. Riscos e mitigações

| Risco | Mitigação |
| :--- | :--- |
| Breaking change `201` → `202` | Versionar API (`/v2`) ou período de compatibilidade |
| Lag de réplica / cache stale | TTL curto + invalidação; endpoint de status do evento |
| Consumer mais lento que producer | HPA no consumer + alertas de lag + backpressure (Pub/Sub) |
| Dual repo sem disciplina | CODEOWNERS + branch protection + GitOps only |
| Custo Pub/Sub + Redis + replicas | Right-size e ambientes não-prod menores |

---

## 12. Referências internas

- Stack atual GKE/CD: `docs/runbooks/github-actions-gke-deploy.md`
- Incidentes/rollback: `docs/runbooks/runbook-globo-comments.md`
- Observabilidade local: `docs/runbooks/observabilidade-local.md`
- IaC atual: `infra/terraform/`
- Manifests atuais: `k8s/`
