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

- Frontend: 72 tests passing
- Backend: 101 tests passing
- AI Service: 124 tests passing
- E2E: 9 tests passing (Playwright)
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
├── docs/                        ← Detailed specifications
│   ├── backend.md               ← Infrastructure, deploy, versioning
│   ├── conventions.md           ← Code conventions with examples
│   ├── data-model.md            ← Full database schema
│   ├── features.md              ← Feature specifications
│   ├── dev-environment.md       ← Local dev setup (ports, fake data, venv)
│   ├── cmdline.md               ← curl examples for all API endpoints
│   └── ses-setup.md             ← AWS SES: domain verification → SMTP → production
├── scripts/                     ← Workspace scripts
├── .templates/                  ← Reusable templates (Jenkinsfile, Makefile, Docker)
├── .libs/                       ← Local symlinks (BashLib, MakeLib) — gitignored
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
2. Behavioral signals (too-fast submit, session flood, bot agents)
3. Honeypot field
4. GPT-4o-mini as final gate — no CAPTCHA

**Solution Approaches (post-login, LLM-only):**
- GPT-4o-mini evaluates content — no behavioral layer needed (auth required)

### Automatic Clustering
1. Load embeddings → HDBSCAN (L2-norm, euclidean, adaptive `min_cluster_size`)
2. LLM labels each cluster → hierarchical tags L1–L9
3. Sub-clustering for deeper hierarchies
4. Problems linked to new tags

### Moderation Workflow

**Problems:**
```
submitted → [behavioral signals] ─→ needs_review ─→ [admin] → approved / rejected
         → [LLM spam filter]    ─→ pending       ─→ [admin] → approved / rejected
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
- [x] FastAPI backend + auth (JWT, magic link, email verification)
- [x] pgvector similarity detection + duplicate filter
- [x] HDBSCAN clustering + LLM labeling → hierarchical tags
- [x] Spam filter: multi-layer for problems (rate limiting → honeypot → GPT-4o-mini), LLM-only for solution approaches
- [x] WebSocket realtime updates (voting, graph changes)
- [x] Moderation workflow (admin queue, batch operations)
- [x] Cytoscape.js graph visualization
- [x] Theme system (6 presets + custom)
- [x] Hetzner infrastructure + TLS + AWS SES
- [x] Region system: 121 DACH regions (ISO 3166-2) + geo-detection for problem submission

**Up next:**
- [ ] Clustering smoke test
- [ ] Beta access for first companies
- [ ] Stripe integration (SaaS pricing)
- [ ] Region-based filtering and ranking in graph view

---

## Documentation

| Document | Content |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Main technical reference, gotchas, conventions |
| [`docs/backend.md`](docs/backend.md) | Infrastructure, deploy, versioning |
| [`docs/data-model.md`](docs/data-model.md) | Full database schema |
| [`docs/features.md`](docs/features.md) | Feature specifications |
| [`docs/moderation-criteria.md`](docs/moderation-criteria.md) | AI spam filter acceptance/rejection criteria (SSoT) |
| [`docs/dev-environment.md`](docs/dev-environment.md) | Local development setup |
| [`docs/cmdline.md`](docs/cmdline.md) | curl examples for all API endpoints |
| [`docs/ui-test-data.md`](docs/ui-test-data.md) | Realistic test data (KMU/DACH context) and spam scenarios for manual UI testing |

---

## Get Involved

**Beta access:** Leading AI projects in your company and want to test the platform?
→ [Get in touch via issue](https://github.com/MikeMitterer/decmap_project/issues/new)

**Feedback & bugs:** [Issues](https://github.com/MikeMitterer/decmap_project/issues)

**Contact:** [office@mikemitterer.at](mailto:office@mikemitterer.at)
