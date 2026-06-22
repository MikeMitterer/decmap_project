# Server-Driven Search & Pagination — Design

**Datum:** 2026-06-22
**Status:** Design (zur Implementierung freigegeben nach User-Review)
**Repos:** `apps/backend` (master), `apps/frontend` (feature/bold-redesign), ggf. `apps/ai-service` (master)

## Problem & Ziel

Das Frontend lädt heute **alle** approved Problems client-seitig (`GET /problems`, kein Limit)
und filtert/sortiert/sucht in-memory über das vollständige `problems.value`-Array. Das skaliert
nicht: Payload, Übersetzungs-Calls (DE-Locale: 1 `/translate` pro Problem), Graph-Rendering
(Cytoscape) und das In-Memory-Filtern werden im niedrigen Tausender-Bereich zum Engpass.

**Ziel:** Suche, Filter, Sortierung und Aggregation laufen **serverseitig**; das Frontend lädt
nur noch die jeweils benötigte Teilmenge. Die App soll mit einer großen Anzahl Datensätze
performant bleiben.

## Bestätigte Entscheidungen (Brainstorming)

1. **Graph = Drill-Down (lazy):** Übersicht zeigt nur Cluster-Nodes + Server-Counts; einzelne
   Problem-Nodes werden erst beim Reinzoomen in einen Cluster nachgeladen.
2. **Table = Infinite-Scroll:** nächste Seite lazy beim Scrollen (bestehender Virtualizer).
3. **Filter/Sort/Suche serverseitig** (zwingend, sobald paginiert wird).
4. **Suche beides voll paginiert:** Keyword **und** semantische Suche sind komplett
   durchblätterbar (Score-/Distanz-basierter Keyset-Cursor).
5. **Echtzeit:** Neue Probleme → „N neue"-Banner (Reload von oben auf Klick). Vote/Edit/Delete
   auf bereits geladene Probleme bleiben sofort live.
6. **Lieferung in 3 Phasen** (inkrementell), siehe unten.

