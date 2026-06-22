# Server-Driven Search & Pagination — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Suche, Filter, Sortierung und Aggregation laufen serverseitig; das Frontend lädt nur die benötigte Teilmenge (Keyset-Cursor), damit die App mit großen Datenmengen performant bleibt.

**Architecture:** Backend ist die einzige Pagination-Quelle: `GET /problems` mit zustandslosem Keyset-Cursor, server-seitigen Filtern/Sort und cross-lingualer Keyword- + Semantik-Suche. Der ai-service liefert dem Backend nur Query-Übersetzung (`/translate`) und Query-Embedding (neuer `/internal/embed-query`); das Backend macht die pgvector-Keyset-Query selbst (wie schon bei Solutions-Similarity). Frontend: `useProblems` wird Cursor-Store, Table = Infinite-Scroll, Graph (Phase 2) = Drill-Down, Echtzeit (Phase 3) = „N neue"-Banner.

**Tech Stack:** FastAPI + SQLAlchemy(async) + asyncpg + pgvector (Backend); Nuxt 3 + TypeScript + @tanstack/vue-virtual (Frontend); pytest (Backend), Vitest + Playwright (Frontend).

**Spec:** `docs/specs/2026-06-22-server-driven-search-pagination-design.md`

## Global Constraints

- **Keyset-Cursor, kein OFFSET.** Cursor = base64(JSON) `{ sort, key, id, emb? }`; zustandslos; Embedding (`emb`, float[1536]) reist nur im `semantic`-Modus mit.
- **Page-Size default 50, Hard-Cap 100.**
- **asyncpg-Klammer-Gotcha:** Param-Cast immer klammern: `(:emb)::vector`, nie `:emb::vector`.
- **Soft-Delete:** jede Problem-Query `deleted_at IS NULL` explizit.
- **Status-Auth:** `status != approved` erfordert Superuser (`current_superuser`).
- **`q` und `semantic` gegenseitig exklusiv.** `semantic` ignoriert `sort`.
- **JSONB SQLite-Variant:** `original_translations` ist `JSONB().with_variant(JSON(), "sqlite")` — Keyset-/Such-SQL portabel halten oder Postgres-spezifische Tests als solche markieren (In-Memory-Testdb ist SQLite).
- **Repos/Branches:** `apps/backend` + `apps/ai-service` auf `master` (direkte Commits erlaubt); `apps/frontend` auf `feature/bold-redesign`.
- **Conventional Commits** + Trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Tests pro Task grün; keine neuen Lint-Errors** (ruff backend/ai-service, eslint frontend — pre-existing Baseline erlaubt).
- **Pro Repo separat committen** (Multi-Repo).

---

# Phase 1 — Backend paginierte API + Table Infinite-Scroll

Liefert „nicht-geladene Daten finden" für Table+Suche. Graph lädt vorerst weiter vollständig über `GET /problems/all`.

---

### Task 1.1: ai-service `POST /internal/embed-query` (Text → Vektor)

**Files:**
- Modify: `apps/ai-service/app/routers/embeddings.py`
- Modify: `apps/ai-service/app/models/responses.py` (Response-Model)
- Test: `apps/ai-service/tests/unit/routers/test_embed_query.py` (create)

**Interfaces:**
- Produces: `POST /internal/embed-query` body `{ "text": str }` → `{ "embedding": float[1536] }`. Service-Token-geschützt.

- [ ] **Step 1: Write the failing test**

```python
# apps/ai-service/tests/unit/routers/test_embed_query.py
from unittest.mock import AsyncMock, patch
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from app.dependencies import get_embedding_provider, verify_service_token
from app.routers import embeddings


@pytest.fixture
def test_app() -> FastAPI:
    app = FastAPI()
    app.include_router(embeddings.router)
    return app


@pytest.fixture
def mock_provider() -> AsyncMock:
    p = AsyncMock()
    p.embed = AsyncMock(return_value=[[0.1] * 1536])
    return p


@pytest.fixture
async def client(test_app, mock_provider):
    test_app.dependency_overrides[get_embedding_provider] = lambda: mock_provider
    test_app.dependency_overrides[verify_service_token] = lambda: None
    async with AsyncClient(transport=ASGITransport(app=test_app), base_url="http://t") as ac:
        yield ac
    test_app.dependency_overrides.clear()


async def test_embed_query_returns_vector(client, mock_provider) -> None:
    r = await client.post("/embeddings/internal/embed-query", json={"text": "schlechte Daten"})
    assert r.status_code == 200
    assert r.json() == {"embedding": [0.1] * 1536}
    mock_provider.embed.assert_awaited_once_with(["schlechte Daten"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/ai-service && .venv/bin/python -m pytest tests/unit/routers/test_embed_query.py -q`
Expected: FAIL (404 / route not found).

- [ ] **Step 3: Add response model**

```python
# apps/ai-service/app/models/responses.py  (append)
class EmbedQueryResult(BaseModel):
    embedding: list[float]
```

- [ ] **Step 4: Add the endpoint**

```python
# apps/ai-service/app/routers/embeddings.py  (add import + route)
from app.models.responses import EmbedQueryResult  # add to imports

@router.post("/internal/embed-query", response_model=EmbedQueryResult,
             dependencies=[Depends(verify_service_token)])
async def embed_query(
    body: dict,
    embedding_provider: EmbeddingProvider = Depends(get_embedding_provider),
) -> EmbedQueryResult:
    """Embed a single query string for the backend's semantic search."""
    text = (body.get("text") or "").strip()
    embeddings = await embedding_provider.embed([text])
    return EmbedQueryResult(embedding=embeddings[0])
```

