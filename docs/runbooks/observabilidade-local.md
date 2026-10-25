# Runbook — Observabilidade local (Prometheus + Grafana)

Procedimento para subir, validar e interpretar a stack de observabilidade da **Globo Comments API** em ambiente local via Docker Compose.

| Campo | Valor |
| :--- | :--- |
| Escopo | Prometheus + Grafana + API (`docker compose`) |
| Dashboard | **Globo Comments API** (`uid: comments-api-sre`) |
| Fonte de métricas | `prometheus-fastapi-instrumentator` → `GET /metrics` |
| Alertas | `ops/alerts/comments-api-alerts.yaml` |

---

## 1. Arquitetura da stack

```text
  Browser / curl
        │
        ▼
  comments-api :8000  ──► /metrics (Prometheus exposition)
        │
        ▼
  prometheus :9090    ── scrape job "comments-api" a cada 5s
        │               + regras de alerta
        ▼
  grafana :3001       ── datasource Prometheus
                        + dashboard Globo Comments API
```

Componentes no `docker-compose.yml`:

| Serviço | Porta no host | Função |
| :--- | :---: | :--- |
| `api` | 8000 | Comments API + endpoint `/metrics` |
| `prometheus` | 9090 | Scrape, TSDB e avaliação de alertas |
| `grafana` | 3001 | UI e dashboard SRE (tema azul Globo) |
| `postgres` | (só rede interna) | Banco da API |

---

## 2. Passo a passo — subir e validar

### 2.1 Pré-requisitos

- Docker Desktop (ou Engine) + Docker Compose v2
- Portas livres: `8000`, `9090`, `3001`

```bash
cd /infradevops-selecao-devops-sr-main
```

### 2.2 Subir a stack

```bash
docker compose up -d --build
docker compose ps
```

Esperado: `comments-api`, `comments-prometheus`, `comments-grafana`, `comments-postgres` com status healthy/running.

### 2.3 Health da API

```bash
curl -sS http://127.0.0.1:8000/health/live | jq .
curl -sS http://127.0.0.1:8000/health/ready | jq .
# ready → "status":"ready", "database":"connected"
```

### 2.4 Gerar tráfego (necessário para ver painéis)

```bash
# Comentários (throughput + latência)
for i in $(seq 1 20); do
  curl -sS -X POST http://127.0.0.1:8000/api/comment/new \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"user${i}@example.com\",\"comment\":\"carga observabilidade ${i}\",\"content_id\":42}" \
    >/dev/null
done

# Listagem
curl -sS http://127.0.0.1:8000/api/comment/list/42 | jq 'length'

# Erro 4xx (client) — body inválido
curl -sS -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8000/api/comment/new \
  -H 'Content-Type: application/json' \
  -d '{"email":"x","comment":"","content_id":0}'
```

Aguarde ~10–15 s para o Prometheus agregar as séries (`scrape_interval: 5s`).

### 2.5 Validar Prometheus

