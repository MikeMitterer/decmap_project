# AWS SES Setup — E-Mail-Versand für DecisionMap

Vollständige Anleitung: Domain-Verifizierung → SMTP-Credentials → Sandbox-Tests →
Production Access → Directus-Konfiguration → Systemtest.

---

## Übersicht

- [Phase 1 — AWS SES Grundsetup](#phase-1--aws-ses-grundsetup)
- [Phase 2 — Domain verifizieren](#phase-2--domain-verifizieren-decisionmapai)
- [Phase 2b — Custom MAIL FROM Domain](#phase-2b--custom-mail-from-domain)
- [Phase 3 — SPF + DMARC](#phase-3--spf--dmarc-dns-absicherung)
- [Phase 4 — Absender-Adresse verifizieren](#phase-4--absender-adresse-verifizieren)
- [Phase 5 — Sandbox: Zieladresse verifizieren + Tests](#phase-5--sandbox-zieladresse-verifizieren--tests)
- [Phase 6 — SMTP Credentials generieren](#phase-6--smtp-credentials-generieren)
- [Phase 7 — Test via Script](#phase-7--test-via-script-ohne-directus)
- [Phase 8 — Production Access beantragen](#phase-8--production-access-beantragen)
- [Phase 9 — Directus konfigurieren](#phase-9--directus-konfigurieren-hetzner-server)
- [Phase 10 — Gesamtsystem-Verifikation](#phase-10--gesamtsystem-verifikation)
- [Referenz](#referenz)

---

## Phase 1 — AWS SES Grundsetup

1. [AWS SES Console öffnen (eu-west-1 / Irland)](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1)
   - SES-Ressourcen sind region-spezifisch — Region einmal wählen und **nicht mehr wechseln**
   - Alle folgenden Links sind bereits auf **eu-west-1** voreingestellt
2. Beim ersten Aufruf: **Get started** — danach direkt über die Links in dieser Anleitung navigieren

[↑ Übersicht](#übersicht)

---

## Phase 2 — Domain verifizieren (decisionmap.ai)

### 2.1 Identity erstellen

1. [SES → Verified Identities → Create Identity](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities)
2. Identity type: **Domain**
3. Domain: `decisionmap.ai`
4. **Easy DKIM** aktivieren: RSA 2048 Bit
5. **Create Identity** klicken

SES zeigt jetzt drei CNAME-Records für DKIM.

### 2.2 DNS-Records bei Hetzner eintragen

> ⚠️ **Gotcha:** DNS-Verwaltung über **[dns.hetzner.com](https://dns.hetzner.com)** — nicht über Hetzner Robot.
> Robot zeigt keine DNS-Zone.

1. [dns.hetzner.com](https://dns.hetzner.com) öffnen → Zone `decisionmap.ai` → **Add record**

**DKIM (3× CNAME — Werte aus SES kopieren):**
```
<token1>._domainkey.decisionmap.ai  CNAME  <wert1>.dkim.amazonses.com.
<token2>._domainkey.decisionmap.ai  CNAME  <wert2>.dkim.amazonses.com.
<token3>._domainkey.decisionmap.ai  CNAME  <wert3>.dkim.amazonses.com.
```

> ⚠️ **Trailing Dot:** Der Value-Eintrag (Ziel des CNAME) muss zwingend mit einem **Punkt enden**
> (`amazonses.com.` — nicht `amazonses.com`). Ohne den abschließenden Punkt zeigt Hetzner
> eine Warnung und hängt die eigene Domain an — die DKIM-Records sind dann ungültig.

### 2.3 Verifizierung abwarten

- SES prüft DNS automatisch (alle paar Minuten)
- Status wechselt von `Pending` → `Verified`
- Kann bis zu **48 Stunden** dauern (meist < 30 Minuten)
- [SES Verified Identities](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities) → Status beobachten

[↑ Übersicht](#übersicht)

---

## Phase 2b — Custom MAIL FROM Domain

Standardmäßig verwendet SES `amazonses.com` im unsichtbaren `Return-Path`-Header (Bounce-Adresse).
Mit einer **Custom MAIL FROM Domain** kommt dieser Header von deiner eigenen Domain →
bessere DMARC-Konformität + Bounce-Handling direkt über AWS.

> AWS SES zeigt in der Console einen Hinweis auf fehlende DNS-Records — das ist dieser Schritt.

### 2b.1 Custom MAIL FROM in SES aktivieren

1. [SES → Verified Identities](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities) → `decisionmap.ai` auswählen
2. Reiter **Authentication** → Abschnitt **Benutzerdefinierte MAIL-From-Domain** → **Bearbeiten** (oben rechts im Abschnitt)
3. MAIL FROM domain anpassen: `mail.decisionmap.ai`

   > ⚠️ **AWS schlägt `no-reply.decisionmap.ai` als Standard vor — diesen Wert nicht einfach übernehmen.**
   > Besser eine sprechende Subdomain wie `mail.decisionmap.ai` wählen: klarer, kürzer, zukunftssicher.
   > Den Wert im Bearbeiten-Dialog vor dem Speichern anpassen.

4. **Save changes**

SES zeigt jetzt zwei DNS-Records die eingetragen werden müssen.

### 2b.2 DNS-Records bei Hetzner eintragen

[dns.hetzner.com](https://dns.hetzner.com) → Zone `decisionmap.ai` → **Add record**

**MX Record:**
```
Name:     mail
Priority: 10
Value:    feedback-smtp.eu-west-1.amazonses.com.
```

> Hetzner DNS hat für MX zwei separate Felder — **Priority:** `10`, **Mail server (Value):** `feedback-smtp.eu-west-1.amazonses.com.`

**SPF Record (TXT):**
```
Name:  mail
Value: "v=spf1 include:amazonses.com ~all"
```

> ⚠️ **Hetzner Name-Feld — nur Subdomain, nie FQDN:**
> Im Feld **Name/Host** nur `mail` eingeben — **nicht** `mail.decisionmap.ai`.
> Hetzner hängt die Zone (`.decisionmap.ai`) automatisch an. Wird `mail.decisionmap.ai`
> eingetragen, entsteht `mail.decisionmap.ai.decisionmap.ai` → Record ungültig, SES-Verifizierung schlägt fehl.
>
> ⚠️ **Trailing Dot — nur beim Value/Ziel-Wert:**
> Das Ziel des MX-Records muss mit Punkt enden (`amazonses.com.` — nicht `amazonses.com`).
> Fehlt der Punkt beim Value, hängt Hetzner die eigene Domain an → MX-Record ebenfalls ungültig.

### 2b.3 Verifizierung abwarten

- SES prüft die Records automatisch (alle paar Minuten)
- Status in [SES → Verified Identities → decisionmap.ai → Authentication](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities) beobachten
- `Custom MAIL FROM domain` wechselt von `Pending` → `Verified`

DNS-Propagation parallel prüfen — **nicht** `decisionmap.ai`, sondern die Subdomain:
[dnschecker.org — mail.decisionmap.ai ALL Records](https://dnschecker.org/all-dns-records-of-domain.php?query=mail.decisionmap.ai&rtype=ALL&dns=google)

[↑ Übersicht](#übersicht)

---

## Phase 3 — SPF + DMARC (DNS-Absicherung)

Ebenfalls in [dns.hetzner.com](https://dns.hetzner.com) → Zone `decisionmap.ai` eintragen:

**SPF (TXT Record):**
```
decisionmap.ai  TXT  "v=spf1 include:amazonses.com ~all"
```
> Falls bereits ein SPF-Record existiert: `include:amazonses.com` in den bestehenden einfügen — nicht duplizieren.

**DMARC (TXT Record):**
```
_dmarc.decisionmap.ai  TXT  "v=DMARC1; p=none; rua=mailto:dmarc@decisionmap.ai"
```
> `p=none` = nur Monitoring, keine Ablehnung. Nach stabilem Betrieb auf `p=quarantine` oder `p=reject` erhöhen.

[↑ Übersicht](#übersicht)

---

## Phase 4 — Absender-Adresse verifizieren

1. [SES → Verified Identities → Create Identity](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities)
2. Identity type: **Email address**
3. Adresse: `noreply@decisionmap.ai`
4. **Create Identity** klicken
5. AWS schickt eine Verification-Mail an `noreply@decisionmap.ai`
6. Diese Mail im Postfach öffnen → Verifikationslink klicken

> Die Domain `decisionmap.ai` muss in Phase 2 bereits `Verified` sein, damit die Mail zugestellt werden kann.

[↑ Übersicht](#übersicht)

---

## Phase 5 — Sandbox: Zieladresse verifizieren + Tests

Im Sandbox-Modus akzeptiert SES **nur verifizierte Zieladressen**. Für den ersten Test:

1. [SES → Verified Identities → Create Identity](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities)
2. Identity type: **Email address**
3. Eigene Test-Adresse eintragen (z.B. persönliche Gmail)
4. Verification-Mail bestätigen

### Testmail über SES Console senden

1. [SES → Verified Identities](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities) → `noreply@decisionmap.ai` auswählen
2. **Send test email** → an die verifizierte Test-Adresse schicken
3. Prüfen ob Mail ankommt + Absender korrekt ist

[↑ Übersicht](#übersicht)

---

## Phase 6 — SMTP Credentials generieren

> ⚠️ SES SMTP Credentials sind **keine normalen IAM Access Keys** — sie werden
> über einen eigenen Algorithmus abgeleitet.
> Niemals einen normalen IAM Access Key direkt als SMTP-Passwort verwenden.

1. [SES → Account dashboard → SMTP settings → Create SMTP credentials](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/smtp)
2. **Create SMTP credentials** klicken
3. IAM User Name: z.B. `decisionmap-ses-smtp` (wird automatisch in [IAM](https://console.aws.amazon.com/iam/home#/users) angelegt)
4. **Create** → SMTP Username + SMTP Password anzeigen
5. **Sofort speichern** — das Passwort wird nur einmal angezeigt

```
SMTP Host:     email-smtp.eu-west-1.amazonaws.com
SMTP Port:     587  (STARTTLS)
SMTP User:     <generierter Username>
SMTP Password: <generiertes Passwort>
```

[↑ Übersicht](#übersicht)

---

## Phase 7 — Test via Script (ohne Directus)

Verbindung und Versand direkt testen — kein Directus, kein Docker nötig.

### Python (ohne externe Dependencies)

```python
#!/usr/bin/env python3
import smtplib
import ssl
from email.mime.text import MIMEText

SMTP_HOST = "email-smtp.eu-west-1.amazonaws.com"
SMTP_PORT = 587
SMTP_USER = "DEIN_SMTP_USERNAME"
SMTP_PASS = "DEIN_SMTP_PASSWORT"
FROM_ADDR = "noreply@decisionmap.ai"
TO_ADDR   = "deine-verifizierte@testadresse.com"  # Sandbox: muss verifiziert sein

msg = MIMEText("SES Test erfolgreich.")
msg["Subject"] = "SES Verbindungstest"
msg["From"]    = FROM_ADDR
msg["To"]      = TO_ADDR

ctx = ssl.create_default_context()
with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as s:
    s.starttls(context=ctx)
    s.login(SMTP_USER, SMTP_PASS)
    s.sendmail(FROM_ADDR, TO_ADDR, msg.as_string())
    print("✓ Mail gesendet")
```

### swaks (falls installiert)

```bash
swaks \
  --to deine-verifizierte@testadresse.com \
  --from noreply@decisionmap.ai \
  --server email-smtp.eu-west-1.amazonaws.com \
  --port 587 \
  --tls \
  --auth-user DEIN_SMTP_USERNAME \
  --auth-password DEIN_SMTP_PASSWORT \
  --header "Subject: SES Test"
```

**Erwartetes Ergebnis:** Mail kommt an, Absender ist `noreply@decisionmap.ai`, kein Spam-Folder.

[↑ Übersicht](#übersicht)

---

## Phase 8 — Production Access beantragen

Im Sandbox-Modus können nur verifizierte Empfänger E-Mails erhalten.
Für echte User-Registrierungen muss der Sandbox-Modus aufgehoben werden.

1. [SES → Account dashboard → Request production access](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/get-set-up)
2. Formular ausfüllen:
   - **Mail type:** Transactional (Registrierung, Passwort-Reset)
   - **Website URL:** `https://decisionmap.ai`
   - **Use case description:** Nutzer-Registrierung + E-Mail-Verifizierung für B2B-SaaS-App; kein Marketing, kein Bulk-Versand
   - **Additional contacts:** eigene E-Mail
   - **Bounce/Complaint handling:** SES Notifications via SNS (oder manuell beschreiben)
3. Absenden → AWS Support prüft innerhalb von **1–3 Werktagen**
4. Bestätigungs-Mail von AWS abwarten

> Nach Freigabe: keine Empfänger-Begrenzung mehr, Sending Limit wird erhöht.

[↑ Übersicht](#übersicht)

---

## Phase 9 — Directus konfigurieren (Hetzner-Server)

### .env auf dem Server aktualisieren

```bash
# Lokal: infrastructure/.env editieren, dann auf Server übertragen
scp infrastructure/.env decmap:/srv/decisionmap/.env
```

Oder direkt auf dem Server:
```bash
ssh decmap
nano /srv/decisionmap/.env
```

**Folgende Variablen setzen:**
```env
EMAIL_FROM=noreply@decisionmap.ai
EMAIL_SMTP_HOST=email-smtp.eu-west-1.amazonaws.com
EMAIL_SMTP_PORT=587
EMAIL_SMTP_USER=<smtp-username>
EMAIL_SMTP_PASSWORD=<smtp-password>
EMAIL_SMTP_SECURE=false
```

> ⚠️ **Gotcha:** `EMAIL_SMTP_HOST` nur setzen wenn SMTP tatsächlich erreichbar ist.
> Ist der Host gesetzt aber nicht erreichbar, wartet Directus beim Start **60 Sekunden**
> auf eine SMTP-Verbindung → Container wird `unhealthy` → alle anderen Services blockiert.
> Während der Einrichtung `EMAIL_SMTP_HOST=` (leer) lassen und erst nach erfolgreichem
> Phase-7-Test setzen.

### Directus neu starten

```bash
make -C infrastructure server-update SVC=backend
# oder direkt:
ssh decmap "cd /srv/decisionmap && docker compose restart backend"
```

### SMTP-Verbindung verifizieren

```bash
# Liest apps/backend/.env automatisch — kein manuelles Credential-Setzen nötig
./scripts/smtp-test.py --send --to dein@email.com
```

Alternativ: Passwort-Reset im Frontend auslösen → Reset-Mail muss ankommen (ab Phase 8: an beliebige Adresse).

> **Hinweis:** Directus 11 hat den "Test-Mail senden"-Button in `Settings → Email` entfernt.
> SMTP-Verifikation ausschließlich über `scripts/smtp-test.py` oder den Passwort-Reset-Flow.

[↑ Übersicht](#übersicht)

---

## Phase 10 — Gesamtsystem-Verifikation

Nach Produktionsfreigabe den kompletten Registrierungs-Flow testen:

- [ ] Neue User-Registrierung im Frontend → Verification-Mail kommt an
- [ ] Link in der Verification-Mail → `/verify-email` → Redirect auf `/login?verified=true`
- [ ] Passwort-Reset-Flow → Reset-Mail kommt an
- [ ] Absender erscheint als `noreply@decisionmap.ai` (kein AWS-Absender)
- [ ] Mail landet **nicht** im Spam-Folder

[↑ Übersicht](#übersicht)

---

## Referenz

| Was | Link |
|---|---|
| SES Console (eu-west-1) | [eu-west-1.console.aws.amazon.com/ses](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1) |
| SES Verified Identities | [→ Verified Identities](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/verified-identities) |
| SES SMTP Settings | [→ SMTP Settings](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/smtp) |
| SES Production Access | [→ Get Set Up](https://eu-west-1.console.aws.amazon.com/ses/home?region=eu-west-1#/get-set-up) |
| IAM Users | [console.aws.amazon.com/iam](https://console.aws.amazon.com/iam/home#/users) |
| Hetzner DNS | [dns.hetzner.com](https://dns.hetzner.com) |
| DNS-Propagation prüfen | [dnschecker.org — decisionmap.ai ALL Records](https://dnschecker.org/all-dns-records-of-domain.php?query=decisionmap.ai&rtype=ALL&dns=google) |
| Directus Admin Email | [cms.decisionmap.ai/admin/settings/email](https://cms.decisionmap.ai/admin/settings/email) |
| SMTP Endpoint | `email-smtp.eu-west-1.amazonaws.com:587` |
| Tracking Issue | MikeMitterer/decmap_project#1 |
