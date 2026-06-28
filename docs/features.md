# Feature-Spezifikationen

## Inhalt

- [Ahnlichkeitserkennung](#ahnlichkeitserkennung)
- [Sprachunabhangige Suche](#sprachunabhangige-suche)
- [Bot-Erkennung](#bot-erkennung)
- [Echtzeit-Updates (WebSocket)](#echtzeit-updates-websocket)
- [Internationalisierung (i18n)](#internationalisierung-i18n)
- [Markdown in Losungen](#markdown-in-losungen)
- [Ubersetzung](#ubersetzung)
- [Tagging und Regionen](#tagging-und-regionen)
- [Editieren von Eintragen](#editieren-von-eintragen)
- [KI-generierte Losungsansatze](#ki-generierte-losungsansatze)
- [Theme-System](#theme-system)
- [Permalink-System](#permalink-system)
- [Authentifizierung](#authentifizierung)
- [Admin-Moderations-Queue](#admin-moderations-queue)
- [Virtuelles Scrollen (Table-View)](#virtuelles-scrollen-table-view)

---

## Ahnlichkeitserkennung

Verhindert Duplikate bevor sie in die Moderations-Queue gelangen.

### Ablauf

```
User tippt Titel oder Beschreibung
      ↓
Live-Check feuert auf beide Felder; gesendet wird description.trim() || title
(spiegelt die Server-Embedding-Quelle _embedding_text: Beschreibung, Titel als Fallback)
      ↓
Debounce 600ms
      ↓
Frontend schickt Text an /similarity Endpunkt
      ↓
TranslationService.to_english() — nicht-englischer Input wird übersetzt
(langdetect: englischer Text wird direkt durchgereicht, kein LLM-Call)
      ↓
KI-Service generiert temporares Embedding (kein DB-Insert)
      ↓
pgvector Cosine-Similarity gegen alle approved problems
(gespeicherte Embeddings basieren auf description_en — Sprachnormalisierung verhindert DE/EN-Vektor-Mismatch)
      ↓
Treffer (Score > 0.85) → ahnliche Probleme werden angezeigt
Kein Treffer → kein Hinweis, Submission lauft normal
      ↓
Bei Treffer: Submission blockiert bis User bestatigt
"Dieses Problem ist trotzdem neu / anders"
```

### Live-Check-Quelle = Server-Embedding-Quelle

`ProblemForm.vue` `watch([title, description])` füttert `checkSimilarity` mit
`description.value.trim() || title.value` — exakt der Text, den das Backend für das
Embedding nutzt (`_embedding_text`: Beschreibung, Titel als Fallback). Ohne diesen Gleichlauf
zeigt ein eindeutiger Titel mit Duplikat-Beschreibung **keine** Live-Warnung, läuft beim Submit
aber in den Duplikat-Pfad → stiller `needs_review`/Auto-Reject statt bewusstem „Trotzdem
einreichen". **Residuale Limitierung:** Der Live-Check embedded den Rohtext (ggf. Deutsch),
der Submit-Hook das kanonische Englisch (nach Übersetzung) — bei nicht-englischer Eingabe können
Live-Hinweis und Server-Verdikt also weiterhin leicht abweichen (vgl. Embedding-Sprach-Mismatch,
Threshold 0.85). Separates, vorbestehendes Thema — getrackt in
[decmap_project#27](https://github.com/MikeMitterer/decmap_project/issues/27).

### Schwellenwert

| Score | Bedeutung |
|---|---|
| > 0.92 | Sehr wahrscheinlich Duplikat |
| 0.85 – 0.92 | Ahnlich — Hinweis mit Link zum bestehenden Problem |
| < 0.85 | Kein Hinweis |

Konfigurierbar uber `SIMILARITY_THRESHOLD` (default: 0.85).

### API-Endpunkt

```python
@router.post("/similarity")
async def check_similarity(payload: SimilarityPayload) -> SimilarityResult:
    """Ahnliche Probleme fur den eingegebenen Text finden. Kein DB-Insert, kein Auth."""
    return await similarity_service.find_similar(payload.text)
```

```python
class SimilarityPayload(BaseModel):
    text: str = Field(min_length=5, max_length=200)

class SimilarProblem(BaseModel):
    id: str
    title: str
    score: float

class SimilarityResult(BaseModel):
    similar_problems: list[SimilarProblem]
    has_duplicates: bool   # True wenn Score > 0.92
```

### pgvector Query

```sql
SELECT id, title, 1 - (embedding <=> %s::vector) AS score
FROM problems
WHERE status = 'approved'
  AND 1 - (embedding <=> %s::vector) > %s
ORDER BY score DESC
LIMIT 5;
```

### Frontend — Debounce in Composable

```typescript
export function useSimilarity() {
  const similarProblems = ref<SimilarProblem[]>([])
  const hasDuplicates = ref<boolean>(false)
  const isChecking = ref<boolean>(false)
  let debounceTimer: ReturnType<typeof setTimeout>

  function checkSimilarity(text: string): void {
    clearTimeout(debounceTimer)
    if (text.length < 10) { similarProblems.value = []; return }
    debounceTimer = setTimeout(async () => {
      isChecking.value = true
      const result = await similarityApi.check(text)
      similarProblems.value = result.similarProblems
      hasDuplicates.value = result.hasDuplicates
      isChecking.value = false
    }, 600)
  }

  return { similarProblems, hasDuplicates, isChecking, checkSimilarity }
}
```

[↑ Inhalt](#inhalt)

---

## Sprachunabhangige Suche

Die Stichwort-Suche findet ein Problem unabhaengig von der UI-Sprache — ein deutscher Substring (`"schlecht"`) findet ein Problem mit deutschem Originaltitel, obwohl der englische Canonical (`"Poor Data Quality"`) ihn nicht enthaelt. Zwei unabhaengige Pfade decken das ab:

**Backend — `GET /internal/problems/search`** akzeptiert neben `q` einen optionalen `q_raw`-Parameter:

| Param | Quelle | ILIKE-Ziel |
|---|---|---|
| `q` | uebersetzte (englische) Query | `title` / `description` (englischer Canonical) |
| `q_raw` | rohe (untuebersetzte) Query des Users | `original_translations::text` (gespeicherter Originaltext, JSONB) |

Fehlt `q_raw`, wird `q` fuer beide Klauseln verwendet — keine Regression. Der AI-Service reicht die rohe Query unveraendert als `q_raw` durch; semantische Suche (Query→EN→Embedding→pgvector) bleibt unveraendert.

**Cross-linguale Symmetrie (Option B — [decmap_project#32](https://github.com/MikeMitterer/decmap_project/issues/32), BE `45c419f` → FTS `8982048`):** Der Keyword-Pfad nutzt seit BE `8982048` (F2 Task 3) **Postgres-Volltextsuche** (FTS) statt ILIKE-Substring: pro Sprache (`en`/`de`) matchen **rohe Query und übersetzte Variante** gegen den Sprach-`to_tsvector` via `@@ plainto_tsquery` (funktionaler GIN-Index, Migration 010). Die Query wird beim ersten Such-Call **in beide Sprachen** uebersetzt — das generische `translate_query(text, lang)` (ai-client) holt `q_en` **und** `q_de` vom ai-service. Per-Sprache-**Stemming** macht die Treffermenge flexions-symmetrisch: `q=missing` und `q=fehlend` liefern dieselbe Treffermenge (Unit-Test `test_fts_stemming_symmetry_english_plural` — beweist konkret `company`/`companies`-Stemming + `company`⇄`Unternehmen`-Symmetrie mit gestubbter Uebersetzung), und — anders als beim frueheren ILIKE-Substring — matchen jetzt **flektierte Formen** ueber den Stamm: das Per-Sprache-Stemming vereinheitlicht **Deklinations-/Pluralformen** (`company`/`companies` → `compani`; deutsche Partizip-Deklinationen `Fehlender`/`fehlende`/`fehlend` → `fehlend`). **Grenze (PG16 german snowball):** finite Verbformen werden **nicht** mit dem Partizip vereinheitlicht — `fehlt` → `fehlt` ≠ `fehlend` → `fehlend`; die frueher dokumentierte flexions-abhaengige Restdifferenz ist damit **deutlich reduziert, aber nicht restlos** behoben. Die cross-linguale `missing`⇄`fehlend`-Symmetrie entsteht primaer aus der **Uebersetzung** (q_de=`fehlend`) plus Stemming, nicht aus Stemming allein. Der rohe `q` matcht zusaetzlich gegen **jede** Sprach-Config — uebersetzungs-ausfall-sicher. **Translate-once-pro-Sprache:** Beide Uebersetzungen werden nur auf Seite 1 geholt (max. **zwei** Roundtrips) und reisen im Cursor mit (N-sprachige Übersetzungs-Map unter Key `qt`; BE `4d6279d`, zuvor fixes `q2`=DE); Folgeseiten uebersetzen nicht erneut, und Pre-`qt`-Cursor degradieren ueber `peek_cursor_translations` sauber zu `None` — kein Backwards-Compat-Bruch. Single Source of Truth der Sprachen: `services/search_languages.py` (`SEARCH_LANGUAGES` + `tsvector_sql`, byte-identisch in Index und Query). **Verbleibende Grenze (kein Bug):** Echte Synonyme (lack/missing/absent) matchen weiterhin nicht gegenseitig — Stemming ≠ Synonym-Expansion; fuer konzept-/synonym-gleiche Treffer bleibt die **semantische Suche** (`semantic=`, s.u.) das richtige Werkzeug.

> **F2 (2026-06-28 — Keyword-FTS + Relevanz-Ranking gelandet, BE Tasks 1–4):** Die registry-getriebene **Postgres-Volltextsuche** (`to_tsvector`/`plainto_tsquery`, Per-Sprache-Stemming, funktionale GIN-Indizes) **ersetzt ILIKE** im `q`-Keyword-Pfad und **reduziert** die flexions-abhaengige Restdifferenz deutlich (Deklinations-/Pluralformen werden ueber den Stamm vereinheitlicht; finite Verbformen wie `fehlt` bleiben unter PG16 german snowball distinkt vom Partizip `fehlend`). **Task 1 (BE `b7563e9`):** Sprach-Registry `services/search_languages.py` (`SEARCH_LANGUAGES` + `tsvector_sql`) als Single Source of Truth + Migration 010 mit funktionalen GIN-Indizes `ix_problems_fts_en` / `ix_problems_fts_de` (en/de, immutable Sprach-Snapshot). **Task 2 (BE `4d6279d`):** Cursor-`q_translations`-Map (N-sprachfaehig). **Task 3 (BE `8982048`):** ILIKE→FTS im Query-Pfad. **Task 4 (BE `59a2b29`):** opt-in Relevanz-Ranking `sort=relevance` (Σ `ts_rank` über die Registry-Sprachen, `ORDER BY rank DESC` + Keyset `(rank, id)`, Cursor traegt `rank` + `q_translations`; ohne `q` Fallback auf `created`; [#37](https://github.com/MikeMitterer/decmap_project/issues/37)). **Task 5 (FE `d3a6950`):** Frontend-`sort=relevance`-Opt-in — ein „Sort by relevance"-Toggle (`table.sortByRelevance`) in der `DmTopBar`-Suchleiste, nur sichtbar bei aktiver **Keyword**-Suche (Suchbegriff vorhanden, KI-Suche aus); `keywordRelevanceEnabled` schaltet `query.sort = 'relevance'` (`dir` entfällt) und erweitert `relevanceSortActive` (s.u.), sodass StatusBar-Hinweis + Sort-Header-Sperre auch im Keyword-Modus greifen. **Task 6 (BE `820083e`):** Extensibility-Smoke-Test `test_third_language_needs_only_registry_and_index` (patcht `SEARCH_LANGUAGES` um `fr`, legt den funktionalen `fr`-Index zur Laufzeit an, beweist: 3. Sprache = Registry-Eintrag + Index, **kein** Code-Change im WHERE/Ranking) + diese Doku. FTS ist seit der Test-DB-Umstellung auf Postgres (Konventionen Fund 40) ohne `skipif` testbar. Design: [`docs/specs/2026-06-27-f2-cross-lingual-search-design.md`](specs/2026-06-27-f2-cross-lingual-search-design.md), Plan: [`docs/plans/2026-06-27-f2-cross-lingual-search.md`](plans/2026-06-27-f2-cross-lingual-search.md).

**Frontend — Local-Match:** `utils/problemSearch.ts` matcht die Suchquery sofort gegen den **angezeigten** (lokalisierten) Titel der bereits geladenen Nodes — „tippe was du siehst" ohne Backend-Roundtrip. Seit Server-Driven Search Phase 1 (s.u.) nur noch im **Graph** (`pages/index.vue`, F2); `pages/table.vue` sucht jetzt server-seitig (`GET /problems?q=`) und hat den Client-Local-Match entfernt.

### Datenmodell & Skalierung (Stand 2026-06-25 — Server-Driven Search Phase 1 + Phase 2 Drill-Down)

**Table + Suche sind server-paginiert.** `GET /problems` liefert seit Phase 1 eine **Keyset-paginierte Seite** statt des kompletten Sets: `{ items, next_cursor, total }`, `limit` default 50 (Hard-Cap 100), zustandsloser base64-Cursor. Parameter:

- `sort` — `created` (default) / `votes` / `title` / `solutions` / `status` / `tag` / `relevance` (Keyset pro Modus). `relevance` ist opt-in und greift nur mit `q` (Σ `ts_rank` über die Registry-Sprachen, `ORDER BY rank DESC` + Keyset auf `(rank, id)`; ohne `q` Fallback auf `created`; BE `59a2b29`, F2 Task 4). `tag` sortiert nach dem Struktur-/Cluster-Tag-Namen (MIN über `tags.level<10`, `''`-Bucket für unclustered); `status` über `(status, id)` — analog `title`; ohne diesen Modus fiel `sort=status` auf `created` zurück, sodass die Table auf Seite 1 gruppiert wirkte, beim Infinite-Scroll aber wieder gemischte Status nachlud.
- `dir` — `asc` | `desc`, server-seitig für **jeden** Sort-Modus wirksam (seit BE `440cb3e`/FE `37cff86`). Fehlt `dir`, gilt der Default je Modus (`created`/`votes`/`solutions` desc, `title`/`status`/`tag` asc); ungültiger Wert → 422. Die effektive Richtung reist im **Cursor** mit (kompakter Key `d`): auf Seite 2+ gewinnt die Cursor-Richtung, `dir` wird ignoriert → die Ordnung bleibt über alle Infinite-Scroll-Seiten konsistent. Der `id`-Tiebreaker folgt immer der Primärrichtung, damit der Keyset-Vergleich korrekt bleibt.
- `q` — cross-lingualer **Keyword**-Modus: **Postgres-FTS** (OR-kombiniert) — pro Sprache (`en`/`de`) matchen **rohe Query und übersetzte Variante** gegen den Sprach-`to_tsvector` via `@@ plainto_tsquery` (funktionaler GIN-Index, Migration 010; ersetzt das frühere ILIKE, BE `8982048`, #32). Per-Sprache-**Stemming** vereinheitlicht Deklinations-/Pluralformen ueber den Stamm (`company`/`companies`, deutsche Partizip-Deklinationen `fehlende`/`fehlend`) — finite Verbformen (`fehlt`) bleiben unter PG16 german snowball distinkt; cross-linguale Symmetrie kommt aus Uebersetzung + Stemming. Die Query-Übersetzung holt das Backend beim ersten Such-Call (cursor=null) **je einmal pro Sprache** vom ai-service (max. zwei Roundtrips) und reicht sie über den Cursor an Folgeseiten weiter (N-sprachige Übersetzungs-Map unter Cursor-Key `qt`; BE `4d6279d`, zuvor fixes `q2`=DE); Details s.o. „Sprachunabhangige Suche".
- `semantic` — **Embedding-Distanz**-Ranking; ignoriert `sort`, ist **exklusiv** zu `q`. Das Query-Embedding holt das Backend einmal via `POST /embeddings/internal/embed-query` und transportiert es zustandslos im Cursor.
- Server-Filter `tags` (Subtree-expandiert, AND), `regions` (OR), `user` (komma-separiert → `IN`), `company` (komma-separiert → case-insensitive ILIKE-OR, zu User-IDs aufgelöst); `status_filter` (default `approved`; `all` = keine Status-Einschränkung; jeder Nicht-`approved`-Wert inkl. `all` → Superuser). `all` greift im Keyword- **und** Semantik-Pfad (geteiltes `base_where`).

`pages/table.vue` ist Infinite-Scroll auf Basis von `useProblems` als **Cursor-Store** (`loadFirstPage`/`loadNextPage`, Race-Guard via `requestVersion`); „N von M" = geladene Items von `total`. Die früheren Client-Filter (`filteredProblems`/`matchesQuery`/`adminSearchIds`/`localizedTitles`-als-Suchindex) sind entfernt; die Titel-Spalte zieht den lokalisierten Titel direkt aus `originalTranslations[locale]?.title` des geladenen Objekts — kein `/translate`-Call pro Problem mehr (der frühere teuerste Posten). `admin/moderation.vue` nutzt denselben Endpoint mit `status_filter=pending|rejected` statt Client-Status-Filter. In der Table sendet ein **Admin** explizit `status_filter=all` (sieht alle Status: approved/pending/rejected/needs_review), ein normaler User `approved` — das Auslassen des Parameters defaultet server-seitig auf `approved`, was den Admin sonst nur approved sehen ließe (Phase-1-Regression, behoben 2026-06-24). Einen UI-Status-Wähler gibt es nicht; der Admin sieht per Default alles. Die **Status-Spalte** mappt auf `sort=status` und ist damit über **alle** Infinite-Scroll-Seiten konsistent gruppiert (BE `934fbf5`, FE `711f5eb`); die **Tag-Spalte** sortiert seit BE `440cb3e`/FE `37cff86` server-seitig über `sort=tag` (Struktur-/Cluster-Tag-Name) statt des früheren `created`-Fallbacks — die „auf Seite 1 sortiert, danach gemischt"-Illusion ist damit behoben. Auch der **Sort-Richtungs-Toggle** ist seit denselben Commits server-seitig wirksam: die Table sendet `sortDirection` als `dir`, der Pfeil ↑/↓ kehrt die Ordnung über alle Seiten konsistent um (Richtung reist im Cursor; vorher ein dokumentierter No-op). **Multi-Value-Filter (BE `30487a1` / FE `bde9361`, #35):** `user`/`company` akzeptieren komma-separierte Mehrfachwerte — `user` als `IN`, `company` als case-insensitive ILIKE-OR (zu User-IDs aufgelöst); die Table sendet alle gewählten Werte (`userFilterIds`/`companyFilters` `.join(',')`), nicht mehr nur den ersten. **Company-Filter (FE `fc68cf6` → Revert `ebb759f`, #29):** Das Firmen-Filtern ist über das violette Firmen-Chip im Problem-Panel (emittiert den exakten Voll-Namen), den `?company=`-URL-Parameter und die aktiven Firmen-Filter-Chips in der Tabelle (je mit × entfernbar) erreichbar. Ein stets sichtbares Freitext-Eingabefeld über der Chip-Leiste wurde in `fc68cf6` eingeführt und in `ebb759f` wieder **entfernt** (samt toter i18n-Keys `companyFilter`/`companyFilterPlaceholder`). **Live-Verify-Erkenntnis (2026-06-27, F1):** `User.company.ilike(n)` matcht den **ganzen** Wert ohne Wildcards — eine Teil-Eingabe (`Acme`) trifft die Seed-Firma `Acme Manufacturing GmbH` **nicht** (0 Treffer); nur der exakte, vollstaendige Firmenname (oder der Panel-Chip, der ihn emittiert) filtert. Für ein **Freitext**-Feld widerspricht das der Nutzererwartung — daher der Revert statt eines Substring-Patches (`%n%` in `_build_filter_clauses` wäre ein Ein-Zeilen-Patch, bewusst offen gelassen). Der Firmenname ist zusätzlich ein **optionales Feld bei der Registrierung** (`pages/login.vue` Register-Tab → `company` im Register-Call, `autocomplete="organization"`) und bleibt ein editierbares Profil-Feld in den Settings (`pages/settings.vue`). Der `user`-Filter hat weiterhin nur den Chip-Einstieg (kein eigenes Eingabefeld). **Panel-Chip-Klarheit (FE `25ffffb`, #30):** Autor- und Firmen-Chip im Problem-Panel (`ProblemPanel.vue`, emittieren `user-filter`/`company-filter`) tragen je ein 👤/🏢-Icon plus `aria-label`/`title`-Tooltip (`panel.filterByAuthor`/`panel.filterByCompany`), damit sie unterscheidbar sind; die Smaragd/Violett-Farbgebung bleibt unverändert (die im Ticket angedachte sekundäre theme-konforme Farbe wurde descoped). Der **Semantik-Modus liefert seit BE `9f61d27` (#28) den Treffer-Score mit** — `_list_problems_semantic` setzt `ProblemRead.score = 1 − Distanz` pro Item, **auf [0,1] geklemmt** (Cosine-Distanz reicht bis 2 — ungeklemmt würde der Match-Score negativ; BE `6aa33e5`, #28 Review). Im Keyword-/Default-Modus `None`; Cursor-Contract unverändert. Der **Frontend-Data-Layer mappt den `score` inzwischen auf den `Problem`-Typ** (`mapProblem` in `data/real/realProblems.ts`, `score?: number`; `undefined` wenn das Backend keinen liefert). Die **UI-Affordanz ist seit FE `868a6bb` (#28) umgesetzt** und hängt seit FE `d0981ab` an `relevanceSortActive` statt am bloßen KI-Toggle. Seit FE `d3a6950` (F2 Task 5) deckt `relevanceSortActive` **beide** Relevanz-Pfade ab: `layouts/default.vue` definiert es als `semantic || keyword` — `semantic` = KI-Suche an **und** Suchbegriff vorhanden, `keyword` = KI-Suche **aus** + Suchbegriff + `keywordRelevanceEnabled`-Toggle — und `provide`-t es (samt `keywordRelevanceEnabled`) an Table und StatusBar. Den Keyword-Toggle exponiert die `DmTopBar` als „Sort by relevance"-Button (`table.sortByRelevance`), nur sichtbar bei `search.trim() && !aiSearch`; ein `watch([searchQuery, aiSearchEnabled])` resettet `keywordRelevanceEnabled` sobald das Suchfeld leert oder die KI-Suche eingeschaltet wird (kein hängender Relevanz-Zustand). Läuft eine Relevanz-Sortierung tatsächlich (= `relevanceSortActive`), deaktiviert `pages/table.vue` die Spalten-Sort-Header (`opacity-40 pointer-events-none` + Tooltip `table.relevanceTooltip`) und sendet im Keyword-Pfad `sort=relevance` (`dir` entfällt) statt des Spalten-Sorts. Das pro-Zeile-Match-Score-Badge (`table.matchScore`, `{n}% Übereinstimmung`, `Math.round(score × 100)`) rendert weiterhin **nur** wenn `score != null` — also im **Semantik**-Modus (das Backend liefert `score` nur dort; der Keyword-`ts_rank` wird nicht als `score` exponiert). KI-Suche an **bei leerem Suchfeld** → normale, voll sortierbare Liste ohne Sperre und Hinweis (die Semantik-Query selbst feuert weiterhin am Toggle, doch ohne Term gibt es keine Relevanz-Ordnung zu schützen). Der **„Sortiert nach Relevanz"-Hinweis (`table.sortedByRelevance`) sitzt seit FE `41a33f2` links unten in der StatusBar** (vorher als Banner über dem Table-Header): `StatusBar.vue` `inject`-t dasselbe `relevanceSortActive` und zeigt den Hinweis (Akzent-farbiges Label) nur dann — `v-if` entfernt ihn beim Aufheben komplett aus dem DOM, eine CSS-`@keyframes`-Animation lässt ihn beim Erscheinen 3× blinken (`prefers-reduced-motion: reduce` schaltet sie ab; das Remount via `v-if` spielt den Blink bei jedem Wieder-Einschalten neu). Die ausgegrauten Sort-Header bleiben als In-Table-Affordanz. Keyword-/Default-Modus unverändert (Badge und Hinweis aus); der opake Cursor-Contract bleibt unangetastet. Contract: `useProblemsPagination.spec.ts` deckt das `score`-Mapping ab (übernommen / `undefined` ohne Backend-Wert) und seit FE `d3a6950` die `sort=relevance`-Wire-Serialisierung (`loadFirstPage({ q, sort: 'relevance' })` → `sort=relevance` im Query-String).

**Der Graph drillt seit Phase 2 (Task 2.3, FE `5bf4a44`) auf das `cluster-summary`-Aggregat** statt alle Probleme zu laden: `pages/index.vue` lädt bei Mount nur `fetchClusterSummary()` (+ Tag-Hierarchie); ein Klick auf einen Cluster lädt dessen Problem-Zeilen lazy über den paginierten `GET /problems?tags=<id>` (`loadFirstPage` + Restseiten via `loadNextPage`), die Suche läuft server-seitig (`loadFirstPage({ q | semantic })`). Der client-seitige `filteredProblems`-Local-Match ist entfernt, `isEmpty` kommt aus dem Aggregat, und WS-Events (`problem.created`/`deleted`, `clustering.completed`) re-fetchen via `refreshOverview()` die `cluster-summary` statt des früheren Voll-Sets. Der Übergangs-Endpoint `GET /problems/all` (= `list_all_problems`, nur `approved`, Hard-Cap) und die Data-Layer-Methoden `fetchAllProblems()` + der `fetchProblems()`-Alias sind seit **Task 2.4** entfernt (BE `routers/problems.py`, FE `realProblems.ts`/`types.ts`) — der Graph lief schon vorher ausschließlich über das Aggregat + Drill-Down. **Phase 3** ersetzt den Re-Fetch bei `problem.created` durch ein „N neue Probleme"-Banner (noch offen). **Backend-seitig steht Phase 2 Task 2.1**: `GET /problems/cluster-summary` (BE `69dab26`) liefert das Aggregat — `max_vote_score`, pro Struktur-Tag (`level < 10`) den Subtree-`problem_count` und `unclustered_count` — ohne alle Problems zu laden; der Subtree-Count nutzt dasselbe portable BFS (`_subtree_tag_ids`) wie der `tags`-Filter (SQLite + Postgres). **Task 2.2** (FE `a378e85` + `42dffab`) ist erledigt: `ProblemGraph.vue` liest `maxVoteScore`, `clusterCounts` (`Map<tagId, count>`) und `unclusteredCount` aus **Props** statt sie aus `props.problems` zu berechnen — inkl. der Unclustered-Such-Badge (`42dffab`), die ihr Label jetzt aus `unclusteredCount` statt `unclustered.length` zieht. Vorbereitung für den Drill-Down, bei dem `props.problems` nur noch den gefilterten Cluster trägt (dann läge `unclustered.length` bei `0`, während die Prop den echten Aggregat-Wert trägt). **Task 2.3** (FE `5bf4a44`) ist erledigt: `pages/index.vue` ist auf `fetchClusterSummary()` + lazy Drill-Down umgestellt (s.o.) — `props.problems` trägt jetzt nur noch den gedrillten Cluster, `ProblemGraph` zieht alle Aggregat-Counts ausschließlich aus den Props. **Task 2.4** ist erledigt: `/problems/all` (Backend-Route + `fetchAllProblems`/`fetchProblems` im Data-Layer) und die verbliebenen Voll-Array-Reste sind entfernt — verbleibend nur noch das Phase-3-„N neue Probleme"-Banner (s.o.). Design + Phasen: [`docs/specs/2026-06-22-server-driven-search-pagination-design.md`](specs/2026-06-22-server-driven-search-pagination-design.md). **Overlap-Fix ([decmap_project#33](https://github.com/MikeMitterer/decmap_project/issues/33)):** Beim Drill-Down hängt `rerender()` in `ProblemGraph.vue` die neuen Nodes aus `buildGraphElements()` an, die ohne Position bei (0,0) starten — Cytoscape zeichnete einen gestapelten Frame, bevor das synchrone `preset`-Layout sie positionierte. Fix: Style-Update + `elements().remove()` + `add()` laufen jetzt in einem `cy.batch()`, das Rendering wird bis nach dem Layout zurückgehalten — kein Aufblitzen überlappender Nodes/Labels mehr.

### URL-adressierbare Tabellen-Filter ([decmap_project#31](https://github.com/MikeMitterer/decmap_project/issues/31), 2026-06-25)

Die Tabellen-Filter sind teil- und bookmarkbar: der Filter-/Sort-State spiegelt in die Query-Parameter der URL, ein geteilter Link stellt ihn beim Laden wieder her. Zentraler Baustein ist `composables/useTableFiltersUrl.ts` — eine **erweiterbare Param↔`ProblemQuery`-Map** (`FILTER_PARAM_MAP`): jeder Filter ist genau **ein Eintrag** (`sort`, `dir`, `q`, `semantic`, `tags`/`regions` als `array: true` komma-serialisiert, `user`, `company`, `status`), künftige Filter docken mit einer Zeile an.

- `parseRouteToQuery(route)` — URL → `ProblemQuery`; leere Strings werden ausgelassen, `q`/`semantic` sind **exklusiv** (`q` gewinnt).
- `queryToRouteParams(query)` — `ProblemQuery` → flacher Param-Record; `null`/leere Werte und leere Arrays raus, Arrays komma-gejoint (konsistent zum Backend-`split(',')`), `q`/`semantic` exklusiv.

`pages/table.vue` verdrahtet beide Richtungen:

- **URL → State (Mount-Hydration):** `onMounted` liest die Query und setzt `tagFilterIds`/`userFilterIds`/`companyFilters`/`sortKey`/`sortDirection`/`searchQuery`, danach **ein** expliziter `loadFirstPage(buildQuery())`.
- **State → URL:** ein eigener `watch([tagFilterIds, userFilterIds, companyFilters, sortKey, sortDirection])` schreibt via `router.replace({ query })` — **kein History-Eintrag**; ein `router.replace` mit identischen Params ist in Vue Router ein No-op, also keine Endlosschleife. `searchQuery` und `semanticSearchEnabled` sind hier **bewusst ausgeschlossen** — sie leben im Layout-Header und würden die URL sonst bei jedem Tastendruck (vor dem Debounce) überschreiben; hydratisiert wird `q` trotzdem, damit ein `?q=…`-Link das Suchfeld wiederherstellt.
- **`isHydrating`-Guard:** ein `ref(true)`, das die Daten-Lade- **und** die Auto-Select-Watches während der Hydration stummschaltet (sonst feuert ein zweiter `loadFirstPage` bzw. die Auto-Selektion mitten in der Ref-Befüllung). Der Guard wird im **`finally`** des Initial-Loads zurückgesetzt — würde ein fehlgeschlagener Load ihn auf `true` stehen lassen, bliebe die Tabelle dauerhaft tot (Review-Fix `bc57d45`). Vgl. Konventionen Fund 37.

Der `company`-Filter ist über das Panel-Chip, den `?company=`-URL-Parameter und die aktiven Tabellen-Chips erreichbar (das in `fc68cf6` ergänzte Freitext-Eingabefeld wurde in `ebb759f` wieder entfernt, #29); `user` bleibt chip-only. Beide sind seit BE `30487a1`/FE `bde9361` multi-value (komma-separiert, vgl. oben).

[↑ Inhalt](#inhalt)

---

## Bot-Erkennung

Mehrschichtiger Ansatz — kein CAPTCHA (UX-Killer).

### Schichten

```
Request kommt rein
      ↓
1. nginx — Rate Limiting (5r/m pro IP)
      ↓
2. DNSBL-Check (aiodnsbl) — bekannte Spam-IPs
      ↓
3. FastAPI Middleware — Verhaltens-Signale + Honeypot
      ↓
4. GPT Spam-Filter
```

### nginx Rate Limiting

```nginx
limit_req_zone $binary_remote_addr zone=submissions:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=translate:10m   rate=5r/m;

location /api/problems {
    limit_req zone=submissions burst=3 nodelay;
}

location /api/translate {
    limit_req zone=translate burst=2 nodelay;
}
```

### Verhaltens-Signale (FastAPI Middleware)

```python
class BotDetectionMiddleware:
    SUSPICIOUS_SIGNALS = [
        "submit_too_fast",        # < 10 Sekunden zwischen Seitenaufruf und Submit
        "session_flood",          # > 10 Submissions in 60 Minuten
        "ip_hash_multi_session",  # ip_hash in > 5 verschiedenen Sessions
        "missing_user_agent",
        "known_bot_agent",
        "honeypot_filled",
    ]
```

- 2+ Signale → automatisch `rejected`, kein GPT-Call
- 1 Signal → `needs_review` mit Flag im Moderations-Log

### Honeypot

```html
<input type="text" name="website" class="absolute -left-[9999px]"
  tabindex="-1" autocomplete="off" aria-hidden="true" />
```

```python
if payload.honeypot:
    return FilterResult(status=ProblemStatus.REJECTED, reason="honeypot")
```

Honeypot-Feld wird nie in der DB gespeichert — nur gepruft.

### Verifikationskriterien (LLM-Prompt)

Die konkreten Akzeptanz- und Ablehnungskriterien des KI-Spam-Filters sind in
[`docs/moderation-criteria.md`](moderation-criteria.md) definiert (SSoT).
Der `_SPAM_SYSTEM`-Prompt in `openai_provider.py` / `anthropic_provider.py` leitet sich
direkt daraus ab — Änderungen an den Kriterien erfordern synchrones Update beider Provider.

Zusammenhang mit Issue #19: `rejection_reason` wird erst sinnvoll befüllt,
wenn der Prompt konkrete Ablehnungsgründe kennt.

### Lösungsansätze (Solution Approaches)

Lösungsansätze werden **direkt per LLM evaluiert** — kein nginx/Middleware/Honeypot-Layer,
da der Einreichungsflow nach Login erfolgt. Prompt: `SOLUTION_SPAM_SYSTEM` in `prompts.py`.

Kriterien: [`docs/moderation-criteria.md → Solution Approaches`](moderation-criteria.md)  
Hook: `POST /hooks/solution-submitted` (vom Backend als BackgroundTask aufgerufen)

**Die KI ist das Moderations-Gate** (kein menschlicher Pflicht-Schritt). Der
`solution-submitted`-Hook entscheidet anhand des LLM-Spam-Filters und des globalen
Duplikat-Checks; `evaluate_solution` (ai-service) gibt direkt den Zielstatus zurück —
früher fälschlich `pending` für saubere Lösungen, die so dauerhaft hängen blieben:

| LLM-Verdikt | Status | `rejection_reason` |
|---|---|---|
| sauber **und** kein Duplikat | `approved` (sofort sichtbar, Embedding wird gespeichert) | — |
| bemängelt (`is_spam: true`) | `needs_review` (Admin-Queue) | LLM-Grund |
| Duplikat ohne `duplicate_confirmed` | `needs_review` | `possible_duplicate` |
| LLM-Fehler (Provider down) | `needs_review` (fail-safe) | `moderation_error` |

Nichts wird **automatisch hart abgelehnt**. Bei Approval feuert der Hook `SolutionApprovedEvent`
→ die Lösung erscheint live im UI.

### Lösungs-Duplikat-Check (global, live + Submit-Backstop)

Analog zur Problem-Similarity, aber über **alle** approved Solutions (nicht problem-scoped):

- **Frontend:** `useSolutionSimilarity` ruft `POST /api/solution-similarity` (debounced 600ms)
  und zeigt eine Live-Warnkarte im `SolutionForm`. „Trotzdem absenden" → `signals: ['duplicate_confirmed']`.
- **AI-Service:** `SolutionSimilarityService`, Public-Endpoint `POST /solution-similarity`
  (nginx-Rate-Limit 10/min — generischer `/api/`-Proxy, keine nginx-Änderung nötig). Im
  `solution-submitted`-Hook läuft der Check als Submit-Backstop und speichert bei Approval
  das Embedding (englischer Canonical via `embed_and_store`).
- **Backend:** `POST /internal/solutions/{id}/embedding` + `POST /internal/solutions/similarity`
  (globaler pgvector-Vergleich). Die `embedding`-Spalte wird erst bei Approval befüllt.

Score > `duplicate_threshold` ohne `duplicate_confirmed` → `needs_review`/`possible_duplicate`;
mit Bestätigung (authentifizierter User) → `approved`.

**Limitierung (Stand 2026-06-19):** Nur der Submit-Approval-Pfad speichert ein Embedding.
Admin-/`AUTO_APPROVE`-genehmigte sowie bereits bestehende Solutions haben noch keins und
werden daher nicht als Duplikat erkannt. Folge-Arbeit: Embedding auch bei Admin-Approval +
ein Solution-Bulk-Reindex (analog Problems).

### Bewusst weggelassen

- CAPTCHA, Browser-Fingerprinting, ML-basierte Bot-Detection

[↑ Inhalt](#inhalt)

---

## Echtzeit-Updates (WebSocket)

> **Grundanforderung:** Live-Updates im UI sind keine optionale Funktion.
> Wenn User A votet, sieht User B den aktualisierten Score sofort — ohne Page-Reload.
> Diese Funktionalität muss auch ohne AI-Service funktionieren.

CRUD uber REST. Ruckmeldungen an das UI uber zwei WebSocket-Quellen.

### Zwei WebSocket-Quellen

| Composable | WebSocket | Verantwortlich für |
|---|---|---|
| `useBackendRealtime.ts` | Backend `/ws` (Port 8001) | Mutations: Vote-Scores, Problem/Solution CRUD |
| `useRealtimeUpdates.ts` | AI-Service `/ws` | AI-Events: `problem.approved`, `clustering.started`, `clustering.completed` |

Vote-Score-Updates laufen **nicht** über den AI-Service — Basis-Funktionalität darf
nicht vom AI-Service abhängen.

### Vote-Score — Ablauf

```
User klickt Vote
      ↓
POST /votes  (FastAPI Backend, Port 8001)
      ↓
Backend berechnet neuen vote_score (Toggle-Logik, s.u.)
      ↓
Response enthält aktualisierten vote_score direkt — kein Re-Fetch nötig
      ↓  (Backend feuert WS-Event)
Backend WebSocket /ws → alle verbundenen Clients
      ↓
useBackendRealtime.ts → applyProblemUpdate(update) → UI aktualisiert
```

**Vote-Toggle-Semantik:** Gleiche Richtung wie vorhandenes Vote → zurückziehen (delta = -1). Entgegengesetzte Richtung → Flip (delta = ±2). Neues Vote → delta = ±1. `fakeVoting.ts` implementiert dieselbe Logik (Contract-Test in `useVoting.contract.spec.ts`).

Sofort-Feedback für den votenden User: `ProblemPanel.vue` aktualisiert den Score direkt aus dem Response-Body — zeigt echten DB-Wert ohne auf WS-Event zu warten.

**vote_score Floor (implementiert):** `vote_score = max(0, current_score - 1)` — kein negativer Score. Downvote auf Score 0 → bleibt 0, kein Vote-Row wird angelegt. Flip up→down bei Score 1 → fällt auf 0, nicht -1.

### AI-Service — Event-Typen

```typescript
type WebSocketEvent =
  | { type: 'problem.approved';     payload: { id: string; clusterId?: string | null } }
  | { type: 'problem.rejected';     payload: { id: string } }
  | { type: 'problem.deleted';      payload: { id: string } }
  | { type: 'clustering.started';   payload: { triggeredBy: string } }
  | { type: 'clustering.completed'; payload: { triggeredBy: string; clustersUpdated: number; assignedCount: number } }
  | { type: 'solution.approved';    payload: { id: string; problemId: string } }
  | { type: 'solution.deleted';     payload: { id: string; problemId: string } }
```

*`cluster.updated` entfernt — `clusters`-Tabelle gedroppt (Migration 005, 2026-05-22). `clustering.started`/`clustering.completed` ersetzen es: Frontend (`useClusteringStatus`) zeigt Spinner während Clustering läuft und re-fetcht Problems+Tags nach Completion. `clusterId` in `problem.approved` ist optional — Clustering-Output landet in `problem_tag` (L1–L9 Tags), nicht im Event-Payload.*

Events auf Entity-Ebene — Frontend entscheidet ob Re-fetch oder direktes State-Update.

### Backend WS — Scalar vs. Relationen

Backend WS-Events liefern Scalar-Felder des Problems. M2M-Relationen (`tags`, `regions`)
kommen nicht im Event-Payload. `applyProblemUpdate` unterscheidet daher zwei Fälle:

| Update-Typ | `edited_at` im WS-Event? | Strategie |
|---|---|---|
| Vote (`vote_score`) | nein | Scalar-Merge reicht (Score direkt übernehmen) |
| Edit (Titel, Tags, …) | **ja** | Scalar-Merge sofort + `fetchProblemById()` asynchron für aktuelle `tagIds`/`regionIds` |

Der Scalar-Merge verhindert Flackern; der REST-Nachlade bringt die vollständigen Relationen.
`ProblemGraph.vue` watcht `props.problems` deep — Graph rendert automatisch neu sobald
der State updated wird.

**Cytoscape.js Badge-Positionierung:** Badge-Mittelpunkt liegt an der Node-Ecke (halbe Badge
inside/outside) — das ist gewolltes Design, kein Bug. `positionSolutionBadge` und
`positionSearchBadges` nutzen `parent.width()/height()` für dynamische Offsets.

**Graph-View — Drag- und Viewport-Persistierung:** Nodes sind im Mindmap-Level frei
ziehbar; nach jedem `dragfree`-Event speichert `ProblemGraph.vue` die aktuellen Positionen
als JSON-Map (`{id: {x, y}}`) in `localStorage['graph-node-positions']`. Decoration-Badges
(`cluster-dot`, `cluster-count-badge`, `vote-score-badge`, `solution-badge`, `search-badge`)
folgen dem Parent live waehrend des Drags via `cy.on('position', '<parent-selector>', ...)`.
Zusaetzlich speichert `cy.on('viewport', ...)` Zoom und Pan mit 400ms-Debounce in
`graph-viewport-mindmap` (nur im Mindmap-Level — Drill-Views ueberschreiben den globalen
Viewport nicht). `centerOnRoot()` stellt beim Mount den gespeicherten Viewport wieder her,
sonst Default-Zoom 1 mit Root zentriert (kein `fit` beim ersten Layout). Reset-Button neben
den Zoom-Controls (i18n `graph.resetPositions`) loescht beide Storage-Keys und re-runt das
aktive Layout — algorithmische Positionen + Default-Viewport wirken wieder.

**Graph-View — Per-Cluster-Identitaetsfarbe:** `utils/tagColor.ts` liefert eine
deterministische Farbe aus `tag.id` (UUID-Hash → Index in 12-Farben-Palette).
`ProblemGraph.vue` faerbt damit die Cluster-Dots links neben jedem Cluster-Knoten
(`background-color: data(color)`), `pages/table.vue` denselben Punkt im Cluster-Chip.
Text- und Hintergrundfarbe der Tabellen-Pille bleiben neutral — der Punkt allein traegt
die Identitaet, damit Listen mit ≥10 Clustern ruhig lesen. Kein Storage, kein State —
reine Funktion der Tag-ID, view-uebergreifend identisch.

### Echtzeit-Edit-Konflikt-Erkennung

Kommt ein WS-Update rein während der User selbst editiert (`canEdit=true` + `isDirty=true`),
zeigt `ProblemPanel.vue` ein Konflikt-Banner statt die Eingaben still zu überschreiben:

| Zustand | WS-Update kommt rein | Ergebnis |
|---|---|---|
| `canEdit=false` (View-Only) | `props.problem` wird durch Parent still aktualisiert | Kein Banner |
| `canEdit=true`, `isDirty=false` | Edit-Felder + interner Snapshot still aktualisiert | Kein Banner |
| `canEdit=true`, `isDirty=true` | **Konflikt-Banner** erscheint | User entscheidet |

**Banner-Aktionen:**
- **Neu laden** → `fetchProblemById()` → Edit-Felder + Snapshot aktualisieren (eigene Eingaben gehen verloren)
- **×** → Banner schließen, eigene Eingaben bleiben, Konflikt wird ignoriert

**Eigenes Speichern triggert kein Banner:** Nach `handleSave()` wird der Snapshot auf die
gerade gespeicherten Werte gesetzt — der WS-Echo des eigenen Saves ergibt `isDirty=false`.

### Frontend — Composables

Beide Composables müssen **explizit** in `onMounted` verbunden werden — sie verbinden
sich nicht automatisch. Fehlt der `connect()`-Call, bleibt der Socket stumm (kein Fehler).

```typescript
// pages/index.vue
const { connect: connectBackend, disconnect: disconnectBackend } = useBackendRealtime({
  onProblemUpdated: applyProblemUpdate,
})
const { connect: connectAiWs, disconnect: disconnectAiWs } = useRealtimeUpdates({ ... })

onMounted(() => { connectBackend(); connectAiWs() })
onUnmounted(() => { disconnectBackend(); disconnectAiWs() })
```

### Voraussetzungen

- Backend (`apps/backend/`) läuft auf Port 8001 — WS-Endpoint: `ws://localhost:8001/ws`
- nginx `api.decisionmap.ai`-Serverblock: Upgrade-Header + `proxy_read_timeout 3600s`

→ Vollständige Dokumentation: [`docs/dev-environment.md`](dev-environment.md)

[↑ Inhalt](#inhalt)

---

## Internationalisierung (i18n)

Nuxt i18n von Anfang an eingebunden. Alle UI-Texte uber `t()`, keine hardcodierten Strings.

```vue
<!-- richtig -->
<h1>{{ t('problems.title') }}</h1>

<!-- falsch -->
<h1>AI Problem Map</h1>
```

Sprachdateien: `frontend/i18n/locales/en.json` — MVP nur Englisch, Struktur vollstandig.

[↑ Inhalt](#inhalt)

---

## Markdown in Losungen

Erlaubt in `solution_approaches.content` — bewusst eingeschrankt.

**Erlaubt:** Links, Fettschrift, Ueberschriften (h2/h3), Listen, Blockquotes | **Nicht erlaubt:** Bilder, Code-Blocke, inline HTML

```typescript
const md = new MarkdownIt({ html: false, linkify: true })
  .disable(['image', 'code', 'fence'])

function renderSolution(content: string): string {
  return DOMPurify.sanitize(md.render(content), {
    ALLOWED_TAGS: ['p', 'strong', 'em', 'a', 'br', 'h2', 'h3', 'ul', 'ol', 'li', 'blockquote'],
    ALLOWED_ATTR: ['href', 'target', 'rel'],
  })
}
```

Links offnen immer in `target="_blank"` mit `rel="noopener noreferrer"` — per DOMPurify-Hook auf allen Links erzwungen, nicht nur auf explizit gesetzten.

Styling: Tailwind-Variant-Selektoren (`.solution-content h2`, `.solution-content ul` etc.) statt `@tailwindcss/typography` `prose`-Klasse.

**`renderSolutionMarkdown`** ist die gemeinsame Render-Funktion: `SolutionDetail.vue` (Anzeige), `SolutionForm.vue` (Live-Preview) und die Admin-Moderations-Queue nutzen alle dieselbe Funktion — garantiert konsistentes Rendering.

**SSR/prerender-Pfad:** Der DOMPurify-Link-Hook wird **lazy und client-seitig** registriert (`ensureHook()`), nicht auf Modul-Ebene — sonst crasht der Import von `markdown.ts` beim Prerender von `/problem/**`, weil DOMPurify dort keine Browser-DOM hat (`addHook is not a function`). Ohne DOM (`typeof window === 'undefined'`) liefert `renderSolutionMarkdown` die rohe `markdown-it`-Ausgabe zurueck — sicher dank `html:false` + disabled `image`/`code`/`fence`. Im Browser laeuft wie bisher DOMPurify + Hook. Vgl. Konventionen Fund 28.

**`SolutionForm.vue` — Split-Editor Modal (T-13, 2026-06-19):** Das Lösungs-Formular ist ein eigenständiges Centered Modal (`<Teleport to="body">` aus der Komponente selbst, 1080px R-02 Glass-Surface, `max-height: min(840px, calc(100vh - 64px))`) — nicht mehr eine Sub-View im rechten Side-Panel. Layout: Header (Eyebrow + Headline + Problem-Titel + AI-Draft-Button + Close), permanenter **Write · Markdown | Live-Preview**-Split (zwei Spalten nebeneinander) statt der früheren „Schreiben | Vorschau"-Tabs, Sticky-Footer mit Submit. Der Submit-CTA nutzt die User-gewählte Akzentfarbe (`background: rgb(var(--th-accent))` + akzent-basierter Schatten `rgb(var(--th-accent) / 0.4)`) statt des früheren Brand-Gradienten (`var(--dm-grad)`) — konsistent zur Gradient-Disziplin (Gradient nur für Identitäts-Flächen, siehe Konventionen Fund 18). Backdrop theme-aware (gleicher Pattern wie `SolutionPopup`/`ProblemForm`); ESC + Backdrop-Klick → `cancel`; ⌘+Enter / Ctrl+Enter aus dem Textarea → Submit. Entfernt gegenüber der Tab-Variante: `previewMode`-State und die Auto-grow-Textarea-Logik (Textarea füllt jetzt die volle Spaltenhöhe). Form-Logik byte-identisch: `createSolution`, `renderSolutionMarkdown`, `useAiDraft`, `translateToEnglish`, Zod-Schema — unverändert (UI-only-Regel). Trigger-Migration analog zu T-12: `ProblemPanel.vue` öffnet via eigenem `isSolutionFormOpen`-Ref (`panelView`-Variante `'solution-form'` entfernt, Panel zeigt weiter das Problem-Detail hinter dem Backdrop); `pages/problem/[id].vue` rendert `<SolutionForm v-if>` als Root-Sibling. Der Problem-Titel in der Header-Subline („Auf: …") ist **lokalisiert**: beide Caller binden `:problem-title="localizedTitle || problem.title"` — `ProblemPanel.vue` befüllt `localizedTitle` in `updateProblemLocalization()` parallel zur Description via `translateForDisplay(title, lang)` (gleicher Token-Race-Guard), `pages/problem/[id].vue` nutzt den dort bereits vorhandenen `localizedTitle`. Der `|| problem.title`-Fallback (englischer Canonical) greift nur im kurzen Moment vor dem Laden der async-Übersetzung — sonst zeigte die Subline auch im DE-Modus den englischen Titel. Die Markdown-Toolbar (B I H " • ↳) ist **funktional** (T-13a, 2026-06-19): jeder Button fügt Markdown an der aktuellen Cursor-/Selektions-Position des Textareas ein. `applyMark(type)` (gegen `textareaRef`) unterscheidet zwei Modi — `wrap(before, after, placeholder)` umschließt die Selektion (`B`→`**`, `I`→`*`, Link→`[…](https://)`; ohne Selektion wird der Platzhalter „Text" eingefügt und markiert), `linePrefix(prefix)` setzt ein Zeilen-Präfix (`H`→`## `, Quote→`> `, Liste→`- `). Nach dem Insert stellt `await nextTick()` + `el.focus()` + `el.setSelectionRange()` Fokus und Selektion wieder her; die Live-Preview rendert die Änderung sofort mit. Jeder Button hat `title`/`aria-label`. Spec: `apps/frontend/tickets/T-13-solution-form-split-editor.md`.

**`SolutionList.vue` — Auth-Sensitive CTA-Position:** Der Lösungsansatz-Einreichen-CTA ist ein Full-Width-Accent-Button (`background: rgb(var(--th-accent))`, `border-radius: 12px`, `padding: 12px 20px`), positioniert **vor** der Lösungs-Liste — nicht darunter. Brand-Gradient (`var(--dm-grad)`) bleibt dem Logo-Wordmark, Cluster→Root-Edges, Root-Node und Login-Headline vorbehalten — Standard-CTAs nutzen die User-gewählte Akzentfarbe (Default: Sunset Orange, 6 Swatches in Settings). Begründung: bei wachsender Anzahl Lösungsansätze schiebt ein Footer-CTA den Button schnell unter den Fold; eine Top-Position bleibt im Sichtbereich. Der Button rendert immer (kein `v-if="currentUser"`), zeigt aber je nach Auth-State eine andere Variante: eingeloggt → Plus-Icon + `t('solution.addButton')` („Lösung hinzufügen" / „Add solution"); Gast → Lock-Icon + `t('solution.signInToContribute')` („Anmelden, um beizutragen" / „Sign in to contribute"). Beide Varianten emittieren denselben `add`-Event — der Redirect-Pfad für Gäste sitzt im Parent (`ProblemPanel.showSolutionForm()`), nicht in `SolutionList`. Pattern-Konsistenz: dieselbe Auth-Sensitive-Icon-Logik wie der globale „+ Problem erfassen"-Button in der Sidebar.

**Gast-Redirect bewahrt View + Problem + Intent:** Klickt ein anonymer User „Sign in to contribute", baut `ProblemPanel.showSolutionForm()` den Redirect aus der **Setup**-`useRoute()` (`route.path` — nicht inline `useRoute().fullPath`, das die falsche View liefert) plus zwei Query-Params: `/login?redirect=<view>?problem=<id>&solution=new`. Die in-memory-Selektion (`selectedProblem`) geht beim Login sonst verloren → der User landet nach dem Login in der Default-Graph-View ohne Panel. Nach dem Login lösen `?problem=<id>` (Page → `focusProblemId`, Panel wird wiederhergestellt) und `?solution=new` (`ProblemPanel.maybeOpenPendingSolutionForm()` öffnet das Solution-Modal, sobald Panel **und** Auth da sind, und strippt danach den `solution`-Param via `router.replace` — One-Shot, kein Reopen bei Reload/Share). `maybeOpenPendingSolutionForm()` läuft in `onMounted` **und** in `watch(currentUser)` — letzteres fängt die Race ab, falls das Panel vor dem `restoreSession()` mountet. Greift denselben Layout-Remount-Mechanismus wie der `PENDING_OPEN_PROBLEM_FORM`-Flow (`login.vue` hat `definePageMeta({ layout: false })` → `default.vue` remountet beim Zurücknavigieren und liest die Query frisch). E2E-Regressions-Spec: `apps/frontend/tests/e2e/solution-redirect.spec.ts` (anonym → Login → Table-View + Panel + Formular offen).

**`SolutionList.vue` — Karten-Layout (Header + 2-Zeilen-Preview):** Jede Lösungs-Karte rendert in zwei Blöcken — Header-Zeile + Content-Preview, statt der früheren einzeiligen Headline mit Vote-Score rechts. Header (Flex-Row, `gap-2`, `mb-2`): 28×28 Avatar-Pille mit User-Initiale (`rgb(var(--th-accent))`-Background, weiße Initiale in `var(--font-display)` Space Grotesk) + Author-Name (14px, semi-bold, Space Grotesk, `truncate`) + optional AI-Badge (Accent-bg `rgb(var(--th-accent))`, 4-Point-Star Sparkle-Icon — `ISpark`-Geometrie statt 🤖-Emoji, „AI" in `uppercase tracking-wider`) + Vote-Score (`ml-auto`, mono, faint, `↑ 12`). Content-Preview unter dem Header: `<p class="text-sm text-th-text-muted line-clamp-2">` mit Plaintext aus `stripMarkdown(content)` — entfernt `**bold**`-Marker und `[label](url)`-Link-Syntax, **keine harte Zeichen-Grenze** mehr (kein `slice(0, 100) + '…'`). Tailwind `line-clamp-2` (`-webkit-line-clamp: 2`) übernimmt das Trunkieren mit Ellipsis je nach Viewport-Breite — bei schmalen Panels weniger Vorschau, bei breiten mehr. Author-Resolver `authorName(solution)`: `isAiGenerated` → `t('problems.aiGenerated')`; kein `userId` → `t('problems.anonymous')`; sonst `getUserById(userId)?.displayName ?? email ?? anonymous`. `authorInitial(solution)`: erstes Zeichen, uppercase, Fallback `?`. AI-Badge nur via `solution.isAiGenerated` — kein Emoji-Prefix im Content mehr.

**`SolutionPopup.vue` — Glass-Modal-Treatment (`glass-dark`/`glass-light`):** Klick auf das Solutions-Badge im Graph öffnet ein theme-awares Glass-Modal — Card-Background `rgba(20,16,28,0.78)` + `backdrop-filter: blur(40px)` + Inset-Highlight (dark) bzw. `rgba(255,255,255,0.86)` + `blur(30px)` (light), Backdrop bewusst dunkler und stärker geblurrt (`rgba(0,0,0,0.55)` + `blur(8px)`) damit das Modal nicht in den Mesh-Orb-Hintergrund einblendet. Frühere Variante nutzte `bg-th-bg` (Page-Color) — auf Glass-Themes verschwamm das Modal mit der Mesh-Surface. Header: Eyebrow `text-[11px] uppercase tracking-wider text-th-text-faint` („Solution approaches (2)") + `font-display` Titel 17px/600. Close-Button: 32×32 rounded Pille mit SVG-`×` statt Glyph, theme-aware Background. Andere Themes (Legacy) rendern weiterhin solid via `rgb(var(--th-surface))` + `rgb(var(--th-border))`. Werte sind als **kanonische R-02-Spec (Glass Modal Surface)** promoted und werden in `ProblemPanel.vue` (`panelContentStyle`), `ProblemForm.vue` und `SolutionForm.vue` (`formContainerStyle`) identisch übernommen — bewusste Inline-Duplikation statt Token-Extraktion (Trade-off und Pruefpattern: siehe Konventionen Fund 23).

**`SolutionPopup.vue` — Listen-Items spiegeln das SolutionList-Karten-Vokabular:** Die früheren Reihen mit `divide-y` + Index-Nummer + Detail-Button wurden ersetzt durch eigenständige Karten (`background: rgba(128,128,128,0.12)` auf Glass / `rgb(var(--th-surface))` solid, `border-radius: 16px`, `padding: 14px`, 1px Theme-Border, `space-y-2` zwischen Karten, `hover:-translate-y-px`-Lift). Karten-Header (Flex-Row, `gap-2`, `mb-2`): 28×28 Avatar-Pille mit Initiale aus `authorName()` (`rgb(var(--th-accent))`-Background, weiße Initiale in `font-display`) + Author-Name (14px, semi-bold, Space Grotesk, `truncate`) + optional AI-Badge (Accent-bg, 4-Point-Star Sparkle-SVG — `M12 2 L14 10 L22 12 L14 14 L12 22 L10 14 L2 12 L10 10 Z`, ersetzt das frühere 🤖-Emoji) + Vote-Score (`ml-auto`, mono, faint, `↑ N`). Content-Preview unter dem Header: `text-sm text-th-text-muted line-clamp-2` mit Plaintext aus `stripMarkdown()` — **keine harte Zeichen-Grenze** (`truncate(text, 120)` entfernt). Locale-aware: ein `watch([locale, solutions])` baut eine `localizedHeadlines: Map<id, string>` über `translateForDisplay(content, lang)` (leer wenn `locale === 'en'`) — DE-User sehen die übersetzte Vorschau, identisch zur SolutionList. Author-Resolver `authorName(solution)`: `isAiGenerated` → `t('problems.aiGenerated')`; kein `userId` → `t('problems.anonymous')`; sonst `getUserById(userId)?.displayName ?? email ?? anonymous` (identisch zu `SolutionList.vue`). Volle Karte ist klickbar (`cursor-pointer` + `@click="openSolution(solution)"`) — der frühere „Show details"-Button auf Hover entfällt. Pattern-Konsistenz: Popup-Karten und Right-Panel-Karten teilen dasselbe visuelle Vokabular, damit der User keinen Stilbruch beim Wechsel zwischen Graph-Klick und Panel-Klick wahrnimmt.

**`ProblemForm.vue` — Centered Modal Layout (T-12, 2026-06-10):** Das Neues-Problem-Formular ist ein Centered Modal (`<Teleport to="body">` mit Backdrop-Dim + 680px-Card, `max-height: calc(100vh - 80px)`) — nicht mehr im rechten Side-Panel. ProblemPanel (Detail-Ansicht eines bestehenden Problems) bleibt unverändert im Side-Panel. Backdrop ist theme-aware: glass-dark `rgba(0,0,0,0.55)` + `blur(8px)`, glass-light `rgba(0,0,0,0.40)` + `blur(4px)` — gleicher Pattern wie `SolutionPopup.vue`. Modal-Card nutzt R-02 Glass Modal Surface via `formContainerStyle` (identische Werte zu `SolutionPopup`/`ProblemPanel`). Header: Eyebrow `NEW PROBLEM` (11px/700/.18em uppercase in `--th-accent`) + Headline `t('form.headline')` (26px Space Grotesk) + Subline `t('form.subline')` (480px max-width) + 32×32 Close-Icon mit `--th-border`. Body ist scrollable Form (`flex-1 overflow-y-auto min-h-0`) mit `id="problem-form"`. Sticky-Footer: Status-Hint links (`t('form.statusHint')` mit grünem Dot) + Ghost-Cancel + Gradient-Submit (`var(--dm-grad)` — Brand-Identität für den Haupt-Submit). Submit-Button referenziert das Formular via `form="problem-form"`-Attribut statt JS-Forward (siehe Konventionen Fund 25). ESC + Backdrop-Klick → `handleCancel`. State-Management: `layouts/default.vue` hat einen separaten `isProblemFormModalOpen`-Ref (distinkt von `isPanelOpen` für die Detail-Ansicht), via `provide/inject` für `pages/index.vue` exponiert. Similarity-Card rendert **inline** zwischen Title und Description (war vor T-12 `<Teleport to="#panel-status-target">` — der Status-Slot ist nach T-12 orphan, Cleanup-Kandidat). Form-Logik byte-identisch zu vorher: `createProblem`, `validateForm`, `useSimilarity`, `useEnglishTranslation`, Tag-Erstellung, `duplicate_confirmed`-Signal-Flow — alle unverändert (UI-only-Regel). Spec: `apps/frontend/tickets/T-12-problem-form-modal.md`.

[↑ Inhalt](#inhalt)

---

## Ubersetzung

Aktive Ubersetzung beim Einreichen — nicht passiv via DeepL-Link:

1. User tippt Titel/Beschreibung in beliebiger Sprache
2. Automatische Spracherkennung (`looksLikeEnglish`): Text gilt als Englisch wenn er keine Unicode-Zeichen > U+007F enthaelt
3. Bei Englisch: `_en`-Felder werden automatisch befuellt, kein Translate-Button noetig
4. Bei Nicht-Englisch: „Translate to English"-Button erscheint
5. Klick uebersetzt beide Felder (Titel + Beschreibung) parallel
6. User kann die englische Version vor dem Submit anpassen
7. Submit triggert Auto-Translate wenn Nicht-Englisch erkannt und noch nicht uebersetzt (`hasNonEnglishContent && !translationDone → handleTranslateAll()`) — EN-Felder sind kein Submit-Blocker

Im Fake-Modus: 700ms simulierter Delay.
Im Real-Modus: KI-Service (TranslationService via konfiguriertem LLM-Provider — OpenAI `gpt-4o-mini` oder Anthropic `claude-haiku-4-5`, je nach `llm_provider` in `.env`).

**`EnglishTranslationSection.vue` — Collapsible UX (Problem Form):** EN-Felder erscheinen als Collapsible-Sektion sobald Nicht-Englisch erkannt wird. Header-Zeile zeigt Chevron-Icon + Titel-Preview im kollabierten Zustand. Auto-Expand nach Uebersetzung: zwei Trigger — `watch(showFields, { immediate: true })` (auch beim Mount wenn showFields bereits true) und `watch(isTranslating)` (Re-Translation wenn Section kollabiert war — showFields aendert sich nicht, der isTranslating-Uebergang true→false triggert Expand). Translate-Button und Info-Button bleiben immer in der Header-Zeile sichtbar — Info-Button nutzt `.stop` um den Collapse-Toggle nicht auszuloesen. Kein visueller Overhead fuer englischsprachige User — `showEnSection` in `useEnglishTranslation.ts` prueft `locale.value !== 'en'` explizit (verhindert falsch-positive Sichtbarkeit, da `looksLikeEnglish` fuer ASCII-Text immer `true` liefert). **`startCollapsed`-Prop:** Wenn `true`, bleibt die Sektion beim `showFields false→true`-Übergang initial eingeklappt — der Caller kontrolliert den Startzustand (z.B. Edit-Modus mit bestehender Übersetzung). 4 Tests in `EnglishTranslationSection.spec.ts` sichern dieses Verhalten ab.

**`ProblemForm.vue` — Textarea Auto-Resize:** Das Beschreibungsfeld wächst beim Tippen automatisch mit dem Inhalt (`@input="autoResize"`). Kein fixer `rows`-Wert — Höhe wird per JavaScript gesetzt. `validateForm` blockt non-ASCII-Eingaben bei `locale === 'en'` via `NON_ASCII_RE` (`/[^\x00-\x7F\p{P}\p{S}\p{N}\p{Z}\p{C}]/u`, Unicode-Property-Escapes) — gleicher Guard wie `handleSave`/`handleSubmit`/`handleSaveEdit` in den anderen Formularen. Nicht-ASCII-Buchstaben (ä ö ü Kyrillisch CJK) blockiert; englische Typographie (– — „" … © €) erlaubt. `"4–6 weeks"` läuft durch.

**`SolutionForm.vue` — Translation Collapsible (inline):** Solutions haben nur ein Content-Feld (kein Titel); `EnglishTranslationSection` ist fuer Titel+Beschreibungs-Paare gebaut. SolutionForm implementiert das Collapsible direkt inline — gleiche visuelle Optik (Chevron, Card-Style, Colour-Tint), gleiche UX (Auto-Expand nach Uebersetzung). Kein `mode`-Flag an `EnglishTranslationSection` — vermeidet unnoetige Komplexi­taet. Der EN-Block hat einen expliziten `locale !== 'en'`-Guard im Template (`v-if`) — kein falsches Anzeigen bei englischer UI-Sprache. `handleSubmit` blockt non-ASCII-Eingaben bei `locale === 'en'` (`form.validation.inputEnglishOnly`). Spec: [`docs/specs/2026-06-07-solution-form-design.md`](specs/2026-06-07-solution-form-design.md)

**originalTranslations (first-class JSONB-Spalte, Migration 009, 2026-06-21):** Der vom User eingereichte Originaltext liegt direkt auf der Problem-Zeile in `problems.original_translations` (JSONB, Format `{lang: {title?, description?}}`) — nicht mehr per `sha256`-Hash aus dem `translation_cache` rekonstruiert. Migration 009 backfillt die Spalte aus dem alten Cache. **Alle `/problems`-Lese-Pfade** (List, Single, Create-/PATCH-/Delete-Response) liefern `original_translations` ans Frontend (`ProblemRead.original_translations`) — gelesen direkt aus der Spalte (`_to_read`), kein Reverse-Mapping mehr. **Create** setzt die Spalte direkt am Problem-Objekt; **Edit (PATCH)** aktualisiert sie **transaktional im selben Commit** wie `title`/`description` — kein Hash-Drift möglich, der Originaltext bleibt update-sicher. Die alten Helfer `_store_original_translations`/`_load_original_translations` sind entfernt; der `TranslationCache` bleibt nur noch für die LLM-Übersetzung (`translations.py`/`solutions.py`). Modell: `JSONB().with_variant(JSON(), "sqlite")` — die In-Memory-Test-DB (kein `visit_JSONB`) baut weiterhin. Siehe Konventionen Fund 30.

> **Contract-Erkenntnis (`ProblemRead`):** Mit dem `original_translations`-Refactor liefert `ProblemRead` **nicht mehr** die früheren englischen Canonical-Felder `title_en` / `description_en` / `content_language` — nur noch `title`, `description` und `original_translations`. Das Frontend (`realProblems.ts` → `BackendProblem`) mappt entsprechend `title`/`description`/`original_translations`; die Contract-Tests (`tests/contract/test_problems.py`) prüfen exakt diese Feld-Liste. Die DB-Spalten `title_en`/`description_en`/`content_language` existieren weiterhin (Schema/Embedding-Quelle, vgl. [`data-model.md`](data-model.md)) — entfernt wurde nur ihre Exposition im API-DTO.

**`translateForDisplay` — Display-seitige Lokalisierung:** `useTranslation` bietet `translateForDisplay(content, lang)` fuer read-only UI-Stellen. `SolutionList.vue` nutzt dies um Headlines in der Liste zu lokalisieren: `watch([locale, solutions])` → `translateForDisplay` fuer alle Solutions → `localizedHeadlines`-Map. Bei `lang === 'en'` wird die Map geleert (EN-Content ist Original). Lokale `_displayCache` verhindert redundante API-Calls.

**Stiller Fallback bei `/translate`-Fehler (transient):** Schlaegt der `/translate`-Call fehl (z.B. nginx Rate-Limit 429, 5r/m burst 2), gibt `translateForDisplayReal` den **englischen Original-Text** zurueck (`catch` → `return text`) und cached dieses Ergebnis **nicht** (nur Erfolge landen in `_displayCache`) — es heilt sich beim naechsten Aufruf selbst. Direkt nach dem Submit ist das Rate-Limit-Fenster durch die eigenen Auto-Translate-Calls (DE→EN) belegt, sodass die Display-Calls (EN→DE) ins 429 laufen koennen. Konsequenz im DE-Modus: Haupt-Felder zeigen Englisch → `looksLikeEnglish()` = `true` → `englishAutoDetected` = `true` → EN-Section klappt faelschlich auf. Kein Datenfehler, rein transient. **Der Edit-Pfad (`ProblemPanel`) ist davon nicht mehr betroffen** — `loadLocalizedEditFields` bevorzugt das gespeicherte `originalTranslations[locale]` (kein LLM-Round-Trip, kein 429-Risiko); `translateForDisplay` greift nur als Fallback fuer Sprachen ohne gespeichertes Original. Reine Display-Stellen ohne gespeichertes Original (z.B. `SolutionList`) koennen den Fallback weiterhin treffen. Siehe Konventionen Fund 26.

[↑ Inhalt](#inhalt)

---

## Tagging und Regionen

Zwei getrennte Konzepte:

- **Tags** (`tags` + `tag`) — inhaltliche Kategorisierung: "governance", "open-source", "shadow-ai"
- **Regionen** (`regions` + `region`) — geografische Einschrankung: 121 DACH-Regionen nach ISO 3166-2 (AT, CH, DE + Bundeslaender/Kantone/Bundeslaender)

Ein Problem kann mehrere Tags und mehrere Regionen haben.
Probleme ohne Region gelten als global relevant.

Regionen beeinflussen das Ranking (lokale Regionen priorisiert fur regionalen User).
Filterung moglich aber nicht erzwungen.

**useRegions-Facade:** Komponenten importieren ausschliesslich `useRegions.ts` (`useRegionsFetch()`) — kein Direktimport von `realRegions`. Facade-Pattern ermoeglicht den `USE_FAKE_DATA`-Switch ohne Komponenten-Aenderungen. `_inflight`-Promise-Cache verhindert doppelte Requests wenn mehrere Komponenten gleichzeitig mounten.

**Geo-Detection:** `useRegionDetection` ermittelt die Region des Users und setzt die Default-Auswahl im Formular.

Erkennungs-Kaskade:
1. **Browser-Geolocation** → Nominatim Reverse-Geocoding → ISO 3166-2 Subdivision-Code (z.B. `DE-BY`) → Region-Match
2. **Backend-Proxy** (`GET /regions/geo`) — greift wenn Geolocation nicht verfügbar ist (HTTP-Kontext) oder verweigert wird. Backend ruft `ip-api.com` server-seitig auf (vermeidet CORS auf HTTP; `ipapi.co` hat zu strenge Rate Limits). `country_code` + `region_code` → `AT-9` → Region-Match; Fallback auf Country-Code wenn Subdivision nicht matched.

HTTP-Kontext (z.B. `int.decisionmap.ai`): Browser blockiert `navigator.geolocation` automatisch auf nicht-sicheren Origins (HTTP) — `error.code === 1` (`PERMISSION_DENIED`), kein User-Popup. Backend-Proxy läuft automatisch als Fallback. Kein Contract-Test — `navigator.geolocation`-Mocking in Vitest ist nicht-trivial, als bekannte Lücke dokumentiert.

**Dev-Limitation:** In LAN-Entwicklungsumgebungen (`int.decisionmap.ai` → LAN-IP in `X-Forwarded-For`) liefert auch der Backend-Proxy `null` — `ip-api.com` geolocated keine privaten RFC-1918-Adressen. Region-Vorauswahl via Geo-Detection ist ein **Production-only Feature**; im lokalen Dev muss die Region manuell im Dropdown gewählt werden.

[↑ Inhalt](#inhalt)

---

## Editieren von Eintragen

- Editieren nur fur den ursprunglichen Autor
- Nach Freigabe (`approved`): Edit setzt Status zuruck auf `needs_review`
- Edit-History nur fur Moderatoren sichtbar
- `edited_at` wird im UI angezeigt
- KI-generierte Eintrage (`is_ai_generated: true`) nur vom Admin editierbar

### Edit-Lokalisierung (ProblemPanel)

Beim Öffnen des Edit-Modus lädt `ProblemPanel.vue` lokalisierte Inhalte in die Edit-Felder:

- **Locale = DE:** `loadLocalizedEditFields()` bevorzugt das vom Backend gelieferte `originalTranslations[locale]` (genau der ursprünglich getippte Text — kein LLM-Round-Trip, kein Rate-Limit-Risiko); nur wenn kein gespeichertes Original für die Locale existiert, fällt es auf `translateForDisplay` (Translation-Cache) zurück. `editTitleEn`/`editDescriptionEn` werden mit dem gespeicherten EN Canonical-Text befüllt.
- **Locale = EN:** Kein Cache-Lookup — englischer Canonical-Text aus `props.problem` (bisheriges Verhalten)
- **Snapshot** wird auf denselben lokalisierten Wert gesetzt → `isDirty` startet als `false`
- **Textarea Auto-Resize:** `watch(editDescriptionOrig)` feuert wenn `loadLocalizedEditFields` den lokalisierten Text setzt — Textarea expandiert sofort beim Öffnen des Edit-Modus. `@input="autoResize"` hält die Höhe beim Tippen aktuell.
- **Sprachwechsel zur Laufzeit:** `watch(locale)` lädt die Edit-Felder neu (nicht nur die Read-Anzeige via `updateProblemLocalization`) — für Owner/Admin sind die Edit-Felder die sichtbare Darstellung, sonst bliebe der Text in der alten Sprache stehen bis ein Problem-Wechsel `loadLocalizedEditFields` triggert. Reload nur bei `canEdit && !isDirty` — ungespeicherte Eingaben werden nicht überschrieben.
- **Erstes Mount / Permalink-Load:** `onMounted` ruft `loadLocalizedEditFields(props.problem)` explizit auf — `watch(problem.id)` ist **nicht** `immediate`, also würde ein frisches Öffnen (Permalink-Load oder erste Auswahl) sonst den englischen Canonical statt des Locale-Texts zeigen. Anschließend `await nextTick()` + `autoResizeDesc()`, damit die Beschreibungs-Textarea schon beim Öffnen auf ihren Inhalt skaliert (nicht erst beim ersten Tippen).

**EN-Felder Sichtbarkeit im Edit-Modus:**
- Bei `locale=en` bleibt die EN-Sektion komplett ausgeblendet — `showEnSection` prueft `locale.value !== 'en'`; kein Uebersetzungsflow noetig. `handleSave` blockt zusaetzlich non-ASCII-Eingaben bei englischer UI-Sprache (`form.validation.inputEnglishOnly`).
- EN-Sektion startet **eingeklappt** — auch wenn `editTitleEn` bereits einen Wert hat. Header zeigt den ersten Satz der vorhandenen Übersetzung als Indikator. Klick auf Header expandiert zur vollen Bearbeitungs-Textarea.
- `hasExistingEnTranslation`-Ref bleibt `true` solange ein nicht-englisches Problem bearbeitet wird — unabhängig davon ob `watch(title)` `editTitleEn` löscht
- Ändert der User den deutschen Text: `watch(title)` löscht `editTitleEn` → EN-Felder bleiben sichtbar (aber geleert) → Übersetzen-Button weiterhin zugänglich
- Neue Übersetzung (Übersetzen-Button): Section expandiert nach Fertigstellung (Auto-Expand)

**`handleSave`:**
- **`isDirty` Guard:** Keine Änderung → API-Call wird übersprungen. Speichern-Button visuell deaktiviert (`disabled:opacity-60`) solange `isDirty=false`
- **Auto-Translate:** Editiert der User auf Deutsch ohne manuell zu übersetzen, übersetzt das System automatisch vor dem Speichern — gleicher Flow wie beim Einreichungs-Formular; Backend speichert korrekten englischen Canonical-Text
- **`original_translations` mitgeschickt:** Bei `locale !== 'en'` sendet `handleSave` (Owner- *und* Admin-Pfad) `{ [locale]: { title, description } }` im PATCH-Body mit → Backend re-cached das editierte Original gegen den neuen EN-Canonical. Nach dem Speichern liest `loadLocalizedEditFields(updated)` das Original aus der PATCH-Response, sodass das Panel den editierten Text ohne Translate-Round-Trip zeigt. EN-Locale-Edits bearbeiten den Canonical direkt (`originalTranslations` = `undefined`).

### Edit-Lokalisierung (SolutionDetail)

`SolutionDetail.vue` — Owner und Superuser sehen einen `✎ Bearbeiten` Button. Edit-Verhalten analog zu `ProblemPanel`:

- **Content-Feld:** User sieht und bearbeitet Inhalt in seiner eingestellten Sprache (DE: Translation-Cache via `translateForDisplay`)
- **Textarea Auto-Resize:** `autoResize()` wird in `nextTick` nach `enterEditMode` ausgeführt — Textarea expandiert sofort auf den vollen Inhalt. `watch(editContent)` + `@input="autoResize"` halten die Höhe live aktuell.
- **EN-Sektion:** Startet **eingeklappt** via `startCollapsed`-Prop — zeigt ersten Satz der vorhandenen Übersetzung als Indikator; `hasExistingEnTranslation` bleibt `true` solange das Feld nicht leer ist. Bei `locale=en` komplett ausgeblendet (inline `v-if="locale !== 'en' && ..."`-Guard).
- Ändert der User den Inhalt: EN-Feld leert sich → Übersetzen-Button erscheint → EN-Felder bleiben sichtbar (aber geleert)
- **`handleSave`:** `isDirty` Guard + non-ASCII-Validation bei `locale=en` + Auto-Translate falls kein EN-Text vorhanden — gleicher Flow wie beim Problem-Edit. Speichern-Button deaktiviert (`disabled:opacity-60`) wenn `editContent.length < 20` oder `isSaving=true`
- **Status:** Owner-Edit wechselt zurück auf `needs_review` (Standard-Flow)
- DeepL-Link entfernt — built-in Translation ersetzt ihn vollständig

### Superuser-Edit auf approved Problems

Superuser-Edits an `title` oder `description` eines bereits `approved` Problems folgen einem anderen Flow:

- Status bleibt `approved` — kein Rückfall auf `needs_review`
- Backend löst `POST /hooks/problem-reindex` als BackgroundTask aus
- Pipeline: Re-Embedding → Re-Clustering → WebSocket-Broadcast

[↑ Inhalt](#inhalt)

---

## KI-generierte Losungsansatze

`is_ai_generated: true` in `solution_approaches` — visuell klar getrennt.

- Eigenes Label "AI-generated" / Badge
- Ranking separat von menschlichen Beitragen
- **Kein Auto-Generieren:** KI erstellt keine Inhalte automatisch bei Problem-Approval — alle Solution-Inhalte kommen von Usern
- KI-Rolle = ausschliesslich Moderation (LLM-Spam-Filter kann `approved` vergeben, identisch zum Problem-Flow)
- `is_ai_generated: true` kennzeichnet Admin-erstellte oder historisch generierte Eintraege
- Admin schaut nur bei Grenzfaellen rein — kein eigener Moderations-Layer fuer Solutions

**Begruendung (Issue #26):** Core Value Prop ist kollektive Intelligenz echter User. Rein KI-generierte Ansaetze (auch admin-abgesegnet) verwassern das.

### KI-Entwurf (User-Triggered Draft)

User kann per Button einen KI-generierten Entwurf anfordern — kein Auto-Generieren, User entscheidet und bearbeitet:

```
User klickt "✦ AI Draft"
  → POST /api/generate-solution { problem_id, lang? }   (AI-Service, kein SERVICE_TOKEN)
  → Draft-Text erscheint in Textarea (auto-grow)
  → User bearbeitet → Uebersetzung → Submit
```

- **`useAiDraft(problemId)`** — neues Composable: `{ draft, loading, error, generate }`; übergibt `locale.value` als `lang`-Parameter → AI-Service generiert Draft in Benutzersprache
- Draft wird nur zurueckgegeben — kein Storage, kein `is_ai_generated`-Flag (User submitted separat via `POST /solutions`)
- Draft wird auf 2000 Zeichen gekuerzt (`.slice(0, 2000)`) — entspricht dem `maxlength` des Content-Feldes
- nginx Rate Limit: 5r/min per IP, Burst=1 (enger als `/translate` wegen LLM-Kosten)
- `USE_FAKE_DATA=true`: Hardcoded Markdown-String nach 800ms Delay
- Spec: [`docs/specs/2026-06-07-solution-form-design.md`](specs/2026-06-07-solution-form-design.md)

[↑ Inhalt](#inhalt)

---

## Theme-System

6 vordefinierte Themes + benutzerdefiniertes Theme per Akzentfarbe.

### Preset-Themes

| Theme | Modus | Akzentfarbe |
|---|---|---|
| Default | Hell | Blau (#2563eb) |
| Forest | Hell | Gruen (#059669) |
| Sunset | Hell | Amber (#d97706) |
| Midnight | Dunkel | Hellblau (#60a5fa) |
| Obsidian | Dunkel | Violett (#a78bfa) |
| Aurora | Dunkel | Teal (#2dd4bf) |

### Custom-Theme

User waehlt eine Akzentfarbe, das System generiert daraus alle UI-Farben:
- Hex → HSL-Konvertierung
- Ableitung von Hintergrund, Oberflaeche, Rahmen, Text, Input-Farben
- Komplementaerfarben fuer Graph-Knoten (Blaetter: Farbton +120°, Loesungen: +160°)
- Ueber 30 CSS Custom Properties werden dynamisch auf dem Document-Root gesetzt

### FOUC-Praevention

Blockierendes Inline-Script im `<head>` (via `nuxt.config.ts`):
- Liest Theme aus `localStorage` bevor Vue geladen wird
- Setzt `data-theme`-Attribut und `dark`-Klasse sofort
- Fallback-Variablen in `:root` stellen sicher dass Styles existieren bevor JS laeuft

### System-Praeferenz

Ohne explizite Theme-Wahl wird `prefers-color-scheme` ausgewertet und das
entsprechende Default-Theme geladen (`glass-light` oder `glass-dark`). Der
FOUC-Bootstrap-Fallback in `nuxt.config.ts` muss identisch zu
`resolveSystemTheme()` in `composables/useTheme.ts` bleiben — bei jedem Wechsel
des Default-Themes beide Stellen gleichzeitig anpassen (siehe Konventionen Fund 21).

[↑ Inhalt](#inhalt)

---

## Permalink-System

Teilbare Links zu einzelnen Problemen — view-aware: Graph-View `/?problem=<id>`, Table-View `/table?problem=<id>`

### Ablauf

1. Layout liest `route.query.problem` beim Laden
2. `focusProblemId` wird via `provide/inject` an alle Child-Komponenten verteilt
3. **Graph-View:** Drills automatisch zur Tag-Hierarchie des Problems (findet den tiefsten
   strukturellen Tag, baut die Ancestor-Chain fuer Breadcrumbs, setzt Filter) und synct via
   `cluster-drill`-Emit den `drilledTagId` des Parents, sodass dessen Cluster-Liste tatsaechlich
   laedt — sonst leeres Grid unter aktiver Breadcrumb (FE `b48009e`, Konventionen Fund 35)
4. **Table-View:** Filtert auf das einzelne Problem
5. Detail-Panel oeffnet sich automatisch — `ProblemPanel` lokalisiert beim Mount (s. Edit-Lokalisierung), sodass ein Permalink-Load in DE deutschen statt englischen Text zeigt
6. Filter-Chip zeigt „Showing single problem" mit Schliessen-Button

### Share-Button

Im Detail-Panel kopiert „Share link" den Permalink in die Zwischenablage. Der Link kodiert die
Ursprungs-View, damit er sie beim Reopen wiederherstellt: Graph-View (`route.path === '/'`) →
`origin + /?problem=<id>`, Table-View (und jeder andere Pfad) → `origin + /table?problem=<id>`. Beide
Ziel-Routen lesen `?problem=` bereits aus (Schritt 1–5 oben). Feedback: „Link copied!" fuer 2 Sekunden;
schlaegt das Kopieren fehl, erscheint ein Error-Toast (`permalink.copyFailed`) statt stillem Nichts.

Das Kopieren laeuft ueber `utils/clipboard.ts` (`copyToClipboard`): `navigator.clipboard.writeText`
existiert nur in Secure Contexts (HTTPS/localhost) und ist auf HTTP-Origins wie `int.decisionmap.ai`
`undefined` → naiver `writeText`-Aufruf wirft, der frueher nur in die Konsole geloggt wurde („nichts
passiert"). Der Util faellt auf das Legacy-`document.execCommand('copy')` via verstecktem `<textarea>`
zurueck — funktioniert auch auf HTTP. Gleiche Secure-Context-Klasse wie der `navigator.geolocation`-
HTTP-Gotcha. Wiederverwendbar fuer kuenftige Share-Buttons (z.B. `SolutionDetail`).

[↑ Inhalt](#inhalt)

---

## Authentifizierung

fastapi-users — JWT-Auth, E-Mail-Verifizierung, Magic Link (`apps/backend/`, Port 8001).

### Registrierung

```
User füllt Register-Formular aus (E-Mail + Passwort + optional Firma)
      ↓
Passwort-Stärke-Checklist live (✓/○ pro Regel, Submit gesperrt bis alle grün)
      ↓
POST /auth/register → Backend (fastapi-users) schickt Verifizierungsmail
      ↓
Frontend zeigt „registrationSent"-State (kein Auto-Login)
      ↓
User klickt Link in Mail → /verify-email.vue → GET /auth/verify?token=XXX
      ↓
Backend antwortet 204 (Erfolg)
      ↓
Frontend leitet weiter auf /login?verified=true → grünes Banner
```

Der Register-Tab (`pages/login.vue`) hat seit FE `fc68cf6` (#29) ein **optionales Firmen-Feld** (`company`, `autocomplete="organization"`); gesetzt wird es als `company || undefined` im Register-Call mitgeschickt. Damit speisen neue User die Firma, an der der spätere `company`-Filter (s. Server-Driven Search) ansetzt.

### Passwort-Stärke-Regeln

| Regel | Min |
|---|---|
| Länge | ≥ 8 Zeichen |
| Großbuchstabe | ≥ 1 |
| Zahl | ≥ 1 |
| Sonderzeichen | ≥ 1 |

Submit bleibt gesperrt bis alle vier Regeln erfüllt sind.

### Magic Link

```
User fordert Magic Link an (E-Mail-Eingabe)
      ↓
POST /auth/request-magic-link → Backend schickt Mail mit Token
      ↓
User klickt Link → /auth/magic-verify.vue → GET /auth/magic-login?token=XXX
      ↓
Backend antwortet mit JWT → Frontend speichert Token, leitet auf / weiter
```

`/auth/magic-verify.vue` ist die Landingpage für Magic-Link-Tokens (B4-Fix: neu angelegt).

### Login / Logout

- POST `/auth/login` → JWT-Token in `localStorage`
- Token wird synchron im `setup()`-Block geladen (`loadPersistedTokens()` vor `onMounted`) — kein Race mit ersten API-Calls
- `restoreSession()` (API-Aufruf zur Session-Validierung) in `onMounted`
- **Logout bewahrt die aktuelle View** (2026-06-24): `handleLogout` (`default.vue`) navigiert **nicht** mehr unbedingt auf `/` (Graph) — der User bleibt in der View, in der er war (z.B. `/table`). Einzige Ausnahme: auth-gated Admin-Routen (`/admin/**`) werden beim Logout explizit verlassen (→ Graph), da die Admin-Middleware nur bei Navigation greift, nicht bei einem In-Place-Wechsel des Auth-States.

### „+" Button — Login-Redirect-Flow

Der `+`-Button ist immer sichtbar (Graph/Table-View), unabhängig vom Auth-Status:

- **Single Source of Truth:** Die Auth-Entscheidung (Formular öffnen vs. Login-Redirect) liegt **ausschließlich** im Container `handleOpenForm` (`default.vue`). Alle `+`-Buttons — auch der `DmTopBar`-Button im Bold-Redesign — emittieren unconditional `open-form`; sie duplizieren die Auth-Prüfung nicht. (Regression-Lesson: ein zweiter, eigenständig auth-prüfender Button emittierte für Gäste `open-login` statt `open-form` und umging so die Flag-Logik → kein Popup nach Login.)
- **Eingeloggt:** Öffnet das Eingabeformular direkt im Panel
- **Nicht eingeloggt:** Setzt localStorage-Flag `PENDING_OPEN_PROBLEM_FORM` + navigiert zu `/login?redirect=<origin>` (Herkunfts-Route via `route.path`, damit der Login zur Ausgangsseite zurückführt — z.B. `/table`); auf `sm:`-Breakpoints zeigt der Button ein Lock-Icon (`opacity-70`) als subtilen Hinweis auf Login-Anforderung
- **Nach Login:** `login.vue` löst das Ziel via `resolveRedirect()` aus `?redirect=` auf (Open-Redirect-Guard: nur interne Pfade, kein `//`-Präfix) und navigiert dorthin — sowohl nach erfolgreichem `handleLogin` als auch im `onMounted`-Auto-Redirect bereits authentifizierter User. `default.vue` prüft dann in `onMounted` (nach `restoreSession()`) das Flag — ist es gesetzt, wird das Formular geöffnet und das Flag gelöscht
- **Ghost-Open Schutz:** Das Flag wird in `onMounted` von `default.vue` **immer** gelöscht — egal ob der User eingeloggt ist oder nicht. Bricht der User den Login ab und loggt sich später normal ein, öffnet sich das Formular nicht ungewollt nochmals.

Der Flow funktioniert für beide Auth-Methoden: Password-Login (`/login?redirect=<origin>` → `router.push(resolveRedirect())`) und Magic Link (`/auth/magic-verify` → `router.replace('/')`). In beiden Fällen mountet `default.vue` neu und der Flag-Check greift.

### Dev-Umgebung

Mailpit als SMTP-Sink — alle Mails landen auf `http://localhost:8025`, kein echter Mailversand.

### Konfiguration

Details: [`backend.md`](backend.md)

[↑ Inhalt](#inhalt)

---

## Admin-Moderations-Queue

`/admin/moderation` — Freigabe/Ablehnung von Problemen und Loesungsansaetzen.

- Zwei Tabs: **Pending** / **Rejected** (Tab-Badge zeigt Gesamt-Anzahl, ungefiltert)
- **Suche:** Filtert live nach Titel, Titel (EN), Beschreibung und Beschreibung (EN)
- **Sortierung:** Toggle "Newest first" / "Oldest first" (`createdAt`)
- Status-Workflow: `pending → needs_review → approved / rejected`
- **`AUTO_APPROVE=true`:** Neue Problems überspringen die Moderations-Queue und wechseln direkt auf `approved`. Feature-Flag wird zur Build-Zeit ins Nuxt-Bundle eingebettet — Änderung erfordert Rebuild + Redeploy.

Filter- und Sortierlogik ist in `useModerationFilter.ts` gekapselt (nicht inline in der Komponente) — 13 Unit-Tests in `useModerationFilter.spec.ts`.

i18n-Keys: `admin.searchPlaceholder`, `admin.sortNewest`, `admin.sortOldest`

### Loesungsansaetze in der Queue

Pending + Rejected Solutions werden als **kombinierte, nach Datum sortierte Liste** angezeigt — keine separate Sektion. Frontend laed beide via `Promise.allSettled` (resilient: ein Fehler blockiert nicht die andere Liste).

Backend: `GET /solutions?status_filter=rejected` erfordert Superuser-Auth fuer alle Nicht-`approved`-Filterwerte.

**Admin-Edit Solutions:** Superuser kann Solution-Inhalte direkt aus der Moderations-Queue heraus bearbeiten — `PATCH /solutions/:id` (Backend). UI: Edit-Formular inline in der Queue-Ansicht, Markdown-Preview-Tab inklusive. Kein Status-Reset — Status bleibt unveraendert (z.B. `needs_review` bleibt `needs_review`). `SolutionUpdate.content`: `Field(min_length=20, max_length=2000)` — gleiche Constraints wie das Submit-Formular.

### duplicate_confirmed Flow

Reicht ein User ein Problem trotz Duplikat-Warnung ein, erhaelt das Problem den Status `needs_review` (statt automatisch `rejected`). Der `rejection_reason="possible_duplicate"` wird in der Admin-Queue als amber Systemhinweis angezeigt (`admin.systemNote` i18n-Key).

Signal-Weg: `ProblemForm.vue` → `signals: ['duplicate_confirmed']` → Backend → AI-Service `hooks.py` → `needs_review` statt `rejected`.

[↑ Inhalt](#inhalt)

---

## Virtuelles Scrollen (Table-View)

`@tanstack/vue-virtual` fuer performante Tabellendarstellung:

- Rendert nur sichtbare Zeilen + 10 Buffer-Zeilen (Overscan)
- Geschaetzte Zeilenhoehe: 53px
- Padding-Spacer oben/unten fuer korrekte Scrollposition
- Tastaturnavigation scrollt automatisch zum naechsten Index
- Skaliert ohne Performance-Einbussen auf tausende Eintraege
