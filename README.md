<p align="center">
  <img src="assets/images/decisionmap-logo-gradient-light.svg" alt="DecisionMap" width="320" />
</p>

# DecisionMap

Eine kollektive Wissensplattform für KI-bezogene Probleme in Unternehmen.

Unternehmen stehen bei der Einführung von KI vor ähnlichen Herausforderungen — aber jedes löst sie isoliert.
DecisionMap macht dieses verteilte Wissen sichtbar: User erfassen reale Probleme, andere liefern
Lösungsansätze, ein KI-Service clustert die Eingaben und visualisiert sie als interaktive Mindmap.

**Zielgruppe:** IT-Entscheider, CDOs, KI-Projektverantwortliche in KMU  
**Domain:** `decisionmap.ai` (Fallback: `frictionmap.ai`)

---

## Wie es funktioniert

1. **Problem erfassen** — kurze Beschreibung eines realen KI-Problems aus dem Unternehmensalltag
   (z.B. Shadow AI, Modellauswahl, Compliance, Datenschutz bei KI-Tools)
2. **Lösungsansätze beisteuern** — keine fertigen Rezepte, sondern Erfahrungen aus der Praxis
3. **KI clustert automatisch** — ähnliche Probleme werden gruppiert und in eine Tag-Hierarchie eingeordnet
4. **Visualisierung** — ein interaktiver Graph zeigt die Problemlandschaft, mit Drill-down zu Details

Kein Beratungstool. Keine Diskussionsplattform. Eine strukturierte, KI-unterstützte Wissensbasis
mit Community-Validierung durch Voting.

---

## Technischer Stack

| Schicht | Technologie | Zweck |
|---|---|---|
| Frontend | Nuxt.js 3 + TypeScript | SPA/SSR-Hybrid, Auto-Imports, SEO-ready |
| CSS | Tailwind CSS | Utility-Klassen, Theme-System per CSS Custom Properties |
| Visualisierung | Cytoscape.js | Interaktive Graph-Darstellung |
| Backend | FastAPI + fastapi-users + SQLAlchemy (asyncio) | Auth, REST API, WebSocket, Admin-Endpoints |
| Datenbank | PostgreSQL + pgvector | Relationale Daten + Embeddings in einer DB |
| KI-Service | FastAPI (Python 3.11+) | Embeddings, Clustering, Spam-Filter, Übersetzung |
| DB-Migrationen | Alembic | Python-nativ, rollbackfähig |
| Echtzeit | WebSocket (FastAPI) | Live-Updates im Multi-User-Betrieb |
| Testing | Vitest / pytest | Unit- und Contract-Tests |
| Hosting | Hetzner + Docker + nginx | Europäisch (DSGVO), Docker Compose |
| CI/CD | Jenkins → SSH → Hetzner | Lokale Jenkins-Instanz |

---

## Repository-Struktur

Multi-Repo — fünf Repositories mit eigenem Release-Zyklus:

```
DecisionMap/                     ← Workspace-Root (Issues, Doku, CI-Koordination)
├── CLAUDE.md                    ← Technische Haupt-Referenz für alle Repos
├── README.md                    ← Dieses File
├── Makefile                     ← Workspace-Orchestrierung
├── data/                        ← Gemeinsame Seed-Daten (SSoT, snake_case JSON)
├── docs/                        ← Detaillierte Spezifikationen
│   ├── backend.md               ← Infrastruktur, Deploy, Versionierung
│   ├── conventions.md           ← Code-Konventionen mit Beispielen
│   ├── data-model.md            ← Vollständiges Datenbankschema
│   ├── features.md              ← Feature-Spezifikationen
│   ├── dev-environment.md       ← Lokale Entwicklungsumgebung (Ports, Fake-Daten, venv)
│   ├── cmdline.md               ← curl-Beispiele für alle API-Endpunkte
│   └── ses-setup.md             ← AWS SES: Domain-Verifizierung → SMTP → Production Access
├── scripts/                     ← Workspace-Skripte
│   ├── db-backup.sh             ← Einheitliches DB-Backup/Restore (Backend + Infrastructure)
│   ├── env-audit.py             ← .env vs .env.example Drift-Erkennung (alle Repos, CI-fähig)
│   ├── gen-fakedata.py          ← Verteilt Seed-Daten an Consumer-Repos
│   ├── git-push-all.sh          ← Git-Push in allen ausgecheckten Sub-Repos
│   ├── repo-status.sh           ← Git-Status aller Sub-Repos
│   └── smtp-test.py             ← SMTP-Relay-Verifikation (AWS SES)
├── .templates/                  ← Wiederverwendbare Templates (Jenkinsfile, Makefile, Docker)
├── .libs/                       ← Lokale Symlinks (BashLib, MakeLib) — gitignored
├── apps/                        ← Service-Repos (gitignored, eigene Repos)
│   ├── backend/                 ← FastAPI Backend + Alembic (Schema-Owner)
│   ├── frontend/                ← Nuxt.js App
│   └── ai-service/              ← FastAPI KI-Service (kein direkter DB-Zugriff)
└── infrastructure/              ← docker-compose, nginx (eigenes Repo)
```

