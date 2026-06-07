# Solution Form: Translation Collapsible + AI Draft Generation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the translation UI in SolutionForm (collapsible, same pattern as ProblemForm) and add a user-triggered "AI Draft" button that generates a solution proposal via the AI service.

**Architecture:** New `POST /generate-solution` endpoint in the AI-Service returns a draft without storing it. Frontend `useAiDraft(problemId)` composable calls this endpoint and feeds the result into an auto-growing textarea in `SolutionForm.vue`. The EN translation section is replaced with a collapsible mirroring `EnglishTranslationSection` visual style but with a single content field.

**Tech Stack:** FastAPI (Python 3.11), pytest-asyncio, Nuxt 3 / Vue 3 / TypeScript, Vitest, Tailwind CSS, nginx

**Spec:** `docs/specs/2026-06-07-solution-form-design.md`

---

## File Map

| Repo | File | Action |
|---|---|---|
| `ai-service` | `app/routers/solutions.py` | **Create** — `POST /generate-solution` endpoint |
| `ai-service` | `main.py` | **Modify** — register `solutions` router |
| `ai-service` | `tests/unit/routers/test_solutions.py` | **Create** — 3 unit tests |
| `infrastructure` | `host/etc/nginx/nginx.conf` | **Modify** — add rate-limit zone + location |
| `infrastructure` | `host/etc/nginx/nginx.dev.conf` | **Modify** — add location (no rate-limit) |
| `frontend` | `composables/useAiDraft.ts` | **Create** — draft generation composable |
| `frontend` | `tests/composables/useAiDraft.spec.ts` | **Create** — 4 unit tests |
| `frontend` | `components/SolutionForm.vue` | **Modify** — auto-grow + AI button + collapsible EN section |
| `frontend` | `i18n/locales/en.json` | **Modify** — add `aiDraft*` keys |

---

## Task 1: AI-Service — Failing Tests for `POST /generate-solution`

**Files:**
- Create: `apps/ai-service/tests/unit/routers/test_solutions.py`

- [ ] **Step 1.1: Create the test file**

```python
# apps/ai-service/tests/unit/routers/test_solutions.py
"""Unit tests for POST /generate-solution (Issue #26 — user-triggered AI draft)."""
from unittest.mock import AsyncMock

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.dependencies import get_backend_client, get_llm_provider

# Will be created in Task 2
from app.routers import solutions

_PROBLEM_ID = "prob-abc-123"
_AI_CONTENT = "## Solution\n\nHere is a solution."
_PROBLEM = {
    "id": _PROBLEM_ID,
    "title": "Missing AI Governance Framework",
    "description": "Our organisation lacks a unified risk assessment framework.",
}

_PATCH_CLIENT = "app.routers.solutions.get_backend_client"
_PATCH_LLM = "app.routers.solutions.get_llm_provider"


@pytest.fixture
def test_app() -> FastAPI:
    app = FastAPI()
    app.include_router(solutions.router)
    return app


@pytest.fixture
def mock_backend_client() -> AsyncMock:
    bc = AsyncMock()
    bc.get_by_id = AsyncMock(return_value=_PROBLEM)
    return bc


@pytest.fixture
def mock_llm() -> AsyncMock:
    llm = AsyncMock()
    llm.generate_solution = AsyncMock(return_value=_AI_CONTENT)
    return llm


@pytest.fixture
async def client(test_app: FastAPI, mock_backend_client: AsyncMock, mock_llm: AsyncMock):
    test_app.dependency_overrides[get_backend_client] = lambda: mock_backend_client
    test_app.dependency_overrides[get_llm_provider] = lambda: mock_llm
    async with AsyncClient(transport=ASGITransport(app=test_app), base_url="http://test") as ac:
        yield ac
    test_app.dependency_overrides.clear()


async def test_generate_solution_returns_content(
    client: AsyncClient,
) -> None:
    """Happy path: problem found, LLM generates draft → 200 with content."""
    response = await client.post("/generate-solution", json={"problem_id": _PROBLEM_ID})
    assert response.status_code == 200
    assert response.json() == {"content": _AI_CONTENT}


async def test_generate_solution_404_when_problem_not_found(
    client: AsyncClient,
    mock_backend_client: AsyncMock,
) -> None:
    """Backend returns None → 404 (problem doesn't exist or is deleted)."""
    mock_backend_client.get_by_id.return_value = None
    response = await client.post("/generate-solution", json={"problem_id": "missing-id"})
    assert response.status_code == 404


async def test_generate_solution_passes_title_and_description_to_llm(
    client: AsyncClient,
    mock_llm: AsyncMock,
) -> None:
    """LLM is called with the problem's title and description, not the ID."""
    await client.post("/generate-solution", json={"problem_id": _PROBLEM_ID})
    mock_llm.generate_solution.assert_awaited_once_with(
        _PROBLEM["title"], _PROBLEM["description"]
    )
```

