# Feature-Spezifikationen

## Ahnlichkeitserkennung

Verhindert Duplikate bevor sie in die Moderations-Queue gelangen.

### Ablauf

```
User tippt Problemtitel
      ↓
Debounce 600ms
      ↓
Frontend schickt Text an /similarity Endpunkt
      ↓
KI-Service generiert temporares Embedding (kein DB-Insert)
      ↓
pgvector Cosine-Similarity gegen alle approved problems
      ↓
Treffer (Score > 0.85) → ahnliche Probleme werden angezeigt
Kein Treffer → kein Hinweis, Submission lauft normal
      ↓
Bei Treffer: Submission blockiert bis User bestatigt
"Dieses Problem ist trotzdem neu / anders"
```

### Schwellenwert

| Score | Bedeutung |
|---|---|
| > 0.92 | Sehr wahrscheinlich Duplikat |
| 0.85 – 0.92 | Ahnlich — Hinweis mit Link zum bestehenden Problem |
| < 0.85 | Kein Hinweis |

Konfigurierbar uber `SIMILARITY_THRESHOLD` (default: 0.85).

### API-Endpunkt

```python
@router.post("/similarity")
async def check_similarity(payload: SimilarityPayload) -> SimilarityResult:
    """Ahnliche Probleme fur den eingegebenen Text finden. Kein DB-Insert, kein Auth."""
    return await similarity_service.find_similar(payload.text)
```

```python
class SimilarityPayload(BaseModel):
    text: str = Field(min_length=5, max_length=200)

class SimilarProblem(BaseModel):
    id: str
    title: str
    score: float

class SimilarityResult(BaseModel):
    similar_problems: list[SimilarProblem]
    has_duplicates: bool   # True wenn Score > 0.92
```

### pgvector Query

```sql
SELECT id, title, 1 - (embedding <=> %s::vector) AS score
FROM problems
WHERE status = 'approved'
  AND 1 - (embedding <=> %s::vector) > %s
ORDER BY score DESC
LIMIT 5;
```

### Frontend — Debounce in Composable

```typescript
export function useSimilarity() {
  const similarProblems = ref<SimilarProblem[]>([])
  const hasDuplicates = ref<boolean>(false)
  const isChecking = ref<boolean>(false)
  let debounceTimer: ReturnType<typeof setTimeout>

  function checkSimilarity(text: string): void {
    clearTimeout(debounceTimer)
    if (text.length < 10) { similarProblems.value = []; return }
    debounceTimer = setTimeout(async () => {
      isChecking.value = true
      const result = await similarityApi.check(text)
      similarProblems.value = result.similarProblems
      hasDuplicates.value = result.hasDuplicates
      isChecking.value = false
    }, 600)
  }

  return { similarProblems, hasDuplicates, isChecking, checkSimilarity }
}
```

---

## Bot-Erkennung

Mehrschichtiger Ansatz — kein CAPTCHA (UX-Killer).

### Schichten

```
Request kommt rein
      ↓
1. nginx — Rate Limiting (5r/m pro IP)
      ↓
2. DNSBL-Check (aiodnsbl) — bekannte Spam-IPs
      ↓
3. FastAPI Middleware — Verhaltens-Signale + Honeypot
      ↓
4. GPT Spam-Filter
```

### nginx Rate Limiting

```nginx
limit_req_zone $binary_remote_addr zone=submissions:10m rate=5r/m;

location /api/problems {
    limit_req zone=submissions burst=3 nodelay;
}
```

### Verhaltens-Signale (FastAPI Middleware)

```python
class BotDetectionMiddleware:
    SUSPICIOUS_SIGNALS = [
        "submit_too_fast",        # < 10 Sekunden zwischen Seitenaufruf und Submit
        "session_flood",          # > 10 Submissions in 60 Minuten
        "ip_hash_multi_session",  # ip_hash in > 5 verschiedenen Sessions
        "missing_user_agent",
        "known_bot_agent",
        "honeypot_filled",
    ]
```

- 2+ Signale → automatisch `rejected`, kein GPT-Call
- 1 Signal → `needs_review` mit Flag im Moderations-Log

### Honeypot

```html
<input type="text" name="website" class="absolute -left-[9999px]"
  tabindex="-1" autocomplete="off" aria-hidden="true" />
```

```python
if payload.honeypot:
    return FilterResult(status=ProblemStatus.REJECTED, reason="honeypot")
```

