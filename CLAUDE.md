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
| Backend | FastAPI + fastapi-users + SQLAlchemy (asyncio) |
| Datenbank | PostgreSQL + pgvector |
| KI-Service | FastAPI (Python 3.11+) |
| Hosting | Hetzner (Docker + nginx) |
| Auth | fastapi-users (JWT im HttpOnly-Cookie, E-Mail-Verifizierung, Magic Link) |
| Visualisierung | Cytoscape.js |
| CSS Framework | Tailwind CSS |
| Logging | consola (Frontend) / structlog (Backend) |
| DB-Zugriff | SQLAlchemy ORM (asyncio) + Alembic |
| DB-Migrationen | Alembic (in `apps/backend/alembic/`) |
| Echtzeit | WebSocket (FastAPI native) |
| Testing | Vitest (Frontend) / pytest (Backend) / Playwright (E2E) |
| CI/CD | Jenkins → SSH → Hetzner |

---

## Repositories

Multi-Repo — fuenf Repos mit eigenem Release-Zyklus.

| Repo | Inhalt | Deploy |
|---|---|---|
| `DecisionMap` (Root) | Issues, Haupt-Doku (CLAUDE.md, docs/), Makefile | — |
| `infrastructure/` | docker-compose, nginx, Orchestrierung, Backups | Hetzner |
| `apps/backend/` | FastAPI Backend (Auth, REST API, WebSocket, Alembic) | Hetzner |
| `apps/frontend/` | Nuxt.js App | Hetzner (eigenstaendig) |
| `apps/ai-service/` | FastAPI KI-Service (HDBSCAN, Embeddings, Spam-Filter) | Hetzner |

`apps/backend/`, `apps/frontend/`, `apps/ai-service/` sind per `.gitignore` ausgeschlossen. `infrastructure/` liegt im Root.

```
apps/frontend       → build → test → deploy frontend
apps/backend        → test → build → db-migrate → deploy backend
apps/ai-service     → test → build → deploy ai-service
infrastructure      → deploy compose + nginx + Orchestrierung
```

---

## Projektstruktur

```
DecisionMap/                     ← Workspace-Root-Repo (Issues, Haupt-Doku)
├── CLAUDE.md                    ← Haupt-Referenz (dieses File)
├── Makefile                     ← Workspace-Orchestrierung
├── docs/                        ← Detaillierte Spezifikationen
├── scripts/                     ← Workspace-Skripte (z.B. db-backup.sh, env-audit.py)
├── .templates/                  ← Wiederverwendbare Templates (Jenkinsfile, Makefile, docker/)
├── .libs/                       ← Lokale Symlinks (BashLib, BashTools, MakeLib) — per .gitignore ausgeschlossen
├── apps/                        ← Service-Repos (gitignored)
│   ├── backend/                 ← FastAPI Backend + Alembic (Schema-Owner)
│   ├── frontend/                ← Nuxt.js App
│   └── ai-service/              ← FastAPI KI-Service (kein direkter DB-Zugriff)
└── infrastructure/              ← Server-Orchestrierung (docker-compose, nginx)
```

Detaillierte Verzeichnisbaeme: siehe jeweilige Sub-CLAUDE.md.

---

## Sub-CLAUDE.md Templates

Jedes Sub-Repo enthaelt eine schlanke CLAUDE.md mit:
- Verweis auf diese Haupt-CLAUDE.md
- Kurzbeschreibung, lokale Entwicklung, Test-Befehle, Deploy-Hinweis

---

## README-Strategie

- `README.md` — **Englisch** (Primary, GitHub-Default, internationales Publikum, Show HN)
- `README.de.md` — **Deutsch** (DACH-Zielgruppe, Beta-User)
- Beide Files verlinken gegenseitig am Anfang
- **Kein Changelog im README** — `git log` + GitHub Releases sind die Changelog-Quellen
- Status-Section wird **ersetzt**, nicht ergänzt — kein Verlaufs-Rauschen
- Interne Dev-Notizen (Bugfixes, Migrations-Details) gehoeren in den Commit-Body, nicht ins README
- Session-Ende: `git diff HEAD` im Root zeigt nur Root-Aenderungen (CLAUDE.md, docs/, README) — Sub-Repo-Code-Aenderungen via `make status` sichtbar

---

## Datenmodell

→ Details on demand: `/data-model` | Vollstaendige Spezifikation: [`docs/data-model.md`](docs/data-model.md)

Kerntabellen: `problems`, `solution_approaches`, `tags`, `regions`, `votes`  
Junction: `problem_tag`, `problem_region` | Audit: `edit_history`, `moderation_log`  
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
- `+` Button → immer sichtbar; eingeloggt → Eingabeformular, nicht eingeloggt → Redirect `/login`; Klick auf Node/Zeile → Detail

---

## Kern-Konventionen

→ Details on demand: `/conventions` | Ausfuehrliche Beispiele: [`docs/conventions.md`](docs/conventions.md)
→ Code-Standards (Stil, Struktur, Scripts, BashLib, Gotchas): `/code-standards`

- **Architektur:** Komponenten = Darstellung, Composables = Logic (Frontend) | Router = HTTP, Services = Logic (Backend)
- **Naming:** TS/Vue `camelCase`/`PascalCase`/`SCREAMING_SNAKE_CASE` | Python `snake_case`/`PascalCase` | DB `snake_case` | Bash Funktionen `camelCase`, Variablen `snake_case`, Konstanten `SCREAMING_SNAKE_CASE`

---

## Features

→ **Ausfuehrliche Spezifikationen:** [`docs/features.md`](docs/features.md)