### Beziehung zur vorangegangenen Suche-Arbeit
- **Bleibt tragend:** `problems.original_translations` (JSONB, Source of Truth) und der
  `q_raw`-Match über `original_translations::text` — eine von drei Quellen der cross-lingualen
  Server-Keyword-Suche (siehe „Keyword (`q`)"), ergänzt um EN-Canonical-Match (roh + EN-übersetzt).
- **Entfällt in der Table:** client-seitiges `filteredProblems`/`matchesQuery`/`adminSearchIds`
  als Suchfilter (Server übernimmt). `localizedTitles` bleibt ggf. nur noch für die Anzeige der
  Titel-Spalte, nicht mehr als Suchindex. Der `gotcha_vue_computed_watch_cycle` (Watcher darf
  computed nicht zurücklesen) entschärft sich dadurch von selbst.

---

## Architektur

### Keyset-Cursor (zustandslos, kein OFFSET)

Pagination über **Keyset**: `WHERE (sort_key, id) <cmp> (:last_key, :last_id) ORDER BY sort_key, id`.
Vorteile gegenüber `OFFSET`: stabil bei Inserts/Deletes während des Scrollens (kein
Duplizieren/Überspringen), konstante Query-Kosten.

**Cursor-Format:** opaker base64-String über JSON:
```json
{ "sort": "created", "key": <sort_value>, "id": "<uuid>", "emb": [..]? }
```
- `key` = der Sortierwert der letzten Zeile (created_at ISO-String / vote_score int / title /
  solution_count int / Embedding-Distanz float).
- `emb` nur im **semantic**-Modus: das einmal (ai-service) berechnete Query-Embedding
  (float[1536]) reist **zustandslos** im Cursor mit (~6 KB base64). Kein Server-State/TTL-Cache.
- Cursor wird serverseitig dekodiert + validiert (Sort-Modus muss zum Request passen).

### Backend-Endpoint (Phase 1): `GET /problems`

`routers/problems.py::list_problems` (heute ~Zeile 166, kein Limit) wird ersetzt durch:

```
GET /problems
  ?limit=50                 # default 50, Hard-Cap z.B. 100
  &cursor=<opaque|null>     # null = erste Seite
  &sort=created|votes|title|solutions   # default created, immer desc außer title (asc)
  &q=<keyword>              # Volltext-Modus, sprachunabhängig (nutzt &sort als Reihenfolge)
  &semantic=<text>          # Semantik-Modus: rankt nach Embedding-Distanz, IGNORIERT &sort
  &tags=<id,id>             # Cluster-Subtree, server-expandiert; AND zwischen mehreren
  &regions=<id,id>          # OR innerhalb; AND ggü. anderen Filtern
  &user=<uuid>
  &company=<name>
  &status=approved          # default; != approved erfordert Superuser

→ 200 { "items": ProblemRead[], "next_cursor": string|null, "total": int }
```

**Filter (alle AND-kombiniert):**
- `tags`: jeden Tag auf seinen Subtree expandieren (rekursiv über `tags.parent_id`, wie heute
  client-seitig `getSubtreeTagIds`), dann `EXISTS (problem_tag WHERE tag_id = ANY(subtree))`.
  Mehrere `tags` → AND (jedes muss matchen), wie das heutige `.every(...)`.
- `regions`: `EXISTS (problem_region WHERE region_id = ANY(:regions))` — OR innerhalb.
- `user`: `problems.user_id = :user`.
- `company`: `JOIN users u ON problems.user_id = u.id WHERE u.company = :company`.
- `status`: default `approved`; jeder andere Wert → `current_superuser`-Check (analog
  bestehendem Solutions-Filter-Gotcha).
- Soft-Delete: immer `deleted_at IS NULL`.

**Modus-Wahl:** `q` und `semantic` sind **gegenseitig exklusiv** (max. einer gesetzt). Ist
`semantic` gesetzt → Distanz-Ranking (Tabellen-Zeile `semantic`), `sort` wird ignoriert. Sonst
gilt der `sort`-Modus; `q` filtert dabei zusätzlich per ILIKE, ändert aber die Reihenfolge nicht.

**Sortier-Keyset pro Modus:**
| Modus | ORDER BY | Keyset-Vergleich |
|---|---|---|
| `sort=created` (default) | `created_at DESC, id DESC` | `(created_at, id) < (:key, :id)` |
| `sort=votes` | `vote_score DESC, id DESC` | `(vote_score, id) < (:key, :id)` |
| `sort=title` | `title ASC, id ASC` | `(title, id) > (:key, :id)` |
| `sort=solutions` | `sol_count DESC, id DESC` | `(sol_count, id) < (:key, :id)` |
| `semantic=<text>` | `distance ASC, id ASC` | `(distance, id) > (:key, :id)` |

- **`solutions`:** `LEFT JOIN (SELECT problem_id, COUNT(*) c FROM solutions
  WHERE status='approved' AND deleted_at IS NULL GROUP BY problem_id) sc` → sortiere/keyset über
  `COALESCE(sc.c, 0)`. Ersetzt den heutigen separaten `/solutions/counts`-Lookup für die Sortierung.
- **`semantic`:** `ORDER BY embedding <=> (:emb)::vector`. Distanz ist berechnet → im WHERE
  wiederholen: `WHERE (embedding <=> (:emb)::vector, id) > (:dist, :id)`. **Keine** Threshold-Filterung
  (alle approved Probleme nach Distanz sortiert → voll durchblätterbar). asyncpg-Klammer-Gotcha:
  `(:emb)::vector` immer geklammert.
- **Keyword (`q`) — cross-lingual:** ODER-Verknüpfung dreier Quellen, damit die Suche
  multilingual wird:
  1. **rohe** Query gegen `original_translations::text` (Originalsprache der Einreichung, exakt),
  2. **rohe** Query gegen `title`/`description` (EN-Canonical, für EN-Eingaben exakt),
  3. **EN-übersetzte** Query gegen `title`/`description` (cross-lingual: DE-Query findet ein
     englisch eingereichtes Problem).
  Die EN-Übersetzung der Query holt das Backend einmal vom ai-service (`to_english`) — geteilt mit
  der Embedding-Beschaffung des semantic-Modus, kein separater Call. Nutzt den gewählten `sort`.
  **Bekannte Limitierung (bewusst akzeptiert):** Quelle 3 ist unscharf bei Übersetzungsvarianten
  („schlecht"→„bad" matcht „Poor data quality" nicht). Gleichsprachige Treffer (Quelle 1/2) sind
  exakt; den unscharfen Cross-Language-Fall fängt der semantische Modus robust ab. Das war die
  ursprüngliche Diagnose-Schwäche der Query-Übersetzung — sie bleibt im reinen Keyword-Modus.

**`total`:** separate `COUNT(*)`-Query mit **denselben** Filtern (ohne cursor/limit/order).
Für „N Treffer" und die Virtualizer-Scrollhöhe.

**Query-Normalisierung beim ersten Such-Call (cursor=null):** Das Backend holt sich einmalig vom
ai-service (a) die **EN-Übersetzung** der Query (`to_english`) — für die cross-linguale
Keyword-Quelle 3 — und (b) im `semantic`-Modus zusätzlich das **Embedding**. Beides wandert in den
`next_cursor`, Folge-Calls lesen es zurück → genau ein ai-service-Roundtrip pro Suchstart, egal ob
Keyword- oder Semantic-Modus. (Vorhandene ai-service-Endpunkte für `to_english` und Embedding in
Phase 1 verifizieren; ggf. `/internal/*`-Route ergänzen.)

### Graph-Aggregat-Endpoint (Phase 2): `GET /problems/cluster-summary`

```
GET /problems/cluster-summary
→ { "max_vote_score": int,
    "clusters": [ { "tag_id": str, "problem_count": int } ],  # echte Subtree-Counts
    "unclustered_count": int }
```
- `max_vote_score`: `MAX(vote_score)` über alle approved Probleme (Graph-Node-Sizing).
- `problem_count` pro Cluster: Count über den Tag-Subtree (serverseitig, korrekt unabhängig vom
  Client-Ladezustand).
- `unclustered_count`: approved Probleme ohne strukturellen Tag.

Der Graph-Drill-Down (Problem-Nodes eines Clusters) nutzt **denselben** paginierten
`GET /problems?tags=<cluster>&...`.

### Übergangspfad (Phase 1): `GET /problems/all`

Solange der Graph in Phase 1 noch vollständig lädt, bleibt ein expliziter Vollständig-Endpoint
`GET /problems/all` (entspricht dem heutigen `list_problems`, mit vernünftigem Hard-Cap, nur
`status=approved`). Wird in **Phase 2** entfernt, sobald der Graph auf `cluster-summary` +
Drill-Down umgestellt ist.

---

## Frontend-Datenfluss

### `useProblems` → Cursor-Store

Heute: `fetchProblems()` ersetzt `problems.value` mit allem. Neu:
```ts
problems            // akkumulierte geladene Seiten (NICHT mehr "alle")
total               // Gesamttreffer (Server)
nextCursor          // null = Ende
loading, hasMore
loadFirstPage(params: ProblemQuery)  // reset + erste Seite (Filter/Sort/Such-Wechsel)
loadNextPage()                        // hängt nächste Seite an (Scroll-Ende)
fetchProblemById(id)                  // bleibt (Detail-Panel, Drill-Down-Klick)
```
- **Race-Guard:** monoton steigende `requestVersion` (wie `useSemanticSearch`) — späte Antworten
  eines überholten `loadFirstPage` werden verworfen.
- `problems.value` bedeutet ab jetzt „aktuell geladen". Alle Konsumenten, die Vollständigkeit
  annahmen (siehe „Betroffene Stellen"), werden angepasst oder auf Server-Werte umgestellt.

### Table-View (Phase 1) — `pages/table.vue`

- Filter/Sort/Such-Refs → ein `watch` → `loadFirstPage(params)` (Reset auf Top). Suche debounced.
- Scroll nähert sich dem Ende (Virtualizer-Sentinel) → `loadNextPage()`.
- Virtualizer-`count` = `total`; gerenderte Rows = geladene Items.
- „**N von M**": `items.length` von `total`.
- **Entfällt:** `filteredProblems`-Computed, `matchesQuery`, `adminSearchIds`,
  `localizedTitles`-als-Suchindex, der `[locale, problems]`-Übersetzungs-Watcher als Suchquelle
  (Titel-Spalten-Anzeige ggf. über `originalTranslations[locale]` aus dem geladenen Objekt statt
  per `/translate`-Call — Skalierungs-Quick-Win).
- **`pages/admin/moderation.vue`:** nutzt denselben Endpoint mit `status=pending|rejected` statt
  client-seitigem Status-Filter über `problems.value`.

### Graph (Phase 2) — `pages/index.vue` + `components/ProblemGraph.vue`

- **Übersicht:** `cluster-summary` liefert Cluster-Counts + `max_vote_score`. Der Graph rendert
  Cluster-Nodes + Counts; **keine** einzelnen Problem-Nodes auf oberster Ebene.
- **Drill-Down:** Klick/Zoom in einen Cluster → `loadFirstPage({tags:[clusterTagId]})` lädt dessen
  Problem-Nodes lazy (bei sehr großen Clustern dort ebenfalls Infinite-Scroll/Mehr-laden).
- `ProblemGraph.vue` bekommt `maxVoteScore`, Cluster-Counts, Unclustered-Count als **Props** vom
  Aggregat statt sie aus `props.problems` zu berechnen (heute Zeilen 262/286/77/1085).
- `problemTags`-Junction-Edges (heute `realTags.ts:38` aus dem Voll-Array) werden für den
  Drill-Down-Cluster aus den geladenen Problemen abgeleitet.
- `GET /problems/all` wird entfernt.

### Echtzeit-Reconciliation (Phase 3)

- **vote/update/delete** (`useBackendRealtime`): find-by-id in `problems.value`, in-place
  anwenden, wenn geladen; sonst ignorieren (nicht sichtbar). Wie heute, nur ohne Voll-Re-Fetch.
- **`problem.created`** → `newSinceLoad++` → **„N neue Probleme"-Banner** oben. Klick →
  `loadFirstPage()` (frisch von oben). Ersetzt das heutige `fetchProblems()`-Komplett-Refetch.
- **`clustering.completed`** → `cluster-summary` neu laden (Graph) + aktuelle Liste refreshen.

---

## Betroffene Stellen (aus App-Audit)

| Datei:Stelle | heutige Vollständigkeits-Annahme | Phase |
|---|---|---|
| `backend/routers/problems.py:166` `list_problems` | kein Limit | 1 (Umbau) |
| `frontend/composables/data/real/realProblems.ts:72` `fetchProblems` | ersetzt ganzes Array | 1 |
| `frontend/pages/table.vue:128` `filteredProblems` | filtert Voll-Array | 1 (entfällt) |
| `table.vue:390` „N von M" | `problems.length` = Total | 1 |
| `table.vue:241` Virtualizer `count` | = geladene Länge | 1 |
| `frontend/pages/admin/moderation.vue:97` Status-Queues | filtert Voll-Array | 1 |
| `frontend/pages/index.vue:111` `filteredProblems` | filtert Voll-Array | 2 |
| `index.vue:81` `isEmpty` | `problems.length===0` | 2 (→ `total===0`) |
| `ProblemGraph.vue:262` `maxVoteScore` | aus Voll-Array | 2 (→ Prop) |
| `ProblemGraph.vue:286` Cluster-Counts | aus Voll-Array | 2 (→ Aggregat) |
| `ProblemGraph.vue:77` Unclustered | aus Voll-Array | 2 (→ Aggregat) |
| `realTags.ts:38` `problemTags` | aus Voll-Array | 2 |
| `useBackendRealtime`/`index.vue:227` `onProblemCreated` | Voll-Re-Fetch | 3 (→ Banner) |

---

## Tests

**Backend (pytest):**
- Cursor encode/decode roundtrip; Validierung (Sort-Modus muss zum Request passen).
- Keyset pro Sort-Modus (created/votes/title/solutions/semantic): zweite Seite schließt lückenlos
  an, keine Duplikate, keine Auslassungen.
- Filter-Kombination: tags-Subtree-Expansion, regions-OR, user, company-JOIN, AND-Verknüpfung.
- `total` konsistent mit Filtern (== Summe aller Seiten).
- Cursor-Stabilität: Insert/Delete zwischen Seite 1 und 2 dupliziert/überspringt nichts.
- Semantic: Embedding im Cursor, stabile Distanz-Reihenfolge; `(:emb)::vector`-Klammern.
- `cluster-summary`: Counts == echte Subtree-Counts; `max_vote_score`; `unclustered_count`.
- SQLite-Testdb-Kompatibilität beachten (JSONB-Variant-Gotcha; ggf. Keyset-SQL portabel halten
  oder Postgres-spezifische Tests markieren).

**Frontend (Vitest):**
- Pure Infinite-Scroll-Logik als testbares Composable/Helper: akkumulieren, `hasMore`, Reset bei
  Filterwechsel, Race-Guard (späte Antwort verworfen).
- „N neue"-Banner-Zählerlogik.
- Page-Komponenten selbst via E2E (kein Page-Mount-Harness im Projekt — bewusst).

**E2E (Playwright):**
- Scrollen lädt nächste Seite nach (Items wachsen, `total` stabil).
- Filter-/Sortwechsel resettet auf Top.
- Server-Suche (DE-Substring findet Problem mit deutschem Original).
- „N neue"-Banner erscheint bei WS-`problem.created` und lädt von oben.

---

## Phasen (Liefergrenzen)

**Phase 1 — Backend paginierte API + Table Infinite-Scroll**
- Backend: `GET /problems` Cursor-Pagination + alle Filter/Sort/Suche; `total`; `GET /problems/all`
  (Übergang); Embedding-Beschaffung für `semantic`.
- Frontend: `useProblems` Cursor-Store; `table.vue` Infinite-Scroll + Server-Filter/Sort/Suche;
  `admin/moderation.vue` server-status; client-Filter/`matchesQuery` raus.
- Graph bleibt unverändert (lädt via `/problems/all`). Temporär inkonsistent, aber lauffähig.
- **Liefert:** „nicht-geladene Daten finden" für Table+Suche; Skalierung der Table.

**Phase 2 — Graph-Drill-Down**
- Backend: `GET /problems/cluster-summary`.
- Frontend: Graph-Übersicht aus Aggregat (Cluster + Counts + max-score als Props); Drill-Down
  lazy pro Cluster; `index.vue`-Voll-Array-Abhängigkeiten entfernt; `/problems/all` entfernt.
- **Liefert:** Skalierung des Graphen; „lade alles" vollständig eliminiert.

**Phase 3 — Echtzeit-Banner + Politur**
- „N neue"-Banner; WS-Reconciliation an Pagination angepasst; `clustering.completed`-Refresh;
  Counts/Stats final; E2E.
- **Liefert:** Lebendige Live-Landkarte unter Pagination.

## Offene Annahmen (Default, widersprechbar)
- Page-Size 50, Hard-Cap 100.
- `regions`: OR innerhalb; `tags`: AND zwischen mehreren (wie heute).
- Graph-Drill-Down: pro Cluster Infinite-Scroll bei sehr großen Clustern.
- ai-service stellt dem Backend `to_english(query)` (für cross-linguale Keyword-Quelle 3) UND
  Query-Embedding (für `semantic`) bereit (vorhandene Pfade in Phase 1 verifizieren; ggf.
  `/internal/*`-Route ergänzen). Beides wird beim ersten Such-Call einmal geholt und im Cursor
  transportiert.
