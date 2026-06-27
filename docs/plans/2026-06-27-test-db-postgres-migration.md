# Test-DB-Umstellung SQLite → Postgres (testcontainers) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Backend-Unit-Tests laufen gegen ein ephemeres echtes PostgreSQL+pgvector (via `testcontainers`) statt In-Memory-SQLite — Schema via Alembic, System-Seeds geladen, Drift-Guard via `alembic check`, Transaction-Rollback-Isolation. Gesamte Suite grün.

**Architecture:** Eine session-scoped Fixture startet `pgvector/pgvector:pg16`, baut das Schema mit `alembic upgrade head` auf, lädt die System-Seeds (`001_regions.sql`, `002_tags.sql`) + einen Baseline-Test-User (committet). Jeder Test läuft in einer Connection-gebundenen Transaktion mit Savepoint, die danach zurückgerollt wird; die FastAPI-App nutzt via `get_async_session`-Override dieselbe Transaktion. Kein SQLite mehr.

**Tech Stack:** pytest + pytest-asyncio, SQLAlchemy(async)+asyncpg, Alembic, testcontainers[postgres], FastAPI (ASGITransport), pgvector.

**Spec:** `docs/specs/2026-06-27-test-db-postgres-migration-design.md`

## Global Constraints

- **Repo/Branch:** `apps/backend` auf `master` (direkte Commits erlaubt). Pro Repo committen.
- **Conventional Commits** + Trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Kein SQLite** mehr im Test-Code nach Abschluss; **kein** `Base.metadata.create_all` für Tests (nur Alembic).
- **System-Seeds = nur** `database/seeds/001_regions.sql` + `002_tags.sql`. **Keine** Demo-Seeds in Tests.
- **Done:** gesamte Unit-Suite grün gegen Postgres; vorher `skipif`-on-sqlite-Tests laufen und sind grün; Contract-Suite unverändert; ruff sauber.
- **Docker** muss beim Testen laufen (lokal + Jenkins-`test`-Stage).
- Befehl bleibt `make api-test` / `.venv/bin/pytest tests/unit`.

---

### Task 1: Dependency + Alembic-URL-Override

**Files:**
- Modify: `apps/backend/pyproject.toml` (dev/test-Dependency `testcontainers[postgres]`)
- Modify: `apps/backend/alembic/env.py` (Test-DB-URL aus Env bevorzugen)

**Interfaces:**
- Produces: Alembic nutzt `os.environ["DATABASE_URL"]`, wenn gesetzt, sonst `settings.database_url` (unverändert für Dev/Prod).

- [ ] **Step 1: Dependency ergänzen.** In `apps/backend/pyproject.toml` zur dev/test-Dependency-Gruppe (dort wo `pytest`/`pytest-asyncio`/`httpx` stehen) hinzufügen:

```toml
testcontainers = {version = "*", extras = ["postgres"]}
```

(Exakte Syntax an die vorhandene Gruppen-/Tool-Konvention im File anpassen — poetry vs PEP621. Falls `aiosqlite` nur für Tests vorhanden war, **noch nicht** entfernen — das passiert in Task 3 nach dem Grün.)

- [ ] **Step 2: Installieren.** Run: `/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/pip install "testcontainers[postgres]"`. Expected: installiert ohne Fehler; `python -c "import testcontainers.postgres"` ok.

- [ ] **Step 3: alembic/env.py — Env-URL bevorzugen.** Die Zeilen, die die URL aus settings setzen, ersetzen:

```python
# Alembic uses a sync URL. Prefer an explicit DATABASE_URL from the environment
# (tests point this at the testcontainer); fall back to app settings for dev/prod.
import os  # noqa: E402 — top-of-file imports are fine; place with the others
_raw_url = os.environ.get("DATABASE_URL") or settings.database_url
_sync_url = _raw_url.replace("+asyncpg", "")
config.set_main_option("sqlalchemy.url", _sync_url)
```

