# F2 — Cross-linguale Keyword-Suche + Relevanz-Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keyword-Suche (`GET /problems?q=`) nutzt registry-getriebenes Postgres-FTS (Stemming pro Sprache, cross-lingual symmetrisch) statt ILIKE und bietet ein opt-in Relevanz-Ranking (`sort=relevance`, `ts_rank`).

**Architecture:** Eine zentrale `SEARCH_LANGUAGES`-Registry + `tsvector_sql`-Template liefern pro Sprache einen FTS-Ausdruck; funktionale GIN-Indizes (Migration 010) machen das `@@`-Match indexierbar. WHERE-Klausel, `ts_rank`-Ranking und LLM-Übersetzung loopen die Registry; der Keyset-Cursor trägt eine `q_translations`-Map. Eine Sprache hinzufügen = Registry-Eintrag + templated Index-Migration + Translation — kein Model-/Frontend-/Cursor-Edit.

**Tech Stack:** FastAPI, SQLAlchemy(async)+asyncpg, Alembic, PostgreSQL FTS (`to_tsvector`/`plainto_tsquery`/`ts_rank`, GIN), pytest (testcontainers Postgres), Nuxt 3 + TypeScript + Vitest.

**Spec:** `docs/specs/2026-06-27-f2-cross-lingual-search-design.md`

## Global Constraints

- **Repos/Branches:** `apps/backend` (master), `apps/frontend` (`feature/bold-redesign`), Root (`master`). Pro Repo committen.
- **Conventional Commits** + Trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Backend-Befehle mit absolutem venv-Pfad** (keine Permission-Rückfrage): `/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest …`.
- **Docker muss laufen** (Unit-Tests starten testcontainers Postgres+pgvector).
- **Kein SQLite** mehr; Tests laufen gegen echtes Postgres.
- **Reines FTS ersetzt ILIKE** (keine additive ILIKE-Beibehaltung).
- **Migrationen sind immutable Snapshots:** Migration listet ihre Sprachen **explizit**, sie loopt NICHT die Live-Registry (sonst divergieren fresh-migrated vs. upgraded DBs).
- **`tsvector_sql`-Output ist ein stabiler Vertrag:** Index- und Query-Ausdruck stammen aus derselben Funktion; eine Änderung erfordert eine Reindex-Migration.
- **Frontend ist sprach-agnostisch:** kennt keine Registry, sendet nur `q` + `sort=relevance`.
- **ruff sauber** (keine neuen Errors); bestehende Test-Suiten bleiben grün.

---

### Task 1: Sprach-Registry + funktionale GIN-Indizes (Migration 010)

**Files:**
- Create: `apps/backend/services/search_languages.py`
- Create: `apps/backend/alembic/versions/010_add_fts_functional_indexes.py`
- Create: `apps/backend/tests/unit/test_fts_indexes.py`

**Interfaces:**
- Produces: `SEARCH_LANGUAGES: list[tuple[str, str]]` und `tsvector_sql(lang: str, config: str) -> str` (genutzt von Migration, WHERE-Klausel Task 3, Ranking Task 4).

- [ ] **Step 1: Registry-Modul schreiben.** Create `apps/backend/services/search_languages.py`:

```python
"""Sprach-Registry für Postgres-Volltextsuche (FTS).

Single Source of Truth für die unterstützten Suchsprachen. WHERE-Klausel,
ts_rank-Ranking und die LLM-Übersetzung in routers/problems.py loopen diese
Registry. Eine Sprache hinzufügen = hier ein Tupel ergänzen + eine funktionale
Index-Migration (analog 010, mit der neuen Sprache explizit) + translate_query
muss die Sprache liefern. Kein weiterer Code-Change nötig.
"""

# (lang_code wie in original_translations, Postgres-Textsuche-Config)
SEARCH_LANGUAGES: list[tuple[str, str]] = [("en", "english"), ("de", "german")]


def tsvector_sql(lang: str, config: str) -> str:
    """FTS-Vektor-SQL einer Sprache — IDENTISCH in funktionalem Index UND Query.

    Stemmt sowohl den Canonical (title/description) als auch den sprachspezifischen
    original_translations-Eintrag: deutsche Einreichungen bleiben bis zur (optionalen)
    EN-Übersetzung deutsch im Canonical, müssen also unter der jeweiligen Config
    auffindbar sein.

    Stabiler Vertrag: Ändert sich der Output, nutzt der Planner bestehende
    funktionale Indizes nicht mehr → Reindex-Migration erforderlich.
    """
    return (
        f"to_tsvector('{config}', "
        f"coalesce(title, '') || ' ' || coalesce(description, '') || ' ' || "
        f"coalesce(original_translations -> '{lang}' ->> 'title', '') || ' ' || "
        f"coalesce(original_translations -> '{lang}' ->> 'description', ''))"
    )
```

- [ ] **Step 2: Migration 010 schreiben.** Create `apps/backend/alembic/versions/010_add_fts_functional_indexes.py`. **Sprachen explizit auflisten** (immutable Snapshot — NICHT `SEARCH_LANGUAGES` loopen):

