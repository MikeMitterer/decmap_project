# Phase 2 Backlog (#28–#33) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die beim Phase-1/2-Verify gefundenen Enhancement-/Bug-Tickets #28–#33 (+ Follow-up #35) umsetzen: Table-Filter-UI (URL-Filter, Firmen-Filter, Chip-Klarheit, Multi-Value), Table-Suche (Relevanz-Score, cross-linguale Symmetrie) und der Graph-Overlap-Fix beim Drill-Down.

**Architecture:** Aufbauend auf der Server-Driven-Pagination (Phase 1) + Graph-Drill-Down (Phase 2). Filter bleiben server-seitig über `GET /problems` (`ProblemQuery` → Cursor-Store `useProblems`); die URL wird Spiegel + initialer Loader des UI-States. Suche bleibt im Backend (Keyword + pgvector-Semantik). Der Graph bleibt auf `cluster-summary` + lazy Drill-Down; der Overlap-Fix ist rein client-seitig in `ProblemGraph.vue`.

**Tech Stack:** FastAPI + SQLAlchemy(async) + asyncpg + pgvector (Backend); FastAPI (ai-service, Translation); Nuxt 3 + TypeScript + @tanstack/vue-virtual + Cytoscape.js (Frontend); pytest (Backend/ai-service), Vitest (Frontend).

**Issues:** `MikeMitterer/decmap_project` #28, #29, #30, #31, #32, #33, #35.

## Global Constraints

- **Repos/Branches:** `apps/backend` + `apps/ai-service` auf `master` (direkte Commits erlaubt); `apps/frontend` auf `feature/bold-redesign`. Pro Repo separat committen.
- **Conventional Commits** + Trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Tests pro Task grün; keine neuen Lint-Errors** (ruff backend/ai-service, eslint frontend — pre-existing Baseline erlaubt).
- **Cursor-Contract** ist opak: `{s, k, i, e?, q?, d?}` (sort, key, id, emb, q_en, dir). Erweiterungen additiv (neuer Key bricht alte Cursor nicht — alte Cursor liefern den Key schlicht als `None`).
- **asyncpg-Klammer-Gotcha:** Param-Cast immer klammern: `(:emb)::vector`, nie `:emb::vector`. (Semantik-SQL inlined den Vektor bereits als String-Literal — nicht ändern.)
- **Soft-Delete:** jede Problem-Query `deleted_at IS NULL` explizit.
- **Status-Auth:** `status != approved` erfordert Superuser.
- **`q` und `semantic` gegenseitig exklusiv.**
- **JSONB SQLite-Variant:** `original_translations` ist `JSONB().with_variant(JSON(), "sqlite")` — Such-SQL portabel halten (`cast(..., Text)` läuft auf beiden).
- **i18n:** alle UI-Strings über `t()`; Keys in `apps/frontend/i18n/locales/{en,de}.json`, flache zweistufige Nesting-Konvention (`section.key`).
- **Themes:** keine hardcoded Farben, wo Theme-Tokens nötig sind; bestehende Chip-Tailwind-Utilities (`emerald`/`violet`) dürfen bleiben.

---

# Phase A — Table Filter-UI (#31, #29, #30, #35)

