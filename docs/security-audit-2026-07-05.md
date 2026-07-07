# Security-Audit — DecisionMap (2026-07-05)

> Vier parallele Audits (Backend, Frontend, AI-Service, Infrastructure/Root).
> Status-Legende: ☐ offen · ⚙️ in Arbeit · ✅ gefixt · ⏸️ zurückgestellt (braucht Entscheidung)

## PRIO 1 — Sicherheitslücken

### CRITICAL
- ✅ **SQLi über Semantik-Cursor** — `apps/backend/routers/problems.py:788–847` (`_embedding_to_str` `:751`).
  Client-kontrollierter `cursor.emb` wird ungevalidet via `repr()` inline in SQL (`('{emb_str}')::vector`) gesetzt.
  String-Element bricht aus dem Literal aus → unauth. SQLi.
  **Fix:** `emb` strikt als `list[float]` validieren (sonst `None`/Fallback); `_embedding_to_str` mit `float(x)` erzwingen.

### HIGH — Backend
- ✅ **Secret-Defaults + Startup nur Warnung** — `config.py:9,29`, `main.py:31–40`.
  `secret_key="dev-secret-key-change-in-production"`, `service_token="dev-service-token"` sind funktionsfähig; `_validate_settings` `print`t nur.
  **Fix:** Defaults `""`; `lifespan` hart `raise RuntimeError` bei leer/Dev-Wert (auch CORS `*`+credentials).
- ✅ **`DELETE /tags/{id}` + `create_tag` ohne Auth** — `apps/backend/routers/tags.py:42–75` (`current_optional_user`).
  **Fix:** `current_active_user`; Löschen auf Superuser beschränken (Tag hat keinen `author_id`).

### HIGH — AI-Service
- ✅ **Fail-open `SERVICE_TOKEN`** — `app/dependencies.py:84–97`, `config.py:20`. Kein Startup-Guard.
  **Fix (umgesetzt):** Startup-Guard im `lifespan` (`main.py`) bricht hart ab; leerer Token nur mit explizitem `ALLOW_INSECURE_DEV=true` (Dev-Opt-in).
- ✅ **Pfad-Injection über `problem_id`** — `app/routers/solutions.py:36` → `app/client/backend_client.py:51`.
  Unauth. `/generate-solution`, `problem_id` ungevalidet in URL, BackendClient hängt `X-Service-Token` an.
  **Fix (umgesetzt):** `problem_id` als `UUID` typisiert; `_seg()` (`urllib.parse.quote(..., safe="")`) auf allen Pfad-Segmenten im BackendClient.
- ✅ **Unauth. LLM-Endpoints ohne In-App-Rate-Limit** — `translate.py:25,48`, `solutions.py:24`.
  **Fix (umgesetzt):** `@limiter.limit` auf `/translate`, `/translate/candidates`, `/generate-solution`; `Field(min_length=1, max_length=5000)` auf `text`, `max_length=8` auf `target_lang`/`lang`.

### HIGH — Infrastructure
- ✅ **Postgres-Port öffentlich** — `infrastructure/docker-compose.yml:22–23` (`5432:5432`).
  **Fix (umgesetzt):** `127.0.0.1:5432:5432`.
- ✅ **App-Ports umgehen nginx** — `docker-compose.yml:60–61,89–90,103–104`.
  **Fix (umgesetzt):** `ports:` → `expose:` für backend/ai-service/frontend; nur nginx published `80/443`.
- ✅ **`/internal/*` extern erreichbar** — `host/etc/nginx/nginx.conf:48–69`.
  **Fix (umgesetzt):** `location /internal/ { return 404; }` (API-Block) + defensiv `location /api/internal/` (App-Block).