```python
"""Add functional GIN indexes for cross-lingual full-text search (en/de)."""
from alembic import op

from services.search_languages import tsvector_sql

revision = "010"
down_revision = "009"
branch_labels = None
depends_on = None

# Explicit snapshot of the languages indexed at THIS migration (immutable).
# Adding a language later → a NEW migration with that language, not editing this.
_LANGS = [("en", "english"), ("de", "german")]


def upgrade() -> None:
    for lang, config in _LANGS:
        op.execute(
            f"CREATE INDEX ix_problems_fts_{lang} "
            f"ON problems USING gin ({tsvector_sql(lang, config)})"
        )


def downgrade() -> None:
    for lang, _config in _LANGS:
        op.execute(f"DROP INDEX IF EXISTS ix_problems_fts_{lang}")
```

- [ ] **Step 3: Failing-Test schreiben.** Create `apps/backend/tests/unit/test_fts_indexes.py`:

```python
"""FTS-Vektor (tsvector_sql) stemmt sprachkorrekt — gegen echtes Postgres."""
import uuid

import pytest
from sqlalchemy import text

from models.problem import Problem
from services.search_languages import tsvector_sql


@pytest.mark.asyncio
async def test_tsvector_de_stems_inflected_german(db_session):
    """German-Config stemmt 'Fehlende'/'fehlt' → matchbar mit plainto_tsquery('german','fehlend')."""
    pid = uuid.uuid4()
    db_session.add(Problem(
        id=pid,
        title="Fehlende KI-Governance, es fehlt ein Rahmen",
        status="approved",
        session_id="fts-test",
    ))
    await db_session.flush()

    expr = tsvector_sql("de", "german")
    row = await db_session.execute(
        text(f"SELECT 1 FROM problems WHERE id = :id "
             f"AND {expr} @@ plainto_tsquery('german', 'fehlend')"),
        {"id": pid},
    )
    assert row.first() is not None, "german stemmer must match 'fehlend' to 'Fehlende'/'fehlt'"


@pytest.mark.asyncio
async def test_tsvector_de_reads_original_translations(db_session):
    """German original in original_translations is indexed under the de config."""
    pid = uuid.uuid4()
    db_session.add(Problem(
        id=pid,
        title="Poor data quality blocks ML",
        status="approved",
        session_id="fts-test",
        original_translations={"de": {"title": "Schlechte Datenqualität", "description": "x"}},
    ))
    await db_session.flush()

    expr = tsvector_sql("de", "german")
    row = await db_session.execute(
        text(f"SELECT 1 FROM problems WHERE id = :id "
             f"AND {expr} @@ plainto_tsquery('german', 'schlecht')"),
        {"id": pid},
    )
    assert row.first() is not None, "de original_translations must be FTS-matchable"
```

- [ ] **Step 4: Test ausführen — muss fehlschlagen, falls Migration noch nicht greift.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_fts_indexes.py -q`
Expected: PASS (die FTS-Ausdrücke funktionieren auch ohne Index; der Index ist nur Performance). Falls FAIL wegen Import/SQL-Fehler → fixen. Der Test verifiziert primär `tsvector_sql`-Korrektheit; Migration-Smoke folgt in Step 5.

- [ ] **Step 5: Migration + Drift-Guard verifizieren.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_fts_indexes.py tests/unit/test_schema_migrations_sync.py -q`
Expected: alle PASS. Der `_db_url`-Fixture-Setup fährt `alembic upgrade head` inkl. Migration 010 — schlägt das fehl, ist die Migration kaputt. Drift-Guard bleibt grün (kein Model-Change).

- [ ] **Step 6: Index-Nutzung optional prüfen (manuell, kein Test).** Optional Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_fts_indexes.py -q` ist ausreichend; eine EXPLAIN-Prüfung ist bei kleiner Testdatenmenge nicht aussagekräftig (Planner wählt Seq-Scan) — daher kein automatischer Index-Nutzungs-Test.

- [ ] **Step 7: ruff + Commit.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/ruff check services/search_languages.py alembic/versions/010_add_fts_functional_indexes.py tests/unit/test_fts_indexes.py`
Dann:

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add services/search_languages.py alembic/versions/010_add_fts_functional_indexes.py tests/unit/test_fts_indexes.py
git commit -m "feat(search): Sprach-Registry + funktionale GIN-FTS-Indizes (en/de)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Cursor → q_translations-Map (behavior-preserving Refactor)

**Files:**
- Modify: `apps/backend/services/cursor.py`
- Modify: `apps/backend/routers/problems.py` (Imports, `_apply_sort_and_keyset`-Signatur + alle `make_next_*`, `list_problems` Übersetzungs-Loop; ILIKE-Block nutzt vorerst die Map-Werte)

**Interfaces:**
- Consumes: `SEARCH_LANGUAGES` (Task 1).
- Produces: `encode_cursor(..., q_translations: dict[str,str] | None = None)`, `peek_cursor_translations(cursor) -> dict | None`, `decode_cursor(...)["q_translations"]`. `_apply_sort_and_keyset(..., q_translations: dict | None = None, q_raw: str | None = None, ...)`.

**Hintergrund:** Verhaltens-erhaltend — ILIKE bleibt in diesem Task erhalten, matcht aber `q` + `q_translations.values()`. Bestehende `test_problems_search.py` müssen grün bleiben (Übersetzungs-Anzahl = Registry-Größe = 2 für en/de).

