<p align="center">
  <img src="assets/images/decisionmap-logo-gradient-light.svg" alt="DecisionMap" width="320" />
</p>

# DecisionMap

**Die kollektive KI-Problemlandkarte für den Mittelstand.**

Irgendwo in einem anderen Unternehmen kämpft gerade jemand mit exakt demselben KI-Problem wie du.
Ihr werdet euch nie begegnen. DecisionMap ändert das.

User erfassen reale KI-Herausforderungen aus ihrem Unternehmensalltag — Shadow AI, Modellauswahl,
Compliance, Datenschutz bei KI-Tools. Andere liefern Lösungsansätze aus der Praxis. Ein KI-Service
clustert die Eingaben automatisch und visualisiert sie als interaktive Problemlandkarte.

**Kein Beratungstool. Keine Diskussionsplattform. Eine strukturierte, KI-gestützte Wissensbasis
mit Community-Validierung durch Voting.**

**Zielgruppe:** IT-Entscheider, CDOs, KI-Projektverantwortliche in KMU  
**Domain:** [decisionmap.ai](https://decisionmap.ai)

[English Version](README.md)

---

## Status

> **Pre-Beta** — Die Plattform ist technisch fertig, wird aber noch nicht öffentlich beworben.
> Ich suche 10–15 Unternehmen für den Beta-Test. Interesse? → [Issue öffnen](https://github.com/MikeMitterer/decmap_project/issues/new) oder direkt melden.

- Frontend: 147 Tests grün
- Backend: 227 Tests grün (190 Unit + 37 Contract)
- AI-Service: 156 Tests grün
- E2E: 11 Tests grün (Playwright)
- Infrastruktur: Hetzner + Docker + nginx + TLS in Betrieb
- SMTP: AWS SES (Domain-Verifizierung abgeschlossen)

---

## Wie es funktioniert

1. **Problem erfassen** — kurze Beschreibung eines realen KI-Problems aus dem Unternehmensalltag
2. **Lösungsansätze beisteuern** — keine fertigen Rezepte, sondern Erfahrungen aus der Praxis
3. **KI clustert automatisch** — ähnliche Probleme werden gruppiert und in eine Tag-Hierarchie eingeordnet
4. **Visualisierung** — ein interaktiver Graph zeigt die Problemlandschaft, mit Drill-down zu Details

---

## Entwicklungsansatz

Dieses Projekt entstand als Experiment in **Vibe-Coding** — KI-gestützter Entwicklung bei der
Architekturentscheidungen, Debugging und Implementierung in enger Zusammenarbeit mit KI-Assistenten
entstehen. Gleichzeitig ist es ein echtes Produkt mit echten Nutzern als Ziel.

Was das konkret bedeutet:
- Alle Architekturentscheidungen sind dokumentiert (CLAUDE.md, docs/)
- Entscheidungsprozesse und Erkenntnisse werden öffentlich geteilt
- Der Stack wurde bewusst für AI-Engineering-Kompetenz gewählt — pgvector, HDBSCAN, LLM-Integration — nicht weil es die einfachste Option war

Der interessante Teil passiert gerade jetzt. Fortschritt und Erkenntnisse gibt es auf
[LinkedIn](https://www.linkedin.com/in/mangolila/).

---

## Technischer Stack

| Schicht | Technologie | Zweck |
|---|---|---|
| Frontend | Nuxt.js 3 + TypeScript | SPA/SSR-Hybrid, Auto-Imports, SEO-ready |
| CSS | Tailwind CSS | Utility-Klassen, Theme-System per CSS Custom Properties |
| Visualisierung | Cytoscape.js | Interaktive Graph-Darstellung |
| Backend | FastAPI + fastapi-users + SQLAlchemy (asyncio) | Auth, REST API, WebSocket, Admin-Endpoints |
| Datenbank | PostgreSQL + pgvector | Relationale Daten + Embeddings in einer DB |
| KI-Service | FastAPI (Python 3.11+) | Embeddings, Clustering, Spam-Filter, Übersetzung |
| DB-Migrationen | Alembic | Python-nativ, rollbackfähig |
| Echtzeit | WebSocket (FastAPI) | Live-Updates im Multi-User-Betrieb |
| Testing | Vitest / pytest / Playwright | Unit-, Contract- und E2E-Tests |
| Hosting | Hetzner + Docker + nginx | Europäisch (DSGVO), Docker Compose |
| CI/CD | Jenkins → SSH → Hetzner | Lokale Jenkins-Instanz |

---

## Repository-Struktur

Multi-Repo — fünf Repositories mit eigenem Release-Zyklus:

```
DecisionMap/                     ← Workspace-Root (Issues, Doku, CI-Koordination)
├── CLAUDE.md                    ← Technische Haupt-Referenz für alle Repos
├── README.md                    ← English version
├── README.de.md                 ← Dieses File (Deutsch)
├── Makefile                     ← Workspace-Orchestrierung
├── docs/                        ← Detaillierte Spezifikationen
│   ├── backend.md               ← Infrastruktur, Deploy, Versionierung
│   ├── conventions.md           ← Code-Konventionen mit Beispielen
│   ├── data-model.md            ← Vollständiges Datenbankschema
│   ├── features.md              ← Feature-Spezifikationen
│   ├── dev-environment.md       ← Lokale Entwicklungsumgebung (Ports, Services, venv)
│   ├── cmdline.md               ← curl-Beispiele für alle API-Endpunkte
│   └── ses-setup.md             ← AWS SES: Domain-Verifizierung → SMTP → Production Access
├── scripts/                     ← Workspace-Skripte
│   ├── db-backup.sh             ← Einheitliches DB-Backup/Restore (Backend + Infrastructure)
│   ├── env-audit.py             ← .env-Audit gegen .env.example als SoT (--strict, --comment-out, --fill, leak-freier --check Wert-Abgleich)
│   ├── git-push-all.sh          ← Git-Push in allen ausgecheckten Sub-Repos
│   ├── repo-status.sh           ← Git-Status aller Sub-Repos
│   └── smtp-test.py             ← SMTP-Relay-Verifikation (AWS SES)
├── .templates/                  ← Wiederverwendbare Templates (Jenkinsfile, Makefile, Docker)
├── .libs/                       ← Lokale Symlinks (BashLib, MakeLib) — gitignored
├── apps/                        ← Service-Repos (gitignored, eigene Repos)
│   ├── backend/                 ← FastAPI Backend + Alembic (Schema-Owner)
│   ├── frontend/                ← Nuxt.js App
│   └── ai-service/              ← FastAPI KI-Service (kein direkter DB-Zugriff)
└── infrastructure/              ← docker-compose, nginx (eigenes Repo)
```

`apps/backend/`, `apps/frontend/`, `apps/ai-service/` und `infrastructure/` haben eigene Git-Repos
und sind per `.gitignore` aus dem Root ausgeschlossen.

---

## Makefile — Wichtigste Targets

```bash
make help          # Alle verfügbaren Befehle anzeigen
make hints         # Lokale URLs (via Dev-Proxy + direkt) und nützliche Links
make info          # Workspace-Umgebungsvariablen
make setup         # .libs/-Symlinks erstellen (einmalig nach dem Klonen)
make status        # Git-Status aller Sub-Repos (dirty + ahead/behind Remote)
```

**Cross-Repo:**
```bash
make git-push-all  # Git-Push in allen ausgecheckten Sub-Repos
make build-all     # Docker-Images bauen (backend + frontend + ai-service)
make push-all      # Images nach ghcr.io pushen
make test-all      # Alle Tests ausführen
make deploy        # Full-Stack Deploy via infrastructure/
make version       # Aktuelle Versionen aller Sub-Repos anzeigen
```

Sub-Repo-Makefiles:
```bash
make -C apps/backend help      # FastAPI Backend, DB, Backup
make -C apps/frontend help     # dev, lint, test, build
make -C apps/ai-service help   # FastAPI dev, test, build
make -C infrastructure help    # Server-Orchestrierung
```

---

## Lokale Entwicklung

```bash
make dev-up    # nginx-Proxy + Docker (Postgres + Backend-API :8001) + overmind (Frontend :3000 + AI-Service :8000 + Backend-Logs)
make dev-down  # overmind beenden + alle Docker-Services stoppen
```

**Via Dev-Proxy** (`make dev-nginx-up`):

| URL | Dienst |
|---|---|
| http://int.decisionmap.ai | App (Frontend) |
| http://backend.int.decisionmap.ai | Backend API (FastAPI) |
| http://int.decisionmap.ai/api/docs | AI-Service (Swagger) |

**Direkt** (ohne Proxy):

| URL | Dienst |
|---|---|
| http://localhost:3000 | Frontend |
| http://localhost:8001 | Backend API (FastAPI) |
| http://localhost:8001/docs | Backend Swagger |
| http://localhost:8000 | AI-Service |
| http://localhost:8000/docs | AI-Service Swagger |
| http://localhost:8025 | Mailpit (SMTP-Sink) |
| http://localhost:8080 | Adminer (DB-UI, Server: `postgres`) |

Voraussetzung: `overmind` installiert (`brew install overmind`).

→ **Vollständige Anleitung:** [`docs/dev-environment.md`](docs/dev-environment.md)

---

## Architektur-Prinzipien

**Trennung von UI und Logik:**
- Frontend: Komponenten = Darstellung, Composables = Logik + API-Kommunikation
- Backend: Router = HTTP, Services = Fachlogik (Services kennen kein HTTP)

**Validierung auf drei Schichten:**
Zod (Frontend) → Pydantic (Backend) → PostgreSQL Constraints

**Kein Hard Delete:**
Alle Entitäten werden per `deleted_at`/`deleted_by` weich gelöscht.

**Mehrsprachigkeit im Datenmodell:**
Jedes Textfeld existiert doppelt — Original + `_en`. Embeddings und Clustering laufen nur auf `_en`-Feldern.

---

## KI-Features

### Ähnlichkeitserkennung

- Debounced-Prüfung (600ms) via pgvector Cosine-Similarity
- Score ≥ 0.85: Hinweis mit Link zum ähnlichen Problem
- Score ≥ 0.92: Wahrscheinliches Duplikat — Submit erfordert Bestätigung → landet in Review-Queue (kein Auto-Reject)

### Spam-Filter

**Probleme (mehrstufig):**

1. nginx Rate Limiting (5 Req/Minute pro IP)
2. Verhaltens-Signale (zu schneller Submit, Session-Flood, Bot-Agents)
3. Honeypot-Feld (verstecktes HTML-Feld)
4. GPT-4o-mini als letzte Instanz

Kein CAPTCHA — Friction-freies UX ist Designziel.

**Lösungsansätze (nach Login, nur LLM):**
- GPT-4o-mini prüft den Inhalt — kein Verhaltens-Layer nötig (Auth vorausgesetzt)

### Automatisches Clustering

1. Embeddings aller Probleme laden
2. HDBSCAN-Clustering (L2-normalisierte Embeddings, euclidean metric, adaptive `min_cluster_size = max(2, sqrt(n/4))`)
3. LLM (GPT-4o) labelt jede Gruppe → erzeugt hierarchische Tags (L1–L9)
4. Sub-Clustering innerhalb großer Gruppen → tiefere Hierarchie-Ebenen
5. Probleme mit neuen Tags verknüpfen

### Moderation-Workflow

**Probleme:**
```
eingereicht → [Verhaltens-Signale] ─→ needs_review ─→ [Admin] → approved / rejected
            → [LLM-Spam-Filter]   ─→ pending       ─→ [Admin] → approved / rejected
                                   ↘ Spam → rejected (automatisch)
```

**Lösungsansätze** (nach Login, kein Verhaltens-Layer):
```
eingereicht → [LLM-Spam-Filter] → pending → [Admin] → approved / rejected
                                ↘ Spam → rejected (automatisch)
```

---

## Tag-Hierarchie

| Level | Erstellt von | Beschreibung |
|---|---|---|
| L0 | System | Wurzelknoten der Plattform |
| L1–L9 | KI (automatisch) | Hierarchische Kategorien aus Problemanalyse |
| L10 | User | Freie Tags (z.B. „shadow-ai", „compliance") |

---

## Datenmodell (Übersicht)

Vollständige Spezifikation: [`docs/data-model.md`](docs/data-model.md)

```
users ──< problems ──< solution_approaches
              │
              ├──>< problem_tag    >──< tags (L0–L10)
              └──>< problem_region >──< regions
```

| Tabelle | Zweck |
|---|---|
| `problems` | KI-Probleme mit Status-Workflow, Embedding, Original + EN |
| `solution_approaches` | Lösungsansätze pro Problem (Markdown) |
| `tags` | Hierarchische Tags (L0 Root → L1–L9 KI → L10 User) |
| `votes` | Up-/Downvotes, DSGVO-konform über `ip_hash` |
| `edit_history` | Änderungsverfolgung (nur Moderatoren) |
| `moderation_log` | Audit-Trail aller Entscheidungen |

---

## Roadmap

**Erledigt:**
- [x] FastAPI Backend + Auth (fastapi-users, JWT im HttpOnly-Cookie, Magic Link, E-Mail-Verifizierung)
- [x] pgvector Ähnlichkeitserkennung + Duplikat-Filter
- [x] HDBSCAN-Clustering + LLM-Labeling → hierarchische Tags
- [x] Spam-Filter: mehrstufig für Probleme (Rate Limiting → Honeypot → GPT-4o-mini), LLM-only für Lösungsansätze
- [x] WebSocket Echtzeit-Updates (Voting, Graph-Änderungen)
- [x] Moderations-Workflow (Admin-Queue, Batch-Operationen)
- [x] Cytoscape.js Graph-Visualisierung
- [x] Theme-System (6 Presets + Custom)
- [x] Hetzner-Infrastruktur + TLS + AWS SES
- [x] Regions-System: 121 DACH-Regionen (ISO 3166-2) + Geo-Detection für Problemeingabe
- [x] KI-Entwurf für Lösungsansätze (User-triggered, kein Auto-Generieren)
- [x] Solution Form: Translation-Collapsible für Inhaltsfeld
- [x] Lösungsansätze editieren für Owner (PATCH /solutions/:id, lokalisierte Edit-Felder, Auto-Resize)
- [x] Problem-Editierung in User-Sprache (Edit-Felder aus gespeichertem Originaltext, kein Übersetzungs-Round-Trip, Auto-Resize)
- [x] Lösungs-Moderation per KI-Gate (sauber → sofort `approved`, bemängelt → Review-Queue, kein menschlicher Pflicht-Schritt)
- [x] Globale Lösungs-Duplikat-Erkennung (live im Formular + Submit-Backstop, pgvector über alle approved Solutions)
- [x] Sprachunabhängige Suche (Keyword + Semantik): Ein deutsches Stichwort wie „schlecht" findet das Problem jetzt, obwohl nur der englische Canonical für Embeddings indexiert ist — die `original_translations` JSONB-Spalte auf `problems` ist Source of Truth für den Originaltext und wird neben der übersetzten Query durchsucht (Backend Postgres-Volltextsuche über Canonical + `original_translations`, Frontend-Local-Match gegen den angezeigten lokalisierten Titel, Semantik-Pfad unverändert)
- [x] Server-driven Search + Pagination (Phase 1): `GET /problems` ist jetzt Keyset-paginiert (`{items, next_cursor, total}`) mit server-seitigem Filter/Sort und cross-lingualer Keyword- + Semantik-Suche; die Tabelle ist Infinite-Scroll auf einem Cursor-Store, die Moderations-Queues filtern server-seitig
- [x] Server-driven Graph (Phase 2, Drill-Down): der Graph lädt keine kompletten Problem-Sets mehr — beim Mount nur das leichte `GET /problems/cluster-summary`-Aggregat, die Problem-Zeilen pro Cluster werden beim Drill-Down lazy über den paginierten `GET /problems?tags=<id>` nachgeladen (Suche ebenfalls server-seitig). Der Übergangs-Endpoint `GET /problems/all` (samt Data-Layer-`fetchAllProblems`/`fetchProblems`) ist in Task 2.4 entfernt; verbleibend nur noch das Phase-3-„N neue Probleme"-Banner
- [x] Autor-/Firmen-Chips (Phase 1): das Problem-Panel zeigt ein klickbares Autor-Chip (smaragd) und — bei nicht-anonymen Autoren mit gesetzter Firma — ein Firmen-Chip (violett); beide sind an die server-seitigen `user`-/`company`-Filter von `GET /problems` verdrahtet. Mehrere Chips zugleich filtern nach allen: `user`/`company` sind seit [decmap_project#35](https://github.com/MikeMitterer/decmap_project/issues/35) multi-value (komma-separiert; `user` → `IN`-Liste, `company` → case-insensitive `ILIKE`-OR). Jedes Chip trägt ein 👤/🏢-Icon plus `aria-label`/`title`-Tooltip („Nach Autor/Firma filtern"), damit beide unterscheidbar sind ([decmap_project#30](https://github.com/MikeMitterer/decmap_project/issues/30); das Smaragd/Violett-Paar bleibt unverändert). Das Firmen-Chip liest die Firma direkt aus `problem.company` (auf **jedem** `ProblemRead` vom Backend geliefert) und zeigt sich daher bei **jedem** Problem mit gesetzter Firma — nicht nur bei eigenen (`9b8f357`). Das Autor-Chip wurde in `70f8a84` nachgezogen: `author_display_name` reist jetzt auf **jedem** `ProblemRead` mit (pro Seite zusammen mit `company` über **einen** gebatchten `_load_authors`-Query aufgelöst), ein `authorLabel`-Computed im Panel bevorzugt ihn — sichtbar für **jeden** nicht-anonymen Autor — und fällt nur für den eigenen/gecachten User auf den User-Cache zurück. Einloggbare Demo-Autoren mit Firma via Seed `005_demo_authors.sql`
- [x] Filter per URL setzbar ([decmap_project#31](https://github.com/MikeMitterer/decmap_project/issues/31)): Tabellen-Filter sind teil- und bookmarkbar via Query-Parametern. Eine zentrale, erweiterbare Param↔`ProblemQuery`-Map (`useTableFiltersUrl` — `sort`/`dir`/`q`/`semantic`/`tags`/`regions`/`user`/`company`/`status`, ein Eintrag pro Filter) hydratisiert den State beim Mount aus der URL und spiegelt ihn via `router.replace` zurück (kein History-Spam, leere Filter raus, `q`/`semantic` exklusiv). Ein `isHydrating`-Guard — im `finally` zurückgesetzt, damit ein fehlgeschlagener Initial-Load die Tabelle nicht tot stellt — unterdrückt während der Mount-Hydration die Daten-Lade- und Auto-Select-Watches; der `q`/`semantic`-Rückschreib-Pfad bleibt bewusst beim Layout-Header, damit die URL nicht bei jedem Tastendruck überschrieben wird
- [x] Firmen-Filter ([decmap_project#29](https://github.com/MikeMitterer/decmap_project/issues/29)): Das Firmen-Filtern ist an den server-seitigen `company`-Filter von `GET /problems` verdrahtet und erreichbar über das violette Firmen-Chip im Problem-Panel (emittiert den exakten Voll-Namen), den `?company=`-URL-Parameter und die aktiven Firmen-Filter-Chips in der Tabelle (je mit × entfernbar); ein optionales Firmen-Feld bei der Registrierung (`pages/login.vue` Register-Tab → `company` im Register-Call) und in den Settings speist den Wert. Der `user`-Filter bleibt chip-only. Ein Freitext-Eingabefeld über der Tabelle wurde erprobt und dann **zurückgenommen** (`ebb759f`): Das Backend matcht den Firmennamen als Ganzwert (`ilike` ohne Wildcards), eine Teil-Eingabe wie `Acme` lieferte gegen `Acme Manufacturing GmbH` 0 Treffer — für ein Freitext-Feld unbrauchbar. Die Chip-/URL-Pfade liefern den exakten kanonischen Namen und bleiben; die Substring-`%name%`-Backend-Änderung wurde bewusst offen gelassen. Die Tabelle rendert jetzt zusätzlich eine sortierbare **Firmen**-Spalte: Die Firma des Autors reist auf **jedem** `ProblemRead` mit (`company`, `null` für anonyme Probleme, pro Seite über **einen** gebatchten Query aufgelöst — kein N+1), und `sort=company` sortiert server-seitig über alle Seiten danach; die Zelle rendert die Firma als kompakten farbigen Monogramm-Badge (1–2 Initialen, Voll-Name im Hover-Tooltip, deterministische Farbe aus der Cluster-Dot-Palette via `colorFromString`), Klick darauf setzt den Firmen-Filter. Bei offenem Detail-Panel (Tabelle ~70 % Breite) schaltet die Tabelle in einen Kompakt-Modus, der die Spalten Cluster und Eingereicht ausblendet, damit die flexible Title-Spalte ihre Breite behält (`27fa7a9`)
- [x] Cross-linguale Keyword-Such-Symmetrie ([decmap_project#32](https://github.com/MikeMitterer/decmap_project/issues/32)): Die Keyword-Query wird beim ersten Such-Call **in beide Sprachen** übersetzt (generisches `translate_query(text, lang)`) und pro Sprache gegen einen funktionalen GIN-**Postgres-FTS**-Index gematcht (`to_tsvector @@ plainto_tsquery`, ersetzt das frühere ILIKE-Substring; BE `8982048`) — so liefern `q=missing` und `q=fehlend` **dieselbe** Treffermenge (Unit-Test `test_fts_stemming_symmetry_english_plural` — `company`⇄`Unternehmen`, gestubbte Übersetzung). Per-Sprache-**Stemming** schließt zudem die frühere Flexions-Lücke: `fehlt`/`fehlende`/`fehlend` und `company`/`companies` matchen jetzt symmetrisch, was der alte Substring-Match nicht konnte. Die Übersetzungen reisen im Cursor unter einem additiven Key mit — in einem Folge-Refactor (`4d6279d`) vom fixen `q2`=DE-Slot zu einer N-sprachigen Übersetzungs-Map verallgemeinert (Cursor-Key `qt`, Schleife über die `SEARCH_LANGUAGES`-Registry) — max. ein Roundtrip pro Registry-Sprache; Cursor von vor der Map degradieren zu `None` (kein Backwards-Compat-Bruch). Echte Synonyme (lack/missing/absent) brauchen weiterhin die semantische Suche — Stemming ist keine Synonym-Expansion. (Produktiv ist exakte Treffer-Count-Parität zwischen DE- und EN-Query best-effort, nicht garantiert: eine Query erreicht die gebeugten Zeilen der anderen Sprache nur über ihre Einzelwort-LLM-Übersetzung, deren exaktes Token — z.B. Partizip `fehlend` vs. finite Verbform `fehlt` — den Stemming-Match entscheidet; „dieselbe Treffermenge" gilt unter der gestubbten/deterministischen Test-Übersetzung. Analyse 2026-06-30, siehe `docs/features.md`.) Der Recall-Hebel ist inzwischen gelandet (Option B, BE `6fd5c1d` / AI `58fcbad`): `translate_query` liefert pro Sprache jetzt **mehrere Kandidaten** — gebeugte Formen + nahe Synonyme vom neuen ai-service-Endpoint `POST /translate/candidates` — und die Per-Sprache-WHERE OR-verknüpft jeden Kandidaten (Unit-Test `test_multi_candidate_or_expansion`), sodass `missing` auch `fehlend`/`vermisst`/… erreicht statt einer evtl. falsch-flektierten Einzelübersetzung. Die Kandidaten reisen pro Sprache als Liste im Cursor; exakte Treffer-Count-Parität DE↔EN bleibt best-effort, da die LLM-Übersetzung nicht-deterministisch ist.
- [x] UI-Affordanz für die Semantik-Suche ([decmap_project#28](https://github.com/MikeMitterer/decmap_project/issues/28)): die Relevanz-Affordanzen hängen an `relevanceSortActive` = KI-Suche **an und ein Suchbegriff vorhanden** (seit `d0981ab`), nicht am bloßen Toggle — KI-Suche an bei leerem Suchfeld bleibt eine normale, voll sortierbare Liste ohne Hinweis und Sperre. Läuft tatsächlich eine Relevanz-Sortierung, zeigt die StatusBar links einen „Sortiert nach Relevanz"-Hinweis (Akzent-farbiges Label, blinkt 3× beim Erscheinen, respektiert `prefers-reduced-motion`, via `v-if` entfernt sobald aufgehoben), die Tabelle gräut und deaktiviert die Spalten-Sort-Header (Tooltip) als In-Table-Affordanz und rendert pro Zeile ein „{n}% match"-Badge (bewusst auch auf DE englisch, nicht „Übereinstimmung") aus dem Backend-Relevanz-`score` (`1 − Distanz`, auf den `Problem`-Typ gemappt in `mapProblem`) — gestaltet als KI-Showcase-Chip (`94c57e3`) mit Funkel-Icon, Mini-Relevanzbalken und erklärendem Tooltip, eingefärbt mit einem eigenen `--th-ai-accent`-Token, das bewusst distinkt vom User-CTA-Akzent bleibt (erste Referenz-Instanz des KI-Marker-Designsystems, [decmap_project#39](https://github.com/MikeMitterer/decmap_project/issues/39)). Keyword-/Default-Modus unverändert, der opake Cursor-Contract bleibt unangetastet
- [x] Graph-Drill-Down Overlap-Fix ([decmap_project#33](https://github.com/MikeMitterer/decmap_project/issues/33)): neu hinzugefügte Nodes aus `buildGraphElements()` starteten bei (0,0) und stapelten sich für einen Frame, bevor das synchrone `preset`-Layout sie positionierte — der Remove/Add/Layout-Zyklus läuft jetzt innerhalb von `cy.batch()`, sodass kein Zwischen-Frame rendert und der Drill-Down nie überlappende Nodes/Labels aufblitzt; Folge-Korrekturen (2026-06-30) härten den Drill-Down weiter: das Stylesheet wird jetzt **vor** dem Batch gesetzt (ein `cy.style()` im `cy.batch()` greift nicht auf die im selben Batch hinzugefügten Elemente — Ursache der fetten grauen Edges + grauen Cluster-Punkte nach einem Problem-Klick), der Drill-Down fittet jetzt nur noch auf die **echten** Knoten via `fitDrillView` — das Layout-eigene `fit: true` fittete die noch bei (0,0) liegenden Dekorations-Badges mit und blähte die Fit-bbox zu einem falschen (zu niedrigen, ~67%) Zoom auf; das Re-Fitten auf die Echt-Knoten nach dem Settle samt 100%-Deckel behebt sowohl diesen Unter-Zoom als auch den Über-Zoom auf dünnen Clustern — und (2026-07-01) wird der `maxZoom` des Drills **vor** dem Layout-`fit` auf 100% gedeckelt (danach wieder auf den manuellen Zoom-Deckel 3 restauriert), sodass der Fit direkt auf ≤100% landet statt auf ~120–130% zu schießen und zurückzuschnappen, das Grid legt jede Tier-Ebene in ihrer natürlichen Größe mit festen node-relativen Gutter aus (`cellW`/`cellH`/`TIER_GAP`, locale-skaliert `s = 1` EN / `1.25` DE) und wählt die Spaltenzahl, die den Fit-Zoom **maximiert** (deterministisch), statt `round(sqrt(...))`, dessen Rundung bei winziger Aspekt-Änderung die Spalten umspringen ließ und die eigentliche Ursache des instabilen 67%↔99%-Zooms war, dann skaliert **ein** zoom-gecapptes `fit` das Ganze uniform in den Viewport — ersetzt das frühere Container-Bruchteil-Spacing (samt `ROW_STEP`-Locale-Offsets), das die Reihen bei höheren deutschen Labels berühren ließ, ein Klick auf den bereits gedrillten Cluster ist jetzt ein No-op (das Neurechnen der identischen Ansicht las sich als ruckartiger Zoom-Sprung), ein `ResizeObserver` re-fittet den aktiven View bei Container-Größenänderung (Detail-Panel auf/zu, Fenster-Resize), sodass der Graph nicht mehr unter das Panel rutscht, und die Verbindungslinien werden dezenter gerendert (Cluster-/Problem-Kanten blasser, Brand-Gradient-Kanten Root→L1 bei `line-opacity 0.55`), damit die Knoten hervortreten und die Linien zurücktreten, und der Drill wurde auf einen instanten Schnitt reduziert — lazy-geladene Problem-Seiten werden zu **einem** debounced Re-Render (140ms) zusammengefasst statt eines vollen Re-Layouts pro gestreamter Seite, und der finale Fit ist instant (`fitDrillView` fittet die Echt-Knoten und deckelt auf 100%, keine Kamera-Animation); ein kurz probierter 200ms-Glide wurde verworfen, weil der Kamera-Flug sich als störende Animation las statt als sauberer Schnitt in den Endzustand; und (2026-07-01) ist die Gegenbewegung — die Rückkehr in die Mindmap-Übersicht — jetzt ein instanter Schnitt statt einer Animation: eine animierte `showMindmap`, die sich mit einem Re-Render überlappte, ließ die Dekorations-Badges (Cluster-Punkte + Count-Badges) aus dem Ursprung über den Screen fliegen (gemessener Sprung auf ~608px, dann Flug auf ~95px) — deshalb laufen jetzt alle sechs `showMindmap`-Aufrufe instant (`showMindmap(false)`), konsistent mit dem instanten Drill; ohne animierte Rückkehr erscheinen die Badges direkt positioniert statt zu fliegen (verifiziert: Badge-zu-Parent-Abstand konstant ~95px)
- [x] Security-Audit (2026-07-05/06, Report: [`docs/security-audit-2026-07-05.md`](docs/security-audit-2026-07-05.md)): vollständiger Workspace-Audit, alle umsetzbaren Findings gefixt — das Auth-JWT wandert vom localStorage in ein **HttpOnly-Cookie** (`decisionmap_auth`, `SameSite=Lax`, Frontend sendet `credentials: 'include'`; Login/Magic-Verify antworten ohne Token-Body, Logout löscht das Cookie server-seitig), nicht-`approved` Probleme/Lösungen liefern Dritten **404** (Existenz wird nie bestätigt; Owner/Superuser sehen sie weiterhin), `GET /health` gibt keine Build-Version mehr preis, **fail-closed Start-Validierung** für `SECRET_KEY`/`SERVICE_TOKEN` (leere/Platzhalter-Werte brechen den Start ab, Dev-Opt-in nur via explizitem `ALLOW_INSECURE_DEV=true`), und SSR/Prerender-Markdown-Sanitizing via `isomorphic-dompurify` (der frühere Raw-Output-Bypass ist entfernt — Allowlist + Link-Hardening laufen jetzt auf Server und Client identisch). Bewusst verschoben (BE-08): ein authentifizierter Admin-WS-Kanal — bis dahin trägt der geteilte unauthentifizierte `/ws`-Broadcast nur opake UUIDs + Status-Enums, nie Titel/Content/Ablehnungsgründe

**Nächste Schritte:**
- [ ] Bold UI Redesign — Glass-Morphism mit Mesh-Orb-Ambient-Background (sichtbar durch transparente TopBar/StatusBar sowie Login/Status/Admin-Seiten), DmSidebar (72px) + DmTopBar App-Shell mit fixierter englischer Brand-Tagline (`MAP PROBLEMS · FIND SOLUTIONS`, nie übersetzt), Glass-Cytoscape-Graph mit Vote-Score-Badges, inset Cluster-Count-Badges, Cluster-Dot-Indikator pro Cluster eigene Farbe (deterministische 12-Farben-Palette via `utils/tagColor.ts`, geteilt mit dem Tabellen-Chip — jedes Cluster behält dieselbe Identitätsfarbe über alle Views), Brand-Gradient-Root-Node (Orange→Pink→Magenta→Violett) und Brand-Gradient-Edges Root→L1 (Orange→Magenta), Radial-Layout mit Geschwister-Dichte-Kollisionsvermeidung (`r ≥ nodeSpacing × N / span`), Mindmap öffnet bei 100% Zoom mit Root-Node zentriert (`centerOnRoot()` stellt — falls vorhanden — den gespeicherten Viewport wieder her, sonst 100% Zoom auf Root, kein `fit` beim ersten Layout), ziehbare Nodes mit Decoration-Badges die bei jeder Positionsänderung mitwandern (`cy.on('position', selector, repositionBadgesFor)`) und User-gezogene Positionen in localStorage persistiert (`graph-node-positions`, beim nächsten Layout via `applyStoredPositions()` wiederhergestellt — algorithmische Position nur für Nodes ohne gespeicherte Position; Positionen sind pro View-Ebene gescoped (Mindmap vs. gedrillter Cluster), sodass ein im Überblick verschobener Node auf jeder Drill-Ebene seine eigene Position behält) sowie der Mindmap-Viewport (Zoom + Pan) mit 400ms-Debounce in `graph-viewport-mindmap` auto-gespeichert (`cy.on('viewport', ...)` nur bei `viewLevel === 'mindmap'`, Reload stellt den exakten Zustand wieder her) mit Reset-Positions-Button neben den Zoom-Controls (löscht beide Storage-Keys und re-runt das aktive Layout — `showMindmap` / `showUnclusteredView` / `applyTagFilters` — sodass wieder die algorithmischen Positionen und der Default-Viewport wirken), Glass-Tabellenansicht (5px-Rounded-Header, Cluster-Chip nur mit Punkt in Cluster-Farbe — Text und Hintergrund bleiben neutral, damit die Zeile ruhig liest; der Punkt allein trägt die Identität), vereinfachte Settings (Mode + 6 Accent-Swatches + ein separater KI-Akzent-Picker (6 Swatches, leer = Theme-Default, persistiert via `dm-ai-accent`, über Theme-Wechsel hinweg wiederhergestellt) + Gradient-Slider, persistiert via `dm-accent` / `dm-grad-strength`; Appearance ohne Login zugänglich), Dark-Glass-Out-of-Box-Default beim Erstbesuch (dunkles Glass-Theme + Sunset-Accent + Fuchsia-KI-Akzent; OS-Hell/Dunkel-Following bleibt opt-in über eine explizite „system"-Preference), Live-Systemstatus-Label und Live-Graph-Zoom-Anzeige im Footer (`useGraphZoom`, sichtbar nur auf dem Graph-View; der Prozentwert selbst in der Accent-Farbe, das Wort „Zoom" faint), die neben der Zoom-Anzeige auch die Maus-/Tastatur-Navigation des Graphen als Inline-Hinweis zeigt (Scroll = Zoom, ⇧+Scroll = horizontal und Ziehen = verschieben inline, mit den Aktionswörtern in der Accent-Farbe; die volle Liste — ⇧+Strg+Scroll = vertikal, Pfeiltasten = verschieben/zwischen Problem-Nodes navigieren — im `title`-Tooltip; unter `md` ausgeblendet), auth-sensitiver Lösungs-CTA (Full-Width-Accent-Button **vor** der Lösungs-Liste, damit er auch bei wachsender Liste sichtbar bleibt — Plus-Icon + „Lösung hinzufügen" für eingeloggte User, Lock-Icon + „Anmelden, um beizutragen" für Gäste; beide Varianten emittieren `add`, der Gast-Redirect kodiert View + Problem + Intent (`?problem=<id>&solution=new`), sodass der User nach dem Login in derselben View landet — mit wiederhergestelltem Panel und erneut geöffnetem Lösungs-Formular), neu gestaltete Lösungs-Karten (Header-Zeile mit Accent-farbiger Avatar-Pille + Author-Name in Space Grotesk + geteiltes `AiBadge` (Sparkle-Icon im eigenen `--th-ai-accent`, bewusst distinkt vom User-CTA-Akzent) — ersetzt das 🤖-Emoji-Prefix und vereinheitlicht sechs zuvor divergente `is_ai_generated`-Badges, während das KI-Marker-Designsystem über alle KI-Touchpoints ausgerollt wird ([decmap_project#39](https://github.com/MikeMitterer/decmap_project/issues/39)) — + faint mono Vote-Score; Content als 2-Zeilen-Preview via `stripMarkdown()` + Tailwind `line-clamp-2` statt harter Zeichen-Limit, sodass die Trunkierung mit der Panel-Breite skaliert — identisches Karten-Vokabular im Graph-Lösungs-Popup, damit Right-Panel und Popup eine gemeinsame visuelle Sprache teilen), Brand-Gradient ausschließlich für Identitäts-Flächen (Logo-Wordmark, Root-Node, Cluster→Root-Edges, Login-Headline — alle anderen CTAs nutzen die User-gewählte Akzentfarbe), EN/DE-Pill-Switcher absolut positioniert oben rechts auf `/login` (gleiche `LanguageSwitcher`-Component wie in der App-Shell, vor dem Anmelden sichtbar damit Erstbesucher die Sprache wechseln können ohne sich einzuloggen), DSGVO-konforme Self-Hosted Fonts, Neues-Problem-Formular öffnet als Centered Modal (T-12 — `<Teleport to="body">` aus `ProblemForm.vue` selbst, 680px R-02 Glass-Surface, Sticky-Footer mit `form="problem-form"`-Submit-Attribut, Similarity-Card inline zwischen Titel und Beschreibung; Problem-Detail bleibt im Side-Panel), Lösungs-Formular öffnet als Split-Editor-Modal (T-13 — self-contained `<Teleport to="body">` aus `SolutionForm.vue` selbst, 1080px R-02 Glass-Surface, permanenter Write | Live-Preview-Split statt der früheren Schreiben/Vorschau-Tabs, funktionale Markdown-Toolbar (Fett/Kursiv/Überschrift/Zitat/Liste/Link — umschließt die Auswahl oder setzt ein Zeilen-Präfix am Cursor), ESC/Backdrop-Schließen, ⌘+Enter zum Absenden; das Side-Panel zeigt weiter das Problem-Detail hinter dem Backdrop) (`branch: feature/bold-redesign`, 147 Tests grün, merge-ready)
- [ ] Clustering Smoke-Test verifizieren
- [ ] Beta-Zugang für erste Unternehmen
- [ ] Stripe-Integration (SaaS-Pricing)
- [ ] Regionsbasierte Filterung und Ranking im Graph-View
- [ ] Server-driven Search + Pagination (Phase 3) — den Voll-Re-Fetch bei `problem.created` durch ein „N neue Probleme"-Banner ersetzen; der Graph-Drill-Down und die `GET /problems/all`-Entfernung (Task 2.4) sind bereits ausgeliefert (siehe [`docs/features.md → Sprachunabhängige Suche`](docs/features.md))
- [ ] Cross-linguale Volltextsuche + Relevanz-Ranking (F2) — das Backend ist **gelandet** (Tasks 1–4): die registry-getriebene Postgres-FTS (`plainto_tsquery` gegen per-Sprache funktionale GIN-Indizes, Migration 010) hat Keyword-ILIKE im `q`-Pfad ersetzt, `fehlt`/`fehlende`/`missing` matchen jetzt symmetrisch via Stemming, plus das opt-in `sort=relevance` (`ts_rank` über die Registry-Sprachen, keyset-paginiert; BE `59a2b29`, #37). Das Frontend-`sort=relevance` ist jetzt ebenfalls **gelandet** (Task 5, FE `d3a6950`); seit 2026-06-30 ist Relevanz bei aktiver Keyword-Suche (Begriff vorhanden, KI-Suche aus) **standardmäßig an** (am Übergang in diesen Zustand gesetzt, damit ein manuelles Ausschalten das Weitertippen überlebt) und sendet `sort=relevance` an `/problems` samt bestehendem StatusBar-Hinweis „Sortiert nach Relevanz". Der explizite „Sort by relevance"-Toggle-**Button** wurde inzwischen **entfernt**: ein Klick auf einen beliebigen Spalten-Header verlässt jetzt die Relevanz und sortiert die geladenen Treffer nach dieser Spalte (innerhalb derselben Suche kein expliziter Rückweg zur Relevanz — eine neue/geleerte Suche startet wieder bei Relevanz). Die Sort-Header sind nur noch im **Semantik**-Modus gesperrt (dort ordnet das Backend server-seitig nach Embedding-Distanz); im Keyword-Relevanz-Default bleiben sie klickbar, und während aktiver Relevanz erscheint kein irreführender Sort-Pfeil. Task 6 (Extensibility-Smoke-Test `test_third_language_needs_only_registry_and_index` + Doku, BE `820083e`) ist ebenfalls **gelandet** — alle sechs F2-Tasks sind drin und die finale Branch-Review ist eingearbeitet (insbesondere I-1: die `original_translations`-Persist-Allowlist wird jetzt aus der Such-Registry abgeleitet — eine Sprache hinzufügen ist damit wirklich nur Registry-Eintrag + Index, kein zweiter hartkodierter Gatekeeper) (siehe [`docs/specs/2026-06-27-f2-cross-lingual-search-design.md`](docs/specs/2026-06-27-f2-cross-lingual-search-design.md))
- [ ] Diskussion / Forum (post-Launch, [decmap_project#38](https://github.com/MikeMitterer/decmap_project/issues/38)) — leichtgewichtige In-App-Kommentare, **am Problem verankert, am Cluster aggregiert**: Threads hängen an stabilen Problem-UUIDs (Cluster-L1-Tags werden von HDBSCAN neu berechnet und verlören ihren Anker), die Cluster-Ansicht zieht die neueste Diskussion über ihre Probleme zur Laufzeit zusammen. Nutzt ~80 % vorhandener Bausteine (Markdown + DOMPurify, LLM-Spam-Filter + `needs_review`-Queue, WebSocket, Voting, Soft-Delete). Launch-gated: erst nach dem öffentlichen Launch gebaut, wenn der Bedarf nachgewiesen ist; eskaliert zu Discourse + SSO, falls echte Forum-Features verlangt werden
- [ ] DNSBL-Check aktivieren (post-Launch)

---

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Technische Haupt-Referenz, Gotchas, Konventionen |
| [`docs/backend.md`](docs/backend.md) | Infrastruktur, Deploy, Makefile, Versionierung |
| [`docs/conventions.md`](docs/conventions.md) | Code-Konventionen mit Beispielen |
| [`docs/data-model.md`](docs/data-model.md) | Vollständiges Datenbankschema |
| [`docs/features.md`](docs/features.md) | Feature-Spezifikationen im Detail |
| [`docs/moderation-criteria.md`](docs/moderation-criteria.md) | KI-Spam-Filter-Kriterien (SSoT) |
| [`docs/security-audit-2026-07-05.md`](docs/security-audit-2026-07-05.md) | Security-Audit-Report: Findings, Fixes, bewusst verschobene Punkte |
| [`docs/dev-environment.md`](docs/dev-environment.md) | Lokale Entwicklungsumgebung |
| [`docs/ses-setup.md`](docs/ses-setup.md) | AWS SES: Domain-Verifizierung → SMTP → Production Access |
| [`docs/cmdline.md`](docs/cmdline.md) | curl-Beispiele für alle API-Endpunkte |
| [`docs/ui-test-data.md`](docs/ui-test-data.md) | Realistische Testdaten (KMU/DACH) und Spam-Szenarien für manuelles UI-Testing |

---

## Mitmachen

**Beta-Zugang:** Du leitest KI-Projekte in einem Unternehmen und willst die Plattform testen?
→ [Melde dich via Issue](https://github.com/MikeMitterer/decmap_project/issues/new)

**Feedback & Bugs:** [Issues](https://github.com/MikeMitterer/decmap_project/issues)

**Kontakt:** [office@mikemitterer.at](mailto:office@mikemitterer.at)
