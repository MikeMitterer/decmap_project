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

> **Grundanforderung:** Live-Updates im UI sind keine optionale Funktion.
> Wenn User A votet, sieht User B den aktualisierten Score sofort — ohne Page-Reload.
> Diese Funktionalität muss auch ohne AI-Service funktionieren.

CRUD uber REST. Ruckmeldungen an das UI uber zwei WebSocket-Quellen.

### Zwei WebSocket-Quellen

| Composable | WebSocket | Verantwortlich für |
|---|---|---|
| `useDirectusRealtime.ts` | Directus `/websocket` | Vote-Score-Updates (`problems.vote_score`) |
| `useRealtimeUpdates.ts` | AI-Service `/ws` | AI-Events: `problem.approved`, `cluster.updated`, `solution.generated` |

Vote-Score-Updates laufen **nicht** über den AI-Service — Basis-Funktionalität darf
nicht vom AI-Service abhängen.

### Vote-Score — Ablauf

```
User klickt Vote
      ↓
POST /items/votes  (Directus REST)
      ↓
GET /items/{collection}/{id}?fields=vote_score  (aktuellen Score laden)
      ↓
PATCH /items/{collection}/{id}  { vote_score: n+1 }  (via Directus REST)
      ↓  (löst Directus WS-Event aus)
Directus WebSocket → alle verbundenen Clients
      ↓
useDirectusRealtime.ts → applyProblemUpdate(update) → UI aktualisiert
```

> **Kein PostgreSQL-Trigger:** `trg_vote_score` / `fn_update_vote_score()` wurden entfernt.
> Score-Berechnung erfolgt in `realVoting.ts` via REST API. Voraussetzung: `update`-Permission
> auf `vote_score` für Public-Policy (`make -C apps/backend db-permissions`).

Sofort-Feedback für den votenden User: `ProblemPanel.vue` ruft nach `submitVote()`
sofort `fetchProblemById()` auf — zeigt echten DB-Wert ohne auf WS-Event zu warten.

### AI-Service — Event-Typen

```typescript
type WebSocketEvent =
  | { type: 'problem.approved';  payload: { id: string; clusterId: string } }
  | { type: 'problem.rejected';  payload: { id: string } }
  | { type: 'problem.deleted';   payload: { id: string } }
  | { type: 'cluster.updated';   payload: { id: string; label: string; problemCount: number } }
  | { type: 'solution.approved'; payload: { id: string; problemId: string } }
  | { type: 'solution.deleted';  payload: { id: string; problemId: string } }
```

Events auf Entity-Ebene — Frontend entscheidet ob Re-fetch oder direktes State-Update.

### Directus WS — nur Scalar-Felder

Directus WS-Subscriptions liefern **ausschließlich Scalar-Felder** — M2M-Relationen
(`tags`, `regions`) kommen nie im Event-Payload. `applyProblemUpdate` unterscheidet
daher zwei Fälle:

| Update-Typ | `edited_at` im WS-Event? | Strategie |
|---|---|---|
| Vote (`vote_score`) | nein | Scalar-Merge reicht (Score direkt übernehmen) |
| Edit (Titel, Tags, …) | **ja** | Scalar-Merge sofort + `fetchProblemById()` asynchron für aktuelle `tagIds`/`regionIds` |

Der Scalar-Merge verhindert Flackern; der REST-Nachlade bringt die vollständigen Relationen.
`ProblemGraph.vue` watcht `props.problems` deep — Graph rendert automatisch neu sobald
der State updated wird.

### Echtzeit-Edit-Konflikt-Erkennung

Kommt ein WS-Update rein während der User selbst editiert (`canEdit=true` + `isDirty=true`),
zeigt `ProblemPanel.vue` ein Konflikt-Banner statt die Eingaben still zu überschreiben:

| Zustand | WS-Update kommt rein | Ergebnis |
|---|---|---|
| `canEdit=false` (View-Only) | `props.problem` wird durch Parent still aktualisiert | Kein Banner |
| `canEdit=true`, `isDirty=false` | Edit-Felder + interner Snapshot still aktualisiert | Kein Banner |
| `canEdit=true`, `isDirty=true` | **Konflikt-Banner** erscheint | User entscheidet |

**Banner-Aktionen:**
- **Neu laden** → `fetchProblemById()` → Edit-Felder + Snapshot aktualisieren (eigene Eingaben gehen verloren)
- **×** → Banner schließen, eigene Eingaben bleiben, Konflikt wird ignoriert

**Eigenes Speichern triggert kein Banner:** Nach `handleSave()` wird der Snapshot auf die
gerade gespeicherten Werte gesetzt — der WS-Echo des eigenen Saves ergibt `isDirty=false`.

### Frontend — Composables

Beide Composables müssen **explizit** in `onMounted` verbunden werden — sie verbinden
sich nicht automatisch. Fehlt der `connect()`-Call, bleibt der Socket stumm (kein Fehler).

