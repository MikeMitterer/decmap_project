# DecisionMap — Projektdokumentation

Konsolidierte Dokumentation des gesamten Projekts. Zusammengeführt aus Konzept, Entscheidungsprotokoll,
aktuellem Frontend-Stand und technischen Spezifikationen.

---

## 1. Was ist DecisionMap?

Eine kollektive Wissensplattform für KI-bezogene Probleme in Unternehmen. Der ursprüngliche Arbeitstitel
war „KI - ProblemLandkart" — der finale Name ist **DecisionMap** (`decisionmap.ai`, Fallback: `frictionmap.ai`).

Unternehmen stehen bei der Einführung von KI vor ähnlichen Herausforderungen — aber jedes löst sie isoliert.
DecisionMap macht dieses verteilte Wissen sichtbar und nutzbar.

### Wie funktioniert es?

1. **User erfassen Probleme** — kurze, präzise Beschreibung eines realen KI-Problems
   aus dem Unternehmensalltag (z.B. Shadow AI, Modellauswahl, Compliance, Open Source im Betrieb)
2. **Andere User liefern Lösungsansätze** — keine fertigen Lösungen, sondern Erfahrungen
   und Ansätze, weil das Thema zu dynamisch ist für abgeschlossene Antworten
3. **KI clustert automatisch** — ähnliche Probleme werden zu Kategorien gruppiert und
   in eine hierarchische Tag-Struktur eingeordnet
4. **Visualisierung als interaktiver Graph** — eine radiale Mindmap zeigt die Tag-Hierarchie,
   mit Drill-down zu einzelnen Problemen

### Positionierung

Kein Beratungstool. Keine Diskussionsplattform.
Eine **strukturierte, KI-unterstützte Wissensbasis** über reale KI-Probleme in Unternehmen —
mit Community-Validierung durch Voting.

- **Zielgruppe:** IT-Entscheider, CDOs, KI-Projektverantwortliche in KMU
- **Sprache:** Englisch (internationale Skalierung), Eingabe in jeder Sprache möglich
- **Prinzip:** Stack Overflow / Reddit — wer etwas einbringt, bekommt etwas zurück

---

## 2. Aktueller Stand

Das Frontend ist im **Fake-Data-Modus** (`USE_FAKE_DATA=true`) vollständig funktionsfähig.
Alle UI-Flows arbeiten End-to-End gegen In-Memory-Daten. Der Real-Data-Layer (Directus + FastAPI
KI-Service) ist vollständig implementiert — `USE_FAKE_DATA=false` aktiviert ihn ohne weiteren Code-Eingriff,
sobald Directus eingerichtet und `DIRECTUS_TOKEN` gesetzt ist.

Der **AI-Service** (FastAPI, Python 3.11+) ist vollständig implementiert und getestet (31 Unit-Tests grün).
Manuelle Endpunkt-Tests per `curl`: [`docs/cmdline.md`](docs/cmdline.md)

### Was funktioniert