`apps/backend/`, `apps/frontend/`, `apps/ai-service/` und `infrastructure/` haben eigene Git-Repos
und sind per `.gitignore` aus dem Root ausgeschlossen.

---

## Makefile — Wichtigste Targets

```bash
make help          # Alle verfügbaren Befehle anzeigen
make hints         # Lokale URLs (via Dev-Proxy + direkt) und nützliche Links
make info          # Workspace-Umgebungsvariablen
make setup         # .libs/-Symlinks erstellen (einmalig nach dem Klonen)
make status        # Git-Status aller Sub-Repos (dirty + ahead/behind Remote)
```

`make help` unterstützt Farbthemen via `MAKE_THEME` (in `.env` oder als Umgebungsvariable):
```bash
make help                      # classic (Standard, Gelb/Blau/Grün)
make help MAKE_THEME=ocean     # Cyan/Türkis
make help MAKE_THEME=earth     # Warme Brauntöne
make help MAKE_THEME=night     # Violett/Lavendel
make help MAKE_THEME=mono      # Schwarz/Weiß
make help MAKE_THEME=sunset    # Rosa/Lachs
make help MAKE_THEME=forest    # Dunkelgrün/Limette
make help MAKE_THEME=neon      # Magenta/Neongrün
```

**Daten:**
```bash
make fakedata-sync # Seed-Daten aus data/ an Frontend + AI-Service verteilen
```

**Versionierung:**
```bash
make version       # Aktuelle Versionen aller Sub-Repos anzeigen
make tags          # Letzte 10 Git-Tags mit Datum
```

**Cross-Repo:**
```bash
make git-push-all  # Git-Push in allen ausgecheckten Sub-Repos
make build-all     # Docker-Images bauen (backend + frontend + ai-service)
make push-all      # Images nach ghcr.io pushen
make test-all      # Alle Tests ausführen
make deploy        # Full-Stack Deploy via infrastructure/
```

Sub-Repo-Makefiles:
```bash
make -C apps/backend help      # FastAPI Backend, DB, Backup
make -C apps/frontend help     # dev, lint, test, build
make -C apps/ai-service help   # FastAPI dev, test, build
make -C infrastructure help    # Server-Orchestrierung
```

---

## Lokale Entwicklung

```bash
make dev-up    # nginx-Proxy + Docker (Postgres + Backend-API :8001) + overmind (Frontend :3000 + AI-Service :8000)
make dev-down  # overmind beenden + alle Docker-Services stoppen
```

**Via Dev-Proxy** (`make dev-nginx-up`):

| URL | Dienst |
|---|---|
| http://int.decisionmap.ai | App (Frontend) |
| http://backend.int.decisionmap.ai | Backend API (FastAPI) |
| http://int.decisionmap.ai/api/docs | AI-Service (Swagger) |

**Direkt** (ohne Proxy):

| URL | Dienst |
|---|---|
| http://localhost:3000 | Frontend |
| http://localhost:8001 | Backend API (FastAPI) |
| http://localhost:8001/docs | Backend Swagger |
| http://localhost:8000 | AI-Service |
| http://localhost:8000/docs | AI-Service Swagger |
| http://localhost:8025 | Mailpit (SMTP-Sink) |
| http://localhost:8080 | Adminer (DB-UI, Server: `postgres`) |

Voraussetzung: `overmind` installiert (`brew install overmind`).

→ **Vollständige Anleitung (Ersteinrichtung, Ports, Fake-Daten, venv-Gotchas):** [`docs/dev-environment.md`](docs/dev-environment.md)

---

## Architektur-Prinzipien

