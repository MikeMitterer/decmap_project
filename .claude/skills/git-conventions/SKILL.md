---
name: git-conventions
description: Guide for writing changelog-worthy Conventional Commit messages. Use when committing code, writing commit messages, or when the user asks about git conventions, commit style, or changelog generation. Covers feat/fix/refactor/chore/docs/test types, subject lines, and body format for single- and multi-repo projects.
---

# Git Conventions

Conventional Commits, changelog-tauglich. Gilt für einzelne Repos und Multi-Repo-Setups gleichermaßen.

## Commit-Format

```
<type>(<scope>): <subject>

<body>
```

- **Subject**: Pflicht — Was ändert sich, aus Nutzerperspektive
- **Body**: Bei nicht-trivialen Änderungen — Warum, welches Problem wird gelöst

---

## Typen

| Typ | Wann |
|---|---|
| `feat` | Neues Verhalten, neue Funktion, neue API |
| `fix` | Fehler behoben — falsches Verhalten korrigiert |
| `refactor` | Umbau ohne Verhaltensänderung (Variablen, Struktur, Lesbarkeit) |
| `chore` | Wartung ohne Produktionsrelevanz (Deps, Config, Build-Scripts) |
| `docs` | Nur Dokumentation (CLAUDE.md, README, Kommentare) |
| `test` | Tests hinzugefügt oder korrigiert |

Faustregel: `feat` und `fix` landen im Changelog — alle anderen sind intern.

---

## Scopes (optional, aber empfohlen)

Scope beschreibt den betroffenen Bereich **innerhalb** eines Repos — nicht den Repo-Namen selbst.
Typische Scopes je nach Projekttyp:

```
feat(api):        HTTP-Routen, Endpunkte
feat(auth):       Authentifizierung, Permissions
feat(db):         Schema, Migrationen, Seeds
feat(docker):     Build-Scripts, Dockerfile
feat(ci):         Pipeline, Deployment
feat(ui):         Komponenten, Views, Layouts
feat(config):     Konfiguration, Umgebungsvariablen
```

Scopes sind projektspezifisch — verwende was im jeweiligen Repo sinnvoll ist.

---

## Subject-Line — Regeln

- Imperativ: "Einführen", "Korrigieren", nicht "eingeführt" oder "wurde eingeführt"
- Aus Nutzerperspektive: Was wird möglich/besser, nicht wie es intern umgesetzt ist
- Max 72 Zeichen
- Kein Punkt am Ende

**Schlecht** (technisch, intern):
```
refactor(docker): STRICT als Variable
fix(api): isinstance-Check geändert
```

**Gut** (Nutzerperspektive, aussagekräftig):
```
refactor(docker): STRICT-Variable für gitDockerTag-Strictness eingeführt
fix(api): Clustering-Endpoint akzeptiert jetzt auch leere Tag-Listen
```

---

## Body — Regeln

- Leerzeile nach Subject
- Erklärt das **Warum**, nicht das Was (das steht im Diff)
- Nennt das gelöste Problem oder den konkreten Vorteil
- Max 72 Zeichen pro Zeile

---

## Vollständige Beispiele

```
feat(clustering): HDBSCAN-Clustering für freigegebene Probleme implementiert

Ersetzt manuelles Tag-Setzen durch automatische Gruppenbildung.
Neue Probleme werden nach Approval direkt einem Cluster zugeordnet,
ohne Admin-Eingriff.
```

```
fix(auth): E-Mail-Verifizierung blockiert Login nach erneutem Senden nicht mehr

Beim zweiten Versenden des Verifizierungs-Links wurde der User
fälschlich ausgeloggt — registrationSent-Flag wurde nicht korrekt
zurückgesetzt.
```

```
refactor(docker): STRICT-Variable für gitDockerTag-Strictness eingeführt

Erlaubt Überschreiben per Env (STRICT=2 ./build.sh --build) ohne
Script-Änderung. Macht den Aufruf selbstdokumentierend — Strict-Level
ist beim Lesen sofort sichtbar statt implizit im Funktionsstandard.
```

```
chore(deps): FastAPI auf 0.111 aktualisiert

Behebt bekannte Sicherheitslücke in Starlette (CVE-2024-XXXX).
Keine API-Änderungen.
```

```
docs(backend): gitDockerTag-Format in backend.md dokumentiert

Bisher fehlte die Erklärung des Tag-Formats
0.1.0-260412.0824.def34.ahead3 — wichtig für Rollback-Entscheidungen.
```

---

## Multi-Repo-Hinweis

In Multi-Repo-Setups hat jedes Sub-Repo seinen eigenen Git-History.
Der Scope beschreibt den Bereich *innerhalb* des Repos — nicht den Repo-Namen selbst.
Wer den Commit liest, sieht bereits durch den Repo-Kontext, in welchem Service er landet.

```
# Im frontend-Repo:
feat(graph): Unclustered-Knoten als virtuellen Root-Knoten darstellen

# Im ai-service-Repo:
feat(clustering): Sub-Clustering für Gruppen > 50 Probleme

# Im backend-Repo:
fix(db): Permissions-Migration idempotent gemacht
```

Gilt genauso wenn ein weiteres Sub-Repo hinzukommt — Scope-Logik bleibt identisch.