- [ ] **Step 1.2: Run tests — expect ImportError (module does not exist yet)**

```bash
cd apps/ai-service
make test-unit 2>&1 | grep -E "ERROR|FAILED|test_solutions"
```

Expected: `ModuleNotFoundError: No module named 'app.routers.solutions'`

---

## Task 2: AI-Service — Implement Endpoint + Register Router

**Files:**
- Create: `apps/ai-service/app/routers/solutions.py`
- Modify: `apps/ai-service/main.py`

- [ ] **Step 2.1: Create `app/routers/solutions.py`**

```python
# apps/ai-service/app/routers/solutions.py
"""User-facing solution generation — returns AI draft without storing it."""
import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.client.backend_client import BackendClient
from app.dependencies import get_backend_client, get_llm_provider
from app.providers.llm.base import LLMProvider

logger = structlog.get_logger()

router = APIRouter(prefix="/generate-solution", tags=["solutions"])


class GenerateSolutionRequest(BaseModel):
    problem_id: str


class GenerateSolutionResponse(BaseModel):
    content: str


@router.post("", response_model=GenerateSolutionResponse)
async def generate_solution(
    body: GenerateSolutionRequest,
    backend_client: BackendClient = Depends(get_backend_client),
    llm: LLMProvider = Depends(get_llm_provider),
) -> GenerateSolutionResponse:
    """Generate an AI solution draft for a problem.

    User-facing — no SERVICE_TOKEN required. Returns draft only;
    the user edits and submits via POST /solutions (backend).
    """
    log = logger.bind(problem_id=body.problem_id)
    problem = await backend_client.get_by_id(body.problem_id)
    if problem is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Problem {body.problem_id} not found",
        )
    title = problem.get("title", "")
    description = problem.get("description") or ""
    content = await llm.generate_solution(title, description)
    log.info("ai_draft_generated")
    return GenerateSolutionResponse(content=content)
```

- [ ] **Step 2.2: Register the router in `main.py`**

In `main.py`, add `solutions` to the import line and add `app.include_router(solutions.router)`.

Find this block in `main.py`:
```python
from app.routers import clustering, embeddings, health, hooks, similarity, translate, websocket
```
Change to:
```python
from app.routers import clustering, embeddings, health, hooks, similarity, solutions, translate, websocket
```

Find this block at the bottom:
```python
app.include_router(health.router)
app.include_router(similarity.router)
app.include_router(translate.router)
app.include_router(hooks.router)
app.include_router(clustering.router)
app.include_router(embeddings.router)
app.include_router(websocket.router)
```
Change to:
```python
app.include_router(health.router)
app.include_router(similarity.router)
app.include_router(translate.router)
app.include_router(solutions.router)
app.include_router(hooks.router)
app.include_router(clustering.router)
app.include_router(embeddings.router)
app.include_router(websocket.router)
```

- [ ] **Step 2.3: Run all unit tests — all must pass**

```bash
cd apps/ai-service
make test-unit
```

Expected: all tests pass including the 3 new ones in `test_solutions.py`. Total count increases by 3.

- [ ] **Step 2.4: Commit**