- [ ] **Step 4: Verify.** Run: `/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/ruff check alembic/env.py`. Expected: keine neuen Errors. (Funktionaler Test folgt in Task 2.)

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add pyproject.toml alembic/env.py
git commit -m "test(infra): testcontainers-Dep + Alembic-URL-Override für Test-DB

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: conftest.py — Postgres-Container, Migrationen, Seeds, Rollback-Fixtures

**Files:**
- Modify: `apps/backend/tests/conftest.py` (Kern-Umbau)

**Interfaces:**
- Produces: Fixtures `db_session` (transaktionsgebunden, rollback), `client`, `auth_client`, `superuser_client` (Signaturen/Namen **unverändert**, damit bestehende Tests sie weiter nutzen). Baseline-Test-User-Row mit `id = _TEST_USER_ID`.
- Consumes: `alembic upgrade head` (Task 1 env-Override), System-Seeds.

**Hintergrund:** Aktuell baut `db_engine` SQLite-in-memory mit `create_all` und ist function-scoped. Neu: session-scoped Container+Engine+Migrationen+Seeds; function-scoped Transaction-Rollback. Die App-Session-Override + Auth-Overrides bleiben im Prinzip, aber ohne SQLite-Workarounds und mit echtem User-Row.

- [ ] **Step 1: conftest.py neu schreiben.** Ersetze den Abschnitt von `# ── in-memory SQLite DB …` bis inkl. `superuser_client` durch:

```python
import os
import uuid
from pathlib import Path

os.environ["MAIL_SUPPRESS"] = "true"
os.environ["AUTO_APPROVE"] = "false"

import asyncpg
import pytest
import pytest_asyncio
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from testcontainers.postgres import PostgresContainer

from auth.users import current_active_user, current_optional_user
from dependencies import get_async_session
from main import app

_BACKEND_DIR = Path(__file__).resolve().parents[1]
_SEED_FILES = ["database/seeds/001_regions.sql", "database/seeds/002_tags.sql"]
_TEST_USER_ID = uuid.UUID("a0000000-0000-4000-8000-000000000001")


@pytest_asyncio.fixture(scope="session")
async def _engine():
    """Ephemeres Postgres+pgvector: Container → Alembic → System-Seeds → Baseline-User."""
    with PostgresContainer("pgvector/pgvector:pg16", driver="asyncpg") as pg:
        async_url = pg.get_connection_url()          # postgresql+asyncpg://...
        dsn = async_url.replace("+asyncpg", "")      # für asyncpg.connect / Alembic

        # Schema via dieselben Migrationen wie Dev/Prod (env.py liest DATABASE_URL).
        os.environ["DATABASE_URL"] = async_url
        cfg = Config(str(_BACKEND_DIR / "alembic.ini"))
        cfg.set_main_option("script_location", str(_BACKEND_DIR / "alembic"))
        command.upgrade(cfg, "head")

        # System-Seeds + Baseline-Test-User (committet, via simple-query-Protokoll).
        raw = await asyncpg.connect(dsn)
        try:
            for rel in _SEED_FILES:
                await raw.execute((_BACKEND_DIR / rel).read_text())
            await raw.execute(
                """
                INSERT INTO users (id, email, hashed_password, is_active, is_superuser,
                                   is_verified, display_name, company)
                VALUES ($1, 'test@test.local', 'x', true, true, true, 'Test User', NULL)
                ON CONFLICT (id) DO NOTHING
                """,
                _TEST_USER_ID,
            )
        finally:
            await raw.close()

        engine = create_async_engine(async_url)
        yield engine
        await engine.dispose()


@pytest_asyncio.fixture
async def db_session(_engine):
    """Connection-gebundene Transaktion + Savepoint; nach dem Test Rollback.

    App-`commit()` schließt nur den Savepoint; ein Listener startet ihn neu, sodass
    Folge-Queries weiterlaufen. Die äußere Transaktion wird nie committet → Test-
    eigene Rows verschwinden, System-Seeds/Baseline-User bleiben.
    """
    connection = await _engine.connect()
    trans = await connection.begin()
    session = AsyncSession(bind=connection, expire_on_commit=False)
    await connection.begin_nested()

    @event.listens_for(session.sync_session, "after_transaction_end")
    def _restart_savepoint(sess, transaction):
        if transaction.nested and not transaction._parent.nested:
            connection.sync_connection.begin_nested()

    try:
        yield session
    finally:
        await session.close()
        await trans.rollback()
        await connection.close()
```