| Feature | Beschreibung |
|---|---|
| **Graph-View** | Interaktive Cytoscape.js-Mindmap mit radialer Tag-Hierarchie, Drill-down zu Problem-Grids, Tastaturnavigation, Zoom-Steuerung |
| **Table-View** | Virtuell gescrollte Tabelle (@tanstack/vue-virtual) mit Sortierung und Tag-/User-/Firmen-Filtern |
| **Problem-CRUD** | Erfassen, Bearbeiten, Moderieren von Problemen mit Titel/Beschreibung in Originalsprache + automatischer englischer Übersetzung |
| **Lösungsansätze** | Hinzufügen, Anzeigen und Bewerten von Lösungsansätzen pro Problem (Markdown: Links + Fettschrift) |
| **Moderation** | Admin-Queue zum Freigeben/Ablehnen von Problemen und Lösungen, Status-Workflow (pending → needs_review → approved/rejected) |
| **Voting** | Up-/Downvotes auf Probleme und Lösungen mit Duplikat-Prävention |
| **Ähnlichkeitserkennung** | Debounced-Prüfung gegen bestehende Probleme während der Erfassung |
| **Permalinks** | `/?problem=<id>` navigiert Graph/Tabelle zum konkreten Problem, öffnet Detail-Panel, teilbar als Link |
| **Theme-System** | 6 Preset-Themes (3 hell, 3 dunkel), Custom-Theme per Akzentfarbe, System-Präferenz-Erkennung, FOUC-frei |
| **Echtzeit-Updates** | WebSocket-Composable für Live-UI-Aktualisierungen |
| **i18n** | Alle UI-Texte über Nuxt i18n (Englisch, Struktur bereit für weitere Sprachen) |
| **Übersetzung** | Automatische Spracherkennung + Übersetzung ins Englische beim Einreichen |
| **Auth** | Login/Registrierung mit Magic-Link-Support (Fake: sofortiger Mock-Login, Real: Directus Auth) |

### Nächste Schritte

- **Directus einrichten (einmalig):** Schema-Import via `docker exec decisionmap-directus npx directus schema apply /directus/schema.json` (Snapshot im Repo), dann API-Token generieren + in `.env` eintragen — Details: `docs/backend.md`
- **Directus Flows konfigurieren:** HTTP-Request-Actions für `problem-submitted`, `problem-approved`, `solution-approved`, `vote-changed` auf `http://ai-service:8000/hooks/*` einrichten
- DNSBL-Check (aiodnsbl) als zweite Schicht im Spam-Filter aktivieren
- Regionsbasierte Filterung und Ranking
- UI-Tests (aktuell: nur Unit-Tests für Composables)

---

## 3. Technischer Stack

| Schicht | Technologie | Zweck |
|---|---|---|
| Frontend | Nuxt.js 3 + TypeScript | SPA/SSR-Hybrid, Auto-Imports, SEO-ready |
| CSS | Tailwind CSS + CSS Custom Properties | Styling über Utility-Klassen, Theme-Tokens als CSS-Variablen |
| Visualisierung | Cytoscape.js | Spezialisiert auf Graphen, gute TypeScript-Types |
| Virtuelles Scrollen | @tanstack/vue-virtual | Performante Tabelle für große Datenmengen |
| Validierung (Frontend) | Zod | TypeScript-first, Typ-Ableitung aus Schema |
| Markdown | markdown-it + DOMPurify | Eingeschränktes Markdown (nur Links + Fettschrift) |
| CMS / Backend | Directus | Admin Panel, Auth, REST API, self-hosted |
| Datenbank | PostgreSQL + pgvector | Embeddings und relationale Daten in einer DB |
| DB-Zugriff | psycopg3 + Repository Pattern | Kein ORM, volle Kontrolle, pgvector nativ |
| DB-Migrationen | Alembic | Python-nativ, async-fähig, Rollback pro Migration |
| KI-Service | FastAPI (Python 3.11+) | Async, Pydantic-Validierung, WebSocket nativ |
| Validierung (Backend) | Pydantic | FastAPI-nativ, HTTP 422 bei ungültigen Requests |
| Echtzeit | WebSocket (FastAPI native) | REST für CRUD, WebSocket für Live-Updates |
| Logging Frontend | consola | Nuxt-nativ, strukturiert |
| Logging Backend | structlog | Key-Value-Ausgabe, async-kompatibel |
| Testing Frontend | Vitest | Unit-Tests + Contract-Tests für alle Composables (Fake & Real) |
| Testing Backend | pytest | Unit-Tests für Services |
| Hosting | Hetzner + Docker + nginx | Europäisch (DSGVO), günstig |
| CI/CD | Jenkins (lokal) → SSH → Hetzner | Bestehende Infrastruktur |
| i18n | @nuxtjs/i18n | Alle UI-Texte externalisiert |

