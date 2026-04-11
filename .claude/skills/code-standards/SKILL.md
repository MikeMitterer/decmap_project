---
name: code-standards
description: Coding- und Script-Qualitätsstandards für dieses Projekt. Aktiviert wenn Code oder Scripts generiert werden — Bash, Python, TypeScript, Vue oder andere Sprachen. Stellt sicher: Funktionsdokumentation, kurze Funktionen, sprechende Variablennamen, --help in Scripts, ANSI-Farben im Output, BashLib-Nutzung, Klassenstruktur, Fehlerbehandlung, Logging, Testing.
---

# Code & Script Standards

Gilt für **allen** generierten Code und Scripts in diesem Projekt — keine Ausnahmen.

---

## Schritt 0: Zuerst .libs/ prüfen

Bevor eine Funktion neu implementiert wird: **prüfen ob sie bereits in `.libs/` existiert.**

```
.libs/
├── BashLib/src/       ← Bash-Funktionen (colors, logging, tools, fs, os, apps, …)
├── BashTools/src/     ← Fertige Bash-Scripts (deploy, sync, notify, …)
└── MakeLib/           ← Makefile-Helpers (colours.mk, tools.mk, urls.mk)
```

### Verfügbare BashLib-Module

| Datei              | Was drin ist |
|--------------------|---|
| `colors.lib.sh`    | `RED`, `GREEN`, `YELLOW`, `ORANGE`, `BLUE`, `CYAN`, `NC`, `SUCCESS`, `INFO`, `WARNING`, `ERROR` + 256-Farben |
| `logging.lib.sh`   | `inf()`, `error()`, `warn()`, `debug()`, `critical()`, `notify()` + LOG_LEVEL-System |
| `tools.lib.sh`     | `usageLine()`, `logFileStatus()`, `repeat()`, `trim()`, `showMenu()`, `scriptToDoc()`, `showModuleLinks()` |
| `apps.lib.sh`      | `checkIfToolIsAvailable()`, Tool-Pfade: `${JQ}`, `${FIND}`, `${TREE}`, `${CURL}`, … |
| `fs.lib.sh`        | `syncToLocalDir()` |
| `os.lib.sh`        | `${MACHINE}` (Linux/Mac/Cygwin), `${ARCHITECTURE}` |
| `styles.lib.sh`    | `MM_GLOBAL_STYLE_*` Variablen für `showMenu()` |

### MakeLib-Module

| Datei          | Was drin ist |
|----------------|---|
| `colours.mk`   | `RED`, `GREEN`, `YELLOW`, `BLUE`, `NC`, `RESET` + `print_colours` |
| `tools.mk`     | `usageLine`, `infoLine`, `optionLine` (Make defines) |

---

## BashLib einbinden

### Einbindungs-Pattern (Guard)

```bash
#!/usr/bin/env bash
set -euo pipefail

BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../.libs/BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/colors.lib.sh";  fi
if [[ "${__LOGGING_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/logging.lib.sh"; fi
if [[ "${__TOOLS_LIB__:=""}"   == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";   fi
```

### Farben & Logging (aus BashLib)

```bash
# Farben direkt verwenden — NICHT neu definieren!
echo -e "${GREEN}✓ Erfolg${NC}"
echo -e "${RED}✗ Fehler${NC}"
echo -e "${YELLOW}⚠ Warnung${NC}"

# Logging-Funktionen — 'info' ist ein System-Kommando, Funktion heißt 'inf'
inf     "Verarbeite Datei: ${source_file}"
warn    "Datei bereits vorhanden"
error   "Datei nicht gefunden"
debug   "Parsed ${line_count} Zeilen"

# Usage-Zeilen und Datei-Status
usageLine "--output FILE" "Ausgabedatei (default: output.json)"
logFileStatus "Config-File:" "${config_path}"
```

### Tool-Pfade (aus apps.lib.sh)

