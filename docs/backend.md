# Infrastructure und Operations

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
| `BASH_TOOLS` | Bash-Tools (`local2Server.sh` usw.) | `.templates/Makefile` — `lh2server`/`update`-Targets |

### Applikation (`.env` / Runtime)

```
# Frontend
USE_FAKE_DATA=true             # true = in-memory Fake-Daten, false = echter Server
WS_URL=ws://localhost:8000     # WebSocket-URL des FastAPI-Service
SHOW_VOTING=false              # Feature Flag: Voting-Visualisierung aktivieren
REQUIRE_AUTH=false             # Feature Flag: Login fuer Einreichungen erzwingen

# Directus
DIRECTUS_URL=                  # Directus-Instanz URL
DIRECTUS_TOKEN=                # Directus Admin-Token
CORS_ORIGIN=http://localhost:3000  # Erlaubter Browser-Origin fuer Directus (nicht Wildcard — browser-invalid mit credentials)

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
SIMILARITY_THRESHOLD=0.85      # Schwellenwert fuer Aehnlichkeitserkennung (0.0–1.0)
DUPLICATE_THRESHOLD=0.92       # Schwellenwert fuer Duplikat-Erkennung
BOT_SUBMIT_MIN_SECONDS=10      # Mindestzeit zwischen Seitenaufruf und Submit
BOT_SESSION_MAX_HOURLY=10      # Max. Submissions pro Session pro Stunde
BOT_IP_MAX_SESSIONS=5          # Max. verschiedene Sessions pro ip_hash
WEBHOOK_SECRET=                # Shared Secret fuer Directus Flows (X-Webhook-Secret Header); leer = Dev-Mode
CORS_ORIGINS=["http://localhost:3000"]  # JSON-Array erlaubter Browser-Origins
```

## Feature Flags

| Flag | Standard | Beschreibung |
|---|---|---|
| `SHOW_VOTING` | `false` | Vote-Scores in der Graph-Visualisierung anzeigen |
| `REQUIRE_AUTH` | `false` | Login fur Einreichungen erzwingen |

---

## Directus-Einrichtung

**Frische Dev-Umgebung:** Ein Befehl richtet alles ein:

```bash
make db-reset   # down -v → up → schema apply → constraints → seed
```

**Verantwortlichkeiten:**

```
database/init/000_schema.sql  → nur PostgreSQL-Extensions (uuid-ossp, vector)
directus/schema.json          → Tabellen + Directus-Metadaten (single source of truth)
database/constraints.sql      → was Directus nicht kann: vector(1536), CHECK-Constraints,
                                 UNIQUE-Constraints (Junction-Tabellen), custom Indizes
```

**Junction-Tabellen** (`problem_cluster`, `problem_tag`, `problem_region`) haben eine
`id UUID PRIMARY KEY` + `UNIQUE(problem_id, ...)` — Directus benoetigt eine Single-Column-PK
fuer M2M-Relationen. M2M-Relationen und Alias-Felder sind in `schema.json` enthalten.

**Was NICHT im Snapshot enthalten ist:**
- `vector(1536)` Spalten (`embedding`, `centroid`) — werden von `db-constraints` + AI-Service via psycopg3 verwaltet
- Directus Flows — muessen einmalig manuell angelegt werden (siehe unten)

**Einzelne Schritte (bei Bedarf):**
```bash
make directus-schema-apply   # Tabellen + Metadaten via schema.json
make db-constraints          # vector-Spalten, Constraints, Junction-Tables, Indizes
make db-seed                 # Seed-Daten
make seed-users              # Test-User + Rolle + Policy in Directus
make db-permissions          # Public-Policy (Anon-READ) + User-Policy (CREATE/UPDATE/DELETE) anlegen
```

**Gotcha — schema apply nach Alembic-Migration:**
Wenn Alembic zuerst laeuft und dabei Directus-Tabellen anlegt, hinterlaesst es verwaiste `directus_*` Metadata-Eintraege. Ein anschliessendes `make directus-schema-apply` schlaegt dann mit Konflikt-Fehler fehl. Loesung: verwaiste `directus_*` Metadata-Eintraege aus den betroffenen Tabellen loeschen, dann erneut `make directus-schema-apply`.

