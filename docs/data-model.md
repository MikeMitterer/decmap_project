# Datenmodell

## Tabellen

**`problems`** — Kernentitat. Erfasst ein KI-Problem aus dem Unternehmensalltag. Durchlauft einen Moderations-Workflow vor der Veroffentlichung. Anonyme Submissions erlaubt. Titel und Beschreibung werden automatisch ins Englische ubersetzt — Embeddings und Clustering laufen ausschliesslich auf den englischen Feldern.
```
id                  uuid (PK)
title               string (required, max 200)  — Originalsprache des Users
title_en            string (required, max 200)  — Englisch, automatisch ubersetzt, anpassbar
description         text (optional)             — Originalsprache
description_en      text (optional)             — Englisch, automatisch ubersetzt, anpassbar
content_language    string (default "en")       — ISO 639-1, z.B. "de", "fr", "es"
status              enum: pending | needs_review | approved | rejected
rejection_reason    string (nullable)
embedding           vector(1536)                — generiert aus title_en + description_en
user_id             FK → directus_users (nullable — anonyme Submissions erlaubt)
session_id          string (nullable)
vote_score          integer (default 0)
is_ai_generated     boolean (default false)
edited_at           timestamp (nullable)
deleted_at          timestamp (nullable)        — Soft Delete durch Admin
deleted_by          FK → directus_users (nullable)
created_at          timestamp
```

**`solution_approaches`** — Losungsansatz zu einem Problem. Markdown (eingeschrankt) erlaubt. Durchlauft denselben Moderations-Workflow wie Problems. Kann von der KI oder von Usern stammen. Enthalt ebenfalls automatische Ubersetzung ins Englische.
```
id                  uuid (PK)
content             text (required, Markdown erlaubt — nur Links und Fettschrift)  — Originalsprache
content_en          text (required)             — Englisch, automatisch ubersetzt, anpassbar
content_language    string (default "en")       — ISO 639-1
status              enum: pending | needs_review | approved | rejected
problem_id          FK → problems
user_id             FK → directus_users (nullable)
session_id          string (nullable)
vote_score          integer (default 0)
is_ai_generated     boolean (default false)
edited_at           timestamp (nullable)
deleted_at          timestamp (nullable)        — Soft Delete durch Admin
deleted_by          FK → directus_users (nullable)
created_at          timestamp
```

**`clusters`** — KI-generierte Problemfelder. Label und Beschreibung werden automatisch aus den geclusterten Embeddings generiert. Centroid ist der Durchschnittsvektor aller zugehorigen Problems.
```
id                  uuid (PK)
label               string (AI-generiert)
description         text (AI-generiert)
centroid            vector(1536)
problem_count       integer (denormalisiert)
updated_at          timestamp
```

**`problem_cluster`** — Junction: Problem ↔ Cluster (n:m). Ein Problem kann in mehreren Clustern vorkommen. Weight ist der Soft-Clustering-Score aus HDBSCAN.
```
problem_id          FK → problems
cluster_id          FK → clusters
weight              float (Soft-Clustering-Score, 0.0–1.0)
PRIMARY KEY (problem_id, cluster_id)
```

**`tags`** — Hierarchische Themen-Tags. Level bestimmt die Ebene in der Taxonomie: L0 Root, L1-L9 KI-generierte Kategorien, L10 User-Tags. Strukturelle Tags (L0-L9) haben ein `parent_id`, User-Tags (L10) sind flach.
```
id                  uuid (PK)
name                string (unique)
level               integer                     — 0 = Root, 1-9 = KI-Kategorien, 10 = User-Tags
parent_id           FK → tags (nullable)        — null bei L0 und L10
locked_by           enum: admin | ai | null     — Schutz vor manueller Bearbeitung
created_at          timestamp
```

Tag-Hierarchie:
- **L0** (Root): Einzelner Wurzelknoten — uebergeordnetes Thema der Plattform. `locked_by: admin`
- **L1** (Top-Kategorien): z.B. "Governance & Compliance" — KI-generiert, `locked_by: ai`
- **L2** (Unterkategorien): z.B. "Shadow AI & Governance" — KI-generiert, `locked_by: ai`
- **L3–L9**: Tiefere KI-generierte Ebenen, werden erst bei groesseren Datenmengen relevant
- **L10** (User-Tags): Flach, kein `parent_id`, z.B. "shadow-ai", "data-privacy" — `locked_by: null`

Beim KI-Clustering werden nur L1–L9 neu generiert. L0 (Root) und L10 (User-Tags) bleiben erhalten.

**`problem_tag`** — Junction: Problem ↔ Tag (n:m) mit optionalem Weight.
```
problem_id          FK → problems
tag_id              FK → tags
weight              float (0.0–1.0, default 1.0)
PRIMARY KEY (problem_id, tag_id)
```

**`regions`** — Lookup: geografische Regionen. Probleme ohne Region gelten als global.
```
id                  uuid (PK)
code                string (unique) — z.B. EU, US, APAC, GLOBAL
name                string           — z.B. "European Union", "United States"
```

**`region`** — Junction: Problem ↔ Region (n:m). Beeinflusst Ranking und optionale Filterung im Graph.
```
problem_id          FK → problems
region_id           FK → regions
PRIMARY KEY (problem_id, region_id)
```