Honeypot-Feld wird nie in der DB gespeichert — nur gepruft.

### Bewusst weggelassen

- CAPTCHA, Browser-Fingerprinting, ML-basierte Bot-Detection

---

## Echtzeit-Updates (WebSocket)

CRUD uber REST. Ruckmeldungen an das UI uber WebSocket — Multi-User-Betrieb bleibt aktuell.

### Ablauf

```
User A submitted Problem
      ↓ REST POST /problems
Directus speichert
      ↓ Webhook
FastAPI verarbeitet (Filter, Embedding, Clustering)
      ↓ WebSocket broadcast
Alle verbundenen Clients erhalten Event
      ↓
UI aktualisiert sich gezielt
```

### Event-Typen

```typescript
type WebSocketEvent =
  | { type: 'problem.approved';  payload: { id: string; clusterId: string } }
  | { type: 'problem.rejected';  payload: { id: string } }
  | { type: 'problem.deleted';   payload: { id: string } }
  | { type: 'cluster.updated';   payload: { id: string; label: string; problemCount: number } }
  | { type: 'solution.approved'; payload: { id: string; problemId: string } }
  | { type: 'solution.deleted';  payload: { id: string; problemId: string } }
  | { type: 'vote.changed';      payload: { entityId: string; entityType: 'problem' | 'solution'; newScore: number } }
```

Events auf Entity-Ebene — Frontend entscheidet ob Re-fetch oder direktes State-Update.

### Backend — FastAPI

```python
connected_clients: set[WebSocket] = set()

@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    connected_clients.add(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        connected_clients.discard(websocket)

async def broadcast(event: WebSocketEvent) -> None:
    message = event.model_dump_json()
    disconnected = set()
    for client in connected_clients:
        try:
            await client.send_text(message)
        except WebSocketDisconnect:
            disconnected.add(client)
    connected_clients.difference_update(disconnected)
```

### Frontend — Composable

```typescript
export function useRealtimeUpdates() {
  const socket = ref<WebSocket | null>(null)

  function connect(): void {
    socket.value = new WebSocket(`${WS_URL}/ws`)
    socket.value.onmessage = (event: MessageEvent) => {
      const wsEvent = JSON.parse(event.data) as WebSocketEvent
      handleEvent(wsEvent)
    }
    socket.value.onclose = () => setTimeout(connect, 3000)  // Reconnect
  }

  onMounted(connect)
  onUnmounted(() => socket.value?.close())
}
```

---

## Internationalisierung (i18n)

Nuxt i18n von Anfang an eingebunden. Alle UI-Texte uber `t()`, keine hardcodierten Strings.

```vue
<!-- richtig -->
<h1>{{ t('problems.title') }}</h1>

<!-- falsch -->
<h1>AI Problem Map</h1>
```

Sprachdateien: `frontend/i18n/locales/en.json` — MVP nur Englisch, Struktur vollstandig.

---

## Markdown in Losungen

Erlaubt in `solution_approaches.content` — bewusst eingeschrankt.

**Erlaubt:** Links, Fettschrift | **Nicht erlaubt:** Uberschriften, Bilder, Code-Blocke, HTML

```typescript
const md = new MarkdownIt({ html: false, linkify: true })
  .disable(['image', 'heading', 'code', 'fence', 'blockquote'])

function renderComment(content: string): string {
  return DOMPurify.sanitize(md.render(content), {
    ALLOWED_TAGS: ['p', 'strong', 'em', 'a', 'br'],
    ALLOWED_ATTR: ['href', 'target', 'rel'],
  })
}
```

Links offnen immer in `target="_blank"` mit `rel="noopener noreferrer"`.

---

## Ubersetzung

Aktive Ubersetzung beim Einreichen — nicht passiv via DeepL-Link:

1. User tippt Titel/Beschreibung in beliebiger Sprache
2. Automatische Spracherkennung pruft ob der Text englisch ist
3. Bei Englisch: `_en`-Felder werden automatisch befuellt, kein Translate-Button noetig
4. Bei Nicht-Englisch: „Translate to English"-Button erscheint
5. Klick uebersetzt beide Felder (Titel + Beschreibung) parallel
6. User kann die englische Version vor dem Submit anpassen
7. Submit erst moeglich wenn `_en`-Felder befuellt und valide sind

Im Fake-Modus: 700ms simulierter Delay.
Im Real-Modus: KI-Service (TranslationService via OpenAI).