(Verify `Depends`, `EmbeddingProvider`, `get_embedding_provider` are imported — they already are for `reindex_all`.)

- [ ] **Step 5: Run test + ruff**

Run: `cd apps/ai-service && .venv/bin/python -m pytest tests/unit/routers/test_embed_query.py -q && .venv/bin/ruff check app/routers/embeddings.py app/models/responses.py`
Expected: PASS; no new ruff errors.

- [ ] **Step 6: Commit**

```bash
cd apps/ai-service && git add app/routers/embeddings.py app/models/responses.py tests/unit/routers/test_embed_query.py
git commit -m "$(cat <<'EOF'
feat(embeddings): /internal/embed-query für Backend-Semantik-Suche

Backend macht die pgvector-Keyset-Query selbst; es braucht nur den
Query-Vektor. Schlanker service-token-geschützter Endpoint.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.2: Backend Cursor-Util (encode/decode/validate)

**Files:**
- Create: `apps/backend/services/cursor.py`
- Test: `apps/backend/tests/unit/test_cursor.py` (create)

**Interfaces:**
- Produces:
  - `encode_cursor(sort: str, key, id: str, emb: list[float] | None = None) -> str` (base64 url-safe of JSON)
  - `decode_cursor(cursor: str, expected_sort: str) -> dict` → `{"sort","key","id","emb"?}`; raises `ValueError` on malformed or sort-mismatch.

- [ ] **Step 1: Write the failing test**

```python
# apps/backend/tests/unit/test_cursor.py
import pytest
from services.cursor import encode_cursor, decode_cursor


def test_roundtrip_created():
    c = encode_cursor("created", "2026-01-01T00:00:00+00:00", "abc")
    out = decode_cursor(c, "created")
    assert out["sort"] == "created"
    assert out["key"] == "2026-01-01T00:00:00+00:00"
    assert out["id"] == "abc"
    assert out.get("emb") is None


def test_roundtrip_semantic_with_embedding():
    emb = [0.5] * 1536
    c = encode_cursor("semantic", 0.42, "xyz", emb)
    out = decode_cursor(c, "semantic")
    assert out["key"] == 0.42
    assert out["emb"] == emb


def test_sort_mismatch_raises():
    c = encode_cursor("created", "k", "id")
    with pytest.raises(ValueError):
        decode_cursor(c, "votes")


def test_malformed_raises():
    with pytest.raises(ValueError):
        decode_cursor("not-base64!!", "created")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && .venv/bin/python -m pytest tests/unit/test_cursor.py -q`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement**

```python
# apps/backend/services/cursor.py
"""Stateless keyset-pagination cursor: base64(url-safe) of a compact JSON object.

Format: {"s": sort, "k": key, "i": id, "e": emb?}
"""
import base64
import json
from typing import Any


def encode_cursor(sort: str, key: Any, id: str, emb: list[float] | None = None) -> str:
    payload: dict[str, Any] = {"s": sort, "k": key, "i": id}
    if emb is not None:
        payload["e"] = emb
    raw = json.dumps(payload, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode()


def decode_cursor(cursor: str, expected_sort: str) -> dict[str, Any]:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode())
        payload = json.loads(raw)
    except Exception as exc:
        raise ValueError(f"malformed cursor: {exc}") from exc
    if payload.get("s") != expected_sort:
        raise ValueError(f"cursor sort {payload.get('s')!r} != expected {expected_sort!r}")
    return {"sort": payload["s"], "key": payload["k"], "id": payload["i"], "emb": payload.get("e")}
```

- [ ] **Step 4: Run test + ruff**

Run: `cd apps/backend && .venv/bin/python -m pytest tests/unit/test_cursor.py -q && .venv/bin/ruff check services/cursor.py`
Expected: PASS; no new ruff errors.

- [ ] **Step 5: Commit**

```bash
cd apps/backend && git add services/cursor.py tests/unit/test_cursor.py
git commit -m "$(cat <<'EOF'
feat(pagination): zustandsloser Keyset-Cursor (encode/decode/validate)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.3: Backend `GET /problems` — Keyset (sort=created) + total

Erster end-to-end Schnitt: nur Default-Sort, kein Filter/keine Suche. Ersetzt NICHT sofort `list_problems` — der alte Endpoint bleibt bis Task 1.8 als `/all` erhalten; dieser Task baut den neuen paginierten Handler unter `GET /problems`.

**Files:**
- Modify: `apps/backend/routers/problems.py` (neuer `list_problems`-Handler + Response-Model `ProblemPage`)
- Test: `apps/backend/tests/unit/test_problems_pagination.py` (create)

**Interfaces:**
- Produces: `GET /problems?limit=&cursor=&sort=created&status=approved`
  → `{ "items": ProblemRead[], "next_cursor": str|null, "total": int }`
- Consumes: `encode_cursor`/`decode_cursor` (Task 1.2).

- [ ] **Step 1: Write the failing test** (seed 3 approved problems, page size 2)

