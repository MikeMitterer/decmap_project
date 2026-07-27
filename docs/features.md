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
Live-Check feuert auf beide Felder; gesendet wird [title, description].filter(Boolean).join('\n\n')
(spiegelt die Server-Embedding-Quelle _embedding_text: Titel + Beschreibung, leere Teile fallen weg)
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
(gespeicherte Embeddings basieren auf title_en + description_en — Sprachnormalisierung verhindert DE/EN-Vektor-Mismatch)
      ↓
Treffer (Score > 0.85) → ahnliche Probleme werden angezeigt
Kein Treffer → kein Hinweis, Submission lauft normal
      ↓
Bei Treffer: Submission blockiert bis User bestatigt
"Dieses Problem ist trotzdem neu / anders"
```

### Live-Check-Quelle = Server-Embedding-Quelle

`ProblemForm.vue` `watch([title, description])` füttert `checkSimilarity` mit
`[title, description].filter(Boolean).join('\n\n')` — exakt der Text, den das Backend für das
Embedding nutzt (`_embedding_text`: Titel + Beschreibung, leere Teile fallen weg). Ohne diesen Gleichlauf
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

**Cross-linguale Symmetrie (Option B — [decmap_project#32](https://github.com/MikeMitterer/decmap_project/issues/32), BE `45c419f` → FTS `8982048`):** Der Keyword-Pfad nutzt seit BE `8982048` (F2 Task 3) **Postgres-Volltextsuche** (FTS) statt ILIKE-Substring: pro Sprache (`en`/`de`) matchen **rohe Query und übersetzte Variante** gegen den Sprach-`to_tsvector` via `@@ plainto_tsquery` (funktionaler GIN-Index, Migration 010). Die Query wird beim ersten Such-Call **in beide Sprachen** uebersetzt — das generische `translate_query(text, lang)` (ai-client) holt `q_en` **und** `q_de` vom ai-service. Per-Sprache-**Stemming** macht die Treffermenge flexions-symmetrisch: `q=missing` und `q=fehlend` liefern dieselbe Treffermenge (Unit-Test `test_fts_stemming_symmetry_english_plural` — beweist konkret `company`/`companies`-Stemming + `company`⇄`Unternehmen`-Symmetrie mit gestubbter Uebersetzung), und — anders als beim frueheren ILIKE-Substring — matchen jetzt **flektierte Formen** ueber den Stamm: das Per-Sprache-Stemming vereinheitlicht **Deklinations-/Pluralformen** (`company`/`companies` → `compani`; deutsche Partizip-Deklinationen `Fehlender`/`fehlende`/`fehlend` → `fehlend`). **Grenze (PG16 german snowball):** finite Verbformen werden **nicht** mit dem Partizip vereinheitlicht — `fehlt` → `fehlt` ≠ `fehlend` → `fehlend`; die frueher dokumentierte flexions-abhaengige Restdifferenz ist damit **deutlich reduziert, aber nicht restlos** behoben. Die cross-linguale `missing`⇄`fehlend`-Symmetrie entsteht primaer aus der **Uebersetzung** (q_de=`fehlend`) plus Stemming, nicht aus Stemming allein. Der rohe `q` matcht zusaetzlich gegen **jede** Sprach-Config — uebersetzungs-ausfall-sicher. **Translate-once-pro-Sprache:** Beide Uebersetzungen werden nur auf Seite 1 geholt (max. **zwei** Roundtrips) und reisen im Cursor mit (N-sprachige Übersetzungs-Map unter Key `qt`; BE `4d6279d`, zuvor fixes `q2`=DE); Folgeseiten uebersetzen nicht erneut, und Pre-`qt`-Cursor degradieren ueber `peek_cursor_translations` sauber zu `None` — kein Backwards-Compat-Bruch. Single Source of Truth der Sprachen: `services/search_languages.py` (`SEARCH_LANGUAGES` + `tsvector_sql`, byte-identisch in Index und Query). **Verbleibende Grenze (kein Bug):** Echte Synonyme (lack/missing/absent) matchen weiterhin nicht gegenseitig — Stemming ≠ Synonym-Expansion; fuer konzept-/synonym-gleiche Treffer bleibt die **semantische Suche** (`semantic=`, s.u.) das richtige Werkzeug. **Treffer-Counts DE↔EN sind nicht garantiert identisch (erwartbar, kein Bug — analysiert 2026-06-30):** Die „dieselbe Treffermenge"-Aussage gilt **unter der gestubbten (deterministischen) Test-Uebersetzung**; produktiv ist exakte Parität mit FTS + LLM-Uebersetzung nicht erreichbar — das Designziel ist hohe Ueberlappung (best-effort Recall), nicht identische Counts. Asymmetrie-Mechanik: eine **DE-Query** (`fehlende`) trifft alle deutschen Beugungen direkt ueber den Stamm im Index; die **EN-Query** (`missing`) erreicht dieselben deutschen Zeilen **nur** ueber ihre vom LLM frei formulierte, nicht-deterministische **Einzelwort-Uebersetzung** — liefert das LLM das Partizip `fehlend`, matcht es; liefert es die finite Verbform `fehlt`, stemmt PG auf ein anderes Lexem und die `fehlend*`-Zeilen fallen aus (genau die `fehlt ≠ fehlend`-Grenze oben). Recall haengt also am exakten Uebersetzungs-Token. **Recall-Hebel umgesetzt (Option B, 2026-06-30):** `translate_query(text, lang)` liefert seitdem **mehrere Kandidaten** statt einer Einzelübersetzung — der ai-service-Endpoint `POST /translate/candidates` (`TranslationService.translate_query_candidates`) gibt 1–6 gebeugte Formen + nahe Synonyme als JSON-Array zurueck (gededuped/gecappt, best-effort → `[]` bei LLM-Fehler), und die Per-Sprache-Loop OR-verknuepft **jeden** Kandidaten als eigene `@@ plainto_tsquery`-Klausel (so trifft `missing`→`fehlend`/`vermisst`/… auch deutsche Zeilen, die eine einzelne, evtl. falsch-flektierte Uebersetzung verfehlt haette; Unit-Test `test_multi_candidate_or_expansion` beweist, dass zwei stamm-distinkte Kandidaten beide matchen). **Das opt-in `sort=relevance`-Ranking spiegelt die WHERE-Loop:** der `ts_rank` summiert seit Option B ueber **jeden** Kandidaten × Sprache (nicht-matchende Varianten tragen 0 bei), nicht mehr nur ueber die rohe Einzeluebersetzung — die Relevanz-Reihenfolge kann sich dadurch gegenueber der Einzeluebersetzung leicht verschieben. Der `/translate`-Single-String-Endpoint (Submit-/Display-Uebersetzung) bleibt **unveraendert** — Kandidaten laufen ueber den separaten `/translate/candidates`-Pfad. Die Kandidaten reisen pro Sprache als **Liste** im Cursor (`qt`-Map: `{lang: [forms]}`); `q_translations` ist jetzt `dict[str, list[str]]`. Exakte Treffer-Parität DE↔EN bleibt prinzipbedingt dennoch nicht garantiert (LLM-Uebersetzung nicht-deterministisch) — Ziel ist hoeherer, nicht perfekt symmetrischer Recall.

> **F2 (2026-06-28 — Keyword-FTS + Relevanz-Ranking gelandet, BE Tasks 1–4):** Die registry-getriebene **Postgres-Volltextsuche** (`to_tsvector`/`plainto_tsquery`, Per-Sprache-Stemming, funktionale GIN-Indizes) **ersetzt ILIKE** im `q`-Keyword-Pfad und **reduziert** die flexions-abhaengige Restdifferenz deutlich (Deklinations-/Pluralformen werden ueber den Stamm vereinheitlicht; finite Verbformen wie `fehlt` bleiben unter PG16 german snowball distinkt vom Partizip `fehlend`). **Task 1 (BE `b7563e9`):** Sprach-Registry `services/search_languages.py` (`SEARCH_LANGUAGES` + `tsvector_sql`) als Single Source of Truth + Migration 010 mit funktionalen GIN-Indizes `ix_problems_fts_en` / `ix_problems_fts_de` (en/de, immutable Sprach-Snapshot). **Task 2 (BE `4d6279d`):** Cursor-`q_translations`-Map (N-sprachfaehig). **Task 3 (BE `8982048`):** ILIKE→FTS im Query-Pfad. **Task 4 (BE `59a2b29`):** opt-in Relevanz-Ranking `sort=relevance` (Σ `ts_rank` über die Registry-Sprachen, `ORDER BY rank DESC` + Keyset `(rank, id)`, Cursor traegt `rank` + `q_translations`; ohne `q` Fallback auf `created`; [#37](https://github.com/MikeMitterer/decmap_project/issues/37)). **Task 5 (FE `d3a6950`):** Frontend-`sort=relevance`-Opt-in — `keywordRelevanceEnabled` schaltet `query.sort = 'relevance'` (`dir` entfällt) und erweitert `relevanceSortActive` (s.u.), sodass StatusBar-Hinweis + Sort-Header-Sperre auch im Keyword-Modus greifen. **Nachtrag (FE `f52f1ea`, 2026-06-30):** Der ursprüngliche „Sort by relevance"-Toggle-Button (`table.sortByRelevance`) in der `DmTopBar` ist **entfernt** — Relevanz ist bei aktiver Keyword-Suche (Begriff vorhanden, KI-Suche aus) jetzt **Default-an** (am Übergang in diesen Zustand gesetzt, damit manuelles Aus das Weitertippen überlebt), ein Klick auf **irgendeinen** Spalten-Header verlässt sie (kein expliziter Rückweg innerhalb derselben Suche), und die Sort-Header sind nur noch im **Semantik**-Modus gesperrt; Details in „Sprachunabhängige Suche" oben. **Task 6 (BE `820083e`):** Extensibility-Smoke-Test `test_third_language_needs_only_registry_and_index` (patcht `SEARCH_LANGUAGES` um `fr`, legt den funktionalen `fr`-Index zur Laufzeit an, beweist: 3. Sprache = Registry-Eintrag + Index, **kein** Code-Change im WHERE/Ranking) + diese Doku. **Final-Review (I-1):** Die Persist-Allowlist `_ALLOWED_TRANSLATION_LANGS` (in `routers/problems.py`, von `_filter_translations` auf eingehende `original_translations` erzwungen) wird jetzt **aus `SEARCH_LANGUAGES` abgeleitet** (Vereinigung mit dem hartkodierten Accept-Set `{de,fr,es,it,pt,nl,pl}`) — so wird der vom User eingereichte Originaltext einer neu registrierten Such-Sprache automatisch persistiert; zuvor haette eine Such-Sprache **ausserhalb** des hartkodierten Sets ihren Originaltext still gefiltert bekommen und die „Registry + Index, kein Code-Change"-Zusage unterlaufen. FTS ist seit der Test-DB-Umstellung auf Postgres (Konventionen Fund 40) ohne `skipif` testbar. Design: [`docs/specs/2026-06-27-f2-cross-lingual-search-design.md`](specs/2026-06-27-f2-cross-lingual-search-design.md), Plan: [`docs/plans/2026-06-27-f2-cross-lingual-search.md`](plans/2026-06-27-f2-cross-lingual-search.md).

**Frontend — Local-Match:** `utils/problemSearch.ts` matcht die Suchquery sofort gegen den **angezeigten** (lokalisierten) Titel der bereits geladenen Nodes — „tippe was du siehst" ohne Backend-Roundtrip. Seit Server-Driven Search Phase 1 (s.u.) nur noch im **Graph** (`pages/index.vue`, F2); `pages/table.vue` sucht jetzt server-seitig (`GET /problems?q=`) und hat den Client-Local-Match entfernt.

### Datenmodell & Skalierung (Stand 2026-06-25 — Server-Driven Search Phase 1 + Phase 2 Drill-Down)

**Table + Suche sind server-paginiert.** `GET /problems` liefert seit Phase 1 eine **Keyset-paginierte Seite** statt des kompletten Sets: `{ items, next_cursor, total }`, `limit` default 50 (Hard-Cap 100), zustandsloser base64-Cursor. Parameter:

- `sort` — `created` (default) / `votes` / `title` / `solutions` / `status` / `tag` / `company` / `relevance` (Keyset pro Modus). `relevance` ist opt-in und greift nur mit `q` (Σ `ts_rank` über die Registry-Sprachen **und alle Übersetzungs-Kandidaten** pro Sprache (Option B, BE `6fd5c1d`), `ORDER BY rank DESC` + Keyset auf `(rank, id)`; ohne `q` Fallback auf `created`; BE `59a2b29`, F2 Task 4). `tag` sortiert nach dem Struktur-/Cluster-Tag-Namen (MIN über `tags.level<10`, `''`-Bucket für unclustered); `company` sortiert nach der Firma des Autors (Outer-Join `users`, `coalesce(User.company, '')` als NULL-freier Keyset-Key — anonyme/firmenlose Probleme landen im `''`-Bucket, gleiche Mechanik wie `tag`); `status` über `(status, id)` — analog `title`; ohne diesen Modus fiel `sort=status` auf `created` zurück, sodass die Table auf Seite 1 gruppiert wirkte, beim Infinite-Scroll aber wieder gemischte Status nachlud.
- `dir` — `asc` | `desc`, server-seitig für **jeden** Sort-Modus wirksam (seit BE `440cb3e`/FE `37cff86`). Fehlt `dir`, gilt der Default je Modus (`created`/`votes`/`solutions` desc, `title`/`status`/`tag`/`company` asc); ungültiger Wert → 422. Die effektive Richtung reist im **Cursor** mit (kompakter Key `d`): auf Seite 2+ gewinnt die Cursor-Richtung, `dir` wird ignoriert → die Ordnung bleibt über alle Infinite-Scroll-Seiten konsistent. Der `id`-Tiebreaker folgt immer der Primärrichtung, damit der Keyset-Vergleich korrekt bleibt.
- `q` — cross-lingualer **Keyword**-Modus: **Postgres-FTS** (OR-kombiniert) — pro Sprache (`en`/`de`) matchen **rohe Query und alle übersetzten Kandidaten** (Multi-Kandidaten, Option B) gegen den Sprach-`to_tsvector` via `@@ plainto_tsquery` (funktionaler GIN-Index, Migration 010; ersetzt das frühere ILIKE, BE `8982048`, #32). Per-Sprache-**Stemming** vereinheitlicht Deklinations-/Pluralformen ueber den Stamm (`company`/`companies`, deutsche Partizip-Deklinationen `fehlende`/`fehlend`) — finite Verbformen (`fehlt`) bleiben unter PG16 german snowball distinkt; cross-linguale Symmetrie kommt aus Uebersetzung + Stemming. Die Query-Übersetzung holt das Backend beim ersten Such-Call (cursor=null) **je einmal pro Sprache** vom ai-service (max. zwei Roundtrips) und reicht sie über den Cursor an Folgeseiten weiter (N-sprachige Übersetzungs-Map unter Cursor-Key `qt`; BE `4d6279d`, zuvor fixes `q2`=DE); Details s.o. „Sprachunabhangige Suche".
- `semantic` — **Embedding-Distanz**-Ranking; ignoriert `sort`, ist **exklusiv** zu `q`. Das Query-Embedding holt das Backend einmal via `POST /embeddings/internal/embed-query` und transportiert es zustandslos im Cursor. Die gespeicherten Problem-Embeddings entstehen aus **Titel + Beschreibung** (`_embedding_text`: `title_en` + `description_en`, `\n\n`-getrennt, leere Teile fallen weg — s. oben „Live-Check-Quelle" + [`data-model.md`](data-model.md)), damit ein Begriff, der nur im Titel steht, ebenfalls in den Vektor einfliesst und in der Semantik-Suche matcht. **Hinweis:** Die absoluten Match-Scores bei diesem Embedding-Modell sind gestaucht (30–40 % kann ein guter Treffer sein) — die Reihenfolge ist **ordinal** zu lesen, 1 %-Punkt Differenz ist Rauschen. Für rein **lexikalische** Titel-Treffer bleibt die Keyword-Suche (`q`, FTS über Titel **und** Beschreibung) das präzisere Werkzeug. **Embedding-Quellen-Wechsel:** Nach jedem Deploy dieser Änderung müssen die Embeddings via `POST /embeddings/reindex` (Service-Token) neu erzeugt werden — sonst sind alte (description-only) Vektoren stale.
- Server-Filter `tags` (Subtree-expandiert, AND), `regions` (OR), `user` (komma-separiert → `IN`), `company` (komma-separiert → case-insensitive ILIKE-OR, zu User-IDs aufgelöst); `status_filter` (default `approved`; `all` = keine Status-Einschränkung; jeder Nicht-`approved`-Wert inkl. `all` → Superuser). `all` greift im Keyword- **und** Semantik-Pfad (geteiltes `base_where`).

`pages/table.vue` ist Infinite-Scroll auf Basis von `useProblems` als **Cursor-Store** (`loadFirstPage`/`loadNextPage`, Race-Guard via `requestVersion`); „N von M" = geladene Items von `total`. Die früheren Client-Filter (`filteredProblems`/`matchesQuery`/`adminSearchIds`/`localizedTitles`-als-Suchindex) sind entfernt; die Titel-Spalte zieht den lokalisierten Titel direkt aus `originalTranslations[locale]?.title` des geladenen Objekts — kein `/translate`-Call pro Problem mehr (der frühere teuerste Posten). `admin/moderation.vue` nutzt denselben Endpoint mit `status_filter=pending|rejected` statt Client-Status-Filter. In der Table sendet ein **Admin** explizit `status_filter=all` (sieht alle Status: approved/pending/rejected/needs_review), ein normaler User `approved` — das Auslassen des Parameters defaultet server-seitig auf `approved`, was den Admin sonst nur approved sehen ließe (Phase-1-Regression, behoben 2026-06-24). Einen UI-Status-Wähler gibt es nicht; der Admin sieht per Default alles. Die **Status-Spalte** mappt auf `sort=status` und ist damit über **alle** Infinite-Scroll-Seiten konsistent gruppiert (BE `934fbf5`, FE `711f5eb`); die **Tag-Spalte** sortiert seit BE `440cb3e`/FE `37cff86` server-seitig über `sort=tag` (Struktur-/Cluster-Tag-Name) statt des früheren `created`-Fallbacks — die „auf Seite 1 sortiert, danach gemischt"-Illusion ist damit behoben. Auch der **Sort-Richtungs-Toggle** ist seit denselben Commits server-seitig wirksam: die Table sendet `sortDirection` als `dir`, der Pfeil ↑/↓ kehrt die Ordnung über alle Seiten konsistent um (Richtung reist im Cursor; vorher ein dokumentierter No-op). **Firmen-Spalte (sortierbar):** Die Table rendert eine eigene **Company**-Spalte (`hidden lg:table-cell`, vor „Submitted") und sortiert sie server-seitig über `sort=company` (s.o.). Die Firma des Autors reist dafür auf **jedem** `ProblemRead` mit (`company`-Feld, `None` für anonyme Probleme) — pro Seite via `_load_authors()` (vormals `_load_companies`; holt seit BE `2e9946f` `company` **und** `display_name` in einer Query) über **einen** gebatchten Query auf die Autor-`user_id`s aufgelöst (kein N+1, spiegelt `_load_junctions`), sowohl in `list_problems` als auch im Semantik-Pfad. **Auch der Detail-Pfad trägt sie jetzt (BE `d8410fd`):** `GET /problems/{id}` baute sein `ProblemRead` früher via `_to_read()` ohne Profil-Auflösung — nur die Liste füllte `company`/`author_display_name`. Der neue DRY-Helper `_read_with_author()` löst das Profil (wie die Liste) und wird von **allen** Single-Problem-Pfaden genutzt (Detail-GET + create/update/delete-Responses), sodass jedes `ProblemRead` die Felder konsistent trägt (+ Regressions-Test: Detail-GET liefert `author_display_name`/`company`) — Live-Fund beim T-14-Browser-Check (Full-Page-Problem-Kontext-Band lädt via `fetchProblemById` → Detail-GET und zeigte deshalb nie Autor/Firma). Die Zelle rendert die Firma als kompakten farbigen **Monogramm-Badge** (`utils/companyBadge.ts`): 1–2 Initialen via `companyInitials()` (Mehrwort → erste Buchstaben der ersten zwei Wörter, überspringt Nicht-Buchstaben — „3M Systems" → `MS`), Voll-Name im `title`-Tooltip, deterministische Farbe via `companyColor()` — das hält die Spalte schmal (ursprünglich ~56px aufs Avatar-Icon dimensioniert, später auf 88px erweitert, damit der EN-Header „COMPANY" passt — s.u.) statt eines breiten Klartext-Felds. Beide Util-Funktionen teilen sich die Cluster-Dot-Palette: `tagColor.ts` wurde DRY-refactored auf ein generisches `colorFromString(key)`, das `tagColor()` (Tag-ID) **und** `companyColor()` (lowercase-getrimmter Firmenname) aufrufen — gleiche 12-Farben-Palette, gleiche Identitätsfarbe wie die Cluster-Dots. Klick auf den Badge setzt direkt den bestehenden `company`-Filter (konsistent mit Tag-/Autor-Chips); anonyme/firmenlose Probleme zeigen „—". **Kompakt-Modus bei offenem Panel (FE `27fa7a9`):** Ist das Detail-Panel offen (`isPanelOpen` → Tabelle ~70% Breite), bekommt die `<table>` die Klasse `table-compact`; der Selektor `.dm-table.table-compact .compact-hide { display:none }` blendet die Sekundärspalten **Cluster** und **Eingereicht** aus, damit `table-fixed` den frei werdenden Platz automatisch der flexiblen Title-Spalte gibt, statt sie auf wenige Zeichen zu quetschen. Die 3-Klassen-Spezifität schlägt Tailwinds `lg:table-cell` (1 Klasse) **quellreihenfolge-unabhängig**. Sichtbar bleiben Title, Votes, Solutions, Company-Badge, Status; Panel zu → alle Spalten zurück. Begleitend wurden die fixen Spaltenbreiten generell gestrafft (Votes 150→84, Solutions 130→84, Status 92→72, Cluster 220→180, Eingereicht 132→120). **EN-Header-Nachzug (FE `64ae95e`):** Bei `table-fixed` sind die Inline-Style-Breiten hart; die längeren englischen Header („SOLUTIONS"/„COMPANY") sind breiter als die deutschen („Lösungen"/„Firma") und liefen mit `whitespace-nowrap` aus ihren auf den DE-Header bzw. das Avatar-Icon dimensionierten Zellen in die Nachbarn — nachgezogen auf Solutions 84→104 und Company 56→88 (px-Padding + Sort-Caret eingerechnet). Die `w-full`-Title-Spalte absorbiert die Mehrbreite, die DE-Header passen weiterhin; da es Inline-Style-Breiten sind (kein Tailwind-`w-[…]`), greift die Änderung sofort beim Reload ohne Dev-Rebuild. **Multi-Value-Filter (BE `30487a1` / FE `bde9361`, #35):** `user`/`company` akzeptieren komma-separierte Mehrfachwerte — `user` als `IN`, `company` als case-insensitive ILIKE-OR (zu User-IDs aufgelöst); die Table sendet alle gewählten Werte (`userFilterIds`/`companyFilters` `.join(',')`), nicht mehr nur den ersten. **Company-Filter (FE `fc68cf6` → Revert `ebb759f`, #29):** Das Firmen-Filtern ist über das violette Firmen-Chip im Problem-Panel (emittiert den exakten Voll-Namen), den `?company=`-URL-Parameter und die aktiven Firmen-Filter-Chips in der Tabelle (je mit × entfernbar) erreichbar. Ein stets sichtbares Freitext-Eingabefeld über der Chip-Leiste wurde in `fc68cf6` eingeführt und in `ebb759f` wieder **entfernt** (samt toter i18n-Keys `companyFilter`/`companyFilterPlaceholder`). **Live-Verify-Erkenntnis (2026-06-27, F1):** `User.company.ilike(n)` matcht den **ganzen** Wert ohne Wildcards — eine Teil-Eingabe (`Acme`) trifft die Seed-Firma `Acme Manufacturing GmbH` **nicht** (0 Treffer); nur der exakte, vollstaendige Firmenname (oder der Panel-Chip, der ihn emittiert) filtert. Für ein **Freitext**-Feld widerspricht das der Nutzererwartung — daher der Revert statt eines Substring-Patches (`%n%` in `_build_filter_clauses` wäre ein Ein-Zeilen-Patch, bewusst offen gelassen). Der Firmenname ist zusätzlich ein **optionales Feld bei der Registrierung** (`pages/login.vue` Register-Tab → `company` im Register-Call, `autocomplete="organization"`) und bleibt ein editierbares Profil-Feld in den Settings (`pages/settings.vue`). Der `user`-Filter hat weiterhin nur den Chip-Einstieg (kein eigenes Eingabefeld). **Panel-Chip-Klarheit (FE `25ffffb`, #30):** Autor- und Firmen-Chip im Problem-Panel (`ProblemPanel.vue`, emittieren `user-filter`/`company-filter`) tragen je ein 👤/🏢-Icon plus `aria-label`/`title`-Tooltip (`panel.filterByAuthor`/`panel.filterByCompany`), damit sie unterscheidbar sind; die Smaragd/Violett-Farbgebung bleibt unverändert (die im Ticket angedachte sekundäre theme-konforme Farbe wurde descoped). **Firmen-Chip entkoppelt vom `userCache` (FE `9b8f357`, #30):** Der ganze Autor-/Firmen-Block hing zuvor an `v-if="author"` — `author = getUserById(problem.userId)` stammt aus dem clientseitigen `userCache`, der nur den **eingeloggten** User auflöst, also war er für normale Betrachter `null` und der Block (inkl. Firmen-Chip) blieb komplett unsichtbar (Symptom: „Firma nirgends angezeigt"). Fix: Das 🏢-Chip liest die Firma direkt aus `problem.company` (auf **jedem** `ProblemRead` vom Backend geliefert, seit der Company-Spalten-Arbeit) statt aus `author.company`, der Wrapper gated auf `author || problem.company`, und das 👤-Autor-Chip bleibt best-effort (`v-if="author"`). Damit erscheint das Firmen-Chip bei **jedem** Problem mit gesetzter Firma, nicht mehr nur bei eigenen. Klick emittiert weiterhin `company-filter` → in der Table persistiert der Filter über den `?company=`-URL-Param (bestehender `useTableFiltersUrl`-Watch); die Graph-View hält ihre Filter bewusst In-Memory (`reloadCurrentView()`) und persistiert den Firmen-Klick **nicht** in die URL — eine View-übergreifende URL-Persistierung bleibt bewusst außerhalb dieses Fixes. **Autor-Chip nachgezogen (BE `2e9946f` / FE `70f8a84`, #30):** Gleiche Klasse wie der Firmen-Fix — das 👤-Autor-Chip hing weiter an `getUserById(problem.userId)` aus dem `userCache` (nur der eingeloggte Betrachter), war für fremde Autoren also `null` und unsichtbar. Fix: Der Autor-Name reist jetzt als `ProblemRead.author_display_name` auf **jedem** Item (gebatcht via `_load_authors`, das `company` + `display_name` in einer Query holt; das frühere `_load_companies` ist darin aufgegangen). `ProblemPanel` rendert das Chip aus einem `authorLabel`-Computed (`problem.authorDisplayName` zuerst, dann Cache-Fallback `displayName`/`email`) und gated es darauf statt auf `v-if="author"`; `user-filter` emittiert `problem.userId`. Damit erscheint auch das Autor-Chip bei **jedem** nicht-anonymen Problem (2 neue Backend-TDD-Tests). **Filter-Chip-Label statt UUID (FE `f2d133a`, #30):** Der aktive User-Filter-Chip (oben in Table- und Graph-View) labelte sich aus `getUserById(userId)` — derselbe `userCache`, der nur den eingeloggten Betrachter kennt — und fiel für fremde Autoren auf die rohe `userId` (UUID) zurück. Neuer `userFilterLabel(userId)`: Client-Cache zuerst (`displayName`/`email`), **sonst** den `authorDisplayName` aus den geladenen `problems` ziehen (beim User-Filter enthält die Liste genau dessen Probleme, die den Namen vom Backend tragen — greift sowohl beim Chip-Klick als auch beim URL-Einstieg `?user=<uuid>`), UUID nur noch als allerletzter Fallback (Autor ohne gesetzten Anzeigenamen). Der **Semantik-Modus liefert seit BE `9f61d27` (#28) den Treffer-Score mit** — `_list_problems_semantic` setzt `ProblemRead.score = 1 − Distanz` pro Item, **auf [0,1] geklemmt** (Cosine-Distanz reicht bis 2 — ungeklemmt würde der Match-Score negativ; BE `6aa33e5`, #28 Review). Im Keyword-/Default-Modus `None`; Cursor-Contract unverändert. Der **Frontend-Data-Layer mappt den `score` inzwischen auf den `Problem`-Typ** (`mapProblem` in `data/real/realProblems.ts`, `score?: number`; `undefined` wenn das Backend keinen liefert). Die **UI-Affordanz ist seit FE `868a6bb` (#28) umgesetzt** und hängt seit FE `d0981ab` an `relevanceSortActive` statt am bloßen KI-Toggle. Seit FE `d3a6950` (F2 Task 5) deckt `relevanceSortActive` **beide** Relevanz-Pfade ab: `layouts/default.vue` definiert es als `semantic || keyword` — `semantic` = KI-Suche an **und** Suchbegriff vorhanden, `keyword` = KI-Suche **aus** + Suchbegriff + `keywordRelevanceEnabled` — und `provide`-t es (samt `keywordRelevanceEnabled`) an Table und StatusBar. **Relevanz ist im Keyword-Modus Default-an (2026-06-30):** `layouts/default.vue` schaltet `keywordRelevanceEnabled` per `watch([searchQuery, aiSearchEnabled], ([q, ai], [oldQ, oldAi]) => …)` **standardmäßig an**, sobald der aktive Keyword-Such-Zustand (`q.trim() && !ai`) betreten wird (`active && !wasActive`) — die beste-Treffer-Reihenfolge ist der Default. Das Einschalten geschieht **nur am Übergang**, nicht bei jedem `watch`-Lauf — so überlebt ein manuelles Aus (= Spalten-Klick, s.u.) das Weitertippen am Suchbegriff (und es greift auch, wenn die KI-Suche bei vorhandenem Begriff ausgeschaltet wird). Verlassen des Zustands (Suchfeld leer **oder** KI-Suche an → `!active`) resettet auf `false` (kein hängender Relevanz-Zustand); eine neue/geleerte Suche startet wieder bei Relevanz. **Spalten-Klick verlässt Relevanz, expliziter Toggle-Button entfernt (2026-06-30):** Den früheren „Sort by relevance"-Button (`table.sortByRelevance`) in der `DmTopBar` gibt es **nicht mehr** — `toggleSort()` in `pages/table.vue` setzt `keywordRelevanceEnabled = false`, sodass ein Klick auf **irgendeinen** Spalten-Header die Relevanz verlässt und die geladenen Treffer nach dieser Spalte sortiert (innerhalb derselben Suche kein expliziter Rückweg zur Relevanz mehr — der kommt über eine neue/geleerte Suche; der i18n-Key `table.sortByRelevance` ist damit verwaist). **Sort-Header nur im Semantik-Modus gesperrt:** Im **Semantik**-Pfad ordnet das Backend server-seitig nach Embedding-Distanz, Spalten-Sort wird dort nicht unterstützt — `pages/table.vue` sperrt die Header daher nur bei `semanticActive` (`semanticSearchEnabled && q.trim()`) via `opacity-40 pointer-events-none` + Tooltip `table.relevanceTooltip`. Im Keyword-Relevanz-Default bleiben die Header **klickbar** (der Klick ist der Ausstieg). Damit kein irreführender Sort-Pfeil (z.B. auf „Submitted") während aktiver Relevanz erscheint, gated ein `activeColumn`-Computed (`relevanceSortActive ? null : sortKey`) die Pfeil-Anzeige. Im Keyword-Pfad sendet die Table `sort=relevance` (`dir` entfällt) statt des Spalten-Sorts. **`keywordRelevanceEnabled` im Lade-Trigger-`watch` (Fix, 2026-06-30):** Der Ref muss im Lade-Trigger-`watch` von `pages/table.vue` stehen (`watch([searchQuery, …, companyFilters, keywordRelevanceEnabled])`) — fehlt er dort, setzt der Wechsel zwar `query.sort='relevance'`, aber `useProblems` lädt nie neu (Klasse: ein neuer Reactive-State, der die Anfrage verändert, muss in den Trigger-`watch`, nicht nur ins Query-Building). Das pro-Zeile-Match-Score-Badge (`table.matchScore`, `{n}% match` — bewusst auch auf DE englisch, **nicht** „Übereinstimmung", konsistent mit dem EN-Label; `Math.round(score × 100)`) rendert weiterhin **nur** wenn `score != null` — also im **Semantik**-Modus (das Backend liefert `score` nur dort; der Keyword-`ts_rank` wird nicht als `score` exponiert). **AI-Match-Badge-Treatment (FE `94c57e3`):** Der rohe Cosine-„% match" ist ein KI-Showcase-Asset, kein zu versteckender Wert — das Badge trägt ein 4-Punkt-Funkel-Icon, den Prozentwert, einen Mini-Relevanzbalken (24×3px) und einen erklärenden Tooltip (`table.matchScoreHint`). **Balken relativ zum besten Treffer normiert (FE `ab8b9f9`):** Der Balken füllt sich **nicht** auf den absoluten `score %`, sondern auf `matchBarWidth(score) = score / maxMatchScore × 100` (geclamped auf 100, 0 ohne Score) — `maxMatchScore` ist der höchste Score der aktuell geladenen Treffer (computed in `pages/table.vue`). Grund: die absoluten Cosine-Scores sind gestaucht (30–40 % ist ein guter Treffer, s. `semantic` oben), ein absolut gefüllter Balken säße bei jedem Treffer weit links und machte Rangunterschiede unsichtbar; relativ zum Listen-Maximum füllt der beste Treffer den Balken nahezu, schwächere skalieren sichtbar dazu. **Der Prozenttext daneben bleibt der rohe absolute Score** (`Math.round(score × 100)`) — der Balken ist ein „Relevanz **innerhalb dieser** Ergebnisse"-Indikator (derselbe Treffer kann je nach Query unterschiedlich breit erscheinen), der absolute %-Wert bleibt die verlässliche Zahl. Eingefärbt wird es **nicht** mit `--th-accent`, sondern mit einem eigenen **`--th-ai-accent`**-Token (`rgb(var(--th-ai-accent)/…)`, s. AI-Akzent-Token unten) — die erste Referenz-Instanz des KI-Marker-Designsystems ([decmap_project#39](https://github.com/MikeMitterer/decmap_project/issues/39)). KI-Suche an **bei leerem Suchfeld** → normale, voll sortierbare Liste ohne Sperre und Hinweis (die Semantik-Query selbst feuert weiterhin am Toggle, doch ohne Term gibt es keine Relevanz-Ordnung zu schützen). Der **„Sortiert nach Relevanz"-Hinweis (`table.sortedByRelevance`) sitzt seit FE `41a33f2` links unten in der StatusBar** (vorher als Banner über dem Table-Header): `StatusBar.vue` `inject`-t dasselbe `relevanceSortActive` und zeigt den Hinweis (Akzent-farbiges Label) nur dann — `v-if` entfernt ihn beim Aufheben komplett aus dem DOM, eine CSS-`@keyframes`-Animation lässt ihn beim Erscheinen 3× blinken (`prefers-reduced-motion: reduce` schaltet sie ab; das Remount via `v-if` spielt den Blink bei jedem Wieder-Einschalten neu). Die ausgegrauten Sort-Header bleiben als In-Table-Affordanz. Keyword-/Default-Modus unverändert (Badge und Hinweis aus); der opake Cursor-Contract bleibt unangetastet. Contract: `useProblemsPagination.spec.ts` deckt das `score`-Mapping ab (übernommen / `undefined` ohne Backend-Wert) und seit FE `d3a6950` die `sort=relevance`-Wire-Serialisierung (`loadFirstPage({ q, sort: 'relevance' })` → `sort=relevance` im Query-String).

**Der Graph drillt seit Phase 2 (Task 2.3, FE `5bf4a44`) auf das `cluster-summary`-Aggregat** statt alle Probleme zu laden: `pages/index.vue` lädt bei Mount nur `fetchClusterSummary()` (+ Tag-Hierarchie); ein Klick auf einen Cluster lädt dessen Problem-Zeilen lazy über den paginierten `GET /problems?tags=<id>` (`loadFirstPage` + Restseiten via `loadNextPage`), die Suche läuft server-seitig (`loadFirstPage({ q | semantic })`). Der client-seitige `filteredProblems`-Local-Match ist entfernt, `isEmpty` kommt aus dem Aggregat, und WS-Events (`problem.created`/`deleted`, `clustering.completed`) re-fetchen via `refreshOverview()` die `cluster-summary` statt des früheren Voll-Sets. Der Übergangs-Endpoint `GET /problems/all` (= `list_all_problems`, nur `approved`, Hard-Cap) und die Data-Layer-Methoden `fetchAllProblems()` + der `fetchProblems()`-Alias sind seit **Task 2.4** entfernt (BE `routers/problems.py`, FE `realProblems.ts`/`types.ts`) — der Graph lief schon vorher ausschließlich über das Aggregat + Drill-Down. **Phase 3** ersetzt den Re-Fetch bei `problem.created` durch ein „N neue Probleme"-Banner (noch offen). **Backend-seitig steht Phase 2 Task 2.1**: `GET /problems/cluster-summary` (BE `69dab26`) liefert das Aggregat — `max_vote_score`, pro Struktur-Tag (`level < 10`) den Subtree-`problem_count` und `unclustered_count` — ohne alle Problems zu laden; der Subtree-Count nutzt dasselbe portable BFS (`_subtree_tag_ids`) wie der `tags`-Filter (SQLite + Postgres). **Task 2.2** (FE `a378e85` + `42dffab`) ist erledigt: `ProblemGraph.vue` liest `maxVoteScore`, `clusterCounts` (`Map<tagId, count>`) und `unclusteredCount` aus **Props** statt sie aus `props.problems` zu berechnen — inkl. der Unclustered-Such-Badge (`42dffab`), die ihr Label jetzt aus `unclusteredCount` statt `unclustered.length` zieht. Vorbereitung für den Drill-Down, bei dem `props.problems` nur noch den gefilterten Cluster trägt (dann läge `unclustered.length` bei `0`, während die Prop den echten Aggregat-Wert trägt). **Task 2.3** (FE `5bf4a44`) ist erledigt: `pages/index.vue` ist auf `fetchClusterSummary()` + lazy Drill-Down umgestellt (s.o.) — `props.problems` trägt jetzt nur noch den gedrillten Cluster, `ProblemGraph` zieht alle Aggregat-Counts ausschließlich aus den Props. **Task 2.4** ist erledigt: `/problems/all` (Backend-Route + `fetchAllProblems`/`fetchProblems` im Data-Layer) und die verbliebenen Voll-Array-Reste sind entfernt — verbleibend nur noch das Phase-3-„N neue Probleme"-Banner (s.o.). Design + Phasen: [`docs/specs/2026-06-22-server-driven-search-pagination-design.md`](specs/2026-06-22-server-driven-search-pagination-design.md). **Overlap-Fix ([decmap_project#33](https://github.com/MikeMitterer/decmap_project/issues/33)):** Beim Drill-Down hängt `rerender()` in `ProblemGraph.vue` die neuen Nodes aus `buildGraphElements()` an, die ohne Position bei (0,0) starten — Cytoscape zeichnete einen gestapelten Frame, bevor das synchrone `preset`-Layout sie positionierte. Fix: nur `elements().remove()` + `add()` laufen in einem `cy.batch()`, das Rendering wird bis nach dem Layout zurückgehalten — kein Aufblitzen überlappender Nodes/Labels mehr. **Korrektur (2026-06-30, FE `components/ProblemGraph.vue`):** `cy.style(buildStyle())` lag ursprünglich **innerhalb** dieses Batch — ein im selben Batch gesetzter Style greift aber **nicht** auf die im selben Batch hinzugefügten Elemente; sie fielen auf Cytoscape-Defaults zurück (graue, dicke Haystack-Edges + 30px-Grau-Default für die Dekorations-Knoten `cluster-dot`/`cluster-count-badge`). Symptom: »fette graue Edges + graue Punkte nach Klick auf ein Problem«. Fix: `cy.style()` **vor** den `cy.batch()` gezogen — der Batch enthält nur noch `remove()`+`add()`; ein Fix behebt Edges **und** Dots, da beide dieselbe Ursache hatten. **Drill-Fit (2026-06-30):** Gedrillte Views (`showUnclusteredView`/`applyTagFilters`) layouten mit `fit: true` — das fittete aber die Dekorations-Badges (`cluster-dot`/`cluster-count-badge`/`vote-score-badge`) mit, die zu dem Zeitpunkt noch bei (0,0) liegen, blähte die Fit-bbox auf und hinterließ einen falschen, zu niedrigen (~67%) Zoom. Fix: Layout **und** Fit laufen nur noch auf den **echten** Knoten (`.problem-node, .inner-cluster-node, .leaf-cluster-node, .root-node, .unclustered-node` — Badges ausgeschlossen), und `fitDrillView()` (im `stop:`-Callback bzw. Non-Animate-Pfad beider Layouts) fittet nach dem Settle erneut auf genau diese Knoten. Das behebt beides: den Unter-Zoom durch Badge-Inflation **und** den Über-Zoom auf dünnen Clustern (wenige Nodes → `fit` skaliert über 100%); nur der Viewport-Zoom ändert sich, die Modell-Positionen bleiben unverändert. **Instanter Kamera-Fit (2026-07-01):** `fitDrillView()` fittet instant nur auf die Echt-Knoten (`cy.fit(real, 56)`) und deckelt danach via `cy.zoom(FIT_MAX_ZOOM = 1)`/`cy.center` auf 100%, falls der Fit darüber landet — kein `cy.animate`. Ein zwischenzeitlich probierter animierter Kamera-Glide (200ms) wurde wieder entfernt: der Kamera-Flug las sich als eigenständige, störende Animation, während der Drill ein sauberer Schnitt in den Endzustand sein soll. `addTagFilter` drillt entsprechend non-animiert (`applyTagFilters(false)`). **Overshoot-Fix (2026-07-01):** Bis dahin zoomte der Drill-`fit` ungecappt (Layout-`fit: true` zielte ungebremst) auf ~120–130% und schnappte erst danach via `fitDrillView`-Cap auf 100% zurück — sichtbares Überschießen. Fix: `maxZoom` wird **vor** `layout.run()` temporär auf `FIT_MAX_ZOOM` (100%) gesetzt und im `stop:`-Callback bzw. Non-Animate-Pfad wieder auf `GRAPH_MAX_ZOOM = 3` (den manuellen Zoom-Deckel aus `initGraph`) restauriert. Dadurch landet der Fit direkt auf ≤100%, statt zu überschießen und zurückzuschnappen — der Deckel schützt so auch den jetzt instanten (non-animierten) Drill-`fit`. **Layout-Strategie (2026-06-30):** `buildProblemsGridPositions` rechnete den Pitch früher als Bruchteil des Containers (`usableW`/`usableH`) plus situative Locale-Offsets — jede Achse handelte mit der anderen und dem Item-Count, DE-Labels (~25% höhere Nodes, s. `buildStyle` `n()`) ließen die Reihen sich berühren. Ersetzt durch **node-relatives Spacing + feste Gutter**: `cellW = problemW + GUTTER_X`, `cellH = problemH + GUTTER_Y`, `TIER_GAP` zwischen Anchor → Children → Grid — jeder Abstand eine unabhängige Konstante aus Node-Footprint + festem Gap (alle mit `s = 1` EN / `1.25` DE skaliert). Die **Spaltenzahl** wählt `buildProblemsGridPositions` als die, die den Fit-Zoom für den aktuellen Container **maximiert** (Schleife über alle Spaltenzahlen, `cols` = arg max `min(availW/contentW, availH/contentH)`) — statt `round(sqrt(...))`, dessen Rundung bei winziger Aspekt-Änderung die Spalten (und damit Zeilen und Fit) umspringen ließ und die eigentliche Ursache des instabilen 67%↔99%-Zooms war; die Gutter bleiben fix, nur die Grid-**Form** adaptiert. Die Tiers werden in ihrer natürlichen Größe ausgelegt (dürfen den Viewport überschreiten); das **eine** zoom-gecappte `fit` (≤100%, s.o.) skaliert das Ganze uniform in den verfügbaren Platz, die Gutter skalieren proportional mit. **Resize-Adaption (2026-06-30):** Cytoscape erkennt Container-Größenänderungen nicht selbst — öffnet sich das Detail-Panel (Graph schrumpft auf ~70%), bliebe der Graph auf der alten Breite zentriert und rutschte unter das Panel. Ein `ResizeObserver` auf `containerRef` ruft bei jeder Breitenänderung `cy.resize()` + (280ms-debounced) `reapplyCurrentLayout(false)` — re-runt `applyTagFilters` (gedrillt) bzw. `showMindmap` (Übersicht) mit dem zoom-gecappten `fit`, sodass der Graph sich immer an den Platz anpasst (Panel auf/zu, Fenster-Resize). Der Debounce ist bewusst 280ms (nicht ~160ms): das Panel öffnet/schließt mit einer CSS-Width-Transition, die den `ResizeObserver` jeden Frame feuert — ein kürzerer Debounce re-fittet mitten in der Animation auf eine Zwischenbreite und hinterlässt einen stale Zoom. Cleanup in `onUnmounted`; jsdom-Polyfill in `tests/setup.ts`. **Re-Klick-No-op (2026-06-30):** `addTagFilter` returnt früh, wenn der Tag bereits aktiv ist — ein Klick auf den schon gedrillten Cluster löst kein erneutes `applyTagFilters` aus (das die identische Ansicht neu fittete/animierte, sichtbar als ruckartiger Zoom-Sprung); nur ein tatsächlich neuer Tag (eine Ebene tiefer drillen) löst Layout + Lazy-Load aus. **Kanten-Dezenz (2026-06-30):** Die Verbindungslinien treten visuell zurück, damit die Knoten hervortreten — `edgeCluster` 0.2→0.12 (dark) / 0.15→0.10 (light), `edgeProblem` 0.12→0.07 / 0.08→0.05, und die Brand-Gradient-Kanten Root→L1 bekommen `line-opacity: 0.55`. **Streaming-Coalescing (2026-07-01):** Beim Drill lädt der Cluster seine Probleme seitenweise nach; jede Seite mutiert `props.problems` und löste bislang ein volles Re-Layout + Re-Fit aus, sodass der Graph durch mehrere Zwischen-Zoom-Zustände „sprang", bevor er sich setzte. Der `watch` auf `props.problems`/`tags`/`problemTags`/`searchActive`/`solutionCounts` ruft jetzt `debouncedRerender()` (140ms) statt `rerender()` direkt — die schnell aufeinanderfolgenden Seiten werden zu **einem** Rerender ~140ms nach der letzten Änderung zusammengefasst, der Graph settlet einmal. Zusammen mit dem instanten Kamera-Fit (s.o.) und dem Vor-dem-Lauf-Zoom-Cap ist der Drill damit ein sauberer Schnitt in den finalen Zustand — die gestreamten Seiten fügen sich zu **einem** Rerender zusammen, es bleiben nur ~2 Zoom-Zustände (z.B. 100→98, unmerklich) statt eines Sprungs durch Zwischenzustände. **Mindmap-Rückkehr — instanter Cut statt Animation (2026-07-01):** Beim **animierten** Zurückwechseln in die Mindmap-Übersicht flogen die Dekorations-Badges (`cluster-dot`/`cluster-count-badge`) quer über den Screen (gemessener Detach: Sprung auf ~608px, dann Flug auf ~95px) — ein animierter `showMindmap` (vom Klick) und ein Rerender überlappten, die Badges wurden mittendrin sichtbar und aus dem Ursprung mit-animiert. Ein zwischenzeitlicher Fix, der die Badges vor `layout.run()` `hide()`te, kaschierte nur das Symptom. Endgültiger Fix: **alle sechs** zuvor animierten `showMindmap`-Aufrufe (`applyTagFilters`-Leerfilter, `removeTagFilter`, `resetPositions`, `resetToMindmap`, zwei in `initGraph`) laufen jetzt **instant** (`showMindmap(false)`) — der Return zur Übersicht ist ein **Cut**, kein Flug, konsistent mit dem instanten Drill; ohne Animation läuft nichts mit (verifiziert: Dot-zu-Parent-Abstand konstant ~95px statt 608→95-Flug). Damit ist der letzte offene Graph-Punkt (Mindmap-Fliegen) erledigt; 143/143 Frontend-Tests grün. **Cluster-Node-Auto-Höhe (2026-07-26, FE `93925f6`):** Lange KI-generierte Cluster-Labels (z.B. „Unified AI Governance Framework Absence") wrappten auf bis zu 4 Zeilen und quollen aus der festen Node-Höhe. Root-, `inner-cluster-node` und `leaf-cluster-node` nutzen jetzt `height: 'label'` + `padding` (12/10px) statt einer fixen `n(...)`-Höhe — die Box wächst mit dem Label, kein Clipping mehr; die Dekorations-Badges (Dot/Count) wandern korrekt mit (Übersicht + Drill live verifiziert). Der Wechsel muss in **beiden** Style-Buildern (Glass **und** Theme) stehen, sonst clippt der jeweils andere Skin weiter. Problem-Nodes bleiben bewusst **fix** — ihre Labels sind vorab getruncated.

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
2. ai-service SpamFilterService:
   Honeypot → signals-Array (≥2 → reject) → LLM Spam-Filter
```