### Warum diese Entscheidungen?

- **Cytoscape.js statt D3.js** — spezialisiert auf Graphen, einfachere API für Mindmap-Layouts
- **Directus statt eigenem Backend** — Admin Panel, Auth und REST API out-of-the-box
- **psycopg3 statt ORM** — volle Kontrolle über SQL, pgvector nativ unterstützt
- **Zod + Pydantic + PostgreSQL Constraints** — Validierung auf drei Schichten, keine Schicht vertraut der anderen blind
- **Tailwind statt Komponenten-CSS** — beste Nuxt 3 Integration, kein Konflikt mit Cytoscape.js
- **consola / structlog statt console.log / logging** — strukturierte Ausgabe, kein Rauschen

---

## 4. Architektur

### Repository-Struktur

Multi-Repo — vier separate Repositories mit eigenem Release-Zyklus:

```
DecisionMap/                     ← Workspace-Root-Repo (Issues, Haupt-Doku, CI-Koordination)
├── CLAUDE.md                    ← Haupt-Referenz
├── docs/                        ← Detaillierte Spezifikationen
├── Makefile                     ← Workspace-Orchestrierung
├── .templates/                  ← Wiederverwendbare Templates (Jenkinsfile, Makefile, docker/)
├── .libs/                       ← Lokale Symlinks (BashLib, BashTools, MakeLib) — per .gitignore ausgeschlossen
├── backend/                     ← docker-compose, nginx, Seeds, Backups, Makefile (eigenes Repo)
├── frontend/                    ← Nuxt.js App (eigenes Repo)
└── ai-service/                  ← FastAPI + Alembic (eigenes Repo)
```

`backend/`, `frontend/` und `ai-service/` sind im Workspace-Root per `.gitignore` ausgeschlossen —
sie haben eigene Repos. Das Workspace-Root-Repo dient als zentraler Ort für Issues und Projektdokumentation.

Jedes Repo hat eine eigene Jenkins-Pipeline — ein Frontend-Deploy triggert keinen Backend-Build.

```
frontend     → build → test → deploy frontend
ai-service   → test → build → db-migrate → deploy ai-service
backend      → deploy compose + config
```

### Rendering-Strategie

Hybrides Rendering per Route — SPA wo App-Feeling gebraucht wird, statisch wo SEO relevant ist:

| Route | Rendering | Grund |
|---|---|---|
| `/` (Graph) | SPA | Interaktive Cytoscape.js-Visualisierung |
| `/table` | SPA | Virtuelles Scrollen, Filter, Sortierung |
| `/admin/**` | SPA | Interner Bereich |
| `/problem/**` | Prerender | SEO — Suchmaschinen sollen Probleme finden |

Deploy-Artefakt: `nuxt build` (Node.js-Server), nicht `nuxt generate` — SPA-Routes und dynamische Daten funktionieren nicht sauber mit statischer Generierung. Details: [`docs/infrastructure.md`](docs/infrastructure.md).

### Data Layer — Fake/Real Switch

Eine einzige Umgebungsvariable (`USE_FAKE_DATA`) schaltet zwischen In-Memory-Daten und echtem Server um.
Beide Layer implementieren dasselbe TypeScript-Interface — kein Unterschied für Komponenten.

```typescript
export function useProblems() {
  return useRuntimeConfig().public.useFakeData
    ? useFakeProblems()
    : useRealProblems()
}
```

Das vereinfacht die UI-Entwicklung erheblich: Man kann das gesamte Frontend testen, ohne ein Backend zu brauchen.
Contract-Tests (`tests/composables/*.contract.spec.ts`) laufen mit `describe.each` gegen beide Layer gleichzeitig
und stellen sicher, dass Fake und Real dasselbe Verhalten zeigen.

### Trennung UI und Business Logic

Striktes Prinzip auf allen Schichten:

