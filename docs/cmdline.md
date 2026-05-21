# AI-Service — Command Line Testing

Alle Endpunkte des AI-Service lassen sich per `curl` testen.
Der Service muss laufen: `make dev` (lokal) oder `make docker-up` (Container).

---

## Inhalt

- [Voraussetzungen](#voraussetzungen)
- [Endpunkte](#endpunkte)
- [API-Dokumentation (Browser)](#api-dokumentation-browser)

> **Schneller Einstieg:** `apps/ai-service/scripts/smoke-test.sh` testet alle Endpunkte ohne curl-Tipparbeit.

---

## Voraussetzungen

```bash
# Service starten (aus ai-service/)
make dev          # uvicorn mit --reload, Port 8000
# oder
make docker-up    # docker compose mit postgres + ai-service
```

Ohne gesetztes `SERVICE_TOKEN` (Dev-Mode) kann der Header bei Hook-Endpunkten
weggelassen werden. Mit Token muss jeder Hook-Aufruf den Header mitschicken:

```
-H "X-Service-Token: <dein-token>"
```

Alternativ via Env-Variable: `SERVICE_TOKEN=xyz ./smoke-test.sh all`

[↑ Inhalt](#inhalt)

---

## Endpunkte

### Health

```bash
curl http://localhost:8000/health          # direkt (Dev)
curl https://decisionmap.ai/api/health    # via nginx (Prod)
```

```json
{"status": "ok", "version": "0.1.0", "embedding_provider": "openai", "llm_provider": "openai"}
```

---

### Similarity-Check

Prüft einen Text gegen alle approved Problems via pgvector Cosine-Similarity.
Kein Auth erforderlich — wird vom Frontend debounced während der Eingabe aufgerufen.

```bash
curl -s http://localhost:8000/similarity \
  -H "Content-Type: application/json" \
  -d '{"text": "We have no AI governance framework in our company"}' | jq
```

```json
{
  "similar_problems": [
    {"id": "uuid-...", "title": "Missing AI policy", "score": 0.91}
  ],
  "has_duplicates": false
}
```

- `score > 0.92` → `has_duplicates: true` (Frontend blockiert Einreichung)
- `score 0.85–0.92` → ähnlich, Hinweis mit Link
- `score < 0.85` → kein Hinweis (z.B. `0.52` für thematisch verwandte, anders formulierte Problems — korrektes Verhalten)

> **Score-Interpretation:** Ein Score von ~0.5 bedeutet semantisch ähnliches Thema, aber andere Formulierung — das ist kein Bug. `text-embedding-3-small` unterscheidet korrekt zwischen *verwandtem Thema* (0.5x) und *fast identischem Text* (0.85+). Der Threshold von 0.85 ist für Duplikat-Erkennung beim Einreichen ausgelegt, nicht für thematische Suche.
>
> **Sprachnormalisierung:** Nicht-englischer Input wird vor dem Embedding via `TranslationService.to_english()` übersetzt (langdetect → LLM nur bei Nicht-Englisch). Gespeicherte Embeddings basieren auf `description_en` — ohne Normalisierung würden DE/EN-Vektoren nie den Threshold erreichen.
>
> **Dev-Threshold:** Bei weniger als ~50 Problems: `SIMILARITY_THRESHOLD=0.55` / `DUPLICATE_THRESHOLD=0.70` in `.env` setzen. Prod-Werte (0.85/0.92) sind für sparse Datasets zu streng.

---

### Hooks (Backend BackgroundTasks → AI-Service)

Diese Endpunkte werden vom FastAPI-Backend als BackgroundTasks aufgerufen. Für manuelle Tests
simulieren sie den Backend-Trigger.

**Problem eingereicht**

```bash
curl -s http://localhost:8000/hooks/problem-submitted \
  -H "Content-Type: application/json" \
  -H "X-Service-Token: <dein-token>" \
  -d '{
    "problem_id": "test-001",
    "title": "Lack of AI governance",
    "description": "No clear policies for AI usage in our org.",
    "ip_hash": "abc123",
    "signals": [],
    "honeypot": null,
    "submitted_at": "2026-04-02T10:00:00Z"
  }' | jq
```

Mit Bot-Signalen (2+ Signale → automatisch rejected, kein LLM-Call):

```bash
-d '{
  ...,
  "signals": ["submit_too_fast", "session_flood"],
  "honeypot": null
}'
```

Mit Honeypot-Feld (sofortiger Reject):

```bash
-d '{
  ...,
  "signals": [],
  "honeypot": "http://spam.example.com"
}'
```

---

**Problem freigegeben** (Admin approval → Embedding + AI-Lösung + Clustering)

```bash
curl -s http://localhost:8000/hooks/problem-approved \
  -H "Content-Type: application/json" \
  -H "X-Service-Token: <dein-token>" \
  -d '{"problem_id": "test-001"}' | jq
```

Antwort ist sofortig (`{"status": "processing"}`), die Pipeline läuft asynchron
im Hintergrund: Embedding → AI-Lösung → Clustering → WebSocket-Broadcast.

---

**Lösung freigegeben**

```bash
curl -s http://localhost:8000/hooks/solution-approved \
  -H "Content-Type: application/json" \
  -H "X-Service-Token: <dein-token>" \
  -d '{"solution_id": "sol-001", "problem_id": "test-001"}' | jq
```

---

### Bulk-Reindex (alle approved Problems neu embedden)

Generiert Embeddings für alle approved Problems — auch für solche, die bereits ein Embedding haben.
Nötig nach einem Modellwechsel oder für die initiale Befüllung.

> **Status:** `POST /embeddings/reindex` (AI-Service) und `GET /internal/problems/approved-all` (Backend)
> sind implementiert. Smoke-Test: `./scripts/smoke-test.sh reindex`.

```bash
curl -s -X POST http://localhost:8000/embeddings/reindex \
  -H "X-Service-Token: <dein-token>" | jq
```

---

### Clustering manuell triggern

Wird normalerweise vom Admin-Panel im Frontend ausgelöst.
Führt HDBSCAN auf allen approved Problems mit Embeddings aus.

```bash
curl -s -X POST http://localhost:8000/clustering/run | jq
```

```json
{
  "clusters_updated": 3,
  "problems_processed": 12,
  "duration_ms": 847
}
```

---

### WebSocket

Empfängt Live-Events die der AI-Service nach jeder Hook-Verarbeitung sendet.

```bash
# Voraussetzung: brew install websocat
websocat ws://localhost:8000/ws
```

Verbindung offen halten, dann in einem zweiten Terminal einen Hook-Call abschicken.
Eingehende Events:

```json
{"type": "problem.approved", "payload": {"id": "test-001", "cluster_id": null}}
{"type": "cluster.updated", "payload": {"id": "uuid-...", "label": "AI Governance", "problem_count": 4}}
{"type": "solution.generated", "payload": {"problem_id": "test-001", "solution_id": "sol-..."}}
```

Vote-Events kommen über den Backend-WebSocket (`useBackendRealtime`, Port 8001) — nicht über den AI-Service-WS.

[↑ Inhalt](#inhalt)

---

## API-Dokumentation (Browser)

FastAPI stellt automatisch eine interaktive OpenAPI-UI bereit:

```
http://localhost:8000/docs       # Swagger UI — alle Endpunkte testbar
http://localhost:8000/redoc      # ReDoc — Read-only Dokumentation
http://localhost:8000/openapi.json  # Raw OpenAPI-Schema
```

Alle Request-Body-Schemas, Validierungsregeln und Response-Typen sind dort
vollständig dokumentiert.

```bash
# Alle Endpunkte als Liste
curl -s http://localhost:8000/openapi.json | jq '.paths | keys'
```
