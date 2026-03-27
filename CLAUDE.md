# CLAUDE.md — DecisionMap

> Haupt-Referenz fur das gesamte Projekt. Gilt fur alle Repos.
> Jedes Sub-Repo enthalt eine schlanke CLAUDE.md die auf dieses File verweist.
> Detaillierte Spezifikationen in `docs/` — siehe Verweise unten.

## Projektuebersicht

Kollektive KI-Problemlandkarte. User erfassen KI-bezogene Probleme aus ihren Unternehmen.
Andere User liefern Loesungsansaetze. Ein KI-Backend-Service clustert die Eingaben und
visualisiert sie als interaktiven Graph. Zielgruppe: IT-Entscheider, CDOs, KI-Projektverantwortliche in KMU.

---

## Stack

| Schicht | Technologie |
|---|---|
| Frontend | Nuxt.js 3 + TypeScript |
| CMS / Backend | Directus |
| Datenbank | PostgreSQL + pgvector |
| KI-Service | FastAPI (Python 3.11+) |
| Hosting | Hetzner (Docker + nginx) |
| Auth | Directus built-in (Magic Link) |
| Visualisierung | Cytoscape.js |
| CSS Framework | Tailwind CSS |
| Logging | consola (Frontend) / structlog (Backend) |
| DB-Zugriff | psycopg3 + Repository Pattern |
| DB-Migrationen | Alembic |
| Echtzeit | WebSocket (FastAPI native) |
| Testing | Vitest (Frontend) / pytest (Backend) |
| CI/CD | Jenkins → SSH → Hetzner |

---

## Repositories

Multi-Repo — vier Repos mit eigenem Release-Zyklus.

| Repo | Inhalt | Deploy |
|---|---|---|
| `DecisionMap` (Root) | Issues, Haupt-Doku (CLAUDE.md, docs/), Makefile | — |
| `infrastructure` | docker-compose, nginx, Seeds, Backups | Hetzner |
| `frontend` | Nuxt.js App | Hetzner (eigenstaendig) |
| `ai-service` | FastAPI, Alembic, Repositories | Hetzner |

`infrastructure/`, `frontend/` und `ai-service/` sind im Workspace-Root per `.gitignore` ausgeschlossen.

```
frontend     → build → test → deploy frontend
ai-service   → test → build → db-migrate → deploy ai-service
infrastructure → deploy compose + config
```

---

## Projektstruktur

```
DecisionMap/                     ← Workspace-Root-Repo (Issues, Haupt-Doku)
├── CLAUDE.md                    ← Haupt-Referenz (dieses File)
├── docs/                        ← Detaillierte Spezifikationen
├── Makefile                     ← Workspace-Orchestrierung
├── .templates/                  ← Wiederverwendbare Templates (Jenkinsfile, Makefile, docker/)
├── .libs/                       ← Lokale Symlinks (BashLib, BashTools, MakeLib) — per .gitignore ausgeschlossen
├── infrastructure/              ← Deployment-Konfiguration
├── frontend/                    ← Nuxt.js App
└── ai-service/                  ← FastAPI + Alembic
```

Detaillierte Verzeichnisbaeme: siehe jeweilige Sub-CLAUDE.md.

---

## Sub-CLAUDE.md Templates

Jedes Sub-Repo enthaelt eine schlanke CLAUDE.md mit:
- Verweis auf diese Haupt-CLAUDE.md
- Kurzbeschreibung, lokale Entwicklung, Test-Befehle, Deploy-Hinweis

---

## Datenmodell

→ **Vollstaendige Spezifikation:** [`docs/data-model.md`](docs/data-model.md)

Kerntabellen: `problems`, `solution_approaches`, `clusters`, `tags`, `regions`, `votes`
Junction-Tabellen: `problem_cluster` (n:m mit Weight), `tag`, `region`
Audit: `edit_history`, `moderation_log`

```
users ──< problems ──< solution_approaches
              │
              ├──>< problem_cluster >──< clusters
              ├──>< problem_tag >──< tags (hierarchisch: L1–L10)
              └──>< problem_region >──< regions
```

DB-Versionierung: Alembic (nie bestehende Migrationen editieren, Breaking Changes zweistufig).
Validierung: 3 Schichten (Zod → Pydantic → PostgreSQL Constraints).

---

## Nuxt Rendering-Strategie

```typescript
routeRules: {
  '/':            { ssr: false },      // Graph-View — SPA
  '/table':       { ssr: false },      // Table-View — SPA
  '/admin/**':    { ssr: false },      // Admin — SPA
  '/problem/**':  { prerender: true }, // Problem-Detail — SEO
  '/cluster/**':  { prerender: true }, // Cluster-Seiten — SEO
}
```

---

## Data Layer — Fake/Real Switch

`USE_FAKE_DATA=true/false` in `.env` — beide Layer implementieren dasselbe Interface.

```typescript
export function useProblems() {
  return useRuntimeConfig().public.useFakeData
    ? useFakeProblems()
    : useRealProblems()
}
```

---

## UI Layout