```bash
if [[ "${__APPS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/apps.lib.sh"; fi

checkIfToolIsAvailable "${JQ}"
"${JQ}" ".problems[]" < data.json   # statt rohem 'jq'
"${FIND}" . -name "*.json"          # statt rohem 'find'
```

### MakeLib einbinden

```makefile
include ../.libs/MakeLib/colours.mk
include ../.libs/MakeLib/tools.mk

help: ## Diese Hilfe anzeigen
    @$(call usageLine, "help", "Diese Hilfe anzeigen")
```

**Neue Funktionen:** Prüfen ob sie generisch in eine BashLib-Datei passen → dort ergänzen.

---

## Architektur-Prinzip

**Frontend:** Komponenten = nur Darstellung. Business Logic, Datentransformation, API-Kommunikation → Composables.

**Backend:** Router = nur HTTP-Belange. Business Logic → Services. Services haben keine Kenntnis von HTTP.

---

## Funktionen & Code

### Dokumentation

Jede Funktion bekommt einen Docstring mit Kurzbeschreibung, Parametern, Rückgabewert.

**Bash:**
```bash
# Prüft ob der angegebene Git-Branch einen Remote-Tracking-Branch hat.
#
# Params:
#   $1 - Pfad zum Repo
#   $2 - Branch-Name
#
# Returns:
#   0 wenn Remote-Tracking vorhanden, 1 wenn nicht
has_remote_tracking() {
    local repo_path="$1"
    local branch_name="$2"
    git -C "${repo_path}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' &>/dev/null
}
```

**Python — Google-Style Docstring:**
```python
def compute_similarity(embedding_a: list[float], embedding_b: list[float]) -> float:
    """Berechnet die Cosine-Similarity zwischen zwei Embeddings.

    Args:
        embedding_a: Erster Embedding-Vektor.
        embedding_b: Zweiter Embedding-Vektor.

    Returns:
        Similarity-Score zwischen 0.0 und 1.0.

    Raises:
        ValueError: Wenn die Vektoren unterschiedliche Längen haben.
    """
```

**TypeScript — JSDoc (einzeilig wenn ausreichend):**
```typescript
/** Alle freigegebenen Probleme aus Directus laden. */
async function fetchApprovedProblems(): Promise<Problem[]>

/**
 * Lädt alle Probleme eines Clusters aus der API.
 *
 * @param clusterId - UUID des Clusters
 * @param limit - Maximale Anzahl Ergebnisse (default: 50)
 * @returns Liste der zugehörigen Problems
 */
async function fetchClusterProblems(clusterId: string, limit = 50): Promise<Problem[]>
```

### Funktionslänge

- **Max ~30 Zeilen** pro Funktion — danach in Hilfsfunktionen aufteilen
- Eine Funktion = eine Aufgabe
- Seiteneffekte isolieren — reine Transformationslogik von I/O trennen

### Variablennamen

- Sprechend und selbsterklärend: `similarity_threshold` statt `thr`
- **TypeScript/Vue Loop-Variablen:** sprechend, kein `i`/`j`/`x` — `problem`, `clusterNode`, `voteEntry`
- **Bash Loop-Variablen:** `i`/`j` nur in kurzen numerischen Loops akzeptiert
- Booleans mit `is_`/`has_`/`should_` Prefix: `is_authenticated`, `has_embeddings`

```typescript
// richtig
for (const problem of problems) { ... }
problems.forEach((problem) => { ... })

// falsch
for (let i = 0; i < problems.length; i++) { ... }
problems.forEach((p) => { ... })
```

### Klassenstruktur

Einheitliche Reihenfolge: **1. Konstruktor → 2. Public → 3. Private**

```typescript
class ClusteringService {
  private readonly cytoscapeInstance: cytoscape.Core

  constructor(container: HTMLElement) { ... }

  renderClusters(clusters: ClusterNode[]): void { ... }          // public zuerst

  private buildGraphElements(clusters: ClusterNode[]): cytoscape.ElementDefinition[] { ... }
}
```

