#!/usr/bin/env python3
#------------------------------------------------------------------------------
# smtp-test.py — Test-Mail über die SMTP-Einstellungen aus .env versenden
#
# Liest EMAIL_SMTP_* und EMAIL_FROM aus der .env-Datei und versendet eine
# Test-Mail via smtplib. Nützlich um SES, smtp2go o.ä. schnell zu verifizieren.
#
# Verwendung:
#   ./scripts/smtp-test.py --send --to <empfaenger> [--env <pfad>]
#   ./scripts/smtp-test.py --send --to admin@example.com
#
# Optionen:
#   --send         Test-Mail versenden
#   --to EMAIL     Empfänger-Adresse (Pflicht bei --send)
#   --env FILE     Pfad zur .env-Datei (default: apps/backend/.env)
#------------------------------------------------------------------------------

import argparse
import smtplib
import sys
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path

APPNAME = Path(__file__).name
WORKSPACE = Path(__file__).parent.parent
DEFAULT_ENV_FILE = WORKSPACE / "apps" / "backend" / ".env"


class Colors:
    YELLOW     = "\033[38;5;11m"
    GREEN      = "\033[38;5;10m"
    LIGHT_BLUE = "\033[38;5;45m"
    CYAN       = "\033[38;5;51m"
    BLUE       = "\033[38;5;75m"
    RED        = "\033[38;5;196m"
    RESET      = "\033[0m"


def usage_line(option: str, description: str, col_width: int = 22) -> None:
    """Gibt eine formatierte Options-Zeile aus.

    Args:
        option:      Kurz- und Langform, z.B. '--send'.
        description: Beschreibung der Option, darf ANSI-Farben enthalten.
        col_width:   Breite der Options-Spalte (default: 22).
    """
    print(f"    {Colors.CYAN}{option:<{col_width}}{Colors.RESET} {description}")


def usage() -> None:
    """Zeigt die Verwendungshinweise an."""
    print(f"\nUsage: {APPNAME} [ options ]\n")
    usage_line("--send",    "Test-Mail versenden")
    usage_line("--to EMAIL", "Empfänger-Adresse (Pflicht bei --send)")
    usage_line("--env FILE", f"Pfad zur .env-Datei (default: {Colors.YELLOW}apps/backend/.env{Colors.RESET})")
    usage_line("-h | --help", "Diese Hilfe anzeigen")
    print(f"\n{Colors.LIGHT_BLUE}Hints:{Colors.RESET}")
    print(f"    {Colors.GREEN}{APPNAME} --send --to dein@email.com{Colors.RESET}")
    print(f"    {Colors.GREEN}{APPNAME} --send --to dein@email.com --env /pfad/zu/.env{Colors.RESET}")
    print()


def parse_env_file(env_path: Path) -> dict[str, str]:
    """Parst eine .env-Datei und gibt ein Dict mit den Werten zurück.

    Args:
        env_path: Pfad zur .env-Datei.

    Returns:
        Dict mit Key-Value-Paaren (Anführungszeichen werden entfernt).

    Raises:
        SystemExit: Wenn die Datei nicht gefunden wird.
    """
    if not env_path.exists():
        print(f"\n{Colors.RED}✗ .env-Datei nicht gefunden:{Colors.RESET} {env_path}\n", file=sys.stderr)
        sys.exit(1)

    env: dict[str, str] = {}
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def show_settings(host: str, port: str, user: str, email_from: str) -> None:
    """Gibt die geladenen SMTP-Einstellungen formatiert aus.

    Args:
        host:       SMTP-Host.
        port:       SMTP-Port.
        user:       SMTP-Benutzername.
        email_from: Absender-Adresse.
    """
    print(f"\n  {Colors.YELLOW}SMTP-Einstellungen{Colors.RESET}\n")
    print(f"    {Colors.BLUE}{'Host:':<20}{Colors.RESET} {host}")
    print(f"    {Colors.BLUE}{'Port:':<20}{Colors.RESET} {port}")
    print(f"    {Colors.BLUE}{'User:':<20}{Colors.RESET} {user or '(keine Auth)'}")
    print(f"    {Colors.BLUE}{'From:':<20}{Colors.RESET} {email_from}")
    print()