```
┌─────────────────────────────────────────────────┐
│  Header: Logo + Nav + Suchfeld                   │
├──────────────────────────┬──────────────────────┤
│   Graph / Table (70%)    │   Panel (30%)         │
│   Suchfeld filtert beide │   Detail / Formular   │
└──────────────────────────┴──────────────────────┘
```

- Modals erlaubt, Primaer-Flows bleiben im Panel
- Mobile: Panel als Drawer
- `+` Button → Eingabeformular, Klick auf Node/Zeile → Detail

---

## Kern-Konventionen

→ **Ausfuehrliche Beispiele:** [`docs/conventions.md`](docs/conventions.md)

### Architektur

- **Frontend:** Komponenten = nur Darstellung. Business Logic → Composables.
- **Backend:** Router = nur HTTP. Business Logic → Services.
- Dependency Injection statt hardcodierter Abhaengigkeiten

### Naming

- **TS/Vue:** `camelCase` Dateien/Variablen, `PascalCase` Komponenten/Types, `SCREAMING_SNAKE_CASE` Konstanten
- **Python:** `snake_case` Dateien/Variablen, `PascalCase` Klassen, Type Hints immer
- **DB:** `snake_case`, Plural Lookup-Tabellen, Singular Junction-Tabellen
- **Loop-Variablen:** immer sprechend — `problem`, nie `p` oder `i`

### TypeScript

- Strict Mode, kein `any` (→ `unknown`), explizite Rueckgabetypen
- Interfaces fuer Objekte, Enums fuer feste Wertesets, keine Magic Strings
- Keine Non-null Assertions (`!`)

### Vue/Nuxt

- Nur Composition API + `<script setup lang="ts">`
- Props und Emits immer typisiert
- Keine API-Aufrufe in Komponenten

### Python/FastAPI

- Type Hints ueberall, Pydantic fuer Request/Response
- Router pro Fachbereich, Services fuer Business Logic

### Logging

- Frontend: `consola` (kein `console.log`)
- Backend: `structlog` (kein natives `logging`)

### Testing

- Frontend: Vitest, nur Composables, API mocken
- Backend: pytest, OpenAI mocken, Fixtures in `tests/fixtures/`

---

## Features

→ **Ausfuehrliche Spezifikationen:** [`docs/features.md`](docs/features.md)

- **Aehnlichkeitserkennung:** Debounced pgvector Cosine-Similarity, Schwellenwert 0.85/0.92
- **Bot-Erkennung:** nginx Rate Limiting → DNSBL → Verhaltens-Signale + Honeypot → GPT Spam-Filter
- **Echtzeit-Updates:** WebSocket Broadcast (problem/cluster/solution/vote Events)
- **i18n:** Nuxt i18n, alle Texte ueber `t()`, MVP nur Englisch
- **Markdown:** markdown-it + DOMPurify (nur Links + Fettschrift)
- **Uebersetzung:** Passiv via DeepL-Link
- **Tagging:** Tags (inhaltlich) + Regionen (geografisch) — getrennte Konzepte
- **Editieren:** Nur eigene Eintraege, setzt Status zurueck, Edit-History fuer Moderatoren
- **KI-Loesungen:** Automatisch bei Approval, visuell getrennt, separates Ranking

---

## Infrastructure

→ **Ausfuehrliche Spezifikation:** [`docs/infrastructure.md`](docs/infrastructure.md)

- **Env-Variablen:** Nie hardcoden, alle in `.env.example`
- **Feature Flags:** `SHOW_VOTING`, `REQUIRE_AUTH`
- **Linting:** ESLint + Prettier (TS) / ruff (Python) — automatisch, nicht verhandelbar
- **Makefile:** `make help` fuer alle Befehle
- **Versionierung:** `hashVer` (BashLib) → `<Jahr>.<Quartal>.0-SNAPSHOT<MMDD>.<HASH>` — automatisch via Jenkins. Details: [`docs/infrastructure.md`](docs/infrastructure.md)
- **Git:** Conventional Commits `<type>(<scope>): <msg>`, direkte Commits auf `main` erlaubt — Jenkins ist die einzige Schranke
- **Seeds:** `database/seeds/` alphabetisch, idempotent
- **Backup:** `make backup/backup-remote`, nie einchecken

---

## Was nicht gemacht wird

- Keine Options API — nur Composition API
- Kein direktes CSS — Tailwind Utility Classes
- Keine Directus-Aufrufe in Komponenten — nur Composables
- Kein `console.log` — `consola` verwenden
- Kein `any` — `unknown` verwenden
- Keine Magic Strings — Enums verwenden
- Kein Hard Delete — Soft Delete ueber `deleted_at`/`deleted_by`
- Keine rohen IP-Adressen — `ip_hash` verwenden
- Kein Markdown ohne DOMPurify-Sanitizing
- Keine hardcodierten UI-Strings — i18n (`t()`)
- `.env` nie einchecken — nur `.env.example`
- `make db-reset` nie auf dem Server
- Keine `TODO`-Kommentare ohne zugehoeriges Issue