- [ ] **Step 2: Client-Fixtures auf neue db_session umstellen.** Die drei Client-Fixtures behalten ihre Namen/Semantik; nur der MagicMock-Superuser wird durch einen **echten** geseedeten User ersetzt und die SQLite-Kommentare entfallen:

```python
def _override_session_factory(db_session):
    async def _override():
        yield db_session
    return _override


def _make_test_user():
    """Identität des Baseline-User-Rows (id=_TEST_USER_ID) für Auth-Overrides."""
    class _U:
        id = _TEST_USER_ID
        email = "test@test.local"
        is_active = True
        is_verified = True
        is_superuser = True
    return _U()


@pytest_asyncio.fixture
async def client(db_session):
    app.dependency_overrides[get_async_session] = _override_session_factory(db_session)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def auth_client(db_session):
    app.dependency_overrides[get_async_session] = _override_session_factory(db_session)
    app.dependency_overrides[current_active_user] = lambda: _make_test_user()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def superuser_client(db_session):
    app.dependency_overrides[get_async_session] = _override_session_factory(db_session)
    app.dependency_overrides[current_active_user] = lambda: _make_test_user()
    app.dependency_overrides[current_optional_user] = lambda: _make_test_user()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
```

Den `base_url`-Session-Fixture (Contract-Tests) **unverändert** am Dateiende lassen.

- [ ] **Step 3: pytest-asyncio session-scope sicherstellen.** Prüfen, dass session-scoped async Fixtures laufen: in `pyproject.toml`/`pytest.ini` muss `asyncio_mode = "auto"` **und** ein session-weiter Loop gesetzt sein (`[tool.pytest.ini_options] asyncio_mode="auto"`, ggf. `asyncio_default_fixture_loop_scope = "session"`). Falls nicht vorhanden, ergänzen.