### HIGH — Frontend (architektonisch)
- ✅ **JWT im localStorage → HttpOnly-Cookie** (Subdomain-Cookie-Variante, Backend 190 + Frontend 148 Tests grün).
  Backend: `auth/backend.py` `BearerTransport`→`CookieTransport` (HttpOnly, `SameSite=Lax`, `cookie_domain`/`cookie_secure` konfigurierbar), `config.py` Cookie-Settings, `magic_link.py` setzt Cookie via `auth_backend.login` statt Token-Body. Frontend: `backendClient.ts` kein localStorage mehr + `credentials:'include'`, `realAuth.ts`/`middleware/admin.ts`/`layouts/default.vue`/`magic-verify.vue` umgebaut. Token ist damit für JS/XSS unlesbar. CSRF: `SameSite=Lax` blockt cross-site state-changing Requests (alle Mutationen sind fetch/XHR, keine Top-Level-GET-Navigation). **Struktur unangetastet:** `api.decisionmap.ai`/`backend.int.decisionmap.ai` bleiben, keine nginx-Restrukturierung, `int.` weiter lauffähig. E2E `storageState` erfasst das Cookie automatisch.
  **Deploy-Env nötig** (in `.env`, harness-gesperrt): Prod `COOKIE_DOMAIN=.decisionmap.ai` + `COOKIE_SECURE=true`; Dev-int `COOKIE_DOMAIN=.int.decisionmap.ai` + `COOKIE_SECURE=false`; localhost `COOKIE_DOMAIN=` (leer) + `COOKIE_SECURE=false`. Compose-Backend-Block reicht sie durch.

## PRIO 1 — MEDIUM

- ✅ **Attribution-Spoofing** (anon `user_id`/`ip_hash` aus Body) — `backend/routers/problems.py:1201`, `solutions.py:119`, `votes.py:26`.
  **Fix (umgesetzt):** anon → `user_id=None`; `user_id` aus `ProblemCreate`/`SolutionCreate`, `ip_hash` aus `VoteCreate` entfernt (server-seitig via `_ip_hash(request)`). Hinweis: `realProblems.ts:298` sendet noch ein (jetzt ignoriertes) `user_id` — Cleanup-Kandidat.
- ✅ **Prompt-Injection im Moderationsverdikt** — `ai-service/providers/llm/*_provider.py` (`is_spam`).
  **Fix (umgesetzt):** `wrap_user_content()` fenced Input in `<user_content>`-Tags (vorhandene Tags gestrippt) + Delimiter-Note in beiden Spam-System-Prompts; `reason` via `_cap_reason` auf 200 Zeichen gekappt.
- ⚙️ **WebSocket ohne Origin-Check** (AI-Service `routers/websocket.py:11–38`; Backend `routers/ws.py`).
  **Fix:** `Origin` gegen `cors_origins`; sonst `close(1008)`. **AI-Service auf Platte umgesetzt (`_origin_allowed`); Backend `routers/ws.py` noch offen.**
- ✅ **nginx Security-Header fehlen** — `nginx.conf` alle 443-Blöcke. HSTS/X-Frame/nosniff/Referrer-Policy. **Umgesetzt (beide 443-Blöcke).**
- ✅ **`server.sh env-local/env-server` cattet `.env`-Werte** — `infrastructure/scripts/server.sh:245–263`.
  **Fix (umgesetzt):** nur Keys (`grep -v '^#' | cut -d= -f1`), lokal + remote.
- ✅ **SSR-Prerender rendert Markdown ohne DOMPurify/Link-Hardening** — `frontend/utils/markdown.ts:29–37`.
  **Fix (umgesetzt):** `isomorphic-dompurify` — identische Allowlist + Link-Hardening-Hook server- (jsdom) und client-seitig; SSR-Raw-Bypass entfernt. Neue Unit-Tests `tests/utils/markdown.spec.ts`.
- ✅ **TLS nicht gehärtet** — `nginx.conf:54–55,78–79`. **Umgesetzt:** Mozilla-Intermediate-Ciphers, `ssl_prefer_server_ciphers off`, Session-Cache.

## PRIO 1 — LOW

- ✅ **Non-constant-time Token-Vergleich** — `backend/dependencies.py:27`, `ai-service/dependencies.py:93`.
  **Fix (umgesetzt):** Backend `secrets.compare_digest`; AI-Service `hmac.compare_digest`.
- ✅ **Fehlende Längenlimits Freitext** — `ProblemCreate`/`ProblemUpdate` (`title` 200, `description` 5000), `SolutionCreate.content` (20–2000).
- ✅ **Mass-Assignment `rejection_reason`** — aus `ProblemUpdate` + `scalar_fields` entfernt.
- ✅ **`v-html`+`replace`** — `frontend/pages/dev-tools.vue:129` → `<i18n-t>`-Slot-Interpolation, `v-html` entfernt.

