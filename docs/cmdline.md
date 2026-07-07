# AI-Service — Command Line Testing

Alle Endpunkte des AI-Service lassen sich per `curl` testen.
Der Service muss laufen: `make dev` (lokal) oder `make docker-up` (Container).

---

## Inhalt

- [Voraussetzungen](#voraussetzungen)
- [Endpunkte](#endpunkte)
- [Backend-Endpunkte](#backend-endpunkte)
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

`SERVICE_TOKEN` ist Pflicht — ein leerer Wert bricht den Service-Start hart ab
(fail-closed, seit [Security-Audit 2026-07-05](security-audit-2026-07-05.md)). Nur mit explizitem Dev-Opt-in
`ALLOW_INSECURE_DEV=true` startet der Service ohne Token; dann kann der Header
bei Hook-Endpunkten weggelassen werden. Mit Token muss jeder Hook-Aufruf den
Header mitschicken:

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
> **Sprachnormalisierung:** Nicht-englischer Input wird vor dem Embedding via `TranslationService.to_english()` übersetzt (langdetect → LLM nur bei Nicht-Englisch). Gespeicherte Embeddings basieren auf **Titel + Beschreibung** (`title_en` + `description_en`) — ohne Normalisierung würden DE/EN-Vektoren nie den Threshold erreichen. Nach dem Quellen-Wechsel (früher description-only): `POST /embeddings/reindex`.
>
> **Dev-Threshold:** Bei weniger als ~50 Problems: `SIMILARITY_THRESHOLD=0.55` / `DUPLICATE_THRESHOLD=0.70` in `.env` setzen. Prod-Werte (0.85/0.92) sind für sparse Datasets zu streng.

---

### Solution-Similarity-Check (global)

Prüft einen Lösungs-Text gegen **alle** approved Solutions (nicht problem-scoped) via pgvector.
Kein Auth — wird vom `SolutionForm` debounced während der Eingabe aufgerufen, und als Submit-Backstop
im `solution-submitted`-Hook. `content` mind. 20, max. 2000 Zeichen.

```bash
curl -s http://localhost:8000/solution-similarity \
  -H "Content-Type: application/json" \
  -d '{"content": "Implement a quarterly AI governance review board with cross-department representatives."}' | jq
```

```json
{
  "similar_solutions": [
    {"id": "uuid-...", "problem_id": "uuid-...", "content": "...", "score": 0.94}
  ],
  "has_duplicates": false
}
```

> Embeddings werden erst bei Solution-Approval gespeichert (`embed_and_store`, englischer Canonical) —
> Admin-/`AUTO_APPROVE`-genehmigte und Alt-Solutions ohne Embedding werden daher noch nicht als
> Duplikat erkannt (Stand 2026-06-19, vgl. [`features.md`](features.md)).

---

### Query-Übersetzungs-Kandidaten (cross-linguale Suche, Multi-Kandidaten Option B)

Erweitert einen Suchbegriff in **mehrere** Kandidaten (gebeugte Formen + nahe Synonyme) in `target_lang`.
Wird ausschließlich vom Backend-Keyword-Pfad (`GET /problems?q=`) genutzt, um den Recall zu erhöhen:
jeder Kandidat wird als eigene `plainto_tsquery`-Klausel gegen den Sprach-`tsvector` OR-verknüpft.
Kein Auth. Getrennt vom Single-String-`POST /translate` (Submit-/Display-Flow bleibt unverändert).
Best-effort: deduped + auf 6 gecappt, `[]` bei LLM-Fehler (Backend fällt dann auf die rohe Query zurück).

```bash
curl -s http://localhost:8000/translate/candidates \
  -H "Content-Type: application/json" \
  -d '{"text": "missing", "target_lang": "de"}' | jq
```

```json
{ "candidates": ["fehlend", "fehlende", "vermisst"] }
```

---

### Hooks (Backend BackgroundTasks → AI-Service)

Diese Endpunkte werden vom FastAPI-Backend als BackgroundTasks aufgerufen. Für manuelle Tests
simulieren sie den Backend-Trigger.

> Realistische Testdaten (KMU-Kontext, DACH) und Spam-Szenarien: [`docs/ui-test-data.md`](ui-test-data.md)

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

**Problem neu indexieren** (Admin-Edit eines approved Problems → Re-Embedding + Re-Clustering)

```bash
curl -s http://localhost:8000/hooks/problem-reindex \
  -H "Content-Type: application/json" \
  -H "X-Service-Token: <dein-token>" \
  -d '{"problem_id": "test-001"}' | jq
```

```json
{"status": "processing"}
```

Wird vom Backend als BackgroundTask ausgelöst, wenn ein Superuser Titel oder
Beschreibung eines bereits approved Problems editiert. Läuft asynchron:
Re-Embedding → Re-Clustering → WebSocket-Broadcast.
Generiert **keine** neue KI-Lösung (die bereits vorhandene bleibt).

---

**Lösung eingereicht** (KI ist das Moderations-Gate — kein menschlicher Pflicht-Schritt)

Sauberer LLM-Befund **und** kein Duplikat → sofort `approved` (Embedding wird gespeichert,
Solution erscheint live). Bemängelt → `needs_review` (Admin-Queue, **kein** Auto-Reject).

```bash
curl -s http://localhost:8000/hooks/solution-submitted \
  -H "Content-Type: application/json" \
  -H "X-Service-Token: <dein-token>" \
  -d '{
    "solution_id": "sol-001",
    "problem_id": "test-001",
    "content": "Implement a quarterly AI governance review board with cross-department representatives.",
    "submitted_at": null
  }' | jq
```

```json
{"status": "approved"}
```

Bemängelte Lösung (→ `needs_review` statt früher `rejected` — die KI lehnt nicht hart ab):
```bash
-d '{"solution_id": "sol-002", "problem_id": "test-001", "content": "I agree. See above.", "submitted_at": null}'
```

```json
{"status": "needs_review", "reason": "placeholder content with no actionable substance"}
```

Globaler Duplikat-Check (über **alle** approved Solutions): Score > `duplicate_threshold` ohne
`"signals": ["duplicate_confirmed"]` → `{"status": "needs_review", "reason": "possible_duplicate"}`.
LLM-Provider down → fail-safe `{"status": "needs_review", "reason": "moderation_error"}`.

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
# Komfort-Wrapper (apps/backend) — SERVICE_TOKEN aus .env, Token wird nie ausgegeben
# (URL kommt NICHT aus der .env: dort steht die interne Backend→AI-Route, nicht der Proxy)
make ai-reindex                              # Default: nginx-Proxy http://int.decisionmap.ai/api
make ai-reindex URL=http://ai-service:8000   # Prod-Override (ai-service-Container)
make ai-reindex URL=http://localhost:8000    # AI-Service direkt (ohne Proxy)

# oder direkt das Script (run-Subcommand Pflicht; --help/no-arg zeigt Hilfe):
bash scripts/ai-reindex.sh run --token <token> --url http://localhost:8000

# oder roh per curl:
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

### KI-Entwurf generieren

Generiert einen Markdown-Draft für einen Lösungsansatz. User-triggered, kein Auto-Generieren.
Kein Auth erforderlich (wie Similarity-Check). nginx Rate Limit: 5r/min per IP, Burst=1.

```bash
curl -s -X POST http://localhost:8000/generate-solution \
  -H "Content-Type: application/json" \
  -d '{"problem_id": "test-001", "lang": "de"}' | jq
```

```json
{
  "draft": "## Lösungsansatz\n\n**Empfehlung:**...",
  "truncated": false
}
```

Draft wird auf 2000 Zeichen gekürzt (`truncated: true` wenn abgeschnitten).
Via nginx: `POST /api/generate-solution` (Port 80/443).

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
{"type": "problem.approved", "payload": {"id": "test-001"}}
{"type": "clustering.started", "payload": {}}
{"type": "clustering.completed", "payload": {"clusters_updated": 5}}
```

Vote-Events kommen über den Backend-WebSocket (`useBackendRealtime`, Port 8001) — nicht über den AI-Service-WS.

[↑ Inhalt](#inhalt)

---

## Backend-Endpunkte

Endpunkte des FastAPI-Backends (Port 8001).

### Problems — Keyset-Pagination + Server-Suche (Server-Driven Search Phase 1)

`GET /problems` liefert eine paginierte Seite `{ items, next_cursor, total }` (kein komplettes
Set mehr). `limit` default 50 (Cap 100); `next_cursor` der Vorseite an `cursor` weiterreichen.

```bash
# Erste Seite, nach Votes sortiert
curl -s "http://localhost:8001/problems?sort=votes&limit=50" | jq '{total, next: .next_cursor, n: (.items|length)}'

# Cross-linguale Keyword-Suche: Query wird pro Sprache in mehrere Kandidaten übersetzt
# (POST /translate/candidates — gebeugte Formen + Synonyme), je Kandidat OR gegen den FTS-tsvector
# — q=missing und q=fehlend liefern dieselbe Menge (#32, Multi-Kandidaten Option B)
curl -s "http://localhost:8001/problems?q=missing" | jq '.items[].title'

# Semantische Suche (Embedding-Distanz; ignoriert sort, exklusiv zu q)
# items[].score = 1 − Distanz, auf [0,1] geklemmt (Relevanz, nur im Semantik-Modus gesetzt; sonst null)
curl -s "http://localhost:8001/problems?semantic=poor%20data%20quality" | jq '{total, scores: [.items[].score]}'

# Server-Filter: Cluster-Subtree (AND), Regionen (OR), user, company
# user/company sind komma-separiert multi-value: user → IN, company → case-insensitive ILIKE-OR
# company ist Ganzwert-ILIKE ohne Wildcards — vollständiger, exakter Firmenname nötig (Live-Verify F1)
curl -s "http://localhost:8001/problems?tags=<tagId>&regions=<regId>&company=Acme%20Manufacturing%20GmbH,NordBank%20AG" | jq '.total'

# Nach Cluster-/Struktur-Tag-Namen sortieren, aufsteigend (bidirektional via dir)
curl -s "http://localhost:8001/problems?sort=tag&dir=asc&limit=50" | jq '.items[].title'

# Nach Firma des Autors sortieren (Company-Spalte der Table); jedes Item trägt company + author_display_name
curl -s "http://localhost:8001/problems?sort=company&dir=asc&limit=50" | jq '.items[] | {title, company, author_display_name}'
```

> `sort`: `created` (default) / `votes` / `title` / `solutions` / `status` / `tag` / `company` / `relevance` (Keyset pro Modus, über alle Seiten gruppiert). `tag` sortiert nach dem Struktur-/Cluster-Tag-Namen (`''`-Bucket für unclustered); `company` nach der Firma des Autors (`coalesce(User.company,'')`, `''`-Bucket für anonym/firmenlos). `relevance` ist opt-in und greift nur mit `q` (Σ `ts_rank` über die FTS-Registry-Sprachen; ohne `q` Fallback auf `created`). Jedes Item trägt die Autor-Profilfelder `company` (Firma) und `author_display_name` (öffentlicher Name; beide pro Seite via `_load_authors` gebatcht, `null` für anonyme Autoren oder ohne gesetzten Namen) — so rendert das Detail-Panel Firma **und** Autor ohne clientseitigen User-Lookup.
> `dir`: `asc` | `desc` — server-seitig für **jeden** Modus wirksam; fehlt `dir`, gilt der Default je Modus (`created`/`votes`/`solutions` desc, `title`/`status`/`tag` asc), ungültiger Wert → `422`. Die Richtung reist im Cursor mit (Seite 2+ behält sie, `dir` wird dann ignoriert).
> `status_filter != approved` erfordert Superuser — inkl. `status_filter=all` (keine Status-Einschränkung; die Admin-Table nutzt es, um alle
> Status zu sehen). `GET /problems/{id}` (analog `GET /solutions/{id}`) liefert für nicht-`approved` Einträge **404** statt 403,
> außer Superuser/Owner — Existenz wird Dritten nie bestätigt ([Security-Audit 2026-07-05](security-audit-2026-07-05.md), BE-06).
> Folgeseite: `?cursor=<next_cursor>` (max. 64 KiB, darüber `422` — BE-09). Der Graph nutzt seit Phase 2 (Task 2.3) `GET /problems/cluster-summary`
> (s.u.) + lazy Drill-Down über `GET /problems?tags=`. Der Übergangs-Endpoint `GET /problems/all` ist seit Task 2.4
> entfernt (samt Data-Layer-`fetchAllProblems`/`fetchProblems`). Contract: [`features.md → Sprachunabhängige Suche`](features.md).

---

### Graph-Cluster-Aggregat (Server-Driven Search Phase 2, Task 2.1)

`GET /problems/cluster-summary` liefert das Graph-Übersichts-Aggregat, ohne alle Problems zu laden —
Basis für den Graph-Drill-Down, der den (seit Task 2.4 entfernten) `GET /problems/all` ablöst. Kein Auth (öffentlich lesbar wie die
approved-Liste). Route ist **vor** `/{problem_id}` deklariert (Shadow-Route-Guard wie `/all` + `/search`).

```bash
curl -s http://localhost:8001/problems/cluster-summary | jq
```

```json
{
  "max_vote_score": 42,
  "clusters": [
    {"tag_id": "uuid-...", "problem_count": 7}
  ],
  "unclustered_count": 3
}
```

> `max_vote_score`: `MAX(vote_score)` über approved, nicht-gelöschte Problems. `clusters`: ein Eintrag pro
> Struktur-Tag (`level < 10`) mit dem **Subtree**-Count (Problem trägt das Tag **oder** einen Nachfahren — selbes
> BFS `_subtree_tag_ids` wie der `tags`-Filter, portabel SQLite + Postgres). `unclustered_count`: approved
> Problems ganz ohne Struktur-Tag. User-Tags (`level = 10`) zählen nicht als Cluster.

---

### Geo-Detection

Ermittelt Land + Region des Clients server-seitig via `ip-api.com` — vermeidet CORS-Restriktionen auf HTTP-Origins (`ipapi.co` hat zu strenge Rate Limits). Nutzt `X-Forwarded-For` Header (gesetzt von nginx).

```bash
curl -s http://localhost:8001/regions/geo | jq
```

```json
{"country_code": null, "region_code": null}
```

`null` ist erwartetes Verhalten beim lokalen curl-Aufruf — Backend überspringt die Geo-Lookup für Loopback-Adressen (`127.0.0.1`, `::1`). Auch private LAN-IPs (RFC-1918: `192.168.x.x`, `10.x.x.x`) werden von `ip-api.com` nicht geolocated → ebenfalls `null`. Region-Vorauswahl via Geo-Detection ist daher ein **Production-only Feature**. Im Browser via nginx mit echter Public-IP liefert der Endpoint die Client-Region.

---

### Solution bearbeiten (Owner + Superuser)

`PATCH /solutions/:id` — erlaubt Inhalt-Edit für den Owner (→ `needs_review`) oder Superuser (Status bleibt unverändert).

Auth läuft über das HttpOnly-Cookie (seit 2026-07-06 kein Bearer-Token mehr) — Login setzt das
Cookie, curl braucht dafür einen Cookie-Jar (`-c` speichern, `-b` mitsenden):

```bash
# Login — setzt das Auth-Cookie in den Jar (kein Token im Response-Body)
curl -s -c /tmp/dm-cookies.txt -X POST http://localhost:8001/auth/jwt/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'username=<email>&password=<passwort>' > /dev/null

curl -s -b /tmp/dm-cookies.txt -X PATCH http://localhost:8001/solutions/<uuid> \
  -H "Content-Type: application/json" \
  -d '{"content": "Überarbeiteter Inhalt — mindestens 20 Zeichen."}' | jq
```

Constraints: `content` min 20, max 2000 Zeichen. Fehlende oder zu kurze Inhalte → `422 Unprocessable Entity`.

[↑ Inhalt](#inhalt)

---

## API-Dokumentation (Browser)

FastAPI stellt automatisch eine interaktive OpenAPI-UI bereit:

```
http://localhost:8000/docs       # Swagger UI — AI-Service, alle Endpunkte testbar
http://localhost:8001/docs       # Swagger UI — Backend, alle Endpunkte testbar
http://localhost:8000/openapi.json  # Raw OpenAPI-Schema (AI-Service)
```

Alle Request-Body-Schemas, Validierungsregeln und Response-Typen sind dort
vollständig dokumentiert.

```bash
# Alle Endpunkte als Liste
curl -s http://localhost:8000/openapi.json | jq '.paths | keys'
curl -s http://localhost:8001/openapi.json | jq '.paths | keys'
```