- **Aehnlichkeitserkennung:** Debounced pgvector Cosine-Similarity, Schwellenwert 0.85/0.92. Einreichen trotz Warnung: `signals: ['duplicate_confirmed']` → `needs_review` + `rejection_reason="possible_duplicate"` (kein Auto-Reject). Live-Check in `ProblemForm.vue` reagiert auf Titel **und** Beschreibung und sendet `[title, description].filter(Boolean).join('\n\n')` — spiegelt die Server-Embedding-Quelle `_embedding_text` (**Titel + Beschreibung**, leere Teile fallen weg), damit Live-Warnung und Submit-Verdikt konsistent sind (sonst Divergenz). Embedding-Quelle umgestellt von description-only → Titel + Beschreibung, damit Semantik-Suche/Similarity auch auf dem Titel matchen (User sieht den Titel zuerst). **Nach Deploy:** `POST /embeddings/reindex` (Service-Token), sonst sind bestehende Embeddings stale.
- **Bot-Erkennung:** Probleme: nginx Rate Limiting → Honeypot → signals-Array (≥2 → reject) → LLM Spam-Filter — alles im ai-service `SpamFilterService`. **Nicht** implementiert (Doku früher überzeichnet): DNSBL und eine backend-seitige `BotDetectionMiddleware`; die behavioral-timing-`BOT_*`-Schwellenwerte (`BOT_SUBMIT_MIN_SECONDS`/`BOT_SESSION_MAX_HOURLY`/`BOT_IP_MAX_SESSIONS`) wurden 2026-07-08 als toter Config entfernt (nie gelesen) — durch das `signals`-Array fließt real nur `duplicate_confirmed`. Lösungsansätze: nur LLM-Spam-Filter (kein Verhaltens-Layer — Auth vorausgesetzt). Verifikationskriterien (SSoT): [`docs/moderation-criteria.md`](docs/moderation-criteria.md)
- **Lösungs-Moderation (KI ist das Gate):** Der `solution-submitted`-Hook entscheidet ohne menschlichen Pflicht-Schritt: LLM-Spam-Filter sauber → `approved` (sofort sichtbar, Embedding wird gespeichert); LLM bemängelt → `needs_review` mit Begründung (Admin-Queue, **kein** Auto-Reject); LLM-Fehler → fail-safe `needs_review` (`moderation_error`). `evaluate_solution` (ai-service) gibt entsprechend `approved`/`needs_review` zurück — früher fälschlich `pending` für saubere Lösungen.
- **Lösungs-Duplikat-Check (global, live):** Analog zur Problem-Similarity, aber über **alle** approved Solutions (nicht problem-scoped). Live im `SolutionForm` (`useSolutionSimilarity` → `POST /ai/solution-similarity`, debounced 600ms) + Submit-Backstop im Hook. Duplikat (Score > `duplicate_threshold`) ohne `duplicate_confirmed` → `needs_review`/`possible_duplicate`; mit Bestätigung (authentifizierter User) → `approved`. Solution-Embeddings: `embedding`-Spalte existiert, wird bei Approval via `embed_and_store` (englischer Canonical) befüllt; Backend-Endpunkte `POST /internal/solutions/{id}/embedding` + `POST /internal/solutions/similarity`.
- **Echtzeit-Updates:** Zwei WebSocket-Quellen: AI-Service WS (`useRealtimeUpdates.ts`) fuer AI-Events (problem.approved, clustering.started, clustering.completed); Backend WS (`useBackendRealtime.ts`) fuer Mutations (problem.updated/created/deleted, solution.updated, Vote-Scores). Voting: `POST /votes` → Backend gibt `vote_score` direkt zurueck, feuert WS-Event. `ProblemGraph.vue` watcht `props.problems` deep — rendert automatisch neu bei Vote-Score-Aenderungen. Der Backend-WS `/ws` ist ein einzelner unauthentifizierter Shared-Broadcast (auch fuer Moderations-Status-Uebergaenge — die Admin-Queue haengt daran); WS-Payloads duerfen deshalb **nur opake UUIDs + Status-Enum** tragen, nie Titel/Content/`rejection_reason` (Security-Audit 2026-07-05, BE-08 bewusst deferred — sauberer Fix waere ein separater auth. Admin-WS-Kanal).
- **i18n:** Nuxt i18n, alle Texte ueber `t()`, MVP nur Englisch
- **Markdown:** markdown-it + DOMPurify in Loesungsansaetzen — erlaubt: Links, Fettschrift, h2/h3, Listen, Blockquotes; verboten: Bilder, Code-Blocke, HTML. Styling via Tailwind-Variant-Selektoren (`.solution-content h2` etc.) — kein `@tailwindcss/typography prose`. DOMPurify-Hook erzwingt `target="_blank" rel="noopener noreferrer"` auf **allen** Links — nicht nur explizit gesetzten. Seit 2026-07-05 via **`isomorphic-dompurify`**: Sanitizing + Link-Hardening laufen identisch auch beim SSR/Prerender (jsdom) — kein Raw-Bypass mehr; der Hook wird weiterhin lazy registriert (`ensureHook()`), nie auf Modul-Ebene. Siehe Gotchas.
- **Uebersetzung:** Aktiv beim Einreichen — `looksLikeEnglish`-Heuristik → bei Nicht-Englisch „Translate to English"-Button → KI-Service `TranslationService` — Uebersetzung ist eine eigene Provider-Achse: `translation_provider` (openai|anthropic) + `openai_translation_model`/`anthropic_translation_model` (leer = das jeweilige `*_llm_model`), unabhaengig von `llm_provider`/`*_llm_model` (Spam/Clustering/KI-Entwurf). Submit triggert Auto-Translate wenn noch nicht uebersetzt. EN-Felder sind kein Submit-Blocker. Kein DeepL, kein lokales Modell. Backend speichert Original-Text in `original_translations` (Admin-sichtbar) und liefert ihn auf **allen** `/problems`-Lese-Pfaden ans Frontend (`ProblemRead.original_translations`) — so zeigt die UI den Originaltext ohne Translate-Round-Trip. Cache-Key: `sha256` pro Feld (Titel/Beschreibung separat). `EnglishTranslationSection.vue` zeigt EN-Felder als Collapsible mit Chevron + Titel-Preview; Auto-Expand nach Uebersetzung. `POST /ai/translate`: nginx Rate Limiting 5r/m pro IP, Burst 2 — verhindert Missbrauch als freies Uebersetzungstool.
- **Suche (cross-lingual, FTS):** `GET /problems?q=` nutzt **Postgres-Volltextsuche** (`to_tsvector @@ plainto_tsquery`, funktionale GIN-Indizes, Migration 010) statt ILIKE. Registry-getrieben: `services/search_languages.py` (`SEARCH_LANGUAGES` + `tsvector_sql`) ist Single Source of Truth — WHERE, `ts_rank`-Ranking und Übersetzung loopen sie. Pro Sprache matchen die rohe Query **und mehrere via `translate_query` gelieferte Übersetzungs-Kandidaten** (Multi-Kandidaten, OR-verknüpft — Option B) gegen den Sprach-`tsvector`; Stemming vereinheitlicht Deklinations-/Pluralformen (nicht finite Verben — `fehlt`≠`fehlend` unter PG german snowball), cross-linguale Symmetrie via Übersetzung+Stemming. `translate_query` holt die Kandidaten vom ai-service-Endpoint `POST /translate/candidates` (`TranslationService.translate_query_candidates` — gebeugte Formen + nahe Synonyme als JSON-Array, gededuped/gecappt; getrennt vom Single-String-`/translate` der Submit-/Display-Flows). Kandidaten reisen N-sprachig im Cursor (`qt`-Map, pro Sprache eine Liste). Mehr Kandidaten = höhere Cross-lingual-Recall (`missing`→`fehlend`/`vermisst`/… statt einer evtl. falsch-flektierten Einzelübersetzung); exakte Treffer-Parität DE↔EN bleibt prinzipbedingt nicht garantiert. **Sprache hinzufügen** = Registry-Eintrag + funktionale-Index-Migration + Translation-Support (kein Model-/Frontend-/Cursor-Edit). Backend-Param `sort=relevance` (Σ `ts_rank`, Keyset `(rank,id)`, ohne `q` Fallback `created`); im Frontend bei aktiver Keyword-Suche (Begriff + KI aus) **standardmäßig an** (am Übergang gesetzt, manuelles Aus überlebt das Weitertippen). Der explizite Relevanz-Toggle-Button entfällt seit 2026-06-30; ein Klick auf einen Spalten-Header verlässt die Relevanz und sortiert nach Spalte (kein Rückweg ausser über eine neue/geleerte Suche). Sort-Header sind nur im **Semantik**-Modus gesperrt (Backend ordnet dort nach Distanz), im Keyword-Relevanz-Default klickbar. Details: [`docs/features.md`](docs/features.md).
- **Tagging:** Tags (inhaltlich) + Regionen (geografisch) — getrennte Konzepte
- **Editieren:** Nur eigene Eintraege, setzt Status zurueck, Edit-History fuer Moderatoren. Edit-Felder werden mit lokalisiertem Text befuellt (DE: bevorzugt das vom Backend gelieferte `originalTranslations[locale]` — kein LLM-Round-Trip; Fallback `translateForDisplay`. EN: Canonical-Text). `handleSave` prueft `isDirty` vor API-Call, triggert Auto-Translate wenn noetig und schickt bei Nicht-EN-Locale `original_translations` im PATCH mit → Backend re-cached das editierte Original gegen den neuen EN-Canonical. Superuser-Edit eines approved Problems: Status bleibt `approved`, triggert `POST /hooks/problem-reindex` (Re-Embedding + Re-Clustering).
- **KI-Loesungen:** Kein Auto-Generieren — alle Solution-Inhalte kommen von Usern. User-triggered Draft: `POST /ai/generate-solution` → AI-Service gibt Markdown-Draft zurueck (kein Storage), User bearbeitet + submitted separat. nginx Rate Limit 5r/min, Burst=1. KI = Moderation (LLM-Spam-Filter, identisch zu Problems). `is_ai_generated: true` kennzeichnet Admin-erstellte Eintraege. Visuell getrennt, separates Ranking.
- **Auth:** JWT im **HttpOnly-Cookie** statt localStorage (seit 2026-07-06, Security-Audit — Token nie JS-lesbar, XSS-Exfiltration geschlossen). `CookieTransport` (`decisionmap_auth`, `SameSite=Lax` als CSRF-Schutz); Prod: `Domain=.decisionmap.ai` + `Secure` via `COOKIE_DOMAIN`/`COOKIE_SECURE`/`COOKIE_SAMESITE`, Dev: host-only + `Secure=false`. Login und Magic-Verify antworten ohne Token-Body (Cookie wird gesetzt); Frontend sendet jeden Backend-Request mit `credentials: 'include'` (`backendFetch`), Session-Restore = Cookie-Probe via `/users/me` (401 = anonym, kein Fehler). Magic-Link-Verify setzt zusaetzlich `is_verified=true` (E-Mail-Besitz bewiesen). E-Mail-Verifizierung nach Registrierung (`registrationSent`-Flag, kein Auto-Login). Passwort-Staerke-Checklist live im Register-Tab (✓/○ pro Regel, Submit gesperrt bis alle gruen). `/verify-email.vue` → Redirect auf `/login?verified=true`. Dev: Mailpit als SMTP-Sink.
- **Status-Page:** `/status` zeigt Live-Status von Backend (FastAPI) und AI-Service. Browser-seitige Health-Checks via `fetch` direkt gegen die Services (kein Server-Route-Proxy). Polling alle 30s, `useServiceStatus` Composable mit Shared State (Modul-Level Refs). StatusBar zeigt Farbindikator: gruen (alle ok), orange (nur Backend degraded), rot (Backend down). Backend: `GET /health` (gibt `status`, `database` zurueck — seit Security-Audit 2026-07-05 bewusst ohne `version`, kein Build-Fingerprinting auf unauthentifiziertem Endpoint). AI-Service: `GET /health`, via nginx `GET /ai/health`.

