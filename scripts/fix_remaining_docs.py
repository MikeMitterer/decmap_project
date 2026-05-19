#!/usr/bin/env python3
"""Fix remaining Directus references after Phase 8 migration."""
import re

ROOT = "/Volumes/DevLocal/DevWeb/Production/DecisionMap"

# ── conventions.md ───────────────────────────────────────────────────
conv_path = ROOT + "/docs/conventions.md"
with open(conv_path) as f:
    c = f.read()

# 1. Fix Jenkins env var name
c = c.replace(
    "Jenkins: Env-Variablen im Build-Job setzen (`DIRECTUS_URL`, `WS_URL`, `SIMILARITY_THRESHOLD`) —",
    "Jenkins: Env-Variablen im Build-Job setzen (`BACKEND_URL`, `WS_URL`, `SIMILARITY_THRESHOLD`) —",
)

# 2. Remove Konkreter Fund 3 (Directus error messages — old layer gone)
c = c.replace(
    "**Konkreter Fund 3:** `useLogin.ts` pruefte Directus-Fehlermeldungen nicht prazise genug —\n"
    "\"email already taken\" wurde nicht als `login.errorEmailTaken` erkannt (Directus liefert\n"
    "`\"Value for email has to be unique.\"`). Fix: `includes('unique')` ergaenzt. Ausserdem:\n"
    "Fallback zeigte immer `\"Something went wrong\"` statt der tatsaechlichen Directus-Meldung —\n"
    "jetzt wird `error.message` direkt angezeigt, generischer Fallback nur wenn kein Text vorhanden.\n",
    "**Konkreter Fund 3:** `useLogin.ts` — Backend-Fehlermeldungen: \"email already taken\" wurde "
    "nicht als `login.errorEmailTaken` erkannt. Fix: `includes('unique')` ergaenzt; "
    "`error.message` wird direkt angezeigt, generischer Fallback nur wenn kein Text vorhanden.\n",
)

# 3. Remove Konkreter Fund 4 (Directus 302 redirect — FastAPI returns 204)
c = c.replace(
    "**Konkreter Fund 4:** `useLogin.ts` (`verify-email`-Pfad) — Directus gibt **302** zurueck, nicht 200.\n"
    "`fetch` ohne `redirect: 'manual'` folgt dem Redirect, bekommt HTML und wirft einen Parse-Fehler.\n"
    "Fix: `fetch(url, { redirect: 'manual' })` + `response.ok || response.type === 'opaqueredirect'` als Erfolg-Check.\n"
    "I18n-Fallout: `login.loading` existierte nicht — Composable nutzt jetzt `login.verifying`.\n",
    "**Konkreter Fund 4:** `useLogin.ts` (`verify-email`-Pfad) — "
    "FastAPI gibt **204** (No Content) zurueck. "
    "I18n-Fallout: `login.loading` existierte nicht — Composable nutzt jetzt `login.verifying`.\n",
)

# 4. Remove Konkreter Fund 6 (fully Directus-specific M2M naming)
c = c.replace(
    "**Konkreter Fund 6:** `realProblems.ts` — Directus M2M Virtual-Field-Naming.\n"
    "`PROBLEM_FIELDS` und `DirectusProblem`-Interface verwendeten `problem_tag.tag_id` / `problem_region.region_id`,\n"
    "aber Directus benennt M2M-Aliasfelder nach `one_field` in der Relation-Definition (`tags`, `regions`).\n"
    "Fix: `problem_tag` → `tags`, `problem_region` → `regions` in Fields-Liste und Interface;\n"
    "`mapProblem` nutzt `raw.tags ?? []` / `raw.regions ?? []` (defensiver Null-Guard).\n"
    "Gleichzeitig: `tags.deleted_by` fehlte im Directus-Schema (selbes Muster wie `deleted_at`) — via REST hinzugefuegt und `schema.json` aktualisiert.\n",
    "",
)

# 5. Remove Konkreter Fund 7 (fully Directus 11 specific)
c = c.replace(
    "**Konkreter Fund 7:** `realAuth.ts` — Directus 11 `admin_access` auf Policy, nicht Role.\n"
    "`role.admin_access` liefert immer `undefined` in Directus 11 (Feld auf `directus_roles` entfernt).\n"
    "Korrekt: `role.policies.policy.admin_access` abfragen — `USER_FIELDS` um `\"role.policies.policy.admin_access\"` ergaenzt, `mapUser` prueft `raw.role?.policies?.some(p => p.policy?.admin_access)`.\n"
    "Gleichzeitig: `date_created` existiert nicht auf `directus_users` in Directus 11 — `createdAt` nutzt `''`-Fallback. `display_name` / `company` sind Custom-Felder die `seed-users.sh` anlegt; fehlen sie, ist das Profil leer ohne Fehler.\n",
    "",
)

with open(conv_path, "w") as f:
    f.write(c)

remaining = [l for l in c.splitlines() if "directus" in l.lower() or "Directus" in l]
print(f"conventions.md: {len(remaining)} remaining Directus lines:")
for l in remaining:
    print(" ", l.strip()[:100])