```bash
cd apps/ai-service
git add app/routers/solutions.py main.py tests/unit/routers/test_solutions.py
git commit -m "feat(ai-service): POST /generate-solution — user-triggered AI draft (Issue #26)"
```

---

## Task 3: nginx — Rate-Limit Zone + Location

**Files:**
- Modify: `infrastructure/host/etc/nginx/nginx.conf`
- Modify: `infrastructure/host/etc/nginx/nginx.dev.conf`

- [ ] **Step 3.1: Add rate-limit zone to `nginx.conf`**

Find this line in `nginx.conf` (around line 35):
```nginx
limit_req_zone $binary_remote_addr zone=translate:10m rate=5r/m;
```
Add a new line directly after it:
```nginx
limit_req_zone $binary_remote_addr zone=generate_solution:10m rate=5r/m;
```

- [ ] **Step 3.2: Add `/api/generate-solution` location to `nginx.conf`**

Find the `/api/translate` location block in `nginx.conf`:
```nginx
        # AI-Service — Übersetzung (strikteres Rate Limiting als allgemeine API)
        location /api/translate {
            limit_req zone=translate burst=2 nodelay;
            set $upstream_ai ai-service:8000;
            rewrite ^/api/(.*)$ /$1 break;
            proxy_pass         http://$upstream_ai$uri$is_args$args;
            proxy_http_version 1.1;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }
```
Add a new location block directly after it:
```nginx
        # AI-Service — KI-Lösungsentwurf (teurer LLM-Call, enger Rate Limit)
        location /api/generate-solution {
            limit_req zone=generate_solution burst=1 nodelay;
            set $upstream_ai ai-service:8000;
            rewrite ^/api/(.*)$ /$1 break;
            proxy_pass         http://$upstream_ai$uri$is_args$args;
            proxy_http_version 1.1;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }
```

- [ ] **Step 3.3: Add location to `nginx.dev.conf` (no rate-limit in dev)**

Find the `/api/translate` location in `nginx.dev.conf`:
```nginx
        location /api/translate {
            set $upstream_ai host.docker.internal:8000;
            rewrite ^/api/(.*)$ /$1 break;
            proxy_pass         http://$upstream_ai$uri$is_args$args;
            proxy_http_version 1.1;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }
```
Add directly after it:
```nginx
        location /api/generate-solution {
            set $upstream_ai host.docker.internal:8000;
            rewrite ^/api/(.*)$ /$1 break;
            proxy_pass         http://$upstream_ai$uri$is_args$args;
            proxy_http_version 1.1;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }
```

- [ ] **Step 3.4: Validate nginx config syntax**

```bash
# From repo root — nginx.conf is not directly testable without docker, do a visual check:
grep -n "generate_solution" infrastructure/host/etc/nginx/nginx.conf
grep -n "generate_solution" infrastructure/host/etc/nginx/nginx.dev.conf
```

Expected: two matches each — one for zone declaration, one for location.

- [ ] **Step 3.5: Commit**

```bash
cd /Volumes/DevLocal/DevWeb/Production/DecisionMap
git add infrastructure/host/etc/nginx/nginx.conf infrastructure/host/etc/nginx/nginx.dev.conf
git commit -m "feat(nginx): rate-limit zone + location for /api/generate-solution"
```

---

## Task 4: Frontend — Failing Tests for `useAiDraft`

**Files:**
- Create: `apps/frontend/tests/composables/useAiDraft.spec.ts`

- [ ] **Step 4.1: Create the test file**