```python
# apps/backend/tests/unit/test_problems_pagination.py
import pytest

# Helper assumes conftest fixtures: superuser_client (auth) + a way to create problems.
# Use the existing POST /problems path via auth_client to seed (see tests/unit/test_problems.py
# for the create payload shape).

async def _create(client, title, description="x" * 60):
    r = await client.post("/problems", json={"title": title, "description": description})
    assert r.status_code == 201, r.text
    return r.json()["id"]


async def test_first_page_returns_limit_items_and_total(auth_client, superuser_client):
    for i in range(3):
        await _create(auth_client, f"Pagination probe number {i}")
    # approve them so default status=approved sees them (use existing admin status route)
    # ... (set status approved via internal/admin path used elsewhere in tests)
    r = await superuser_client.get("/problems?limit=2&sort=created&status=approved")
    body = r.json()
    assert len(body["items"]) == 2
    assert body["total"] >= 3
    assert body["next_cursor"] is not None


async def test_second_page_continues_without_overlap(superuser_client):
    first = (await superuser_client.get("/problems?limit=2&sort=created&status=approved")).json()
    ids1 = {p["id"] for p in first["items"]}
    cur = first["next_cursor"]
    second = (await superuser_client.get(f"/problems?limit=2&sort=created&status=approved&cursor={cur}")).json()
    ids2 = {p["id"] for p in second["items"]}
    assert ids1.isdisjoint(ids2)
```

> NOTE for implementer: align the seed/approve steps with the existing problem-creation + approval helpers in `tests/unit/test_problems.py` (this codebase seeds via the API + an internal status update). Keep the assertions above.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && .venv/bin/python -m pytest tests/unit/test_problems_pagination.py -q`
Expected: FAIL (response has no `items`/`next_cursor`/`total`).

- [ ] **Step 3: Implement the paginated handler**

Replace the body of `list_problems` (`routers/problems.py` ~166). Keep the `ProblemRead` mapping via the existing `_to_read` + `_load_junctions`.

```python
from services.cursor import encode_cursor, decode_cursor  # add import

class ProblemPage(BaseModel):
    items: list[ProblemRead]
    next_cursor: str | None
    total: int

@router.get("", response_model=ProblemPage)
async def list_problems(
    limit: int = 50,
    cursor: str | None = None,
    sort: str = "created",
    status_filter: str = "approved",
    session: AsyncSession = Depends(get_async_session),
    current_user: Optional[User] = Depends(current_optional_user),
) -> ProblemPage:
    limit = max(1, min(limit, 100))
    if status_filter != "approved":
        if not (current_user and current_user.is_superuser):
            raise HTTPException(status_code=403, detail="Not allowed")

    base_where = [Problem.deleted_at.is_(None), Problem.status == status_filter]

    # total (same filters, no keyset/limit)
    total = (await session.execute(
        select(func.count()).select_from(Problem).where(*base_where)
    )).scalar_one()

    # keyset for sort=created: (created_at, id) DESC
    q = select(Problem).where(*base_where)
    if cursor:
        cur = decode_cursor(cursor, sort)
        from datetime import datetime
        last_dt = datetime.fromisoformat(cur["key"])
        q = q.where(tuple_(Problem.created_at, Problem.id) < tuple_(last_dt, uuid.UUID(cur["id"])))
    q = q.order_by(Problem.created_at.desc(), Problem.id.desc()).limit(limit + 1)

    rows = (await session.execute(q)).scalars().all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = None
    if has_more and rows:
        last = rows[-1]
        next_cursor = encode_cursor("created", last.created_at.isoformat(), str(last.id))

    tags_map, regions_map = await _load_junctions(session, [p.id for p in rows])
    items = [_to_read(p, tags_map.get(p.id, []), regions_map.get(p.id, [])) for p in rows]
    return ProblemPage(items=items, next_cursor=next_cursor, total=total)
```

Add `from sqlalchemy import tuple_, func` to imports if missing.

> SQLite note: `tuple_(a, b) < tuple_(x, y)` compiles to row-value comparison. SQLite supports row-value comparisons since 3.15 — verify the in-memory test DB version; if it errors, fall back to the expanded form `(a < x) OR (a = x AND b < y)` (document the choice).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/backend && .venv/bin/python -m pytest tests/unit/test_problems_pagination.py tests/unit -q`
Expected: PASS; full suite stays green (other tests that called `/problems` expecting a bare list must be updated to read `.items` — fix them in this task).

- [ ] **Step 5: ruff + commit**

```bash
cd apps/backend && .venv/bin/ruff check routers/problems.py services/cursor.py
git add routers/problems.py tests/
git commit -m "$(cat <<'EOF'
feat(problems): GET /problems Keyset-Pagination (sort=created) + total

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.4: Backend — weitere Sort-Modi (votes, title, solutions)

**Files:**
- Modify: `apps/backend/routers/problems.py`
- Test: `apps/backend/tests/unit/test_problems_pagination.py` (extend)

**Interfaces:**
- Produces: `sort=votes|title|solutions` an `GET /problems`. Keyset pro Modus (siehe Spec-Tabelle).

- [ ] **Step 1: Write failing tests** — one per sort mode asserting ordering + no-overlap across two pages.

```python
async def test_sort_votes_desc_keyset(superuser_client):
    p = (await superuser_client.get("/problems?limit=2&sort=votes&status=approved")).json()
    scores = [it["voteScore"] for it in p["items"]]
    assert scores == sorted(scores, reverse=True)
    if p["next_cursor"]:
        p2 = (await superuser_client.get(f"/problems?limit=2&sort=votes&status=approved&cursor={p['next_cursor']}")).json()
        assert {x["id"] for x in p["items"]}.isdisjoint({x["id"] for x in p2["items"]})