Browser: [http://localhost:9090](http://localhost:9090)

**Targets**

1. Menu **Status → Targets**
2. Job `comments-api` deve estar **UP**
3. Job `prometheus` (self-scrape) também **UP**

**Queries úteis (Graph → Expression)**

```promql
up{job="comments-api"}
sum(rate(http_requests_total{job="comments-api"}[1m]))
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="comments-api"}[5m])) by (le))
```

Via CLI:

```bash
curl -sS 'http://127.0.0.1:9090/api/v1/targets' \
  | jq '.data.activeTargets[] | {job: .labels.job, health}'

curl -sS 'http://127.0.0.1:9090/api/v1/query?query=up{job="comments-api"}' | jq .
```

**Alertas**

1. **Alerts** no Prometheus (ou `Status → Rules`)
2. Regras carregadas de `ops/alerts/comments-api-alerts.yaml`
3. Em idle saudável: regras em estado `inactive` (não firing)

### 2.6 Validar Grafana

Browser: [http://localhost:3001](http://localhost:3001)

| Campo | Valor |
| :--- | :--- |
| Usuário | `admin` |
| Senha | `admin` |

1. **Connections → Data sources → Prometheus** → *Save & test* → deve retornar OK  
2. **Dashboards → Globo Comments API** (ou busque `comments-api-sre`)  
3. Refresh `5s` — confira Status ONLINE, RPS > 0 e latência após a carga do §2.4  

Arquivos provisionados:

- Datasource: `ops/grafana/provisioning/datasources/prometheus.yaml`
- Dashboard: `ops/grafana/comments-api.json`

### 2.7 Parar / limpar

```bash
docker compose down          # mantém volume do Postgres
docker compose down -v       # remove também o volume pgdata
```

---

## 3. Métricas — o que a API expõe

A instrumentação vem do **Prometheus FastAPI Instrumentator**. As séries principais usadas no dashboard:

### 3.1 Disponibilidade

| Métrica / expressão | Significado |
| :--- | :--- |
| `up{job="comments-api"}` | `1` = Prometheus conseguiu scrapear `/metrics`; `0` = target DOWN |
| `GET /health/live` | Processo vivo (não é série Prometheus; usado por probe K8s) |
| `GET /health/ready` | App + banco OK |

**Painel Grafana:** *Status da API*  
**Alerta:** `CommentsAPIDown` (`up == 0` por > 30s)

### 3.2 Tráfego (Traffic) — Golden Signal

| Métrica | Tipo | Significado |
| :--- | :--- | :--- |
| `http_requests_total` | Counter | Contagem cumulativa de requisições HTTP (labels: `handler`, `status`, `method`, …) |
| `sum(rate(http_requests_total[1m]))` | Derivada | **Throughput (RPS)** — requisições por segundo na janela |

**Painéis:** *Throughput Total (RPS)*, *Requisições por Handler e Status HTTP*, *Distribuição 2xx/4xx/5xx*

Labels úteis:

- `handler` — rota (ex.: `/api/comment/new`)
- `status` — código HTTP (`200`, `201`, `422`, `500`, …)

### 3.3 Latência (Latency) — Golden Signal

| Métrica | Tipo | Significado |
| :--- | :--- | :--- |
| `http_request_duration_seconds_bucket` | Histogram | Duração das requests em buckets (`le`) |
| `histogram_quantile(0.50, …)` | p50 | Mediana — metade das requests abaixo desse valor |
| `histogram_quantile(0.95, …)` | p95 | 95% das requests abaixo (SLO operacional) |
| `histogram_quantile(0.99, …)` | p99 | Cauda — outliers / pior caso típico |

**SLO de referência:** p95 **&lt; 200 ms**  
**Painel:** *Latência p95 (SLO &lt; 200ms)* e *Percentis p50/p95/p99*  
**Alerta:** `CommentsAPIHighLatencyP95` (p95 > 0.2s por > 1m)

### 3.4 Erros (Errors) — Golden Signal

| Expressão | Significado |
| :--- | :--- |
| `http_requests_total{status=~"5.."}` | Erros de servidor (falha da API/deps) |
| `http_requests_total{status=~"4.."}` | Erros de cliente (payload inválido, etc.) |
| `http_requests_total{status=~"2.."}` | Sucesso |
| `(rate 5xx / rate total) * 100` | **Taxa de erro 5xx (%)** |

**SLO de referência:** taxa 5xx **&lt; 1%**  
**Painel:** *Taxa de Erro 5xx (SLO &lt; 1%)*  
**Alerta:** `CommentsAPIHigh5xxErrorRate`

### 3.5 Saturação (Saturation)

Neste stack local **não** há painéis explícitos de CPU/memória do container (precisaria de cAdvisor/node-exporter). No GKE Autopilot a saturação aparece via métricas do cluster + HPA (`cpu`/`memory` utilization).

### 3.6 Mapa rápido: painel → consulta

| Painel Grafana | PromQL (resumo) | Interpretação |
| :--- | :--- | :--- |
| Status da API | `up{job="comments-api"}` | Target scrapeável |
| Throughput Total (RPS) | `sum(rate(http_requests_total[1m]))` | Carga atual |
| Latência p95 | `histogram_quantile(0.95, sum(rate(..._bucket[5m])) by (le))` | SLO latência |
| Taxa de Erro 5xx | `(rate 5xx / rate total) * 100` | SLO erro |
| Req. por Handler/Status | `sum(rate(...[1m])) by (handler, status)` | Qual rota/status cresce |
| Percentis p50/p95/p99 | `histogram_quantile(0.50\|0.95\|0.99, …)` | Forma da latência |
| Distribuição 2xx/4xx/5xx | `rate` filtrado por `status` | Qualidade do tráfego |

---

## 4. Alertas configurados

Arquivo: `ops/alerts/comments-api-alerts.yaml` (montado em `/etc/prometheus/alerts`).

| Alerta | Condição | Severidade | Ação inicial |
| :--- | :--- | :---: | :--- |
| `CommentsAPIDown` | `up == 0` (> 30s) | critical | `docker compose logs api` / health |
| `CommentsAPIHigh5xxErrorRate` | 5xx > 1% (> 1m) | critical | logs da API, banco, payload |
| `CommentsAPIHighLatencyP95` | p95 > 200ms (> 1m) | warning | carga, queries lentas, pool DB |
| `CommentsAPIDatabaseDisconnected` | `probe_success == 0` | critical | Postgres / `DATABASE_URL` *(série opcional; preferir `/health/ready`)* |

Para forçar um alerta de latência em lab (carga artificial), aumente o loop de `curl` ou adicione delay na API — em condições normais locais o p95 costuma ficar bem abaixo de 200ms.

---

## 5. Troubleshooting rápido

| Sintoma | Verificação | Correção |
| :--- | :--- | :--- |
| Grafana sem dados | Prometheus Targets `comments-api` | `docker compose restart prometheus api` |
| Target DOWN | `curl localhost:8000/metrics` | API fora / rede Compose |
| Dashboard vazio | Houve tráfego nos últimos 15m? | Rodar §2.4 e esperar ~15s |
| Porta 3001/9090 ocupada | `lsof -i :3001` / `:9090` | Parar processo ou alterar ports no compose |
| Login Grafana | user/senha | `admin` / `admin` (compose) |
| `/health/ready` 503 | Postgres | `docker compose logs postgres` |

```bash
docker compose logs -f api prometheus grafana
curl -sS http://127.0.0.1:8000/metrics | grep -E '^http_requests_total|^http_request_duration' | head
```

---

## 6. Relação com o GKE

- No cluster, a Deployment anota `prometheus.io/scrape=true` e path `/metrics`.
- Esta stack Compose **não** scrapea o GKE automaticamente.
- Para inspecionar só as métricas da API no Autopilot:

```bash
kubectl port-forward -n comments svc/comments-api 8080:80
curl -sS http://127.0.0.1:8080/metrics | head -40
```

Para Grafana no GKE seria necessário Prometheus Operator / Managed Collection (fora do escopo deste runbook local).

---

## 7. Checklist de aceite

- [ ] `docker compose ps` com API, Prometheus e Grafana up  
- [ ] `/health/ready` → `database: connected`  
- [ ] Prometheus Target `comments-api` = UP  
- [ ] Após carga, RPS e latência aparecem no dashboard **Globo Comments API**  
- [ ] Datasource Prometheus no Grafana com *Save & test* OK  