```typescript
// apps/frontend/tests/composables/useAiDraft.spec.ts
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

vi.mock('consola', () => ({
  consola: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}))

describe('useAiDraft', () => {
  const fetchMock = vi.fn()

  beforeEach(async () => {
    vi.resetModules()
    vi.stubGlobal('$fetch', fetchMock)
    fetchMock.mockReset()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('generate() calls /generate-solution with problem_id and sets draft', async () => {
    fetchMock.mockResolvedValue({ content: '## AI Solution\n\nDraft here.' })
    const { useAiDraft } = await import('~/composables/useAiDraft')
    const { draft, loading, error, generate } = useAiDraft('prob-123')

    await generate()

    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining('/generate-solution'),
      expect.objectContaining({ method: 'POST', body: { problem_id: 'prob-123' } }),
    )
    expect(draft.value).toBe('## AI Solution\n\nDraft here.')
    expect(loading.value).toBe(false)
    expect(error.value).toBe('')
  })

  it('loading is true during generation, false after', async () => {
    let resolveCall!: () => void
    fetchMock.mockReturnValue(new Promise<{ content: string }>((res) => {
      resolveCall = () => res({ content: 'draft' })
    }))
    const { useAiDraft } = await import('~/composables/useAiDraft')
    const { loading, generate } = useAiDraft('prob-123')

    const p = generate()
    expect(loading.value).toBe(true)
    resolveCall()
    await p
    expect(loading.value).toBe(false)
  })

  it('sets error and clears draft on API failure', async () => {
    fetchMock.mockRejectedValue(new Error('Network error'))
    const { useAiDraft } = await import('~/composables/useAiDraft')
    const { draft, error, generate } = useAiDraft('prob-123')

    await generate()

    expect(error.value).toBe('aiDraftError')
    expect(draft.value).toBe('')
  })

  it('resets error at start of each generate() call', async () => {
    fetchMock.mockRejectedValueOnce(new Error('fail'))
    fetchMock.mockResolvedValueOnce({ content: 'retry worked' })
    const { useAiDraft } = await import('~/composables/useAiDraft')
    const { error, generate } = useAiDraft('prob-123')

    await generate()              // first call fails
    expect(error.value).toBe('aiDraftError')

    await generate()              // second call succeeds
    expect(error.value).toBe('')  // error is cleared
  })
})
```

- [ ] **Step 4.2: Run tests — expect import error**

```bash
cd apps/frontend
npm run test -- tests/composables/useAiDraft.spec.ts 2>&1 | grep -E "FAIL|ERROR|Cannot find"
```

Expected: `Cannot find module '~/composables/useAiDraft'`

---

## Task 5: Frontend — Implement `useAiDraft.ts`

**Files:**
- Create: `apps/frontend/composables/useAiDraft.ts`

- [ ] **Step 5.1: Create the composable**

```typescript
// apps/frontend/composables/useAiDraft.ts
import { ref } from 'vue'
import type { Ref } from 'vue'
import { consola } from 'consola'

export function useAiDraft(problemId: string): {
  draft: Ref<string>
  loading: Ref<boolean>
  error: Ref<string>
  generate: () => Promise<void>
} {
  const config = useRuntimeConfig()
  const aiServiceUrl = config.public.aiServiceUrl as string

  const draft = ref<string>('')
  const loading = ref<boolean>(false)
  const error = ref<string>('')

  async function generateFake(): Promise<void> {
    loading.value = true
    error.value = ''
    await new Promise((resolve) => setTimeout(resolve, 800))
    draft.value = '## Recommendation: Phased AI Governance Framework\n\n**Phase 1 (4 weeks):** Designate an AI officer and create an initial catalogue of permitted AI tools.\n\n**Phase 2 (8 weeks):** Use ISO 42001 as a structural reference — certification not required. Quarterly reviews with IT, Legal, and one business unit.\n\n**Implementation:** Define a pilot project with a narrowly scoped use-case before broader rollout.'
    loading.value = false
  }

  async function generateReal(): Promise<void> {
    loading.value = true
    error.value = ''
    try {
      const response = await $fetch<{ content: string }>(`${aiServiceUrl}/generate-solution`, {
        method: 'POST',
        body: { problem_id: problemId },
      })
      draft.value = response.content
    } catch (err) {
      consola.error('useAiDraft: generation failed', { err })
      error.value = 'aiDraftError'
    } finally {
      loading.value = false
    }
  }

  const generate = config.public.useFakeData ? generateFake : generateReal

  return { draft, loading, error, generate }
}
```

