# Infrastructure und Operations

## Umgebungsvariablen

Nie hardcoden. Immer aus der Umgebung lesen. Alle in `.env.example` dokumentiert.

```
OPENAI_API_KEY=           # OpenAI API-Key fur Embeddings und Filterung
DIRECTUS_URL=             # Directus-Instanz URL
DIRECTUS_TOKEN=           # Directus Admin-Token
POSTGRES_URL=             # PostgreSQL Connection String
CLUSTERING_INTERVAL=360   # Batch-Clustering-Intervall in Minuten
SHOW_VOTING=false         # Feature Flag: Voting-Visualisierung aktivieren
SIMILARITY_THRESHOLD=0.85 # Schwellenwert fur Ahnlichkeitserkennung (0.0–1.0)
TRANSLATION_MODEL=gpt-4o-mini  # Modell fur automatische Ubersetzung
WS_URL=ws://localhost:8000     # WebSocket-URL des FastAPI-Service
USE_FAKE_DATA=true             # true = in-memory Fake-Daten, false = echter Server
BOT_SUBMIT_MIN_SECONDS=10     # Mindestzeit zwischen Seitenaufruf und Submit
BOT_SESSION_MAX_HOURLY=10     # Max. Submissions pro Session pro Stunde
BOT_IP_MAX_SESSIONS=5         # Max. verschiedene Sessions pro ip_hash
```

## Feature Flags

| Flag | Standard | Beschreibung |
|---|---|---|
| `SHOW_VOTING` | `false` | Vote-Scores in der Graph-Visualisierung anzeigen |
| `REQUIRE_AUTH` | `false` | Login fur Einreichungen erzwingen |

---

## Datenfluss

```
User reicht Problem ein
    → Directus speichert mit status: pending
    → Webhook lost KI-Service aus
    → [geplant] DNSBL-Check in FastAPI Middleware
    → Spam-Filter bewertet
        → Klarer Spam: status: rejected (automatisch)
        → Unklar / gultig: status: needs_review
    → Admin pruft Moderations-Queue
        → Freigegeben: status: approved
        → Embedding wird generiert
        → Batch-Cluster-Job aktualisiert problem_cluster
        → KI generiert Losungsansatz (is_ai_generated: true)
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

## Makefile

Alle haufigen Operationen uber `make`. `make help` zeigt alle Befehle.

```makefile
# Entwicklung
up / down / logs

# Code-Qualitat
lint / lint-frontend / lint-backend
format / format-frontend / format-backend

# Testing
test / test-frontend / test-backend

# Datenbank
db-migrate / db-migrate-create / db-migrate-status / db-rollback
db-seed / db-reset (nur lokal!)

# Backup
backup / backup-schema / backup-restore / backup-remote

# Build / Deploy
build / deploy
```

---

## Versionierung

**Format:** `<TAG-oder-0.0.0>[-PRERELEASE][+YYMMDD.HHMM.<hash>[.dirty]]`

| Teil | Bedeutung |
|---|---|
| MAJOR | Breaking Change |
| MINOR | Neues Feature (ruckwartskompatibel) |
| PATCH | Bugfix (ruckwartskompatibel) |

```
1.0.0                              # Release
1.0.0-beta.1                       # Pre-Release
1.0.0+240315.1430.a3f9c2d          # Build-Metadata
0.0.0+240315.1430.a3f9c2d          # Vor dem ersten Tag
```

Build-Metadata automatisch vom Jenkins-Build — nie manuell.

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

- Kein direktes Committen auf `main`
- `main` ist immer deploybar
- Feature-Branches per PR/MR mergen

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
