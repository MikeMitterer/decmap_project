# Frontend: ProblemTag.id fehlt in realTags.ts + types.ts

Gefunden bei Analyse der Real-Data-Layer-Implementierung (2026-04-05).

## Problem

`ProblemTag` hat kein `id`-Feld, obwohl `problem_tag` in der DB eine UUID-PK hat
(seit M2M-Refactoring: `id UUID DEFAULT uuid_generate_v4() PRIMARY KEY`).

## Anpassungen nötig

**`frontend/types.ts`**
```typescript
export interface ProblemTag {
  id: string          // neu
  problemId: string
  tagId: string
  weight: number
}
```

**`frontend/composables/realTags.ts`** — DirectusProblemTag Interface + fields-Query:
```typescript
interface DirectusProblemTag {
  id: string          // neu
  problem_id: string
  tag_id: string
  weight: number
}

// fields-Query anpassen:
ptParams = new URLSearchParams({ fields: 'id,problem_id,tag_id,weight', limit: '-1' })
```

## Kein Breaking Change

- Vue-Components arbeiten auf `tagIds: string[]` (Aggregation) — unberührt
- `realProblems.ts` mappt nur `tag_id`-Arrays — unberührt
- Fake-Implementierungen + Tests — unberührt

Das `id`-Feld wird derzeit nicht genutzt, aber die DB liefert es.
Fehlend schadet nicht, aber ist inkonsistent mit dem DB-Schema und könnte
bei zukünftigen Tag-Operationen (Edit, Delete eines konkreten problem_tag-Eintrags) fehlen.
