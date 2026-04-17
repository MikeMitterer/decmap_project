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
├── scripts/                     ← Workspace-Skripte (z.B. gen-fakedata.py)
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
→ Code-Standards (Stil, Struktur, Scripts, BashLib, Gotchas): `/code-standards`

- **Architektur:** Komponenten = Darstellung, Composables = Logic (Frontend) | Router = HTTP, Services = Logic (Backend)
- **Naming:** TS/Vue `camelCase`/`PascalCase`/`SCREAMING_SNAKE_CASE` | Python `snake_case`/`PascalCase` | DB `snake_case` | Bash Funktionen `camelCase`, Variablen `snake_case`, Konstanten `SCREAMING_SNAKE_CASE`

---

## Features

→ **Ausfuehrliche Spezifikationen:** [`docs/features.md`](docs/features.md)

- **Aehnlichkeitserkennung:** Debounced pgvector Cosine-Similarity, Schwellenwert 0.85/0.92
- **Bot-Erkennung:** nginx Rate Limiting → DNSBL → Verhaltens-Signale + Honeypot → GPT Spam-Filter
- **Echtzeit-Updates:** Zwei WebSocket-Quellen: AI-Service WS fuer AI-Events (problem.approved, cluster.updated, solution.generated); Directus WS Subscription fuer Vote-Score-Updates (`problems.vote_score` — Score wird per REST `GET`+`PATCH` berechnet, kein PostgreSQL-Trigger). Frontend: `useRealtimeUpdates.ts` (AI-Service) + `useDirectusRealtime.ts` (Directus WS). `ProblemGraph.vue` watcht `props.problems` deep — Graph-View rendert automatisch neu wenn Vote-Scores sich aendern.
- **i18n:** Nuxt i18n, alle Texte ueber `t()`, MVP nur Englisch
- **Markdown:** markdown-it + DOMPurify (nur Links + Fettschrift)
- **Uebersetzung:** Aktiv beim Einreichen — `looksLikeEnglish`-Heuristik → bei Nicht-Englisch „Translate to English"-Button → KI-Service `TranslationService` via konfiguriertem LLM-Provider (`openai_llm_model`/`anthropic_model` in `.env`). Kein DeepL, kein lokales Modell.
- **Tagging:** Tags (inhaltlich) + Regionen (geografisch) — getrennte Konzepte
- **Editieren:** Nur eigene Eintraege, setzt Status zurueck, Edit-History fuer Moderatoren
- **KI-Loesungen:** Automatisch bei Approval, visuell getrennt, separates Ranking
- **Auth:** E-Mail-Verifizierung nach Registrierung (`registrationSent`-Flag, kein Auto-Login). Passwort-Staerke-Checklist live im Register-Tab (✓/○ pro Regel, Submit gesperrt bis alle gruen). `/verify-email.vue` → Redirect auf `/login?verified=true`. Dev: Mailpit als SMTP-Sink.
- **Status-Page:** `/status` zeigt Live-Status von Backend (Directus) und AI-Service (FastAPI). Browser-seitige Health-Checks via `fetch` direkt gegen die Services (kein Server-Route-Proxy — Browser laeuft auf dem Host wo Docker-Port-Mappings greifen). Polling alle 30s, `useServiceStatus` Composable mit Shared State (Modul-Level Refs). StatusBar zeigt Farbindikator: gruen (alle ok), orange (nur Backend), rot (Backend down). Directus `/server/health` liefert ohne Auth keine Version. AI-Service: Direkt `GET /health`, via nginx `GET /api/health` (wsUrl → aiUrl Konvertierung in `useServiceStatus`).

---

## Infrastructure

→ **Ausfuehrliche Spezifikation:** [`docs/backend.md`](docs/backend.md)

