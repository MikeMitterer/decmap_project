# task-verification-workflow — Design-Spec

> **Datum:** 2026-07-26
> **Status:** Design abgestimmt, bereit für Implementierungs-Plan
> **Ziel:** Das im `apps/frontend/_tickets/`-Ordner gewachsene Arbeitsprinzip als
> portablen, projektübergreifenden **Skill** extrahieren — nicht als DecisionMap-
> Spezifikum. Die projektspezifische Designer↔CC-Kurier-Maschinerie bleibt außen vor.

---

## 1. Kontext & Problem

Im Frontend ist ein reifes Ticket-System entstanden (`apps/frontend/_tickets/`):
`STATUS.md` (Hub mit INBOX/OUTBOX/QUEUE/ARCHIVE), `README.md` (Workflow +
10 Template-Mindeststandards), einzelne `T-NN`/`R-NN`-Ticket-Files, `VERIFY.md`
(5-Spalten-Cheatsheet), `QUESTIONS.md` (Fragen-Buffer beim Testen).

Das System fusioniert **zwei Dinge**, von denen nur eines portabel ist:

- **(A) Designer↔CC-Async-Protokoll** — zwei KI-Instanzen (Design-System-KI +
  Claude Code), Mike als menschlicher Mittelmann, ZIP-Transfer, INBOX/OUTBOX,
  Roundtrips. **Stark an das spezielle Setup gekoppelt.**
- **(B) Das Arbeitsprinzip** — Zerlegung in kleine verifizierbare Einheiten,
  zweistufige Mensch/KI-Verifikation, Fragen-Capture. **Portabel, das eigentliche
  Juwel.**

Der Skill extrahiert **(B)**. **(A)** bleibt projektlokale Doku.

### Nicht-Ziele / Reinvent-Risiken (bewusst adressiert)

- **GH-Issues nicht neu erfinden.** Lokale Tickets sind ephemere Ausführungs-
  einheiten; das durable „Warum" lebt in GitHub-Issues. GH wird **ergänzt, nie
  ersetzt** (siehe §6).
- **superpowers nicht duplizieren.** `verification-before-completion` (Evidenz vor
  Claims) und `executing-plans` (Zerlegung mit Review-Checkpoints) lehren die
  Prinzipien schon. Dieser Skill liefert die **persistenten Artefakt-Formate**,
  die diese Prinzipien über Chat-Sessions und über die Mensch/KI-Grenze hinweg
  dauerhaft machen — und **verweist** auf jene Skills, statt sie zu kopieren.

---

## 2. Das Arbeitsprinzip (Kern)