**`votes`** — Up/Downvotes auf Problems und Solution Approaches. Anonyme Votes uber session_id und ip_hash nachverfolgbar. Duplicate-Vote-Prevention per UNIQUE Constraint.
```
id                  uuid (PK)
entity_type         enum: problem | solution
entity_id           uuid
vote_type           enum: up | down
user_id             FK → directus_users (nullable)
session_id          string (nullable)
ip_hash             string
created_at          timestamp
UNIQUE (entity_id, entity_type, user_id)
```

**`edit_history`** — Versionierung von Anderungen an Problems und Solution Approaches. Nur fur Moderatoren sichtbar. Jede Anderung nach Approval lost erneute Moderation aus.
```
id                  uuid (PK)
entity_type         enum: problem | solution
entity_id           uuid
previous_content    text
edited_by           FK → directus_users
edited_at           timestamp
```

**`moderation_log`** — Audit-Trail aller Moderationsentscheidungen. Unveranderlich — keine Updates, nur Inserts.
```
id                  uuid (PK)
entity_type         enum: problem | solution
entity_id           uuid
action              enum: approved | rejected | flagged
reason              string (nullable)
moderator_id        FK → directus_users
created_at          timestamp
```

## Beziehungen

```
users ──< problems ──< solution_approaches
              │
              ├──>< problem_cluster >──< clusters
              │
              ├──>< problem_tag >──< tags (hierarchisch: L1–L10)
              │
              └──>< problem_region >──< regions
```

## Datenbank-Versionierung (Alembic)

Alembic verwaltet alle Schema-Anderungen an den Custom-Tabellen.
Directus-System-Tabellen sind ausgenommen — die verwaltet Directus selbst.

### Regeln

- Bestehende Migrationen werden **niemals editiert** — auch nicht um Tippfehler zu korrigieren
- Jede Schema-Anderung bekommt eine neue Migration
- Migrationen sind atomar — eine Migration = eine logische Anderung
- Jede Migration hat ein `upgrade()` und ein `downgrade()`
- Migrationen werden in CI/CD automatisch beim Deploy ausgefuhrt

### Migration erstellen

```bash
make db-migrate-create MSG="add_region_weight_to_region_table"
```

### Upgrade-Prozess

```bash
make db-migrate        # alle ausstehenden Migrationen ausfuhren
make db-migrate-status # aktuellen Stand anzeigen
make db-rollback       # letzte Migration ruckgangig machen
```

Jenkins fuhrt `make db-migrate` automatisch vor jedem Deploy aus.
Bei Fehler bricht der Deploy ab — kein Code-Deploy mit fehlgeschlagener Migration.

### Beispiel Migration

```python
def upgrade() -> None:
    op.add_column(
        "region",
        sa.Column("weight", sa.Float(), nullable=False, server_default="1.0")
    )

def downgrade() -> None:
    op.drop_column("region", "weight")
```

### Umgang mit Breaking Changes

Spalten oder Tabellen werden nie direkt geloscht — zweistufiger Prozess:

```
Stufe 1 (Deploy A): Spalte als deprecated markieren, Code nutzt sie nicht mehr
Stufe 2 (Deploy B): Spalte in separater Migration loschen
```

## Validierung (3 Schichten)

Validierung lauft auf drei Schichten — keine Schicht vertraut der vorherigen blind.

| Schicht | Tool | Zweck |
|---|---|---|
| Frontend | Zod | UX — sofortiges Feedback, kein unnotiger Request |
| Backend | Pydantic | Sicherheit — kein ungultiger Input in die Business Logic |
| Datenbank | PostgreSQL Constraints | Integritat — unabhangig von der Applikationsschicht |

### Frontend (Zod)

```typescript
import { z } from 'zod'

const ProblemSchema = z.object({
  title: z.string().min(10).max(200),
  description: z.string().max(2000).optional(),
})

type ProblemInput = z.infer<typeof ProblemSchema>

const result = ProblemSchema.safeParse(input)
if (!result.success) {
  validationErrors.value = result.error.flatten().fieldErrors
  return
}
```

### Backend (Pydantic)

```python
class ProblemPayload(BaseModel):
    title: str = Field(min_length=10, max_length=200)
    description: str | None = Field(default=None, max_length=2000)

    @field_validator('title')
    @classmethod
    def title_must_not_be_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError('Title must not be blank')
        return value.strip()
```

### Datenbank (PostgreSQL Constraints)

```sql
ALTER TABLE problems
  ADD CONSTRAINT title_length CHECK (char_length(title) BETWEEN 10 AND 200),
  ADD CONSTRAINT description_length CHECK (description IS NULL OR char_length(description) <= 2000),
  ADD CONSTRAINT vote_score_non_negative CHECK (vote_score >= 0);

ALTER TABLE votes
  ADD CONSTRAINT one_vote_per_entity UNIQUE (entity_id, entity_type, user_id);
```

Validierungsregeln die sich andern mussen auf allen drei Schichten gleichzeitig angepasst werden.
Zod-Schema und Pydantic-Modell mussen dieselben Regeln widerspiegeln.
