# AI-Service — Command Line Testing

Alle Endpunkte des AI-Service lassen sich per `curl` testen.
Der Service muss laufen: `make dev` (lokal) oder `make docker-up` (Container).

---

## Inhalt

- [Voraussetzungen](#voraussetzungen)
- [Endpunkte](#endpunkte)
- [API-Dokumentation (Browser)](#api-dokumentation-browser)

---

## Voraussetzungen

```bash
# Service starten (aus ai-service/)
make dev          # uvicorn mit --reload, Port 8000
# oder
make docker-up    # docker compose mit postgres + ai-service
```

Ohne gesetztes `WEBHOOK_SECRET` (Dev-Mode) kann der Header bei Hook-Endpunkten
weggelassen werden. Mit Secret muss jeder Hook-Aufruf den Header mitschicken:

```
-H "X-Webhook-Secret: <dein-secret>"
```

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
- `score < 0.85` → kein Hinweis

---

### Hooks (Directus Flows → AI-Service)

Diese Endpunkte werden von Directus Flows aufgerufen. Für manuelle Tests
simulieren sie den Directus-Trigger.

**Problem eingereicht**

```bash
curl -s http://localhost:8000/hooks/problem-submitted \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: <dein-secret>" \
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
  -H "X-Webhook-Secret: <dein-secret>" \
  -d '{"problem_id": "test-001"}' | jq
```

Antwort ist sofortig (`{"status": "processing"}`), die Pipeline läuft asynchron
im Hintergrund: Embedding → AI-Lösung → Clustering → WebSocket-Broadcast.

---

**Lösung freigegeben**

```bash
curl -s http://localhost:8000/hooks/solution-approved \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: <dein-secret>" \
  -d '{"solution_id": "sol-001", "problem_id": "test-001"}' | jq
```

---

**Vote geändert**

```bash
curl -s http://localhost:8000/hooks/vote-changed \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: <dein-secret>" \
  -d '{
    "entity_id": "test-001",
    "entity_type": "problem"
  }' | jq
```

`new_score` ist optional — der AI-Service berechnet ihn aus `problems.vote_score`. Kann zum Testen mitgeschickt werden um den DB-Lookup zu überspringen.

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
{"type": "vote.changed", "payload": {"entity_id": "test-001", "entity_type": "problem", "new_score": 5}}
```

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