```python
class SpamFilter:
    def __init__(self, openai_client: OpenAIClient) -> None: ...
    def evaluate(self, text: str) -> FilterResult: ...      # public
    def _build_prompt(self, text: str) -> str: ...           # private
```

### Dependency Injection

Abhängigkeiten injizieren, nicht intern instanziieren — nur so sind Klassen testbar.

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

---

## TypeScript

- Strict Mode immer aktiv
- Kein `any` — bei unbekanntem Typ `unknown`
- Explizite Rückgabetypen bei allen Funktionen
- Keine Non-null Assertions (`!`) — null explizit behandeln
- Enums für feste Wertesets — keine Magic Strings
- Interfaces für Objektstrukturen, Type Aliases für Unions

```typescript
enum ProblemStatus {
  PENDING = 'pending',
  NEEDS_REVIEW = 'needs_review',
  APPROVED = 'approved',
}
```

---

## Vue / Nuxt

- Ausschließlich Composition API — **keine Options API**
- `<script setup lang="ts">` immer
- **Keine API-Aufrufe in Komponenten** — alle Datenzugriffe über Composables
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

### Composable-Struktur

```typescript
export function useProblems() {
  const problems = ref<Problem[]>([])
  const loading  = ref<boolean>(false)
  const error    = ref<string | null>(null)

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

### Gotcha — v-if/v-else-Kette nicht unterbrechen

Ein neues `v-if` innerhalb einer laufenden Kette bricht sie auf:

```vue
<!-- falsch — Toolbar-v-if unterbricht die loading/error/content-Kette -->
<div v-if="loading">...</div>
<div v-else-if="error">...</div>
<div v-if="!loading && !error"><Toolbar /></div>  <!-- neue Kette! -->
<div v-else-if="activeTab === 'queue'">...</div>  <!-- bezieht sich auf inneres v-if -->

<!-- richtig -->
<div v-if="loading">...</div>
<div v-else-if="error">...</div>
<div v-else>
  <Toolbar />
  <div v-if="activeTab === 'queue'">...</div>
  <div v-else>...</div>
</div>
```

---

## Python / FastAPI

- Type Hints überall
- Pydantic-Modelle für alle Request/Response-Schemas
- Router = ein pro Fachbereich, nur HTTP-Belange
- Services = Business Logic — keine Logic in `main.py`

### Gotcha — Background Tasks brauchen eigene DB-Connection

Request-scoped Connections sind beim Task-Start bereits geschlossen:

```python
# falsch
async def my_task(conn: AsyncConnection) -> None:
    await conn.execute(...)

# richtig
async def my_task(postgres_url: str) -> None:
    async with await psycopg.AsyncConnection.connect(postgres_url) as conn:
        await conn.execute(...)
```

### Gotcha — CORS

`allow_credentials=True` + `allow_origins=["*"]` ist browser-invalid — **nie zusammen verwenden**:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,  # aus .env, nie "*" mit credentials
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### Gotcha — Modul-Level-Imports für Testbarkeit

Optionale Dependencies auf Modul-Level importieren — sonst greift `patch()` in Tests nicht:

```python
import hdbscan  # richtig — Modul-Level, patchbar

def cluster(...):
    import hdbscan  # falsch — lokaler Import, patch() greift nicht
```

### Webhook-Security

```python
async def _verify_webhook_secret(
    x_webhook_secret: str | None = Header(None),
    settings: Settings = Depends(get_settings),
) -> None:
    """Prüft den Webhook-Secret-Header. Leeres Secret = Dev-Mode."""
    if settings.webhook_secret and x_webhook_secret != settings.webhook_secret:
        raise HTTPException(status_code=403)