**Trennung von UI und Logik:**
- Frontend: Komponenten = Darstellung, Composables = Logik + API-Kommunikation
- Backend: Router = HTTP, Services = Fachlogik (Services kennen kein HTTP)

**Validierung auf drei Schichten:**
Zod (Frontend) → Pydantic (Backend) → PostgreSQL Constraints

**Kein Hard Delete:**
Alle Entitäten werden per `deleted_at`/`deleted_by` weich gelöscht.

**Mehrsprachigkeit im Datenmodell:**
Jedes Textfeld existiert doppelt — Original + `_en`. Embeddings und Clustering laufen nur auf `_en`-Feldern.

---

## KI-Features

### Ähnlichkeitserkennung

Verhindert Duplikate bereits während der Eingabe:
- Debounced-Prüfung (600ms) via pgvector Cosine-Similarity
- Score ≥ 0.85: Hinweis mit Link zum ähnlichen Problem
- Score ≥ 0.92: Wahrscheinliches Duplikat — Submit erfordert Bestätigung

### Spam-Filter (mehrstufig)

1. nginx Rate Limiting (5 Req/Minute pro IP)
2. Verhaltens-Signale (zu schneller Submit, Session-Flood, Bot-Agents)
3. Honeypot-Feld (verstecktes HTML-Feld)
4. GPT-4o-mini als letzte Instanz

Kein CAPTCHA — Friction-freies UX ist Designziel.

### Automatisches Clustering

Ein zyklischer Job analysiert alle freigegebenen Probleme:

1. Embeddings aller Probleme laden
2. HDBSCAN-Clustering → findet natürliche Gruppen (keine vorgegebene Anzahl nötig)
3. LLM (GPT-4o) labelt jede Gruppe → erzeugt hierarchische Tags (L1–L9)
4. Sub-Clustering innerhalb großer Gruppen → tiefere Hierarchie-Ebenen
5. Probleme mit neuen Tags verknüpfen

### Moderation-Workflow

```
eingereicht → pending
    ↓ KI-Spam-Filter
klarer Spam → rejected (automatisch)
unklar/ok   → needs_review
    ↓ Admin-Queue
freigegeben → approved → Embedding + Clustering + KI-Lösungsansatz generiert
abgelehnt   → rejected
```

---

## Tag-Hierarchie

Das Ordnungsprinzip für den Graph:

| Level | Erstellt von | Beschreibung |
|---|---|---|
| L0 | System | Wurzelknoten der Plattform |
| L1–L9 | KI (automatisch) | Hierarchische Kategorien aus Problemanalyse |
| L10 | User | Freie Tags (z.B. „shadow-ai", „compliance") |

L0 und L10 bleiben beim Clustering immer erhalten — nur L1–L9 werden neu generiert.

---

## Datenmodell (Übersicht)

Vollständige Spezifikation: [`docs/data-model.md`](docs/data-model.md)

```
users ──< problems ──< solution_approaches
              │
              ├──>< problem_cluster >──< clusters
              ├──>< problem_tag    >──< tags (L0–L10)
              └──>< problem_region >──< regions
```

| Tabelle | Zweck |
|---|---|
| `problems` | KI-Probleme mit Status-Workflow, Embedding, Original + EN |
| `solution_approaches` | Lösungsansätze pro Problem (Markdown) |
| `tags` | Hierarchische Tags (L0 Root → L1–L9 KI → L10 User) |
| `clusters` | KI-generierte Problemfelder mit Centroid-Vektor |
| `votes` | Up-/Downvotes, DSGVO-konform über `ip_hash` |
| `edit_history` | Änderungsverfolgung (nur Moderatoren) |
| `moderation_log` | Audit-Trail aller Entscheidungen |

---

## Versionierung

Zwei Mechanismen — Details: [`docs/backend.md`](docs/backend.md)

- **Release-Tags:** SemVer + Datum via `bumpVer` → `v0.1.0+260411.1430`
- **Docker-Snapshots:** `gitDockerTag` → `0.1.0-260412.0824.def34` — automatisch via Jenkins

Version pro Sub-Repo ablesen:
```bash
make version
```