---

## Infrastructure

→ **Ausfuehrliche Spezifikation:** [`docs/backend.md`](docs/backend.md)

- **Env-Variablen:** Nie hardcoden, alle in `.env.example`
- **Feature Flags:** `AUTO_APPROVE` — **rein server-seitig** (Backend `settings.auto_approve` → `initial_status`), schaltet neue Problems **und Lösungen** direkt auf `approved` und überspringt das LLM-Moderations-Gate (Spam/Duplikat); Embedding + Clustering laufen weiter. Das gleichnamige, nie gelesene Frontend-Public-Flag (`runtimeConfig.public.autoApprove` / `NUXT_PUBLIC_AUTO_APPROVE`) wurde 2026-07-08 entfernt — ein Public-Client-Flag darf Moderation nicht umgehen. (Die früher gelisteten `SHOW_VOTING`/`REQUIRE_AUTH` waren nie im Code verdrahtet und wurden 2026-07-07 entfernt — Voting ist immer aktiv, Auth strukturell via fastapi-users/Route-Guards.)
- **Linting:** ESLint + Prettier (TS) / ruff (Python) — automatisch, nicht verhandelbar
- **Makefile:** Jedes Sub-Repo hat ein eigenes Makefile. `make help` (Root: Workspace-Delegation), `make -C apps/backend help` (Docker, DB, Backup). Details: [`docs/backend.md`](docs/backend.md)
- **Versionierung:** SemVer + Datum (`semVerBump`, BashLib `version.lib.sh`): `v<MAJOR>.<MINOR>.<PATCH>+<YYMMDD>.<HHMM>.<HASH>`, Start bei `0.1.0`. Docker-Snapshots: `gitDockerTag` → `<MAJOR>.<MINOR>.<PATCH>-<YYMMDD>.<HHMM>.<HASH>[.ahead<N>]` (z.B. `0.1.0-260412.0824.def34.ahead3`) — automatisch via Jenkins. Details: [`docs/backend.md`](docs/backend.md)
- **Git:** Conventional Commits `<type>(<scope>): <msg>`, direkte Commits auf `master` erlaubt — Jenkins ist die einzige Schranke. Details on demand: `/git-conventions`
- **Seeds:** `apps/backend/database/seeds/` — System-Seeds (`001_regions.sql`, `002_tags.sql`), Demo-Daten in `seeds/demo/`. `make db-seed` (System), `make db-seed-demo` (+ Demo). Alphabetisch, idempotent.
- **Backup:** `scripts/db-backup.sh` (einheitliches Script, `.dump`-Format). Dev: `make -C apps/backend backup|restore|backup-list`. Prod: `make -C infrastructure backup|backup-restore|backup-list|backup-pull|backup-push`. Nie einchecken. Details: [`docs/backend.md`](docs/backend.md)
- **Backend-Architektur:** Nuxt → FastAPI (`apps/backend/`, Port 8001) → PostgreSQL. AI-Service (`apps/ai-service/`, Port 8000) kommuniziert nur ueber `/internal/*` Backend-API — kein direkter DB-Zugriff.

---

## Kritische Gotchas

→ Vollstaendige Liste on demand: `/gotchas`