@router.post("/hooks/problem-submitted", dependencies=[Depends(_verify_webhook_secret)])
async def on_problem_submitted(...): ...
```

---

## Fehlerbehandlung

- Fehler nie stillschweigend schlucken
- Mit Kontext loggen — `consola` (Frontend) / `structlog` (Backend)
- Benutzer-Fehlermeldungen: generisch, keine internen Details
- Alle async-Operationen in try/catch/finally

---

## Logging

**Frontend — `consola`** — kein `console.log` im eingecheckten Code:

```typescript
import { consola } from 'consola'
consola.info('Probleme geladen', { count: problems.length })
consola.error('Embedding fehlgeschlagen', { problemId, error })
```

**Backend — `structlog`** — kein natives `logging`:

```python
import structlog
logger = structlog.get_logger()
logger.info("embedding_generated", problem_id=problem_id, duration_ms=duration)
```

---

## Datenbank-Zugriff (KI-Service)

`psycopg3` + Repository Pattern — kein ORM. Kein Raw-SQL außerhalb der Repository-Schicht.

```python
class ProblemRepository:
    def __init__(self, connection: AsyncConnection) -> None:
        """
        Args:
            connection: Aktive psycopg3 AsyncConnection.
        """
        self.connection = connection

    async def find_approved(self) -> list[Problem]:
        """Gibt alle Problems mit Status APPROVED zurück."""
        async with self.connection.cursor(row_factory=class_row(Problem)) as cursor:
            await cursor.execute(
                "SELECT * FROM problems WHERE status = %s",
                (ProblemStatus.APPROVED,)
            )
            return await cursor.fetchall()
```

---

## Testing

### Frontend (Vitest)

- Unit-Tests nur für Composables — keine UI-Tests vorerst
- Alle Directus API-Aufrufe mocken
- Testdatei spiegelt Quelle: `composables/useProblems.ts` → `tests/composables/useProblems.spec.ts`
- **`vi.mock()` muss vor den Imports stehen** — Vitest hoisted Mocks nicht automatisch

### Contract-Tests (Fake → Real)

Jede Fake-Implementierung braucht Contract-Tests, die bei Umstieg auf Real-Data direkt wiederverwendet werden:

```typescript
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

### Backend (pytest)

- Unit-Tests für: Spam-Filter, Embedding-Pipeline, Clustering-Service
- Keine echten OpenAI-Aufrufe — Client mocken
- Fake-Daten in `tests/fakedata/`
- Testdatei spiegelt Quelle: `services/spam_filter.py` → `tests/test_spam_filter.py`

---

## Scripts: Aufruf-Konventionen

### Shebang — direkte Ausführbarkeit

Jedes Script beginnt mit einem Shebang damit es direkt von der Kommandozeile aufgerufen werden kann:

```bash
#!/usr/bin/env bash       # Bash
#!/usr/bin/env python3    # Python
```

Anschließend `chmod +x` setzen:
```bash
chmod +x scripts/mein-script.sh
chmod +x scripts/mein-script.py
```

### Kein "stilles Loslegen" — --help bei keiner Option

**Ein Script darf ohne explizite Option nicht einfach loslegen.**

- Kein Argument → `--help` anzeigen und beenden
- Die eigentliche Funktion des Scripts muss über eine explizite Option oder ein Argument ausgelöst werden
- Auch Scripts die "nur eine Sache tun" brauchen eine explizite Option dafür

```
# richtig
./repo-status.sh --show       # zeigt die Tabelle
./repo-status.sh              # zeigt --help

./gen-fakedata.py --generate  # generiert die Daten
./gen-fakedata.py --dry-run   # dry-run
./gen-fakedata.py             # zeigt --help

# falsch
./repo-status.sh              # startet sofort ohne Bestätigung
./gen-fakedata.py             # schreibt sofort Dateien
```

### Kurz- und Langform für Optionen

Wenn eine sinnvolle Kurzform existiert, **beide Formen anbieten** — Kurzform zuerst, getrennt durch `|`:

| Kurzform | Langform      | Wann anbieten |
|----------|---------------|---|
| `-h`     | `--help`      | immer |
| `-i`     | `--info`      | immer wenn App-Info vorhanden |
| `-v`     | `--verbose`   | immer wenn vorhanden |
| `-g`     | `--generate`  | wenn sinnvoll ableitbar |
| `-n`     | `--dry-run`   | gebräuchliche Konvention |
| `-o`     | `--output`    | immer wenn Output-Pfad |

