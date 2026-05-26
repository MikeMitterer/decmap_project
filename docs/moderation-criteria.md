# Moderation Criteria — KI-Spam-Filter

> SSoT für alle Verifikationskriterien des `SpamFilterService`.
> Die LLM-Prompts in `prompts.py` leiten sich direkt aus diesem Dokument ab.
> Änderungen hier → Prompts in `prompts.py` synchron anpassen.

---

## Problems (Problemeingaben)

Prompt: `SPAM_SYSTEM` in `app/providers/llm/prompts.py`

### Ablehnen (`is_spam: true`)

| Kriterium | Beispiele |
|---|---|
| Sinnloser Text / Test-Eingaben | „asdf", „test test test", Zufallszeichen, leere Inhalte |
| Werbung / Marketing / Produktanpreisungen | „Kaufen Sie jetzt unser KI-Tool!", Affiliate-Links |
| Persönliche Daten | Namen, Adressen, Telefonnummern, E-Mail-Adressen |
| Kein Bezug zu KI/Technologie im geschäftlichen Kontext | Politische Meinungen, Weltanschauung, Private Themen |
| Eindeutig bot-generierter Content | Copy-Paste-Flut, Template-Fülltext, Lorem Ipsum |

### Zur manuellen Prüfung (`is_spam: false`, Status → `needs_review`)

Die Eskalation nach `needs_review` wird **nicht** vom LLM gesteuert — sie erfolgt auf Ebene
der Verhaltens-Signale in `BotDetectionMiddleware` (1 Signal → `needs_review`).
Der LLM liefert nur `is_spam: true/false`.

Grenzfälle, bei denen `is_spam: false` erwartet wird, aber manuell geprüft werden sollte:

- Sehr kurze Texte (< 20 Wörter) ohne klaren KI-Bezug
- Ungewöhnliche Sprache / schlechte Grammatik aber inhaltlich plausibel
- Thematisch grenzwertig: Technologie-bezogen, aber kein konkretes KI-Problem

### Akzeptieren (`is_spam: false`, Status → `pending` → Admin-Freigabe)

Zielgruppe: IT-Entscheider, CDOs, KI-Projektverantwortliche in KMU.

Akzeptiert wird alles, was ein echtes KI-bezogenes Geschäftsproblem einer Organisation beschreibt — insbesondere:

- **Datenstrategie:** Datenverfügbarkeit, -qualität, Daten-Governance
- **Modell-Deployment:** Integration in bestehende Systeme, Infrastruktur-Kosten
- **KI-Governance & Compliance:** EU AI Act, DSGVO-Konformität, Audit-Trails
- **Skill-Gap:** Fehlende KI-Kompetenz im Team, Weiterbildungsbedarf
- **Tool-Auswahl:** Build vs. Buy, Vendor-Lock-in, API-Kosten
- **ROI & Messbarkeit:** Erfolgsmetriken, Business Case für KI-Investitionen
- **Halluzinationen & Zuverlässigkeit:** Qualitätssicherung von LLM-Outputs in Produktion
- **Integrationsprobleme:** Legacy-Systeme, API-Anbindung, Daten-Pipelines

---

## Solution Approaches (Lösungsansätze)

Prompt: `SOLUTION_SPAM_SYSTEM` in `app/providers/llm/prompts.py`

Kein signals/honeypot-Layer — Lösungsansätze werden direkt per LLM evaluiert
(kein Browser-seitiges Bot-Detection, da der Einreichungsflow nach Login erfolgt).

### Ablehnen (`is_spam: true`)

| Kriterium | Beispiele |
|---|---|
| Inhaltsleerer Text / Platzhaltercontent | „I agree", „See above", „...", leere Sätze |
| Werbung für Produkte oder Dienstleistungen | „Nutzen Sie Tool XY — jetzt 20% Rabatt" |
| Kein Bezug zum verlinkten Problem | Vollständig anderes Thema, Off-Topic |
| Meinungsäußerung ohne Handlungsansatz | „KI ist gefährlich", „Das wird nie funktionieren" |
| Eindeutiges Duplikat der KI-generierten Lösung | Wortgleiche oder nahezu identische Übernahme |

### Grenzfälle (`is_spam: false`, Status → `pending`)

Der LLM-Check für Lösungsansätze liefert nur `is_spam: true/false` — keine `needs_review`-Stufe.
Grenzfälle landen als `pending` in der Admin-Queue:

- Sehr kurze Antworten (< 30 Wörter) mit potenziell sinnvollem Kern
- Grenzfall zwischen persönlicher Meinung und konkretem Lösungsvorschlag
- Lösung thematisch passend aber ohne nachvollziehbaren Handlungsschritt

### Akzeptieren (`is_spam: false`, Status → `pending` → Admin-Freigabe)

Zielgruppe: IT-Entscheider, CDOs, KI-Projektverantwortliche in KMU.

Akzeptiert wird, was einen konkreten, umsetzbaren Lösungsansatz für das verlinkte Problem beschreibt:

- Mindestens ein nachvollziehbarer Handlungsschritt oder eine klare Empfehlung
- Bezug zum KI-Kontext des verlinkten Problems erkennbar
- Zielgruppe KMU: pragmatisch, nicht rein akademisch

Beispiele akzeptabler Lösungsansätze:

- **Prozess-Ansatz:** „Einführung eines internen AI Review Boards mit monatlichem Audit"
- **Tool-Empfehlung mit Begründung:** „Wir nutzen Azure ML Pipelines — skaliert gut mit bestehendem Azure-Stack"
- **Framework-Vorschlag:** „EU AI Act Readiness Assessment als ersten Schritt, dann schrittweise Implementierung"

---

## Gemeinsame Regeln

### `rejection_reason`

Wenn `is_spam: true`, muss `reason` einen konkreten, menschenlesbaren Ablehnungsgrund
auf Englisch enthalten (max. 100 Zeichen). Dieser wird als `rejection_reason` in der DB gespeichert
und ist für Moderatoren in der Admin-Queue sichtbar.

Wenn `is_spam: false`, ist `reason` ein leerer String.

### Prompt-Synchronisierung

Änderungen an den Kriterien in diesem Dokument müssen synchron in `prompts.py` nachgezogen werden:

| Inhaltstyp | Prompt-Konstante |
|---|---|
| Probleme | `SPAM_SYSTEM` |
| Lösungsansätze | `SOLUTION_SPAM_SYSTEM` |