Reihenfolge: erst das URL-/Filter-Schema (#31) als Fundament, dann Multi-Value-Backend (#35), Company-Filter-UI (#29), Chip-Klarheit (#30).

---

### Task A1: Frontend — `useTableFiltersUrl` Composable (#31)

**Files:**
- Create: `apps/frontend/composables/useTableFiltersUrl.ts`
- Test: `apps/frontend/tests/composables/useTableFiltersUrl.spec.ts` (create)

**Interfaces:**
- Produces: `useTableFiltersUrl()` → `{ parseRouteToQuery(route): ProblemQuery, queryToRouteParams(q: ProblemQuery): Record<string,string>, FILTER_PARAM_MAP }`.
- Consumes: `ProblemQuery` aus `composables/data/types.ts` (Felder: `sort, dir, q, semantic, tags, regions, user, company, status`).

Das Composable kapselt die **zentrale Param↔ProblemQuery-Map** (ein Eintrag pro Filter) plus serialize/deserialize. Array-Filter (`tags`/`regions`) komma-getrennt. `q`/`semantic` gegenseitig exklusiv (nie beide in die URL). Leere Werte werden weggelassen.

- [ ] **Step 1: Write the failing test**

```ts
// apps/frontend/tests/composables/useTableFiltersUrl.spec.ts
import { describe, it, expect } from 'vitest'
import { useTableFiltersUrl } from '~/composables/useTableFiltersUrl'

describe('useTableFiltersUrl', () => {
  const { parseRouteToQuery, queryToRouteParams } = useTableFiltersUrl()

  it('parseRouteToQuery: liest user + company aus der Route', () => {
    const q = parseRouteToQuery({ query: { user: 'u-1', company: 'Acme GmbH' } })
    expect(q.user).toBe('u-1')
    expect(q.company).toBe('Acme GmbH')
  })

  it('parseRouteToQuery: komma-getrennte tags bleiben String (Backend split)', () => {
    const q = parseRouteToQuery({ query: { tags: 't1,t2' } })
    expect(q.tags).toBe('t1,t2')
  })

  it('queryToRouteParams: round-trip lässt leere Filter weg', () => {
    const params = queryToRouteParams({ user: 'u-1', company: '', tags: [] })
    expect(params).toEqual({ user: 'u-1' })
  })

  it('queryToRouteParams: q und semantic schließen sich aus (q gewinnt)', () => {
    const params = queryToRouteParams({ q: 'foo', semantic: 'foo' })
    expect(params.q).toBe('foo')
    expect(params.semantic).toBeUndefined()
  })

  it('queryToRouteParams: tags-Array wird komma-gejoint', () => {
    const params = queryToRouteParams({ tags: ['t1', 't2'] })
    expect(params.tags).toBe('t1,t2')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/frontend && npx vitest run tests/composables/useTableFiltersUrl.spec.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

```ts
// apps/frontend/composables/useTableFiltersUrl.ts
import type { ProblemQuery } from '~/composables/data/types'

/**
 * Zentrale Map URL-Param ↔ ProblemQuery-Feld. Neuer Filter = ein Eintrag.
 * `array: true` → komma-getrennte Serialisierung (konsistent mit Backend split(',')).
 */
interface FilterParam {
  param: string
  field: keyof ProblemQuery
  array?: boolean
}

export const FILTER_PARAM_MAP: FilterParam[] = [
  { param: 'sort', field: 'sort' },
  { param: 'dir', field: 'dir' },
  { param: 'q', field: 'q' },
  { param: 'semantic', field: 'semantic' },
  { param: 'tags', field: 'tags', array: true },
  { param: 'regions', field: 'regions', array: true },
  { param: 'user', field: 'user' },
  { param: 'company', field: 'company' },
  { param: 'status', field: 'status' },
]

export function useTableFiltersUrl() {
  function parseRouteToQuery(route: { query: Record<string, unknown> }): ProblemQuery {
    const q: ProblemQuery = {}
    for (const { param, field } of FILTER_PARAM_MAP) {
      const raw = route.query[param]
      if (typeof raw === 'string' && raw.length > 0) {
        ;(q as Record<string, string>)[field] = raw
      }
    }
    // q/semantic exklusiv: q gewinnt
    if (q.q && q.semantic) delete q.semantic
    return q
  }

  function queryToRouteParams(query: ProblemQuery): Record<string, string> {
    const out: Record<string, string> = {}
    for (const { param, field, array } of FILTER_PARAM_MAP) {
      const val = (query as Record<string, unknown>)[field]
      if (val == null) continue
      if (array) {
        const joined = Array.isArray(val) ? val.join(',') : String(val)
        if (joined.length > 0) out[param] = joined
      } else if (String(val).length > 0) {
        out[param] = String(val)
      }
    }
    if (out.q && out.semantic) delete out.semantic
    return out
  }

  return { parseRouteToQuery, queryToRouteParams, FILTER_PARAM_MAP }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/frontend && npx vitest run tests/composables/useTableFiltersUrl.spec.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd apps/frontend
git add composables/useTableFiltersUrl.ts tests/composables/useTableFiltersUrl.spec.ts
git commit -m "feat(table): useTableFiltersUrl — zentrale Param↔ProblemQuery-Map (#31)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A2: Frontend — `table.vue` URL-Sync verdrahten (#31)

**Files:**
- Modify: `apps/frontend/pages/table.vue`

**Interfaces:**
- Consumes: `useTableFiltersUrl` (A1), `useRoute`/`useRouter` (Nuxt), bestehende Filter-Refs `tagFilterIds`, `userFilterIds`, `companyFilters`, `sortKey`, `sortDirection`, injizierte `searchQuery`/`semanticSearchEnabled`, `buildQuery()`, `loadFirstPage`.

UI-State bleibt Source of Truth; URL = Spiegel + initialer Loader. Beim Mount URL→State; bei State-Änderung State→URL via `router.replace` (debounced für `q`). Leere Filter aus der URL entfernen.

- [ ] **Step 1: Mount-Hydration URL→State.** In `<script setup>` von `table.vue` nach den Filter-Refs einfügen:

```ts
import { useTableFiltersUrl } from '~/composables/useTableFiltersUrl'

const route = useRoute()
const router = useRouter()
const { parseRouteToQuery, queryToRouteParams } = useTableFiltersUrl()

onMounted(() => {
  const q = parseRouteToQuery(route)
  if (q.tags) tagFilterIds.value = String(q.tags).split(',').filter(Boolean)
  if (q.user) userFilterIds.value = [q.user]
  if (q.company) companyFilters.value = [q.company]
  if (q.sort) sortKey.value = q.sort
  if (q.dir) sortDirection.value = q.dir as 'asc' | 'desc'
  // searchQuery/semantic werden vom Layout injiziert; nur setzen, wenn vorhanden
  if (q.q && searchQuery) searchQuery.value = q.q
})
```

(Hinweis: `searchQuery`/`semanticSearchEnabled` sind injizierte Refs — nur schreiben, wenn nicht readonly; falls das Layout sie readonly bereitstellt, diesen Teil weglassen und nur lokale Filter hydrieren.)

- [ ] **Step 2: State→URL Sync.** Direkt nach dem bestehenden Filter-`watch` (der `triggerLoad` aufruft) eine zweite, separate Watch ergänzen, die die URL spiegelt:

```ts
watch(
  [tagFilterIds, userFilterIds, companyFilters, sortKey, sortDirection],
  () => {
    const params = queryToRouteParams(buildQuery())
    router.replace({ query: params })
  },
  { deep: true },
)
```

`buildQuery()` liefert bereits die `ProblemQuery` aus den Refs; `queryToRouteParams` entfernt leere Werte. `router.replace` vermeidet History-Spam.

- [ ] **Step 3: Verify.** Run: `cd apps/frontend && npx vitest run` — grün; `npx eslint pages/table.vue` — 0 neue Errors. Manuell (später Live-Verify): `/table?user=<id>` lädt gefiltert; Chip-Klick aktualisiert URL; Reload reproduziert Zustand.

- [ ] **Step 4: Commit**

```bash
cd apps/frontend
git add pages/table.vue
git commit -m "feat(table): Filter ↔ URL zwei-Wege-Sync (router.replace, Mount-Hydration) (#31)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A3: Backend — user/company-Filter Multi-Value + company ILIKE (#35, #29)

**Files:**
- Modify: `apps/backend/routers/problems.py` (`_build_filter_clauses`, lines ~210–302)
- Test: `apps/backend/tests/unit/test_problems_filters.py` (erweitern/erstellen)

**Interfaces:**
- Konsumiert weiterhin `user_param`/`company_param` als `str | None` aus der Route, jetzt **komma-getrennt** interpretiert (konsistent mit `tags`/`regions`).
- `user` → mehrere UUIDs (`Problem.user_id.in_([...])`); `company` → mehrere Namen, **ILIKE** (Freitext-tauglich) OR-verknüpft, aufgelöst zu User-IDs.

- [ ] **Step 1: Write the failing test**

```python
# apps/backend/tests/unit/test_problems_filters.py
import pytest

@pytest.mark.asyncio
async def test_company_filter_ilike_case_insensitive(client, seed_problems_with_companies):
    # seed: ein Problem mit Autor company="Acme Manufacturing GmbH"
    r = await client.get("/problems?company=acme manufacturing gmbh")
    assert r.status_code == 200
    assert r.json()["total"] >= 1

@pytest.mark.asyncio
async def test_company_filter_multi_value_or(client, seed_problems_with_companies):
    # seed: Autoren mit company "Acme" und "Nordbank"
    r = await client.get("/problems?company=Acme,Nordbank")
    assert r.status_code == 200
    # beide Firmen-Probleme enthalten
    assert r.json()["total"] >= 2

@pytest.mark.asyncio
async def test_user_filter_multi_value_in(client, seed_two_authored_problems):
    uid1, uid2 = seed_two_authored_problems
    r = await client.get(f"/problems?user={uid1},{uid2}")
    assert r.status_code == 200
    assert r.json()["total"] == 2
```

(Falls keine passende Fixture existiert: am bestehenden Filter-Test-Setup in `tests/unit/` orientieren — User mit `company` anlegen + Probleme diesen Usern zuordnen. Die genauen Fixture-Namen an das vorhandene Conftest anpassen.)

- [ ] **Step 2: Run to verify fail.** Run: `/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_filters.py -q`. Expected: FAIL.

- [ ] **Step 3: Implement.** In `_build_filter_clauses` die user-/company-Klauseln ersetzen:

```python
# user: komma-getrennte UUIDs → IN-Liste
if user_param:
    user_uuids: list[uuid.UUID] = []
    for part in user_param.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            user_uuids.append(uuid.UUID(part))
        except ValueError:
            continue
    if user_uuids:
        where.append(Problem.user_id.in_(user_uuids))

# company: komma-getrennte Namen → ILIKE OR, aufgelöst zu User-IDs
if company_param:
    names = [n.strip() for n in company_param.split(",") if n.strip()]
    if names:
        company_clause = or_(*[User.company.ilike(n) for n in names])
        user_id_rows = await session.execute(select(User.id).where(company_clause))
        company_user_ids = [row[0] for row in user_id_rows.all()]
        if company_user_ids:
            where.append(Problem.user_id.in_(company_user_ids))
        else:
            where.append(Problem.id.is_(None))  # always-false sentinel
```

(`or_` ggf. importieren, falls noch nicht im File. ILIKE ohne `%`-Wildcards = case-insensitive exact; für Substring später `f"%{n}%"` — bewusst exact-insensitive für eindeutige Firmen.)

- [ ] **Step 4: Run to verify pass** + ruff. Run die Tests + `/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/ruff check routers/ tests/`.

- [ ] **Step 5: Frontend sendet alle Chips.** In `apps/frontend/pages/table.vue` `buildQuery()`: statt nur `userFilterIds.value[0]`/`companyFilters.value[0]` jetzt komma-gejoint senden:

```ts
if (userFilterIds.value.length) query.user = userFilterIds.value.join(',')
if (companyFilters.value.length) query.company = companyFilters.value.join(',')
```

Den Phase-1-Limitations-Kommentar (nur `[0]`) entfernen. `cd apps/frontend && npx vitest run` grün, eslint 0 neu.

- [ ] **Step 6: Commit** (zwei Repos)

```bash
cd apps/backend && git add routers/problems.py tests/unit/test_problems_filters.py
git commit -m "feat(problems): user/company-Filter Multi-Value + company ILIKE (#35, #29)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
cd ../frontend && git add pages/table.vue
git commit -m "feat(table): alle user/company-Chips an Server senden (Multi-Value) (#35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A4: Frontend — Company-Filter-Eingabe in der Table-View + Registrierungsfeld (#29)

**Files:**
- Modify: `apps/frontend/pages/table.vue` (sichtbares Company-Filter-Input + aktive-Filter-Chips)
- Modify: `apps/frontend/i18n/locales/en.json` + `de.json` (neue Keys)
- Modify: `apps/frontend/pages/register.vue` *(falls company dort fehlt — prüfen; UserCreate hat das Feld bereits)*

**Interfaces:**
- Consumes: `companyFilters` ref, `handleCompanyFilter` (existiert), `loadFirstPage` über bestehende Watch.

**Hinweis:** Das **editierbare** Firmenfeld in Settings existiert bereits (`settings.vue` + `company` in UserRead/Update + Model). Diese Task liefert nur den **Filter-Einstieg** in der Table + optional das Registrierungsfeld.

- [ ] **Step 1: i18n-Keys.** In `en.json` Abschnitt `"table"` ergänzen:

```json
"companyFilter": "Filter by company",
"companyFilterPlaceholder": "Company name",
"activeFilters": "Active filters",
"clearFilter": "Remove filter"
```

Analog in `de.json`: `"Nach Firma filtern"`, `"Firmenname"`, `"Aktive Filter"`, `"Filter entfernen"`.

- [ ] **Step 2: Company-Filter-Input + aktive-Chips im Table-Header.** Über der Tabelle ein Eingabefeld + Anzeige aktiver Company-Chips. Beispiel-Markup (in den bestehenden Filter-/Header-Bereich von `table.vue` einfügen, Tailwind-Stil an vorhandene Controls anpassen):

```vue
<div class="flex items-center gap-2">
  <input
    v-model.trim="companyFilterInput"
    type="text"
    :placeholder="t('table.companyFilterPlaceholder')"
    :aria-label="t('table.companyFilter')"
    class="px-2 py-1 rounded border border-th-input-border bg-th-input-bg text-sm"
    @keyup.enter="addCompanyFilter"
  />
  <span
    v-for="c in companyFilters"
    :key="c"
    class="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-violet-50 text-violet-700 text-xs dark:bg-violet-900/40 dark:text-violet-300"
  >
    🏢 {{ c }}
    <button type="button" :aria-label="t('table.clearFilter')" @click="removeCompanyFilter(c)">×</button>
  </span>
</div>
```

Script-Logik:

```ts
const companyFilterInput = ref('')
function addCompanyFilter(): void {
  const v = companyFilterInput.value.trim()
  if (v && !companyFilters.value.includes(v)) companyFilters.value.push(v)
  companyFilterInput.value = ''
}
function removeCompanyFilter(c: string): void {
  companyFilters.value = companyFilters.value.filter((x) => x !== c)
}
```

Die bestehende Filter-Watch löst `loadFirstPage` aus; A2 spiegelt in die URL.

- [ ] **Step 3: Registrierungsfeld prüfen.** `grep -n "company" apps/frontend/pages/register.vue`. Falls kein Feld: ein optionales `company`-Input analog zu `displayName` ergänzen und an `register(...)` durchreichen (UserCreate akzeptiert `company` bereits). Falls schon vorhanden: keine Änderung, in der Task-Report notieren.

- [ ] **Step 4: Verify.** `cd apps/frontend && npx vitest run` grün; `npx eslint pages/table.vue pages/register.vue` 0 neu. Manuell (Live-Verify): Firmenname eingeben → Tabelle filtert server-seitig; Chip entfernbar; `total` korrekt.

- [ ] **Step 5: Commit**

```bash
cd apps/frontend
git add pages/table.vue pages/register.vue i18n/locales/en.json i18n/locales/de.json
git commit -m "feat(table): sichtbarer Company-Filter (Freitext) + Registrierungsfeld (#29)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task A5: Frontend — Autor-/Firmen-Chip im ProblemPanel klarer (#30)

**Files:**
- Modify: `apps/frontend/components/ProblemPanel.vue` (Chips ~785–800)
- Modify: `apps/frontend/i18n/locales/en.json` + `de.json`

**Interfaces:** Klick-Verhalten unverändert (emit `user-filter`/`company-filter`).

- [ ] **Step 1: i18n-Keys.** In `en.json` (`"panel"` oder passender Abschnitt — vorhandene Konvention prüfen):

```json
"filterByAuthor": "Filter by author",
"filterByCompany": "Filter by company"
```

DE: `"Nach Autor filtern"`, `"Nach Firma filtern"`.

- [ ] **Step 2: Icons + aria-label.** Autor-Chip (emerald) um Person-Icon + `:aria-label`/`:title` ergänzen, Firmen-Chip (violet) um Gebäude-Icon:

```vue
<button
  type="button"
  :aria-label="t('panel.filterByAuthor')"
  :title="t('panel.filterByAuthor')"
  class="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-emerald-50 text-emerald-700 font-medium hover:bg-emerald-100 transition-colors dark:bg-emerald-900/40 dark:text-emerald-300 dark:hover:bg-emerald-900"
  @click="emit('user-filter', author!.id)"
>
  <span aria-hidden="true">👤</span>
  {{ author.displayName ?? author.email }}
</button>

<button
  v-if="author.company"
  type="button"
  :aria-label="t('panel.filterByCompany')"
  :title="t('panel.filterByCompany')"
  class="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-violet-50 text-violet-700 font-medium hover:bg-violet-100 transition-colors dark:bg-violet-900/40 dark:text-violet-300 dark:hover:bg-violet-900"
  @click="emit('company-filter', author!.company!)"
>
  <span aria-hidden="true">🏢</span>
  {{ author.company }}
</button>
```

(Icon als Emoji oder, falls das Projekt eine Icon-Komponente nutzt, diese verwenden — vorhandene Icon-Konvention prüfen via `grep`.)

- [ ] **Step 3: Verify.** `cd apps/frontend && npx vitest run` grün; `npx eslint components/ProblemPanel.vue` 0 neu. Light/Dark + Glass-Themes visuell konsistent (Tailwind-Utilities mit `dark:`-Varianten — kein hardcoded rgba).

- [ ] **Step 4: Commit**

```bash
cd apps/frontend
git add components/ProblemPanel.vue i18n/locales/en.json i18n/locales/de.json
git commit -m "feat(panel): Autor-/Firmen-Chip mit Icon + aria-label unterscheidbar (#30)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

# Phase B — Table Suche (#28, #32)

---

### Task B1: Backend — Relevanz-Score im Semantik-Modus ausliefern (#28)

**Files:**
- Modify: `apps/backend/routers/problems.py` (`ProblemRead` ~57–76, `_to_read` ~151–160, `_list_problems_semantic` ~703–719)
- Test: `apps/backend/tests/unit/test_problems_semantic.py` (erweitern)

**Interfaces:**
- Produces: `ProblemRead.score: Optional[float] = None`. Nur im Semantik-Branch gesetzt (`1 - cosine_distance`); sonst `None`/weggelassen. Cursor-Contract unverändert.

- [ ] **Step 1: Write the failing test**

```python
# apps/backend/tests/unit/test_problems_semantic.py
@pytest.mark.asyncio
async def test_semantic_items_carry_score(client, seed_embedded_problems, monkeypatch):
    # semantic-Suche liefert score = 1 - dist pro Item
    r = await client.get("/problems?semantic=datenleck")
    assert r.status_code == 200
    items = r.json()["items"]
    assert items, "expected semantic hits"
    assert all(it.get("score") is not None for it in items)
    assert all(0.0 <= it["score"] <= 1.0 for it in items)

@pytest.mark.asyncio
async def test_keyword_items_have_no_score(client, seed_problems):
    r = await client.get("/problems?q=test")
    assert r.status_code == 200
    assert all(it.get("score") is None for it in r.json()["items"])
```

(An die vorhandene Semantik-Test-Infrastruktur anpassen; Semantik-Tests sind teils `skipif`-on-sqlite — vgl. Phase-1 Task 1.7. Falls die pgvector-Distanz nur auf Postgres läuft, den Score-Assert analog `skipif` markieren und einen sqlite-tauglichen Pfad für den Keyword-`None`-Fall behalten.)

- [ ] **Step 2: Run to verify fail.** `/Volumes/DevLocal/DevWeb/Production/DecisionMap/apps/backend/.venv/bin/python -m pytest tests/unit/test_problems_semantic.py -q`.

- [ ] **Step 3: Implement.**
  1. `ProblemRead` Feld ergänzen: `score: Optional[float] = None`.
  2. `_to_read` um optionalen Parameter erweitern:

```python
def _to_read(p, tags, regions, *, score: float | None = None) -> ProblemRead:
    read = ProblemRead.model_validate(p)
    read.tags = tags
    read.regions = regions
    read.score = score
    return read
```

(An die tatsächliche `_to_read`-Implementierung anpassen — falls sie Felder einzeln setzt, `score` analog ergänzen.)
  3. Im Semantik-Branch (`_list_problems_semantic`, ~719) den Score aus `p._dist` durchreichen:

```python
items = [
    _to_read(p, tags_map.get(p.id, []), regions_map.get(p.id, []), score=1.0 - p._dist)
    for p in problems
]
```

Keyword-/Default-Branch ruft `_to_read` **ohne** `score` → bleibt `None`.

- [ ] **Step 4: Run to verify pass** + ruff.

- [ ] **Step 5: Commit**

```bash
cd apps/backend
git add routers/problems.py tests/unit/test_problems_semantic.py
git commit -m "feat(problems): Relevanz-Score (1-dist) in Semantik-Page-Items (#28)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task B2: Frontend — Relevanz-Badge + Modus-Label + Sort-Header-Deaktivierung (#28)

**Files:**
- Modify: `apps/frontend/composables/data/types.ts` (`Problem` + `BackendProblem`)
- Modify: `apps/frontend/composables/data/real/realProblems.ts` (`mapProblem`)
- Modify: `apps/frontend/pages/table.vue` (Badge, Label, Sort-Header)
- Modify: `apps/frontend/i18n/locales/en.json` + `de.json`
- Test: `apps/frontend/tests/components/...` bzw. composable-Spec für mapProblem

**Interfaces:**
- Consumes: `Problem.score?: number` (neu), `semanticSearchEnabled` (injected ref).

- [ ] **Step 1: Write the failing test** (mapProblem trägt score):

```ts
// in der bestehenden realProblems/mapProblem-Spec (oder tests/composables/realProblems.spec.ts)
it('mapProblem: übernimmt score aus dem Backend-Item', () => {
  const mapped = mapProblem({ /* ...minimal BackendProblem... */, score: 0.92 } as any)
  expect(mapped.score).toBe(0.92)
})
```

- [ ] **Step 2: Run to verify fail.** `cd apps/frontend && npx vitest run` (neuer Assert schlägt fehl).

- [ ] **Step 3: Implement types + mapping.**
  - `types.ts`: `Problem` um `score?: number` ergänzen.
  - `realProblems.ts`: `BackendProblem` um `score?: number`; `mapProblem` um `score: raw.score`.

- [ ] **Step 4: Badge + Label + Sort-Header in `table.vue`.**
  - i18n-Keys (`en.json` `"table"`): `"sortedByRelevance": "Sorted by relevance"`, `"relevanceTooltip": "Sorted by relevance in AI search"`, `"matchScore": "{n}% match"`. DE analog.
  - Modus-Label im Table-Header: `v-if="semanticSearchEnabled"` → `{{ t('table.sortedByRelevance') }}`.
  - Sort-Header deaktivieren bei Semantik: an den klickbaren Spalten-Headern `:class="{ 'opacity-40 pointer-events-none': semanticSearchEnabled }"` + `:title="semanticSearchEnabled ? t('table.relevanceTooltip') : ''"`.
  - Badge in der Titel-Zelle (nur Semantik + score gesetzt):

```vue
<span
  v-if="semanticSearchEnabled && problem.score != null"
  class="ml-2 inline-block px-1.5 py-0.5 rounded text-[10px] bg-th-accent/10 text-th-accent"
>
  {{ t('table.matchScore', { n: Math.round(problem.score * 100) }) }}
</span>
```

- [ ] **Step 5: Verify.** `cd apps/frontend && npx vitest run` grün; `npx eslint .` 0 neu. Optional FE-Spec: Badge nur sichtbar wenn `semanticSearchEnabled` true.

- [ ] **Step 6: Commit**

```bash
cd apps/frontend
git add composables/data/types.ts composables/data/real/realProblems.ts pages/table.vue i18n/locales/en.json i18n/locales/de.json
git commit -m "feat(table): Relevanz-Badge + 'nach Relevanz sortiert' + Sort-Header im Semantik-Modus deaktiviert (#28)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task B3: Backend + ai-service — cross-linguale Keyword-Symmetrie (Option B) (#32)

**Files:**
- Modify: `apps/backend/services/ai_client.py` (generischer `translate_query`)
- Modify: `apps/backend/routers/problems.py` (Keyword-OR-Klausel + q_de-Threading)
- Modify: `apps/backend/cursor.py` (q_de-Key + peek)
- Test: `apps/backend/tests/unit/test_problems_search.py` (erweitern)

**Interfaces:**
- Cursor wird um Key `"q2"` (q_de) erweitert — additiv, alte Cursor liefern `None`.
- `translate_query(text, target_lang)` ersetzt/ergänzt `translate_query_to_en`.

- [ ] **Step 1: Write the failing test** (Symmetrie):

```python
# apps/backend/tests/unit/test_problems_search.py
@pytest.mark.asyncio
async def test_keyword_search_symmetric_en_finds_de_only(client, seed_cross_lingual, monkeypatch):
    # seed: Problem nur deutsch ("Fehlender KI-Governance-Rahmen"), kein EN-Canonical
    # translate("missing"->de)="fehlend" (stub)
    r_en = await client.get("/problems?q=missing")
    r_de = await client.get("/problems?q=fehlend")
    assert r_en.status_code == 200 and r_de.status_code == 200
    ids_en = {it["id"] for it in r_en.json()["items"]}
    ids_de = {it["id"] for it in r_de.json()["items"]}
    assert ids_en == ids_de  # gleiche Konzept-Treffermenge
```

Translate-Aufrufe im Test stubben (monkeypatch auf `translate_query`), damit `missing→fehlend` / `fehlend→missing` deterministisch sind.

- [ ] **Step 2: Run to verify fail.**

- [ ] **Step 3: ai_client generisch.** In `ai_client.py`:

```python
async def translate_query(text: str, target_lang: str) -> str | None:
    """Best-effort Übersetzung einer Such-Query in target_lang (ISO 639-1)."""
    try:
        client = get_ai_client()
        r = await client.post("/translate", json={"text": text, "target_lang": target_lang})
        r.raise_for_status()
        return r.json().get("translated")
    except Exception as exc:
        logger.warning("translate_query_failed", error=str(exc), target=target_lang)
        return None
```

`translate_query_to_en` als dünnen Wrapper behalten (`return await translate_query(text, "en")`) für bestehende Aufrufer.

- [ ] **Step 4: Cursor q_de.** In `cursor.py` `encode_cursor`/`decode_cursor` um optionalen `q_de`-Parameter unter Key `"q2"` erweitern (analog `"q"`); `peek_cursor_q_de(cursor)` ergänzen (parallel zu `peek_cursor_q_en`).

- [ ] **Step 5: Keyword-Branch (Option B).** In `routers/problems.py`:
  - q_en + q_de auflösen (Seite 1) bzw. aus Cursor lesen:

```python
q_en: str | None = None
q_de: str | None = None
if q:
    if cursor:
        q_en = peek_cursor_q_en(cursor)
        q_de = peek_cursor_q_de(cursor)
    else:
        q_en = await translate_query(q, "en")
        q_de = await translate_query(q, "de")
```

  - OR-Klausel: **alle** Varianten (`q`, `q_en`, `q_de`) gegen **alle drei** Quellen (`title`, `description`, `cast(original_translations, Text)`):

```python
patterns = [p for p in (q, q_en, q_de) if p]
raw_clauses = []
for pat in patterns:
    like = f"%{pat}%"
    raw_clauses.extend([
        Problem.title.ilike(like),
        Problem.description.ilike(like),
        cast(Problem.original_translations, Text).ilike(like),
    ])
base_where.append(or_(*raw_clauses))
```

  - `next_cursor` für Keyword: `q_de` mitführen (Key `"q2"`).

- [ ] **Step 6: Run to verify pass** + ruff. Beachte: Übersetzungen **einmal** pro Such-Session (Seite 1), danach aus Cursor — kein Re-Call pro Seite (Assert: translate-Stub max. 2× aufgerufen über mehrere Seiten).

- [ ] **Step 7: Commit**

```bash
cd apps/backend
git add services/ai_client.py routers/problems.py cursor.py tests/unit/test_problems_search.py
git commit -m "feat(problems): cross-linguale Keyword-Symmetrie — q in DE+EN gegen alle Quellen (#32)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

# Phase C — Graph Drill-Down Overlap-Fix (#33)

---

### Task C1: Frontend — Node/Label-Overlap beim Drill-Down beseitigen (#33)

**Files:**
- Modify: `apps/frontend/components/ProblemGraph.vue` (`rerender` ~1709–1725, `buildGraphElements` ~280–409, Grid-/Mindmap-Layout-Pfade)

**Interfaces:** rein intern; kein Prop-/Emit-Vertrag ändert sich.

**Root Cause (aus Code-Analyse):** Neue Nodes aus `buildGraphElements()` haben kein `position` → starten bei (0,0). Nach `cy.elements().remove()` + `cy.add(...)` rendert Cytoscape einen Frame mit allen Nodes am Ursprung, bevor das (synchron laufende) `preset`-Layout die Positionen setzt → sichtbarer Stapel-Flash, bis User zoomt/pant. Badge-Nodes ebenso.

**Fix (höchste Hebelwirkung, ohne Parent-Vertrag):** (1) remove/add/layout in `rerender` in `cy.batch()` kapseln, damit kein Zwischenframe rendert; (2) bekannte Positionen direkt beim Add mitgeben.

- [ ] **Step 1: `rerender` batchen.** Die Sequenz in `rerender()` umschließen:

```ts
function rerender(): void {
  if (!cytoscapeInstance) return
  const cy = cytoscapeInstance
  cy.batch(() => {
    cy.style(buildStyle() as unknown as string)
    cy.elements().remove()
    cy.add(buildGraphElements())
  })
  if (tagFilterIds.value.length > 0) {
    applyTagFilters(false)
  } else {
    showMindmap(false)
  }
  if (props.selectedProblemId) {
    cy.getElementById(props.selectedProblemId).addClass('active-problem-node')
  }
}
```

`cy.batch()` unterdrückt Re-Render bis zum Ende des Callbacks; das nachfolgende `preset`-Layout (`animate:false`) setzt Positionen, bevor der nächste Frame zeichnet.

- [ ] **Step 2: Initiale Positionen beim Add.** In den Grid-/Mindmap-Pfaden werden die Positionen bereits berechnet (`buildProblemsGridPositions`/`buildMindmapPositions` → `positions`-Map, die der `preset`-Layout-`positions(node)`-Callback nutzt). Damit Nodes nie bei (0,0) erscheinen, beim `preset`-Layout `animate: false` für den Drill-Re-Render sicherstellen (ist bereits `false` in `rerender`-Pfad) **und** im `stop:`-Pfad `positionBadges()` direkt aufrufen (bereits vorhanden). Falls nach Step 1 noch ein Flash bleibt: in `buildGraphElements` für Nodes mit bekannter Position das `position`-Feld setzen — dazu die `positions`-Map als optionalen Parameter durchreichen:

```ts
function buildGraphElements(positions: Record<string, { x: number; y: number }> = {}): ElementDefinition[] {
  // ... beim Pushen jedes Node-Elements:
  // position: positions[nodeId] // wenn vorhanden
}
```

und in `rerender` die zuvor berechnete Positionsmap übergeben. (Step 1 allein behebt den Flash i.d.R. bereits; Step 2 nur ergänzen, falls der manuelle Live-Verify noch Stapel zeigt.)

- [ ] **Step 3: Verify.** `cd apps/frontend && npx vitest run` grün (Graph hat keinen Unit-Test — sicherstellen, dass keine Typfehler/Regressionen); `npx eslint components/ProblemGraph.vue` 0 neu. **Manueller Live-Verify (Pflicht, da kein Unit-Test):** Drill in einen Cluster → Nodes/Labels nie übereinander, kein Zoom/Pan nötig; Übersicht ↔ Drill ↔ Suche mehrfach durchspielen.

- [ ] **Step 4: Commit**

```bash
cd apps/frontend
git add components/ProblemGraph.vue
git commit -m "fix(graph): kein Node/Label-Overlap beim Drill-Down (cy.batch + initiale Positionen) (#33)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Phase C Done-Kriterium:** Beim Drill-Down sind Nodes/Labels nie gestapelt; Layout vor dem ersten sichtbaren Frame final; kein manuelles Zoom/Pan nötig.

---

## Self-Review

**Spec coverage** (jedes Ticket → Task):
- #31 URL-Filter (zentrale Map + Composable + zwei-Wege-Sync, `router.replace`, leere Filter raus) → A1 + A2 ✓
- #35 Multi-Value user/company → A3 (Backend IN/ILIKE-OR) + A3 Step 5 (Frontend sendet alle Chips) ✓
- #29 Firmenfeld editierbar (bereits vorhanden, dokumentiert) + sichtbarer Company-Filter + Registrierungsfeld → A4; company ILIKE → A3 ✓
- #30 Autor-/Firmen-Chip mit Icon + aria-label → A5 ✓
- #28 Relevanz-Score Backend + Badge/Label/Sort-Header-Deaktivierung → B1 + B2 ✓
- #32 cross-linguale Symmetrie (q in DE+EN gegen alle Quellen, beide im Cursor, einmalige Übersetzung) → B3 ✓
- #33 Graph-Overlap (cy.batch + initiale Positionen) → C1 ✓

**Type consistency:** `ProblemQuery`-Felder (A1/A2) = `types.ts`-Definition; `score` durchgängig `Optional[float]`/`score?: number` (B1/B2); Cursor-Keys `"q"`/`"q2"` konsistent (B3); `buildGraphElements`-Signatur in C1 abwärtskompatibel (Default-Param).

**Offene Annahmen für Implementer:** Fixture-/Conftest-Namen (A3/B1/B3) an vorhandene Tests anpassen; Semantik-Tests ggf. `skipif`-on-sqlite (B1/B3 — pgvector nur Postgres); Icon-Konvention in #30/#29 (Emoji vs. Icon-Komponente) per `grep` am Projektstil ausrichten; falls `searchQuery`/`semanticSearchEnabled` readonly injiziert sind, die URL→q-Hydration in A2 weglassen.

**Abhängigkeiten/Reihenfolge:** A1→A2 (Composable vor Sync); A3 vor/parallel A4 (ILIKE macht Freitext-Filter brauchbar); B1→B2 (Score-Feld vor Badge); Phasen A/B/C untereinander unabhängig.
