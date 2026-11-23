# STT dual-job providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split Speech-to-text platform settings into independent Audio Transcribe and Entity/Flowchart generation assignees, add Cursor as a generation-only provider with a live model list, and stop one vendor from killing the other job.

**Architecture:** Replace `enabled` with `transcribe_active` / `generation_active` (partial unique indexes). Runtime uses `ProviderSettings.active_for(job)`. Cursor is one new file under `app/services/speech_to_text/providers/` using Cloud Agents HTTP for `#chat` and `GET /v1/models` for health + model cache.

**Tech Stack:** Rails 8.1.2, Trailblazer activities, Reform, ViewComponent, Tailwind, RSpec, OutboundHttp/Faraday.

## Global Constraints

- Grok 4.6 only; omit `model` or pass `inherit` on Task launches.
- I18n en + zh-CN for every new user-facing string; English value byte-identical to what would have been hard-coded.
- No hard-coded UI copy.
- Platform settings remain owner-only under customer `81721200`.
- No `customer_id` on `speech_to_text_provider_settings` (platform-wide, same as today).
- No backward-compatibility shims: drop `enabled`; update every call site.
- Controllers/Puma must not construct vendor HTTP clients; Cursor model fetch lives in `TestConnection` (job).
- Do not git commit (user has not asked).
- TDD: failing spec first for new behavior.
- Spec: `docs/stt-dual-job-providers-design.md`

---

### Task 1: Backend — schema, model, activities, Cursor provider

Do not edit views, components, routes, or controllers.

- [ ] Write failing model/activity/provider specs for dual jobs + Cursor
- [ ] Run those specs; confirm they fail on missing API
- [ ] Implement migration, model, activities, Cursor provider, I18n keys used by backend errors
- [ ] Run targeted specs; they pass
- [ ] Do not commit

### Task 2: Security — controller wiring

Do not edit models, migrations, components, or activities.

- [ ] Failing request spec: PATCH can assign Cursor to generation without disabling AWS transcribe
- [ ] Implement controller param/permit + assignee keys; dashboard uses generation assignee
- [ ] Targeted request specs pass
- [ ] Do not commit

### Task 3: Frontend — settings UI + dictate/assistant gating

Do not edit models, migrations, routes, or controllers. Follow UX doc `docs/stt-dual-job-providers-ux.md` when present.

- [ ] Failing component spec: two job group headings; Cursor generation select; AWS generation “not supported”
- [ ] Implement ERB/component + locales
- [ ] Component specs pass
- [ ] Do not commit

### Task 4: QA — isolation, auth, stale specs

Specs only.

- [ ] Grep `enabled` / `.active` on STT provider settings; rewrite stale specs
- [ ] Auth matrix unchanged; mixed assignees work
- [ ] Do not commit

### Task 5: Release

- [ ] Run targeted STT + dashboard + dictate specs
- [ ] Do not commit