`_en`-Felder sind nur sichtbar wenn Nicht-Englisch erkannt wird — kein visueller Overhead fuer englischsprachige User.

---

## Tagging und Regionen

Zwei getrennte Konzepte:

- **Tags** (`tags` + `tag`) — inhaltliche Kategorisierung: "governance", "open-source", "shadow-ai"
- **Regionen** (`regions` + `region`) — geografische Einschrankung: EU, US, APAC, GLOBAL

Ein Problem kann mehrere Tags und mehrere Regionen haben.
Probleme ohne Region gelten als global relevant.

Regionen beeinflussen das Ranking (EU-Probleme hoher fur EU-User).
Filterung moglich aber nicht erzwungen.

---

## Editieren von Eintragen

- Editieren nur fur den ursprunglichen Autor
- Nach Freigabe (`approved`): Edit setzt Status zuruck auf `needs_review`
- Edit-History nur fur Moderatoren sichtbar
- `edited_at` wird im UI angezeigt
- KI-generierte Eintrage (`is_ai_generated: true`) nur vom Admin editierbar

---

## KI-generierte Losungsansatze

`is_ai_generated: true` in `solution_approaches` — visuell klar getrennt.

- Eigenes Label "AI-generated" / Badge
- Ranking separat von menschlichen Beitragen
- Automatisch generiert bei `approved`-Status
- Keine menschliche Moderation, aber als KI-Inhalt gekennzeichnet

---

## Theme-System

6 vordefinierte Themes + benutzerdefiniertes Theme per Akzentfarbe.

### Preset-Themes

| Theme | Modus | Akzentfarbe |
|---|---|---|
| Default | Hell | Blau (#2563eb) |
| Forest | Hell | Gruen (#059669) |
| Sunset | Hell | Amber (#d97706) |
| Midnight | Dunkel | Hellblau (#60a5fa) |
| Obsidian | Dunkel | Violett (#a78bfa) |
| Aurora | Dunkel | Teal (#2dd4bf) |

### Custom-Theme

User waehlt eine Akzentfarbe, das System generiert daraus alle UI-Farben:
- Hex → HSL-Konvertierung
- Ableitung von Hintergrund, Oberflaeche, Rahmen, Text, Input-Farben
- Komplementaerfarben fuer Graph-Knoten (Blaetter: Farbton +120°, Loesungen: +160°)
- Ueber 30 CSS Custom Properties werden dynamisch auf dem Document-Root gesetzt

### FOUC-Praevention

Blockierendes Inline-Script im `<head>` (via `nuxt.config.ts`):
- Liest Theme aus `localStorage` bevor Vue geladen wird
- Setzt `data-theme`-Attribut und `dark`-Klasse sofort
- Fallback-Variablen in `:root` stellen sicher dass Styles existieren bevor JS laeuft

### System-Praeferenz

Ohne explizite Theme-Wahl wird `prefers-color-scheme` ausgewertet und das
entsprechende Default-Theme geladen (default-light oder midnight-dark).

---

## Permalink-System

Teilbare Links zu einzelnen Problemen: `/?problem=<id>`

### Ablauf

1. Layout liest `route.query.problem` beim Laden
2. `focusProblemId` wird via `provide/inject` an alle Child-Komponenten verteilt
3. **Graph-View:** Drills automatisch zur Tag-Hierarchie des Problems (findet den tiefsten
   strukturellen Tag, baut die Ancestor-Chain fuer Breadcrumbs, setzt Filter)
4. **Table-View:** Filtert auf das einzelne Problem
5. Detail-Panel oeffnet sich automatisch
6. Filter-Chip zeigt „Showing single problem" mit Schliessen-Button

### Share-Button

Im Detail-Panel kopiert „Share link" den Permalink (`origin + /?problem=<id>`) in die Zwischenablage.
Feedback: „Link copied!" fuer 2 Sekunden.

---

## Virtuelles Scrollen (Table-View)

`@tanstack/vue-virtual` fuer performante Tabellendarstellung:

- Rendert nur sichtbare Zeilen + 10 Buffer-Zeilen (Overscan)
- Geschaetzte Zeilenhoehe: 53px
- Padding-Spacer oben/unten fuer korrekte Scrollposition
- Tastaturnavigation scrollt automatisch zum naechsten Index
- Skaliert ohne Performance-Einbussen auf tausende Eintraege
