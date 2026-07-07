#!/usr/bin/env python3
"""env-audit.py — Prüft .env gegen .env.example (Source of Truth) in allen Repos.

.env.example ist die SoT: sie definiert die vollständige, dokumentierte Key-Menge.
.env wird dagegen geprüft. Meldet Drift ohne Values offenzulegen.

Konventionen in .env.example:
    - Beschreibung eines Keys: Debian-Style `#:`-Zeile(n) direkt über dem Key
      (durch eine Leerzeile getrennte Kommentare gehören NICHT dazu). Alle `#:`-Zeilen
      des angrenzenden Kommentar-Blocks werden angezeigt.
    - Pflicht vs. optional: leerer Wert (`KEY=`) = Pflicht; Wert vorhanden
      (`KEY=default`) = optional (Default greift). Override via `[optional]` /
      `[required]` am Anfang der ersten `#:`-Zeile.

Exit-Codes:
    0  — .env erfüllt die SoT (nur optionale Keys dürfen fehlen)
    1  — Drift: Pflicht-Key fehlt in .env ODER .env hat einen der SoT unbekannten Key
    2  — keine Repos/.env-Dateien gefunden
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import NamedTuple

APPNAME = Path(__file__).name
ROOT    = Path(__file__).parent.parent

REPOS = [
    ROOT / "apps" / "backend",
    ROOT / "apps" / "frontend",
    ROOT / "apps" / "ai-service",
    ROOT / "infrastructure",
]

# Zeile, die nur aus Deko-/Trennzeichen besteht (z.B. "# ─── Section ───").
_DECORATION_RE = re.compile(r"^#\s*[\W_]*$")


# ─── ANSI Output ──────────────────────────────────────────────────────────────

class C:
    YELLOW = "\033[38;5;11m"
    GREEN  = "\033[38;5;10m"
    RED    = "\033[38;5;196m"
    ORANGE = "\033[38;5;214m"
    BLUE   = "\033[38;5;33m"
    CYAN   = "\033[38;5;51m"
    GREY   = "\033[38;5;245m"
    BOLD   = "\033[1m"
    RESET  = "\033[0m"


def usage_line(option: str, description: str, col_width: int = 32) -> None:
    """Gibt eine formatierte Options-Zeile aus."""
    print(f"    {C.CYAN}{option:<{col_width}}{C.RESET} {description}")


def usage() -> None:
    """Zeigt die Hilfe."""
    print(f"\nUsage: {APPNAME} [ options ]\n")
    usage_line("-a | --audit",     "Alle Repos prüfen (Standard)")
    usage_line("-m | --map",       "Konsolidierte Cross-Repo-Karte aller Keys (Überblick)")
    usage_line("-r | --repo PATH", "Nur ein einzelnes Repo prüfen")
    usage_line("-q | --quiet",     "Nur Drift ausgeben (kein OK-Status)")
    usage_line("-s | --strict",    "Warnungen (unbekannte Keys, fehlende Doku) als Fehler werten")
    usage_line("-c | --comment-out", "SoT-unbekannte Keys in .env AUSKOMMENTIEREN (mit Backup)")
    usage_line("-f | --fill",      "Fehlende SoT-Keys (Wert + Doku) in .env ÜBERNEHMEN (mit Backup)")
    usage_line("-k | --check",     "Wert-Gegenüberstellung .env ↔ SoT (leak-frei: Geheimes maskiert)")
    usage_line("-R | --reveal -y", "wie --check, aber ROHE Werte (NUR im eigenen Terminal ausführen!)")
    usage_line("-h | --help",      "Diese Hilfe anzeigen")
    print(f"\n{C.BLUE}Beispiele:{C.RESET}")
    print(f"    {C.GREEN}{APPNAME} --audit{C.RESET}")
    print(f"    {C.GREEN}{APPNAME} --repo apps/backend{C.RESET}")
    print()


# ─── Parsing ──────────────────────────────────────────────────────────────────

class ExampleKey(NamedTuple):
    name:        str
    required:    bool         # leerer Wert (oder [required]) → Pflicht
    description: list[str]     # alle `#:`-Zeilen des angrenzenden Blocks
    default:     str          # Beispiel-/Default-Wert aus .env.example


class ExampleFile(NamedTuple):
    keys:         dict[str, ExampleKey]
    duplicates:   list[str]        # mehrfach definierte Keys
    orphan_docs:  int              # `#:`-Blöcke, die keinem Key zugeordnet sind


class AuditResult(NamedTuple):
    repo:           Path
    env_exists:     bool
    example_exists: bool
    unknown:        list[str]              # in .env, nicht in SoT (.env.example)
    missing_req:    list[str]              # Pflicht-Key, fehlt in .env
    missing_opt:    list[str]              # optionaler Key, fehlt in .env
    synced:         int
    example:        ExampleFile


def _normalize_key(raw: str) -> str:
    """Vereinheitlicht einen Key-Namen (strippt `export ` + Whitespace)."""
    raw = raw.strip()
    if raw.startswith("export "):
        raw = raw[len("export "):].strip()
    return raw


def _classify(value: str, desc: list[str]) -> tuple[bool, list[str]]:
    """Bestimmt Pflicht/optional + bereinigt die Beschreibung.

    Regel: leerer Wert = Pflicht. `[optional]`/`[required]` am Anfang der ersten
    `#:`-Zeile überschreibt und wird aus der Anzeige entfernt.
    """
    required = value.strip() == ""
    cleaned = [d for d in desc if d]
    if cleaned:
        low = cleaned[0].lower()
        if low.startswith("[optional]"):
            required = False
            cleaned[0] = cleaned[0][len("[optional]"):].strip()
        elif low.startswith("[required]"):
            required = True
            cleaned[0] = cleaned[0][len("[required]"):].strip()
        cleaned = [d for d in cleaned if d]
    return required, cleaned


def parse_env_keys(path: Path) -> set[str]:
    """Liest alle Key-Namen aus einer .env-Datei (ignoriert Kommentare + Leerzeilen)."""
    keys: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key = _normalize_key(line.split("=", 1)[0])
        if key:
            keys.add(key)
    return keys


def parse_example(path: Path) -> ExampleFile:
    """Parst .env.example: Keys + `#:`-Beschreibungen des jeweils angrenzenden Blocks.

    Eine Leerzeile trennt einen Kommentar-Block vom Key darunter. Innerhalb eines
    Blocks zählen alle `#:`-Zeilen als Beschreibung; normale `#`-Zeilen (Header,
    Notizen) werden ignoriert, ohne den Block zu unterbrechen.
    """
    keys: dict[str, ExampleKey] = {}
    duplicates: list[str] = []
    orphan_docs = 0
    pending: list[str] = []

    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            if pending:
                orphan_docs += 1      # `#:`-Block, den kein Key aufgenommen hat
            pending = []
            continue
        if stripped.startswith("#:"):
            pending.append(stripped[2:].strip())
            continue
        if stripped.startswith("#"):
            continue                  # normaler Kommentar: ignorieren, Block bleibt
        if "=" not in stripped:
            pending = []
            continue
        name, value = stripped.split("=", 1)
        name = _normalize_key(name)
        required, desc = _classify(value, pending)
        if name in keys:
            duplicates.append(name)
        keys[name] = ExampleKey(name, required, desc, _clean_value(value))
        pending = []

    return ExampleFile(keys, duplicates, orphan_docs)


def _ensure_backup(env_path: Path, suffix: str) -> Path:
    """Legt einmal pro Lauf (je suffix) ein Backup des ORIGINAL-.env an — idempotent.

    Kombinierte Mutationen (--comment-out + --fill) teilen sich so EIN Backup; die
    zweite Operation überschreibt nicht das Backup des Originals mit einem
    Zwischenstand.
    """
    backup = env_path.with_name(f"{env_path.name}.bak-{suffix}")
    if not backup.exists():
        backup.write_text(env_path.read_text(encoding="utf-8"), encoding="utf-8")
    return backup


def comment_out_env(env_path: Path, unknown: list[str],
                    backup_suffix: str) -> tuple[Path, list[str]]:
    """Kommentiert SoT-unbekannte Keys in .env aus (`#` davor). Legt vorher ein Backup an.

    Gibt (Backup-Pfad, betroffene Keys) zurück. Gibt niemals Werte aus — arbeitet
    ausschliesslich zeilenweise auf der Datei; der Wert bleibt (auskommentiert) erhalten.
    """
    backup = _ensure_backup(env_path, backup_suffix)
    unknown_set = set(unknown)
    out: list[str] = []
    affected: list[str] = []

    for raw in env_path.read_text(encoding="utf-8").splitlines(keepends=True):
        body   = raw.rstrip("\n").rstrip("\r")
        ending = raw[len(body):]                       # Zeilenende bewahren (\n, \r\n)
        stripped = body.strip()
        is_assignment = bool(stripped) and not stripped.startswith("#") and "=" in stripped
        key = _normalize_key(stripped.split("=", 1)[0]) if is_assignment else None
        if key in unknown_set:
            affected.append(key)
            out.append(f"# {body}{ending}")            # auskommentieren, Wert bleibt im File
            continue
        out.append(raw)

    env_path.write_text("".join(out), encoding="utf-8")
    return backup, affected


def extract_example_blocks(path: Path) -> dict[str, str]:
    """Roh-Text-Block je Key aus .env.example: die angrenzenden `#:`-Zeilen +
    die Zuweisungszeile, unverändert (inkl. `[optional]`/`[required]`-Marker).

    Gleiche Block-Zuordnung wie parse_example (Leerzeile trennt, normale `#`-Zeilen
    unterbrechen den Block nicht) — nur wird der Rohtext statt der geparsten Felder
    behalten, damit --fill die Doku 1:1 in die .env übernimmt.
    """
    blocks: dict[str, str] = {}
    pending: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        stripped = raw.strip()
        if not stripped:
            pending = []
            continue
        if stripped.startswith("#:"):
            pending.append(raw.rstrip())
            continue
        if stripped.startswith("#"):
            continue                       # normaler Kommentar: ignorieren, Block bleibt
        if "=" not in stripped:
            pending = []
            continue
        name = _normalize_key(stripped.split("=", 1)[0])
        blocks[name] = "\n".join([*pending, raw.rstrip()])
        pending = []
    return blocks


def fill_env(env_path: Path, example_path: Path, missing: list[str],
             backup_suffix: str) -> tuple[Path, list[str]]:
    """Hängt fehlende SoT-Keys (Wert + `#:`-Doku) ans Ende der .env an. Backup vorher.

    Überschreibt NICHTS Bestehendes — nur nicht vorhandene Keys werden ergänzt. Die
    Reihenfolge folgt der .env.example. Rückgabe: (Backup-Pfad, ergänzte Keys).
    """
    blocks = extract_example_blocks(example_path)
    missing_set = set(missing)
    added: list[str] = []
    chunks: list[str] = []
    for name, block in blocks.items():          # Datei-Reihenfolge der SoT
        if name in missing_set:
            chunks.append(block)
            added.append(name)
    if not chunks:
        return env_path.with_name(f"{env_path.name}.bak-{backup_suffix}"), []

    backup = _ensure_backup(env_path, backup_suffix)
    body = env_path.read_text(encoding="utf-8")
    if body and not body.endswith("\n"):
        body += "\n"
    header = f"\n# ─── Ergänzt aus .env.example (env-audit {backup_suffix}) ───\n"
    env_path.write_text(body + header + "\n".join(chunks) + "\n", encoding="utf-8")
    return backup, added


def audit_repo(repo: Path) -> AuditResult:
    """Vergleicht .env gegen die SoT .env.example in einem Repo."""
    env_path     = repo / ".env"
    example_path = repo / ".env.example"
    env_exists     = env_path.exists()
    example_exists = example_path.exists()

    if not example_exists:
        return AuditResult(repo, env_exists, False, [], [], [], 0,
                           ExampleFile({}, [], 0))

    example = parse_example(example_path)
    if not env_exists:
        return AuditResult(repo, False, True, [], [], [], 0, example)

    env_keys     = parse_env_keys(env_path)
    example_keys = set(example.keys)

    unknown     = sorted(env_keys - example_keys)
    missing     = example_keys - env_keys
    missing_req = sorted(k for k in missing if example.keys[k].required)
    missing_opt = sorted(k for k in missing if not example.keys[k].required)
    synced      = len(env_keys & example_keys)

    return AuditResult(repo, True, True, unknown, missing_req, missing_opt,
                       synced, example)


# ─── Wert-Inspektion (leak-frei bzw. reveal) ──────────────────────────────────

# Key-Namen, deren WERT geheim ist → nie im Klartext (nur Fingerprint), ausser --reveal.
_SECRET_NAME_RE = re.compile(r"(SECRET|TOKEN|PASSWORD|PASSWD|API[_-]?KEY|_KEY|^KEY$)", re.I)
# Credentials in URLs (scheme://user:pass@host) → auch bei nicht-geheimem Key maskieren.
_URL_CRED_RE = re.compile(r"(\w+://)([^:/@\s]+):([^@/\s]+)@")


def _clean_value(raw: str) -> str:
    """Strippt Whitespace und ein umschliessendes Quote-Paar."""
    v = raw.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        v = v[1:-1]
    return v


def parse_env_pairs(path: Path) -> dict[str, str]:
    """Liest KEY → Wert aus einer .env (nur intern; Werte werden nie ungefiltert gedruckt)."""
    pairs: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        pairs[_normalize_key(k)] = _clean_value(v)
    return pairs


def _is_secret_name(name: str) -> bool:
    return bool(_SECRET_NAME_RE.search(name))


def _fingerprint(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()[:8]


def _infer_type(default: str) -> str:
    """Leitet den erwarteten Typ aus dem SoT-Default ab."""
    d = default.strip()
    if d == "":
        return "any"
    if d.lower() in ("true", "false"):
        return "bool"
    if re.fullmatch(r"-?\d+", d):
        return "int"
    if re.fullmatch(r"-?\d+\.\d+", d):
        return "float"
    if d.startswith("[") and d.endswith("]"):
        return "json"
    if re.match(r"^\w+://", d):
        return "url"
    if "@" in d and "." in d and " " not in d:
        return "mail"
    return "str"


def _valid_for_type(value: str, ttype: str) -> bool:
    """Prüft den Wert gegen den erwarteten Typ (ohne den Wert auszugeben)."""
    v = value.strip()
    if v == "" or ttype in ("any", "str"):
        return True
    if ttype == "bool":
        return v.lower() in ("true", "false")
    if ttype == "int":
        return bool(re.fullmatch(r"-?\d+", v))
    if ttype == "float":
        return bool(re.fullmatch(r"-?\d+(\.\d+)?", v))
    if ttype == "json":
        try:
            json.loads(v)
            return True
        except (ValueError, TypeError):
            return False
    if ttype == "url":
        return bool(re.match(r"^\w+://", v))
    if ttype == "mail":
        return "@" in v and "." in v
    return True


_ANSI_RE = re.compile(r"\033\[[0-9;]*m")


def _visible_len(text: str) -> int:
    """Sichtbare Breite eines (ggf. ANSI-gefärbten) Strings."""
    return len(_ANSI_RE.sub("", text))


def _fit(text: str, width: int) -> str:
    """Kürzt (mit …) oder füllt einen ANSI-freien Text auf exakt `width` Zeichen."""
    if width <= 0:
        return ""
    if len(text) > width:
        return text[: width - 1] + "…" if width > 1 else text[:width]
    return text + " " * (width - len(text))


def _matches_default(name: str, value: str, default: str) -> bool:
    """True, wenn der .env-Wert dem SoT-Default entspricht (fingerprint-basiert bei Geheimem)."""
    if _is_secret_name(name):
        return _fingerprint(value) == _fingerprint(default)
    return value == default


def _render_cell(name: str, value: str | None, reveal: bool,
                 empty_warn: bool = False, diverges: bool = False) -> tuple[str, str]:
    """Zellinhalt als (plain_text, ansi_farbe). Ohne --reveal: Geheimes → Fingerprint,
    URL-Credentials maskiert. Mit --reveal: Rohwert. Leere Farbe = Standardfarbe.

    empty_warn=True markiert einen gesetzten, aber leeren Wert orange (Problem-Hinweis) —
    genutzt für die .env-Spalte, wo `KEY=` (leer) meist unbeabsichtigt ist.
    diverges=True färbt einen gesetzten Wert gelb (weicht vom SoT-Default ab) — spiegelt
    den „abweichend"-Status in die .env-Spalte.
    """
    if value is None:
        return "—", C.GREY
    if value == "":
        return "(leer)", C.ORANGE if empty_warn else C.GREY
    diverge_col = C.YELLOW if diverges else ""
    if reveal:
        return value, diverge_col
    if _is_secret_name(name):
        return f"●●● {_fingerprint(value)}", diverge_col or C.GREY
    return _URL_CRED_RE.sub(r"\1***:***@", value), diverge_col


def _display_value(name: str, value: str | None, reveal: bool) -> str:
    """Gefärbter Einzelwert (für die Cross-Repo-Ausgabe)."""
    text, color = _render_cell(name, value, reveal)
    return f"{color}{text}{C.RESET}" if color else text


def _status_cell(name: str, present: bool, env_value: str, default: str, ttype: str) -> str:
    """Baut die Status-Zelle: Typ-Validität + gleich/abweichend zum SoT-Default."""
    if not present:
        return f"{C.RED}fehlt in .env{C.RESET}"
    parts: list[str] = []
    if env_value == "":
        parts.append(f"{C.ORANGE}leer{C.RESET}")
    elif not _valid_for_type(env_value, ttype):
        parts.append(f"{C.RED}UNGÜLTIG({ttype}){C.RESET}")
    else:
        parts.append(f"{C.GREEN}ok{C.RESET}")
    if default != "":
        same = _matches_default(name, env_value, default)
        parts.append(f"{C.GREY}gleich{C.RESET}" if same else f"{C.YELLOW}abweichend{C.RESET}")
    elif env_value != "":
        parts.append(f"{C.GREY}gesetzt{C.RESET}")
    return " · ".join(parts)


def repo_key_names(repo: Path) -> set[str]:
    """Alle Key-Namen eines Repos (.env.example ∪ .env) — für eine globale Spaltenbreite."""
    names: set[str] = set()
    if (repo / ".env.example").exists():
        names |= set(parse_example(repo / ".env.example").keys)
    if (repo / ".env").exists():
        names |= set(parse_env_pairs(repo / ".env"))
    return names


def key_column_width(repos: list[Path]) -> int:
    """Einheitliche KEY-Spaltenbreite über ALLE Repos — sonst starten die Wert-Spalten
    je Repo unterschiedlich weit (kürzester vs. längster Key-Name)."""
    longest = max((len(n) for r in repos for n in repo_key_names(r)), default=8)
    return max(8, min(26, longest))


def print_comparison(repo: Path, reveal: bool, w_key: int) -> bool:
    """Spalten-Gegenüberstellung .env ↔ .env.example je Key. Rückgabe: hat_fehler."""
    example_path = repo / ".env.example"
    env_path     = repo / ".env"
    print(f"\n  {C.BLUE}{repo_label(repo)}{C.RESET}")
    if not example_path.exists():
        print(f"    {C.RED}✗ .env.example (SoT) fehlt{C.RESET}")
        return True
    if not env_path.exists():
        print(f"    {C.YELLOW}⚠ .env fehlt — nicht konfiguriert{C.RESET}")
        return False

    example = parse_example(example_path)
    env     = parse_env_pairs(env_path)
    names   = sorted(set(example.keys) | set(env))
    has_error = False

    # ── Spaltenbreiten aus der Terminal-Breite ableiten (w_key ist global, s.o.) ──
    cols    = shutil.get_terminal_size((100, 24)).columns
    # Spalten (Default), gestapelt bei schmalem Terminal ODER --reveal (dort volle,
    # ungekürzte Rohwerte statt in Spalten abgeschnitten).
    stacked = cols < 72 or reveal
    if not stacked:
        avail = cols - 4 - w_key - 3 * 2 - 26           # 4 Indent, 3×2 Gaps, 26 Status-Reserve
        w_val = max(12, min(46, avail // 2))
        print(f"    {C.GREY}{_fit('KEY', w_key)}  {_fit('.env', w_val)}  "
              f"{_fit('SoT (.env.example)', w_val)}  Status{C.RESET}")

    for name in names:
        ek      = example.keys.get(name)
        present = name in env
        env_val = env.get(name, "")
        default = ek.default if ek else ""
        ttype   = _infer_type(default) if ek else "any"

        note = f"{C.RED}nicht in SoT{C.RESET}" if ek is None \
            else _status_cell(name, present, env_val, default, ttype)
        if (ek is None) or (present and not _valid_for_type(env_val, ttype)) \
                or (ek is not None and ek.required and not present):
            has_error = True

        diverges = (present and env_val != "" and default != ""
                    and not _matches_default(name, env_val, default))
        env_txt, env_col = _render_cell(name, env_val if present else None, reveal,
                                        empty_warn=True, diverges=diverges)
        sot_txt, sot_col = _render_cell(name, default if ek else None, reveal)

        if stacked:
            print(f"    {C.CYAN}{name}{C.RESET}")
            print(f"        .env = {env_col}{env_txt}{C.RESET}")
            print(f"        SoT  = {sot_col}{sot_txt}{C.RESET}")
            print(f"        → {note}")
        else:
            print(f"    {C.CYAN}{_fit(name, w_key)}{C.RESET}  "
                  f"{env_col}{_fit(env_txt, w_val)}{C.RESET}  "
                  f"{sot_col}{_fit(sot_txt, w_val)}{C.RESET}  {note}")

    return has_error


def print_cross_repo(repos: list[Path], reveal: bool) -> None:
    """Vergleicht Keys, die in mehreren Repos vorkommen (z.B. SERVICE_TOKEN müssen matchen)."""
    by_key: dict[str, dict[str, str]] = {}
    for repo in repos:
        env_path = repo / ".env"
        if not env_path.exists():
            continue
        for name, value in parse_env_pairs(env_path).items():
            by_key.setdefault(name, {})[repo_label(repo)] = value

    shared = {k: v for k, v in by_key.items() if len(v) >= 2}
    if not shared:
        return
    print(f"\n  {C.BLUE}Cross-Repo-Konsistenz{C.RESET} {C.GREY}(Keys in ≥2 Repos){C.RESET}")
    for name in sorted(shared):
        values = shared[name]
        distinct = set(values.values())
        repos_str = ", ".join(sorted(values))
        if len(distinct) == 1:
            only = next(iter(distinct))
            proof = _fingerprint(only) if _is_secret_name(name) and not reveal else \
                (_display_value(name, only, reveal))
            print(f"    {C.CYAN}{name:<26}{C.RESET} {C.GREEN}MATCH{C.RESET}   "
                  f"{C.GREY}{repos_str}{C.RESET}   {proof}")
        else:
            print(f"    {C.CYAN}{name:<26}{C.RESET} {C.RED}MISMATCH{C.RESET}   "
                  f"{C.GREY}{repos_str}{C.RESET}")


_REPO_TAG = {"backend": "BE", "frontend": "FE", "ai-service": "AI", "infrastructure": "INF"}


def _repo_tag(repo: Path) -> str:
    return _REPO_TAG.get(repo.name, repo.name[:3].upper())


def print_map(repos: list[Path]) -> None:
    """Konsolidierte Cross-Repo-Karte aller Keys aus den .env.example (SoT):
    je Key, in welchem Repo (R=Pflicht / o=optional) + Kurzbeschreibung."""
    tags: list[tuple[str, Path]] = [(_repo_tag(r), r) for r in repos]
    data: dict[str, dict[str, bool]] = {}
    desc: dict[str, str] = {}
    for tag, repo in tags:
        ex = repo / ".env.example"
        if not ex.exists():
            continue
        for name, ek in parse_example(ex).keys.items():
            data.setdefault(name, {})[tag] = ek.required
            if ek.description and name not in desc:
                desc[name] = ek.description[0]

    if not data:
        print(f"\n  {C.YELLOW}Keine .env.example gefunden.{C.RESET}\n")
        return

    cols   = shutil.get_terminal_size((100, 24)).columns
    labels = [t for t, _ in tags]
    w_key  = max(8, min(28, max(len(n) for n in data)))
    w_tag  = max(3, max((len(t) for t in labels), default=3))
    w_desc = max(10, cols - (4 + w_key + 2 + len(labels) * (w_tag + 1) + 2))
    rule   = "─" * min(cols - 2, 92)

    def cell(name: str, tag: str) -> str:
        if tag not in data[name]:
            return f"{C.GREY}{'·':>{w_tag}}{C.RESET}"
        req = data[name][tag]
        col = C.RED if req else C.GREEN
        return f"{col}{('R' if req else 'o'):>{w_tag}}{C.RESET}"

    print(f"\n{C.BOLD}  Env-Karte{C.RESET}  {C.GREY}(alle .env.example / SoT){C.RESET}")
    print(f"  {rule}")
    head_tags = " ".join(f"{lbl:>{w_tag}}" for lbl in labels)
    print(f"    {C.GREY}{_fit('KEY', w_key)}  {head_tags}  Beschreibung{C.RESET}")
    for name in sorted(data):
        cells = " ".join(cell(name, lbl) for lbl in labels)
        print(f"    {C.CYAN}{_fit(name, w_key)}{C.RESET}  {cells}  "
              f"{C.GREY}{_fit(desc.get(name, ''), w_desc)}{C.RESET}")
    total  = len(data)
    shared = sum(1 for r in data.values() if len(r) >= 2)
    print(f"  {rule}")
    print(f"    {C.GREY}{total} Keys · {shared} in ≥2 Repos · "
          f"{C.RED}R{C.GREY}=Pflicht  {C.GREEN}o{C.GREY}=optional  ·=fehlt{C.RESET}\n")


# ─── Output ───────────────────────────────────────────────────────────────────

def repo_label(repo: Path) -> str:
    """Kurzer, lesbarer Repo-Name relativ zum Root."""
    try:
        rel = repo.relative_to(ROOT)
        return str(rel) if str(rel) != "." else "DecisionMap (Root)"
    except ValueError:
        return str(repo)


def _print_description(desc: list[str], hint: str) -> None:
    """Gibt alle `#:`-Beschreibungszeilen eines Keys aus."""
    for line in desc:
        print(f"{hint}{C.GREY}#: {line}{C.RESET}")


def print_result(result: AuditResult, quiet: bool, strict: bool) -> tuple[bool, bool]:
    """Gibt den Befund eines Repos aus. Rückgabe: (hat_fehler, hat_warnung)."""
    indent = "    "
    hint   = "      "
    print(f"\n  {C.BLUE}{repo_label(result.repo)}{C.RESET}")

    if not result.example_exists:
        print(f"{indent}{C.RED}✗ .env.example (SoT) fehlt — kein Vergleich möglich{C.RESET}")
        return True, False
    if not result.env_exists:
        print(f"{indent}{C.YELLOW}⚠ .env fehlt — noch nicht konfiguriert{C.RESET}")
        return False, True

    ex = result.example
    has_error = bool(result.unknown or result.missing_req)

    # Doku-/Struktur-Warnungen der SoT
    undocumented = sorted(k for k, v in ex.keys.items() if not v.description)
    has_warning = bool(result.unknown or ex.duplicates or ex.orphan_docs or undocumented)

    if not has_error and not has_warning and not quiet:
        print(f"{indent}{C.GREEN}✓ {result.synced} Keys in Sync{C.RESET}")
        return False, False

    if result.synced and not quiet:
        print(f"{indent}{C.GREEN}✓ {result.synced} Keys in Sync{C.RESET}")

    # Pflicht-Keys fehlen (echter Konfigurationsfehler)
    for key in result.missing_req:
        print(f"{indent}{C.RED}✗ {key:<35}{C.RESET}  Pflicht-Key fehlt in .env")
        _print_description(ex.keys[key].description, hint)

    # Der SoT unbekannte Keys in .env
    for key in result.unknown:
        print(f"{indent}{C.RED}✗ {key:<35}{C.RESET}  in .env, nicht in SoT (.env.example)")
        print(f"{hint}{C.GREY}→ aus .env entfernen — oder, falls bewusst neu, in .env.example (+ Code) aufnehmen{C.RESET}")

    # Optionale Keys fehlen (Info, kein Fehler)
    if not quiet:
        for key in result.missing_opt:
            print(f"{indent}{C.CYAN}○ {key:<35}{C.RESET}  optional, fehlt in .env (Default in .env.example)")
            _print_description(ex.keys[key].description, hint)

    # SoT-Qualitätswarnungen
    for key in ex.duplicates:
        print(f"{indent}{C.YELLOW}⚠ {key:<35}{C.RESET}  mehrfach in .env.example definiert")
    if ex.orphan_docs:
        print(f"{indent}{C.YELLOW}⚠ {ex.orphan_docs} verwaiste #:-Beschreibung(en) in .env.example (kein Key darunter){C.RESET}")
    if undocumented and not quiet:
        joined = ", ".join(undocumented)
        print(f"{indent}{C.YELLOW}⚠ ohne #:-Doku in .env.example: {C.RESET}{C.GREY}{joined}{C.RESET}")

    return has_error, has_warning


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-a", "--audit",  action="store_true")
    parser.add_argument("-m", "--map",    action="store_true")
    parser.add_argument("-r", "--repo",   type=Path, default=None)
    parser.add_argument("-q", "--quiet",  action="store_true")
    parser.add_argument("-s", "--strict", action="store_true")
    parser.add_argument("-h", "--help",   action="store_true")
    parser.add_argument("-c", "--comment-out", dest="comment_out", action="store_true")
    parser.add_argument("-f", "--fill",   action="store_true")
    parser.add_argument("-k", "--check",  action="store_true")
    parser.add_argument("-R", "--reveal", action="store_true")
    parser.add_argument("-y", "--yes",    action="store_true")
    args = parser.parse_args()

    if args.help or (not args.audit and not args.map and not args.comment_out
                     and not args.fill and not args.check and not args.reveal
                     and args.repo is None):
        usage()
        return 0

    repos = [args.repo.resolve()] if args.repo else REPOS
    repos = [r for r in repos if r.exists()]
    if not repos:
        print(f"\n{C.RED}Keine Repos gefunden.{C.RESET}\n")
        return 2

    # ── Konsolidierte Karte (--map) ──
    if args.map:
        print_map(repos)
        return 0

    # ── Wert-Gegenüberstellung (--check / --reveal) ──
    if args.check or args.reveal:
        if args.reveal and not args.yes:
            print(f"\n  {C.RED}--reveal zeigt ROHE Geheimwerte.{C.RESET}")
            print(f"  {C.YELLOW}Nur im eigenen Terminal ausführen — nie über einen Assistenten.{C.RESET}")
            print(f"  {C.GREY}Bewusst bestätigen: {APPNAME} --reveal --yes{C.RESET}\n")
            return 2
        heading = "Wert-Gegenüberstellung" + (f" {C.RED}[REVEAL — Rohwerte]{C.RESET}" if args.reveal else " (leak-frei)")
        print(f"\n{C.BOLD}  {heading}{C.RESET}  {C.GREY}(.env ↔ SoT .env.example){C.RESET}")
        print(f"  {'─' * 50}")
        w_key = key_column_width(repos)
        any_error = False
        for repo in repos:
            any_error = print_comparison(repo, args.reveal, w_key) or any_error
        print_cross_repo(repos, args.reveal)
        print()
        return 1 if any_error else 0

    print(f"\n{C.BOLD}  .env Audit{C.RESET}  {C.GREY}(SoT: .env.example){C.RESET}")
    print(f"  {'─' * 50}")

    backup_suffix = datetime.now().strftime("%Y%m%d-%H%M%S")

    any_error = False
    any_warning = False
    for repo in repos:
        result = audit_repo(repo)
        has_error, has_warning = print_result(result, args.quiet, args.strict)
        any_error = any_error or has_error
        any_warning = any_warning or has_warning

        if args.comment_out and result.env_exists and result.unknown:
            backup, affected = comment_out_env(repo / ".env", result.unknown, backup_suffix)
            print(f"    {C.GREEN}✎ {len(affected)} Key(s) auskommentiert{C.RESET}"
                  f"  {C.GREY}Backup: {backup.name}{C.RESET}")
            for key in affected:
                print(f"      {C.GREY}- {key}{C.RESET}")

        if args.fill and result.env_exists:
            missing = result.missing_req + result.missing_opt
            if missing:
                backup, added = fill_env(repo / ".env", repo / ".env.example",
                                         missing, backup_suffix)
                print(f"    {C.GREEN}✎ {len(added)} Key(s) aus SoT ergänzt{C.RESET}"
                      f"  {C.GREY}Backup: {backup.name}{C.RESET}")
                for key in added:
                    req = "" if not result.example.keys[key].required \
                        else f"  {C.RED}(Pflicht — Wert setzen){C.RESET}"
                    print(f"      {C.GREY}+ {key}{C.RESET}{req}")
        elif args.fill and not result.env_exists and result.example_exists:
            print(f"    {C.GREY}→ keine .env — anlegen mit: cp .env.example .env{C.RESET}")

    print()
    if any_error or (args.strict and any_warning):
        print(f"  {C.RED}✗ Drift gegen die SoT (.env.example) — .env angleichen{C.RESET}\n")
        return 1
    if any_warning and not args.quiet:
        print(f"  {C.YELLOW}✓ .env erfüllt die SoT — Warnungen offen (siehe oben){C.RESET}\n")
        return 0
    if not args.quiet:
        print(f"  {C.GREEN}✓ Alle Repos erfüllen die SoT{C.RESET}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