---

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Technische Haupt-Referenz, Gotchas, Konventionen (kompakt) |
| [`docs/backend.md`](docs/backend.md) | Infrastruktur, Deploy, Makefile, Versionierung |
| [`docs/conventions.md`](docs/conventions.md) | Code-Konventionen mit Beispielen |
| [`docs/data-model.md`](docs/data-model.md) | Vollständiges Datenbankschema |
| [`docs/features.md`](docs/features.md) | Feature-Spezifikationen im Detail |
| [`docs/dev-environment.md`](docs/dev-environment.md) | Lokale Entwicklungsumgebung (Ports, Fake-Daten, WebSocket, venv) |
| [`docs/ses-setup.md`](docs/ses-setup.md) | AWS SES: Domain-Verifizierung → SMTP → Production Access |
| [`docs/cmdline.md`](docs/cmdline.md) | curl-Beispiele für alle API-Endpunkte |

---

## Aktueller Stand

Beide Data-Layer (Fake + Real) sind vollständig implementiert.

- **Frontend:** 180 Tests in 15 Dateien grün — Composables, Contract-Tests (Fake & Real)
- **Backend:** 14 Unit-Tests grün
- **AI-Service:** 37 Unit-Tests grün

**Hetzner-Infrastruktur (in Betrieb):** nginx + TLS + Docker Compose laufen. SMTP: AWS SES (Domain-Verifizierung abgeschlossen, Sandbox-Modus). Tracking: MikeMitterer/decmap_project#1. AI-Service-Image (`decisionmap-ai-service`) auf ghcr.io, deploy via `make -C infrastructure deploy-service SVC=ai-service`.

**Backend-Migration (Phase 8 abgeschlossen):** Directus vollständig entfernt. Stack: FastAPI (`apps/backend/`, Port 8001) + fastapi-users + SQLAlchemy asyncio. Phase 7: AI-Service nutzt `BackendClient` (httpx) statt direktem DB-Zugriff — `app/repositories/` gelöscht, `psycopg[binary]` entfernt. Phase 8: Directus aus docker-compose, nginx, env vars, CLAUDE.md entfernt — `cms.decisionmap.ai` → `api.decisionmap.ai` (Port 8001), `useDirectusRealtime.ts` → `useBackendRealtime.ts`.

→ Details: [`docs/backend.md`](docs/backend.md)

**Offene Punkte:**
- Clustering-Job implementieren (HDBSCAN + LLM-Labeling im ai-service)
- Bulk-Reindex: `POST /embeddings/reindex` (AI-Service) implementiert; Backend `GET /internal/problems/approved-all` (ohne Embedding-Filter) fehlt noch — nötig für initiale Befüllung und Re-Embedding nach Modellwechsel
- DNSBL-Check aktivieren (nach Launch bei Bedarf)
- E2E-Tests mit Playwright
- Regionsbasierte Filterung und Ranking

**Code-Review 2026-05-18 — alle Bugs gefixt (23 Fixes, alle Tests grün):**

Backend:
- B1: `PATCH`/`DELETE /problems` — Ownership-Check + Superuser-Gate ergänzt
- B2: Startup-Warnung bei Default-Werten für `SECRET_KEY`, `SERVICE_TOKEN`, Wildcard-CORS
- B3: `store_embedding` + `update_status` in `internal.py` filtern jetzt `deleted_at IS NULL`
- B4: `pages/auth/magic-verify.vue` angelegt — Frontend-Landingpage für Magic-Link-Token
- B5: WS-Broadcasts nach `create_ai_solution` + `upsert_cluster` in `internal.py` ergänzt

AI-Service:
- A1–A4: `test_security.py`, `database/`-Dir, `mock_db_conn`-Fixture, tote Config-Felder entfernt
- A6: `generate_embedding`-Closure ruft `get_embedding_provider()` intern auf (kein Request-Scope-Leak)
- A7: Veralteter Directus-Kommentar in `main.py` ersetzt

Frontend:
- F1: `isTextFieldActive()` in `table.vue:255` korrekt deklariert
- F2: Vote-Buttons in `/problem/[id].vue` zeigen aktiven State nach Vote (kein Permanent-Disable)
- F3: Admin-Middleware leitet eingeloggten Non-Admin auf `/` statt `/login`
- F4: `problemTags` in `realTags.ts` als `computed` ref (reaktiv, kein staler Snapshot)
- F5: External-Update-Banner-Strings nach i18n verschoben
- F6: Toter `mockDirectusUser`-Alias + 11 Directus-Testdateien aus `apps/backend/tests/` entfernt
- F7: Ping-Intervall startet in `socket.onopen`, stoppt in `onclose`/`disconnect()`