- [ ] **Step 5.2: Run the 4 useAiDraft tests — all must pass**

```bash
cd apps/frontend
npm run test -- tests/composables/useAiDraft.spec.ts
```

Expected: 4 tests pass.

- [ ] **Step 5.3: Run full test suite to check for regressions**

```bash
cd apps/frontend
npm run test
```

Expected: all tests pass.

- [ ] **Step 5.4: Commit**

```bash
cd apps/frontend
git add composables/useAiDraft.ts tests/composables/useAiDraft.spec.ts
git commit -m "feat(frontend): useAiDraft composable — user-triggered AI solution draft (Issue #26)"
```

---

## Task 6: Frontend — Auto-Grow Textarea + AI Draft Button + i18n

**Files:**
- Modify: `apps/frontend/components/SolutionForm.vue`
- Modify: `apps/frontend/i18n/locales/en.json`

- [ ] **Step 6.1: Add i18n keys to `en.json`**

In `i18n/locales/en.json`, find the `"solution"` block. Add these keys to it (alongside the existing ones):

```json
"aiDraft": "AI Draft",
"aiDraftLoading": "Generating…",
"aiDraftRetry": "↺ Regenerate",
"aiDraftError": "Draft generation failed. Try again."
```

The `solution.contentEnLabel` key already exists — do not duplicate it.

- [ ] **Step 6.2: Update the script section of `SolutionForm.vue`**

Replace the entire `<script setup lang="ts">` block with:

```typescript
<script setup lang="ts">
import { ref, computed, watch, nextTick, onMounted } from 'vue'
import { z } from 'zod'
import { consola } from 'consola'
import { useSolutions } from '~/composables/useSolutions'
import { useTranslation } from '~/composables/useTranslation'
import { useAiDraft } from '~/composables/useAiDraft'
import { useToast } from '~/composables/useToast'

const props = defineProps<{
  problemId: string
  problemTitle: string
}>()

const emit = defineEmits<{
  (event: 'submitted' | 'cancel'): void
}>()

const { t } = useI18n()

const { createSolution } = useSolutions()
const { looksLikeEnglish, translateToEnglish } = useTranslation()
const { show: showToast } = useToast()
const { draft: aiDraft, loading: aiLoading, error: aiError, generate: generateDraft } = useAiDraft(props.problemId)

// ─── Form State ───────────────────────────────────────────────────────────────

const content = ref<string>('')
const contentEn = ref<string>('')
const honeypot = ref<string>('')
const submitting = ref<boolean>(false)
const translating = ref<boolean>(false)
const showEnglishFields = ref<boolean>(false)
const isCollapsed = ref<boolean>(false)
const translateError = ref<string>('')
const validationErrors = ref<Record<string, string>>({})
const textareaRef = ref<HTMLTextAreaElement | null>(null)

const SolutionSchema = z.object({
  content: z.string().min(20).max(2000),
})

const isEnglish = computed<boolean>(() => looksLikeEnglish(content.value))
const charCount = computed<number>(() => content.value.length)

// ─── Auto-grow ────────────────────────────────────────────────────────────────

function autoResize(): void {
  const el = textareaRef.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = `${el.scrollHeight}px`
}

watch(content, () => nextTick(autoResize))
onMounted(() => nextTick(autoResize))

// ─── Translation detection ────────────────────────────────────────────────────

watch(content, (newContent) => {
  if (looksLikeEnglish(newContent) && newContent.length >= 20) {
    contentEn.value = newContent
    showEnglishFields.value = true
    isCollapsed.value = false
  } else {
    contentEn.value = ''
    showEnglishFields.value = false
    isCollapsed.value = false
  }
})

// ─── AI Draft ────────────────────────────────────────────────────────────────

async function handleGenerateDraft(): Promise<void> {
  await generateDraft()
  if (aiDraft.value) {
    content.value = aiDraft.value
    await nextTick(autoResize)
  }
}

// ─── Translation ──────────────────────────────────────────────────────────────

async function handleTranslate(): Promise<void> {
  if (content.value.length < 20) return
  translating.value = true
  translateError.value = ''
  try {
    contentEn.value = await translateToEnglish(content.value)
    showEnglishFields.value = true
    isCollapsed.value = false
  } catch {
    translateError.value = 'translation_failed'
  } finally {
    translating.value = false
  }
}

// ─── Submit ───────────────────────────────────────────────────────────────────

async function handleSubmit(): Promise<void> {
  validationErrors.value = {}

  const result = SolutionSchema.safeParse({ content: content.value })
  if (!result.success) {
    const fieldErrors = result.error.flatten().fieldErrors
    if (fieldErrors['content']?.[0]) {
      validationErrors.value['content'] = t('solution.validation.contentMin')
    }
    return
  }

  submitting.value = true

  if (!isEnglish.value && !contentEn.value) {
    try {
      contentEn.value = await translateToEnglish(content.value)
      showEnglishFields.value = true
    } catch {
      consola.warn('SolutionForm: auto-translation failed, submitting original text')
    }
  }

  const englishContent = contentEn.value.trim() || content.value
  const originalTranslations = contentEn.value && !isEnglish.value
    ? { de: content.value }
    : undefined

  try {
    await createSolution({
      content: englishContent,
      originalTranslations,
      problemId: props.problemId,
      honeypot: honeypot.value,
    })
    showToast(t('solution.submitSuccess'))
    content.value = ''
    contentEn.value = ''
    showEnglishFields.value = false
    isCollapsed.value = false
    translateError.value = ''
    emit('submitted')
  } catch (submitError) {
    consola.error('SolutionForm: submit failed', { error: submitError })
    showToast(t('solution.submitError'), 'error')
    submitting.value = false
  }
}
</script>
```

