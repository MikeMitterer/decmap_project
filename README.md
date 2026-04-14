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
| CMS / Backend | Directus | Admin Panel, Auth, REST API (self-hosted) |
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
│   └── cmdline.md               ← curl-Beispiele für alle API-Endpunkte
├── scripts/                     ← Workspace-Skripte
│   ├── db-backup.sh             ← Einheitliches DB-Backup/Restore (Backend + Infrastructure)
│   ├── gen-fakedata.py          ← Verteilt Seed-Daten an Consumer-Repos
│   └── repo-status.sh           ← Git-Status aller Sub-Repos
├── .templates/                  ← Wiederverwendbare Templates (Jenkinsfile, Makefile, Docker)
├── .libs/                       ← Lokale Symlinks (BashLib, MakeLib) — gitignored
├── apps/                        ← Service-Repos (gitignored, eigene Repos)
│   ├── backend/                 ← Directus-Konfiguration + Seeds
│   ├── frontend/                ← Nuxt.js App
│   └── ai-service/              ← FastAPI + Alembic
└── infrastructure/              ← docker-compose, nginx (eigenes Repo)
```

`apps/backend/`, `apps/frontend/`, `apps/ai-service/` und `infrastructure/` haben eigene Git-Repos
und sind per `.gitignore` aus dem Root ausgeschlossen.

---

## Makefile — Wichtigste Targets

```bash
make help          # Alle verfügbaren Befehle anzeigen
make info          # Workspace-Umgebungsvariablen
make setup         # .libs/-Symlinks erstellen (einmalig nach dem Klonen)
make status        # Git-Status aller Sub-Repos (dirty + ahead/behind Remote)
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
make -C apps/backend help      # Directus, DB, Backup
make -C apps/frontend help     # dev, lint, test, build
make -C apps/ai-service help   # FastAPI dev, test, build
make -C infrastructure help    # Server-Orchestrierung
```

---

## Lokale Entwicklung

```bash
make dev-up    # Docker (Postgres + Directus) + overmind (Frontend :5000 + AI-Service :8000)
make dev-down  # Docker-Services stoppen
```

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
| [`docs/cmdline.md`](docs/cmdline.md) | curl-Beispiele für alle API-Endpunkte |

---

## Aktueller Stand

Beide Data-Layer (Fake + Real) sind vollständig implementiert.

- **Frontend:** 172 Tests in 15 Dateien grün — Composables, Contract-Tests (Fake & Real)
- **AI-Service:** 31 Unit-Tests grün

**Hetzner-Infrastruktur (in Betrieb):** nginx + TLS + Docker Compose laufen. Directus auf Subdomain `cms.decisionmap.ai` (kein `/cms`-Pfad-Prefix, `PUBLIC_URL=https://cms.decisionmap.ai`). SMTP noch offen (Blocker — User-Registrierung): AWS SES in Einrichtung (Domain-Verifizierung läuft, Sandbox-Modus). Tracking: MikeMitterer/decmap_project#1. AI-Service-Image (`decisionmap-ai-service`) auf ghcr.io, deploy via `make -C infrastructure deploy-service SVC=ai-service`.

**Echtzeit-Vote-Updates implementiert:** `useDirectusRealtime.ts` subscribed auf `problems.update` via Directus WebSocket — `trg_vote_score` hält `vote_score` synchron, kein AI-Service-Umweg. Erfordert `WEBSOCKETS_ENABLED=true` + `WEBSOCKETS_REST_AUTH=public` in `backend/.env`.

Noch ausstehend: Directus-Schema-Import + API-Token + Flows konfigurieren
(HTTP-Webhooks auf `http://ai-service:8000/hooks/*` für `problem-submitted`, `problem-approved` etc.)
`vote-changed`-Flow per Script anlegbar: `make -C infrastructure setup-vote-flow`
→ Details: [`docs/backend.md`](docs/backend.md)

**Offene Punkte:**
- Clustering-Job implementieren (HDBSCAN + LLM-Labeling im ai-service)
- DNSBL-Check aktivieren (nach Launch bei Bedarf)
- E2E-Tests mit Playwright
- Regionsbasierte Filterung und Ranking
