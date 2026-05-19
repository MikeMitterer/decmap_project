#!/usr/bin/env python3
"""One-shot fixer: update dev-environment.md for Directus→FastAPI migration."""
import subprocess

path = "/Volumes/DevLocal/DevWeb/Production/DecisionMap/docs/dev-environment.md"
with open(path, "r") as f:
    content = f.read()

# 1. Fix "Mailpit läuft separat" note
content = content.replace(
    "Mailpit läuft separat (z.B. auf Unraid oder lokal) — nicht Teil von `make dev-up`.",
    "Mailpit und Adminer laufen im Backend-Docker-Compose — Teil von `make -C apps/backend dev-up`."
)

# 2. Fix .env section (Directus vars -> FastAPI vars)
old_env = (
    "**`apps/backend/.env`** (Directus):\n"
    "```env\n"
    "WEBSOCKETS_ENABLED=true                                    # Pflicht — sonst kein Live-Vote-Update\n"
    "WEBSOCKETS_REST_AUTH=public                                # Anonyme WS-Subscriptions erlauben\n"
    "PUBLIC_URL=http://cms.int.decisionmap.ai                   # Pflicht — Directus CORS + Auth-Mails\n"
    "CORS_ORIGIN=http://int.decisionmap.ai                      # Frontend-Origin erlauben\n"
    "USER_REGISTER_URL_ALLOW_LIST=http://int.decisionmap.ai/verify-email  # E-Mail-Verifizierungslink\n"
    "```"
)
new_env = (
    "**`apps/backend/.env`** (FastAPI):\n"
    "```env\n"
    "SECRET_KEY=                                # JWT-Signing-Key (openssl rand -hex 32)\n"
    "SERVICE_TOKEN=                             # X-Service-Token für interne AI-Service-Endpoints\n"
    "CORS_ORIGINS=http://int.decisionmap.ai     # Frontend-Origin (kommasepariert)\n"
    "BACKEND_URL=http://localhost:8001          # Für AI-Service-Konfiguration\n"
    "```"
)
content = content.replace(old_env, new_env)

# 3. Fix "Echter Directus + AI-Service"
content = content.replace(
    "USE_FAKE_DATA=false  # Echter Directus + AI-Service",
    "USE_FAKE_DATA=false  # Echter FastAPI-Backend + AI-Service"
)