Kurzformen die mehrdeutig oder ungebräuchlich wären → nur Langform anbieten.

### Usage-Ausgabe mit ANSI-Farben (Bash)

Die Usage-Funktion folgt einem festen Aufbau — abgeleitet aus den BashTools-Scripts:

```bash
#!/usr/bin/env bash

BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../.libs/BashLib/src" && pwd)}"
if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
if [[ "${__TOOLS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";  fi

# APPNAME immer als readonly Variable definieren
readonly APPNAME="$(basename "$0")"

# Zeigt die Verwendungshinweise an.
#
# Aufbau:
#   1. Usage-Zeile mit ${APPNAME}
#   2. Optionen — mit usageLine(), Kurz|Lang-Form, dynamische Werte in ${YELLOW}
#   3. Gruppen-Trenner in ${BLUE} wenn viele Optionen
#   4. Hints-Sektion mit Beispiel-Aufrufen in ${GREEN}
#
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo

    # Optionen — usageLine() aus BashLib, Trennzeichen '|' zwischen Kurz- und Langform
    usageLine "-g | --generate          " "Generiert Fake-Daten nach ${YELLOW}apps/frontend${NC} und ${YELLOW}apps/ai-service${NC}"
    usageLine "-n | --dry-run           " "Zeigt was generiert würde, ohne Dateien zu schreiben"
    usageLine "-v | --verbose           " "Verbose-Ausgabe"
    usageLine "-i | --info              " "Zeigt Script-Einstellungen"
    usageLine "-h | --help              " "Diese Hilfe anzeigen"
    echo

    # Hints — Beispiel-Aufrufe in ${GREEN}, Abschnittstitel in ${LIGHT_BLUE}
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Generieren:    ${GREEN}${APPNAME} --generate${NC}"
    echo -e "    Dry-Run:       ${GREEN}${APPNAME} --dry-run${NC}"
    echo
}

# Kein Argument → Help anzeigen (keine Ausnahmen)
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

# Für viele Optionen: bei komplexen Scripten Gruppen mit ${BLUE}-Trennern:
#
# usage() {
#     echo
#     echo "Usage: ${APPNAME} [ options ]"
#     echo
#     echo -e "\t${BLUE}# Hauptfunktionen -------------------------------------------------------${NC}"
#     usageLine "-g | --generate" "Generiert die Fake-Daten"
#     usageLine "-n | --dry-run " "Dry-Run"
#     echo
#     echo -e "\t${BLUE}# Info / Help -----------------------------------------------------------${NC}"
#     usageLine "-i | --info   " "Script-Einstellungen anzeigen"
#     usageLine "-h | --help   " "Diese Hilfe anzeigen"
#     echo
#     echo -e "${LIGHT_BLUE}Hints:${NC}"
#     echo -e "    ${GREEN}${APPNAME} --generate${NC}"
#     echo
# }

case "$1" in
    -g|--generate) run_main ;;
    -n|--dry-run)  run_main --dry ;;
    -v|--verbose)  VERBOSE=true; run_main ;;
    -i|--info)     show_info ;;
    -h|--help)     usage; exit 0 ;;
    *) echo -e "${RED}Unbekannte Option: $1${NC}" >&2; usage; exit 1 ;;
esac
```

**Die Bash-Konvention gilt für alle Script-Sprachen** — Python folgt exakt demselben Aufbau.

**Zusammenfassung Usage-Konventionen (sprachunabhängig):**
- `APPNAME` — Scriptname ohne Hardcoding (Bash: `basename "$0"`, Python: `Path(__file__).name`)
- Optionen mit `|` zwischen Kurz- und Langform: `"-g | --generate"`
- Dynamische Werte in Beschreibungen farbig: Bash `${YELLOW}…${NC}`, Python `f"{Colors.YELLOW}…{Colors.RESET}"`
- Gruppen-Trenner für komplexe Scripts in Blau
- Hints-Sektion am Ende: Titel in `LIGHT_BLUE`, Beispiel-Befehle in `GREEN`
- Leerzeilen vor/nach Blöcken