- [ ] **Step 6.3: Update the template — add AI button + auto-grow textarea**

Replace the content textarea section in the `<template>` block. Find this:

```html
    <!-- Content textarea -->
    <div>
      <label class="block text-xs font-medium text-th-text-muted mb-1" for="solution-content">
        {{ t('solution.contentLabel') }}
      </label>
      <textarea
        id="solution-content"
        v-model="content"
        rows="5"
        maxlength="2000"
        :placeholder="t('solution.contentPlaceholder')"
        class="w-full px-3 py-2 bg-th-input-bg text-th-text border border-th-input-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand resize-none"
        :class="{ 'border-red-400': validationErrors['content'] }"
      />
```

Replace with:

```html
    <!-- Content textarea -->
    <div>
      <!-- Label row: field label left, AI draft button right -->
      <div class="flex items-center justify-between mb-1">
        <label class="text-xs font-medium text-th-text-muted" for="solution-content">
          {{ t('solution.contentLabel') }}
        </label>
        <button
          type="button"
          :disabled="aiLoading"
          class="flex items-center gap-1 text-xs font-medium text-brand hover:text-brand-dark transition-colors disabled:opacity-50"
          @click="handleGenerateDraft"
        >
          <svg v-if="aiLoading" class="w-3 h-3 animate-spin" viewBox="0 0 24 24" fill="none">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <span v-if="aiLoading">{{ t('solution.aiDraftLoading') }}</span>
          <span v-else-if="aiDraft">{{ t('solution.aiDraftRetry') }}</span>
          <span v-else>✦ {{ t('solution.aiDraft') }}</span>
        </button>
      </div>
      <textarea
        id="solution-content"
        ref="textareaRef"
        v-model="content"
        maxlength="2000"
        :placeholder="t('solution.contentPlaceholder')"
        class="w-full px-3 py-2 bg-th-input-bg text-th-text border border-th-input-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand resize-none overflow-hidden min-h-[80px]"
        :class="{ 'border-red-400': validationErrors['content'] }"
        @input="autoResize"
      />
```

Also add the AI error display right after the `charCount` span row. Find:

```html
      <div class="flex items-center justify-between mt-1">
        <span v-if="validationErrors['content']" class="text-xs text-red-500">
          {{ validationErrors['content'] }}
        </span>
        <span v-else class="text-xs text-th-text-faint">
          {{ t('solution.contentHint') }}
        </span>
        <span class="text-xs text-th-text-faint">{{ charCount }}/2000</span>
      </div>
    </div>
```

