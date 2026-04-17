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
| Docker + Docker Compose V2 | Postgres, Directus, Mailpit | `docker compose` (Plugin), nicht `docker-compose` |
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
    │       ├── decisionmap-directus :8055   (directus/directus:11)
    │       └── decisionmap-directus-seed    (einmaliger Seed-Run)
    │
    └── overmind start -f Procfile.dev
            ├── frontend   → npm --prefix apps/frontend run dev    :3000
            └── aiservice  → uvicorn main:app --reload             :8000
```

Mailpit läuft separat (z.B. auf Unraid oder lokal) — nicht Teil von `make dev-up`.

**Ports (direkt):**

| Service | Port | URL |
|---|---|---|
| nginx Dev-Proxy | 80 | http://int.decisionmap.ai |
| Frontend (Nuxt dev) | 3000 | http://localhost:3000 |
| Directus (CMS) | 8055 | http://localhost:8055 |
| AI-Service (FastAPI) | 8000 | http://localhost:8000 |
| PostgreSQL | 5432 | localhost:5432 |
| Mailpit (SMTP-Sink) | 8025 | http://localhost:8025 (separat) |

**Via nginx-Proxy (`int.decisionmap.ai`):**

| URL | Ziel |
|---|---|
| http://int.decisionmap.ai | Frontend (Nuxt dev) |
| http://cms.int.decisionmap.ai/admin | Directus Admin |
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
# → Werte eintragen (DB-Credentials, API-Keys, Directus-Token etc.)

# 5. DNS-Einträge setzen (einmalig, /etc/hosts oder lokaler DNS)
# 192.168.0.25  int.decisionmap.ai
# 192.168.0.25  cms.int.decisionmap.ai

# 6. Stack starten
make dev-up

# 7. DB initialisieren (einmalig, nach erstem Start)
make -C apps/backend db-reset

# 8. Directus-Permissions setzen (einmalig, nach db-reset)
make -C apps/backend db-permissions
```

### DNS-Voraussetzung (`int.decisionmap.ai`)

Die lokalen Dev-URLs (`int.decisionmap.ai`, `cms.int.decisionmap.ai`) müssen auf
die IP-Adresse des Dev-Rechners zeigen — entweder per `/etc/hosts` oder via lokalem DNS
(z.B. Unraid-DNS, Pi-hole, Adguard Home):

```
# /etc/hosts (oder lokaler DNS-Server)
192.168.0.25  int.decisionmap.ai
192.168.0.25  cms.int.decisionmap.ai
```

Die `docker-compose.dev.yml` konfiguriert nginx als Reverse-Proxy auf Port 80.
nginx erreicht Nuxt via `host.docker.internal:3000` — Nuxt muss daher auf `0.0.0.0`
binden (nicht nur `localhost`). Das Procfile.dev setzt `PORT=3000`; falls Nuxt trotzdem
nur auf `127.0.0.1` horcht, `NUXT_HOST=0.0.0.0` ergänzen.

### Wichtige .env-Variablen für lokale Entwicklung

**`apps/backend/.env`** (Directus):
```env
WEBSOCKETS_ENABLED=true                                    # Pflicht — sonst kein Live-Vote-Update
WEBSOCKETS_REST_AUTH=public                                # Anonyme WS-Subscriptions erlauben
PUBLIC_URL=http://cms.int.decisionmap.ai                   # Pflicht — Directus CORS + Auth-Mails
CORS_ORIGIN=http://int.decisionmap.ai                      # Frontend-Origin erlauben
USER_REGISTER_URL_ALLOW_LIST=http://int.decisionmap.ai/verify-email  # E-Mail-Verifizierungslink
```

**`apps/frontend/.env`**:
```env
USE_FAKE_DATA=false            # true = kein Backend nötig (UI-Entwicklung)
DEV_TOOLS=true                 # Dev-Tools-Seite (/dev-tools) aktivieren — in .env.example leer lassen
                               # Erfordert Admin-Login — ohne Login werden Tools ausgeblendet
```

[↑ Inhalt](#inhalt)

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

[↑ Inhalt](#inhalt)

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
GET /items/{collection}/{id}?fields=vote_score  (aktuellen Score laden)
      ↓
PATCH /items/{collection}/{id}  { vote_score: n+1 }  (via Directus REST)
      ↓  (löst Directus WS-Event aus)
Directus WebSocket → alle verbundenen Clients
      ↓
useDirectusRealtime.ts → applyProblemUpdate(update)
      ↓
UI aktualisiert sich live (kein Reload)
```

> **Kein PostgreSQL-Trigger:** `trg_vote_score` / `fn_update_vote_score()` wurden entfernt.
> Der Score wird stattdessen per REST API berechnet und via `PATCH` geschrieben — Directus
> löst dabei automatisch WS-Events aus. Voraussetzung: `update`-Permission auf `vote_score`
> für die Public-Policy (`make -C apps/backend db-permissions`).

**Sofort-Feedback für den votenden User:**
Nach `submitVote()` ruft `handleVote()` in `ProblemPanel.vue` sofort `fetchProblemById()`
auf — zeigt den echten DB-Wert ohne auf den WS-Event zu warten.

### Kritische Voraussetzungen

1. **`WEBSOCKETS_ENABLED=true`** in `apps/backend/.env`
2. **`WEBSOCKETS_REST_AUTH=public`** in `apps/backend/.env`
3. **`PUBLIC_URL=http://cms.int.decisionmap.ai`** in `apps/backend/.env` — Directus prüft die
   Origin gegen PUBLIC_URL. Stimmt sie nicht überein, verwirft Directus die WS-Verbindung
   nach ~3 s lautlos (Reconnect-Loop). Zusammen mit `CORS_ORIGIN=http://int.decisionmap.ai` setzen.
4. **`connect()` explizit in `onMounted` aufrufen** — beide Composables verbinden sich
   nicht automatisch. Fehlt der Call, bleibt der Socket stumm (kein Fehler, kein Event).
5. **Directus Flow "Vote Score Broadcast"** muss angelegt sein:
   ```bash
   make -C infrastructure setup-vote-flow
   # Neu anlegen (falls bereits vorhanden):
   make -C infrastructure setup-vote-flow -- --force
   ```

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

Für Directus WebSocket hinter nginx muss der `cms.decisionmap.ai`-Serverblock Upgrade-Headers weiterleiten:

```nginx
server {
    server_name cms.decisionmap.ai;
    location / {
        proxy_pass http://directus:8055;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;   # Pflicht — default 60s bricht WS-Verbindung bei Stille
    }
}
```

Ohne Upgrade-Header schlägt der WS-Handshake lautlos fehl.
Ohne `proxy_read_timeout 3600s` wird die Verbindung nach 60 s Inaktivität getrennt —
auch wenn Directus Pings schickt (Ping-Intervall kann > 60 s sein).

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
aiservice: apps/ai-service/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --reload --app-dir apps/ai-service
```

Alle Pfade relativ zum Workspace-Root (`DecisionMap/`). overmind muss aus dem
Workspace-Root gestartet werden (das tut `make dev-up` automatisch).

**Port 3000 (nicht 5000):** Auf macOS belegt AirPlay Receiver `0.0.0.0:5000` — Nuxt würde
auf 5000 starten, der Port ist aber bereits belegt. `PORT=3000` explizit setzen vermeidet
den Konflikt und stellt sicher, dass nginx via `host.docker.internal:3000` erreichbar ist.
