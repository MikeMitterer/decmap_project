# Datenmodell — DecisionMap

Vollstaendige Spezifikation: `docs/data-model.md`

---

## Kerntabellen

`problems`, `solution_approaches`, `clusters`, `tags`, `regions`, `votes`

Junction-Tabellen: `problem_cluster` (n:m mit Weight), `problem_tag`, `problem_region`

Audit: `edit_history`, `moderation_log`

## Beziehungen

```
users ──< problems ──< solution_approaches
              │
              ├──>< problem_cluster >──< clusters
              ├──>< problem_tag >──< tags (hierarchisch: L0–L10)
              └──>< problem_region >──< regions
```

## Tag-Hierarchie

- L0 = Root (System-intern, nie sichtbar)
- L1–L9 = KI-generierte Cluster-Tags
- L10 = User-Tags (einzige Ebene die User direkt vergeben)

## Regeln

- DB-Versionierung: Alembic — nie bestehende Migrationen editieren, Breaking Changes zweistufig
- Validierung: 3 Schichten — Zod (Frontend) → Pydantic (AI-Service) → PostgreSQL Constraints
- Kein Hard Delete — Soft Delete ueber `deleted_at` / `deleted_by`
- Seeds: `database/seeds/` alphabetisch, idempotent

## Directus-spezifisch

- M2M-Aliasfelder heissen nach `one_field` in der Relation-Definition (z.B. `tags`, nicht `problem_tag`)
- Alembic-angelegte Spalten muessen in Directus per `POST /fields/{collection}` registriert werden
- Permissions nie per SQL — immer via REST API (`make db-permissions`)
