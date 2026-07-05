# UI Test-Daten — Problems & Solution Approaches

Testszenarien für manuelles UI-Testing und curl-basiertes Seeding.

> **Dev-Endpunkte:** Backend `http://localhost:8001` | nginx-Proxy `https://int.decisionmap.ai`  
> **Auth:** Login als Admin/Superuser vor curl-Calls — JWT-Token aus Cookie/Login-Response verwenden.
> **UI-/Form-Pendant:** Copy-paste-fertige Einträge zum direkten Testen des „+ Add problem"-Flows
> (Form, Similarity-Check, EN-Translation, Moderation, Locale-Guard) liegen in
> `apps/frontend/tickets/SAMPLE-PROBLEMS.md` — dieses Dokument hier ist die curl-/Seeding-Variante.

---

## Inhalt

- [Legitime Probleme](#legitime-probleme)
- [Lösungsansätze](#lösungsansätze)
- [Spam-Probleme](#spam-probleme)
- [Demo-Autoren (Autor-/Firmen-Chip)](#demo-autoren-autor-firmen-chip)
- [curl-Referenz](#curl-referenz)

---

## Legitime Probleme

### P1 — Fehlender KI-Governance-Rahmen

**Titel:** Fehlender KI-Governance-Rahmen im Unternehmen

**Beschreibung:**
Unsere Geschäftsführung hat keine klaren Richtlinien für den Einsatz von KI-Tools festgelegt.
Mitarbeiter nutzen eigenständig verschiedene Dienste (ChatGPT, Copilot, Midjourney) ohne
einheitliche Standards. Es ist unklar, welche Daten in externe Systeme übertragen werden dürfen
und wer bei Datenschutzverstößen haftet. Ein unternehmensweites Regelwerk fehlt vollständig.

**Tags (L10):** governance, compliance, policy  
**Region:** DACH

---

### P2 — Unkontrollierter KI-Einsatz durch Mitarbeiter (Shadow AI)

**Titel:** Shadow AI: Mitarbeiter nutzen KI-Tools ohne IT-Wissen

**Beschreibung:**
Mindestens 30 % unserer Mitarbeiter verwenden KI-Tools eigenständig für ihre Arbeit,
ohne dass IT oder Management davon weiß. In Umfragen gaben Mitarbeiter an, vertrauliche
Kundendaten und interne Dokumente in öffentliche KI-Systeme einzugeben. Wir haben aktuell
keinen Überblick, welche Tools genutzt werden und welche Daten dabei abfließen könnten.

**Tags (L10):** shadow-it, security, data-privacy  
**Region:** DACH

---

### P3 — KI-Halluzinationen in Kundenberichten

**Titel:** KI-generierte Berichte enthalten faktisch falsche Informationen

**Beschreibung:**
Unser Vertriebsteam erstellt Kundenberichte zunehmend mit KI-Unterstützung.
In drei Fällen innerhalb von zwei Monaten enthielten die finalen Dokumente sachlich falsche
Angaben — darunter erfundene Produktspezifikationen und falsche Gesetzesreferenzen —
die erst nach Versendung an Kunden auffielen. Wir haben aktuell keinen systematischen
Prüfprozess für KI-generierte Inhalte.

**Tags (L10):** hallucinations, quality-assurance, risk  
**Region:** DACH

---

### P4 — Fehlende KI-Kompetenz im Team

**Titel:** KI-Einsatz scheitert an fehlendem Know-how der Mitarbeiter

**Beschreibung:**
Wir haben Lizenzen für mehrere KI-Tools erworben, die Nutzungsrate liegt jedoch unter 15 %.
Mitarbeiter geben an, nicht zu wissen, wie sie die Tools effektiv einsetzen sollen.
Es gibt keine internen Schulungen, keinen definierten KI-Verantwortlichen und keine
Best-Practice-Sammlung. Die Investition droht wirkungslos zu bleiben.

**Tags (L10):** training, adoption, change-management  
**Region:** DACH

---

### P5 — Fehlende Methodik zur KI-ROI-Messung

**Titel:** Wir können den ROI unserer KI-Investitionen nicht messen

**Beschreibung:**
Unser Unternehmen hat in den letzten 12 Monaten über 50.000 € in KI-Tools und -Projekte
investiert. Eine belastbare Methode, um den Return on Investment zu messen, fehlt.
Die Geschäftsführung fordert Nachweise über Effizienzgewinne, wir können aber keine
konkreten Zahlen liefern. KI-Projekte laufen Gefahr, nicht verlängert oder gestrichen
zu werden — unabhängig von ihrem tatsächlichen Nutzen.

**Tags (L10):** roi, metrics, business-value  
**Region:** DACH

---

## Lösungsansätze

### L1 → P1 (Governance)

**Titel:** AI Policy Framework schrittweise einführen

**Inhalt:**
Einen KI-Beauftragten benennen (bestehende Rolle erweitern, kein Neueinstellung nötig)
und einen initialen Katalog erlaubter KI-Tools erstellen. Jedes Tool wird einer von drei
Risikoklassen zugeordnet: intern-only, mit Datenanonymisierung nutzbar, vollständig
gesperrt. ISO 42001 als Orientierungsrahmen verwenden — nicht zertifizierungspflichtig,
aber strukturgebend. Quartalsreviews mit je einem Vertreter aus IT, Legal und einer Fachabteilung.
Umsetzbar in 4–6 Wochen ohne externes Budget.

---

### L2 → P1 (Governance)

**Titel:** KI-Governance-Ausschuss mit klaren Entscheidungswegen

**Inhalt:**
Einen bereichsübergreifenden AI Governance Council einrichten: CTO/IT-Leitung,
Datenschutzbeauftragter, HR und ein rotierender Fachbereichsvertreter.
Monatliche Meetings, Entscheidungen per Mehrheit, Eskalationspfad zur Geschäftsführung.
Erster Output: ein zweiseitiges „Acceptable Use Policy"-Dokument, das alle Mitarbeiter
digital unterschreiben. Toolstack: bestehendes Intranet + einfaches Ticketsystem für
Tool-Freigabeanträge.

---

### L3 → P2 (Shadow AI)

**Titel:** Zentrales KI-Tool-Portfolio als Shadow-AI-Gegenmittel

**Inhalt:**
Die IT stellt ein kuratiertes Portfolio genehmigter KI-Tools bereit — auf einer internen
Tool-Seite sichtbar für alle. Nicht-genehmigte Tools werden via IT-Policy für
Unternehmensgeräte eingeschränkt (kein vollständiges Blocking nötig, aber klare Richtlinie).
Parallel: eine 30-minütige Awareness-Session pro Abteilung, die konkret erklärt,
welche Daten nie in externe KI-Systeme eingegeben werden dürfen (Kundendaten, NDA-Inhalte,
Finanzdaten). Erfahrungsgemäß reicht Aufklärung + einfache Alternativen, um 80 % der
Schatten-Nutzung zu reduzieren.

---

### L4 → P3 (Halluzinationen)

**Titel:** Vier-Augen-Pflicht für KI-generierte Kundendokumente

**Inhalt:**
Alle KI-generierten Dokumente, die an externe Empfänger gehen, erhalten einen
Pflicht-Review-Schritt im Workflow: ein zweiter Mitarbeiter zeichnet ab, dass
Faktenangaben, Zahlen und Gesetzesreferenzen manuell geprüft wurden.
Umsetzung: einfacher Stempel/Checkbox im bestehenden Dokumentenmanagement-System.
Ergänzend: eine interne Checkliste „Was KI-Tools nicht verlässlich können"
(aktuelle Gesetzeslagen, Produktspezifikationen, Finanzkennzahlen) — sichtbar
im Team-Wiki und als Kurzversion am Bildschirm.

---

### L5 → P4 (Kompetenz)

**Titel:** KI-Champions-Programm statt flächendeckender Schulung

**Inhalt:**
Statt alle Mitarbeiter gleichzeitig zu schulen: pro Abteilung einen freiwilligen
KI-Champion identifizieren (intrinsisch motiviert, bereits experimentierfreudig).
Diese Personen erhalten 2–3 Tage dedizierte Einarbeitung + Zugang zu Premium-Tool-Lizenzen.
Sie werden zur ersten Anlaufstelle in ihrer Abteilung und geben Wissen informell weiter.
Monatliches Champions-Meeting tauscht Learnings aus und sammelt Tool-Feedback für IT.
Kosten: minimal. Wirkung: nachweislich höhere Adoptionsrate als Top-Down-Pflichtschulungen.

---

## Spam-Probleme

> Diese Einreichungen sollen vom LLM-Spam-Filter **abgelehnt** oder zumindest als
> `needs_review` markiert werden.

---

### SPAM-1 — Vage / inhaltsleere Einreichung

**Titel:** KI macht Probleme

**Beschreibung:**
Wir haben Probleme mit KI. Es funktioniert nicht so wie wir das wollen.
Bitte helfen. Danke.

**Erwartetes Ergebnis:** `rejected` — kein spezifisches Problem beschrieben,
keine Unternehmenskontext, kein Handlungsansatz möglich.

---

### SPAM-2 — Werbliche Einreichung / Eigenwerbung

**Titel:** Unsere KI-Lösung löst alle Ihre Probleme!

**Beschreibung:**
Sind Sie auf der Suche nach einer leistungsstarken KI-Plattform für Ihr Unternehmen?
Unser Produkt KI-Master Pro 3000 ist die Antwort! Besuchen Sie jetzt ki-master-pro.de
und vereinbaren Sie eine kostenlose Demo. Wir bieten die beste KI-Software auf dem Markt —
von Experten entwickelt, von Tausenden Unternehmen genutzt. Kontaktieren Sie uns heute!

**Erwartetes Ergebnis:** `rejected` — werblicher Inhalt, kein echtes Problem,
externe URL, Eigenwerbung.

---

## Demo-Autoren (Autor-/Firmen-Chip)

Seed `database/seeds/demo/005_demo_authors.sql` (via `make db-seed-demo`) legt zwei einloggbare
Demo-User mit Firma an und hängt sie als Autoren an bestehende approved Probleme — macht das
violette Firmen-Chip im Problem-Detail-Panel und den server-seitigen `?company=`-Filter testbar.
Der UPDATE ist idempotent und greift auch auf bereits eingespielten Daten.

| Login | Passwort | Firma | Probleme |
|---|---|---|---|
| `demo.acme@int.decisionmap.ai` | `DemoPass123!` | Acme Manufacturing GmbH | 4 |
| `demo.nordbank@int.decisionmap.ai` | `DemoPass123!` | NordBank AG | 2 |

> **Passwort:** `DemoPass123!` erfüllt die Login-Form-Regeln (`pages/login.vue`: ≥8 Zeichen,
> Groß-/Kleinbuchstabe, Ziffer **und** Sonderzeichen) — `demopass123` schlägt den Client-Login fehl.

**Test:** Ein **beliebiges** Problem mit Firma öffnen → violettes Firmen-Chip (🏢) erscheint (bei
nicht-anonymen Autoren zusätzlich das grüne Autor-Chip 👤, z.B. „Demo Acme"; je mit Filter-Tooltip/`aria-label`, #30) → Firma anklicken
filtert die Table server-seitig auf diese Company.
Der Chip emittiert den exakten Voll-Namen; derselbe Filter ist auch via `?company=`-URL setzbar.

> **Firmen-Chip jetzt auf jedem Problem (`9b8f357`, #30):** Das Firmen-Chip liest die Firma direkt aus
> `problem.company` (vom Backend auf **jedem** `ProblemRead` geliefert) und zeigt sich daher bei **jedem**
> Problem mit gesetzter Firma — nicht mehr nur bei eigenen. Zuvor hing der **ganze** Autor-/Firmen-Block am
> clientseitigen `userCache` (`v-if="author"`); für normale Betrachter war `author` `null`, also blieb das Chip
> unsichtbar. Fix: Wrapper-Bedingung auf `author || problem.company` erweitert, das 🏢-Chip auf `problem.company`
> gated. Das 👤-Autor-Chip wurde in `70f8a84` (#30) nach derselben Logik nachgezogen: `author_display_name`
> reist jetzt auf **jedem** `ProblemRead` mit (gebatcht via `_load_authors`, das `company` + `display_name` in
> einer Query holt), das Chip rendert aus `problem.authorDisplayName` (Cache-Fallback nur für den eigenen User)
> und erscheint daher bei **jedem** nicht-anonymen Problem, nicht mehr nur bei eigenen.
> Die sortierbare **Firmen-Spalte** der Table nutzt dieselbe `ProblemRead.company`-Quelle
> und rendert sie als kompakten farbigen **Monogramm-Badge** (1–2 Initialen, Vollname per Hover-Tooltip);
> `sort=company` + Klick auf den Badge (= Firmen-Filter) sind ebenfalls testbar.
> **Kompakt-Modus (`27fa7a9`):** Eine Zeile anklicken (Detail-Panel öffnet, Tabelle ~70 % Breite) → die Spalten
> **Cluster** und **Eingereicht** verschwinden, damit die Title-Spalte den Platz behält; Panel schließen → alle Spalten zurück.

> **Live-Verify F1 (2026-06-27, #29):** der `company`-Filter ist ein Ganzwert-ILIKE **ohne** Wildcards —
> der **vollständige, exakte** Firmenname (`Acme Manufacturing GmbH`, nicht `Acme`) ist nötig, sonst 0 Treffer.
> Das in `fc68cf6` erprobte Freitext-Eingabefeld über der Tabelle wurde deshalb in `ebb759f` wieder **entfernt** —
> Firmen-Filtern läuft über Panel-Chip + `?company=`-URL + aktive Tabellen-Chips.

---

## curl-Referenz

### Login (JWT-Token holen)

```bash
TOKEN=$(curl -s -X POST http://localhost:8001/auth/jwt/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin@decisionmap.local&password=<passwort>" \
  | jq -r '.access_token')
```

---

### Problem einreichen (Backend-API)

```bash
curl -s -X POST http://localhost:8001/problems \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "title": "Fehlender KI-Governance-Rahmen im Unternehmen",
    "description": "Unsere Geschäftsführung hat keine klaren Richtlinien für den Einsatz von KI-Tools festgelegt. Mitarbeiter nutzen eigenständig verschiedene Dienste ohne einheitliche Standards.",
    "title_en": "Missing AI Governance Framework",
    "description_en": "Our management has not established clear guidelines for AI tool usage. Employees independently use various services without unified standards, creating data privacy and security risks.",
    "signals": [],
    "honeypot": null
  }' | jq
```

---

### AI-Service Hook: Problem-submitted manuell testen

```bash
# Legitimes Problem
curl -s http://localhost:8000/hooks/problem-submitted \
  -H "Content-Type: application/json" \
  -d '{
    "problem_id": "<uuid-aus-problem-create>",
    "title": "Missing AI Governance Framework",
    "description": "Our management has not established clear guidelines for AI tool usage.",
    "ip_hash": "test-hash-001",
    "signals": [],
    "honeypot": null,
    "submitted_at": "2026-06-02T10:00:00Z"
  }' | jq

# Spam-Problem 1 (inhaltslos)
curl -s http://localhost:8000/hooks/problem-submitted \
  -H "Content-Type: application/json" \
  -d '{
    "problem_id": "spam-test-001",
    "title": "KI macht Probleme",
    "description": "Wir haben Probleme mit KI. Es funktioniert nicht so wie wir das wollen. Bitte helfen. Danke.",
    "ip_hash": "test-hash-spam-001",
    "signals": [],
    "honeypot": null,
    "submitted_at": "2026-06-02T10:01:00Z"
  }' | jq

# Spam-Problem 2 (werblich)
curl -s http://localhost:8000/hooks/problem-submitted \
  -H "Content-Type: application/json" \
  -d '{
    "problem_id": "spam-test-002",
    "title": "Unsere KI-Lösung löst alle Ihre Probleme!",
    "description": "Sind Sie auf der Suche nach einer leistungsstarken KI-Plattform? Unser Produkt KI-Master Pro 3000 ist die Antwort! Besuchen Sie jetzt ki-master-pro.de!",
    "ip_hash": "test-hash-spam-002",
    "signals": [],
    "honeypot": null,
    "submitted_at": "2026-06-02T10:02:00Z"
  }' | jq
```

---

### AI-Service Hook: Solution-submitted testen

```bash
# Legitime Lösung
curl -s http://localhost:8000/hooks/solution-submitted \
  -H "Content-Type: application/json" \
  -d '{
    "solution_id": "<uuid-aus-solution-create>",
    "problem_id": "<problem-uuid>",
    "content": "Einen KI-Beauftragten benennen und einen initialen Katalog erlaubter KI-Tools erstellen. ISO 42001 als Orientierungsrahmen verwenden. Quartalsreviews mit IT, Legal und Fachabteilungen.",
    "submitted_at": null
  }' | jq

# Spam-Lösung (zu kurz / inhaltslos)
curl -s http://localhost:8000/hooks/solution-submitted \
  -H "Content-Type: application/json" \
  -d '{
    "solution_id": "spam-sol-001",
    "problem_id": "<problem-uuid>",
    "content": "Ja, stimme zu. Sehe oben.",
    "submitted_at": null
  }' | jq
```