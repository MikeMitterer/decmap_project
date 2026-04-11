# Kritische Gotchas — DecisionMap

Bekannte Fallstricke die bei der Entwicklung aufgetreten sind.

---

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