# 4. Replace entire Echtzeit WS section
old_ws = (
    "### Zwei WebSocket-Quellen\n\n"
    "| Composable | WebSocket-Quelle | Verantwortlich für |\n"
    "|---|---|---|\n"
    "| `useDirectusRealtime.ts` | Directus WS (`/websocket`) | Vote-Score-Updates (`problems.vote_score`) |\n"
    "| `useRealtimeUpdates.ts` | AI-Service WS (`/ws`) | AI-Events: `problem.approved`, `cluster.updated`, `solution.generated` |\n"
    "\n"
    "### Vote-Score-Flow\n"
    "\n"
    "```\n"
    "User klickt Vote\n"
    "      ↓\n"
    "POST /items/votes  (Directus REST)\n"
    "      ↓\n"
    "GET /items/{collection}/{id}?fields=vote_score  (aktuellen Score laden)\n"
    "      ↓\n"
    "PATCH /items/{collection}/{id}  { vote_score: n+1 }  (via Directus REST)\n"
    "      ↓  (löst Directus WS-Event aus)\n"
    "Directus WebSocket → alle verbundenen Clients\n"
    "      ↓\n"
    "useDirectusRealtime.ts → applyProblemUpdate(update)\n"
    "      ↓\n"
    "UI aktualisiert sich live (kein Reload)\n"
    "```\n"
    "\n"
    "> **Kein PostgreSQL-Trigger:** `trg_vote_score` / `fn_update_vote_score()` wurden entfernt.\n"
    "> Der Score wird stattdessen per REST API berechnet und via `PATCH` geschrieben — Directus\n"
    "> löst dabei automatisch WS-Events aus. Voraussetzung: `update`-Permission auf `vote_score`\n"
    "> für die Public-Policy (`make -C apps/backend db-permissions`).\n"
    "\n"
    "**Sofort-Feedback für den votenden User:**\n"
    "Nach `submitVote()` ruft `handleVote()` in `ProblemPanel.vue` sofort `fetchProblemById()`\n"
    "auf — zeigt den echten DB-Wert ohne auf den WS-Event zu warten.\n"
    "\n"
    "### Kritische Voraussetzungen\n"
    "\n"
    "1. **`WEBSOCKETS_ENABLED=true`** in `apps/backend/.env`\n"
    "2. **`WEBSOCKETS_REST_AUTH=public`** in `apps/backend/.env`\n"
    "3. **`PUBLIC_URL=http://cms.int.decisionmap.ai`** in `apps/backend/.env` — Directus prüft die\n"
    "   Origin gegen PUBLIC_URL. Stimmt sie nicht überein, verwirft Directus die WS-Verbindung\n"
    "   nach ~3 s lautlos (Reconnect-Loop). Zusammen mit `CORS_ORIGIN=http://int.decisionmap.ai` setzen.\n"
    "4. **`connect()` explizit in `onMounted` aufrufen** — beide Composables verbinden sich\n"
    "   nicht automatisch. Fehlt der Call, bleibt der Socket stumm (kein Fehler, kein Event).\n"
    "5. **Directus Flow \"Vote Score Broadcast\"** muss angelegt sein:\n"
    "   ```bash\n"
    "   make -C infrastructure setup-vote-flow\n"
    "   # Neu anlegen (falls bereits vorhanden):\n"
    "   make -C infrastructure setup-vote-flow -- --force\n"
    "   ```"
)
new_ws = (
    "### Zwei WebSocket-Quellen\n\n"
    "| Composable | WebSocket-Quelle | Verantwortlich für |\n"
    "|---|---|---|\n"
    "| `useBackendRealtime.ts` | Backend WS (`ws://localhost:8001/ws`) | Mutations: Vote-Scores, Problem/Solution CRUD |\n"
    "| `useRealtimeUpdates.ts` | AI-Service WS (`/ws`) | AI-Events: `problem.approved`, `cluster.updated`, `solution.generated` |\n"
    "\n"
    "### Vote-Score-Flow\n"
    "\n"
    "```\n"
    "User klickt Vote\n"
    "      ↓\n"
    "POST /votes  (FastAPI Backend, Port 8001)\n"
    "      ↓\n"
    "Backend berechnet neuen vote_score (Toggle-Logik)\n"
    "      ↓\n"
    "Response enthält aktualisierten vote_score direkt — kein Re-Fetch nötig\n"
    "      ↓  (Backend feuert WS-Event)\n"
    "Backend WebSocket /ws → alle verbundenen Clients\n"
    "      ↓\n"
    "useBackendRealtime.ts → applyProblemUpdate(update)\n"
    "      ↓\n"
    "UI aktualisiert sich live (kein Reload)\n"
    "```\n"
    "\n"
    "**Vote-Toggle-Semantik:** Gleiche Richtung wie vorhandenes Vote → zurückziehen (delta = -1). "
    "Entgegengesetzte Richtung → Flip (delta = ±2). Neues Vote → delta = ±1.\n"
    "\n"
    "**Sofort-Feedback für den votenden User:**\n"
    "`ProblemPanel.vue` aktualisiert den Score direkt aus dem Response-Body — zeigt echten "
    "DB-Wert ohne auf den WS-Event zu warten.\n"
    "\n"
    "### Kritische Voraussetzungen\n"
    "\n"
    "1. **Backend läuft auf Port 8001** — WS-Endpoint: `ws://localhost:8001/ws`\n"
    "2. **`connect()` explizit in `onMounted` aufrufen** — beide Composables verbinden sich\n"
    "   nicht automatisch. Fehlt der Call, bleibt der Socket stumm (kein Fehler, kein Event)."
)
content = content.replace(old_ws, new_ws)

# 5. Fix nginx section
old_nginx = (
    "### nginx (Produktion)\n"
    "\n"
    "Für Directus WebSocket hinter nginx muss der `cms.decisionmap.ai`-Serverblock Upgrade-Headers weiterleiten:\n"
    "\n"
    "```nginx\n"
    "server {\n"
    "    server_name cms.decisionmap.ai;\n"
    "    location / {\n"
    "        proxy_pass http://directus:8055;\n"
    "        proxy_set_header Upgrade $http_upgrade;\n"
    "        proxy_set_header Connection \"upgrade\";\n"
    "        proxy_read_timeout 3600s;   # Pflicht — default 60s bricht WS-Verbindung bei Stille\n"
    "    }\n"
    "}\n"
    "```\n"
    "\n"
    "Ohne Upgrade-Header schlägt der WS-Handshake lautlos fehl.\n"
    "Ohne `proxy_read_timeout 3600s` wird die Verbindung nach 60 s Inaktivität getrennt —\n"
    "auch wenn Directus Pings schickt (Ping-Intervall kann > 60 s sein)."
)
new_nginx = (
    "### nginx (Produktion)\n"
    "\n"
    "Der `api.decisionmap.ai`-Serverblock muss WS-Upgrade-Headers weiterleiten:\n"
    "\n"
    "```nginx\n"
    "server {\n"
    "    server_name api.decisionmap.ai;\n"
    "    location / {\n"
    "        proxy_pass http://backend:8001;\n"
    "        proxy_set_header Upgrade $http_upgrade;\n"
    "        proxy_set_header Connection \"upgrade\";\n"
    "        proxy_read_timeout 3600s;   # Pflicht — default 60s bricht WS-Verbindung bei Stille\n"
    "    }\n"
    "}\n"
    "```\n"
    "\n"
    "Ohne Upgrade-Header schlägt der WS-Handshake lautlos fehl.\n"
    "Ohne `proxy_read_timeout 3600s` wird die Verbindung nach 60 s Inaktivität getrennt."
)
content = content.replace(old_nginx, new_nginx)

with open(path, "w") as f:
    f.write(content)

print("Done. Remaining Directus refs:")
result = subprocess.run(
    ["grep", "-in", "directus", path],
    capture_output=True, text=True
)
print(result.stdout or "(none)")
