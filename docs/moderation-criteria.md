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
des `signals`-Arrays im ai-service `SpamFilterService` (genau 1 Signal → `needs_review`,
≥2 Signale → `rejected`, 0 → LLM). Der LLM liefert nur `is_spam: true/false`. Hinweis: Eine
`BotDetectionMiddleware`, die behavioral-timing-Signale berechnet, ist derzeit **nicht**
implementiert (die `BOT_*`-Schwellenwerte wurden 2026-07-08 als toter Config entfernt) —
faktisch fließt nur `duplicate_confirmed` durch das Array.

Ein **LLM-/Provider-Fehler** während der Moderation (RateLimit, Quota-Erschöpfung, API-Ausfall)
eskaliert ebenfalls fail-safe nach `needs_review` (`moderation_error`) — **nicht** `rejected`
(seit 2026-07-25, symmetrisch zu Lösungen; s. `moderation_error` unter *Gemeinsame Regeln*).

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

**Die KI ist das Moderations-Gate** (keine menschliche Freigabe für saubere Lösungen):

| LLM-Verdikt | Status | `rejection_reason` |
|---|---|---|
| `is_spam: false` (sauber) **und** kein Duplikat | `approved` (auto, sofort sichtbar) | — |
| `is_spam: true` (bemängelt) | `needs_review` (Admin-Queue) | LLM-Grund (z. B. `promotional_content`) |
| Globales Duplikat (pgvector) ohne `duplicate_confirmed` | `needs_review` | `possible_duplicate` |
| LLM-Fehler (Provider down) | `needs_review` | `moderation_error` |

Nichts wird **automatisch hart abgelehnt** — bemängelte Lösungen landen mit Begründung in der
Admin-Queue, der Admin entscheidet final. Pipeline: `solution-submitted`-Hook → LLM-Spam-Filter →
(falls sauber) globaler Duplicate-Check über alle approved Solutions → Approval + Embedding speichern.

### Bemängeln (`is_spam: true` → `needs_review`)

| Kriterium | Beispiele |
|---|---|
| Inhaltsleerer Text / Platzhaltercontent | „I agree", „See above", „...", leere Sätze |
| Werbung für Produkte oder Dienstleistungen | „Nutzen Sie Tool XY — jetzt 20% Rabatt" |
| Kein Bezug zum verlinkten Problem | Vollständig anderes Thema, Off-Topic |
| Meinungsäußerung ohne Handlungsansatz | „KI ist gefährlich", „Das wird nie funktionieren" |

### Akzeptieren (`is_spam: false`, kein Duplikat → Status `approved`)

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

Wenn `is_spam: false`, ist `reason` leer — außer ein System-Wert (z. B. `possible_duplicate`) greift.

**System-generierte Werte (nicht vom LLM):**

| Wert | Quelle | Bedeutung |
|---|---|---|
| `possible_duplicate` (Problem) | Backend Duplicate-Detection | User hat trotz Duplikat-Warnung eingereicht (`signals: ['duplicate_confirmed']`). Status → `needs_review`. Admin-Queue zeigt amber Systemhinweis (`admin.systemNote` i18n-Key). |
| `possible_duplicate` (Solution) | AI-Service globaler pgvector-Check im `solution-submitted`-Hook | Spam-saubere Lösung gleicht einer bestehenden approved Solution (Score > `duplicate_threshold`) **ohne** `duplicate_confirmed`-Signal → Status `needs_review`. Mit `duplicate_confirmed` (authentifizierter User bestätigt „ist anders") → `approved`. |
| `moderation_error` (Problem + Solution) | LLM-Provider-Fehler im Spam-Filter (`is_spam` wirft: RateLimit/Quota/API-Ausfall) | Spam-Check konnte nicht laufen → fail-safe `needs_review` statt Auto-Approve/Reject. Gilt seit 2026-07-25 **symmetrisch für Probleme** (`SpamFilterService`, vorher fälschlich `rejected` — eine Provider-Quota-Störung lehnte still jedes eingehende Problem ab). Auto-Reject bleibt echten Spam-Verdikten, Honeypot und ≥2 Signalen vorbehalten. |

### Prompt-Synchronisierung

Änderungen an den Kriterien in diesem Dokument müssen synchron in `prompts.py` nachgezogen werden:

| Inhaltstyp | Prompt-Konstante |
|---|---|
| Probleme | `SPAM_SYSTEM` |
| Lösungsansätze | `SOLUTION_SPAM_SYSTEM` |
