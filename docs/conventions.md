# Code-Konventionen und Beispiele

## Architekturprinzip: Trennung UI und Business Logic

**Frontend:** Komponenten = nur Darstellung. Business Logic, Datentransformation, API-Kommunikation → Composables.
**Backend:** Router = nur HTTP-Belange. Business Logic → Services. Services haben keine Kenntnis von HTTP.

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
- Junction-Tabellen: `snake_case`, Singular — `tag`, `region`, `problem_cluster`
- Spalten: `snake_case` — `cluster_id`, `vote_score`, `created_at`
- Fremdschlussel: `{tabelle_singular}_id` — `problem_id`, `user_id`

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
  clusterId: string | null
  voteScore: number
}

enum ProblemStatus {
  PENDING = 'pending',
  NEEDS_REVIEW = 'needs_review',
  APPROVED = 'approved',
  REJECTED = 'rejected'
}

async function fetchApprovedProblems(): Promise<Problem[]> {
  const problems = await directus.request(readItems('problems'))
  return problems ?? []
}
```

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

---

## Composables

Alle Directus-Kommunikation und Business Logic in Composables. Keine Ausnahmen.

```typescript
export function useProblems() {
  const problems = ref<Problem[]>([])
  const loading = ref<boolean>(false)
  const error = ref<string | null>(null)

  async function fetchApprovedProblems(): Promise<void> {
    loading.value = true
    error.value = null
    try {
      problems.value = await directus.request(readItems('problems'))
    } catch (fetchError) {
      error.value = 'Probleme konnten nicht geladen werden'
    } finally {
      loading.value = false
    }
  }

  return { problems, loading, error, fetchApprovedProblems }
}
```

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
Alle Hook-Endpoints verwenden `_verify_webhook_secret()` als Dependency.
Leeres `WEBHOOK_SECRET` = Dev-Mode (kein Check). Niemals Secrets in Code hardcoden.

```python
async def _verify_webhook_secret(
    x_webhook_secret: str | None = Header(None),
    settings: Settings = Depends(get_settings),
) -> None:
    if settings.webhook_secret and x_webhook_secret != settings.webhook_secret:
        raise HTTPException(status_code=403)

@router.post("/hooks/problem-submitted", dependencies=[Depends(_verify_webhook_secret)])
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
export function useVoting(apiClient: DirectusClient = defaultClient) { ... }
```

- Funktionen klein und fokussiert — eine Sache pro Funktion
- Seiteneffekte isolieren — reine Transformationslogik von I/O trennen

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
/** Alle freigegebenen Probleme aus Directus laden. */
async function fetchApprovedProblems(): Promise<Problem[]>
```

---

## Fehlerbehandlung

- Fehler nie stillschweigend schlucken
- Mit Kontext loggen — `consola` (Frontend) / `structlog` (Backend)
- Benutzer-Fehlermeldungen: generisch, keine internen Details
- Alle async-Operationen in try/catch

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

---

## Testing

### Frontend (Vitest)

- Unit-Tests nur fur Composables — keine UI-Tests vorerst
- Alle Directus API-Aufrufe mocken
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

**Implementiert fuer:** `useAuth`, `useProblems`, `useVoting`, `useSimilarity`, `useSolutions`, `useTags`, `useClusters`
(`tests/composables/*.contract.spec.ts` — je mit `describe.each` gegen Fake und Real)

**Vitest-Konfiguration:** `vitest.config.ts` schliesst nur `directusClient.ts` aus Coverage aus —
der gesamte Real-Layer (auth, problems, voting, similarity, tags, solutions, clusters) wird gemessen.
`tests/setup.ts` stellt `useRuntimeConfig`-Stub und `import.meta.client = true` bereit.

**Test-Umgebung (Env-Variablen):**
Prioritaetskette: Shell/Jenkins-Env → `.env.test.local` → `.env.test` → Hardcoded-Fallback.
`.env.test` ist committed (sichere Defaults fuer lokale Entwicklung); `.env.test.local` bleibt gitignored.
`vitest.config.ts` laedt `.env.test` via `loadEnv`, respektiert bereits gesetzte `process.env`.
`tests/setup.ts` liest alle URLs/Schwellenwerte aus `process.env` — keine hardcodierten Strings.
Jenkins: Env-Variablen im Build-Job setzen (`DIRECTUS_URL`, `WS_URL`, `SIMILARITY_THRESHOLD`) —
sie ueberschreiben automatisch die `.env.test`-Defaults, ohne dass eine Datei noetig waere.

