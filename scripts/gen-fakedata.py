#!/usr/bin/env python3
"""
gen-fakedata.py — Verteilt kanonische Seed-Daten aus data/ an Consumer-Repos.

Single Source of Truth: data/*.json (snake_case, UUIDs)

Generiert:
  apps/frontend/composables/data/fake/seeds.json   — camelCase, kombiniert
  apps/ai-service/tests/fakedata/problems.json     — snake_case + embedding: null

Usage:
  python3 scripts/gen-fakedata.py
  make fakedata-sync
"""

import json
from pathlib import Path

ROOT = Path(__file__).parent.parent
DATA = ROOT / "data"


# ─── Konvertierung ────────────────────────────────────────────────────────────

def to_camel(name: str) -> str:
    parts = name.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def snake_to_camel(obj):
    if isinstance(obj, dict):
        return {to_camel(k): snake_to_camel(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [snake_to_camel(i) for i in obj]
    return obj


# ─── Daten laden ─────────────────────────────────────────────────────────────

def load(filename: str) -> list:
    return json.loads((DATA / filename).read_text())


# ─── Target: frontend seeds.json ─────────────────────────────────────────────

def gen_frontend():
    target = ROOT / "apps/frontend/composables/data/fake/seeds.json"
    if not target.parent.exists():
        print(f"  skip frontend (Pfad nicht gefunden: {target.parent})")
        return

    seeds = {
        "problems":    snake_to_camel(load("problems.json")),
        "solutions":   snake_to_camel(load("solutions.json")),
        "tags":        snake_to_camel(load("tags.json")),
        "regions":     snake_to_camel(load("regions.json")),
        "problemTags": snake_to_camel(load("problem_tags.json")),
    }
    target.write_text(json.dumps(seeds, indent=2, ensure_ascii=False) + "\n")
    print(f"  frontend/seeds.json — {len(seeds['problems'])} problems")


# ─── Target: ai-service tests/fakedata/problems.json ─────────────────────────

def gen_ai_service():
    target = ROOT / "apps/ai-service/tests/fakedata/problems.json"
    if not target.parent.exists():
        print(f"  skip ai-service (Pfad nicht gefunden: {target.parent})")
        return

    problems = load("problems.json")
    fakedata_fields = {
        "id", "title", "description", "title_en", "description_en", "status", "is_ai_generated"
    }
    fakedata = [
        {**{k: v for k, v in p.items() if k in fakedata_fields}, "embedding": None}
        for p in problems
        if p.get("status") == "approved"
    ]
    target.write_text(json.dumps(fakedata, indent=2, ensure_ascii=False) + "\n")
    print(f"  ai-service/tests/fakedata/problems.json — {len(fakedata)} problems (approved only)")


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("Generiere Fake-Daten aus data/ ...")
    gen_frontend()
    gen_ai_service()
    print("Fertig.")