> **Implementierungsstand (Stand 2026-07-08):** Tatsächlich verdrahtet sind
> nur nginx-Rate-Limiting, Honeypot und der LLM-Spam-Filter — alle drei im
> ai-service `SpamFilterService`. Ein DNSBL-Check (`aiodnsbl`) und eine
> backend-seitige `BotDetectionMiddleware` existieren **nicht** im Code; die
> geplanten `BOT_*`-Schwellenwerte (`BOT_SUBMIT_MIN_SECONDS`,
> `BOT_SESSION_MAX_HOURLY`, `BOT_IP_MAX_SESSIONS`) wurden 2026-07-08 als toter
> Config entfernt (nie gelesen). Das `signals`-Array reist zwar Frontend → Hook,
> aber es berechnet aktuell **niemand** behavioral-timing-Signale — durch den
> Pfad fließt einzig `duplicate_confirmed`.

### nginx Rate Limiting

```nginx
limit_req_zone $binary_remote_addr zone=submissions:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=translate:10m   rate=5r/m;

location /ai/problems {
    limit_req zone=submissions burst=3 nodelay;
}

location /ai/translate {
    limit_req zone=translate burst=2 nodelay;
}
```

### Verhaltens-Signale (signals-Array — geplant, nur Plumbing)

Das `signals`-Array wird vom Frontend im Hook-Payload mitgeschickt und im
ai-service `SpamFilterService` ausgewertet:

