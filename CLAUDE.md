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

Multi-Repo — vier Repos mit eigenem Release-Zyklus.

| Repo | Inhalt | Deploy |
|---|---|---|
| `DecisionMap` (Root) | Issues, Haupt-Doku (CLAUDE.md, docs/), Makefile | — |
| `backend` | docker-compose, nginx, Seeds, Backups, Makefile | Hetzner |
| `frontend` | Nuxt.js App | Hetzner (eigenstaendig) |
| `ai-service` | FastAPI, Alembic, Repositories | Hetzner |

`backend/`, `frontend/` und `ai-service/` sind im Workspace-Root per `.gitignore` ausgeschlossen.

```
frontend     → build → test → deploy frontend
ai-service   → test → build → db-migrate → deploy ai-service
backend      → deploy compose + config
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
├── backend/                     ← Deployment-Konfiguration
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
- **Auth:** E-Mail-Verifizierung nach Registrierung (`registrationSent`-Flag, kein Auto-Login). Passwort-Staerke-Checklist live im Register-Tab (✓/○ pro Regel, Submit gesperrt bis alle gruen). `/verify-email.vue` → Redirect auf `/login?verified=true`. Dev: Mailpit als SMTP-Sink.
- **Status-Page:** `/status` zeigt Live-Status von Backend (Directus) und AI-Service (FastAPI). Browser-seitige Health-Checks via `fetch` direkt gegen die Services (kein Server-Route-Proxy — Browser laeuft auf dem Host wo Docker-Port-Mappings greifen). Polling alle 30s, `useServiceStatus` Composable mit Shared State (Modul-Level Refs). StatusBar zeigt Farbindikator: gruen (alle ok), orange (nur Backend), rot (Backend down). Directus `/server/health` liefert ohne Auth keine Version.

---

## Infrastructure

→ **Ausfuehrliche Spezifikation:** [`docs/backend.md`](docs/backend.md)

- **Env-Variablen:** Nie hardcoden, alle in `.env.example`
- **Feature Flags:** `SHOW_VOTING`, `REQUIRE_AUTH`
- **Linting:** ESLint + Prettier (TS) / ruff (Python) — automatisch, nicht verhandelbar
- **Makefile:** Jedes Sub-Repo hat ein eigenes Makefile. `make help` (Root: Workspace-Delegation), `make -C backend help` (Docker, DB, Backup). Details: [`docs/backend.md`](docs/backend.md)
- **Versionierung:** `hashVer` (BashLib) → `<Jahr>.<Quartal>.0-SNAPSHOT<MMDD>.<HASH>` — automatisch via Jenkins. Details: [`docs/backend.md`](docs/backend.md)
- **Git:** Conventional Commits `<type>(<scope>): <msg>`, direkte Commits auf `master` erlaubt — Jenkins ist die einzige Schranke
- **Seeds:** `database/seeds/` alphabetisch, idempotent
- **Backup:** `make -C backend backup` / `make -C backend backup-remote`, nie einchecken

---

## Kritische Gotchas

- **Seeds L0/L1:** `seeds.json` hat noch L1=root — DB-Schema und TS-Types verwenden L0=root. Muss vor Real-Data-Layer korrigiert werden.
- **Directus schema apply nach Alembic:** `directus_*` Metadata loeschen, dann erneut `make directus-schema-apply` — sonst schlaegt Apply fehl.
- **Webhook-Endpunkte:** Immer per `_verify_webhook_secret()` Dependency absichern. Leeres `WEBHOOK_SECRET` = Dev-Mode (kein Check).
- **FastAPI Background Tasks:** Brauchen eigene psycopg-Connection — Request-scoped Connection ist beim Task-Start bereits geschlossen.
- **CORS:** `allow_credentials=True` + `allow_origins=["*"]` ist browser-invalid — nie zusammen verwenden.
- **Directus Registrierung:** `USERS_REGISTER_ALLOW_PUBLIC: "true"` im Directus-Container (docker-compose) setzen — sonst liefert `/users/register` 403, unabhaengig von Permissions. `make seed-users` setzt dies automatisch via `PATCH /settings`.
- **Directus Verification-URL-Whitelist:** `USER_REGISTER_URL_ALLOW_LIST` im Directus-Container setzen (kommagetrennte erlaubte `verification_url`-Prefixes). Ohne diesen Guard akzeptiert Directus beliebige `verification_url` in `/users/register` — Phishing-Vektor. Produktions-URL + `http://localhost:3000` fuer Dev eintragen.
- **Directus Permissions nie per SQL:** Direktes `INSERT INTO directus_permissions` umgeht den Directus-Cache — 403 ohne Fehlermeldung. Permissions immer via REST API setzen (`make db-permissions` / `make seed-users`).
- **Alembic-Spalten im Directus-Schema registrieren:** Spalten die Alembic anlegt (z.B. `tags.deleted_at`, `tags.deleted_by`), sind Directus unbekannt bis sie in `schema.json` oder per `POST /fields/{collection}` registriert sind. Filter auf unbekannte Felder schlaegt mit Validierungsfehler fehl.
- **Directus M2M Virtual-Field-Naming:** M2M-Aliasfelder heissen nach `one_field` in der Relation-Definition — nicht nach dem Junction-Table. `problems` → Junction `problem_tag` → `tags` heisst im `readItems`-Ergebnis `tags` (nicht `problem_tag`). In Fields-Liste und Interface entsprechend `tags.tag_id` / `regions.region_id` verwenden, nicht `problem_tag.tag_id`.
- **Directus M2M Permissions:** User-Policy braucht `CREATE`/`DELETE` auf Junction-Tables (`problem_tag`, `problem_region`) — Directus schreibt bei M2M-PATCH intern in diese Tabellen. Fehlt die Permission, schlaegt Problem-Submit mit 403 fehl. `make db-permissions` setzt dies idempotent.
- **Directus 11 Nullable-FK-Validierungsbug:** Directus validiert nullable FK-Felder (`tags.parent_id`, `*.deleted_by`) gegen eigene Relation-Metadata — `PATCH` mit `null` schlaegt mit 400 fehl obwohl PostgreSQL `NULL` erlaubt. Fix: `DELETE /relations/{collection}/{field}`. PostgreSQL-Constraint bleibt, Directus-Validierung entfaellt.
- **Directus 11 `admin_access` auf Policy, nicht Role:** `role.admin_access` gibt immer `undefined` — das Feld ist nach `directus_policies` gewandert. Korrekt: `role.policies.policy.admin_access` in `USER_FIELDS` requesten und per `policies.some(p => p.policy?.admin_access)` auswerten.
- **Directus 11 `directus_users` Custom-Felder:** `date_created` existiert nicht (Fallback `''`). `display_name` und `company` sind Custom-Felder die `seed-users.sh` anlegt. User-Policy braucht READ + UPDATE auf `directus_users` (eigener Account, `id == $CURRENT_USER`) — sonst 403 beim Profil-Laden/-Speichern.
- **Health-Checks nur Browser-seitig:** Nitro Server-Routes auf macOS koennen Docker-Desktop-gemappte localhost-Ports nicht erreichen (TCP verbindet, aber 0 Bytes Antwort). Health-Checks muessen daher per `fetch()` direkt aus dem Browser laufen (`useServiceStatus` Composable). Browser laeuft auf dem Host wo Docker-Port-Mappings greifen. `AbortSignal.timeout(10_000)` verwenden — kuerzere Timeouts koennen Chrome Private Network Access (PNA) Preflight-Probleme ausloesen.

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