## PRIO 2 — Deploy-Integrität / Code-Qualität

- ✅ **Prod-`docker-compose.yml` ist stale (Directus)** — auf FastAPI-Stack umgeschrieben (backend `expose: 8001`, `SECRET_KEY`/`SERVICE_TOKEN`/`DATABASE_URL`, `.local`-Default weg, ai-service ohne DB-/Directus-Vars, `directus_uploads`-Volume entfernt).
  **Vor Deploy verifizieren (ANNAHME im Compose-Kommentar):** Backend-Image bindet uvicorn auf `0.0.0.0:8001`, Health = `GET /health`.
- ✅ **`apps/backend/docker/Dockerfile:22`** — `FROM directus/directus:11`, Beispiel-`admin123`.
  **Fix (umgesetzt):** Two-Stage-`python:3.11-slim`-Image (non-root, `EXPOSE 8001`, `uvicorn main:app`) — siehe „Directus-Reste im Backend-Repo" unten.
- ✅ **`infrastructure/database/permissions.sql`** — gelöscht (samt `setup-vote-flow.sh`, `db-permissions`-Target/Command in Makefile + `server.sh`).
- ⚙️ **Command-Injection unquoted Remote-Args** — `server.sh:53,290`. `restore`-Dateiname via `printf %q` gequotet; generisches `remoteExec "$*"` unverändert.
- ☐ **Dev-Compose Secret-Defaults** — `apps/backend/docker-compose.dev.yml:68,72,18`.
- ☐ **ai-service Runtime installiert `mc`/`jq`** — `apps/ai-service/docker/Dockerfile:29–32`.
- ☐ **`embed_query`/`translate` nehmen `dict` statt Pydantic** — `ai-service/routers/embeddings.py:72`.
- ☐ **`build/lib/...` veralteter Router-Baum** — sicherstellen: nicht ins Image, `.dockerignore`.
- ✅ **Feature-Flags `REQUIRE_AUTH`/`SHOW_VOTING`** — nicht ergänzt, sondern als tote Config **entfernt** (2026-07-07): nie im Code gelesen (kein `Settings`-Feld, keine `runtimeConfig.public`-Exposition). Voting ist immer aktiv, Auth strukturell via fastapi-users + Route-Guards. Raus aus `infrastructure/.env.example`, `apps/backend/.env.example`, `docker-compose.yml`, docs.

## Fortschritt (Stand 2026-07-05, laufende Session)

### ✅ Erledigt — Backend (Fixer-Agent, 190 Tests grün)
- ✅ CRITICAL SQLi Semantik-Cursor: `emb` strikt als `list[float]` validiert, `_embedding_to_str` via `float(x)` gehärtet.
- ✅ Secret-Defaults `""` + `_validate_settings` wirft `RuntimeError` im `lifespan` (leer/Dev-Wert/CORS-`*`). Test-Fixture setzt explizite Test-Secrets.
- ✅ `DELETE /tags/{id}` + `create_tag`: `current_active_user`, Delete superuser-gated.
- ✅ Attribution-Spoofing: anon `user_id=None`; `user_id` aus Create-Schemas; `ip_hash` aus `VoteCreate` (server-seitig via `_ip_hash`).
- ✅ constant-time `secrets.compare_digest`; Freitext-`max_length`; `rejection_reason` aus `ProblemUpdate`.

### ✅ Erledigt — Frontend (Fixer-Agent, 148 Tests grün)
- ✅ SSR/Prerender-Markdown: `isomorphic-dompurify` → EIN Sanitize-Pfad (Allowlist + Link-Hardening) server- und clientseitig. Neuer Test `tests/utils/markdown.spec.ts`.
- ✅ `dev-tools.vue` `v-html`+`replace` → `<i18n-t>`-Interpolation.