- **Env-Variablen:** Nie hardcoden, alle in `.env.example`
- **Feature Flags:** `SHOW_VOTING`, `REQUIRE_AUTH`, `AUTO_APPROVE`
- **Linting:** ESLint + Prettier (TS) / ruff (Python) — automatisch, nicht verhandelbar
- **Makefile:** Jedes Sub-Repo hat ein eigenes Makefile. `make help` (Root: Workspace-Delegation), `make -C apps/backend help` (Docker, DB, Backup). Details: [`docs/backend.md`](docs/backend.md)
- **Versionierung:** SemVer + Datum (`bumpVer`): `v<MAJOR>.<MINOR>.<PATCH>+<YYMMDD>.<HHMM>.<HASH>`, Start bei `0.1.0`. Docker-Snapshots: `gitDockerTag` → `<MAJOR>.<MINOR>.<PATCH>-<YYMMDD>.<HHMM>.<HASH>[.ahead<N>]` (z.B. `0.1.0-260412.0824.def34.ahead3`) — automatisch via Jenkins. Details: [`docs/backend.md`](docs/backend.md)
- **Git:** Conventional Commits `<type>(<scope>): <msg>`, direkte Commits auf `master` erlaubt — Jenkins ist die einzige Schranke. Details on demand: `/git-conventions`
- **Seed-Daten (SSoT):** `data/*.json` (snake_case, UUIDs) — nie direkt in Consumer-Repos editieren. `make fakedata-sync` verteilt an `apps/frontend/.../seeds.json` (camelCase) und `apps/ai-service/tests/fakedata/` (snake_case + embedding).
- **Seeds:** `apps/backend/database/seeds/` alphabetisch, idempotent
- **Backup:** `scripts/db-backup.sh` (einheitliches Script, `.dump`-Format). Dev: `make -C apps/backend backup|restore|backup-list`. Prod: `make -C infrastructure backup|backup-restore|backup-list|backup-pull|backup-push`. Nie einchecken. Details: [`docs/backend.md`](docs/backend.md)

---

## Kritische Gotchas

→ Vollstaendige Liste on demand: `/gotchas`

