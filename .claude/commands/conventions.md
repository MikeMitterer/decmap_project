# Kern-Konventionen — DecisionMap

Ausfuehrliche Beispiele: `docs/conventions.md`

---

## Architektur

- **Frontend:** Komponenten = nur Darstellung. Business Logic → Composables.
- **Backend:** Router = nur HTTP. Business Logic → Services.
- Dependency Injection statt hardcodierter Abhaengigkeiten

## Naming

- **TS/Vue:** `camelCase` Dateien/Variablen, `PascalCase` Komponenten/Types, `SCREAMING_SNAKE_CASE` Konstanten
- **Python:** `snake_case` Dateien/Variablen, `PascalCase` Klassen, Type Hints immer
- **DB:** `snake_case`, Plural Lookup-Tabellen, Singular Junction-Tabellen
- **Loop-Variablen:** immer sprechend — `problem`, nie `p` oder `i`

## TypeScript

- Strict Mode, kein `any` (→ `unknown`), explizite Rueckgabetypen
- Interfaces fuer Objekte, Enums fuer feste Wertesets, keine Magic Strings
- Keine Non-null Assertions (`!`)

## Vue/Nuxt

- Nur Composition API + `<script setup lang="ts">`
- Props und Emits immer typisiert
- Keine API-Aufrufe in Komponenten

## Python/FastAPI

- Type Hints ueberall, Pydantic fuer Request/Response
- Router pro Fachbereich, Services fuer Business Logic

## Logging

- Frontend: `consola` (kein `console.log`)
- Backend: `structlog` (kein natives `logging`)

## Testing

- Frontend: Vitest, nur Composables, API mocken
- Backend: pytest, OpenAI mocken, Fixtures in `tests/fixtures/`
