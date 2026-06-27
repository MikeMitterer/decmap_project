# Test-DB-Umstellung: SQLite → Postgres (testcontainers) — Design

**Datum:** 2026-06-27
**Status:** Approved (Brainstorm) → bereit für Implementierungsplan
**Repo:** `apps/backend`

## Motivation

Die Backend-**Unit-Tests** laufen aktuell gegen eine In-Memory-**SQLite**-DB (`tests/conftest.py:26`, `sqlite+aiosqlite:///:memory:`), während Dev/Prod **PostgreSQL + pgvector** nutzen. Das ist die einzige SQLite-Nutzung im Projekt und verursacht:

- **Test/Dev-Drift:** SQLite erzwingt FKs standardmäßig nicht, ist typ-lasch und kennt kein pgvector → Constraints/Verhalten weichen vom echten System ab.
- **Tote Tests:** pgvector-Semantik-Tests sind `skipif`-on-sqlite → laufen nie wirklich.
- **Workarounds im Test-Code:** MagicMock-Superuser + `user_id=None`, um „PostgreSQL-UUID-Inkompatibilität mit SQLite" zu umgehen (Kommentare in `conftest.py`).
- **JSONB → JSON-Variant** in den Models nur wegen SQLite.

**Ziel:** Unit-Tests laufen gegen echtes Postgres (pgvector), per `testcontainers` ephemer. Kein SQLite mehr im Test-Code. Test-Schema/Constraints/Seeds **identisch zu Dev/Prod** (keine parallelen Definitionen). Nach der Umstellung ist die **gesamte Suite grün**, inkl. der vorher übersprungenen pgvector-Tests.

## Non-Goals

- Keine Änderung am Prod-/Dev-Verhalten oder an der App-Logik.
- **Contract-Tests** (`tests/contract/`, laufen bereits gegen echtes Postgres via httpx) bleiben unverändert.
- Keine Migration der Demo-Seeds in Tests (nur System-Seeds — s. u.).
- `JSONB().with_variant(JSON(), "sqlite")` in den Models darf bleiben (harmlos, separates Cleanup) — optionales Aufräumen kein Blocker.
- F2 (cross-linguale FTS) ist ein **Folgeprojekt**, das von dieser Umstellung profitiert (FTS wird dann ohne `skipif` testbar).

## Kern-Prinzip gegen Drift

**Tests konsumieren dieselben Artefakte wie Dev/Prod**, statt eigene parallele Definitionen zu pflegen:

1. **Schema/Constraints:** Aufbau via **`alembic upgrade head`** (dieselben Migrationen 001–009 wie Dev/Prod), **nicht** `Base.metadata.create_all`. → Tabellen, FKs, CHECKs, Unique-Constraints, Indizes, pgvector-Extension per Konstruktion identisch. Deckt zusätzlich nicht-laufbare Migrationen (from-scratch) auf.
2. **Schema↔Model-Guard:** Test via **`alembic check`** (autogenerate pending-ops) — schlägt fehl, wenn ORM-Models und Migrationen auseinanderlaufen.
3. **Seed-Daten:** echte System-Seeds laden — **`database/seeds/001_regions.sql`** + **`database/seeds/002_tags.sql`** (Regionen + Tags L0–L9, deterministische uuid5-IDs). **Keine** Demo-Seeds. Entspricht exakt einem frischen `make db-reset`. Bricht ein Seed-File, fällt es im Test auf.
4. **Constraints echt erzwungen:** FKs/Typen greifen jetzt → Alt-Tests, die SQLite-Lascheit ausnutzten, werden gefixt (Drift-Abbau).
5. **Gleicher Code-Pfad:** echte FastAPI-App (ASGI); nur `get_async_session` zeigt auf die Test-Transaktion.

## Architektur / Komponenten

### 1. Ephemerer Postgres via testcontainers
- Neue dev/test-Dependency: `testcontainers[postgres]`.
- **Session-scoped** Fixture startet `pgvector/pgvector:pg16` (enthält pgvector), liefert eine **asyncpg**-Connection-URL (aus Host/Port des Containers konstruiert).
- Container lebt für die gesamte Test-Session, wird am Ende entsorgt.

### 2. Schema-Aufbau (session-scoped, einmalig)
- `alembic upgrade head` gegen die Container-DB. Alembic-`env.py` muss die Test-DB-URL akzeptieren (Override via Env-Var, z. B. `DATABASE_URL`/`TEST_DATABASE_URL`).
- pgvector-Extension entsteht dabei automatisch (Migration `002_add_pgvector`).

### 3. System-Seeds (session-scoped, nach Migrationen, committet)
- `001_regions.sql` dann `002_tags.sql` (alphabetisch, idempotent) gegen die Container-DB ausführen und **committen** → Baseline für alle Tests sichtbar.

