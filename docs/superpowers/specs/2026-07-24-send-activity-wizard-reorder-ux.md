# UX Spec: Send Activity Wizard Reorder (who → what → when → review)

**Date:** 2026-07-24  
**Status:** ready for frontend  
**Audience:** `admin` / `owner` (admin module surface)  
**Change type:** Reorder + rename only — **identical visual chrome** to today’s wizard

---

## Figma alignment

| Item | Value |
|---|---|
| Intent | Align with existing admin multi-step wizard chrome (progress nav + `card` + Continue/Back). No new visual language. |
| Figma MCP | **Blocked in this agent environment** — `plugin-figma-figma` returned `needsAuth`; interactive `mcp_auth` is desktop-only. |
| Visual source of truth (until Figma frame exists) | Live implementation: `Emails::SendActivityBuilderComponent` + partials under `app/views/admin/modules/emails/send_activities/_wizard_step_*.html.erb` |
| Figma frame (to capture after auth) | Create frame set **“Send Activity Wizard — reordered”** with four states (Audience / Content / Schedule / Review) cloned from current wizard; rename progress label Setup → Schedule; move Name onto Audience. Node ID TBD after capture. |
| Placeholder reference | `figma: pending-auth — implement against live wizard chrome + this doc` |

**Frontend rule:** Do not invent spacing, colors, typography, or button styles. Reuse existing Tailwind tokens (`text-text-*`, `text-primary`, `border-border`, `card`, `btn btn-primary`, `btn btn-secondary`, `form-label`, `input-field`, `text-heading`, `text-body-sm`).

---

## 1. Surface inventory

| Surface | Nav area | URL |
|---|---|---|
| New Send Activity wizard | **Modules** (`Modules / Email / Send Activity`) | `/:cid/admin/modules/emails/send_activities/new` (+ `?step=` on redirects) |
| Edit Send Activity wizard | **Modules** | `/:cid/admin/modules/emails/send_activities/:id/edit?step=` |

Out of scope: index, show, pause/cancel/send-now, Settings, Maintenance toggles, platform module settings.

---

## 2. Step model (approved)

```
STEPS = %w[audience content schedule review]
# mental model: who → what → when → review
```

| # | Key | Progress / card title (en) | Fields (editable) |
|---|---|---|---|
| 1 | `audience` | Audience | `name`, `email_list_id` |
| 2 | `content` | Content | `email_template_id` |
| 3 | `schedule` | Schedule *(renamed from Setup)* | `scheduled_at`, `timezone`, `recurrence_preset` |
| 4 | `review` | Review | none (read-only summary) |

**Removed step key:** `setup` — no longer in `STEPS`. Deep-linking `?step=setup` is an invalid step (existing invalid-step error path).

**Default step:** `audience` (new and when step param blank).

**I18n (frontend must add both locales):**

| Key | `en` (byte-identical to intended UI string) | Notes |
|---|---|---|
| `…wizard.steps.audience` | `Audience` | keep |
| `…wizard.steps.content` | `Content` | keep |
| `…wizard.steps.schedule` | `Schedule` | **new** (replaces `setup`) |
| `…wizard.steps.review` | `Review` | keep |
| `…wizard.steps.setup` | — | remove after callers updated |

Field labels reuse existing keys (`common.labels.name`, `form.list_label`, `form.template_label`, `form.schedule_label`, `common.labels.timezone`, `form.recurrence_label`).

Optional copy tweak (non-blocking): `new.subtitle` currently says “Choose a template and audience list to send.” — may stay as-is for this reorder; do not block on subtitle rewrite.

---

## 3. Layout spec per surface

Shared page chrome (unchanged):

```
[ Breadcrumbs: Modules › Email › Send Activity › New|Edit ]

New Send Activity / Edit Send Activity     ← text-heading
subtitle                                    ← text-body-sm

┌────────────────── max-w-4xl ──────────────────┐
│  (wizard component)                           │
└───────────────────────────────────────────────┘
```

Shared wizard chrome (unchanged structure):

```
[ Progress nav — horizontal ol, 4 steps ]
  completed → checkmark SVG + label (sm+)
  current   → number + text-primary + label
  upcoming  → number + muted + label
  connectors: after:border-b after:border-border (sm+)

[ Validation errors — shared/form_errors if any ]

┌────────────── card p-6 ──────────────┐
│  <h2> Step label </h2>               │
│  … step body …                       │
└──────────────────────────────────────┘

[ Back (btn-secondary) |          Continue/Create/Update (btn-primary) ]
  Back → GET same url?step=<previous>
  No Back on step 1 (empty spacer)
```