### ✅ Erledigt — Infrastructure (selbst + Cleanup-Agent)
- ✅ nginx: Security-Header (HSTS/nosniff/X-Frame/Referrer-Policy), TLS gehärtet (ECDHE-Suite, session cache), `/internal/` + `/api/internal/` → 404.
- ✅ Ports: Postgres → `127.0.0.1:5432`, App-Services → `expose` (kein Host-Publish).
- ✅ `server.sh`: `env-local`/`env-server` nur Keys, `restore`-Arg via `printf %q`.
- ✅ Directus RESTLOS aus Infra entfernt: `docker-compose.yml` auf FastAPI-Stack (backend 8001, `SECRET_KEY`/`SERVICE_TOKEN`/`DATABASE_URL`, `.local`-Default weg, ai-service ohne DB-Vars), `setup-vote-flow.sh`/`permissions.sql`/nginx-`.bak` gelöscht, Makefile/`server.sh`/CLAUDE.md bereinigt, `alembic downgrade` auf `backend` korrigiert. Die `.env.example`-Bereinigung ist inzwischen erledigt (2026-07-06, siehe unten).

### ✅ Erledigt — AI-Service (Fixer-Agent)
- ✅ SERVICE_TOKEN-Startup-Guard (fail-closed, `ALLOW_INSECURE_DEV`-Opt-in), Pfad-Injection via `_seg()`/UUID, In-App-Rate-Limit auf LLM-Endpoints, Prompt-Injection-Delimiter (`wrap_user_content`), WS-Origin-Check (`_origin_allowed`).

### ✅ Erledigt — Directus-Restentfernung (alle Repos)
- ✅ Backend-`docker/Dockerfile` von `FROM directus/directus:11` auf Two-Stage-`python:3.11-slim` (non-root, `EXPOSE 8001`, uvicorn) umgeschrieben; `docker/build.sh` (backend + frontend), `.gitignore`, `000_schema.sql`-Kommentar bereinigt; Frontend-Docker `NUXT_PUBLIC_DIRECTUS_URL` → `NUXT_PUBLIC_BACKEND_URL`.
- ✅ Gelöscht: `scripts/seed-users.sh` (Directus-API-Seeding, keine Referenzen), Root `scripts/fix_dev_env.py` + `scripts/fix_remaining_docs.py`, Frontend `README.backup.md`.
- ⏸️ **`database/constraints.sql`:** Directus-Wording entfernt + Legacy-Hinweis gesetzt (Alembic ist Schema-Owner, Datei referenziert gedroppte `clusters`-Tabellen) — Datei + Makefile-Target `db-constraints` löschen, sobald bestätigt ist, dass kein Dev/Prod-Flow sie noch aufruft.

