# Runbook Globo Comments

Procedimento operacional único para **triagem de incidentes** e **rollback** da Globo Comments API no GKE Autopilot.

| Campo | Valor |
| :--- | :--- |
| Serviço | Comments API (`comments-api`) |
| Namespace | `comments` |
| Dashboard | Grafana — **Globo Comments API** (`uid: comments-api-sre`) |
| Deploy | Kustomize + `kubectl` (sem Helm) |

---

## 1. Escopo e responsabilidades

Use este runbook quando:

- alertas Prometheus/Grafana indicarem indisponibilidade, erro ou latência;
- um deploy recente correlacionar com regressão;
- for necessário conter impacto e/ou reverter versão.

**Não cobre** disaster recovery completo do Cloud SQL (backups/PITR via `gcloud sql` no Console/CLI).

---

## 2. Severidade e alertas

| Alerta | Sev | Condição | Primeira ação |
| :--- | :---: | :--- | :--- |
| `CommentsAPIDown` | P1 | `up{job="comments-api"} == 0` (> 30s) | Checar pods e logs de startup |
| `CommentsAPIHigh5xxErrorRate` | P1 | 5xx > 1% (> 1m) — viola SLO | Logs, banco, tráfego anômalo |
| `CommentsAPIDatabaseDisconnected` | P1 | readiness / health sem banco | Cloud SQL, VPC, ExternalSecret |
| `CommentsAPIHighLatencyP95` | P2 | p95 > 200ms (> 1m) | CPU/memória, HPA, pool de conexões |

**SLO de referência:** disponibilidade 99,9% · latência p95 &lt; 200ms.

---

## 3. Fluxo rápido (5 minutos)

```text
Alerta / sintoma
    │
    ├─ Deploy nos últimos 30–60 min? ──Sim──► Rollback (§5) + validar saúde
    │
    ├─ Pods Ready? ──Não──► describe + logs (§4.1 / §4.2)
    │
    ├─ /health/ready falha? ──Sim──► Secret/ESO + Cloud SQL (§4.3 / §4.4)
    │
    └─ Latência / 5xx com pods OK ──► scale / restart (§4.5) ou rollback (§5)
```

---

## 4. Triagem e contenção

Pré-requisito: contexto do cluster (`gcloud container clusters get-credentials ...`).

### 4.1 Pods e eventos

```bash
kubectl get pods -n comments -o wide
kubectl describe pods -l app.kubernetes.io/name=comments-api -n comments
kubectl get pdb -n comments
```

Atenção a: `CrashLoopBackOff`, `OOMKilled`, `ImagePullBackOff`, probes falhando.

### 4.2 Logs da aplicação

```bash
kubectl logs -l app.kubernetes.io/name=comments-api -n comments --tail=100 -f
kubectl logs -l app.kubernetes.io/name=comments-api -n comments --tail=500 \
  | grep -iE "error|exception|critical"
```

### 4.3 External Secrets e Secret do banco

```bash
kubectl get externalsecrets -n comments
kubectl describe externalsecret comments-api-db-secret -n comments
kubectl get secret comments-api-db-secret -n comments
```

Se a Secret não existir ou o ExternalSecret estiver em erro: revisar ESO, Workload Identity e Secret Manager (`dev-comments-db-url`).

### 4.4 Conectividade com Cloud SQL

```bash
kubectl run netshoot --rm -i --tty --image nicolaka/netshoot -n comments -- \
  nc -zv <CLOUDSQL_PRIVATE_IP> 5432
```

Substitua `<CLOUDSQL_PRIVATE_IP>` pelo IP privado da instância (output Terraform / Console).

### 4.5 Contenção imediata

**Reinício controlado**

```bash
kubectl rollout restart deployment/comments-api -n comments
kubectl rollout status deployment/comments-api -n comments --timeout=3m
```

**Scale manual** (HPA no limite ou saturação)

```bash
kubectl scale deployment/comments-api --replicas=5 -n comments
```

**Rollback** — se o incidente coincidir com deploy recente → seção 5.

### 4.6 Smoke check pós-contenção

```bash
kubectl exec -i -t deployment/comments-api -n comments -c comments-api -- \
  python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/health/ready').read().decode())"
```

Ou via port-forward:

```bash
kubectl port-forward -n comments svc/comments-api 8080:80
curl -s http://localhost:8080/health/live
curl -s http://localhost:8080/health/ready
```

---

## 5. Rollback

O histórico fica no Deployment (`revisionHistoryLimit: 10`). Não há releases Helm.

### 5.1 Preferencial — `kubectl rollout undo`

**Histórico**

```bash
kubectl rollout history deployment/comments-api -n comments
```

**Reverter o último deploy**

```bash
kubectl rollout undo deployment/comments-api -n comments
kubectl rollout status deployment/comments-api -n comments --timeout=3m
```

**Reverter para revisão específica**

```bash
kubectl rollout undo deployment/comments-api --to-revision=<N> -n comments
kubectl rollout status deployment/comments-api -n comments --timeout=3m
```

Validar com o smoke check da seção 4.6.

### 5.2 Alternativa — redeploy de imagem estável (Kustomize)

Quando souber o SHA bom no Artifact Registry:

```bash
export PROJECT_ID="<seu-projeto>"
export REGION="us-central1"
export IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/comments-repo/comments-api"
export IMAGE_TAG="<sha-estavel>"
export ENVIRONMENT="dev"

./ops/scripts/deploy-gcp-kustomize.sh
./ops/scripts/cd/verify-deploy.sh
```

### 5.3 Após o rollback

1. Comunicar contenção (sev, impacto, versão atual).
2. Confirmar métricas no Grafana (**Globo Comments API**).
3. Manter o incidente aberto até causa raiz e follow-up.
4. Registrar aprendizado (postmortem breve / nota em `COMMENTS.md` se fizer sentido).

---

## 6. Comunicação (modelo)

| Fase | O que registrar |
| :--- | :--- |
| Detectar | Alerta, horário, evidência (curl/Grafana) |
| Declarar | Severidade, impacto, quem comanda |
| Conter | Restart, scale ou rollback (comando + horário) |
| Recuperar | Saúde verde + métricas estáveis |
| Aprender | Causa, ação preventativa, dono |

---

## 7. Referências

| Documento | Uso |
| :--- | :--- |
| [github-actions-gke-deploy.md](./github-actions-gke-deploy.md) | Subida GCP e esteira CD |
| [COMMENTS.md](../../COMMENTS.md) | Decisões e arquitetura |
| Dashboard Grafana | **Globo Comments API** (`uid: comments-api-sre`) |