### 4. Per-Test-Isolation: Transaction-Rollback
- **session-scoped:** Container + async-Engine + Migrationen + Seeds (committet).
- **function-scoped:** Connection öffnen → äußere Transaktion `begin()` → Session an diese Connection binden → `begin_nested()`-Savepoint; ein Event-Listener startet den Savepoint nach jedem App-`commit()` neu (SQLAlchemy „join an external transaction"-Pattern). Nach dem Test: **Rollback** der äußeren Transaktion → Test-eigene Rows verschwinden, System-Seeds bleiben.
- `get_async_session`-Override liefert **dieselbe** transaktionsgebundene Session, damit App-Schreibvorgänge + Test-Assertions denselben (uncommitteten) Stand sehen.

### 5. Auth-Fixtures (SQLite-Hacks raus)
- Die `current_active_user`/`current_optional_user`-Overrides bleiben als Mechanismus.
- **Aber:** ein **echter** Test-User-Row (id = `_TEST_USER_ID`) wird **als Teil der Session-Baseline** (nach den System-Seeds, committet) angelegt, damit authored Ressourcen gültige FKs haben (auf Postgres mit erzwungenen FKs nötig; vorher via `user_id=None` umgangen) und der Row in jedem Test sichtbar ist. Damit testen wir den realen authored-Pfad statt eines anonymen Sonderfalls.
- Die irreführenden „SQLite-UUID-Inkompatibilität"-Kommentare entfernen.

### 6. pgvector-Tests reaktivieren
- Alle `skipif`-on-sqlite-Marker entfernen → Semantik-/Embedding-Tests laufen jetzt echt gegen pgvector und müssen grün sein.

### 7. Aufruf / CI
- Befehl bleibt: `make api-test` / `.venv/bin/pytest tests/unit`. testcontainers managed die DB-Lifecycle.
- Voraussetzung: Docker beim Testen verfügbar (lokal + Jenkins-`test`-Stage — beides gegeben).
- Doku in `apps/backend/CLAUDE.md` (+ ggf. README) ergänzen: Unit-Tests brauchen jetzt Docker.

## Risiken / erwartete Arbeit

- **Strenge von Postgres** (FK-Enforcement, Typ-/NOT-NULL-Striktheit, UUID-Casts) deckt Tests auf, die SQLite-Lascheit ausnutzten → diese werden gefixt. Das ist beabsichtigt, kann aber den Umstellungs-Aufwand vergrößern (Anzahl betroffener Tests erst bei der Umsetzung sichtbar).
- **Performance:** Container-Start (~Sekunden) + Migrationen einmal pro Session; Transaction-Rollback hält die Per-Test-Kosten niedrig. Gesamtlaufzeit steigt moderat vs. SQLite-in-Memory — akzeptiert für Korrektheit.
- **Async + testcontainers + Savepoint-Rollback** ist fummelig (Event-Loop-Scope, session-scoped async Fixtures, Savepoint-Restart-Listener) — im Plan als eigene, getestete Schritte.
- **Alembic gegen Test-URL:** `env.py` muss die Test-DB-URL sauber übernehmen, ohne Dev/Prod-Konfiguration zu beeinflussen.

## Done-Kriterien

- [ ] `tests/conftest.py` nutzt kein SQLite mehr; Unit-Tests laufen gegen ephemeres Postgres (testcontainers, pgvector-Image).
- [ ] Schema via `alembic upgrade head`; System-Seeds (`001_regions.sql`, `002_tags.sql`) geladen.
- [ ] `alembic check`-Guard-Test vorhanden und grün (Models ↔ Migrationen synchron).
- [ ] Alle `skipif`-on-sqlite-Marker entfernt; vorher übersprungene pgvector-Tests laufen und sind grün.
- [ ] SQLite-bedingte Workarounds (MagicMock-only-Auth-Kommentare, `user_id=None`-Begründung) entfernt; echter Test-User geseedet.
- [ ] **Gesamte Unit-Suite grün gegen Postgres**; Contract-Suite unverändert grün; ruff sauber.
- [ ] `CLAUDE.md` (backend) dokumentiert die neue Docker-Voraussetzung.

## Betroffene Dateien (Erstschätzung)

- `apps/backend/tests/conftest.py` (Kern-Umbau: Container, Engine, Migrationen, Seeds, Rollback-Fixtures, Auth-User-Seed)
- `apps/backend/alembic/env.py` (Test-DB-URL-Override)
- `apps/backend/pyproject.toml` (Dependency `testcontainers[postgres]`)
- `apps/backend/tests/unit/` (skipif-Marker entfernen; ggf. Tests fixen, die auf SQLite-Lascheit bauten)
- neuer Guard-Test (z. B. `apps/backend/tests/unit/test_schema_migrations_sync.py`)
- `apps/backend/CLAUDE.md` (Docker-Voraussetzung für Tests)
