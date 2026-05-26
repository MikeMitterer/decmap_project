# Moderation Criteria — KI-Spam-Filter

> SSoT für alle Verifikationskriterien des `SpamFilterService`.
> Der LLM-Prompt in `openai_provider.py` / `anthropic_provider.py` leitet sich direkt aus diesem Dokument ab.

## Ablehnen (`is_spam: true`)

| Kriterium | Beispiele |
|---|---|
| Sinnloser Text / Test-Eingaben | „asdf", „test test test", Zufallszeichen, leere Inhalte |
| Werbung / Marketing / Produktanpreisungen | „Kaufen Sie jetzt unser KI-Tool!", Affiliate-Links |
| Persönliche Daten | Namen, Adressen, Telefonnummern, E-Mail-Adressen |
| Kein Bezug zu KI/Technologie im geschäftlichen Kontext | Politische Meinungen, Weltanschauung, Private Themen |
| Eindeutig bot-generierter Content | Copy-Paste-Flut, Template-Fülltext, Lorem Ipsum |

## Zur manuellen Prüfung (`is_spam: false`, Status → `needs_review`)

Die Eskalation nach `needs_review` wird **nicht** vom LLM gesteuert — sie erfolgt auf Ebene
der Verhaltens-Signale in `BotDetectionMiddleware` (1 Signal → `needs_review`).
Der LLM liefert nur `is_spam: true/false`.

Grenzfälle, bei denen `is_spam: false` erwartet wird, aber manuell geprüft werden sollte:

- Sehr kurze Texte (< 20 Wörter) ohne klaren KI-Bezug
- Ungewöhnliche Sprache / schlechte Grammatik aber inhaltlich plausibel
- Thematisch grenzwertig: Technologie-bezogen, aber kein konkretes KI-Problem

## Akzeptieren (`is_spam: false`, Status → `pending` → Admin-Freigabe)

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

## Zusammenhang mit `rejection_reason`

Wenn `is_spam: true`, muss `reason` einen konkreten, menschenlesbaren Ablehnungsgrund
auf Englisch enthalten (max. 100 Zeichen). Dieser wird als `rejection_reason` in der DB gespeichert
und ist für Moderatoren in der Admin-Queue sichtbar (Issue #19).

Wenn `is_spam: false`, ist `reason` ein leerer String.

## LLM-Prompt (SSoT-Ableitung)

Der aktuelle `_SPAM_SYSTEM`-Prompt in beiden Providern ist eine direkte Ableitung dieser Kriterien.
Änderungen hier → Prompt in `openai_provider.py` und `anthropic_provider.py` synchron anpassen.