- **Frontend:** Komponenten sind ausschließlich für Darstellung zuständig. Jede Business Logic,
  Datentransformation und API-Kommunikation gehört in Composables.
- **Backend:** Router behandeln ausschließlich HTTP-Belange. Business Logic gehört in Services.
  Services haben keine Kenntnis von HTTP-Konzepten.

---

## 5. Datenmodell

Vollständiges Schema: siehe [`docs/data-model.md`](data-model.md)

### Kerntabellen

```
users ──< problems ──< solution_approaches
              │
              ├──>< problem_cluster >──< clusters
              ├──>< problem_tag >──< tags (hierarchisch: L1–L10)
              └──>< problem_region >──< regions
```

| Tabelle | Zweck |
|---|---|
| `problems` | KI-Probleme mit Titel/Beschreibung in Original + Englisch, Status-Workflow, Embedding |
| `solution_approaches` | Lösungsansätze pro Problem, Markdown (eingeschränkt), eigene Moderation |
| `tags` | Hierarchische Themen-Tags mit Level (L0 Root → L1-L9 KI-Kategorien → L10 User-Tags) |
| `clusters` | KI-generierte Problemfelder mit Centroid-Vektor |
| `regions` | Geografische Regionen (EU, US, APAC, GLOBAL) |
| `votes` | Up-/Downvotes mit Duplikat-Prävention |
| `edit_history` | Änderungsverfolgung (nur für Moderatoren sichtbar) |
| `moderation_log` | Audit-Trail aller Moderationsentscheidungen |

### Tag-Hierarchie

Das Tag-System ist eine mehrstufige Taxonomie — nicht flach:

| Level | Typ | Erstellt von | Beschreibung |
|---|---|---|---|
| L0 | Root | System | Wurzelknoten — übergeordnetes Thema der Plattform |
| L1–L9 | Kategorien | KI (zyklisch) | Hierarchische Kategorien, automatisch aus Problemanalyse generiert |
| L10 | User-Tags | User | Flache Tags ohne Hierarchie (z.B. „shadow-ai", „data-privacy") |

Jeder Tag hat:
- `level` — die Hierarchie-Ebene (0–10)
- `parent_id` — Verweis auf den Eltern-Tag (null bei L0 und L10)
- `locked_by` — Schutz vor manueller Bearbeitung (`admin`, `ai`, oder null)

**Wichtig:** Beim KI-Clustering werden nur die strukturellen Tags (L1–L9) neu generiert.
L0 (Root) und L10 (User-Tags) bleiben immer erhalten.

### Mehrsprachigkeit im Datenmodell

Jedes Textfeld existiert doppelt — Original + `_en`:

- `title` / `title_en`
- `description` / `description_en`
- `content` / `content_en`

`content_language` speichert die Sprache des Originals (ISO 639-1).
Embeddings und Clustering laufen ausschließlich auf den `_en`-Feldern.

### Schlüsselentscheidungen

- **Cluster sind n:m** — ein Problem kann in mehreren Clustern vorkommen (`problem_cluster` mit Weight)
- **Tags und Regionen sind getrennt** — inhaltliche vs. geografische Dimension, bewusst nicht vermischt
- **Anonyme Submissions erlaubt** — `user_id` nullable, Pflicht-Login per Feature Flag zuschaltbar
- **Kein Hard Delete** — ausschließlich Soft Delete über `deleted_at`/`deleted_by`
- **Validierung auf drei Schichten** — Zod (Frontend) → Pydantic (Backend) → PostgreSQL Constraints

---

## 6. Tag-Hierarchie und KI-Generierung

### Das Konzept

Die Tag-Hierarchie ist das zentrale Ordnungsprinzip — sie bestimmt, wie Probleme im
Mindmap-Graph angeordnet werden.