# ── data-model.md ────────────────────────────────────────────────────
dm_path = ROOT + "/docs/data-model.md"
with open(dm_path) as f:
    d = f.read()

# 1. Fix junction table PK comments
d = d.replace(
    "id                  uuid (PK, uuid_generate_v4())  — Directus benoetigt Single-Column-PK fuer M2M",
    "id                  uuid (PK, uuid_generate_v4())",
)

# 2. Rewrite the stale Alembic section
d = d.replace(
    "Alembic verwaltet **Schema-Aenderungen** nach dem initialen Setup.\n"
    "Der initiale Zustand gehoert Directus (`schema.json`) — Alembic greift erst danach.\n"
    "\n"
    "```\n"
    "database/init/000_schema.sql  → nur PostgreSQL-Extensions (uuid-ossp, vector)\n"
    "directus/schema.json          → Tabellen + Directus-Metadaten (single source of truth)\n"
    "database/constraints.sql      → vector(1536), CHECK-Constraints, custom Indizes\n"
    "```\n"
    "\n"
    "Directus-System-Tabellen sind ausgenommen — die verwaltet Directus selbst.",
    "Alembic verwaltet das gesamte Schema — vom initialen Setup bis zu allen Migrationen.\n"
    "\n"
    "```\n"
    "database/init/000_schema.sql     → nur PostgreSQL-Extensions (uuid-ossp, vector)\n"
    "alembic/versions/001_initial.py  → initiale Tabellen (Alembic baseline)\n"
    "alembic/versions/00N_*.py        → inkrementelle Schema-Aenderungen\n"
    "database/constraints.sql         → vector(1536), CHECK-Constraints, custom Indizes\n"
    "```",
)

with open(dm_path, "w") as f:
    f.write(d)

remaining_dm = [l for l in d.splitlines() if "directus" in l.lower()]
print(f"\ndata-model.md: {len(remaining_dm)} remaining Directus lines:")
for l in remaining_dm:
    print(" ", l.strip()[:100])

# ── ses-setup.md ─────────────────────────────────────────────────────
ses_path = ROOT + "/docs/ses-setup.md"
with open(ses_path) as f:
    s = f.read()

# Update intro line
s = s.replace(
    "Production Access → Directus-Konfiguration → Systemtest.",
    "Production Access → Backend-Konfiguration → Systemtest.",
)

# Update Phase 7 heading
s = s.replace(
    "## Phase 7 — Test via Script (ohne Directus)\n\n"
    "Verbindung und Versand direkt testen — kein Directus, kein Docker nötig.",
    "## Phase 7 — Test via Script\n\n"
    "Verbindung und Versand direkt testen — kein Docker nötig.",
)

# Update Phase 9 heading and content
s = s.replace(
    "## Phase 9 — Directus konfigurieren (Hetzner-Server)",
    "## Phase 9 — Backend konfigurieren (Hetzner-Server)",
)

# Update Directus restart section
s = s.replace(
    "### Directus neu starten",
    "### Backend neu starten",
)

# Update SMTP healthcheck gotcha (Directus is gone, note applies to FastAPI now)
s = s.replace(
    "> Ist der Host gesetzt aber nicht erreichbar, wartet Directus beim Start **60 Sekunden**\n"
    "> auf eine SMTP-Verbindung → Container wird `unhealthy` → alle anderen Services blockiert.\n",
    "> Ist der Host gesetzt aber nicht erreichbar, kann der Backend-Container beim Start verzögert starten.\n",
)

# Remove Directus test-mail-button note
s = s.replace(
    "> **Hinweis:** Directus 11 hat den \"Test-Mail senden\"-Button in `Settings → Email` entfernt.\n"
    "> SMTP-Verifikation ausschließlich über `scripts/smtp-test.py` oder den Passwort-Reset-Flow.",
    "> SMTP-Verifikation über `scripts/smtp-test.py` oder den Passwort-Reset-Flow.",
)

# Remove Directus Admin Email reference row from table
s = s.replace(
    "| Directus Admin Email | [cms.decisionmap.ai/admin/settings/email](https://cms.decisionmap.ai/admin/settings/email) |\n",
    "",
)

# TOC update
s = s.replace(
    "- [Phase 7 — Test via Script](#phase-7--test-via-script-ohne-directus)",
    "- [Phase 7 — Test via Script](#phase-7--test-via-script)",
)
s = s.replace(
    "- [Phase 9 — Directus konfigurieren](#phase-9--directus-konfigurieren-hetzner-server)",
    "- [Phase 9 — Backend konfigurieren](#phase-9--backend-konfigurieren-hetzner-server)",
)

with open(ses_path, "w") as f:
    f.write(s)

remaining_ses = [l for l in s.splitlines() if "directus" in l.lower()]
print(f"\nses-setup.md: {len(remaining_ses)} remaining Directus lines:")
for l in remaining_ses:
    print(" ", l.strip()[:100])