- **Seeds L0/L1:** `seeds.json` hat noch L1=root — DB-Schema/TS-Types verwenden L0=root.
- **Directus schema apply nach Alembic:** `directus_*` Metadata loeschen, dann erneut `make directus-schema-apply`.
- **Directus Permissions nie per SQL:** Umgeht Directus-Cache → 403. Immer via REST API (`make db-permissions`).
- **FastAPI Background Tasks:** Eigene psycopg-Connection — Request-scoped ist beim Task-Start geschlossen.
- **CORS:** `allow_credentials=True` + `allow_origins=["*"]` ist browser-invalid — nie zusammen.
- **Health-Checks nur Browser-seitig:** Nitro Server-Routes erreichen Docker-Ports nicht. `fetch()` direkt im Browser, `AbortSignal.timeout(10_000)`.
- **Let's Encrypt Symlinks (nginx-Container):** `live/fullchain.pem` ist ein Symlink auf `archive/` — beide Verzeichnisse in `docker-compose.yml` mounten, sonst schlägt TLS fehl.
- **Docker Compose V2 auf Ubuntu:** `docker.io` (Ubuntu-Paket) liefert kein `docker compose` (V2). Offizielles Docker-Repository erforderlich — `docker-compose-plugin` installieren.
- **Directus Live-URL:** `https://cms.decisionmap.ai/` — Subdomain, kein Pfad-Prefix. `PUBLIC_URL=https://cms.decisionmap.ai` in `.env` Pflicht. nginx leitet `/cms`-Pfade nicht um.
- **Directus SMTP-Healthcheck blockiert Start:** `EMAIL_SMTP_HOST` gesetzt aber nicht erreichbar → 60s Timeout → Container `unhealthy`. `EMAIL_SMTP_HOST=` (leer) setzen bis SMTP konfiguriert ist.
- **AWS SES DKIM CNAME — Trailing Dot:** CNAME-Value-Eintrag muss mit Punkt enden (`xxxxx.dkim.amazonses.com.` — nicht ohne Punkt). Fehlt der Punkt, haengt Hetzner die eigene Domain an → DKIM-Records ungueltig. DNS-Verwaltung ueber `dns.hetzner.com` (neues Interface), nicht Hetzner Robot (lehnt externe CNAME-Ziele ab). Vollstaendige Anleitung: [`docs/ses-setup.md`](docs/ses-setup.md).
- **nginx `proxy_pass` mit Variable + `rewrite` — drei Gotchas:** (1) `proxy_pass http://$var/` macht keine Prefix-Substitution — `/api/health` landet als `/api/health` beim Backend. (2) `rewrite ... break` stoppt auch `set` — `set $var` immer **vor** `rewrite` stellen, sonst bleibt Variable leer → "no host in upstream". (3) `proxy_pass http://$var` ohne URI nach `rewrite` nimmt die Original-URI — `$uri` explizit übergeben: `proxy_pass http://$upstream$uri$is_args$args`.
- **Directus Flow HTTP-Request-Body:** Trigger-Payload wird nicht automatisch weitergeleitet — im HTTP-Request-Operation explizit mappen: `{"entity_id": "{{$trigger.payload.entity_id}}"}`. Fehlendes Mapping → leerer Body beim Webhook-Empfänger.
- **WebSocket Composables brauchen explizites `connect()` in `onMounted`:** `useRealtimeUpdates` (AI-Service WS) und `useDirectusRealtime` verbinden sich nicht automatisch. Fehlt der `connect()`-Call in `onMounted`, bleibt der Socket stumm — kein Fehler, kein Event. Beide Composables in `index.vue` explizit starten.
- **nginx WebSocket-Upgrade fuer Directus:** Der `cms.decisionmap.ai`-Serverblock braucht `proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";` + `proxy_read_timeout 3600s` — ohne Upgrade-Header schlaegt der Handshake lautlos fehl; ohne `proxy_read_timeout` bricht nginx die WS-Verbindung nach 60 s Inaktivitaet ab (Directus Ping-Intervall kann groesser sein).
- **`useDirectusRealtime` Reconnect-Loop (~3 s):** Symptom: WS verbindet sich, trennt sich sofort, wiederholt sich im 3-Sekunden-Takt. Ursache: `PUBLIC_URL` oder `CORS_ORIGIN` in Directus `.env` stimmt nicht mit der tatsaechlichen Frontend-Origin ueberein → Directus verwirft die Verbindung. Fix: `PUBLIC_URL=http://cms.int.decisionmap.ai` + `CORS_ORIGIN=http://int.decisionmap.ai` setzen, Directus neu starten.
- **Directus M2M PATCH — Junction-Record-`id` Pflicht:** Beim PATCH einer M2M-Relation (z.B. `problem_tags`, `problem_regions`) unterscheidet Directus: Junction-Record **mit** `id` → UPDATE (existierender Eintrag); **ohne** `id` → INSERT (neuer Eintrag). Werden alle Tags ohne `id` geschickt, versucht Directus fuer jeden Tag einen neuen Junction-Row einzufuegen → Unique-Constraint `(problem_id, tag_id)` schlaegt fehl. Fix: Vor dem PATCH existierende Junction-Records laden, per `tag_id`/`region_id` mappen und die Junction-`id` fuer bereits vorhandene Eintraege mitschicken. **Bevorzugte Loesung (robuster):** Scalar-Felder und M2M trennen — `PATCH` nur Scalar-Felder, dann `DELETE /items/problem_tag?filter[problem_id][_eq]=<id>` + `POST /items/problem_tag` mit explizitem `problem_id`, anschliessend Re-fetch.

---

## Was nicht gemacht wird

- Kein direktes CSS — Tailwind Utility Classes
- Kein Hard Delete — Soft Delete ueber `deleted_at`/`deleted_by`
- Keine rohen IP-Adressen — `ip_hash` verwenden
- Kein Markdown ohne DOMPurify-Sanitizing
- Keine hardcodierten UI-Strings — i18n (`t()`)
- `.env` nie einchecken — nur `.env.example`
- `make db-reset` nie auf dem Server
- Keine `TODO`-Kommentare ohne zugehoeriges Issue