| Level | Erstellt von | Beschreibung |
|---|---|---|
| **L0** | System | Wurzelknoten — das übergeordnete Thema: „Probleme die sich aus der Anwendung, Einführung und dem Arbeiten mit KI für Firmen, Mitarbeiter und Personen ergeben" |
| **L1–L9** | KI (zyklisch) | Hierarchische Kategorien, automatisch generiert durch Analyse aller Probleme in der Datenbank |
| **L10** | User | Flache, frei wählbare Tags ohne Hierarchie (z.B. „shadow-ai", „data-privacy") |

### Wie die KI-Generierung funktioniert

Ein zyklischer Job (manuell ausgelöst oder zeitgesteuert) analysiert alle freigegebenen Probleme
und erzeugt daraus die Kategorie-Hierarchie:

```
Zyklischer Job
    ↓
1. Alle approved Problems mit Embeddings aus der DB lesen
    ↓
2. Clustering-Algorithmus (HDBSCAN) auf die Embeddings anwenden
   → findet natürliche Gruppen ähnlicher Probleme
   (HDBSCAN erkennt automatisch wie viele Gruppen es gibt —
    man muss die Anzahl nicht vorgeben)
    ↓
3. LLM (z.B. GPT-4o) bekommt die Probleme jeder Gruppe
   → generiert ein prägnantes Label + kurze Beschreibung
   → das werden die L1-Tags (Top-Kategorien)
    ↓
4. Innerhalb großer L1-Gruppen: Sub-Clustering
   → erneut Clustering auf die Teilmenge
   → LLM labelt die Untergruppen
   → das werden L2-Tags, bei Bedarf weiter bis L9
    ↓
5. Alte L1–L9 Tags löschen, neue einfügen
   L0 (Root) und L10 (User-Tags) bleiben unangetastet
    ↓
6. Probleme mit den neuen Tags verknüpfen (problem_tag Tabelle)
```

### Skalierung

- Bei wenigen Problemen (~50 Seed) reichen L1 + vielleicht L2
- Tiefere Ebenen (L3–L9) werden erst bei hunderten oder tausenden Problemen relevant
- HDBSCAN kommt mit unterschiedlich großen Gruppen klar — eine Kategorie kann 50 Probleme haben, eine andere nur 5
- Probleme die nirgends reinpassen bleiben als „Noise" ohne strukturellen Tag (behalten aber ihre L10 User-Tags)

### Was ist HDBSCAN?

HDBSCAN (Hierarchical Density-Based Spatial Clustering of Applications with Noise) ist ein
Algorithmus der ähnliche Datenpunkte automatisch zu Gruppen zusammenfasst. Im Gegensatz zu
einfacheren Verfahren muss man nicht vorher angeben, wie viele Gruppen es geben soll —
der Algorithmus findet die natürliche Struktur in den Daten selbst.

Im Kontext von DecisionMap: Jedes Problem hat ein Embedding (einen Zahlenvektor mit 1536 Dimensionen),
der den Inhalt semantisch repräsentiert. Probleme mit ähnlichem Inhalt liegen im Vektorraum nahe
beieinander. HDBSCAN erkennt diese „Klumpen" und ordnet sie zu Gruppen zusammen.

---

## 7. Features im Detail

Vollständige technische Spezifikationen: siehe [`docs/features.md`](features.md)

### Übersetzung

**Aktive Übersetzung beim Einreichen** — nicht passiv via DeepL-Link:

1. User tippt Titel/Beschreibung in beliebiger Sprache
2. Automatische Spracherkennung prüft ob der Text englisch ist
3. Bei Englisch: `_en`-Felder werden automatisch befüllt (kein Translate-Button nötig)
4. Bei Nicht-Englisch: „Translate to English"-Button erscheint
5. Klick übersetzt beide Felder (Titel + Beschreibung) parallel
6. User kann die englische Version vor dem Submit noch anpassen
7. Submit erst möglich wenn `_en`-Felder befüllt und valide sind

Im Fake-Modus wird die Übersetzung mit 700ms Delay simuliert.
Im Real-Modus läuft sie über den KI-Service (TranslationService).