- 2+ Signale → sofort `rejected`, kein LLM-Call
- genau 1 Signal → `needs_review`, kein LLM-Call
- 0 Signale → LLM-Evaluation

Der **Auswertungs-Pfad** existiert, aber es gibt aktuell keine Instanz, die
behavioral-timing-Signale (`submit_too_fast`, `session_flood`,
`ip_hash_multi_session` etc.) berechnet und einspeist — eine
`BotDetectionMiddleware` ist **nicht** implementiert. Die früher hierfür
vorgesehenen `BOT_*`-Schwellenwerte wurden 2026-07-08 entfernt (toter Config).
Faktisch fließt durch das `signals`-Array nur `duplicate_confirmed`.

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

### LLM-/Provider-Fehler → fail-safe `needs_review` (seit 2026-07-25)

Wirft der LLM-Call in `SpamFilterService` (RateLimit, Quota-Erschöpfung, API-Ausfall),
liefert `FilterResult` **`needs_review` / `moderation_error`** — **nicht** mehr `rejected`.
Da der `problem-submitted`-Hook ein Background-Task ist, hätte eine Provider-Quota-Störung
sonst still **jedes** eingehende Problem abgelehnt (User sieht „eingereicht", Eintrag danach
still verworfen). Jetzt symmetrisch zu `evaluate_solution()`; Auto-Reject bleibt echten
Spam-Verdikten, Honeypot und ≥2 Signalen vorbehalten. Contract-Tests:
`test_llm_failure_fails_safe_to_needs_review` (Hook-Pipeline) +
`test_evaluate_llm_error_fails_safe_to_needs_review` (Service). Der fail-safe hält den
Eintrag zwar, verbirgt aber das system-kritische Provider-Problem — eine **Admin-Benachrichtigung**
bei Provider-Quota/-Ausfall (Logging → Telegram) ist als eigener Blocker separat offen
([decmap_project#40](https://github.com/MikeMitterer/decmap_project/issues/40)); künftige
system-kritische Fehler werden bewusst **gleich** behandelt (ein Alert-Pfad, nicht pro Fehler neu).

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

Bei `AUTO_APPROVE=true` entfällt dieses Gate: Der Backend-Wert (`settings.auto_approve`) setzt
`initial_status="approved"` direkt in `routers/solutions.py` — die Lösung wird sofort sichtbar,
ohne LLM-Spam-/Duplikat-Check. Reine Server-Entscheidung, kein Frontend-Flag (Details:
[`backend.md`](backend.md)).

### Lösungs-Duplikat-Check (global, live + Submit-Backstop)

Analog zur Problem-Similarity, aber über **alle** approved Solutions (nicht problem-scoped):

- **Frontend:** `useSolutionSimilarity` ruft `POST /ai/solution-similarity` (debounced 600ms)
  und zeigt eine Live-Warnkarte im `SolutionForm`. „Trotzdem absenden" → `signals: ['duplicate_confirmed']`.
- **AI-Service:** `SolutionSimilarityService`, Public-Endpoint `POST /solution-similarity`
  (nginx-Rate-Limit 10/min — generischer `/ai/`-Proxy, keine nginx-Änderung nötig). Im
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
| `useRealtimeUpdates.ts` | AI-Service `/ai/ws` | AI-Events: `problem.approved`, `clustering.started`, `clustering.completed` |

Vote-Score-Updates laufen **nicht** über den AI-Service — Basis-Funktionalität darf
nicht vom AI-Service abhängen.

**Payload-Regel (BE-08, [Security-Audit 2026-07-05](security-audit-2026-07-05.md), bewusst deferred):**
Der Backend-`/ws` ist ein einzelner **unauthentifizierter Shared-Broadcast** — auch
Moderations-Status-Übergänge laufen darüber (die Admin-Queue hängt daran). WS-Payloads dürfen
deshalb nur **opake UUIDs + Status-Enum** tragen, nie Titel/Content/`rejection_reason`
(der Content selbst ist für Dritte seit BE-06 ein 404). Sauberer Fix wäre ein separater
authentifizierter Admin-WS-Kanal — größerer Umbau, bewusst verschoben.

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

**Cytoscape.js Cluster-Knoten — Auto-Höhe (2026-07-26, FE `93925f6`, Live-Fund):** Inner-/Leaf-Cluster-Knoten **und** der Root-Knoten nutzen `height: 'label'` + `padding` statt fester Höhe (in **beiden** Stylesheets — Glass und Theme). Die Box wächst mit dem Label, damit lange KI-generierte Cluster-Namen (z.B. „Unified AI Governance Framework Absence", mehrzeilig gewrappt) nicht mehr aus der Node-Höhe quellen/clippen. Dot- und Count-Badges wandern korrekt mit (sie lesen `parent.height()`). **Problem-Knoten bleiben fixhoch** — ihre Labels sind vorab getruncated, also kein Overflow-Risiko.

**Graph-View — Drag- und Viewport-Persistierung:** Nodes sind frei ziehbar; nach jedem
`dragfree`-Event speichert `ProblemGraph.vue` die aktuellen Positionen in
`localStorage['graph-node-positions']`. **Per-View gescoped (2026-07-01):** Die Map ist
verschachtelt (`{scope: {id: {x, y}}}`) — ein Knoten (z.B. ein Cluster) hat im Mindmap eine
**andere** Layout-Position als wenn er der Anchor eines gedrillten Views ist, daher wird pro
Ebene gescoped: `mindmap` bzw. `drill:<sortierte tag-ids>` (`currentPositionScope`). Ohne
Scoping erschiene eine im Mindmap verschobene Box eine Ebene tiefer an derselben Stelle.
`saveCurrentPositions` speichert nur die im aktuellen View **sichtbaren** Knoten (`!node.hidden()`)
— versteckte Knoten gehoeren zu anderen Ebenen und duerfen ihre (stale) Position nicht in den
aktuellen Scope leaken. Das Legacy-Flachformat (`{id: {x, y}}`) wird beim Laden automatisch in den
`mindmap`-Scope migriert (kein Datenverlust). `saveCurrentPositions` ueberspringt zudem jeden
Knoten mit exakt `(0,0)`: `rerender()` fuegt neue Nodes ohne Position bei `(0,0)` ein, bevor das
`preset`-Layout sie setzt — feuert in genau diesem Frame ein `dragfree`-Event, wuerde sonst
`{0,0}` persistiert und beim naechsten Laden stapeln sich **alle** Boxen uebereinander
(»ueberlappende Boxen«-Bug, ueberlebt Reloads, weil er aus dem Storage kommt). Der Reset-Button
loescht den ganzen `graph-node-positions`-Key — also **alle** Ebenen auf einmal.
Decoration-Badges
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
- nginx `backend.decisionmap.ai`-Serverblock: Upgrade-Header + `proxy_read_timeout 3600s`

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

**SSR/prerender-Pfad (seit [Security-Audit 2026-07-05](security-audit-2026-07-05.md)):** `utils/markdown.ts` importiert **`isomorphic-dompurify`** statt `dompurify` — das liefert server- (jsdom) wie client-seitig eine voll initialisierte Instanz, sodass `renderSolutionMarkdown` auf **beiden** Pfaden dieselbe strikte Allowlist **und** den Link-Hardening-Hook anwendet (der fruehere SSR-Bypass, der die rohe `markdown-it`-Ausgabe lieferte, ist entfernt — prerenderte Snapshots enthalten nie unsanitized/un-gehaertete Links). Der Hook wird weiterhin **lazy** registriert (`ensureHook()` im Render-Call, nie auf Modul-Ebene) — kein DOM-Seiteneffekt beim Import. Unit-Tests: `tests/utils/markdown.spec.ts`. Vgl. Konventionen Fund 28.

**`SolutionForm.vue` — Split-Editor Modal (T-13, 2026-06-19):** Das Lösungs-Formular ist ein eigenständiges Centered Modal (`<Teleport to="body">` aus der Komponente selbst, 1080px R-02 Glass-Surface, `max-height: min(840px, calc(100vh - 64px))`) — nicht mehr eine Sub-View im rechten Side-Panel. Layout: Header (Eyebrow + Headline + Problem-Titel + AI-Draft-Button + Close), permanenter **Write · Markdown | Live-Preview**-Split (zwei Spalten nebeneinander) statt der früheren „Schreiben | Vorschau"-Tabs, Sticky-Footer mit Submit. Der Submit-CTA nutzt die User-gewählte Akzentfarbe (`background: rgb(var(--th-accent))` + akzent-basierter Schatten `rgb(var(--th-accent) / 0.4)`) statt des früheren Brand-Gradienten (`var(--dm-grad)`) — konsistent zur Gradient-Disziplin (Gradient nur für Identitäts-Flächen, siehe Konventionen Fund 18). Backdrop theme-aware (gleicher Pattern wie `SolutionPopup`/`ProblemForm`); ESC + Backdrop-Klick → `cancel`; ⌘+Enter / Ctrl+Enter aus dem Textarea → Submit. Entfernt gegenüber der Tab-Variante: `previewMode`-State und die Auto-grow-Textarea-Logik (Textarea füllt jetzt die volle Spaltenhöhe). Form-Logik byte-identisch: `createSolution`, `renderSolutionMarkdown`, `useAiDraft`, `translateToEnglish`, Zod-Schema — unverändert (UI-only-Regel). Trigger-Migration analog zu T-12: `ProblemPanel.vue` öffnet via eigenem `isSolutionFormOpen`-Ref (`panelView`-Variante `'solution-form'` entfernt, Panel zeigt weiter das Problem-Detail hinter dem Backdrop); `pages/problem/[id].vue` rendert `<SolutionForm v-if>` als Root-Sibling. Der Problem-Titel in der Header-Subline („Auf: …") ist **lokalisiert**: beide Caller binden `:problem-title="localizedTitle || problem.title"` — `ProblemPanel.vue` befüllt `localizedTitle` in `updateProblemLocalization()` parallel zur Description via `translateForDisplay(title, lang)` (gleicher Token-Race-Guard), `pages/problem/[id].vue` nutzt den dort bereits vorhandenen `localizedTitle`. Der `|| problem.title`-Fallback (englischer Canonical) greift nur im kurzen Moment vor dem Laden der async-Übersetzung — sonst zeigte die Subline auch im DE-Modus den englischen Titel. Die Markdown-Toolbar (B I H " • ↳) ist **funktional** (T-13a, 2026-06-19): jeder Button fügt Markdown an der aktuellen Cursor-/Selektions-Position des Textareas ein. `applyMark(type)` (gegen `textareaRef`) unterscheidet zwei Modi — `wrap(before, after, placeholder)` umschließt die Selektion (`B`→`**`, `I`→`*`, Link→`[…](https://)`; ohne Selektion wird der Platzhalter „Text" eingefügt und markiert), `linePrefix(prefix)` setzt ein Zeilen-Präfix (`H`→`## `, Quote→`> `, Liste→`- `). Nach dem Insert stellt `await nextTick()` + `el.focus()` + `el.setSelectionRange()` Fokus und Selektion wieder her; die Live-Preview rendert die Änderung sofort mit. Jeder Button hat `title`/`aria-label`. Spec: `apps/frontend/_tickets/solved/T-13-solution-form-split-editor.md`.

**`ProblemPanel.vue` — Sticky Action-Footer + freistehende Panel-Karte (T-16, 2026-07-26):** CTA und Voting sitzen nicht mehr im Scroll-Flow der Liste, sondern in einem **Sticky-Footer am Panel-Boden** — der Body scrollt darunter, der Footer bleibt immer sichtbar (löst das „CTA rutscht unter den Fold"-Problem der früheren Top-Position, ohne den Button nach oben zwingen zu müssen). Gerendert via `<Teleport to="#panel-status-target">` in den nach T-12 **verwaisten** Layout-Slot — der dortige Cleanup-Kandidat ist damit wieder in Gebrauch (kein toter Slot mehr) — und nur in der Problem-Detail-View. Inhalt des Footers: Vote-Pill (▲ Score ▼) · Lösungs-Zähler (`solution.countLabel`, vue-i18n-Plural, de+en) · Solution-CTA. **Vote-Pill-Tooltip bei bereits abgegebener Stimme (`c34fb35` → `2b903ef`):** Ist `currentVote !== null`, tragen die ▲/▼-Buttons ein `title`/`aria-label` `problems.alreadyVoted` („Bereits abgestimmt — eine Stimme pro Problem" / „You've already voted — one vote per problem", de+en) — vorher war die einzige Rückmeldung der `not-allowed`-Cursor. Erster Ansatz (`c34fb35`) hängte den `title` an den **Pill-Container**, weil das native `title` über `disabled`-Buttons unterdrückt wird; das erschien jedoch nur unzuverlässig „aufblitzend" (nur über Score/Lücken). Finaler Fix (`2b903ef`): die Buttons nutzen `aria-disabled` + Click-Guard in `handleVote` statt des `disabled`-Attributs → hover-fähig, jeder Pfeil trägt den `title` zuverlässig; Sperre und `not-allowed`-Cursor unverändert. Der CTA behält die Auth-Sensitive-Variante (eingeloggt → Plus-Icon + `t('solution.addButton')` „Lösung hinzufügen"/„Add solution"; Gast → Lock-Icon + `t('solution.signInToContribute')` „Anmelden, um beizutragen"/„Sign in to contribute"; beide Zustände rufen dasselbe lokale `showSolutionForm()` — eingeloggt öffnet es das Solution-Modal, für Gäste baut es den Redirect `?problem=<id>&solution=new` selbst und pusht `/login` (kein `add`-Emit mehr, da der CTA jetzt in `ProblemPanel` selbst sitzt, nicht in `SolutionList`)), jetzt solid `rgb(var(--th-accent))` (auth) bzw. getönte Outline (Gast) — alle Farben token-basiert; Brand-Gradient (`var(--dm-grad)`) bleibt Identitäts-Flächen vorbehalten (Logo-Wordmark, Root-Node, Cluster→Root-Edges, Login-Headline). Dadurch ist `SolutionList.vue` **reine Liste** (CTA, `add`-Emit und ungenutztes `currentUser` entfernt), und der Admin-Lock-Hinweis wurde von der blauen Voll-Box auf einen dezenten Inline-`ⓘ` (`th-text-faint`) reduziert. Ergänzend macht `layouts/default.vue` die **Panel-Spalte zur freistehenden Karte**: Voll-Border (`1px solid rgb(var(--th-border))`) statt `border-left`, `border-radius: 8px` (`rounded-lg`; = Radius der Tabellen-Header-Bar — beide ursprünglich 5px (`183b5c5`), von der T-17-Radius-Skala `cd16526` gemeinsam auf 8px gehoben, s. Konventionen Fund 70), 14px Desktop-Margin — aber **oben 0** (`lg:mt-0`, damit der Panel-Header-Trennstrich mit der Tabellen-Kopflinie fluchtet, browser-gemessen beide auf Y=110) und **links 10px** (`lg:ml-[10px]`, ~30% schmälerer Panel↔Tabelle-Gap; rechts/unten behalten 14px) → `lg:m-[14px] lg:mt-0 lg:ml-[10px]`, zweischichtiger Drop-Shadow. Die **Panel-Header-Bar** bekommt zudem die **inverse Behandlung der Tabellen-Kopfzeile** (`panelHeaderStyle` = `rgb(var(--th-surface) / 0.9)` + `blur(20px)`, spiegelt `headerStyle` in `table.vue` — dunklerer Hintergrund, hellerer Vordergrund; nur Glass-Themes, sonst `{}`). Spec: `apps/frontend/_tickets/solved/T-16-panel-sticky-cta.md`.

**Gast-Redirect bewahrt View + Problem + Intent:** Klickt ein anonymer User „Sign in to contribute", baut `ProblemPanel.showSolutionForm()` den Redirect aus der **Setup**-`useRoute()` (`route.path` — nicht inline `useRoute().fullPath`, das die falsche View liefert) plus zwei Query-Params: `/login?redirect=<view>?problem=<id>&solution=new`. Die in-memory-Selektion (`selectedProblem`) geht beim Login sonst verloren → der User landet nach dem Login in der Default-Graph-View ohne Panel. Nach dem Login lösen `?problem=<id>` (Page → `focusProblemId`, Panel wird wiederhergestellt) und `?solution=new` (`ProblemPanel.maybeOpenPendingSolutionForm()` öffnet das Solution-Modal, sobald Panel **und** Auth da sind, und strippt danach den `solution`-Param via `router.replace` — One-Shot, kein Reopen bei Reload/Share). `maybeOpenPendingSolutionForm()` läuft in `onMounted` **und** in `watch(currentUser)` — letzteres fängt die Race ab, falls das Panel vor dem `restoreSession()` mountet. Greift denselben Layout-Remount-Mechanismus wie der `PENDING_OPEN_PROBLEM_FORM`-Flow (`login.vue` hat `definePageMeta({ layout: false })` → `default.vue` remountet beim Zurücknavigieren und liest die Query frisch). E2E-Regressions-Spec: `apps/frontend/tests/e2e/solution-redirect.spec.ts` (anonym → Login → Table-View + Panel + Formular offen).

**`SolutionList.vue` — Karten-Layout (Header + 2-Zeilen-Preview):** Jede Lösungs-Karte rendert in zwei Blöcken — Header-Zeile + Content-Preview, statt der früheren einzeiligen Headline mit Vote-Score rechts. Header (Flex-Row, `gap-2`, `mb-2`): 28×28 Avatar-Pille mit User-Initiale (`rgb(var(--th-accent))`-Background, weiße Initiale in `var(--font-display)` Space Grotesk) + Author-Name (14px, semi-bold, Space Grotesk, `truncate`) + optional AI-Badge (Accent-bg `rgb(var(--th-accent))`, 4-Point-Star Sparkle-Icon — `ISpark`-Geometrie statt 🤖-Emoji, „AI" in `uppercase tracking-wider`) + Vote-Score (`ml-auto`, mono, faint, `↑ 12`). Content-Preview unter dem Header: `<p class="text-sm text-th-text-muted line-clamp-2">` mit Plaintext aus `stripMarkdown(content)` — entfernt `**bold**`-Marker und `[label](url)`-Link-Syntax, **keine harte Zeichen-Grenze** mehr (kein `slice(0, 100) + '…'`). Tailwind `line-clamp-2` (`-webkit-line-clamp: 2`) übernimmt das Trunkieren mit Ellipsis je nach Viewport-Breite — bei schmalen Panels weniger Vorschau, bei breiten mehr. Author-Resolver `authorName(solution)`: `isAiGenerated` → `t('problems.aiGenerated')`; kein `userId` → `t('problems.anonymous')`; sonst `getUserById(userId)?.displayName ?? email ?? anonymous`. `authorInitial(solution)`: erstes Zeichen, uppercase, Fallback `?`. AI-Badge nur via `solution.isAiGenerated` — kein Emoji-Prefix im Content mehr.

**`SolutionFullPage.vue` — Read-only Vollansicht (T-11, 2026-07-21):** Ein langer Lösungsansatz bekommt eine eigene Seite unter der neuen Route `/problem/:problemId/solution/:solutionId` (`pages/problem/[problemId]/solution/[solutionId].vue` als dünner Wrapper um `SolutionFullPage.vue`). Von jeder Lösungs-Karte in `SolutionList.vue` führt ein „↗ In voller Ansicht öffnen"-Link auf die Seite (`@click.stop` — der Klick öffnet die Vollansicht, selektiert aber **nicht** die Karte; Regressionstest in `SolutionList.spec.ts`). **Route-Rule bewusst `{ ssr: false, prerender: false }`** für `/problem/*/solution/**` — im Gegensatz zu `/problem/**` und `/cluster/**` (die für SEO prerendern): die View lädt Solutions zur Laufzeit (`fetchSolutions(problemId)` + `.find(id)`, es gibt keinen by-id-Endpoint, gleiches Deep-Link-Muster wie `ProblemPanel`) und löst Autor-Namen nur clientseitig/auth-abhängig auf → keine SEO-Fläche, prerender würde eine leere Shell einfrieren. **Zwei-Spalten-Reading-Layout:** links die App-Nav-Rail, mittig die Reading-Column (max ~680px) mit Eyebrow „LÖSUNGSANSATZ" + Author-Chip + `renderSolutionMarkdown(content)`, rechts eine Kontext-Rail mit **allen** Solutions des Problems (2-Zeilen-Snippet via `stripMarkdown`, aktive mit Accent-Border, Klick wechselt die aktive Solution ohne Seitenwechsel). **Rail-Links reichen den `?from=`-Origin weiter** (`railTarget(solutionId)`): ohne das ließ ein Solution-Wechsel im Rail den `?from=` fallen → der nächste Back fiel auf den Graph (`/?problem=`) zurück, auch wenn der User aus der Tabelle kam (`route.query.from` war beim Rail-Klick weg). `solutionUrl` bleibt bewusst origin-frei (Share/Permalink leakt keine Herkunft); `railTarget` hängt `?from=` nur bei internem Pfad an — gleicher Open-Redirect-Guard (`startsWith('/')` und nicht `//`) wie `backTarget`. **Back / „← Mindmap" stellt den GANZEN Graph-View wieder her** (Selektion + Drill-Level + Zoom/Pan), nicht nur die Selektion: die `/`-Seite wird beim Navigieren zur Vollansicht komplett unmounted (kein `<KeepAlive>`), also spiegeln `?problem=<id>` (Selektion) **und** das neue `?cluster=<tagId>` (aktiver Drill-Leaf) in die URL — der Solution-Full-Page trägt `route.fullPath` als `?from=` zurück, Back reproduziert beides. Restore über `restoreDrillView(leafTagId)` (baut die Ahnen-Kette aus dem Leaf und emittiert `cluster-drill` → Subtree lazy-load, **kein** Über-Drillen zum tiefsten Problem-Tag) + `graph-viewport-drill` (pro Scope, beim `onUnmounted` gespeichert, in `fitDrillView` reinstated, breiten-robust via Modell-Mittelpunkt). Der Cold-Deep-Link ohne erhaltenen Drill seedet `[target]`; mit Drill füllt `loadCluster` den Subtree, das Seeding entfällt. Beim frischen Remount lief `initGraph` gegen eine noch leere Problems-Liste, daher baut `debouncedRerender` die lokalisierten Node-Labels vor dem Render neu auf (`updateLocalizedLabels`, nur `locale != 'en'`) — sonst zeigten die Knoten nach der Rückkehr den englischen Canonical-`title` statt der DE-Übersetzung. Selektiertes Problem-Node trägt nur einen Akzent-Rahmen, **keine `overlay`-Corona** (Halo blähte die Fit-bbox auf — bewusst entfernt). Deep-Detail: siehe die zwei Round-Trip-Gotchas in `CLAUDE.md`. **Kein erfundener Titel** (Solutions haben nur `content`) und **kein Job-Titel**: der Author-Chip nutzt `solutionAuthorName` — eigener Eintrag → Name, fremd → `t('problems.anonymous')` („Anonymous"), KI-Eintrag → `AiBadge` mit `t('problems.aiGenerated')`. Übersetzung folgt dem **globalen Display-Locale** (`useLocale` + `translateForDisplay`, `isTranslating`-Puls auf Titel und Content) — **kein** Per-Item-Toggle. **Voting:** `submitVote(EntityType.SOLUTION, …)` liefert ein Delta, das sowohl den lokalen Score als auch — via `updateVoteScore` — den geteilten `solutions.value`-Eintrag patcht, damit der Score einen Rail-Wechsel überlebt (Test: „patches the shared solutions.value entry … so the score survives rail navigation"). Share = Permalink via `copyToClipboard` + Toast; **kein Bookmark**. **Problem-Kontext-Band (T-14, 2026-07-23):** Behebt den 🔴-HOCH-Punkt aus dem T-11-Test — das Problem selbst war in der Vollansicht unsichtbar (nur der Titel) und der Vote-Score erschien als kryptisches unbeschriftetes „↑ N". Variante B: ein **sticky, einklappbares Band innerhalb der Reading-Column** (`sticky top-0`, fluchtet mit der 680px-Lesespalte + deren 40px-Padding — Auf-/Zuklappen bewegt **nur** den Solution-Content darunter, der rechte Rail bleibt unberührt; Live-Korrektur `026c81b`, ersetzt das ursprüngliche full-width-Band über beide Spalten). **Default eingeklappt** (`problemOpen = ref(false)`): eine maximal kompakte, einzeilige Headline — Eyebrow „PROBLEM" + Titel links, Score-Pill + **▲/▼-Toggle** rechts. **Aufgeklappt** (`problemOpen`) erscheinen zusätzlich die gerenderte `problem.description` (via `renderSolutionMarkdown` — dieselbe Util wie der Solution-Content, DRY), die Problem-Meta über die **geteilte `<ProblemMetaChips>`-Komponente** (SSoT mit dem Problem-Panel — Status-Badge farbcodiert, AI-Badge, Kategorie-Tags L1–9 mit Gradient-Dot, User-Tags L10 als `#name`, Regionen; Tag-Namen aus dem bestehenden `useTags`-Lookup, kein neuer Store) und eine bedingte Autor/Firma-Row (`v-if="problem.authorDisplayName || problem.company"`). **Live-Verify + Fix 2026-07-25 (BE `d8410fd`):** Die Autor/Firma-Row rendert jetzt korrekt (live gegen `int.decisionmap.ai` bestätigt — aufgeklapptes Band zeigt „Mike · MangoLila"). Zuvor kam sie **nie**: `SolutionFullPage` lädt das Problem über `fetchProblemById` → `GET /problems/{id}` (`get_problem`), und dieser Detail-Endpoint baute sein `ProblemRead` via `_to_read(p, tags, regions)` **ohne** die `company`/`author_display_name`-kwargs — nur der Listen-/Semantik-Pfad löste sie gebatcht via `_load_authors` auf (vgl. Company-Spalte oben), also kamen beide Felder als `null` an und das `v-if` griff nie. Fix (DRY): neuer Helper `_read_with_author(session, p, tags, regions)` löst das Autor-Profil wie die Liste und wird von **allen** Single-Problem-Pfaden genutzt (Detail-GET + create/update/delete-Responses) → jedes `ProblemRead` trägt die Felder konsistent. Regressionstest `test_detail_endpoint_includes_author_profile` (Detail liefert die Felder + Parität zur Liste), Backend-Unit-Suite 198 grün. Der Rest des Bands (Titel, Beschreibung, Score-Pill, Meta-Chips, EN/DE-Switch, 429-Tag-Übersetzung) war schon vorher bestätigt. Detail-Erkenntnis: Konventionen Fund 69. Der Score wandert aus der Top-Leiste in eine **beschriftete Pill** „▲ N Stimmen" (`problems.voteCountLabel`, vue-i18n-Plural DE/EN, unit-only) — die Top-Leiste zeigt stattdessen „Lösungsansatz i von n" (`solution.solutionCounter`). Die Problem-Beschreibung folgt demselben **globalen EN/DE-Display-Locale** wie der Titel (`resolveDisplayDescription`, `originalTranslations`-zuerst, `isTranslating`-Puls). Die kompakte Headline (Titel + Score-Pill) rendert immer, sobald `problem` geladen ist; der **▲/▼-Toggle** und der aufklappbare Teil erscheinen nur, wenn **Beschreibung oder** Tags/Regionen existieren — ein gemeinsamer Guard `isExpandable` (`hasProblemDescription || hasProblemMeta`) + `toggleProblem()` steuern das. Fehlt alles, bleibt es bei der reinen Headline ohne Toggle (`ProblemMetaChips` selbst rendert Status + AI-Badge immer, wenn aufgeklappt). **Die Headline selbst ist ein Klick-Ziel** (Commit `6e0fd49`, Mike-Feedback): nicht nur der ▲/▼-Toggle, auch ein Klick auf Eyebrow + Titel klappt das Band auf/zu (`toggleProblem()`, selber `isExpandable`-Guard); bei expandierbarem Inhalt ist die Headline keyboard-operabel (`role="button"`, `tabindex="0"`, Enter/Space, `aria-expanded`, `cursor-pointer select-none`), sonst inert (kein Button-Role, kein Cursor). **Theming-Entscheidung:** Der Ticket-Vorschlag hardcoded `rgba(0,0,0,0.22)`/`rgba(255,255,255,0.6)` wurde bewusst durch `rgb(var(--th-surface) / 0.55)` ersetzt — der Band tönt sich pro Theme automatisch korrekt, ohne Light/Dark-Fallunterscheidung (siehe Gotcha „Komponenten-Inline-rgba bricht Theme-Switch"); Tag-Chips auf `--th-accent-2`, Score-Pill auf `--th-inner`, gleiches Token-Prinzip. UI-only: rendert nur das bereits geladene `problem.value`, `useTags`-Fetch nur fire-and-forget für die Tag-Namen. **Geteilte Chip-Komponente `ProblemMetaChips.vue` (2026-07-23, Commit `01e33d9`):** Das Band renderte anfangs eigene, simple Tag-Chips und divergierte damit sichtbar vom Problem-Panel (Panel: farbcodierter Status, Kategorie-Tag mit Gradient-Dot, User-Tag `#name`, Regionen). Statt das Markup zu kopieren (würde erneut auseinanderlaufen) wurde eine rein **präsentationale** SSoT-Komponente `components/ProblemMetaChips.vue` extrahiert und in **beiden** Ansichten eingesetzt: Props = bereits aufgelöste, lokalisierte `tags` (mit `level`: 10 = User-Tag `#name`, <10 = Kategorie-Tag mit Gradient-Dot) + `regions` + `status` + `isAiGenerated`; die `clickable`-Prop schaltet interaktive `<button>` + `tag-filter`-Emit (Panel) gegen inerte `<span>`s (Full-Page, read-only). `ProblemPanel.vue` wurde vom Inline-Chip-Block auf die Komponente umgestellt (verhaltens-erhaltend, `tag-filter`-Emit erhalten, `metaTags`/`metaRegions`-Computeds), das Full-Page-Band liefert dieselbe Struktur (Regionen via `useRegionsFetch`, strukturelle Tag-Namen DE-lokalisiert). Keine Datenschicht-Abhängigkeit in der Komponente → trivial testbar. **Extrahierte Utils:** `stripMarkdown`, `solutionAuthorName` und `authorInitial` wurden aus `SolutionList.vue` in `utils/solutionDisplay.ts` gezogen (reine Funktionen, `getUserById`/`t` injiziert statt Composable-Calls) und werden von `SolutionList` **und** `SolutionFullPage` geteilt — kein Duplikat. UI-only-Regel: Validation, Voting-Modell, Datenmodell und Backend-Endpoints unverändert (kein neues `title`-Feld, kein by-id-Endpoint, kein Edit-Modus auf dieser Seite). Tests: `tests/components/SolutionFullPage.spec.ts` (28 Fälle — Markdown-Sanitizing, Anonymous/eigener/KI-Autor, Rail-Aktiv-Marker, Vote-Patch + Score-Persistenz über Rail-Wechsel, Rail-`?from=`-Weitergabe + Open-Redirect-Guard, Owner/Admin-Edit-Sichtbarkeit, Share-Toast, Mindmap-Link, Not-Found bei fehlendem Problem bzw. unbekannter `solutionId`; +6 Band-Fälle aus T-14: Titel+gerenderte Beschreibung im Band, Score-Pill beschriftet + nackter Pfeil aus der Top-Leiste raus, Solution-Counter „i von n", ein Chip pro auflösbarer Tag-ID via Shared-Lookup, Toggle klappt Beschreibung+Tags weg, kein Block+Toggle wenn Beschreibung **und** Tags/Regionen fehlen; +2 aus `6e0fd49`: Headline-Klick klappt auf/zu, inerte Headline ohne expandierbaren Inhalt) — Band-Chips laufen jetzt über die geteilte Komponente; ihre Status/Level-Unterscheidung/Regionen/AI/`clickable`-Logik deckt `tests/components/ProblemMetaChips.spec.ts` (6 Fälle) ab (Vitest 194/194). Specs: `apps/frontend/_tickets/solved/T-11-long-solution-fullpage.md`, `apps/frontend/_tickets/solved/T-14-problem-context-fullpage.md`.

**`ProblemContextBand` + geteilter Detail-Body — Band-Chrome als geteilte Komponenten + volles Problem-Detail im New-Solution-Modal (2026-07-27, Commits `e22984a`/`83140ee`/`fdaafde`/`e34fdd4`/`9e37b53`):** Das „Problem-Headline klicken → Detail aufklappen"-Muster des T-14-Bands wird jetzt **auch im New-Solution-Modal** (`SolutionForm.vue`) gezeigt — vorher war dort nur die „On: <Titel>"-Zeile sichtbar. Das Problem wird beim **Öffnen des Modals eager** via `fetchProblemById` geladen (nicht erst beim Aufklappen), damit die **Vote-Pill „▲ N votes"** (`ProblemVotePill`) schon in der eingeklappten Kopfzeile neben dem Titel steht; ein Klick auf die Headline (inkl. ▲/▼-Chevron, Keyboard Enter/Space, `aria-expanded`) klappt **dasselbe volle Detail wie die Full-Page** auf: gerenderte Beschreibung + Meta-Chips (Status/AI/Tags/Regionen) + Autor/Firma. Lokalisiert über denselben Display-Locale-Pfad wie die Full-Page (Re-Lokalisierung bei Sprachwechsel), nur **einmal** gefetcht (kein Re-Fetch beim Toggeln) und Fehler fail-safe (`consola.warn`, kein Crash). Die Chevron-Tooltips reusen die bestehenden `solution.showFullProblem` / `showLess`; neu ist nur `solution.problemLoading` (der `noProblemDescription`-Key entfiel mit dem geteilten Detail-Body — `ProblemContextDetail` blendet eine leere Beschreibung per `v-if` aus, statt einen Platzhalter zu zeigen). Statt zwei paralleler Implementierungen wurde das Muster in **eine** Quelle gezogen — drei neue geteilte Bausteine, die **Full-Page UND Modal** konsumieren: **`components/ProblemContextBand.vue`** kapselt die klickbare Headline-Hülle (a11y: `role`/`tabindex`/`aria-expanded`, Enter/Space), den ▲/▼-Toggle und die aufklappbare Region (`v-model:open` + `expandable`-Prop; Slots `headline` / `trailing` für die Vote-Pill / default für den Body). **`components/ProblemContextDetail.vue`** rendert den aufgeklappten Body (Beschreibung via `ProblemDescription` + geteilte `<ProblemMetaChips>` + Autor/Firma-Row) — die Full-Page hat ihre eigenen Inline-Versionen dieser Teile **verloren** und nutzt jetzt denselben Baustein. **`composables/useProblemMeta.ts`** löst die Tag-/Regionen-Chips (Tags + Regionen einmal on-mount gefetcht, unbekannte IDs übersprungen statt roh gezeigt) in **derselben Shape** auf, die das `ProblemPanel` an `ProblemMetaChips` füttert — SSoT, damit das Problem überall identisch liest. **`components/ProblemDescription.vue`** rendert die (lokalisierte) Beschreibung als sanitized Markdown mit dem kanonischen Prose-Styling (`renderSolutionMarkdown` + der lange `[&_h2]…`-Klassenblock liegen jetzt an **einer** Stelle statt in zwei Files) — inklusive `[&>:first-child]:mt-0` / `[&>:last-child]:mb-0`, die die führende/schließende Prose-Marge kollabieren, sodass allein der Container-`mt` den Headline→Text-Abstand setzt (die Prose-Regel `[&_p]:my-2` gab dem ersten Absatz sonst zusätzliche 8px oben; Header→Text via `[&>:first-child]:mt-0` von ~19px auf 11px (`e34fdd4`), danach der Container-`mt` von `mt-2` (8px) auf `mt-1` (4px) → ~7px sichtbar (`9e37b53`, Meta-Chips-Leitmarge im No-Description-Fall analog), in beiden Ansichten identisch da geteilt). **`components/ProblemVotePill.vue`** ist die beschriftete Vote-Pill der Kopfzeile. Full-Page-Verhalten unverändert (alle `problem-band-*`-Testids erhalten), UI-only (Validation, Voting-Modell, Backend-Endpoints unberührt). **Contract-Test-Erkenntnis:** `SolutionFullPage.spec` und `SolutionForm.spec` müssen die geteilten Komponenten explizit registrieren (`global.components`), weil Nuxt-Auto-Import in vitest nicht greift (gleiche Klasse wie `AppModal` in T-18); `ProblemMetaChips` bleibt gestubbt (Chip-Internals deckt `ProblemMetaChips.spec` ab), `useProblemMeta`-Deps (Tags/Regionen) inert gemockt. Tests: +5 SolutionForm-Band-Specs (eager Fetch auf Open + Vote-Pill in der eingeklappten Kopfzeile; Aufklappen rendert Beschreibung + Meta-Chips + Autor, DE-Locale liest das gespeicherte Original; Fetch nur **einmal**, kein Re-Fetch beim Toggeln) — Vitest 213/213, eslint 0 Errors, beide Flächen (Modal + Full-Page zeigen identisch Votes + Tags + Region + Status + Autor) live verifiziert.

**`SolutionPopup.vue` — Glass-Modal-Treatment (`glass-dark`/`glass-light`):** Klick auf das Solutions-Badge im Graph öffnet ein theme-awares Glass-Modal — Card-Background `rgba(20,16,28,0.78)` + `backdrop-filter: blur(40px)` + Inset-Highlight (dark) bzw. `rgba(255,255,255,0.86)` + `blur(30px)` (light), Backdrop bewusst dunkler und stärker geblurrt (`rgba(0,0,0,0.55)` + `blur(8px)`) damit das Modal nicht in den Mesh-Orb-Hintergrund einblendet. Frühere Variante nutzte `bg-th-bg` (Page-Color) — auf Glass-Themes verschwamm das Modal mit der Mesh-Surface. Header: Eyebrow `text-[11px] uppercase tracking-wider text-th-text-faint` („Solution approaches (2)") + `font-display` Titel 17px/600. Close-Button: 32×32 rounded Pille mit SVG-`×` statt Glyph, theme-aware Background. Andere Themes (Legacy) rendern weiterhin solid via `rgb(var(--th-surface))` + `rgb(var(--th-border))`. Werte sind als **kanonische R-02-Spec (Glass Modal Surface)** promoted und werden in `ProblemPanel.vue` (`panelContentStyle`), `ProblemForm.vue` und `SolutionForm.vue` (`formContainerStyle`) identisch übernommen — bewusste Inline-Duplikation statt Token-Extraktion (Trade-off und Pruefpattern: siehe Konventionen Fund 23).

**`SolutionPopup.vue` — Listen-Items spiegeln das SolutionList-Karten-Vokabular:** Die früheren Reihen mit `divide-y` + Index-Nummer + Detail-Button wurden ersetzt durch eigenständige Karten (`background: rgba(128,128,128,0.12)` auf Glass / `rgb(var(--th-surface))` solid, `border-radius: 16px`, `padding: 14px`, 1px Theme-Border, `space-y-2` zwischen Karten, `hover:-translate-y-px`-Lift). Karten-Header (Flex-Row, `gap-2`, `mb-2`): 28×28 Avatar-Pille mit Initiale aus `authorName()` (`rgb(var(--th-accent))`-Background, weiße Initiale in `font-display`) + Author-Name (14px, semi-bold, Space Grotesk, `truncate`) + optional AI-Badge (Accent-bg, 4-Point-Star Sparkle-SVG — `M12 2 L14 10 L22 12 L14 14 L12 22 L10 14 L2 12 L10 10 Z`, ersetzt das frühere 🤖-Emoji) + Vote-Score (`ml-auto`, mono, faint, `↑ N`). Content-Preview unter dem Header: `text-sm text-th-text-muted line-clamp-2` mit Plaintext aus `stripMarkdown()` — **keine harte Zeichen-Grenze** (`truncate(text, 120)` entfernt). Locale-aware: ein `watch([locale, solutions])` baut eine `localizedHeadlines: Map<id, string>` über `translateForDisplay(content, lang)` (leer wenn `locale === 'en'`) — DE-User sehen die übersetzte Vorschau, identisch zur SolutionList. Author-Resolver `authorName(solution)`: `isAiGenerated` → `t('problems.aiGenerated')`; kein `userId` → `t('problems.anonymous')`; sonst `getUserById(userId)?.displayName ?? email ?? anonymous` (identisch zu `SolutionList.vue`). Volle Karte ist klickbar (`cursor-pointer` + `@click="openSolution(solution)"`) — der frühere „Show details"-Button auf Hover entfällt. Pattern-Konsistenz: Popup-Karten und Right-Panel-Karten teilen dasselbe visuelle Vokabular, damit der User keinen Stilbruch beim Wechsel zwischen Graph-Klick und Panel-Klick wahrnimmt.

**`ProblemForm.vue` — Centered Modal Layout (T-12, 2026-06-10):** Das Neues-Problem-Formular ist ein Centered Modal (`<Teleport to="body">` mit Backdrop-Dim + 680px-Card, `max-height: calc(100vh - 80px)`) — nicht mehr im rechten Side-Panel. ProblemPanel (Detail-Ansicht eines bestehenden Problems) bleibt unverändert im Side-Panel. Backdrop ist theme-aware: glass-dark `rgba(0,0,0,0.55)` + `blur(8px)`, glass-light `rgba(0,0,0,0.40)` + `blur(4px)` — gleicher Pattern wie `SolutionPopup.vue`. Modal-Card nutzt R-02 Glass Modal Surface via `formContainerStyle` (identische Werte zu `SolutionPopup`/`ProblemPanel`). Header: Eyebrow `NEW PROBLEM` (11px/700/.18em uppercase in `--th-accent`) + Headline `t('form.headline')` (26px Space Grotesk) + Subline `t('form.subline')` (480px max-width) + 32×32 Close-Icon mit `--th-border`. Body ist scrollable Form (`flex-1 overflow-y-auto min-h-0`) mit `id="problem-form"`. Sticky-Footer: Status-Hint links (`t('form.statusHint')` mit grünem Dot) + Ghost-Cancel + solidem Accent-Submit (`rgb(var(--th-accent))` + accent-getönter Schatten — seit T-15-Follow-up 2026-07-24; vorher `var(--dm-grad)`, dessen Violett-Ende `#8B47C9` „dumpfer" wirkte als die übrigen CTAs, jetzt angeglichen an SolutionForm-Submit/TopBar/Panel/Full-Page). Submit-Button referenziert das Formular via `form="problem-form"`-Attribut statt JS-Forward (siehe Konventionen Fund 25). ESC + Backdrop-Klick → `handleCancel`. State-Management: `layouts/default.vue` hat einen separaten `isProblemFormModalOpen`-Ref (distinkt von `isPanelOpen` für die Detail-Ansicht), via `provide/inject` für `pages/index.vue` exponiert. Similarity-Card rendert **inline** zwischen Title und Description (war vor T-12 `<Teleport to="#panel-status-target">` — den `#panel-status-target`-Slot nutzt seit T-16 der Panel-Sticky-Footer, er ist damit nicht mehr orphan). Form-Logik byte-identisch zu vorher: `createProblem`, `validateForm`, `useSimilarity`, `useEnglishTranslation`, Tag-Erstellung, `duplicate_confirmed`-Signal-Flow — alle unverändert (UI-only-Regel). Spec: `apps/frontend/_tickets/solved/T-12-problem-form-modal.md`.

**Einheitliches Modal-Chrome — Frosted-Backdrop + Shell-Geometrie (T-15, 2026-07-23):** Beide Form-Modals (`ProblemForm.vue`, `SolutionForm.vue`) teilen sich seit T-15 einen **Frosted-Backdrop** und identische Außen-Geometrie — **zunächst nur Backdrop + Abstände, die R-02 Glass-Modal-Surface (Fill-Farbe/Blur) selbst bleibt unverändert** (Mike-Vorgabe: Farbänderung am Modal zu weitreichend; Border/Schatten wurden erst im Elevation-Nachtrag unten angefasst). Backdrop (Variante A, auf `isDark` gekeyt → deckt Glass **und** Non-Glass-Themes): `rgb(8 5 14 / 0.28)` + `backdrop-filter: blur(30px)` (dark) / `rgb(24 16 32 / 0.20)` + `blur(30px)` (light) — kaum abgedunkelt, starker Blur, sodass die Mesh-Orb-Farben weich durchschimmern statt zu hartem Schwarz einzublenden (ersetzt den früheren dunkleren `rgba(0,0,0,0.55)`+`blur(8px)`-Scrim). Shell-Geometrie beider Modals vereinheitlicht: Overlay-Padding `40px`, Radius `24px`, Header `24/28/0`, Body `24/28`, Sticky-Footer `16/28` — das Solution-Modal hatte vorher Overlay `32`, Body `py-5`, Footer `14`, jetzt identisch zum Problem-Modal; Header-Top (`24`) und Footer-Bottom (`16`) sitzen bei jedem Modal gleich. Der getönte Scrim ist die bewusste **R-09-Ausnahme** (theme-unabhängiges `rgb(… / α)` erlaubt — der Scrim soll gerade *nicht* pro Theme mitfärben; siehe Konventionen Fund 63). **Follow-up am Live-Stand (2026-07-24, Commit `bcd4794`):** Die identische Shell-Geometrie allein fluchtete die beiden Modals **nicht** — das Solution-Modal war content-höhen-getrieben (`max-height: min(840px, 100vh-64)`) und schwebte bei kurzem Split-Editor-Content mittig mit ~160px Rand, während das Problem-Modal ~44px hatte (bei identischem Viewport gemessen). Fix (Mikes Wahl A): feste **Fill-Höhe `height: min(720px, calc(100vh - 80px))`** — das Modal füllt jetzt wie das Problem-Modal (~40px Rand, `-80` passt zum 40px-Overlay-Padding), der Split-Editor bekommt mehr Schreibfläche. Zweiter Punkt: der Problem-Submit-Button wirkte „dumpfer" — er nutzte als einziger CTA noch `var(--dm-grad)` (Gradient endet in Violett `#8B47C9`) statt des soliden `rgb(var(--th-accent))`; angeglichen an SolutionForm-Submit/TopBar/Panel/Full-Page (solides Accent + accent-getönter Schatten). Regel-Bestätigung: gleiche Padding-Werte fluchten zwei Modals nur, wenn beide dieselbe Höhen-Strategie haben — ein content-höhen-getriebenes Modal mit kurzem Inhalt braucht eine feste Fill-Höhe, sonst schwebt es. Reiner Chrome-Change (`git revert`-bar), kein neuer Spec (Vitest 194/194, eslint 0 Errors). Als **Reverse-Ticket R-10** an Design gemeldet (die zwei getrennten Modal-Wrapper — byte-identischer Backdrop + je eigene Teleport/ESC-Logik — zu einer geteilten `<AppModal>`-Shell zusammenführen), im UI-only-Ticket nicht erzwungen (>40 Zeilen, ESC/Teleport-betroffen, echtes Verhalten statt reinem Präsentations-Extract → bewusst Mikes Entscheidung), Backdrops bis dahin wertgleich gehalten. **Mike-Go 2026-07-27:** R-10 (+ das gefaltete R-02 Modal-Chrome) ist jetzt als eigenes Ticket **`T-18` (AppModal-Shell)** angelegt (`ready`, „bald umsetzen, DRY") — die geteilte Shell (Teleport/Backdrop/ESC/Chrome/Geometrie) wird aus `ProblemForm`+`SolutionForm` extrahiert, die R-02-Chrome-Werte reisen als DS-Handoff aus T-18. **Elevation-Nachtrag (2026-07-24, Commit `ba7ac34` + Follow-up):** Auf dem barely-dimmed Frosted-Backdrop verschwamm die Modal-Kante mit dem Mesh — die 4%-Weiß-Inset-Hairline (`0 0 0 1px rgba(255,255,255,0.04) inset`) hob zu wenig ab. Beide Form-Modals bekamen daher einen **sichtbaren 1px-Border** (glass-dark `rgba(255,255,255,0.15)`, glass-light `rgba(0,0,0,0.10)`) statt der Inset-Hairline, plus einen **tieferen zweilagigen Drop-Shadow** (dark `0 40px 120px -24px rgba(0,0,0,0.8), 0 16px 48px -16px rgba(0,0,0,0.6)`; light `0 40px 120px -24px rgba(40,20,60,0.4), 0 16px 48px -16px rgba(40,20,60,0.3)`) — das Modal liest sich jetzt als klar abgehobene schwebende Fläche. **Fill-Farbe + Blur unverändert**, aber die zwei Form-Modals divergieren damit bewusst von der kanonischen R-02-Surface (nur `ProblemForm`/`SolutionForm` in `formContainerStyle`, nicht `SolutionPopup`/`ProblemPanel`) — Referenz: Claude-Design-Mockup 2026-07-24, Vitest 194/194. Spec: `apps/frontend/_tickets/solved/T-15-modal-shell-contrast.md`.

**`AppModal.vue` — geteilte Modal-Shell (T-18, 2026-07-27):** Setzt das aus T-15 als **R-10** gemeldete Reverse-Ticket um — der von `ProblemForm.vue` und `SolutionForm.vue` doppelt gepflegte Modal-Rahmen (`Teleport to="body"`, Frosted-Backdrop, Glass-R-02-Card-Surface inkl. der T-15-Border/Shadow-Elevation, ESC-schließen, Backdrop-Klick-schließen, `@click.stop`) liegt jetzt in **einer** Komponente. Kontrakt: Prop `open` (default `true`, Caller mounten weiter per `v-if`) + `cardStyle` (Geometrie-Override, auf die Card-Surface gemergt) + Emit `close` + Default-Slot (Caller liefern ihren eigenen Sticky-Header / scrollbaren Body / Sticky-Footer). Die feste SolutionForm-Fill-Höhe (`min(720px, 100vh − 80)`, T-15-Follow-up) und ProblemForms `max-height` reisen jeweils als `cardStyle`-Prop mit — nicht hart verdrahtet, sodass der Extract keinen Caller in die Maße des anderen zwingt. **Reiner DRY-Refactor:** die R-02-Surface- und Frosted-Backdrop-Werte sind byte-identisch aus den Pre-Extraction-Forms übernommen — kein Redesign, Live-Render beider Modals unverändert (`git revert`-bar). **Contract-Test-Erkenntnis:** Der ESC-`document`-Listener läuft ohne `import.meta.client`-Guard, weil `onMounted`/`onUnmounted` projekt-konventionell client-only sind (feuern nie im SSR) — erst dadurch ist der ESC-Pfad im jsdom-Test überhaupt prüfbar (Konventionen Fund 71). Tests: neue `tests/components/AppModal.spec.ts` (Slot-Render, ESC-schließen, Backdrop-Klick, `open=false` = kein Render, Unmount-Cleanup); `SolutionForm.spec` mountet jetzt durch AppModal (Vitest 210/210, eslint 0 Errors). R-02-Chrome-Werte als DS-Handoff in `_tickets/STATUS.md` abgelegt. Spec: `apps/frontend/_tickets/T-18-appmodal-shell.md`. Die T-12/T-15-Einträge oben behalten ihre eigene Teleport/Backdrop-Beschreibung als historischen Pre-T-18-Stand.

**`pages/settings.vue` — Profil/Erscheinungsbild als Tab-Layout (2026-07-25):** Die Settings-Seite ist von zwei gestapelten Karten (Profil-Karte nur bei `isAuthenticated` + separate Erscheinungsbild-Karte) auf **zwei stets sichtbare Tabs** (`Profil` | `Erscheinungsbild`, `role="tablist"`) umgestellt — eine konsistente Anordnung für eingeloggte User **und** Gäste; der aktive Tab rendert seinen Inhalt in **einer** Panel-Karte. Tab-Stil ist der **dezente Underline-Stil aus dem Admin-/Moderations-Bereich** (feine untere Linie, aktiver Tab nur mit farbigem Unterstrich + `text-brand` — kein gefüllter Gradient-Pill; `0d85d9c`), damit das Tab-Muster projektweit konsistent bleibt. **Entscheidung (Variante a):** Beide Tabs sind immer sichtbar; ein Gast, der den Profil-Tab öffnet, sieht statt des nur-eingeloggt-sinnvollen Formulars einen **ruhigen Login-Hinweis** — dezenter Inline-Text (neuer i18n-Key `settings.profile_login_hint`, EN/DE) + „Sign in →"-Link in `text-brand` (kein großer Gradient-Button) — vorher war die Profil-Karte für Gäste komplett ausgeblendet (`v-if="isAuthenticated"`). Erscheinungsbild bleibt ohne Login zugänglich. Profilfelder (Display-Name/Company) werden **reaktiv** aus `currentUser` geseedet — `watch(currentUser, { immediate: true })` statt One-Shot im `onMounted`, weil die Session-Wiederherstellung async ist und ein harter `/settings`-Aufruf sonst leere Felder zeigt (`c8753fc`, siehe Gotcha). Reines UI-Layout: Profil-Formular, Mode/Accent/KI-Accent/Gradient-Steuerungen und ihre Persistenz (`dm-accent`/`dm-ai-accent`/`dm-grad-strength`) unverändert.

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

Uebersetzt via KI-Service (`TranslationService`). Uebersetzung ist eine **eigene Faehigkeits-Achse** neben Embedding und LLM: `TRANSLATION_PROVIDER` (openai | anthropic) waehlt den Backend-Provider (OpenAI `gpt-4o-mini` bzw. Anthropic `claude-haiku-4-5` als Default-Modell), `OPENAI_TRANSLATION_MODEL` / `ANTHROPIC_TRANSLATION_MODEL` (Schema `<provider>_<zweck>_model`, leer = das jeweilige `*_LLM_MODEL`) das Modell — durchgereicht an **alle** Uebersetzungs-Calls (Submit/Display/Such-Kandidaten via `translate_query_candidates`). Spam-Filter, Clustering und KI-Entwurf laufen unabhaengig ueber `LLM_PROVIDER` + `*_LLM_MODEL`. Ein reiner Uebersetzungs-Provider (z.B. Mistral/lokal) fuegt sich als `TRANSLATION_PROVIDER=mistral` + `MISTRAL_TRANSLATION_MODEL` ein, ohne Umbenennung.

**`EnglishTranslationSection.vue` — Collapsible UX (Problem Form):** EN-Felder erscheinen als Collapsible-Sektion sobald Nicht-Englisch erkannt wird. Header-Zeile zeigt Chevron-Icon + Titel-Preview im kollabierten Zustand. Auto-Expand nach Uebersetzung: zwei Trigger — `watch(showFields, { immediate: true })` (auch beim Mount wenn showFields bereits true) und `watch(isTranslating)` (Re-Translation wenn Section kollabiert war — showFields aendert sich nicht, der isTranslating-Uebergang true→false triggert Expand). Translate-Button und Info-Button bleiben immer in der Header-Zeile sichtbar — Info-Button nutzt `.stop` um den Collapse-Toggle nicht auszuloesen. Kein visueller Overhead fuer englischsprachige User — `showEnSection` in `useEnglishTranslation.ts` prueft `locale.value !== 'en'` explizit (verhindert falsch-positive Sichtbarkeit, da `looksLikeEnglish` fuer ASCII-Text immer `true` liefert). **`startCollapsed`-Prop:** Wenn `true`, bleibt die Sektion beim `showFields false→true`-Übergang initial eingeklappt — der Caller kontrolliert den Startzustand (z.B. Edit-Modus mit bestehender Übersetzung). 4 Tests in `EnglishTranslationSection.spec.ts` sichern dieses Verhalten ab.

**`ProblemForm.vue` — Textarea Auto-Resize:** Das Beschreibungsfeld wächst beim Tippen automatisch mit dem Inhalt (`@input="autoResize"`). Kein fixer `rows`-Wert — Höhe wird per JavaScript gesetzt. `validateForm` blockt non-ASCII-Eingaben bei `locale === 'en'` via `NON_ASCII_RE` (`/[^\x00-\x7F\p{P}\p{S}\p{N}\p{Z}\p{C}]/u`, Unicode-Property-Escapes) — gleicher Guard wie `handleSave`/`handleSubmit`/`handleSaveEdit` in den anderen Formularen. Nicht-ASCII-Buchstaben (ä ö ü Kyrillisch CJK) blockiert; englische Typographie (– — „" … © €) erlaubt. `"4–6 weeks"` läuft durch.

**`SolutionForm.vue` — Translation Collapsible (inline):** Solutions haben nur ein Content-Feld (kein Titel); `EnglishTranslationSection` ist fuer Titel+Beschreibungs-Paare gebaut. SolutionForm implementiert das Collapsible direkt inline — gleiche visuelle Optik (Chevron, Card-Style, Colour-Tint), gleiche UX (Auto-Expand nach Uebersetzung). Kein `mode`-Flag an `EnglishTranslationSection` — vermeidet unnoetige Komplexi­taet. Der EN-Block hat einen expliziten `locale !== 'en'`-Guard im Template (`v-if`) — kein falsches Anzeigen bei englischer UI-Sprache. `handleSubmit` blockt non-ASCII-Eingaben bei `locale === 'en'` (`form.validation.inputEnglishOnly`). Spec: [`docs/specs/2026-06-07-solution-form-design.md`](specs/2026-06-07-solution-form-design.md)

**originalTranslations (first-class JSONB-Spalte, Migration 009, 2026-06-21):** Der vom User eingereichte Originaltext liegt direkt auf der Problem-Zeile in `problems.original_translations` (JSONB, Format `{lang: {title?, description?}}`) — nicht mehr per `sha256`-Hash aus dem `translation_cache` rekonstruiert. Migration 009 backfillt die Spalte aus dem alten Cache. **Alle `/problems`-Lese-Pfade** (List, Single, Create-/PATCH-/Delete-Response) liefern `original_translations` ans Frontend (`ProblemRead.original_translations`) — gelesen direkt aus der Spalte (`_to_read`), kein Reverse-Mapping mehr. **Create** setzt die Spalte direkt am Problem-Objekt; **Edit (PATCH)** aktualisiert sie **transaktional im selben Commit** wie `title`/`description` — kein Hash-Drift möglich, der Originaltext bleibt update-sicher. Die alten Helfer `_store_original_translations`/`_load_original_translations` sind entfernt; der `TranslationCache` bleibt nur noch für die LLM-Übersetzung (`translations.py`/`solutions.py`). Modell: `JSONB().with_variant(JSON(), "sqlite")` — die In-Memory-Test-DB (kein `visit_JSONB`) baut weiterhin. Siehe Konventionen Fund 30.

> **Contract-Erkenntnis (`ProblemRead`):** Mit dem `original_translations`-Refactor liefert `ProblemRead` **nicht mehr** die früheren englischen Canonical-Felder `title_en` / `description_en` / `content_language` — nur noch `title`, `description` und `original_translations`. Das Frontend (`realProblems.ts` → `BackendProblem`) mappt entsprechend `title`/`description`/`original_translations`; die Contract-Tests (`tests/contract/test_problems.py`) prüfen exakt diese Feld-Liste. Die DB-Spalten `title_en`/`description_en`/`content_language` existieren weiterhin (Schema/Embedding-Quelle, vgl. [`data-model.md`](data-model.md)) — entfernt wurde nur ihre Exposition im API-DTO.

**`translateForDisplay` — Display-seitige Lokalisierung:** `useTranslation` bietet `translateForDisplay(content, lang)` fuer read-only UI-Stellen. `SolutionList.vue` nutzt dies um Headlines in der Liste zu lokalisieren: `watch([locale, solutions])` → `translateForDisplay` fuer alle Solutions → `localizedHeadlines`-Map. Bei `lang === 'en'` wird die Map geleert (EN-Content ist Original). Lokale `_displayCache` verhindert redundante API-Calls.

**Stiller Fallback bei `/translate`-Fehler (transient):** Schlaegt der `/translate`-Call fehl (z.B. nginx Rate-Limit 429, 5r/m burst 2), gibt `translateForDisplay` den **englischen Original-Text** zurueck (`catch` → `return text`) und cached dieses Ergebnis **nicht** (nur Erfolge landen in `_displayCache`) — es heilt sich beim naechsten Aufruf selbst. Direkt nach dem Submit ist das Rate-Limit-Fenster durch die eigenen Auto-Translate-Calls (DE→EN) belegt, sodass die Display-Calls (EN→DE) ins 429 laufen koennen. Konsequenz im DE-Modus: Haupt-Felder zeigen Englisch → `looksLikeEnglish()` = `true` → `englishAutoDetected` = `true` → EN-Section klappt faelschlich auf. Kein Datenfehler, rein transient. **Der Edit-Pfad (`ProblemPanel`) ist davon nicht mehr betroffen** — `loadLocalizedEditFields` bevorzugt das gespeicherte `originalTranslations[locale]` (kein LLM-Round-Trip, kein 429-Risiko); `translateForDisplay` greift nur als Fallback fuer Sprachen ohne gespeichertes Original. Reine Display-Stellen ohne gespeichertes Original (z.B. `SolutionList`) koennen den Fallback weiterhin treffen. Siehe Konventionen Fund 26.

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

**User-Tag-Anlage im `ProblemForm` (2026-07-24):** Das Label-Eingabefeld **schlägt existierende Tags zur Auswahl vor** und bietet „Create" nur für tatsächlich neue Namen an. Dafür lädt das Formular seine Tag-Liste selbst — `onMounted(fetchTags)`, da `useTags()` per-Instance-State hält (ohne den Load bliebe die Liste leer → jeder getippte Name sähe neu aus → nur „Create"). Serverseitig ist die Anlage idempotent: `POST /tags` dedupliziert **nicht-gelöschte** L10-Tags case-insensitiv (nie ein 500 durch Doppelanlage), `realTags.createTag` **upsertet** das Ergebnis in die lokale Liste (das Backend kann ein bestehendes Tag zurückgeben). Ein soft-deleted Match wird **nicht** revived, sondern mit `409` abgewiesen (Löschung ist superuser-only Moderation — Revive wäre ein Authorization-Bypass). Datenmodell + Gotcha-Detail: [`docs/data-model.md`](data-model.md) (L10) und Konventionen Fund 68.

**Tag-Namen-Lokalisierung (`name_translations`, Migration 011, 2026-07-24):** Strukturelle Tag-Labels (L1–L9) sind KI-generiert und **englisch**; sie werden nicht mehr pro Render live übersetzt. `tags.name_translations` (JSONB `{lang: text}`, analog `problems.original_translations`) hält vorab-berechnete Übersetzungen. Der ai-service übersetzt das generierte Label **beim Clustering-Upsert** (`ClusteringService._translate_label` → `BackendClient.upsert_tag(..., name_translations=…)`); ein `upsert` mit gleichem `(name, level)` **aktualisiert** die gespeicherten Übersetzungen (ON-CONFLICT-Refresh, kein Ignore). Für vor der Migration angelegte Tags gibt es einen **Einmal-Backfill**: `POST /clustering/backfill-tag-translations` (ai-service, `backfill_tag_translations()`) → Backend `PATCH /internal/tags/{id}/translations` (`set_tag_translations`) — nur strukturelle Tags **ohne** Übersetzung (L10-User-Tags und bereits vollständige werden übersprungen). Die Übersetzung nutzt den bestehenden `translation_cache` und die **provider-scoped** Übersetzungs-Achse (`translation_provider` + `*_translation_model`), zentral über die DRY-Factory `build_translation_service()` (eine Construction-Stelle für Dependency, Scheduler und beide Reindex/Approve-Hooks). `/tags` liefert `name_translations` ans Frontend (`Tag.nameTranslations`, `mapTag`); die Anzeige liest `tagDisplayName(tag, locale)` (`utils/tagDisplay.ts`) statt `translateForDisplay(tag.name)` — EN-Canonical für `en`, sonst `nameTranslations[locale] ?? name`, **aber User-Tags (L10) nie**: ein Guard `locale === 'en' || tag.level >= 10 → tag.name` gibt L10 immer im Roh-`name` zurück. Begründung: strukturelle L1–L9-Labels sind KI-generierte *maschinelle* Labels (Übersetzung hilft dem DE-Nutzer), L10-Tags sind die *eigenen Worte* des Autors (eine LLM-Rückübersetzung wäre falsch). Der Backfill/Clustering befüllt heute ohnehin keine L10-Übersetzungen — der Guard verankert die Regel **im Code** (an einer Stelle, sichtbar erzwungen) statt sie von der Datenlage abhängen zu lassen, sodass ein künftig versehentlich gesetztes L10-`name_translations` die UI nicht anfassen kann. **Rollout:** Backend (`a355520`) + ai-service (`db6f41c`) + Frontend (`c9820da`/`580dae7`, `feature/bold-redesign`) committet. **Alle** Read-Sites lesen jetzt `tagDisplayName(tag, locale)` — kein Live-Translate für Tag-Namen mehr: `table.vue`, `pages/problem/[id].vue`, `ProblemPanel.vue`, `SolutionFullPage.vue` (ihre `localizedTagNames`-Blöcke + `watch(tags)` entfernt; `ProblemMetaChips.vue` ist rein präsentational und bekommt die schon lokalisierten Namen von diesen Callern) **und** die Cytoscape-Cluster-Node-Labels + Breadcrumb-Chip in `ProblemGraph.vue` (Commit `580dae7`, 2026-07-24 — der `localizedTagLabels`-Ref und der Tag-Zweig in `updateLocalizedLabels` sind raus; `updateLocalizedLabels` übersetzt nur noch die **Problem-Titel**). Der Graph-View war der eigentliche 429-Live-Auslöser: das Umschalten dorthin feuerte einen `/translate`-Burst über alle sichtbaren Cluster-Nodes gleichzeitig. Test: `tests/utils/tagDisplay.spec.ts` (EN-Canonical / DE-Übersetzung / Fallback auf `name` bei fehlender Übersetzung / leere `nameTranslations` / **L10-User-Tag nie übersetzt, auch bei vorhandener Übersetzung**). Behebt den Haupttreiber des `/ai/translate`-429 (~13 Live-Calls je DE-Table-Load, vgl. Konventionen Fund 26/67). **Nach Deploy einmalig den Backfill auslösen**, sonst bleiben bestehende Tags ohne DE-Übersetzung (neue kommen automatisch).

**useRegions-Facade:** Komponenten importieren ausschliesslich `useRegions.ts` (`useRegionsFetch()`) — kein Direktimport von `realRegions`. Facade-Pattern kapselt die Datenquelle (urspruenglich fuer den inzwischen entfernten Fake-Layer-Switch eingefuehrt). `_inflight`-Promise-Cache verhindert doppelte Requests wenn mehrere Komponenten gleichzeitig mounten.

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
  → POST /ai/generate-solution { problem_id, lang? }   (AI-Service, kein SERVICE_TOKEN)
  → Draft-Text erscheint in Textarea (auto-grow)
  → User bearbeitet → Uebersetzung → Submit
```

- **`useAiDraft(problemId)`** — neues Composable: `{ draft, loading, error, generate }`; übergibt `locale.value` als `lang`-Parameter → AI-Service generiert Draft in Benutzersprache
- Draft wird nur zurueckgegeben — kein Storage, kein `is_ai_generated`-Flag (User submitted separat via `POST /solutions`)
- **2000-Zeichen-Cap zweistufig durchgesetzt** (systemweites Content-Limit: textarea `maxlength`, Zod, Backend-Pydantic, DB-CHECK): (1) der AI-Service-Prompt (`prompts.py`, `_SOLUTION_SYSTEM_BASE`) gibt „Keep the ENTIRE response under 2000 characters" als **hartes Limit** vor + verlangt einen vollstaendigen, in sich geschlossenen Entwurf (~200–250 Woerter, Saetze immer beenden) — frueher „be concise (200–400 words)", was den Cap sprengte und Frontend-seitig mitten im Wort abgeschnitten wurde. (2) `useAiDraft`-Backstop `fitDraft()` trimmt eine seltene Ueberlaenge an der letzten **Satz- (dann Wort-)Grenze** statt hartem mid-word `.slice(0, 2000)` — der Entwurf endet sauber statt „abgeschnitten". Contract-Test `tests/composables/useAiDraft.spec.ts` (2 Faelle): Ueberlaenge endet an Satzgrenze (echtes Praefix, nie mid-word), Wortgrenzen-Fallback ohne Satzterminator. Deploy: Prompt-Fix laeuft ueber die **ai-service-Pipeline** (nicht den Frontend-Branch), sonst greift nur der Backstop
- nginx Rate Limit: 5r/min per IP, Burst=1 (enger als `/translate` wegen LLM-Kosten)
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

### KI-Akzent-Token (`--th-ai-accent`)

Eigene Akzentfarbe **ausschliesslich fuer KI-getriebene UI** — bewusst distinkt von `--th-accent` (dem User-CTA-Akzent), damit „das hat die KI gemacht" visuell lesbar ist. Eingefuehrt mit dem AI-Match-Badge (FE `94c57e3`) als erste Referenz-Instanz des KI-Marker-Designsystems ([decmap_project#39](https://github.com/MikeMitterer/decmap_project/issues/39)), seither **konsequent ueber alle KI-Touchpoints ausgerollt** (FE `b42707d`/`8216cc9`/`59bc7b9`).

- **Pro Theme handgetoent** in `assets/css/themes.css` (`--th-ai-accent` + `--th-ai-accent-hover`), immer **gegen den jeweiligen `--th-accent` kontrastierend**: kuehle Accents (blau/violett) → Violett, warme/gruene (orange/amber/pink/teal) → Cyan; Light-Themes dunkler getoent (lesbar auf hellem Grund), Dark-Themes heller. `obsidian-dark` (violetter Accent) bekommt Cyan, damit AI ≠ Accent. `custom-*` faellt auf den `:root`-Default (Violett `#7C3AED`) zurueck. **`glass-dark` (Out-of-Box-Default-Theme, FE `4881536`)** traegt als KI-Akzent **Fuchsia** (`#D946EF`, hover `#C026D3`) statt des frueheren Cyan — die Maintainer-bevorzugte Default-Kombi (dunkles Glass + Sunset-Accent `#FF8C00` + Fuchsia-KI-Akzent); kontrastiert weiterhin klar den warmen Sunset-Accent.
- Als Tailwind-Utility-Farben `th-ai-accent` / `th-ai-accent-hover` registriert (`tailwind.config.ts`); Verwendung via `rgb(var(--th-ai-accent) / <alpha>)` (Alpha-Modifier-Pattern, siehe Konventionen).
- **On-Accent-Text-Token `--th-ai-accent-text`** (FE `79c0d7e`, theme-aware seit FE `4bc6d96`): Textfarbe **auf** dem KI-Akzent — eigenes Token statt Zweckentfremden des regulaeren `--th-accent-text` (Token-Kopplung vermieden). In `:root` weiss (`255 255 255`); die vier **hellen** Themes (`default`/`forest`/`sunset`/`glass-light`) ueberschreiben es auf einen dunklen On-Accent-Wert, damit der Text auch auf hellem Grund lesbar bleibt, die dunklen Themes erben das Weiss. Anwendungsfall: das AI-Match-Badge faerbte zuvor Karo, Text und Mini-Balken **gleich** (alle `--th-ai-accent`) → der Balken ging optisch unter; jetzt setzt der Text seine eigene On-Accent-Farbe **inline** (`style="color: rgb(var(--th-ai-accent-text))"`, gleiches Idiom wie der Balken daneben), Karo und Balken bleiben im KI-Akzent und heben sich ab. **Inline-`rgb` statt der Tailwind-Utility `text-th-ai-accent-text`** ist bewusst: eine im Dev neu eingefuehrte text-Utility wird vom Tailwind-JIT nicht zuverlaessig sofort regeneriert (s. Konventionen, JIT-Staleness) — der Inline-Style greift ueber Vue-HMR unabhaengig vom Tailwind-Build.
- **User-Override** in `/settings`: KI-Akzent-Picker (6 Swatches: Cyan/Violett/Indigo/Sky/Fuchsia/Teal, leere Auswahl = Theme-Default), persistiert in `localStorage` unter `dm-ai-accent`. `initTheme()` in `composables/useTheme.ts` restored den Override in `--th-ai-accent` — spiegelt exakt das `dm-accent`-Handling, sodass der Override **ueber Theme-Wechsel hinweg** kleben bleibt.
- **Wiederverwendbare `AiBadge.vue`-Komponente** (FE `b42707d`) ist der **Enforcement-Punkt** des Designsystems: kapselt das KI-Vokabular (4-Punkt-Funkel-Icon + `--th-ai-accent` + erklaerender Tooltip) in einer Komponente (Props `label`/`tooltip`/`size`, DOM-frei → prerender-sicher). Texte aus dem neuen i18n-`ai`-Namespace (`badge`/`badgeHint`/`clusterHint`/`generatedHint`/`translationHint`/`moderationHint`, en+de). Damit wurden **sechs divergente `is_ai_generated`-Badges vereinheitlicht** (vorher: 2× generischer `--th-accent`, 2× hartkodiertes `bg-purple-*`, 1× nacktes 🤖): `SolutionList`, `SolutionPopup`, `SolutionDetail`, `ProblemPanel`, `problem/[id]` (Problem- + Loesungs-Header).
- **Rollout ueber alle KI-Touchpoints** (FE `8216cc9`/`59bc7b9`): Duplikat-Similarity-Karten (`ProblemForm` + `SolutionForm`) tragen den KI-Akzent + den Cosine-`%` mit erklaerendem Tooltip (`similarity.scoreHint`); AI-Draft-Button (`SolutionForm`), KI-Suche-Toggle (`DmTopBar`), KI-Uebersetzungs-Button (`EnglishTranslationSection`, vorher `bg-blue-600` + Globus → KI-Akzent + Funkel) und die LLM-Moderations-System-Note (`admin/moderation`, **nur** das `needs_review`-Verdikt — die manuelle Ablehnungs-Begruendung bleibt unmarkiert). Cluster-Markierung sitzt am **Spalten-Header** der Table („KI-erkannt", `ai.clusterHint`), **nicht** an den einzelnen Cluster-Chips — die Graph-Hierarchie vermittelt das Clustering bereits, die Chips bleiben ruhig.

### FOUC-Praevention

Blockierendes Inline-Script im `<head>` (via `nuxt.config.ts`):
- Liest Theme aus `localStorage` bevor Vue geladen wird
- Setzt `data-theme`-Attribut und `dark`-Klasse sofort
- Fallback-Variablen in `:root` stellen sicher dass Styles existieren bevor JS laeuft

### System-Praeferenz

Der Erstbesuch-Default ist seit FE `4881536` **`glass-dark`** (Out-of-Box-Look:
dunkles Glass + Sunset-Accent + Fuchsia-KI-Akzent) — **nicht** mehr OS-gefolgtes
Hell/Dunkel. OS-Following (`prefers-color-scheme` → `glass-light`/`glass-dark`)
bleibt **opt-in** ueber eine explizite `system`-Preference (`theme-id === 'system'`
bzw. `theme-system-preference === 'system'`). Der FOUC-Bootstrap-Fallback in
`nuxt.config.ts` muss identisch zu `composables/useTheme.ts` bleiben — bei jedem
Wechsel des Default-Themes beide Stellen gleichzeitig anpassen (siehe Konventionen Fund 21).

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
4. **Table-View:** Reduziert die Liste auf genau das verlinkte Problem. `onMounted` holt es bei
   gesetztem `?problem=<id>` direkt via `fetchProblemById` (analog zur Graph-View), ersetzt
   `problems` durch diesen einen Eintrag (`total=1`, `hasMore=false`) und oeffnet das Panel. **Bugfix
   (FE `3d89391`):** zuvor suchte der alte Pfad das Problem nur per `find()` in der bereits geladenen
   ersten Seite und reduzierte die Liste nie — lag es nicht auf Seite 1 (Default 50, `sort=created`),
   blieb das Panel zu **und** alle Eintraege sichtbar. Wird das Problem nicht gefunden (geloescht /
   nicht sichtbar), faellt die View ueber `clearFocusProblem()` auf die volle Liste zurueck.
5. Detail-Panel oeffnet sich automatisch — `ProblemPanel` lokalisiert beim Mount (s. Edit-Lokalisierung), sodass ein Permalink-Load in DE deutschen statt englischen Text zeigt
6. Filter-Chip zeigt „Showing single problem" mit Schliessen-Button — in der Table-View laedt der
   Dismiss (`handleClearFocus`) die volle Liste nach (`loadFirstPage`), sonst bliebe der eine
   reduzierte Eintrag stehen

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

fastapi-users — JWT-Auth via **HttpOnly-Cookie**, E-Mail-Verifizierung, Magic Link (`apps/backend/`, Port 8001).

Seit 2026-07-06 (Security-Audit) wird das JWT als HttpOnly-Cookie transportiert (`CookieTransport`, Cookie `decisionmap_auth`) statt im localStorage — der Token ist fuer JavaScript nie lesbar (XSS-Exfiltration geschlossen), `SameSite=Lax` blockt cross-site State-Changing-Requests (CSRF). Prod teilt das Cookie via `Domain=.decisionmap.ai` zwischen Frontend und `api.` (Subdomain-Cookie-Variante, keine nginx-Restrukturierung); Dev nutzt ein host-only Cookie ohne `Secure`. Konfiguration: `COOKIE_DOMAIN`/`COOKIE_SECURE`/`COOKIE_SAMESITE`. Das Frontend sendet jeden Backend-Request mit `credentials: 'include'` (`backendFetch`).

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
POST /auth/magic-link → Backend schickt Mail mit Token
      ↓
User klickt Link → /auth/magic-verify.vue → GET /auth/magic-verify?token=XXX (credentials: 'include')
      ↓
Backend setzt das HttpOnly-Auth-Cookie (kein Token im Body) + is_verified=true
      ↓
Frontend hydriert die Session via restoreSession(), leitet auf / weiter
```

Ein erfolgreicher Magic-Link beweist E-Mail-Besitz — das Backend setzt dabei `is_verified=true`
(unverifizierte Accounts werden so nachverifiziert).

`/auth/magic-verify.vue` ist die Landingpage für Magic-Link-Tokens (B4-Fix: neu angelegt).

### Login / Logout

- POST `/auth/jwt/login` → Backend setzt das JWT als **HttpOnly-Cookie** (kein Token im Response-Body); der anschließende `/users/me`-Call laedt den User. Kein client-seitiger Token-State mehr — das fruehere `loadPersistedTokens()`-Muster (synchron im `setup()`) ist mit der Cookie-Migration entfallen
- `restoreSession()` in `onMounted` = Cookie-Probe via `/users/me` — ein 401 bedeutet schlicht „nicht eingeloggt" (anonym), kein Fehler
- POST `/auth/jwt/logout` → Backend loescht das Cookie (Logout ist nicht mehr rein client-seitig)
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
- **`AUTO_APPROVE=true`:** Neue Problems **und Lösungen** überspringen die Moderations-Queue und wechseln direkt auf `approved` (`initial_status` in `routers/problems.py` bzw. `routers/solutions.py`). Übersprungen wird das gesamte LLM-Moderations-Gate (Spam-Filter, Duplikat-Check, `needs_review`-Queue) — der `-approved`-Hook (Embedding + Clustering) läuft weiterhin, ist aber Anreicherung *nach* der Freigabe, kein Gate. Nicht verwechseln mit dem AI-Service-Log `problem_auto_approved`, das die KI im *normalen* Flow (`AUTO_APPROVE=false`) nach sauberem Spam-/Dup-Check ausgibt. Wirksam ist ausschließlich der **Backend**-Wert (`settings.auto_approve`); ein Frontend-Gegenstück gibt es nicht — das ungenutzte Public-Flag wurde entfernt (Details: [`backend.md`](backend.md)).

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