```typescript
// pages/index.vue
const { connect: connectDirectus, disconnect: disconnectDirectus } = useDirectusRealtime({
  onProblemUpdated: applyProblemUpdate,
})
const { connect: connectAiWs, disconnect: disconnectAiWs } = useRealtimeUpdates({ ... })

onMounted(() => { connectDirectus(); connectAiWs() })
onUnmounted(() => { disconnectDirectus(); disconnectAiWs() })
```

### Voraussetzungen

- `WEBSOCKETS_ENABLED=true` und `WEBSOCKETS_REST_AUTH=public` in `apps/backend/.env`
- `PUBLIC_URL` + `CORS_ORIGIN` korrekt gesetzt — sonst Reconnect-Loop (~3 s) ohne Fehlermeldung
- Directus Flow "Vote Score Broadcast" angelegt (`make -C infrastructure setup-vote-flow`)
- nginx `cms.decisionmap.ai`-Serverblock: Upgrade-Header + `proxy_read_timeout 3600s`

→ Vollständige Dokumentation: [`docs/dev-environment.md`](dev-environment.md)

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
2. Automatische Spracherkennung (`looksLikeEnglish`): Text gilt als Englisch wenn er keine Unicode-Zeichen > U+007F enthaelt
3. Bei Englisch: `_en`-Felder werden automatisch befuellt, kein Translate-Button noetig
4. Bei Nicht-Englisch: „Translate to English"-Button erscheint
5. Klick uebersetzt beide Felder (Titel + Beschreibung) parallel
6. User kann die englische Version vor dem Submit anpassen
7. Submit erst moeglich wenn `_en`-Felder befuellt und valide sind

Im Fake-Modus: 700ms simulierter Delay.
Im Real-Modus: KI-Service (TranslationService via konfiguriertem LLM-Provider — OpenAI `gpt-4o-mini` oder Anthropic `claude-haiku-4-5`, je nach `llm_provider` in `.env`).

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

## Authentifizierung

Directus built-in Auth — kein eigener Auth-Service.

### Registrierung

```
User füllt Register-Formular aus (E-Mail + Passwort)
      ↓
Passwort-Stärke-Checklist live (✓/○ pro Regel, Submit gesperrt bis alle grün)
      ↓
POST /users/register → Directus schickt Verifizierungsmail
      ↓
Frontend zeigt „registrationSent"-State (kein Auto-Login)
      ↓
User klickt Link in Mail → /verify-email.vue → GET /users/register/verify-email?token=XXX
      ↓
Directus antwortet 302 (redirect: 'manual' + opaqueredirect = Erfolg)
      ↓
Frontend leitet weiter auf /login?verified=true → grünes Banner
```

### Passwort-Stärke-Regeln

| Regel | Min |
|---|---|
| Länge | ≥ 8 Zeichen |
| Großbuchstabe | ≥ 1 |
| Zahl | ≥ 1 |
| Sonderzeichen | ≥ 1 |

Submit bleibt gesperrt bis alle vier Regeln erfüllt sind.

### Login / Logout

- POST `/auth/login` → JWT-Token in `localStorage`
- Token wird synchron im `setup()`-Block geladen (`loadPersistedTokens()` vor `onMounted`) — kein Race mit ersten API-Calls
- `restoreSession()` (API-Aufruf zur Session-Validierung) in `onMounted`

### Dev-Umgebung

Mailpit als SMTP-Sink — alle Mails landen auf `http://localhost:8025`, kein echter Mailversand.

### Konfiguration

Details zur Directus-Konfiguration (`USERS_REGISTER_ALLOW_PUBLIC`, `USER_REGISTER_URL_ALLOW_LIST`, Permissions): [`backend.md`](backend.md)

---

## Admin-Moderations-Queue

`/admin/moderation` — Freigabe/Ablehnung von Problemen und Loesungsansaetzen.

- Zwei Tabs: **Pending** / **Rejected** (Tab-Badge zeigt Gesamt-Anzahl, ungefiltert)
- **Suche:** Filtert live nach Titel, Titel (EN), Beschreibung und Beschreibung (EN)
- **Sortierung:** Toggle "Newest first" / "Oldest first" (`createdAt`)
- Status-Workflow: `pending → needs_review → approved / rejected`
- **`AUTO_APPROVE=true`:** Neue Problems überspringen die Moderations-Queue und wechseln direkt auf `approved`. Feature-Flag wird zur Build-Zeit ins Nuxt-Bundle eingebettet — Änderung erfordert Rebuild + Redeploy.

Filter- und Sortierlogik ist in `useModerationFilter.ts` gekapselt (nicht inline in der Komponente) — 13 Unit-Tests in `useModerationFilter.spec.ts`.

i18n-Keys: `admin.searchPlaceholder`, `admin.sortNewest`, `admin.sortOldest`

---

## Virtuelles Scrollen (Table-View)

`@tanstack/vue-virtual` fuer performante Tabellendarstellung:

- Rendert nur sichtbare Zeilen + 10 Buffer-Zeilen (Overscan)
- Geschaetzte Zeilenhoehe: 53px
- Padding-Spacer oben/unten fuer korrekte Scrollposition
- Tastaturnavigation scrollt automatisch zum naechsten Index
- Skaliert ohne Performance-Einbussen auf tausende Eintraege
