# Feature-Spezifikationen

## Inhalt

- [Ahnlichkeitserkennung](#ahnlichkeitserkennung)
- [Bot-Erkennung](#bot-erkennung)
- [Echtzeit-Updates (WebSocket)](#echtzeit-updates-websocket)
- [Internationalisierung (i18n)](#internationalisierung-i18n)
- [Markdown in Losungen](#markdown-in-losungen)
- [Ubersetzung](#ubersetzung)
- [Tagging und Regionen](#tagging-und-regionen)
- [Editieren von Eintragen](#editieren-von-eintragen)
- [KI-generierte Losungsansatze](#ki-generierte-losungsansatze)
- [Theme-System](#theme-system)
- [Permalink-System](#permalink-system)
- [Authentifizierung](#authentifizierung)
- [Admin-Moderations-Queue](#admin-moderations-queue)
- [Virtuelles Scrollen (Table-View)](#virtuelles-scrollen-table-view)

---

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
TranslationService.to_english() — nicht-englischer Input wird übersetzt
(langdetect: englischer Text wird direkt durchgereicht, kein LLM-Call)
      ↓
KI-Service generiert temporares Embedding (kein DB-Insert)
      ↓
pgvector Cosine-Similarity gegen alle approved problems
(gespeicherte Embeddings basieren auf description_en — Sprachnormalisierung verhindert DE/EN-Vektor-Mismatch)
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

[↑ Inhalt](#inhalt)

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
limit_req_zone $binary_remote_addr zone=translate:10m   rate=5r/m;

location /api/problems {
    limit_req zone=submissions burst=3 nodelay;
}

location /api/translate {
    limit_req zone=translate burst=2 nodelay;
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

### Verifikationskriterien (LLM-Prompt)

Die konkreten Akzeptanz- und Ablehnungskriterien des KI-Spam-Filters sind in
[`docs/moderation-criteria.md`](moderation-criteria.md) definiert (SSoT).
Der `_SPAM_SYSTEM`-Prompt in `openai_provider.py` / `anthropic_provider.py` leitet sich
direkt daraus ab — Änderungen an den Kriterien erfordern synchrones Update beider Provider.

Zusammenhang mit Issue #19: `rejection_reason` wird erst sinnvoll befüllt,
wenn der Prompt konkrete Ablehnungsgründe kennt.

### Lösungsansätze (Solution Approaches)

Lösungsansätze werden **direkt per LLM evaluiert** — kein nginx/Middleware/Honeypot-Layer,
da der Einreichungsflow nach Login erfolgt. Prompt: `SOLUTION_SPAM_SYSTEM` in `prompts.py`.

Kriterien: [`docs/moderation-criteria.md → Solution Approaches`](moderation-criteria.md)  
Hook: `POST /hooks/solution-submitted` (vom Backend als BackgroundTask aufgerufen)

### Bewusst weggelassen

- CAPTCHA, Browser-Fingerprinting, ML-basierte Bot-Detection

[↑ Inhalt](#inhalt)

---

## Echtzeit-Updates (WebSocket)

> **Grundanforderung:** Live-Updates im UI sind keine optionale Funktion.
> Wenn User A votet, sieht User B den aktualisierten Score sofort — ohne Page-Reload.
> Diese Funktionalität muss auch ohne AI-Service funktionieren.

CRUD uber REST. Ruckmeldungen an das UI uber zwei WebSocket-Quellen.

### Zwei WebSocket-Quellen

| Composable | WebSocket | Verantwortlich für |
|---|---|---|
| `useBackendRealtime.ts` | Backend `/ws` (Port 8001) | Mutations: Vote-Scores, Problem/Solution CRUD |
| `useRealtimeUpdates.ts` | AI-Service `/ws` | AI-Events: `problem.approved`, `solution.generated` |

Vote-Score-Updates laufen **nicht** über den AI-Service — Basis-Funktionalität darf
nicht vom AI-Service abhängen.

### Vote-Score — Ablauf

```
User klickt Vote
      ↓
POST /votes  (FastAPI Backend, Port 8001)
      ↓
Backend berechnet neuen vote_score (Toggle-Logik, s.u.)
      ↓
Response enthält aktualisierten vote_score direkt — kein Re-Fetch nötig
      ↓  (Backend feuert WS-Event)
Backend WebSocket /ws → alle verbundenen Clients
      ↓
useBackendRealtime.ts → applyProblemUpdate(update) → UI aktualisiert
```

**Vote-Toggle-Semantik:** Gleiche Richtung wie vorhandenes Vote → zurückziehen (delta = -1). Entgegengesetzte Richtung → Flip (delta = ±2). Neues Vote → delta = ±1. `fakeVoting.ts` implementiert dieselbe Logik (Contract-Test in `useVoting.contract.spec.ts`).

Sofort-Feedback für den votenden User: `ProblemPanel.vue` aktualisiert den Score direkt aus dem Response-Body — zeigt echten DB-Wert ohne auf WS-Event zu warten.

**vote_score Floor (implementiert):** `vote_score = max(0, current_score - 1)` — kein negativer Score. Downvote auf Score 0 → bleibt 0, kein Vote-Row wird angelegt. Flip up→down bei Score 1 → fällt auf 0, nicht -1.

### AI-Service — Event-Typen

```typescript
type WebSocketEvent =
  | { type: 'problem.approved';     payload: { id: string; clusterId?: string | null } }
  | { type: 'problem.rejected';     payload: { id: string } }
  | { type: 'problem.deleted';      payload: { id: string } }
  | { type: 'clustering.started';   payload: { triggeredBy: string } }
  | { type: 'clustering.completed'; payload: { triggeredBy: string; clustersUpdated: number; assignedCount: number } }
  | { type: 'solution.approved';    payload: { id: string; problemId: string } }
  | { type: 'solution.deleted';     payload: { id: string; problemId: string } }
```

*`cluster.updated` entfernt — `clusters`-Tabelle gedroppt (Migration 005, 2026-05-22). `clustering.started`/`clustering.completed` ersetzen es: Frontend (`useClusteringStatus`) zeigt Spinner während Clustering läuft und re-fetcht Problems+Tags nach Completion. `clusterId` in `problem.approved` ist optional — Clustering-Output landet in `problem_tag` (L1–L9 Tags), nicht im Event-Payload.*

Events auf Entity-Ebene — Frontend entscheidet ob Re-fetch oder direktes State-Update.

### Backend WS — Scalar vs. Relationen

Backend WS-Events liefern Scalar-Felder des Problems. M2M-Relationen (`tags`, `regions`)
kommen nicht im Event-Payload. `applyProblemUpdate` unterscheidet daher zwei Fälle:

| Update-Typ | `edited_at` im WS-Event? | Strategie |
|---|---|---|
| Vote (`vote_score`) | nein | Scalar-Merge reicht (Score direkt übernehmen) |
| Edit (Titel, Tags, …) | **ja** | Scalar-Merge sofort + `fetchProblemById()` asynchron für aktuelle `tagIds`/`regionIds` |

Der Scalar-Merge verhindert Flackern; der REST-Nachlade bringt die vollständigen Relationen.
`ProblemGraph.vue` watcht `props.problems` deep — Graph rendert automatisch neu sobald
der State updated wird.

**Cytoscape.js Badge-Positionierung:** Badge-Mittelpunkt liegt an der Node-Ecke (halbe Badge
inside/outside) — das ist gewolltes Design, kein Bug. `positionSolutionBadge` und
`positionSearchBadges` nutzen `parent.width()/height()` für dynamische Offsets.

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
const { connect: connectBackend, disconnect: disconnectBackend } = useBackendRealtime({
  onProblemUpdated: applyProblemUpdate,
})
const { connect: connectAiWs, disconnect: disconnectAiWs } = useRealtimeUpdates({ ... })

onMounted(() => { connectBackend(); connectAiWs() })
onUnmounted(() => { disconnectBackend(); disconnectAiWs() })
```

### Voraussetzungen

- Backend (`apps/backend/`) läuft auf Port 8001 — WS-Endpoint: `ws://localhost:8001/ws`
- nginx `api.decisionmap.ai`-Serverblock: Upgrade-Header + `proxy_read_timeout 3600s`

→ Vollständige Dokumentation: [`docs/dev-environment.md`](dev-environment.md)

[↑ Inhalt](#inhalt)

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

[↑ Inhalt](#inhalt)

---

## Markdown in Losungen

Erlaubt in `solution_approaches.content` — bewusst eingeschrankt.

**Erlaubt:** Links, Fettschrift, Ueberschriften (h2/h3), Listen, Blockquotes | **Nicht erlaubt:** Bilder, Code-Blocke, inline HTML

```typescript
const md = new MarkdownIt({ html: false, linkify: true })
  .disable(['image', 'code', 'fence'])

function renderSolution(content: string): string {
  return DOMPurify.sanitize(md.render(content), {
    ALLOWED_TAGS: ['p', 'strong', 'em', 'a', 'br', 'h2', 'h3', 'ul', 'ol', 'li', 'blockquote'],
    ALLOWED_ATTR: ['href', 'target', 'rel'],
  })
}
```

Links offnen immer in `target="_blank"` mit `rel="noopener noreferrer"` — per DOMPurify-Hook auf allen Links erzwungen, nicht nur auf explizit gesetzten.

Styling: Tailwind-Variant-Selektoren (`.solution-content h2`, `.solution-content ul` etc.) statt `@tailwindcss/typography` `prose`-Klasse.

[↑ Inhalt](#inhalt)

---

## Ubersetzung

Aktive Ubersetzung beim Einreichen — nicht passiv via DeepL-Link:

1. User tippt Titel/Beschreibung in beliebiger Sprache
2. Automatische Spracherkennung (`looksLikeEnglish`): Text gilt als Englisch wenn er keine Unicode-Zeichen > U+007F enthaelt
3. Bei Englisch: `_en`-Felder werden automatisch befuellt, kein Translate-Button noetig
4. Bei Nicht-Englisch: „Translate to English"-Button erscheint
5. Klick uebersetzt beide Felder (Titel + Beschreibung) parallel
6. User kann die englische Version vor dem Submit anpassen
7. Submit triggert Auto-Translate wenn Nicht-Englisch erkannt und noch nicht uebersetzt (`hasNonEnglishContent && !translationDone → handleTranslateAll()`) — EN-Felder sind kein Submit-Blocker

Im Fake-Modus: 700ms simulierter Delay.
Im Real-Modus: KI-Service (TranslationService via konfiguriertem LLM-Provider — OpenAI `gpt-4o-mini` oder Anthropic `claude-haiku-4-5`, je nach `llm_provider` in `.env`).

**`EnglishTranslationSection.vue` — Collapsible UX:** EN-Felder erscheinen als Collapsible-Sektion sobald Nicht-Englisch erkannt wird. Header-Zeile zeigt Chevron-Icon + Titel-Preview im kollabierten Zustand. Auto-Expand nach Uebersetzung: zwei Trigger — `watch(showFields, { immediate: true })` (auch beim Mount wenn showFields bereits true) und `watch(isTranslating)` (Re-Translation wenn Section kollabiert war — showFields aendert sich nicht, der isTranslating-Uebergang true→false triggert Expand). Translate-Button und Info-Button bleiben immer in der Header-Zeile sichtbar — Info-Button nutzt `.stop` um den Collapse-Toggle nicht auszuloesen. Kein visueller Overhead fuer englischsprachige User.

**originalTranslations:** Backend speichert den originalen (nicht-englischen) Text in `original_translations` — fuer Admins sichtbar. Translation-Cache-Key basiert auf `sha256` des jeweiligen Feld-Inhalts (Titel/Beschreibung separat, nicht pauschal `sha256(title)`).

[↑ Inhalt](#inhalt)

---

## Tagging und Regionen

Zwei getrennte Konzepte:

- **Tags** (`tags` + `tag`) — inhaltliche Kategorisierung: "governance", "open-source", "shadow-ai"
- **Regionen** (`regions` + `region`) — geografische Einschrankung: 121 DACH-Regionen nach ISO 3166-2 (AT, CH, DE + Bundeslaender/Kantone/Bundeslaender)

Ein Problem kann mehrere Tags und mehrere Regionen haben.
Probleme ohne Region gelten als global relevant.

Regionen beeinflussen das Ranking (lokale Regionen priorisiert fur regionalen User).
Filterung moglich aber nicht erzwungen.

**useRegions-Facade:** Komponenten importieren ausschliesslich `useRegions.ts` (`useRegionsFetch()`) — kein Direktimport von `realRegions`. Facade-Pattern ermoeglicht den `USE_FAKE_DATA`-Switch ohne Komponenten-Aenderungen. `_inflight`-Promise-Cache verhindert doppelte Requests wenn mehrere Komponenten gleichzeitig mounten.

**Geo-Detection:** `useRegionDetection` ermittelt die Region des Users und setzt die Default-Auswahl im Formular.

Erkennungs-Kaskade:
1. **Browser-Geolocation** → Nominatim Reverse-Geocoding → ISO 3166-2 Subdivision-Code (z.B. `DE-BY`) → Region-Match
2. **Backend-Proxy** (`GET /regions/geo`) — greift wenn Geolocation nicht verfügbar ist (HTTP-Kontext) oder verweigert wird. Backend ruft `ip-api.com` server-seitig auf (vermeidet CORS auf HTTP; `ipapi.co` hat zu strenge Rate Limits). `country_code` + `region_code` → `AT-9` → Region-Match; Fallback auf Country-Code wenn Subdivision nicht matched.

HTTP-Kontext (z.B. `int.decisionmap.ai`): Browser blockiert `navigator.geolocation` automatisch auf nicht-sicheren Origins (HTTP) — `error.code === 1` (`PERMISSION_DENIED`), kein User-Popup. Backend-Proxy läuft automatisch als Fallback. Kein Contract-Test — `navigator.geolocation`-Mocking in Vitest ist nicht-trivial, als bekannte Lücke dokumentiert.

**Dev-Limitation:** In LAN-Entwicklungsumgebungen (`int.decisionmap.ai` → LAN-IP in `X-Forwarded-For`) liefert auch der Backend-Proxy `null` — `ip-api.com` geolocated keine privaten RFC-1918-Adressen. Region-Vorauswahl via Geo-Detection ist ein **Production-only Feature**; im lokalen Dev muss die Region manuell im Dropdown gewählt werden.

[↑ Inhalt](#inhalt)

---

## Editieren von Eintragen

- Editieren nur fur den ursprunglichen Autor
- Nach Freigabe (`approved`): Edit setzt Status zuruck auf `needs_review`
- Edit-History nur fur Moderatoren sichtbar
- `edited_at` wird im UI angezeigt
- KI-generierte Eintrage (`is_ai_generated: true`) nur vom Admin editierbar

### Superuser-Edit auf approved Problems

Superuser-Edits an `title` oder `description` eines bereits `approved` Problems folgen einem anderen Flow:

- Status bleibt `approved` — kein Rückfall auf `needs_review`
- Backend löst `POST /hooks/problem-reindex` als BackgroundTask aus
- Pipeline: Re-Embedding → Re-Clustering → WebSocket-Broadcast
- Bereits vorhandene KI-Lösung bleibt unverändert (kein neuer AI-Solution-Lauf)

[↑ Inhalt](#inhalt)

---

## KI-generierte Losungsansatze

`is_ai_generated: true` in `solution_approaches` — visuell klar getrennt.

- Eigenes Label "AI-generated" / Badge
- Ranking separat von menschlichen Beitragen
- **Kein Auto-Generieren:** KI erstellt keine Inhalte automatisch bei Problem-Approval — alle Solution-Inhalte kommen von Usern
- KI-Rolle = ausschliesslich Moderation (LLM-Spam-Filter kann `approved` vergeben, identisch zum Problem-Flow)
- `is_ai_generated: true` kennzeichnet Admin-erstellte oder historisch generierte Eintraege
- Admin schaut nur bei Grenzfaellen rein — kein eigener Moderations-Layer fuer Solutions

**Begruendung (Issue #26):** Core Value Prop ist kollektive Intelligenz echter User. Rein KI-generierte Ansaetze (auch admin-abgesegnet) verwassern das.

[↑ Inhalt](#inhalt)

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

[↑ Inhalt](#inhalt)

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

[↑ Inhalt](#inhalt)

---

## Authentifizierung

fastapi-users — JWT-Auth, E-Mail-Verifizierung, Magic Link (`apps/backend/`, Port 8001).

### Registrierung

```
User füllt Register-Formular aus (E-Mail + Passwort)
      ↓
Passwort-Stärke-Checklist live (✓/○ pro Regel, Submit gesperrt bis alle grün)
      ↓
POST /auth/register → Backend (fastapi-users) schickt Verifizierungsmail
      ↓
Frontend zeigt „registrationSent"-State (kein Auto-Login)
      ↓
User klickt Link in Mail → /verify-email.vue → GET /auth/verify?token=XXX
      ↓
Backend antwortet 204 (Erfolg)
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

### Magic Link

```
User fordert Magic Link an (E-Mail-Eingabe)
      ↓
POST /auth/request-magic-link → Backend schickt Mail mit Token
      ↓
User klickt Link → /auth/magic-verify.vue → GET /auth/magic-login?token=XXX
      ↓
Backend antwortet mit JWT → Frontend speichert Token, leitet auf / weiter
```

`/auth/magic-verify.vue` ist die Landingpage für Magic-Link-Tokens (B4-Fix: neu angelegt).

### Login / Logout

- POST `/auth/login` → JWT-Token in `localStorage`
- Token wird synchron im `setup()`-Block geladen (`loadPersistedTokens()` vor `onMounted`) — kein Race mit ersten API-Calls
- `restoreSession()` (API-Aufruf zur Session-Validierung) in `onMounted`

### „+" Button — Login-Redirect-Flow

Der `+`-Button ist immer sichtbar (Graph/Table-View), unabhängig vom Auth-Status:

- **Eingeloggt:** Öffnet das Eingabeformular direkt im Panel
- **Nicht eingeloggt:** Setzt localStorage-Flag `PENDING_OPEN_PROBLEM_FORM` + navigiert zu `/login`; auf `sm:`-Breakpoints zeigt der Button ein Lock-Icon (`opacity-70`) als subtilen Hinweis auf Login-Anforderung
- **Nach Login:** `default.vue` prüft in `onMounted` (nach `restoreSession()`) das Flag — ist es gesetzt, wird das Formular geöffnet und das Flag gelöscht
- **Ghost-Open Schutz:** Das Flag wird in `onMounted` von `default.vue` **immer** gelöscht — egal ob der User eingeloggt ist oder nicht. Bricht der User den Login ab und loggt sich später normal ein, öffnet sich das Formular nicht ungewollt nochmals.

Der Flow funktioniert für beide Auth-Methoden: Password-Login (`/login` → `router.push('/')`) und Magic Link (`/auth/magic-verify` → `router.replace('/')`). In beiden Fällen mountet `default.vue` neu und der Flag-Check greift.

### Dev-Umgebung

Mailpit als SMTP-Sink — alle Mails landen auf `http://localhost:8025`, kein echter Mailversand.

### Konfiguration

Details: [`backend.md`](backend.md)

[↑ Inhalt](#inhalt)

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

### Loesungsansaetze in der Queue

Pending + Rejected Solutions werden als **kombinierte, nach Datum sortierte Liste** angezeigt — keine separate Sektion. Frontend laed beide via `Promise.allSettled` (resilient: ein Fehler blockiert nicht die andere Liste).

Backend: `GET /solutions?status_filter=rejected` erfordert Superuser-Auth fuer alle Nicht-`approved`-Filterwerte.

### duplicate_confirmed Flow

Reicht ein User ein Problem trotz Duplikat-Warnung ein, erhaelt das Problem den Status `needs_review` (statt automatisch `rejected`). Der `rejection_reason="possible_duplicate"` wird in der Admin-Queue als amber Systemhinweis angezeigt (`admin.systemNote` i18n-Key).

Signal-Weg: `ProblemForm.vue` → `signals: ['duplicate_confirmed']` → Backend → AI-Service `hooks.py` → `needs_review` statt `rejected`.

[↑ Inhalt](#inhalt)

---

## Virtuelles Scrollen (Table-View)

`@tanstack/vue-virtual` fuer performante Tabellendarstellung:

- Rendert nur sichtbare Zeilen + 10 Buffer-Zeilen (Overscan)
- Geschaetzte Zeilenhoehe: 53px
- Padding-Spacer oben/unten fuer korrekte Scrollposition
- Tastaturnavigation scrollt automatisch zum naechsten Index
- Skaliert ohne Performance-Einbussen auf tausende Eintraege