- **Seeds-Trennung:** `seeds/` = System-Daten (Regions + Tags L0–L9), `seeds/demo/` = Demo-Daten (Problems, Solutions, User-Tags L10). `make db-reset` importiert nur System-Seeds — nie Demo-Daten in Production einspielen.
- **FastAPI Soft-Delete-Filter:** `deleted_at IS NULL` wird NICHT automatisch gefiltert — jede Query braucht diesen Filter explizit. Gilt auch fuer `/internal/*`-Endpoints (`store_embedding`, `update_status`) — nicht nur in den oeffentlichen Routes.
- **FastAPI Ownership-Check:** `current_user` authentifiziert — aber PATCH/DELETE auf user-eigene Ressourcen brauchen explizite Ownership-Pruefung: `if resource.author_id != current_user.id: raise HTTPException(403)`. Fehlt der Check, kann jeder eingeloggte User fremde Eintraege manipulieren.
- **FastAPI Solutions-Filter Auth:** `GET /solutions?status_filter=rejected` (und alle Nicht-`approved`-Werte) erfordert Superuser-Auth — normaler User bekommt 403. Nur `status_filter=approved` ist ohne erhöhte Rechte zugänglich. Nicht aus der Route-Signatur erkennbar.
- **FastAPI Detail-Endpoints: nicht-`approved` → 404, nicht 403:** `GET /problems/{id}` und `GET /solutions/{id}` liefern fuer nicht-`approved` Eintraege 404, ausser der Aufrufer ist Superuser oder Owner (`current_optional_user`-Guard, seit Security-Audit 2026-07-05, BE-06). Bewusst 404 statt 403 — die Existenz eines pending/rejected Eintrags wird Dritten nie bestaetigt. Tests, die pending Inhalte anonym lesen, erwarten deshalb 404.
- **FastAPI Secret-Defaults:** `SECRET_KEY` und `SERVICE_TOKEN` nie mit funktionsfaehigen Prod-Werten defaulten. Seit 2026-07-05 erzwungen: Defaults sind `""`, `_validate_settings` (Backend `main.py`) wirft beim Start `RuntimeError` bei leerem/Platzhalter-Wert oder CORS-`*`+credentials; der ai-service bricht bei leerem `SERVICE_TOKEN` ebenfalls hart ab (Dev-Opt-in nur via explizitem `ALLOW_INSECURE_DEV=true`). Audit-Report: [`docs/security-audit-2026-07-05.md`](docs/security-audit-2026-07-05.md).
- **FastAPI `MAIL_FROM` — kein `.local`:** Ist `MAIL_FROM` auf eine `.local`-Domain gesetzt (z.B. `noreply@decisionmap.local`), startet das Backend nicht — auch wenn `MAIL_SUPPRESS=true`. Immer eine gueltige Domain verwenden.
- **FastAPI WebSocket-Events explizit:** FastAPI feuert keine automatischen DB-Events — nach jedem Mutations-Endpoint `ws_manager.broadcast()` aufrufen.
- **FastAPI Background Tasks:** Brauchen eigene DB-Connection — Request-scoped Connection ist beim Task-Start geschlossen.
- **asyncpg `:param::type` bricht Parameter-Substitution:** `embedding <=> :emb::vector` in SQLAlchemy `text()` bindet nur den ersten Parameter — asyncpg stoppt Substitution beim `::` direkt nach dem Parameternamen. Fix: Klammern setzen: `embedding <=> (:emb)::vector`. Ohne Klammern fehlt `emb` komplett in den gebundenen Parametern → PostgreSQL sieht `:` im SQL → Syntax Error.
- **CORS:** `allow_credentials=True` + `allow_origins=["*"]` ist browser-invalid — nie zusammen.
- **Health-Checks nur Browser-seitig:** Nitro Server-Routes erreichen Docker-Ports nicht. `fetch()` direkt im Browser, `AbortSignal.timeout(10_000)`.
- **Let's Encrypt Symlinks (nginx-Container):** `live/fullchain.pem` ist ein Symlink auf `archive/` — beide Verzeichnisse in `docker-compose.yml` mounten, sonst schlägt TLS fehl.
- **Docker Compose V2 auf Ubuntu:** `docker.io` (Ubuntu-Paket) liefert kein `docker compose` (V2). Offizielles Docker-Repository erforderlich — `docker-compose-plugin` installieren.
- **AWS SES DNS-Records — Trailing Dot + Hetzner Name-Feld:** Alle Ziel-Werte (CNAME und MX) muessen mit Punkt enden (`xxxxx.dkim.amazonses.com.`, `feedback-smtp.eu-west-1.amazonses.com.`). Fehlt der Punkt, haengt Hetzner die eigene Domain an → Records ungueltig. Im Name/Host-Feld nur die Subdomain eintragen (`mail` — nicht `mail.decisionmap.ai`): Hetzner haengt die Zone automatisch an → `mail.decisionmap.ai.decisionmap.ai` bei FQDN-Eingabe. DNS-Verwaltung ueber `dns.hetzner.com` (neues Interface), nicht Hetzner Robot (lehnt externe CNAME-Ziele ab). Vollstaendige Anleitung: [`docs/ses-setup.md`](docs/ses-setup.md).
- **AWS SES Custom MAIL FROM Domain:** AWS schlaegt `no-reply.decisionmap.ai` als Standard vor — nicht blind uebernehmen. Bessere Wahl: `mail.decisionmap.ai` (kuerzer, klarer). Im Bearbeiten-Dialog im Abschnitt *Benutzerdefinierte MAIL-From-Domain* vor dem Speichern anpassen.
- **nginx `proxy_pass` mit Variable + `rewrite` — drei Gotchas:** (1) `proxy_pass http://$var/` macht keine Prefix-Substitution — `/ai/health` landet als `/ai/health` beim AI-Service. (2) `rewrite ... break` stoppt auch `set` — `set $var` immer **vor** `rewrite` stellen, sonst bleibt Variable leer → "no host in upstream". (3) `proxy_pass http://$var` ohne URI nach `rewrite` nimmt die Original-URI — `$uri` explizit übergeben: `proxy_pass http://$upstream$uri$is_args$args`.
- **WebSocket Composables brauchen explizites `connect()` in `onMounted`:** `useRealtimeUpdates` (AI-Service WS) und `useBackendRealtime` verbinden sich nicht automatisch. Fehlt der `connect()`-Call in `onMounted`, bleibt der Socket stumm — kein Fehler, kein Event.
- **Internal API Tag-Naming:** DB-Spalte heisst `name`, die `/internal/tags` API nutzt `label` — transparente Umwandlung im Backend. ai-service immer `label` verwenden.
- **AI-Service kein direkter DB-Zugriff:** ai-service nutzt ausschliesslich `/internal/*` Backend-Endpoints via `BackendClient` (httpx). Kein psycopg, kein SQLAlchemy im ai-service.
- **uvicorn `--app-dir` aendert nicht das Working Directory:** python-dotenv sucht `.env` im CWD, nicht in `--app-dir`. Procfile.dev verwendet deshalb `bash -c 'cd apps/ai-service && uvicorn ...'` — sonst findet der AI-Service seine `.env` nicht und Similarity-Requests schlagen still fehl.
- **uvicorn `--reload` erkennt keine `.env`-Aenderungen:** `--reload` reagiert nur auf Python-File-Aenderungen. Nach jeder `.env`-Aenderung (z.B. `SIMILARITY_THRESHOLD`) braucht der AI-Service einen vollstaendigen Neustart — sonst bleiben neue Einstellungen wirkungslos (alte Werte greifen still weiter, kein Fehler). Hinweis: `MIN_CLUSTER_SIZE` ist kein Env-Key mehr — HDBSCAN skaliert adaptiv (`sqrt(n/4)`).
- **Stales `.overmind.sock` blockiert `make dev-up`:** Bricht overmind unerwartet ab (Crash, Ctrl+C), bleibt `.overmind.sock` im Root liegen. Der naechste `make dev-up` schlaegt fehl, weil overmind das Socket noch belegt sieht. `make dev-down` raeumt das Socket automatisch auf (`rm -f .overmind.sock`). Manuell: `rm -f .overmind.sock`.
- **Procfile.dev `backend` = Log-Follower:** `docker logs -f decisionmap-backend-api` — kein Container-Start. `overmind restart backend` startet nur den `docker logs`-Prozess neu, nicht den Container. Container-Lifecycle: `make -C apps/backend dev-up/dev-down`.
- **Nuxt Layout `localStorage` braucht `import.meta.client`-Guard:** `default.vue` wird als Layout auch fuer SSR-Routen (`/problem/**`, `/cluster/**`) gerendert. `localStorage`-Zugriff ausserhalb von `onMounted` → `ReferenceError: localStorage is not defined`. Guard: `if (import.meta.client) { ... localStorage ... }`. `onMounted` ist implizit client-seitig — kein Guard noetig.
- **Keine DOM-abhaengigen Library-Seiteneffekte auf Modul-Ebene (DOMPurify-Hook crasht Prerender):** `DOMPurify.addHook(...)` (und jeder `document.*`/`window.*`-Zugriff) im Modul-Body crasht den Prerender/SSR von `/problem/**` + `/cluster/**` — beim Import ist der DOMPurify-Default-Export eine uninitialisierte Factory ohne `addHook`/`sanitize` (`addHook is not a function`). `utils/markdown.ts` nutzt deshalb **`isomorphic-dompurify`** (voll initialisierte Instanz auf Server via jsdom und Client — seit 2026-07-05; der fruehere Raw-Bypass bei `typeof window === 'undefined'` ist entfernt, Allowlist + Link-Hardening laufen auf beiden Pfaden) und registriert den Hook lazy via `ensureHook()` im Render-Call (idempotent, nie auf Modul-Ebene). Gleiche Klasse wie der `localStorage`-auf-SSR-Routen-Gotcha. Regel: DOM-abhaengige Seiteneffekte lazy hinter `typeof window`-Guard, nie im Modul-Body von Code der ueber eine prerender/SSR-Route importiert wird.
- **`PENDING_OPEN_PROBLEM_FORM`-Flag muss unconditional geloescht werden:** `default.vue` `onMounted` loescht das Flag **immer** — auch wenn der User nicht eingeloggt ist. Fehlt das unconditional Clear, oeffnet sich das Formular beim naechsten Login unerwartet (Ghost-Open nach abgebrochenem Login).
- **`+`-Button-Auth-Entscheidung nur im Container, nicht im emittierenden Button:** Alle `+`-Buttons (inkl. `DmTopBar`) emittieren unconditional `open-form`; die Auth-Pruefung (Formular vs. Login-Redirect) liegt allein in `handleOpenForm` (`default.vue`). Ein Button, der selbst auth-prueft und fuer Gaeste `open-login` emittiert, umgeht die `PENDING_OPEN_PROBLEM_FORM`-Flag-Logik → kein Popup nach Login (Bold-Redesign-Regression). Der Gast-Redirect setzt `?redirect=<origin>` (`route.path`); `login.vue` loest das Ziel via `resolveRedirect()` auf — Open-Redirect-Guard: nur interne Pfade (`startsWith('/')` und nicht `//`), sonst Fallback `/`. Gilt fuer `handleLogin` und den `onMounted`-Auto-Redirect.
- **Nuxt Buttons ohne `type` submitten als Form-Submit:** HTML-Default ist `type="submit"`. Buttons in Layouts, Panels und Komponenten immer explizit `type="button"` setzen — ausser bei echten Submit-Buttons in Formularen. Betrifft z.B. Dark-Mode-Toggle, Logout, Panel-Close, Breadcrumb-Segmente.
- **Modal-Submit-Button im Sticky-Footer braucht `form="<id>"`-Attribut:** Modal-Layout = Header / scrollbarer Body (= `<form id="...">`) / Sticky-Footer. Submit-Button sitzt im Footer, also ausserhalb des `<form>`-Elements. HTML5 erlaubt `<button form="<form-id>" type="submit">` — der Klick triggert ein Submit auf das referenzierte Form. Alternative (`@click="handleSubmit()"` von ausserhalb) bricht Browser-Form-Semantik: kein `Enter`-Submit aus Eingabefeldern, keine native HTML5-Validation. Eingefuehrt in T-12 (`ProblemForm.vue`).
- **Scrollbarer Modal-Body braucht `min-h-0` auf dem flex-Child:** Modal-Card ist Flex-Column (Header `shrink-0` / Body `flex-1 overflow-y-auto` / Footer `shrink-0`). Default-Flex-Item hat `min-height: min-content` — bei langen Forms expandiert der Body auf seine Content-Hoehe und das Modal waechst ueber `max-height` hinaus, `overflow-y-auto` greift nie. Fix: `min-h-0` auf den Body. Analog `min-w-0` in horizontalen Flex-Layouts mit Truncation. Vgl. Konventionen Fund 25.
- **Centered Modal `<Teleport to="body">` gehoert IN die Komponente, nicht in den Caller:** T-12-Pattern fuer ProblemForm — `<Teleport to="body">` sitzt im Template der Komponente selbst. Caller rendert nur `<ProblemForm v-if="open" />` als Root-Sibling. Vorteil: die Komponente kontrolliert ihren Render-Kontext (Backdrop, Z-Index, Body-Mount) — kein Caller-Vertrag. State-Trennung: `isProblemFormModalOpen` ist im Layout ein eigener Ref distinkt von `isPanelOpen` (das Side-Panel zeigt weiterhin Problem-Detail). Nach T-12 ist `#panel-status-target` in `layouts/default.vue` orphan (Cleanup-Kandidat). **Migrations-Gotcha (Fix `87eb98f`):** sobald eine Komponente self-contained Teleport bekommt, oeffnet sich das Modal bei jedem Mount der Komponente — alle `pages/*.vue` muessen den alten Pre-T-12-Pattern (`<Teleport to="#panel-slot-target"><ProblemForm v-else /></Teleport>`) auf `<ProblemForm v-if="isProblemFormModalOpen" />` als Root-Sibling umstellen. Wurde initial nur fuer `pages/index.vue` gemacht; `pages/table.vue` rendert die Form unconditional im `panel-slot`-Teleport (sobald `selectedProblem` null war) — beim Routing-Wechsel auf `/table` poppte das Modal auf, ohne dass „+ Add problem" geklickt wurde. Regel: beim Einfuehren von self-contained Teleport-Komponenten **alle** Verwender via `grep -rE 'ProblemForm|<KomponentenName' apps/frontend/pages/ apps/frontend/components/` auditieren — Refactor ist nicht abgeschlossen, bevor jeder Mount-Pfad einen v-if-Guard hat.
- **FOUC-Bootstrap muss zu `resolveSystemTheme()` passen:** Das parser-blockende Inline-Skript in `nuxt.config.ts` (`app.head.script`) setzt `data-theme` vor dem Vue-Mount. Sein Fallback bei `theme-system-preference === 'system'` muss exakt die IDs liefern, die `resolveSystemTheme()` in `composables/useTheme.ts` zurueckgibt (`glass-dark`/`glass-light`). Driftet das auseinander (z.B. nach einem Default-Theme-Wechsel), flackert beim ersten Reload kurz das alte Theme auf, bevor der Mount korrigiert. Kein Konsolen-Fehler. **Drei Stellen muessen bei jedem Default-Theme-Switch synchron bleiben:** (1) Bootstrap-Skript in `nuxt.config.ts`, (2) `resolveSystemTheme()` in `composables/useTheme.ts`, (3) `activeThemeId` und `customAccent` Initial-Werte im selben File (SSR-/Hardcore-Fallback, bevor `initTheme()` localStorage gelesen hat). Default-Historie: T-09 stellte (3) von `default-light`/`#2563eb` auf `glass-light`/`#C53A82` um; seit 2026-06-29 ist der Out-of-Box-Default `glass-dark`/`#FF8C00` (Sunset-Accent) mit Fuchsia-KI-Akzent. **Erstbesuch folgt nicht mehr dem OS:** Bootstrap-`!t`-Zweig und `initTheme()`-First-Visit liefern hart `glass-dark` (OS-Following nur opt-in via explizites `theme-system-preference === 'system'`, das weiterhin `resolveSystemTheme()` nutzt). Bestehende User mit gespeichertem `theme-id` in localStorage spueren nichts (`initTheme()` ueberschreibt den Initial-State), aber der erste SSR-Render-Tick ohne Storage haengt sonst am alten Default.
- **Komponenten-Inline-rgba bricht Theme-Switch:** Border/Text-Color via `rgb(var(--th-accent))`, Background aber `rgba(255,140,0,0.14)` (hardcoded Glass-Dark-Sunset) → in 7 von 8 Themes haengt der orange Hintergrund neben dem theme-konformen Border. Fix: `rgb(var(--th-accent) / 0.14)` — die `--th-*`-Tokens sind als space-separated RGB-Tripel definiert, `rgb(... / alpha)` kombiniert Token und Transparenz ohne Custom-Property-Aufspaltung. Suchpattern: `grep -rE 'rgba?\([0-9]+,\s*[0-9]+,\s*[0-9]+' apps/frontend/components/`.
- **`--th-border` vorberechnet, nicht via Opacity-Modifier:** Glass-Themes hatten `--th-border: 255 255 255` mit der Annahme, jede Komponente nutzt `border-th-border/10`. 69 Treffer von `border-th-border` (ohne Modifier) zogen solid-weiße Linien quer durch die UI. Fix in `assets/css/themes.css` (Commit `08ea1be`): Token-Werte auf ihre intendierte Sichtbarkeit vorberechnen — Glass-Dark `50 44 68` (≈15% Weiß auf `#08060E`), Glass-Light `226 223 218` (≈8% Dunkel auf `#F4F1EA`). `--th-border-subtle` und `--th-input-border` analog. Regel: Token-Werte tragen ihre intendierte Farbe — Opacity-Modifier sind eine fakultative Verfeinerung, kein Pflicht-Vertrag.
- **Clustering schreibt in `problem_tag`:** `clusters` und `problem_cluster` sind gedroppt (Migration 005, 2026-05-22). Der AI-Service legt L1-Tags via `POST /internal/tags/upsert` an und verknuepft Probleme via `POST /internal/problems/{id}/structural-tag`. Das Frontend liest ausschliesslich `problem_tag` — keine separate Cluster-Tabelle.
- **`problem_tag` FK-Violation durch veraltete Tag-IDs:** Das Frontend haelt `editTagIds` aus dem letzten Laden des Problems. Wenn Clustering danach Tags loescht/ersetzt, sind diese IDs veraltet. `_replace_junctions()` in `routers/problems.py` validiert deshalb alle Tag-IDs gegen die `tags`-Tabelle vor dem INSERT — stale IDs werden still gefiltert. Symptom ohne Fix: `IntegrityError ForeignKeyViolationError` → User sieht "Could not save changes".
- **Cytoscape.js Badge-Position:** Badge-Mittelpunkt liegt an der Node-Ecke (halbe Badge inside/outside) — gewolltes Design, kein Bug. `positionSolutionBadge` und `positionSearchBadges` nutzen `parent.width()/height()` fuer dynamische Offsets.
- **Cytoscape Gradient braucht `background-fill: 'linear-gradient'`:** Ohne dieses Property werden alle `background-gradient-*`-Stops still ignoriert — Node rendert solid (`background-color`). Kein Konsolen-Fehler. Gilt analog fuer Edges (`line-fill: 'linear-gradient'`, sonst nur `line-color`). Reihenfolge in der Style-Map egal — Vorhandensein zaehlt. Betrifft Root-Node und Root→L1-Edges im Glass-Stylesheet.
- **Cytoscape `cy.style()` nie in `cy.batch()`:** Ein im Batch gesetzter Style greift **nicht** auf die im selben Batch hinzugefuegten Elemente — sie fallen auf Cytoscape-Defaults zurueck (Edges grau/dick/Haystack, Knoten 30px-Grau-Kreis). Symptom in `ProblemGraph.vue` `rerender()`: »fette graue Edges + graue Cluster-Punkte nach Klick auf ein Problem« (kein Konsolen-Fehler, kein HMR-Problem — ein frischer Mount maskiert es, erst der naechste `rerender` schlaegt zu). Fix: `cy.style(buildStyle())` **vor** den `cy.batch()` ziehen; der Batch enthaelt nur `elements().remove()` + `add()`. Ein Fix behebt Edges und Dekorations-Knoten gemeinsam (gleiche Ursache).
- **Cytoscape Decoration-Badges folgen Drag nur via `position`-Event:** `positionBadges()` laeuft nur am Layout-Ende. Beim manuellen Drag des Parent bleibt die Decoration-Node stehen. Fix: `cy.on('position', '<parent-selector>', repositionBadgesFor)` — Selektor muss alle ziehbaren Parent-Klassen aufzaehlen (`.inner-cluster-node, .leaf-cluster-node, .root-node, .unclustered-node, .problem-node`), **nicht** `'node'` — sonst feuert das Event auch fuer die Decoration-Badges selbst und loest Endlosschleifen aus. Persistente User-Positionen schreibt `cy.on('dragfree', 'node', save)` (nicht `position` — feuert tausendmal pro Drag), Restore via `applyStoredPositions()` im Layout-`stop:`-Callback.
- **Cytoscape Viewport-Persistence ausschliesslich via `viewport`-Event + Debounce:** `zoom` und `pan` separat zu listenen feuert ≥60×/s waehrend Pan-Drag — localStorage thrasht. `cy.on('viewport', cb)` deckt beide ab; `setTimeout`+`clearTimeout` mit 400ms-Debounce schreibt erst nach Stillstand. Guard `viewLevel === 'mindmap'` verhindert dass Drill-Views (`fit:true`) den globalen Viewport ueberschreiben. Restore in `centerOnRoot()`: erst `loadStoredViewport()`-Probe, sonst Default-Zoom 1 + `cy.center(root)`.
- **Cytoscape erkennt Container-Resize nicht — `ResizeObserver` → `cy.resize()` + Re-Layout:** Oeffnet sich das Detail-Panel (Graph schrumpft auf ~70%), bleibt das Canvas auf der alten Breite zentriert und rutscht unter das Panel — Cytoscape feuert kein Resize-Event von selbst. `ProblemGraph.vue` observed `containerRef`, ruft bei jeder Breitenaenderung `cy.resize()` + (280ms-debounced) `reapplyCurrentLayout(false)` (re-runt `applyTagFilters`/`showMindmap` mit dem zoom-gecappten `fit`). Debounce 280ms (nicht ~160ms): das Panel oeffnet/schliesst mit CSS-Width-Transition die jeden Frame feuert — ein kuerzerer Debounce re-fittet mitten in der Animation auf eine Zwischenbreite. Cleanup (`disconnect()` + `clearTimeout`) in `onUnmounted`; jsdom hat kein `ResizeObserver` → No-Op-Polyfill in `tests/setup.ts`, sonst werfen die Mount-Tests. Drill-Fit nur auf **echten** Knoten: das Layout-eigene `fit:true` fittet die Dekorations-Badges mit, die noch bei `(0,0)` liegen → aufgeblaehte Fit-bbox → falscher zu-niedriger (~67%) Zoom. `fitDrillView()` (im `stop:` + Non-Animate-Pfad) fittet nur auf die sichtbaren Echt-Knoten und deckelt auf `FIT_MAX_ZOOM = 1` — behebt Unter-Zoom (Badge-Inflation) **und** Ueber-Zoom (duenne Cluster); Modell-Positionen unveraendert. Der Drill ist ein **instanter Schnitt**, keine Zoom-Animation: `addTagFilter` drillt non-animiert (`applyTagFilters(false)`) und `fitDrillView` fittet instant nur auf die Echt-Knoten (`cy.fit(real, 56)`, danach `cy.zoom(FIT_MAX_ZOOM)`/`cy.center` falls > 100%). Ein zwischenzeitlich probierter animierter Kamera-Glide (`cy.animate`, 200ms) wurde wieder entfernt — der Kamera-Flug las sich als eigenstaendige, stoerende Animation; ein Drill soll ein sauberer Schnitt in den Endzustand sein. `maxZoom` wird trotzdem **vor** `layout.run()` temporaer auf `FIT_MAX_ZOOM` gesetzt und im `stop:`/Non-Animate-Pfad wieder auf `GRAPH_MAX_ZOOM = 3` (den manuellen Zoom-Deckel aus `initGraph`) restauriert, damit der Layout-eigene `fit:true` nicht ueber 100% schiesst. Die Spaltenzahl waehlt `buildProblemsGridPositions` als die den Fit-Zoom **maximierende** (deterministisch) statt `round(sqrt(...))` (dessen Rundungssprung das instabile 67%↔99%-Zoom verursachte). `addTagFilter(tagId)` returnt frueh wenn der Tag bereits aktiv ist — Klick auf den schon gedrillten Cluster ist ein No-op (sonst ruckartiger Re-Fit-Sprung). **Streaming-Coalescing:** der `watch` auf `props.problems` etc. ruft `debouncedRerender()` (140ms) statt `rerender()` — beim Drill lazy-geladene Seiten werden zu **einem** Rerender zusammengefasst, sonst springt der Graph durch mehrere Zwischen-Zoom-Zustaende, bevor er sich setzt.
- **Cytoscape `saveCurrentPositions` nie `(0,0)` persistieren:** `rerender()` fuegt neue Nodes ohne Position bei `(0,0)` ein, bevor das `preset`-Layout sie setzt. Feuert in genau diesem Frame ein `dragfree`-Event, schreibt der Save `{0,0}` in `localStorage['graph-node-positions']` → beim naechsten Laden stapeln sich **alle** Boxen uebereinander (»ueberlappende Boxen«-Bug, ueberlebt Reloads weil aus dem Storage). Fix: jeden Knoten mit exakt `x === 0 && y === 0` ueberspringen. Regel: einen Persistenz-Snapshot nie ungefiltert aus einem State ziehen, der einen legitimen Uebergangs-Nullwert kennt.
- **Cytoscape Node-Positionen sind per-View gescoped, nicht flach:** Ein Knoten (z.B. ein Cluster) hat im Mindmap eine **andere** Layout-Position als wenn er der Anchor eines gedrillten Views ist — eine flache `{id: {x,y}}`-Map liesse eine im Mindmap verschobene Box eine Ebene tiefer an derselben Stelle wieder auftauchen. `graph-node-positions` ist daher verschachtelt (`{scope: {id: {x,y}}}`), Scope = `mindmap` bzw. `drill:<sortierte tag-ids>` (`currentPositionScope`). `saveCurrentPositions` schreibt **nur** die im aktuellen View **sichtbaren** Knoten (`!node.hidden()`) in den aktiven Scope — versteckte Knoten gehoeren zu anderen Ebenen und wuerden sonst ihre stale Position leaken. Das Legacy-Flachformat wird beim Laden (`loadAllStoredPositions`) automatisch in den `mindmap`-Scope migriert. Der Reset-Button loescht den ganzen Key (**alle** Ebenen).
- **Mindmap-Rueckkehr ist ein instanter Cut (`showMindmap(false)` an allen Call-Sites), keine Animation:** Beim **animierten** Zurueckwechseln in die Mindmap-Uebersicht flogen die Dekorations-Badges (`cluster-dot`/`cluster-count-badge`) quer ueber den Screen (»Mindmap-Fliegen«) — ein animierter `showMindmap` (vom Klick) und ein Rerender ueberlappten, die Badges wurden mittendrin sichtbar und aus dem Ursprung mit-animiert (gemessen: Sprung auf ~608px, dann Flug auf ~95px). Ein zwischenzeitlicher Fix, der die Badges vor `layout.run()` `hide()`te, kaschierte nur das Symptom (und ist nicht mehr im Code — `showMindmap` **zeigt** die Badges vor dem Layout). Endgueltiger Fix: **alle sechs** zuvor animierten `showMindmap`-Aufrufe (`applyTagFilters`-Leerfilter, `removeTagFilter`, `resetPositions`, `resetToMindmap`, zwei in `initGraph`) laufen jetzt **instant** (`showMindmap(false)`) — der Return zur Uebersicht ist ein **Cut**, kein Flug, konsistent mit dem instanten Drill (`applyTagFilters(false)`). Ohne Animation laeuft nichts mit; verifiziert: Dot-zu-Parent-Abstand konstant ~95px statt 608→95-Flug. Regel wie beim Drill-Fit: Dekorations-Badges nie in ein animiertes Layout mitlaufen lassen — hier geloest, indem der Uebergang gar nicht mehr animiert.
- **`navigator.geolocation` PERMISSION_DENIED auf HTTP-Origins:** Browser blockiert `navigator.geolocation` automatisch auf nicht-sicheren Origins (HTTP ohne HTTPS) — `error.code === 1` (`PERMISSION_DENIED`), auch ohne User-Ablehnung. Betrifft `int.decisionmap.ai` (HTTP-Staging). `useRegionDetection` faengt diesen Fall und schaltet auf Backend-Proxy (`GET /regions/geo`) um. Backend ruft `ip-api.com` server-seitig auf (vermeidet CORS auf HTTP; `ipapi.co` hat zu strenge Rate Limits). `country_code + region_code` → Region-Match (z.B. `AT-9`).
- **`navigator.clipboard` nur im Secure Context — naiver `writeText` faellt auf HTTP still aus:** Gleiche Secure-Context-Klasse wie der Geolocation-Gotcha. `navigator.clipboard` existiert nur auf HTTPS/`localhost`; auf HTTP-Origins (`int.decisionmap.ai`) ist es `undefined` → `writeText` wirft, ein `catch` der nur `consola.error` ruft = Silent-Fail. Fix: `utils/clipboard.ts` (`copyToClipboard`) mit Legacy-`document.execCommand('copy')`-Fallback (verstecktes `<textarea>`), gibt `true`/`false` statt zu werfen; `import.meta.client`-Guard. `ProblemPanel.copyPermalink` zeigt bei `false` einen Error-Toast (`permalink.copyFailed`). Wiederverwendbar fuer kuenftige Share-Buttons. Regel: jeden Secure-Context-only Browser-API-Zugriff (`clipboard`, `geolocation`, `crypto.subtle`) mit HTTP-Fallback **oder** sichtbarem Fehler-Pfad versehen.
- **Playwright `waitForLoadState('networkidle')` haengt in Nuxt:** Nuxt oeffnet WebSockets fuer alle User (auch anon) in `onMounted`. `networkidle` wartet auf Netzwerkruhe — bei offenen WS-Verbindungen tritt diese nie ein. Fix: `'domcontentloaded'` oder `'load'` verwenden, nicht `'networkidle'`. Gilt fuer alle Specs die anon-Routen testen.
- **Playwright `baseURL` in `playwright.config.ts` und `global-setup.ts` muessen uebereinstimmen:** Beide muessen `E2E_BASE_URL` als Quelle nutzen (Default: `http://localhost:3000`). Unterschiedliche Defaults fuehren zu Cookie-Domain-Mismatch: Auth-Cookie wird fuer Host A gesetzt, Spec laeuft gegen Host B → `authenticated`-Tests schlagen still fehl.
- **`EnglishTranslationSection` `isCollapsed` und async Props:** `showFields` transitiert `false → true` waehrend `loadLocalizedEditFields` laeuft (async) — `watch(showFields)` feuert und expandiert die Sektion trotz `startCollapsed=true`. Fix: `startCollapsed`-Prop + `onMounted`-Guard (`if (showFields.value && startCollapsed) isCollapsed.value = true`). Ohne Vitest-Spec nicht erkennbar — Komponenten-Collapse-Verhalten testen.
- **EN-Section sichtbar bei `locale=en` ohne locale-Guard:** `looksLikeEnglish()` gibt `true` fuer ASCII-Text zurueck — bei englischer UI-Sprache wird `englishAutoDetected=true` und damit `showEnSection=true`, obwohl kein Uebersetzungsflow noetig ist. Fix: `showEnSection` in `useEnglishTranslation.ts` prueft `locale.value !== 'en'`; `SolutionForm.vue` und `SolutionDetail.vue` haben denselben inline-Guard (`v-if="locale !== 'en' && content.length >= 20"`). Ergaenzend blocken `validateForm`/`handleSave`/`handleSubmit`/`handleSaveEdit` non-ASCII-Eingaben via `NON_ASCII_RE` (`/[^\x00-\x7F\p{P}\p{S}\p{N}\p{Z}\p{C}]/u` — Unicode-Property-Escapes: Buchstaben wie ä ö ü Kyrillisch CJK blockiert, Satzzeichen/Symbole/Zahlen erlaubt) mit `form.validation.inputEnglishOnly` wenn `locale === 'en'`. `"4–6 weeks"` läuft durch.