1. **Zerlegen** — kleine, einzweckige, time-boxte Einheiten (Tickets);
   scope-limited-by-default (z.B. „UI-only", solange das Ticket nicht mehr erlaubt).
2. **Zweistufig verifizieren** — die KI macht einen Live-Vorabcheck mit
   Ehrlichkeits-Legende (`✅/⚠️/◑/➖`) und notiert Evidenz; der Mensch macht den
   Final-Check in einer **getrennten, nie überschriebenen** Spalte.
3. **Ort = Status** — offene Tickets im Board-Root, erledigte in `solved/`;
   `git mv … solved/` bei Fertigstellung ist die einzige Statusänderung (keine
   Emoji-Stati an vier Stellen synchron halten).
4. **Fragen drainieren** — `QUESTIONS.md` ist ein ephemerer Capture-Buffer, der
   gegen leer tendiert: jeder Eintrag löst auf zu *sofort erledigt / GH-Issue /
   beantwortet+gelöscht*. Nichts wohnt dort dauerhaft.
5. **GH ergänzen, nie ersetzen** — Tickets ephemer, GH durable.

Der Designer-Kurier (STATUS.md INBOX/OUTBOX) ist eine **optionale Erweiterung**
von Punkt 2 + Handoff, wenn eine zweite Partei async beteiligt ist. Kein Kern.

---

## 3. Was der Skill ist

- **Name:** `task-verification-workflow`
- **Ort:** system-level (`~/.claude/skills/`) — portabel über alle Projekte
  (konform zu Mikes Regel: allgemeine Skills → `~/.claude/skills/`,
  projektspezifisches ins Repo).
- **Ortsagnostisch:** der Skill lehrt Prinzip + Formate; *wo* der `_tickets/`-Ordner
  liegt, ist eine dokumentierte Entscheidung mit Empfehlung (§7).
- **Abgrenzung:** referenziert `verification-before-completion` und
  `executing-plans`, statt deren Inhalte zu wiederholen.

---

## 4. Artefakte & Formate

### 4.1 Ticket-File (`T-NN-kurz-slug.md` im Board-Root) — Struktur & Reihenfolge

Ein Ticket ist der **vollständige Container** einer Arbeitseinheit — Beschreibung,
Akzeptanz **und Verify-Matrix in einer Datei**. Kein separates Verify-File
(sonst Sync-Problem eine Ebene kleiner). `git mv` archiviert alles atomar.

**Feste Reihenfolge im File** (bewusst: die Verify-Matrix steht **oben**, direkt
nach dem Header — sie ist die Haupt-Interaktionsfläche, kein Scrollen bis ans Ende):

**1. Header (kompakt, reines Markdown)** — ID + Titel als H1, Metadaten als
einzeilige Markdown-Tabelle, dann die Kurzbeschreibung. Kein YAML-Frontmatter
(Lesbarkeit; das spätere `gen-index.sh` parst die Tabelle):

```markdown
# T-16 · <Titel>

| Repo | Status | Time-box | Scope | GH-Issue |
|---|---|---|---|---|
| frontend | ready | ~1.5 h | UI-only | #NN |

**Löst:** 1–2 Sätze — was das Ticket löst.
```

- `Repo`: `frontend | backend | ai-service | infra | root | cross` (Liste der
  berührten Repos bei Cross-Repo, §7.1).
- `Status`: `ready | in-progress | blocked | done`.
- `Scope`: `UI-only | <explizit erweitert>`.
- `GH-Issue`: `#NN` (optional, das durable „Warum") — oder `—`.

**2. Verify-Matrix** — direkt nach dem Header (§4.2). Oben positioniert, damit ohne
Scrollen geprüft und annotiert werden kann.

**3. Ticket-Details** — darunter:
- **Kontext / Ziel** — ausführlicher als die Header-Kurzbeschreibung, soweit nötig.
- **Akzeptanzkriterien** — Checkliste (`- [ ]`), abhakbar (Definition of Done).
- **Side-Effects** — Pflicht-Sektion (auch „keine").
- **Auflösung** — Commit-Hash(es) je Repo (`backend d8410fd`), Lint-Status,
  Findings. Am Ende, wird zuletzt gefüllt; ersetzt die INBOX-Meldung im Solo-Modus.

### 4.2 Verify-Matrix (im Ticket eingebettet)

Spalten: `# | Where | Look for | AI | Human`

- **`AI`** — die eigene Live-Verifikation der KI. Legende:
  `✅` bestätigt · `⚠️` bestätigt mit Einschränkung (Fußnote) ·
  `◑` teilweise (Fußnote) · `➖` keine Live-Verifikation (nur Unit/Review).
  **Nur die KI schreibt hier**; Evidenz als Fußnote unter der Tabelle.
- **`Human`** — allein der Mensch. **Nie von der KI überschreiben.**
- „Where" = URL/Pfad, „Look for" = beobachtbares Kriterium.

Diese Matrix ist die durable, datei-basierte Instanz von
`verification-before-completion`: die KI muss Evidenz notieren und darf `✅` nicht
behaupten, wo nur `➖`/`◑` zutrifft. Over-Claims werden in der Fußnote korrigiert.

### 4.3 `QUESTIONS.md`

Eine Datei, **tendiert gegen leer**. Format je Eintrag:

```
- [ ] <Frage/Gedanke, mitten im Testen notiert>
```

Auflösung (Pflicht, zeitnah) → genau eines von:
- **sofort erledigt** → abhaken + 1 Zeile Ergebnis, dann bei nächster Rotation entfernen;
- **GH-Issue** → Eintrag ersetzt durch `→ #NN`, dann entfernen;
- **beantwortet** → Antwort steht durable woanders (Commit/Doku/GH) → **löschen**.

Fragen werden **nicht** archiviert (im Gegensatz zu Tickets). Ihr Wert liegt nach
der Auflösung woanders; git-History ist der Audit-Trail. Optional
`QUESTIONS-answered.md` (Frage + 1 Zeile + Issue-Link), wenn ein sichtbarer
Verlauf gewünscht ist — aber Default ist Löschen.

**Unterscheidung, die den Rotations-Unterschied trägt:**
Tickets **akkumulieren** (in `solved/`), Fragen **drainieren** (nach GH / raus).

---

## 5. Rotation & Ort = Status

```
_tickets/
├── README.md            # Workflow + Konventionen (stabil, wächst nicht)
├── QUESTIONS.md         # ephemer, tendiert gegen leer
├── INDEX.md             # optional, generiert: 1 Zeile je offenem Ticket
├── T-16-....md          # offene Tickets liegen direkt im Board-Root
├── T-17-....md
└── solved/
    ├── T-14-....md
    └── T-15-....md
```

- **Ort = Status.** Ein Ticket-File im Board-**Root** ist offen; erledigt wird es
  per `git mv … solved/`. Kein `active/`-Unterordner. `in-progress`/`blocked` sind
  ein **Header-Feld**, kein eigener Ordner.
- **Fertig = `git mv T-14*.md solved/`.** Eine Quelle, keine Tabellen-Stati.
- **Bonus:** getrennte Files eliminieren Merge-Konflikte — der frühere
  „append-at-top, immutable-below"-Trick wird überflüssig.
- **`solved/` skaliert:** wird im Arbeitsalltag nie geöffnet (Scan-Kosten null).
  Bei Bedarf `solved/phase-E/` gruppieren — erst wenn nötig (YAGNI).
- **Ein-Blick-Überblick** (den das alte monolithische `VERIFY.md` bot) ersetzt das
  Root-Listing der offenen Ticket-Files selbst plus optional ein dünnes
  **generiertes** `INDEX.md` (nicht handgepflegt).

Dieses Muster ist kein Neuland — es entspricht dem etablierten „ein Markdown pro
Work-Item, erledigte in einen Archiv-Ordner" (wie `executing-plans` mit Plan-Files).

---

## 6. GH-Issue-Grenze

| Aspekt | lokales Ticket | GH-Issue |
|---|---|---|
| Zweck | ephemere Ausführungseinheit (≤ ~2 h) | durables „Was/Warum" |
| Lebensdauer | bis `solved/` | bis geschlossen, dann Historie |
| Autor | Mensch / KI im Arbeitskontext | Mensch / promoviert aus QUESTIONS |

**Regel:** Jeder `QUESTIONS.md`-Eintrag und jedes nicht-triviale Ticket, das
durable Scope trägt, referenziert ein GH-Issue statt es zu ersetzen. Der **einzige**
reale Konflikt mit GH ist **Drift** (QUESTIONS/Tickets werden still zum Schatten-
Backlog) — die Drain-Regel (§4.3) und Ort=Status (§5) verhindern das.

---

## 7. Multi-Repo: Ort folgt Scope (verteilte Boards)

DecisionMap ist ein Multi-Repo-Workspace (Root-Repo = Meta/Doku; `apps/*` +
`infrastructure/` gitignored, eigene Release-Zyklen). Grundsatz: **der Ort eines
Artefakts folgt seinem Scope** — verteilt, nicht zentralisiert.

- **Jedes Sub-Projekt *kann* ein eigenes `_tickets/`-Board haben** — gilt dann nur
  für dieses Repo (colokiert mit Code + dessen git-History + Commit-Hashes).
- **Hat das Root ein `_tickets/`-Board, gilt es projektübergreifend** — für echt
  übergreifende Arbeit.
- Ein Board ist **optional** (`kann`): ein Repo ohne `_tickets/` nutzt den Workflow
  einfach nicht. Der Skill ist ortsagnostisch und trägt dieses Modell nativ.

„Ein Board" bedeutet **eine Methode** (via Skill), nicht **ein Ordner**.

### 7.1 Single-Home nach Ownership (die Regel gegen Ausfransen)

Die Trennung ist nicht scharf — ein Frontend-Ticket kann Backend-Änderungen
erzwingen. Damit Tickets nicht doppelt entstehen oder „wohin damit?" jedes Mal neu
verhandelt wird, gilt **eine** Regel:

> **Ein Ticket hat genau einen Ort — bestimmt davon, wo das *Deliverable / die
> Akzeptanzkriterien* liegen, NICHT davon, wo überall Code angefasst wird.**

- Frontend-Feature mit kleinem Backend-Endpoint als Nebeneffekt → **frontend-owned**,
  lebt in `apps/frontend/_tickets/`. Die Backend-Änderung wird **nicht** neu abgelegt,
  sondern in der „Auflösung" als Commit-Hash notiert (`backend d8410fd`).
  `Repo:`-Header = `cross` bzw. Liste der berührten Repos.
- Echt übergreifend (kein primärer Owner — workspace-weiter Refactor, geteilte
  Konvention, koordinierte infra+backend+frontend-Änderung) → **Root**-Board.
- **Nie zwei Ticket-Files für eine Einheit.** GitHub-Weg: ein Issue lebt in einem
  Repo, auch wenn der Fix mehrere Repos über verlinkte PRs berührt.

**Tie-Breaker** für den unklaren Fall:
1. Wo landet das user-sichtbare Deliverable / die Akzeptanz? → das Repo ownt.
2. Spannt die Akzeptanz über Repos ohne primäres? → Root.
3. Unsicher? → das Repo, in dem gerade gearbeitet wird.

**Wann doch zwei Tickets?**
- **Kleine, inzidentelle** Cross-Repo-Änderung → im selben Ticket miterledigen +
  Hash notieren.
- **Substanzielle, eigenständige** Arbeit im anderen Repo → **eigenes** Ticket in
  *dessen* Board, per `GH-Issue:`/Ticket-ID verlinkt (analog „ein Issue vs.
  gesplittete Issues + linked PRs").

### 7.2 Der Design-Kurier ist ein Board im Kurier-Modus

Der Frontend-Design-Austausch ist kein Sonderfall, sondern **ein Sub-Projekt-Board,
das zusätzlich im Kurier-Modus läuft** (STATUS.md INBOX/OUTBOX, Roundtrips). Es
bleibt aus zwei Gründen in `apps/frontend/_tickets/`:

- **Boundary / Least-Privilege:** Claude Design hat **read-only**-Zugriff auf
  `apps/frontend/` und liefert Tickets/VERIFY/STATUS per **ZIP** (keine Schreib-
  Oberfläche im Repo). Es **liest** den aktuellen Stand aus seinem Frontend-Scope,
  um den nächsten Roundtrip anzuhängen (Delta-Regel). Zöge man diese Files ins Root,
  bräche der Lesepfad oder Designs Scope müsste auf Root ausgeweitet werden
  (über-privilegiert: Backend-Auth, Infra, `.env`).
- **Ownership:** die UI-Tickets sind frontend-owned → nach §7.1 ohnehin frontend-lokal.

Kein Zugriff wird angefasst; die Boundary bleibt intakt ohne Kompromiss.

**Der Hub drainiert (wie `QUESTIONS.md`, §4.3):** STATUS.md ist eine **Live-Tafel,
kein Log**. INBOX/OUTBOX halten nur den **aktuellen, unverarbeiteten** Austausch;
verarbeitete Blöcke werden **entfernt** (git ist der Trail). `ACTIVE QUEUE` und
`ARCHIVE` entfallen — die offene Queue sind die Ticket-Files im Board-Root, die
Historie liegt in `solved/` + git; durable Entscheidungen leben kuratiert im
Kontext-Block. So bleibt der Hub konstant klein, statt pro Roundtrip zu wachsen.

### 7.3 Preis: fragmentierter Überblick (YAGNI-Mitigation)

Mehrere Boards (Root + Sub-Repos) heißt „was läuft überall?" an mehreren Orten. Für
Solo+KI meist unkritisch (man weiß, in welchem Repo man ist). Ein Root-Aggregator,
der über Boards hinweg listet, ist **YAGNI** — erst bauen, wenn es real wehtut.

### 7.4 Single-Repo-Fall

In einem Single-Repo-Projekt liegt `_tickets/` einfach im Repo-Root — dasselbe
Muster, ein Level.

---

## 8. Skill-Paket-Inhalt

```
~/.claude/skills/task-verification-workflow/
├── SKILL.md                     # Prinzip (§2) + Formate (§4/5) + GH-Grenze (§6)
│                                #   + Ort-folgt-Scope (§7) + Verweise auf superpowers
└── templates/
    ├── ticket.md                # Ticket-Template (§4.1) mit eingebetteter Verify-Matrix
    └── QUESTIONS.md             # Kopf + Drain-Regel-Erinnerung
```

**Erster Wurf = SKILL.md + Templates.** `scripts/gen-index.sh` (aus den offenen
Root-Ticket-Files ein `INDEX.md` generieren; ANSI, `--help`, BashLib-Konvention)
wird **nachgezogen**, nicht im ersten Build. Bis dahin ist der Ein-Blick-Überblick
das Root-Listing der offenen Ticket-Files selbst (§5); ein `INDEX.md` ist optional
und darf zwischenzeitlich manuell sein.

- **SKILL.md `description`** (Deutsch, final — auf Triggering getunt, um den
  *Workflow-/Verifikations-Akt* formuliert, nicht um „Code schreiben"; grenzt so
  gegen `code-standards` ab):

  > Arbeitsprinzip, um Arbeit in kleine, verifizierbare Happen zu zerlegen:
  > einzweckige, time-boxte Tickets mit eingebetteter Verify-Matrix (zweistufig —
  > KI-Vorabcheck mit Ehrlichkeits-Legende ✅/⚠️/◑/➖ + getrennte, nie
  > überschriebene Mensch-Spalte); Fragen beim Testen festhalten und nach GitHub
  > drainieren. Verwenden beim Zerlegen einer Aufgabe in Tickets/Arbeitspakete,
  > beim Anlegen oder Pflegen eines `_tickets/`-Boards (offene Tickets im Root,
  > erledigte in `solved/`), beim
  > schrittweisen Abarbeiten eines Features/Bugfixes mit Mensch/KI-Verifikations-
  > Handoff, oder beim Sammeln von Fragen/Findings während des Testens. Tickets
  > ergänzen GitHub-Issues, ersetzen sie nie.

- Sprache: Deutsch (konform zu Mikes bestehenden Skills; Code-Kommentare EN ok).

---

## 9. Migration (später, separat — Skill zuerst)

1. **Skill bauen** (dieser Spec → Plan → Skill). Ortsagnostisch, kein Repo-Eingriff.
2. **Danach** Migration als eigener Schritt:
   - Bestehende Frontend-Struktur umstellen: offene Tickets im `_tickets/`-Root,
     erledigte nach `solved/`, Verify-im-Ticket. Design-Kurier (STATUS.md +
     UI-Tickets + VERIFY) **bleibt** in `apps/frontend/_tickets/` (§7.2).
   - Root `_tickets/`-Board **bei Bedarf** anlegen — nur für echt übergreifende
     Arbeit (§7.1). Sub-Repo-owned Arbeit lebt im Board des jeweiligen Repos
     (`apps/backend/_tickets/` etc.), sobald dort eines gebraucht wird.
   - Board-Anlage ist optional/inkrementell — kein Big-Bang über alle Repos.

3. **Claude Design über die neue Struktur informieren (Kurier-Modus).** Weil Design
   die Frontend-Tickets/VERIFY *autort*, wird das neue Format erst wirksam, wenn
   Design es liefert. Die Umstellung ist erst abgeschlossen, wenn:
   - **`STATUS.md`-Context-Block + `_tickets/README.md`** die neue Struktur
     beschreiben (Designs Wissensquellen): neue Ticket-Variante (feste Reihenfolge
     **Header → Verify-Matrix → Details** in *einem* File, §4.1), Layout (offene
     Tickets im Root, erledigte in `solved/`, §5), **`VERIFY.md` aufgelöst** in die
     Verify-Matrix je Ticket (kein separates VERIFY.md mehr).
   - Ein **INBOX-Eintrag** (CC → Design) die Änderung explizit ankündigt und ein
     **Referenz-Ticket im neuen Format** als Muster mitliefert (im ZIP-Roundtrip),
     damit die nächste Design-Lieferung konform ist.
   - Der **erste Roundtrip nach der Umstellung** gegen das neue Format geprüft und
     jede Abweichung in der INBOX zurückgemeldet wird.

   > Diese Info-Pflicht gilt generell: ändert sich die Ticket-/Board-Struktur, muss
   > jede *autorende* zweite Partei (Mensch oder KI) über die Kanäle informiert
   > werden, die sie liest (Context-Block, README, INBOX) — nicht nur die Files
   > umbauen.

---

## 10. Out of Scope / YAGNI

- Kein Auto-Sync zwischen QUESTIONS und GH (manuelle Promotion reicht).
- Kein `solved/`-Unterordner-Schema, bis `solved/` real unübersichtlich wird.
- Kein Tooling, das STATUS.md/Kurier automatisiert — bleibt projektlokal.
- Kein Ersatz für `verification-before-completion`/`executing-plans` — Verweis.

---

## 11. Offene Mikro-Punkte (für Plan/Review)

- ~~Ticket-Header als YAML-frontmatter vs. Markdown-Tabelle~~ → **entschieden:
  reines Markdown** (H1 + einzeilige Metadaten-Tabelle + „Löst:"-Zeile, §4.1).
- ~~Ob `gen-index.sh` Teil des ersten Wurfs ist~~ → **entschieden: nachgezogen**
  (§8), nicht im ersten Build.
- ~~Genauer Wortlaut der SKILL.md-`description`~~ → **entschieden: Deutsch,
  finale Fassung in §8**.

_Alle Mikro-Punkte entschieden — Spec ist implementierungsreif._
