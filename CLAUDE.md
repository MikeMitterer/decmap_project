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
| Auth | Directus built-in (E-Mail-Verifizierung, Passwort-Staerke-Validierung) |
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

Multi-Repo — fuenf Repos mit eigenem Release-Zyklus.

| Repo | Inhalt | Deploy |
|---|---|---|
| `DecisionMap` (Root) | Issues, Haupt-Doku (CLAUDE.md, docs/), Makefile | — |
| `infrastructure/` | docker-compose, nginx, Orchestrierung, Backups | Hetzner |
| `apps/backend/` | Directus-Konfiguration, Seeds, Makefile | Hetzner |
| `apps/frontend/` | Nuxt.js App | Hetzner (eigenstaendig) |
| `apps/ai-service/` | FastAPI, Alembic, Repositories | Hetzner |

`apps/backend/`, `apps/frontend/`, `apps/ai-service/` sind per `.gitignore` ausgeschlossen. `infrastructure/` liegt im Root.

```
apps/frontend       → build → test → deploy frontend
apps/ai-service     → test → build → db-migrate → deploy ai-service
apps/backend        → deploy Directus-Konfiguration + Seeds
infrastructure      → deploy compose + nginx + Orchestrierung
```

---

## Projektstruktur

```
DecisionMap/                     ← Workspace-Root-Repo (Issues, Haupt-Doku)
├── CLAUDE.md                    ← Haupt-Referenz (dieses File)
├── Makefile                     ← Workspace-Orchestrierung
├── data/                        ← Shared Seed/Fixture-Daten (SSoT, snake_case JSON)
├── docs/                        ← Detaillierte Spezifikationen
├── scripts/                     ← Workspace-Skripte (z.B. gen-fixtures.py)
├── .templates/                  ← Wiederverwendbare Templates (Jenkinsfile, Makefile, docker/)
├── .libs/                       ← Lokale Symlinks (BashLib, BashTools, MakeLib) — per .gitignore ausgeschlossen
├── apps/                        ← Service-Repos (gitignored)
│   ├── backend/                 ← Directus-Konfiguration + Seeds
│   ├── frontend/                ← Nuxt.js App
│   └── ai-service/              ← FastAPI + Alembic
└── infrastructure/              ← Server-Orchestrierung (docker-compose, nginx)
```

Detaillierte Verzeichnisbaeme: siehe jeweilige Sub-CLAUDE.md.

---

## Sub-CLAUDE.md Templates

Jedes Sub-Repo enthaelt eine schlanke CLAUDE.md mit:
- Verweis auf diese Haupt-CLAUDE.md
- Kurzbeschreibung, lokale Entwicklung, Test-Befehle, Deploy-Hinweis

---

## Datenmodell

→ Details on demand: `/data-model` | Vollstaendige Spezifikation: [`docs/data-model.md`](docs/data-model.md)

Kerntabellen: `problems`, `solution_approaches`, `clusters`, `tags`, `regions`, `votes`  
Junction: `problem_cluster` (n:m mit Weight), `problem_tag`, `problem_region` | Audit: `edit_history`, `moderation_log`  
Tags: L0=Root (System), L1–L9=KI, L10=User | Validierung: Zod → Pydantic → PostgreSQL Constraints

---

## Nuxt Rendering-Strategie

