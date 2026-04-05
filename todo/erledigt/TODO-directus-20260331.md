# Directus Einrichtung — ToDo

## Ausgangslage (Claude)
Option B — Schema-Snapshot (empfohlen):
Directus kann seine Konfiguration als JSON exportieren (schema apply). 
Ich kann ein fertiges Schema-Snapshot-File für dein Datenmodell erstellen, 
das du einmalig per CLI importierst — dann ist alles
automatisch konfiguriert und versioniert.

  ---
Soll ich Option B umsetzen — also ein Directus-Schema-Snapshot auf Basis des bestehenden Datenmodells erstellen?

❯ Wenn du Option B ausführst, ich das manuell mache und von meiner Version einen Snapshot mache - kannst du das dann vergleichen und mich auf Fehler aufmerksam machen?

## Zugangsdaten
Directus Admin: http://localhost:8055
Login: `admin@decisionmap.dev` / `admin123`

---

## 1. Collections registrieren

**Settings → Data Model → Create Collection**

Jede Tabelle einmalig registrieren. Primary Key ist immer `id` (UUID).

- [ ] `problems`
- [ ] `solution_approaches`
- [ ] `clusters`
- [ ] `tags`
- [ ] `regions`
- [ ] `votes`
- [ ] `edit_history`
- [ ] `moderation_log`
- [ ] `problem_cluster` *(Junction — Directus warnt wegen fehlendem PK, trotzdem registrieren)*
- [ ] `problem_tag` *(Junction)*
- [ ] `problem_region` *(Junction)*

---

## 2. Relations konfigurieren

**Settings → Data Model → [Collection] → Add Field → Relational**

| Collection | Feld | Relation | Ziel |
|---|---|---|---|
| `solution_approaches` | `problem_id` | Many-to-One | `problems` |
| `tags` | `parent_id` | Many-to-One | `tags` *(self-referential)* |
| `problems` | `solutions` | One-to-Many | `solution_approaches.problem_id` |
| `problems` | `clusters` | Many-to-Many | `clusters` via `problem_cluster` |
| `problems` | `tags` | Many-to-Many | `tags` via `problem_tag` |
| `problems` | `regions` | Many-to-Many | `regions` via `problem_region` |

---

## 3. Rollen & Berechtigungen

**Settings → Roles & Permissions**

### Public (bereits vorhanden)
Read-Zugriff auf:
- [ ] `problems` — nur `status = approved` (Filter setzen)
- [ ] `clusters`
- [ ] `tags`
- [ ] `regions`

### Editor (neu anlegen)
- [ ] Neue Rolle "Editor" erstellen
- [ ] `problems` — Create, Read eigene Einträge
- [ ] `solution_approaches` — Create, Read eigene Einträge
- [ ] `votes` — Create, Read

---

## 4. API-Token erstellen

**Settings → Users → Admin User → Token generieren**

- [ ] Token generieren
- [ ] In `infrastructure/.env` eintragen: `DIRECTUS_TOKEN=<token>`

---

## 5. Snapshot exportieren & prüfen lassen

Wenn alles oben abgehakt ist:

```bash
docker exec decisionmap-directus node cli.js schema snapshot --yes /directus/snapshot.json \
  && docker cp decisionmap-directus:/directus/snapshot.json \
     infrastructure/directus/schema-snapshot.json
```

Dann den Snapshot Claude zeigen zur Überprüfung.
