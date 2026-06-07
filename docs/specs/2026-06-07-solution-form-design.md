# Solution Form: Translation Collapsible + AI Draft Generation

**Date:** 2026-06-07
**Status:** Approved
**Repos:** `apps/frontend`, `apps/ai-service`, `infrastructure`

---

## Problem

Two gaps in `SolutionForm.vue`:

1. **Translation UI** — The EN translation section is always fully expanded, taking up excessive panel space. The Problem Form uses a collapsible `EnglishTranslationSection` component; the Solution Form does not.

2. **AI Draft Generation** — Issue #26 specifies a user-triggered "Generate AI Draft" flow. The backend auto-generation was removed (2026-06-07), but the frontend entry point and AI-Service endpoint are missing entirely.

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Translation collapsible | Inline in `SolutionForm.vue`, not via `EnglishTranslationSection` | Solutions have one content field; `EnglishTranslationSection` is built for title+description pairs. Extending it with a mode flag adds unnecessary complexity. |
| AI draft composable | New `useAiDraft(problemId)` | Keeps `SolutionForm` slim; testable in isolation |
| AI endpoint location | New `app/routers/solutions.py` in AI-Service | Mirrors `translate.py` pattern; no `SERVICE_TOKEN` required (user-facing) |
| Textarea sizing | Auto-grow (B1) | Avoids "small box" feeling; draft may be 400–1200 chars; panel scrolls naturally |
| Rate limiting | 5r/min per IP, burst=1 | LLM call is expensive; tighter than `/translate` (burst=2) |

---

## Architecture

```
SolutionForm.vue
  ├── useAiDraft(problemId)       → POST /api/generate-solution (AI-Service)
  ├── useTranslation()            → POST /api/translate (AI-Service, existing)
  └── useSolutions().createSolution → POST /solutions (Backend, existing)

nginx
  └── location /api/generate-solution  [rate: 5r/min, burst=1]  → AI-Service :8000
```

---

## Part 1: AI-Service — `POST /generate-solution`

**New file:** `app/routers/solutions.py`

### Request / Response

```python
class GenerateSolutionRequest(BaseModel):
    problem_id: str

class GenerateSolutionResponse(BaseModel):
    content: str  # Markdown-formatted AI draft
```

### Endpoint behaviour

```
POST /generate-solution
1. Fetch problem from backend via BackendClient.get_by_id(problem_id)
2. 404 if problem not found or deleted
3. Call llm.generate_solution(title, description)
4. Return { content: "<markdown>" }
```

- **No `verify_service_token`** — this is user-facing (same as `/translate`)
- **No storage** — draft is returned only; user submits separately via `POST /solutions`
- `description` falls back to empty string if null (same pattern as `hooks.py`)

### Router registration

`main.py`: include `solutions_router` alongside `translate_router`.

### Tests

- `tests/unit/routers/test_solutions.py`
  - `test_generate_solution_returns_content` — LLM returns text → 200 with content
  - `test_generate_solution_404_when_problem_not_found` — backend returns None → 404
  - `test_generate_solution_propagates_llm_content` — content is passed through unmodified

---

## Part 2: nginx — Rate Limit

**File:** `infrastructure/host/etc/nginx/nginx.conf` (and `nginx.dev.conf`)

```nginx
limit_req_zone $binary_remote_addr zone=generate_solution:10m rate=5r/m;

location /api/generate-solution {
    limit_req zone=generate_solution burst=1 nodelay;
    # same proxy_pass pattern as /api/translate
    ...
}
```

Also add to `nginx.dev.conf` (without rate limiting in dev, or with relaxed limits).

---

## Part 3: Frontend — `SolutionForm.vue`

### 3a. New composable: `useAiDraft`

**File:** `composables/useAiDraft.ts`

```typescript
// Usage in SolutionForm: const { draft, loading, error, generate } = useAiDraft(props.problemId)

// State
const draft = ref<string>('')
const loading = ref<boolean>(false)
const error = ref<string>('')

// Action — problemId captured from constructor arg, not passed per-call
async function generate(): Promise<void>
  // POST /api/generate-solution  { problem_id }
  // On success: draft.value = response.content
  // On error:   error.value = 'aiDraftError'
  // Resets error at start of each call

return { draft, loading, error, generate }
```