---

## Was nicht gemacht wird

- Kein direktes CSS — Tailwind Utility Classes
- Kein Hard Delete — Soft Delete ueber `deleted_at`/`deleted_by`
- Keine rohen IP-Adressen — `ip_hash` verwenden
- Kein Markdown ohne DOMPurify-Sanitizing
- Keine hardcodierten UI-Strings — i18n (`t()`)
- `.env` nie einchecken — nur `.env.example`
- Keys nie nur in `.env` ergaenzen — `.env.example` ist die **Source of Truth** fuer den Key-Bestand (neuer Key = `.env.example` + Code; ein Key, den die `.env.example` nicht kennt, gehoert aus der `.env` entfernt, nicht „nachdokumentiert")
- `.env`-Values nie ausgeben (`cat`/`grep` auf `.env` verboten) — nur Keys via `env-audit.py` oder `cut -d= -f1`; Werte-Abgleich nur via `env-audit.py --check` (leak-frei: Secrets als `sha256:`-Fingerprint, URL-Credentials maskiert, Typ-Check aus SoT-Default, Cross-Repo-Konsistenz z.B. `SERVICE_TOKEN`). `--reveal --yes` (Rohwerte) ist dem User im eigenen Terminal vorbehalten — nie durch einen Assistenten ausfuehren
- `.env`/`.env.example`-Kommentare **immer ueber dem Wert** (eigene `#`-Zeile), nie inline (`KEY=value # comment`). Inline-Kommentare sind parser-abhaengig — python-dotenv/Nuxt/Compose strippen sie nur mit Leerzeichen vor `#`, aeltere Parser nehmen sie in den Wert auf (korrumpiert still z.B. `MAIL_PORT`). Above-line ist ueber alle Parser eindeutig. Key-**Beschreibungen** in `.env.example` als Debian-Style **`#:`-Zeile(n)** direkt ueber dem Key (maschinenlesbar via `env-audit.py`); leerer Wert = Pflicht-Key, `[optional]`/`[required]` am Anfang der ersten `#:`-Zeile als Override. Konsistenz: `make env-audit` (`--strict` fuer CI); SoT-unbekannte Keys auskommentieren: `env-audit.py --comment-out` (Kurzform `-c`, mit `.env.bak-<timestamp>`-Backup, gitignored — kein eigenes Make-Target); fehlende SoT-Keys (Wert + `#:`-Doku) in die `.env` uebernehmen: `env-audit.py --fill` (Kurzform `-f`, haengt nur nicht vorhandene Keys an, ueberschreibt **nie** bestehende Werte, gleiches `.bak-<timestamp>`-Backup; `-c` + `-f` kombinierbar, teilen ein Backup). Details: [`docs/conventions.md`](docs/conventions.md).
- `make db-reset` nie auf dem Server
- `git status` nie im Root — immer `make status` (Sub-Repos sind gitignored und fuer Root unsichtbar)
- Keine `TODO`-Kommentare ohne zugehoeriges Issue