### Ähnlichkeitserkennung

Verhindert Duplikate, bevor sie in die Moderations-Queue gelangen:

- Debounce 600ms während der Eingabe
- Cosine-Similarity via pgvector gegen alle freigegebenen Probleme
- Ab Score 0.85: Hinweis mit Link zum bestehenden Problem
- Ab Score 0.92: Wahrscheinliches Duplikat — Submission blockiert bis User bestätigt
- Schwellenwert konfigurierbar über `SIMILARITY_THRESHOLD`

### Qualitätssicherung und Moderation

Mehrstufiger Ansatz — KI filtert vor, Mensch entscheidet:

```
Problem eingereicht → status: pending
    ↓
KI-Spam-Filter (GPT-4o-mini)
    ↓
Klarer Spam → status: rejected (automatisch)
Unklar/Gültig → status: needs_review
    ↓
Admin prüft in Moderations-Queue
    ↓
Freigegeben → status: approved → Embedding + Clustering + KI-Lösungsansatz
Abgelehnt → status: rejected (mit Begründung)
```

### Bot-Erkennung

Mehrschichtiger Ansatz — kein CAPTCHA (widerspricht UX-Prinzip „so wenig Friction wie möglich"):

1. **nginx Rate Limiting** — 5 Requests/Minute pro IP
2. **DNSBL** (geplant) — bekannte Spam-IPs via `aiodnsbl`
3. **Verhaltens-Signale** — zu schneller Submit, Session-Flood, Multi-Session pro IP, Bot-Agents
4. **Honeypot-Feld** — verstecktes HTML-Feld, bei Befüllung sofort rejected
5. **GPT Spam-Filter** — letzte Instanz

Bei 2+ verdächtigen Signalen: automatisch `rejected`.
Bei 1 Signal: `needs_review` mit Flag im Moderations-Log.

### Voting

Von Anfang an implementiert:
- Up-/Downvotes auf Probleme und Lösungsansätze
- Anonyme Votes über `session_id` + `ip_hash` (DSGVO-konform, keine rohen IPs)
- Duplikat-Prävention per UNIQUE Constraint
- `vote_score` denormalisiert auf Problem/Solution für schnelle Sortierung
- Visualisierung per Feature Flag (`SHOW_VOTING`) zuschaltbar

### Echtzeit-Updates (WebSocket)

CRUD läuft über REST. Rückmeldungen ans UI über WebSocket — so bleibt die Ansicht
im Multi-User-Betrieb aktuell.

Events auf Entity-Ebene: `problem.approved`, `cluster.updated`, `vote.changed`,
`solution.approved`, u.a. Frontend entscheidet ob Re-fetch oder direktes State-Update.

In-Memory Set für verbundene Clients — reicht für MVP-Größe.

### Editieren

- Nur eigene Einträge editierbar
- Nach Freigabe: Edit setzt Status zurück auf `needs_review` (erneute Moderation)
- Vollständige Edit-History — nur für Moderatoren sichtbar
- KI-generierte Einträge (`is_ai_generated: true`) nur vom Admin editierbar

### KI-generierte Lösungsansätze

Werden automatisch generiert wenn ein Problem den Status `approved` erhält:
- Visuell klar getrennt im UI (eigenes „AI-generated"-Label/Badge)
- Separates Ranking — konkurrieren nicht mit Community-Beiträgen
- Keine menschliche Moderation nötig, aber als KI-Inhalt gekennzeichnet

---

## 8. Theme-System

6 vordefinierte Themes + benutzerdefiniertes Theme:

| Theme | Modus | Akzentfarbe |
|---|---|---|
| Default | Hell | Blau (#2563eb) |
| Forest | Hell | Grün (#059669) |
| Sunset | Hell | Amber (#d97706) |
| Midnight | Dunkel | Hellblau (#60a5fa) |
| Obsidian | Dunkel | Violett (#a78bfa) |
| Aurora | Dunkel | Teal (#2dd4bf) |

### Custom-Theme

User wählt eine Akzentfarbe → das System generiert daraus alle UI-Farben automatisch:
- Hex → HSL-Konvertierung
- Ableitung von Hintergrund, Oberfläche, Rahmen, Text, Input-Farben
- Komplementärfarben für Graph-Knoten (Blätter: Farbton +120°, Lösungen: +160°)
- Über 30 CSS Custom Properties werden dynamisch gesetzt

### Theme-aware Logo

Der Header wechselt automatisch zwischen `decisionmap-logo-gradient-light.svg` (heller Modus)
und `decisionmap-logo-gradient-dark.svg` (dunkler Modus) über `isDark` aus `useTheme()`.
Beide SVG-Varianten liegen in `assets/images/` (Gradient Orange→Lila).

Die SVGs haben keinen `<rect>`-Hintergrund — die Pin-Cutouts (Kreise + Linien) sind als
`<mask>` implementiert, was echte transparente Löcher erzeugt und auf jedem Theme-Hintergrund
funktioniert. Header-Höhe: `h-16` (64 px), Logo-Höhe: `h-11` (44 px).

### FOUC-Prävention

Ein blockierendes Inline-Script im `<head>` liest das Theme aus `localStorage` und setzt das
`data-theme`-Attribut + `dark`-Klasse **bevor** Vue geladen wird. Dadurch kein sichtbarer
Farbwechsel beim Seitenaufbau.

### Systemfarb-Präferenz

Wenn kein Theme explizit gewählt ist, wird die Betriebssystem-Einstellung
(`prefers-color-scheme: dark/light`) automatisch erkannt und das entsprechende
Default-Theme geladen.

---

## 9. Permalink-System

Jedes Problem hat einen teilbaren Link: `/?problem=<id>`

- Der Layout liest den Query-Parameter beim Laden
- Graph-View drills automatisch zur Tag-Hierarchie des Problems hinunter
- Table-View filtert auf das einzelne Problem
- Detail-Panel öffnet sich automatisch
- Filter-Chip zeigt „Showing single problem" mit Schließen-Button
- „Share link"-Button im Detail-Panel kopiert den Permalink in die Zwischenablage

---

## 10. UI und Layout

```
┌─────────────────────────────────────────────────┐
│  Header: Logo + Nav + Suchfeld                   │
├──────────────────────────┬──────────────────────┤
│   Graph / Table (70%)    │   Panel (30%)         │
│   Suchfeld filtert beide │   Detail / Formular   │
└──────────────────────────┴──────────────────────┘
```

- Toggle zwischen Graph-View und Table-View
- `+` Button öffnet Eingabeformular im Panel
- Klick auf Graph-Knoten oder Tabellenzeile öffnet Detail im Panel
- Panel kann geschlossen werden — Hauptbereich nutzt dann volle Breite
- Mobile: Panel als Drawer über den Hauptbereich
- Modals sind erlaubt, aber Primär-Flows (Erfassung, Detail) bleiben im Panel

---

## 11. Infrastructure und Betrieb

Vollständige Spezifikation: siehe [`docs/backend.md`](backend.md)

### Makefile

Root-Makefile delegiert an Sub-Repos. `make help` zeigt alle Root-Targets (Setup, Entwicklung, Code-Qualität, Testing). Sub-Repo-Makefiles: `make -C backend help` (Docker, DB, Backup), `make -C frontend help` (dev, lint, test, build).

`make setup` — erstellt `.libs/`-Symlinks zu lokalen Entwicklungs-Bibliotheken (BashLib, BashTools, MakeLib). Einmalig nach dem Klonen, benötigt `DEV_LOCAL`-Env-Variable.

`make dev-up` / `make dev-down` — standalone Dev-Umgebung (Postgres + Directus + Mailpit) über `docker-compose.dev.yml`. Logs: `make -C backend dev-logs`. Test-User anlegen: `make -C backend seed-users`.

### Umgebungsvariablen

Nie hardcoden — alle in `.env.example` dokumentiert. Wichtigste:

| Variable | Beschreibung |
|---|---|
| `USE_FAKE_DATA` | `true` = In-Memory, `false` = echter Server |
| `LLM_PROVIDER` / `EMBEDDING_PROVIDER` | `openai` (Standard) oder `anthropic` |
| `OPENAI_API_KEY` | Für Embeddings + LLM (wenn Provider = openai) |
| `SIMILARITY_THRESHOLD` | Schwellenwert Ähnlichkeitserkennung (0.85) |
| `SHOW_VOTING` | Feature Flag: Vote-Scores im Graph |
| `REQUIRE_AUTH` | Feature Flag: Login für Submissions erzwingen |

### Seed-Daten

SQL-Files in `database/seeds/` — alphabetisch importiert, idempotent via `ON CONFLICT DO NOTHING`.
Dieselben Files für Entwicklung und Tests.

### Versionierung

Build-Scripts verwenden `hashVer` (BashLib) — Format: `<Jahr>.<Quartal>.0-SNAPSHOT<MMDD>.<HASH>` (z.B. `26.1.0-SNAPSHOT0327.a3f9`).
Automatisch via Jenkins — nie manuell setzen. Vollständige Spezifikation: [`docs/backend.md`](docs/backend.md).

### Backup

`make -C backend backup` (lokal) und `make -C backend backup-remote` (vom Server holen).
Backups werden nie eingecheckt — `database/backups/` in `.gitignore`.

---

## 12. Code-Konventionen

Vollständige Beispiele: siehe [`docs/conventions.md`](conventions.md)

### Kurzübersicht

| Bereich | Regel |
|---|---|
| TypeScript-Dateien | `camelCase` |
| Komponenten | `PascalCase` |
| Loop-Variablen | immer sprechend — `problem`, nie `p` oder `i` |
| `any` | Verboten — `unknown` verwenden |
| Logging | `consola` (Frontend) / `structlog` (Backend) |
| API-Aufrufe | Nur in Composables (Frontend) / Services (Backend) |
| Styling | Nur Tailwind Utility-Klassen, kein direktes CSS |
| UI-Strings | Nur über `t()` (i18n), keine hardcodierten Texte |
| Fehlerbehandlung | Nie schlucken, immer mit Kontext loggen |
| Soft Delete | Kein Hard Delete — `deleted_at`/`deleted_by` |

---

## 13. MVP-Timetable (ursprüngliche Planung)

| Phase | Tage | Inhalt |
|---|---|---|
| Infrastruktur | 3 | Docker Compose, Directus, Jenkins, nginx |
| KI-Service | 5 | FastAPI, Spam-Filter, Embeddings, HDBSCAN Clustering |
| Frontend | 5 | Nuxt, Composables, Graph-View, Table-View |
| Admin & Beta | 3 | Moderation, Seed-Daten, End-to-End-Test |
| **Gesamt** | **16 Tage** | **~5–6 Wochen mit Puffer** |

Basis: 4 Stunden produktive Arbeitszeit pro Tag.

### Bewusst zurückgestellt (nach Beta)

- Reputation / Ranking-System für User
- SEO-optimierte Cluster-Seiten
- Export / API
- Multi-Language Support (Frontend-Strings)
- Komplexes Rollen-System
- Cross-Platform (Ionic Vue)
- Redis Pub/Sub (nur bei mehreren Server-Instanzen)

---

## 14. Offene Punkte

- **Clustering-Job implementieren** — HDBSCAN + LLM-Labeling im ai-service (siehe Abschnitt 6)
- **Domain registrieren** — `decisionmap.ai` + `frictionmap.ai` sichern
- **DNSBL aktivieren** — nach Launch wenn Bot-Aktivität zunimmt
