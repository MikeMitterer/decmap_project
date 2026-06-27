# F2 — Cross-linguale Keyword-Suche + Relevanz-Ranking (Postgres FTS) — Design

**Datum:** 2026-06-27
**Status:** Approved (Brainstorm) → bereit für Implementierungsplan
**Repos:** `apps/backend` (FTS + `sort=relevance`) + `apps/frontend` (Sort-Option)
**Issues:** #32 (cross-linguale Such-Symmetrie) + #37 (Relevanz-Sortierung)
**Voraussetzung:** Test-DB-Umstellung auf Postgres (erledigt 2026-06-27) — FTS ist jetzt ohne `skipif` testbar.

## Motivation

Die Keyword-Suche (`GET /problems?q=`) übersetzt die Anfrage heute via ai-service LLM nach EN und DE (`translate_query`, 1× pro Sprache, im Cursor gecacht) und matcht alle Varianten (raw `q`, `q_en`, `q_de`) per **ILIKE-Substring** gegen `title`, `description` und `original_translations` (JSONB → Text).

**Problem:** ILIKE ist ein literaler Substring-Match — er kennt keine Morphologie. `fehlend` matcht `fehlende`/`fehlenden` (zufällig, weil Substring), aber **nicht** `fehlt`; und die EN→DE-Übersetzung `missing`→`fehlend` verfehlt flektierte deutsche Formen. Befund: `missing`→4 Treffer vs. `fehlend`→6 Treffer — **asymmetrisch**. Außerdem gibt es **kein Relevanz-Ranking**: Treffer werden nur nach `created`/`votes`/… sortiert, nicht nach Übereinstimmungsgüte (#37).

**Ziel:** Symmetrischer, morphologie-bewusster Recall via Postgres-Volltextsuche (Stemming pro Sprache) **und** ein opt-in Relevanz-Ranking (`ts_rank`). EN- und DE-Suche liefern dieselbe Treffermenge; eine explizite Anfrage kann nach Relevanz sortiert werden.

## Non-Goals

- **Keine Präfix-/Substring-Suche** (`gov` → `governance`). FTS arbeitet wort-/lexem-basiert. Präfix-Suche (`to_tsquery('gov:*')`) ist ein optionales späteres Add-on, kein Teil von F2 — aktuell von keinem Test/Feature gefordert.
- **Keine Änderung an der semantischen Suche** (`?semantic=`, pgvector). Bleibt unverändert; `q` und `semantic` bleiben mutually exclusive.
- **Keine zusätzlichen Sprachen** außer EN/DE (MVP-Sprachumfang).
- **Keine Änderung der Übersetzungs-Pipeline** (`translate_query`, Cursor-Caching, „≤2× pro Such-Session"-Invariante bleiben).
- **Keine weiteren Sprach-Konfigs für `original_translations`** außer `de` (EN-Original liegt bereits im Canonical `title`/`description`).

## Kern-Prinzip

**Reines FTS ersetzt ILIKE** (Ansatz A — gewählt). Statt Substring-Match werden gestemmte `tsvector`-Spalten pro Sprache gegen `plainto_tsquery` gematcht. Die LLM-Übersetzung bleibt (sie liefert die cross-linguale Brücke); FTS ergänzt die **innersprachliche** Morphologie (Stemming). Beides zusammen = symmetrischer Recall.

Verworfen: Additiv FTS + ILIKE (Ansatz B) — doppelte WHERE-Logik, ILIKE bringt Asymmetrie-Rauschen zurück, Ranking-Signal nur aus dem FTS-Teil (inkonsistent).

## Architektur / Komponenten

### 1. Schema — Migration 010 (`apps/backend`)

Zwei `STORED GENERATED` tsvector-Spalten auf `problems` + GIN-Indizes:

```sql
ALTER TABLE problems ADD COLUMN search_en tsvector
  GENERATED ALWAYS AS (
    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))
  ) STORED;

ALTER TABLE problems ADD COLUMN search_de tsvector
  GENERATED ALWAYS AS (
    to_tsvector('german',
      coalesce(title, '') || ' ' || coalesce(description, '') || ' ' ||
      coalesce(original_translations -> 'de' ->> 'title', '') || ' ' ||
      coalesce(original_translations -> 'de' ->> 'description', ''))
  ) STORED;

CREATE INDEX ix_problems_search_en ON problems USING gin (search_en);
CREATE INDEX ix_problems_search_de ON problems USING gin (search_de);
```

- **Warum `search_de` auch `title`/`description` einschließt:** Die EN-Übersetzung ist optional/asynchron („EN-Felder sind kein Submit-Blocker") — eine deutsche Einreichung bleibt bis zur Übersetzung **deutsch im Canonical** `title`/`description`. `search_de` muss diese Felder daher mit-stemmen (sonst verfehlt eine DE-Suche untranslatierte deutsche Probleme; genau dieser Fall steckt in `test_keyword_search_symmetric_en_finds_de_only`). `search_en` bleibt auf den (englischen) Canonical beschränkt; `original_translations -> 'de'` ist reines Deutsch und gehört nur in `search_de`.
- **IMMUTABLE-Anforderung erfüllt:** `->`/`->>` (jsonb), `||`, `coalesce`, `to_tsvector(regconfig, text)` mit **konstanter** Config sind alle immutable → generierte Spalten zulässig.
- **Backfill:** Generierte Spalten berechnen sich automatisch für alle bestehenden Zeilen — kein separater Backfill-Schritt nötig.
- **Downgrade:** Indizes + Spalten droppen.

### 2. ORM-Model + Drift-Guard

Beide Spalten im `Problem`-Model als `Computed`-Spalten spiegeln (Typ `TSVECTOR` aus `sqlalchemy.dialects.postgresql`), sonst meldet der Drift-Guard (`test_schema_migrations_sync.py`) `remove_column`:

```python
from sqlalchemy import Computed
from sqlalchemy.dialects.postgresql import TSVECTOR

search_en: Mapped[Optional[str]] = mapped_column(
    TSVECTOR,
    Computed("to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))",
             persisted=True),
    nullable=True,
)
# search_de analog mit der german/JSONB-Expression
```

Die Spalten werden **nie** über das ORM gelesen/geschrieben — nur in raw-SQL-`text()`/Core-Ausdrücken für Match + Rank verwendet (analog `embedding`, das in `_to_read` ausgeschlossen ist). In `_to_read` ausschließen (nicht serialisieren).

**Risiko / Verify-Schritt:** Der Drift-Guard muss grün bleiben. `compare_metadata` vergleicht den Computed-`sqltext` per Default **nicht** — Anwesenheit der Spalte sollte genügen. Falls doch ein kosmetischer Computed-/Typ-Diff gemeldet wird: eng begrenzte, **dokumentierte** Ausnahme im Guard (gleiches Muster wie die tolerierten Index-/Constraint-Diffs) — kein echter Drift wird verdeckt.

### 3. Recall (WHERE) — ersetzt den ILIKE-Block in `list_problems`

`q_en`/`q_de` werden wie heute aufgelöst (Page 1: `translate_query(q, "en"|"de")`; Page 2+: aus dem Cursor). Der ILIKE-Block wird ersetzt durch:

```
OR(
   search_en @@ plainto_tsquery('english', v)   für v in [q, q_en] wenn v truthy,
   search_de @@ plainto_tsquery('german',  v)    für v in [q, q_de] wenn v truthy,
)
```

- **Raw `q` gegen beide Configs** ist der Übersetzungs-Ausfall-sichere Pfad: schlägt der ai-service fehl (`translate_query` → `None`, z. B. in Unit-Tests), matcht `q` trotzdem gegen `search_en` **und** `search_de`. Das deckt u. a. `test_q_matches_original_translations_raw` (`q=schlecht` → German-Stemmer `Schlechte`→`schlecht`) ohne Übersetzung ab.
- Dedup identischer Varianten (z. B. `q == q_en`) ist nicht nötig — doppelte OR-Klauseln sind harmlos; optional bereinigen.
- Operator via SQLAlchemy Core: `Problem.search_en.op("@@")(func.plainto_tsquery("english", v))`.

### 4. Relevanz — neuer `sort=relevance` (opt-in)

Neuer Branch in `_apply_sort_and_keyset` (erhält `q_en`/`q_de` bereits als Parameter). Rank als Summe der Sprach-Ränge:

```
rank = ts_rank(search_en, plainto_tsquery('english', coalesce(q_en, q)))
     + ts_rank(search_de, plainto_tsquery('german',  coalesce(q_de, q)))
```

- `ORDER BY rank DESC, id ASC`; **Keyset** auf `(rank, id)` — exakt analog zum bestehenden `semantic`-Distanz-Keyset (`_list_problems_semantic`). Der Branch gibt `(Problem, rank)`-Rows zurück (wie `solutions`/`tag`-Sort) und hängt `rank` als Attribut an, damit `make_next_cursor` ihn liest.
- **Cursor** trägt `rank` + `id` + `q_en` + `q_de` (q-Varianten sind ohnehin in jedem Cursor) → Page 2+ ohne Re-Translate, identische `plainto_tsquery`-Inputs.
- **`sort=relevance` ohne `q`** → graceful Fallback auf `created` (kein Ranking-Signal vorhanden; kein 422).
- **Summe vs. greatest:** `sum` gewählt — ein Treffer in beiden Sprachquellen (EN-Canonical + DE-Original) ist relevanter als in nur einer. Bei nur einer Quelle ist der andere Summand 0.

Andere Sort-Modi (`created`/`votes`/`title`/`status`/`solutions`/`tag`) bleiben **unverändert** und profitieren nur vom verbesserten FTS-Recall in der WHERE-Klausel.

### 5. Frontend (`apps/frontend`)

- **„Relevance"** als zusätzliche Sort-Option im Such-/Table-Kontext, sinnvoll nur bei aktiver Keyword-Suche (`q` gesetzt). `sort=relevance` an die `/problems`-API durchreichen.
- Die bestehende **„Sorted by relevance"-StatusBar-Logik** (heute für `semantic`/`relevanceSortActive` in `layouts/default.vue`) wird auf den Keyword-Relevanz-Fall erweitert: Hinweis + Sort-Sperre, wenn Keyword-Suche aktiv **und** `sort=relevance`.
- Verhalten bei Wechsel Suche↔kein-Suchbegriff: fällt `q` weg, zurück auf den vorherigen/Default-Sort (kein hängender `relevance`-Zustand ohne Query).

## Datenfluss

```
User tippt q
  → Frontend GET /problems?q=…&sort=relevance (oder &sort=created)
  → Backend: q_en = translate_query(q,'en'), q_de = translate_query(q,'de')   [Page 1, gecacht im Cursor]
  → WHERE: search_en @@ plainto_tsquery('english', {q,q_en})
        OR search_de @@ plainto_tsquery('german',  {q,q_de})
  → sort=relevance: ORDER BY ts_rank(en)+ts_rank(de) DESC, id ; Keyset (rank,id)
     sonst:         bisherige Sortierung, FTS nur im WHERE
  → ProblemPage(items, next_cursor[rank,id,q_en,q_de], total)
```

## Risiken / erwartete Arbeit

- **Drift-Guard ↔ Computed-Spalten** (s. Komponente 2) — fragilster Punkt; Verifikation = Guard grün. Fallback: dokumentierte Ausnahme.
- **German-Stemmer-Erwartungen:** Tests müssen reale Snowball-`german`-Stemming-Ergebnisse annehmen (z. B. `fehlend`/`fehlende`/`fehlt`→`fehl`), nicht idealisierte. Bei Überraschungen Erwartung an tatsächliche Lexeme anpassen (kein Verstecken).
- **`plainto_tsquery` vs. leere Query:** `plainto_tsquery('english','')` → leere tsquery, matcht nichts (korrekt; leerer `q` geht ohnehin nicht in den q-Branch).
- **Mixed-Language-Felder:** `to_tsvector('english', …)` auf deutschem Canonical-Text (selten — Canonical ist per Konvention EN) stemmt suboptimal, aber harmlos; DE-Original deckt den deutschen Pfad ab.
- **Performance:** GIN-Index macht Match indexierbar; `ts_rank` ist eine Sortier-Berechnung über die Treffermenge (klein bei aktueller Daten-Größe). Akzeptabel.
- **Bestehende Tests:** Die 7 `test_problems_search.py`-Fälle müssen unter reinem FTS grün bleiben (analysiert: gedeckt, inkl. `schlecht`→`Schlechte` via Stemmer). Bei Abweichung Ursache prüfen, nicht Test aufweichen.

## Done-Kriterien

- [ ] Migration 010 erstellt `search_en`/`search_de` (generated) + GIN-Indizes; `alembic upgrade head` läuft sauber; Downgrade vorhanden.
- [ ] `Problem`-Model spiegelt beide Spalten als `Computed`; `_to_read` schließt sie aus; **Drift-Guard grün**.
- [ ] ILIKE-Recall durch FTS (`@@ plainto_tsquery`, beide Configs, raw + übersetzte Varianten) ersetzt.
- [ ] `sort=relevance` implementiert: `ts_rank`-Summe, `ORDER BY rank DESC, id`, Keyset `(rank,id)`, Cursor trägt `rank`+`q_en`+`q_de`; ohne `q` → Fallback `created`.
- [ ] Alle bestehenden `test_problems_search.py` grün (gegen echtes Postgres, kein `skipif`).
- [ ] Neue Tests: (a) Stemming-Symmetrie `fehlend`/`fehlende`/`fehlt` ⇄ `missing` → identische Treffermenge; (b) `sort=relevance` ordnet stärkeren Treffer vor schwächerem; (c) Relevance-Keyset-Pagination ohne Overlap + `translate_query` ≤2×.
- [ ] Frontend: „Relevance"-Sort-Option, `sort=relevance` durchgereicht, „Sorted by relevance"-Hinweis/Sort-Sperre auf Keyword-Fall erweitert; Vitest-Abdeckung.
- [ ] Gesamte Backend-Unit-Suite + Frontend-Suite grün; ruff sauber (keine neuen Errors).

## Betroffene Dateien (Erstschätzung)

**Backend (`apps/backend`):**
- neu: `alembic/versions/010_add_fts_search_columns.py`
- `models/problem.py` (zwei `Computed`-tsvector-Spalten)
- `routers/problems.py` (`list_problems` WHERE-Block; `_apply_sort_and_keyset` `relevance`-Branch; Cursor; `_to_read`-Ausschluss; Docstring/`sort`-Aufzählung)
- ggf. `services/cursor.py` (falls Relevance-Cursor-Key wie `semantic`-`emb` ein eigenes Feld braucht)
- Tests: `tests/unit/test_problems_search.py` (Symmetrie/Stemming), neuer `tests/unit/test_problems_relevance.py` (Ranking + Keyset)

**Frontend (`apps/frontend`):**
- Sort-Option-Komponente (Such-/Table-Kontext) + API-Param `sort=relevance`
- `layouts/default.vue` (relevanceSortActive auf Keyword-Fall erweitern) + StatusBar-Hinweis
- Vitest-Specs für die neue Sort-Option

**Root (`docs/`):** `docs/features.md` (Suche-Sektion: FTS + Relevanz), CLAUDE.md-Feature-Zeile (Suche).
