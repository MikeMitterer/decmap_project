# Infrastructure und Operations

## Inhalt

- [Umgebungsvariablen](#umgebungsvariablen)
- [Feature Flags](#feature-flags)
- [Directus-Einrichtung](#directus-einrichtung)
- [Datenfluss](#datenfluss)
- [Code-Formatierung und Linting](#code-formatierung-und-linting)
- [CI/CD — Jenkins Pipeline](#cicd--jenkins-pipeline)
- [Makefile-Struktur](#makefile-struktur)
- [Versionierung](#versionierung)
- [Git-Konventionen](#git-konventionen)
- [Seed-Daten](#seed-daten)
- [Backup](#backup)

---

## Umgebungsvariablen

Nie hardcoden. Immer aus der Umgebung lesen. Alle in `.env.example` dokumentiert.

### Build-Maschine (Jenkins-Agent / Entwickler-Workstation)

Diese Variablen gehoeren nicht in `.env.example` — sie werden einmalig in der Shell-Umgebung gesetzt.

| Variable | Zeigt auf | Benoetigt von |
|---|---|---|
| `DEV_LOCAL` | Lokales Dev-Verzeichnis (z.B. `/Volumes/DevLocal`) | `make setup` — erstellt `.libs/`-Symlinks |
| `DEV_MAKE` | `MakeLib`-Verzeichnis | Root-`Makefile` + `.templates/Makefile` — `include ${DEV_MAKE}/colours.mk`, `tools.mk` |
| `DEV_DOCKER` | Docker-Hilfsskripte | `.templates/docker/build.sh` — Build + Push |
| `BASH_LIBS` | Bash-Bibliotheken (`*.lib.sh`) | `.templates/docker/build.sh` — sourced via `. ${BASH_LIBS}/build.lib.sh` usw. |
| `BASH_TOOLS` | Bash-Tools (`local2Server.sh` usw.) | `.templates/Makefile` — `lh2server`/`update`-Targets |

### Applikation (`.env` / Runtime)

```
# Frontend
USE_FAKE_DATA=true             # true = in-memory Fake-Daten, false = echter Server
WS_URL=ws://localhost:8000     # WebSocket-URL des FastAPI-Service
SHOW_VOTING=false              # Feature Flag: Voting-Visualisierung aktivieren
REQUIRE_AUTH=false             # Feature Flag: Login fuer Einreichungen erzwingen
AUTO_APPROVE=false             # Feature Flag: Neue Problems automatisch freischalten (ohne Moderations-Review)

# Directus
DIRECTUS_URL=                  # Directus-Instanz URL
DIRECTUS_TOKEN=                # Directus Admin-Token
CORS_ORIGIN=http://localhost:3000  # Erlaubter Browser-Origin fuer Directus (nicht Wildcard — browser-invalid mit credentials)
WEBSOCKETS_ENABLED=true        # Pflicht fuer useDirectusRealtime.ts (Vote-Score-Updates via WS Subscription)
WEBSOCKETS_REST_AUTH=public    # Anonyme WS-Subscriptions erlauben (vote_score ist oeffentlich lesbar)

# Datenbank
POSTGRES_URL=                  # PostgreSQL Connection String (ai-service)

# AI-Service — Provider
EMBEDDING_PROVIDER=openai      # openai | (ollama — noch nicht implementiert)
LLM_PROVIDER=openai            # openai | anthropic
OPENAI_API_KEY=                # OpenAI API-Key fuer Embeddings + LLM-Calls
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
OPENAI_LLM_MODEL=gpt-4o-mini
ANTHROPIC_API_KEY=             # Nur benoetigt wenn LLM_PROVIDER=anthropic
ANTHROPIC_MODEL=claude-haiku-4-5-20251001

# AI-Service — Konfiguration
CLUSTERING_INTERVAL=360        # Batch-Clustering-Intervall in Minuten
SIMILARITY_THRESHOLD=0.85      # Schwellenwert fuer Aehnlichkeitserkennung (0.0–1.0)
DUPLICATE_THRESHOLD=0.92       # Schwellenwert fuer Duplikat-Erkennung
BOT_SUBMIT_MIN_SECONDS=10      # Mindestzeit zwischen Seitenaufruf und Submit
BOT_SESSION_MAX_HOURLY=10      # Max. Submissions pro Session pro Stunde
BOT_IP_MAX_SESSIONS=5          # Max. verschiedene Sessions pro ip_hash
WEBHOOK_SECRET=                # Shared Secret fuer Directus Flows (X-Webhook-Secret Header); leer = Dev-Mode
CORS_ORIGINS=["http://localhost:3000"]  # JSON-Array erlaubter Browser-Origins
```

## Feature Flags

| Flag | Standard | Beschreibung |
|---|---|---|
| `SHOW_VOTING` | `false` | Vote-Scores in der Graph-Visualisierung anzeigen |
| `REQUIRE_AUTH` | `false` | Login fuer Einreichungen erzwingen |
| `AUTO_APPROVE` | `false` | Neue Problems automatisch freischalten (ohne Moderations-Review) |

**Hinweis:** Frontend-Feature-Flags (`SHOW_VOTING`, `REQUIRE_AUTH`, `AUTO_APPROVE`) werden zur Build-Zeit in das Nuxt-Bundle eingebettet (`runtimeConfig.public.*`). Eine Änderung in `.env` auf dem Server greift erst nach einem Rebuild + Redeploy des Frontend-Images:
```bash
# apps/frontend
make build
# infrastructure
make deploy-service SVC=frontend
```

[↑ Inhalt](#inhalt)

---

## Directus-Einrichtung

**Frische Dev-Umgebung:** Ein Befehl richtet alles ein:

```bash
make db-reset   # down -v → up → schema apply → constraints → seed
```

**Verantwortlichkeiten:**

```
database/init/000_schema.sql  → nur PostgreSQL-Extensions (uuid-ossp, vector)
directus/schema.json          → Tabellen + Directus-Metadaten (single source of truth)
database/constraints.sql      → was Directus nicht kann: vector(1536), CHECK-Constraints,
                                 UNIQUE-Constraints (Junction-Tabellen), custom Indizes
```

**Junction-Tabellen** (`problem_cluster`, `problem_tag`, `problem_region`) haben eine
`id UUID PRIMARY KEY` + `UNIQUE(problem_id, ...)` — Directus benoetigt eine Single-Column-PK
fuer M2M-Relationen. M2M-Relationen und Alias-Felder sind in `schema.json` enthalten.

**Was NICHT im Snapshot enthalten ist:**
- `vector(1536)` Spalten (`embedding`, `centroid`) — werden von `db-constraints` + AI-Service via psycopg3 verwaltet
- Directus Flows — muessen einmalig manuell angelegt werden (siehe unten)

**Einzelne Schritte (bei Bedarf):**
```bash
make directus-schema-apply   # Tabellen + Metadaten via schema.json
make db-constraints          # vector-Spalten, Constraints, Junction-Tables, Indizes
make db-seed                 # Seed-Daten
make seed-users              # Test-User + Rolle + Policy in Directus
make db-permissions          # Public-Policy (Anon-READ) + User-Policy (CREATE/UPDATE/DELETE) anlegen
```

**Gotcha — schema apply nach Alembic-Migration:**
Wenn Alembic zuerst laeuft und dabei Directus-Tabellen anlegt, hinterlaesst es verwaiste `directus_*` Metadata-Eintraege. Ein anschliessendes `make directus-schema-apply` schlaegt dann mit Konflikt-Fehler fehl. Loesung: verwaiste `directus_*` Metadata-Eintraege aus den betroffenen Tabellen loeschen, dann erneut `make directus-schema-apply`.

**Gotcha — Direktus Benutzer-Registrierung:**
`USERS_REGISTER_ALLOW_PUBLIC: "true"` muss im Directus-Container gesetzt sein (docker-compose.yml), damit der `/users/register`-Endpunkt fuer anonyme Requests freigegeben ist. Ohne diesen Flag liefert Directus 403 — auch wenn alle anderen Permissions korrekt konfiguriert sind.
`make seed-users` setzt `public_registration: true` automatisch via `PATCH /settings` — kein manueller UI-Schritt noetig. `make db-reset` ruft `seed-users` mit auf.

**Gotcha — E-Mail-Verifizierung:**
E-Mail-Verifizierung und Auto-Login nach Register sind inkompatibel: Directus schickt nach `/users/register` eine Verifizierungsmail — ein unmittelbarer Login-Versuch schlaegt fehl, weil der Account noch unverifiziert ist.
`make seed-users` setzt `public_registration_verify_email: true` — in allen Umgebungen aktiv. Dev nutzt Mailpit als SMTP-Sink. Auto-Login nach Register entfaellt komplett; stattdessen zeigt das Frontend eine "Check your email"-Box (`registrationSent`-Flag in `login.vue`). User klickt Verifizierungslink → dann erst einloggen.
Directus 11: `/users/verify-email?token=XXX` ist ein reiner API-Endpunkt — nach erfolgreichem Verify erfolgt ein Redirect auf `PUBLIC_URL`. Der Token wird beim ersten Aufruf verbraucht; ein zweiter Klick liefert "Invalid verification code". `PUBLIC_URL` in der Directus-Konfiguration auf `http://localhost:3000/login` (Dev) bzw. die Produktions-URL setzen, damit der Browser nach der Verifizierung direkt zum Login weitergeleitet wird.
Frontend-seitig: `/verify-email.vue` ruft `GET /users/register/verify-email?token=XXX` an Directus auf und leitet bei Erfolg auf `/login?verified=true` weiter. Die Login-Seite zeigt dort ein gruenes Banner "Email verified — you can now sign in."
Directus antwortet auf den Verify-Endpunkt mit **302** (nicht 200) — fetch muss daher mit `redirect: 'manual'` aufgerufen werden, sonst folgt es dem Redirect, bekommt HTML statt JSON und die Fehlerbehandlung schlaegt fehl. Status-Check: `response.ok || response.type === 'opaqueredirect'` (2xx + Redirect = Erfolg).

**Security:** `USER_REGISTER_URL_ALLOW_LIST` im Directus-Container setzen (kommagetrennte erlaubte URL-Prefixes, z.B. `http://localhost:3000,https://decisionmap.example.com`). Ohne diesen Guard akzeptiert Directus jede beliebige `verification_url` im Register-Request — Phishing-Vektor. Directus prueft nur, ob die URL mit einem der erlaubten Prefixes beginnt.

**SMTP-Konfiguration testen (Directus 11):** Directus 11 hat keinen Mail-Test-Button mehr im UI — Konfiguration nur per Env-Variablen, Testen per API:
```bash
curl -X POST https://cms.decisionmap.ai/utils/mail/test \
  -H "Authorization: Bearer <DIRECTUS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"to": "test@example.com"}'
```
Antwort: `{}` bei Erfolg, Fehlerobjekt mit SMTP-Details bei Fehler.

Alternativ als E2E-Test (kein Token nötig) — triggert die echte Reset-Mail-Pipeline:
```bash
curl -X POST https://cms.decisionmap.ai/auth/password/request \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com"}'
```
Antwort ist immer leer (`204`) — Mail kommt an wenn SMTP korrekt konfiguriert ist.

**Gotcha — Hetzner blockiert SMTP-Port 587:**
Hetzner VPS blockiert ausgehende SMTP-Verbindungen auf Port 587 (STARTTLS) standardmäßig. Test: `nc -zv in-v3.mailjet.com 587` — Timeout bedeutet blockiert. Lösung: Port 465 (TLS) verwenden:
```
EMAIL_SMTP_PORT=465
EMAIL_SMTP_SECURE=true
```
Port 465 ist auf Hetzner in der Regel offen. Falls nicht: Hetzner Cloud Firewall im Panel prüfen (Firewalls → Outbound Rules, Port 465/587 freischalten) — die externe Cloud Firewall überschreibt `ufw`. Alternativ: Hetzner-Support (Port-Freischaltung beantragen) oder Mailjet HTTP-API statt SMTP verwenden.

**Gotcha — Mailjet "Relay access denied":**
SMTP-Verbindung klappt (Port 465 offen), aber Mailjet lehnt den Versand ab: `535 Relay access denied`. Ursachen:
1. **Falsche Credentials:** `EMAIL_SMTP_USER` = Mailjet API Key, `EMAIL_SMTP_PASSWORD` = Mailjet Secret Key (nicht Passwort des Mailjet-Accounts).
2. **Unbekannte Sender-Domain:** `EMAIL_FROM=noreply@decisionmap.ai` — die Domain muss in Mailjet als verifizierte Sender-Domain eingetragen sein (Mailjet Dashboard → Sender domains & addresses).
3. **Fehlender SPF-Record:** Mailjet prüft ob der sendende Server in der SPF-Policy der Domain autorisiert ist. DNS TXT-Record für `decisionmap.ai` muss `include:spf.mailjet.com` enthalten. Es darf nur **einen** SPF-Record pro Domain geben — bestehende Einträge ergänzen, nicht ersetzen. Beispiel (inkl. typischer `+a +mx` Einträge): `v=spf1 +a +mx include:spf.mailjet.com ~all`. Vorhandenes `?all` (neutral) durch `~all` (SoftFail) ersetzen — bessere Zustellbarkeit. Änderungen im DNS können bis zu 30 Minuten propagieren.
```
EMAIL_SMTP_USER=<Mailjet API Key>
EMAIL_SMTP_PASSWORD=<Mailjet Secret Key>
EMAIL_FROM=noreply@decisionmap.ai
```
4. **Mailjet Trial-Account:** Im Trial-Modus kann Mailjet nur an verifizierte Test-Empfänger senden. Mailjet Dashboard → **Account → My Plan** prüfen. Falls "Trial" steht: Account aktivieren/upgraden oder Test-Empfänger in Mailjet whitelisten (Senders & Domains → Test Recipients).

**Gotcha — Directus SMTP-Healthcheck blockiert Container-Start:**
Directus prüft im `/server/health`-Endpunkt die SMTP-Verbindung. Ist `EMAIL_SMTP_HOST` gesetzt aber nicht erreichbar, wartet Directus bis zu 60 Sekunden auf Timeout — Docker markiert den Container inzwischen als `unhealthy`. Lösung: `EMAIL_SMTP_HOST=` (leer) setzen, solange SMTP nicht benötigt wird, dann Container neu starten:
```bash
# In /srv/decisionmap/.env
EMAIL_SMTP_HOST=
```
```bash
docker compose up -d --no-deps --force-recreate backend
```

Tipp: `GET /server/ping` antwortet sofort mit `{"data":"pong"}` — unabhängig von SMTP. Eignet sich für einfache Verfügbarkeitsprüfungen ohne den SMTP-Timeout-Pfad.

**SMTP-Provider — Wechsel:** Mailjet (unzuverlässig) → smtp2go evaluiert → **AWS SES** gewählt (vollständige Einrichtungsanleitung: [`docs/ses-setup.md`](ses-setup.md)).
Bis zur Konfiguration: `EMAIL_SMTP_HOST=` (leer) — sonst 60s-Timeout bei Container-Start.
Tracking: MikeMitterer/decmap_project#1.

**SMTP-Provider — AWS SES (Produktion):**
AWS SES skaliert besser als smtp2go für Produktion. Konfiguration:
```
EMAIL_SMTP_HOST=email-smtp.<region>.amazonaws.com
EMAIL_SMTP_PORT=587
EMAIL_SMTP_USER=<IAM-SMTP-Credentials-User>
EMAIL_SMTP_PASSWORD=<IAM-SMTP-Credentials-Secret>
EMAIL_SMTP_SECURE=false
EMAIL_FROM=noreply@decisionmap.ai
```
SMTP-Credentials in der AWS Console erstellen: SES → "Create SMTP credentials" → IAM-User mit `ses:SendRawEmail`. Sandbox-Modus initial aktiv — nur verifizierte Empfänger erreichbar bis Production-Access beantragt.

SMTP-Verbindung testen: `./scripts/smtp-test.py --send --to dein@email.com` (liest `apps/backend/.env` automatisch).

**Gotcha — Hetzner blockiert ggf. Port 587:** Mit Mailjet wurde beobachtet, dass Hetzner VPS ausgehende Verbindungen auf Port 587 blockiert. AWS SES unterstützt auch Port 465 (TLS) als Fallback: `EMAIL_SMTP_PORT=465`, `EMAIL_SMTP_SECURE=true`. Vor Go-Live testen: `./scripts/smtp-test.py` oder `nc -zv email-smtp.<region>.amazonaws.com 587`.

**Gotcha — Hetzner DNS + SES DKIM CNAME:**
SES DKIM-Einrichtung erzeugt CNAME-Records die auf externe Hostnamen zeigen (`xxxxx.dkim.amazonses.com`). Hetzner Robot (alte Oberfläche) lehnt externe CNAME-Ziele mit Validierungsfehler ab. Lösung: DNS-Einträge in `dns.hetzner.com` (neues Interface) anlegen — dort funktionieren externe CNAME-Ziele problemlos. Hetzners Validierungswarnung ist übereifrig — die Records werden trotzdem korrekt an AWS übermittelt.

Wenn `dns.hetzner.com` ebenfalls blockiert: DNS auf Route 53 oder Cloudflare delegieren — beide Anbieter akzeptieren externe CNAME-Ziele ohne Einschränkungen. AWS Route 53 bietet zudem "Easy DKIM" mit automatischem Record-Setup direkt aus der SES-Console.

**Hinweis:** AWS hat TXT-basierte Domain-Verifizierung 2024 abgeschafft — nur noch DKIM-CNAMEs werden unterstützt.

**Gotcha — Directus Permissions nie per direktem SQL setzen:**
`INSERT INTO directus_permissions ...` umgeht den Directus-In-Memory-Cache. Permissions greifen dann erst nach einem Neustart — ohne sichtbare Fehlermeldung erscheint trotzdem 403. Permissions immer ueber die Directus REST API setzen (`PATCH /policies/{id}` oder `POST /permissions`). `make db-permissions` und `make seed-users` verwenden ausschliesslich REST-Aufrufe.

**Gotcha — Alembic-Spalten fehlen im Directus-Schema:**
Spalten die Alembic anlegt (z.B. `deleted_at`, `deleted_by` auf `tags`), sind Directus nicht bekannt, solange sie nicht explizit in `schema.json` definiert oder via Directus API hinzugefuegt werden. Fehlt die Definition, lehnt Directus Filter auf diese Spalte (z.B. `filter[deleted_at][_null]=true`) mit einem Validierungsfehler ab. Fix: Feld via `POST /fields/{collection}` hinzufuegen und `schema.json` aktualisieren, damit es bei `make directus-schema-apply` reproduzierbar ist. Gilt fuer alle Alembic-Spalten — nicht nur `deleted_at`, sondern auch `deleted_by` und andere Audit-Felder.

**Gotcha — Directus M2M Virtual-Field-Naming:**
Directus benennt M2M-Aliasfelder auf der "One"-Seite nach dem `one_field`-Wert in der Relation-Definition — nicht nach dem Junction-Table-Namen. Beispiel: die Relation `problems` → `problem_tag` → `tags` heisst im `readItems`-Ergebnis `tags` (nicht `problem_tag`), weil `one_field: "tags"` gesetzt ist. Ebenso `regions` statt `problem_region`. In `PROBLEM_FIELDS` und `DirectusProblem`-Interface deshalb `tags.tag_id` (nicht `problem_tag.tag_id`) und `regions.region_id` (nicht `problem_region.region_id`) verwenden. Defensiver Null-Guard im Mapper: `raw.tags ?? []` statt direktem Zugriff.

**Gotcha — Directus 11 Nullable-FK-Validierungsbug:**
Directus 11 validiert nullable Foreign-Key-Felder (z.B. `tags.parent_id`, `problems.deleted_by`, `solution_approaches.deleted_by`) zur Laufzeit gegen seine eigene Relation-Metadata — auch wenn PostgreSQL `NULL` erlaubt. Ein `PATCH`-Request mit `null` auf einem solchen Feld schlaegt mit einem Validierungsfehler fehl, obwohl die DB die `NULL`-Schreibung akzeptieren wuerde. Fix: die Directus-Relation-Metadata fuer diese Felder ueber die REST API entfernen (`DELETE /relations/{collection}/{field}`). Die PostgreSQL-FK-Constraint bleibt erhalten — nur Directus prueft nicht mehr. `make db-permissions` / `make seed-users` enthalten diesen Fix idempotent. Symptom: `PATCH` auf Item mit Soft-Delete oder selbst-referenzierendem Parent schlaegt mit 400 fehl.

**Gotcha — Directus M2M PATCH — Junction-Record-`id` Pflicht:**
Beim PATCH einer M2M-Relation (z.B. `problem_tags`, `problem_regions`) unterscheidet Directus anhand der `id` im Junction-Objekt:
- Junction-Record **mit** `id` → UPDATE (existierender Eintrag bleibt erhalten)
- Junction-Record **ohne** `id` → INSERT (neuer Eintrag wird angelegt)

Werden alle Tags ohne `id` geschickt (z.B. `[{tag_id: "uuid1"}, ...]`), versucht Directus fuer jeden Tag einen neuen Junction-Row einzufuegen → Unique-Constraint `(problem_id, tag_id)` schlaegt fehl.

**Fix A (include `id`):** Vor dem PATCH existierende Junction-Records laden (`GET /items/problem_tag?filter[problem_id][_eq]=<id>&fields=id,tag_id`), per `tag_id` mappen und die Junction-`id` fuer bereits vorhandene Eintraege mitschicken. Neue Tags bekommen keine `id` → Directus legt sie an. Fehlende Tags → Directus loescht sie.

**Fix B (explicit DELETE + POST) — bevorzugt in `realProblems.ts`:** Scalar-Felder und M2M-Relationen trennen.
1. `PATCH /items/problems/{id}` — nur Scalar-Felder (kein `tags`/`regions` im Body)
2. `DELETE /items/problem_tag?filter[problem_id][_eq]=<id>` — alle bestehenden Junction-Records loeschen
3. `POST /items/problem_tag` — neue Records mit explizitem `problem_id` anlegen
4. Dasselbe fuer `problem_region`
5. Re-fetch via `fetchProblemById()` — damit `tagIds` im Rueckgabewert die frisch angelegten Records widerspiegelt

Fix B ist expliziter und funktioniert unabhaengig davon wie Directus M2M intern verarbeitet.

**Gotcha — Directus Filter-Queries in curl / Shell-Scripts:**
Directus-Filterpfade enthalten eckige Klammern (`filter[field][_eq]=value`). curl interpretiert diese als URL-Bereich und schlaegt mit "URL rejected" fehl. Loesung: `--get --data-urlencode` verwenden oder die gesamte URL in Anfuehrungszeichen setzen und die Klammern mit `%5B`/`%5D` encoden. Beides gilt auch fuer `filter[_and][]`-Arrays.

**Gotcha — Directus User-Rollen und Permissions (Directus 11):**
Neu registrierte User erhalten automatisch die Rolle "User" (`app_access: false`) — sie koennen sich nicht im Directus-Admin-Backend einloggen. Nur der Admin-User hat `admin_access: true`.
Directus 11: Permissions sind nicht direkt an Rollen geknuepft, sondern an **Policy-Objekte** (`directus_policies`), die dann der Rolle (oder direkt dem Public-Access) zugewiesen werden. `make seed-users` legt Role + Policy idempotent an; `make db-permissions` richtet Public- und User-Policy ein.

Permission-Matrix:

| Rolle | READ | CREATE/UPDATE | DELETE |
|---|---|---|---|
| **Public (anonym)** | `problems`, `solution_approaches`, `clusters`, `tags`, `regions`, `problem_cluster`, `problem_tag`, `problem_region` | — | — |
| **User (eingeloggt)** | wie Public + `votes` | `problems`, `solution_approaches`, `tags`, `votes`, `problem_tag` (M2M), `problem_region` (M2M) | `votes`, `problem_tag`, `problem_region` |
| **Admin** | alle | alle | alle |

`votes` ist bewusst nicht in der Public-Policy — Vote-Scores sind in `problems.vote_score` eingebettet, einzelne Stimmen muessen anonym nicht abrufbar sein.

**Wichtig — `fields: ["*"]`:** Jede Permission in der Public-Policy muss `fields: ["*"]` (alle Felder) gesetzt haben. Fehlt diese Angabe, antwortet Directus zwar mit 200, liefert aber leere Objekte — der Graph bleibt leer ohne sichtbaren Fehler. `make db-permissions` setzt dies automatisch.

**Debugging — User bekommt 403 obwohl Permissions korrekt konfiguriert sind:**
Wenn Role → Policy → Permissions alle korrekt gesetzt sind, aber der eingeloggte User trotzdem 403 bekommt, hat er wahrscheinlich **keine Rolle zugewiesen** (`"role": null`). Pruefung:
```bash
curl -s "http://localhost:8055/users?fields=id,email,role&limit=20" \
  -H "Authorization: Bearer $TOKEN"
```
Fehlende Rolle kann passieren wenn `make seed-users` nicht `default_role` in Directus-Settings setzt oder der User vor dem Seed-Lauf angelegt wurde. Loesung: Rolle im Directus-Admin manuell zuweisen oder User loeschen und neu registrieren (nach `make seed-users`).

**Gotcha — Directus 11: `admin_access` nicht mehr auf Role-Objekt:**
In Directus 11 ist `admin_access` von `directus_roles` nach `directus_policies` gewandert. `role.admin_access` existiert nicht mehr und gibt immer `undefined` zurueck — das Admin-Menue bleibt unsichtbar ohne Fehlermeldung.
Korrekte Pruefung: `role.policies?.some(p => p.policy?.admin_access === true)` (Directus gibt `role.policies` als Array von `{policy: {admin_access: boolean}}` zurueck, wenn `policies.policy.admin_access` in `USER_FIELDS` requested wird). In `realAuth.ts`: `USER_FIELDS` muss `"role.policies.policy.admin_access"` enthalten; `mapUser` liest `raw.role?.policies?.some(p => p.policy?.admin_access)`.

**Gotcha — Directus 11: Custom-Felder auf `directus_users` und fehlende Systemfelder:**
`directus_users` hat in Directus 11 kein `date_created`-Feld — `createdAt` muss auf `''` als Fallback gemappt werden (kein Query-Fehler, aber `undefined` wenn requested).
`display_name` und `company` sind nicht im Standard-Schema — sie muessen als Custom-Felder via API (`POST /fields/directus_users`) oder `seed-users.sh` angelegt werden. Fehlen sie, gibt Directus beim Lesen `undefined` zurueck (kein Fehler).
User-Policy braucht ausserdem READ auf `directus_users` (filter: `id == $CURRENT_USER`, alle Felder) und UPDATE auf `directus_users` (filter: `id == $CURRENT_USER`, Felder: `display_name, company`) — ohne diese Permissions schlaegt das Laden und Speichern des User-Profils mit 403 fehl. `make seed-users` richtet beides idempotent ein.

**Flows einrichten (einmalig manuell — nicht im Snapshot):**
Directus Flows verbinden Datenereignisse mit dem AI-Service.

| Flow | Trigger | Ziel |
|---|---|---|
| `problem-submitted` | Action: `problems.items.create` | `POST http://ai-service:8000/hooks/problem-submitted` |
| `problem-approved` | Action: `problems.items.update` (filter: `status=approved`) | `POST http://ai-service:8000/hooks/problem-approved` |
| `solution-approved` | Action: `solution_approaches.items.update` (filter: `status=approved`) | `POST http://ai-service:8000/hooks/solution-approved` |
| `vote-changed` | Action: `votes.items.create` | `POST http://ai-service:8000/hooks/vote-changed` |

Jeder Flow: Trigger → HTTP-Request-Action → Ziel-URL, Methode POST, Header `X-Webhook-Secret: <WEBHOOK_SECRET>`.

Der `vote-changed`-Flow kann per Script angelegt werden (benötigt laufendes Directus):
```bash
make -C infrastructure setup-vote-flow
# Neu anlegen falls bereits vorhanden:
make -C infrastructure setup-vote-flow -- --force
```

**Gotcha — `vote-changed` Flow Body:** Directus-Flow-Trigger-Payload muss explizit auf den HTTP-Request-Body gemappt werden. Body im HTTP-Request-Operation:
```json
{
  "entity_id": "{{$trigger.payload.entity_id}}",
  "entity_type": "{{$trigger.payload.entity_type}}"
}
```
`new_score` muss **nicht** mitgeschickt werden — der AI-Service liest `problems.vote_score` direkt aus der DB.

[↑ Inhalt](#inhalt)

---

## Datenfluss

```
User reicht Problem ein
    → Directus speichert mit status: pending
    → Directus Flow → POST /hooks/problem-submitted (X-Webhook-Secret Header)
        → _verify_webhook_secret() Dependency pruft Header (leer = Dev-Mode)
        → SpamFilter bewertet (sync, LLM-Call)
            → Klarer Spam: status: rejected (automatisch)
            → Unklar / gultig: status: needs_review
        → DB-Write mit eigener psycopg-Connection
        → background_tasks.add_task(...) → 200 sofort zurueck
        → [async, nach Response]:
            embed (eigene Conn) → solution generieren (eigene Conn)
            → cluster aktualisieren (eigene Conn) → WebSocket broadcast
    → Admin pruft Moderations-Queue
        → Freigegeben: status: approved
    → Frontend liest freigegebene Probleme + Cluster aus Directus
    → Cytoscape.js rendert Graph
```

[↑ Inhalt](#inhalt)

---

## Code-Formatierung und Linting

Formatierung ist nicht verhandelbar — automatisch vor Commit und in Jenkins.

### TypeScript / Vue

- **ESLint** + `eslint-plugin-vue` — Linting
- **Prettier** + `eslint-config-prettier` — Formatierung

```bash
make lint-frontend    # ESLint prufen
make format-frontend  # Prettier anwenden
```

### Python

- **ruff** — Linting und Formatierung (ersetzt flake8 + black + isort)

```bash
make lint-backend     # ruff check
make format-backend   # ruff format
```

[↑ Inhalt](#inhalt)

---

## CI/CD — Jenkins Pipeline

Jedes Sub-Repo hat eine eigene Pipeline. Ein Frontend-Deploy triggert keinen Backend-Build.

### Frontend-Pipeline (Reihenfolge invariant)

```
1. checkout
2. npm ci
3. lint (ESLint + Prettier)
4. test (Vitest)
5. docker build-amd64 (Multi-Stage: build → runner) + push nach ghcr.io
6. make -C infrastructure deploy-service SVC=frontend
```

### AI-Service-Pipeline

```
1. checkout
2. pip install (inkl. hdbscan, scikit-learn, numpy)
3. lint (ruff)
4. test (pytest)
5. docker build-amd64 (Multi-Stage: build → runner) + push nach ghcr.io
6. make -C infrastructure deploy-service SVC=ai-service
```

**Gotcha — Lange Build-Zeit durch native Kompilierung:** `hdbscan` hängt von `scikit-learn` und `numpy` ab — beide kompilieren C/Fortran-Extensions beim `pip install`. Der erste Build in CI ohne Layer-Cache dauert deutlich länger als reine Python-Pakete. Ist einmalig solange der Docker Layer-Cache warm bleibt; bei Cache-Miss (z.B. nach `requirements.txt`-Änderung) wiederholt sich die Kompilierung. Base-Image mit vorinstallierten Binär-Wheels (`python:3.11-slim` + `--only-binary=:all:`) kann die Zeit reduzieren.

### Server-Voraussetzungen (Hetzner)

`docker compose` (V2) erfordert das offizielle Docker-Repository — **nicht** `docker.io` (Ubuntu-Paket):

```bash
# Altes Paket entfernen
sudo apt-get remove docker.io docker-compose

# Offizielles Docker-Repo einrichten
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

`docker.io` liefert keinen `docker compose`-Subcommand (V2) — nur das veraltete standalone `docker-compose` (V1). Das Makefile und alle Pipeline-Schritte verwenden V2-Syntax (`docker compose up`).

### Deploy-Strategie

`nuxt build` erzeugt einen Node.js-Server (nicht statische Dateien). Das Docker-Image
wird lokal auf dem Jenkins-Agent gebaut, nach ghcr.io gepusht und via
`make -C infrastructure deploy-service SVC=frontend` deployed
(SSH + `docker compose pull frontend` + `docker compose up --no-deps --force-recreate frontend`).

**Warum nicht `nuxt generate`?** Die SPA-Routes (`ssr: false`) und dynamische Daten
funktionieren nicht sauber mit statischer Generierung.

**Dockerfile (Multi-Stage):**
- Base Image: `node:20-bookworm-slim` (Debian 12 slim) — nicht Alpine, da native npm-Dependencies sonst musl-Kompatibilitätsprobleme verursachen
- Stage `builder`: `npm ci` + `nuxt build` → erzeugt `.output/`
- Stage `runner`: nur Node.js + `.output/` — kein `node_modules`, kein Source-Code im Image

**Naming-Konvention:** Image- und Container-Namen folgen dem Schema `decisionmap-<service>`
(z.B. `decisionmap-backend`, `decisionmap-frontend`, `decisionmap-ai-service`, `decisionmap-postgres`).
Definiert in `infrastructure/docker-compose.yml`.

**Jenkinsfile:** Lint + Test laufen auf allen Branches. Build + Deploy nur auf `main`.
Lokales Build-Image wird nach dem Deploy auf dem Jenkins-Agent geloescht.
[`.templates/Jenkinsfile`](../.templates/Jenkinsfile) ist ein generisches Ausgangs-Template — muss fuer die oben beschriebene Deploy-Strategie (ghcr.io Push + `make -C infrastructure deploy-service`) angepasst werden. Konkret: `sh './docker/app/build --build'` → `sh './docker/build.sh --build'` (Pfad auf `docker/build.sh` des Sub-Repos anpassen).

**Build-Script:** [`.templates/docker/build.sh`](../.templates/docker/build.sh) ist das generische Bash-Template fuer Sub-Repo-Build-Skripte. (Das ebenfalls vorhandene `.templates/docker/Dockerfile` ist ein generisches Debian/certbot-Base-Image fuer Tooling — kein Nuxt-Template.) Enthaelt Platform-Erkennung, BashLib-Includes, `--build`/`--push`/`--images`-Flags und TAG-Erzeugung via `gitDockerTag` aus `version.lib.sh` (BashLib) — Format: `<VERSION>-<YYMMDD>.<HHMM>.<HASH>[.ahead<N>][.d]`, z.B. `0.1.0-260412.0824.def34.ahead3`; Git-Tag-Format: `v<VERSION>+<YYMMDD>.<HHMM>.<HASH>`. Benoetigt `DEV_DOCKER`-Env-Variable auf der Build-Maschine (zeigt auf Docker-Hilfsskripte). Pro Sub-Repo nach `docker/build.sh` kopieren und `NAMESPACE`/`NAME`/Deploy-Logik anpassen. **Wichtig:** Der `--push`-Zweig im Template ruft `pushImage2DockerHub` auf — dieser Block muss vollstaendig durch `docker push ghcr.io/...` ersetzt werden (Docker Hub wird nicht verwendet; Images gehen nach ghcr.io). Das Dockerfile liegt in `docker/`, der Build-Context ist das Parent-Verzeichnis des Sub-Repos (`docker build -f Dockerfile ..`). **Achtung:** Da der Build-Context das gesamte Sub-Repo-Verzeichnis umfasst, muss `docker/` in `.dockerignore` ausgeschlossen werden — sonst landet das Build-Verzeichnis selbst im Image.

**Gotcha — `--builder default` und fehlendes `--load` in `docker build`:**
`docker buildx build --builder default` schlägt fehl wenn auf Mac mit Docker Desktop der aktive Context `desktop-linux` ist — `default` ist dann kein gültiger Builder-Name (Fehlermeldung: `use docker --context=default buildx ...`). `--builder default` weglassen — buildx verwendet automatisch den aktiven Context:
- **Mac / Docker Desktop:** aktiver Context = `desktop-linux` (docker driver, direkt am lokalen Daemon)
- **Linux / CI / Jenkins:** aktiver Context = `default` (docker driver, existiert dort immer)

Der `multiarch`-Builder (docker-container driver) wird für single-arch Builds nicht benötigt. Ausserdem: ohne `--load` landet das gebaute Image nicht im lokalen Docker-Daemon (buildx cached es nur intern). `--load` ist Pflicht, wenn das Image lokal weiterverwendet oder gepusht werden soll.
```bash
# Falsch:
docker buildx build --builder default --platform linux/amd64 -t myimage .
# Richtig:
docker buildx build --platform linux/amd64 --load -t myimage .
```

**`.dockerignore` fuer Multi-Stage-Builds:** `.output/` muss in `.dockerignore` stehen — nicht weil `COPY --from=builder` den Host liest (das tut es nicht, es greift auf Stage 1 zu), sondern weil `COPY . .` in Stage 1 ein lokales `.output/` (vom Host) in den Build-Context uebertraegt. Das kann ein veraltetes lokales Artefakt in Stage 1 einschleppen, bevor `npm run build` laeuft. `node_modules/` und `.output/` gehoeren daher beide in `.dockerignore`.

### Konfiguration ausserhalb der Pipeline

Das `.env` liegt auf dem Hetzner-Server — Jenkins deployt nur den Build-Artefakt.
Vorlage: `infrastructure/.env.example` (alle Variablen mit Prod-Defaults, HTTPS-URLs, `USE_FAKE_DATA=false`).

```bash
# Erstmalig einrichten oder aktualisieren:
cp infrastructure/.env.example infrastructure/.env
# Werte setzen, dann hochladen:
scp infrastructure/.env decmap:/srv/decisionmap/.env
```

Phasenumschaltung ausschliesslich durch Anpassen von `.env` auf dem Server:

```bash
# Phase 1 — Fake-Daten
USE_FAKE_DATA=true

# Phase 2 — Live (Pipeline unveraendert)
USE_FAKE_DATA=false
```

### nginx — TLS-Terminierung

nginx laeuft als Docker-Container (`nginx:bookworm`, Debian 12). TLS wird im Container terminiert, nicht auf dem Host.

**Image:** `nginx:bookworm` statt Alpine — Debian-Basis, User `nginx` (Alpine verwendet `www-data`).

**Let's Encrypt Volumes:** Beide Pfade muessen gemountet werden, weil `live/fullchain.pem` ein Symlink auf `archive/` ist:

```yaml
volumes:
  - /etc/letsencrypt/live/decisionmap.ai:/etc/letsencrypt/live/decisionmap.ai:ro
  - /etc/letsencrypt/archive/decisionmap.ai:/etc/letsencrypt/archive/decisionmap.ai:ro
```

**nginx.conf:**
- Port 80: reiner `301`-Redirect zu HTTPS
- Port 443: TLS (`TLSv1.2/1.3`), alle Location-Bloecke (Frontend, CMS, AI-Service, WebSocket)

**Directus auf Subdomain `cms.decisionmap.ai`:**
Directus läuft auf einer eigenen Subdomain — kein `/cms`-Pfad-Prefix, kein `proxy_redirect`. `PUBLIC_URL=https://cms.decisionmap.ai` in `.env` Pflicht.

```nginx
server {
    server_name cms.decisionmap.ai;
    location / {
        proxy_pass http://directus:8055;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

**Directus WebSocket-Subscriptions hinter nginx:** Der Subdomain-Block muss WebSocket-Upgrade-Headers weiterleiten — sonst schlägt `useDirectusRealtime.ts` lautlos fehl.

**nginx — `proxy_pass` mit Variable + `rewrite` — drei Gotchas:**

1. **`proxy_pass http://$var/` macht keine Prefix-Substitution.** Ohne Variable würde `location /api/` + `proxy_pass http://upstream/` das `/api/`-Prefix automatisch ersetzen. Mit Variable passiert das nicht — `/api/health` landet als `/api/health` beim Backend. Fix: `rewrite` + `$uri` explizit übergeben.

2. **`rewrite ... break` stoppt auch `set`.** `break` unterbricht alle Direktiven des nginx Rewrite-Moduls — dazu gehört auch `set`. Eine `set`-Direktive nach `rewrite ... break` wird nie ausgeführt → Variable bleibt leer → nginx-Error "no host in upstream". **`set` immer vor `rewrite` stellen.**

3. **`proxy_pass http://$var` (ohne URI) nach `rewrite` nimmt die Original-URI.** `$uri` enthält nach einem `rewrite` die neue URI — explizit übergeben:
```nginx
location /api/ {
    set $upstream_ai ai-service:8000;          # set VOR rewrite
    rewrite ^/api/(.*)$ /$1 break;
    proxy_pass http://$upstream_ai$uri$is_args$args;
}
```

**`host-install`:** Installiert nur noch systemd-Service und cert-watcher — kein nginx auf dem Host, keine `nginx -t`/`systemctl reload nginx` Schritte.

**Cert-Rotation:** `unpackCert.sh` (`host/usr/local/bin/`) entpackt neue Zertifikate und startet den nginx-Container neu — aufgerufen durch den systemd cert-watcher (`cert.decisionmap.ai.path`).

**Server-Voraussetzung — Docker Compose V2:** Alle Makefiles verwenden `docker compose` (V2, kein Bindestrich). Auf Ubuntu 24.04 mit offiziellem Docker-Repository ist das Compose-Plugin ein separates Paket:

```bash
sudo apt-get install docker-compose-plugin
docker compose version   # → Docker Compose version v2.x.x
```

Bei `docker.io`-Installation (Ubuntu-Paket statt Docker-Repo) muss zuerst das offizielle Docker-Repository eingerichtet werden.

[↑ Inhalt](#inhalt)

---

## Makefile-Struktur

Jedes Sub-Repo hat ein eigenes Makefile fuer seinen Kontext. `make help` zeigt die Befehle des jeweiligen Repos, `make hints` zeigt Service-URLs, SSH-Befehle und Abhaengigkeiten.

Konventionen (Struktur, `##@`-Gruppen, `.PHONY`, `info`/`hints`-Targets, Farben): `/code-standards`

`make help` unterstützt Farbthemen via `MAKE_THEME` (Env-Variable oder `.env`): `classic` (Standard), `ocean`, `earth`, `night`, `mono`, `sunset`, `forest`, `neon`.

| Makefile | Zustandig fuer |
|---|---|
| `Makefile` (Root) | Workspace-Setup, Delegation an Sub-Repos, Cross-Repo lint/test |
| `infrastructure/Makefile` | docker-compose, nginx, Server-Orchestrierung |
| `apps/backend/Makefile` | Directus, Datenbank, Backup, Seeds, Versioning |
| `apps/frontend/Makefile` | Dev-Server, Lint, Test, Build, Versioning |
| `apps/ai-service/Makefile` | Dev-Server, Lint, Test, Build, DB-Migrationen, Versioning |

[`.templates/Makefile`](../.templates/Makefile) ist ein generisches Ausgangs-Template. Benoetigt `DEV_MAKE`-Env-Variable (zeigt auf `MakeLib`).

**Versioning-Voraussetzung:** `bumpVer` benoetigt `BASH_LIBS` und eine Versionsdatei (`package.json`, `pyproject.toml` oder `VERSION`). Jedes Sub-Repo muss genau eine davon enthalten:

| Repo | Versionsdatei |
|---|---|
| `apps/backend/` | `VERSION` |
| `apps/frontend/` | `package.json` |
| `apps/ai-service/` | `pyproject.toml` |

```bash
# Workspace-Root
make setup             # .libs/-Symlinks erstellen (einmalig, benoetigt DEV_LOCAL)
make status            # Git-Status aller Workspace-Repos (dirty + ahead/behind Remote)
make fakedata-sync     # Fake-Daten aus data/ generieren und an Consumer-Repos verteilen
make dev-up            # Docker-Services + overmind (Frontend + AI-Service via Procfile.dev)
make dev-down          # Docker-Services stoppen
make lint              # → delegiert an apps/frontend/ und apps/ai-service/
make test              # → delegiert an apps/frontend/ und apps/ai-service/

# Backend (aus apps/backend/ oder via make -C apps/backend ...)
make up / down / logs                                 # Alle Services
make dev-up / dev-down / dev-logs                     # Dev-Umgebung (Directus + Mailpit)
make db-reset                                         # DB zurücksetzen (schema → constraints → seed)
make directus-schema-apply                            # ↳ Directus-Schema anwenden
make db-constraints                                   # ↳ vector-Spalten, Constraints, Junction-Tables
make db-seed                                          # ↳ Seed-Daten einspielen
make db-migrate / db-rollback / db-migrate-status     # Alembic-Migrationen (nach initialem Setup)
make seed-users                                       # Test-User in Directus
make backup / backup-schema / backup-restore          # Backup
make build / deploy                                   # Build & Deploy
make precheck / version / tags                        # Versioning
make tag-patch / tag-minor / tag-major                # SemVer Git-Tag setzen + pushen

# AI-Service (aus apps/ai-service/ oder via make -C apps/ai-service ...)
make install / install-dev                            # Abhaengigkeiten
make lint / format                                    # Code-Qualitaet (ruff)
make test / test-unit / test-contract                 # Tests (pytest)
make dev                                              # uvicorn mit --reload
make build / docker-up / docker-down                  # Docker
make db-migrate / db-migrate-create / db-rollback     # Alembic
make precheck / version / tags                        # Versioning
make tag-patch / tag-minor / tag-major                # SemVer Git-Tag setzen + pushen
# → Manuelle curl-Tests aller Endpunkte: docs/cmdline.md

# Frontend (aus apps/frontend/ oder via make -C apps/frontend ...)
make dev / install / lint / format / test             # Entwicklung
make build / deploy                                   # Deploy
make tag-patch / tag-minor / tag-major                # Versioning
```

[↑ Inhalt](#inhalt)

---

## Versionierung

### Release-Tags (SemVer + Datum)

**Format:** `v<MAJOR>.<MINOR>.<PATCH>+<YYMMDD>.<HHMM>` — klassisches SemVer, Datum als Build-Metadata.

```
v0.1.0+260411.1430      # Erstes Release
v0.2.0+260422.1400      # Minor-Bump (neues Feature)
v0.2.1+260510.1115      # Patch-Bump (Bugfix)
v1.0.0+260701.0900      # Major-Bump (Breaking Change)
v0.3.0-rc1+260628.1600  # Release Candidate
```

Alle Repos starten bei `0.1.0`. Major/Minor/Patch wird manuell gewaehlt.

**Makefile-Targets:**

```makefile
make tag-major          # Major-Bump (0.1.0 → 1.0.0)
make tag-minor          # Minor-Bump (0.1.0 → 0.2.0)
make tag-patch          # Patch-Bump (0.1.0 → 0.1.1)
make tag-minor MSG="…"  # mit Tag-Message
make version            # Aktuelle Version anzeigen
make tags               # Letzte 10 Tags anzeigen
```

`bumpVer` (BashLib) schreibt die Version in die Datei (`VERSION`, `package.json` oder `pyproject.toml`),
erstellt einen Git-Commit und setzt den Tag. Reihenfolge: Version berechnen → Datei schreiben → Commit → Tag.

### Snapshot-Tags (Docker)

Build-Scripts verwenden `gitDockerTag` aus `version.lib.sh` (BashLib) fuer Docker-Image-Tags — automatisch via Jenkins.

**Format:** `<MAJOR>.<MINOR>.<PATCH>-<YYMMDD>.<HHMM>.<HASH>[.ahead<N>][.d]`

```
0.1.0-260412.0824.def34           # normaler Snapshot-Build
0.1.0-260412.0824.def34.ahead3    # 3 unpushte Commits ueber dem Tag
0.1.0-260412.0824.def34.d         # dirty Working Tree
```

Snapshot-Tags werden automatisch vom Jenkins-Build erzeugt — nie manuell.

[↑ Inhalt](#inhalt)

---

## Git-Konventionen

### Commit-Messages

Format: `<type>(<scope>): <beschreibung>`

| Type | Wann |
|---|---|
| `feat` | Neues Feature |
| `fix` | Bugfix |
| `refactor` | Umstrukturierung ohne Funktionsanderung |
| `test` | Tests |
| `chore` | Build, Dependencies, Konfiguration |
| `docs` | Dokumentation |

### Branch-Naming

```
feature/<kurze-beschreibung>
fix/<kurze-beschreibung>
chore/<kurze-beschreibung>
```

- `main` ist immer deploybar — Jenkins ist die einzige Schranke
- Direkte Commits auf `main` sind erlaubt (kleines Team)
- Feature-Branches optional, aber empfohlen fuer groessere Aenderungen

[↑ Inhalt](#inhalt)

---

## Seed-Daten

**SSoT:** `data/*.json` im Root-Repo (snake_case, UUIDs). Nie direkt in Consumer-Repos editieren.

```bash
make fakedata-sync                           # generieren + verteilen
python3 scripts/gen-fakedata.py -n               # --dry-run: pruefen ohne schreiben
```

`make fakedata-sync` verteilt an `apps/frontend` (camelCase) und `apps/ai-service/tests/fakedata/` (snake_case + embedding-Stub).

**Backend SQL-Seeds** in `database/seeds/` — alphabetisch importiert, idempotent (`ON CONFLICT DO NOTHING`).
Manuell anpassen wenn sich `data/*.json` aendert (kein automatisches Sync fuer SQL-Seeds).

```
database/seeds/
├── 001_regions.sql      ← EU, US, APAC, GLOBAL
├── 002_tags.sql         ← governance, open-source, ...
└── 003_problems.sql     ← 40–50 Seed-Probleme mit Embeddings
```

```bash
make db-seed             # alle importieren
make db-seed FILE=003    # einzelnes File
make db-reset            # DB zurucksetzen + Migrationen + Seed (nur lokal!)
```

Dieselben Files in `docker-compose.test.yml` — kein separater Test-Datensatz.

[↑ Inhalt](#inhalt)

---

## Backup

Einheitliches Script `scripts/db-backup.sh` — wird von Backend- und Infrastructure-Makefile genutzt.
Immer `--format=custom` (`.dump`), wiederherstellbar mit `pg_restore`.

```bash
# Backend (Dev)
make -C apps/backend backup              # vollstaendiges DB-Backup
make -C apps/backend backup-list         # vorhandene Backups auflisten
make -C apps/backend restore FILE=database/backups/decisionmap_20260412_120000.dump

# Infrastructure (Prod)
make -C infrastructure backup            # vollstaendiges DB-Backup auf dem Server
make -C infrastructure backup-schema     # nur Schema sichern
make -C infrastructure backup-list       # vorhandene Backups anzeigen
make -C infrastructure backup-restore FILE=backups/decisionmap_20260412_120000.dump
make -C infrastructure backup-pull       # Server → lokal (rsync backups/)
make -C infrastructure backup-push       # lokal → Server (rsync backups/)
```

Das Script delegiert alle Operationen via `docker compose exec` und akzeptiert
`--compose-file`, `--service`, `--backup-dir`, `--user`, `--db` (oder Env-Variablen):

```bash
scripts/db-backup.sh --help   # vollstaendige Optionsliste
```

Backups nie einchecken — `database/backups/` bzw. `backups/` in `.gitignore`.

**Restore mit aktiven Services:** Directus und AI-Service halten offene DB-Connections. `pg_restore` kann dann keine DROP/CREATE-Operationen auf verwendeten Tabellen ausführen → partieller Restore möglich. Vor einem Restore die betroffenen Services stoppen (`docker compose stop directus ai-service`), danach neu starten.
