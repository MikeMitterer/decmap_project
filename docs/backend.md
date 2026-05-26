# Infrastructure und Operations

## Inhalt

- [Umgebungsvariablen](#umgebungsvariablen)
- [Feature Flags](#feature-flags)
- [Backend-Einrichtung](#backend-einrichtung)
- [Datenfluss](#datenfluss)
- [Code-Formatierung und Linting](#code-formatierung-und-linting)
- [CI/CD — Jenkins Pipeline](#cicd--jenkins-pipeline)
- [Makefile-Struktur](#makefile-struktur)
- [Versionierung](#versionierung)
- [Git-Konventionen](#git-konventionen)
- [Seed-Daten](#seed-daten)
- [Backup](#backup)

---

## Umgebungsvariablen

Nie hardcoden. Immer aus der Umgebung lesen. Alle in `.env.example` dokumentiert.

### Build-Maschine (Jenkins-Agent / Entwickler-Workstation)

Diese Variablen gehoeren nicht in `.env.example` — sie werden einmalig in der Shell-Umgebung gesetzt.

| Variable | Zeigt auf | Benoetigt von |
|---|---|---|
| `DEV_LOCAL` | Lokales Dev-Verzeichnis (z.B. `/Volumes/DevLocal`) | `make setup` — erstellt `.libs/`-Symlinks |
| `DEV_MAKE` | `MakeLib`-Verzeichnis | Root-`Makefile` + `.templates/Makefile` — `include ${DEV_MAKE}/colours.mk`, `tools.mk` |
| `DEV_DOCKER` | Docker-Hilfsskripte | `.templates/docker/build.sh` — Build + Push |
| `BASH_LIBS` | Bash-Bibliotheken (`*.lib.sh`) | `.templates/docker/build.sh` — sourced via `. ${BASH_LIBS}/build.lib.sh` usw. |
| `BASH_TOOLS` | Bash-Tools (`genCerts.sh` usw.) | `.templates/docker/build.sh` — Zertifikate in Docker-Image kopieren |

### Applikation (`.env` / Runtime)

```
# Frontend
USE_FAKE_DATA=true             # true = in-memory Fake-Daten, false = echter Server
BACKEND_URL=http://localhost:8001  # FastAPI-Backend (apps/backend/, Port 8001)
WS_URL=ws://localhost:8000     # WebSocket-URL des FastAPI-Service
SHOW_VOTING=false              # Feature Flag: Voting-Visualisierung aktivieren
REQUIRE_AUTH=false             # Feature Flag: Login fuer Einreichungen erzwingen
AUTO_APPROVE=false             # Feature Flag: Neue Problems automatisch freischalten (ohne Moderations-Review)

# Datenbank
POSTGRES_URL=                  # PostgreSQL Connection String (ai-service)

# AI-Service — Provider
EMBEDDING_PROVIDER=openai      # openai | (ollama — noch nicht implementiert)
LLM_PROVIDER=openai            # openai | anthropic
OPENAI_API_KEY=                # OpenAI API-Key fuer Embeddings + LLM-Calls
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
OPENAI_LLM_MODEL=gpt-4o-mini
ANTHROPIC_API_KEY=             # Nur benoetigt wenn LLM_PROVIDER=anthropic
ANTHROPIC_MODEL=claude-haiku-4-5-20251001

# AI-Service — Konfiguration
CLUSTERING_INTERVAL=360        # Batch-Clustering-Intervall in Minuten
SIMILARITY_THRESHOLD=0.85      # Schwellenwert fuer Aehnlichkeitserkennung (0.0–1.0); Dev mit <50 Problems: 0.55 (Prod-Werte zu streng)
DUPLICATE_THRESHOLD=0.92       # Schwellenwert fuer Duplikat-Erkennung; Dev: 0.70
BOT_SUBMIT_MIN_SECONDS=10      # Mindestzeit zwischen Seitenaufruf und Submit
BOT_SESSION_MAX_HOURLY=10      # Max. Submissions pro Session pro Stunde
BOT_IP_MAX_SESSIONS=5          # Max. verschiedene Sessions pro ip_hash
SERVICE_TOKEN=                 # Shared Secret (X-Service-Token Header); leer = Dev-Mode (kein Check)
CORS_ORIGINS=["http://localhost:3000"]  # JSON-Array erlaubter Browser-Origins

# apps/backend/ — FastAPI Backend (Port 8001)
DATABASE_URL=postgresql+asyncpg://decisionmap:decisionmap@localhost:5432/decisionmap
SECRET_KEY=dev-secret-key-change-in-production
FRONTEND_URL=http://localhost:3000    # Basis-URL fuer E-Mail-Links (Verify, Reset, Magic Link)
MAIL_SERVER=email-smtp.eu-west-1.amazonaws.com
MAIL_PORT=587
MAIL_USERNAME=                        # AWS SES SMTP-Zugangsdaten
MAIL_PASSWORD=
MAIL_FROM=noreply@decisionmap.ai
MAIL_SUPPRESS=false                   # true = kein echter E-Mail-Versand (Pflicht in Tests)
AI_SERVICE_URL=http://localhost:8000
SERVICE_TOKEN=dev-service-token       # Shared Secret apps/backend ↔ apps/ai-service
```

## Feature Flags

| Flag | Standard | Beschreibung |
|---|---|---|
| `SHOW_VOTING` | `false` | Vote-Scores in der Graph-Visualisierung anzeigen |
| `REQUIRE_AUTH` | `false` | Login fuer Einreichungen erzwingen |
| `AUTO_APPROVE` | `false` | Neue Problems automatisch freischalten (ohne Moderations-Review) |

**Hinweis:** Frontend-Feature-Flags (`SHOW_VOTING`, `REQUIRE_AUTH`, `AUTO_APPROVE`) werden zur Build-Zeit in das Nuxt-Bundle eingebettet (`runtimeConfig.public.*`). Eine Änderung in `.env` auf dem Server greift erst nach einem Rebuild + Redeploy des Frontend-Images:
```bash
# apps/frontend
make build
# infrastructure
make deploy-service SVC=frontend
```

[↑ Inhalt](#inhalt)

---

## Backend-Einrichtung

**Frische Dev-Umgebung:** Ein Befehl richtet alles ein:

```bash
make db-reset   # down -v → up → wait PostgreSQL → db-migrate (Alembic) → db-seed → up
```

**Verantwortlichkeiten:**

```
alembic/                 → alle DDL: Tabellen, vector-Spalten, Constraints, Indizes (SSoT)
database/seeds/          → Seed-Daten (alphabetisch, idempotent)
```

**Junction-Tabellen** (`problem_tag`, `problem_region`) haben `id UUID PRIMARY KEY` + `UNIQUE(problem_id, ...)`. (`problem_cluster` gedroppt in Migration 005, 2026-05-22)

**Einzelne Schritte (bei Bedarf):**
```bash
make db-migrate          # Alembic upgrade head
make db-seed             # Seed-Daten einspielen
make api-dev             # FastAPI-Dev-Server (Port 8001, --reload)
```

**Dev-URLs (nach `make dev-up`):**

| URL | Dienst |
|---|---|
| http://int.decisionmap.ai | App (Frontend) |
| http://backend.int.decisionmap.ai | Backend API (FastAPI) |
| http://localhost:8001/docs | FastAPI Swagger |
| http://localhost:8025 | Mailpit (SMTP-Sink) |
| http://localhost:8080 | Adminer (DB-UI, Server: `postgres`, User/DB: `decisionmap`) |

**Auth (fastapi-users):**
E-Mail-Verifizierung nach Registrierung — `registrationSent`-Flag im Frontend, kein Auto-Login.
`/verify-email.vue` → `GET /auth/verify?token=XXX` → Redirect auf `/login?verified=true`.
Dev: Mailpit als SMTP-Sink (`http://localhost:8025`).

**SMTP — AWS SES (Produktion):**
```
MAIL_SERVER=email-smtp.eu-west-1.amazonaws.com
MAIL_PORT=587
MAIL_USERNAME=<IAM-SMTP-Credentials-User>
MAIL_PASSWORD=<IAM-SMTP-Credentials-Secret>
MAIL_FROM=noreply@decisionmap.ai
```
Vollständige Einrichtungsanleitung: [`docs/ses-setup.md`](ses-setup.md). Tracking: MikeMitterer/decmap_project#1.

SMTP-Verbindung testen: `./scripts/smtp-test.py --send --to dein@email.com` (liest `apps/backend/.env` automatisch).

**Gotcha — Hetzner blockiert ggf. Port 587:** Mit Mailjet wurde beobachtet, dass Hetzner VPS ausgehende Verbindungen auf Port 587 blockiert. AWS SES unterstützt auch Port 465 (TLS) als Fallback: `EMAIL_SMTP_PORT=465`, `EMAIL_SMTP_SECURE=true`. Vor Go-Live testen: `./scripts/smtp-test.py` oder `nc -zv email-smtp.<region>.amazonaws.com 587`.

**Gotcha — Hetzner DNS + SES DKIM CNAME:**
SES DKIM-Einrichtung erzeugt CNAME-Records die auf externe Hostnamen zeigen (`xxxxx.dkim.amazonses.com`). Hetzner Robot (alte Oberfläche) lehnt externe CNAME-Ziele mit Validierungsfehler ab. Lösung: DNS-Einträge in `dns.hetzner.com` (neues Interface) anlegen — dort funktionieren externe CNAME-Ziele problemlos. Hetzners Validierungswarnung ist übereifrig — die Records werden trotzdem korrekt an AWS übermittelt.

Wenn `dns.hetzner.com` ebenfalls blockiert: DNS auf Route 53 oder Cloudflare delegieren — beide Anbieter akzeptieren externe CNAME-Ziele ohne Einschränkungen. AWS Route 53 bietet zudem "Easy DKIM" mit automatischem Record-Setup direkt aus der SES-Console.

**Hinweis:** AWS hat TXT-basierte Domain-Verifizierung 2024 abgeschafft — nur noch DKIM-CNAMEs werden unterstützt.

**Gotcha — Custom MAIL FROM Domain — AWS-Standard nicht übernehmen:**
SES schlägt `no-reply.decisionmap.ai` als Standard-Subdomain vor. Bessere Wahl: `mail.decisionmap.ai` (kürzer, klarer, zukunftssicher). Im Bearbeiten-Dialog im Abschnitt *Benutzerdefinierte MAIL-From-Domain* vor dem Speichern anpassen. Für Custom MAIL FROM sind zwei DNS-Records nötig: MX (`feedback-smtp.eu-west-1.amazonses.com.`, Priority 10) und SPF-TXT (`v=spf1 include:amazonses.com ~all`) — beide auf `mail.decisionmap.ai`. Trailing Dot gilt auch hier: nur beim MX-Ziel-Wert, **nicht** beim Name/Host-Eintrag. Details: [`docs/ses-setup.md#phase-2b`](ses-setup.md).

**Flows (FastAPI BackgroundTasks):**

> **Phase 5–8 abgeschlossen (Directus vollständig entfernt):** Phase 5: `problem-submitted`, `problem-approved`, `solution-approved` vom FastAPI-Backend gefeuert (BackgroundTasks). Phase 6: Internal API `/internal/*` (11 Endpoints, `X-Service-Token`). Phase 7: AI-Service nutzt `BackendClient` (httpx) statt direktem DB-Zugriff — `app/repositories/` gelöscht, `psycopg[binary]` entfernt, alle Services + hooks.py + scheduler.py auf BackendClient umgestellt. Migration 004: `cluster_tag`-Junction + UNIQUE auf `clusters.label` + UNIQUE auf `tags(name, level)`. Phase 8: Directus aus docker-compose, nginx, env vars, CLAUDE.md entfernt. `cms.decisionmap.ai` → `api.decisionmap.ai` (Port 8001). `useDirectusRealtime.ts` → `useBackendRealtime.ts`. `directusClient.ts`, `apps/backend/directus/` gelöscht.

Alle Flows werden jetzt vom FastAPI-Backend ausgeloest (keine Directus-Abhaengigkeit mehr):

| Flow | Status |
|---|---|
| `problem-submitted` | ✓ Backend Phase 5 (BackgroundTask) |
| `problem-approved` | ✓ Backend Phase 5 (BackgroundTask) |
| `solution-submitted` | ✓ Backend (BackgroundTask → `POST /hooks/solution-submitted` → AI-Service Spam-Filter) |
| `solution-approved` | ✓ Backend Phase 5 (BackgroundTask) |
| `vote-changed` | ✓ Backend Phase 8 (`POST /votes` → WS broadcast) |

**Vote-Toggle-Semantik (`POST /votes`):** Gleiche Richtung → Vote wird zurückgezogen (delta = -1). Entgegengesetzte Richtung → Flip (delta = ±2). Neues Vote → delta = ±1. Backend gibt `vote_score` direkt im Response zurück — kein Re-Fetch nötig. `fakeVoting.ts` implementiert dieselbe Logik (Contract-Test in `useVoting.contract.spec.ts` verifiziert den Vertrag).

**Internal API `/internal/*` (Phase 6 — Phase 7 abgeschlossen, AI-Service nutzt ausschließlich diese API):**

Alle Endpoints erfordern `X-Service-Token: <SERVICE_TOKEN>` Header (`verify_service_token` Dependency, 403 bei Fehler, Dev-Wert `dev-service-token`).

| Endpoint | Zweck |
|---|---|
| `POST /internal/problems/{id}/embedding` | Embedding speichern |
| `PATCH /internal/problems/{id}/status` | Status aktualisieren |
| `GET /internal/problems/approved` | Approved-Problems **die bereits ein Embedding haben** — für Clustering (filtert Problems ohne Embedding heraus) |
| `GET /internal/problems/approved-all` | Alle approved Problems **unabhängig vom Embedding-Status** — für Bulk-Reindex |
| `GET /internal/problems/{id}` | Problem by ID |
| `POST /internal/problems/{id}/solutions` | AI-generierte Lösung anlegen |
| `POST /internal/similarity` | pgvector Cosine-Similarity-Suche |
| `POST /internal/tags/upsert` | Tag upsert (API: `label` → DB: `name`) |
| `GET /internal/tags/l0-root` | L0-Root-Tag holen — Ausgangspunkt fuer L1-Cluster-Tags |
| `DELETE /internal/tags/structural` | Alle L1–L9 Tags loeschen (Cascade auf `problem_tag`) — vor Reclustering |
| `POST /internal/problems/{id}/structural-tag` | Problem einem L1-Cluster-Tag zuweisen (`problem_tag`) |

**Bulk-Reindex:** `POST /embeddings/reindex` (AI-Service) + `GET /internal/problems/approved-all` (Backend) sind implementiert — letzterer liefert alle approved Problems ohne Embedding-Filter (für initiale Befüllung oder Re-Embedding nach Modellwechsel). Smoke-Test: `./scripts/smoke-test.sh reindex`.

**Gotcha — asyncpg `:param::type` bricht Parameter-Substitution:** In SQLAlchemy `text()` Queries stoppt asyncpg die Substitution beim `::` direkt nach dem Parameternamen. Fix: Klammern setzen — `embedding <=> (:emb)::vector` statt `embedding <=> :emb::vector`.

**Embedding-Input — Sprachnormalisierung (implementiert):** Gespeicherte Embeddings basieren nur auf `description_en` (`_embedding_text()`: `description_en` bevorzugt, `title` als Fallback). Similarity-Queries werden vor dem Embedding via `TranslationService.to_english()` ins Englische übersetzt — DE+EN-Vektor-Mismatch gegen Threshold 0.85 ist damit vermieden. `TranslationService` nutzt `langdetect>=1.0.9` zur Spracherkennung: englischer Text wird direkt durchgereicht (kein LLM-Call), nur nicht-englischer Text löst einen API-Call aus.

**Gotcha — Tags: API-Feld `label` ↔ DB-Spalte `name`:** Die `tags`-Tabelle hat eine Spalte `name` (historisch — Umbenennung nicht nötig). Der AI-Service schickt/erwartet `label`. Die Internal API mappt transparent: `label` im Request-Body → `name` in der DB, `name` in der DB → `label` im Response.

**Gotcha — `useServiceStatus` URL-Detection:** Das Composable unterscheidet die zwei Services anhand der URL-Signatur, nicht anhand eines Namens-Parameters. Backend wird an `:8001` erkannt (Port im URL-String), AI-Service an `/api/health` (Pfad-Präfix nach nginx-Proxy). In Tests müssen Mock-URLs diese Muster enthalten (`url.includes(':8001')` vs. `url.includes('/api/health')`). Außerdem prüft `fetchJson()` `res.ok` bevor es parst — Mocks müssen `ok: true, status: 200` setzen, sonst gibt `fetchJson` immer `null` zurück.

[↑ Inhalt](#inhalt)

---

## Datenfluss

```
User reicht Problem ein
    → FastAPI POST /problems (apps/backend/, Port 8001)
        → _ip_hash(request) hasht X-Forwarded-For/client.host (SHA256)
        → Problem in DB schreiben (status: pending)
        → BackgroundTask: notify_problem_submitted → POST /hooks/problem-submitted (ai-service)
            → _verify_service_token() prueft X-Service-Token Header
            → SpamFilter bewertet (sync, LLM-Call)
                → Klarer Spam: status: rejected
                → Unklar / gueltig: status: needs_review
            → [async, nach Response]:
                embed (eigene Conn) → WebSocket broadcast
    → Admin prueft Moderations-Queue → Freigabe
        → FastAPI PATCH /admin/problems/:id → status: approved
        → BackgroundTask: notify_problem_approved → POST /hooks/problem-approved (ai-service)
            → embed + AI-Loesung generieren + Cluster aktualisieren → WS broadcast
    → Frontend empfaengt Updates via useBackendRealtime.ts (WS /ws, Port 8001)
    → Cytoscape.js rendert Graph
```

[↑ Inhalt](#inhalt)

---

## Code-Formatierung und Linting

Formatierung ist nicht verhandelbar — automatisch vor Commit und in Jenkins.

### TypeScript / Vue

- **ESLint** + `eslint-plugin-vue` — Linting
- **Prettier** + `eslint-config-prettier` — Formatierung

```bash
make lint-frontend    # ESLint prufen
make format-frontend  # Prettier anwenden
```

### Python

- **ruff** — Linting und Formatierung (ersetzt flake8 + black + isort)

```bash
make lint-backend     # ruff check
make format-backend   # ruff format
```

[↑ Inhalt](#inhalt)

---

## CI/CD — Jenkins Pipeline

Jedes Sub-Repo hat eine eigene Pipeline. Ein Frontend-Deploy triggert keinen Backend-Build.

### Frontend-Pipeline (Reihenfolge invariant)

```
1. checkout
2. npm ci
3. lint (ESLint + Prettier)
4. test (Vitest)
5. docker build-amd64 (Multi-Stage: build → runner) + push nach ghcr.io
6. make -C infrastructure deploy-service SVC=frontend
```

### AI-Service-Pipeline

```
1. checkout
2. pip install (inkl. hdbscan, scikit-learn, numpy)
3. lint (ruff)
4. test (pytest)
5. docker build-amd64 (Multi-Stage: build → runner) + push nach ghcr.io
6. make -C infrastructure deploy-service SVC=ai-service
```

**Gotcha — Lange Build-Zeit durch native Kompilierung:** `hdbscan` hängt von `scikit-learn` und `numpy` ab — beide kompilieren C/Fortran-Extensions beim `pip install`. Der erste Build in CI ohne Layer-Cache dauert deutlich länger als reine Python-Pakete. Ist einmalig solange der Docker Layer-Cache warm bleibt; bei Cache-Miss (z.B. nach `requirements.txt`-Änderung) wiederholt sich die Kompilierung. Base-Image mit vorinstallierten Binär-Wheels (`python:3.11-slim` + `--only-binary=:all:`) kann die Zeit reduzieren.

### Server-Voraussetzungen (Hetzner)

`docker compose` (V2) erfordert das offizielle Docker-Repository — **nicht** `docker.io` (Ubuntu-Paket):

```bash
# Altes Paket entfernen
sudo apt-get remove docker.io docker-compose

# Offizielles Docker-Repo einrichten
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

`docker.io` liefert keinen `docker compose`-Subcommand (V2) — nur das veraltete standalone `docker-compose` (V1). Das Makefile und alle Pipeline-Schritte verwenden V2-Syntax (`docker compose up`).

### Deploy-Strategie

`nuxt build` erzeugt einen Node.js-Server (nicht statische Dateien). Das Docker-Image
wird lokal auf dem Jenkins-Agent gebaut, nach ghcr.io gepusht und via
`make -C infrastructure deploy-service SVC=frontend` deployed
(SSH + `docker compose pull frontend` + `docker compose up --no-deps --force-recreate frontend`).

**Warum nicht `nuxt generate`?** Die SPA-Routes (`ssr: false`) und dynamische Daten
funktionieren nicht sauber mit statischer Generierung.

**Dockerfile (Multi-Stage):**
- Base Image: `node:20-bookworm-slim` (Debian 12 slim) — nicht Alpine, da native npm-Dependencies sonst musl-Kompatibilitätsprobleme verursachen
- Stage `builder`: `npm ci` + `nuxt build` → erzeugt `.output/`
- Stage `runner`: nur Node.js + `.output/` — kein `node_modules`, kein Source-Code im Image

**Naming-Konvention:** Image- und Container-Namen folgen dem Schema `decisionmap-<service>`
(z.B. `decisionmap-backend`, `decisionmap-frontend`, `decisionmap-ai-service`, `decisionmap-postgres`).
Definiert in `infrastructure/docker-compose.yml`.

**Jenkinsfile:** Lint + Test laufen auf allen Branches. Build + Deploy nur auf `main`.
Lokales Build-Image wird nach dem Deploy auf dem Jenkins-Agent geloescht.
[`.templates/Jenkinsfile`](../.templates/Jenkinsfile) ist ein generisches Ausgangs-Template — muss fuer die oben beschriebene Deploy-Strategie (ghcr.io Push + `make -C infrastructure deploy-service`) angepasst werden. Konkret: `sh './docker/app/build --build'` → `sh './docker/build.sh --build'` (Pfad auf `docker/build.sh` des Sub-Repos anpassen).

**Build-Script:** [`.templates/docker/build.sh`](../.templates/docker/build.sh) ist das generische Bash-Template fuer Sub-Repo-Build-Skripte. (Das ebenfalls vorhandene `.templates/docker/Dockerfile` ist ein generisches Debian/certbot-Base-Image fuer Tooling — kein Nuxt-Template.) Enthaelt Platform-Erkennung, BashLib-Includes, `--build`/`--push`/`--images`-Flags und TAG-Erzeugung via `gitDockerTag` aus `version.lib.sh` (BashLib) — Format: `<VERSION>-<YYMMDD>.<HHMM>.<HASH>[.ahead<N>][.d]`, z.B. `0.1.0-260412.0824.def34.ahead3`; Git-Tag-Format: `v<VERSION>+<YYMMDD>.<HHMM>.<HASH>`. Benoetigt `DEV_DOCKER`-Env-Variable auf der Build-Maschine (zeigt auf Docker-Hilfsskripte). Pro Sub-Repo nach `docker/build.sh` kopieren und `NAMESPACE`/`NAME`/Deploy-Logik anpassen. **Wichtig:** Der `--push`-Zweig im Template ruft `pushImage2DockerHub` auf — dieser Block muss vollstaendig durch `docker push ghcr.io/...` ersetzt werden (Docker Hub wird nicht verwendet; Images gehen nach ghcr.io). Das Dockerfile liegt in `docker/`, der Build-Context ist das Parent-Verzeichnis des Sub-Repos (`docker build -f Dockerfile ..`). **Achtung:** Da der Build-Context das gesamte Sub-Repo-Verzeichnis umfasst, muss `docker/` in `.dockerignore` ausgeschlossen werden — sonst landet das Build-Verzeichnis selbst im Image.

**Gotcha — `--builder default` und fehlendes `--load` in `docker build`:**
`docker buildx build --builder default` schlägt fehl wenn auf Mac mit Docker Desktop der aktive Context `desktop-linux` ist — `default` ist dann kein gültiger Builder-Name (Fehlermeldung: `use docker --context=default buildx ...`). `--builder default` weglassen — buildx verwendet automatisch den aktiven Context:
- **Mac / Docker Desktop:** aktiver Context = `desktop-linux` (docker driver, direkt am lokalen Daemon)
- **Linux / CI / Jenkins:** aktiver Context = `default` (docker driver, existiert dort immer)

Der `multiarch`-Builder (docker-container driver) wird für single-arch Builds nicht benötigt. Ausserdem: ohne `--load` landet das gebaute Image nicht im lokalen Docker-Daemon (buildx cached es nur intern). `--load` ist Pflicht, wenn das Image lokal weiterverwendet oder gepusht werden soll.
```bash
# Falsch:
docker buildx build --builder default --platform linux/amd64 -t myimage .
# Richtig:
docker buildx build --platform linux/amd64 --load -t myimage .
```

**`.dockerignore` fuer Multi-Stage-Builds:** `.output/` muss in `.dockerignore` stehen — nicht weil `COPY --from=builder` den Host liest (das tut es nicht, es greift auf Stage 1 zu), sondern weil `COPY . .` in Stage 1 ein lokales `.output/` (vom Host) in den Build-Context uebertraegt. Das kann ein veraltetes lokales Artefakt in Stage 1 einschleppen, bevor `npm run build` laeuft. `node_modules/` und `.output/` gehoeren daher beide in `.dockerignore`.

### Konfiguration ausserhalb der Pipeline

Das `.env` liegt auf dem Hetzner-Server — Jenkins deployt nur den Build-Artefakt.
Vorlage: `infrastructure/.env.example` (alle Variablen mit Prod-Defaults, HTTPS-URLs, `USE_FAKE_DATA=false`).

```bash
# Erstmalig einrichten oder aktualisieren:
cp infrastructure/.env.example infrastructure/.env
# Werte setzen, dann hochladen:
scp infrastructure/.env decmap:/srv/decisionmap/.env
```

Phasenumschaltung ausschliesslich durch Anpassen von `.env` auf dem Server:

```bash
# Phase 1 — Fake-Daten
USE_FAKE_DATA=true

# Phase 2 — Live (Pipeline unveraendert)
USE_FAKE_DATA=false
```

### nginx — TLS-Terminierung

nginx laeuft als Docker-Container (`nginx:bookworm`, Debian 12). TLS wird im Container terminiert, nicht auf dem Host.

**Image:** `nginx:bookworm` statt Alpine — Debian-Basis, User `nginx` (Alpine verwendet `www-data`).

**Let's Encrypt Volumes:** Beide Pfade muessen gemountet werden, weil `live/fullchain.pem` ein Symlink auf `archive/` ist:

```yaml
volumes:
  - /etc/letsencrypt/live/decisionmap.ai:/etc/letsencrypt/live/decisionmap.ai:ro
  - /etc/letsencrypt/archive/decisionmap.ai:/etc/letsencrypt/archive/decisionmap.ai:ro
```

**nginx.conf:**
- Port 80: reiner `301`-Redirect zu HTTPS
- Port 443: TLS (`TLSv1.2/1.3`), alle Location-Bloecke (Frontend, Backend-API, AI-Service, WebSocket)

**Backend API auf Subdomain `api.decisionmap.ai`:**
FastAPI Backend läuft auf Port 8001 — kein Pfad-Prefix, direkte Subdomain.

```nginx
server {
    server_name api.decisionmap.ai;
    location / {
        proxy_pass http://backend:8001;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

**Backend WebSocket hinter nginx:** Der Subdomain-Block muss WebSocket-Upgrade-Headers weiterleiten — sonst schlägt `useBackendRealtime.ts` lautlos fehl.

**nginx — `proxy_pass` mit Variable + `rewrite` — drei Gotchas:**

1. **`proxy_pass http://$var/` macht keine Prefix-Substitution.** Ohne Variable würde `location /api/` + `proxy_pass http://upstream/` das `/api/`-Prefix automatisch ersetzen. Mit Variable passiert das nicht — `/api/health` landet als `/api/health` beim Backend. Fix: `rewrite` + `$uri` explizit übergeben.

2. **`rewrite ... break` stoppt auch `set`.** `break` unterbricht alle Direktiven des nginx Rewrite-Moduls — dazu gehört auch `set`. Eine `set`-Direktive nach `rewrite ... break` wird nie ausgeführt → Variable bleibt leer → nginx-Error "no host in upstream". **`set` immer vor `rewrite` stellen.**

3. **`proxy_pass http://$var` (ohne URI) nach `rewrite` nimmt die Original-URI.** `$uri` enthält nach einem `rewrite` die neue URI — explizit übergeben:
```nginx
location /api/ {
    set $upstream_ai ai-service:8000;          # set VOR rewrite
    rewrite ^/api/(.*)$ /$1 break;
    proxy_pass http://$upstream_ai$uri$is_args$args;
}
```

**`host-install`:** Installiert nur noch systemd-Service und cert-watcher — kein nginx auf dem Host, keine `nginx -t`/`systemctl reload nginx` Schritte.

**Cert-Rotation:** `unpackCert.sh` (`host/usr/local/bin/`) entpackt neue Zertifikate und startet den nginx-Container neu — aufgerufen durch den systemd cert-watcher (`cert.decisionmap.ai.path`).

**Server-Voraussetzung — Docker Compose V2:** Alle Makefiles verwenden `docker compose` (V2, kein Bindestrich). Auf Ubuntu 24.04 mit offiziellem Docker-Repository ist das Compose-Plugin ein separates Paket:

```bash
sudo apt-get install docker-compose-plugin
docker compose version   # → Docker Compose version v2.x.x
```

Bei `docker.io`-Installation (Ubuntu-Paket statt Docker-Repo) muss zuerst das offizielle Docker-Repository eingerichtet werden.

[↑ Inhalt](#inhalt)

---

## Makefile-Struktur

Jedes Sub-Repo hat ein eigenes Makefile fuer seinen Kontext. `make help` zeigt die Befehle des jeweiligen Repos, `make hints` zeigt Service-URLs, SSH-Befehle und Abhaengigkeiten — eigenstaendiges Target, kein `@$(MAKE) hints` am Ende von `help`.

Konventionen (Struktur, `##@`-Gruppen, `.PHONY`, `info`/`hints`-Targets, Farben): `/code-standards`

**Comment-Syntax (awk-basiertes `make help`):**

```makefile
##@ Setup                     # Gruppen-Header (gelb eingerückt)

.PHONY: setup
setup: ## Symlinks erstellen   # Standard-Target (blau)
deploy: ##R Deploy auf Server  # Server-Op → gelb hervorgehoben
db-reset: ##D DB zurücksetzen  # Danger-Op → rot hervorgehoben
```

`help`-Regel greift alle Zeilen mit `##@` (Gruppen) und alle Targets mit `## desc` — kein Boilerplate pro Target nötig. Die `THEME_*`-Variablen (`THEME_COLOR_GROUP`, `THEME_COLOR_TARGET`, `THEME_COLOR_DESC`) kommen aus MakeLib (`include ${DEV_MAKE}/colours.mk` + `include ${DEV_MAKE}/tools.mk`). `##R`-Marker = Server-Ops (gelb), `##D`-Marker = Danger-Ops (rot).

`make help` unterstützt Farbthemen via `MAKE_THEME` (Env-Variable oder `.env`): `classic` (Standard), `ocean`, `earth`, `night`, `mono`, `sunset`, `forest`, `neon`.

| Makefile | Zustandig fuer |
|---|---|
| `Makefile` (Root) | Workspace-Setup, Delegation an Sub-Repos, Cross-Repo lint/test |
| `infrastructure/Makefile` | docker-compose, nginx, Server-Orchestrierung |
| `apps/backend/Makefile` | FastAPI Backend: Datenbank, Backup, Seeds, Versioning (`install`, `api-dev`, `db-migrate`, `db-seed`, `api-test`, `api-test-contract`) |
| `apps/frontend/Makefile` | Dev-Server, Lint, Test, Build, Versioning |
| `apps/ai-service/Makefile` | Dev-Server, Lint, Test, Build, DB-Migrationen, Versioning |

[`.templates/Makefile`](../.templates/Makefile) ist ein generisches Ausgangs-Template mit `##@`/`## desc`/`##R`/`##D`-Stil. Benoetigt nur `DEV_MAKE` — kein `setup`-Target, kein `DEV_LOCAL`.

**Versioning-Voraussetzung:** `bumpVer` benoetigt `BASH_LIBS` und eine Versionsdatei (`package.json`, `pyproject.toml` oder `VERSION`). Jedes Sub-Repo muss genau eine davon enthalten:

| Repo | Versionsdatei |
|---|---|
| `apps/backend/` | `VERSION` |
| `apps/frontend/` | `package.json` |
| `apps/ai-service/` | `pyproject.toml` |

```bash
# Workspace-Root
make setup             # .libs/-Symlinks erstellen (einmalig, benoetigt DEV_LOCAL)
make status            # Git-Status aller Workspace-Repos (dirty + ahead/behind Remote)
make dev-up            # Docker-Services + overmind (Frontend + AI-Service via Procfile.dev)
make dev-down          # Docker-Services stoppen
make env-audit         # .env vs .env.example Drift-Erkennung (alle Repos; Exit-Code 1 bei Drift)
make lint              # → delegiert an apps/frontend/ und apps/ai-service/
make test              # → delegiert an apps/frontend/ und apps/ai-service/

# Backend (aus apps/backend/ oder via make -C apps/backend ...)
make up / down / logs                                 # Alle Services
make dev-up / dev-down / dev-logs                     # Dev-Umgebung (Postgres + Backend-API + Mailpit)
make db-reset                                         # DB zurücksetzen (down -v → up → migrate → seed)
make db-migrate / db-rollback / db-migrate-status     # Alembic-Migrationen
make db-seed                                          # ↳ Seed-Daten einspielen
make backup / backup-schema / backup-restore          # Backup
make build / deploy                                   # Build & Deploy
make precheck / version / tags                        # Versioning
make tag-patch / tag-minor / tag-major                # SemVer Git-Tag setzen + pushen
make install                                          # FastAPI-Backend Python-Abhaengigkeiten
make api-dev                                          # FastAPI-Dev-Server (Port 8001, --reload)
make api-test                                         # Unit-Tests (pytest tests/unit/)
make api-test-contract                                # Contract-Tests (pytest tests/contract/)

# AI-Service (aus apps/ai-service/ oder via make -C apps/ai-service ...)
make install / install-dev                            # Abhaengigkeiten
make lint / format                                    # Code-Qualitaet (ruff)
make test / test-unit / test-contract                 # Tests (pytest)
make dev                                              # uvicorn mit --reload
make build / docker-up / docker-down                  # Docker
make db-migrate / db-migrate-create / db-rollback     # Alembic
make precheck / version / tags                        # Versioning
make tag-patch / tag-minor / tag-major                # SemVer Git-Tag setzen + pushen
# → Manuelle curl-Tests aller Endpunkte: docs/cmdline.md

# Frontend (aus apps/frontend/ oder via make -C apps/frontend ...)
make dev / install / lint / format / test             # Entwicklung
make build / deploy                                   # Deploy
make tag-patch / tag-minor / tag-major                # Versioning
```

[↑ Inhalt](#inhalt)

---

## Versionierung

### Release-Tags (SemVer + Datum)

**Format:** `v<MAJOR>.<MINOR>.<PATCH>+<YYMMDD>.<HHMM>` — klassisches SemVer, Datum als Build-Metadata.

```
v0.1.0+260411.1430      # Erstes Release
v0.2.0+260422.1400      # Minor-Bump (neues Feature)
v0.2.1+260510.1115      # Patch-Bump (Bugfix)
v1.0.0+260701.0900      # Major-Bump (Breaking Change)
v0.3.0-rc1+260628.1600  # Release Candidate
```

Alle Repos starten bei `0.1.0`. Major/Minor/Patch wird manuell gewaehlt.

**Makefile-Targets:**

```makefile
make tag-major          # Major-Bump (0.1.0 → 1.0.0)
make tag-minor          # Minor-Bump (0.1.0 → 0.2.0)
make tag-patch          # Patch-Bump (0.1.0 → 0.1.1)
make tag-minor MSG="…"  # mit Tag-Message
make version            # Aktuelle Version anzeigen
make tags               # Letzte 10 Tags anzeigen
```

`bumpVer` (BashLib) schreibt die Version in die Datei (`VERSION`, `package.json` oder `pyproject.toml`),
erstellt einen Git-Commit und setzt den Tag. Reihenfolge: Version berechnen → Datei schreiben → Commit → Tag.

### Snapshot-Tags (Docker)

Build-Scripts verwenden `gitDockerTag` aus `version.lib.sh` (BashLib) fuer Docker-Image-Tags — automatisch via Jenkins.

**Format:** `<MAJOR>.<MINOR>.<PATCH>-<YYMMDD>.<HHMM>.<HASH>[.ahead<N>][.d]`

```
0.1.0-260412.0824.def34           # normaler Snapshot-Build
0.1.0-260412.0824.def34.ahead3    # 3 unpushte Commits ueber dem Tag
0.1.0-260412.0824.def34.d         # dirty Working Tree
```

Snapshot-Tags werden automatisch vom Jenkins-Build erzeugt — nie manuell.

[↑ Inhalt](#inhalt)

---

## Git-Konventionen

### Commit-Messages

Format: `<type>(<scope>): <beschreibung>`

| Type | Wann |
|---|---|
| `feat` | Neues Feature |
| `fix` | Bugfix |
| `refactor` | Umstrukturierung ohne Funktionsanderung |
| `test` | Tests |
| `chore` | Build, Dependencies, Konfiguration |
| `docs` | Dokumentation |

### Branch-Naming

```
feature/<kurze-beschreibung>
fix/<kurze-beschreibung>
chore/<kurze-beschreibung>
```

- `main` ist immer deploybar — Jenkins ist die einzige Schranke
- Direkte Commits auf `main` sind erlaubt (kleines Team)
- Feature-Branches optional, aber empfohlen fuer groessere Aenderungen

[↑ Inhalt](#inhalt)

---

## Seed-Daten

**Backend SQL-Seeds** in `database/seeds/` — alphabetisch importiert, idempotent (`ON CONFLICT DO NOTHING`).

```
database/seeds/
├── 001_regions.sql      ← EU, US, APAC, GLOBAL
├── 002_tags.sql         ← governance, open-source, ...
└── 003_problems.sql     ← 40–50 Seed-Probleme mit Embeddings
```

```bash
make db-seed             # alle importieren
make db-seed FILE=003    # einzelnes File
make db-reset            # DB zurucksetzen + Migrationen + Seed (nur lokal!)
```

Dieselben Files in `docker-compose.test.yml` — kein separater Test-Datensatz.

[↑ Inhalt](#inhalt)

---

## Backup

Einheitliches Script `scripts/db-backup.sh` — wird von Backend- und Infrastructure-Makefile genutzt.
Immer `--format=custom` (`.dump`), wiederherstellbar mit `pg_restore`.

```bash
# Backend (Dev)
make -C apps/backend backup              # vollstaendiges DB-Backup
make -C apps/backend backup-list         # vorhandene Backups auflisten
make -C apps/backend restore FILE=database/backups/decisionmap_20260412_120000.dump

# Infrastructure (Prod)
make -C infrastructure backup            # vollstaendiges DB-Backup auf dem Server
make -C infrastructure backup-schema     # nur Schema sichern
make -C infrastructure backup-list       # vorhandene Backups anzeigen
make -C infrastructure backup-restore FILE=backups/decisionmap_20260412_120000.dump
make -C infrastructure backup-pull       # Server → lokal (rsync backups/)
make -C infrastructure backup-push       # lokal → Server (rsync backups/)
```

Das Script delegiert alle Operationen via `docker compose exec` und akzeptiert
`--compose-file`, `--service`, `--backup-dir`, `--user`, `--db` (oder Env-Variablen):

```bash
scripts/db-backup.sh --help   # vollstaendige Optionsliste
```

Backups nie einchecken — `database/backups/` bzw. `backups/` in `.gitignore`.

**Restore mit aktiven Services:** Backend und AI-Service halten offene DB-Connections. `pg_restore` kann dann keine DROP/CREATE-Operationen auf verwendeten Tabellen ausführen → partieller Restore möglich. Vor einem Restore die betroffenen Services stoppen (`docker compose stop backend ai-service`), danach neu starten.