**Gotcha — Direktus Benutzer-Registrierung:**
`USERS_REGISTER_ALLOW_PUBLIC: "true"` muss im Directus-Container gesetzt sein (docker-compose.yml), damit der `/users/register`-Endpunkt fuer anonyme Requests freigegeben ist. Ohne diesen Flag liefert Directus 403 — auch wenn alle anderen Permissions korrekt konfiguriert sind.
`make seed-users` setzt `public_registration: true` automatisch via `PATCH /settings` — kein manueller UI-Schritt noetig. `make db-reset` ruft `seed-users` mit auf.

**Gotcha — E-Mail-Verifizierung:**
E-Mail-Verifizierung und Auto-Login nach Register sind inkompatibel: Directus schickt nach `/users/register` eine Verifizierungsmail — ein unmittelbarer Login-Versuch schlaegt fehl, weil der Account noch unverifiziert ist.
`make seed-users` setzt `public_registration_verify_email: true` — in allen Umgebungen aktiv. Dev nutzt Mailpit als SMTP-Sink. Auto-Login nach Register entfaellt komplett; stattdessen zeigt das Frontend eine "Check your email"-Box (`registrationSent`-Flag in `login.vue`). User klickt Verifizierungslink → dann erst einloggen.
Directus 11: `/users/verify-email?token=XXX` ist ein reiner API-Endpunkt — nach erfolgreichem Verify erfolgt ein Redirect auf `PUBLIC_URL`. Der Token wird beim ersten Aufruf verbraucht; ein zweiter Klick liefert "Invalid verification code". `PUBLIC_URL` in der Directus-Konfiguration auf `http://localhost:3000/login` (Dev) bzw. die Produktions-URL setzen, damit der Browser nach der Verifizierung direkt zum Login weitergeleitet wird.
Frontend-seitig: `/verify-email.vue` ruft `GET /users/register/verify-email?token=XXX` an Directus auf und leitet bei Erfolg auf `/login?verified=true` weiter. Die Login-Seite zeigt dort ein gruenes Banner "Email verified — you can now sign in."
Directus antwortet auf den Verify-Endpunkt mit **302** (nicht 200) — fetch muss daher mit `redirect: 'manual'` aufgerufen werden, sonst folgt es dem Redirect, bekommt HTML statt JSON und die Fehlerbehandlung schlaegt fehl. Status-Check: `response.ok || response.type === 'opaqueredirect'` (2xx + Redirect = Erfolg).

**Security:** `USER_REGISTER_URL_ALLOW_LIST` im Directus-Container setzen (kommagetrennte erlaubte URL-Prefixes, z.B. `http://localhost:3000,https://decisionmap.example.com`). Ohne diesen Guard akzeptiert Directus jede beliebige `verification_url` im Register-Request — Phishing-Vektor. Directus prueft nur, ob die URL mit einem der erlaubten Prefixes beginnt.

**Gotcha — Directus Permissions nie per direktem SQL setzen:**
`INSERT INTO directus_permissions ...` umgeht den Directus-In-Memory-Cache. Permissions greifen dann erst nach einem Neustart — ohne sichtbare Fehlermeldung erscheint trotzdem 403. Permissions immer ueber die Directus REST API setzen (`PATCH /policies/{id}` oder `POST /permissions`). `make db-permissions` und `make seed-users` verwenden ausschliesslich REST-Aufrufe.

**Gotcha — Alembic-Spalten fehlen im Directus-Schema:**
Spalten die Alembic anlegt (z.B. `deleted_at`, `deleted_by` auf `tags`), sind Directus nicht bekannt, solange sie nicht explizit in `schema.json` definiert oder via Directus API hinzugefuegt werden. Fehlt die Definition, lehnt Directus Filter auf diese Spalte (z.B. `filter[deleted_at][_null]=true`) mit einem Validierungsfehler ab. Fix: Feld via `POST /fields/{collection}` hinzufuegen und `schema.json` aktualisieren, damit es bei `make directus-schema-apply` reproduzierbar ist. Gilt fuer alle Alembic-Spalten — nicht nur `deleted_at`, sondern auch `deleted_by` und andere Audit-Felder.