Replace with:

```html
      <div class="flex items-center justify-between mt-1">
        <span v-if="validationErrors['content']" class="text-xs text-red-500">
          {{ validationErrors['content'] }}
        </span>
        <span v-else-if="aiError" class="text-xs text-red-500 dark:text-red-400">
          {{ t('solution.aiDraftError') }}
        </span>
        <span v-else class="text-xs text-th-text-faint">
          {{ t('solution.contentHint') }}
        </span>
        <span class="text-xs text-th-text-faint">{{ charCount }}/2000</span>
      </div>
    </div>
```

- [ ] **Step 6.4: Run frontend tests**

```bash
cd apps/frontend
npm run test
```

Expected: all tests pass.

- [ ] **Step 6.5: Commit**

```bash
cd apps/frontend
git add components/SolutionForm.vue i18n/locales/en.json
git commit -m "feat(frontend): SolutionForm — auto-grow textarea + AI draft button (Issue #26)"
```

---

## Task 7: Frontend — Translation Collapsible

**Files:**
- Modify: `apps/frontend/components/SolutionForm.vue`

Replace the entire EN section in the template (everything from `<!-- Translate button -->` to the closing `</div>` of the EN textarea). Find this block:

```html
    <!-- Translate button (non-English) -->
    <div v-if="!isEnglish && content.length >= 20 && !showEnglishFields" class="flex flex-col gap-1.5">
      <div class="flex items-center gap-2">
        <button
          type="button"
          :disabled="translating"
          class="px-3 py-1.5 text-sm font-medium text-brand border border-brand rounded-lg hover:bg-brand hover:text-white transition-colors disabled:opacity-60"
          @click="handleTranslate"
        >
          <span v-if="translating">{{ t('form.translating') }}</span>
          <span v-else>{{ t('form.translateButton') }}</span>
        </button>
      </div>
      <p v-if="translateError" class="text-xs text-red-600 dark:text-red-400">
        {{ t('form.translateError') }}
      </p>
    </div>

    <!-- English detected badge -->
    <div v-if="isEnglish && content.length >= 20" class="text-xs text-green-600 dark:text-green-400">
      {{ t('form.englishDetected') }}
    </div>

    <!-- English version -->
    <div v-if="showEnglishFields && !isEnglish">
      <label class="block text-xs font-medium text-th-text-muted mb-1" for="solution-content-en">
        {{ t('solution.contentEnLabel') }}
      </label>
      <textarea
        id="solution-content-en"
        v-model="contentEn"
        rows="4"
        maxlength="2000"
        :placeholder="t('solution.contentEnPlaceholder')"
        class="w-full px-3 py-2 bg-th-input-bg text-th-text border border-th-input-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand resize-none"
        :class="{ 'border-red-400': validationErrors['contentEn'] }"
      />
      <span v-if="validationErrors['contentEn']" class="text-xs text-red-500 mt-1">
        {{ validationErrors['contentEn'] }}
      </span>
    </div>
```

Replace with this collapsible EN section:

