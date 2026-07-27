<p align="center">
  <img src="assets/images/decisionmap-logo-gradient-light.svg" alt="DecisionMap" width="320" />
</p>

# DecisionMap

**The Collective AI Problem Map for Mid-Market Companies.**

Somewhere in another company, someone is struggling with the exact same AI problem as you.
You'll never meet. DecisionMap changes that.

Users submit real AI challenges from their day-to-day business — shadow AI, model selection,
compliance, data privacy with AI tools. Others contribute practical solutions from experience.
An AI backend clusters the submissions automatically and visualizes them as an interactive problem map.

**Not a consulting tool. Not a discussion forum. A structured, AI-supported knowledge base
with community validation through voting.**

**Target audience:** IT decision-makers, CDOs, AI project leads in mid-market companies  
**Domain:** [decisionmap.ai](https://decisionmap.ai)

[Deutsche Version](README.de.md)

---

## Status

> **Pre-Beta** — The platform is technically ready but not yet publicly promoted.
> Looking for 10–15 companies for the beta test. Interested? → [Open an issue](https://github.com/MikeMitterer/decmap_project/issues/new) or reach out directly.

- Frontend: 147 tests passing
- Backend: 227 tests passing (190 unit + 37 contract)
- AI Service: 156 tests passing
- E2E: 11 tests passing (Playwright)
- Infrastructure: Hetzner + Docker + nginx + TLS running
- SMTP: AWS SES (domain verification complete)

---

## How It Works

1. **Submit a problem** — brief description of a real AI challenge from daily business life
2. **Contribute solutions** — not polished recipes, but practical experience from the field
3. **AI clusters automatically** — similar problems are grouped into a tag hierarchy
4. **Visualization** — an interactive graph shows the problem landscape with drill-down to details

---

## Development Approach

This project is an experiment in **vibe-coding** — AI-assisted development where architecture
decisions, debugging and implementation emerge through close collaboration with AI assistants.
At the same time it's a real product with real users as the goal.

What that means in practice:
- All architecture decisions are documented (CLAUDE.md, docs/)
- Decision processes and learnings are shared publicly
- The stack was chosen deliberately for AI engineering depth — pgvector, HDBSCAN, LLM integration — not because it was the simplest option

The interesting part is happening right now. Follow progress and learnings on
[LinkedIn](https://www.linkedin.com/in/mangolila/).

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Frontend | Nuxt.js 3 + TypeScript | SPA/SSR hybrid, auto-imports, SEO-ready |
| CSS | Tailwind CSS | Utility classes, theme system via CSS custom properties |
| Visualization | Cytoscape.js | Interactive graph rendering |
| Backend | FastAPI + fastapi-users + SQLAlchemy (asyncio) | Auth, REST API, WebSocket, admin endpoints |
| Database | PostgreSQL + pgvector | Relational data + embeddings in one DB |
| AI Service | FastAPI (Python 3.11+) | Embeddings, clustering, spam filter, translation |
| DB Migrations | Alembic | Python-native, rollback-capable |
| Realtime | WebSocket (FastAPI) | Live updates in multi-user operation |
| Testing | Vitest / pytest / Playwright | Unit, contract and E2E tests |
| Hosting | Hetzner + Docker + nginx | European (GDPR), Docker Compose |
| CI/CD | Jenkins → SSH → Hetzner | Local Jenkins instance |

---

## Repository Structure

Multi-repo — five repositories with independent release cycles:

```
DecisionMap/                     ← Workspace root (issues, docs, CI coordination)
├── CLAUDE.md                    ← Main technical reference for all repos
├── README.md                    ← This file (English)
├── README.de.md                 ← German version
├── Makefile                     ← Workspace orchestration
├── .repo-status.conf.sh         ← Repo list + issue repo for make status (ProjectTools repo-status.sh)
├── docs/                        ← Detailed specifications
│   ├── backend.md               ← Infrastructure, deploy, versioning
│   ├── conventions.md           ← Code conventions with examples
│   ├── data-model.md            ← Full database schema
│   ├── features.md              ← Feature specifications
│   ├── dev-environment.md       ← Local dev setup (ports, services, venv)
│   ├── cmdline.md               ← curl examples for all API endpoints
│   └── ses-setup.md             ← AWS SES: domain verification → SMTP → production
├── scripts/                     ← Workspace scripts
│   ├── db-backup.sh             ← Unified DB backup/restore (backend + infrastructure)
│   ├── env-audit.py             ← .env audit against .env.example as SoT (--strict, --comment-out, --fill, leak-free --check value comparison, cross-repo liveness/superset/forwarding/compose-var guard)
│   ├── git-push-all.sh          ← Git push across all checked-out sub-repos
│   ├── routing-check.sh         ← Anti-drift guard: greps the whole tree for stale domains/routing prefixes (make routing-check)
│   └── smtp-test.py             ← SMTP relay verification (backend MAIL_* keys — SES / Mailpit)
├── .templates/                  ← Reusable templates (Jenkinsfile, Makefile, Docker)
├── .libs/                       ← Local symlinks (BashLib, MakeLib, ProjectTools) — gitignored
├── apps/                        ← Service repos (gitignored, own repos)
│   ├── backend/                 ← FastAPI backend + Alembic (schema owner)
│   ├── frontend/                ← Nuxt.js app
│   └── ai-service/              ← FastAPI AI service (no direct DB access)
└── infrastructure/              ← docker-compose, nginx (own repo)
```

---

## Makefile — Key Targets

```bash
make help          # Show all available commands
make hints         # Local URLs (via dev proxy + direct) and useful links
make setup         # Create .libs/ symlinks (once after cloning)
make status        # Git status for all sub-repos (dirty + ahead/behind remote)
```

**Cross-repo:**
```bash
make git-push-all  # Git push across all checked-out sub-repos
make build-all     # Build Docker images (backend + frontend + ai-service)
make test-all      # Run all tests
make deploy        # Full-stack deploy via infrastructure/
make version       # Show current versions of all sub-repos
```

Sub-repo makefiles:
```bash
make -C apps/backend help      # FastAPI backend, DB, backup
make -C apps/frontend help     # dev, lint, test, build
make -C apps/ai-service help   # FastAPI dev, test, build
make -C infrastructure help    # Server orchestration
```

---

## Local Development

```bash
make dev-up    # nginx proxy + Docker (Postgres + backend :8001) + overmind (frontend :3000 + AI service :8000 + backend logs)
make dev-down  # stop overmind + all Docker services
```

| URL | Service |
|---|---|
| http://localhost:3000 | Frontend |
| http://localhost:8001/docs | Backend Swagger |
| http://localhost:8000/docs | AI service Swagger |
| http://localhost:8025 | Mailpit (SMTP sink) |
| http://localhost:8080 | Adminer (DB UI, server: `postgres`) |

→ **Full setup guide:** [`docs/dev-environment.md`](docs/dev-environment.md)

---

## Architecture Principles

- **Frontend:** components = presentation, composables = logic + API communication
- **Backend:** router = HTTP, services = business logic (no HTTP knowledge in services)
- **Validation:** Zod (frontend) → Pydantic (backend) → PostgreSQL constraints
- **No hard deletes:** soft-delete via `deleted_at`/`deleted_by`
- **Multilingual:** every text field exists twice — original + `_en`; embeddings use `_en` only

---

## AI Features

### Similarity Detection
- Debounced check (600ms) via pgvector cosine similarity
- Score ≥ 0.85: hint with link to similar problem
- Score ≥ 0.92: likely duplicate — submit requires confirmation → routed to review queue (not auto-rejected)

### Spam Filter

**Problems (multi-layer):**
1. nginx rate limiting (5 req/minute per IP)
2. Honeypot field (instant reject if filled)
3. GPT-4o as final gate — no CAPTCHA

> Submissions also carry a `signals` array evaluated server-side (≥2 → reject, 1 → review). Behavioral-signal *computation* (too-fast submit, session flood, bot agents) is **not yet implemented** — only the `duplicate_confirmed` signal currently flows through.

**Solution Approaches (post-login, LLM-only):**
- GPT-4o evaluates content — no behavioral layer needed (auth required)

### Automatic Clustering
1. Load embeddings → HDBSCAN (L2-norm, euclidean, adaptive `min_cluster_size`)
2. LLM labels each cluster → hierarchical tags L1–L9
3. Sub-clustering for deeper hierarchies
4. Problems linked to new tags

### Moderation Workflow

**Problems:**
```
submitted → [honeypot / signals] ─→ rejected / needs_review   (signals: only duplicate_confirmed today)
         → [LLM spam filter]     ─→ pending       ─→ [admin] → approved / rejected
                                  ↘ spam → rejected (automatic)
```

**Solution Approaches** (post-login, no behavioral layer):
```
submitted → [LLM spam filter] → pending → [admin] → approved / rejected
                              ↘ spam → rejected (automatic)
```

---

## Tag Hierarchy

| Level | Created by | Description |
|---|---|---|
| L0 | System | Platform root node |
| L1–L9 | AI (automatic) | Hierarchical categories from problem analysis |
| L10 | User | Free tags (e.g. "shadow-ai", "compliance") |

---

## Data Model (Overview)

```
users ──< problems ──< solution_approaches
              ├──>< problem_tag    >──< tags (L0–L10)
              └──>< problem_region >──< regions
```

Full specification: [`docs/data-model.md`](docs/data-model.md)

---

## Roadmap

**Done:**
- [x] FastAPI backend + auth (JWT in HttpOnly cookie, magic link, email verification)
- [x] pgvector similarity detection + duplicate filter
- [x] HDBSCAN clustering + LLM labeling → hierarchical tags
- [x] Spam filter: multi-layer for problems (rate limiting → honeypot → GPT-4o), LLM-only for solution approaches
- [x] WebSocket realtime updates (voting, graph changes)
- [x] Moderation workflow (admin queue, batch operations)
- [x] Cytoscape.js graph visualization
- [x] Theme system (6 presets + custom)
- [x] Hetzner infrastructure + TLS + AWS SES
- [x] Region system: 121 DACH regions (ISO 3166-2) + geo-detection for problem submission
- [x] AI Draft for solution approaches (user-triggered, no auto-generate)
- [x] Solution Form: translation collapsible for solution content field
- [x] Solution editing for owners (PATCH /solutions/:id, localized fields, auto-resize)
- [x] Problem editing in user locale (edit fields from stored original text, no re-translation round-trip, auto-resize)
- [x] Solution moderation gate (AI is the gate: clean → approved instantly, flagged → review queue, no mandatory human step)
- [x] Global solution duplicate detection (live in the form + submit-time backstop, pgvector across all approved solutions)
- [x] Language-independent search (keyword + semantic): a German/non-English keyword like "schlecht" now matches the problem even though only the English canonical is indexed for embeddings — the `original_translations` JSONB column on `problems` is the source of truth for the original text, searched alongside the translated query (backend Postgres full-text search over the canonical + `original_translations`, frontend local match against the displayed localized title, semantic path unchanged)
- [x] Server-driven search + pagination (Phase 1): `GET /problems` is now keyset-paginated (`{items, next_cursor, total}`) with server-side filter/sort and cross-lingual keyword + semantic search; the table is infinite-scroll on a cursor store and the moderation queues filter server-side
- [x] Server-driven graph (Phase 2, drill-down): the graph no longer full-loads all problems — on mount it fetches only the lightweight `GET /problems/cluster-summary` aggregate, and each cluster's problem rows load lazily on drill-down via the paginated `GET /problems?tags=<id>` (search runs server-side too). The transitional `GET /problems/all` (plus the data-layer `fetchAllProblems`/`fetchProblems`) has been removed in Task 2.4; only the Phase 3 "N new problems" banner remains
- [x] Author / company chips (Phase 1): the problem panel shows a clickable author chip (emerald) and, for non-anonymous authors with a company set, a company chip (violet) — each wired to the server-side `user` / `company` filters of `GET /problems`. Selecting several chips filters by all of them: `user` / `company` are multi-value (comma-separated; `user` → `IN` list, `company` → case-insensitive `ILIKE`-OR) since [decmap_project#35](https://github.com/MikeMitterer/decmap_project/issues/35). Each chip carries a 👤/🏢 icon plus an `aria-label`/`title` tooltip ("Filter by author/company") so the two are distinguishable ([decmap_project#30](https://github.com/MikeMitterer/decmap_project/issues/30); the emerald/violet colour pair is unchanged). The company chip reads `problem.company` straight off each `ProblemRead` (always delivered by the backend), so it shows on **any** problem with a company set — not only your own (`9b8f357`). The author chip got the same treatment in `70f8a84`: `author_display_name` now rides on every `ProblemRead` (resolved per page alongside `company` in one batched `_load_authors` query), so the panel's `authorLabel` prefers it — shown for **any** non-anonymous author — and only falls back to the client-side user cache for your own/cached user. Demo authors with companies via seed `005_demo_authors.sql`
- [x] URL-addressable table filters ([decmap_project#31](https://github.com/MikeMitterer/decmap_project/issues/31)): table filters are shareable/bookmarkable via query params. A central, extensible param↔`ProblemQuery` map (`useTableFiltersUrl` — `sort`/`dir`/`q`/`semantic`/`tags`/`regions`/`user`/`company`/`status`, one entry per filter) hydrates state from the URL on mount and mirrors state back via `router.replace` (no history spam, empty filters dropped, `q`/`semantic` mutually exclusive). An `isHydrating` guard — cleared in a `finally` so a failed initial load can't dead-lock the table — suppresses the data-load and auto-select watches during mount hydration; `q`/`semantic` write-back is intentionally left to the layout header so the URL isn't rewritten on every keystroke
- [x] Company filter ([decmap_project#29](https://github.com/MikeMitterer/decmap_project/issues/29)): company filtering is wired to the server-side `company` filter of `GET /problems` and reachable via the violet company chip in the problem panel (emits the exact full name), the `?company=` URL param, and the active company filter chips in the table (each removable with ×); an optional company field at registration (`pages/login.vue` register tab → `company` in the register call) and in settings feeds the value. The `user` filter stays chip-only. A free-text company input above the table was tried and then **reverted** (`ebb759f`): the backend matches the company name as a whole value (`ilike` without wildcards), so a partial entry like `Acme` returned 0 hits against `Acme Manufacturing GmbH` — unusable for a free-text field. The chip/URL paths supply the exact canonical name, so they stay; the substring `%name%` backend change was deliberately left open. The table now also renders a sortable **Company** column: the author's company rides on every `ProblemRead` (`company`, `null` for anonymous problems, resolved per page via a single batched query — no N+1) and `sort=company` orders by it server-side across all pages; the cell renders the company as a compact coloured monogram badge (1–2 initials, full name on hover, deterministic colour sharing the cluster-dot palette via `colorFromString`) and clicking it applies that company filter. When the detail panel is open (table shrinks to ~70 %), the table switches to a compact mode that hides the Cluster and Submitted columns so the flexible Title column keeps its width (`27fa7a9`)
- [x] Cross-lingual keyword search symmetry ([decmap_project#32](https://github.com/MikeMitterer/decmap_project/issues/32)): the keyword query is translated into **both** EN and DE on the first search call (generic `translate_query(text, lang)`) and matched per language against a functional GIN **Postgres FTS** index (`to_tsvector @@ plainto_tsquery`, replacing the earlier ILIKE substring; BE `8982048`), so `q=missing` and `q=fehlend` return the **same** result set (unit test `test_fts_stemming_symmetry_english_plural` — `company`⇄`Unternehmen`, stubbed translation). Per-language **stemming** also closes the former inflection gap — `fehlt`/`fehlende`/`fehlend` and `company`/`companies` now match symmetrically, which the old substring match could not. The translations ride in the cursor under an additive key — generalized (`4d6279d`) from the fixed `q2`=DE slot to an N-language translation map (cursor key `qt`, looping the `SEARCH_LANGUAGES` registry) — at most one roundtrip per registry language; cursors predating the map degrade to `None` (no backwards-compat break). True synonyms (lack/missing/absent) still need semantic search — stemming is not synonym expansion. (In production, exact hit-count parity between the DE and EN query is best-effort, not guaranteed: a cross-language query reaches the other language's inflected rows only via its single-word LLM translation, whose exact token — e.g. participle `fehlend` vs. finite verb `fehlt` — decides the stemming match; the "same result set" holds under the stubbed/deterministic test translation. Analysis 2026-06-30, see `docs/features.md`.) The recall lever has since landed (Option B, BE `6fd5c1d` / AI `58fcbad`): `translate_query` now returns **several candidates** per language — inflected forms + near-synonyms from the new ai-service `POST /translate/candidates` endpoint — and the per-language WHERE OR-combines each candidate (unit test `test_multi_candidate_or_expansion`), so `missing` reaches `fehlend`/`vermisst`/… instead of one possibly mis-inflected translation. Candidates ride per language as a list in the cursor; exact DE↔EN count parity stays best-effort because the LLM translation is non-deterministic.
- [x] Semantic-search UI affordance ([decmap_project#28](https://github.com/MikeMitterer/decmap_project/issues/28)): the relevance affordances hinge on `relevanceSortActive` = AI search **on and a non-empty query** (since `d0981ab`), not the bare toggle — AI search on with an empty search box stays a normal, fully sortable list with no hint or lock. When relevance sorting is actually running, the left of the StatusBar shows a "Sorted by relevance" hint (accent-coloured label, blinks 3× on appearance, respects `prefers-reduced-motion`, removed via `v-if` when lifted), the table greys out and disables the column sort headers (tooltip) as the in-table affordance, and renders a per-row "{n}% match" badge from the backend relevance `score` (`1 − distance`, mapped onto the `Problem` type in `mapProblem`) — styled as an AI-showcase chip (`94c57e3`) with a sparkle icon, a mini relevance bar and an explanatory tooltip, coloured with a dedicated `--th-ai-accent` token kept distinct from the user-CTA accent (the first reference instance of the AI-marker design system, [decmap_project#39](https://github.com/MikeMitterer/decmap_project/issues/39)). Keyword/default mode is unchanged and the opaque cursor contract stays untouched
- [x] Graph drill-down overlap fix ([decmap_project#33](https://github.com/MikeMitterer/decmap_project/issues/33)): newly added nodes from `buildGraphElements()` used to start at (0,0) and stack for one frame before the synchronous `preset` layout positioned them — the remove/add/layout cycle now runs inside `cy.batch()` so no intermediate frame renders, and drill-down never flashes overlapping nodes/labels; follow-up rendering corrections (2026-06-30) hardened the drill-down further: the stylesheet is now re-applied **before** the batch (a `cy.style()` set inside `cy.batch()` doesn't reach elements added in the same batch — the cause of fat grey edges + grey cluster dots after a problem click), the drill-down now fits on the **real nodes only** via `fitDrillView` — the layout's own `fit: true` included the decoration badges still parked at (0,0), inflating the fit bbox into a wrong (too-low, ~67%) zoom; refitting on the real nodes after the layout settles and clamping to 100% fixes both that under-zoom and the over-zoom on sparse clusters — and (2026-07-01) the drill's `maxZoom` is capped to 100% **before** the layout runs its `fit` (restored to the manual-zoom ceiling of 3 afterwards), so the fit lands at ≤100% directly instead of exceeding to ~120–130% and snapping back, the grid lays each tier out at its natural size with fixed node-relative gutters (`cellW`/`cellH`/`TIER_GAP`, locale-scaled `s = 1` EN / `1.25` DE) and picks the column count that **maximises** the fit zoom (deterministic) rather than `round(sqrt(...))`, whose rounding flipped columns on a tiny aspect change and was the real cause of the unstable 67%↔99% zoom, then a single zoom-capped `fit` scales the whole thing into the viewport — replacing the earlier container-fraction spacing (and its `ROW_STEP` locale offsets) that made rows touch on taller German labels, clicking the already-drilled cluster is now a no-op (re-running the identical layout read as a jarring zoom jump), a `ResizeObserver` re-fits the active view when the container changes size (detail panel open/close, window resize) so the graph no longer slides under the panel, and the connecting edges are rendered more subtly (cluster/problem links faded, brand-gradient root→L1 edges at `line-opacity 0.55`) so the nodes stand out and the lines recede, and the drill was reduced to an instant cut — lazy-loaded problem pages are coalesced into a single debounced re-render (140ms) instead of one full re-layout per streamed page, and the final fit is instant (`fitDrillView` fits the real nodes and clamps to 100%, no camera animation); a briefly-tried 200ms animated glide was dropped because the camera flight read as a distracting animation rather than a clean cut to the final state; and (2026-07-01) the reverse move — the return to the mindmap overview — is now an instant cut rather than an animation: an animated `showMindmap` overlapping a re-render used to make the decoration badges (cluster dots + count badges) fly in from the origin across the screen (measured jump to ~608px, then a flight to ~95px), so all six `showMindmap` call sites now run instantly (`showMindmap(false)`), consistent with the instant drill — with no animated return the badges simply appear positioned instead of flying (verified: badge-to-parent distance constant at ~95px)
- [x] Security audit (2026-07-05/06, report: [`docs/security-audit-2026-07-05.md`](docs/security-audit-2026-07-05.md)): full workspace audit with all actionable findings fixed — auth JWT moved from localStorage to an **HttpOnly cookie** (`decisionmap_auth`, `SameSite=Lax`, frontend sends `credentials: 'include'`; login/magic-verify no longer return a token body, logout clears the cookie server-side), non-`approved` problems/solutions return **404** to third parties (existence never confirmed; owner/superuser still see them), `GET /health` no longer exposes the build version, **fail-closed startup validation** for `SECRET_KEY`/`SERVICE_TOKEN` (empty/placeholder values abort start, dev opt-in only via explicit `ALLOW_INSECURE_DEV=true`), and SSR/prerender markdown sanitizing via `isomorphic-dompurify` (the former raw-output bypass is removed — allowlist + link hardening now run on both server and client). Deliberately deferred (BE-08): an authenticated admin WS channel — until then the shared unauthenticated `/ws` broadcast carries only opaque UUIDs + status enums, never titles/content/rejection reasons
- [x] Localized tag/cluster names (`tags.name_translations`, migration 011): AI-generated L1–L9 cluster labels are English and were live-translated on every German list/graph load (~13 `/ai/translate` calls per DE table load → nginx 5r/m 429 — the main driver of the display-side rate limit). They are now pre-translated into a `name_translations` JSONB column (analogous to `problems.original_translations`) at clustering upsert (ON-CONFLICT refresh, not ignore), with a one-off `POST /clustering/backfill-tag-translations` for pre-migration tags (structural L1–L9 without a translation only); the frontend reads `nameTranslations[locale] ?? name` (`utils/tagDisplay.ts`) instead of translating live, closing the DE-list 429 (backend `a355520` + ai-service `db6f41c` on master; frontend display switch `c9820da`/`580dae7` on `feature/bold-redesign`)
- [x] Moderation fail-safe on provider errors (2026-07-25): a failing LLM spam-filter call (rate limit, quota exhaustion, API outage) now escalates a problem to `needs_review` (`moderation_error`) instead of silently rejecting it — previously a provider-quota hiccup in the background hook rejected every incoming problem. Auto-reject stays reserved for real spam verdicts, the honeypot and ≥2 signals; symmetric with the solution path (criteria: [`docs/moderation-criteria.md`](docs/moderation-criteria.md))

**Up next:**
- [ ] Bold UI redesign — glass-morphism with mesh-orb ambient background (visible through transparent TopBar/StatusBar and across login/status/admin pages), DmSidebar (72px) + DmTopBar app shell with a fixed English brand tagline (`MAP PROBLEMS · FIND SOLUTIONS`, never translated), glass Cytoscape graph with vote-score badges, inset cluster-count badges, cluster nodes that auto-size to fit long AI-generated labels (problem nodes stay fixed-height since their labels are pre-truncated), per-cluster colour-coded dot indicators (deterministic 12-colour palette via `utils/tagColor.ts`, shared with the table chip so every cluster keeps the same identity colour across views), full brand-gradient root node (orange→pink→magenta→violet) and brand-gradient root→L1 edges (orange→magenta), radial layout with sibling-density collision avoidance (`r ≥ nodeSpacing × N / span`), mindmap opens at 100% zoom centered on the root node (`centerOnRoot()` restores the saved viewport when one exists, otherwise defaults to 100% zoom on root — no `fit` on initial layout), draggable nodes with decoration badges that follow the parent on every position change (`cy.on('position', selector, repositionBadgesFor)`) and user-dragged positions persisted to localStorage (`graph-node-positions`, restored via `applyStoredPositions()` after every layout — algorithmic positions only used for nodes the user hasn't moved; positions are scoped per view level (mindmap vs. each drilled cluster) so a node dragged in the overview keeps its own position at each drill level), plus the mindmap viewport (zoom + pan) auto-saved to `graph-viewport-mindmap` with a 400ms debounce (`cy.on('viewport', ...)` only while `viewLevel === 'mindmap'`) so reload restores the exact state, with a reset-positions button next to the zoom controls (clears both storage keys and re-runs the active layout — `showMindmap` / `showUnclusteredView` / `applyTagFilters` — so the algorithmic positions and default viewport take over again), glass table view (8px rounded header, cluster chip with a per-cluster colour dot only — text and background stay neutral so the row reads quietly; the dot alone carries the identity), simplified Settings (mode + 6 accent swatches + a separate AI-accent picker (6 swatches, empty = per-theme default, persisted via `dm-ai-accent` and restored across theme switches) + gradient slider, persisted via `dm-accent` / `dm-grad-strength`; organised into two always-visible tabs — Profile (login-gated: guests see a login hint instead of the form) and Appearance (accessible without login)), a dark-glass out-of-the-box default look on first visit (dark glass theme + sunset accent + fuchsia AI accent; OS light/dark following stays opt-in via an explicit "system" preference), live system-status label and live graph-zoom indicator in the footer (`useGraphZoom`, visible only on the graph view; the zoom percentage itself rendered in the accent colour, the "Zoom" label faint) that also surfaces the graph's mouse/keyboard navigation as an inline hint next to the zoom readout (scroll = zoom, ⇧+scroll = horizontal pan and drag = pan shown inline with the action words in the accent colour; the full scheme — ⇧+Ctrl+scroll = vertical pan, arrow keys = pan/navigate between problem nodes — in the `title` tooltip; hidden below `md`), auth-sensitive solution CTA (full-width accent-coloured button that lives in a sticky action footer at the panel bottom — alongside the vote pill (which carries a one-vote-per-problem tooltip once you've voted) and a solution counter (T-16) — so it stays visible as the list scrolls beneath it (`SolutionList` is now a pure list); plus icon + "Add solution" when signed in, lock icon + "Sign in to contribute" for guests; both states call the same local `showSolutionForm()` (no more `add` event now that the CTA lives in `ProblemPanel` rather than `SolutionList`), and for guests it encodes view + problem + intent (`?problem=<id>&solution=new`) so after login the user returns to the same view with the panel restored and the solution form reopened), redesigned solution cards (header row with accent-coloured avatar pill + author name in Space Grotesk + a shared `AiBadge` (sparkle icon in the dedicated `--th-ai-accent`, distinct from the user-CTA accent) — replacing the 🤖 emoji prefix and unifying six previously divergent `is_ai_generated` badges as the AI-marker design system rolls out across every AI touchpoint ([decmap_project#39](https://github.com/MikeMitterer/decmap_project/issues/39)) — + faint mono vote-score; content rendered as a 2-line preview via `stripMarkdown()` + Tailwind `line-clamp-2` instead of a hard character slice, so the truncation adapts to panel width — same card vocabulary inside the graph solutions popup, so the right-panel and the popup share a single visual language), brand gradient reserved for identity surfaces only (logo wordmark, root node, cluster→root edges, login headline — every other CTA uses the user-selected accent), EN/DE pill switcher absolute-positioned top-right on `/login` (same `LanguageSwitcher` component used in the app shell, visible before authentication so first-time visitors can switch language without signing in), self-hosted DSGVO-compliant fonts, new-problem form opens as centered modal (T-12 — `<Teleport to="body">` from inside `ProblemForm.vue`, 680px R-02 glass surface, sticky footer with `form="problem-form"` submit attribute, similarity card inline between title and description; problem detail still renders in the side panel), solution form opens as a split-editor modal (T-13 — self-contained `<Teleport to="body">` from inside `SolutionForm.vue`, 1080px R-02 glass surface, permanent Write | Live-Preview split replacing the earlier Write/Preview tabs, a functional Markdown toolbar (bold/italic/heading/quote/list/link that wrap or line-prefix the caret selection), ESC/backdrop close, ⌘+Enter to submit; the side panel keeps showing the problem detail behind the backdrop), and a read-only full-page solution view (T-11 — new client-only route `/problem/:problemId/solution/:solutionId`, deliberately `ssr: false, prerender: false` since it loads solutions at runtime (`fetchSolutions(problemId)` + `.find(id)`, no by-id endpoint) and resolves author names client-side, so unlike the prerendered problem/cluster pages it is **not** an SEO surface; two-column reading layout — a Markdown reading column beside a rail of the problem's other solutions that swaps the active one on click, no invented title and no job-title, foreign authors shown as "Anonymous" and AI entries via the shared `AiBadge`, translation follows the global EN/DE display locale (no per-item toggle), voting patches both the local score and the shared `solutions.value` entry so the score survives rail navigation, share-permalink and no bookmark; Back / "← Mindmap" restores the entire graph view — selection + drill level + zoom/pan, mirrored through `?problem=`/`?cluster=` and carried in `?from=` (the rail links forward the same origin so switching solutions in the rail keeps the back target, while the share permalink stays origin-free), with the selected node showing only an accent border instead of an overlay corona; opened via an "↗ open in full view" link on the solution cards, with `stripMarkdown` + author-name/initial helpers extracted into `utils/solutionDisplay.ts` shared with the card list, plus a sticky collapsible problem-context band (T-14) inside the reading column (aligned with the 680px column so expand/collapse only moves the solution content below, leaving the right rail untouched) — collapsed by default to a compact one-line headline (eyebrow + title + labelled vote pill + ▲/▼ toggle; the headline row itself is a click/keyboard toggle too, sharing one `isExpandable` guard) that expands to reveal the problem's rendered description (`renderSolutionMarkdown`, following the same global EN/DE display locale as the solution) and status/AI/tag/region chips rendered by the shared `<ProblemMetaChips>` component (single source of truth with the problem panel, so the two views can't diverge), and the vote score surfaced as a labelled "▲ N votes" pill (vue-i18n plural) replacing the bare "↑ N" in the top bar, which now reads "Solution i of n"; the band tint uses `rgb(var(--th-surface) / 0.55)` so it retints per theme instead of a hardcoded rgba; no band or toggle only when the problem has neither description nor tags/regions), plus unified modal chrome across the problem and solution modals (T-15 — a shared frosted backdrop (`rgb(8 5 14 / 0.28)` + `blur(30px)` dark / `rgb(24 16 32 / 0.20)` light, keyed on `isDark` so non-glass themes get it too) lets the mesh colours shimmer softly through instead of dimming to hard black, and identical shell geometry (40px overlay padding, 24/28 header-top/body, 16/28 sticky footer) lines both modals up top and bottom — the R-02 modal surface itself initially untouched (its border + shadow only later strengthened, see below); the tinted scrim is the intentional R-09 exception, theme-independent `rgb(…/α)` allowed; a follow-up gave the split-editor solution modal a fixed fill height (`min(720px, 100vh − 80)`) so it actually lines up with the problem modal (~40px margin) instead of floating at content height, and switched the problem-form submit button from the brand gradient to the solid `--th-accent` used by every other CTA; and, since the barely-dimmed frosted backdrop let the modal edge blur into the mesh, both form modals gained a visible 1px border (dark `rgba(255,255,255,0.15)`, light `rgba(0,0,0,0.10)`) plus a deeper two-layer drop shadow so the surface reads as a clearly lifted floating card — fill colour and blur unchanged, so the two form modals deliberately diverge from the canonical R-02 surface on border/shadow only), and the TopBar's "+ Add problem" action is disabled on routes where the problem form isn't mounted (solution full page, settings, status, admin) — clicking it there previously only flipped the modal flag with nothing to render, so the modal ghost-opened on the next return to the map/table; the same route gate (a single `isProblemListView` computed for `/` and `/table`) now also disables the search input and AI-search toggle on those routes, which only filter the graph/table and were otherwise operable-but-inert (⌘K is a no-op there too), plus a unified corner-radius scale (T-17 — corners collapse from ~10 ad-hoc values to three: 8px for structural containers/controls/chips, 12px for cards/modals, `full` for pills/circles; the table header and panel card both moved 5px→8px to keep their shared radius, Cytoscape canvas nodes excluded), and the shared modal chrome was factored out into a real `AppModal.vue` shell (T-18 — the `Teleport to="body"`, frosted backdrop, glass R-02 card surface, ESC-to-close and backdrop-click that both form modals had duplicated now live in one component; callers pass `open` + a `cardStyle` geometry override and fill a default slot, so SolutionForm keeps its fixed fill-height and ProblemForm its `max-height` — a pure DRY refactor with byte-identical chrome, no user-visible change), and the problem-context band chrome (T-14) — its click/keyboard headline shell, rendered Markdown description, expanded detail body (description + status/AI/tag/region chips + author) and labelled vote pill — was factored into shared `ProblemContextBand`/`ProblemDescription`/`ProblemContextDetail`/`ProblemVotePill` components (plus a `useProblemMeta` composable resolving the tag/region chips the same way the panel feeds them) now consumed by both the full page and the new-solution modal, where the problem is fetched eagerly when the modal opens (so the vote pill shows in the collapsed headline) and a click on the `On: <title>` headline expands the same full detail as the full page — description, meta chips and author reading identically in both (fetched once, same localised path) (`branch: feature/bold-redesign`, 213 tests green, merge-ready)
- [ ] Clustering smoke test
- [ ] Beta access for first companies
- [ ] Stripe integration (SaaS pricing)
- [ ] Region-based filtering and ranking in graph view
- [ ] Server-driven search + pagination (Phase 3) — replace the full re-fetch on `problem.created` with an "N new problems" banner; the graph drill-down and the `GET /problems/all` removal (Task 2.4) already shipped (see [`docs/features.md → Language-independent search`](docs/features.md))
- [ ] Cross-lingual full-text search + relevance ranking (F2) — the backend has **landed** (Tasks 1–4): registry-driven Postgres FTS (`plainto_tsquery` against per-language functional GIN indexes, Migration 010) replaced keyword ILIKE in the `q` path, so `fehlt`/`fehlend`/`missing` now match symmetrically via stemming, plus the opt-in `sort=relevance` (`ts_rank` over the language registry, keyset-paginated; BE `59a2b29`, #37). The frontend `sort=relevance` has now landed too (Task 5, FE `d3a6950`), and as of 2026-06-30 relevance is **on by default** whenever keyword search is active (query present, AI search off — set at the transition into that state so a manual switch-off survives further typing), sending `sort=relevance` to `/problems` with the existing StatusBar "Sorted by relevance" hint. The explicit "Sort by relevance" toggle button has since been **removed**: clicking any column header now leaves relevance and sorts the loaded results by that column instead (so within one search there's no explicit way back to relevance — a new/cleared search restarts at relevance). Sort headers are locked only in **semantic** mode (where the backend orders server-side by embedding distance); in the keyword-relevance default they stay clickable, and no misleading sort arrow shows while relevance is active. Task 6 (the extensibility smoke-test `test_third_language_needs_only_registry_and_index` + docs, BE `820083e`) has landed too — all six F2 tasks are in and the final whole-branch review has been applied (notably I-1: the `original_translations` persist-allowlist is now derived from the search registry, so adding a language really is registry-entry + index only — no second hardcoded gatekeeper) (see [`docs/specs/2026-06-27-f2-cross-lingual-search-design.md`](docs/specs/2026-06-27-f2-cross-lingual-search-design.md))
- [ ] Discussion / forum (post-launch, [decmap_project#38](https://github.com/MikeMitterer/decmap_project/issues/38)) — lightweight in-app comments, **problem-anchored, cluster-aggregated**: threads attach to stable problem UUIDs (cluster L1-tags are re-computed by HDBSCAN and would lose their anchor), the cluster view aggregates the latest discussion across its problems at read time. Reuses ~80 % of existing building blocks (Markdown + DOMPurify, LLM spam filter + `needs_review` queue, WebSocket, voting, soft-delete). Launch-gated: built only after the public launch proves demand; escalates to Discourse + SSO if real forum features are needed
- [ ] Add DNSBL check (post-launch — not currently implemented)

---

## Documentation

| Document | Content |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Main technical reference, gotchas, conventions |
| [`docs/backend.md`](docs/backend.md) | Infrastructure, deploy, versioning |
| [`docs/data-model.md`](docs/data-model.md) | Full database schema |
| [`docs/features.md`](docs/features.md) | Feature specifications |
| [`docs/moderation-criteria.md`](docs/moderation-criteria.md) | AI spam filter acceptance/rejection criteria (SSoT) |
| [`docs/security-audit-2026-07-05.md`](docs/security-audit-2026-07-05.md) | Security audit report: findings, fixes, deliberately deferred items |
| [`docs/dev-environment.md`](docs/dev-environment.md) | Local development setup |
| [`docs/cmdline.md`](docs/cmdline.md) | curl examples for all API endpoints |
| [`docs/ui-test-data.md`](docs/ui-test-data.md) | Realistic test data (KMU/DACH context) and spam scenarios for manual UI testing |

---

## Get Involved

**Beta access:** Leading AI projects in your company and want to test the platform?
→ [Get in touch via issue](https://github.com/MikeMitterer/decmap_project/issues/new)

**Feedback & bugs:** [Issues](https://github.com/MikeMitterer/decmap_project/issues)

**Contact:** [office@mikemitterer.at](mailto:office@mikemitterer.at)