- [ ] **Step 1: cursor.py generalisieren.** In `apps/backend/services/cursor.py` `q_en`/`q_de` durch `q_translations` ersetzen. Neue/­geänderte Funktionen:

```python
def encode_cursor(
    sort: str,
    key: Any,
    id: str,
    emb: list[float] | None = None,
    q_translations: dict[str, str] | None = None,
    direction: str | None = None,
) -> str:
    """Encode a keyset cursor as a url-safe base64 string.

    q_translations: per-language translated query map ({lang: text}); threaded
    through pages so translate_query runs at most once per language per session.
    Stored under key "qt".
    """
    payload: dict[str, Any] = {"s": sort, "k": key, "i": id}
    if emb is not None:
        payload["e"] = emb
    if q_translations:
        payload["qt"] = q_translations
    if direction is not None:
        payload["d"] = direction
    raw = json.dumps(payload, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode()


def peek_cursor_translations(cursor: str) -> dict | None:
    """Best-effort extraction of the cached translation map ("qt") from a cursor,
    WITHOUT sort-validation — used to reuse translations on later pages.

    Returns None on any malformed input (full decode_cursor enforces validity).
    """
    try:
        payload = json.loads(base64.urlsafe_b64decode(cursor.encode()))
        return payload.get("qt")
    except Exception:
        return None
```