```typescript
routeRules: {
  '/':            { ssr: false },      // Graph-View — SPA
  '/table':       { ssr: false },      // Table-View — SPA
  '/admin/**':    { ssr: false },      // Admin — SPA
  '/login':       { ssr: false },      // Login — SPA
  '/settings':    { ssr: false },      // Settings — SPA
  '/status':      { ssr: false },      // Status-Page — SPA
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

→ Details on demand: `/conventions` | Ausfuehrliche Beispiele: [`docs/conventions.md`](docs/conventions.md)

- **Architektur:** Komponenten = Darstellung, Composables = Logic (Frontend) | Router = HTTP, Services = Logic (Backend)
- **Naming:** TS/Vue `camelCase`/`PascalCase`/`SCREAMING_SNAKE_CASE` | Python `snake_case`/`PascalCase` | DB `snake_case`
- **TypeScript:** Strict, kein `any` (→ `unknown`), kein `!`, explizite Rueckgabetypen, Enums statt Magic Strings
- **Vue:** Nur Composition API + `<script setup lang="ts">`, keine API-Aufrufe in Komponenten
- **Python:** Type Hints ueberall, Pydantic Request/Response, Router pro Fachbereich
- **Logging:** `consola` (Frontend) / `structlog` (Backend) — kein `console.log` / `logging`
- **Testing:** Vitest (nur Composables, API mocken) / pytest (OpenAI mocken, Fixtures in `tests/fixtures/`)

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
- **Auth:** E-Mail-Verifizierung nach Registrierung (`registrationSent`-Flag, kein Auto-Login). Passwort-Staerke-Checklist live im Register-Tab (✓/○ pro Regel, Submit gesperrt bis alle gruen). `/verify-email.vue` → Redirect auf `/login?verified=true`. Dev: Mailpit als SMTP-Sink.
- **Status-Page:** `/status` zeigt Live-Status von Backend (Directus) und AI-Service (FastAPI). Browser-seitige Health-Checks via `fetch` direkt gegen die Services (kein Server-Route-Proxy — Browser laeuft auf dem Host wo Docker-Port-Mappings greifen). Polling alle 30s, `useServiceStatus` Composable mit Shared State (Modul-Level Refs). StatusBar zeigt Farbindikator: gruen (alle ok), orange (nur Backend), rot (Backend down). Directus `/server/health` liefert ohne Auth keine Version.

---

## Infrastructure

→ **Ausfuehrliche Spezifikation:** [`docs/backend.md`](docs/backend.md)

- **Env-Variablen:** Nie hardcoden, alle in `.env.example`
- **Feature Flags:** `SHOW_VOTING`, `REQUIRE_AUTH`
- **Linting:** ESLint + Prettier (TS) / ruff (Python) — automatisch, nicht verhandelbar
- **Makefile:** Jedes Sub-Repo hat ein eigenes Makefile. `make help` (Root: Workspace-Delegation), `make -C apps/backend help` (Docker, DB, Backup). Details: [`docs/backend.md`](docs/backend.md)
- **Versionierung:** SemVer + Datum (`bumpVer`): `v<MAJOR>.<MINOR>.<PATCH>+<YYMMDD>.<HHMM>`, Start bei `0.1.0`. Docker-Snapshots: `hashVer` → `<MAJOR>.<MINOR>.<PATCH>-SNAPSHOT<MMDD>.<HASH>` — automatisch via Jenkins. Details: [`docs/backend.md`](docs/backend.md)
- **Git:** Conventional Commits `<type>(<scope>): <msg>`, direkte Commits auf `master` erlaubt — Jenkins ist die einzige Schranke
- **Seed-Daten (SSoT):** `data/*.json` (snake_case, UUIDs) — nie direkt in Consumer-Repos editieren. `make fixtures-sync` verteilt an `apps/frontend/.../seeds.json` (camelCase) und `apps/ai-service/tests/fixtures/` (snake_case + embedding).
- **Seeds:** `apps/backend/database/seeds/` alphabetisch, idempotent
- **Backup:** `make -C apps/backend backup` / `make -C apps/backend backup-remote`, nie einchecken

---

## Kritische Gotchas

→ Vollstaendige Liste on demand: `/gotchas`

- **Seeds L0/L1:** `seeds.json` hat noch L1=root — DB-Schema/TS-Types verwenden L0=root.
- **Directus schema apply nach Alembic:** `directus_*` Metadata loeschen, dann erneut `make directus-schema-apply`.
- **Directus Permissions nie per SQL:** Umgeht Directus-Cache → 403. Immer via REST API (`make db-permissions`).
- **FastAPI Background Tasks:** Eigene psycopg-Connection — Request-scoped ist beim Task-Start geschlossen.
- **CORS:** `allow_credentials=True` + `allow_origins=["*"]` ist browser-invalid — nie zusammen.
- **Health-Checks nur Browser-seitig:** Nitro Server-Routes erreichen Docker-Ports nicht. `fetch()` direkt im Browser, `AbortSignal.timeout(10_000)`.

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
