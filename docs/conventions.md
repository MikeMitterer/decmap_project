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

### Backend (pytest)

- Unit-Tests fur: Spam-Filter, Embedding-Pipeline, Clustering-Service
- Keine echten OpenAI-Aufrufe — Client mocken
- Fixtures in `tests/fixtures/`
- Testdatei spiegelt Quelle: `services/spam_filter.py` → `tests/test_spam_filter.py`