- `USE_FAKE_DATA=true` → returns a hardcoded Markdown string after 800ms delay (no real API call)
- Error is reset on each new `generate()` call

### 3b. `SolutionForm.vue` changes

**Auto-grow textarea:**
```vue
<textarea
  ref="textareaRef"
  v-model="content"
  class="... min-h-[80px] resize-none overflow-hidden"
  @input="autoResize"
/>
```
```typescript
const textareaRef = ref<HTMLTextAreaElement | null>(null)

function autoResize(): void {
  const el = textareaRef.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = `${el.scrollHeight}px`
}

watch(content, () => nextTick(autoResize))
onMounted(() => nextTick(autoResize))
```

**AI Draft button (inline next to field label):**
```vue
<div class="flex items-center justify-between mb-1">
  <label ...>{{ t('solution.contentLabel') }}</label>
  <button type="button" :disabled="aiLoading" @click="handleGenerateDraft">
    <span v-if="aiLoading">{{ t('solution.aiDraftLoading') }}</span>
    <span v-else-if="draft">{{ t('solution.aiDraftRetry') }}</span>
    <span v-else>✦ {{ t('solution.aiDraft') }}</span>
  </button>
</div>
```

When draft is loaded → `content.value = draft.value` → textarea auto-resizes → translation detection runs via existing `watch(content)`.

**Translation collapsible (inline, mirrors `EnglishTranslationSection` visual style):**

- Replaces current always-visible raw `<textarea>` for `contentEn`
- Collapsible: `isCollapsed` ref, chevron icon, click to toggle
- Collapsed state shows first 60 chars of `contentEn` as preview
- Card style: `rounded-lg border p-3` with blue tint (non-English) or green tint (auto-detected)
- Header: "English Version" label + ℹ info icon + chevron + Translate button / "English detected" badge
- Expanded: single `<textarea>` for `contentEn` (rows=3)
- Auto-expands when translation completes (same logic as `EnglishTranslationSection`: `watch(showEnglishFields)`)

**AI Draft error display:**
```vue
<p v-if="aiError" class="text-xs text-red-600 dark:text-red-400 mt-1">
  {{ t('solution.aiDraftError') }}
</p>
```

### 3c. New i18n keys (`locales/en.json`)

```json
"solution": {
  "aiDraft": "AI Draft",
  "aiDraftLoading": "Generating…",
  "aiDraftRetry": "↺ Regenerate",
  "aiDraftError": "Draft generation failed. Try again.",
  "contentEnLabel": "English version",
  "contentEnPlaceholder": "English translation of your solution approach"
}
```

---

## Data Flow: Full Submit with AI Draft + Translation

```
1. User clicks "✦ AI Draft"
   → POST /api/generate-solution { problem_id }
   → content = AI markdown text
   → textarea auto-grows

2. User edits content (now in German, e.g.)
   → watch(content) fires → looksLikeEnglish = false
   → Translation section appears (collapsed, translate button visible)

3. User clicks "Translate"
   → POST /api/translate { text: content, target_lang: "en" }
   → contentEn = translated text
   → Translation section auto-expands

4. User clicks "Einreichen"
   → auto-translate runs if contentEn still empty
   → POST /solutions {
       content: contentEn || content,
       originalTranslations: { de: content },  // if translated
       problemId,
       honeypot
     }
```

---

## Out of Scope

- Markdown preview in the solution textarea (separate feature)
- Auth requirement for draft generation (anonymous users can generate drafts; moderation handles spam on submit)
- Caching of generated drafts

---

## Files Changed

| Repo | File | Change |
|---|---|---|
| `ai-service` | `app/routers/solutions.py` | New — `POST /generate-solution` |
| `ai-service` | `main.py` | Register `solutions_router` |
| `ai-service` | `tests/unit/routers/test_solutions.py` | New — 3 unit tests |
| `infrastructure` | `host/etc/nginx/nginx.conf` | Add `generate_solution` zone + location |
| `infrastructure` | `host/etc/nginx/nginx.dev.conf` | Add location (no rate limit in dev) |
| `frontend` | `composables/useAiDraft.ts` | New — generate draft composable |
| `frontend` | `components/SolutionForm.vue` | Auto-grow + AI draft button + translation collapsible |
| `frontend` | `locales/en.json` | New i18n keys |