Primary CTA labels (unchanged behavior):

| Context | Non-review | Review |
|---|---|---|
| New (`method: post`) | Continue | Create |
| Edit (`method: patch`) | Continue | Update |

No Stimulus required for this reorder. No jump-to-step links on Review. Progress nav remains non-clickable (display-only), same as today.

---

### 3.1 Step 1 — Audience (`audience`)

**Purpose:** Who is this send for + what do we call it.

```
Progress: ① Audience  —  2 Content  —  3 Schedule  —  4 Review
          (current)

┌─ card ─────────────────────────────────────────┐
│  Audience                                      │
│                                                │
│  Name                                          │
│  [________________________________________]    │
│                                                │
│  List                                          │
│  [ — select list —                      ▾ ]    │
└────────────────────────────────────────────────┘

[          ]                         [ Continue ]
```

| Region | Data |
|---|---|
| Name | `Emails::SendActivities::SendActivity#name` |
| List | `email_list_id` ← `@lists` (`id`, `name`) |

**Empty / loading / error**

- Empty lists: select still renders with blank option; validation on Continue if required by model.
- Loading: none (server-rendered).
- Error: `shared/form_errors` above card; invalid fields keep standard `input-field` + model errors.

**Actions:** Continue (primary). No Back.

---

### 3.2 Step 2 — Content (`content`)

**Purpose:** What email to send.

```
Progress: ✓ Audience  —  ② Content  —  3 Schedule  —  4 Review

┌─ card ─────────────────────────────────────────┐
│  Content                                       │
│                                                │
│  Template                                      │
│  [ — select template —                  ▾ ]    │
└────────────────────────────────────────────────┘

[ Back ]                              [ Continue ]
```

| Region | Data |
|---|---|
| Template | `email_template_id` ← `@templates` |

**States:** same pattern as Audience (blank option, validation on Continue).

**Actions:** Back → `?step=audience`. Continue → persist + advance to `schedule`.

---

### 3.3 Step 3 — Schedule (`schedule`) *(was Setup)*

**Purpose:** When to send (and optional recurrence). **Name is no longer here.**

```
Progress: ✓ Audience  —  ✓ Content  —  ③ Schedule  —  4 Review

┌─ card ─────────────────────────────────────────┐
│  Schedule                                      │
│                                                │
│  Schedule (optional)     Timezone              │
│  [ datetime-local    ]   [ US zones / UTC ▾ ]  │
│  (grid: 1 col mobile / 2 col md+)              │
│                                                │
│  Recurrence (optional)                         │
│  [ None / Daily / Weekly / Monthly      ▾ ]    │
└────────────────────────────────────────────────┘

[ Back ]                              [ Continue ]
```

| Region | Data |
|---|---|
| Schedule | `scheduled_at` (wall clock in selected timezone) |
| Timezone | `timezone` |
| Recurrence | `recurrence_preset` → mapped to `recurrence_rule` server-side |

**Empty schedule:** blank datetime → Review shows “Send immediately” (`review.send_now`) — unchanged semantics.

**Actions:** Back → `?step=content`. Continue → `review`.

**Partial rename:** `_wizard_step_setup.html.erb` → `_wizard_step_schedule.html.erb` (fields minus `name`).

---

### 3.4 Step 4 — Review (`review`)

**Purpose:** Confirm before Create/Update. Read-only. **No inline edit. No jump links to prior steps.**

```
Progress: ✓ Audience  —  ✓ Content  —  ✓ Schedule  —  ④ Review

┌─ card ─────────────────────────────────────────┐
│  Review                                        │
│                                                │
│  Name        │  Spring Newsletter              │
│  List        │  Members – Active               │  ← who
│  Template    │  Welcome HTML                   │  ← what
│  Schedule    │  July 24, 2026 09:00 …          │  ← when
│              │  (or “Send immediately”)        │
│  Timezone    │  America/Los_Angeles            │
│  Recurrence  │  None                           │
└────────────────────────────────────────────────┘

[ Back ]                    [ Create ] / [ Update ]
```