**Gotcha — Directus M2M Virtual-Field-Naming:**
Directus benennt M2M-Aliasfelder auf der "One"-Seite nach dem `one_field`-Wert in der Relation-Definition — nicht nach dem Junction-Table-Namen. Beispiel: die Relation `problems` → `problem_tag` → `tags` heisst im `readItems`-Ergebnis `tags` (nicht `problem_tag`), weil `one_field: "tags"` gesetzt ist. Ebenso `regions` statt `problem_region`. In `PROBLEM_FIELDS` und `DirectusProblem`-Interface deshalb `tags.tag_id` (nicht `problem_tag.tag_id`) und `regions.region_id` (nicht `problem_region.region_id`) verwenden. Defensiver Null-Guard im Mapper: `raw.tags ?? []` statt direktem Zugriff.

**Gotcha — Directus 11 Nullable-FK-Validierungsbug:**
Directus 11 validiert nullable Foreign-Key-Felder (z.B. `tags.parent_id`, `problems.deleted_by`, `solution_approaches.deleted_by`) zur Laufzeit gegen seine eigene Relation-Metadata — auch wenn PostgreSQL `NULL` erlaubt. Ein `PATCH`-Request mit `null` auf einem solchen Feld schlaegt mit einem Validierungsfehler fehl, obwohl die DB die `NULL`-Schreibung akzeptieren wuerde. Fix: die Directus-Relation-Metadata fuer diese Felder ueber die REST API entfernen (`DELETE /relations/{collection}/{field}`). Die PostgreSQL-FK-Constraint bleibt erhalten — nur Directus prueft nicht mehr. `make db-permissions` / `make seed-users` enthalten diesen Fix idempotent. Symptom: `PATCH` auf Item mit Soft-Delete oder selbst-referenzierendem Parent schlaegt mit 400 fehl.

**Gotcha — Directus Filter-Queries in curl / Shell-Scripts:**
Directus-Filterpfade enthalten eckige Klammern (`filter[field][_eq]=value`). curl interpretiert diese als URL-Bereich und schlaegt mit "URL rejected" fehl. Loesung: `--get --data-urlencode` verwenden oder die gesamte URL in Anfuehrungszeichen setzen und die Klammern mit `%5B`/`%5D` encoden. Beides gilt auch fuer `filter[_and][]`-Arrays.

**Gotcha — Directus User-Rollen und Permissions (Directus 11):**
Neu registrierte User erhalten automatisch die Rolle "User" (`app_access: false`) — sie koennen sich nicht im Directus-Admin-Backend einloggen. Nur der Admin-User hat `admin_access: true`.
Directus 11: Permissions sind nicht direkt an Rollen geknuepft, sondern an **Policy-Objekte** (`directus_policies`), die dann der Rolle (oder direkt dem Public-Access) zugewiesen werden. `make seed-users` legt Role + Policy idempotent an; `make db-permissions` richtet Public- und User-Policy ein.

Permission-Matrix:

| Rolle | READ | CREATE/UPDATE | DELETE |
|---|---|---|---|
| **Public (anonym)** | `problems`, `solution_approaches`, `clusters`, `tags`, `regions`, `problem_cluster`, `problem_tag`, `problem_region` | — | — |
| **User (eingeloggt)** | wie Public + `votes` | `problems`, `solution_approaches`, `tags`, `votes`, `problem_tag` (M2M), `problem_region` (M2M) | `votes`, `problem_tag`, `problem_region` |
| **Admin** | alle | alle | alle |

`votes` ist bewusst nicht in der Public-Policy — Vote-Scores sind in `problems.vote_score` eingebettet, einzelne Stimmen muessen anonym nicht abrufbar sein.

**Wichtig — `fields: ["*"]`:** Jede Permission in der Public-Policy muss `fields: ["*"]` (alle Felder) gesetzt haben. Fehlt diese Angabe, antwortet Directus zwar mit 200, liefert aber leere Objekte — der Graph bleibt leer ohne sichtbaren Fehler. `make db-permissions` setzt dies automatisch.