async def test_sort_title_asc_keyset(superuser_client):
    p = (await superuser_client.get("/problems?limit=2&sort=title&status=approved")).json()
    titles = [it["title"] for it in p["items"]]
    assert titles == sorted(titles)


async def test_sort_solutions_desc(superuser_client):
    p = (await superuser_client.get("/problems?limit=5&sort=solutions&status=approved")).json()
    # solution-less problems sort to 0; just assert it returns + paginates
    assert "items" in p and "next_cursor" in p
```

- [ ] **Step 2: Run to verify fail** — `pytest tests/unit/test_problems_pagination.py -q` → FAIL (unsupported sort).

- [ ] **Step 3: Implement per-mode keyset.** Factor a helper `_apply_sort_and_keyset(q, sort, cursor)` returning `(q, make_next_cursor_fn)`:

```python
def _apply_sort_and_keyset(q, sort, cursor, limit):
    if sort == "created":
        # (as Task 1.3)
        ...
    elif sort == "votes":
        if cursor:
            cur = decode_cursor(cursor, "votes")
            q = q.where(tuple_(Problem.vote_score, Problem.id) < tuple_(int(cur["key"]), uuid.UUID(cur["id"])))
        q = q.order_by(Problem.vote_score.desc(), Problem.id.desc())
        make_next = lambda last: encode_cursor("votes", last.vote_score, str(last.id))
    elif sort == "title":
        if cursor:
            cur = decode_cursor(cursor, "title")
            q = q.where(tuple_(Problem.title, Problem.id) > tuple_(cur["key"], uuid.UUID(cur["id"])))
        q = q.order_by(Problem.title.asc(), Problem.id.asc())
        make_next = lambda last: encode_cursor("title", last.title, str(last.id))
    elif sort == "solutions":
        # LEFT JOIN solution counts; order by COALESCE(count,0) DESC, id DESC
        ...  # see below
    else:
        raise HTTPException(422, f"unknown sort {sort}")
    return q, make_next
```

For `solutions`, build a subquery:
```python
from models.solution import Solution
sol_count = (
    select(Solution.problem_id, func.count().label("c"))
    .where(Solution.status == "approved", Solution.deleted_at.is_(None))
    .group_by(Solution.problem_id).subquery()
)
# join + COALESCE(sol_count.c, 0); keyset over (coalesce, id) DESC.
```
Refactor `list_problems` to call `_apply_sort_and_keyset`. The `make_next` closure builds the cursor from the last row (for `solutions`, also select the coalesced count onto the row so the cursor key is available).

- [ ] **Step 4: Run to verify pass** — `pytest tests/unit -q` green.

- [ ] **Step 5: ruff + commit** — `feat(problems): Sort-Modi votes/title/solutions mit Keyset`.

---

### Task 1.5: Backend — Filter (tags-subtree, regions, user, company)

**Files:**
- Modify: `apps/backend/routers/problems.py`
- Test: `apps/backend/tests/unit/test_problems_filters.py` (create)

**Interfaces:**
- Produces: query params `tags`, `regions`, `user`, `company` on `GET /problems`, AND-combined; applied to BOTH the page query and the `total` count.

- [ ] **Step 1: Write failing tests** — seed problems with tags/regions/user, assert filtered results + that `total` matches the filtered count.

```python
async def test_tag_filter_subtree(superuser_client, ...):
    # create a parent structural tag + child, assign child to one problem,
    # filter by parent → that problem is returned (subtree expansion)
    ...
async def test_user_filter(superuser_client, ...): ...
async def test_total_reflects_filters(superuser_client, ...):
    r = (await superuser_client.get("/problems?tags=<id>&status=approved")).json()
    assert r["total"] == len(_collect_all_pages(r))  # sum across pages == total
```

- [ ] **Step 2: Run to verify fail.**

- [ ] **Step 3: Implement filters** as a shared `_apply_filters(q, params)` used by BOTH the page query and the count query:

```python
def _subtree_tag_ids(session, tag_ids) -> set[str]:
    # recursively expand each tag to its descendants via tags.parent_id
    ...
# tags: AND over each requested tag's subtree EXISTS in problem_tag
# regions: EXISTS problem_region WHERE region_id = ANY(regions)  (OR within)
# user: Problem.user_id == user
# company: JOIN users u ON Problem.user_id == u.id WHERE u.company == company
```

Build `base_where`/joins once, reuse for `total` and the page. Parse comma-separated `tags=a,b`, `regions=x,y`.

- [ ] **Step 4: Run to verify pass** — `pytest tests/unit -q` green.

- [ ] **Step 5: ruff + commit** — `feat(problems): server-seitige Filter (tags-subtree, regions, user, company)`.

---

### Task 1.6: Backend — Keyword-Suche `q` (cross-lingual, 3 Quellen)

**Files:**
- Modify: `apps/backend/routers/problems.py`
- Modify: `apps/backend/services/ai_client.py` (add `translate_query_to_en`)
- Test: `apps/backend/tests/unit/test_problems_search.py` (create)

**Interfaces:**
- Consumes: ai-service `POST /translate` (`{text, target_lang:"en"}` → `{translated}`).
- Produces: `&q=<keyword>` on `GET /problems`. When `q` set and `cursor` null, backend fetches EN translation once and embeds it in `next_cursor` (key `qen`). Keyword OR over: raw vs `original_translations::text`, raw vs title/description, EN-translated vs title/description.

- [ ] **Step 1: Write failing test** (mock the translation call):

```python
async def test_q_matches_original_translations_raw(superuser_client, ...):
    # problem English canonical "Poor data quality", original_translations.de="Schlechte..."
    r = (await superuser_client.get("/problems?q=schlecht&status=approved")).json()
    assert any("Poor data" in it["title"] for it in r["items"])