**Review row order (aligned to who → what → when):**

1. Name  
2. List  
3. Template  
4. Schedule (`scheduled_at` or send-now copy)  
5. Timezone  
6. Recurrence  

*(Today’s review lists Template before List and Timezone before Schedule — reorder the `<dl>` to match the new mental model. Same `dt`/`dd` grid classes.)*

**Missing associations:** show `common.labels.em_dash` (unchanged).

**Actions:** Back → `?step=schedule`. Primary Create (new) / Update (edit). No secondary “edit section” controls.

---

## 4. Interaction flows

### 4.1 Create (happy path)

1. `GET …/send_activities/new` → Audience (default).  
2. Fill Name + List → Continue → POST → save draft → redirect edit/new flow with `?step=content` (same persistence pattern as today).  
3. Select Template → Continue → `?step=schedule`.  
4. Optional schedule/timezone/recurrence → Continue → `?step=review`.  
5. Create → flash success → show (or existing post-create destination).

### 4.2 Edit (happy path)

1. `GET …/:id/edit` or `?step=audience|content|schedule|review`.  
2. Same Continue / Back chain.  
3. On Review → Update.

### 4.3 Back navigation

- Always GET `url?step=<previous_step>` (no form submit).  
- Does not clear already-saved draft fields.

### 4.4 Validation failure

- Stay on current step; render `shared/form_errors` + field errors.  
- Progress nav still marks prior steps completed, current as current.

### 4.5 Invalid step

- `?step=setup` or unknown → invalid-step error (`wizard.invalid_step`) — same as today for bad keys.

### 4.6 Permission denied

- Controller auth unchanged (`admin`/`owner` on admin module path). No UX change.

### 4.7 Empty catalog (no lists / no templates)

- Selects show blank option only; Continue fails model validation; user must create list/template elsewhere (no in-wizard create CTA in this change).

---

## 5. Component reuse map

| Piece | Reuse / change |
|---|---|
| Page breadcrumbs | `BreadcrumbsComponent` (unchanged) |
| Page title block | Inline `text-heading` / `text-body-sm` on `new`/`edit` views (unchanged) |
| Wizard shell | `Emails::SendActivityBuilderComponent` — update `STEPS`, default step, labels |
| Progress nav | Existing markup in component ERB — only step keys/labels change |
| Step bodies | Partials: keep `wizard_step_content`, `wizard_step_review`; extend `wizard_step_audience` with Name; rename setup → schedule |
| Form errors | `shared/form_errors` |
| Buttons | `btn btn-primary` / `btn btn-secondary` |
| Generic `FormFields::WizardComponent` | **Do not switch to it** — Send Activity keeps its own server-step wizard |

**New components:** none.

**Stimulus:** none for this reorder.

---

## 6. Tailwind & Stimulus notes

- Keep existing utilities on the component (`space-y-6`, `mb-8`, `card p-6`, `text-lg font-semibold text-text-primary`, progress `text-text-muted` / `text-primary`, `border-border`, responsive `hidden sm:inline`, schedule `grid grid-cols-1 md:grid-cols-2 gap-4`).
- Review: `dl.divide-y.divide-border-subtle` + `py-3 grid grid-cols-1 sm:grid-cols-3`.
- No new Stimulus controller, values, or actions.
- Responsive: unchanged — progress labels hide on xs; schedule grid stacks on mobile.

---

## 7. Implementation checklist (for frontend / backend handoff)

- [ ] `STEPS = %w[audience content schedule review]` in builder component **and** `Emails::SendActivities::Build`
- [ ] Default step `audience`
- [ ] Audience permits/renders `name` + `email_list_id`
- [ ] Schedule permits/renders `scheduled_at`, `timezone`, `recurrence_preset` (no `name`)
- [ ] Partial rename setup → schedule
- [ ] I18n `steps.schedule` in `en` + `zh-CN`; drop `setup`
- [ ] Review `<dl>` order: name → list → template → schedule → timezone → recurrence
- [ ] Specs updated for step order / deep links / field permissions per step
- [ ] No visual token changes

---

## 8. Open items

1. **Figma frame capture** after desktop MCP auth — clone four wizard states; attach URL/node id to this doc.  
2. Subtitle copy on New page optionally updated later to “Name an audience and choose what to send.” — not required for READY_FOR_FRONTEND.