**Debugging — User bekommt 403 obwohl Permissions korrekt konfiguriert sind:**
Wenn Role → Policy → Permissions alle korrekt gesetzt sind, aber der eingeloggte User trotzdem 403 bekommt, hat er wahrscheinlich **keine Rolle zugewiesen** (`"role": null`). Pruefung:
```bash
curl -s "http://localhost:8055/users?fields=id,email,role&limit=20" \
  -H "Authorization: Bearer $TOKEN"
```
Fehlende Rolle kann passieren wenn `make seed-users` nicht `default_role` in Directus-Settings setzt oder der User vor dem Seed-Lauf angelegt wurde. Loesung: Rolle im Directus-Admin manuell zuweisen oder User loeschen und neu registrieren (nach `make seed-users`).

**Gotcha — Directus 11: `admin_access` nicht mehr auf Role-Objekt:**
In Directus 11 ist `admin_access` von `directus_roles` nach `directus_policies` gewandert. `role.admin_access` existiert nicht mehr und gibt immer `undefined` zurueck — das Admin-Menue bleibt unsichtbar ohne Fehlermeldung.
Korrekte Pruefung: `role.policies?.some(p => p.policy?.admin_access === true)` (Directus gibt `role.policies` als Array von `{policy: {admin_access: boolean}}` zurueck, wenn `policies.policy.admin_access` in `USER_FIELDS` requested wird). In `realAuth.ts`: `USER_FIELDS` muss `"role.policies.policy.admin_access"` enthalten; `mapUser` liest `raw.role?.policies?.some(p => p.policy?.admin_access)`.

**Gotcha — Directus 11: Custom-Felder auf `directus_users` und fehlende Systemfelder:**
`directus_users` hat in Directus 11 kein `date_created`-Feld — `createdAt` muss auf `''` als Fallback gemappt werden (kein Query-Fehler, aber `undefined` wenn requested).
`display_name` und `company` sind nicht im Standard-Schema — sie muessen als Custom-Felder via API (`POST /fields/directus_users`) oder `seed-users.sh` angelegt werden. Fehlen sie, gibt Directus beim Lesen `undefined` zurueck (kein Fehler).
User-Policy braucht ausserdem READ auf `directus_users` (filter: `id == $CURRENT_USER`, alle Felder) und UPDATE auf `directus_users` (filter: `id == $CURRENT_USER`, Felder: `display_name, company`) — ohne diese Permissions schlaegt das Laden und Speichern des User-Profils mit 403 fehl. `make seed-users` richtet beides idempotent ein.

**Flows einrichten (einmalig manuell — nicht im Snapshot):**
Directus Flows verbinden Datenereignisse mit dem AI-Service.

| Flow | Trigger | Ziel |
|---|---|---|
| `problem-submitted` | Action: `problems.items.create` | `POST http://ai-service:8000/hooks/problem-submitted` |
| `problem-approved` | Action: `problems.items.update` (filter: `status=approved`) | `POST http://ai-service:8000/hooks/problem-approved` |
| `solution-approved` | Action: `solution_approaches.items.update` (filter: `status=approved`) | `POST http://ai-service:8000/hooks/solution-approved` |
| `vote-changed` | Action: `votes.items.create/update/delete` | `POST http://ai-service:8000/hooks/vote-changed` |

Jeder Flow: Trigger → HTTP-Request-Action → Ziel-URL, Methode POST, Header `X-Webhook-Secret: <WEBHOOK_SECRET>`.

---

## Datenfluss

```
User reicht Problem ein
    → Directus speichert mit status: pending
    → Directus Flow → POST /hooks/problem-submitted (X-Webhook-Secret Header)
        → _verify_webhook_secret() Dependency pruft Header (leer = Dev-Mode)
        → SpamFilter bewertet (sync, LLM-Call)
            → Klarer Spam: status: rejected (automatisch)
            → Unklar / gultig: status: needs_review
        → DB-Write mit eigener psycopg-Connection
        → background_tasks.add_task(...) → 200 sofort zurueck
        → [async, nach Response]:
            embed (eigene Conn) → solution generieren (eigene Conn)
            → cluster aktualisieren (eigene Conn) → WebSocket broadcast
    → Admin pruft Moderations-Queue
        → Freigegeben: status: approved
    → Frontend liest freigegebene Probleme + Cluster aus Directus
    → Cytoscape.js rendert Graph
```

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

---