**Konkreter Fund 1:** `realVoting.ts` hatte keinen Duplicate-Vote-Guard — ein zweiter Vote
lieferte einen Delta statt 0. Der Contract-Test hat das aufgedeckt; die Implementierung wurde
vor dem Merge korrigiert.

**Konkreter Fund 2:** `useSimilarity.ts` hatte `try/finally` ohne `catch` — unhandled Promise
rejection wenn der Data-Layer wirft. Aufgedeckt beim Schreiben von Verhaltens-Tests; `catch` ergaenzt
(loggt Warnung, setzt State leer).

**Konkreter Fund 3:** `useLogin.ts` pruefte Directus-Fehlermeldungen nicht prazise genug —
"email already taken" wurde nicht als `login.errorEmailTaken` erkannt (Directus liefert
`"Value for email has to be unique."`). Fix: `includes('unique')` ergaenzt. Ausserdem:
Fallback zeigte immer `"Something went wrong"` statt der tatsaechlichen Directus-Meldung —
jetzt wird `error.message` direkt angezeigt, generischer Fallback nur wenn kein Text vorhanden.

**Konkreter Fund 4:** `useLogin.ts` (`verify-email`-Pfad) — Directus gibt **302** zurueck, nicht 200.
`fetch` ohne `redirect: 'manual'` folgt dem Redirect, bekommt HTML und wirft einen Parse-Fehler.
Fix: `fetch(url, { redirect: 'manual' })` + `response.ok || response.type === 'opaqueredirect'` als Erfolg-Check.
I18n-Fallout: `login.loading` existierte nicht — Composable nutzt jetzt `login.verifying`.

**Konkreter Fund 5:** `default.vue` Layout — Auth-Token-Race-Condition.
`loadPersistedTokens()` war in `onMounted` — damit war der Token noch nicht gesetzt, wenn `index.vue`'s
`onMounted` (z.B. `fetchTags()`) lief und 403 zurueckbekam. Fix: `loadPersistedTokens()` synchron im
`setup()`-Block aufrufen; `restoreSession()` (API-Aufruf) bleibt in `onMounted`. Reihenfolge:
`setup()` → Token aus localStorage → `onMounted` fetchTags (Token vorhanden) → `onMounted` restoreSession.

**Konkreter Fund 6:** `realProblems.ts` — Directus M2M Virtual-Field-Naming.
`PROBLEM_FIELDS` und `DirectusProblem`-Interface verwendeten `problem_tag.tag_id` / `problem_region.region_id`,
aber Directus benennt M2M-Aliasfelder nach `one_field` in der Relation-Definition (`tags`, `regions`).
Fix: `problem_tag` → `tags`, `problem_region` → `regions` in Fields-Liste und Interface;
`mapProblem` nutzt `raw.tags ?? []` / `raw.regions ?? []` (defensiver Null-Guard).
Gleichzeitig: `tags.deleted_by` fehlte im Directus-Schema (selbes Muster wie `deleted_at`) — via REST hinzugefuegt und `schema.json` aktualisiert.

**Konkreter Fund 7:** `realAuth.ts` — Directus 11 `admin_access` auf Policy, nicht Role.
`role.admin_access` liefert immer `undefined` in Directus 11 (Feld auf `directus_roles` entfernt).
Korrekt: `role.policies.policy.admin_access` abfragen — `USER_FIELDS` um `"role.policies.policy.admin_access"` ergaenzt, `mapUser` prueft `raw.role?.policies?.some(p => p.policy?.admin_access)`.
Gleichzeitig: `date_created` existiert nicht auf `directus_users` in Directus 11 — `createdAt` nutzt `''`-Fallback. `display_name` / `company` sind Custom-Felder die `seed-users.sh` anlegt; fehlen sie, ist das Profil leer ohne Fehler.

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
