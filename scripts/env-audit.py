#!/usr/bin/env python3
"""env-audit.py — Vergleicht .env gegen .env.example in allen Repos.

Prüft für jedes Repo ob alle Keys dokumentiert (.env.example) und
konfiguriert (.env) sind. Meldet Drift ohne Values offenzulegen.

Exit-Codes:
    0  — alles in Sync
    1  — Drift gefunden (fehlende Keys)
    2  — Keine .env-Dateien gefunden
"""

import argparse
import sys
from pathlib import Path
from typing import NamedTuple

APPNAME = Path(__file__).name
ROOT    = Path(__file__).parent.parent

REPOS = [
    ROOT,
    ROOT / "apps" / "backend",
    ROOT / "apps" / "frontend",
    ROOT / "apps" / "ai-service",
    ROOT / "infrastructure",
]


# ─── ANSI Output ──────────────────────────────────────────────────────────────

class C:
    YELLOW     = "\033[38;5;11m"
    GREEN      = "\033[38;5;10m"
    RED        = "\033[38;5;196m"
    BLUE       = "\033[38;5;33m"
    CYAN       = "\033[38;5;51m"
    BOLD       = "\033[1m"
    RESET      = "\033[0m"


def usage_line(option: str, description: str, col_width: int = 32) -> None:
    """Gibt eine formatierte Options-Zeile aus."""
    print(f"    {C.CYAN}{option:<{col_width}}{C.RESET} {description}")


def usage() -> None:
    print(f"\nUsage: {APPNAME} [ options ]\n")
    usage_line("-a | --audit",   "Alle Repos prüfen (Standard)")
    usage_line("-r | --repo PATH", "Nur ein einzelnes Repo prüfen")
    usage_line("-q | --quiet",   "Nur Fehler ausgeben (kein OK-Status)")
    usage_line("-h | --help",    "Diese Hilfe anzeigen")
    print(f"\n{C.BLUE}Beispiele:{C.RESET}")
    print(f"    {C.GREEN}{APPNAME} --audit{C.RESET}")
    print(f"    {C.GREEN}{APPNAME} --repo apps/backend{C.RESET}")
    print()


# ─── Parsing ──────────────────────────────────────────────────────────────────

class AuditResult(NamedTuple):
    repo:          Path
    env_exists:    bool
    example_exists: bool
    undocumented:  list[str]   # in .env, fehlt in .env.example
    unconfigured:  list[str]   # in .env.example, fehlt in .env
    synced:        int          # Anzahl Keys in Sync


def parse_keys(path: Path) -> set[str]:
    """Liest alle Key-Namen aus einer .env-Datei (ignoriert Kommentare + Leerzeilen)."""
    keys = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # KEY=value oder KEY= oder KEY  (ohne =)
        key = line.split("=", 1)[0].strip()
        if key:
            keys.add(key)
    return keys


def audit_repo(repo: Path) -> AuditResult:
    """Vergleicht .env gegen .env.example in einem Repo."""
    env_path     = repo / ".env"
    example_path = repo / ".env.example"

    env_exists     = env_path.exists()
    example_exists = example_path.exists()

    if not env_exists or not example_exists:
        return AuditResult(repo, env_exists, example_exists, [], [], 0)

    env_keys     = parse_keys(env_path)
    example_keys = parse_keys(example_path)

    undocumented = sorted(env_keys - example_keys)
    unconfigured = sorted(example_keys - env_keys)
    synced       = len(env_keys & example_keys)

    return AuditResult(repo, env_exists, example_exists,
                       undocumented, unconfigured, synced)


# ─── Output ───────────────────────────────────────────────────────────────────

def repo_label(repo: Path) -> str:
    """Kurzer, lesbarer Repo-Name relativ zum Root."""
    try:
        rel = repo.relative_to(ROOT)
        return str(rel) if str(rel) != "." else "DecisionMap (Root)"
    except ValueError:
        return str(repo)


def print_result(result: AuditResult, quiet: bool) -> bool:
    """Gibt den Audit-Befund eines Repos aus. Gibt True zurück wenn Drift."""
    label  = repo_label(result.repo)
    indent = "    "

    has_drift = bool(result.undocumented or result.unconfigured)
    missing   = not result.env_exists or not result.example_exists

    print(f"\n  {C.BLUE}{label}{C.RESET}")

    if not result.example_exists:
        print(f"{indent}{C.YELLOW}⚠ .env.example fehlt — kein Vergleich möglich{C.RESET}")
        return False

    if not result.env_exists:
        print(f"{indent}{C.YELLOW}⚠ .env fehlt — noch nicht konfiguriert{C.RESET}")
        return False

    if not has_drift:
        if not quiet:
            print(f"{indent}{C.GREEN}✓ {result.synced} Keys in Sync{C.RESET}")
        return False

    if result.synced > 0 and not quiet:
        print(f"{indent}{C.GREEN}✓ {result.synced} Keys in Sync{C.RESET}")

    for key in result.undocumented:
        print(f"{indent}{C.RED}✗ {key:<35}{C.RESET}  in .env, fehlt in .env.example  {C.YELLOW}(undokumentiert){C.RESET}")

    for key in result.unconfigured:
        print(f"{indent}{C.YELLOW}○ {key:<35}{C.RESET}  in .env.example, fehlt in .env  {C.CYAN}(nicht konfiguriert){C.RESET}")

    return True


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-a", "--audit",  action="store_true")
    parser.add_argument("-r", "--repo",   type=Path, default=None)
    parser.add_argument("-q", "--quiet",  action="store_true")
    parser.add_argument("-h", "--help",   action="store_true")
    args = parser.parse_args()

    if args.help or (not args.audit and args.repo is None):
        usage()
        return 0

    repos = [args.repo.resolve()] if args.repo else REPOS
    repos = [r for r in repos if r.exists()]

    if not repos:
        print(f"\n{C.RED}Keine Repos gefunden.{C.RESET}\n")
        return 2

    print(f"\n{C.BOLD}  .env Audit{C.RESET}")
    print(f"  {'─' * 50}")

    any_drift = False
    for repo in repos:
        result    = audit_repo(repo)
        has_drift = print_result(result, args.quiet)
        if has_drift:
            any_drift = True

    print()
    if any_drift:
        print(f"  {C.RED}✗ Drift gefunden — .env.example aktualisieren oder .env konfigurieren{C.RESET}\n")
        return 1

    if not args.quiet:
        print(f"  {C.GREEN}✓ Alle Repos in Sync{C.RESET}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
