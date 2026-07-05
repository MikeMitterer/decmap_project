# Code-Konventionen und Beispiele

## Inhalt

- [Architekturprinzip: Trennung UI und Business Logic](#architekturprinzip-trennung-ui-und-business-logic)
- [Namenskonventionen](#namenskonventionen)
- [TypeScript — Typisierung](#typescript-typisierung)
- [Vue / Nuxt](#vue--nuxt)
- [Composables](#composables)
- [Python / FastAPI](#python-fastapi)
- [Workspace Scripts (scripts/)](#workspace-scripts-scripts)
- [Klassenstruktur](#klassenstruktur)
- [Testbarkeit](#testbarkeit)
- [Dokumentation](#dokumentation)
- [Fehlerbehandlung](#fehlerbehandlung)
- [Logging](#logging)
- [Datenbank-Zugriff (KI-Service)](#datenbank-zugriff-ki-service)
- [Testing](#testing)

---

## Architekturprinzip: Trennung UI und Business Logic

**Frontend:** Komponenten = nur Darstellung. Business Logic, Datentransformation, API-Kommunikation → Composables.
**Backend:** Router = nur HTTP-Belange. Business Logic → Services. Services haben keine Kenntnis von HTTP.

[↑ Inhalt](#inhalt)

---

## Namenskonventionen

### TypeScript / Vue

| Element | Stil | Beispiel |
|---|---|---|
| Dateien | `camelCase` | `problemForm.vue`, `useProblems.ts` |
| Komponenten | `PascalCase` | `ProblemForm`, `ProblemGraph` |
| Composables | `camelCase` + `use`-Prafix | `useProblems`, `useVoting` |
| Variablen/Funktionen | `camelCase`, sprechend | `clusterLabel`, `fetchApprovedProblems()` |
| Loop-Variablen | sprechend, kein `i/j/x` | `problem`, `clusterNode`, `voteEntry` |
| Konstanten | `SCREAMING_SNAKE_CASE` | `MAX_PROBLEM_LENGTH` |
| Types/Interfaces | `PascalCase` | `Problem`, `ClusterNode` |
| Enums | `PascalCase` Name, `SCREAMING_SNAKE_CASE` Werte | `ProblemStatus.NEEDS_REVIEW` |

```typescript
// richtig
for (const problem of problems) { ... }
problems.forEach((problem) => { ... })
clusterNodes.map((clusterNode) => clusterNode.label)

// falsch
for (let i = 0; i < problems.length; i++) { ... }
problems.forEach((p) => { ... })
```

### Python

| Element | Stil | Beispiel |
|---|---|---|
| Dateien/Module | `snake_case` | `spam_filter.py` |
| Funktionen/Variablen | `snake_case`, sprechend | `generate_embedding()` |
| Loop-Variablen | sprechend | `problem`, `cluster_node` |
| Klassen | `PascalCase` | `EmbeddingService` |
| Konstanten | `SCREAMING_SNAKE_CASE` | `EMBEDDING_MODEL` |
| Type Hints | immer | — |

```python
# richtig
for problem in problems: ...
approved = [problem for problem in problems if problem.status == ProblemStatus.APPROVED]

# falsch
for p in problems: ...
result = [x for x in problems if x.status == "approved"]
```

### Bash / Shell-Scripts

| Element | Stil | Beispiel |
|---|---|---|
| Funktionen | `camelCase` | `doBackup()`, `printRepoRow()`, `checkService()` |
| Lokale Variablen | `snake_case` | `local dump_file`, `local repo_path` |
| Globale Konstanten | `SCREAMING_SNAKE_CASE` | `BACKUP_DIR`, `POSTGRES_SERVICE` |
| Skript-Dateien | `kebab-case` | `db-backup.sh`, `repo-status.sh` |

### Datenbank

- Tabellen: `snake_case`, Plural fur Lookup — `problems`, `tags`, `regions`
- Junction-Tabellen: `snake_case`, Singular — `tag`, `region` ~~`problem_cluster`~~ *(gedroppt Migration 005)*
- Spalten: `snake_case` — `cluster_id`, `vote_score`, `created_at`
- Fremdschlussel: `{tabelle_singular}_id` — `problem_id`, `user_id`

[↑ Inhalt](#inhalt)

---

## TypeScript — Typisierung

- Strict Mode immer aktiv
- Kein `any` — bei unbekanntem Typ `unknown`
- Explizite Ruckgabetypen bei allen Funktionen
- Interfaces fur Objektstrukturen, Type Aliases fur Unions
- Keine Non-null Assertions (`!`) — null explizit behandeln
- Enums fur feste Wertesets — keine Magic Strings

```typescript
interface Problem {
  id: string
  title: string
  status: ProblemStatus
  voteScore: number
}

enum ProblemStatus {
  PENDING = 'pending',
  NEEDS_REVIEW = 'needs_review',
  APPROVED = 'approved',
  REJECTED = 'rejected'
}

async function fetchApprovedProblems(): Promise<Problem[]> {
  const problems = await backendFetch<Problem[]>('/problems?status=approved')
  return problems ?? []
}
```

[↑ Inhalt](#inhalt)

---

## Vue / Nuxt

- Ausschliesslich Composition API — keine Options API
- `<script setup lang="ts">` immer
- Keine direkten API-Aufrufe in Komponenten — alle Datenzugriffe uber Composables
- Props und Emits immer typisiert

**Gotcha — `v-if`/`v-else-if`/`v-else`-Kette darf nicht unterbrochen werden:**
Ein neues `v-if` auf einem Element innerhalb einer laufenden Kette bricht die Kette auf. Alle nachfolgenden `v-else-if`/`v-else` beziehen sich dann auf das innere `v-if` — nicht auf das aeussere. Symptom: Branches werden nie oder immer gerendert.

```vue
<!-- falsch — Toolbar-v-if unterbricht die loading/error/content-Kette -->
<div v-if="loading">...</div>
<div v-else-if="error">...</div>
<div v-if="!loading && !error">  <!-- neue Kette! -->
  <Toolbar />
</div>
<div v-else-if="activeTab === 'queue'">...</div>  <!-- bezieht sich auf inneres v-if -->

<!-- richtig — alles innerhalb eines v-else -->
<div v-if="loading">...</div>
<div v-else-if="error">...</div>
<div v-else>
  <Toolbar />  <!-- immer sichtbar wenn Daten geladen -->
  <div v-if="activeTab === 'queue'">...</div>
  <div v-else>...</div>
</div>
```

```vue
<script setup lang="ts">
const props = defineProps<{
  problemId: string
  showVoting?: boolean
}>()

const emit = defineEmits<{
  (event: 'submitted', problemId: string): void
}>()
</script>
```

[↑ Inhalt](#inhalt)

---

## Composables

Alle Backend-Kommunikation und Business Logic in Composables. Keine Ausnahmen.

```typescript
export function useProblems() {
  const problems = ref<Problem[]>([])
  const loading = ref<boolean>(false)
  const error = ref<string | null>(null)

  async function fetchApprovedProblems(): Promise<void> {
    loading.value = true
    error.value = null
    try {
      problems.value = await backendFetch<Problem[]>('/problems?status=approved') ?? []
    } catch (fetchError) {
      error.value = 'Probleme konnten nicht geladen werden'
    } finally {
      loading.value = false
    }
  }

  return { problems, loading, error, fetchApprovedProblems }
}
```

[↑ Inhalt](#inhalt)

---

## Python / FastAPI

- Type Hints uberall
- Pydantic-Modelle fur alle Request/Response-Schemas
- Router = ein pro Fachbereich, nur HTTP-Belange
- Services = Business Logic
- Keine Business Logic in `main.py`

```python
# richtig — Logik im Service
@router.post("/filter")
async def filter_problem(payload: ProblemPayload) -> FilterResult:
    return spam_filter.evaluate(payload.text)
```

**Background Tasks — eigene DB-Connection:**
Request-scoped Connections sind geschlossen, bevor Background Tasks laufen.
Jeder Background Task oeffnet deshalb seine eigene `psycopg.AsyncConnection`.

```python
# falsch — Connection aus Request-Scope ist beim Task-Start geschlossen
async def my_task(conn: AsyncConnection) -> None:
    await conn.execute(...)

# richtig — Task oeffnet eigene Connection
async def my_task(postgres_url: str) -> None:
    async with await psycopg.AsyncConnection.connect(postgres_url) as conn:
        await conn.execute(...)
```

**CORS:**
`allow_credentials=True` ist mit `allow_origins=["*"]` browser-invalid.
Konfigurierbarer Origin aus Settings, `allow_credentials=False`.

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,  # aus .env, nie "*" mit credentials
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Webhook-Security:**
Alle Hook-Endpoints verwenden `_verify_service_token()` als Dependency.
Leeres `SERVICE_TOKEN` = Dev-Mode (kein Check). Niemals Secrets in Code hardcoden.

```python
async def _verify_service_token(
    x_service_token: str | None = Header(None),
    settings: Settings = Depends(get_settings),
) -> None:
    if settings.service_token and x_service_token != settings.service_token:
        raise HTTPException(status_code=403)

@router.post("/hooks/problem-submitted", dependencies=[Depends(_verify_service_token)])
async def on_problem_submitted(...): ...
```

**Modul-Level-Imports fur Testbarkeit:**
Optionale Dependencies (z.B. `hdbscan`) auf Modul-Level importieren, nicht lokal in Funktionen.
Nur so kann `patch("module.hdbscan")` in Tests greifen.

```python
# richtig
import hdbscan  # Modul-Level — patchbar in Tests

# falsch
def cluster(...):
    import hdbscan  # lokaler Import — patch() greift nicht
```

[↑ Inhalt](#inhalt)

---

## Workspace Scripts (scripts/)

Alle Skripte in `scripts/` — Bash und Python — folgen derselben CLI-Konvention:

- Kein Argument → Help anzeigen (`exit 0`)
- `-h | --help` → Help anzeigen (`exit 0`)
- Aktions-Flags explizit angeben (z.B. `--generate`, `--show`)
- `APPNAME` aus dem Dateinamen ableiten — nie hardcoden

**Python-Scripts:**

```python
APPNAME = Path(__file__).name   # aus Dateiname, nicht hardcodiert

class Colors:
    YELLOW     = "\033[38;5;11m"   # angelehnt an BashLib colors.lib.sh
    GREEN      = "\033[38;5;10m"
    CYAN       = "\033[38;5;51m"
    LIGHT_BLUE = "\033[38;5;45m"
    BLUE       = "\033[38;5;33m"
    RED        = "\033[38;5;196m"
    BOLD       = "\033[1m"
    RESET      = "\033[0m"

def usage() -> None:
    print(f"\nUsage: {APPNAME} [ options ]\n")
    usage_line("-g | --generate", "...")
    usage_line("-h | --help",     "Diese Hilfe anzeigen")
    print(f"\n{Colors.LIGHT_BLUE}Hints:{Colors.RESET}")
    print(f"    {Colors.GREEN}{APPNAME} --generate{Colors.RESET}")
    print()

def main() -> None:
    if len(sys.argv) == 1 or sys.argv[1] in ("-h", "--help"):
        usage(); sys.exit(0)
    args = parse_args(sys.argv[1:])
    ...

# argparse nur zum Parsen — add_help=False, eigene usage() statt argparse-Help
parser = argparse.ArgumentParser(add_help=False)
```

**Bash-Scripts:** BashLib `usageLine()` und `colors.lib.sh` verwenden; gleicher Aufbau.

`set -eou pipefail` ist Mindeststandard für alle Bash-Scripts.

Kritische Gotchas (Details: `/code-standards`):
- **Lib-Funktionen geben keine Ausgaben** — nur differenzierte Exit-Codes (2, 3, …); Fehlermeldungen gehören in den Aufrufer.
- **`readonly VAR="$(cmd)"`** gibt immer Exit-Code 0 — `|| exit 1` dahinter triggert nie. Stattdessen: `VAR="$(cmd)" || _rc=$?` dann `readonly VAR`.

[↑ Inhalt](#inhalt)

---

## Klassenstruktur

Einheitliche Reihenfolge: 1. Konstruktor 2. Public-Methoden 3. Private-Methoden

```typescript
class ClusteringService {
  private readonly cytoscapeInstance: cytoscape.Core
  constructor(container: HTMLElement) { ... }
  // public zuerst
  renderClusters(clusters: ClusterNode[]): void { ... }
  // private danach
  private buildGraphElements(clusters: ClusterNode[]): cytoscape.ElementDefinition[] { ... }
}
```

```python
class SpamFilter:
    def __init__(self, openai_client: OpenAIClient) -> None: ...
    def evaluate(self, text: str) -> FilterResult: ...      # public
    def _build_prompt(self, text: str) -> str: ...           # private
```

[↑ Inhalt](#inhalt)

---

## Testbarkeit

**Dependency Injection** — Abhangigkeiten injizieren, nicht intern instanziieren.

```python
# richtig
class EmbeddingService:
    def __init__(self, openai_client: OpenAIClient) -> None:
        self._openai_client = openai_client

# falsch
class EmbeddingService:
    def __init__(self) -> None:
        self._openai_client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
```

```typescript
// richtig
export function useVoting(apiClient: BackendClient = defaultClient) { ... }
```

- Funktionen klein und fokussiert — eine Sache pro Funktion
- Seiteneffekte isolieren — reine Transformationslogik von I/O trennen

[↑ Inhalt](#inhalt)

---

## Dokumentation

- Offentliche Funktionen/Klassen: immer kurzer Docstring
- Interne Hilfsfunktionen: nur wenn nicht selbsterklarend
- Keine Docstrings fur Boilerplate

**Python:** Google-Style Docstrings
```python
def generate_embedding(text: str) -> list[float]:
    """Embedding-Vektor fur den ubergebenen Text generieren.

    Args:
        text: Rohe Problembeschreibung fur das Embedding.
    Returns:
        Liste von Floats als Embedding-Vektor.
    Raises:
        EmbeddingError: Wenn der OpenAI API-Aufruf fehlschlagt.
    """
```

**TypeScript:** JSDoc, einzeilig wenn ausreichend
```typescript
/** Alle freigegebenen Probleme aus dem Backend laden. */
async function fetchApprovedProblems(): Promise<Problem[]>
```

[↑ Inhalt](#inhalt)

---

## Fehlerbehandlung

- Fehler nie stillschweigend schlucken
- Mit Kontext loggen — `consola` (Frontend) / `structlog` (Backend)
- Benutzer-Fehlermeldungen: generisch, keine internen Details
- Alle async-Operationen in try/catch

[↑ Inhalt](#inhalt)

---

## Logging

### Frontend — `consola`

Kein `console.log` im eingecheckten Code — immer `consola`.

```typescript
import { consola } from 'consola'
consola.info('Probleme geladen', { count: problems.length })
consola.error('Embedding fehlgeschlagen', { problemId, error })
```

### Backend — `structlog`

Kein natives `logging` — immer `structlog`.

```python
import structlog
logger = structlog.get_logger()
logger.info("embedding_generated", problem_id=problem_id, duration_ms=duration)
```

[↑ Inhalt](#inhalt)

---

## Datenbank-Zugriff (KI-Service)

`psycopg3` + Repository Pattern — kein ORM. Kein Raw-SQL ausserhalb der Repository-Schicht.

```python
class ProblemRepository:
    def __init__(self, connection: AsyncConnection) -> None:
        self.connection = connection

    async def find_approved(self) -> list[Problem]:
        async with self.connection.cursor(row_factory=class_row(Problem)) as cursor:
            await cursor.execute("SELECT * FROM problems WHERE status = %s", (ProblemStatus.APPROVED,))
            return await cursor.fetchall()
```

[↑ Inhalt](#inhalt)

---

## Testing

### Frontend (Vitest)

- Unit-Tests nur fur Composables — keine UI-Tests vorerst
- Alle Backend-API-Aufrufe mocken
- Testdatei spiegelt Quelle: `composables/useProblems.ts` → `tests/composables/useProblems.spec.ts`
- `vi.mock()` muss **vor** den Imports stehen — Vitest hoisted Mocks nicht automatisch wenn Imports davor kommen

### Contract-Tests (Fake → Real)

Jede Fake-Implementierung braucht Contract-Tests, die beim Umstieg auf Real-Data direkt wiederverwendet werden koennen.

```typescript
// tests/composables/useProblems.contract.spec.ts
// Dieselben Tests laufen gegen Fake- UND Real-Implementierung
describe.each([
  ['fake', useFakeProblems],
  ['real', useRealProblems],
])('%s implementation', (_, useImpl) => {
  it('liefert ein Array von Problems', async () => {
    const { problems } = useImpl()
    await nextTick()
    expect(Array.isArray(problems.value)).toBe(true)
  })
})
```

Ziel: Wenn `USE_FAKE_DATA=false` gesetzt wird, fallen keine neuen Tests noetig — die Contract-Tests greifen.

**Implementiert fuer:** `useAuth`, `useProblems`, `useVoting`, `useSimilarity`, `useSolutions`, `useTags`, `useClusters`, `useRegions`
(`tests/composables/*.contract.spec.ts` — je mit `describe.each` gegen Fake und Real)

Hinweis: `useRegionDetection` (Browser Geolocation API) hat noch keinen Contract-Test — `navigator.geolocation`-Mocking in Vitest ist nicht-trivial. Als bekannte Luecke dokumentiert, kein Blocker.

**Vitest-Konfiguration:** `vitest.config.ts` schliesst nur `backendClient.ts` aus Coverage aus —
der gesamte Real-Layer (auth, problems, voting, similarity, tags, solutions, clusters) wird gemessen.
`tests/setup.ts` stellt `useRuntimeConfig`-Stub und `import.meta.client = true` bereit.

**Test-Umgebung (Env-Variablen):**
Prioritaetskette: Shell/Jenkins-Env → `.env.test.local` → `.env.test` → Hardcoded-Fallback.
`.env.test` ist committed (sichere Defaults fuer lokale Entwicklung); `.env.test.local` bleibt gitignored.
`vitest.config.ts` laedt `.env.test` via `loadEnv`, respektiert bereits gesetzte `process.env`.
`tests/setup.ts` liest alle URLs/Schwellenwerte aus `process.env` — keine hardcodierten Strings.
Jenkins: Env-Variablen im Build-Job setzen (`BACKEND_URL`, `WS_URL`, `SIMILARITY_THRESHOLD`) —
sie ueberschreiben automatisch die `.env.test`-Defaults, ohne dass eine Datei noetig waere.

**Konkreter Fund 1:** `realVoting.ts` hatte keinen Duplicate-Vote-Guard — ein zweiter Vote
lieferte einen Delta statt 0. Der Contract-Test hat das aufgedeckt; die Implementierung wurde
vor dem Merge korrigiert.

**Konkreter Fund 2:** `useSimilarity.ts` hatte `try/finally` ohne `catch` — unhandled Promise
rejection wenn der Data-Layer wirft. Aufgedeckt beim Schreiben von Verhaltens-Tests; `catch` ergaenzt
(loggt Warnung, setzt State leer).

**Konkreter Fund 3:** `useLogin.ts` pruefte Backend-Fehlermeldungen nicht prazise genug —
"email already taken" wurde nicht als `login.errorEmailTaken` erkannt. Fix: HTTP-Status pruefen
(422 = Validierungsfehler, `detail`-Feld auswerten). Fallback zeigt `error.message` direkt statt
immer "Something went wrong".

**Konkreter Fund 4:** `useLogin.ts` (`verify-email`-Pfad) — fastapi-users gibt **204** zurueck.
Kein Response-Body — nur `response.ok` pruefen, nicht parsen.
I18n-Fallout: `login.loading` existierte nicht — Composable nutzt jetzt `login.verifying`.

**Konkreter Fund 5:** `default.vue` Layout — Auth-Token-Race-Condition.
`loadPersistedTokens()` war in `onMounted` — damit war der Token noch nicht gesetzt, wenn `index.vue`'s
`onMounted` (z.B. `fetchTags()`) lief und 403 zurueckbekam. Fix: `loadPersistedTokens()` synchron im
`setup()`-Block aufrufen; `restoreSession()` (API-Aufruf) bleibt in `onMounted`. Reihenfolge:
`setup()` → Token aus localStorage → `onMounted` fetchTags (Token vorhanden) → `onMounted` restoreSession.

**Konkreter Fund 6:** `realProblems.ts` — Internal-API Tag-Naming (`label` vs. `name`).
Backend-API gibt Tags mit Feld `label` zurueck (nicht `name` wie in DB-Spalte). Contract-Test deckte auf, dass `mapProblem` `tag.name` las — gibt `undefined`. Fix: `tag.label` verwenden. Gilt fuer alle `/internal/tags`-Endpoints.

**Konkreter Fund 7:** `useServiceStatus.ts` — URL-Detection-Logik und `fetchJson`.
Composable unterscheidet Backend (:8001) von AI-Service (/api/health) per URL-String-Pattern. `fetchJson()` prueft `res.ok` vor dem Parsen — Mock ohne `ok: true` gibt `null` zurueck (kein Parse-Fehler). Contract-Test deckte auf: Mocks benoetigen `ok: true, status: 200`.

**Konkreter Fund 8:** `default.vue` Layout — `localStorage`-Zugriff auf SSR-Routen.
`default.vue` ist das gemeinsame Layout fuer SPA- und SSR-Routen (`/problem/**`, `/cluster/**`).
`localStorage`-Zugriff ausserhalb von `onMounted` → `ReferenceError: localStorage is not defined` beim serverseitigen Rendering.
Fix: `if (import.meta.client) { ... localStorage ... }` als Guard; `onMounted` ist implizit client-seitig — dort kein Guard noetig.
Betrifft alle Nuxt-Layouts die als Wrapper fuer Hybrid-Routen (SPA + prerender) dienen.

**Konkreter Fund 9:** Buttons ohne `type`-Attribut submitten als Form-Submit.
HTML-Default fuer `<button>` ist `type="submit"`. Buttons in Layouts, Panels und Komponenten ohne explizites `type="button"` loesen versehentlich Form-Submits aus.
Fix: Alle UI-Buttons explizit `type="button"` setzen — ausser bei echten Submit-Buttons in Formularen.
Betroffen waren z.B. Dark-Mode-Toggle, Logout-Button, Panel-Close, Breadcrumb-Segmente.

**Konkreter Fund 10:** `useVoting.contract.spec.ts` — `test_vote_flip_direction`. Contract-Test assertierte `vote_score = -1` fuer Flip-down bei Score 1 (altes Verhalten ohne Floor). Mit dem implementierten Floor (`CASE WHEN score > 0 THEN score - 1 ELSE 0`) ist der korrekte Wert `0` — kein negativer Score, kein Vote-Row bei Downvote auf 0. Race-Condition-Analyse (PostgreSQL READ COMMITTED): SQL-CASE-WHEN-Floor ist atomar und sicher. Contract-Test verhindert Silent Regression bei zukuenftigem Umbau der Vote-Logik — falsche Assertion wurde vom Reviewer gefunden, bevor der Code in `master` landete.

**Konkreter Fund 11:** `useRegions.ts` — Facade + `_inflight`-Race-Condition-Fix.
Direkter Import von `realRegions` in Komponenten verhinderte den `USE_FAKE_DATA`-Switch.
Fix: `useRegions.ts`-Facade (`useRegionsFetch()`) als einziger Einstiegspunkt — Komponenten importieren nur die Facade.
Zusaetzlich: `_inflight`-Promise-Cache verhindert parallele Requests wenn mehrere Komponenten gleichzeitig mounten.
Pattern: `if (_inflight) return _inflight; _inflight = fetch(...).finally(() => { _inflight = null })`.
Hardcodierte Gruppen-Labels (`DACH/World`) durch `t('form.regionsGroupDE/AT/CH/World')` ersetzt (i18n-Keys in `en.json`).

**Konkreter Fund 12:** `pages/index.vue` — `hasActiveFilters`-Computed mit Strict-Null-Check.
`route.query.problem` ist `string | undefined` (nicht `string | null`) — fehlt der Query-Parameter, ist der Wert `undefined`. `default.vue` reicht den daraus initialisierten Ref via `provide/inject` weiter; bestimmte Init-Pfade liefern `undefined` statt `null`. Die Computed nutzte `focusProblemId.value !== null` — `undefined !== null` ist `true`, also rendert der Filter-Row-Wrapper (`min-h-[45px] border-b border-th-border`), obwohl die inneren Chips per truthy-`v-if="focusProblemId"` allesamt leer bleiben. Effekt: leere 45px-Box mit Bottom-Border direkt unter der TopBar — ein sichtbarer horizontaler Strich im Graph-View. Fix: Truthy-Check (`!!focusProblemId.value`) — konsistent zum Pattern der inneren `v-if`s. `pages/table.vue` machte es bereits richtig. Regel: in Computed/Watch ueber `route.query.*`-abgeleitete Refs nie strict gegen `null` vergleichen — `??`-Defaults und Truthy-Checks bevorzugen.

**Konkreter Fund 13:** `ProblemGraph.vue` — Radial-Layout Collision-Avoidance via Arc-Length-Constraint.
`depthRadius(depth)` liefert nur einen festen Tiefen-Radius — bei vielen Geschwistern (z.B. 5 Sub-Cluster auf ~60° Arc) sind die Pro-Kind-Slots zu eng, und beim `cy.fit()` rendern Labels wie *"Strategic Execution"* / *"Strategy & Operations"* übereinander. Fix: zusätzliche `minRadius`-Berechnung pro Subtree, dann grösseren Radius nehmen:
`minRadius = nodeSpacing × N / span`  →  `radius = max(depthRadius(depth), minRadius)`.
Mathematisch: Arc-Länge zwischen Geschwistern ist `r × (span/N)` — muss `≥ nodeSpacing` sein, sonst überlappen die Bounding-Circles. `nodeSpacing` ist theme- + locale-aware: Glass-Cluster (200px breit EN / 250px DE) brauchen mehr Luft als Legacy (170px); deutsche Labels bekommen +25% Breite. Cytoscape `fit()` zoomt das gesamte Layout auf den Viewport — der grössere relative Radius bleibt kollisionsfrei, auch wenn der Endzoom kleiner ausfällt. Regel: bei radialen Layouts immer beide Constraints (Tiefen-Radius UND Geschwister-Dichte) berücksichtigen, sonst rendern dichte Sub-Bäume korrupt.

**Konkreter Fund 14:** `ProblemGraph.vue` — Decoration-Badges folgen Drag-Bewegungen via `position`-Event, User-Positionen in localStorage persistiert.
Decoration-Nodes (cluster-dot, cluster-count-badge, vote-score-badge, solution-badge, search-badge) sind eigenständige Cytoscape-Nodes — keine Kinder im Cytoscape-Sinne. `positionBadges()` läuft nur am Layout-Ende; beim manuellen Drag der Parent-Pille blieben die Badges früher an ihrer alten Position stehen. Fix: `cy.on('position', '<parent-selector>', cb)` feuert kontinuierlich während des Drags (mouse-move) — Callback `repositionBadgesFor(parent)` sucht alle Decoration-Kinder über `cy.getElementById('<prefix>-<parentId>')` und positioniert sie relativ zur aktuellen Parent-Position. Selektor muss alle ziehbaren Parent-Klassen aufzählen (`.inner-cluster-node, .leaf-cluster-node, .root-node, .unclustered-node, .problem-node`), nicht `'node'` — sonst feuert das Event auch für die Decoration-Badges selbst und löst Endlosschleifen aus.
Position-Persistence: `cy.on('dragfree', 'node', saveCurrentPositions)` schreibt nach jedem Drag-Release alle aktuellen Node-Positionen als JSON-Map (`{id: {x,y}}`) in `localStorage['graph-node-positions']`. `applyStoredPositions()` läuft am Ende **jedes** Layouts (showMindmap/applyTagFilters/showUnclusteredView) — überschreibt die algorithmischen Positionen nur für IDs die in der Map existieren; neue Nodes (z.B. nach Clustering-Update) behalten ihre Default-Position aus dem Layout-Algorithmus. Reset-Button (4. Button rechts unten neben den Zoom-Controls, i18n-Key `graph.resetPositions`) ruft `resetPositions()` auf: entfernt den localStorage-Key und re-runt das aktive Layout (`showMindmap` ohne Filter / `showUnclusteredView` bei Unclustered-Filter / `applyTagFilters` bei Tag-Filter) — `applyStoredPositions()` findet danach keine Overrides → algorithmische Positionen wirken. Regel: für persistierte User-Interaktionen in Cytoscape immer Storage-write am `dragfree`/`dragfreeon`-Event (nicht `position` — feuert tausendmal pro Drag) und Storage-read **nach** dem Layout-Run (`stop:`-Callback, nicht davor — sonst überschreibt das Layout die wiederhergestellten Positionen).

**Konkreter Fund 15:** `ProblemGraph.vue` — Viewport-Persistence (Zoom + Pan) mit Debounce; `centerOnRoot()` als Restore-or-Default.
Position-Persistence aus Fund 14 deckt nur die Node-Positionen — Zoom-Level und Pan gehen beim Reload verloren. Naheliegende Lösung: `cy.on('zoom', save)` + `cy.on('pan', save)` separat. Problem: beide Events feuern in jedem Render-Tick (1× pro Mouse-Wheel-Tick, ≥60× pro Sekunde während Pan-Drag) → localStorage-Writes thrashen.
Fix: kombiniertes `cy.on('viewport', cb)`-Event (deckt Zoom **und** Pan ab) mit 400ms-Debounce via `setTimeout` + `clearTimeout`-Reset — erst nach 400ms Stillstand schreibt `saveCurrentViewport()` den `{zoom, pan: {x, y}}`-Snapshot in `localStorage['graph-viewport-mindmap']`. Guard: Save nur wenn `viewLevel === 'mindmap'` — Drill-Views nutzen `fit:true` und dürfen den globalen Viewport nicht überschreiben.
Restore-or-Default in `centerOnRoot()`: vorher nur `cy.zoom(1) + cy.center(root)`; neu zuerst `loadStoredViewport()`-Probe — bei Hit `cy.zoom(saved.zoom) + cy.pan(saved.pan)` (exakte Wiederherstellung inkl. Pan-Offset), sonst Default-State. Reset-Button löscht **beide** Keys (`graph-node-positions` + `graph-viewport-mindmap`) und re-runt das aktive Layout. Regel: für persistierte Viewport-States in Cytoscape immer das kombinierte `viewport`-Event statt `zoom`/`pan` einzeln verwenden, Writes debouncen (≥300ms), und Restore in der Layout-`stop:`-Callback durchführen — sonst überschreibt der erste Render-Tick die wiederhergestellten Werte.

**Konkreter Fund 16:** `utils/tagColor.ts` — deterministische Per-Cluster-Farbe als View-übergreifende Identität.
Cluster-Visualisierung war an zwei Stellen inkonsistent: Graph-Dot rendert einen warmen Gradient (alle Cluster gleich), Tabellen-Chip nutzte statisches `bg-blue-50 text-blue-700` (alle Cluster blau). Effekt: derselbe Cluster sah im Graph anders aus als in der Tabelle, und benachbarte Cluster im Graph waren visuell ununterscheidbar. Naheliegende Lösung: pro Cluster ein Custom-Field in der DB. Problem: Tags entstehen automatisch durch HDBSCAN-Clustering — kein User-Edit-Pfad für eine Farbe, und neue Cluster nach Re-Clustering hätten keine.
Fix: deterministischer Hash über `tag.id` (UUID-String) → Index in eine kuratierte 12-Farben-Palette (Sunset Orange, Sky Cyan, Emerald, Violet, Pink, Amber, Blue, Lavender, Rose, Green, Teal, Magenta — bewusst kontrastierende Hues, lesbar auf Glass-Dark **und** Glass-Light). Hash: `hash = ((hash * 31) + charCode) | 0` über alle Zeichen — stabil über Reloads, stabil über Re-Clustering solange die Tag-ID gleich bleibt. `ProblemGraph.vue` setzt die Farbe via Cytoscape data-mapper (`'background-color': 'data(color)'` auf `.cluster-dot`, Dot von 8×8 auf 10×10 vergrößert weil solide Farbe weniger Präsenz hat als Gradient). `pages/table.vue` setzt **nur** den Dot in der Cluster-Farbe — Text und Background bleiben neutral (Glass: `text-th-text-muted` / `bg-white/5`; Legacy: `text-blue-700` / `bg-blue-50`), kein farbiger Border. Erste Iteration färbte Text + 20%-Alpha-Border + Dot — wirkte zu unruhig auf Listen mit ≥10 verschiedenen Clustern; User-Entscheidung: Dot allein trägt die Identität, Chip selbst bleibt zurückhaltend. Kein Storage, kein State — die Identitätsfarbe ist eine reine Funktion der Tag-ID.
Trade-off: bei >12 Clustern wiederholen sich Farben — akzeptabel, weil die Wahrscheinlichkeit von zwei sichtbar-benachbarten Clustern mit derselben Farbe gering ist und HDBSCAN bei diesem Projekt typisch 5–12 L1-Cluster liefert. Regel: View-übergreifende visuelle Identität für auto-generierte Entitäten (Cluster, Auto-Tags) immer deterministisch aus der ID ableiten — keine DB-Spalte, kein State. Funktion muss von **allen** Views importiert werden, nicht pro View neu implementiert (sonst driften die Paletten und derselbe Cluster bekommt zwei Farben). Dosierung der Farbintensität ist eine separate Designentscheidung pro View — die Funktion liefert die Farbe, jeder Konsument entscheidet, wo sie aufgetragen wird (Graph: Dot 10×10; Tabelle: Dot 6×6 + neutrale Pille). **Nachtrag (2026-06-29):** `tagColor(tagId)` ist auf ein generisches `colorFromString(key)` DRY-refactored (`tagColor` delegiert nur noch); so zieht auch die Firmen-Monogramm-Badge der Table (`utils/companyBadge.ts` → `companyColor`, gekeyt am lowercase-getrimmten Firmennamen) dieselbe Palette deterministisch, ohne das Hash→Palette-Schema zu duplizieren.

**Konkreter Fund 17:** `SolutionList.vue` — Markdown-Preview via `stripMarkdown()` + Tailwind `line-clamp-2` statt harter Zeichen-Grenze.
Frühere Headline-Logik nutzte einen hardcodierten Char-Slice (`content.slice(0, 100) + '…'`). Probleme: (1) Truncation ignoriert die tatsächliche Render-Breite — bei schmalem Panel brechen 100 Zeichen in 4+ Zeilen, bei breitem Panel passen 100 Zeichen kaum in eine Zeile, der `…`-Indikator verschwendet Platz. (2) Markdown-Marker (`**bold**`, `[label](url)`) zählen mit ins Limit — der User sieht abgeschnittene Linksyntax statt mehr Text. Fix: zweistufig — zuerst `stripMarkdown(content)` entfernt nur die Formatierungs-Marker (`.replace(/\*\*/g, '')`, `.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')`) und liefert reinen Plaintext; dann übernimmt CSS via Tailwind `line-clamp-2` (`-webkit-line-clamp: 2; display: -webkit-box; -webkit-box-orient: vertical; overflow: hidden`) die Trunkierung basierend auf der tatsächlichen Element-Breite. Voll-Markdown-Rendering bleibt unverändert auf `SolutionDetail.vue` und `SolutionForm.vue`-Preview-Tab (gemeinsame `renderSolutionMarkdown`-Funktion). Regel: für mehrzeilige Previews von Markdown-Content immer Marker entfernen (kein Render, kein DOMPurify nötig — reiner Text-Strip) und CSS-Clamp den Cut-Off bestimmen lassen — nie `slice(0, N)` mit hardcodierter Länge. Pattern überträgt sich auf jede Card/List-Komponente, die Markdown-Felder als Vorschau zeigt.

**Konkreter Fund 18:** Brand-Gradient (`var(--dm-grad)`) vs. Accent (`rgb(var(--th-accent))`) — eindeutige Trennung.
Frühere Bold-Redesign-Iteration färbte mehrere CTAs gleichzeitig mit `var(--dm-grad)`: TopBar-„+ Problem erfassen", SolutionList-„+ Lösung hinzufügen", AI-Badge in Solution-Karten. Effekt: drei konkurrierende Gradient-Auftritte direkt neben dem Logo-Wordmark „Decision**Map**" — das Brand-Mark verlor an Gewicht, weil identische Farbe überall auftauchte. Fix: Gradient ausschließlich für **Identitäts-Flächen** (Logo-Wordmark, Root-Node im Graph, Cluster→Root-Edges, Login-Headline „your problem."); alle Standard-CTAs und Status-Pills nutzen `rgb(var(--th-accent))` — die User-gewählte Akzentfarbe aus Settings (Default: Sunset Orange, 6 Swatches). Konkret betroffen: `DmTopBar.vue` Z.311 (Add-Problem-Button), `SolutionList.vue` Z.50 (Submit-CTA), Z.115 (AI-Badge) sowie nachgezogen der Footer-Submit-Button im `SolutionForm.vue`-Modal (T-13, `rgb(var(--th-accent))` + akzent-basierter Schatten statt `var(--dm-grad)`). Verbleibende bewusste Ausnahme: der Haupt-Submit im `ProblemForm.vue`-Modal (T-12) trägt weiterhin `var(--dm-grad)` als „Haupt-Submit"-Brand-Akzent — wenn auch dieser auf Akzent vereinheitlicht werden soll, separates Ticket. Regel: ein Gradient pro Brand-System ist visuelle Identität — wird er auf Standard-Controls angewendet, verliert er diese Funktion. CTAs/Badges/Pills bekommen die Akzentfarbe (variierbar pro User), Identitäts-Flächen den fixen Gradient. Bei Reviews neuer Komponenten prüfen: `var(--dm-grad)` taucht **nur** an den vier Identitäts-Stellen auf.

**Konkreter Fund 19:** Cytoscape — `background-fill: 'linear-gradient'` ist Pflicht, sonst werden alle `background-gradient-*`-Properties **stillschweigend ignoriert**.
`ProblemGraph.vue` definiert in `buildGlassStylesheet()` die `background-gradient-direction`, `background-gradient-stop-colors` und `background-gradient-stop-positions` für `.root-node` (4-stop Brand-Gradient Orange→Pink→Magenta→Violett) und die Root→L1-Edges (Orange→Magenta). Ohne `'background-fill': 'linear-gradient'` rendert Cytoscape nur die `background-color` (solid Orange) — alle Gradient-Stops werden ignoriert. Kein Konsolen-Fehler, kein Warning. Symptom: solider Knoten statt Gradient, der Bug fällt nur visuell auf. Default-`background-fill` ist `solid`. Regel: bei jedem Cytoscape-Style mit Gradient zuerst `'background-fill': 'linear-gradient'` (bzw. `'radial-gradient'`) setzen, dann erst die `background-gradient-*`-Properties — Reihenfolge in der Style-Map ist egal, das **Vorhandensein** zählt. Gilt analog für `line-fill` bei Edges (`line-fill: 'linear-gradient'`, sonst zieht die Edge nur `line-color` solid durch).

**Konkreter Fund 20:** Theme-aware Modal-Pattern — `useTheme()` statt CSS-Variablen für Glass-Surfaces (`SolutionPopup.vue` als Referenz).
Modals und Popups wurden frueher mit `bg-th-bg` (Page-Color) gestylt — auf den Glass-Themes (`glass-dark`/`glass-light`) blendete das Modal in den Mesh-Orb-Hintergrund ein, weil `--th-bg` auch der Body-Background ist. Naheliegender Fix: ein separater `--th-modal-surface`-Token. Problem: Glass-Modals brauchen **gleichzeitig** semi-transparente Farbe UND `backdrop-filter: blur(...)` plus inset Highlight — ein einzelner CSS-Token kann das nicht ausdruecken, und `hover:bg-*`-Tailwind-Utilities koennen keine theme-spezifischen rgba-Werte mit Backdrop-Filter kombinieren.
Fix: in `<script setup>` via `useTheme()` `activeThemeId.value + isDark.value` lesen und einen `cardStyle`-Computed bilden (`{background, backdropFilter, border, boxShadow}` je Theme). Glass-Dark: `rgba(20,16,28,0.78)` + `blur(40px)` + Inset-Highlight `inset 0 0 0 1px rgba(255,255,255,0.04)` + Shadow `0 30px 80px -20px rgba(0,0,0,0.6)`. Glass-Light: `rgba(255,255,255,0.86)` + `blur(30px)` + warmer Shadow. Andere Themes: `rgb(var(--th-surface))` + `rgb(var(--th-border))` solid (kein Backdrop-Filter, kein Inset). Backdrop-Dim ebenfalls theme-abhaengig (`rgba(0,0,0,0.55) + blur(8px)` fuer Glass statt `rgba(0,0,0,0.4) + blur(4px)`) — ohne die staerkere Abdunkelung verschwimmt das helle Glass-Modal optisch mit dem Mesh-Orb-Hintergrund.
Listen-Items im Modal folgen dem **SolutionList-Karten-Vokabular** statt eines Reihen-mit-Divider-Layouts: jede Karte hat ihren eigenen `itemCardStyle`-Computed (Glass: `rgba(128,128,128,0.12)`, andere: `rgb(var(--th-surface))`) mit `border-radius: 16px`, 1px Theme-Border, `padding: 14px` und `space-y-2` zwischen den Karten — Hover-Affordance via `hover:-translate-y-px` (Tailwind-Utility ist hier ok, weil sie nur eine Transform setzt, keine theme-spezifische rgba-Logik). Frühere Iteration nutzte `divide-y` + Inline-`@mouseenter/@mouseleave` mit `itemHoverStyle` — sah auf Glass mit harten Dividers unruhig aus; eigenständige Karten lesen ruhiger und matchen das Right-Panel.
Regel: jede Modal-, Drawer- oder Tooltip-Komponente, die auf Glass-Themes rendern soll, nutzt die `useTheme()`-Hook statt blind CSS-Variablen zu kombinieren. Inline-Style ist hier explizit gewollt — der gemischte rgba- + `backdrop-filter`-State laesst sich nicht in ein Tailwind-Utility verpacken, ohne den Theme-Switch zu brechen. Listen-Inhalte innerhalb solcher Modals: niemals ein eigenes Item-Vokabular erfinden — wenn dieselben Daten an anderer Stelle (Right-Panel, Card-Liste) bereits gerendert werden, dasselbe Karten-Layout wiederverwenden, damit der User keinen Stilbruch beim Wechsel der Surface wahrnimmt. Legacy-Pfad (solid `--th-surface`) bleibt bestehen.

**Konkreter Fund 21:** Bootstrap-Skript und Komponenten-Inline-Styles muessen mit dem Token-System harmonieren — kein hardcoded Theme-Fallback, keine hardcoded rgba-Konstante.
Zwei Stellen entkoppelten sich vom Theme-System und brachen beim Wechsel des Default-Themes (`midnight-dark`/`default-light` → `glass-dark`/`glass-light`):
(1) **FOUC-Bootstrap in `nuxt.config.ts`** (`app.head.script[0].innerHTML`) — parser-blockendes Inline-Skript im `<head>`, das vor dem Mount synchron `data-theme` und ggf. die `dark`-Klasse auf `<html>` setzt. Frueher hartcodiert `'midnight-dark'`/`'default-light'`; mit Glass als kanonischem Default flackerte beim ersten Reload kurz Blau auf, bevor `useTheme.ts` im Mount auf Glass umstellte. Fix: identische IDs wie `composables/useTheme.ts` (`glass-dark`/`glass-light`). **Seit FE `4881536`** ist der Erstbesuch-Default (`!t` — kein gespeichertes `theme-id`) **unconditional `glass-dark`** (Out-of-Box-Look), **nicht** mehr OS-gefolgt: `matchMedia('(prefers-color-scheme:dark)')` wird nur noch bei **explizitem** `t==='system' || p==='system'` ausgewertet (→ `glass-dark`/`glass-light`), der `!t`-Zweig setzt direkt `glass-dark`. Spiegelbild im `initTheme()`-Erstbesuch-Branch (`systemPreference='explicit'`, `activeThemeId='glass-dark'`) und in den Initial-Refs (`activeThemeId='glass-dark'`, `customAccent='#FF8C00'`, vorher `glass-light`/`#C53A82`). Der String bleibt eine einzige Zeile — nicht in Template-Literal umformatieren, parser-blocking soll minimal sein.
(2) **Komponenten-Inline-rgba in `DmFilterChip.vue`** (`chipStyle`-Computed) — Border und Text-Farbe nutzten korrekt `rgb(var(--th-accent))`, der Hintergrund war jedoch `rgba(255, 140, 0, 0.14)` (Glass-Dark-Sunset-Orange `#FF8C00`). In `glass-light` (Magenta `#C53A82`), `forest-light` (Gruen), `midnight-dark` (Hellblau) etc. stand der orange Hintergrund neben dem theme-konformen Border — sichtbarer Stilbruch in 7 von 8 Themes. Fix: `rgb(var(--th-accent) / 0.14)`. Die `--th-*`-Tokens sind als space-separated RGB-Tripel definiert; die `rgb(... / alpha)`-Syntax kombiniert Token und Transparenz ohne Custom-Property-Aufspaltung. **Wiederholung in T-06:** Das Similarity-Status-Panel in `ProblemForm.vue` (`v-if="isChecking || similarProblems.length > 0"`) trug exakt dasselbe Anti-Pattern (`rgba(255,140,0,0.08)` Background, `rgba(255,140,0,0.25)` Border) — Fix identisch via `rgb(var(--th-accent) / 0.08)` und `/ 0.25`. Das Suchpattern unten findet diese Klasse von Regressionen zuverlaessig — beim Touch jeder Komponente einmal laufen lassen, nicht nur bei Theme-Wechseln.
Regel: bei jedem Default-Theme-Wechsel **beide** Stellen gleichzeitig pruefen — Bootstrap-FOUC-Skript und alle Komponenten-Inline-Styles. Suchpattern fuer hardcoded Theme-Farben: `grep -rE 'rgba?\([0-9]+,\s*[0-9]+,\s*[0-9]+' components/ pages/ assets/` — jeder Treffer mit Akzent-, Border- oder Surface-Charakter ist ein Kandidat fuer den Token-Pfad. Inline-`rgb()`-Strings duerfen nur dann hardcoded sein, wenn sie eine **konstante** Brand-Identitaet ausdruecken (Logo-Wordmark, Mesh-Orbs in Themes.css) — UI-Tints, Borders und Backgrounds folgen immer `var(--th-*)`. Tickets-Pattern (`apps/frontend/tickets/T-01`, `T-02`, `T-06`) als Referenz fuer kleine, isolierte Theme-Token-Fixes.

**Konkreter Fund 22:** Token-Werte vorberechnen statt Opacity-Modifier-Pflicht — `--th-border` in `assets/css/themes.css`.
Glass-Dark/-Light setzten `--th-border: 255 255 255` mit dem impliziten Vertrag, jede Komponente nutzt `border-th-border/10`. Realitaet: 69 Treffer von `border-th-border` ohne `/N`-Modifier zogen solid-weiße Linien quer durch Panels, Cards, Modals und das Right-Panel. Fix: Token-Werte auf ihre intendierte Sichtbarkeit vorberechnen — Glass-Dark `50 44 68` (≈15% Weiß auf `#08060E` aubergine-black), Glass-Light `226 223 218` (≈8% Dunkel auf `#F4F1EA` warm paper). `--th-border-subtle` und `--th-input-border` analog mit graduierten Opacities (≈26%/≈20%). Regel: ein Design-Token traegt seine **intendierte** Farbe — Opacity-Modifier sind eine fakultative Verfeinerung an einzelnen Komponenten, kein impliziter Pflichtvertrag fuer alle Konsumenten. Stelle bei Theme-Token immer die Frage: „Wie soll das visuell wirken, wenn jemand den Token roh nutzt?" — die Antwort ist der korrekte Wert.

**Konkreter Fund 23:** Glass-Surface-Werte als kanonische Spec **R-02** (Glass Modal Surface) und **R-03** (Inner Card on Glass) — Inline-Duplikation statt Token.
Das in Fund 20 fuer `SolutionPopup.vue` etablierte Theme-aware Modal-Pattern wurde via Design-Session-Reverse-Tickets (`R-02`, `R-03`) als kanonische Spec promoted und in T-04 (`ProblemPanel.vue`) + T-05 (`ProblemForm.vue`) ueber alle Glass-Surfaces vereinheitlicht. Werte vorher / nachher: `rgba(20,16,28,0.7)` / `rgba(255,255,255,0.85)` ohne Shadow → kanonisch `rgba(20,16,28,0.78)` + `blur(40px)` + Drop `0 30px 80px -20px rgba(0,0,0,0.6)` + Inset-Hairline `0 0 0 1px rgba(255,255,255,0.04) inset` / `rgba(255,255,255,0.86)` + `blur(30px)` + warmer Drop `0 30px 80px -20px rgba(60,40,80,0.25)`. Inner-Card (R-03, `voteBarStyle` in `ProblemPanel.vue`): `rgba(128,128,128,0.15)` → kanonisch `rgba(128,128,128,0.12)` — das 50%-Grau ist theme-agnostisch und liest sich korrekt auf Dark- **und** Light-Glass. Konsumenten R-02: `SolutionPopup.vue`, `ProblemPanel.vue` (`panelContentStyle`), `ProblemForm.vue` (`formContainerStyle`). Konsumenten R-03: `SolutionList.vue`, `SolutionPopup.vue` (`itemCardStyle`), `ProblemPanel.vue` (`voteBarStyle`).
Bewusste Architektur-Entscheidung: **keine** Token-Einfuehrung (`--th-glass-overlay-bg` etc. wurde abgelehnt), **keine** shared Component. Begruendung: ein einzelner CSS-Token kann den gemischten `rgba` + `backdrop-filter` + `box-shadow`-State nicht ausdruecken (siehe Fund 20) — Inline-Werte sind explizit, auditierbar und beim Theme-Switch trivial inspizierbar. Bei kuenftigen Glass-Modal-/Form-/Panel-Komponenten werden die Werte aus der DS-Card-Preview (`preview/components-glass-modal.html`, `preview/components-card-inner.html`) **kopiert** — nicht erfunden. Inline-Variante eines bestehenden Pattern (z.B. abweichender Blur) → vorher Reverse-Ticket: das Ziel ist max. eine Glass-Surface-Definition, nicht 5. Pruefpattern beim Touch jeder Glass-Komponente: `grep -E 'rgba\(20,16,28|rgba\(255,255,255,0\.8[56]|rgba\(128,128,128,0\.12' components/` — Treffer sind R-02/R-03-Konsumenten, alle muessen identische Werte tragen.

**Konkreter Fund 24:** T-08 — Scoped-CSS-Klasse fuer Inline-Style-Duplikate erst extrahieren, wenn **≥2 echte Duplikate** vorliegen.
`DmTopBar.vue` hatte ein vermutetes Glass-Detection-Inline-Style-Pattern (`isGlassTheme ? (isDark ? rgba(255,255,255,0.06/0.10) : rgba(0,0,0,0.04/0.08)) : Token`) — auf den ersten Blick an 5+ Stellen wiederholt. Pattern-Reality-Check vor der Extraktion ergab nur **2 echte Duplikate** (Search-Input Z. 135 + EN/DE-Pill Z. 227); die anderen drei vermuteten Stellen (Header-Background-Switch Z. 97, Locale-Active-State Z. 240, AI-Toggle) trugen leicht abweichende Token-Mischungen (border-color + alpha-bg vs. full-border + solid-bg). Akzeptanzkriterium aus dem Ticket war `≥2` — also Extraktion: `.dm-tb-glass-chip` in scoped `<style>`-Block am Ende der SFC, Selektoren via `[data-theme="glass-dark"]` / `[data-theme="glass-light"]` greifen ueber das HTML-Root-`data-theme`-Attribut. Non-Glass-Themes behalten ihr Inline-`:style` — die Token-Mischung passt nicht ins Klassen-Modell ohne weitere Differenzierung. Diff netto +7 Zeilen (statt der vermuteten +50). Focus-Handler ueberschreibt `border-color` weiterhin inline — Specificity-Stack passt, weil scoped-Klasse von Vue mit `[data-v-*]`-Attribut versehen wird und Inline-Style sowieso schlaegt. Regel: **erst Pattern-Reality-Check, dann Extraktion** — Inline-Style-Duplikate auszaehlen, nicht schaetzen. Wenn nur 1 echtes Duplikat existiert: nicht extrahieren (Projekt-Policy „nicht alles muss DRY sein" gilt). Bei ≥2: gemeinsame Branches in Scoped-Klasse, abweichende Branches inline lassen — Mischlosungen sind explizit erlaubt. Time-box (T-08: 25min Soft, 35min Hard) und Abbruch-Bedingungen (Diff > 80 Zeilen → `git reset --hard`, INBOX-Meldung) verhindern Refactor-Sprawl.

**Konkreter Fund 25:** T-12 — Modal-Container fuer scrollende Formulare: Teleport-in-Component, Submit via `form="<id>"`-Attribut, `min-h-0` auf flex-Body.
T-12 hat das Neues-Problem-Formular von Side-Panel auf Centered Modal umgestellt (`components/ProblemForm.vue`). Drei Implementations-Entscheidungen, die nicht offensichtlich richtig sind:
(1) **`<Teleport to="body">` liegt im `ProblemForm.vue` selbst** — nicht im Caller (`pages/index.vue`). Frueher rendert `pages/index.vue` `<Teleport to="#panel-slot-target">` um die Form ins Side-Panel zu schieben. Neue Variante: `ProblemForm` ist self-contained, der Caller rendert nur `<ProblemForm v-if="isProblemFormModalOpen" />` als Root-Sibling, das Teleport sitzt im Template der Komponente. Vorteil: die Komponente kontrolliert ihren Render-Kontext — Backdrop, Z-Index, Body-Mount sind kein Caller-Vertrag. State-Trennung im Layout: `isProblemFormModalOpen` ist ein **eigener** Ref distinkt von `isPanelOpen` (das Side-Panel zeigt weiterhin Problem-Detail) — beide werden via `provide/inject` aus `layouts/default.vue` exponiert.
(2) **Submit-Button im Sticky-Footer referenziert die Form via `form="problem-form"`-Attribut.** Modal-Layout = Header / scrollbarer Body (= `<form>`) / Sticky-Footer. Der Submit-Button sitzt im Footer, also ausserhalb des `<form>`-Elements. HTML5 erlaubt `<button form="<form-id>" type="submit">` — der Klick triggert ein Submit auf das referenzierte Form, ohne dass der Button DOM-Kind sein muss. Alternative (`@click="handleSubmit()"` von ausserhalb) bricht Browser-Form-Semantik: kein `Enter`-Submit aus Eingabefeldern, keine native HTML5-Validation. Pattern uebertragbar auf alle Modal-Form-Komponenten (zukuenftiges SolutionForm-Modal).
(3) **Scrollbarer Modal-Body braucht `min-h-0` auf dem flex-Child.** Modal-Card ist Flex-Column (Header `shrink-0` / Body `flex-1 overflow-y-auto` / Footer `shrink-0`). Default-Flex-Item hat `min-height: min-content` — bei langen Forms expandiert der Body auf seine Content-Hoehe und das Modal waechst ueber `max-height: calc(100vh - 80px)` hinaus, Scroll greift nicht. Fix: `min-h-0` auf den Body (`flex-1 overflow-y-auto min-h-0`). Ohne `min-h-0` greift `overflow-y-auto` nicht, weil der Container nie Overflow erlebt — er waechst stattdessen. Regel: jeder scrollbare Flex-Child im Modal/Drawer/Panel braucht `min-h-0` (analog `min-w-0` in horizontalen Layouts).
Similarity-Card wurde von `<Teleport to="#panel-status-target">` (ausserhalb der Form) auf inline-render zwischen Title und Description umgestellt — der Status-Slot war ein Side-Panel-Artefakt und ist nach T-12 orphan (Cleanup-Kandidat: `#panel-status-target` in `layouts/default.vue:273`). Form-Logik (createProblem, validateForm, useSimilarity, useEnglishTranslation, Tag-Erstellung, duplicate_confirmed-Signal) byte-identisch — UI-only-Regel aus dem T-12-Ticket strikt eingehalten. Spec: `apps/frontend/tickets/T-12-problem-form-modal.md`.

**Post-T-12 Regression — Ghost-Open auf `/table` (Fix `87eb98f`):** Der Initial-T-12-Refactor hat nur `pages/index.vue` auf das neue Modal-Mount-Pattern umgestellt; `pages/table.vue` rendert die Form weiterhin im alten Side-Panel-Slot (`<Teleport to="#panel-slot-target"><ProblemForm v-else /></Teleport>` — unconditional gemountet wenn kein `selectedProblem` gesetzt war). Sobald `ProblemForm` sein eigenes `<Teleport to="body">` Modal traegt, oeffnet jeder Mount der Komponente das Modal — der Routing-Wechsel auf `/table` poppte deshalb das Centered Modal auf, obwohl kein „+ Add problem"-Klick erfolgt war. Fix analog zu `pages/index.vue`: `ProblemForm` aus dem panel-slot Teleport entfernen, als Root-Sibling mit `v-if="isProblemFormModalOpen"` rendern, `isProblemFormModalOpen` + `closeProblemFormModal` via `inject` aus dem Layout beziehen. Meta-Lesson: beim Einfuehren von self-contained Teleport-Komponenten **vor** dem Commit alle Verwender systematisch auditieren (`grep -rn '<ProblemForm' apps/frontend/pages/ apps/frontend/components/`) — der Refactor ist nicht abgeschlossen, bevor jeder Mount-Pfad einen v-if-Guard hat. Beim Touch state-tragender Komponenten ist „nur ein File angefasst, restliche Pages identisch" eine Annahme, kein Beleg. Regel: Page-Coverage-Check ist Teil jedes Modal-Refactors, nicht ein Folge-Bugfix.

**Konkreter Fund 26:** `translateForDisplayReal` (`composables/useTranslation.ts`) — stiller EN-Fallback bei `/translate`-Fehler kippt im DE-Modus die EN-Section.
`translateForDisplay(content, lang)` uebersetzt das kanonisch gespeicherte Englisch zur Laufzeit zurueck in die UI-Sprache (z.B. EN→DE im Problem-Panel via `loadLocalizedEditFields`). Schlaegt der `/translate`-Call fehl, gibt der `catch`-Block stillschweigend den **englischen** `text` zurueck (`return text`, Z. 86) und cached ihn **nicht** (nur Erfolge → `_displayCache`, Z. 82). Trigger in der Praxis: nginx-Rate-Limit auf `/api/translate` (5r/m, burst 2). Beim Submit feuern die Auto-Translate-Calls (DE→EN fuer Titel + Beschreibung); klickt der User das Problem direkt danach an, feuern die Display-Calls (EN→DE) und laufen ins 429. Kaskade im DE-Modus: Felder zeigen Englisch → `looksLikeEnglish()` = `true` → `englishAutoDetected` = `true` → EN-Section klappt faelschlich auf (leere EN-Felder, weil der `watch` in `useEnglishTranslation` bei englischem Orig-Text die EN-Felder leert). **Es ist kein Datenfehler** — das deutsche Original liegt korrekt in `original_translations.de`. **Self-healing:** der Fehlversuch wird nicht gecached → der naechste Aufruf (Rate-Limit-Fenster zurueckgesetzt, oder Re-Fetch nach Clustering via `editedAt`-Watch) liefert wieder Deutsch → EN-Section eingeklappt. **Behoben via Fix-Option (1):** `/problems` liefert `original_translations` jetzt ans Frontend (`ProblemRead.original_translations`, Batch-Read `_load_original_translations` reverse-mappt die `sha256(englisch)`-Cache-Keys auf Titel/Beschreibung). `loadLocalizedEditFields` bevorzugt `originalTranslations[locale]` statt des LLM-Round-Trips — kein 429-Risiko mehr im Edit-Pfad, `translateForDisplay` bleibt nur Fallback fuer Sprachen ohne gespeichertes Original. PATCH re-cached das Original gegen den **neuen** englischen Canonical (`_store_original_translations`, DRY-Helper aus dem Create-Pfad), sodass ein Edit das Original mitfuehrt. Restrisiko (2) — 429 bei reinen Display-Stellen ohne gespeichertes Original (z.B. `SolutionList`) — bleibt offen. Vgl. Features-Doc, `translateForDisplay`-Abschnitt.

**Konkreter Fund 27:** `navigator.clipboard` nur im Secure Context — naiver `writeText` faellt auf HTTP-Origins still aus.
`ProblemPanel.copyPermalink` rief `navigator.clipboard.writeText(url)` in einem `try/catch`, dessen `catch` den Fehler **nur in die Konsole** loggte (kein UI-Feedback). `navigator.clipboard` existiert aber ausschliesslich in Secure Contexts (HTTPS oder `localhost`); auf einem HTTP-Origin wie dem Staging-Host `int.decisionmap.ai` ist es `undefined` → `writeText` wirft sofort → fuer den User „nichts passiert". Gleiche Secure-Context-Klasse wie der dokumentierte `navigator.geolocation`-`PERMISSION_DENIED`-Gotcha (Geo-Detection faellt auf Backend-Proxy zurueck). **Fix (Frontend-only, zwei Teile):** (1) neuer wiederverwendbarer Util `utils/clipboard.ts` (`copyToClipboard(text): Promise<boolean>`) — nutzt `navigator.clipboard?.writeText` wenn vorhanden, faellt sonst (oder bei Reject wegen Focus/Permission) auf das Legacy-`document.execCommand('copy')` via verstecktem `<textarea>` zurueck, das auch auf HTTP funktioniert; gibt `true`/`false` statt zu werfen. `import.meta.client`-Guard fuer SSR-Routen. (2) `copyPermalink` zeigt bei `false` jetzt einen Error-Toast (`permalink.copyFailed`, EN+DE) statt stillem Nichts. Regel: jeden Secure-Context-only Browser-API-Zugriff (`clipboard`, `geolocation`, `crypto.subtle`, Service Worker) mit HTTP-Fallback **oder** sichtbarem Fehler-Pfad versehen — ein `catch`, der nur `consola.error` aufruft, ist auf HTTP-Staging faktisch ein Silent-Fail. Wiederverwendbar fuer kuenftige Share-Buttons (z.B. `SolutionDetail`). Vgl. Features-Doc, Permalink-System / Share-Button.

**Konkreter Fund 28:** `utils/markdown.ts` — `DOMPurify.addHook(...)` auf Modul-Ebene crasht SSR/prerender.
Der Link-Hardening-Hook (erzwingt `rel="noopener noreferrer"` + `target="_blank"` auf allen Links) war auf Modul-Ebene registriert. `DOMPurify` braucht aber ein Browser-DOM: beim SSR/prerender von `/problem/**` (`routeRules` → `prerender: true`) ist der Default-Export eine uninitialisierte Factory **ohne** `addHook`/`sanitize`. Das blosse Importieren von `markdown.ts` (via `SolutionForm`/`SolutionDetail`) wertet den Modul-Body aus → `addHook is not a function` → Render-Crash. Sichtbar wurde es ueber den T-12-Similarity-Flow (Klick auf einen Match navigiert auf `/problem/{id}`), war aber ein vorbestehender Latenzbug auf **jeder** Navigation zu einer prerender-Route. **Fix (Frontend-only):** (1) Hook lazy via `ensureHook()` (Idempotenz-Flag) statt auf Modul-Ebene — nur beim ersten client-seitigen Render. (2) `renderSolutionMarkdown` gibt bei fehlendem DOM (`typeof window === 'undefined'`) die rohe `markdown-it`-Ausgabe zurueck — sicher ohne DOMPurify dank `html:false` + disabled `image`/`code`/`fence`. Kein Hydration-Mismatch: `/problem/[id]` fetcht Solutions erst in `onMounted` (client), bei SSR ist die Liste leer → `renderSolutionMarkdown` wird server-seitig nie mit Inhalt aufgerufen. Das dokumentierte Hook-Verhalten (rel/target auf allen Links) bleibt unveraendert, nur lazy/client-seitig. Regel: keine DOM-abhaengigen Library-Seiteneffekte (`DOMPurify.addHook`, `document.*`, `window.*`) auf Modul-Ebene in Code, der ueber eine prerender/SSR-Route importiert werden kann — lazy hinter einen `typeof window`-Guard legen. Gleiche Klasse wie der `localStorage`-auf-SSR-Routen-Gotcha (Fund 8).

**Konkreter Fund 29:** T-13 — Vitest-Test eines Teleport-Modals, dessen Submit-Button via `form="<id>"` ausserhalb des `<form>` haengt.
T-13 hat `SolutionForm.vue` auf das self-contained Teleport-Modal mit Sticky-Footer-Submit umgestellt (Fund 25-Pattern, `form="solution-form"`). Beim Anpassen von `tests/components/SolutionForm.spec.ts` zwei nicht-offensichtliche Test-Erkenntnisse: (1) **`<Teleport>` muss gestubbt werden** (`global: { stubs: { teleport: true } }`) — sonst rendert der Modal-Inhalt nach `body` und `wrapper.find('#solution-content')` erreicht die Felder nicht. (2) **jsdom honoriert die `form="<id>"`-Cross-Element-Assoziation nicht** — ein `.trigger('click')` auf den Footer-Submit-Button loest in jsdom **kein** Form-Submit aus (im echten Browser schon). Fix: das Submit-Event direkt auf der Form feuern (`wrapper.find('#solution-form').trigger('submit')`) statt den Button zu klicken; der fruehere `findSubmitBtn`-Helper (suchte den Button per Text `actions.submit`) wurde durch `submitForm(wrapper)` ersetzt. Regel: bei `form="<id>"`-Submit-Buttons im Test das Form-`submit`-Event triggern, nicht den Button-Klick — die HTML5-Assoziation ist Browser-Verhalten, das jsdom nicht nachbildet. Spec ergaenzt um den anonymen Login-Redirect-Flow (`tests/e2e/solution-redirect.spec.ts`, Playwright): `data-testid="add-solution"` (`SolutionList.vue`) + `data-testid="solution-form"` (`SolutionForm.vue`) als stabile E2E-Selektoren.

**Konkreter Fund 30:** Sprachunabhaengige Suche — `original_translations` als first-class JSONB-Spalte + `q_raw`-Such-Parameter; JSONB-Variant fuer die SQLite-Test-DB.
Symptom: ein deutscher Substring (`"schlecht"`) fand das Problem nicht, weil die Keyword-Suche nur gegen den englischen Canonical (`title`/`description`) per ILIKE lief — der Originaltitel lag vorher nur als `sha256`-gekeyter Eintrag im `translation_cache`, nicht durchsuchbar. Zwei zusammenhaengende Aenderungen:
(1) **Daten:** `problems.original_translations` ist jetzt eine **first-class JSONB-Spalte** (Migration 009, Format `{lang: {title?, description?}}`), transaktional bei Create **und** PATCH im selben Commit wie `title`/`description` geschrieben — kein Hash-Drift mehr, der Originaltext ist update-sicher. Backfill aus dem alten Cache. Die `sha256`-Reverse-Mapping-Helfer (`_store_/_load_original_translations`) sind entfernt; `_to_read` liest direkt aus der Spalte. (2) **Suche:** `GET /internal/problems/search` bekommt `q_raw` — `q` (uebersetzt) trifft `title`/`description`, `q_raw` (roh) trifft `original_translations::text` via `.cast(Text).ilike(...)`. Fallback auf `q`, wenn `q_raw` fehlt — keine Regression. Frontend matcht zusaetzlich lokal gegen den **angezeigten** Titel (`utils/problemSearch.ts`, in `table.vue` + `index.vue`/Graph) — sprachunabhaengig ueber zwei unabhaengige Pfade.
**Contract-Test-Erkenntnis:** Die In-Memory-SQLite-Test-DB hat keinen `visit_JSONB` — eine reine `JSONB`-Spalte bricht den Schema-Build der Tests. Fix im Modell: `JSONB().with_variant(JSON(), "sqlite")` (Postgres = JSONB, SQLite = generisches JSON); der `'{}'::jsonb`-Server-Default-Cast lebt in Migration 009, die nur auf Postgres laeuft, das Modell nutzt das dialekt-neutrale `server_default=text("'{}'")`. Regel: dialekt-spezifische Spaltentypen (JSONB, ARRAY, Vector) im Modell mit `.with_variant(...)` fuer den Test-Dialekt absichern — sonst gruene Prod-Migration, aber roter Test-Schema-Build. Tests: `test_migration_009_backfill.py` + `test_search_q_raw_matches_original_translations` (backend), `problemSearch.spec.ts` (frontend). *(Nachtrag Fund 40: seit dem Umzug der Test-DB auf echtes Postgres ist die `"sqlite"`-Variante totes Legacy — die Regel „dialekt-spezifische Typen im Modell absichern" gilt nur noch hypothetisch, der reale Test-Dialekt ist jetzt Postgres.)*

**Folge-Bug (Fix `0504873`) — reaktiver Endlos-Zyklus durch den Such-Local-Match:** Der Frontend-Local-Match (F1, `pages/table.vue`) machte `filteredProblems` von `localizedTitles` abhaengig — aber **nur** wenn ein Query getippt ist (`if (query)`-Zweig in `matchesQuery`). Der bestehende `localizedTitles`-Watcher beobachtete seinerseits `filteredProblems` und schrieb `localizedTitles` zurueck → beim ersten Tastendruck schloss sich der Zyklus (`Tippen → filteredProblems liest localizedTitles → Watcher feuert → schreibt localizedTitles → filteredProblems invalidiert → ∞`) und fror den Tab komplett ein (Main-Thread-Endlosschleife, DevTools unerreichbar). Leeres Suchfeld las `localizedTitles` nicht → kein Zyklus, daher trat der Hang exakt „beim ersten Buchstaben" auf. `pages/index.vue`/Graph war immun, weil sein Watcher die Titel von Anfang an aus dem **ungefilterten** `problems`-Array bezog. Fix: den `table.vue`-Watcher ebenfalls aus `problems` speisen (nicht aus dem zuruecklesenden `filteredProblems`). Regel: ein `watch`, der einen Ref X schreibt, darf nie ein `computed` beobachten, das X liest — Watcher-Quelle immer das rohe Quell-Array, nie der zurueckspiegelnde abgeleitete Wert. Test-Luecke, die den Zyklus durch alle 100 gruenen Tests rutschen liess: `problemSearch.spec.ts` testet nur den puren Helper, kein Page-Mount — die reaktive Interaktion mit dem bestehenden Watcher liegt ausserhalb des Helper-Scopes.

**Konkreter Fund 31:** Server-Driven Search Phase 1 — zwei Final-Review-Funde im paginierten `GET /problems`.
(1) **Nullable-Spalte taugt nicht als „niemals wahr"-Guard.** Der `company`-Filter ohne passende User soll die Leermenge liefern; der erste Versuch nutzte `Problem.user_id.is_(None)` als immer-falsch-Bedingung — aber `user_id` ist **nullable** (anonyme Session-Submissions), also matchte der Ausdruck **alle** anonymen Probleme und gab sie trotz nicht existierender Company zurueck (Auth-/Sichtbarkeits-Leak). Fix: `Problem.id.is_(None)` — die PK ist non-nullable → garantiert falsch, portabel ueber PostgreSQL + SQLite (statt `literal(False)`, das je ORM-Version dialekt-spezifische Kompilierung braucht). Regel: ein „never-true"-Filter-Guard muss gegen eine **non-nullable** Spalte (PK) laufen, nie gegen eine nullable. Regressions-Test: `company=NoSuchCompany` → `items=[] total=0` (`test_problems_filters.py`).
(2) **Fail-soft verschluckt einen Routing-Bug.** `services/ai_client.embed_query()` postete an `/internal/embed-query`, aber der ai-service mountet den Embeddings-Router unter `prefix="/embeddings"` → echter Pfad `/embeddings/internal/embed-query`. Weil `embed_query` **alle** Exceptions schluckt und `None` zurueckgibt, war die **semantische Suche in Production lautlos tot** (leere Seite, kein Fehler-Log). Regel: ein fail-soft-Client (Exception → `None`/leer) braucht einen **Pfad-Contract-Test**, der die exakte URL asserted — sonst wird ein 404 vom falschen Prefix nie sichtbar. Test: `test_ai_client.py` (`assert_awaited_once_with("/embeddings/internal/embed-query", ...)`).
**Contract-Test-Erkenntnis (Keyset/Semantik):** Die Keyset- und Semantik-Tests sind **Postgres-Contract-Tests** mit echten Assertions (zweite Seite schliesst lueckenlos an, keine Duplikate; `semantic` ignoriert `sort` und holt das Embedding genau einmal, danach aus dem Cursor). ~~Da die In-Memory-SQLite-Test-DB kein pgvector hat, laufen sie nur gegen Postgres (skip/mark sonst).~~ Seit Fund 40 ist die Test-DB selbst echtes Postgres+pgvector — die `skipif`-Marker sind entfernt, die Tests laufen unbedingt. `(:emb)::vector` immer geklammert (asyncpg-Substitutions-Gotcha).
**Contract-Test-Erkenntnis (Envelope-Wechsel bricht Bare-List-Consumer):** Der Wechsel von `GET /problems` auf das paginierte `ProblemPage`-Envelope (`{items, next_cursor, total}`) brach drei bestehende Tests der **Live-Server-Contract-Suite** (`tests/contract/test_problems.py`), die die Antwort weiterhin als blanke Liste konsumierten — `isinstance(json, list)`, `json[0]`, `for p in json`. Sie waren bei der Implementierung mitgewandert in `tests/unit` (neue Keyset-Tests), aber die Contract-Suite (separater Lauf, `make api-test-contract` gegen `localhost:8001`) wurde nicht auditiert. Fix: alle Consumer auf `json["items"]` umgestellt. Gleichzeitig fiel ein **zweiter, aelterer** Drift auf: `test_problem_item_shape` verlangte `title_en`/`description_en`/`content_language` — die der `original_translations`-Refactor laengst aus `ProblemRead` entfernt hatte (Frontend `realProblems.ts` mappt sie auch nicht mehr); die Shape-Assertion wurde an den realen Contract angeglichen (`title`/`description`/`original_translations`). Regel: aendert sich das Response-Shape eines Endpoints, **beide** Test-Suiten auditieren — Unit *und* die separat laufende Contract-Suite (`grep -rn 'get("/problems")' tests/`). Pre-existierend und davon unberuehrt: `test_solution_item_shape` fragt `/solutions?status_filter=pending` **unauthentifiziert** ab → 403 (dokumentierte Solutions-Filter-Auth-Gotcha), braucht einen Superuser-Client.

**Konkreter Fund 32:** Zwei Phase-1-Folge-Regressionen (2026-06-24).
(1) **Server-seitiger Param-Default ≠ „kein Filter".** `GET /problems` defaultet `status_filter` auf `approved`. Die neue `pages/table.vue` ließ `status` für Admins *weg* in der Annahme „kein Filter = alle Status" — tatsächlich griff der Server-Default und der Admin sah nur approved (Regression ggü. der alten Table). Fix: Backend kennt jetzt `status_filter=all` (keine Status-Einschränkung, superuser-gated über die bestehende `!=approved → 403`-Schranke, im Keyword- **und** Semantik-Pfad via geteiltem `base_where`); das Frontend sendet `status='all'` für Admins **explizit**, `'approved'` sonst (BE `6e90a5e`, FE `1746896`). Regel: defaultet ein Endpoint-Param server-seitig, kann der Client ihn nicht weglassen um „kein Filter" zu meinen — den Öffnungs-Wert (`all`/`*`) explizit senden. Tests: BE `test_status_filter_all_*` (Superuser sieht alle Status, Nicht-Superuser → 403), FE `useProblemsPagination.spec.ts` (`status='all'` → `status_filter=all` auf der Wire).
(2) **Nuxt-Route-Middleware läuft nur bei Navigation, nicht bei In-Place-Auth-Wechsel.** `handleLogout` pushte unbedingt `/` → man landete nach dem Abmelden immer in der Graph-View, auch aus der Table. Fix (`59b8f77`): aktuelle View beibehalten; nur auth-gated Admin-Routen (`/admin/**`) explizit verlassen — deren Middleware greift bei einem In-Place-Logout (Auth-State ändert sich ohne Navigation) nicht und würde sonst eine geschützte Route eingeloggt-frei stehen lassen. Regel: bei In-Place-Auth-Zustandswechseln (Logout ohne Routenwechsel) Middleware-Schutz nicht voraussetzen — auth-gated Routen im Handler selbst explizit verlassen, alle anderen Views erhalten.
(3) **Unbekannter `sort`-Wert fällt still auf `created` zurück → „Seite-1-Illusion" bei Keyset-Pagination.** Die Table-Status-Spalte sendete `sort=status`, aber das Backend kannte den Modus nicht und fiel auf `created` zurück. Da es keinen Client-Sort gibt, wirkte Seite 1 zufällig gruppiert, beim Infinite-Scroll kamen die Status aber gemischt nach. Fix: echter `sort=status`-Keyset-Modus über `(status, id)` (analog `title`, BE `934fbf5`, FE `711f5eb`). **Contract-Test-Erkenntnis:** Ein Sort-Test, der nur die **erste Seite** prüft, ist gegenüber dem stillen `created`-Fallback blind — die erste Seite kann zufällig sortiert aussehen. Der Test muss daher **alle** Seiten durchpaginieren und über die zusammengeführte Sequenz die globale Status-Ordnung **und** Überlappungsfreiheit (kein Item doppelt) asserten (`test_problems_pagination.py`). Regel: jeder neue Keyset-Sort-Modus braucht einen Test, der über Seitengrenzen hinweg die globale Ordnung verifiziert, nicht nur die erste Seite.

**Konkreter Fund 33:** Bidirektionaler Keyset-Sort (`dir=asc|desc`) + `tag`-Modus (2026-06-24, BE `440cb3e`, FE `37cff86`).
Die Table-Sort-Richtung und die Cluster-Spalte waren server-seitig No-ops: das Backend kannte nur feste Richtungen je Modus, und `sort=tag` fiel auf `created` zurück. `GET /problems` akzeptiert jetzt `dir` (`asc`/`desc`, sonst → 422), das **jeder** Keyset-Modus respektiert, plus einen `tag`-Modus (Sortierung nach dem Struktur-/Cluster-Tag-Namen, MIN über `tags.level<10`, `''`-Bucket für unclustered). Das Frontend sendet `sortDirection` als `dir` und mappt `tag`→`tag` (kein `created`-Fallback mehr). **Architektur-Disziplin (Keyset):** ein einziges `asc`-Flag steuert ORDER-BY-Richtung, Keyset-Operator (`>`/`<`) **und** den `id`-Tiebreaker über zwei Helper (`_ordered`/`_keyset`) — so ist Operator/Richtungs-Drift (die klassische Keyset-Fehlerquelle: Richtung dreht, Operator nicht) baulich ausgeschlossen. Die effektive Richtung reist im **Cursor** (kompakter Key `d`): auf Seite 2+ gewinnt die Cursor-Richtung, `dir` wird ignoriert. **Contract-Test-Erkenntnis:** ein Bidirektional-Test darf sich nicht auf Seite 1 beschränken — er muss beweisen, dass die Richtung **über Seitengrenzen** stabil bleibt, gerade wenn der `dir`-Param auf der Folgeseite umgedreht wird (der Cursor muss gewinnen, sonst springt die Ordnung mitten im Infinite-Scroll). Tests: `test_problems_pagination.py` (Richtung pro Modus, Cursor-Direction schlägt `dir` auf Seite 2), `test_cursor.py` (Roundtrip mit/ohne `direction`-Key — Alt-Cursor ohne `d` → per-Modus-Default), FE `useProblemsPagination.spec.ts` (`dir` auf der Wire / weggelassen).

**Konkreter Fund 34:** `pages/table.vue` — Virtualizer + `table-layout: auto` = „atmende" Spalten; Fix `table-fixed` (2026-06-24, FE `7cf37a8`).
Die Table ist zeilen-virtualisiert (`@tanstack/vue-virtual`, nur sichtbare Zeilen via `row.index` im DOM). Mit dem Browser-Default `table-layout: auto` berechnet der Browser die Spaltenbreiten aus dem **aktuell gerenderten** Inhalt — beim Infinite-Scroll wechselt das sichtbare Fenster, also ändern sich die Breiten pro Scroll-Position: ein langer Titel verbreitert die Titel-Spalte und schiebt Cluster + Folgespalten nach rechts, beim Wegscrollen wieder zurück. Symptom: horizontal „springende"/„atmende" Spalten beim Scrollen, kein Konsolen-Fehler. Fix: `table-fixed` auf das `<table>` + feste Breiten pro Spalte (Endstand `52e7b67`: Cluster 220px · Votes 150px · Lösungen 130px · Erstellt 132px · Status 92px — die Titel-Spalte nimmt den Rest; der Votes-Header hieß bis `24536e3` „Bewertungen", s.u.); lange Titel `truncate` (Ellipsis) statt `line-clamp-1` + voller Titel als Hover-`title`-Tooltip. Regel: jede **virtualisierte** Tabelle braucht `table-layout: fixed` mit expliziten Spaltenbreiten — bei `auto` hängt das Layout vom zufällig sichtbaren Zeilenfenster ab, nicht vom Gesamtdatensatz. Reine Layout-Klassen, keine Logik-Änderung — keine neuen Tests (119 grün).
**Folge-Fix (`0879c2f`) — Header-Overlap unter `table-fixed`:** Die zwei numerischen Spalten waren zunächst zu schmal für ihre langen deutschen `whitespace-nowrap`-Header („Bewertungen"/„Lösungen"), die unter `table-fixed` über den Zellrand in die Nachbarspalte liefen (Überschneidung). Die flexende Titel-Spalte fängt die Mehrbreite auf, daher kein horizontaler Gesamt-Überlauf. Regel: unter `table-fixed` muss eine Spaltenbreite das **längste lokalisierte** Header-Label (nicht nur den Zellinhalt) fassen — `nowrap`-Header ohne Platz brechen sonst still in die Nachbarspalte.
**Folge-Fix (`52e7b67`) — Spaltenbreiten als Inline-`style` statt Tailwind-`w-[Npx]`:** Die korrigierten Breiten blieben beim User wirkungslos (Header-Overlap weiterhin sichtbar), obwohl der `table-fixed`-Umbau selbst griff. Ursache: **Tailwind-JIT regeneriert geänderte Arbitrary-Werte (`w-[140px]` → `w-[150px]`) im Dev nicht zuverlässig sofort** — das alte CSS bleibt gecacht, also greift die neue Breite erst nach Dev-Server-Neustart, während strukturelle Klassen (`table-fixed`) sofort wirken. Fix: Breiten als Inline-`style="width: …px"` setzen — greifen über Vue-HMR unabhängig vom Tailwind-Build. Regel: nachträglich justierte Arbitrary-Pixelwerte, die *sofort* sichtbar sein müssen, als Inline-`style` setzen statt als `w-[Npx]`-Klasse — sonst maskiert gecachtes JIT-CSS den Effekt und der Fix wirkt fälschlich als „kommt nicht an".
**Folge-Fix (`24536e3`) — DE-Header `voteScore` „Bewertungen" → „Votes":** Auf Wunsch aus dem Verify trägt die Vote-Spalte jetzt in **beiden** Locales das kurze Label „Votes" (EN war bereits „Votes"). Nebeneffekt: der lange deutsche `whitespace-nowrap`-Header „Bewertungen" entfällt, womit der Header-Overlap aus dem `0879c2f`-Fix für diese Spalte gegenstandslos wird (die feste 150px-Breite bleibt; relevant bleibt der Overlap-Punkt nur noch für „Lösungen"). Reine i18n-Änderung (`i18n/locales/de.json`), keine Logik, keine neuen Tests.

**Folge-Fix (`7c0d38e`) — Scroll-Offset nach Sort-/Filter-Wechsel zurücksetzen:** Dieselbe Virtualizer-Eigenheit, andere Achse. `loadFirstPage` setzt `problems` beim Sort-/Filter-/Such-Wechsel auf die erste Seite (50 Zeilen) zurück, aber die virtuelle Content-Höhe richtet sich nach `total` — das bleibt beim reinen Sortwechsel unverändert (z.B. 282 Zeilen). Stand der Scroll noch unten, renderte der Virtualizer Zeilen jenseits des frisch zurückgesetzten `problems`-Arrays → leerer/„schwarzer" Viewport, bis man hochscrollte. Fix: `triggerLoad` ruft nach dem Laden (`await loadFirstPage` + `nextTick`) ein neues `scrollToTop()` (`scrollRef.scrollTo({top:0})` **und** `virtualizer.scrollToOffset(0)` — beide nötig, Container-Scroll + Virtualizer-State) — bei **jedem** Sort-/Filter-/Such-Wechsel. Regel: bei virtualisierten Listen jeden Datensatz-Reset von einem Scroll-Reset auf den Anfang begleiten — ein stehengebliebener Offset zeigt sonst Zeilen jenseits der neuen Datenmenge. Reine Layout-/Scroll-Logik, keine neuen Tests (119 grün).

**Konkreter Fund 35:** Drill-Down-State zweigeteilt — jeder Pfad, der `tagFilterIds` setzt, muss `cluster-drill` emittieren (2026-06-25, FE `b48009e`).
Seit dem Phase-2-Drill-Down hält der Graph (`ProblemGraph.vue`) seine visuelle Tag-Fokussierung in `tagFilterIds`, während der Parent (`pages/index.vue`) den davon **getrennten** `drilledTagId` führt — er entscheidet, ob `runSearch('')` den gedrillten Cluster lädt (Aggregat-Branch) oder den Übersichts-Pfad (`null`) nimmt. `addTagFilter()` synct beide via `emit('cluster-drill', id)`. Der Permalink-Pfad `navigateToProblem()` (Fokus auf ein verlinktes Problem) setzte aber nur `tagFilterIds` und emittierte **nicht** — der Graph war visuell gedrillt, `index.vue`s `drilledTagId` blieb `null`, `runSearch('')` nahm den Null-Branch → leeres Problem-Grid **unter aktiver Breadcrumb**. Fix: direkt nach jeder `tagFilterIds`-Zuweisung `emit('cluster-drill', deepestTag.id)` bzw. `UNCLUSTERED_ID` — identisches Muster wie `addTagFilter()`. Regel: liegt ein UI-Zustand redundant in zwei Komponenten (hier visueller Drill im Child, Lade-Entscheidung im Parent), muss **jeder** Setter des einen den anderen mit-synchronisieren — ein neuer Einstiegspunkt (`navigateToProblem`), der nur die lokale Hälfte setzt, desynct still. Reiner 5-Zeilen-Sync, keine neuen Tests (119 grün).

**Konkreter Fund 36:** Loader nur beim Initial-Load — der Graph bleibt über Drill/Suche/Pagination gemountet (2026-06-25, FE `24c321d`).
`pages/index.vue` band den Lade-Spinner früher an `v-if="problemsLoading || tagsLoading"`. Seit dem Phase-2-Drill-Down togglen genau diese Refs aber bei **jedem** Drill, jeder server-seitigen Suche und jeder Pagination-Iteration — der Spinner ersetzte also den Graphen bei jeder Interaktion, `ProblemGraph` wurde unmounted und neu gemountet, und die Cytoscape-Instanz verlor Viewport, User-gezogene Positionen und Selektion (die persistierten Zustände aus Fund 14/15 wurden zwar aus localStorage wiederhergestellt, aber mit sichtbarem Flackern + Re-Layout pro Klick). Fix: separater `initialLoading`-Ref, der `true` startet und im `finally`-Block von `onMounted` **einmalig permanent** auf `false` gesetzt wird; der Spinner hängt jetzt an `v-if="initialLoading"`. Drills/Suchen/Pagination togglen ihn nie wieder → `ProblemGraph` bleibt über den gesamten Session-Lebenszyklus gemountet, die Cytoscape-Instanz (Viewport, Positionen, Selektion) bleibt erhalten, nachgeladene Cluster-Zeilen aktualisieren nur `props.problems`. Regel: einen globalen Lade-Indikator nie an einen Ref binden, der pro In-Place-Interaktion (Drill, Lazy-Load, Filter) toggled — sonst wird die zustandstragende Visualisierung bei jeder Interaktion zerstört; einen dedizierten „erstes Mount erledigt"-Ref verwenden, der nur einmal kippt. Reine Mount-Lifecycle-Änderung, keine neuen Tests (119 grün).

**Konkreter Fund 37:** Filter↔URL-Zwei-Wege-Sync braucht einen Hydration-Guard, der im `finally` kippt (2026-06-25, FE `b509b12`/`2a710ae`/`bc57d45`, #31).
Die URL-adressierbaren Tabellen-Filter (`useTableFiltersUrl` + `pages/table.vue`) spiegeln den Filter-State in die Query (`router.replace`) und hydratisieren ihn beim Mount zurück. Drei Fallen: (1) Beim Setzen der Filter-Refs aus der URL feuern die bestehenden Watches (Daten-Laden + Auto-Select) — ein zweiter `loadFirstPage` bzw. eine Selektion mitten in der Befüllung. Fix: ein `isHydrating = ref(true)`, das **jeden** dieser Watches per `if (isHydrating.value) return` stummschaltet; `onMounted` befüllt erst alle Refs und ruft **einmal** explizit `loadFirstPage(buildQuery())`. (2) Der Guard muss im **`finally`** des Initial-Loads zurückgesetzt werden — wird er nach einem geworfenen Load nicht gekippt, bleibt er `true` und die Tabelle reagiert nie wieder auf Filter/Sort (Dead-Table). (3) Der State→URL-`watch` darf **nicht** `searchQuery`/`semantic` enthalten: die leben im Layout-Header und würden die URL bei jedem Tastendruck (vor dem Debounce) überschreiben — `q` wird zwar hydratisiert (geteilter `?q=…`-Link), aber nicht pro Keystroke zurückgeschrieben. `router.replace` mit identischen Params ist in Vue Router ein No-op → der Sync-Watch kann keine Endlosschleife auslösen. Regel: Zwei-Wege-State↔URL-Sync immer mit einem `finally`-gekippten Hydration-Flag absichern und hochfrequente Eingabe-Refs aus dem Rückschreib-Watch heraushalten.

**Konkreter Fund 38:** Cross-linguale Keyword-Symmetrie via additivem Cursor-Key (2026-06-25, BE `45c419f`, #32).
Der Keyword-Pfad von `GET /problems?q=` übersetzte die Query bisher nur **einseitig** ins Englische (`translate_query_to_en`), was eine asymmetrische Treffermenge erzeugte (`q=missing` fand deutsches *fehlend*-Material nicht). Fix (Option B): `translate_query(text, lang)` generalisiert die Übersetzung; das Backend holt auf Seite 1 **beide** Richtungen (`q_en` + `q_de`) und OR-kombiniert `[q, q_en, q_de] × [title, description, original_translations::text]`. **Cursor-Backwards-Compat-Pattern:** die zweite Übersetzung reist unter einem **additiven** Cursor-Key (`q2`) — alte, vor #32 erzeugte Cursor haben keinen `q2`, und `peek_cursor_q_de` gibt für sie still `None` zurück statt zu werfen; der OR-Block überspringt jede `None`-Variante. Ein neuer Key im Cursor-Payload darf also **nie** ein Pflicht-Feld beim Decode sein, sonst brechen in-flight-Cursor über das Deployment hinweg. Der alte `translate_query_to_en` bleibt als dünner Wrapper (Import-Kompatibilität). **Contract-Test-Erkenntnis:** der Symmetrie-Test darf sich nicht auf eine Richtung beschränken — er muss beweisen, dass EN-Query und DE-Query **dieselbe** Treffermenge liefern (`ids_en == ids_de`), und gleichzeitig die **Translate-once-pro-Sprache**-Invariante halten: genau **zwei** `translate_query`-Calls auf Seite 1 (EN+DE), **null** auf Folgeseiten (Cursor-Reuse). Vorher prüfte der Test „genau ein Call" — die Mock-Signatur musste von `_mock(text)` auf `_mock(text, target_lang)` mitwandern. Regel: erweitert ein Feature den Cursor-Payload, immer additiv + `peek_*`-Toleranz; und ein Cross-lingual-Test beweist Symmetrie über Result-Set-Gleichheit, nicht nur einen einzelnen Treffer. **Live-Verify-Nachtrag (2026-06-27):** der Contract-Test ist mit **gestubbter** Übersetzung grün — er beweist die symmetrische *Verdrahtung*, nicht die reale Wirkung. Live mit dem echten LLM blieb EN→DE unvollständig: `q=missing` erreichte deutsches Material nicht, weil die LLM-Übersetzung eine flektierte/abweichende Form (`Fehlender` statt `fehlend`) liefert, die der Substring-Match nicht trifft (DE→EN lief). Das ist die in #32 erlaubte „begründete Restdifferenz" (lexikalischer Match bleibt flexions-abhängig), kein Regressions-Bug. Regel-Erweiterung: ein gestubbter Symmetrie-Test deckt die Verdrahtung ab, aber eine lexikalische Cross-lingual-Garantie braucht Live-Verify oder Stamm-/Teilwort-Matching — die semantische Suche bleibt der zuverlässige cross-linguale Pfad. **Generalisierungs-Nachtrag (BE `4d6279d`):** der fixe `q2`/`q_de`-Cursor-Key wurde zu einer **N-sprachigen Übersetzungs-Map** verallgemeinert — Cursor-Key `qt` (`{lang: text}`), die Übersetzungs-Schleife läuft über die Such-Sprach-Registry `SEARCH_LANGUAGES`, Extraktion via `peek_cursor_translations` statt `peek_cursor_q_de`. Verhaltens-erhaltend (ILIKE bleibt vorerst); das additive-Key- + `peek_*`-`None`-Toleranz-Pattern bleibt identisch, nur nicht mehr auf zwei Sprachen fixiert. **FTS-Nachtrag (BE `8982048`, F2 Task 3):** der ILIKE-Substring-Block im `q`-Pfad ist durch **Postgres-FTS** ersetzt — pro Sprache `to_tsvector(config, …) @@ plainto_tsquery(config, …)` (funktionaler GIN-Index, Migration 010, identische SQL aus `tsvector_sql`). Per-Sprache-**Stemming** löst die oben als „begründete Restdifferenz" dokumentierte flexions-abhängige Lücke auf: `fehlt`/`fehlende`/`fehlend`/`missing` und `company`/`companies` matchen jetzt symmetrisch. Der Unit-Test `test_fts_stemming_symmetry_english_plural` beweist die Stamm-Symmetrie (`company`/`companies` + `company`⇄`Unternehmen`) mit gestubbter Übersetzung; die rohe Query läuft zusätzlich gegen **jede** Sprach-Config (übersetzungs-ausfall-sicher). Regel-Erweiterung: Stamm-Matching (FTS) ist der Weg zu lexikalischer Cross-lingual-Symmetrie über Flexionen — Synonyme bleiben Sache der semantischen Suche. **Multi-Kandidaten-Nachtrag (Option B, BE `6fd5c1d` / AI `58fcbad`):** die im Live-Verify festgehaltene Restschwäche — eine **einzelne** LLM-Übersetzung trifft evtl. die falsche Flexion (`fehlt` ≠ `fehlend` unter PG german snowball) — wird jetzt am Recall-Hebel adressiert: `translate_query(text, lang)` gibt statt einer Einzelübersetzung eine **Liste von Kandidaten** zurück (gebeugte Formen + nahe Synonyme), geholt vom neuen ai-service-Endpoint `POST /translate/candidates` (`TranslationService.translate_query_candidates` — robustes Parsing: JSON-Array, Array-aus-Prosa, Komma-/Newline-Fallback; case-insensitiver Dedupe; Cap 6; `[]` bei LLM-Fehler, damit die Suche nie bricht). Die FTS-WHERE-Loop OR-verknüpft **jeden** Kandidaten als eigene `plainto_tsquery`-Klausel, der `relevance`-`ts_rank` summiert über alle. So erreicht `q=missing` über mehrere DE-Kandidaten (`fehlend`/`vermisst`/…) auch die Zeilen, die eine falsch-flektierte Einzelübersetzung verfehlt hätte. Getrennt vom Single-String-`POST /translate` (Submit-/Display-Flow unverändert). **Cursor-Payload:** `q_translations` ist jetzt `dict[str, list[str]]` und reist pro Sprache als **Liste** im `qt`-Map-Cursor (nur `cursor.py`-Typen angepasst, JSON-Logik unverändert). **Contract-Test-Erkenntnis:** neuer Unit-Test `test_multi_candidate_or_expansion` (zwei stamm-**distinkte** Kandidaten müssen **beide** matchen — beweist die OR-Expansion, nicht nur einen Treffer); dabei mussten die bestehenden Such-/Relevance-/Cursor-Mocks von Einzelstring auf **Listen**-Rückgabe umgestellt werden (`translate_query` gibt jetzt `list`, nicht `str|None`). Regel: verwandelt ein Feature einen Single-Value-Contract in einen Multi-Value-Contract (eine Übersetzung → Kandidatenliste), müssen **alle** Mocks derselben Funktion synchron auf den neuen Rückgabetyp wandern — sonst grünt der neue Test, aber die Altbestands-Tests brechen still am Typ. Exakte Treffer-Parität DE↔EN bleibt best-effort (LLM-Übersetzung nicht-deterministisch); die semantische Suche bleibt der garantierte cross-linguale Pfad.

**Konkreter Fund 39:** Freitext-Filter braucht Substring-ILIKE, nicht Ganzwert-ILIKE (2026-06-27 Live-Verify, F1, #29).
Der `company`-Filter (`_build_filter_clauses`, `routers/problems.py`) nutzt `User.company.ilike(n)` **ohne** `%`-Wildcards = Ganzwert-Match (nur case-insensitiv). Live-Verify: Tippen von `Acme` ins Freitext-Company-Feld liefert **0 Treffer**, weil die Seed-Firma `Acme Manufacturing GmbH` heißt — nur der exakte, vollständige Name (oder der Panel-Chip, der ihn emittiert) filtert. Für ein **Freitext**-Eingabefeld widerspricht das der Nutzererwartung (der violette Panel-Chip emittiert den Voll-Namen, dort passt Ganzwert; das Eingabefeld aus #29 nicht). Plan-Annahme war „eindeutige Firmennamen" — hält in der Praxis nicht. **Entscheidung des Users:** statt den Ganzwert-Match auf Substring (`User.company.ilike(f"%{n}%")`) aufzuweichen, wurde das Freitext-Eingabefeld wieder **entfernt** (Revert `ebb759f`); Firmen-Filtern bleibt über Panel-Chip + `?company=`-URL + aktive Tabellen-Chips, die alle den exakten Voll-Namen liefern. Der Substring-Patch ist bewusst offen gelassen. Regel: ein **Freitext**-Filterfeld impliziert Substring-Match; exakter ILIKE ist nur für Chip-/Dropdown-Quellen vertretbar, die den kanonischen Voll-Wert liefern — passt die Backend-Semantik nicht zur Eingabe-Affordanz, ist das Entfernen der Affordanz eine valide Alternative zum Aufweichen des Matches.

**Konkreter Fund 40:** Test-DB-Umstellung SQLite → ephemeres Postgres+pgvector (testcontainers) (2026-06-27, BE `c183ed2`…`ad7f1a9`).
Die Backend-Unit-Tests liefen bisher gegen In-Memory-SQLite mit `Base.metadata.create_all` — pgvector-/JSONB-/Constraint-Semantik war nicht testbar, ~7 Tests waren `skipif`-on-sqlite ausgesperrt. Neu: `conftest.py` startet ein ephemeres `pgvector/pgvector:pg16`, baut das Schema mit **`alembic upgrade head`** auf (nicht `create_all` — testet damit zugleich die Migrationen), lädt System-Seeds + einen Baseline-User. Die `skipif`-Marker und `aiosqlite` sind raus; pgvector-Semantik-Tests und 3 vormals leere `@skip`-Stubs (`upsert_tag`, `assign_structural_tag`, `similarity_search`) laufen jetzt echt. Drei nicht-offensichtliche Erkenntnisse:
(1) **Event-Loop-Falle.** Der naheliegende Entwurf — session-scoped Async-Engine + manueller `after_transaction_end`-Listener für Rollback-Isolation — crasht mit *„Future attached to a different loop"* (pytest-asyncio gibt jedem Test einen frischen Loop, die session-scoped Engine hängt am ersten). Lösung: **Setup synchron** (psycopg2: `alembic upgrade`, Seeds, Baseline-User), Engine/Session **function-scoped**, Isolation über SQLAlchemy-2.0-`join_transaction_mode="create_savepoint"` statt fragilem Listener. Regel: keine session-scoped Async-Engine über function-scoped Loops teilen — Setup synchron, Async-Ressourcen pro Test.
(2) **Drift-Guard via `compare_metadata`, nicht `command.check`.** `alembic check` (Plan-Vorschlag) failt hier **immer**, weil Indizes/Constraints per Projekt-Konvention nur in den Migrationen leben, nicht in `__table_args__`. `test_schema_migrations_sync.py` prüft daher gezielt **strukturellen** Drift (Tabelle/Spalte/Typ) via `compare_metadata` und toleriert reine Index-/Constraint-Diffs bewusst. Regel: ein Models↔Migrationen-Drift-Guard muss zur Konvention passen, wo Indizes/Constraints definiert sind — sonst meldet er Dauer-Fehlalarm.
(3) **Echtes Postgres = echte Constraints.** Mit SQLite tolerierte Asserts brachen unter den realen FK/CHECK/UNIQUE-Regeln: Solutions brauchen ein echtes Problem (FK), Titel ≥10 Zeichen (CHECK), eindeutige Region-Codes (UNIQUE), und die 9 System-Seed-Tags zählen in Tag-/Cluster-Asserts mit. Regel: nach dem Umzug auf die echte Engine zählt die Seed-Baseline in jeder Count-Assertion mit — Fixtures gegen reale Constraints schreiben, nicht gegen die laxe Test-DB.
Damit entfällt die frühere „läuft nur gegen Postgres (skip sonst)"-Einschränkung der pgvector-/Keyset-/Semantik-Tests (Fund 31) — die Test-DB **ist** jetzt Postgres. Die `.with_variant(JSON(), "sqlite")`-Modell-Absicherung aus Fund 30 ist damit totes Legacy (harmlos, aber nicht mehr nötig).

**Konkreter Fund 41:** Funktionaler GIN-FTS-Index nur wirksam, wenn die Index-SQL **byte-identisch** zur Query-SQL ist (2026-06-27, BE `b7563e9`/`8982048`, F2).
Ein funktionaler Index auf `to_tsvector(config, …)` wird vom Planner nur genutzt, wenn der Query-Ausdruck **exakt** denselben SQL-Text erzeugt — schon eine abweichende `coalesce`-Reihenfolge oder Whitespace lässt den Planner auf einen Seq-Scan zurückfallen (kein Fehler, nur stiller Performance-Verlust). Lösung: **eine** Helper-Funktion `tsvector_sql(lang, config)` in `services/search_languages.py` als Single Source of Truth, die sowohl die Migration 010 (Index-DDL) **als auch** die WHERE-Klausel in `list_problems` speist — der Index-Ausdruck kann gar nicht von der Query driften. Die Sprach-Registry `SEARCH_LANGUAGES` ist derselbe SSoT für die Loop-Sprachen (eine Sprache hinzufügen = ein Tupel + eine Index-Migration, kein weiterer Code-Change). Regel: jeder funktionale Index, der von einer Query getroffen werden soll, generiert seinen Ausdruck aus **derselben** Funktion wie die Query — nie zwei handgeschriebene Kopien. Ändert sich der Output, nutzt der Planner bestehende Indizes nicht mehr → Reindex-Migration nötig. Unit-Tests (`tests/unit/`): `test_fts_indexes.py` prüft die Index-Existenz, `test_fts_stemming_symmetry_english_plural` die Wirkung (Stamm-Symmetrie `company`/`companies`); Drift fängt zusätzlich `test_schema_migrations_sync.py`.

**Konkreter Fund 42:** `sort=relevance` — `ts_rank`-Ranking ohne `score`-Exposition, Keyset auf `(rank, id)`, graceful Fallback ohne `q` (2026-06-28, BE `59a2b29`, F2 Task 4, #37).
Das opt-in Relevanz-Ranking summiert `ts_rank` über **alle** Registry-Sprachen (pro Sprache die übersetzte Variante, Fallback `q_raw`) und sortiert `ORDER BY rank DESC` + Keyset auf `(rank, id)`; der `rank`-Wert reist im Cursor mit. Drei nicht-offensichtliche Entscheidungen, je durch einen Unit-Test abgesichert (`tests/unit/test_problems_relevance.py`): (1) **Keine `score`-Exposition.** Anders als der Semantik-Modus (`score = 1 − Distanz` im `ProblemRead`) gibt `sort=relevance` den `ts_rank`-Wert **nicht** ans Frontend — er lebt nur als interne `rank`-Spalte für die Keyset-Ordnung. Begründung: `ts_rank` ist eine unkalibrierte, korpus-relative Zahl ohne sinnvolle Prozent-Interpretation; ein „{n}% Match"-Badge wäre irreführend (Test: `test_relevance_orders_stronger_match_first` prüft nur die *Reihenfolge* — Term in Titel+Beschreibung rankt vor nur-Beschreibung). (2) **`sort=relevance` ohne `q` ist kein Fehler.** Ohne Suchbegriff fehlt das Ranking-Signal — statt 422 fällt der Modus **graceful auf `created`** zurück (Test: `test_relevance_without_q_falls_back_to_created`). Regel: ein opt-in Sort-Modus, dessen Signal von einem anderen Param abhängt, degradiert bei fehlendem Signal still auf den Default-Sort, statt zu werfen — der Client darf den Modus setzen, ohne ihn an die `q`-Präsenz koppeln zu müssen. (3) **Keyset über `(rank, id)` ist überlappungsfrei** wie die anderen Modi — der Test paginiert beide Seiten durch und asserted Disjunktheit + Vollabdeckung (`test_relevance_keyset_pagination_no_overlap`), nicht nur Seite 1 (vgl. Fund 32/33). Frontend-Opt-in (Task 5) seit FE `d3a6950` gelandet; Extensibility-Smoke/Doku (Task 6) seit BE `820083e` gelandet — alle sechs F2-Tasks drin.

**Konkreter Fund 43:** Final-Review F2 (I-1) — Persist-Allowlist `_ALLOWED_TRANSLATION_LANGS` aus der Such-Registry ableiten, sonst hat die „Registry + Index, kein Code-Change"-Zusage ein stilles Leck (2026-06-28, BE, F2 Final-Review).
Die Extensibility-Zusage aus Fund 41/42 (eine Such-Sprache hinzufügen = `SEARCH_LANGUAGES`-Tupel + funktionaler Index) übersah einen zweiten Code-Pfad: `_filter_translations` in `routers/problems.py` verwirft jede eingehende `original_translations`-Sprache, die **nicht** in der hartkodierten `_ALLOWED_TRANSLATION_LANGS`-Menge (`{de,fr,es,it,pt,nl,pl}`) steht. Eine neu registrierte Such-Sprache **ausserhalb** dieses Sets hätte zwar einen FTS-Index bekommen, aber ihr User-Originaltext wäre beim Schreiben **still gefiltert** worden — der `q_raw`/`original_translations`-Match liefe dann ins Leere, ohne Fehler. Fix: `_ALLOWED_TRANSLATION_LANGS = {…} | {lang for lang, _ in SEARCH_LANGUAGES if lang != "en"}` — die Allowlist erbt jede Registry-Sprache automatisch; `search_languages.py` trägt einen Rück-Verweis-Kommentar, damit die Kopplung sichtbar bleibt. Regel: bei „eine Registry ist Single Source of Truth"-Zusagen **jeden** Pfad prüfen, der dieselbe Sprach-/Schlüssel-Menge unabhängig hartkodiert (Persist-Allowlist, Validierung, Serialisierung) — ein zweiter, nicht abgeleiteter Gatekeeper macht die Zusage still unwahr. (Mit-Cleanup: `_DEFAULT_DIRECTION` um `relevance: desc` ergänzt; `q_raw`-Docstring spiegelt die jetzige Nutzung als Per-Sprache-Rank-Fallback statt „reserviert/ungenutzt".)

**Konkreter Fund 44:** Firma des Autors als angezeigte, sortierbare Table-Spalte — gebatchter Resolve (kein N+1) + `coalesce`-Keyset für die nullable-Beziehung (2026-06-29, BE + FE).
Die `company`-Filter-Infrastruktur (#29/#35) lieferte die Firma nie ans Frontend zurück — sie war nur ein WHERE-Kriterium. Diese Session exponiert sie als `ProblemRead.company` und macht sie als eigene Table-Spalte sortierbar. Zwei nicht-offensichtliche Entscheidungen, je TDD-abgesichert (`tests/unit/test_problems_filters.py`, erst RED dann GREEN): (1) **Pro-Seite gebatcht statt pro-Item.** Die Firma sitzt auf `users`, nicht auf `problems` — ein naiver Lookup pro Zeile wäre N+1. `_load_companies(session, problems)` (seit Fund 47 zu `_load_authors` erweitert — holt zusätzlich `display_name`) holt `{user_id: company}` für die **distinkten** Autoren einer Seite über **einen** `select(User.id, User.company).where(User.id.in_(…))` und reicht ihn an `_to_read(company=…)` — gleiche Mechanik wie `_load_junctions`; läuft in `list_problems` **und** `_list_problems_semantic`. Anonyme Probleme (`user_id IS NULL`) tragen keinen Eintrag → `company=None` (Test: `test_response_company_null_for_anonymous` — anonym darf nie werfen). (2) **`coalesce(User.company, '')` als NULL-freier Keyset-Key.** Der `sort=company`-Modus outer-joint `users` und sortiert über `coalesce(User.company, '')` — anonyme/firmenlose Probleme fallen in den `''`-Bucket (bei `asc` vorne), exakt der `tag`-Sort-Trick (Fund 33). Ein nullable Sort-Key bräche den Keyset-Vergleich; der `''`-Default hält ihn simpel und portabel. Keyset-Disjunktheit über zwei Seiten getestet (`test_sort_company_keyset_no_overlap`, vgl. Fund 32/33), bidirektional via `dir` (`_DEFAULT_DIRECTION["company"]="asc"`). Frontend: `Problem.company` (`mapProblem`: `raw.company ?? null`), `SortKey`/`toBackendSort`/`fromBackendSort` um `company` erweitert, neue `hidden lg:table-cell`-Spalte (`colspan` 6→7), Klick auf die Zelle setzt den `company`-Filter. Die Zelle rendert die Firma als kompakten **Monogramm-Badge** (`utils/companyBadge.ts`: `companyInitials()` 1–2 Initialen, Voll-Name im `title`; `companyColor()` deterministische Farbe) statt Klartext — hält die Spalte bei ~56px. **DRY-Refactor:** `tagColor.ts` exportiert jetzt ein generisches `colorFromString(key)`; `tagColor()` (Tag-ID) und `companyColor()` (lowercase-getrimmter Name) rufen es auf — eine Palette, gleiche Identitätsfarbe wie die Cluster-Dots, kein dupliziertes Hash→Palette-Schema (9 neue `companyBadge`-Tests). Regel: ein abgeleitetes Feld auf einer 1:N-Beziehung wird **pro Seite gebatcht** aufgelöst (nie pro Item), und ein Sort darüber nutzt `coalesce(col, '')` als NULL-freien Keyset-Key — derselbe Trick wie jeder andere nullable Sort-Modus.

**Konkreter Fund 45:** Ein vom Backend geliefertes Feld nie hinter einem clientseitigen Cache-Lookup verstecken (2026-06-29, FE `9b8f357`, #30).
Direkte Folge von Fund 44: das Firmen-Chip im Problem-Panel (`ProblemPanel.vue`) hing — wie schon vor der Company-Spalten-Arbeit — an `author = getUserById(problem.userId)` und renderte `author.company`. `getUserById` liest den clientseitigen `userCache`, der **nur den eingeloggten User** auflöst; für jeden normalen Betrachter ist `author` `null`, also blieb der **ganze** `v-if="author"`-Block (Autor- **und** Firmen-Chip) unsichtbar — die Firma war „nirgends angezeigt", obwohl das Backend sie seit Fund 44 auf **jedem** `ProblemRead.company` mitliefert. Fix: das 🏢-Chip liest `problem.company` direkt (`v-if="problem.company"`), der Block-Wrapper gated auf `author || problem.company`, das 👤-Autor-Chip bleibt best-effort (`v-if="author"`). Regel: sobald ein Feld auf der vom Backend gelieferten Entität liegt, **direkt aus der Entität rendern** — ein clientseitiger Lookup (User-Cache, Author-Resolve) als Sichtbarkeits-Gate koppelt die Anzeige an einen Zustand, der nur für eigene/eingeloggte Daten gefüllt ist, und versteckt das Feld still für alle anderen. Kein Vitest-Test (reine Render-Bedingung; 136 Tests grün, ESLint 0); Erkennungsmerkmal ist die Diskrepanz „Backend liefert das Feld immer" vs. „UI gated es hinter `author`/Cache". (Das 👤-Autor-Chip wurde in Fund 47 nach derselben Regel nachgezogen.)

**Konkreter Fund 46:** Ein Deep-Link-Reduce muss sein Ziel direkt fetchen — nie per `find()` im bereits geladenen, paginierten Set suchen (2026-06-29, FE `3d89391`).
Der Table-View-Permalink (`?problem=<id>`) zeigte „alle Einträge weiterhin angezeigt" und ein geschlossenes Panel. Ursache: `onMounted` suchte das Ziel nur per `problems.value.find(...)` in der **bereits geladenen ersten Seite** (`loadFirstPage`, Default-Limit 50, `sort=created`) und reduzierte die Liste nie. Bei Keyset-Pagination liegt das verlinkte Problem oft **gar nicht** auf Seite 1 → `find` schlug fehl, Panel blieb zu, Liste ungefiltert. Die Graph-View machte es bereits korrekt (`fetchProblemById` → `problems = [target]`). Fix: bei gesetztem `focusProblemId` holt `onMounted` das Problem direkt via `fetchProblemById`, ersetzt `problems` durch den einen Eintrag (`total=1`, `hasMore=false`) und öffnet das Panel; nicht gefunden (gelöscht/nicht sichtbar) → `clearFocusProblem()` + volle Liste. Der Dismiss-Chip ruft `handleClearFocus()` (lädt `loadFirstPage` nach), sonst bliebe der reduzierte Eintrag stehen. Regel: ein „auf genau X reduzieren"-Flow (Permalink, Deep-Link, Single-Select) holt X **direkt vom Server** — die clientseitig geladene Seite ist bei serverseitiger Pagination keine verlässliche Quelle. Kein Vitest-Test (Deep-Link-Flow; 136 grün, ESLint 0); manuell gegenzutesten.

**Konkreter Fund 47:** Derselbe Cache-Lookup-Fehler beim Autor-Chip — `author_display_name` reist jetzt auf jedem `ProblemRead` mit (2026-06-29, BE `2e9946f` + FE `70f8a84`, #30).
Fund 45 entkoppelte das Firmen-Chip vom `userCache`, ließ aber das 👤-Autor-Chip bewusst best-effort (`v-if="author"`) — für fremde Autoren also weiterhin unsichtbar, obwohl jeder approved Autor in der DB einen `display_name` trägt. Gleiche Wurzel, gleicher Fix: Das Backend liefert den Namen jetzt direkt als `ProblemRead.author_display_name`. Statt eines zweiten Lookups wurde `_load_companies` zu **`_load_authors`** umgebaut — holt `company` **und** `display_name` der distinkten Seiten-Autoren in **einer** Query (vorher zwei) und gibt `{user_id: (company, display_name)}` zurück; beide Call-Sites (`list_problems` + `_list_problems_semantic`) angepasst. Frontend: `Problem.authorDisplayName` (`mapProblem`), neuer `authorLabel`-Computed im `ProblemPanel` — `problem.authorDisplayName` **zuerst** (für jeden Betrachter da), dann Cache-Fallback (`author.displayName ?? author.email`, eigener/gecachter User); das Chip gated auf `authorLabel`, `user-filter` emittiert `problem.userId` (nicht mehr `author!.id`, das ohne Cache `undefined` wäre). Damit erscheint das Autor-Chip bei **jedem** nicht-anonymen Problem. TDD: zwei neue Backend-Tests (`author_display_name` im Response; `null` ohne gesetzten Namen — erst RED, dann GREEN; 188 BE / 136 FE grün, ESLint 0). Verschärfung zu Fund 45: liegt ein Anzeige-Feld auf der Entität, **vom Backend liefern und direkt rendern** — ein clientseitiger Cache-Fallback ist nur Beiwerk, nie das primäre Sichtbarkeits-Gate; und ein zweites abgeleitetes Feld auf derselben 1:N-Beziehung wird in **dieselbe** gebatchte Query gezogen, nicht in eine zweite.

**Konkreter Fund 48:** KI-Marker als eigenes Designsystem — wiederverwendbare `AiBadge.vue` als **einziger Enforcement-Punkt** + dedizierter `--th-ai-accent`-Token statt N divergenter Inline-Badges (2026-06-29, FE `94c57e3`/`b42707d`/`8216cc9`/`59bc7b9`, #39).
„Das hat die KI gemacht" war über die UI verstreut in **sechs** divergenten `is_ai_generated`-Badges kodiert (2× generischer `--th-accent`, 2× hartkodiertes `bg-purple-*`, 1× nacktes 🤖-Emoji) — visuell uneinheitlich und nirgends vom User-CTA-Akzent unterscheidbar. Konsolidierung in zwei Schritten: (1) **Eigener Token `--th-ai-accent`** (+ `-hover`), pro Theme handgetönt in `assets/css/themes.css`, immer gegen den jeweiligen `--th-accent` kontrastierend (kühle Accents → Violett, warme/grüne → Cyan; `glass-dark`-Default → Fuchsia gegen Sunset), als Tailwind-Utility registriert, via `rgb(var(--th-ai-accent) / <alpha>)` genutzt (Alpha-Modifier-Pattern, Fund 22), User-Override in `/settings` persistiert unter `dm-ai-accent` und in `initTheme()` restored (spiegelt `dm-accent`). Begleitend ein **On-Accent-Text-Token `--th-ai-accent-text`** (FE `79c0d7e`, theme-aware seit `4bc6d96`) statt Zweckentfremden des `--th-accent-text` — die Text-auf-KI-Akzent-Farbe ist eigenständig themebar (weiß in `:root` + dunklen Themes, in den vier hellen Themes `default`/`forest`/`sunset`/`glass-light` auf dunkel überschrieben), sodass das AI-Match-Badge seinen Text gegen Karo+Balken absetzt, ohne Token-Kopplung an den User-CTA-Akzent. Das Badge trägt die Farbe **inline** (`rgb(var(--th-ai-accent-text))`, gleiches Idiom wie der Mini-Balken daneben), **nicht** über die Tailwind-Utility `text-th-ai-accent-text` — eine im Dev neu eingeführte text-Utility regeneriert der Tailwind-JIT nicht zuverlässig sofort (s. Fund 34, Folge-Fix `52e7b67`), der Inline-Style greift über Vue-HMR. (2) **`AiBadge.vue`** kapselt das KI-Vokabular (4-Punkt-Funkel-Icon + `--th-ai-accent` + erklärender Tooltip) in **einer** Komponente (Props `label`/`tooltip`/`size`, DOM-frei → prerender-sicher, Texte aus neuem i18n-`ai`-Namespace, en+de) und ist der Enforcement-Punkt: jeder KI-Touchpoint importiert sie, statt sein eigenes Badge zu malen. Rollout über alle KI-Flächen (Solution-Karten/-Popup/-Detail, ProblemPanel, `problem/[id]`, Duplikat-Similarity-Karten + Cosine-`%`, AI-Draft-Button, KI-Suche-Toggle, Übersetzungs-Button, LLM-Moderations-System-Note — Cluster-Markierung am **Spalten-Header**, nicht an den Chips). Regel: wenn dieselbe semantische Markierung (》KI-generiert《, 》validiert《, 》extern《) an ≥3 Stellen mit driftenden Inline-Styles auftaucht, ist das ein Designsystem — ein Token für die Farbe **und** eine Komponente als Enforcement-Punkt, nicht N Kopien; die Komponente ist die Stelle, an der das Vokabular erzwungen wird, der Token die Stelle, an der die Farbe themebar bleibt. Spiegelt Fund 16 (eine Palette, eine Identität) auf der Badge-Ebene.

**Konkreter Fund 49:** Eine Empty-/Loading-Bedingung muss dieselbe Quelle prüfen, aus der gerendert wird — ein Legacy-Array-Längen-Check überlebt einen Render-Quellen-Refactor still (2026-06-30, FE `components/ProblemGraph.vue`).
Das Empty-Overlay im Graphen (»Noch keine freigegebenen Probleme.«) hing an `v-if="problems.length === 0"` — eine Bedingung aus der Pre-Phase-2-Architektur, in der der Graph **alle** Probleme lud. Seit dem Lazy-Cluster-Summary-Drill-Down (Fund 35/36, Task 2.3) rendert die Mindmap-**Übersicht** ihre Knoten aber aus `clusterCounts`/`unclusteredCount` (Aggregat-Props), während `props.problems` leer bleibt, bis ein Cluster gedrillt wird. Dadurch war `problems.length === 0` in der Übersicht **dauerhaft** wahr → die Meldung lag permanent über dem korrekt gerenderten Graphen, ohne Fehler. Fix: die Bedingung spiegelt jetzt **alle drei** echten Render-Quellen: `v-if="problems.length === 0 && clusterCounts.size === 0 && unclusteredCount === 0"`. Regressionstest `tests/components/ProblemGraph.empty-overlay.spec.ts` (3 Fälle: Cluster vorhanden / nur Unclustered / wirklich leer — vor Fix rot, nach Fix grün; 143 FE grün, ESLint 0). Regel: ändert ein Refactor die Render-Quelle einer Visualisierung (Voll-Array → Aggregat, Fund 35/36), muss **jede** davon abgeleitete Bedingung mitziehen — Empty-State, Counts, Badges; ein stehengebliebener `array.length`-Check liest die alte Quelle und liefert ein dauerhaft wahres (oder falsches) Gate ohne Konsolen-Fehler. Erkennungsmerkmal: ein Overlay/Spinner, der unabhängig vom sichtbaren Inhalt klebt.

**Konkreter Fund 50:** Glass-Light — Sidebar bekommt einen dezenten dunklen Tint, damit die App-Shell-Fläche sich vom hellen Hintergrund abhebt (2026-06-30, FE `components/DmSidebar.vue`, Commit `4feef2b`).
Auf der warmen Paper-Glass-Light-Fläche (`#F4F1EA`) mit dunkler Schrift lief die Sidebar mit `rgba(255,255,255,.5)` (50% Weiß) ohne Abgrenzung in den Hintergrund. Fix: **Sidebar** im Glass-Light auf `rgba(0,0,0,.10)` (eine einzige Alpha-Stellschraube, höher = dunkler), strikt auf den Light-Zweig begrenzt (`isGlassTheme && !isDark`) — **Glass-Dark** behält `rgba(0,0,0,.2)`, Nicht-Glass-Themes ihren `rgb(var(--th-surface))`-Pfad. Schrift und Icons unverändert — die Sidebar-Fläche bleibt hell genug für die dunklen Texte. Reiner Inline-Tint, keine neuen Tests (143 FE grün). Die Sidebar nutzt konstantes Schwarz mit niedrigem Alpha (`rgba(0,0,0,.10)`) — eine bewusste Ausnahme vom Token-Pfad (Fund 21), analog zum 50%-Grau der Inner-Cards (Fund 23): theme-agnostisch lesbar auf hellem Glass, kein akzent-/oberflächengebundener Wert. **Tabellen-Header und TopBar bewusst nicht angetastet:** Ein Ansatz, den Sticky-Tabellen-Header im Glass-Light per verschachteltem `data-theme="glass-dark"` als **echte dunkle Bar** zu rendern (Header-Subtree löst dann den dunklen Tokensatz auf), wurde evaluiert, aber **nicht** ausgeliefert — `headerStyle` (`pages/table.vue:544`) bleibt für **beide** Glass-Themes schlicht `rgba(var(--th-surface) / 0.9)`, der Light-Header bleibt also hell. Auch die TopBar bleibt in **beiden** Glass-Modi `transparent` (die README-Zusage »transparente TopBar« gilt unverändert für Light **und** Dark). **Festgehalten für später:** `assets/css/themes.css` scoped **alle** `--th-*`-Tokens unter `[data-theme="…"]`, daher lässt ein verschachteltes `data-theme`-Attribut einen Subtree den **kompletten** Tokensatz eines anderen Themes auflösen (Hintergrund **und** Text kippen zusammen) — sauberer als Einzel-Zellen umzufärben, falls ein Bereich künftig konsistent wie ein anderes Theme aussehen soll.

**Konkreter Fund 51:** `cy.style()` gehört **vor** `cy.batch()`, nie hinein — ein im Batch gesetzter Style greift nicht auf die im selben Batch hinzugefügten Elemente (2026-06-30, FE `components/ProblemGraph.vue`).
`rerender()` setzte das Stylesheet (`cy.style(buildStyle())`) zusammen mit `elements().remove()` + `add()` in **einem** `cy.batch()` (eingeführt mit dem Overlap-Fix #33). Cytoscape wendet einen im Batch gesetzten Style aber **nicht** auf Elemente an, die im selben Batch hinzugefügt werden — sie fallen auf die Cytoscape-Defaults zurück: Edges auf grau (`#999`), Haystack-Kurve, dick; die Dekorations-**Knoten** `cluster-dot`/`cluster-count-badge` auf den 30px-Grau-Default-Kreis. Symptom: »fette graue Edges **und** graue Punkte, sobald man ein Problem anklickt« — **eine** Ursache, kein HMR-/Staging-Problem (Hard-Reload maskierte es nur, weil ein frischer Mount den Style korrekt setzt; erst der nächste `rerender` schlug zu). Fix: `cy.style(buildStyle())` **vor** den `cy.batch()` ziehen, der Batch enthält nur noch `remove()`+`add()` — der eine Fix behebt Edges und Dots gemeinsam (143 FE grün, ESLint 0). Im `ProblemGraph.vue` existiert nur **dieser eine** `cy.batch()`-Block; die übrigen `.style()`-Aufrufe stehen bereits korrekt außerhalb. Regel (spiegelt den CLAUDE.md-Gotcha): Style-Mutationen nie mit Element-Mutationen im selben `cy.batch()` mischen — `cy.style()` zuerst und außerhalb, dann den Batch nur für `remove()`/`add()`.

**Konkreter Fund 52:** Drill-Fit nur auf den **echten** Knoten — die Layout-eigene `fit: true` fittet die Dekorations-Badges mit, die zu dem Zeitpunkt noch bei `(0,0)` liegen, bläht die Fit-bbox auf und hinterlässt einen falschen (zu niedrigen, ~67 %) Zoom; `fitDrillView()` re-fittet im `stop` ausschließlich auf die sichtbaren Echt-Knoten und deckelt auf `FIT_MAX_ZOOM = 1` (2026-06-30, FE `components/ProblemGraph.vue`).
`showUnclusteredView`/`applyTagFilters` layouten mit `fit: true` — aber die Badges (`cluster-dot`/`cluster-count-badge`/`vote-score-badge`) stehen nicht in den `positions` und sitzen während des Layout-Fits noch bei `(0,0)`; die Fit-bbox umschließt sie mit, der Endzoom fällt zu niedrig aus (Symptom: gedrillte Ansicht bei ~67 % statt voller Breite). Fix: Layout **und** Fit laufen nur noch auf den Echt-Knoten (`.problem-node, .inner-cluster-node, .leaf-cluster-node, .root-node, .unclustered-node` — Badges ausgeschlossen), und `fitDrillView()` (aufgerufen im `stop:`-Callback **und** im Non-Animate-Pfad beider Layouts) fittet nach dem Settle erneut auf genau diese Knoten, deckelt `cy.zoom() > FIT_MAX_ZOOM` auf `1` und `cy.center(real)`. Ein Fix behebt beides: den Unter-Zoom durch Badge-Inflation **und** den Über-Zoom auf dünnen Clustern (wenige Nodes → `fit` skaliert über 100 %). Nur der Viewport-Zoom ändert sich, die Modell-Positionen nicht — der nächste `fit`/Re-Layout rechnet wieder frisch.

**Konkreter Fund 53:** Grid-Layout node-relativ + feste Gutter statt situativer Magic-Numbers — Abstand = Node-Größe + **fester** Gap pro Achse, dann **genau ein** zoom-gecapptes `fit` skaliert das Ganze uniform in den Viewport (2026-06-30, FE `components/ProblemGraph.vue`, ersetzt den früheren `ROW_STEP`/Offset-Ansatz).
`buildProblemsGridPositions` rechnete Spalten-/Zeilen-Pitch als Bruchteil des `usableW`/`usableH` (Container minus Padding) — dadurch handelte jede Achse mit der anderen **und** mit dem Item-Count, was bei DE-Labels (~25% höhere Nodes, s. `buildStyle` `n()`) zu berührenden Reihen führte und punktuelle Locale-Offsets (`ROW_STEP = round(108·s)`) nötig machte. Neuer Ansatz: die Tiers werden in ihrer **natürlichen** Größe ausgelegt — `cellW = problemW + GUTTER_X`, `cellH = problemH + GUTTER_Y`, `TIER_GAP` zwischen Anchor → Children → Grid; jeder Abstand ist eine **unabhängige** Konstante aus Node-Footprint + festem Gap (alle mit demselben Locale-Faktor `s = 1` EN / `1.25` DE wie `buildStyle.n()` skaliert, **keine** Achse als Funktion des Counts oder des Containers). Das Grid darf den Viewport überschreiten — das **eine** `fit` (zoom-gecappt ≤100%, Fund 52) skaliert alles uniform herunter, die Gutter skalieren proportional mit. Die **Spaltenzahl** wählt `buildProblemsGridPositions` als die, die den Fit-Zoom für den aktuellen Container **maximiert** (Schleife über alle `c`, `z = min(availW/contentW, availH/contentH)`, `cols` = arg max `z`) — nicht `round(sqrt(count·aspect))`, dessen Rundung bei winziger Aspekt-Änderung die Spalten (und damit Zeilen und Fit) umspringen ließ und die eigentliche Ursache des instabilen 67 %↔99 %-Zooms war; die Gutter bleiben fix, nur die Grid-**Form** adaptiert. Vier Prinzipien ersetzen das Abstands-Gefummel: (1) Spacing node-relativ + feste Gutter (unabhängige Konstanten je Achse), (2) Spaltenzahl = die den Fit-Zoom maximierende (deterministisch, kein Rundungssprung), (3) genau ein `fit` auf den Echt-Knoten skaliert uniform (Fund 52), (4) `ResizeObserver` re-fittet bei Container-Resize (Fund 54). Regel: Layout-Abstände als Node-Größe + feste Konstante definieren und **einmal** per zoom-gecapptem `fit` einpassen — nie als Container-Bruchteil, der Achsen und Count miteinander verhandeln lässt und situative Magic-Numbers nach sich zieht.

**Konkreter Fund 54:** Cytoscape erkennt Container-Resize nicht selbst — `ResizeObserver` → `cy.resize()` + Re-Layout des aktiven Views, sonst rutscht der Graph beim Öffnen des Detail-Panels unter das Panel (2026-06-30, FE `components/ProblemGraph.vue`).
Öffnet sich das Detail-Panel (Graph-Bereich schrumpft auf ~70%), bleibt das Cytoscape-Canvas auf der alten Breite zentriert und schiebt sich unter das Panel — Cytoscape feuert kein Resize-Event von selbst. Fix: ein `ResizeObserver` auf `containerRef` ruft bei jeder **Breiten**-Änderung (`Math.abs(w - lastWidth) >= 1`) `cy.resize()` und nach 280ms-Debounce `reapplyCurrentLayout(false)` — der re-runt `applyTagFilters` (gedrillt) bzw. `showMindmap` (Übersicht), beide mit dem zoom-gecappten `fit`, sodass der Graph sich **immer** an den verfügbaren Platz anpasst (Panel auf/zu, Fenster-Resize) statt einmalig auf eine feste Breite gerechnet zu sein. Der Debounce ist bewusst 280ms (nicht ~160ms): das Detail-Panel öffnet/schließt mit einer CSS-Width-Transition, die den `ResizeObserver` in **jedem** Frame feuert — ein kürzerer Debounce re-fittet mitten in der Animation auf eine Zwischenbreite und hinterlässt einen falschen (stale) Zoom; 280ms überdauert die Transition, sodass der Fit immer die Endbreite trifft. Cleanup: `resizeObserver.disconnect()` + `clearTimeout` in `onUnmounted`. jsdom kennt `ResizeObserver` nicht — `tests/setup.ts` liefert einen No-Op-Polyfill (sonst werfen die Mount-Tests). Regel: jede Cytoscape-Komponente, deren Container seine Größe ändern kann (Panel, Drawer, Split-View), braucht einen `ResizeObserver` → `cy.resize()` + Re-Fit; die einzige robuste Adaption, keine hartkodierten Breiten.

**Konkreter Fund 55:** `saveCurrentPositions` darf nie eine transiente `(0,0)`-Position persistieren — ein `dragfree` während des „add-at-origin"-Frames vergiftet sonst den Storage und stapelt künftig **alle** Nodes übereinander (2026-06-30, FE `components/ProblemGraph.vue`).
`rerender()` fügt neue Nodes ohne Position bei `(0,0)` hinzu, bevor das `preset`-Layout sie setzt (s. Overlap-Fix #33). Feuert in genau diesem Frame ein `dragfree`-Event, schreibt `saveCurrentPositions` `{0,0}` für jeden noch nicht positionierten Knoten in `localStorage['graph-node-positions']` — beim nächsten Laden restauriert `applyStoredPositions` diese `(0,0)` und alle Boxen liegen aufeinander (der »überlappende Boxen«-Bug, der auch nach einem Reload bleibt, weil er aus dem Storage kommt). Fix: `saveCurrentPositions` überspringt jeden Knoten mit exakt `x === 0 && y === 0`. Regel: einen Persistenz-Snapshot nie ungefiltert aus einem State ziehen, der einen legitimen Übergangs-Nullwert kennt — den transienten Sentinel (`(0,0)` vor dem Layout) explizit ausschließen, sonst überlebt er im Storage und korrumpiert jeden Folge-Load.

**Konkreter Fund 56:** Klick auf den bereits gedrillten Cluster ist ein No-op — `addTagFilter` returnt früh, wenn der Tag schon im Filter-Set ist, sonst re-fittet/re-animiert `applyTagFilters` die identische Ansicht und das liest sich als ruckartiger Zoom-Sprung (2026-06-30, FE `components/ProblemGraph.vue`).
`addTagFilter(tagId)` hängte den Tag früher auch dann an (`includes`-Guard nur gegen Doppel-Eintrag im Array), wenn er bereits der aktive Anchor war — der reaktive Watcher löste ein erneutes `applyTagFilters` aus, das dieselbe Ansicht mit `fit`/Animation neu rechnete: sichtbar als kurzer korrigierender Zoom-Snap auf genau dem Cluster, den der User schon offen hat. Fix: `if (tagFilterIds.value.includes(tagId)) return` **vor** der Mutation — nur ein tatsächlich neuer Tag (eine Ebene tiefer drillen) löst Layout + Lazy-Load aus. Regel: ein Navigations-Trigger, der den bereits aktiven Zustand erneut setzt, muss ein No-op sein — sonst bezahlt der User für seinen Klick mit einem Re-Layout-Flackern.

**Konkreter Fund 57:** Zoom-Overshoot beim Drill — die Fit-Animation muss ihr Zoom-Ziel **vor** dem Lauf deckeln, nicht erst danach korrigieren (2026-07-01, FE `components/ProblemGraph.vue`).
`fitDrillView()` (Fund 52) deckelt den Zoom erst im `stop:`-Callback auf `FIT_MAX_ZOOM = 1`. Die Layout-Animation selbst lief aber mit dem Instanz-`maxZoom` von `3` und zielte bei dünnen Clustern ungebremst auf ~120–130% — der User sah die Animation überschwingen und danach via `fitDrillView` auf 100% zurückschnappen. Ein reiner Post-Fix-Cap heilt den Endzustand, nicht die Animation. Fix: `maxZoom` **vor** `layout.run()` temporär auf `FIT_MAX_ZOOM` setzen und im `stop:`-Callback **und** im Non-Animate-Pfad wieder auf `GRAPH_MAX_ZOOM = 3` (den manuellen Zoom-Deckel, identisch zum `initGraph`-`maxZoom`) restaurieren — die Animation zielt dadurch direkt auf ≤100%. Regel: ein animiertes Ziel, das einen harten Deckel hat, muss den Deckel **vor** der Animation setzen; ihn erst am Ende zu erzwingen produziert ein sichtbares Überschwingen-und-Zurückschnappen.

**Konkreter Fund 58:** Die letzten zwei Ruckler der Drill-Animation — Streaming-Seiten coalescen; der Kamera-Fit wurde am Ende wieder auf einen **instanten Schnitt** zurückgesetzt (2026-07-01, FE `components/ProblemGraph.vue`).
Nach dem Overshoot-Cap (Fund 57) blieben zwei sichtbare Sprünge: (1) **Streaming-Seiten** — der Drill lädt die Cluster-Probleme seitenweise, jede Seite mutiert `props.problems` und der `deep`-`watch` feuerte pro Seite ein volles `rerender()` (Re-Layout + Re-Fit), sodass der Graph durch mehrere Zwischen-Zoom-Zustände sprang, bevor er sich setzte. Fix: der `watch` ruft `debouncedRerender()` (140ms) statt `rerender()` direkt — die schnell aufeinanderfolgenden Seiten werden zu **einem** Rerender ~140ms nach der letzten Änderung zusammengefasst, der Graph settlet einmal (`rerenderTimer` in `onUnmounted` gecleart). (2) **Kamera-Fit** — der Final-Snap wurde zuerst animiert (`cy.animate`, 200ms Glide), am Ende aber wieder auf einen **instanten Schnitt** zurückgesetzt: `fitDrillView` fittet instant auf die Echt-Knoten (`cy.fit(real, 56)`, danach `cy.zoom(FIT_MAX_ZOOM)`/`cy.center` falls > 100%) und `addTagFilter` drillt non-animiert (`applyTagFilters(false)`). Der Kamera-Flug las sich als eigenständige, störende Animation — ein Drill soll ein sauberer Schnitt in den Endzustand sein, keine Zoom-Reise; mit der Coalescing aus (1) bleiben nur noch ~2 Zoom-Zustände (z.B. 100→98, unmerklich). Kein neuer Test (reine Timing-Politur, 143 FE grün). Regel: die eigentliche Politur ist die Streaming-Coalescing (1), die die gestreamten Seiten zu **einem** Endzustand zusammenfasst; die Kamera-Animation (2) war ein Umweg — wenn ein Übergang „komisch" wirkt, ist die kleinste gute Antwort oft der Schnitt, nicht die aufwendigere Animation.

**Konkreter Fund 59:** Graph-Navigations-Commands in der StatusBar sichtbar machen — die vorhandene Zoom-Anzeige ist der Aufhänger, nicht ein neuer UI-Block (2026-07-01, FE `components/StatusBar.vue`).
Die Maus-/Tastatur-Steuerung des Graphen (`handleWheel`/`handleKeydown` in `ProblemGraph.vue`, mit der Graph-Überarbeitung `2c9bb8a` gelandet) war funktional, aber unentdeckbar: Scroll = Zoom, ⇧+Scroll = horizontaler Pan, ⇧+Strg+Scroll = vertikaler Pan, Pfeiltasten = verschieben/zwischen Problem-Nodes navigieren. `StatusBar.vue` zeigt die Commands jetzt **rechts neben der bestehenden Zoom-Anzeige** — an dasselbe `zoomPercent`-Signal gekoppelt, das schon die Zoom-Info steuert (`v-if="zoomPercent"`), also **nur im Graph-View** (in der Table ist `zoomPercent` null → Hinweis komplett aus). Inline stehen drei Hinweise, jeweils als faint **Präfix** + Aktionswort in der **Accent-Farbe** (`text-th-accent/80`, gedämpft), damit sich die Aktionen abheben ohne laut zu sein: `ctrl_scroll` „Scroll:" + `zoom` „Zoom", `ctrl_shift` „Shift+Scroll:" + `ctrl_dir` „links/rechts", `ctrl_drag` „Ziehen:" + `ctrl_move` „verschieben" (Klick+Ziehen = Pan ist Cytoscape-nativ, kein `handleWheel`-Command — wird nur als Discoverability-Hinweis mitgeführt). Die **vollständige** Liste (`status.controls` = „Ziehen: verschieben · Scroll: Zoom · Shift+Scroll: links/rechts · Shift+Strg+Scroll: hoch/runter · Pfeiltasten: verschieben/navigieren") sitzt im `title`-Tooltip — so bleibt die Zeile schlank, ohne Commands zu verstecken. Die Labels sind bewusst **ausgeschrieben** (kein „⇧"/„↔"-Symbol) — winzige Modifier-Glyphen sind auf Footer-Größe schlecht lesbar; voller Text („Shift+Scroll: links/rechts") liest sich sofort. Unter `md` (`hidden md:inline-flex`) fällt der Hinweis für Platz weg, die Zoom-Info bleibt. Zugleich wurde die bestehende Zoom-Anzeige selbst umgestellt: der **Prozentwert** (`zoomPercent`, z.B. „62%") steht jetzt in der Accent-Farbe (`text-th-accent/80`), das Wort „Zoom" bleibt faint — dieselbe Präfix-faint-/Aktion-accent-Logik wie bei den Hinweisen, damit die eigentliche Zahl heraussticht. Kein neuer Test (reine i18n + Template-Ergänzung, 143 FE grün). Regel: eine bestehende, kontextrichtige Anzeige (hier die Zoom-Info, schon graph-view-gated) ist der natürliche Aufhänger für verwandte Discoverability-Hinweise — Inline nur das Nötigste, den Rest in den Tooltip, gegated am selben Sichtbarkeits-Signal statt an einer duplizierten View-Prüfung.

Diese Faelle bestaetigen: Contract-Tests und Implementierungsdetails finden echte Bugs, nicht nur strukturelle Abweichungen.

**Verhaltens-Tests fuer zustandsbehaftete Composables** (`*.composable.spec.ts`):
Composables mit reaktivem State (Debounce, isChecking, reset()) bekommen dedizierte Verhaltens-Tests
zusaetzlich zu den Contract-Tests. Konvention: spiegeln die entsprechenden Python-Service-Tests
(`useSimilarity.composable.spec.ts` ↔ `test_similarity_service.py`,
`useTranslation.spec.ts` ↔ `test_translation_service.py`).

**Template-Logik gehoert in Composables, nicht in Komponenten:**
Filterfunktionen, Sortierlogik und andere zustandsbehaftete Berechnungen die in Komponenten inline landen,
sind per CLAUDE.md-Konvention in Composables zu extrahieren — nur so sind sie testbar.
Konkretes Beispiel: `filterAndSort` in `moderation.vue` → `useModerationFilter.ts` (13 Unit-Tests in `useModerationFilter.spec.ts`).
Erkennungsmerkmal: Funktion nutzt reaktive Props/State und waere sonst nur ueber Template-Snapshots testbar.

### Backend (pytest)

- Unit-Tests fur: Spam-Filter, Embedding-Pipeline, Clustering-Service
- Keine echten OpenAI-Aufrufe — Client mocken
- Fake-Daten in `tests/fakedata/`
- Testdatei spiegelt Quelle: `services/spam_filter.py` → `tests/test_spam_filter.py`
- **Test-DB = echtes Postgres+pgvector (testcontainers), kein SQLite mehr.** Die Backend-Unit-Tests (`apps/backend/tests/unit/`) laufen gegen ein ephemeres `pgvector/pgvector:pg16`, das `conftest.py` einmalig hochfährt (Docker erforderlich). Schema via `alembic upgrade head` (kein `Base.metadata.create_all`), System-Seeds (`001_regions.sql`/`002_tags.sql`) + ein Baseline-Test-User committet. Isolation pro Test via function-scoped Async-Session mit `join_transaction_mode="create_savepoint"` (Rollback nach jedem Test). Siehe Fund 40. Stand: 189 Unit-Tests, 0 skipped.
