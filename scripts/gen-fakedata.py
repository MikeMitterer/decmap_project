#!/usr/bin/env python3
"""gen-fakedata.py — Verteilt kanonische Seed-Daten aus data/ an Consumer-Repos.

Single Source of Truth: data/*.json (snake_case, UUIDs)

Generiert:
  apps/frontend/composables/data/fake/seeds.json   — camelCase, kombiniert
  apps/ai-service/tests/fakedata/problems.json     — snake_case + embedding: null
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

APPNAME = Path(__file__).name
ROOT    = Path(__file__).parent.parent
DATA    = ROOT / "data"

# Felder die aus problems.json in die AI-Service Fake-Daten übernommen werden
AI_SERVICE_FIELDS = {
    "id", "title", "description", "title_en", "description_en",
    "status", "is_ai_generated",
}


# ─── ANSI Output ──────────────────────────────────────────────────────────────
# Farben angelehnt an BashLib colors.lib.sh (256-Farben)

class Colors:
    YELLOW     = "\033[38;5;11m"
    GREEN      = "\033[38;5;10m"
    RED        = "\033[38;5;196m"
    BLUE       = "\033[38;5;33m"
    CYAN       = "\033[38;5;51m"
    LIGHT_BLUE = "\033[38;5;45m"
    BOLD       = "\033[1m"
    RESET      = "\033[0m"


def usage_line(option: str, description: str, col_width: int = 30) -> None:
    """Gibt eine formatierte Options-Zeile aus (entspricht usageLine aus BashLib).

    Args:
        option:      Kurz- und Langform, z.B. '-g | --generate'.
        description: Beschreibung, darf ANSI-Farben enthalten.
        col_width:   Breite der Options-Spalte (default: 30).
    """
    print(f"    {Colors.CYAN}{option:<{col_width}}{Colors.RESET} {description}")


def usage() -> None:
    """Zeigt die Verwendungshinweise an — gleicher Aufbau wie Bash-Konvention."""
    print(f"\nUsage: {APPNAME} [ options ]\n")
    usage_line("-g | --generate", f"Generiert Fake-Daten nach {Colors.YELLOW}apps/frontend{Colors.RESET} und {Colors.YELLOW}apps/ai-service{Colors.RESET}")
    usage_line("-n | --dry-run",  "Zeigt was generiert würde, ohne Dateien zu schreiben")
    usage_line("-h | --help",     "Diese Hilfe anzeigen")
    print(f"\n{Colors.LIGHT_BLUE}Hints:{Colors.RESET}")
    print(f"    Generieren:    {Colors.GREEN}{APPNAME} --generate{Colors.RESET}")
    print(f"    Dry-Run:       {Colors.GREEN}{APPNAME} --dry-run{Colors.RESET}")
    print()


def log_section(title: str) -> None:
    """Gibt eine Abschnitts-Überschrift in Cyan aus."""
    print(f"\n{Colors.BOLD}{Colors.CYAN}▶ {title}{Colors.RESET}")


def log_success(message: str) -> None:
    """Gibt eine Erfolgs-Meldung in Grün aus."""
    print(f"  {Colors.GREEN}✓{Colors.RESET}  {message}")


def log_skip(message: str) -> None:
    """Gibt eine Warnung in Gelb aus (z.B. wenn ein Zielpfad fehlt)."""
    print(f"  {Colors.YELLOW}⚠{Colors.RESET}  {message}")


def log_dry_run(message: str) -> None:
    """Gibt eine Dry-Run-Meldung in Blau aus."""
    print(f"  {Colors.BLUE}ℹ{Colors.RESET}  [dry-run] {message}")


# ─── Konvertierung ────────────────────────────────────────────────────────────

def to_camel(name: str) -> str:
    """Konvertiert einen snake_case-String zu camelCase.

    Args:
        name: Snake-case Bezeichner, z.B. 'cluster_id'.

    Returns:
        camelCase-Bezeichner, z.B. 'clusterId'.
    """
    parts = name.split("_")
    return parts[0] + "".join(part.capitalize() for part in parts[1:])


def snake_to_camel(obj: Any) -> Any:
    """Konvertiert alle Keys eines JSON-Objekts rekursiv von snake_case zu camelCase.

    Args:
        obj: Dict, Liste oder primitiver Wert.

    Returns:
        Dasselbe Objekt mit camelCase-Keys (Dicts) bzw. unverändert (Primitives).
    """
    if isinstance(obj, dict):
        return {to_camel(k): snake_to_camel(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [snake_to_camel(item) for item in obj]
    return obj


# ─── Daten laden ─────────────────────────────────────────────────────────────

def load_json(filename: str) -> list:
    """Lädt eine JSON-Datei aus dem data/-Verzeichnis.

    Args:
        filename: Dateiname relativ zu data/, z.B. 'problems.json'.

    Returns:
        Geparstes JSON-Objekt (typischerweise eine Liste).
    """
    return json.loads((DATA / filename).read_text())


def write_json(target: Path, data: Any, dry_run: bool) -> None:
    """Schreibt Daten als formatiertes JSON in eine Datei.

    Args:
        target:  Zielpfad der JSON-Datei.
        data:    Zu schreibende Daten.
        dry_run: Wenn True, wird nichts geschrieben.
    """
    if dry_run:
        log_dry_run(f"würde schreiben → {target.relative_to(ROOT)}")
        return
    target.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


# ─── Target: frontend seeds.json ─────────────────────────────────────────────

def gen_frontend(dry_run: bool = False) -> None:
    """Generiert seeds.json für das Frontend (camelCase).

    Kombiniert problems, solutions, tags, regions und problem_tags
    in eine einzelne seeds.json-Datei mit camelCase-Keys.

    Args:
        dry_run: Wenn True, wird nichts geschrieben — nur Ausgabe.
    """
    target = ROOT / "apps/frontend/composables/data/fake/seeds.json"

    if not target.parent.exists():
        log_skip(f"frontend übersprungen (Pfad nicht gefunden: {target.parent.relative_to(ROOT)})")
        return

    seeds = {
        "problems":    snake_to_camel(load_json("problems.json")),
        "solutions":   snake_to_camel(load_json("solutions.json")),
        "tags":        snake_to_camel(load_json("tags.json")),
        "regions":     snake_to_camel(load_json("regions.json")),
        "problemTags": snake_to_camel(load_json("problem_tags.json")),
    }

    write_json(target, seeds, dry_run)
    log_success(f"frontend/seeds.json → {len(seeds['problems'])} problems")


# ─── Target: ai-service tests/fakedata/problems.json ─────────────────────────

def gen_ai_service(dry_run: bool = False) -> None:
    """Generiert problems.json für den AI-Service (snake_case, approved only).

    Filtert auf Status 'approved', behält nur die für Tests relevanten Felder
    und setzt embedding auf null.

    Args:
        dry_run: Wenn True, wird nichts geschrieben — nur Ausgabe.
    """
    target = ROOT / "apps/ai-service/tests/fakedata/problems.json"

    if not target.parent.exists():
        log_skip(f"ai-service übersprungen (Pfad nicht gefunden: {target.parent.relative_to(ROOT)})")
        return

    all_problems = load_json("problems.json")
    approved_problems = [
        {**{k: v for k, v in problem.items() if k in AI_SERVICE_FIELDS}, "embedding": None}
        for problem in all_problems
        if problem.get("status") == "approved"
    ]

    write_json(target, approved_problems, dry_run)
    log_success(f"ai-service/fakedata/problems.json → {len(approved_problems)} problems (approved)")


# ─── CLI ──────────────────────────────────────────────────────────────────────

def parse_args(argv: list) -> argparse.Namespace:
    """Parst die Kommandozeilen-Argumente.

    add_help=False — eigene usage() wird statt argparse-Help verwendet.

    Args:
        argv: Argument-Liste (typischerweise sys.argv[1:]).

    Returns:
        Geparstes Namespace-Objekt.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-g", "--generate", action="store_true")
    parser.add_argument("-n", "--dry-run",  action="store_true")
    return parser.parse_args(argv)


def main() -> None:
    """Entry Point — zeigt Help wenn keine Option angegeben."""
    if len(sys.argv) == 1 or sys.argv[1] in ("-h", "--help"):
        usage()
        sys.exit(0)

    args = parse_args(sys.argv[1:])

    if not args.generate and not args.dry_run:
        usage()
        sys.exit(0)

    log_section("Generiere Fake-Daten aus data/")
    gen_frontend(dry_run=args.dry_run)
    gen_ai_service(dry_run=args.dry_run)
    log_section("Fertig")


if __name__ == "__main__":
    main()