async def test_q_cross_lingual_via_translation(superuser_client, monkeypatch, ...):
    # problem English-only "Poor data quality" (no DE original)
    # mock translate_query_to_en("schlecht") -> "poor"
    r = (await superuser_client.get("/problems?q=schlecht&status=approved")).json()
    assert any("Poor data" in it["title"] for it in r["items"])
```

- [ ] **Step 2: Run to verify fail.**

- [ ] **Step 3: Add `translate_query_to_en` to `services/ai_client.py`:**

```python
async def translate_query_to_en(text: str) -> str | None:
    """Best-effort EN translation of a search query (cross-lingual keyword source 3)."""
    try:
        client = get_ai_client()
        r = await client.post("/translate", json={"text": text, "target_lang": "en"})
        r.raise_for_status()
        return r.json().get("translated")
    except Exception as exc:
        logger.warning("translate_query_failed", error=str(exc))
        return None
```

- [ ] **Step 4: Implement keyword OR-clause in `list_problems`.** When `q` present:
  - resolve `q_en`: if `cursor` → from decoded cursor key `qen`; else `await translate_query_to_en(q)` and store it in every produced cursor.
  - `WHERE ( title ILIKE :p OR description ILIKE :p OR original_translations::text ILIKE :p` (raw `%q%`) `OR title ILIKE :pen OR description ILIKE :pen )` (EN `%q_en%`, only if `q_en`).
  - Use SQLAlchemy `.ilike()` (binds params; column cast `cast(Problem.original_translations, Text)` — safe, column-side cast). The `q_en` travels in the cursor JSON (extend `encode_cursor` payload or carry as part of `key` dict — extend cursor to allow an extra `q` field). Simplest: add optional `q_en` param to `encode_cursor`/`decode_cursor`.

- [ ] **Step 5: Run to verify pass** + ruff.

- [ ] **Step 6: Commit** — `feat(problems): cross-linguale Keyword-Suche (q, 3 Quellen + Query-Übersetzung)`.

---

### Task 1.7: Backend — Semantik-Suche `semantic` (pgvector Keyset)

**Files:**
- Modify: `apps/backend/routers/problems.py`
- Modify: `apps/backend/services/ai_client.py` (add `embed_query`)
- Test: `apps/backend/tests/unit/test_problems_semantic.py` (create — mark Postgres-only if pgvector unavailable in SQLite test DB)

**Interfaces:**
- Consumes: ai-service `POST /internal/embed-query` (Task 1.1) → `{embedding}`.
- Produces: `&semantic=<text>` on `GET /problems`. Distance-ordered keyset; embedding carried in cursor `emb`.

- [ ] **Step 1: Write failing test.** Since the in-memory SQLite test DB has no pgvector, this is a **Postgres contract test** (mark with skip if `DATABASE_URL` is sqlite) OR a focused test mocking the embedding call + asserting the SQL is built (distance order + keyset). Minimum: assert that `semantic=` ignores `sort` and that the embedding is fetched once and reused from cursor on page 2.

- [ ] **Step 2: Run to verify fail.**

- [ ] **Step 3: Add `embed_query` to `ai_client.py`:**

```python
async def embed_query(text: str) -> list[float] | None:
    try:
        client = get_ai_client()
        r = await client.post("/internal/embed-query", json={"text": text})
        r.raise_for_status()
        return r.json()["embedding"]
    except Exception as exc:
        logger.warning("embed_query_failed", error=str(exc))
        return None