def build_message(email_from: str, to_address: str, host: str, port: str) -> MIMEMultipart:
    """Erstellt die Test-Mail als MIME-Objekt.

    Args:
        email_from:  Absender-Adresse.
        to_address:  Empfänger-Adresse.
        host:        SMTP-Host (für Mail-Body).
        port:        SMTP-Port (für Mail-Body).

    Returns:
        Fertig aufgebautes MIMEMultipart-Objekt.
    """
    msg = MIMEMultipart()
    msg["From"]    = f"DecisionMap SMTP-Test <{email_from}>"
    msg["To"]      = to_address
    msg["Subject"] = "DecisionMap SMTP-Test"
    msg["Date"]    = datetime.now().strftime("%a, %d %b %Y %H:%M:%S +0000")

    body = (
        f"Dies ist eine Test-Mail von {APPNAME}.\n\n"
        f"Einstellungen:\n"
        f"  Host: {host}\n"
        f"  Port: {port}\n"
        f"  From: {email_from}\n\n"
        f"Wenn du diese Mail siehst, funktioniert der SMTP-Relay korrekt.\n"
    )
    msg.attach(MIMEText(body, "plain", "utf-8"))
    return msg


def send_test_mail(env_path: Path, to_address: str) -> None:
    """Liest .env, baut die Mail und versendet sie via SMTP STARTTLS.

    Args:
        env_path:   Pfad zur .env-Datei.
        to_address: Empfänger-Adresse.

    Raises:
        SystemExit: Bei fehlenden Pflichtfeldern oder SMTP-Fehler.
    """
    env = parse_env_file(env_path)

    smtp_host     = env.get("EMAIL_SMTP_HOST", "")
    smtp_port     = int(env.get("EMAIL_SMTP_PORT", "587"))
    smtp_user     = env.get("EMAIL_SMTP_USER", "")
    smtp_password = env.get("EMAIL_SMTP_PASSWORD", "")
    email_from    = env.get("EMAIL_FROM", "")

    if not smtp_host:
        print(f"\n{Colors.RED}✗ EMAIL_SMTP_HOST nicht gesetzt in:{Colors.RESET} {env_path}\n", file=sys.stderr)
        sys.exit(1)

    if not email_from:
        print(f"\n{Colors.RED}✗ EMAIL_FROM nicht gesetzt in:{Colors.RESET} {env_path}\n", file=sys.stderr)
        sys.exit(1)

    show_settings(smtp_host, str(smtp_port), smtp_user, email_from)

    msg = build_message(email_from, to_address, smtp_host, str(smtp_port))

    print(f"  Versende Test-Mail an {Colors.CYAN}{to_address}{Colors.RESET} ... ", end="", flush=True)

    try:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=15) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            if smtp_user and smtp_password:
                server.login(smtp_user, smtp_password)
            server.sendmail(email_from, [to_address], msg.as_string())

        print(f"{Colors.GREEN}✓ gesendet{Colors.RESET}\n")

    except smtplib.SMTPAuthenticationError as exc:
        print(f"{Colors.RED}✗ Authentifizierung fehlgeschlagen{Colors.RESET}\n", file=sys.stderr)
        print(f"  {Colors.YELLOW}Hinweis:{Colors.RESET} SMTP-User/Password prüfen — bei AWS SES müssen die", file=sys.stderr)
        print(f"  SMTP-Credentials (nicht IAM-Keys) unter 'SMTP Settings' erzeugt werden.\n", file=sys.stderr)
        print(f"  Detail: {exc}\n", file=sys.stderr)
        sys.exit(1)

    except smtplib.SMTPException as exc:
        print(f"{Colors.RED}✗ SMTP-Fehler:{Colors.RESET} {exc}\n", file=sys.stderr)
        sys.exit(1)

    except OSError as exc:
        print(f"{Colors.RED}✗ Verbindung fehlgeschlagen:{Colors.RESET} {smtp_host}:{smtp_port}\n", file=sys.stderr)
        print(f"  Detail: {exc}\n", file=sys.stderr)
        sys.exit(1)


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parst die Kommandozeilen-Argumente.

    Args:
        argv: Argument-Liste (typischerweise sys.argv[1:]).

    Returns:
        Geparstes Namespace-Objekt.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--send",   action="store_true")
    parser.add_argument("--to",     default="")
    parser.add_argument("--env",    default=str(DEFAULT_ENV_FILE))
    parser.add_argument("-h", "--help", action="store_true")
    return parser.parse_args(argv)


def main() -> None:
    """Entry Point."""
    if len(sys.argv) == 1:
        usage()
        sys.exit(0)

    args = parse_args(sys.argv[1:])

    if args.help:
        usage()
        sys.exit(0)

    if args.send:
        if not args.to:
            print(f"\n{Colors.RED}✗ --to EMAIL fehlt{Colors.RESET}\n", file=sys.stderr)
            usage()
            sys.exit(1)
        send_test_mail(Path(args.env), args.to)
    else:
        usage()


if __name__ == "__main__":
    main()