```html
    <!-- English version — collapsible (mirrors EnglishTranslationSection pattern) -->
    <div
      v-if="content.length >= 20"
      :class="[
        'rounded-lg border p-3 space-y-2',
        isEnglish
          ? 'border-green-200 bg-green-50/50 dark:border-green-800 dark:bg-green-950/20'
          : 'border-blue-200 bg-blue-50/50 dark:border-blue-800 dark:bg-blue-950/20',
      ]"
    >
      <!-- Header row -->
      <div class="flex items-center justify-between gap-2">
        <span
          class="flex items-center gap-1 cursor-pointer select-none"
          :class="showEnglishFields ? 'cursor-pointer' : ''"
          @click="showEnglishFields && (isCollapsed = !isCollapsed)"
        >
          <span
            class="text-xs font-semibold uppercase tracking-wide"
            :class="isEnglish ? 'text-green-700 dark:text-green-400' : 'text-blue-700 dark:text-blue-400'"
          >
            {{ t('form.englishVersion') }}
          </span>
          <!-- Chevron — only shown when EN field is visible -->
          <svg
            v-if="showEnglishFields"
            class="w-3 h-3 transition-transform duration-200 text-th-text-faint ml-0.5"
            :class="isCollapsed ? '' : 'rotate-180'"
            viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
          </svg>
        </span>

        <!-- Translate button (non-English, no translation yet) -->
        <button
          v-if="!isEnglish"
          type="button"
          :disabled="translating"
          class="flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-md transition-colors disabled:opacity-60 shrink-0"
          @click="handleTranslate"
        >
          <svg v-if="translating" class="w-3 h-3 animate-spin" viewBox="0 0 24 24" fill="none">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <svg v-else class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <circle cx="12" cy="12" r="10" />
            <path d="M2 12h20M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20" />
          </svg>
          {{ translating ? t('form.translating') : t('form.translateButton') }}
        </button>

        <!-- English auto-detected badge -->
        <span
          v-else
          class="inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded-full bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
        >
          <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
          </svg>
          {{ t('form.englishDetected') }}
        </span>
      </div>

      <!-- Translation error -->
      <p v-if="translateError" class="text-xs text-red-600 dark:text-red-400">
        {{ t('form.translateError') }}
      </p>

      <!-- Collapsed preview: first 60 chars of EN content -->
      <div
        v-if="showEnglishFields && isCollapsed"
        class="text-xs text-th-text-muted truncate px-0.5 cursor-pointer"
        @click="isCollapsed = false"
      >
        {{ contentEn.slice(0, 60) || '—' }}
      </div>

      <!-- EN textarea: shown after translation or auto-detected English -->
      <div v-if="showEnglishFields && !isCollapsed">
        <label
          class="block text-xs font-medium mb-1"
          :class="isEnglish ? 'text-green-700 dark:text-green-400' : 'text-blue-700 dark:text-blue-400'"
          for="solution-content-en"
        >
          {{ t('solution.contentEnLabel') }}
        </label>
        <textarea
          id="solution-content-en"
          v-model="contentEn"
          rows="3"
          maxlength="2000"
          :placeholder="translating ? t('form.translating') : t('solution.contentEnPlaceholder')"
          :disabled="translating"
          class="w-full px-3 py-1.5 border border-th-border-subtle rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand focus:border-transparent resize-none disabled:opacity-50 bg-th-surface transition-colors"
        />
      </div>
    </div>
```

- [ ] **Step 7.1: Run frontend tests**

```bash
cd apps/frontend
npm run test
```

Expected: all tests pass.

- [ ] **Step 7.2: Commit**

```bash
cd apps/frontend
git add components/SolutionForm.vue
git commit -m "feat(frontend): SolutionForm — translation collapsible section (Issue #26)"
```

---

## Self-Review Checklist

- [x] **`POST /generate-solution`** — Task 1+2: endpoint + 3 tests ✓
- [x] **nginx rate-limit** — Task 3: zone + location in both conf files ✓
- [x] **`useAiDraft` composable** — Task 4+5: 4 tests + implementation ✓
- [x] **Auto-grow textarea** — Task 6: `textareaRef` + `autoResize` + `onMounted` + `watch` ✓
- [x] **AI draft button** — Task 6: inline label row, 3 states (idle / loading / retry) ✓
- [x] **AI draft error** — Task 6: shown below textarea ✓
- [x] **i18n keys** — Task 6: `aiDraft`, `aiDraftLoading`, `aiDraftRetry`, `aiDraftError` ✓
- [x] **Translation collapsible** — Task 7: card, chevron, collapsed preview, translate button, detected badge ✓
- [x] **Fake data support** — `useAiDraft.generateFake()` returns hardcoded draft after 800ms ✓
- [x] **`solution.contentEnPlaceholder`** — already exists in `en.json` as `"Edit if needed"` ✓
