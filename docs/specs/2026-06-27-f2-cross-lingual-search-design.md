# F2 — Cross-linguale Keyword-Suche + Relevanz-Ranking (Postgres FTS) — Design

**Datum:** 2026-06-27
**Status:** Approved (Brainstorm) → bereit für Implementierungsplan
**Repos:** `apps/backend` (FTS + `sort=relevance`) + `apps/frontend` (Sort-Option)
**Issues:** #32 (cross-linguale Such-Symmetrie) + #37 (Relevanz-Sortierung)
**Voraussetzung:** Test-DB-Umstellung auf Postgres (erledigt 2026-06-27) — FTS ist jetzt ohne `skipif` testbar.

## Motivation

Die Keyword-Suche (`GET /problems?q=`) übersetzt die Anfrage heute via ai-service LLM nach EN und DE (`translate_query`, 1× pro Sprache, im Cursor gecacht) und matcht alle Varianten (raw `q`, `q_en`, `q_de`) per **ILIKE-Substring** gegen `title`, `description` und `original_translations` (JSONB → Text).

**Problem:** ILIKE ist ein literaler Substring-Match — er kennt keine Morphologie. `fehlend` matcht `fehlende`/`fehlenden` (zufällig, weil Substring), aber **nicht** `fehlt`; und die EN→DE-Übersetzung `missing`→`fehlend` verfehlt flektierte deutsche Formen. Befund: `missing`→4 Treffer vs. `fehlend`→6 Treffer — **asymmetrisch**. Außerdem gibt es **kein Relevanz-Ranking**: Treffer werden nur nach `created`/`votes`/… sortiert, nicht nach Übereinstimmungsgüte (#37).

**Ziel:** Symmetrischer, morphologie-bewusster Recall via Postgres-Volltextsuche (Stemming pro Sprache) **und** ein opt-in Relevanz-Ranking (`ts_rank`). EN- und DE-Suche liefern dieselbe Treffermenge; eine explizite Anfrage kann nach Relevanz sortiert werden. **Die Sprachunterstützung muss erweiterbar sein** — eine weitere Sprache darf nur einen Registry-Eintrag + eine templated Index-Migration + Translation-Support kosten (kein Model-/Frontend-Edit).

## Non-Goals

- **Keine Präfix-/Substring-Suche** (`gov` → `governance`). FTS arbeitet wort-/lexem-basiert. Präfix-Suche (`to_tsquery('gov:*')`) ist ein optionales späteres Add-on, kein Teil von F2.
- **Keine Änderung an der semantischen Suche** (`?semantic=`, pgvector). Bleibt unverändert; `q` und `semantic` bleiben mutually exclusive.
- **Keine neue Übersetzungs-*Infrastruktur*.** `translate_query` + Cursor-Caching + „≤1× pro Sprache pro Such-Session"-Invariante bleiben; sie werden nur über die Sprach-Registry **geloopt** statt en/de hartzukodieren.

> **Bewusst KEIN Non-Goal mehr:** zusätzliche Sprachen. Das Design ist registry-getrieben; EN/DE ist nur die Initial-Registry (MVP-Datenbestand). Weitere Sprachen sind per Design „relativ einfach" erweiterbar (s. Komponente 1).

## Kern-Prinzip

**Reines, registry-getriebenes FTS ersetzt ILIKE** (Ansatz A — gewählt). Statt Substring-Match werden gestemmte `to_tsvector`-Ausdrücke pro Sprache gegen `plainto_tsquery` gematcht; die unterstützten Sprachen stehen in **einer** zentralen Registry, über die Schema-Indizes, WHERE-Klausel, Ranking und Übersetzung alle iterieren. Die LLM-Übersetzung bleibt (cross-linguale Brücke); FTS ergänzt die innersprachliche Morphologie (Stemming). Beides zusammen = symmetrischer Recall.

Verworfen: Additiv FTS + ILIKE (doppelte Logik, Asymmetrie-Rauschen) sowie generierte tsvector-Spalten (erzwingen pro Sprache eine ORM-`Computed`-Spalte + Drift-Guard-Spiegelung → Extensibility-Reibung).

## Architektur / Komponenten

### 1. Sprach-Registry + funktionale GIN-Indizes (Extensibility-Kern)

**Eine zentrale Registry** (neues Modul `apps/backend/services/search_languages.py`) als Single Source of Truth:

```python
# (lang_code in original_translations, Postgres-Textsuche-Config)
SEARCH_LANGUAGES: list[tuple[str, str]] = [("en", "english"), ("de", "german")]

def tsvector_sql(lang: str, config: str) -> str:
    """SQL-Ausdruck für den FTS-Vektor einer Sprache — IDENTISCH in Index + Query.

    Stabiler Vertrag: Ändert sich der Output, müssen die funktionalen Indizes per
    Reindex-Migration neu erstellt werden (sonst nutzt der Planner sie nicht mehr).
    """
    return (
        f"to_tsvector('{config}', "
        f"coalesce(title, '') || ' ' || coalesce(description, '') || ' ' || "
        f"coalesce(original_translations -> '{lang}' ->> 'title', '') || ' ' || "
        f"coalesce(original_translations -> '{lang}' ->> 'description', ''))"
    )
```

**Funktionale GIN-Indizes** (Migration 010) — einer pro Sprache, auf exakt diesem Ausdruck:

```sql
CREATE INDEX ix_problems_fts_en ON problems USING gin (to_tsvector('english', …));
CREATE INDEX ix_problems_fts_de ON problems USING gin (to_tsvector('german',  …));
```

Die Migration **importiert `tsvector_sql`** und erzeugt die Index-Statements daraus → Index-Ausdruck und Query-Ausdruck sind garantiert identisch, der Planner nutzt den Index für das `@@`-Match.

- **Warum jede Sprach-Config auch `title`/`description` mit-stemmt (nicht nur `original_translations->lang`):** Die EN-Übersetzung ist optional/asynchron („EN-Felder sind kein Submit-Blocker") — eine Einreichung bleibt bis zur Übersetzung **in ihrer Originalsprache im Canonical** `title`/`description`. Jede Sprach-Config muss diese Felder daher mit-stemmen (sonst verfehlt eine Suche untranslatierte Probleme; genau dieser Fall steckt in `test_keyword_search_symmetric_en_finds_de_only`). Das Mit-Stemmen fremdsprachiger Canonical-Texte in einer anderen Config ist harmloses Rauschen (matcht keine fremde Query).
- **IMMUTABLE erfüllt:** `->`/`->>`, `||`, `coalesce`, `to_tsvector(regconfig, text)` mit **konstanter** Config sind immutable → funktionaler Index zulässig.
- **Kein Backfill, keine ORM-/Model-Spalte:** Funktionale Indizes brauchen weder eine Spalte noch Backfill; das `Problem`-Model bleibt unverändert → **kein** Drift-Guard-Risiko (Indizes leben per Konvention nur in Migrationen, der Guard toleriert das bereits).

**Eine Sprache hinzufügen** = (1) Tupel in `SEARCH_LANGUAGES` ergänzen, (2) templated Index-Migration (ein `CREATE INDEX` via `tsvector_sql`), (3) `translate_query` muss die Sprache liefern. WHERE/Ranking/Übersetzung adaptieren sich automatisch (sie loopen die Registry). Kein Model-, kein Frontend-, kein Cursor-Format-Edit.

### 2. Übersetzung + Cursor (N-sprachfähig)

Auf Page 1 wird `q` für **jede** Registry-Sprache übersetzt (`translate_query(q, lang)`, best-effort; `None` = Sprache überspringen) und als Map gesammelt: `q_translations: dict[str, str]` (z. B. `{"en": "...", "de": "..."}`). Diese Map wird in **jedem** Cursor unter Key `"qt"` mitgeführt → Page 2+ liest sie ohne Re-Translate.

`services/cursor.py` wird generalisiert: `encode_cursor(..., q_translations: dict[str,str] | None = None)` (statt fixer `q_en`/`q_de`); `decode_cursor` liefert `q_translations`; neue `peek_cursor_translations(cursor) -> dict | None`. Die bisherigen `q_en`/`q_de`-Parameter + `peek_cursor_q_en/q_de` entfallen (nichts deployed → sauberer Replace). Alle Sort-Branches in `_apply_sort_and_keyset` reichen `q_translations` durch (statt `q_en`/`q_de`).

### 3. Recall (WHERE) — ersetzt den ILIKE-Block in `list_problems`

```
fts_clauses = []
for lang, config in SEARCH_LANGUAGES:
    for v in {q, q_translations.get(lang)} if truthy:
        fts_clauses.append(
            literal_column(tsvector_sql(lang, config)) @@ plainto_tsquery(config, v)
        )
base_where.append(or_(*fts_clauses))
```

- **Raw `q` gegen jede Sprach-Config** ist der Übersetzungs-Ausfall-sichere Pfad (ai-service down → `q_translations` leer; `q` matcht trotzdem gegen alle Configs). Deckt `test_q_matches_original_translations_raw` (`q=schlecht` → German-Stemmer `Schlechte`→`schlecht`) ohne Übersetzung ab.
- `literal_column(tsvector_sql(...))` spiegelt den vorhandenen `semantic`-Stil (`literal_column(dist_sql)`) und matcht den funktionalen Index.

### 4. Relevanz — neuer `sort=relevance` (opt-in)

Neuer Branch in `_apply_sort_and_keyset` (erhält `q_translations` + raw `q`). Rank = Summe der Sprach-Ränge über die Registry:

```
rank = Σ_lang  ts_rank(literal_column(tsvector_sql(lang, config)),
                       plainto_tsquery(config, q_translations.get(lang) or q))
```

- `ORDER BY rank DESC, id ASC`; **Keyset** auf `(rank, id)` — exakt im Muster des `semantic`-Distanz-Keysets (`(expr < last) OR (expr == last AND id < last_id)`, Float-Vergleich, Ausdruck im WHERE wiederholt, da Alias dort nicht referenzierbar). Branch gibt `(Problem, rank)`-Rows zurück (wie `tag`/`solutions`), hängt `rank` als Attribut an.
- **Cursor** trägt `rank`+`id`+`q_translations`.
- **`sort=relevance` ohne `q`** → graceful Fallback auf `created` (kein Ranking-Signal; kein 422).
- **`sum` statt `greatest`:** Treffer in mehreren Sprachquellen ist relevanter; bei nur einer Quelle ist der andere Summand 0.
- Kein `score`-Feld in `ProblemRead` für Relevanz-Treffer (`ts_rank` ist nicht 0..1 wie die semantische Cosine-Score) → der semantische Score-Badge im Frontend erscheint nicht; die Relevanz-Ordnung wird über StatusBar-Hinweis + Header-Lock angezeigt.

Andere Sort-Modi (`created`/`votes`/`title`/`status`/`solutions`/`tag`) bleiben unverändert und profitieren nur vom besseren FTS-Recall in der WHERE-Klausel.

### 5. Frontend (`apps/frontend`)

Sprach-agnostisch — das Frontend kennt keine Sprach-Registry, es sendet nur `q` + `sort=relevance`.

- **`SortKey`-Union** in `pages/table.vue` um `'relevance'` erweitern; `toBackendSort`/`fromBackendSort` mappen `relevance ↔ relevance`. Der API-Builder (`composables/data/real/realProblems.ts`, `buildQueryString`) serialisiert `query.sort` bereits generisch → keine Änderung nötig.
- **Opt-in-Steuerung:** Neuer Layout-State `keywordRelevanceEnabled` (in `layouts/default.vue`, analog `aiSearchEnabled`), per `provide` an Kinder. Eine „Relevanz"-Umschaltung in `DmTopBar` ist nur sichtbar, wenn ein Keyword-Suchbegriff aktiv ist **und** AI-/Semantic-Suche **aus** ist. `pages/table.vue` injiziert `keywordRelevanceEnabled`; in `buildQuery()` → `sort='relevance'`, wenn aktiv.
- **`relevanceSortActive`** (Layout-Computed) wird erweitert: `true` auch für den Keyword-Relevanz-Fall (`!aiSearchEnabled && query && keywordRelevanceEnabled`). Dadurch greifen die **bestehenden** Mechaniken automatisch: „Sorted by relevance"-Hinweis in `StatusBar` + Sort-Header-Lock in `table.vue` (Score-Badge erscheint nicht, da Backend keinen Score liefert).
- **State-Reset:** `keywordRelevanceEnabled` zurücksetzen, wenn der Suchbegriff geleert oder AI-Suche eingeschaltet wird (kein hängender Relevanz-Zustand).

## Datenfluss

```
User tippt q (AI-Suche aus) + aktiviert "Relevanz"
  → Frontend GET /problems?q=…&sort=relevance
  → Backend: q_translations = { lang: translate_query(q, lang) for lang in SEARCH_LANGUAGES }  [Page 1, im Cursor]
  → WHERE: OR über Sprachen:  tsvector_sql(lang) @@ plainto_tsquery(config, {q, q_translations[lang]})
  → sort=relevance: ORDER BY Σ ts_rank(...) DESC, id ; Keyset (rank,id)
     sonst:          bisherige Sortierung, FTS nur im WHERE
  → ProblemPage(items, next_cursor[rank,id,qt], total)
```

## Risiken / erwartete Arbeit

- **Funktionaler-Index-Match:** Der Query-Ausdruck muss textuell zum Index-Ausdruck passen, damit der Planner den GIN-Index nutzt. Garantiert durch die **gemeinsame** `tsvector_sql`-Quelle in Migration + Query. `tsvector_sql`-Output ist ein stabiler Vertrag — Änderung erfordert Reindex-Migration (dokumentiert).
- **German-Stemmer-Erwartungen:** Tests müssen reale Snowball-`german`-Ergebnisse annehmen (`fehlend`/`fehlende`/`fehlt`→`fehl`), nicht idealisierte. Bei Überraschungen Erwartung an tatsächliche Lexeme anpassen (kein Verstecken).
- **Cursor-Refactor:** Umstellung `q_en`/`q_de` → `q_translations`-Map berührt alle Sort-Branches + `cursor.py` + die Such-Tests (Translate-Aufruf-Zählung). Mechanisch, aber breit.
- **Übersetzungs-Last:** N Sprachen = N `translate_query`-Calls auf Page 1 (gecacht). Bei EN/DE = 2 (wie heute). Skaliert linear mit Registry-Größe.
- **`plainto_tsquery('', '')`** → leere tsquery, matcht nichts (korrekt; leerer `q` geht nicht in den q-Branch).
- **Bestehende Tests:** Die 7 `test_problems_search.py`-Fälle müssen unter reinem FTS grün bleiben (analysiert: gedeckt, inkl. `schlecht`→`Schlechte` via Stemmer; Translate-Zählung jetzt = Registry-Größe, nicht fix 2 — Tests entsprechend anpassen). Bei Abweichung Ursache prüfen, nicht Test aufweichen.

## Done-Kriterien

- [ ] `services/search_languages.py`: `SEARCH_LANGUAGES` + `tsvector_sql`; Initial-Registry `en`+`de`.
- [ ] Migration 010 erstellt funktionale GIN-Indizes (`ix_problems_fts_en`/`_de`) via `tsvector_sql`; `alembic upgrade head` sauber; Downgrade dropt sie. **Kein** Model-/Spalten-Change; Drift-Guard bleibt grün.
- [ ] ILIKE-Recall durch registry-geloopte FTS (`@@ plainto_tsquery`, alle Configs, raw + übersetzte Varianten) ersetzt.
- [ ] `cursor.py` generalisiert auf `q_translations`-Map (`"qt"`); alle Sort-Branches gereicht; `peek_cursor_translations` vorhanden.
- [ ] `sort=relevance`: `Σ ts_rank` über Registry, `ORDER BY rank DESC, id`, Keyset `(rank,id)`, Cursor trägt `rank`+`qt`; ohne `q` → Fallback `created`.
- [ ] Alle bestehenden `test_problems_search.py` grün (gegen echtes Postgres).
- [ ] Neue Tests: (a) Stemming-Symmetrie `fehlend`/`fehlende`/`fehlt` ⇄ `missing` → identische Treffermenge; (b) `sort=relevance` ordnet stärkeren Treffer vor schwächerem; (c) Relevance-Keyset-Pagination ohne Overlap; (d) **Extensibility-Smoke:** eine dritte Registry-Sprache (z. B. `("fr","french")`, nur im Test gepatcht inkl. Index) wird ohne Code-Änderung außerhalb der Registry/Migration matchbar.
- [ ] Frontend: `'relevance'` in `SortKey`+Mapping; `keywordRelevanceEnabled`-State + Toggle (nur bei aktiver Keyword-Suche); `relevanceSortActive` auf Keyword-Fall erweitert (StatusBar-Hinweis + Header-Lock greifen); Vitest-Abdeckung.
- [ ] Gesamte Backend-Unit-Suite + Frontend-Suite grün; ruff sauber (keine neuen Errors).

## Betroffene Dateien (Erstschätzung)

**Backend (`apps/backend`):**
- neu: `services/search_languages.py` (`SEARCH_LANGUAGES`, `tsvector_sql`)
- neu: `alembic/versions/010_add_fts_functional_indexes.py` (funktionale GIN-Indizes via `tsvector_sql`)
- `services/cursor.py` (`q_translations`-Map statt `q_en`/`q_de`; `peek_cursor_translations`)
- `routers/problems.py` (`list_problems` WHERE-Block; `_apply_sort_and_keyset` `relevance`-Branch + `q_translations`-Threading; `q`-Übersetzungs-Loop; Docstring/`sort`-Aufzählung)
- Tests: `tests/unit/test_problems_search.py` (FTS-Symmetrie/Stemming + Translate-Zählung = Registry-Größe), neuer `tests/unit/test_problems_relevance.py` (Ranking + Keyset + Extensibility-Smoke)

**Frontend (`apps/frontend`):**
- `pages/table.vue` (`SortKey`+Mapping; inject `keywordRelevanceEnabled`; `buildQuery` `sort=relevance`)
- `layouts/default.vue` (`keywordRelevanceEnabled` ref + provide; `relevanceSortActive` erweitern; Reset-Logik)
- `components/DmTopBar.vue` (Relevanz-Toggle, sichtbar nur bei aktiver Keyword-Suche)
- Vitest: Sort-/Relevanz-Spec (z. B. `tests/composables/useProblemsPagination.spec.ts` erweitern + Toggle-Spec)

**Root (`docs/`):** `docs/features.md` (Suche: FTS + Relevanz + Sprach-Registry), CLAUDE.md-Feature-Zeile (Suche).
