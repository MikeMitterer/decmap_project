# Lokale Entwicklungsumgebung

## Voraussetzungen

| Tool | Zweck | Version |
|---|---|---|
| Docker + Docker Compose V2 | Postgres, Directus, Mailpit | `docker compose` (Plugin), nicht `docker-compose` |
| Node.js | Frontend (Nuxt) | 20+ |
| Python | AI-Service (FastAPI) | 3.11+ |
| overmind | Prozess-Manager für Procfile | `brew install overmind` |
| `DEV_LOCAL` | Zeigt auf lokales Dev-Verzeichnis mit BashLib/MakeLib | Env-Variable |

**Docker Compose V2 auf Ubuntu:** Das Ubuntu-Paket `docker.io` liefert kein `docker compose` (V2).
Offizielles Docker-Repository + `docker-compose-plugin` installieren.

---

## Architektur der lokalen Umgebung

```
make dev-up
    ├── make -C apps/backend dev-up          → Docker Compose (docker-compose.dev.yml)
    │       ├── decisionmap-postgres :5432   (pgvector/pgvector:pg16)
    │       ├── decisionmap-directus :8055   (directus/directus:11)
    │       └── decisionmap-directus-seed    (einmaliger Seed-Run)
    │
    └── overmind start -f Procfile.dev
            ├── frontend   → npm --prefix apps/frontend run dev    :5000
            └── aiservice  → uvicorn main:app --reload             :8000
```

Mailpit läuft separat (z.B. auf Unraid oder lokal) — nicht Teil von `make dev-up`.

**Ports:**

| Service | Port | URL |
|---|---|---|
| Frontend (Nuxt dev) | 5000 | http://localhost:5000 |
| Directus (CMS) | 8055 | http://localhost:8055 |
| AI-Service (FastAPI) | 8000 | http://localhost:8000 |
| PostgreSQL | 5432 | localhost:5432 |
| Mailpit (SMTP-Sink) | 8025 | http://localhost:8025 (separat) |

---

## Starten und Stoppen

```bash
# Alles starten (Docker + Frontend + AI-Service)
make dev-up

# Docker-Services stoppen (Frontend + AI-Service werden via Ctrl+C in overmind gestoppt)
make dev-down

# Einzeln starten (ohne overmind)
make -C apps/backend dev-up    # nur Docker
make -C apps/frontend dev      # nur Frontend
make -C apps/ai-service dev    # nur AI-Service
```

`make dev-up` blockiert im Terminal (overmind läuft im Vordergrund). Ctrl+C stoppt alle
Prozesse in overmind — Docker-Container laufen weiter bis `make dev-down`.

---

## Ersteinrichtung (neues Dev-Gerät)

```bash
# 1. Sub-Repos auschecken
git clone ... apps/backend
git clone ... apps/frontend
git clone ... apps/ai-service

# 2. Workspace-Symlinks
make setup   # .libs/BashLib, .libs/BashTools, .libs/MakeLib → DEV_LOCAL

# 3. AI-Service venv erstellen
cd apps/ai-service
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
cd ../..

# 4. .env-Dateien anlegen (aus .env.example)
cp apps/backend/.env.example    apps/backend/.env
cp apps/frontend/.env.example   apps/frontend/.env
cp apps/ai-service/.env.example apps/ai-service/.env
# → Werte eintragen (DB-Credentials, API-Keys, Directus-Token etc.)

# 5. Stack starten
make dev-up

# 6. DB initialisieren (einmalig, nach erstem Start)
make -C apps/backend db-reset
```

### Wichtige .env-Variablen für lokale Entwicklung

**`apps/backend/.env`** (Directus):
```env
WEBSOCKETS_ENABLED=true        # Pflicht — sonst kein Live-Vote-Update
WEBSOCKETS_REST_AUTH=public    # Anonyme WS-Subscriptions erlauben
```

**`apps/frontend/.env`**:
```env
USE_FAKE_DATA=false            # true = kein Backend nötig (UI-Entwicklung)
```

---

## Fake-Daten vs. echte Daten