### ✅ Erledigt — Zweite Backend-Welle (Fixer-Agent, 190 Tests grün, unabhängig verifiziert)
- ✅ **BE-06 (HIGH):** `GET /problems/{id}` + `GET /solutions/{id}` — nicht-`approved` → 404 außer Superuser/Owner (`current_optional_user`-Guard).
- ✅ **BE-10 (MEDIUM):** Magic-Link setzt `is_verified=True` bei erfolgreicher Verifikation.
- ✅ **BE-09 (MEDIUM):** Cursor-Größenlimit `_MAX_CURSOR_LENGTH=65536` am `list_problems`-Entry → 422.
- ✅ **BE-12 (MEDIUM):** `services/moderation.py` `VALID_STATUSES` (SSoT) + `StatusBody`-`field_validator` + `rejection_reason` max_length=1000; `admin.py` nutzt dieselbe Menge.
- ✅ **BE-14/BE-13 (LOW):** `current_optional_user` `verified=True`; `version` aus öffentlichem `/health` entfernt.
- ⏸️ **BE-08 (MEDIUM):** bewusst NICHT umgesetzt — `/ws` ist ein einzelner unauth. Shared-Broadcast; Status-Filter würde Admin-/Moderations-Realtime brechen. Payloads tragen nur opake UUIDs + Status-Enum (nie Titel/Content/`rejection_reason`); Content selbst ist seit BE-06 404. Sauberer Fix = eigener auth. Admin-WS-Kanal (größerer Umbau, separat).
- ✅ **`.env.example` alle vier Repos neu geschrieben (2026-07-06):** Die Harness-Sperre wurde aufgelöst, indem `.claude/settings.local.json` die Deny-Regel auf echte Secrets verengt (`.env`, `.env.local`, `.env.*.local`, `.env.production/development/staging/test`) — `.env.example` ist les-/editierbar, `.env` bleibt gesperrt. Umgesetzt: infra komplett auf FastAPI-Stack (35 Keys, kein Directus mehr, `SECRET_KEY`/`MAIL_*`/`COOKIE_*`/`BACKEND_PUBLIC_URL`), backend (`POSTGRES_URL` raus, `COOKIE_*` rein), ai-service (`ALLOW_INSECURE_DEV` rein, totes `MIN_CLUSTER_SIZE` raus), frontend (`USE_FAKE_DATA` raus — Fake-Layer komplett entfernt, Frontend-Suite dadurch 147 Tests). `WEBHOOK_SECRET` (Directus-Legacy, nirgends im Code) aus dem Compose entfernt. Kommentare durchgängig above-line (siehe Konventionen). **Nur noch offen (manuell durch Mike):** lokale `.env`-Files an die neuen `.env.example` angleichen — Drift-Liste via `make env-audit`; SoT-unbekannte Keys automatisch via `env-audit.py --comment-out` (fehlende Pflicht-Keys bleiben manuell).
- ✅ **JWT localStorage → HttpOnly-Cookie: UMGESETZT** (Subdomain-Cookie). Details siehe „HIGH — Frontend" oben. Nur noch offen: `COOKIE_DOMAIN`/`COOKIE_SECURE` in den `.env`-Files setzen (harness-gesperrt, manuell).
- ✅ **`scripts/env-audit.py` auf SoT-Semantik umgeschrieben (2026-07-06, Lauf verifiziert):** prüft `.env` gegen `.env.example` (nicht mehr umgekehrt) — unbekannte Keys + fehlende Pflicht-Keys = Fehler (Exit 1), fehlende optionale Keys nur Info. Pflicht = leerer Wert, Override via `[optional]`/`[required]`; Key-Beschreibungen als Debian-Style `#:`-Zeilen im angrenzenden Block; `--strict` macht Warnungen (unbekannte Keys, Duplikate, verwaiste `#:`-Blöcke, fehlende Doku) CI-tauglich zu Fehlern. Der Verifikationslauf bestätigt den bekannten Drift (Legacy-Keys wie `POSTGRES_URL`/`USE_FAKE_DATA`/`MIN_CLUSTER_SIZE`/Directus-Reste in den lokalen `.env`, fehlende `COOKIE_*`/`SECRET_KEY`/`SERVICE_TOKEN`/`MAIL_*`). Alle vier `.env.example` sind auf `#:`-Beschreibungszeilen umgestellt (inkl. `[optional]`-Tags) — `make env-audit` läuft ohne Doku-Warnungen (verifiziert 2026-07-06). Konvention: [`docs/conventions.md`](conventions.md).
- ✅ **`env-audit.py --comment-out` (2026-07-06, an Fixture verifiziert):** kommentiert genau die der SoT unbekannten Keys in der `.env` aus (auskommentieren statt löschen — Wert bleibt reversibel), Backup `.env.bak-<timestamp>` vorher, `export`-Präfixe korrekt, gibt niemals Values aus. `.env.bak-*` in die `.gitignore` von backend/ai-service/infrastructure ergänzt (frontend via `.env.*` schon abgedeckt) — Backups enthalten Secrets, dürfen nie eingecheckt werden.
- ✅ **`infrastructure/.env.example` versioniert (2026-07-06):** Die `.gitignore`-Zeile, die `.env.example` selbst ignorierte, ist entfernt — die infra-SoT-Vorlage ist jetzt im Index (`git add`, noch nicht committed). Bestätigt als Fehler: Templates gehören ins Repo, `.env` bleibt ignoriert.

## Positiv verifiziert (kein Handlungsbedarf)
Ownership-Checks korrekt; Soft-Delete-Filter konsequent (auch `/internal/*`); `/internal/*` router-weit token-geschützt; Bind-Params in `internal.py`; Magic-Link gehasht+expiry+konstante Antwort; `ip_hash` SHA-256; Jinja autoescape; keine Secrets in getrackten Files; Open-Redirect-Guard korrekt; DOMPurify-Client-Config solide; Clipboard/Geo HTTP-Fallbacks; ai-service non-root; sudoers eng.