## CI/CD — Jenkins Pipeline

Jedes Sub-Repo hat eine eigene Pipeline. Ein Frontend-Deploy triggert keinen Backend-Build.

### Frontend-Pipeline (Reihenfolge invariant)

```
1. checkout
2. npm ci
3. lint (ESLint + Prettier)
4. test (Vitest)
5. docker build (Multi-Stage: build → runner)
6. docker save | ssh → docker load → docker compose up
```

### Deploy-Strategie

`nuxt build` erzeugt einen Node.js-Server (nicht statische Dateien). Das Docker-Image
wird lokal auf dem Jenkins-Agent gebaut und per `docker save | ssh | docker load`
auf den Hetzner-Server uebertragen. Restart via `docker compose up --no-deps --force-recreate frontend`.

**Warum nicht `nuxt generate`?** Die SPA-Routes (`ssr: false`) und dynamische Daten
funktionieren nicht sauber mit statischer Generierung.

**Dockerfile (Multi-Stage):**
- Base Image: `node:20-bookworm-slim` (Debian 12 slim) — nicht Alpine, da native npm-Dependencies sonst musl-Kompatibilitätsprobleme verursachen
- Stage `builder`: `npm ci` + `nuxt build` → erzeugt `.output/`
- Stage `runner`: nur Node.js + `.output/` — kein `node_modules`, kein Source-Code im Image

**Naming-Konvention:** Image- und Container-Namen folgen dem Schema `decisionmap-<service>`
(z.B. `decisionmap-frontend`, `decisionmap-ai-service`, `decisionmap-postgres`).
Definiert in `backend/docker-compose.yml`.

**Jenkinsfile:** Lint + Test laufen auf allen Branches. Build + Deploy nur auf `main`.
Lokales Build-Image wird nach dem Deploy auf dem Jenkins-Agent geloescht.
[`.templates/Jenkinsfile`](../.templates/Jenkinsfile) ist ein generisches Ausgangs-Template — muss fuer die oben beschriebene Deploy-Strategie (docker save|ssh|load) angepasst werden. Konkret: `sh './docker/app/build --build'` → `sh './docker/build.sh --build'` (Pfad auf `docker/build.sh` des Sub-Repos anpassen).

**Build-Script:** [`.templates/docker/build.sh`](../.templates/docker/build.sh) ist das generische Bash-Template fuer Sub-Repo-Build-Skripte. (Das ebenfalls vorhandene `.templates/docker/Dockerfile` ist ein generisches Debian/certbot-Base-Image fuer Tooling — kein Nuxt-Template.) Enthaelt Platform-Erkennung, BashLib-Includes, `--build`/`--push`/`--images`-Flags und TAG-Erzeugung via `hashVer 4 "" .` (→ `26.1.0-SNAPSHOT0327.a3f9`). Benoetigt `DEV_DOCKER`-Env-Variable auf der Build-Maschine (zeigt auf Docker-Hilfsskripte). Pro Sub-Repo nach `docker/build.sh` kopieren und `NAMESPACE`/`NAME`/Deploy-Logik anpassen. **Wichtig:** Der `--push`-Zweig im Template ruft `pushImage2DockerHub` auf — dieser Block muss vollstaendig durch `docker save | ssh | docker load` ersetzt werden (Docker Hub wird nicht verwendet). Das Dockerfile liegt in `docker/`, der Build-Context ist das Parent-Verzeichnis des Sub-Repos (`docker build -f Dockerfile ..`). **Achtung:** Da der Build-Context das gesamte Sub-Repo-Verzeichnis umfasst, muss `docker/` in `.dockerignore` ausgeschlossen werden — sonst landet das Build-Verzeichnis selbst im Image.

**`.dockerignore` fuer Multi-Stage-Builds:** `.output/` muss in `.dockerignore` stehen — nicht weil `COPY --from=builder` den Host liest (das tut es nicht, es greift auf Stage 1 zu), sondern weil `COPY . .` in Stage 1 ein lokales `.output/` (vom Host) in den Build-Context uebertraegt. Das kann ein veraltetes lokales Artefakt in Stage 1 einschleppen, bevor `npm run build` laeuft. `node_modules/` und `.output/` gehoeren daher beide in `.dockerignore`.

