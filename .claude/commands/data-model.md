# Datenmodell — DecisionMap

Vollstaendige Spezifikation: `docs/data-model.md`

---

## Kerntabellen

`problems`, `solution_approaches`, `tags`, `regions`, `votes`

Junction-Tabellen: `problem_tag`, `problem_region`

~~`clusters`, `problem_cluster`~~ *(gedroppt — Migration 005, 2026-05-22; Clustering laeuft jetzt ueber `problem_tag` L1–L9)*

Audit: `edit_history`, `moderation_log`

## Beziehungen

```
users ──< problems ──< solution_approaches
              │
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