In `decode_cursor` das Rückgabe-Dict anpassen: `q_en`/`q_de` entfernen, `"q_translations": payload.get("qt")` ergänzen. Die alten `peek_cursor_q_en`/`peek_cursor_q_de` **löschen**. Den Modul-Docstring-Format-Kommentar (Zeile „Format: …") auf `"qt"` aktualisieren.

- [ ] **Step 2: problems.py-Imports anpassen.** In `apps/backend/routers/problems.py` den Cursor-Import ändern:

```python
from services.cursor import (
    decode_cursor,
    encode_cursor,
    peek_cursor_translations,
)
from services.search_languages import SEARCH_LANGUAGES, tsvector_sql
```

(Entferne `peek_cursor_q_en`, `peek_cursor_q_de` aus dem Import. `tsvector_sql` wird in Task 3/4 genutzt — Import jetzt schon setzen ist ok, sonst ruff F401: in diesem Task nur `SEARCH_LANGUAGES` importieren und `tsvector_sql` in Task 3 ergänzen, um F401 zu vermeiden.)

- [ ] **Step 3: `_apply_sort_and_keyset`-Signatur + Cursor-Aufrufe.** Signatur ändern: `q_en`, `q_de` → `q_translations`, plus `q_raw`:

```python
def _apply_sort_and_keyset(
    q: Select,
    sort: str,
    cursor: str | None,
    limit: int,
    dialect_name: str = "sqlite",
    base_where: list[Any] | None = None,
    q_translations: dict[str, str] | None = None,
    q_raw: str | None = None,
    dir_param: str | None = None,
) -> tuple[Select, Callable[[Any], str]]:
```

In **jeder** `make_next_*`-Closure (created, votes, title, status, solutions, tag) den `encode_cursor`-Aufruf von `q_en=q_en, q_de=q_de` auf `q_translations=q_translations` umstellen. Beispiel (created):

```python
        def _make_next_created(last: Any) -> str:
            return encode_cursor(
                "created", last.created_at.isoformat(), str(last.id),
                q_translations=q_translations, direction=direction,
            )
```

(Analog votes/title/status/solutions/tag — nur `q_en=…, q_de=…` → `q_translations=q_translations` ersetzen.)

- [ ] **Step 4: `list_problems` Übersetzungs-Loop + Aufruf.** Den Block, der `q_en`/`q_de` auflöst (heute via `peek_cursor_q_en/q_de` bzw. `translate_query(q,"en"|"de")`), ersetzen durch:

```python
    # ── Resolve q_translations: read from cursor on pages 2+, translate once per
    #    registry language on page 1; threaded through every cursor as "qt". ──
    q_translations: dict[str, str] = {}
    if q:
        if cursor:
            q_translations = peek_cursor_translations(cursor) or {}
        else:
            for lang, _config in SEARCH_LANGUAGES:
                tr = await translate_query(q, lang)
                if tr:
                    q_translations[lang] = tr
```

Den ILIKE-Block **vorerst beibehalten**, aber Patterns aus der Map ziehen:

```python
    if q:
        patterns = [p for p in (q, *q_translations.values()) if p]
        raw_clauses: list[Any] = []
        for pat in patterns:
            like = f"%{pat}%"
            raw_clauses.extend([
                Problem.title.ilike(like),
                Problem.description.ilike(like),
                cast(Problem.original_translations, Text).ilike(like),
            ])
        base_where.append(or_(*raw_clauses))
```

Den `_apply_sort_and_keyset`-Aufruf anpassen: `q_en=q_en, q_de=q_de` → `q_translations=q_translations, q_raw=q`.

- [ ] **Step 5: Bestehende Such-Tests laufen.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_search.py tests/unit/test_problems_pagination.py -q`
Expected: alle PASS (Verhalten unverändert; Übersetzung 2× = en+de). Falls die Translate-Zähl-Asserts brechen, prüfen — sollten weiterhin 2 sein (Registry en+de).

- [ ] **Step 6: ruff + Commit.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/ruff check services/cursor.py routers/problems.py`

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add services/cursor.py routers/problems.py
git commit -m "refactor(search): Cursor trägt q_translations-Map (N-sprachfähig)

Ersetzt fixe q_en/q_de durch eine {lang: text}-Map (Cursor-Key 'qt'); Übersetzung
loopt SEARCH_LANGUAGES. Verhaltens-erhaltend (ILIKE bleibt vorerst).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: ILIKE → registry-geloopte FTS (Recall)

**Files:**
- Modify: `apps/backend/routers/problems.py` (`list_problems` WHERE-Block; `tsvector_sql`-Import aktivieren)
- Modify: `apps/backend/tests/unit/test_problems_search.py` (neue Symmetrie-/Stemming-Tests)

**Interfaces:**
- Consumes: `SEARCH_LANGUAGES`, `tsvector_sql` (Task 1), `q_translations` (Task 2).

- [ ] **Step 1: Failing-Test (Stemming-Symmetrie) schreiben.** In `apps/backend/tests/unit/test_problems_search.py` ergänzen:

```python
@pytest.mark.asyncio
async def test_fts_stemming_symmetry_fehlend_missing(superuser_client, monkeypatch):
    """missing⇄fehlend finden dieselbe Menge über flektierte deutsche Formen (Stemming)."""
    async def _mock_translate(text: str, target_lang: str) -> str | None:
        t = text.lower()
        if "missing" in t and target_lang == "de":
            return "fehlend"
        if "fehlend" in t and target_lang == "en":
            return "missing"
        return text
    monkeypatch.setattr("routers.problems.translate_query", _mock_translate)

    # Drei flektierte deutsche Formen — ILIKE 'fehlend' verfehlt 'fehlt'; FTS stemmt alle → 'fehl'.
    for title in ["Fehlende Governance Richtlinie", "Fehlender klarer Rahmen",
                  "Es fehlt ein klarer Prozess"]:
        await _create_approved(superuser_client, title=title)

    ids_en = {it["id"] for it in
              (await superuser_client.get("/problems?q=missing&status_filter=approved")).json()["items"]}
    ids_de = {it["id"] for it in
              (await superuser_client.get("/problems?q=fehlend&status_filter=approved")).json()["items"]}
    assert ids_en == ids_de, f"EN/DE müssen symmetrisch sein: {ids_en} vs {ids_de}"
    assert len(ids_en) == 3, f"alle 3 flektierten Formen müssen matchen, got {len(ids_en)}"
```

- [ ] **Step 2: Test ausführen — muss fehlschlagen.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_search.py::test_fts_stemming_symmetry_fehlend_missing -q`
Expected: FAIL — ILIKE matcht „Es fehlt …" nicht (`fehlt` ≠ Substring `fehlend`), `len(ids_en) == 2`.

- [ ] **Step 3: ILIKE-Block durch FTS ersetzen.** In `list_problems` den ILIKE-`if q:`-Block (raw_clauses) ersetzen durch:

```python
    # ── Keyword filter: registry-geloopte FTS (ersetzt ILIKE) ─────────────────
    # Pro Sprache: raw q UND die übersetzte Variante gegen den Sprach-tsvector.
    # Raw q gegen jede Config = Übersetzungs-Ausfall-sicher.
    if q:
        fts_clauses: list[Any] = []
        for lang, config in SEARCH_LANGUAGES:
            variants = {v for v in (q, q_translations.get(lang)) if v}
            vec = literal_column(tsvector_sql(lang, config))
            for v in variants:
                fts_clauses.append(vec.op("@@")(func.plainto_tsquery(config, v)))
        base_where.append(or_(*fts_clauses))
```

`tsvector_sql` zum Import aus `services.search_languages` hinzufügen (falls in Task 2 weggelassen). `literal_column` ist bereits importiert (semantic-Branch); falls nicht, aus `sqlalchemy` ergänzen. `cast`/`Text` werden hier nicht mehr gebraucht — Imports nur entfernen, wenn sonst ungenutzt (sonst lassen).

- [ ] **Step 4: Neuen Test + alle Such-Tests grün.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_search.py -q`
Expected: alle PASS, inkl. neuer Symmetrie-Test (`len==3`) und die 7 bestehenden (FTS deckt sie ab: `schlecht`→`Schlechte` via german-Stemmer, `poor data` via english, Translate-Zählung = 2).

- [ ] **Step 5: Volle Backend-Unit-Suite + ruff.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit -q`
Expected: alle grün. Dann:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/ruff check routers/problems.py tests/unit/test_problems_search.py`

- [ ] **Step 6: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add routers/problems.py tests/unit/test_problems_search.py
git commit -m "feat(search): registry-FTS ersetzt ILIKE — cross-linguale Stemming-Symmetrie

q + übersetzte Varianten matchen pro Sprache gegen to_tsvector @@ plainto_tsquery
(funktionaler GIN-Index). EN/DE-Suche liefert symmetrische Treffermenge über
flektierte Formen. Behebt #32.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `sort=relevance` (ts_rank + Keyset)

**Files:**
- Modify: `apps/backend/routers/problems.py` (`relevance`-Branch in `_apply_sort_and_keyset`; `list_problems` Fallback + Row-Unpack + Docstring)
- Create: `apps/backend/tests/unit/test_problems_relevance.py`

**Interfaces:**
- Consumes: `SEARCH_LANGUAGES`, `tsvector_sql`, `q_translations`, `q_raw`.
- Produces: `sort="relevance"` Cursor (`encode_cursor("relevance", rank, id, q_translations=…)`).

- [ ] **Step 1: Failing-Tests schreiben.** Create `apps/backend/tests/unit/test_problems_relevance.py`:

```python
"""Unit tests — GET /problems?sort=relevance (ts_rank, opt-in, Keyset)."""
import pytest

_TOKEN = {"X-Service-Token": "dev-service-token"}


async def _create_approved(client, title: str, description: str = "x" * 60) -> str:
    r = await client.post("/problems", json={
        "title": title, "description": description, "session_id": "rel-test",
    })
    assert r.status_code == 201, r.text
    pid = r.json()["id"]
    r2 = await client.patch(f"/internal/problems/{pid}/status",
                            json={"status": "approved"}, headers=_TOKEN)
    assert r2.status_code == 200, r2.text
    return pid


@pytest.mark.asyncio
async def test_relevance_orders_stronger_match_first(superuser_client, monkeypatch):
    """Ein Problem mit dem Term in Titel+Beschreibung rankt vor nur-Beschreibung."""
    async def _noop_translate(text, target_lang):
        return None
    monkeypatch.setattr("routers.problems.translate_query", _noop_translate)

    weak = await _create_approved(superuser_client,
                                  title="Unrelated heading text", description="governance " + "x" * 50)
    strong = await _create_approved(superuser_client,
                                    title="Governance governance framework", description="governance policy")

    r = await superuser_client.get("/problems?q=governance&sort=relevance&status_filter=approved")
    assert r.status_code == 200, r.text
    ids = [it["id"] for it in r.json()["items"]]
    assert ids.index(strong) < ids.index(weak), f"stronger match must rank first: {ids}"


@pytest.mark.asyncio
async def test_relevance_without_q_falls_back_to_created(superuser_client, monkeypatch):
    """sort=relevance ohne q → graceful Fallback (created), kein 422."""
    async def _noop_translate(text, target_lang):
        return None
    monkeypatch.setattr("routers.problems.translate_query", _noop_translate)
    await _create_approved(superuser_client, title="Some problem without query")
    r = await superuser_client.get("/problems?sort=relevance&status_filter=approved")
    assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_relevance_keyset_pagination_no_overlap(superuser_client, monkeypatch):
    """Zwei Relevance-Seiten überlappen nicht und decken alle Treffer ab."""
    async def _noop_translate(text, target_lang):
        return None
    monkeypatch.setattr("routers.problems.translate_query", _noop_translate)
    for i in range(4):
        await _create_approved(superuser_client, title=f"Relevance governance item {i}")

    p1 = (await superuser_client.get(
        "/problems?q=governance&sort=relevance&limit=2&status_filter=approved")).json()
    ids1 = {it["id"] for it in p1["items"]}
    assert len(ids1) == 2 and p1["next_cursor"]
    p2 = (await superuser_client.get(
        f"/problems?q=governance&sort=relevance&limit=2&status_filter=approved&cursor={p1['next_cursor']}")).json()
    ids2 = {it["id"] for it in p2["items"]}
    assert ids1.isdisjoint(ids2), f"page overlap: {ids1 & ids2}"
    assert len(ids1 | ids2) == 4
```

- [ ] **Step 2: Tests ausführen — müssen fehlschlagen.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_relevance.py -q`
Expected: FAIL — `sort=relevance` ist „unsupported sort" (422) bzw. Fallback fehlt.

- [ ] **Step 3: relevance-Branch in `_apply_sort_and_keyset` einfügen.** Direkt vor dem finalen `else: raise HTTPException(... "unsupported sort" ...)` ergänzen:

```python
    elif sort == "relevance":
        # ts_rank-Summe über alle Registry-Sprachen; pro Sprache übersetzte Variante
        # (Fallback raw q). Match-Set kommt aus dem FTS-WHERE (list_problems).
        rank_terms = []
        for lang, config in SEARCH_LANGUAGES:
            variant = (q_translations or {}).get(lang) or q_raw or ""
            rank_terms.append(
                func.ts_rank(
                    literal_column(tsvector_sql(lang, config)),
                    func.plainto_tsquery(config, variant),
                )
            )
        rank_core = rank_terms[0]
        for t in rank_terms[1:]:
            rank_core = rank_core + t
        q = q.add_columns(rank_core.label("rank"))

        if cursor:
            try:
                cur = decode_cursor(cursor, "relevance")
                last_rank = float(cur["key"])
                last_id = uuid.UUID(cur["id"])
            except (ValueError, KeyError) as exc:
                raise HTTPException(status_code=422, detail="invalid cursor") from exc
            q = q.where(
                (rank_core < last_rank)
                | ((rank_core == last_rank) & (Problem.id < last_id))
            )

        q = q.order_by(rank_core.desc(), Problem.id.desc()).limit(limit + 1)

        def _make_next_relevance(last: Any) -> str:
            return encode_cursor(
                "relevance", float(last._rank), str(last.id), q_translations=q_translations
            )

        return q, _make_next_relevance
```

- [ ] **Step 4: `list_problems` — Fallback, Aufruf-Param, Row-Unpack.** Drei Änderungen:

(a) Vor dem Semantik-/q-Block einen Fallback ergänzen (nach der `dir`-Validierung):

```python
    # sort=relevance ohne Query hat kein Ranking-Signal → graceful Fallback.
    if sort == "relevance" and not q:
        sort = "created"
```

(b) Der `_apply_sort_and_keyset`-Aufruf hat in Task 2 bereits `q_translations=q_translations, q_raw=q` — sicherstellen, dass das so ist.

(c) Im Row-Unpacking `("solutions", "tag")` um `"relevance"` erweitern und das Key-Attribut mappen:

```python
    if sort in ("solutions", "tag", "relevance"):
        rows_full = result
        has_more = len(rows_full) > limit
        rows_full = rows_full[:limit]
        key_attr = {"solutions": "sol_c", "tag": "tag_key", "relevance": "_rank"}[sort]
        problems = []
        for row in rows_full:
            p = row[0]
            setattr(p, key_attr, row[1])
            problems.append(p)
    else:
        ...
```

- [ ] **Step 5: Docstring + sort-Aufzählung aktualisieren.** Im `list_problems`-Docstring `sort`-Zeile um `relevance` ergänzen: „… ``tag`` (structural/cluster tag name), ``relevance`` (ts_rank über q — opt-in, nur mit ``q``; ohne ``q`` Fallback auf ``created``)."

- [ ] **Step 6: Tests + volle Suite + ruff.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_relevance.py -q` → PASS;
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit -q` → alle grün;
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/ruff check routers/problems.py tests/unit/test_problems_relevance.py`

- [ ] **Step 7: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add routers/problems.py tests/unit/test_problems_relevance.py
git commit -m "feat(search): opt-in sort=relevance (ts_rank, Keyset)

Σ ts_rank über Registry-Sprachen, ORDER BY rank DESC + Keyset (rank,id); Cursor
trägt rank + q_translations; ohne q Fallback auf created. Behebt #37.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Frontend — `sort=relevance` Opt-in + StatusBar-Hinweis

**Files:**
- Modify: `apps/frontend/pages/table.vue` (`SortKey`+Mapping; inject `keywordRelevanceEnabled`; `buildQuery`)
- Modify: `apps/frontend/layouts/default.vue` (`keywordRelevanceEnabled` ref + provide; `relevanceSortActive` erweitern; Reset)
- Modify: `apps/frontend/components/DmTopBar.vue` (Relevanz-Toggle, sichtbar nur bei aktiver Keyword-Suche)
- Modify: `apps/frontend/i18n` Locale-Datei(en) (neue Keys `table.sortByRelevance`)
- Modify: `apps/frontend/tests/composables/useProblemsPagination.spec.ts` (sort=relevance Wire-Test)

**Interfaces:**
- Consumes: Backend `sort=relevance` (Task 4). `relevanceSortActive`/`provide`-Muster (bestehend).

- [ ] **Step 1: Failing Vitest — sort=relevance landet auf der Wire.** In `apps/frontend/tests/composables/useProblemsPagination.spec.ts` ergänzen (im Sort-Block ~Z.304):

```typescript
it('loadFirstPage: sort=relevance wird auf die Wire serialisiert', async () => {
  mockBackendFetch.mockResolvedValueOnce(makePage(['p1'], null, 1))
  await layer.loadFirstPage({ q: 'governance', sort: 'relevance' })
  const callPath = mockBackendFetch.mock.calls[0][1] as string
  expect(callPath).toContain('sort=relevance')
  expect(callPath).toContain('q=governance')
})
```

- [ ] **Step 2: Test ausführen — muss grün sein (Builder generisch).** Run:
`cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/frontend && npx vitest run tests/composables/useProblemsPagination.spec.ts`
Expected: PASS — `buildQueryString` serialisiert `query.sort` bereits generisch. (Falls der `ProblemQuery`-Typ `sort` auf ein Union einschränkt, das `'relevance'` nicht enthält → TS-Fehler; dann in Step 3 den Typ erweitern.)

- [ ] **Step 3: `SortKey` + Mapping erweitern.** In `apps/frontend/pages/table.vue`:

```typescript
type SortKey = 'title' | 'tag' | 'voteScore' | 'solutions' | 'status' | 'createdAt' | 'relevance'
```

In `toBackendSort` ergänzen: `case 'relevance': return 'relevance'`. In `fromBackendSort` die Map um `relevance: 'relevance'` ergänzen. Falls `ProblemQuery.sort` (in `composables/data/types` o. ä.) ein String-Union ist, dort `'relevance'` ergänzen.

- [ ] **Step 4: Layout-State + Provide + relevanceSortActive.** In `apps/frontend/layouts/default.vue`:

```typescript
const keywordRelevanceEnabled = ref<boolean>(false)
provide('keywordRelevanceEnabled', keywordRelevanceEnabled)

// Relevanz aktiv: semantische Suche (AI an + Query) ODER Keyword-Relevanz (AI aus
// + Query + Toggle an). Beides triggert Hinweis + Sort-Lock.
const relevanceSortActive = computed<boolean>(() => {
  const hasQuery = searchQuery.value.trim().length > 0
  const semantic = aiSearchEnabled.value && hasQuery
  const keyword = !aiSearchEnabled.value && hasQuery && keywordRelevanceEnabled.value
  return semantic || keyword
})

// Reset, damit kein hängender Relevanz-Zustand entsteht.
watch([searchQuery, aiSearchEnabled], () => {
  if (!searchQuery.value.trim() || aiSearchEnabled.value) keywordRelevanceEnabled.value = false
})
```

(Die bestehende `relevanceSortActive`-Computed ersetzen.)

- [ ] **Step 5: DmTopBar-Toggle.** In `apps/frontend/components/DmTopBar.vue` ein `keyword-relevance` v-model + Prop ergänzen und einen kompakten Toggle/Chip rendern, der nur erscheint, wenn `search.trim()` gesetzt **und** `aiSearch` aus ist:

```typescript
interface Props {
  search: string
  aiSearch: boolean
  keywordRelevance: boolean
  user: { displayName: string; isAdmin: boolean } | null
}
// emits: 'update:keyword-relevance': [value: boolean]
```

```vue
<button
  v-if="search.trim() && !aiSearch"
  type="button"
  class="text-[11px] font-mono px-2 py-1 rounded"
  :class="keywordRelevance ? 'bg-th-accent/15 text-th-accent' : 'text-th-muted'"
  @click="$emit('update:keyword-relevance', !keywordRelevance)"
>
  {{ t('table.sortByRelevance') }}
</button>
```

In `layouts/default.vue` den `<DmTopBar>` um `v-model:keyword-relevance="keywordRelevanceEnabled"` erweitern.

- [ ] **Step 6: table.vue — sort=relevance anwenden.** In `apps/frontend/pages/table.vue` injizieren + in `buildQuery()` nutzen:

```typescript
const keywordRelevanceEnabled = inject<Ref<boolean>>('keywordRelevanceEnabled', ref(false))
```

In `buildQuery()` nach der `q`/`semantic`-Entscheidung:

```typescript
  if (query.q && keywordRelevanceEnabled.value) {
    query.sort = 'relevance'
    query.dir = undefined
  } else {
    query.sort = toBackendSort(sortKey.value)
    query.dir = sortDirection.value
  }
```

(Wenn ein Sort-Header geklickt wird, soll `keywordRelevanceEnabled` nicht erzwungen aktiv bleiben — optional: in `toggleSort()` `keywordRelevanceEnabled.value = false` setzen, damit Header-Klick die Relevanz verlässt. Die Header sind bei `relevanceSortActive` ohnehin gesperrt; das Verlassen geschieht über den Toggle.)

- [ ] **Step 7: i18n-Keys.** In der/den Locale-Datei(en) `table.sortByRelevance` ergänzen (z. B. EN „Sort by relevance"). `table.sortedByRelevance` existiert bereits (StatusBar-Hinweis) und wird wiederverwendet.

- [ ] **Step 8: Frontend-Tests + Lint.** Run:
`cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/frontend && npx vitest run` → alle grün;
`cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/frontend && npm run lint` → sauber.

- [ ] **Step 9: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/frontend
git add -A
git commit -m "feat(search): opt-in 'Relevance'-Sort für Keyword-Suche

SortKey relevance + keywordRelevanceEnabled-Toggle (nur bei aktiver Keyword-Suche,
AI-Suche aus); relevanceSortActive erweitert → 'Sorted by relevance'-Hinweis +
Sort-Header-Lock greifen. Sendet sort=relevance an /problems.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Extensibility-Smoke-Test + Doku

**Files:**
- Modify: `apps/backend/tests/unit/test_problems_relevance.py` (Extensibility-Smoke)
- Modify: `docs/features.md` (Root)
- Modify: `CLAUDE.md` (Root, Suche-Feature-Zeile)

**Interfaces:** keine neuen.

- [ ] **Step 1: Extensibility-Smoke-Test schreiben.** Beweist, dass eine dritte Sprache nur Registry + Index braucht (kein anderer Code). In `tests/unit/test_problems_relevance.py` ergänzen:

```python
@pytest.mark.asyncio
async def test_third_language_needs_only_registry_and_index(superuser_client, monkeypatch, db_session):
    """Eine dritte Sprache (fr) wird allein durch Registry-Eintrag + funktionalen
    Index matchbar — ohne Änderung an WHERE/Ranking-Code."""
    from sqlalchemy import text as _sql_text

    import routers.problems as problems_mod
    from services.search_languages import tsvector_sql

    # Registry zur Laufzeit um French erweitern (simuliert den Registry-Eintrag).
    monkeypatch.setattr(problems_mod, "SEARCH_LANGUAGES",
                        [("en", "english"), ("de", "german"), ("fr", "french")])
    # Funktionalen Index für fr anlegen (simuliert die templated Migration).
    await db_session.execute(_sql_text(
        f"CREATE INDEX IF NOT EXISTS ix_problems_fts_fr ON problems USING gin ({tsvector_sql('fr', 'french')})"
    ))

    async def _mock_translate(text, target_lang):
        if target_lang == "fr" and "missing" in text.lower():
            return "manquant"
        return None
    monkeypatch.setattr("routers.problems.translate_query", _mock_translate)

    # Französisches Original; q=missing → fr 'manquant' stemmt 'manquante' → match.
    r = await superuser_client.post("/problems", json={
        "title": "Cadre de gouvernance manquante",
        "description": "x" * 60, "session_id": "fr-test",
    })
    pid = r.json()["id"]
    await superuser_client.patch(f"/internal/problems/{pid}/status",
                                 json={"status": "approved"}, headers=_TOKEN)

    ids = {it["id"] for it in
           (await superuser_client.get("/problems?q=missing&status_filter=approved")).json()["items"]}
    assert pid in ids, "French problem must match via registry-driven FTS without code changes"
```

- [ ] **Step 2: Test ausführen.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_relevance.py::test_third_language_needs_only_registry_and_index -q`
Expected: PASS. Falls FAIL → die WHERE/Ranking-Logik loopt die Registry nicht korrekt (echter Defekt, fixen). Danach volle Suite:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit -q` → alle grün.

- [ ] **Step 3: Doku aktualisieren.** In `docs/features.md` die Such-Sektion ergänzen: Postgres-FTS (Stemming pro Sprache, cross-lingual symmetrisch via LLM-Übersetzung + Stemming), `SEARCH_LANGUAGES`-Registry (Sprache hinzufügen = Registry + Index-Migration + Translation), opt-in `sort=relevance` (ts_rank, Keyset). In `CLAUDE.md` (Root) die Such-/Features-Zeile entsprechend kurz ergänzen.

- [ ] **Step 4: Commit (backend-Test).**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add tests/unit/test_problems_relevance.py
git commit -m "test(search): Extensibility-Smoke — dritte Sprache nur via Registry + Index

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Commit (Root-Doku).**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap
git add docs/features.md CLAUDE.md
git commit -m "docs: F2 cross-linguale FTS-Suche + sort=relevance + Sprach-Registry

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Done-Kriterium Gesamt:** `pytest tests/unit` grün (inkl. FTS-Symmetrie, Relevance-Ranking/Keyset, Extensibility-Smoke); bestehende Such-Tests grün; Frontend-Vitest + Lint grün; ruff sauber; Drift-Guard grün; `sort=relevance` end-to-end (Backend + Frontend-Toggle + StatusBar-Hinweis).

---

## Self-Review

**Spec-Coverage:** Registry + tsvector_sql → T1 ✓ · funktionale GIN-Indizes (Migration 010, immutable Snapshot) → T1 ✓ · search_de stemmt Canonical → tsvector_sql-Template T1 ✓ · Cursor q_translations-Map → T2 ✓ · Übersetzung loopt Registry → T2 ✓ · FTS ersetzt ILIKE (raw + Varianten, alle Configs) → T3 ✓ · Stemming-Symmetrie → T3-Test ✓ · sort=relevance (Σ ts_rank, Keyset, Fallback) → T4 ✓ · kein score-Feld für Relevanz → T4 (keine score-Übergabe) ✓ · Frontend SortKey+Toggle+relevanceSortActive → T5 ✓ · Extensibility-Smoke → T6 ✓ · Doku → T6 ✓ · Drift-Guard grün (kein Model-Change) → T1 Step 5 ✓.

**Platzhalter-Scan:** Keine TBD/TODO. Implementierungsabhängige Stellen sind mit konkreter Anweisung markiert: i18n-Locale-Dateipfad (T5.7 — projektspezifisch), `ProblemQuery.sort`-Typort (T5.3 — „falls Union"), `cast`/`Text`-Import-Cleanup (T3.3 — „nur wenn sonst ungenutzt").

**Typ-/Namens-Konsistenz:** `q_translations: dict[str,str]` konsistent T2 (cursor/encode/decode/peek) ↔ T3 (WHERE) ↔ T4 (rank); `q_raw` T2-Signatur ↔ T4-Branch; `_rank`-Attribut T4-Branch (`last._rank`) ↔ Row-Unpack-Map (`"relevance": "_rank"`); `tsvector_sql(lang, config)` Signatur konsistent T1↔Migration↔T3↔T4; `keywordRelevanceEnabled` konsistent layout(provide)↔table(inject)↔DmTopBar(v-model); `sort='relevance'` konsistent Frontend `toBackendSort` ↔ Backend Branch.

**Risiko-Hinweis für Ausführung:** Fragilster Teil ist der Cursor-Refactor (T2, breit über alle Sort-Branches) — Verifikation strikt über „bestehende Such-/Pagination-Tests grün". Zweiter Punkt: der funktionale-Index-Ausdruck muss textuell zum Query-Ausdruck passen (beide via `tsvector_sql`) — bei Perf-Zweifeln manuell `EXPLAIN` prüfen, ist aber für Korrektheit irrelevant.