**Python — eigene `usage()` statt argparse-Help:**

argparse-Hilfe ist nicht colorierbar. Daher: `add_help=False`, eigene `usage()`- und `usage_line()`-Funktionen — visuell identisch zur Bash-Konvention.

```python
#!/usr/bin/env python3
import sys
from pathlib import Path

APPNAME = Path(__file__).name

# Farben — angelehnt an BashLib colors.lib.sh (256-Farben)
class Colors:
    YELLOW     = "\033[38;5;11m"
    GREEN      = "\033[38;5;10m"
    LIGHT_BLUE = "\033[38;5;45m"
    CYAN       = "\033[38;5;51m"
    RED        = "\033[38;5;196m"
    RESET      = "\033[0m"


def usage_line(option: str, description: str, col_width: int = 30) -> None:
    """Gibt eine formatierte Options-Zeile aus (entspricht usageLine aus BashLib).

    Args:
        option:      Kurz- und Langform, z.B. '-g | --generate'.
        description: Beschreibung der Option, darf ANSI-Farben enthalten.
        col_width:   Breite der Options-Spalte (default: 30).
    """
    print(f"    {Colors.CYAN}{option:<{col_width}}{Colors.RESET} {description}")


def usage() -> None:
    """Zeigt die Verwendungshinweise an — gleicher Aufbau wie Bash-Konvention."""
    print(f"\nUsage: {APPNAME} [ options ]\n")
    usage_line("-g | --generate", f"Generiert Fake-Daten nach {Colors.YELLOW}apps/frontend{Colors.RESET} und {Colors.YELLOW}apps/ai-service{Colors.RESET}")
    usage_line("-n | --dry-run",  "Zeigt was generiert würde, ohne Dateien zu schreiben")
    usage_line("-h | --help",     "Diese Hilfe anzeigen")
    print(f"\n{Colors.LIGHT_BLUE}Hints:{Colors.RESET}")
    print(f"    Generieren:    {Colors.GREEN}{APPNAME} --generate{Colors.RESET}")
    print(f"    Dry-Run:       {Colors.GREEN}{APPNAME} --dry-run{Colors.RESET}")
    print()


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parst die Kommandozeilen-Argumente. add_help=False — eigene usage() wird verwendet.

    Args:
        argv: Argument-Liste (typischerweise sys.argv[1:]).

    Returns:
        Geparstes Namespace-Objekt.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-g", "--generate", action="store_true")
    parser.add_argument("-n", "--dry-run",  action="store_true")
    return parser.parse_args(argv)


def main() -> None:
    """Entry Point — zeigt Help wenn keine Option angegeben."""
    # Kein Argument → Help anzeigen (keine Ausnahmen)
    if len(sys.argv) == 1:
        usage()
        sys.exit(0)

    if sys.argv[1] in ("-h", "--help"):
        usage()
        sys.exit(0)

    args = parse_args(sys.argv[1:])

    if args.generate or args.dry_run:
        run_generation(dry_run=args.dry_run)
    else:
        usage()
        sys.exit(0)
```

---

## ANSI Output-Gestaltung

**Mit BashLib** → vorhandene Konstanten und Funktionen verwenden (s.o.).

**Ohne BashLib** (nur wenn nicht eingebunden werden kann):
```bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
```

### Output-Struktur

```
▶ Verarbeite Seed-Daten           ← Section (CYAN/Bold)
  ✓ problems.json geladen          ← Erfolg (GREEN), 2 Leerzeichen
  ⚠ tags.json: veraltete Einträge  ← Warnung (YELLOW)
  ✗ ai-service nicht gefunden      ← Fehler (RED)
  ℹ → apps/frontend/seeds.json     ← Info (BLUE)
      Detail-Info                  ← Sub-Item, 6 Leerzeichen
```

Icons: `✓` Erfolg · `✗` Fehler · `⚠` Warnung · `ℹ` Info · `→` Ziel/Pfad