```env
USE_FAKE_DATA=true   # In-Memory-Daten, kein Backend nötig — ideal für reine UI-Arbeit
USE_FAKE_DATA=false  # Echter Directus + AI-Service
```

Beide Layer implementieren dasselbe Interface — kein Unterschied für Komponenten.
Seed-Daten synchron halten:

```bash
make fakedata-sync   # data/*.json → apps/frontend (camelCase) + apps/ai-service/tests/fakedata/
```

`data/*.json` (snake_case, UUIDs) sind die einzige Quelle der Wahrheit — nie direkt in
Consumer-Repos editieren.

---

## Echtzeit-Updates — Grundanforderung

> **Live-Updates im UI sind eine Grundanforderung, keine optionale Funktion.**
> Wenn User A votet, muss User B den aktualisierten Score sehen — ohne Page-Reload.
> Diese Funktionalität muss auch dann funktionieren, wenn der AI-Service nicht läuft.

### Zwei WebSocket-Quellen

| Composable | WebSocket-Quelle | Verantwortlich für |
|---|---|---|
| `useDirectusRealtime.ts` | Directus WS (`/websocket`) | Vote-Score-Updates (`problems.vote_score`) |
| `useRealtimeUpdates.ts` | AI-Service WS (`/ws`) | AI-Events: `problem.approved`, `cluster.updated`, `solution.generated` |

### Vote-Score-Flow

```
User klickt Vote
      ↓
POST /items/votes  (Directus REST)
      ↓
PostgreSQL Trigger trg_vote_score
      ↓ (synchron)
problems.vote_score inkrementiert
      ↓
Directus Flow "Vote Score Broadcast"
      ↓  (ItemsService.updateOne — löst WS-Event aus)
Directus WebSocket → alle verbundenen Clients
      ↓
useDirectusRealtime.ts → applyVoteScore(id, voteScore)
      ↓
UI aktualisiert sich live (kein Reload)
```

**Sofort-Feedback für den votenden User:**
Nach `submitVote()` ruft `handleVote()` in `ProblemPanel.vue` sofort `fetchProblemById()`
auf — zeigt den echten DB-Wert ohne auf den WS-Event zu warten.

### Kritische Voraussetzungen

1. **`WEBSOCKETS_ENABLED=true`** in `apps/backend/.env`
2. **`WEBSOCKETS_REST_AUTH=public`** in `apps/backend/.env`
3. **`connect()` explizit in `onMounted` aufrufen** — beide Composables verbinden sich
   nicht automatisch. Fehlt der Call, bleibt der Socket stumm (kein Fehler, kein Event).
4. **Directus Flow "Vote Score Broadcast"** muss angelegt sein:
   ```bash
   make -C infrastructure setup-vote-flow
   # Neu anlegen (falls bereits vorhanden):
   make -C infrastructure setup-vote-flow -- --force
   ```

### nginx (Produktion)

Für Directus WebSocket hinter nginx muss der `cms.decisionmap.ai`-Serverblock Upgrade-Headers weiterleiten:

```nginx
server {
    server_name cms.decisionmap.ai;
    location / {
        proxy_pass http://directus:8055;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Ohne diese Header schlägt der WS-Handshake lautlos fehl.

---

## AI-Service venv-Gotcha

Das venv enthält absolute Pfade in Shebangs. Wenn das Repo verschoben wird (z.B. von
`DecisionMap/ai-service/` nach `DecisionMap/apps/ai-service/`), ist das venv kaputt:

```
bad interpreter: /old/path/.venv/bin/python3.1: No such file or directory
```

**Fix:** venv neu erstellen:
```bash
cd apps/ai-service
rm -rf .venv
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
```

---

## Procfile.dev

```
frontend:  npm --prefix apps/frontend run dev
aiservice: apps/ai-service/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --reload --app-dir apps/ai-service
```

Alle Pfade relativ zum Workspace-Root (`DecisionMap/`). overmind muss aus dem
Workspace-Root gestartet werden (das tut `make dev-up` automatisch).
