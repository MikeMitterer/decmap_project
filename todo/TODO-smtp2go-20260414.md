# TODO: SMTP2GO als Mail-Relay einrichten

**Erstellt:** 2026-04-14  
**GitHub Issue:** MikeMitterer/decmap_project#1  
**Priorität:** hoch — Blocker (User-Registrierung funktioniert ohne SMTP nicht)

## Kontext

Mailjet funktioniert nicht zuverlässig, Support schlecht.
smtp2go als Ersatz evaluiert — Port 2525 verfügbar (Hetzner blockiert 587).

## Aufgaben

- [ ] Account bei smtp2go anlegen (Free Tier: 1.000 Mails/Monat)
- [ ] Sender-Domain `decisionmap.ai` verifizieren (SPF + DKIM in DNS eintragen)
- [ ] Directus `.env` auf Hetzner aktualisieren:
  ```env
  EMAIL_SMTP_HOST=mail.smtp2go.com
  EMAIL_SMTP_PORT=2525
  EMAIL_SMTP_USER=<smtp2go-username>
  EMAIL_SMTP_PASSWORD=<api-key>
  EMAIL_SMTP_SECURE=false
  EMAIL_FROM=noreply@decisionmap.ai
  ```
- [ ] `.env.example` in `apps/backend/` aktualisieren
- [ ] Test: Registrierungs-Mail + Password-Reset-Mail auf Produktion

## Hinweise

- Port 2525 bevorzugen (Hetzner blockiert 587, 465 hatte Probleme mit Mailjet)
- `EMAIL_SMTP_HOST=` leer lassen bis konfiguriert — sonst blockiert Directus-Start 60s