```
(Service-token header: `get_ai_client()` must include `X-Service-Token` — verify; the internal route requires it.)

- [ ] **Step 4: Implement semantic branch.** When `semantic` set:
  - resolve `emb`: from cursor `emb` if present, else `await embed_query(semantic)`; if `None` → 503-ish fallback (return empty page with `total=0`, log).
  - `ORDER BY embedding <=> (:emb)::vector ASC, id ASC` (parenthesized cast). Select the distance as a column: `(Problem.embedding.cosine_distance(bindparam("emb"))).label("dist")` — pgvector SQLAlchemy supports `.cosine_distance`. Keyset: `WHERE (dist, id) > (:last_dist, :last_id)` — repeat the distance expression in WHERE.
  - `total` = count of approved with `embedding IS NOT NULL` under the same filters.
  - next_cursor: `encode_cursor("semantic", last_dist, str(last.id), emb)`.

- [ ] **Step 5: Run to verify pass** (focused/mocked + Postgres contract if available) + ruff.

- [ ] **Step 6: Commit** — `feat(problems): semantische Suche mit Distanz-Keyset (Embedding im Cursor)`.

---

### Task 1.8: Backend — `GET /problems/all` (Übergangs-Endpoint)

**Files:**
- Modify: `apps/backend/routers/problems.py`
- Test: `apps/backend/tests/unit/test_problems.py` (adjust existing list tests if needed)

**Interfaces:**
- Produces: `GET /problems/all?status=approved` → `list[ProblemRead]` (no pagination, hard-cap e.g. 5000). Used by the graph during Phase 1; removed in Phase 2.

- [ ] **Step 1: Write failing test** — `GET /problems/all` returns a bare list of all approved.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Add route** (the pre-pagination `list_problems` body): select all approved (`LIMIT 5000`), map via `_to_read`. Status-auth like the paginated one.
- [ ] **Step 4: Run to verify pass** + ruff.
- [ ] **Step 5: Commit** — `feat(problems): GET /problems/all Übergangs-Endpoint für Graph (Phase 1)`.

---

### Task 1.9: Frontend — `useProblems` Cursor-Store

**Files:**
- Modify: `apps/frontend/composables/data/real/realProblems.ts`
- Modify: `apps/frontend/composables/data/types.ts` (add `ProblemQuery`, `ProblemPage`)
- Test: `apps/frontend/tests/composables/useProblemsPagination.spec.ts` (create — test the pure accumulation/race logic; mock backendFetch)

**Interfaces:**
- Produces (on the data layer):
  - `loadFirstPage(query: ProblemQuery): Promise<void>` — resets `problems`, sets `total`/`nextCursor`.
  - `loadNextPage(): Promise<void>` — appends; no-op if `!hasMore` or `loading`.
  - refs: `problems`, `total`, `nextCursor`, `loading`, `hasMore`.
  - `fetchAllProblems(): Promise<void>` — calls `GET /problems/all` into `problems` (graph, Phase 1).
- `ProblemQuery = { sort?, q?, semantic?, tags?, regions?, user?, company?, status? }`.

- [ ] **Step 1: Write failing test** for pure logic: two sequential `loadNextPage` accumulate; `loadFirstPage` resets; a stale `loadFirstPage` (older requestVersion) does not overwrite a newer result.

```ts
// mock backendFetch to return {items, next_cursor, total}; assert accumulation + race-guard
```

- [ ] **Step 2: Run to verify fail** — `npx vitest run tests/composables/useProblemsPagination.spec.ts`.

- [ ] **Step 3: Implement** the cursor store in `realProblems.ts`: module-level `problems`, `total`, `nextCursor`, `loading`, `hasMore`; `requestVersion` monotone counter (race-guard like `useSemanticSearch`); build query string from `ProblemQuery`; `loadFirstPage` resets array + version, `loadNextPage` appends using `nextCursor`. Keep `fetchProblemById`, `createProblem`, etc. Add `fetchAllProblems` hitting `/problems/all`.

- [ ] **Step 4: Run to verify pass** + eslint.

- [ ] **Step 5: Commit** — `feat(problems): useProblems als Cursor-Store (loadFirstPage/loadNextPage)`.

---

### Task 1.10: Frontend — `table.vue` Infinite-Scroll + Server-Suche/Filter/Sort

**Files:**
- Modify: `apps/frontend/pages/table.vue`
- Delete (logic): client-side `filteredProblems`/`matchesQuery`/`adminSearchIds` as the filter source
- Remove: `apps/frontend/utils/problemSearch.ts` usage in table (keep file if index.vue still uses it pre-Phase-2; remove when unused)
- Test: covered by E2E (Task 3.4) + the composable test (1.9). No page-mount test (project has none).

**Interfaces:**
- Consumes: `useProblems` cursor store (1.9).

- [ ] **Step 1: Wire filter/sort/search refs → `loadFirstPage`.** A single `watch` on `[searchQuery, aiSearchEnabled, sortKey, sortDirection, tagFilterIds, userFilterIds, companyFilters]` (debounce search) → builds `ProblemQuery` (`q` vs `semantic` based on the AI-search toggle) → `loadFirstPage(query)`.
- [ ] **Step 2: Virtualizer → server pages.** `count` = `total`; render loaded `problems`; when the virtualizer reaches near the end (last index within ~10 of loaded length and `hasMore`), call `loadNextPage()`.
- [ ] **Step 3: „N von M".** `problems.length` (geladen) `of` `total`.
- [ ] **Step 4: Remove** the client `filteredProblems` computed, `matchesQuery`, `adminSearchIds`, and the `localizedTitles`-as-search watcher. Title-column display: prefer `problem.originalTranslations?.[locale]?.title ?? problem.title` (no per-row `/translate` call).
- [ ] **Step 5: Verify** `npx vitest run` green (existing tests unaffected or updated), `npx eslint pages/table.vue` clean.
- [ ] **Step 6: Commit** — `feat(table): server-driven Infinite-Scroll + Suche/Filter/Sort`.

---

### Task 1.11: Frontend — `admin/moderation.vue` server-side status

**Files:**
- Modify: `apps/frontend/pages/admin/moderation.vue`

- [ ] **Step 1:** Replace the client-side `problems.value.filter(status===...)` queues with three cursor loads: `loadFirstPage({status:'pending'})` etc. (or a dedicated lightweight fetch per status using the paginated endpoint). Keep the existing moderation actions.
- [ ] **Step 2:** Verify eslint + a manual smoke (no unit harness).
- [ ] **Step 3: Commit** — `feat(moderation): Problem-Queues server-seitig via status-Filter`.

---

### Task 1.12: Frontend — Graph (`index.vue`) nutzt `/problems/all` (Phase-1-Übergang)

**Files:**
- Modify: `apps/frontend/pages/index.vue`

- [ ] **Step 1:** Change `index.vue`'s `fetchProblems()` call to `fetchAllProblems()` so the graph keeps its complete-set behavior during Phase 1 (Table no longer loads all). Leave the rest of index.vue/graph untouched (Phase 2 refactors it).
- [ ] **Step 2:** Verify graph still renders all nodes/counts; `npx vitest run` green; eslint clean.
- [ ] **Step 3: Commit** — `feat(graph): Übergang auf /problems/all bis Drill-Down (Phase 1)`.

**Phase 1 Done-Kriterium:** Table paginiert server-seitig, Suche findet nicht-geladene Probleme, Graph unverändert korrekt. Backend-Suite grün, Frontend-Suite grün, ai-service-Suite grün.

---

# Phase 2 — Graph-Drill-Down

Eliminiert die „lade alles"-Abhängigkeit des Graphen.

---

### Task 2.1: Backend — `GET /problems/cluster-summary`

**Files:**
- Modify: `apps/backend/routers/problems.py`
- Test: `apps/backend/tests/unit/test_cluster_summary.py` (create)

**Interfaces:**
- Produces: `GET /problems/cluster-summary` → `{ max_vote_score: int, clusters: [{tag_id, problem_count}], unclustered_count: int }`.

- [ ] **Step 1: Write failing test** — seed problems with/without structural tags; assert `max_vote_score`, per-cluster subtree counts, `unclustered_count`.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Implement.** `max_vote_score = SELECT MAX(vote_score) WHERE approved`. For each structural tag (level < 10): count approved problems whose tags fall in its subtree (reuse `_subtree_tag_ids`). `unclustered_count` = approved with no structural tag. Single endpoint, no pagination.
- [ ] **Step 4: Run to verify pass** + ruff.
- [ ] **Step 5: Commit** — `feat(problems): GET /problems/cluster-summary (Graph-Aggregat)`.

---

### Task 2.2: Frontend — `ProblemGraph.vue` akzeptiert Aggregat-Props

**Files:**
- Modify: `apps/frontend/components/ProblemGraph.vue`

**Interfaces:**
- Consumes: new props `maxVoteScore: number`, `clusterCounts: Map<string,number>`, `unclusteredCount: number`.

- [ ] **Step 1:** Add the three props. Replace `Math.max(...props.problems.map(p=>p.voteScore))` (line ~262) with `props.maxVoteScore`; replace cluster count computation (line ~286) with `props.clusterCounts.get(tagId)`; replace unclustered detection count (line ~77/1085) with `props.unclusteredCount`. The `props.problems` array now holds only the drilled-in cluster's problems (or empty on overview).
- [ ] **Step 2:** Verify `npx vitest run` (graph has no unit test; ensure no type errors) + eslint clean.
- [ ] **Step 3: Commit** — `refactor(graph): Counts/max-score als Props statt aus Voll-Array`.

---

### Task 2.3: Frontend — `index.vue` Drill-Down + cluster-summary

**Files:**
- Modify: `apps/frontend/pages/index.vue`
- Modify: `apps/frontend/composables/data/real/realProblems.ts` (add `fetchClusterSummary`)

**Interfaces:**
- Produces: `fetchClusterSummary(): Promise<ClusterSummary>`.

- [ ] **Step 1:** On mount, load `cluster-summary` (not all problems). Render overview: cluster nodes + counts + max-score via props (2.2); `props.problems = []` on overview.
- [ ] **Step 2:** On cluster click/zoom → `loadFirstPage({tags:[clusterTagId]})` → pass loaded problems to the graph as the drilled-in set (Infinite-Scroll within a large cluster via `loadNextPage`).
- [ ] **Step 3:** `isEmpty` → `clusterSummary.clusters.length === 0 && unclustered === 0`. Remove client `filteredProblems` (search now server-side via the same `loadFirstPage`).
- [ ] **Step 4:** Verify graph renders overview + drill-down; `npx vitest run` green; eslint clean.
- [ ] **Step 5: Commit** — `feat(graph): Drill-Down — Übersicht aus cluster-summary, Nodes lazy pro Cluster`.

---

### Task 2.4: Remove `/problems/all` + Voll-Array-Reste

**Files:**
- Modify: `apps/backend/routers/problems.py` (remove `/all`)
- Modify: `apps/frontend/composables/data/real/realProblems.ts` (remove `fetchAllProblems`)
- Modify: `apps/frontend/composables/data/real/realTags.ts` (`problemTags` from drilled set, not full array)

- [ ] **Step 1:** Confirm no caller uses `/problems/all` or `fetchAllProblems` (`grep`). Remove both. Adjust `problemTags` derivation to the currently loaded (drilled) problems.
- [ ] **Step 2:** Verify both suites green; eslint + ruff clean.
- [ ] **Step 3: Commit** (two repos) — `refactor: lade-alles-Pfad entfernt (Drill-Down vollständig)`.

**Phase 2 Done-Kriterium:** Graph lädt nie mehr alle Probleme; Übersicht + Counts korrekt aus Aggregat; Drill-Down lazy. Beide Suiten grün.

---

# Phase 3 — Echtzeit-Banner + Politur

---

### Task 3.1: Frontend — „N neue"-Banner-Komponente

**Files:**
- Create: `apps/frontend/components/NewItemsBanner.vue`
- Modify: `apps/frontend/i18n/locales/{en,de}.json` (key `realtime.newProblems`)
- Test: `apps/frontend/tests/components/NewItemsBanner.spec.ts` (create)

**Interfaces:**
- Produces: `<NewItemsBanner :count="n" @reload="..." />` — hidden when `count===0`.

- [ ] **Step 1: Write failing test** — renders count when >0, hidden at 0, emits `reload` on click.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Implement** the small presentational component + i18n keys (`"{count} neue Probleme — anzeigen"` / `"{count} new problems — show"`).
- [ ] **Step 4: Run to verify pass** + eslint.
- [ ] **Step 5: Commit** — `feat(realtime): NewItemsBanner-Komponente`.

---

### Task 3.2: Frontend — WS-Reconciliation an Pagination

**Files:**
- Modify: `apps/frontend/pages/table.vue` + `apps/frontend/pages/index.vue`
- Modify: `apps/frontend/composables/useBackendRealtime.ts` (handlers only if needed)

- [ ] **Step 1:** `newSinceLoad` ref; `onProblemCreated` → `newSinceLoad++` (no re-fetch). Render `<NewItemsBanner :count="newSinceLoad" @reload="loadFirstPage(currentQuery); newSinceLoad=0" />`.
- [ ] **Step 2:** `vote/update/delete`: keep in-place find-by-id in the loaded `problems`; ignore if not loaded (no full re-fetch).
- [ ] **Step 3:** Verify `npx vitest run` green; eslint clean. Manual: create a problem in another tab → banner appears.
- [ ] **Step 4: Commit** — `feat(realtime): N-neue-Banner statt Voll-Re-Fetch; in-place Updates`.

---

### Task 3.3: Frontend — `clustering.completed` Refresh

**Files:**
- Modify: `apps/frontend/pages/index.vue`

- [ ] **Step 1:** `onClusteringCompleted` → reload `cluster-summary` (+ current drill-down list if open) instead of `fetchProblems()`+`fetchTags()` full reload.
- [ ] **Step 2:** Verify + commit — `feat(realtime): clustering.completed aktualisiert cluster-summary`.

---

### Task 3.4: E2E (Playwright)

**Files:**
- Create: `apps/frontend/tests/e2e/pagination.spec.ts`

- [ ] **Step 1: Write E2E specs:**
  - Scrollen lädt nächste Seite (Items wachsen, `total` stabil).
  - Filter-/Sortwechsel resettet auf Top (erste Items ändern sich, Scroll oben).
  - Server-Suche: DE-Substring eines deutsch eingereichten Problems findet es; cross-lingual eines englisch eingereichten via Semantik-Toggle.
  - „N neue"-Banner erscheint nach WS-`problem.created` und lädt von oben.
  Use `waitForLoadState('domcontentloaded')` (NICHT `networkidle` — WS bleibt offen, Gotcha).
- [ ] **Step 2:** Run `npm run test:e2e` against `int.decisionmap.ai` (needs creds).
- [ ] **Step 3: Commit** — `test(e2e): Pagination/Infinite-Scroll/Suche/Banner`.

**Phase 3 Done-Kriterium:** Live-Landkarte unter Pagination; Banner + in-place Updates; E2E grün.

---

## Self-Review

**Spec coverage** (jede Spec-Sektion → Task):
- Keyset-Cursor → 1.2 ✓ · `GET /problems` Contract → 1.3–1.7 ✓ · Filter → 1.5 ✓ · Sort-Modi → 1.4 ✓ · cross-linguale Keyword-Suche (3 Quellen) → 1.6 ✓ · Semantik-Keyset + Embedding-im-Cursor → 1.7 ✓ · Query-Normalisierung geteilt → 1.6/1.7 (translate + embed beim ersten Call) ✓ · `total` → 1.3 ✓ · `/problems/all` Übergang → 1.8, entfernt 2.4 ✓ · `cluster-summary` → 2.1 ✓ · `useProblems` Cursor-Store → 1.9 ✓ · Table Infinite-Scroll → 1.10 ✓ · moderation server-status → 1.11 ✓ · Graph Drill-Down → 2.2/2.3 ✓ · Voll-Array-Reste (`maxVoteScore`/counts/`problemTags`) → 2.2/2.4 ✓ · Echtzeit-Banner → 3.1/3.2 ✓ · clustering.completed → 3.3 ✓ · Tests → je Task + 3.4 E2E ✓.
- **ai-service `embed-query`** (von Spec als „ggf. ergänzen" markiert) → Task 1.1 ✓.

**Offene Verifikationen, die Implementer-Tasks früh klären:**
- 1.3: SQLite row-value-Vergleich (`tuple_`) — sonst expandierte OR-Form.
- 1.7: pgvector im SQLite-Testdb fehlt → Postgres-Contract-Test oder mock-basiert.
- 1.6: `get_ai_client()` muss `X-Service-Token` für `/internal/embed-query` setzen (1.7) — `/translate` ist öffentlich.

**Type consistency:** `ProblemPage{items,next_cursor,total}` (Backend) ↔ `ProblemQuery`/Store-Refs (Frontend 1.9) ↔ `loadFirstPage/loadNextPage` (1.9→1.10/2.3/3.2) konsistent. Cursor-Felder `{s,k,i,e}` intern, API-seitig opak.

**Annahmen:** Page-Size 50/Cap 100; `tags` AND / `regions` OR; Drill-Down Infinite-Scroll bei großen Clustern.