### Konfiguration ausserhalb der Pipeline

Das `.env` liegt auf dem Hetzner-Server — Jenkins deployt nur den Build-Artefakt.
Phasenumschaltung ausschliesslich durch Anpassen von `.env` auf dem Server:

```bash
# Phase 1 — Fake-Daten
USE_FAKE_DATA=true

# Phase 2 — Live (Pipeline unveraendert)
USE_FAKE_DATA=false
DIRECTUS_URL=https://...
NUXT_PUBLIC_API_BASE=https://...
```

---

## Makefile-Struktur

Jedes Sub-Repo hat ein eigenes Makefile fuer seinen Kontext. `make help` zeigt die Befehle des jeweiligen Repos.

| Makefile | Zustandig fuer |
|---|---|
| `Makefile` (Root) | Workspace-Setup, Delegation an Sub-Repos, Cross-Repo lint/test |
| `backend/Makefile` | Docker, Datenbank, Backup, Deploy, Versioning |
| `frontend/Makefile` | Dev-Server, Lint, Test, Build, Versioning |
| `ai-service/Makefile` | Dev-Server, Lint, Test, Build, DB-Migrationen, Versioning |

[`.templates/Makefile`](../.templates/Makefile) ist ein generisches Ausgangs-Template. Benoetigt `DEV_MAKE`-Env-Variable (zeigt auf `MakeLib`).

**Versioning-Voraussetzung:** `bumpVer` benoetigt `BASH_LIBS` und eine Versionsdatei (`package.json`, `pyproject.toml` oder `VERSION`). Jedes Sub-Repo muss genau eine davon enthalten:

| Repo | Versionsdatei |
|---|---|
| `backend/` | `VERSION` |
| `frontend/` | `package.json` |
| `ai-service/` | `pyproject.toml` |

```bash
# Workspace-Root
make setup             # .libs/-Symlinks erstellen (einmalig, benoetigt DEV_LOCAL)
make dev-up            # → delegiert an backend/Makefile
make lint              # → delegiert an frontend/ und ai-service/
make test              # → delegiert an frontend/ und ai-service/

# Backend (aus backend/ oder via make -C backend ...)
make up / down / logs                                 # Alle Services
make dev-up / dev-down / dev-logs                     # Dev-Umgebung (Directus + Mailpit)
make db-reset                                         # DB zurücksetzen (schema → constraints → seed)
make directus-schema-apply                            # ↳ Directus-Schema anwenden
make db-constraints                                   # ↳ vector-Spalten, Constraints, Junction-Tables
make db-seed                                          # ↳ Seed-Daten einspielen
make db-migrate / db-rollback / db-migrate-status     # Alembic-Migrationen (nach initialem Setup)
make seed-users                                       # Test-User in Directus
make backup / backup-schema / backup-restore          # Backup
make build / deploy                                   # Build & Deploy
make precheck / version / tags                        # Versioning
make tag-patch / tag-minor / tag-major                # Git-Tag setzen + pushen

# AI-Service (aus ai-service/ oder via make -C ai-service ...)
make install / install-dev                            # Abhaengigkeiten
make lint / format                                    # Code-Qualitaet (ruff)
make test / test-unit / test-contract                 # Tests (pytest)
make dev                                              # uvicorn mit --reload
make build / docker-up / docker-down                  # Docker
make db-migrate / db-migrate-create / db-rollback     # Alembic
make precheck / version / tags                        # Versioning
make tag-patch / tag-minor / tag-major                # Git-Tag setzen + pushen
# → Manuelle curl-Tests aller Endpunkte: docs/cmdline.md

# Frontend (aus frontend/ oder via make -C frontend ...)
make dev / install / lint / format / test             # Entwicklung
make build / deploy                                   # Deploy
make tag-patch / tag-minor / tag-major                # Versioning
```

---

## Versionierung

Build-Scripts verwenden `hashVer` (BashLib-Funktion) — kein klassisches SemVer.

**Format:** `<Jahr>.<Quartal>.0[-<PRERELEASE><MMDD>][<META_SEP><HASH>]`

