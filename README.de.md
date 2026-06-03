<p align="center">
  <img src="assets/images/decisionmap-logo-gradient-light.svg" alt="DecisionMap" width="320" />
</p>

# DecisionMap

**Die kollektive KI-Problemlandkarte für den Mittelstand.**

Irgendwo in einem anderen Unternehmen kämpft gerade jemand mit exakt demselben KI-Problem wie du.
Ihr werdet euch nie begegnen. DecisionMap ändert das.

User erfassen reale KI-Herausforderungen aus ihrem Unternehmensalltag — Shadow AI, Modellauswahl,
Compliance, Datenschutz bei KI-Tools. Andere liefern Lösungsansätze aus der Praxis. Ein KI-Service
clustert die Eingaben automatisch und visualisiert sie als interaktive Problemlandkarte.

**Kein Beratungstool. Keine Diskussionsplattform. Eine strukturierte, KI-gestützte Wissensbasis
mit Community-Validierung durch Voting.**

**Zielgruppe:** IT-Entscheider, CDOs, KI-Projektverantwortliche in KMU  
**Domain:** [decisionmap.ai](https://decisionmap.ai)

[English Version](README.md)

---

## Status

> **Pre-Beta** — Die Plattform ist technisch fertig, wird aber noch nicht öffentlich beworben.
> Ich suche 10–15 Unternehmen für den Beta-Test. Interesse? → [Issue öffnen](https://github.com/MikeMitterer/decmap_project/issues/new) oder direkt melden.

- Frontend: 180 Tests grün
- Backend: 101 Tests grün
- AI-Service: 124 Tests grün
- E2E: 9 Tests grün (Playwright)
- Infrastruktur: Hetzner + Docker + nginx + TLS in Betrieb
- SMTP: AWS SES (Domain-Verifizierung abgeschlossen)

---

## Wie es funktioniert

1. **Problem erfassen** — kurze Beschreibung eines realen KI-Problems aus dem Unternehmensalltag
2. **Lösungsansätze beisteuern** — keine fertigen Rezepte, sondern Erfahrungen aus der Praxis
3. **KI clustert automatisch** — ähnliche Probleme werden gruppiert und in eine Tag-Hierarchie eingeordnet
4. **Visualisierung** — ein interaktiver Graph zeigt die Problemlandschaft, mit Drill-down zu Details

---

## Entwicklungsansatz

Dieses Projekt entstand als Experiment in **Vibe-Coding** — KI-gestützter Entwicklung bei der
Architekturentscheidungen, Debugging und Implementierung in enger Zusammenarbeit mit KI-Assistenten
entstehen. Gleichzeitig ist es ein echtes Produkt mit echten Nutzern als Ziel.

Was das konkret bedeutet:
- Alle Architekturentscheidungen sind dokumentiert (CLAUDE.md, docs/)
- Entscheidungsprozesse und Erkenntnisse werden öffentlich geteilt
- Der Stack wurde bewusst für AI-Engineering-Kompetenz gewählt — pgvector, HDBSCAN, LLM-Integration — nicht weil es die einfachste Option war

Der interessante Teil passiert gerade jetzt. Fortschritt und Erkenntnisse gibt es auf
[LinkedIn](https://www.linkedin.com/in/mangolila/).

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
| Testing | Vitest / pytest / Playwright | Unit-, Contract- und E2E-Tests |
| Hosting | Hetzner + Docker + nginx | Europäisch (DSGVO), Docker Compose |
| CI/CD | Jenkins → SSH → Hetzner | Lokale Jenkins-Instanz |

---

## Repository-Struktur

Multi-Repo — fünf Repositories mit eigenem Release-Zyklus:

```
DecisionMap/                     ← Workspace-Root (Issues, Doku, CI-Koordination)
├── CLAUDE.md                    ← Technische Haupt-Referenz für alle Repos
├── README.md                    ← English version
├── README.de.md                 ← Dieses File (Deutsch)
├── Makefile                     ← Workspace-Orchestrierung
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

**Cross-Repo:**
```bash
make git-push-all  # Git-Push in allen ausgecheckten Sub-Repos
make build-all     # Docker-Images bauen (backend + frontend + ai-service)
make push-all      # Images nach ghcr.io pushen
make test-all      # Alle Tests ausführen
make deploy        # Full-Stack Deploy via infrastructure/
make version       # Aktuelle Versionen aller Sub-Repos anzeigen
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
make dev-up    # nginx-Proxy + Docker (Postgres + Backend-API :8001) + overmind (Frontend :3000 + AI-Service :8000 + Backend-Logs)
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

→ **Vollständige Anleitung:** [`docs/dev-environment.md`](docs/dev-environment.md)

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

- Debounced-Prüfung (600ms) via pgvector Cosine-Similarity
- Score ≥ 0.85: Hinweis mit Link zum ähnlichen Problem
- Score ≥ 0.92: Wahrscheinliches Duplikat — Submit erfordert Bestätigung → landet in Review-Queue (kein Auto-Reject)

### Spam-Filter

**Probleme (mehrstufig):**

1. nginx Rate Limiting (5 Req/Minute pro IP)
2. Verhaltens-Signale (zu schneller Submit, Session-Flood, Bot-Agents)
3. Honeypot-Feld (verstecktes HTML-Feld)
4. GPT-4o-mini als letzte Instanz

Kein CAPTCHA — Friction-freies UX ist Designziel.

**Lösungsansätze (nach Login, nur LLM):**
- GPT-4o-mini prüft den Inhalt — kein Verhaltens-Layer nötig (Auth vorausgesetzt)

### Automatisches Clustering

1. Embeddings aller Probleme laden
2. HDBSCAN-Clustering (L2-normalisierte Embeddings, euclidean metric, adaptive `min_cluster_size = max(2, sqrt(n/4))`)
3. LLM (GPT-4o) labelt jede Gruppe → erzeugt hierarchische Tags (L1–L9)
4. Sub-Clustering innerhalb großer Gruppen → tiefere Hierarchie-Ebenen
5. Probleme mit neuen Tags verknüpfen

### Moderation-Workflow

**Probleme:**
```
eingereicht → [Verhaltens-Signale] ─→ needs_review ─→ [Admin] → approved / rejected
            → [LLM-Spam-Filter]   ─→ pending       ─→ [Admin] → approved / rejected
                                   ↘ Spam → rejected (automatisch)
```

**Lösungsansätze** (nach Login, kein Verhaltens-Layer):
```
eingereicht → [LLM-Spam-Filter] → pending → [Admin] → approved / rejected
                                ↘ Spam → rejected (automatisch)
```

---

## Tag-Hierarchie

| Level | Erstellt von | Beschreibung |
|---|---|---|
| L0 | System | Wurzelknoten der Plattform |
| L1–L9 | KI (automatisch) | Hierarchische Kategorien aus Problemanalyse |
| L10 | User | Freie Tags (z.B. „shadow-ai", „compliance") |

---

## Datenmodell (Übersicht)

Vollständige Spezifikation: [`docs/data-model.md`](docs/data-model.md)

```
users ──< problems ──< solution_approaches
              │
              ├──>< problem_tag    >──< tags (L0–L10)
              └──>< problem_region >──< regions
```

| Tabelle | Zweck |
|---|---|
| `problems` | KI-Probleme mit Status-Workflow, Embedding, Original + EN |
| `solution_approaches` | Lösungsansätze pro Problem (Markdown) |
| `tags` | Hierarchische Tags (L0 Root → L1–L9 KI → L10 User) |
| `votes` | Up-/Downvotes, DSGVO-konform über `ip_hash` |
| `edit_history` | Änderungsverfolgung (nur Moderatoren) |
| `moderation_log` | Audit-Trail aller Entscheidungen |

---

## Roadmap

**Erledigt:**
- [x] FastAPI Backend + Auth (fastapi-users, JWT, Magic Link, E-Mail-Verifizierung)
- [x] pgvector Ähnlichkeitserkennung + Duplikat-Filter
- [x] HDBSCAN-Clustering + LLM-Labeling → hierarchische Tags
- [x] Spam-Filter: mehrstufig für Probleme (Rate Limiting → Honeypot → GPT-4o-mini), LLM-only für Lösungsansätze
- [x] WebSocket Echtzeit-Updates (Voting, Graph-Änderungen)
- [x] Moderations-Workflow (Admin-Queue, Batch-Operationen)
- [x] Cytoscape.js Graph-Visualisierung
- [x] Theme-System (6 Presets + Custom)
- [x] Hetzner-Infrastruktur + TLS + AWS SES

**Nächste Schritte:**
- [ ] Clustering Smoke-Test verifizieren
- [ ] Beta-Zugang für erste Unternehmen
- [ ] Stripe-Integration (SaaS-Pricing)
- [ ] Regionsbasierte Filterung und Ranking
- [ ] DNSBL-Check aktivieren (post-Launch)

---

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Technische Haupt-Referenz, Gotchas, Konventionen |
| [`docs/backend.md`](docs/backend.md) | Infrastruktur, Deploy, Makefile, Versionierung |
| [`docs/conventions.md`](docs/conventions.md) | Code-Konventionen mit Beispielen |
| [`docs/data-model.md`](docs/data-model.md) | Vollständiges Datenbankschema |
| [`docs/features.md`](docs/features.md) | Feature-Spezifikationen im Detail |
| [`docs/moderation-criteria.md`](docs/moderation-criteria.md) | KI-Spam-Filter-Kriterien (SSoT) |
| [`docs/dev-environment.md`](docs/dev-environment.md) | Lokale Entwicklungsumgebung |
| [`docs/ses-setup.md`](docs/ses-setup.md) | AWS SES: Domain-Verifizierung → SMTP → Production Access |
| [`docs/cmdline.md`](docs/cmdline.md) | curl-Beispiele für alle API-Endpunkte |
| [`docs/ui-test-data.md`](docs/ui-test-data.md) | Realistische Testdaten (KMU/DACH) und Spam-Szenarien für manuelles UI-Testing |

---

## Mitmachen

**Beta-Zugang:** Du leitest KI-Projekte in einem Unternehmen und willst die Plattform testen?
→ [Melde dich via Issue](https://github.com/MikeMitterer/decmap_project/issues/new)

**Feedback & Bugs:** [Issues](https://github.com/MikeMitterer/decmap_project/issues)

**Kontakt:** [office@mikemitterer.at](mailto:office@mikemitterer.at)
