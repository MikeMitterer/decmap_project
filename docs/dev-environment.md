# Lokale Entwicklungsumgebung

## Inhalt

- [Voraussetzungen](#voraussetzungen)
- [Architektur der lokalen Umgebung](#architektur-der-lokalen-umgebung)
- [Starten und Stoppen](#starten-und-stoppen)
- [Ersteinrichtung (neues Dev-Gerät)](#ersteinrichtung-neues-dev-gerät)
- [Fake-Daten vs. echte Daten](#fake-daten-vs-echte-daten)
- [Echtzeit-Updates — Grundanforderung](#echtzeit-updates-grundanforderung)
- [AI-Service venv-Gotcha](#ai-service-venv-gotcha)
- [Procfile.dev](#procfiledev)

---

## Voraussetzungen

| Tool | Zweck | Version |
|---|---|---|
| Docker + Docker Compose V2 | Postgres, Backend-API, Mailpit, Adminer | `docker compose` (Plugin), nicht `docker-compose` |
| Node.js | Frontend (Nuxt) | 20+ |
| Python | AI-Service (FastAPI) | 3.11+ |
| overmind | Prozess-Manager für Procfile | `brew install overmind` |
| `DEV_LOCAL` | Zeigt auf lokales Dev-Verzeichnis mit BashLib/MakeLib | Env-Variable |

**Docker Compose V2 auf Ubuntu:** Das Ubuntu-Paket `docker.io` liefert kein `docker compose` (V2).
Offizielles Docker-Repository + `docker-compose-plugin` installieren.

[↑ Inhalt](#inhalt)

---

## Architektur der lokalen Umgebung

```
make dev-up
    ├── docker compose -f infrastructure/docker-compose.dev.yml up -d
    │       └── decisionmap-nginx-dev :80    (nginx-Reverse-Proxy, Dev-Config)
    │
    ├── make -C apps/backend dev-up          → Docker Compose (docker-compose.dev.yml)
    │       ├── decisionmap-postgres :5432   (pgvector/pgvector:pg16)
    │       ├── decisionmap-backend-api :8001 (FastAPI + Alembic auto-migrate)
    │       ├── decisionmap-mailpit :8025    (SMTP-Sink)
    │       └── decisionmap-adminer :8080    (DB-UI)
    │
    └── overmind start -f Procfile.dev
            ├── frontend   → npm --prefix apps/frontend run dev    :3000
            └── aiservice  → uvicorn main:app --reload             :8000
```

Mailpit und Adminer laufen im Backend-Docker-Compose — Teil von `make -C apps/backend dev-up`.

**Ports (direkt):**

| Service | Port | URL |
|---|---|---|
| nginx Dev-Proxy | 80 | http://int.decisionmap.ai |
| Frontend (Nuxt dev) | 3000 | http://localhost:3000 |
| Backend-API (FastAPI) | 8001 | http://localhost:8001 — `GET /` → 307 → `/docs` (Swagger) |
| AI-Service (FastAPI) | 8000 | http://localhost:8000 |
| PostgreSQL | 5432 | localhost:5432 |
| Mailpit (SMTP-Sink) | 8025 | http://localhost:8025 |
| Adminer (DB-UI) | 8080 | http://localhost:8080 — Server: `postgres`, DB/User/PW: `decisionmap` |

**Via nginx-Proxy (`int.decisionmap.ai`):**

| URL | Ziel |
|---|---|
| http://int.decisionmap.ai | Frontend (Nuxt dev) |
| http://backend.int.decisionmap.ai | Backend API (FastAPI) — öffnet Swagger direkt |
| http://int.decisionmap.ai/api/docs | AI-Service (FastAPI Swagger) |

[↑ Inhalt](#inhalt)

---

## Starten und Stoppen

```bash
# Alles starten (nginx-Proxy + Docker + Frontend + AI-Service)
make dev-up

# Alles stoppen (overmind quit + Docker runterfahren)
make dev-down

# nginx Dev-Proxy
make dev-nginx-reload   # Config neu laden (ohne Container-Restart)
make dev-nginx-logs     # Proxy-Logs verfolgen

# Einzeln starten (ohne overmind)
make -C apps/backend dev-up    # nur Docker
make -C apps/frontend dev      # nur Frontend
make -C apps/ai-service dev    # nur AI-Service
```

`make dev-up` blockiert im Terminal (overmind läuft im Vordergrund). `make dev-down` aus
einem zweiten Terminal-Tab aufrufen — oder Ctrl+C in overmind und danach
`make -C apps/backend dev-down && docker compose -f infrastructure/docker-compose.dev.yml down`.

> **Gotcha `.overmind.sock`:** Bricht overmind unerwartet ab (Crash, Ctrl+C), bleibt
> `.overmind.sock` liegen. Der nächste `make dev-up` schlägt dann fehl, weil overmind
> das Socket noch belegt sieht. `make dev-down` räumt das Socket automatisch auf
> (`rm -f .overmind.sock`).

[↑ Inhalt](#inhalt)

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
# → Werte eintragen (DB-Credentials, SECRET_KEY, SERVICE_TOKEN etc.)

# 5. DNS-Einträge setzen (einmalig, /etc/hosts oder lokaler DNS)
# 192.168.0.25  int.decisionmap.ai
# 192.168.0.25  backend.int.decisionmap.ai

# 6. Stack starten
make dev-up

# 7. DB initialisieren (einmalig, nach erstem Start)
make -C apps/backend db-reset
```

### DNS-Voraussetzung (`int.decisionmap.ai`)

Die lokalen Dev-URLs müssen auf die IP-Adresse des Dev-Rechners zeigen — per `/etc/hosts`
oder lokalem DNS (z.B. Unraid-DNS, Pi-hole, Adguard Home):

```
# /etc/hosts (oder lokaler DNS-Server)
192.168.0.25  int.decisionmap.ai
192.168.0.25  backend.int.decisionmap.ai
```

Die `docker-compose.dev.yml` konfiguriert nginx als Reverse-Proxy auf Port 80.
nginx erreicht Nuxt via `host.docker.internal:3000` — Nuxt muss daher auf `0.0.0.0`
binden (nicht nur `localhost`). Das Procfile.dev setzt `PORT=3000`; falls Nuxt trotzdem
nur auf `127.0.0.1` horcht, `NUXT_HOST=0.0.0.0` ergänzen.

### Wichtige .env-Variablen für lokale Entwicklung

**`apps/backend/.env`**:
```env
DATABASE_URL=postgresql+asyncpg://decisionmap:decisionmap@localhost:5432/decisionmap
SECRET_KEY=dev-secret-key-change-in-production
FRONTEND_URL=http://localhost:3000    # Basis-URL für E-Mail-Links (Verify, Reset, Magic Link)
MAIL_SUPPRESS=true                    # kein echter E-Mail-Versand in Dev
EMAIL_FROM=noreply@decisionmap.ai     # Darf keine .local-Domain sein — Backend startet sonst nicht
SERVICE_TOKEN=dev-service-token       # Shared Secret apps/backend ↔ apps/ai-service
AI_SERVICE_URL=http://localhost:8000  # Docker löst localhost:8000 als host.docker.internal auf
```

> **Gotcha `EMAIL_FROM`:** Ist `EMAIL_FROM` auf eine `.local`-Domain gesetzt (z.B. `noreply@decisionmap.local`),
> startet das Backend nicht. Immer eine gültige Domain verwenden, auch in Dev mit `MAIL_SUPPRESS=true`.

> **Gotcha `AI_SERVICE_URL` in Docker:** Der Backend-Container läuft in Docker, der AI-Service lokal.
> `http://localhost:8000` im Backend-Container würde den Container selbst ansprechen.
> Die `docker-compose.dev.yml` löst das via `extra_hosts: host.docker.internal:host-gateway` —
> `localhost` im Container wird automatisch auf `host.docker.internal` umgeschrieben.

**`apps/frontend/.env`**:
```env
BACKEND_URL=http://localhost:8001     # FastAPI Backend
USE_FAKE_DATA=false                   # true = kein Backend nötig (UI-Entwicklung)
DEV_TOOLS=true                        # Dev-Tools-Seite (/dev-tools) — Erfordert Admin-Login
```

[↑ Inhalt](#inhalt)

---

## Fake-Daten vs. echte Daten

```env
USE_FAKE_DATA=true   # In-Memory-Daten, kein Backend nötig — ideal für reine UI-Arbeit
USE_FAKE_DATA=false  # Echter FastAPI-Backend + AI-Service
```

Beide Layer implementieren dasselbe Interface — kein Unterschied für Komponenten.

[↑ Inhalt](#inhalt)

---

## Echtzeit-Updates — Grundanforderung

> **Live-Updates im UI sind eine Grundanforderung, keine optionale Funktion.**
> Wenn User A votet, muss User B den aktualisierten Score sehen — ohne Page-Reload.
> Diese Funktionalität muss auch dann funktionieren, wenn der AI-Service nicht läuft.

### Zwei WebSocket-Quellen

| Composable | WebSocket-Quelle | Verantwortlich für |
|---|---|---|
| `useBackendRealtime.ts` | Backend WS `ws://localhost:8001/ws` | Mutations: Vote-Scores, Problem/Solution CRUD |
| `useRealtimeUpdates.ts` | AI-Service WS (`/ws`) | AI-Events: `problem.approved`, `cluster.updated`, `solution.generated` |

### Vote-Score-Flow

```
User klickt Vote
      ↓
POST /votes  (FastAPI Backend, Port 8001)
      ↓
Backend berechnet neuen vote_score (Toggle-Semantik)
      ↓
Response enthält aktualisierten vote_score direkt — kein Re-Fetch nötig
      ↓  (Backend feuert WS-Event)
Backend WebSocket /ws → alle verbundenen Clients
      ↓
useBackendRealtime.ts → applyProblemUpdate(update)
      ↓
UI aktualisiert sich live (kein Reload)
```

**Vote-Toggle-Semantik:** Gleiche Richtung wie vorhandenes Vote → zurückziehen (delta = -1).
Entgegengesetzte Richtung → Flip (delta = ±2). Neues Vote → delta = ±1.

**Sofort-Feedback:** `ProblemPanel.vue` aktualisiert den Score direkt aus dem Response-Body —
zeigt echten DB-Wert ohne auf WS-Event zu warten.

### Kritische Voraussetzungen

1. **`connect()` explizit in `onMounted` aufrufen** — beide Composables verbinden sich
   nicht automatisch. Fehlt der Call, bleibt der Socket stumm (kein Fehler, kein Event).
2. **Backend läuft auf Port 8001** — WS-Endpoint: `ws://localhost:8001/ws`.

### Voting-Zustand für Tests zurücksetzen

Die Dev-Tools-Seite (`http://int.decisionmap.ai/dev-tools`, aktiviert via `DEV_TOOLS=true` in `apps/frontend/.env`) bietet zwei Werkzeuge:

| Werkzeug | Aktion | Auth |
|---|---|---|
| **Vote-Cache leeren** | Löscht `localStorage.decisionmap_votes` — Browser verhält sich danach wie ein frischer User | Nicht erforderlich |
| **DB-Votes zurücksetzen** | Löscht alle DB-Einträge in `votes` + setzt alle `vote_score`-Werte auf 0 | Admin-Login erforderlich |

Alternativ direkt im Browser (Konsole):
```javascript
localStorage.removeItem('decisionmap_votes')
```

Danach kann beliebig oft gevoted werden — nützlich für manuelle Tests des Vote-Flows.

### nginx (Produktion)

Der `api.decisionmap.ai`-Serverblock muss WebSocket-Upgrade-Headers weiterleiten:

```nginx
server {
    server_name api.decisionmap.ai;
    location / {
        proxy_pass http://backend:8001;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;   # Pflicht — default 60s bricht WS-Verbindung bei Stille
    }
}
```

Ohne Upgrade-Header schlägt der WS-Handshake lautlos fehl.
Ohne `proxy_read_timeout 3600s` wird die Verbindung nach 60 s Inaktivität getrennt.

[↑ Inhalt](#inhalt)

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

[↑ Inhalt](#inhalt)

---

## Procfile.dev

```
frontend:  PORT=3000 npm --prefix apps/frontend run dev
aiservice: bash -c 'cd apps/ai-service && .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --reload'
```

Alle Pfade relativ zum Workspace-Root (`DecisionMap/`). overmind muss aus dem
Workspace-Root gestartet werden (das tut `make dev-up` automatisch).

> **Gotcha `uvicorn --app-dir` vs `.env`:** `--app-dir` setzt nur den Python-Suchpfad für
> das Modul — das Working Directory bleibt der Workspace-Root. python-dotenv sucht `.env`
> aber im CWD, nicht in `--app-dir`. Deshalb `bash -c 'cd apps/ai-service && uvicorn ...'`
> statt `uvicorn ... --app-dir apps/ai-service`. Fehlt das, findet der AI-Service seinen
> OpenAI-Key und andere `.env`-Werte nicht — Similarity-Requests schlagen still fehl.

**Port 3000 (nicht 5000):** Auf macOS belegt AirPlay Receiver `0.0.0.0:5000` — Nuxt würde
auf 5000 starten, der Port ist aber bereits belegt. `PORT=3000` explizit setzen vermeidet
den Konflikt und stellt sicher, dass nginx via `host.docker.internal:3000` erreichbar ist.