```
26.1.0-SNAPSHOT0327.a3f9     # Snapshot-Build (Docker-Image-Tag)
26.1.0-SNAPSHOT0327+a3f9     # Snapshot-Build (SemVer-konform, nicht fuer Docker)
26.1.0                        # Release-Tag (manuell gesetzt)
```

**`hashVer`-Parameter:**

| Parameter | Standard | Bedeutung |
|---|---|---|
| `HASH_DIGITS` | — | Laenge des Hash-Anteils (0 = kein Hash) |
| `PRERELEASE_IDENTIFIER` | `SNAPSHOT` | Praefix vor MMDD; leer = kein Praefix |
| `META_SEPARATOR` | `+` | Trenner vor Hash; `.` fuer Docker (`+` ist in Image-Tags ungueltig) |

**Docker-Image-Tags:** `hashVer 4 "" .` → `26.1.0-SNAPSHOT0327.a3f9`
`META_SEPARATOR` muss `.` sein — Docker lehnt `+` in Tags ab.

**Alternative: `semVerWithDate`** — wenn `package.json`-Version als Basis benoetigt wird:
`semVerWithDate "" . 1 4` → `1.2.3-build-260327.1445.a3f9` (+ `.dirty` bei uncommitted changes).
Vorteil: Version stammt aus dem Git-Tag (`vX.Y.Z`), enthaelt Datum+Uhrzeit und dirty-Flag.
Voraussetzung: Git-Tag bei jedem `package.json`-Versionssprung setzen.

**`bumpVer` / `gitUpdateVersionTag`** — fuer Git-Tags und Versionsdateien (`package.json`, `pyproject.toml`, `VERSION`):

```
v26.3.0+260327.1445     # Release-Tag mit Timestamp (SemVer Build-Metadata)
v26.3.0-rc1+260327.1445 # Pre-Release
```

Format: `v<YY>.<minor>.<patch>[+<YYMMDD.HHMM>]` — kein Hash-Anteil, kein Quartal-Zwang.
`gitUpdateVersionTag` ist idempotent: Falls HEAD bereits getaggt ist, wird der bestehende Tag zurueckgegeben.

**Tag-Ordering bei `bumpVer`:** Git-Tag immer **nach** dem Commit setzen, nicht davor.
Begruendung: `git checkout v26.1.0` muss einen konsistenten Stand liefern — `package.json` und Tag zeigen auf denselben Commit.
Reihenfolge: `_gitCalcNextVersion` → Datei schreiben → `git commit` → `_gitSetVersionTag`.

**Makefile-Targets fuer Version-Bumping (Sub-Repos):**

```makefile
tag-patch   # Patch hochzaehlen  (26.3.0 → 26.3.1)
tag-minor   # Minor hochzaehlen  (26.3.0 → 26.4.0)
tag-major   # Major hochzaehlen  (26.3.0 → 27.0.0)
```

Diese Targets rufen `bumpVer` auf und setzen den Git-Tag automatisch nach dem Commit.
Snapshot-Tags (Docker-Image-Tags via `hashVer`) werden automatisch vom Jenkins-Build erzeugt — nie manuell.

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

---

## Seed-Daten

SQL-Files in `database/seeds/` — alphabetisch importiert, idempotent (`ON CONFLICT DO NOTHING`).

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

---

## Backup

```bash
make backup              # vollstandiges DB-Backup
make backup-schema       # nur Schema
make backup-restore FILE=database/backups/2024-03-15_120000.sql
make backup-remote       # Backup von Hetzner holen
```

```makefile
backup:
	@mkdir -p database/backups
	@TIMESTAMP=$$(date +%Y-%m-%d_%H%M%S) && \
	  docker compose exec postgres pg_dump -U $${POSTGRES_USER} -d $${POSTGRES_DB} \
	    --no-owner --no-acl -f /tmp/backup_$${TIMESTAMP}.sql && \
	  docker compose cp postgres:/tmp/backup_$${TIMESTAMP}.sql \
	    database/backups/$${TIMESTAMP}.sql

backup-remote:
	ssh hetzner "cd /app && make backup"
	scp hetzner:/app/database/backups/$$(ssh hetzner "ls -t /app/database/backups | head -1") \
	  database/backups/
```

Backups nie einchecken — `database/backups/` in `.gitignore`.