- [ ] **Step 4: Suite gegen Postgres laufen lassen (Docker erforderlich).** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit -q`
Expected: Container startet, Migrationen + Seeds laufen, Tests werden ausgeführt. **Manche Tests dürfen hier noch rot sein** (skipif-Marker / Postgres-Striktheit) — das fixt Task 3. Erfolgskriterium dieses Tasks: Collection + DB-Setup funktionieren, ein Großteil grün, kein Fixture-/Connection-Crash.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add tests/conftest.py pyproject.toml
git commit -m "test(infra): Unit-Tests gegen ephemeres Postgres (testcontainers) statt SQLite

conftest: session-scoped pgvector-Container + alembic upgrade head + System-Seeds
+ Baseline-Test-User; Transaction-Rollback-Isolation; echter User statt MagicMock.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: skipif-Marker entfernen + Postgres-bedingte Test-Fehler fixen

**Files:**
- Modify: `apps/backend/tests/unit/*` (skipif-Marker entfernen; einzelne Tests anpassen)
- Modify: `apps/backend/pyproject.toml` (jetzt ungenutztes `aiosqlite` aus Test-Deps entfernen)

**Interfaces:** keine neuen; bestehende Tests müssen grün werden.

- [ ] **Step 1: skipif-on-sqlite finden + entfernen.** Run: `grep -rn "sqlite" tests/unit/`. Jeden `@pytest.mark.skipif(... sqlite ...)`-Marker (und zugehörige Helfer/Imports) entfernen, sodass die pgvector-Semantik-Tests jetzt regulär laufen.

- [ ] **Step 2: Volle Suite laufen + Fehlerliste erstellen.** Run: `/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit -q`. Die roten Tests notieren — typische Ursachen unter echtem Postgres:
  - **FK-Violations**, wo vorher (SQLite) FKs nicht erzwungen wurden → fehlende Parent-Rows seeden bzw. echte IDs verwenden (Baseline-User/-Tags/-Regionen nutzen).
  - **UUID-/Typ-Striktheit** → keine String-statt-UUID-Hacks mehr.
  - **NOT NULL / CHECK / Unique** → Testdaten an die echten Constraints anpassen.
  - **pgvector**: Embedding-Inserts müssen gültige Vektoren liefern.

- [ ] **Step 3: Fehler fixen — pro Test minimal.** Jeden roten Test so anpassen, dass er das **echte** Constraint-konforme Szenario testet (nicht Constraints umgehen). Tests, die nur dank SQLite-Lascheit „grün" waren, werden korrekt gemacht. Nach jedem Cluster erneut `pytest tests/unit -q`.

- [ ] **Step 4: aiosqlite entfernen.** Wenn `grep -rn "sqlite" tests/` leer ist, `aiosqlite` aus den Test-Deps in `pyproject.toml` streichen. Run: `grep -rn "sqlite" tests/ alembic/ *.py` → muss leer sein (kein SQLite mehr).

- [ ] **Step 5: Volle Suite grün + ruff.** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit -q` → **alle grün**;
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/ruff check tests/ alembic/` → keine neuen Errors.

- [ ] **Step 6: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add tests/ pyproject.toml
git commit -m "test: skipif-on-sqlite entfernt, Tests an echte Postgres-Constraints angepasst

pgvector-Semantik-Tests laufen jetzt echt; FK/Typ/NOT-NULL-Striktheit erfüllt.
aiosqlite aus Test-Deps entfernt — kein SQLite mehr im Projekt.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Drift-Guard — `alembic check` (Schema ↔ Model)

**Files:**
- Create: `apps/backend/tests/unit/test_schema_migrations_sync.py`

**Interfaces:** Consumes Task-1/2 (Migrationen laufen gegen `_engine`/Container-DB).

- [ ] **Step 1: Failing-/Guard-Test schreiben.** Der Test fährt `alembic check` gegen die migrierte Test-DB und schlägt fehl, wenn Autogenerate ausstehende Ops findet (Model ≠ Migrationen):

```python
# apps/backend/tests/unit/test_schema_migrations_sync.py
"""Guard: ORM-Models und Alembic-Migrationen dürfen nicht auseinanderlaufen."""
import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from alembic.util import CommandError

_BACKEND_DIR = Path(__file__).resolve().parents[2]


@pytest.mark.asyncio
async def test_models_match_migrations(_engine):
    """`alembic check` findet keine ausstehenden Autogenerate-Ops."""
    cfg = Config(str(_BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(_BACKEND_DIR / "alembic"))
    # _engine-Fixture hat DATABASE_URL bereits auf die Container-DB gesetzt + upgrade head gefahren.
    assert os.environ.get("DATABASE_URL"), "Test-DB-URL muss gesetzt sein"
    try:
        command.check(cfg)  # raises CommandError bei pending diffs
    except CommandError as exc:
        pytest.fail(f"Models und Migrationen driften: {exc}")
```

- [ ] **Step 2: Lauf — muss grün sein (oder echten Drift aufdecken).** Run:
`/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_schema_migrations_sync.py -q`
Expected: PASS. Falls FAIL → es gibt echten Drift; entweder eine fehlende Migration ergänzen (`alembic revision --autogenerate`) **oder**, wenn der Diff nur kosmetisch/nicht-autogenerierbar ist (z. B. pgvector-Typen, Server-Defaults), den Guard gezielt auf die relevanten Objekte eingrenzen und die Ausnahme im Test dokumentieren. **Keinen** echten Schema-Drift unter den Tisch kehren.

- [ ] **Step 3: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add tests/unit/test_schema_migrations_sync.py
git commit -m "test(guard): alembic check — Models/Migrationen-Drift schlägt fehl

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Doku — Docker-Voraussetzung für Tests

**Files:**
- Modify: `apps/backend/CLAUDE.md` (Test-Abschnitt)

- [ ] **Step 1: CLAUDE.md ergänzen.** Im Abschnitt „Tests" notieren, dass Unit-Tests jetzt ein echtes Postgres+pgvector via testcontainers nutzen (Docker erforderlich), Schema via Alembic + System-Seeds, Isolation via Transaction-Rollback; kein SQLite mehr. Beispiel-Zeile:

```markdown
> Unit-Tests starten via `testcontainers` ein ephemeres `pgvector/pgvector:pg16`
> (Docker erforderlich), bauen das Schema mit `alembic upgrade head` + System-Seeds
> und isolieren jeden Test per Transaction-Rollback. Kein SQLite mehr.
```

- [ ] **Step 2: Commit.**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend
git add CLAUDE.md
git commit -m "docs(backend): Unit-Tests brauchen Docker (testcontainers Postgres)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Done-Kriterium Gesamt:** `pytest tests/unit` grün gegen Postgres (inkl. vormals geskippter pgvector-Tests + Drift-Guard); `grep -rn sqlite tests/` leer; ruff sauber; Contract-Suite unverändert.

---

## Self-Review

**Spec-Coverage:** testcontainers-Container → T2 ✓ · alembic upgrade head → T2 ✓ · System-Seeds (001/002) → T2 ✓ · Baseline-User (Session, committet) → T2 ✓ · Transaction-Rollback-Isolation → T2 ✓ · App-Session-Override → T2 ✓ · Auth ohne SQLite-Hacks/echter User → T2 ✓ · skipif entfernen + pgvector-Tests grün → T3 ✓ · alembic-check-Guard → T4 ✓ · kein SQLite (aiosqlite raus) → T3 ✓ · env.py-URL-Override → T1 ✓ · Docker/CI-Doku → T5 ✓ · Done-Kriterien → Task-Schlusszeile ✓.

**Platzhalter-Scan:** Keine TODO/TBD. Offene Stellen sind bewusst implementierungsabhängig markiert: exakte pyproject-Dep-Syntax (T1.1 — an vorhandene Konvention anpassen), Liste der zu fixenden Tests (T3 — erst zur Laufzeit sichtbar, mit konkreter Ursachen-Checkliste), alembic-check-Ausnahmen nur bei echtem nicht-autogenerierbarem Diff (T4 — mit Anweisung, echten Drift nicht zu verstecken).

**Typ-/Namens-Konsistenz:** `_TEST_USER_ID` (uuid) konsistent T2/T4-Kontext; Fixture-Namen `db_session`/`client`/`auth_client`/`superuser_client`/`base_url` unverändert (bestehende Tests bleiben kompatibel); `_engine`-Fixture von db_session + Guard-Test (T4) genutzt; `DATABASE_URL`-Env-Vertrag zwischen T1 (env.py) und T2 (Fixture setzt ihn) konsistent.

**Risiko-Hinweis für Ausführung:** Der async-Savepoint-Restart-Listener (T2 Step 1) ist der fragilste Teil — falls Folge-`commit()`s im App-Code nach dem ersten Savepoint-Ende fehlschlagen, ist der Listener-Trigger (`transaction.nested and not transaction._parent.nested`) gegen die installierte SQLAlchemy-Version zu prüfen und ggf. an deren aktuelles Rezept anzupassen. Verifikation strikt über „volle Suite grün".
